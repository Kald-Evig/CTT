"""
test_mis_items.py — Tests de GET /items/mis-items.

Cubre: ítems propios, sin ítems, aislamiento multi-tenant,
items no asignados al usuario e inclusión de proyecto_nombre.
"""

import pytest

from app.database import Base, SessionLocal, engine
from app.enums import EmpresaPlan, ItemEstado, Rol
from app.main import app
from app.models import Empresa, EmpresaUsuario, Item, Proyecto, Usuario
from fastapi.testclient import TestClient


def _reset():
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)


@pytest.fixture()
def client():
    return TestClient(app)


@pytest.fixture()
def db_limpia():
    _reset()
    s = SessionLocal()
    try:
        yield s
    finally:
        s.close()


def _headers(uid: str, empresa_id: str | None = None) -> dict:
    h = {"Authorization": f"Bearer {uid}"}
    if empresa_id:
        h["X-Empresa-Id"] = empresa_id
    return h


def _empresa_usuario_proyecto(db):
    """Crea empresa, trabajador y proyecto base. Devuelve (empresa, trab, proyecto)."""
    emp = Empresa(nombre="Constructora Test", rut_empresa="76.500.001-1",
                  email_contacto="test@c.cl", plan=EmpresaPlan.PRO)
    db.add(emp); db.flush()

    trab = Usuario(firebase_uid="uid-trab-mi", nombre_completo="Carlos Trab",
                   email="trab@c.cl")
    db.add(trab); db.flush()

    db.add(EmpresaUsuario(empresa_id=emp.id, usuario_id=trab.id, rol=Rol.TRABAJADOR))

    proy = Proyecto(empresa_id=emp.id, nombre="Obra Central",
                    created_by=trab.id)
    db.add(proy); db.flush()
    return emp, trab, proy


# ── Caso 1: trabajador con ítems asignados ────────────────────────────────────
def test_mis_items_retorna_items_asignados(client, db_limpia):
    emp, trab, proy = _empresa_usuario_proyecto(db_limpia)

    item1 = Item(proyecto_id=proy.id, nombre="Tarea A", nivel_profundidad=0,
                 asignado_a=trab.id, estado=ItemEstado.ABIERTO, orden=1)
    item2 = Item(proyecto_id=proy.id, nombre="Tarea B", nivel_profundidad=0,
                 asignado_a=trab.id, estado=ItemEstado.EN_PROGRESO, orden=2)
    db_limpia.add_all([item1, item2])
    db_limpia.commit()

    r = client.get("/items/mis-items", headers=_headers("uid-trab-mi"))
    assert r.status_code == 200
    data = r.json()
    assert len(data) == 2
    nombres = {i["nombre"] for i in data}
    assert nombres == {"Tarea A", "Tarea B"}


# ── Caso 2: proyecto_nombre incluido en la respuesta ─────────────────────────
def test_mis_items_incluye_nombre_proyecto(client, db_limpia):
    emp, trab, proy = _empresa_usuario_proyecto(db_limpia)

    db_limpia.add(Item(proyecto_id=proy.id, nombre="Tarea X", nivel_profundidad=0,
                       asignado_a=trab.id, estado=ItemEstado.ABIERTO))
    db_limpia.commit()

    r = client.get("/items/mis-items", headers=_headers("uid-trab-mi"))
    assert r.status_code == 200
    assert r.json()[0]["proyecto_nombre"] == "Obra Central"


# ── Caso 3: sin ítems asignados → lista vacía ────────────────────────────────
def test_mis_items_sin_items_asignados(client, db_limpia):
    emp, trab, proy = _empresa_usuario_proyecto(db_limpia)

    # Ítem existe pero asignado a otro usuario
    otro = Usuario(firebase_uid="uid-otro-mi", nombre_completo="Otro",
                   email="otro@c.cl")
    db_limpia.add(otro); db_limpia.flush()
    db_limpia.add(Item(proyecto_id=proy.id, nombre="Tarea Ajena",
                       nivel_profundidad=0, asignado_a=otro.id,
                       estado=ItemEstado.ABIERTO))
    db_limpia.commit()

    r = client.get("/items/mis-items", headers=_headers("uid-trab-mi"))
    assert r.status_code == 200
    assert r.json() == []


# ── Caso 4: aislamiento — no muestra ítems de otra empresa ───────────────────
def test_mis_items_aislamiento_empresa(client, db_limpia):
    emp, trab, proy = _empresa_usuario_proyecto(db_limpia)

    # Segunda empresa con su propio proyecto e ítem, pero misma persona
    emp_b = Empresa(nombre="Empresa B", rut_empresa="76.500.002-2",
                    email_contacto="b@b.cl", plan=EmpresaPlan.BASIC)
    db_limpia.add(emp_b); db_limpia.flush()
    db_limpia.add(EmpresaUsuario(empresa_id=emp_b.id, usuario_id=trab.id,
                                 rol=Rol.TRABAJADOR))
    proy_b = Proyecto(empresa_id=emp_b.id, nombre="Obra B", created_by=trab.id)
    db_limpia.add(proy_b); db_limpia.flush()
    db_limpia.add(Item(proyecto_id=proy_b.id, nombre="Tarea Empresa B",
                       nivel_profundidad=0, asignado_a=trab.id,
                       estado=ItemEstado.ABIERTO))

    # Ítem en empresa A
    db_limpia.add(Item(proyecto_id=proy.id, nombre="Tarea Empresa A",
                       nivel_profundidad=0, asignado_a=trab.id,
                       estado=ItemEstado.ABIERTO))
    db_limpia.commit()

    # Con empresa A activa solo ve la tarea de A
    r = client.get("/items/mis-items",
                   headers=_headers("uid-trab-mi", empresa_id=emp.id))
    assert r.status_code == 200
    nombres = [i["nombre"] for i in r.json()]
    assert "Tarea Empresa A" in nombres
    assert "Tarea Empresa B" not in nombres


# ── Caso 5: ítems de todos los estados aparecen ──────────────────────────────
def test_mis_items_incluye_todos_los_estados(client, db_limpia):
    emp, trab, proy = _empresa_usuario_proyecto(db_limpia)

    for estado in (ItemEstado.ABIERTO, ItemEstado.EN_PROGRESO,
                   ItemEstado.PENDIENTE_REVISION, ItemEstado.TERMINADO):
        db_limpia.add(Item(proyecto_id=proy.id, nombre=f"Tarea {estado.value}",
                           nivel_profundidad=0, asignado_a=trab.id, estado=estado))
    db_limpia.commit()

    r = client.get("/items/mis-items", headers=_headers("uid-trab-mi"))
    assert r.status_code == 200
    assert len(r.json()) == 4
