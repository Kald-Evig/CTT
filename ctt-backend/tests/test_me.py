"""
test_me.py — Suite de tests para GET /me.

Cubre: usuario con una empresa, con dos empresas, sin empresas, inexistente,
empresa suspendida, membresía inactiva y super_admin sin empresas.
"""

import pytest
from fastapi.testclient import TestClient

from app.database import Base, SessionLocal, engine
from app.enums import EmpresaEstado, EmpresaPlan, Rol, UsuarioEstado
from app.main import app
from app.models import Empresa, EmpresaUsuario, Usuario


def _reset():
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)


@pytest.fixture()
def client():
    return TestClient(app)


@pytest.fixture()
def db_limpia():
    """Sesión limpia contra la BD de test."""
    _reset()
    s = SessionLocal()
    try:
        yield s
    finally:
        s.close()


def _headers(uid: str) -> dict:
    return {"Authorization": f"Bearer {uid}"}


# ── Caso 1: usuario con una empresa activa ────────────────────────────────────
def test_me_una_empresa(client, db_limpia):
    emp = Empresa(
        nombre="Empresa Alpha",
        rut_empresa="76.111.111-1",
        email_contacto="alpha@test.cl",
        plan=EmpresaPlan.PRO,
    )
    db_limpia.add(emp)
    db_limpia.flush()

    usuario = Usuario(
        firebase_uid="uid-alpha",
        nombre_completo="Ana López",
        email="ana@test.cl",
    )
    db_limpia.add(usuario)
    db_limpia.flush()

    db_limpia.add(EmpresaUsuario(
        empresa_id=emp.id, usuario_id=usuario.id, rol=Rol.ADMIN,
    ))
    db_limpia.commit()

    r = client.get("/me", headers=_headers("uid-alpha"))
    assert r.status_code == 200
    data = r.json()

    assert data["usuario"]["email"] == "ana@test.cl"
    assert data["usuario"]["nombre_completo"] == "Ana López"
    assert data["usuario"]["es_super_admin"] is False
    assert "rut" not in data["usuario"]

    assert len(data["empresas"]) == 1
    assert data["empresas"][0]["empresa_nombre"] == "Empresa Alpha"
    assert data["empresas"][0]["rol"] == "admin"


# ── Caso 2: usuario con dos empresas activas ──────────────────────────────────
def test_me_dos_empresas(client, db_limpia):
    emp1 = Empresa(nombre="Empresa 1", rut_empresa="76.100.001-1",
                   email_contacto="e1@test.cl", plan=EmpresaPlan.PRO)
    emp2 = Empresa(nombre="Empresa 2", rut_empresa="76.100.002-2",
                   email_contacto="e2@test.cl", plan=EmpresaPlan.BASIC)
    db_limpia.add_all([emp1, emp2])
    db_limpia.flush()

    usuario = Usuario(firebase_uid="uid-dos", nombre_completo="Carlos Mena",
                      email="carlos@test.cl")
    db_limpia.add(usuario)
    db_limpia.flush()

    db_limpia.add_all([
        EmpresaUsuario(empresa_id=emp1.id, usuario_id=usuario.id, rol=Rol.COORDINADOR),
        EmpresaUsuario(empresa_id=emp2.id, usuario_id=usuario.id, rol=Rol.RESIDENTE),
    ])
    db_limpia.commit()

    r = client.get("/me", headers=_headers("uid-dos"))
    assert r.status_code == 200
    data = r.json()

    nombres = {e["empresa_nombre"] for e in data["empresas"]}
    assert nombres == {"Empresa 1", "Empresa 2"}
    assert len(data["empresas"]) == 2


# ── Caso 3: usuario sin empresas → 200 con lista vacía ───────────────────────
def test_me_sin_empresas(client, db_limpia):
    usuario = Usuario(firebase_uid="uid-solo", nombre_completo="Pedro Sin Empresa",
                      email="pedro@test.cl")
    db_limpia.add(usuario)
    db_limpia.commit()

    r = client.get("/me", headers=_headers("uid-solo"))
    assert r.status_code == 200
    data = r.json()
    assert data["empresas"] == []
    assert data["usuario"]["email"] == "pedro@test.cl"


# ── Caso 4: firebase_uid no registrado → 404 ─────────────────────────────────
def test_me_usuario_inexistente(client, db_limpia):
    r = client.get("/me", headers=_headers("uid-que-no-existe"))
    assert r.status_code == 404
    assert "no encontrado" in r.json()["detail"].lower()


# ── Caso 5: empresa suspendida no aparece en la lista ────────────────────────
def test_me_empresa_suspendida_no_aparece(client, db_limpia):
    emp_ok = Empresa(nombre="Empresa Activa", rut_empresa="76.200.001-1",
                     email_contacto="ok@test.cl", plan=EmpresaPlan.PRO,
                     estado=EmpresaEstado.ACTIVO)
    emp_susp = Empresa(nombre="Empresa Suspendida", rut_empresa="76.200.002-2",
                       email_contacto="susp@test.cl", plan=EmpresaPlan.TRIAL,
                       estado=EmpresaEstado.SUSPENDIDO)
    db_limpia.add_all([emp_ok, emp_susp])
    db_limpia.flush()

    usuario = Usuario(firebase_uid="uid-susp", nombre_completo="Laura Vera",
                      email="laura@test.cl")
    db_limpia.add(usuario)
    db_limpia.flush()

    db_limpia.add_all([
        EmpresaUsuario(empresa_id=emp_ok.id, usuario_id=usuario.id, rol=Rol.ADMIN),
        EmpresaUsuario(empresa_id=emp_susp.id, usuario_id=usuario.id, rol=Rol.TRABAJADOR),
    ])
    db_limpia.commit()

    r = client.get("/me", headers=_headers("uid-susp"))
    assert r.status_code == 200
    nombres = [e["empresa_nombre"] for e in r.json()["empresas"]]
    assert "Empresa Suspendida" not in nombres
    assert "Empresa Activa" in nombres


# ── Caso 6: membresía con estado=inactivo no aparece ─────────────────────────
def test_me_membresia_inactiva_no_aparece(client, db_limpia):
    emp = Empresa(nombre="Empresa Trial", rut_empresa="76.300.001-1",
                  email_contacto="trial@test.cl", plan=EmpresaPlan.TRIAL)
    db_limpia.add(emp)
    db_limpia.flush()

    usuario = Usuario(firebase_uid="uid-inact", nombre_completo="Mario Rivas",
                      email="mario@test.cl")
    db_limpia.add(usuario)
    db_limpia.flush()

    db_limpia.add(EmpresaUsuario(
        empresa_id=emp.id, usuario_id=usuario.id,
        rol=Rol.TRABAJADOR, estado=UsuarioEstado.INACTIVO,
    ))
    db_limpia.commit()

    r = client.get("/me", headers=_headers("uid-inact"))
    assert r.status_code == 200
    assert r.json()["empresas"] == []


# ── Caso 7: super_admin sin empresas → 200 con lista vacía ───────────────────
def test_me_super_admin_sin_empresas(client, db_limpia):
    usuario = Usuario(firebase_uid="uid-sa", nombre_completo="Super Admin",
                      email="sa@ctt.cl", es_super_admin=True)
    db_limpia.add(usuario)
    db_limpia.commit()

    r = client.get("/me", headers=_headers("uid-sa"))
    assert r.status_code == 200
    data = r.json()
    assert data["usuario"]["es_super_admin"] is True
    assert data["empresas"] == []
