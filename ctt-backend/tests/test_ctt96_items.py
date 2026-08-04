"""
test_ctt96_items.py — Autorización resource-scoped en endpoints de ítem (CTT-96).

Verifica require_item_access para todos los roles (ramas a/b/c del trabajador incluidas)
y el invariante anti-leak: acceso de asignatario no expone ítems hermanos ni el proyecto.
"""
import pytest

from app.enums import ItemEstado, Rol
from app.models import EmpresaUsuario, Item, Proyecto, ProyectoUsuario, Usuario


# ── Acceso correcto por rol ───────────────────────────────────────────────────

def test_admin_puede_ver_item(client, seeded):
    r = client.get(f"/items/{seeded.item}", headers=seeded.headers(seeded.admin))
    assert r.status_code == 200


def test_coordinador_principal_puede_ver_item(client, seeded):
    r = client.get(f"/items/{seeded.item}", headers=seeded.headers(seeded.coord))
    assert r.status_code == 200


def test_residente_miembro_puede_ver_item(client, seeded):
    r = client.get(f"/items/{seeded.item}", headers=seeded.headers(seeded.resid))
    assert r.status_code == 200


def test_trabajador_asignado_puede_ver_item(client, seeded):
    # seeded.trab está asignado a seeded.item (rama a) — sin membresía en el proyecto.
    r = client.get(f"/items/{seeded.item}", headers=seeded.headers(seeded.trab))
    assert r.status_code == 200


# ── Denegaciones por rol ──────────────────────────────────────────────────────

def test_trabajador_miembro_no_asignado_recibe_403(client, seeded, db):
    # Añadir membresía para seeded.trab (rama b: miembro pero no asignado al nuevo ítem).
    db.add(ProyectoUsuario(
        proyecto_id=seeded.proyecto,
        usuario_id=seeded.trab_id,
        rol_en_proyecto=Rol.TRABAJADOR,
    ))
    otro_item = Item(
        proyecto_id=seeded.proyecto,
        nivel_profundidad=0,
        nombre="Ítem ajeno",
        asignado_a=None,  # sin asignar: rama (b) = miembro activo pero no asignado a este ítem
        estado=ItemEstado.ABIERTO,
        created_by=seeded.coord_id,
    )
    db.add(otro_item)
    db.commit()

    r = client.get(f"/items/{otro_item.id}", headers=seeded.headers(seeded.trab))
    assert r.status_code == 403, r.text


def test_trabajador_sin_relacion_recibe_404(client, seeded):
    # Ítem no asignado a trab y trab sin membresía → 404 (OWASP A01, IDOR prevention).
    otro_item_id = client.post(
        "/items",
        json={"proyecto_id": seeded.proyecto, "nombre": "Sin asignar"},
        headers=seeded.headers(seeded.coord),
    ).json()["id"]

    r = client.get(f"/items/{otro_item_id}", headers=seeded.headers(seeded.trab))
    assert r.status_code == 404


def test_residente_sin_membresia_recibe_404(client, seeded, db):
    resid2 = Usuario(firebase_uid="t-resid2", nombre_completo="Resid2", email="resid2@a.cl")
    db.add(resid2)
    db.flush()
    db.add(EmpresaUsuario(empresa_id=seeded.emp_a, usuario_id=resid2.id, rol=Rol.RESIDENTE))
    db.commit()

    r = client.get(f"/items/{seeded.item}", headers=seeded.headers(resid2.firebase_uid))
    assert r.status_code == 404


def test_coordinador_no_principal_recibe_404(client, seeded, db):
    coord2 = Usuario(firebase_uid="t-coord2", nombre_completo="Coord2", email="coord2@a.cl")
    db.add(coord2)
    db.flush()
    db.add(EmpresaUsuario(empresa_id=seeded.emp_a, usuario_id=coord2.id, rol=Rol.COORDINADOR))
    db.commit()

    r = client.get(f"/items/{seeded.item}", headers=seeded.headers(coord2.firebase_uid))
    assert r.status_code == 404


def test_empresa_b_recibe_404(client, seeded):
    # admin_b pertenece a empresa B — ítem es de empresa A → tenant aísla.
    r = client.get(f"/items/{seeded.item}", headers=seeded.headers(seeded.admin_b))
    assert r.status_code == 404


# ── Membresía del asignatario (CTT-96) — ambos caminos de asignación ──────────

def test_asignar_trabajador_no_miembro_da_409(client, seeded):
    """POST /asignar a un trabajador que NO es miembro del proyecto → 409."""
    # seeded.trab es TRABAJADOR de empresa A pero NO miembro de seeded.proyecto.
    r = client.post(
        f"/items/{seeded.item}/asignar",
        json={"usuario_id": seeded.trab_id},
        headers=seeded.headers(seeded.coord),
    )
    assert r.status_code == 409, r.text


def test_crear_item_asignatario_no_miembro_da_409(client, seeded):
    """crear_item con asignado_a no-miembro → 409 (misma regla, sin puerta trasera)."""
    r = client.post(
        "/items",
        json={"proyecto_id": seeded.proyecto, "nombre": "X", "asignado_a": seeded.trab_id},
        headers=seeded.headers(seeded.coord),
    )
    assert r.status_code == 409, r.text


# ── crear_item: autorización resource-scoped por body.proyecto_id (CTT-96) ─────

def test_coordinador_no_principal_no_crea_item(client, seeded, db):
    """Coordinador que NO es coordinador_principal del proyecto → 404 al crear ítem."""
    coord2 = Usuario(firebase_uid="t-coord2c", nombre_completo="Coord2c", email="coord2c@a.cl")
    db.add(coord2)
    db.flush()
    db.add(EmpresaUsuario(empresa_id=seeded.emp_a, usuario_id=coord2.id, rol=Rol.COORDINADOR))
    db.commit()

    r = client.post(
        "/items",
        json={"proyecto_id": seeded.proyecto, "nombre": "Intruso"},
        headers=seeded.headers(coord2.firebase_uid),
    )
    assert r.status_code == 404, r.text


def test_crear_item_parent_de_otro_proyecto_da_404(client, seeded, db):
    """parent_item_id de un ítem de otro proyecto → 404 idéntico al de un padre inexistente.

    Evita el oráculo de existencia: 'existe en otro proyecto' y 'no existe' deben ser
    respuestas indistinguibles (OWASP A01).
    """
    otro_proy = Proyecto(empresa_id=seeded.emp_a, nombre="Otro Proy",
                         created_by=seeded.admin_id)
    db.add(otro_proy)
    db.flush()
    item_otro = Item(proyecto_id=otro_proy.id, nivel_profundidad=0, nombre="Padre ajeno",
                     estado=ItemEstado.ABIERTO, created_by=seeded.admin_id)
    db.add(item_otro)
    db.commit()

    h_coord = seeded.headers(seeded.coord)  # coord es principal de seeded.proyecto
    r_ajeno = client.post(
        "/items",
        json={"proyecto_id": seeded.proyecto, "nombre": "Hijo", "parent_item_id": item_otro.id},
        headers=h_coord,
    )
    r_inventado = client.post(
        "/items",
        json={"proyecto_id": seeded.proyecto, "nombre": "Hijo",
              "parent_item_id": "id-inexistente"},
        headers=h_coord,
    )
    assert r_ajeno.status_code == 404, r_ajeno.text
    assert r_inventado.status_code == 404, r_inventado.text
    # Indistinguibles: mismo código y mismo cuerpo.
    assert r_ajeno.json() == r_inventado.json()


# ── Anti-leak: acceso de asignatario no expone ítems hermanos ni el proyecto ──

def test_asignatario_no_ve_items_hermanos(client, seeded):
    """Acceso de trab a su ítem NO debe permitir ver ítems del mismo proyecto."""
    h_trab = seeded.headers(seeded.trab)
    h_coord = seeded.headers(seeded.coord)

    hermano_id = client.post(
        "/items",
        json={"proyecto_id": seeded.proyecto, "nombre": "Hermano"},
        headers=h_coord,
    ).json()["id"]

    # trab puede ver su ítem asignado.
    assert client.get(f"/items/{seeded.item}", headers=h_trab).status_code == 200
    # trab NO puede ver el hermano (no asignado, no miembro → 404).
    assert client.get(f"/items/{hermano_id}", headers=h_trab).status_code == 404


def test_asignatario_lista_solo_sus_items_del_proyecto(client, seeded):
    """GET /items?proyecto_id=X: el trabajador ve solo sus ítems asignados, no los hermanos."""
    h_coord = seeded.headers(seeded.coord)
    # Ítem hermano no asignado a trab, en el mismo proyecto.
    hermano_id = client.post(
        "/items",
        json={"proyecto_id": seeded.proyecto, "nombre": "Hermano"},
        headers=h_coord,
    ).json()["id"]

    r = client.get(
        f"/items?proyecto_id={seeded.proyecto}",
        headers=seeded.headers(seeded.trab),
    )
    assert r.status_code == 200, r.text
    ids = {it["id"] for it in r.json()}
    assert seeded.item in ids       # su ítem asignado
    assert hermano_id not in ids    # no ve el hermano


def test_coordinador_no_principal_no_lista_items(client, seeded, db):
    """GET /items?proyecto_id=X para coordinador NO principal de la MISMA empresa → 404.

    Es guard, no filtro: la puerta lateral del listado responde 404 igual que la
    factory de detalle (no lista vacía, que sería un oráculo de existencia del proyecto).
    """
    coord2 = Usuario(firebase_uid="t-coord2-list", nombre_completo="Coord2 List",
                     email="coord2list@a.cl")
    db.add(coord2)
    db.flush()
    db.add(EmpresaUsuario(empresa_id=seeded.emp_a, usuario_id=coord2.id, rol=Rol.COORDINADOR))
    db.commit()

    r = client.get(f"/items?proyecto_id={seeded.proyecto}",
                   headers=seeded.headers(coord2.firebase_uid))
    assert r.status_code == 404, r.text


def test_trabajador_miembro_lista_solo_sus_asignados(client, seeded, db):
    """GET /items?proyecto_id=X para TRABAJADOR miembro activo Y con asignación:
    200, ve su ítem asignado, NO ve los hermanos, NO ve sus asignados de OTRO proyecto.

    El tercer caso (asignado en otro proyecto de la misma empresa) distingue el filtro
    real (proyecto_id + empresa_id + asignado_a) de uno que ignore proyecto_id y devuelva
    todos los asignados del tenant.
    """
    # Membresía activa en el proyecto (seeded.trab ya está asignado a seeded.item).
    db.add(ProyectoUsuario(
        proyecto_id=seeded.proyecto,
        usuario_id=seeded.trab_id,
        rol_en_proyecto=Rol.TRABAJADOR,
    ))
    # Otro proyecto de la MISMA empresa, con un ítem asignado a trab.
    otro_proy = Proyecto(empresa_id=seeded.emp_a, nombre="Obra A2",
                         coordinador_principal_id=seeded.coord_id, created_by=seeded.coord_id)
    db.add(otro_proy)
    db.flush()
    item_otro_proy = Item(proyecto_id=otro_proy.id, nivel_profundidad=0,
                          nombre="Asignado en otro proyecto", asignado_a=seeded.trab_id,
                          estado=ItemEstado.ABIERTO, created_by=seeded.coord_id)
    db.add(item_otro_proy)
    db.commit()

    # Hermano en el mismo proyecto, no asignado a trab.
    hermano_id = client.post(
        "/items",
        json={"proyecto_id": seeded.proyecto, "nombre": "Hermano"},
        headers=seeded.headers(seeded.coord),
    ).json()["id"]

    r = client.get(f"/items?proyecto_id={seeded.proyecto}",
                   headers=seeded.headers(seeded.trab))
    assert r.status_code == 200, r.text
    ids = {it["id"] for it in r.json()}
    assert seeded.item in ids               # su ítem asignado en este proyecto
    assert hermano_id not in ids            # membresía no le abre los hermanos
    assert item_otro_proy.id not in ids     # proyecto_id filtra: su asignado de OTRO proyecto no aparece


def test_trabajador_no_ve_items_de_otra_empresa(client, seeded, db):
    """GET /items con proyecto_id de empresa B y X-Empresa-Id de A → 200 vacío (filtro tenant)."""
    # trab también es TRABAJADOR en empresa B, con un ítem asignado allí.
    db.add(EmpresaUsuario(empresa_id=seeded.emp_b, usuario_id=seeded.trab_id, rol=Rol.TRABAJADOR))
    proy_b = Proyecto(empresa_id=seeded.emp_b, nombre="Obra B", created_by=seeded.admin_b_id)
    db.add(proy_b)
    db.flush()
    item_b = Item(proyecto_id=proy_b.id, nivel_profundidad=0, nombre="Ítem B",
                  asignado_a=seeded.trab_id, estado=ItemEstado.ABIERTO,
                  created_by=seeded.admin_b_id)
    db.add(item_b)
    db.commit()

    # Con X-Empresa-Id de A, pidiendo el proyecto de B: el ítem de B queda fuera por tenant.
    r = client.get(f"/items?proyecto_id={proy_b.id}",
                   headers=seeded.headers(seeded.trab, seeded.emp_a))
    assert r.status_code == 200, r.text
    assert r.json() == []


def test_asignatario_no_puede_ver_el_proyecto(client, seeded):
    """GET /proyectos/{id} para trab sin membresía → 404."""
    r = client.get(f"/proyectos/{seeded.proyecto}", headers=seeded.headers(seeded.trab))
    assert r.status_code == 404


# ── Parametrized: factory aplica en los 4 sub-endpoints GET de ítem ──────────

@pytest.mark.parametrize("url_tpl", [
    "/items/{id}",
    "/items/{id}/comentarios",
    "/items/{id}/evidencias",
    "/items/{id}/historial",
])
def test_empresa_b_recibe_404_en_endpoints_get(client, seeded, url_tpl):
    """Actor de empresa B no puede acceder a ítems de empresa A (tenant isolation)."""
    url = url_tpl.format(id=seeded.item)
    r = client.get(url, headers=seeded.headers(seeded.admin_b))
    assert r.status_code == 404


# ── Trabajador sin relación: sub-endpoints GET de ítem → 404 (IDOR intra-empresa) ──

@pytest.mark.parametrize("sub", ["comentarios", "evidencias", "historial"])
def test_trabajador_sin_relacion_recibe_404_en_subendpoints(client, seeded, sub):
    """Trabajador sin membresía y sin asignación → 404 en comentarios/evidencias/historial.

    No se reutiliza seeded.item: seeded.trab es su asignatario y daría 200. Se crea un
    ítem sin asignar del que trab no es miembro ni asignatario → 404 (OWASP A01, IDOR).
    Distinto del parametrize de arriba, cuyo actor es admin_b (aislamiento cross-tenant).
    """
    otro_item_id = client.post(
        "/items",
        json={"proyecto_id": seeded.proyecto, "nombre": "Sin asignar sub"},
        headers=seeded.headers(seeded.coord),
    ).json()["id"]

    r = client.get(f"/items/{otro_item_id}/{sub}", headers=seeded.headers(seeded.trab))
    assert r.status_code == 404, r.text
