"""
auth.py — Autenticación y contexto de sesión.

MODO MOCK (default): el cliente envía `Authorization: Bearer <firebase_uid>` y,
si pertenece a varias empresas, `X-Empresa-Id: <id>` para elegir la empresa activa.
No hay validación criptográfica: es para demo/UAT local.

MODO FIREBASE (producción, Sección 4.3): se valida el JWT con firebase-admin y se
extrae el `uid`. El RESTO del flujo es idéntico, porque ambos modos terminan
resolviendo un `firebase_uid` -> usuario interno -> empresa activa -> rol.
Para activarlo: AUTH_MODE=firebase y reemplazar `_resolver_uid` por la verificación
real (un único punto de cambio).

El objeto AuthContext es lo que reciben los endpoints: quién es, en qué empresa
opera y con qué rol. Todo el filtrado multi-tenant (Sección 4.2) parte de aquí.
"""

from dataclasses import dataclass

from fastapi import Depends, Header, HTTPException, status
from sqlalchemy.orm import Session

from app.config import settings
from app.database import get_db
from app.enums import Rol, UsuarioEstado
from app.models import EmpresaUsuario, Usuario


@dataclass
class AuthContext:
    """Contexto de sesión resuelto para cada request."""
    usuario: Usuario
    empresa_id: str | None           # None solo para Super Admin sin empresa activa
    rol: Rol | None                  # rol en la empresa activa
    es_super_admin: bool


def _resolver_uid(authorization: str | None) -> str:
    """Extrae el firebase_uid del header Authorization.

    En MODO FIREBASE este es el único método a reemplazar por la verificación
    real del JWT (firebase_admin.auth.verify_id_token).
    """
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Falta token. Use 'Authorization: Bearer <token>'.",
        )
    token = authorization.split(" ", 1)[1].strip()

    if settings.AUTH_MODE == "firebase":
        # PRODUCCIÓN: validar JWT con firebase-admin y devolver decoded["uid"].
        # from firebase_admin import auth as fb_auth
        # return fb_auth.verify_id_token(token)["uid"]
        raise HTTPException(
            status_code=status.HTTP_501_NOT_IMPLEMENTED,
            detail="AUTH_MODE=firebase requiere configurar firebase-admin.",
        )

    # MOCK: el token ES el firebase_uid.
    return token


def get_current_context(
    authorization: str | None = Header(default=None),
    x_empresa_id: str | None = Header(default=None),
    db: Session = Depends(get_db),
) -> AuthContext:
    """Dependencia principal: resuelve usuario, empresa activa y rol.

    - Valida que el usuario exista y esté activo.
    - Si pertenece a varias empresas, exige `X-Empresa-Id` para elegir la activa
      (Sección 14.3: selección de empresa al iniciar sesión).
    - Verifica que el usuario esté activo EN esa empresa.
    """
    uid = _resolver_uid(authorization)

    usuario = db.query(Usuario).filter(Usuario.firebase_uid == uid).first()
    if usuario is None:
        raise HTTPException(status_code=401, detail="Usuario no encontrado.")
    if usuario.estado != UsuarioEstado.ACTIVO:
        raise HTTPException(status_code=403, detail="Usuario inactivo.")

    # Membresías activas del usuario.
    membresias = (
        db.query(EmpresaUsuario)
        .filter(EmpresaUsuario.usuario_id == usuario.id,
                EmpresaUsuario.estado == UsuarioEstado.ACTIVO)
        .all()
    )

    # Super Admin sin empresa: opera a nivel plataforma.
    if not membresias:
        if usuario.es_super_admin:
            return AuthContext(usuario=usuario, empresa_id=None, rol=None,
                               es_super_admin=True)
        raise HTTPException(status_code=403, detail="El usuario no pertenece a "
                                                    "ninguna empresa activa.")

    # Resolver empresa activa.
    if len(membresias) == 1 and x_empresa_id is None:
        activa = membresias[0]
    else:
        if x_empresa_id is None:
            raise HTTPException(
                status_code=400,
                detail="Pertenece a varias empresas: indique 'X-Empresa-Id'.",
            )
        activa = next((m for m in membresias if m.empresa_id == x_empresa_id), None)
        if activa is None:
            raise HTTPException(status_code=403,
                                detail="No tiene acceso a esa empresa.")

    return AuthContext(
        usuario=usuario,
        empresa_id=activa.empresa_id,
        rol=activa.rol,
        es_super_admin=usuario.es_super_admin,
    )


def requiere_empresa(ctx: AuthContext) -> str:
    """Helper: asegura que hay una empresa activa y devuelve su id.

    Útil en endpoints de obra donde el Super Admin sin empresa no aplica.
    """
    if ctx.empresa_id is None or ctx.rol is None:
        raise HTTPException(status_code=400,
                            detail="Se requiere una empresa activa para esta acción.")
    return ctx.empresa_id
