"""
test_ctt78.py — Autorización resource-scoped en endpoints de proyecto (CTT-78).

Cubre los 6 endpoints no cubiertos por test_authz.py (que testa la factory directa):
  - GET  /proyectos              (listar — scope por rol)
  - GET  /proyectos/dashboard    (dashboard — scope por rol + acceso_reportes)
  - GET  /proyectos/{id}         (obtener — factory lectura)
  - PUT  /proyectos/{id}         (editar  — factory gestionar + puede)
  - GET  /proyectos/{id}/historial (historial — factory lectura + puede)
  - POST /proyectos/{id}/cerrar  (cerrar  — factory gestionar + puede)

Más: test de escalación (coordinador no principal intenta reasignarse).
"""

import pytest

from app.enums import EmpresaPlan, Rol
from app.models import Empresa, EmpresaUsuario, Proyecto, ProyectoUsuario, Usuario


# ── Fixture ───────────────────────────────────────────────────────────────────

@pytest.fixture()
def d78(db):
    """
    Empresa A con 6 actores; Empresa B para test cross-tenant.

    empresa_a:
      admin    — ADMIN
      coord_p  — COORDINADOR, coordinador_principal del proyecto
      coord_o  — COORDINADOR, NO coordinador_principal
      resid_m  — RESIDENTE, miembro activo en proyecto_usuarios
      resid_nm — RESIDENTE, sin membresía en proyecto_usuarios
      trab     — TRABAJADOR, sin membresía

    empresa_b:
      admin_b  — ADMIN (cross-tenant)

    proyecto: empresa_a, coordinador_principal_id = coord_p.id
    proyecto_usuarios: resid_m es miembro activo
    """
    emp_a = Empresa(nombre="Emp78 A", rut_empresa="76.111.111-1",
                    email_contacto="a@78.cl", plan=EmpresaPlan.PRO)
    emp_b = Empresa(nombre="Emp78 B", rut_empresa="77.222.222-2",
                    email_contacto="b@78.cl", plan=EmpresaPlan.BASIC)
    db.add_all([emp_a, emp_b])
    db.flush()

    admin   = Usuario(firebase_uid="78-admin",    nombre_completo="Admin",    email="admin@78.cl")
    coord_p = Usuario(firebase_uid="78-coord-p",  nombre_completo="Coord P",  email="coord.p@78.cl")
    coord_o = Usuario(firebase_uid="78-coord-o",  nombre_completo="Coord O",  email="coord.o@78.cl")
    resid_m = Usuario(firebase_uid="78-resid-m",  nombre_completo="Resid M",  email="resid.m@78.cl")
    resid_nm = Usuario(firebase_uid="78-resid-nm", nombre_completo="Resid NM", email="resid.nm@78.cl")
    trab    = Usuario(firebase_uid="78-trab",     nombre_completo="Trab",     email="trab@78.cl")
    admin_b = Usuario(firebase_uid="78-admin-b",  nombre_completo="Admin B",  email="admin.b@78.cl")
    db.add_all([admin, coord_p, coord_o, resid_m, resid_nm, trab, admin_b])
    db.flush()

    db.add_all([
        EmpresaUsuario(empresa_id=emp_a.id, usuario_id=admin.id,    rol=Rol.ADMIN),
        EmpresaUsuario(empresa_id=emp_a.id, usuario_id=coord_p.id,  rol=Rol.COORDINADOR),
        EmpresaUsuario(empresa_id=emp_a.id, usuario_id=coord_o.id,  rol=Rol.COORDINADOR),
        EmpresaUsuario(empresa_id=emp_a.id, usuario_id=resid_m.id,  rol=Rol.RESIDENTE),
        EmpresaUsuario(empresa_id=emp_a.id, usuario_id=resid_nm.id, rol=Rol.RESIDENTE),
        EmpresaUsuario(empresa_id=emp_a.id, usuario_id=trab.id,     rol=Rol.TRABAJADOR),
        EmpresaUsuario(empresa_id=emp_b.id, usuario_id=admin_b.id,  rol=Rol.ADMIN),
    ])

    proyecto = Proyecto(
        empresa_id=emp_a.id,
        nombre="Obra CTT-78",
        coordinador_principal_id=coord_p.id,
        created_by=coord_p.id,
    )
    db.add(proyecto)
    db.flush()
    db.add(ProyectoUsuario(proyecto_id=proyecto.id, usuario_id=resid_m.id,
                           rol_en_proyecto=Rol.RESIDENTE))
    db.commit()

    def h(uid: str, empresa_id: str | None = None) -> dict:
        hdr = {"Authorization": f"Bearer {uid}"}
        if empresa_id:
            hdr["X-Empresa-Id"] = empresa_id
        return hdr

    return {
        "db":      db,
        "pid":     proyecto.id,
        "emp_a":   emp_a.id,
        "emp_b":   emp_b.id,
        "admin":   (admin.firebase_uid,    emp_a.id),
        "coord_p": (coord_p.firebase_uid,  emp_a.id),
        "coord_o": (coord_o.firebase_uid,  emp_a.id),
        "resid_m": (resid_m.firebase_uid,  emp_a.id),
        "resid_nm":(resid_nm.firebase_uid, emp_a.id),
        "trab":    (trab.firebase_uid,     emp_a.id),
        "admin_b": (admin_b.firebase_uid,  emp_b.id),
        "coord_p_id": coord_p.id,
        "coord_o_id": coord_o.id,
        "h": h,
    }


def _hdr(d, actor: str) -> dict:
    uid, emp = d[actor]
    return d["h"](uid, emp)


# ── GET /proyectos — listar (scope por rol) ───────────────────────────────────

def test_listar_admin_ve_proyecto(client, d78):
    r = client.get("/proyectos", headers=_hdr(d78, "admin"))
    assert r.status_code == 200
    ids = [p["id"] for p in r.json()]
    assert d78["pid"] in ids


def test_listar_coord_p_ve_proyecto(client, d78):
    r = client.get("/proyectos", headers=_hdr(d78, "coord_p"))
    assert r.status_code == 200
    ids = [p["id"] for p in r.json()]
    assert d78["pid"] in ids


def test_listar_coord_o_no_ve_proyecto(client, d78):
    r = client.get("/proyectos", headers=_hdr(d78, "coord_o"))
    assert r.status_code == 200
    assert r.json() == []


def test_listar_resid_m_ve_proyecto(client, d78):
    r = client.get("/proyectos", headers=_hdr(d78, "resid_m"))
    assert r.status_code == 200
    ids = [p["id"] for p in r.json()]
    assert d78["pid"] in ids


def test_listar_resid_nm_no_ve_proyecto(client, d78):
    r = client.get("/proyectos", headers=_hdr(d78, "resid_nm"))
    assert r.status_code == 200
    assert r.json() == []


def test_listar_empresa_b_no_ve_empresa_a(client, d78):
    r = client.get("/proyectos", headers=_hdr(d78, "admin_b"))
    assert r.status_code == 200
    assert r.json() == []


# ── GET /proyectos/dashboard — scope por rol + acceso_reportes ───────────────

def test_dashboard_admin_ve_proyecto(client, d78):
    r = client.get("/proyectos/dashboard", headers=_hdr(d78, "admin"))
    assert r.status_code == 200
    ids = [p["id"] for p in r.json()]
    assert d78["pid"] in ids


def test_dashboard_coord_p_ve_proyecto(client, d78):
    r = client.get("/proyectos/dashboard", headers=_hdr(d78, "coord_p"))
    assert r.status_code == 200
    ids = [p["id"] for p in r.json()]
    assert d78["pid"] in ids


def test_dashboard_coord_o_no_ve_proyecto(client, d78):
    r = client.get("/proyectos/dashboard", headers=_hdr(d78, "coord_o"))
    assert r.status_code == 200
    assert r.json() == []


def test_dashboard_resid_m_ve_proyecto(client, d78):
    r = client.get("/proyectos/dashboard", headers=_hdr(d78, "resid_m"))
    assert r.status_code == 200
    ids = [p["id"] for p in r.json()]
    assert d78["pid"] in ids


def test_dashboard_resid_nm_no_ve_proyecto(client, d78):
    r = client.get("/proyectos/dashboard", headers=_hdr(d78, "resid_nm"))
    assert r.status_code == 200
    assert r.json() == []


# ── GET /proyectos/{id} — factory lectura ────────────────────────────────────

def test_obtener_admin_200(client, d78):
    r = client.get(f"/proyectos/{d78['pid']}", headers=_hdr(d78, "admin"))
    assert r.status_code == 200
    assert r.json()["id"] == d78["pid"]


def test_obtener_coord_p_200(client, d78):
    r = client.get(f"/proyectos/{d78['pid']}", headers=_hdr(d78, "coord_p"))
    assert r.status_code == 200


def test_obtener_coord_o_404(client, d78):
    r = client.get(f"/proyectos/{d78['pid']}", headers=_hdr(d78, "coord_o"))
    assert r.status_code == 404


def test_obtener_resid_m_200(client, d78):
    r = client.get(f"/proyectos/{d78['pid']}", headers=_hdr(d78, "resid_m"))
    assert r.status_code == 200


def test_obtener_resid_nm_404(client, d78):
    r = client.get(f"/proyectos/{d78['pid']}", headers=_hdr(d78, "resid_nm"))
    assert r.status_code == 404


def test_obtener_empresa_b_404(client, d78):
    r = client.get(f"/proyectos/{d78['pid']}", headers=_hdr(d78, "admin_b"))
    assert r.status_code == 404


# ── PUT /proyectos/{id} — factory gestionar + puede ──────────────────────────

def test_editar_admin_200(client, d78):
    r = client.put(f"/proyectos/{d78['pid']}", json={"nombre": "Obra Editada Admin"},
                   headers=_hdr(d78, "admin"))
    assert r.status_code == 200


def test_editar_coord_p_200(client, d78):
    r = client.put(f"/proyectos/{d78['pid']}", json={"nombre": "Obra Editada Coord"},
                   headers=_hdr(d78, "coord_p"))
    assert r.status_code == 200


def test_editar_coord_o_404(client, d78):
    r = client.put(f"/proyectos/{d78['pid']}", json={"nombre": "Hack"},
                   headers=_hdr(d78, "coord_o"))
    assert r.status_code == 404


def test_editar_resid_403(client, d78):
    r = client.put(f"/proyectos/{d78['pid']}", json={"nombre": "Hack"},
                   headers=_hdr(d78, "resid_m"))
    assert r.status_code == 403


def test_editar_empresa_b_404(client, d78):
    r = client.put(f"/proyectos/{d78['pid']}", json={"nombre": "Hack"},
                   headers=_hdr(d78, "admin_b"))
    assert r.status_code == 404


# ── GET /proyectos/{id}/historial — factory lectura + puede ──────────────────

def test_historial_admin_200(client, d78):
    r = client.get(f"/proyectos/{d78['pid']}/historial", headers=_hdr(d78, "admin"))
    assert r.status_code == 200
    assert isinstance(r.json(), list)


def test_historial_coord_p_200(client, d78):
    r = client.get(f"/proyectos/{d78['pid']}/historial", headers=_hdr(d78, "coord_p"))
    assert r.status_code == 200


def test_historial_coord_o_404(client, d78):
    r = client.get(f"/proyectos/{d78['pid']}/historial", headers=_hdr(d78, "coord_o"))
    assert r.status_code == 404


def test_historial_resid_m_200(client, d78):
    r = client.get(f"/proyectos/{d78['pid']}/historial", headers=_hdr(d78, "resid_m"))
    assert r.status_code == 200


def test_historial_resid_nm_404(client, d78):
    r = client.get(f"/proyectos/{d78['pid']}/historial", headers=_hdr(d78, "resid_nm"))
    assert r.status_code == 404


def test_historial_empresa_b_404(client, d78):
    r = client.get(f"/proyectos/{d78['pid']}/historial", headers=_hdr(d78, "admin_b"))
    assert r.status_code == 404


# ── POST /proyectos/{id}/cerrar — factory gestionar + puede ──────────────────

def test_cerrar_admin_200(client, d78):
    r = client.post(f"/proyectos/{d78['pid']}/cerrar", headers=_hdr(d78, "admin"))
    assert r.status_code == 200
    assert r.json()["estado"] == "cerrado"


def test_cerrar_coord_p_403(client, d78):
    """Coordinador principal pasa la factory pero puede() bloquea (cerrar = solo Admin)."""
    r = client.post(f"/proyectos/{d78['pid']}/cerrar", headers=_hdr(d78, "coord_p"))
    assert r.status_code == 403


def test_cerrar_coord_o_404(client, d78):
    """Coordinador no principal → la factory da 404 antes de llegar a puede()."""
    r = client.post(f"/proyectos/{d78['pid']}/cerrar", headers=_hdr(d78, "coord_o"))
    assert r.status_code == 404


def test_cerrar_resid_403(client, d78):
    r = client.post(f"/proyectos/{d78['pid']}/cerrar", headers=_hdr(d78, "resid_m"))
    assert r.status_code == 403


def test_cerrar_empresa_b_404(client, d78):
    r = client.post(f"/proyectos/{d78['pid']}/cerrar", headers=_hdr(d78, "admin_b"))
    assert r.status_code == 404


# ── Escalación ────────────────────────────────────────────────────────────────

def test_escalacion_coord_o_no_puede_autopromocionar(client, d78):
    """Coordinador no principal intenta asignarse como coordinador_principal via PUT.
    La factory rechaza antes de que el body sea procesado: 404."""
    r = client.put(
        f"/proyectos/{d78['pid']}",
        json={"coordinador_principal_id": d78["coord_o_id"]},
        headers=_hdr(d78, "coord_o"),
    )
    assert r.status_code == 404
    # El proyecto no fue modificado — coord_p sigue siendo el principal.
    r2 = client.get(f"/proyectos/{d78['pid']}", headers=_hdr(d78, "admin"))
    assert r2.json()["coordinador_principal_id"] == d78["coord_p_id"]
