"""
routers/me.py — Perfil del usuario autenticado (GET /me).

Devuelve los datos básicos del usuario y la lista de empresas activas a las
que pertenece. No requiere empresa activa — un usuario sin empresas recibe
lista vacía (200), no un error. Diseñado para que el móvil determine la
navegación post-login (selección de empresa / ruta por rol).
"""

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.auth import get_usuario_actual
from app.database import get_db
from app.enums import EmpresaEstado, UsuarioEstado
from app.models import Empresa, EmpresaUsuario, Usuario
from app.schemas import EmpresaMeOut, MeOut, MeUsuarioOut

router = APIRouter(tags=["Sesión"])


@router.get("/me", response_model=MeOut)
def obtener_perfil_propio(
    usuario: Usuario = Depends(get_usuario_actual),
    db: Session = Depends(get_db),
):
    """Retorna el perfil del usuario autenticado y sus empresas activas.

    Reglas de filtro para la lista de empresas:
    - empresa_usuario.estado = activo  (membresía activa)
    - empresa.estado != suspendido     (empresa operativa — activo o trial)
    """
    filas = (
        db.query(EmpresaUsuario, Empresa)
        .join(Empresa, Empresa.id == EmpresaUsuario.empresa_id)
        .filter(
            EmpresaUsuario.usuario_id == usuario.id,
            EmpresaUsuario.estado == UsuarioEstado.ACTIVO,
            Empresa.estado != EmpresaEstado.SUSPENDIDO,
        )
        .all()
    )

    empresas = [
        EmpresaMeOut(
            empresa_id=eu.empresa_id,
            empresa_nombre=emp.nombre,
            rol=eu.rol,
        )
        for eu, emp in filas
    ]

    return MeOut(
        usuario=MeUsuarioOut.model_validate(usuario),
        empresas=empresas,
    )
