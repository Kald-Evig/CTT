"""
routers/notificaciones.py — Notificaciones in-app del usuario (Sección 9.1).

El badge con contador y la lista de notificaciones del MVP se alimentan de aquí.
"""

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.auth import AuthContext, get_current_context
from app.database import get_db
from app.models import Notificacion
from app.schemas import NotificacionOut

router = APIRouter(prefix="/notificaciones", tags=["Notificaciones"])


@router.get("", response_model=list[NotificacionOut])
def mis_notificaciones(
    ctx: AuthContext = Depends(get_current_context),
    db: Session = Depends(get_db),
):
    """Lista las notificaciones del usuario actual (más recientes primero)."""
    return (
        db.query(Notificacion)
        .filter(Notificacion.usuario_id == ctx.usuario.id)
        .order_by(Notificacion.created_at.desc())
        .all()
    )


@router.post("/{notif_id}/leer")
def marcar_leida(
    notif_id: str,
    ctx: AuthContext = Depends(get_current_context),
    db: Session = Depends(get_db),
):
    """Marca una notificación propia como leída."""
    notif = (
        db.query(Notificacion)
        .filter(Notificacion.id == notif_id,
                Notificacion.usuario_id == ctx.usuario.id)
        .first()
    )
    if notif is None:
        raise HTTPException(404, "Notificación no encontrada.")
    notif.leida = True
    db.commit()
    return {"id": notif.id, "leida": True}
