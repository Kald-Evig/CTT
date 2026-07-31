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

Reglas (fuente de verdad — CTT-44, CTT-78):
  - ADMIN / Super Admin → pasa siempre, sin verificar relación con el proyecto.
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
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.auth import AuthContext, get_current_context, requiere_empresa
from app.database import get_db
from app.enums import Rol, UsuarioEstado
from app.models import Item, Proyecto, ProyectoUsuario
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

        if ctx.rol == Rol.ADMIN or ctx.es_super_admin:
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


# ── Item access (CTT-96) ──────────────────────────────────────────────────────

def require_item_access(
    item_id: str,
    ctx: AuthContext = Depends(get_current_context),
    db: Session = Depends(get_db),
) -> Item:
    """Dependencia FastAPI para autorización resource-scoped en endpoints de ítem.

    Una sola query: JOIN Proyecto (tenant) + OUTER JOIN ProyectoUsuario (en ON,
    no en WHERE, para preservar la fila del ítem cuando no hay membresía).

    Reglas (CTT-96, decisión Kald 29-jul-2026):
      ADMIN / Super Admin → pasa siempre dentro de la empresa.
      COORDINADOR         → pasa si es coordinador_principal del proyecto; 404 si no.
      RESIDENTE           → pasa si tiene membresía activa en proyecto_usuarios; 404 si no.
      TRABAJADOR          → (a) asignado_a == él → pasa (gana sobre ausencia de membresía).
                            (b) membresía activa pero no asignado → 403.
                            (c) sin membresía y no asignado → 404 (OWASP A01).
    """
    empresa_id = requiere_empresa(ctx)

    row = (
        db.query(Item, Proyecto, ProyectoUsuario)
        .join(Proyecto, (Item.proyecto_id == Proyecto.id) & (Proyecto.empresa_id == empresa_id))
        .outerjoin(
            ProyectoUsuario,
            (ProyectoUsuario.proyecto_id == Item.proyecto_id)
            & (ProyectoUsuario.usuario_id == ctx.usuario.id)
            & (ProyectoUsuario.estado == UsuarioEstado.ACTIVO),
        )
        .filter(Item.id == item_id)
        .first()
    )
    if row is None:
        raise HTTPException(404, "Ítem no encontrado.")
    item, proyecto, membresia = row

    if ctx.rol == Rol.ADMIN or ctx.es_super_admin:
        return item

    if ctx.rol == Rol.COORDINADOR:
        if proyecto.coordinador_principal_id != ctx.usuario.id:
            raise HTTPException(404, "Ítem no encontrado.")
        return item

    if ctx.rol == Rol.RESIDENTE:
        if membresia is None:
            raise HTTPException(404, "Ítem no encontrado.")
        return item

    # TRABAJADOR — (a) gana sobre membresía; luego (b) vs (c).
    if item.asignado_a == ctx.usuario.id:
        return item
    if membresia is not None:
        raise HTTPException(403, "Este ítem no está asignado a usted.")
    raise HTTPException(404, "Ítem no encontrado.")


# ── Scope helpers (CTT-78) ────────────────────────────────────────────────────
# Ambas funciones expresan la misma regla de visibilidad por rol.
# Si se modifica una, actualizar la otra en paralelo.

def scope_orm(q, ctx: AuthContext):
    """Aplica filtro de visibilidad a un query ORM ya filtrado por empresa_id."""
    if ctx.es_super_admin or ctx.rol == Rol.ADMIN:
        return q
    if ctx.rol == Rol.COORDINADOR:
        return q.filter(Proyecto.coordinador_principal_id == ctx.usuario.id)
    return (
        q.join(ProyectoUsuario, ProyectoUsuario.proyecto_id == Proyecto.id)
        .filter(
            ProyectoUsuario.usuario_id == ctx.usuario.id,
            ProyectoUsuario.estado == UsuarioEstado.ACTIVO,
        )
    )


def scope_sql(ctx: AuthContext) -> tuple[str, dict]:
    """Retorna (cláusula_extra, params_extra) para añadir al WHERE del dashboard SQL.

    Expresa la misma regla que scope_orm — siempre actualizarlas en paralelo.
    """
    if ctx.es_super_admin or ctx.rol == Rol.ADMIN:
        return "", {}
    if ctx.rol == Rol.COORDINADOR:
        return (
            "\nAND p.coordinador_principal_id = :scope_uid",
            {"scope_uid": ctx.usuario.id},
        )
    return (
        "\nAND EXISTS ("
        "SELECT 1 FROM proyecto_usuarios pu "
        "WHERE pu.proyecto_id = p.id "
        "AND pu.usuario_id = :scope_uid "
        "AND pu.estado = 'activo'"
        ")",
        {"scope_uid": ctx.usuario.id},
    )


def _ids_proyectos_visibles(db: Session, ctx: AuthContext) -> set[str] | None:
    """IDs de proyectos visibles para el usuario según su rol; None = todos.

    Usar solo donde no es posible expresar el scope como filtro ORM directo
    (actualmente: filtro sobre AuditLog, que no tiene FK a Proyecto).
    Para listing de proyectos usar scope_orm; para el dashboard usar scope_sql.

    Deuda (CTT-96): las tres implementaciones de este módulo expresan la
    misma regla de visibilidad. Unificarlas requeriría materializar IDs en
    rutas de listing (un roundtrip extra de BD) y generar SQL IN dinámico
    en el dashboard — trade-off no vale la pena hoy. Si se agrega un 4.º
    lugar, evaluar de nuevo.
    """
    if ctx.es_super_admin or ctx.rol == Rol.ADMIN:
        return None
    empresa_id = requiere_empresa(ctx)
    if ctx.rol == Rol.COORDINADOR:
        return set(
            db.scalars(
                select(Proyecto.id).where(
                    Proyecto.empresa_id == empresa_id,
                    Proyecto.coordinador_principal_id == ctx.usuario.id,
                )
            ).all()
        )
    # RESIDENTE / TRABAJADOR: visibilidad por membresía activa en proyecto_usuarios.
    return set(
        db.scalars(
            select(ProyectoUsuario.proyecto_id)
            .join(Proyecto, ProyectoUsuario.proyecto_id == Proyecto.id)
            .where(
                Proyecto.empresa_id == empresa_id,
                ProyectoUsuario.usuario_id == ctx.usuario.id,
                ProyectoUsuario.estado == UsuarioEstado.ACTIVO,
            )
        ).all()
    )
