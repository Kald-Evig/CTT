"""
test_ctt97.py — GET /usuarios: gating por rol y minimización del padrón.

- Lectura del padrón gateada por la acción `ver_usuarios`: Trabajador → 403;
  Residente / Coordinador / Admin → 200.
- El LISTADO responde con UsuarioBaseOut y NO expone `rut`. La gestión del padrón
  (POST /usuarios) sí lo trae (UsuarioCreateOut). Ese par fija el contrato de
  minimización: el RUT viaja solo donde el Admin lo necesita para gestionar.
"""

import pytest

from app.routers import usuarios as usuarios_router


@pytest.mark.parametrize(
    "rol_attr, esperado",
    [
        ("trab", 403),   # Trabajador: su app no consume /usuarios
        ("resid", 200),
        ("coord", 200),
        ("admin", 200),
    ],
)
def test_ver_usuarios_gating_por_rol(client, seeded, rol_attr, esperado):
    uid = getattr(seeded, rol_attr)
    r = client.get("/usuarios", headers=seeded.headers(uid, seeded.emp_a))
    assert r.status_code == esperado, r.text


def test_listado_no_expone_rut(client, seeded):
    """GET /usuarios (UsuarioBaseOut) no debe incluir la clave `rut`."""
    r = client.get("/usuarios", headers=seeded.headers(seeded.admin, seeded.emp_a))
    assert r.status_code == 200, r.text
    data = r.json()
    assert len(data) >= 1
    for u in data:
        assert "rut" not in u, f"el listado no debe exponer rut: {u}"


class _FbUser:
    uid = "fb-uid-ctt97"


def test_post_usuarios_si_trae_rut(client, seeded, monkeypatch):
    """POST /usuarios (UsuarioCreateOut) SÍ trae `rut`: el Admin gestiona el padrón."""
    # Firebase Admin mockeado: reusar uid existente y devolver un reset link.
    monkeypatch.setattr(
        usuarios_router.fb_auth, "get_user_by_email", lambda email: _FbUser()
    )
    monkeypatch.setattr(
        usuarios_router.fb_auth,
        "generate_password_reset_link",
        lambda email: "https://reset.example/abc",
    )
    r = client.post(
        "/usuarios",
        headers=seeded.headers(seeded.admin, seeded.emp_a),
        json={
            "nombre_completo": "Nuevo Trabajador",
            "email": "nuevo.ctt97@a.cl",
            "rol": "trabajador",
            "rut": "12.345.678-5",
        },
    )
    assert r.status_code == 201, r.text
    body = r.json()
    assert "rut" in body
    assert body["rut"] == "12.345.678-5"


# ── incluir_inactivos gateado a administración (CTT-97, PASO 4) ────────────────
def _seed_trabajador_inactivo(db, seeded):
    """Agrega un trabajador con membresía INACTIVA en la empresa A. Devuelve su id."""
    from app.enums import Rol, UsuarioEstado
    from app.models import EmpresaUsuario, Usuario
    u = Usuario(firebase_uid="t-inactivo-ctt97", nombre_completo="Inactivo CTT97",
                email="inactivo.ctt97@a.cl")
    db.add(u)
    db.flush()
    db.add(EmpresaUsuario(empresa_id=seeded.emp_a, usuario_id=u.id,
                          rol=Rol.TRABAJADOR, estado=UsuarioEstado.INACTIVO))
    db.commit()
    return u.id


def test_residente_incluir_inactivos_no_recibe_inactivos(client, seeded, db):
    """Residente con incluir_inactivos=true NO recibe inactivos: se fuerza a activos."""
    uid_inactivo = _seed_trabajador_inactivo(db, seeded)
    r = client.get(
        "/usuarios",
        params={"incluir_inactivos": True},
        headers=seeded.headers(seeded.resid, seeded.emp_a),
    )
    assert r.status_code == 200, r.text
    ids = {u["id"] for u in r.json()}
    assert ids, "el listado no debe venir vacío (hay usuarios activos)"
    assert uid_inactivo not in ids, "Residente no debe ver inactivos ni pidiéndolos"


def test_admin_incluir_inactivos_si_recibe_inactivos(client, seeded, db):
    """Control positivo: Admin con incluir_inactivos=true SÍ recibe el inactivo."""
    uid_inactivo = _seed_trabajador_inactivo(db, seeded)
    r = client.get(
        "/usuarios",
        params={"incluir_inactivos": True},
        headers=seeded.headers(seeded.admin, seeded.emp_a),
    )
    assert r.status_code == 200, r.text
    ids = {u["id"] for u in r.json()}
    assert uid_inactivo in ids, "Admin con incluir_inactivos=true debe ver el inactivo"
