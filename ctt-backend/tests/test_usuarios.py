"""
test_usuarios.py — CTT-46/CTT-57: filtro ?rol= en GET /usuarios
y validación 422 al asignar ítems a rol distinto de trabajador.
"""


def _h(seeded, uid=None, empresa_id=None):
    return seeded.headers(uid or seeded.coord, empresa_id or seeded.emp_a)


# ── GET /usuarios — sin filtro → todos los usuarios activos ──────────────────

def test_sin_filtro_devuelve_todos(client, seeded):
    r = client.get("/usuarios", headers=_h(seeded))
    assert r.status_code == 200, r.text
    roles = {u["rol"] for u in r.json()}
    assert roles == {"admin", "coordinador", "residente", "trabajador"}


def test_usuario_out_incluye_campo_rol(client, seeded):
    r = client.get("/usuarios", headers=_h(seeded))
    assert r.status_code == 200, r.text
    for u in r.json():
        assert "rol" in u
        assert u["rol"] in {"admin", "coordinador", "residente", "trabajador"}


# ── GET /usuarios — filtro por rol único ─────────────────────────────────────

def test_filtro_trabajador_solo_devuelve_trabajadores(client, seeded):
    r = client.get("/usuarios", params={"rol": "trabajador"}, headers=_h(seeded))
    assert r.status_code == 200, r.text
    data = r.json()
    assert len(data) >= 1
    assert all(u["rol"] == "trabajador" for u in data)


def test_filtro_coordinador_solo_devuelve_coordinadores(client, seeded):
    r = client.get("/usuarios", params={"rol": "coordinador"}, headers=_h(seeded))
    assert r.status_code == 200, r.text
    data = r.json()
    assert len(data) >= 1
    assert all(u["rol"] == "coordinador" for u in data)


def test_filtro_residente_solo_devuelve_residentes(client, seeded):
    r = client.get("/usuarios", params={"rol": "residente"}, headers=_h(seeded))
    assert r.status_code == 200, r.text
    data = r.json()
    assert len(data) >= 1
    assert all(u["rol"] == "residente" for u in data)


# ── GET /usuarios — filtro multi-rol (parámetro repetido) ────────────────────

def test_filtro_coordinador_y_admin(client, seeded):
    r = client.get(
        "/usuarios",
        params=[("rol", "coordinador"), ("rol", "admin")],
        headers=_h(seeded),
    )
    assert r.status_code == 200, r.text
    roles = {u["rol"] for u in r.json()}
    assert roles <= {"coordinador", "admin"}
    assert "trabajador" not in roles
    assert "residente" not in roles


# ── GET /usuarios — rol inválido → 422 ───────────────────────────────────────

def test_rol_invalido_422(client, seeded):
    r = client.get("/usuarios", params={"rol": "superheroe"}, headers=_h(seeded))
    assert r.status_code == 422, r.text


# ── Multi-tenant: GET /usuarios solo devuelve usuarios de la empresa del ctx ──

def test_multitenant_aislamiento(client, seeded):
    """admin_b desde emp_b NO ve usuarios de emp_a."""
    r = client.get("/usuarios", headers=_h(seeded, uid=seeded.admin_b, empresa_id=seeded.emp_b))
    assert r.status_code == 200, r.text
    ids = {u["id"] for u in r.json()}
    assert seeded.coord_id not in ids
    assert seeded.trab_id not in ids


def test_multitenant_mismo_usuario_rol_por_empresa(client, seeded, db):
    """Un usuario con rol distinto en cada empresa aparece con el rol correcto en cada contexto."""
    from app.enums import Rol
    from app.models import EmpresaUsuario, Usuario

    u = Usuario(firebase_uid="u-dual-rol", nombre_completo="Dual", email="dual@ctt.cl")
    db.add(u)
    db.flush()
    db.add(EmpresaUsuario(empresa_id=seeded.emp_a, usuario_id=u.id, rol=Rol.COORDINADOR))
    db.add(EmpresaUsuario(empresa_id=seeded.emp_b, usuario_id=u.id, rol=Rol.TRABAJADOR))
    db.commit()

    # En emp_a aparece como coordinador
    r_a = client.get("/usuarios", params={"rol": "coordinador"}, headers=_h(seeded))
    assert r_a.status_code == 200, r_a.text
    assert any(x["id"] == u.id for x in r_a.json())

    # En emp_a NO aparece como trabajador
    r_a2 = client.get("/usuarios", params={"rol": "trabajador"}, headers=_h(seeded))
    assert r_a2.status_code == 200, r_a2.text
    assert not any(x["id"] == u.id for x in r_a2.json())

    # En emp_b aparece como trabajador
    r_b = client.get(
        "/usuarios",
        params={"rol": "trabajador"},
        headers=_h(seeded, uid=seeded.admin_b, empresa_id=seeded.emp_b),
    )
    assert r_b.status_code == 200, r_b.text
    assert any(x["id"] == u.id for x in r_b.json())


# ── POST /items — validación de rol del asignatario ──────────────────────────

def test_crear_item_asignatario_trabajador_ok(client, seeded):
    r = client.post(
        "/items",
        json={
            "proyecto_id": seeded.proyecto,
            "nombre": "Ítem con asignación válida",
            "asignado_a": seeded.trab_id,
        },
        headers=_h(seeded),
    )
    assert r.status_code == 201, r.text
    assert r.json()["asignado_a"] == seeded.trab_id


def test_crear_item_asignatario_residente_422(client, seeded):
    """Asignar a un Residente devuelve 422 — solo trabajadores ejecutan partidas."""
    r = client.post(
        "/items",
        json={
            "proyecto_id": seeded.proyecto,
            "nombre": "Ítem inválido",
            "asignado_a": seeded.resid_id,
        },
        headers=_h(seeded),
    )
    assert r.status_code == 422, r.text


def test_crear_item_asignatario_coordinador_422(client, seeded):
    r = client.post(
        "/items",
        json={
            "proyecto_id": seeded.proyecto,
            "nombre": "Ítem inválido coord",
            "asignado_a": seeded.coord_id,
        },
        headers=_h(seeded),
    )
    assert r.status_code == 422, r.text


def test_crear_item_sin_asignacion_ok(client, seeded):
    r = client.post(
        "/items",
        json={"proyecto_id": seeded.proyecto, "nombre": "Ítem sin asignar"},
        headers=_h(seeded),
    )
    assert r.status_code == 201, r.text
    assert r.json()["asignado_a"] is None


# ── POST /items/{id}/asignar — validación de rol del asignatario ──────────────

def test_asignar_trabajador_ok(client, seeded):
    r = client.post(
        f"/items/{seeded.item}/asignar",
        json={"usuario_id": seeded.trab_id},
        headers=_h(seeded),
    )
    assert r.status_code == 200, r.text
    assert r.json()["asignado_a"] == seeded.trab_id


def test_asignar_residente_422(client, seeded):
    """POST /asignar con Residente devuelve 422."""
    r = client.post(
        f"/items/{seeded.item}/asignar",
        json={"usuario_id": seeded.resid_id},
        headers=_h(seeded),
    )
    assert r.status_code == 422, r.text


def test_asignar_coordinador_422(client, seeded):
    r = client.post(
        f"/items/{seeded.item}/asignar",
        json={"usuario_id": seeded.coord_id},
        headers=_h(seeded),
    )
    assert r.status_code == 422, r.text


def test_asignar_usuario_otra_empresa_404(client, seeded):
    """Asignar a un usuario de otra empresa devuelve 404."""
    r = client.post(
        f"/items/{seeded.item}/asignar",
        json={"usuario_id": seeded.admin_b_id},
        headers=_h(seeded),
    )
    assert r.status_code == 404, r.text
