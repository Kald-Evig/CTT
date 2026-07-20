"""test_authz.py — Tests unitarios de require_project_access (authz.py).

Llama la dependencia interna directamente (sin HTTP) para aislar la lógica
de autorización de la capa de routing. Cada test verifica un predicado preciso:
status_code correcto, o que el Proyecto retornado es el esperado.
"""

import pytest
from fastapi import HTTPException

from app.auth import AuthContext
from app.authz import require_project_access
from app.enums import EmpresaPlan, Rol
from app.models import Empresa, EmpresaUsuario, Proyecto, ProyectoUsuario, Usuario


# ── Fixture ───────────────────────────────────────────────────────────────────

@pytest.fixture()
def datos_authz(db):
    """Empresa con 7 actores, 1 proyecto.

    Actores:
      admin          — ADMIN de la empresa
      coord_princ    — COORDINADOR y coordinador_principal del proyecto
      coord_otro     — COORDINADOR, pero no coordinador_principal
      resid_miembro  — RESIDENTE con membresía activa en proyecto_usuarios
      resid_fuera    — RESIDENTE sin membresía en proyecto_usuarios
      trab_sin       — TRABAJADOR sin membresía en proyecto_usuarios
      trab_miembro   — TRABAJADOR con membresía activa en proyecto_usuarios
    """
    emp = Empresa(nombre="Emp AuthZ", rut_empresa="76.222.222-2",
                  email_contacto="authz@t.cl", plan=EmpresaPlan.PRO)
    db.add(emp)
    db.flush()

    admin        = Usuario(firebase_uid="az-admin",    nombre_completo="Admin",           email="admin@az.cl")
    coord_princ  = Usuario(firebase_uid="az-coord-p",  nombre_completo="Coord Principal", email="coord.p@az.cl")
    coord_otro   = Usuario(firebase_uid="az-coord-o",  nombre_completo="Coord Otro",      email="coord.o@az.cl")
    resid_m      = Usuario(firebase_uid="az-resid-m",  nombre_completo="Resid Miembro",   email="resid.m@az.cl")
    resid_fuera  = Usuario(firebase_uid="az-resid-nm", nombre_completo="Resid Fuera",     email="resid.nm@az.cl")
    trab_sin     = Usuario(firebase_uid="az-trab-s",   nombre_completo="Trab Sin",        email="trab.s@az.cl")
    trab_miembro = Usuario(firebase_uid="az-trab-m",   nombre_completo="Trab Miembro",    email="trab.m@az.cl")
    db.add_all([admin, coord_princ, coord_otro, resid_m, resid_fuera, trab_sin, trab_miembro])
    db.flush()

    db.add_all([
        EmpresaUsuario(empresa_id=emp.id, usuario_id=admin.id,        rol=Rol.ADMIN),
        EmpresaUsuario(empresa_id=emp.id, usuario_id=coord_princ.id,  rol=Rol.COORDINADOR),
        EmpresaUsuario(empresa_id=emp.id, usuario_id=coord_otro.id,   rol=Rol.COORDINADOR),
        EmpresaUsuario(empresa_id=emp.id, usuario_id=resid_m.id,      rol=Rol.RESIDENTE),
        EmpresaUsuario(empresa_id=emp.id, usuario_id=resid_fuera.id,  rol=Rol.RESIDENTE),
        EmpresaUsuario(empresa_id=emp.id, usuario_id=trab_sin.id,     rol=Rol.TRABAJADOR),
        EmpresaUsuario(empresa_id=emp.id, usuario_id=trab_miembro.id, rol=Rol.TRABAJADOR),
    ])

    proyecto = Proyecto(empresa_id=emp.id, nombre="Proyecto AuthZ",
                        coordinador_principal_id=coord_princ.id,
                        created_by=coord_princ.id)
    db.add(proyecto)
    db.flush()

    db.add_all([
        ProyectoUsuario(proyecto_id=proyecto.id, usuario_id=resid_m.id,
                        rol_en_proyecto=Rol.RESIDENTE),
        ProyectoUsuario(proyecto_id=proyecto.id, usuario_id=trab_miembro.id,
                        rol_en_proyecto=Rol.TRABAJADOR),
    ])
    db.commit()

    def ctx(usuario: Usuario, rol: Rol) -> AuthContext:
        return AuthContext(usuario=usuario, empresa_id=emp.id,
                          rol=rol, es_super_admin=False)

    return {
        "db":          db,
        "proyecto_id": proyecto.id,
        "admin":        ctx(admin,        Rol.ADMIN),
        "coord_princ":  ctx(coord_princ,  Rol.COORDINADOR),
        "coord_otro":   ctx(coord_otro,   Rol.COORDINADOR),
        "resid_m":      ctx(resid_m,      Rol.RESIDENTE),
        "resid_fuera":  ctx(resid_fuera,  Rol.RESIDENTE),
        "trab_sin":     ctx(trab_sin,     Rol.TRABAJADOR),
        "trab_miembro": ctx(trab_miembro, Rol.TRABAJADOR),
    }


def _invoke(operacion: str, d: dict, actor: str) -> Proyecto:
    """Llama la dependencia interna directamente, sin HTTP."""
    dep = require_project_access(operacion)
    return dep(proyecto_id=d["proyecto_id"], ctx=d[actor], db=d["db"])


# ── lectura ───────────────────────────────────────────────────────────────────

def test_admin_lectura_pasa(datos_authz):
    p = _invoke("lectura", datos_authz, "admin")
    assert p.id == datos_authz["proyecto_id"]


def test_coordinador_principal_lectura_pasa(datos_authz):
    p = _invoke("lectura", datos_authz, "coord_princ")
    assert p.id == datos_authz["proyecto_id"]


def test_coordinador_otro_lectura_404(datos_authz):
    with pytest.raises(HTTPException) as exc:
        _invoke("lectura", datos_authz, "coord_otro")
    assert exc.value.status_code == 404


def test_residente_miembro_lectura_pasa(datos_authz):
    p = _invoke("lectura", datos_authz, "resid_m")
    assert p.id == datos_authz["proyecto_id"]


def test_residente_fuera_lectura_404(datos_authz):
    with pytest.raises(HTTPException) as exc:
        _invoke("lectura", datos_authz, "resid_fuera")
    assert exc.value.status_code == 404


def test_trabajador_sin_membresia_lectura_404(datos_authz):
    """Trabajador sin membresía activa → no revelar existencia del proyecto."""
    with pytest.raises(HTTPException) as exc:
        _invoke("lectura", datos_authz, "trab_sin")
    assert exc.value.status_code == 404


def test_trabajador_miembro_lectura_403(datos_authz):
    """Trabajador con membresía activa → ve el proyecto, pero no puede la operación."""
    with pytest.raises(HTTPException) as exc:
        _invoke("lectura", datos_authz, "trab_miembro")
    assert exc.value.status_code == 403


# ── gestionar ─────────────────────────────────────────────────────────────────

def test_admin_gestionar_pasa(datos_authz):
    p = _invoke("gestionar", datos_authz, "admin")
    assert p.id == datos_authz["proyecto_id"]


def test_coordinador_principal_gestionar_pasa(datos_authz):
    p = _invoke("gestionar", datos_authz, "coord_princ")
    assert p.id == datos_authz["proyecto_id"]


def test_coordinador_otro_gestionar_404(datos_authz):
    with pytest.raises(HTTPException) as exc:
        _invoke("gestionar", datos_authz, "coord_otro")
    assert exc.value.status_code == 404


def test_residente_gestionar_403(datos_authz):
    with pytest.raises(HTTPException) as exc:
        _invoke("gestionar", datos_authz, "resid_m")
    assert exc.value.status_code == 403


def test_trabajador_sin_membresia_gestionar_404(datos_authz):
    """Trabajador sin membresía activa → no revelar existencia del proyecto."""
    with pytest.raises(HTTPException) as exc:
        _invoke("gestionar", datos_authz, "trab_sin")
    assert exc.value.status_code == 404


def test_trabajador_miembro_gestionar_403(datos_authz):
    """Trabajador con membresía activa → ve el proyecto, pero no puede la operación."""
    with pytest.raises(HTTPException) as exc:
        _invoke("gestionar", datos_authz, "trab_miembro")
    assert exc.value.status_code == 403
