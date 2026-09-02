"""test_conflictos_mios.py — CTT-117 tramo 1 (backend).

Cubre:
  - 2-B: resolver_conflicto persiste version_ganadora en la fila.
  - 2-C: GET /sync/conflictos/mios scopea por usuario_id del token, sin ramas por
         rol, solo RESUELTOS, y su schema excluye cambio_local/cambio_servidor.
  - 2-D: GET /sync/conflictos sigue rechazando al Trabajador (403).
"""

from datetime import datetime

from app.enums import ConflictoEstado, ItemEstado
from app.models import Item, SyncConflicto


def _item(db, d, nombre):
    it = Item(
        proyecto_id=d.proyecto,
        nivel_profundidad=0,
        nombre=nombre,
        asignado_a=d.trab_id,
        estado=ItemEstado.ABIERTO,
        created_by=d.coord_id,
    )
    db.add(it)
    db.commit()
    return it.id


def _conflicto(db, item_id, usuario_id, dispositivo_id, *,
               estado=ConflictoEstado.PENDIENTE, version_ganadora=None,
               resuelto_at=None):
    c = SyncConflicto(
        item_id=item_id,
        usuario_id=usuario_id,
        dispositivo_id=dispositivo_id,
        cambio_local={"estado": "en_progreso"},
        cambio_servidor={"estado": "abierto"},
        estado=estado,
        version_ganadora=version_ganadora,
        resuelto_at=resuelto_at,
    )
    db.add(c)
    db.commit()
    return c.id


def test_resolver_persiste_version_ganadora(seeded, client, db):
    d = seeded
    c_local = _conflicto(db, _item(db, d, "IL"), d.trab_id, "dev-1")
    c_serv = _conflicto(db, _item(db, d, "IS"), d.trab_id, "dev-2")

    r1 = client.post(f"/sync/conflictos/{c_local}/resolver",
                     json={"version_ganadora": "local"}, headers=d.headers(d.coord))
    assert r1.status_code == 200, r1.text
    assert r1.json()["version_ganadora"] == "local"

    r2 = client.post(f"/sync/conflictos/{c_serv}/resolver",
                     json={"version_ganadora": "servidor"}, headers=d.headers(d.coord))
    assert r2.status_code == 200, r2.text
    assert r2.json()["version_ganadora"] == "servidor"

    # 2-B: persistido en la FILA, no solo en la respuesta.
    db.expire_all()
    assert db.get(SyncConflicto, c_local).version_ganadora == "local"
    assert db.get(SyncConflicto, c_serv).version_ganadora == "servidor"


def test_mios_scopea_por_usuario_sin_ramas_de_rol(seeded, client, db):
    d = seeded
    # Un conflicto resuelto propio por cada rol (usuario_id = originador).
    c_t = _conflicto(db, _item(db, d, "T"), d.trab_id, "dev-t",
                     estado=ConflictoEstado.RESUELTO, version_ganadora="local",
                     resuelto_at=datetime(2026, 2, 1))
    c_r = _conflicto(db, _item(db, d, "R"), d.resid_id, "dev-r",
                     estado=ConflictoEstado.RESUELTO, version_ganadora="servidor",
                     resuelto_at=datetime(2026, 2, 2))
    c_c = _conflicto(db, _item(db, d, "C"), d.coord_id, "dev-c",
                     estado=ConflictoEstado.RESUELTO, version_ganadora="local",
                     resuelto_at=datetime(2026, 2, 3))

    ids_t = {x["id"] for x in client.get("/sync/conflictos/mios",
                                          headers=d.headers(d.trab)).json()}
    ids_r = {x["id"] for x in client.get("/sync/conflictos/mios",
                                          headers=d.headers(d.resid)).json()}
    ids_c = {x["id"] for x in client.get("/sync/conflictos/mios",
                                          headers=d.headers(d.coord)).json()}

    assert ids_t == {c_t}
    assert ids_r == {c_r}
    assert ids_c == {c_c}


def test_mios_excluye_pendientes_y_ajenos(seeded, client, db):
    d = seeded
    resuelto = _conflicto(db, _item(db, d, "OK"), d.trab_id, "dev-ok",
                          estado=ConflictoEstado.RESUELTO, version_ganadora="local",
                          resuelto_at=datetime(2026, 3, 1))
    _conflicto(db, _item(db, d, "PEND"), d.trab_id, "dev-pend")  # pendiente propio
    _conflicto(db, _item(db, d, "AJENO"), d.resid_id, "dev-aj",  # resuelto ajeno
               estado=ConflictoEstado.RESUELTO, version_ganadora="servidor",
               resuelto_at=datetime(2026, 3, 2))

    ids = {x["id"] for x in client.get("/sync/conflictos/mios",
                                       headers=d.headers(d.trab)).json()}
    assert ids == {resuelto}


def test_mios_incluye_preexistente_con_version_null(seeded, client, db):
    d = seeded
    viejo = _conflicto(db, _item(db, d, "OLD"), d.trab_id, "dev-old",
                       estado=ConflictoEstado.RESUELTO, version_ganadora=None,
                       resuelto_at=datetime(2025, 12, 1))
    fila = next(x for x in client.get("/sync/conflictos/mios",
                                      headers=d.headers(d.trab)).json()
               if x["id"] == viejo)
    assert fila["version_ganadora"] is None


def test_mios_schema_sin_snapshots(seeded, client, db):
    d = seeded
    _conflicto(db, _item(db, d, "S"), d.trab_id, "dev-s",
               estado=ConflictoEstado.RESUELTO, version_ganadora="local",
               resuelto_at=datetime(2026, 4, 1))
    fila = client.get("/sync/conflictos/mios", headers=d.headers(d.trab)).json()[0]
    assert set(fila.keys()) == {
        "id", "item_id", "dispositivo_id", "version_ganadora", "resuelto_at", "estado",
    }
    assert "cambio_local" not in fila
    assert "cambio_servidor" not in fila


def test_get_conflictos_sigue_403_trabajador(seeded, client, db):
    d = seeded
    r = client.get("/sync/conflictos", headers=d.headers(d.trab))
    assert r.status_code == 403, r.text
