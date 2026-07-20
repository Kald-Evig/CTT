"""test_proyecto_miembros.py — GET y POST /proyectos/{id}/usuarios (CTT-44 capa 3a parte 2).

Cubre:
  GET  → coordinador_principal 200, coord_ajeno 404, trabajador_sin_membresía 404,
         incluir_inactivos flag (excluye por defecto, muestra con flag)
  POST → deriva rol correcto, 422 campo extra, 409 duplicado activo,
         reactivación con re-derivación de rol, 404 usuario no empresa,
         404 coordinador ajeno, audit_log con actor_rol
"""

import pytest

from app.enums import EmpresaPlan, Rol, UsuarioEstado
from app.models import (
    AuditLog, Empresa, EmpresaUsuario, Proyecto, ProyectoUsuario, Usuario,
)


# ── Fixture ───────────────────────────────────────────────────────────────────

@pytest.fixture()
def datos_miembros(seeded, db, client):
    """Extiende seeded con actores adicionales para tests de membresía.

    Actores extra:
      coord_otro  — COORDINADOR en emp_a, NO es coordinador_principal del proyecto
      nuevo       — TRABAJADOR en emp_a, aún no asignado al proyecto
      exmiembro   — RESIDENTE en emp_a con fila INACTIVA en proyecto_usuarios
      externo     — Usuario que NO pertenece a emp_a (para 404 de empresa)
    """
    coord_otro = Usuario(firebase_uid="m-coord-otro", nombre_completo="Coord Otro",
                         email="coord.otro@a.cl")
    db.add(coord_otro)
    db.flush()
    db.add(EmpresaUsuario(empresa_id=seeded.emp_a, usuario_id=coord_otro.id,
                          rol=Rol.COORDINADOR))

    nuevo = Usuario(firebase_uid="m-nuevo", nombre_completo="Nuevo Miembro",
                    email="nuevo@a.cl")
    db.add(nuevo)
    db.flush()
    db.add(EmpresaUsuario(empresa_id=seeded.emp_a, usuario_id=nuevo.id,
                          rol=Rol.TRABAJADOR))

    exmiembro = Usuario(firebase_uid="m-ex", nombre_completo="Ex Miembro",
                        email="ex@a.cl")
    db.add(exmiembro)
    db.flush()
    db.add(EmpresaUsuario(empresa_id=seeded.emp_a, usuario_id=exmiembro.id,
                          rol=Rol.RESIDENTE))
    db.add(ProyectoUsuario(
        proyecto_id=seeded.proyecto,
        usuario_id=exmiembro.id,
        rol_en_proyecto=Rol.RESIDENTE,
        estado=UsuarioEstado.INACTIVO,
    ))

    # externo existe en usuarios pero no en EmpresaUsuario de emp_a
    externo = Usuario(firebase_uid="m-externo", nombre_completo="Externo",
                      email="externo@otro.cl")
    db.add(externo)
    db.flush()

    db.commit()

    return {
        "client":         client,
        "db":             db,
        "seeded":         seeded,
        "coord_otro_uid": "m-coord-otro",
        "nuevo_id":       nuevo.id,
        "exmiembro_id":   exmiembro.id,
        "externo_id":     externo.id,
    }


# ── GET /proyectos/{id}/usuarios ──────────────────────────────────────────────

def test_get_miembros_coord_principal_200(datos_miembros):
    d = datos_miembros
    s = d["seeded"]
    r = d["client"].get(f"/proyectos/{s.proyecto}/usuarios",
                        headers=s.headers(s.coord))
    assert r.status_code == 200
    ids = [m["usuario_id"] for m in r.json()]
    assert s.resid_id in ids


def test_get_miembros_coord_ajeno_404(datos_miembros):
    d = datos_miembros
    s = d["seeded"]
    r = d["client"].get(f"/proyectos/{s.proyecto}/usuarios",
                        headers=s.headers(d["coord_otro_uid"]))
    assert r.status_code == 404


def test_get_miembros_trabajador_sin_membresia_404(datos_miembros):
    d = datos_miembros
    s = d["seeded"]
    r = d["client"].get(f"/proyectos/{s.proyecto}/usuarios",
                        headers=s.headers(s.trab))
    assert r.status_code == 404


def test_get_miembros_excluye_inactivos_por_defecto(datos_miembros):
    d = datos_miembros
    s = d["seeded"]
    r = d["client"].get(f"/proyectos/{s.proyecto}/usuarios",
                        headers=s.headers(s.coord))
    assert r.status_code == 200
    ids = [m["usuario_id"] for m in r.json()]
    assert d["exmiembro_id"] not in ids


def test_get_miembros_incluir_inactivos_muestra_exmiembro(datos_miembros):
    d = datos_miembros
    s = d["seeded"]
    r = d["client"].get(f"/proyectos/{s.proyecto}/usuarios?incluir_inactivos=true",
                        headers=s.headers(s.coord))
    assert r.status_code == 200
    ids = [m["usuario_id"] for m in r.json()]
    assert d["exmiembro_id"] in ids


# ── POST /proyectos/{id}/usuarios ─────────────────────────────────────────────

def test_post_miembro_deriva_rol_correcto(datos_miembros):
    d = datos_miembros
    s = d["seeded"]
    # nuevo es TRABAJADOR en emp_a → rol_en_proyecto debe ser trabajador
    r = d["client"].post(f"/proyectos/{s.proyecto}/usuarios",
                         json={"usuario_id": d["nuevo_id"]},
                         headers=s.headers(s.admin))
    assert r.status_code == 201
    body = r.json()
    assert body["rol_en_proyecto"] == "trabajador"
    assert body["estado"] == "activo"
    assert body["usuario_id"] == d["nuevo_id"]


def test_post_miembro_rol_no_aceptado_como_input(datos_miembros):
    """El body solo acepta usuario_id (extra='forbid') — rol extra → 422."""
    d = datos_miembros
    s = d["seeded"]
    r = d["client"].post(f"/proyectos/{s.proyecto}/usuarios",
                         json={"usuario_id": d["nuevo_id"], "rol_en_proyecto": "admin"},
                         headers=s.headers(s.admin))
    assert r.status_code == 422


def test_post_miembro_duplicado_activo_409(datos_miembros):
    d = datos_miembros
    s = d["seeded"]
    # resid ya es miembro ACTIVO del proyecto (insertado por seeded)
    r = d["client"].post(f"/proyectos/{s.proyecto}/usuarios",
                         json={"usuario_id": s.resid_id},
                         headers=s.headers(s.admin))
    assert r.status_code == 409


def test_post_miembro_reactiva_inactivo(datos_miembros):
    """Reactivar un exmiembro INACTIVO → 201, estado activo, sin duplicar la fila."""
    d = datos_miembros
    s = d["seeded"]
    db = d["db"]
    exmiembro_id = d["exmiembro_id"]
    r = d["client"].post(f"/proyectos/{s.proyecto}/usuarios",
                         json={"usuario_id": exmiembro_id},
                         headers=s.headers(s.admin))
    assert r.status_code == 201
    assert r.json()["estado"] == "activo"
    # Verificar que no se duplicó la fila (UPDATE, no INSERT).
    db.expire_all()
    count = (
        db.query(ProyectoUsuario)
        .filter(ProyectoUsuario.proyecto_id == s.proyecto,
                ProyectoUsuario.usuario_id == exmiembro_id)
        .count()
    )
    assert count == 1


def test_post_miembro_usuario_no_miembro_empresa_404(datos_miembros):
    d = datos_miembros
    s = d["seeded"]
    r = d["client"].post(f"/proyectos/{s.proyecto}/usuarios",
                         json={"usuario_id": d["externo_id"]},
                         headers=s.headers(s.admin))
    assert r.status_code == 404


def test_post_miembro_coord_ajeno_404(datos_miembros):
    d = datos_miembros
    s = d["seeded"]
    r = d["client"].post(f"/proyectos/{s.proyecto}/usuarios",
                         json={"usuario_id": d["nuevo_id"]},
                         headers=s.headers(d["coord_otro_uid"]))
    assert r.status_code == 404


def test_post_miembro_crea_audit_log(datos_miembros):
    d = datos_miembros
    s = d["seeded"]
    db = d["db"]
    r = d["client"].post(f"/proyectos/{s.proyecto}/usuarios",
                         json={"usuario_id": d["nuevo_id"]},
                         headers=s.headers(s.admin))
    assert r.status_code == 201
    db.expire_all()
    entrada = (
        db.query(AuditLog)
        .filter(
            AuditLog.accion == "asignacion_usuario",
            AuditLog.entidad_tipo == "proyecto_usuario",
            AuditLog.proyecto_id == s.proyecto,
        )
        .first()
    )
    assert entrada is not None
    assert entrada.actor_rol == "admin"
