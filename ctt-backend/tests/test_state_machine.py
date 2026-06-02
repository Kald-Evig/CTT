"""
test_state_machine.py — Tests de la máquina de estados (Secciones 5.3 y 6.2).

Es la pieza crítica del backend: un error aquí corrompe el estado de una obra.
Se prueban transiciones válidas, bloqueos por rol/condición y las tres reglas
de negocio R1 (PROBLEMA bloquea), R2 (un solo problema abierto) y R3 (TERMINADO
irreversible salvo Admin).

Los tests operan directamente sobre la máquina de estados con la sesión `db`,
sin pasar por la capa HTTP, para aislar la lógica de dominio.
"""

import pytest

from app.enums import EmpresaPlan, ItemEstado, ProblemaEstado, Rol
from app.models import Empresa, Item, ItemProblema, Proyecto
from app.state_machine import (
    TransicionInvalida, cerrar_problema, revertir_terminado, transicionar,
)

TRAB = "u-trab"      # id interno del trabajador asignado


def _crear_item(db, *, estado=ItemEstado.ABIERTO, asignado_a=TRAB) -> Item:
    """Crea el grafo mínimo (empresa→proyecto→ítem) y devuelve el ítem persistido."""
    emp = Empresa(nombre="E", rut_empresa="1-9", email_contacto="e@e.cl",
                  plan=EmpresaPlan.PRO)
    db.add(emp); db.flush()
    proy = Proyecto(empresa_id=emp.id, nombre="P", created_by="u-x")
    db.add(proy); db.flush()
    item = Item(proyecto_id=proy.id, nivel_profundidad=0, nombre="Tarea",
                asignado_a=asignado_a, estado=estado, created_by="u-x")
    db.add(item); db.flush()
    return item


# ── Transiciones válidas (happy path) ────────────────────────────────────────
def test_abierto_a_en_progreso_trabajador_asignado(db):
    item = _crear_item(db)
    transicionar(db, item, ItemEstado.EN_PROGRESO, rol=Rol.TRABAJADOR, usuario_id=TRAB)
    assert item.estado == ItemEstado.EN_PROGRESO


def test_en_progreso_a_pendiente_revision(db):
    item = _crear_item(db, estado=ItemEstado.EN_PROGRESO)
    transicionar(db, item, ItemEstado.PENDIENTE_REVISION,
                 rol=Rol.TRABAJADOR, usuario_id=TRAB)
    assert item.estado == ItemEstado.PENDIENTE_REVISION


def test_pendiente_a_terminado_residente(db):
    item = _crear_item(db, estado=ItemEstado.PENDIENTE_REVISION)
    transicionar(db, item, ItemEstado.TERMINADO, rol=Rol.RESIDENTE, usuario_id="u-res")
    assert item.estado == ItemEstado.TERMINADO


# ── Bloqueos por rol ─────────────────────────────────────────────────────────
def test_residente_no_puede_iniciar_tarea(db):
    item = _crear_item(db)
    with pytest.raises(TransicionInvalida):
        transicionar(db, item, ItemEstado.EN_PROGRESO,
                     rol=Rol.RESIDENTE, usuario_id="u-res")


def test_trabajador_no_puede_aprobar(db):
    item = _crear_item(db, estado=ItemEstado.PENDIENTE_REVISION)
    with pytest.raises(TransicionInvalida):
        transicionar(db, item, ItemEstado.TERMINADO,
                     rol=Rol.TRABAJADOR, usuario_id=TRAB)


# ── Condiciones ──────────────────────────────────────────────────────────────
def test_iniciar_requiere_estar_asignado(db):
    item = _crear_item(db, asignado_a="otro-trabajador")
    with pytest.raises(TransicionInvalida):
        transicionar(db, item, ItemEstado.EN_PROGRESO,
                     rol=Rol.TRABAJADOR, usuario_id=TRAB)


def test_rechazo_requiere_comentario(db):
    item = _crear_item(db, estado=ItemEstado.PENDIENTE_REVISION)
    with pytest.raises(TransicionInvalida):
        transicionar(db, item, ItemEstado.EN_PROGRESO,  # rechazo
                     rol=Rol.RESIDENTE, usuario_id="u-res", comentario="   ")
    # Con comentario válido sí procede.
    transicionar(db, item, ItemEstado.EN_PROGRESO,
                 rol=Rol.RESIDENTE, usuario_id="u-res", comentario="Falta sello.")
    assert item.estado == ItemEstado.EN_PROGRESO


def test_marcar_problema_requiere_descripcion(db):
    item = _crear_item(db, estado=ItemEstado.EN_PROGRESO)
    with pytest.raises(TransicionInvalida):
        transicionar(db, item, ItemEstado.PROBLEMA,
                     rol=Rol.TRABAJADOR, usuario_id=TRAB, descripcion_problema="")


# ── Transición inexistente ───────────────────────────────────────────────────
def test_transicion_inexistente_falla(db):
    item = _crear_item(db)  # ABIERTO
    with pytest.raises(TransicionInvalida):
        transicionar(db, item, ItemEstado.TERMINADO, rol=Rol.ADMIN, usuario_id="u-adm")


# ── R1: PROBLEMA bloquea ─────────────────────────────────────────────────────
def test_problema_bloquea_otras_transiciones(db):
    item = _crear_item(db, estado=ItemEstado.EN_PROGRESO)
    transicionar(db, item, ItemEstado.PROBLEMA, rol=Rol.TRABAJADOR,
                 usuario_id=TRAB, descripcion_problema="Cañería rota")
    assert item.estado == ItemEstado.PROBLEMA
    assert item.estado_previo == ItemEstado.EN_PROGRESO
    # Intentar avanzar mientras está en PROBLEMA debe fallar (R1).
    with pytest.raises(TransicionInvalida):
        transicionar(db, item, ItemEstado.PENDIENTE_REVISION,
                     rol=Rol.TRABAJADOR, usuario_id=TRAB)


# ── R2: un solo problema abierto ─────────────────────────────────────────────
def test_un_solo_problema_abierto(db):
    item = _crear_item(db, estado=ItemEstado.EN_PROGRESO)
    transicionar(db, item, ItemEstado.PROBLEMA, rol=Rol.TRABAJADOR,
                 usuario_id=TRAB, descripcion_problema="Primero")
    # Forzar (de forma artificial) volver a EN_PROGRESO sin cerrar el problema
    # y reintentar marcar problema: la guarda R2 debe impedir un segundo abierto.
    item.estado = ItemEstado.EN_PROGRESO
    db.flush()
    with pytest.raises(TransicionInvalida):
        transicionar(db, item, ItemEstado.PROBLEMA, rol=Rol.TRABAJADOR,
                     usuario_id=TRAB, descripcion_problema="Segundo")
    abiertos = (
        db.query(ItemProblema)
        .filter(ItemProblema.item_id == item.id,
                ItemProblema.estado == ProblemaEstado.ABIERTO)
        .count()
    )
    assert abiertos == 1


# ── cerrar_problema restaura el estado previo ────────────────────────────────
def test_cerrar_problema_restaura_estado_previo(db):
    item = _crear_item(db, estado=ItemEstado.EN_PROGRESO)
    transicionar(db, item, ItemEstado.PROBLEMA, rol=Rol.TRABAJADOR,
                 usuario_id=TRAB, descripcion_problema="Cañería rota")
    # La sesión usa autoflush=False; en la app real cada paso es un request que
    # confirma (y por tanto vacía) la transacción. Aquí lo simulamos con flush.
    db.flush()
    cerrar_problema(db, item, rol=Rol.RESIDENTE, usuario_id="u-res")
    db.flush()
    assert item.estado == ItemEstado.EN_PROGRESO  # restaurado
    assert item.estado_previo is None
    abiertos = (
        db.query(ItemProblema)
        .filter(ItemProblema.item_id == item.id,
                ItemProblema.estado == ProblemaEstado.ABIERTO)
        .count()
    )
    assert abiertos == 0


def test_cerrar_problema_rol_invalido(db):
    item = _crear_item(db, estado=ItemEstado.EN_PROGRESO)
    transicionar(db, item, ItemEstado.PROBLEMA, rol=Rol.TRABAJADOR,
                 usuario_id=TRAB, descripcion_problema="Falla")
    with pytest.raises(TransicionInvalida):
        cerrar_problema(db, item, rol=Rol.TRABAJADOR, usuario_id=TRAB)


# ── R3: TERMINADO irreversible salvo Admin ───────────────────────────────────
def test_terminado_irreversible_via_transicionar(db):
    item = _crear_item(db, estado=ItemEstado.TERMINADO)
    with pytest.raises(TransicionInvalida):
        transicionar(db, item, ItemEstado.PENDIENTE_REVISION,
                     rol=Rol.RESIDENTE, usuario_id="u-res")


def test_revertir_terminado_solo_admin(db):
    item = _crear_item(db, estado=ItemEstado.TERMINADO)
    # Residente no puede.
    with pytest.raises(TransicionInvalida):
        revertir_terminado(db, item, rol=Rol.RESIDENTE,
                           usuario_id="u-res", motivo="error")
    # Admin sí, y vuelve a PENDIENTE_REVISION.
    revertir_terminado(db, item, rol=Rol.ADMIN, usuario_id="u-adm",
                       motivo="Se aprobó por error")
    assert item.estado == ItemEstado.PENDIENTE_REVISION


def test_revertir_terminado_requiere_motivo(db):
    item = _crear_item(db, estado=ItemEstado.TERMINADO)
    with pytest.raises(TransicionInvalida):
        revertir_terminado(db, item, rol=Rol.ADMIN, usuario_id="u-adm", motivo="  ")
