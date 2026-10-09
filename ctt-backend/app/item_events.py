"""
item_events.py — Registro único de escrituras de ítem (CTT-143 A' / D1).

`registrar_escritura_item()` es el ÚNICO lugar que escribe `item_historial`. Toda
ruta que modifica un `Item` lo llama DESPUÉS de mutar el objeto: hace `flush`
(version_id_col sube `items.version` sobre el ítem sucio), lee la `version`
resultante y escribe EXACTAMENTE una fila de historial con esa `version` + el
`actor_rol` denormalizado (P1/P2).

NO incrementa `version` a mano (la gestiona version_id_col del ORM) y NO hace
commit: el endpoint es dueño de la transacción, igual que `record_audit`
(audit.py). Así el historial, el audit y el cambio de negocio quedan atómicos.
"""

from sqlalchemy.orm import Session

from app.models import Item, ItemHistorial


def registrar_escritura_item(
    db: Session,
    item: Item,
    *,
    accion: str,
    usuario_id: str | None,
    actor_rol: str | None,
    estado_anterior: str | None = None,
    estado_nuevo: str | None = None,
    diff: dict | None = None,
    detalle: str | None = None,
    dispositivo_id: str | None = None,
    idempotency_key: str | None = None,
) -> int:
    """Materializa el bump de `version` y escribe una fila de `item_historial`.

    Devuelve la `version` resultante (posterior a la escritura). El llamador ya
    mutó el `item` (estado/asignado/campos) o lo acaba de crear; aquí solo se
    flushea para que version_id_col asigne la versión y se registra el evento.
    """
    # Flush: version_id_col asigna/incrementa items.version sobre el ítem ya mutado
    # (o lo inserta, con version=1, si es nuevo). Recién ahí item.version es el valor
    # POSTERIOR a esta escritura. Un flush previo de record_audit no vuelve a subirla:
    # el ítem ya no está sucio, así que el bump ocurre una sola vez por request.
    db.flush()
    nueva_version = item.version
    db.add(
        ItemHistorial(
            item_id=item.id,
            usuario_id=usuario_id,
            accion=accion,
            estado_anterior=estado_anterior,
            estado_nuevo=estado_nuevo,
            detalle=detalle,
            version=nueva_version,
            diff=diff,
            dispositivo_id=dispositivo_id,
            idempotency_key=idempotency_key,
            actor_rol=actor_rol,
        )
    )
    return nueva_version
