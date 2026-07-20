"""
authz.py — Autorización resource-scoped (OWASP A01, NIST AC-6).

Separa el control de acceso a recursos específicos (proyecto, ítem) de la
autenticación (auth.py) y de los permisos de rol genérico (permissions.py).

`require_project_access(operacion)` es una factory que retorna una dependencia
FastAPI. Úsala via los aliases nombrados:

    proyecto: Proyecto = Depends(require_project_read)
    proyecto: Proyecto = Depends(require_project_manage)

La dependencia retorna el Proyecto cargado; FastAPI lo cachea en el request,
evitando una segunda query en el endpoint.

Reglas (fuente de verdad — CTT-44):
  - ADMIN          → pasa siempre, sin verificar relación con el proyecto.
  - COORDINADOR    → pasa solo si es coordinador_principal del proyecto.
                     Si no lo es: 404 (RFC 9110 — no revelar existencia).
  - RESIDENTE      → lectura: pasa si tiene membresía activa en proyecto_usuarios.
                     gestionar: 403 (rol sin capacidad de escritura).
                     Si no es miembro para lectura: 404 (OWASP A01).
  - TRABAJADOR     → sin membresía activa en proyecto_usuarios: 404.
                     con membresía activa: 403 (ve el proyecto, no puede la operación).
"""

from typing import Callable, Literal

from fastapi import Depends, HTTPException
from sqlalchemy.orm import Session

from app.auth import AuthContext, get_current_context, requiere_empresa
from app.database import get_db
from app.enums import Rol, UsuarioEstado
from app.models import Proyecto, ProyectoUsuario
from app.tenancy import get_proyecto_de_empresa


def require_project_access(
    operacion: Literal["lectura", "gestionar"],
) -> Callable[..., Proyecto]:
    """Factory: retorna una dependencia FastAPI para autorización resource-scoped.

    Parametrizada por operación para evitar duplicar la lógica ADMIN/COORDINADOR/
    TRABAJADOR (que es idéntica en ambas variantes) y mantener un punto único de
    modificación para CTT-78 y siguientes.
    """
    def _dep(
        proyecto_id: str,
        ctx: AuthContext = Depends(get_current_context),
        db: Session = Depends(get_db),
    ) -> Proyecto:
        empresa_id = requiere_empresa(ctx)
        # Valida tenant y existencia; 404 automático si no pertenece a la empresa.
        proyecto = get_proyecto_de_empresa(db, proyecto_id, empresa_id)

        if ctx.rol == Rol.ADMIN:
            return proyecto

        if ctx.rol == Rol.COORDINADOR:
            if proyecto.coordinador_principal_id != ctx.usuario.id:
                # 404, no 403 — no revelar que el proyecto existe (RFC 9110, OWASP A01).
                raise HTTPException(status_code=404, detail="Proyecto no encontrado.")
            return proyecto

        if ctx.rol == Rol.RESIDENTE:
            if operacion == "gestionar":
                raise HTTPException(status_code=403,
                                    detail="Su rol no puede gestionar miembros del proyecto.")
            # lectura: requiere membresía activa en proyecto_usuarios.
            membresia = (
                db.query(ProyectoUsuario)
                .filter(
                    ProyectoUsuario.proyecto_id == proyecto.id,
                    ProyectoUsuario.usuario_id == ctx.usuario.id,
                    ProyectoUsuario.estado == UsuarioEstado.ACTIVO,
                )
                .first()
            )
            if membresia is None:
                raise HTTPException(status_code=404, detail="Proyecto no encontrado.")
            return proyecto

        # TRABAJADOR (y cualquier rol futuro no listado):
        # verificar visibilidad antes de rechazar — fuente única: proyecto_usuarios.
        en_proyecto = (
            db.query(ProyectoUsuario)
            .filter(
                ProyectoUsuario.proyecto_id == proyecto.id,
                ProyectoUsuario.usuario_id == ctx.usuario.id,
                ProyectoUsuario.estado == UsuarioEstado.ACTIVO,
            )
            .first()
        )
        if en_proyecto is None:
            # Sin membresía activa — no revelar existencia (RFC 9110, OWASP A01).
            raise HTTPException(status_code=404, detail="Proyecto no encontrado.")
        # Es miembro pero el rol no puede acceder a ninguna operación de este endpoint.
        raise HTTPException(status_code=403,
                            detail="Su rol no puede acceder a esta operación.")

    return _dep


# Aliases nombrados — úsalos en los endpoints para evitar repetir el literal.
require_project_read   = require_project_access("lectura")
require_project_manage = require_project_access("gestionar")
