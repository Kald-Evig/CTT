"""
conftest.py — Fixtures compartidas para la suite de tests.

Usa una BD SQLite de TEST separada (variable de entorno fijada ANTES de importar
la app). Cada test parte de un esquema limpio y, donde aplica, con datos sembrados.
"""

import os

# IMPORTANTE: fijar la BD de test antes de importar cualquier módulo de la app,
# porque el engine se crea al importar app.database.
os.environ["DATABASE_URL"] = "sqlite:///./test_ctt.db"
os.environ["AUTH_MODE"] = "mock"

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from app.database import Base, SessionLocal, engine  # noqa: E402
from app.enums import EmpresaPlan, ItemEstado, Rol  # noqa: E402
from app.main import app  # noqa: E402
from app.models import (  # noqa: E402
    Empresa, EmpresaUsuario, Item, Proyecto, ProyectoUsuario, Usuario,
)


def _reset():
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)


@pytest.fixture()
def db():
    """Sesión limpia contra la BD de test."""
    _reset()
    s = SessionLocal()
    try:
        yield s
    finally:
        s.close()


@pytest.fixture()
def client():
    return TestClient(app)


class Datos:
    """Contenedor simple con los ids/tokens del set sembrado."""
    pass


@pytest.fixture()
def seeded(db):
    """Inserta un set conocido: 2 empresas, usuarios por rol y un ítem asignado.

    Devuelve un objeto con ids y un helper `headers(uid, empresa_id=None)`.
    """
    d = Datos()

    emp_a = Empresa(nombre="Empresa A", rut_empresa="76.000.000-1",
                    email_contacto="a@a.cl", plan=EmpresaPlan.PRO)
    emp_b = Empresa(nombre="Empresa B", rut_empresa="77.000.000-2",
                    email_contacto="b@b.cl", plan=EmpresaPlan.BASIC)
    db.add_all([emp_a, emp_b]); db.flush()

    admin = Usuario(firebase_uid="t-admin", nombre_completo="Admin", email="admin@a.cl")
    coord = Usuario(firebase_uid="t-coord", nombre_completo="Coord", email="coord@a.cl")
    resid = Usuario(firebase_uid="t-resid", nombre_completo="Resid", email="resid@a.cl")
    trab = Usuario(firebase_uid="t-trab", nombre_completo="Trab", email="trab@a.cl")
    # Usuario de la Empresa B (para tests de aislamiento).
    admin_b = Usuario(firebase_uid="t-admin-b", nombre_completo="AdminB", email="admin@b.cl")
    db.add_all([admin, coord, resid, trab, admin_b]); db.flush()

    db.add_all([
        EmpresaUsuario(empresa_id=emp_a.id, usuario_id=admin.id, rol=Rol.ADMIN),
        EmpresaUsuario(empresa_id=emp_a.id, usuario_id=coord.id, rol=Rol.COORDINADOR),
        EmpresaUsuario(empresa_id=emp_a.id, usuario_id=resid.id, rol=Rol.RESIDENTE),
        EmpresaUsuario(empresa_id=emp_a.id, usuario_id=trab.id, rol=Rol.TRABAJADOR),
        EmpresaUsuario(empresa_id=emp_b.id, usuario_id=admin_b.id, rol=Rol.ADMIN),
    ])

    proyecto = Proyecto(empresa_id=emp_a.id, nombre="Obra A",
                        coordinador_principal_id=coord.id, created_by=coord.id)
    db.add(proyecto); db.flush()
    db.add(ProyectoUsuario(proyecto_id=proyecto.id, usuario_id=resid.id,
                           rol_en_proyecto=Rol.RESIDENTE))

    item = Item(proyecto_id=proyecto.id, nivel_profundidad=0, nombre="Tarea raíz",
                asignado_a=trab.id, estado=ItemEstado.ABIERTO, created_by=coord.id)
    db.add(item); db.flush()

    # Exponer ids.
    d.emp_a, d.emp_b = emp_a.id, emp_b.id
    d.admin, d.coord, d.resid, d.trab, d.admin_b = (
        admin.firebase_uid, coord.firebase_uid, resid.firebase_uid,
        trab.firebase_uid, admin_b.firebase_uid,
    )
    d.proyecto = proyecto.id
    d.item = item.id
    # Ids internos (los endpoints de asignación trabajan con el id interno,
    # no con el firebase_uid).
    d.admin_id, d.coord_id, d.resid_id, d.trab_id, d.admin_b_id = (
        admin.id, coord.id, resid.id, trab.id, admin_b.id,
    )
    db.commit()

    def headers(uid: str, empresa_id: str | None = None) -> dict:
        h = {"Authorization": f"Bearer {uid}"}
        if empresa_id:
            h["X-Empresa-Id"] = empresa_id
        return h

    d.headers = headers
    return d
