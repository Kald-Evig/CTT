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

from datetime import datetime

from sqlalchemy.orm import Session

from app.clock import get_now
from app.enums import ItemEstado
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
    now: datetime | None = None,
) -> int:
    """Materializa el bump de `version` y escribe una fila de `item_historial`.

    Devuelve la `version` resultante (posterior a la escritura). El llamador ya
    mutó el `item` (estado/asignado/campos) o lo acaba de crear; aquí solo se
    flushea para que version_id_col asigne la versión y se registra el evento.
    """
    # CTT-161: un SOLO instante para toda esta escritura (el reloj inyectable get_now() que el
    # endpoint resuelve y pasa; fallback al mismo reloj si no se pasó). Se usa para sellar
    # terminado_en Y para el created_at de la fila de historial, de modo que el invariante
    # "terminado_en == created_at del evento hacia terminado" se cumpla también en RUNTIME (no
    # solo tras el backfill). Es naive UTC, consistente con el round-trip del DateTime sin tz.
    instante = now if now is not None else get_now()
    # Este helper es también el ÚNICO que mantiene items.terminado_en. Al ENTRAR a TERMINADO lo
    # sella con [instante]; al SALIR lo limpia a NULL. Escribe SOLO cuando el valor cambia de
    # verdad (no toca una creación ni una transición entre estados no-terminales): así no
    # re-ensucia el ítem ni provoca un segundo bump de version. Las escrituras SIN cambio de
    # estado (edicion_datos, asignacion → estado_nuevo=None) tampoco lo tocan. Por eso las rutas
    # de transición llaman a este helper ANTES de record_audit: el sello de terminado_en viaja
    # en el MISMO UPDATE que el estado (un solo bump de version, invariante de CTT-143).
    if estado_nuevo == ItemEstado.TERMINADO.value:
        if item.terminado_en is None:
            item.terminado_en = instante
    elif estado_nuevo is not None and item.terminado_en is not None:
        item.terminado_en = None
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
            # CTT-161: el MISMO instante que terminado_en (no el default aware _now() de la
            # columna), para que terminado_en == created_at del evento hacia terminado.
            created_at=instante,
        )
    )
    return nueva_version
