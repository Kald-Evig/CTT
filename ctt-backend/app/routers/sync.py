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

from app.audit import record_audit
from app.auth import (
    AuthContext,
    actor_de,
    exigir_permiso,
    get_current_context,
    requiere_empresa,
)
from app.authz import scope_orm
from app.database import get_db
from app.enums import ConflictoEstado, ItemEstado, ProblemaEstado
from app.models import Item, ItemComentario, ItemProblema, Proyecto, SyncConflicto
from app.schemas import ConflictoMioOut, ConflictoResolverIn

router = APIRouter(prefix="/sync", tags=["Sincronización"])


def _conflicto_dict(c) -> dict:
    """Campos comunes de un SyncConflicto para las respuestas de sync.

    Cada endpoint agrega su extra: created_at en el listado, version_ganadora
    en la resolución.
    """
    return {
        "id": c.id,
        "item_id": c.item_id,
        "cambio_local": c.cambio_local,
        "cambio_servidor": c.cambio_servidor,
        "dispositivo_id": c.dispositivo_id,
        "estado": c.estado.value,
        "resuelto_por": c.resuelto_por,
        "resuelto_at": c.resuelto_at,
    }


@router.get("/conflictos")
def listar_conflictos(
    estado: str | None = None,
    ctx: AuthContext = Depends(get_current_context),
    db: Session = Depends(get_db),
):
    """Lista conflictos de la empresa activa, filtrables por estado (Coordinador/Admin).

    Si no se especifica ?estado=, devuelve solo los PENDIENTES (comportamiento
    original, para no romper clientes existentes).
    """
    empresa_id = requiere_empresa(ctx)
    exigir_permiso(
        ctx, "resolver_conflictos_sync", "Su rol no puede ver/resolver conflictos."
    )

    if estado is not None:
        try:
            filtro_estado = ConflictoEstado(estado)
        except ValueError:
            valores = [e.value for e in ConflictoEstado]
            raise HTTPException(422, f"Estado inválido: '{estado}'. Valores válidos: {valores}")
    else:
        filtro_estado = ConflictoEstado.PENDIENTE

    q = (
        db.query(SyncConflicto)
        .join(Item, SyncConflicto.item_id == Item.id)
        .join(Proyecto, Item.proyecto_id == Proyecto.id)
        .filter(
            Proyecto.empresa_id == empresa_id,
            SyncConflicto.estado == filtro_estado,
        )
    )
    conflictos = scope_orm(q, ctx).all()
    return [
        {**_conflicto_dict(c), "created_at": c.created_at} for c in conflictos
    ]


@router.get("/conflictos/mios", response_model=list[ConflictoMioOut])
def listar_conflictos_mios(
    ctx: AuthContext = Depends(get_current_context),
    db: Session = Depends(get_db),
):
    """[TEMPORAL — CTT-117] Conflictos RESUELTOS originados por el usuario del token.

    Una sola regla de autorización: estado == RESUELTO y usuario_id == sujeto del
    token. Sin ramas por rol — cualquier rol autenticado ve únicamente los suyos.
    Permite al dispositivo saber qué versión ganó y reconciliar su cola local
    (sync_pendientes).

    Se retira cuando se implemente CTT-104 (version_id_col / If-Match), que hará
    innecesario este canal de reconciliación por pull.
    """
    return (
        db.query(SyncConflicto)
        .filter(
            SyncConflicto.usuario_id == ctx.usuario.id,
            SyncConflicto.estado == ConflictoEstado.RESUELTO,
        )
        .order_by(SyncConflicto.resuelto_at.desc())
        .all()
    )


@router.post("/conflictos/{conflicto_id}/resolver")
def resolver_conflicto(
    conflicto_id: str,
    body: ConflictoResolverIn,
    ctx: AuthContext = Depends(get_current_context),
    db: Session = Depends(get_db),
):
    """Resuelve un conflicto eligiendo la versión local o la del servidor.

    Si gana 'local', se aplica el estado de cambio_local al ítem y se preserva
    el comentario (Fix A). Si gana 'servidor', el ítem no se modifica. En ambos
    casos se cierran problemas huérfanos (Fix B) y el conflicto queda resuelto.
    """
    empresa_id = requiere_empresa(ctx)
    exigir_permiso(
        ctx, "resolver_conflictos_sync", "Su rol no puede resolver conflictos."
    )

    q = (
        db.query(SyncConflicto)
        .join(Item, SyncConflicto.item_id == Item.id)
        .join(Proyecto, Item.proyecto_id == Proyecto.id)
        .filter(SyncConflicto.id == conflicto_id, Proyecto.empresa_id == empresa_id)
    )
    conflicto = scope_orm(q, ctx).first()
    if conflicto is None:
        raise HTTPException(404, "Conflicto no encontrado.")
    if conflicto.estado == ConflictoEstado.RESUELTO:
        raise HTTPException(409, "El conflicto ya fue resuelto.")

    item = db.query(Item).filter(Item.id == conflicto.item_id).first()

    if body.version_ganadora == "local":
        # Fix C — antes de aplicar la versión local, verificar que el estado del
        # servidor no cambió desde que se registró el conflicto. Si cambió, el
        # Coordinador estaría decidiendo sobre información desactualizada y puede
        # pisar un cambio posterior legítimo.
        estado_servidor_capturado = (conflicto.cambio_servidor or {}).get("estado")
        if estado_servidor_capturado and item.estado.value != estado_servidor_capturado:
            raise HTTPException(
                status_code=409,
                detail=(
                    f"El ítem cambió de estado desde que se registró este conflicto "
                    f"(capturado: '{estado_servidor_capturado}', actual: '{item.estado.value}'). "
                    "Refresca la cola de conflictos antes de reintentar."
                ),
            )

        nuevo_estado_str = (conflicto.cambio_local or {}).get("estado")
        if nuevo_estado_str:
            item.estado = ItemEstado(nuevo_estado_str)

        # Fix A — preservar comentario del cambio local en item_comentarios con
        # prefijo que lo identifique como proveniente de una resolución de conflicto.
        comentario_local = (conflicto.cambio_local or {}).get("comentario")
        if comentario_local:
            db.add(ItemComentario(
                item_id=conflicto.item_id,
                usuario_id=ctx.usuario.id,
                texto=f"[Resolución de conflicto de sync] {comentario_local}",
            ))

    # Fix B — cerrar problemas abiertos si el estado final del item no es PROBLEMA.
    # Si version_ganadora == "servidor", item.estado ya es el estado definitivo
    # (no se modificó). Si fue "local", item.estado ya refleja el nuevo estado.
    if item.estado != ItemEstado.PROBLEMA:
        ahora = datetime.now(timezone.utc)
        problemas_abiertos = (
            db.query(ItemProblema)
            .filter(
                ItemProblema.item_id == conflicto.item_id,
                ItemProblema.estado == ProblemaEstado.ABIERTO,
            )
            .all()
        )
        for problema in problemas_abiertos:
            problema.estado = ProblemaEstado.CERRADO
            problema.cerrado_por = ctx.usuario.id
            problema.cerrado_at = ahora

    conflicto.estado = ConflictoEstado.RESUELTO
    conflicto.resuelto_por = ctx.usuario.id
    conflicto.resuelto_at = datetime.now(timezone.utc)
    conflicto.version_ganadora = body.version_ganadora

    # Audit de la resolución (CTT-117 tramo 3). Misma transacción que la resolución:
    # record_audit hace db.add, no commit; el db.commit() de abajo es el único.
    # Se audita SIEMPRE, no solo el descarte (auditar solo los descartes sesga el
    # log). El desenlace vive en meta (accion es una sola para poder filtrar todas
    # las resoluciones sin conocer las variantes). Se lee version_ganadora de la
    # COLUMNA ya asignada (el hecho), no de body (la intención). Dos actores: quien
    # resolvió (Coordinador, actor_de) y de quién era el cambio en disputa
    # (trabajador + dispositivo, en meta para que sea consultable). El diff solo
    # existe cuando ganó local, que es el único desenlace que cambia item.estado.
    gano_local = conflicto.version_ganadora == "local"
    record_audit(
        db,
        empresa_id=empresa_id,
        **actor_de(ctx),
        accion="resolucion_conflicto",
        entidad_tipo="item",
        entidad_id=conflicto.item_id,
        proyecto_id=item.proyecto_id,
        diff={
            "estado": [
                (conflicto.cambio_servidor or {}).get("estado"),
                (conflicto.cambio_local or {}).get("estado"),
            ]
        }
        if gano_local
        else None,
        detalle=f"Conflicto {conflicto.id}: ganó {conflicto.version_ganadora}.",
        metadata={
            "conflicto_id": conflicto.id,
            "version_ganadora": conflicto.version_ganadora,
            "trabajador_afectado_id": conflicto.usuario_id,
            "dispositivo_afectado_id": conflicto.dispositivo_id,
        },
    )
    db.commit()

    return {
        **_conflicto_dict(conflicto),
        "version_ganadora": body.version_ganadora,
    }
