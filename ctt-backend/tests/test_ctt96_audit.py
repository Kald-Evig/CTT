"""
test_ctt96_audit.py — Resource-scoped auth en GET /audit-log (CTT-96).

Cubre:
  - Coordinador SIN param: solo ve entradas de sus proyectos.
  - Coordinador CON ?proyecto_id ajeno: 404.
  - Coordinador CON ?proyecto_id propio: 200 con sus entradas.
  - Admin SIN param: ve todo, incluidas entradas con proyecto_id NULL.
  - Residente / Trabajador: 403 (bloqueados por puede()).
  - Entrada con proyecto_id=NULL: invisible para Coordinador, visible para Admin.
"""

import pytest

from app.audit import record_audit
from app.enums import EmpresaPlan, Rol
from app.models import Empresa, EmpresaUsuario, Proyecto, Usuario


@pytest.fixture()
def d96a(db):
    """
    Empresa con 5 actores y 2 proyectos.

    empresa:
      admin    — ADMIN
      coord_p  — COORDINADOR, coordinador_principal de proy_a
      coord_o  — COORDINADOR, coordinador_principal de proy_b
      resid    — RESIDENTE (sin membresía en ningún proyecto)
      trab     — TRABAJADOR (sin membresía en ningún proyecto)

    Entradas de audit:
      entrada_a    — proyecto_id = proy_a.id  (visible para coord_p y admin)
      entrada_b    — proyecto_id = proy_b.id  (visible solo para coord_o y admin)
      entrada_null — proyecto_id = None       (solo admin; acción empresa-scope)
    """
    emp = Empresa(nombre="Emp96A", rut_empresa="76.996.997-7",
                  email_contacto="a@96a.cl", plan=EmpresaPlan.PRO)
    db.add(emp)
    db.flush()

    admin   = Usuario(firebase_uid="96a-admin",   nombre_completo="Admin 96A",
                      email="admin@96a.cl")
    coord_p = Usuario(firebase_uid="96a-coord-p", nombre_completo="Coord P 96A",
                      email="coord.p@96a.cl")
    coord_o = Usuario(firebase_uid="96a-coord-o", nombre_completo="Coord O 96A",
                      email="coord.o@96a.cl")
    resid   = Usuario(firebase_uid="96a-resid",   nombre_completo="Resid 96A",
                      email="resid@96a.cl")
    trab    = Usuario(firebase_uid="96a-trab",    nombre_completo="Trab 96A",
                      email="trab@96a.cl")
    db.add_all([admin, coord_p, coord_o, resid, trab])
    db.flush()

    db.add_all([
        EmpresaUsuario(empresa_id=emp.id, usuario_id=admin.id,   rol=Rol.ADMIN),
        EmpresaUsuario(empresa_id=emp.id, usuario_id=coord_p.id, rol=Rol.COORDINADOR),
        EmpresaUsuario(empresa_id=emp.id, usuario_id=coord_o.id, rol=Rol.COORDINADOR),
        EmpresaUsuario(empresa_id=emp.id, usuario_id=resid.id,   rol=Rol.RESIDENTE),
        EmpresaUsuario(empresa_id=emp.id, usuario_id=trab.id,    rol=Rol.TRABAJADOR),
    ])

    proy_a = Proyecto(empresa_id=emp.id, nombre="Proy A 96A",
                      coordinador_principal_id=coord_p.id, created_by=coord_p.id)
    proy_b = Proyecto(empresa_id=emp.id, nombre="Proy B 96A",
                      coordinador_principal_id=coord_o.id, created_by=coord_o.id)
    db.add_all([proy_a, proy_b])
    db.flush()

    # flush entre llamadas: _next_folio usa MAX(folio)+1 en sesión activa;
    # sin flush los tres registros computan folio=1 y el commit falla por UNIQUE.
    record_audit(db, empresa_id=emp.id, actor_id=coord_p.id,
                 actor_nombre="Coord P 96A", actor_rol="coordinador",
                 accion="edicion_datos", entidad_tipo="proyecto",
                 entidad_id=proy_a.id, proyecto_id=proy_a.id)
    db.flush()
    record_audit(db, empresa_id=emp.id, actor_id=coord_o.id,
                 actor_nombre="Coord O 96A", actor_rol="coordinador",
                 accion="edicion_datos", entidad_tipo="proyecto",
                 entidad_id=proy_b.id, proyecto_id=proy_b.id)
    db.flush()
    # Entrada empresa-scope: proyecto_id=None. No existen aún en producción,
    # pero el test blinda la Opción A para cuando aparezcan.
    record_audit(db, empresa_id=emp.id, actor_id=admin.id,
                 actor_nombre="Admin 96A", actor_rol="admin",
                 accion="crear_usuario", entidad_tipo="usuario",
                 entidad_id=coord_p.id, proyecto_id=None)
    db.commit()

    def h(uid: str) -> dict:
        return {"Authorization": f"Bearer {uid}", "X-Empresa-Id": emp.id}

    return {
        "proy_a_id": proy_a.id,
        "proy_b_id": proy_b.id,
        "admin":   admin.firebase_uid,
        "coord_p": coord_p.firebase_uid,
        "coord_o": coord_o.firebase_uid,
        "resid":   resid.firebase_uid,
        "trab":    trab.firebase_uid,
        "h": h,
    }


def test_coord_sin_param_ve_solo_sus_proyectos(client, d96a):
    r = client.get("/audit-log", headers=d96a["h"](d96a["coord_p"]))
    assert r.status_code == 200, r.text
    entradas = r.json()
    ids_proyecto = {e["proyecto_id"] for e in entradas}
    assert ids_proyecto == {d96a["proy_a_id"]}


def test_coord_proyecto_ajeno_404(client, d96a):
    r = client.get(f"/audit-log?proyecto_id={d96a['proy_b_id']}",
                   headers=d96a["h"](d96a["coord_p"]))
    assert r.status_code == 404, r.text


def test_coord_proyecto_propio_200(client, d96a):
    r = client.get(f"/audit-log?proyecto_id={d96a['proy_a_id']}",
                   headers=d96a["h"](d96a["coord_p"]))
    assert r.status_code == 200, r.text
    entradas = r.json()
    assert len(entradas) == 1
    assert entradas[0]["proyecto_id"] == d96a["proy_a_id"]


def test_admin_sin_param_ve_todo(client, d96a):
    r = client.get("/audit-log", headers=d96a["h"](d96a["admin"]))
    assert r.status_code == 200, r.text
    assert len(r.json()) == 3


def test_residente_403(client, d96a):
    r = client.get("/audit-log", headers=d96a["h"](d96a["resid"]))
    assert r.status_code == 403, r.text


def test_trabajador_403(client, d96a):
    r = client.get("/audit-log", headers=d96a["h"](d96a["trab"]))
    assert r.status_code == 403, r.text


def test_entrada_null_invisible_coord_visible_admin(client, d96a):
    """proyecto_id=NULL es invisible para Coordinador (Opción A) y visible para Admin."""
    r_coord = client.get("/audit-log", headers=d96a["h"](d96a["coord_p"]))
    r_admin = client.get("/audit-log", headers=d96a["h"](d96a["admin"]))

    assert r_coord.status_code == 200, r_coord.text
    assert r_admin.status_code == 200, r_admin.text

    nulos_coord = [e for e in r_coord.json() if e["proyecto_id"] is None]
    nulos_admin = [e for e in r_admin.json() if e["proyecto_id"] is None]

    assert len(nulos_coord) == 0
    assert len(nulos_admin) == 1
