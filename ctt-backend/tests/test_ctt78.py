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


# ── AJUSTE 1: Coordinador creador queda como coordinador_principal (CTT-78) ──

def test_crear_coordinador_sin_principal_queda_como_principal(client, d78):
    """Bug fix: Coordinador crea sin body.coordinador_principal_id → auto-asignado.
    Sin el fix, la factory le rechazaba PUT con 404 al intentar editar su propio proyecto."""
    hdr = _hdr(d78, "coord_p")
    r = client.post("/proyectos", json={"nombre": "Nuevo CTT-78"}, headers=hdr)
    assert r.status_code == 201, r.text
    nuevo_id = r.json()["id"]
    assert r.json()["coordinador_principal_id"] == d78["coord_p_id"]

    # Puede editar inmediatamente — este era el bug bloqueante
    r_put = client.put(f"/proyectos/{nuevo_id}", json={"nombre": "Editado"},
                       headers=hdr)
    assert r_put.status_code == 200, r_put.text


def test_crear_coordinador_con_otro_principal_no_sobreescribe(client, d78):
    """Si body.coordinador_principal_id viene definido, se respeta sin sobreescribir."""
    hdr = _hdr(d78, "coord_p")
    r = client.post(
        "/proyectos",
        json={"nombre": "Delegado", "coordinador_principal_id": d78["coord_o_id"]},
        headers=hdr,
    )
    assert r.status_code == 201, r.text
    assert r.json()["coordinador_principal_id"] == d78["coord_o_id"]


def test_crear_admin_sin_principal_queda_null(client, d78):
    """Admin crea sin coordinador_principal_id → queda null.
    Admin no necesita principal: pasa por el bypass es_super_admin/ADMIN de la factory."""
    hdr = _hdr(d78, "admin")
    r = client.post("/proyectos", json={"nombre": "Proj Admin"}, headers=hdr)
    assert r.status_code == 201, r.text
    nuevo_id = r.json()["id"]
    assert r.json()["coordinador_principal_id"] is None

    # Admin puede editarlo igual (bypass de factory)
    r_put = client.put(f"/proyectos/{nuevo_id}", json={"nombre": "Edit Admin"},
                       headers=hdr)
    assert r_put.status_code == 200, r_put.text



# ── AJUSTE 2: Consistencia entre scope_orm, scope_sql y la factory ─────────

@pytest.fixture()
def d78_scope(db):
    """
    Fixture de consistencia: 3 proyectos con distinta configuración de
    coordinador_principal y membresías, para verificar que las tres
    implementaciones del scope concuerdan.

      proy_a: coordinador_principal = coord_p; miembros: resid_a (RESIDENTE), trab_a (TRABAJADOR)
      proy_b: coordinador_principal = coord_o; miembros: resid_b (RESIDENTE)
      proy_c: coordinador_principal = None;    sin miembros

    La consume test_scope_consistencia_entre_fuentes, que verifica:
      - Consistencia scope_orm / scope_sql / factory sobre el mismo conjunto.
      - Invariante A: visibilidad de proyecto ↔ visibilidad de ítem (CTT-96).
      - Invariante B: el TRABAJADOR ve exactamente sus ítems asignados (CTT-96).
    """
    emp = Empresa(nombre="Emp Scope", rut_empresa="76.999.999-9",
                  email_contacto="scope@t.cl", plan=EmpresaPlan.PRO)
    db.add(emp)
    db.flush()

    admin    = Usuario(firebase_uid="sc-admin",    nombre_completo="Admin Sc",    email="admin@sc.cl")
    coord_p  = Usuario(firebase_uid="sc-coord-p",  nombre_completo="Coord P Sc",  email="coord.p@sc.cl")
    coord_o  = Usuario(firebase_uid="sc-coord-o",  nombre_completo="Coord O Sc",  email="coord.o@sc.cl")
    resid_a  = Usuario(firebase_uid="sc-resid-a",  nombre_completo="Resid A Sc",  email="resid.a@sc.cl")
    resid_b  = Usuario(firebase_uid="sc-resid-b",  nombre_completo="Resid B Sc",  email="resid.b@sc.cl")
    resid_nm = Usuario(firebase_uid="sc-resid-nm", nombre_completo="Resid NM Sc", email="resid.nm@sc.cl")
    trab_a   = Usuario(firebase_uid="sc-trab-a",   nombre_completo="Trab A Sc",   email="trab.a@sc.cl")
    trab_nm  = Usuario(firebase_uid="sc-trab-nm",  nombre_completo="Trab NM Sc",  email="trab.nm@sc.cl")
    db.add_all([admin, coord_p, coord_o, resid_a, resid_b, resid_nm, trab_a, trab_nm])
    db.flush()

    db.add_all([
        EmpresaUsuario(empresa_id=emp.id, usuario_id=admin.id,    rol=Rol.ADMIN),
        EmpresaUsuario(empresa_id=emp.id, usuario_id=coord_p.id,  rol=Rol.COORDINADOR),
        EmpresaUsuario(empresa_id=emp.id, usuario_id=coord_o.id,  rol=Rol.COORDINADOR),
        EmpresaUsuario(empresa_id=emp.id, usuario_id=resid_a.id,  rol=Rol.RESIDENTE),
        EmpresaUsuario(empresa_id=emp.id, usuario_id=resid_b.id,  rol=Rol.RESIDENTE),
        EmpresaUsuario(empresa_id=emp.id, usuario_id=resid_nm.id, rol=Rol.RESIDENTE),
        EmpresaUsuario(empresa_id=emp.id, usuario_id=trab_a.id,   rol=Rol.TRABAJADOR),
        EmpresaUsuario(empresa_id=emp.id, usuario_id=trab_nm.id,  rol=Rol.TRABAJADOR),
    ])

    proy_a = Proyecto(empresa_id=emp.id, nombre="Scope A",
                      coordinador_principal_id=coord_p.id, created_by=coord_p.id)
    proy_b = Proyecto(empresa_id=emp.id, nombre="Scope B",
                      coordinador_principal_id=coord_o.id, created_by=coord_o.id)
    proy_c = Proyecto(empresa_id=emp.id, nombre="Scope C",
                      coordinador_principal_id=None, created_by=admin.id)
    db.add_all([proy_a, proy_b, proy_c])
    db.flush()

    db.add_all([
        ProyectoUsuario(proyecto_id=proy_a.id, usuario_id=resid_a.id,
                        rol_en_proyecto=Rol.RESIDENTE),
        ProyectoUsuario(proyecto_id=proy_b.id, usuario_id=resid_b.id,
                        rol_en_proyecto=Rol.RESIDENTE),
        ProyectoUsuario(proyecto_id=proy_a.id, usuario_id=trab_a.id,
                        rol_en_proyecto=Rol.TRABAJADOR),
    ])
    db.commit()

    def h(uid: str) -> dict:
        return {"Authorization": f"Bearer {uid}"}

    return {
        "universo":  {proy_a.id, proy_b.id, proy_c.id},
        "proy_a_id": proy_a.id,
        "proy_b_id": proy_b.id,
        "admin":     admin.firebase_uid,
        "coord_p":   coord_p.firebase_uid,
        "coord_o":   coord_o.firebase_uid,
        "resid_a":   resid_a.firebase_uid,
        "resid_b":   resid_b.firebase_uid,
        "resid_nm":  resid_nm.firebase_uid,
        "trab_a":    trab_a.firebase_uid,
        "trab_a_id": trab_a.id,
        "trab_nm":   trab_nm.firebase_uid,
        "h": h,
    }


def test_scope_consistencia_entre_fuentes(client, d78_scope):
    """
    Verifica que scope_orm (GET /proyectos), scope_sql (GET /proyectos/dashboard)
    y la factory (GET /proyectos/{id}) concuerdan sobre el mismo conjunto de proyectos
    para cada actor.

    Si cualquiera de las tres implementaciones diverge, este test rompe — es el mecanismo
    que reemplaza al comentario 'actualizar en paralelo'.

    Fixture: 3 proyectos (proy_a principal=coord_p, proy_b principal=coord_o, proy_c sin
    principal). Membresías: resid_a→proy_a, resid_b→proy_b, trab_a→proy_a.

    Nota sobre TRABAJADOR: la lista (scope_orm) incluye sus proyectos con membresía,
    pero la factory devuelve 403 (visible pero sin permiso de acceso). Se verifica que
    la factory no devuelve 404 (que sería inconsistente con la visibilidad en lista).
    TRABAJADOR no tiene acceso al dashboard (acceso_reportes), así que la comparación
    A==B no aplica para ese rol.
    """
    d = d78_scope
    universo = d["universo"]
    actores = [
        "admin", "coord_p", "coord_o",
        "resid_a", "resid_b", "resid_nm",
        "trab_a", "trab_nm",
    ]

    for actor in actores:
        hdr = d["h"](d[actor])

        # A: ids visibles via scope_orm (GET /proyectos)
        r_lista = client.get("/proyectos", headers=hdr)
        assert r_lista.status_code == 200, \
            f"[{actor}] GET /proyectos devolvió {r_lista.status_code}"
        ids_lista = {p["id"] for p in r_lista.json()}

        # B: ids visibles via scope_sql (GET /proyectos/dashboard)
        # Solo para roles con acceso_reportes; TRABAJADOR recibe 403 → skip comparación.
        r_dash = client.get("/proyectos/dashboard", headers=hdr)
        if r_dash.status_code == 200:
            ids_dash = {p["id"] for p in r_dash.json()}
            assert ids_lista == ids_dash, (
                f"[{actor}] scope_orm ≠ scope_sql: "
                f"lista={ids_lista} dashboard={ids_dash}"
            )

        # C: factory por proyecto — visibilidad en lista ↔ factory no devuelve 404
        for pid in universo:
            r_get = client.get(f"/proyectos/{pid}", headers=hdr)
            if pid in ids_lista:
                assert r_get.status_code != 404, (
                    f"[{actor}] proyecto {pid!r} está en lista "
                    f"pero factory devuelve 404"
                )
            else:
                assert r_get.status_code == 404, (
                    f"[{actor}] proyecto {pid!r} NO está en lista "
                    f"pero factory devuelve {r_get.status_code}"
                )

    # ── Invariante A: visibilidad de proyecto ↔ visibilidad de ítem ──────────────
    # Crear un ítem en proy_a (admin lo crea; sin asignación).
    h_admin = d["h"](d["admin"])
    r_item = client.post(
        "/items",
        json={"proyecto_id": d["proy_a_id"], "nombre": "Ítem scope A"},
        headers=h_admin,
    )
    assert r_item.status_code == 201, f"[Invariante A setup] {r_item.text}"
    item_a_id = r_item.json()["id"]

    for actor in actores:
        hdr = d["h"](d[actor])
        ids_visibles = {p["id"] for p in client.get("/proyectos", headers=hdr).json()}
        r_item_get = client.get(f"/items/{item_a_id}", headers=hdr)

        if d["proy_a_id"] in ids_visibles:
            # Actor ve proy_a → el ítem responde 200 (acceso) o 403 (visible sin permiso).
            # Aserción exacta: != 404 pasaría con 500/401/422/400 y ocultaría un endpoint roto.
            assert r_item_get.status_code in (200, 403), (
                f"[Invariante A] [{actor}] ve proy_a en lista pero ítem devuelve "
                f"{r_item_get.status_code}"
            )
        else:
            # Actor no ve proy_a → no debe poder acceder al ítem.
            assert r_item_get.status_code == 404, (
                f"[Invariante A] [{actor}] NO ve proy_a pero ítem devuelve {r_item_get.status_code}"
            )

    # ── Invariante B: TRABAJADOR ve exactamente sus ítems asignados ──────────────
    h_trab_a = d["h"](d["trab_a"])
    h_trab_nm = d["h"](d["trab_nm"])

    # item_a no está asignado a trab_a → 403 (miembro del proyecto pero no asignado).
    r = client.get(f"/items/{item_a_id}", headers=h_trab_a)
    assert r.status_code == 403, (
        f"[Invariante B] trab_a accedió a ítem no asignado con {r.status_code}"
    )

    # Crear ítem asignado a trab_a → trab_a debe poder verlo.
    r_mi = client.post(
        "/items",
        json={"proyecto_id": d["proy_a_id"], "nombre": "Ítem de trab_a",
              "asignado_a": d["trab_a_id"]},
        headers=h_admin,
    )
    assert r_mi.status_code == 201, f"[Invariante B setup] {r_mi.text}"
    item_trab_id = r_mi.json()["id"]

    assert client.get(f"/items/{item_trab_id}", headers=h_trab_a).status_code == 200, (
        "[Invariante B] trab_a no puede ver su ítem asignado"
    )
    # trab_nm: no miembro, no asignado → 404.
    assert client.get(f"/items/{item_trab_id}", headers=h_trab_nm).status_code == 404, (
        "[Invariante B] trab_nm accedió a ítem ajeno"
    )

    # ── Jerarquía (DoD "incluidos los hijos"): las DOS invariantes valen sobre un HIJO ──
    # Hijo de item_a en proy_a (nivel 1), sin asignación.
    r_hijo = client.post(
        "/items",
        json={"proyecto_id": d["proy_a_id"], "nombre": "Hijo scope A",
              "parent_item_id": item_a_id},
        headers=h_admin,
    )
    assert r_hijo.status_code == 201, f"[Jerarquía setup] {r_hijo.text}"
    hijo_id = r_hijo.json()["id"]

    # Invariante A sobre el hijo: visibilidad de proy_a ↔ visibilidad del hijo.
    for actor in actores:
        hdr = d["h"](d[actor])
        ids_visibles = {p["id"] for p in client.get("/proyectos", headers=hdr).json()}
        r_hijo_get = client.get(f"/items/{hijo_id}", headers=hdr)
        if d["proy_a_id"] in ids_visibles:
            assert r_hijo_get.status_code in (200, 403), (
                f"[Jerarquía/Invariante A] [{actor}] ve proy_a pero el hijo devuelve "
                f"{r_hijo_get.status_code}"
            )
        else:
            assert r_hijo_get.status_code == 404, (
                f"[Jerarquía/Invariante A] [{actor}] NO ve proy_a pero el hijo devuelve "
                f"{r_hijo_get.status_code}"
            )

    # Invariante B sobre el hijo: el TRABAJADOR ve exactamente sus hijos asignados.
    # hijo no asignado a trab_a → 403 (miembro del proyecto pero no asignado al hijo).
    assert client.get(f"/items/{hijo_id}", headers=h_trab_a).status_code == 403, (
        "[Jerarquía/Invariante B] trab_a accedió a hijo no asignado"
    )
    # Crear hijo asignado a trab_a → trab_a debe poder verlo.
    r_hijo_mi = client.post(
        "/items",
        json={"proyecto_id": d["proy_a_id"], "nombre": "Hijo de trab_a",
              "parent_item_id": item_a_id, "asignado_a": d["trab_a_id"]},
        headers=h_admin,
    )
    assert r_hijo_mi.status_code == 201, f"[Jerarquía/Invariante B setup] {r_hijo_mi.text}"
    hijo_trab_id = r_hijo_mi.json()["id"]
    assert client.get(f"/items/{hijo_trab_id}", headers=h_trab_a).status_code == 200, (
        "[Jerarquía/Invariante B] trab_a no puede ver su hijo asignado"
    )
    # trab_nm: no miembro, no asignado → 404.
    assert client.get(f"/items/{hijo_trab_id}", headers=h_trab_nm).status_code == 404, (
        "[Jerarquía/Invariante B] trab_nm accedió a hijo ajeno"
    )
