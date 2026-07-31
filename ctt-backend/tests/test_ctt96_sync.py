"""
test_ctt96_sync.py — Scope resource-scoped para CTT-96 fase 2.

Verifica que GET /sync/conflictos y POST /sync/conflictos/{id}/resolver
aplican scope_orm: un Coordinador solo ve y resuelve conflictos de
proyectos donde es coordinador_principal.

Fixture: emp_a con dos coordinadores y dos proyectos, uno por cada uno,
cada proyecto con un ítem y un conflicto PENDIENTE (el endpoint sin
?estado= filtra a PENDIENTE por defecto; nacen en ese estado para que
los tests fallen por el motivo correcto si el scope deja de funcionar).
"""

import pytest

from app.enums import ConflictoEstado, EmpresaPlan, ItemEstado, Rol
from app.models import (
    Empresa, EmpresaUsuario, Item, ItemComentario, Proyecto, SyncConflicto, Usuario,
)


@pytest.fixture()
def d96_sync(db):
    """
    emp_a:
      admin   → ADMIN
      coord_p → COORDINADOR, coordinador_principal de proy_a
      coord_o → COORDINADOR, coordinador_principal de proy_b
      resid   → RESIDENTE

    proy_a: coord_p como principal; item_a → conflicto_a (PENDIENTE).
    proy_b: coord_o como principal; item_b → conflicto_b (PENDIENTE).
    """
    emp_a = Empresa(nombre="Emp 96 Sync", rut_empresa="76.111.111-1",
                    email_contacto="sync96@t.cl", plan=EmpresaPlan.PRO)
    db.add(emp_a)
    db.flush()

    admin   = Usuario(firebase_uid="s96-admin",   nombre_completo="Admin 96",   email="admin@s96.cl")
    coord_p = Usuario(firebase_uid="s96-coord-p", nombre_completo="Coord P 96", email="coord.p@s96.cl")
    coord_o = Usuario(firebase_uid="s96-coord-o", nombre_completo="Coord O 96", email="coord.o@s96.cl")
    resid   = Usuario(firebase_uid="s96-resid",   nombre_completo="Resid 96",   email="resid@s96.cl")
    db.add_all([admin, coord_p, coord_o, resid])
    db.flush()

    db.add_all([
        EmpresaUsuario(empresa_id=emp_a.id, usuario_id=admin.id,   rol=Rol.ADMIN),
        EmpresaUsuario(empresa_id=emp_a.id, usuario_id=coord_p.id, rol=Rol.COORDINADOR),
        EmpresaUsuario(empresa_id=emp_a.id, usuario_id=coord_o.id, rol=Rol.COORDINADOR),
        EmpresaUsuario(empresa_id=emp_a.id, usuario_id=resid.id,   rol=Rol.RESIDENTE),
    ])

    proy_a = Proyecto(empresa_id=emp_a.id, nombre="Obra P",
                      coordinador_principal_id=coord_p.id, created_by=coord_p.id)
    proy_b = Proyecto(empresa_id=emp_a.id, nombre="Obra O",
                      coordinador_principal_id=coord_o.id, created_by=coord_o.id)
    db.add_all([proy_a, proy_b])
    db.flush()

    item_a = Item(proyecto_id=proy_a.id, nivel_profundidad=0, nombre="Tarea P",
                  estado=ItemEstado.ABIERTO, created_by=coord_p.id)
    item_b = Item(proyecto_id=proy_b.id, nivel_profundidad=0, nombre="Tarea O",
                  estado=ItemEstado.ABIERTO, created_by=coord_o.id)
    db.add_all([item_a, item_b])
    db.flush()

    conflicto_a = SyncConflicto(
        item_id=item_a.id,
        cambio_local={"estado": "en_progreso", "comentario": "comentario de prueba CTT-96"},
        cambio_servidor={"estado": "abierto"},
        dispositivo_id="dev-a",
        usuario_id=coord_p.id,
        estado=ConflictoEstado.PENDIENTE,
    )
    conflicto_b = SyncConflicto(
        item_id=item_b.id,
        cambio_local={"estado": "en_progreso", "comentario": None},
        cambio_servidor={"estado": "abierto"},
        dispositivo_id="dev-b",
        usuario_id=coord_o.id,
        estado=ConflictoEstado.PENDIENTE,
    )
    db.add_all([conflicto_a, conflicto_b])
    db.commit()
    db.refresh(conflicto_a)
    db.refresh(conflicto_b)

    def h(uid):
        return {"Authorization": f"Bearer {uid}", "X-Empresa-Id": emp_a.id}

    return {
        "admin":       admin.firebase_uid,
        "coord_p":     coord_p.firebase_uid,
        "coord_o":     coord_o.firebase_uid,
        "resid":       resid.firebase_uid,
        "coord_p_id":  coord_p.id,
        "conflicto_a": conflicto_a.id,
        "conflicto_b": conflicto_b.id,
        "item_a":      item_a.id,
        "h": h,
    }


# ── GET /sync/conflictos ──────────────────────────────────────────────────────

def test_get_coord_principal_ve_el_suyo_y_no_el_ajeno(client, d96_sync):
    d = d96_sync
    r = client.get("/sync/conflictos", headers=d["h"](d["coord_p"]))
    assert r.status_code == 200, r.text
    ids = {c["id"] for c in r.json()}
    assert d["conflicto_a"] in ids
    assert d["conflicto_b"] not in ids


def test_get_coord_ajeno_ve_el_suyo_y_no_el_ajeno(client, d96_sync):
    d = d96_sync
    r = client.get("/sync/conflictos", headers=d["h"](d["coord_o"]))
    assert r.status_code == 200, r.text
    ids = {c["id"] for c in r.json()}
    assert d["conflicto_b"] in ids
    assert d["conflicto_a"] not in ids


def test_get_admin_ve_todos(client, d96_sync):
    d = d96_sync
    r = client.get("/sync/conflictos", headers=d["h"](d["admin"]))
    assert r.status_code == 200, r.text
    ids = {c["id"] for c in r.json()}
    assert d["conflicto_a"] in ids
    assert d["conflicto_b"] in ids


def test_get_residente_devuelve_403(client, d96_sync):
    d = d96_sync
    r = client.get("/sync/conflictos", headers=d["h"](d["resid"]))
    assert r.status_code == 403, r.text


# ── POST /sync/conflictos/{id}/resolver ──────────────────────────────────────

def test_resolver_coord_ajeno_devuelve_404(client, d96_sync, db):
    d = d96_sync
    r = client.post(
        f"/sync/conflictos/{d['conflicto_a']}/resolver",
        json={"version_ganadora": "local"},
        headers=d["h"](d["coord_o"]),
    )
    assert r.status_code == 404, r.text

    db.expire_all()
    c = db.query(SyncConflicto).filter(SyncConflicto.id == d["conflicto_a"]).first()
    assert c.estado == ConflictoEstado.PENDIENTE
    item = db.query(Item).filter(Item.id == d["item_a"]).first()
    assert item.estado == ItemEstado.ABIERTO
    comentario = db.query(ItemComentario).filter(ItemComentario.item_id == d["item_a"]).first()
    assert comentario is None


def test_resolver_coord_principal_devuelve_200(client, d96_sync, db):
    d = d96_sync
    r = client.post(
        f"/sync/conflictos/{d['conflicto_a']}/resolver",
        json={"version_ganadora": "servidor"},
        headers=d["h"](d["coord_p"]),
    )
    assert r.status_code == 200, r.text

    db.expire_all()
    c = db.query(SyncConflicto).filter(SyncConflicto.id == d["conflicto_a"]).first()
    assert c.estado == ConflictoEstado.RESUELTO
    assert c.resuelto_por == d["coord_p_id"]


def test_resolver_admin_devuelve_200(client, d96_sync):
    d = d96_sync
    r = client.post(
        f"/sync/conflictos/{d['conflicto_a']}/resolver",
        json={"version_ganadora": "servidor"},
        headers=d["h"](d["admin"]),
    )
    assert r.status_code == 200, r.text


def test_resolver_residente_devuelve_403(client, d96_sync):
    d = d96_sync
    r = client.post(
        f"/sync/conflictos/{d['conflicto_a']}/resolver",
        json={"version_ganadora": "servidor"},
        headers=d["h"](d["resid"]),
    )
    assert r.status_code == 403, r.text
