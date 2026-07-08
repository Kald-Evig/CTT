"""
test_get_proyecto.py — Tests para CTT-61: GET /proyectos/{id}.
"""

from app.models import Proyecto


def _h(seeded, uid):
    return seeded.headers(uid, seeded.emp_a)


def test_get_proyecto_devuelve_todos_los_campos(client, seeded, db):
    """GET devuelve ProyectoOut completo incluyendo los campos que el dashboard omite."""
    proyecto = Proyecto(
        empresa_id=seeded.emp_a,
        nombre="Obra Completa",
        descripcion="Descripción de prueba",
        ubicacion_nombre="Santiago Centro",
        coordinador_principal_id=seeded.coord_id,
        created_by=seeded.coord_id,
    )
    db.add(proyecto)
    db.commit()

    r = client.get(f"/proyectos/{proyecto.id}", headers=_h(seeded, seeded.coord))
    assert r.status_code == 200, r.text
    data = r.json()

    assert data["id"] == proyecto.id
    assert data["nombre"] == "Obra Completa"
    assert data["descripcion"] == "Descripción de prueba"
    assert data["ubicacion_nombre"] == "Santiago Centro"
    assert data["coordinador_principal_id"] == seeded.coord_id
    assert data["empresa_id"] == seeded.emp_a


def test_get_proyecto_empresa_ajena_es_404(client, seeded, db):
    """Multi-tenant: proyecto de empresa B devuelve 404 para usuario de empresa A."""
    proyecto_b = Proyecto(
        empresa_id=seeded.emp_b,
        nombre="Obra B secreta",
        created_by=seeded.admin_b_id,
    )
    db.add(proyecto_b)
    db.commit()

    r = client.get(f"/proyectos/{proyecto_b.id}", headers=_h(seeded, seeded.coord))
    assert r.status_code == 404, r.text
