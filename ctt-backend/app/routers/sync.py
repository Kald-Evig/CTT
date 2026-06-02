"""
routers/sync.py — Conflictos de sincronización (Sección 8).

El backend NO resuelve conflictos automáticamente: los encola y un
Coordinador/Admin elige la versión ganadora (Sección 8.4). Este router expone
la cola pendiente y la resolución manual.

Nota: la INGESTA de cambios offline (el endpoint que recibe la cola del
dispositivo y detecta el conflicto comparando device_timestamp vs server_timestamp)
es lógica de cliente+servidor que requiere el SyncService de Flutter; aquí se
modela la cola y la resolución, que es la parte que vive 100% en el backend.
"""

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.auth import AuthContext, get_current_context, requiere_empresa
from app.database import get_db
from app.enums import ConflictoEstado, ItemEstado
from app.models import Item, Proyecto, SyncConflicto
from app.permissions import puede
from app.schemas import ConflictoResolverIn

router = APIRouter(prefix="/sync", tags=["Sincronización"])


@router.get("/conflictos")
def listar_conflictos(
    ctx: AuthContext = Depends(get_current_context),
    db: Session = Depends(get_db),
):
    """Lista los conflictos PENDIENTES de la empresa activa (Coordinador/Admin)."""
    empresa_id = requiere_empresa(ctx)
    if not puede(ctx.rol, "resolver_conflictos_sync"):
        raise HTTPException(403, "Su rol no puede ver/resolver conflictos.")
    conflictos = (
        db.query(SyncConflicto)
        .join(Item, SyncConflicto.item_id == Item.id)
        .join(Proyecto, Item.proyecto_id == Proyecto.id)
        .filter(Proyecto.empresa_id == empresa_id,
                SyncConflicto.estado == ConflictoEstado.PENDIENTE)
        .all()
    )
    return [
        {
            "id": c.id,
            "item_id": c.item_id,
            "cambio_local": c.cambio_local,
            "cambio_servidor": c.cambio_servidor,
            "dispositivo_id": c.dispositivo_id,
            "created_at": c.created_at,
        }
        for c in conflictos
    ]


@router.post("/conflictos/{conflicto_id}/resolver")
def resolver_conflicto(
    conflicto_id: str,
    body: ConflictoResolverIn,
    ctx: AuthContext = Depends(get_current_context),
    db: Session = Depends(get_db),
):
    """Resuelve un conflicto eligiendo la versión local o la del servidor.

    Si gana 'local', se aplica el estado del cambio local al ítem; si gana
    'servidor', se descarta el cambio local. En ambos casos el conflicto queda
    marcado como resuelto.
    """
    empresa_id = requiere_empresa(ctx)
    if not puede(ctx.rol, "resolver_conflictos_sync"):
        raise HTTPException(403, "Su rol no puede resolver conflictos.")

    conflicto = (
        db.query(SyncConflicto)
        .join(Item, SyncConflicto.item_id == Item.id)
        .join(Proyecto, Item.proyecto_id == Proyecto.id)
        .filter(SyncConflicto.id == conflicto_id, Proyecto.empresa_id == empresa_id)
        .first()
    )
    if conflicto is None:
        raise HTTPException(404, "Conflicto no encontrado.")
    if conflicto.estado == ConflictoEstado.RESUELTO:
        raise HTTPException(409, "El conflicto ya fue resuelto.")

    if body.version_ganadora == "local":
        item = db.query(Item).filter(Item.id == conflicto.item_id).first()
        nuevo_estado = (conflicto.cambio_local or {}).get("estado")
        if item and nuevo_estado:
            # Aplicación directa de la decisión humana (omite la máquina de
            # estados a propósito: es una resolución administrativa de conflicto).
            item.estado = ItemEstado(nuevo_estado)

    conflicto.estado = ConflictoEstado.RESUELTO
    conflicto.resuelto_por = ctx.usuario.id
    conflicto.resuelto_at = datetime.now(timezone.utc)
    db.commit()
    return {"id": conflicto.id, "estado": conflicto.estado.value,
            "version_ganadora": body.version_ganadora}
