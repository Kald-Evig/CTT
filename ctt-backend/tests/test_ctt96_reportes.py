"""
test_ctt96_reportes.py — Autorización resource-scoped en endpoints de reportes (CTT-96).

Verifica que los 4 endpoints de reportes respeten el alcance de proyecto:
  - GET /reportes/avance/{proyecto_id}
  - GET /reportes/retrasos/{proyecto_id}
  - GET /reportes/problemas/{proyecto_id}
  - GET /reportes/actividad/{proyecto_id}

Regla: Coordinador ajeno al proyecto recibe 404 (no 200 ni 403).
"""

import pytest

from app.enums import EmpresaPlan, Rol
from app.models import Empresa, EmpresaUsuario, Proyecto, Usuario


ENDPOINTS = [
    "/reportes/avance/{pid}",
    "/reportes/retrasos/{pid}",
    "/reportes/problemas/{pid}",
    "/reportes/actividad/{pid}",
]


@pytest.fixture()
def d96r(db):
    """
    Empresa con 3 actores; un proyecto.

    empresa:
      admin    — ADMIN
      coord_p  — COORDINADOR, coordinador_principal del proyecto
      coord_o  — COORDINADOR, ajeno al proyecto (no es principal ni miembro)

    proyecto: coordinador_principal_id = coord_p.id
    """
    emp = Empresa(nombre="Emp96R", rut_empresa="76.996.996-6",
                  email_contacto="r@96.cl", plan=EmpresaPlan.PRO)
    db.add(emp)
    db.flush()

    admin   = Usuario(firebase_uid="96r-admin",   nombre_completo="Admin 96R",
                      email="admin@96r.cl")
    coord_p = Usuario(firebase_uid="96r-coord-p", nombre_completo="Coord P 96R",
                      email="coord.p@96r.cl")
    coord_o = Usuario(firebase_uid="96r-coord-o", nombre_completo="Coord O 96R",
                      email="coord.o@96r.cl")
    db.add_all([admin, coord_p, coord_o])
    db.flush()

    db.add_all([
        EmpresaUsuario(empresa_id=emp.id, usuario_id=admin.id,   rol=Rol.ADMIN),
        EmpresaUsuario(empresa_id=emp.id, usuario_id=coord_p.id, rol=Rol.COORDINADOR),
        EmpresaUsuario(empresa_id=emp.id, usuario_id=coord_o.id, rol=Rol.COORDINADOR),
    ])

    proyecto = Proyecto(empresa_id=emp.id, nombre="Obra 96R",
                        coordinador_principal_id=coord_p.id,
                        created_by=coord_p.id)
    db.add(proyecto)
    db.commit()

    def h(uid: str) -> dict:
        return {"Authorization": f"Bearer {uid}", "X-Empresa-Id": emp.id}

    return {
        "pid": proyecto.id,
        "admin":   admin.firebase_uid,
        "coord_p": coord_p.firebase_uid,
        "coord_o": coord_o.firebase_uid,
        "h": h,
    }


@pytest.mark.parametrize("tpl", ENDPOINTS)
def test_reporte_admin_200(client, d96r, tpl):
    url = tpl.format(pid=d96r["pid"])
    r = client.get(url, headers=d96r["h"](d96r["admin"]))
    assert r.status_code == 200, r.text


@pytest.mark.parametrize("tpl", ENDPOINTS)
def test_reporte_coord_principal_200(client, d96r, tpl):
    url = tpl.format(pid=d96r["pid"])
    r = client.get(url, headers=d96r["h"](d96r["coord_p"]))
    assert r.status_code == 200, r.text


@pytest.mark.parametrize("tpl", ENDPOINTS)
def test_reporte_coord_ajeno_404(client, d96r, tpl):
    url = tpl.format(pid=d96r["pid"])
    r = client.get(url, headers=d96r["h"](d96r["coord_o"]))
    assert r.status_code == 404, r.text
