"""
routers/audit.py — GET /audit-log (CTT-48).

Devuelve el log operativo de la empresa activa. Solo Coordinador y Admin
(ver_audit_log en la matriz de permisos).

Filtros opcionales:
  ?proyecto_id=  — entradas de ese proyecto
  ?entidad_tipo= — "item", "proyecto", etc.
  ?entidad_id=   — historial de una entidad puntual (combinable con entidad_tipo)

Paginación:
  ?limit=50      — máx 200 por llamada (default 50)
  ?offset=0      — desplazamiento
"""

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.auth import AuthContext, get_current_context, requiere_empresa
from app.database import get_db
from app.models import AuditLog
from app.permissions import puede
from app.schemas import AuditLogOut

router = APIRouter(prefix="/audit-log", tags=["Audit log"])


@router.get("", response_model=list[AuditLogOut])
def listar_audit_log(
    proyecto_id: str | None = Query(default=None),
    entidad_tipo: str | None = Query(default=None),
    entidad_id: str | None = Query(default=None),
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
    ctx: AuthContext = Depends(get_current_context),
    db: Session = Depends(get_db),
):
    """Log operativo de la empresa. Coordinador y Admin solamente.

    Orden: más reciente primero (created_at DESC).
    """
    empresa_id = requiere_empresa(ctx)
    if not puede(ctx.rol, "ver_audit_log"):
        raise HTTPException(403, "Su rol no tiene acceso al audit log.")

    q = db.query(AuditLog).filter(AuditLog.empresa_id == empresa_id)

    if proyecto_id is not None:
        q = q.filter(AuditLog.proyecto_id == proyecto_id)
    if entidad_tipo is not None:
        q = q.filter(AuditLog.entidad_tipo == entidad_tipo)
    if entidad_id is not None:
        q = q.filter(AuditLog.entidad_id == entidad_id)

    entradas = (
        q.order_by(AuditLog.created_at.desc())
        .offset(offset)
        .limit(limit)
        .all()
    )
    return [
        AuditLogOut(
            id=e.id,
            folio=e.folio,
            empresa_id=e.empresa_id,
            actor_id=e.actor_id,
            actor_nombre=e.actor_nombre,
            actor_rol=e.actor_rol,
            accion=e.accion,
            entidad_tipo=e.entidad_tipo,
            entidad_id=e.entidad_id,
            proyecto_id=e.proyecto_id,
            diff=e.diff,
            detalle=e.detalle,
            device_ts=e.device_ts,
            synced_offline=e.synced_offline,
            created_at=e.created_at,
        )
        for e in entradas
    ]
