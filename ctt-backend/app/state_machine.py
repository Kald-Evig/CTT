"""
state_machine.py — Máquina de estados de ítems.

Implementa LITERALMENTE la tabla de transiciones de la Sección 6.2 y las
restricciones de negocio de la Sección 5.3. Es la pieza crítica: un error aquí
corrompe el estado de una obra, por eso las transiciones se declaran como datos
y se validan paso a paso.

Reglas de negocio aplicadas (Sección 5.3):
  R1. Un ítem en PROBLEMA no puede cambiar de estado hasta cerrar el problema.
  R2. Un ítem solo puede tener UN problema ABIERTO a la vez.
  R3. TERMINADO es irreversible — solo un Admin puede revertirlo (excepción).
"""

from dataclasses import dataclass
from datetime import datetime, timezone

from sqlalchemy.orm import Session

from app.enums import ItemEstado, ProblemaEstado, Rol
from app.models import Item, ItemHistorial, ItemProblema


class TransicionInvalida(Exception):
    """Se lanza cuando una transición de estado no está permitida."""
    pass


@dataclass(frozen=True)
class Transicion:
    """Una regla de transición de la tabla 6.2."""
    desde: ItemEstado
    hacia: ItemEstado
    roles: frozenset[Rol]
    requiere_asignacion: bool = False       # el ítem debe estar asignado al actor
    requiere_comentario: bool = False       # rechazo necesita comentario
    requiere_descripcion_problema: bool = False


# ── Tabla de transiciones (espejo exacto de la Sección 6.2) ──────────────────
# NOTA: "PROBLEMA -> estado anterior" NO está aquí: cerrar un problema es una
# acción aparte (cerrar_problema), porque restaura el estado_previo dinámicamente.
TRANSICIONES: list[Transicion] = [
    Transicion(ItemEstado.ABIERTO, ItemEstado.EN_PROGRESO,
               frozenset({Rol.TRABAJADOR}), requiere_asignacion=True),

    Transicion(ItemEstado.EN_PROGRESO, ItemEstado.PENDIENTE_REVISION,
               frozenset({Rol.TRABAJADOR})),

    Transicion(ItemEstado.EN_PROGRESO, ItemEstado.PROBLEMA,
               frozenset({Rol.TRABAJADOR, Rol.RESIDENTE}),
               requiere_descripcion_problema=True),

    Transicion(ItemEstado.PENDIENTE_REVISION, ItemEstado.TERMINADO,
               frozenset({Rol.RESIDENTE, Rol.COORDINADOR, Rol.ADMIN})),

    Transicion(ItemEstado.PENDIENTE_REVISION, ItemEstado.EN_PROGRESO,  # rechazo
               frozenset({Rol.RESIDENTE, Rol.COORDINADOR, Rol.ADMIN}),
               requiere_comentario=True),

    Transicion(ItemEstado.PENDIENTE_REVISION, ItemEstado.PROBLEMA,
               frozenset({Rol.RESIDENTE}),
               requiere_descripcion_problema=True),
]


def _buscar_transicion(desde: ItemEstado, hacia: ItemEstado) -> Transicion | None:
    for t in TRANSICIONES:
        if t.desde == desde and t.hacia == hacia:
            return t
    return None


def _now() -> datetime:
    return datetime.now(timezone.utc)


def transicionar(
    db: Session,
    item: Item,
    nuevo_estado: ItemEstado,
    *,
    rol: Rol,
    usuario_id: str,
    comentario: str | None = None,
    descripcion_problema: str | None = None,
) -> Item:
    """Aplica una transición de estado validando rol, condiciones y reglas.

    Lanza TransicionInvalida si algo no cumple. En caso de éxito muta el ítem,
    registra historial y (si corresponde) crea el problema. NO hace commit:
    el llamador decide cuándo confirmar la transacción.
    """
    estado_actual = item.estado

    # R3: TERMINADO es irreversible por esta vía (ver revertir_terminado).
    if estado_actual == ItemEstado.TERMINADO:
        raise TransicionInvalida(
            "El ítem está TERMINADO (irreversible). Solo un Admin puede revertirlo."
        )

    # R1: en PROBLEMA, la única salida es cerrar el problema (cerrar_problema).
    if estado_actual == ItemEstado.PROBLEMA:
        raise TransicionInvalida(
            "El ítem está en PROBLEMA. Debe cerrarse el problema antes de "
            "cambiar de estado."
        )

    # ¿Existe la transición solicitada?
    transicion = _buscar_transicion(estado_actual, nuevo_estado)
    if transicion is None:
        raise TransicionInvalida(
            f"Transición no permitida: {estado_actual.value} -> {nuevo_estado.value}"
        )

    # ¿El rol puede ejecutarla?
    if rol not in transicion.roles:
        raise TransicionInvalida(
            f"El rol '{rol.value}' no puede ejecutar "
            f"{estado_actual.value} -> {nuevo_estado.value}."
        )

    # Condición: ítem asignado al actor (ABIERTO -> EN_PROGRESO).
    if transicion.requiere_asignacion and item.asignado_a != usuario_id:
        raise TransicionInvalida(
            "Solo el trabajador asignado puede iniciar este ítem."
        )

    # Condición: rechazo requiere comentario obligatorio.
    if transicion.requiere_comentario and not (comentario and comentario.strip()):
        raise TransicionInvalida("El rechazo requiere un comentario obligatorio.")

    # Condición: marcar problema requiere descripción.
    if transicion.requiere_descripcion_problema and not (
        descripcion_problema and descripcion_problema.strip()
    ):
        raise TransicionInvalida("Marcar un problema requiere una descripción.")

    # ── Efectos de la transición ─────────────────────────────────────────────
    if nuevo_estado == ItemEstado.PROBLEMA:
        # R2: no debe existir ya un problema abierto.
        abierto = (
            db.query(ItemProblema)
            .filter(ItemProblema.item_id == item.id,
                    ItemProblema.estado == ProblemaEstado.ABIERTO)
            .first()
        )
        if abierto is not None:
            raise TransicionInvalida("El ítem ya tiene un problema abierto.")

        # Guardamos el estado al que volver al cerrar el problema (Sección 6.2).
        item.estado_previo = estado_actual
        db.add(ItemProblema(
            item_id=item.id,
            reportado_por=usuario_id,
            descripcion=descripcion_problema.strip(),
        ))

    item.estado = nuevo_estado

    # Registro en el log de cambios (Sección 10 / "Ver log de cambios").
    db.add(ItemHistorial(
        item_id=item.id,
        usuario_id=usuario_id,
        accion="cambio_estado",
        estado_anterior=estado_actual.value,
        estado_nuevo=nuevo_estado.value,
        detalle=comentario or descripcion_problema,
    ))
    return item


def cerrar_problema(
    db: Session,
    item: Item,
    *,
    rol: Rol,
    usuario_id: str,
) -> Item:
    """Cierra el problema abierto y restaura el estado previo del ítem (Sección 6.2).

    Roles permitidos: Residente, Coordinador, Admin.
    """
    if rol not in (Rol.RESIDENTE, Rol.COORDINADOR, Rol.ADMIN):
        raise TransicionInvalida(
            f"El rol '{rol.value}' no puede cerrar problemas."
        )
    if item.estado != ItemEstado.PROBLEMA:
        raise TransicionInvalida("El ítem no está en estado PROBLEMA.")

    problema = (
        db.query(ItemProblema)
        .filter(ItemProblema.item_id == item.id,
                ItemProblema.estado == ProblemaEstado.ABIERTO)
        .first()
    )
    if problema is None:
        raise TransicionInvalida("No hay un problema abierto que cerrar.")

    problema.estado = ProblemaEstado.CERRADO
    problema.cerrado_por = usuario_id
    problema.cerrado_at = _now()

    # Restaurar el estado al que estaba antes del problema.
    estado_restaurado = item.estado_previo or ItemEstado.EN_PROGRESO
    item.estado = estado_restaurado
    item.estado_previo = None

    db.add(ItemHistorial(
        item_id=item.id,
        usuario_id=usuario_id,
        accion="cierre_problema",
        estado_anterior=ItemEstado.PROBLEMA.value,
        estado_nuevo=estado_restaurado.value,
        detalle="Problema cerrado; estado restaurado.",
    ))
    return item


def revertir_terminado(
    db: Session,
    item: Item,
    *,
    rol: Rol,
    usuario_id: str,
    motivo: str,
) -> Item:
    """Excepción de R3: SOLO un Admin puede revertir un ítem TERMINADO.

    Vuelve a PENDIENTE_REVISION para re-evaluación. Requiere motivo.
    """
    if rol != Rol.ADMIN:
        raise TransicionInvalida("Solo un Admin puede revertir un ítem terminado.")
    if item.estado != ItemEstado.TERMINADO:
        raise TransicionInvalida("El ítem no está TERMINADO.")
    if not (motivo and motivo.strip()):
        raise TransicionInvalida("Revertir un terminado requiere un motivo.")

    item.estado = ItemEstado.PENDIENTE_REVISION
    db.add(ItemHistorial(
        item_id=item.id,
        usuario_id=usuario_id,
        accion="reversion_terminado",
        estado_anterior=ItemEstado.TERMINADO.value,
        estado_nuevo=ItemEstado.PENDIENTE_REVISION.value,
        detalle=f"Reversión excepcional (Admin): {motivo.strip()}",
    ))
    return item
