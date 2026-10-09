"""
test_ctt143_version_historial.py — CTT-143 (A' / D1 / D2).

Invariante central: TODA ruta de escritura de `items` deja `version + 1` (creación:
version == 1) y EXACTAMENTE una fila nueva en `item_historial`, con esa `version` y la
`accion` correspondiente. Cubre las 7 rutas ORM: crear, editar, asignar, transición,
cerrar_problema, revertir_terminado y resolución de conflicto (gana local).

La version la gestiona version_id_col (P1/D2); la fila de historial la escribe el helper
único `registrar_escritura_item`.
"""

import pytest

from app.enums import ItemEstado, Rol
from app.models import (
    EmpresaUsuario, Item, ItemHistorial, ProyectoUsuario, SyncConflicto, Usuario,
)


def _h(seeded, uid):
    return seeded.headers(uid, seeded.emp_a)


def _version(db, item_id):
    """Version actual del ítem, leída fresca de la BD (evita el identity-map)."""
    db.expire_all()
    return db.query(Item.version).filter(Item.id == item_id).scalar()


def _hist_count(db, item_id):
    return db.query(ItemHistorial).filter(ItemHistorial.item_id == item_id).count()


def _ultima_hist(db, item_id):
    return (
        db.query(ItemHistorial)
        .filter(ItemHistorial.item_id == item_id)
        .order_by(ItemHistorial.version.desc())
        .first()
    )


# ── Builders por ruta: preparan el estado, ejecutan la acción medida y devuelven
#    (item_id, version_antes, hist_antes, response, accion_esperada). ──────────────

def _caso_creacion(client, seeded, db):
    r = client.post("/items", headers=_h(seeded, seeded.coord),
                    json={"proyecto_id": seeded.proyecto, "nombre": "Nuevo ítem"})
    item_id = r.json().get("id") if r.status_code == 201 else None
    # Creación: no hay ítem previo → version esperada 1, hist esperado 1.
    return item_id, 0, 0, r, "creacion"


def _caso_edicion(client, seeded, db):
    item_id = seeded.item  # ABIERTO (editable)
    v, h = _version(db, item_id), _hist_count(db, item_id)
    r = client.put(f"/items/{item_id}", headers=_h(seeded, seeded.coord),
                   json={"nombre": "Renombrado"})
    return item_id, v, h, r, "edicion_datos"


def _caso_asignacion(client, seeded, db):
    # Un trabajador DISTINTO del actual (seeded.item está asignado a trab), miembro
    # activo del proyecto — si no, _validar_asignatario_miembro daría 409.
    tx = Usuario(firebase_uid="t-trabx", nombre_completo="TrabX", email="trabx@a.cl")
    db.add(tx); db.flush()
    db.add(EmpresaUsuario(empresa_id=seeded.emp_a, usuario_id=tx.id, rol=Rol.TRABAJADOR))
    db.add(ProyectoUsuario(proyecto_id=seeded.proyecto, usuario_id=tx.id,
                           rol_en_proyecto=Rol.TRABAJADOR))
    db.commit()
    item_id = seeded.item
    v, h = _version(db, item_id), _hist_count(db, item_id)
    r = client.post(f"/items/{item_id}/asignar", headers=_h(seeded, seeded.coord),
                    json={"usuario_id": tx.id})
    return item_id, v, h, r, "asignacion"


def _caso_cambio_estado(client, seeded, db):
    item_id = seeded.item  # ABIERTO, asignado a trab → abierto→en_progreso válido
    v, h = _version(db, item_id), _hist_count(db, item_id)
    r = client.post(f"/items/{item_id}/transicion", headers=_h(seeded, seeded.trab),
                    json={"nuevo_estado": "en_progreso"})
    return item_id, v, h, r, "cambio_estado"


def _caso_cierre_problema(client, seeded, db):
    item_id = seeded.item
    # abierto→en_progreso (trab), en_progreso→problema (trab, con descripción).
    client.post(f"/items/{item_id}/transicion", headers=_h(seeded, seeded.trab),
                json={"nuevo_estado": "en_progreso"})
    client.post(f"/items/{item_id}/transicion", headers=_h(seeded, seeded.trab),
                json={"nuevo_estado": "problema", "descripcion_problema": "Fuga"})
    v, h = _version(db, item_id), _hist_count(db, item_id)
    r = client.post(f"/items/{item_id}/cerrar-problema", headers=_h(seeded, seeded.coord))
    return item_id, v, h, r, "cierre_problema"


def _caso_reversion(client, seeded, db):
    item_id = seeded.item
    client.post(f"/items/{item_id}/transicion", headers=_h(seeded, seeded.trab),
                json={"nuevo_estado": "en_progreso"})
    client.post(f"/items/{item_id}/transicion", headers=_h(seeded, seeded.trab),
                json={"nuevo_estado": "pendiente_revision"})
    client.post(f"/items/{item_id}/transicion", headers=_h(seeded, seeded.resid),
                json={"nuevo_estado": "terminado"})
    v, h = _version(db, item_id), _hist_count(db, item_id)
    r = client.post(f"/items/{item_id}/revertir-terminado",
                    headers=_h(seeded, seeded.admin), params={"motivo": "Rehacer medición"})
    return item_id, v, h, r, "reversion_terminado"


def _caso_resolucion_conflicto(client, seeded, db):
    item_id = seeded.item  # ABIERTO → cambio_servidor coincide (Fix C pasa)
    c = SyncConflicto(
        item_id=item_id,
        cambio_local={"estado": "en_progreso"},
        cambio_servidor={"estado": ItemEstado.ABIERTO.value},
        dispositivo_id="disp-1", usuario_id=seeded.trab_id,
    )
    db.add(c); db.commit()
    v, h = _version(db, item_id), _hist_count(db, item_id)
    r = client.post(f"/sync/conflictos/{c.id}/resolver", headers=_h(seeded, seeded.coord),
                    json={"version_ganadora": "local"})
    return item_id, v, h, r, "resolucion_conflicto"


_CASOS = [
    ("creacion", _caso_creacion),
    ("edicion_datos", _caso_edicion),
    ("asignacion", _caso_asignacion),
    ("cambio_estado", _caso_cambio_estado),
    ("cierre_problema", _caso_cierre_problema),
    ("reversion_terminado", _caso_reversion),
    ("resolucion_conflicto", _caso_resolucion_conflicto),
]


@pytest.mark.parametrize("nombre,builder", _CASOS, ids=[n for n, _ in _CASOS])
def test_toda_escritura_sube_version_y_deja_una_fila_de_historial(
    nombre, builder, client, seeded, db,
):
    item_id, v_antes, h_antes, resp, accion = builder(client, seeded, db)

    assert resp.status_code in (200, 201), f"{nombre}: {resp.status_code} {resp.text}"
    assert item_id is not None, f"{nombre}: no se obtuvo item_id"

    # version + 1 (creación: 0 → 1).
    assert _version(db, item_id) == v_antes + 1, f"{nombre}: version no subió +1"

    # exactamente UNA fila nueva de historial.
    assert _hist_count(db, item_id) == h_antes + 1, f"{nombre}: no dejó 1 fila de historial"

    # la última fila trae la accion esperada y la version resultante.
    ultima = _ultima_hist(db, item_id)
    assert ultima.accion == accion, f"{nombre}: accion {ultima.accion!r} != {accion!r}"
    assert ultima.version == v_antes + 1, f"{nombre}: historial.version != version del ítem"
