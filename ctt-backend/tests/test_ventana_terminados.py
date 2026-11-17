"""
test_ventana_terminados.py - CTT-161: ventana de terminados en GET /items/mis-items.

Regla: /items/mis-items devuelve SIEMPRE los ítems activos; un TERMINADO solo si su
`terminado_en` es >= corte, con corte = now - N*24h y N = empresas.dias_ventana_terminados.
El reloj (`get_now`) es una dependencia inyectable: estos tests lo FIJAN con
`app.dependency_overrides`, de modo que el corte sea determinista.

Cobertura (una por punto del ticket):
  a) un terminado a N-1s del corte sale; a N+1s no sale.
  b) un ítem activo nunca sale, cualquiera sea su antigüedad.
  c) reversión del Admin de un terminado viejo -> reaparece; al re-terminar cuenta desde
     el nuevo terminado_en.
  d) dos empresas con N distinto.
  e) consistencia: para todo terminado, terminado_en = created_at del ULTIMO evento del
     historial hacia 'terminado' (propiedad del backfill de la migración).
  f) backfill: un terminado SIN historial recibe updated_at.

(e) y (f) ejecutan el SQL de backfill REAL importado desde la migración
c7e9a1b3d5f2 (no una copia), sobre la BD de test.
"""
import importlib.util
import pathlib
from contextlib import contextmanager
from datetime import datetime, timedelta

import pytest
import sqlalchemy as sa

from app.clock import get_now
from app.enums import ItemEstado, Rol
from app.main import app
from app.models import (
    Empresa, EmpresaUsuario, Item, ItemHistorial, Proyecto, ProyectoUsuario, Usuario,
)

# Reloj fijo de referencia (naive UTC, como get_now).
T0 = datetime(2026, 6, 1, 12, 0, 0)


@contextmanager
def reloj_fijo(t: datetime):
    """Fija get_now() en [t] para todos los endpoints durante el bloque."""
    app.dependency_overrides[get_now] = lambda: t
    try:
        yield
    finally:
        app.dependency_overrides.pop(get_now, None)


def _h(seeded, uid):
    return seeded.headers(uid, seeded.emp_a)


def _ids(resp):
    return {x["id"] for x in resp.json()}


def _crear_item(db, proy_id, asignado_id, estado, *, terminado_en=None,
                nombre="Item", updated_at=None):
    it = Item(proyecto_id=proy_id, nivel_profundidad=0, nombre=nombre,
              asignado_a=asignado_id, estado=estado, terminado_en=terminado_en)
    db.add(it)
    db.flush()
    if updated_at is not None:
        # updated_at tiene onupdate=_now; para fijar un valor de respaldo del backfill se
        # setea con UPDATE directo (evita que el onupdate lo pise).
        db.execute(sa.text("UPDATE items SET updated_at = :u WHERE id = :i"),
                   {"u": updated_at, "i": it.id})
    iid = it.id
    db.commit()
    return iid


# ── (a) borde del corte: N-1s dentro, N+1s fuera ──────────────────────────────
def test_a_borde_de_la_ventana(client, seeded, db):
    corte = T0 - timedelta(days=30)  # emp_a usa el default N=30
    dentro = _crear_item(db, seeded.proyecto, seeded.trab_id, ItemEstado.TERMINADO,
                         terminado_en=corte + timedelta(seconds=1), nombre="dentro")
    fuera = _crear_item(db, seeded.proyecto, seeded.trab_id, ItemEstado.TERMINADO,
                        terminado_en=corte - timedelta(seconds=1), nombre="fuera")

    with reloj_fijo(T0):
        r = client.get("/items/mis-items", headers=_h(seeded, seeded.trab))
    assert r.status_code == 200, r.text
    ids = _ids(r)
    assert dentro in ids, "el terminado a N-1s del corte (mas nuevo) debe salir"
    assert fuera not in ids, "el terminado a N+1s del corte (mas viejo) NO debe salir"


# ── (b) un ítem activo nunca se filtra por antigüedad ─────────────────────────
@pytest.mark.parametrize("estado", [
    ItemEstado.ABIERTO, ItemEstado.EN_PROGRESO,
    ItemEstado.PENDIENTE_REVISION, ItemEstado.PROBLEMA,
])
def test_b_activo_nunca_se_cae(client, seeded, db, estado):
    # created_at/updated_at quedan "ahora" (real), pero un activo no depende de terminado_en.
    activo = _crear_item(db, seeded.proyecto, seeded.trab_id, estado, nombre=estado.value)

    # Reloj MUY en el futuro: el corte deja atrás cualquier terminado, pero el activo queda.
    with reloj_fijo(T0 + timedelta(days=10_000)):
        r = client.get("/items/mis-items", headers=_h(seeded, seeded.trab))
    assert r.status_code == 200, r.text
    assert activo in _ids(r), f"un ítem {estado.value} (activo) nunca debe caerse de mis-items"


# ── (c) reversión del Admin y re-término ──────────────────────────────────────
def test_c_reversion_y_reterminado(client, seeded, db):
    # Terminado VIEJO (fuera de la ventana de 30 días respecto de T0).
    iid = _crear_item(db, seeded.proyecto, seeded.trab_id, ItemEstado.TERMINADO,
                      terminado_en=T0 - timedelta(days=40), nombre="viejo")

    with reloj_fijo(T0):
        r0 = client.get("/items/mis-items", headers=_h(seeded, seeded.trab))
        assert iid not in _ids(r0), "el terminado viejo no debe salir antes de revertir"

        # Admin revierte -> PENDIENTE_REVISION (activo). terminado_en vuelve a NULL.
        rr = client.post(f"/items/{iid}/revertir-terminado",
                         headers=_h(seeded, seeded.admin), params={"motivo": "Rehacer"})
        assert rr.status_code == 200, rr.text
        r1 = client.get("/items/mis-items", headers=_h(seeded, seeded.trab))
        assert iid in _ids(r1), "tras revertir, el ítem activo debe reaparecer"

    db.expire_all()
    assert db.get(Item, iid).terminado_en is None, "la reversión limpia terminado_en"
    v = db.query(Item.version).filter(Item.id == iid).scalar()

    # Re-terminar bajo el reloj fijo T0: el residente aprueba PENDIENTE_REVISION -> TERMINADO.
    with reloj_fijo(T0):
        rt = client.post(f"/items/{iid}/transicion", headers=_h(seeded, seeded.resid),
                         json={"nuevo_estado": "terminado", "version_base": v})
        assert rt.status_code == 200, rt.text
        r2 = client.get("/items/mis-items", headers=_h(seeded, seeded.trab))
        assert iid in _ids(r2), "re-terminado con terminado_en reciente: debe salir"

    db.expire_all()
    assert db.get(Item, iid).terminado_en == T0, "cuenta desde el NUEVO terminado_en (=T0)"


# ── (d) dos empresas con N distinto ───────────────────────────────────────────
def test_d_n_por_empresa(client, seeded, db):
    # emp_a: N por defecto = 30. emp_b: N = 5.
    db.execute(sa.text("UPDATE empresas SET dias_ventana_terminados = 5 WHERE id = :i"),
               {"i": seeded.emp_b})
    # Un proyecto + ítem terminado para admin_b en emp_b, con la MISMA antigüedad (10 días).
    proy_b = Proyecto(empresa_id=seeded.emp_b, nombre="Obra B", created_by=seeded.admin_b_id)
    db.add(proy_b); db.flush()
    item_b = _crear_item(db, proy_b.id, seeded.admin_b_id, ItemEstado.TERMINADO,
                         terminado_en=T0 - timedelta(days=10), nombre="term-b")
    # Un terminado de la misma antigüedad para trab en emp_a.
    item_a = _crear_item(db, seeded.proyecto, seeded.trab_id, ItemEstado.TERMINADO,
                         terminado_en=T0 - timedelta(days=10), nombre="term-a")

    with reloj_fijo(T0):
        ra = client.get("/items/mis-items", headers=seeded.headers(seeded.trab, seeded.emp_a))
        rb = client.get("/items/mis-items", headers=seeded.headers(seeded.admin_b, seeded.emp_b))
    assert ra.status_code == 200 and rb.status_code == 200
    assert item_a in _ids(ra), "emp_a (N=30): un terminado de 10 días SIGUE visible"
    assert item_b not in _ids(rb), "emp_b (N=5): el mismo terminado de 10 días ya NO se envía"


# ── Backfill: cargar el SQL REAL de la migración ──────────────────────────────
def _cargar_sql_backfill() -> str:
    ruta = (pathlib.Path(__file__).resolve().parents[1]
            / "alembic" / "versions" / "c7e9a1b3d5f2_ctt161_ventana_terminados.py")
    spec = importlib.util.spec_from_file_location("ctt161_mig", ruta)
    mig = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mig)
    return mig._BACKFILL_TERMINADO_EN


# ── (e) consistencia: terminado_en = MAX(created_at) de eventos hacia terminado ─
def test_e_consistencia_con_historial(client, seeded, db):
    # Terminado SIN terminado_en (como una fila previa a CTT-161), con historial:
    # dos eventos a 'terminado' (el MAX manda) + una reversión intermedia (se ignora).
    iid = _crear_item(db, seeded.proyecto, seeded.trab_id, ItemEstado.TERMINADO,
                      terminado_en=None, nombre="con-hist")
    eventos = [
        ("cambio_estado", "terminado", datetime(2026, 1, 10, 9, 0, 0)),
        ("reversion_terminado", "pendiente_revision", datetime(2026, 2, 1, 9, 0, 0)),
        ("cambio_estado", "terminado", datetime(2026, 3, 15, 18, 30, 0)),  # <- MAX hacia terminado
    ]
    for accion, est, ts in eventos:
        h = ItemHistorial(item_id=iid, usuario_id=seeded.trab_id, accion=accion,
                          estado_nuevo=est)
        db.add(h); db.flush()
        db.execute(sa.text("UPDATE item_historial SET created_at = :c WHERE id = :i"),
                   {"c": ts, "i": h.id})
    db.commit()

    db.execute(sa.text(_cargar_sql_backfill()))
    db.commit()

    db.expire_all()
    esperado = db.query(sa.func.max(ItemHistorial.created_at)).filter(
        ItemHistorial.item_id == iid, ItemHistorial.estado_nuevo == "terminado").scalar()
    obtenido = db.get(Item, iid).terminado_en
    assert obtenido == esperado == datetime(2026, 3, 15, 18, 30, 0), (
        f"terminado_en ({obtenido}) debe ser el created_at del ULTIMO evento a terminado")


# ── (f) backfill sin historial: usa updated_at ────────────────────────────────
def test_f_backfill_sin_historial_usa_updated_at(client, seeded, db):
    upd = datetime(2026, 4, 20, 8, 15, 0)
    iid = _crear_item(db, seeded.proyecto, seeded.trab_id, ItemEstado.TERMINADO,
                      terminado_en=None, nombre="sin-hist", updated_at=upd)

    db.execute(sa.text(_cargar_sql_backfill()))
    db.commit()

    db.expire_all()
    it = db.get(Item, iid)
    assert it.terminado_en == upd, "sin historial, el backfill usa updated_at"
    # y ningún terminado queda en NULL tras el backfill.
    nulos = db.query(Item).filter(Item.estado == ItemEstado.TERMINADO,
                                  Item.terminado_en.is_(None)).count()
    assert nulos == 0
