"""test_supervisores.py — _supervisores_del_proyecto excluye residentes INACTIVOS.

Cubre CTT-44 capa 2: la función de notificación a supervisores debe respetar
el campo estado de proyecto_usuarios (solo ACTIVO recibe notificaciones).
"""

import pytest

from app.enums import EmpresaPlan, Rol, UsuarioEstado
from app.models import Empresa, Proyecto, ProyectoUsuario, Usuario
from app.routers.items import _supervisores_del_proyecto


@pytest.fixture()
def datos_supervisores(db):
    """Proyecto con 1 residente ACTIVO, 1 INACTIVO y 1 coordinador principal."""
    emp = Empresa(nombre="Emp Supervisores", rut_empresa="76.555.555-5",
                  email_contacto="sv@t.cl", plan=EmpresaPlan.PRO)
    db.add(emp)
    db.flush()

    coord = Usuario(firebase_uid="sv-coord", nombre_completo="Coord SV",
                    email="coord@sv.cl")
    resid_activo = Usuario(firebase_uid="sv-resid-activo",
                           nombre_completo="Resid Activo",
                           email="activo@sv.cl")
    resid_inactivo = Usuario(firebase_uid="sv-resid-inactivo",
                             nombre_completo="Resid Inactivo",
                             email="inactivo@sv.cl")
    db.add_all([coord, resid_activo, resid_inactivo])
    db.flush()

    proyecto = Proyecto(empresa_id=emp.id, nombre="Obra SV",
                        coordinador_principal_id=coord.id,
                        created_by=coord.id)
    db.add(proyecto)
    db.flush()

    db.add_all([
        ProyectoUsuario(proyecto_id=proyecto.id, usuario_id=resid_activo.id,
                        rol_en_proyecto=Rol.RESIDENTE,
                        estado=UsuarioEstado.ACTIVO),
        ProyectoUsuario(proyecto_id=proyecto.id, usuario_id=resid_inactivo.id,
                        rol_en_proyecto=Rol.RESIDENTE,
                        estado=UsuarioEstado.INACTIVO),
    ])
    db.commit()

    return {
        "db": db,
        "proyecto": proyecto,
        "coord_id": coord.id,
        "resid_activo_id": resid_activo.id,
        "resid_inactivo_id": resid_inactivo.id,
    }


def test_supervisores_excluye_residente_inactivo(datos_supervisores):
    """Residente INACTIVO NO debe aparecer entre los supervisores notificados."""
    d = datos_supervisores
    resultado = _supervisores_del_proyecto(d["db"], d["proyecto"])
    ids = {u.id for u in resultado}
    assert d["resid_inactivo_id"] not in ids


def test_supervisores_incluye_residente_activo(datos_supervisores):
    """Residente ACTIVO sí debe aparecer entre los supervisores notificados."""
    d = datos_supervisores
    resultado = _supervisores_del_proyecto(d["db"], d["proyecto"])
    ids = {u.id for u in resultado}
    assert d["resid_activo_id"] in ids


def test_supervisores_incluye_coordinador_principal(datos_supervisores):
    """coordinador_principal_id siempre aparece, independiente de estado."""
    d = datos_supervisores
    resultado = _supervisores_del_proyecto(d["db"], d["proyecto"])
    ids = {u.id for u in resultado}
    assert d["coord_id"] in ids
