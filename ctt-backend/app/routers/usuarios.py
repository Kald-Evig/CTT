"""
routers/usuarios.py — Gestión de usuarios dentro de una empresa (Sección 14.2).

La creación de usuarios siempre pasa por Firebase Auth: se genera una
contraseña aleatoria server-side (nunca visible, nunca persistida), se inserta
en BD y se devuelve un reset link para que el Admin lo entregue al usuario
por fuera de banda. AUTH_MODE solo controla la validación del token entrante
(CTT-88, no se toca aquí).

Si el email ya existe en Firebase se reutiliza su uid; si ya pertenece a la
empresa se devuelve 409.
"""

import logging
import secrets
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query
from firebase_admin import auth as fb_auth
from sqlalchemy.orm import Session

from app.auth import AuthContext, get_current_context, requiere_empresa
from app.database import get_db
from app.enums import Rol, UsuarioEstado
from app.models import EmpresaUsuario, Usuario
from app.permissions import puede
from app.schemas import UsuarioCreate, UsuarioCreateOut, UsuarioEstadoUpdate, UsuarioRolUpdate, UsuarioOut

router = APIRouter(prefix="/usuarios", tags=["Usuarios"])

_log_err = logging.getLogger(__name__)

# Jerarquía de roles para la regla anti-escalada (Sección 2.1).
_JERARQUIA_ROL: dict[Rol, int] = {
    Rol.TRABAJADOR: 0,
    Rol.RESIDENTE: 1,
    Rol.COORDINADOR: 2,
    Rol.ADMIN: 3,
}


def _usuario_a_dict(u: Usuario, rol: Rol) -> dict:
    return {
        "id": u.id,
        "nombre_completo": u.nombre_completo,
        "rut": u.rut,
        "email": u.email,
        "estado": u.estado,
        "rol": rol,
    }


@router.post("", status_code=201, response_model=UsuarioCreateOut)
def crear_usuario(
    body: UsuarioCreate,
    ctx: AuthContext = Depends(get_current_context),
    db: Session = Depends(get_db),
):
    """Crea un usuario en Firebase + BD y lo asocia a la empresa activa (Admin / Super Admin)."""
    empresa_id = requiere_empresa(ctx)
    if not puede(ctx.rol, "crear_usuarios", ctx.es_super_admin):
        raise HTTPException(403, "Su rol no puede crear usuarios.")

    # Anti-escalación: nunca asignar un rol superior al del actor.
    # Default -1 en el actor: un rol desconocido no hereda privilegio máximo.
    if ctx.rol is not None and (
        _JERARQUIA_ROL.get(body.rol, 0) > _JERARQUIA_ROL.get(ctx.rol, -1)
    ):
        raise HTTPException(403, "No puede asignar un rol superior al suyo.")

    # Idempotencia: si el email ya existe en Firebase, reusar su uid.
    firebase_uid: str | None = None
    usuario_existia_en_firebase = False
    try:
        fb_user = fb_auth.get_user_by_email(body.email)
        firebase_uid = fb_user.uid
        usuario_existia_en_firebase = True
    except fb_auth.UserNotFoundError:
        pass

    if firebase_uid is None:
        # Crear cuenta con contraseña aleatoria server-side.
        # La contraseña nunca se comunica, guarda ni loguea.
        _pwd = secrets.token_urlsafe(32)
        try:
            fb_user = fb_auth.create_user(
                email=body.email,
                password=_pwd,
                email_verified=False,
            )
            firebase_uid = fb_user.uid
        except Exception as exc:
            _log_err.error(
                "Error al crear cuenta en Firebase: email=%s error=%s", body.email, exc
            )
            raise HTTPException(
                502, "Error al crear la cuenta en el proveedor de autenticación."
            ) from exc
        finally:
            _pwd = None  # minimizar ventana en memoria

    # Insertar o reusar en la BD.
    usuario = db.query(Usuario).filter(Usuario.email == body.email).first()
    if usuario is None:
        usuario = Usuario(
            firebase_uid=firebase_uid,
            nombre_completo=body.nombre_completo,
            rut=body.rut,
            email=body.email,
            telefono=body.telefono,
        )
        db.add(usuario)
        db.flush()

    ya = (
        db.query(EmpresaUsuario)
        .filter(
            EmpresaUsuario.usuario_id == usuario.id,
            EmpresaUsuario.empresa_id == empresa_id,
        )
        .first()
    )
    if ya is not None:
        raise HTTPException(409, "El usuario ya pertenece a esta empresa.")

    db.add(EmpresaUsuario(empresa_id=empresa_id, usuario_id=usuario.id, rol=body.rol))
    try:
        db.commit()
    except Exception as exc:
        db.rollback()
        if not usuario_existia_en_firebase:
            # Solo borrar si nosotros lo creamos; si ya existía, no tocarlo.
            try:
                fb_auth.delete_user(firebase_uid)
            except Exception as del_exc:
                _log_err.error(
                    "Firebase uid huérfano tras fallo de BD: uid=%s error=%s",
                    firebase_uid,
                    del_exc,
                )
        raise HTTPException(500, "Error al crear usuario. Intenta de nuevo.") from exc

    reset_link: str | None = None
    reset_link_pendiente = False
    try:
        reset_link = fb_auth.generate_password_reset_link(body.email)
    except Exception as exc:
        _log_err.error(
            "No se pudo generar reset link: email=%s error=%s", body.email, exc
        )
        reset_link_pendiente = True

    db.refresh(usuario)
    resp = _usuario_a_dict(usuario, body.rol)
    resp["reset_link"] = reset_link
    resp["reset_link_pendiente"] = reset_link_pendiente
    return resp


@router.patch("/{usuario_id}/estado", response_model=UsuarioOut)
def actualizar_estado_usuario(
    usuario_id: str,
    body: UsuarioEstadoUpdate,
    ctx: AuthContext = Depends(get_current_context),
    db: Session = Depends(get_db),
):
    """Activa o desactiva la membresía de un usuario en la empresa activa.

    Modifica EmpresaUsuario.estado (empresa-scoped), no Usuario.estado (global).
    Justificación: get_current_context filtra membresías activas por
    EmpresaUsuario.estado; INACTIVO aquí bloquea acceso a esta empresa sin
    afectar otras membresías. Usuario.estado = INACTIVO es una acción de
    Super Admin (plataforma) y requiere un endpoint separado.
    """
    empresa_id = requiere_empresa(ctx)
    if not puede(ctx.rol, "crear_usuarios", ctx.es_super_admin):
        raise HTTPException(403, "Su rol no puede gestionar usuarios.")

    if usuario_id == ctx.usuario.id:
        raise HTTPException(409, "No puede modificar su propio estado de acceso.")

    fila = (
        db.query(EmpresaUsuario)
        .filter(
            EmpresaUsuario.empresa_id == empresa_id,
            EmpresaUsuario.usuario_id == usuario_id,
        )
        .first()
    )
    if fila is None:
        raise HTTPException(404, "Usuario no encontrado en esta empresa.")

    fila.estado = body.estado
    db.commit()

    usuario = db.query(Usuario).filter(Usuario.id == usuario_id).first()
    resp = _usuario_a_dict(usuario, fila.rol)
    resp["estado"] = fila.estado.value  # estado de membresía, no global
    return resp


@router.patch("/{usuario_id}/rol", response_model=UsuarioOut)
def actualizar_rol_usuario(
    usuario_id: str,
    body: UsuarioRolUpdate,
    ctx: AuthContext = Depends(get_current_context),
    db: Session = Depends(get_db),
):
    """Cambia el rol de un usuario en la empresa activa (gestionar_roles).

    Anti-escalación: nunca puede asignarse un rol superior al del actor.
    Usa el permiso 'gestionar_roles' (permissions.py:33), que existía en la
    matriz pero no tenía ningún endpoint invocándolo.
    """
    empresa_id = requiere_empresa(ctx)
    if not puede(ctx.rol, "gestionar_roles", ctx.es_super_admin):
        raise HTTPException(403, "Su rol no puede gestionar roles.")

    # Anti-escalación: misma regla que en crear_usuario. Default -1 en el actor.
    if ctx.rol is not None and (
        _JERARQUIA_ROL.get(body.rol, 0) > _JERARQUIA_ROL.get(ctx.rol, -1)
    ):
        raise HTTPException(403, "No puede asignar un rol superior al suyo.")

    if usuario_id == ctx.usuario.id:
        raise HTTPException(409, "No puede modificar su propio rol.")

    fila = (
        db.query(EmpresaUsuario)
        .filter(
            EmpresaUsuario.empresa_id == empresa_id,
            EmpresaUsuario.usuario_id == usuario_id,
        )
        .first()
    )
    if fila is None:
        raise HTTPException(404, "Usuario no encontrado en esta empresa.")

    fila.rol = body.rol
    db.commit()

    usuario = db.query(Usuario).filter(Usuario.id == usuario_id).first()
    resp = _usuario_a_dict(usuario, fila.rol)
    resp["estado"] = fila.estado.value
    return resp


@router.get("", response_model=list[UsuarioOut])
def listar_usuarios(
    roles: Annotated[list[Rol] | None, Query(alias="rol")] = None,
    incluir_inactivos: bool = False,
    ctx: AuthContext = Depends(get_current_context),
    db: Session = Depends(get_db),
):
    """Lista los usuarios que pertenecen a la empresa activa.

    Sin ?rol= → devuelve todos. Con uno o más ?rol=x&rol=y → filtra por esos roles.
    incluir_inactivos=false (default) → solo membresías activas (comportamiento original).
    incluir_inactivos=true → devuelve activos e inactivos (uso exclusivo de Admin UI).
    """
    empresa_id = requiere_empresa(ctx)
    q = (
        db.query(Usuario, EmpresaUsuario.rol, EmpresaUsuario.estado)
        .join(EmpresaUsuario, EmpresaUsuario.usuario_id == Usuario.id)
        .filter(EmpresaUsuario.empresa_id == empresa_id)
    )
    if not incluir_inactivos:
        q = q.filter(EmpresaUsuario.estado == UsuarioEstado.ACTIVO)
    if roles:
        q = q.filter(EmpresaUsuario.rol.in_(roles))
    result = []
    for u, rol, estado_membresia in q.all():
        d = _usuario_a_dict(u, rol)
        d["estado"] = estado_membresia.value
        result.append(d)
    return result
