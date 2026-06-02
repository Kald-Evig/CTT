"""
routers/usuarios.py — Gestión de usuarios dentro de una empresa (Sección 14.2).

Crear usuario crea: (1) el Usuario interno, (2) su membresía en la empresa activa
con el rol indicado. En MODO MOCK también genera un firebase_uid que se devuelve
para poder "iniciar sesión" en la demo (en producción lo provee Firebase Auth).
"""

import uuid

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.auth import AuthContext, get_current_context, requiere_empresa
from app.config import settings
from app.database import get_db
from app.enums import UsuarioEstado
from app.models import EmpresaUsuario, Usuario
from app.permissions import puede
from app.schemas import UsuarioCreate, UsuarioOut

router = APIRouter(prefix="/usuarios", tags=["Usuarios"])


@router.post("", status_code=201)
def crear_usuario(
    body: UsuarioCreate,
    ctx: AuthContext = Depends(get_current_context),
    db: Session = Depends(get_db),
):
    """Crea un usuario y lo asocia a la empresa activa (Admin / Super Admin)."""
    empresa_id = requiere_empresa(ctx)
    if not puede(ctx.rol, "crear_usuarios", ctx.es_super_admin):
        raise HTTPException(403, "Su rol no puede crear usuarios.")

    # ¿Ya existe un usuario con ese email? Reusarlo (puede pertenecer a varias
    # empresas — Sección 14.3) en vez de duplicar.
    usuario = db.query(Usuario).filter(Usuario.email == body.email).first()
    firebase_uid = None
    if usuario is None:
        firebase_uid = str(uuid.uuid4())  # producción: lo entrega Firebase
        usuario = Usuario(
            firebase_uid=firebase_uid,
            nombre_completo=body.nombre_completo,
            rut=body.rut,
            email=body.email,
            telefono=body.telefono,
        )
        db.add(usuario)
        db.flush()  # obtener usuario.id sin commit todavía

    # Evitar membresía duplicada en la misma empresa.
    ya = (
        db.query(EmpresaUsuario)
        .filter(EmpresaUsuario.usuario_id == usuario.id,
                EmpresaUsuario.empresa_id == empresa_id)
        .first()
    )
    if ya is not None:
        raise HTTPException(409, "El usuario ya pertenece a esta empresa.")

    db.add(EmpresaUsuario(empresa_id=empresa_id, usuario_id=usuario.id, rol=body.rol))
    db.commit()
    db.refresh(usuario)

    resp = UsuarioOut.model_validate(usuario).model_dump()
    # Solo en modo mock devolvemos el uid para facilitar el login de demo.
    if settings.AUTH_MODE == "mock" and firebase_uid:
        resp["firebase_uid_demo"] = firebase_uid
    return resp


@router.get("", response_model=list[UsuarioOut])
def listar_usuarios(
    ctx: AuthContext = Depends(get_current_context),
    db: Session = Depends(get_db),
):
    """Lista los usuarios que pertenecen a la empresa activa."""
    empresa_id = requiere_empresa(ctx)
    return (
        db.query(Usuario)
        .join(EmpresaUsuario, EmpresaUsuario.usuario_id == Usuario.id)
        .filter(EmpresaUsuario.empresa_id == empresa_id,
                EmpresaUsuario.estado == UsuarioEstado.ACTIVO)
        .all()
    )
