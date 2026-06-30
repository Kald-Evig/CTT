"""
audit.py — Registro operativo de acciones (CTT-48).

`record_audit()` escribe una fila en `audit_log` dentro de la sesión activa del
request. NO hace commit: el endpoint que lo llama es dueño del commit. Esto
garantiza que la entrada de auditoría y el cambio de negocio son atómicos — si el
commit falla, ninguno persiste.

Uso típico (en un endpoint):

    record_audit(db, empresa_id=empresa_id, actor_id=ctx.usuario.id, ...)
    db.commit()          # ← una sola transacción
"""

from datetime import date, datetime

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models import AuditLog


def a_serializable(v: object) -> object:
    """Convierte date a str ISO para el diff de auditoría (JSON no serializa date nativamente)."""
    if isinstance(v, date):
        return v.isoformat()
    return v


def record_audit(
    db: Session,
    *,
    empresa_id: str,
    actor_id: str | None,
    actor_nombre: str,
    actor_rol: str,
    accion: str,
    entidad_tipo: str,
    entidad_id: str,
    proyecto_id: str | None = None,
    diff: dict | None = None,
    detalle: str | None = None,
    metadata: dict | None = None,
    device_ts: datetime | None = None,
    synced_offline: bool = False,
) -> AuditLog:
    """Registra una acción en el audit_log operativo.

    Parámetros clave:
    - actor_nombre / actor_rol: denormalizados — sobreviven si el usuario cambia o
      se desactiva. Pasar ctx.usuario.nombre_completo y ctx.rol.value directamente.
    - diff: {campo: [valor_anterior, valor_nuevo]}. Para cambios de estado:
      {"estado": ["abierto", "en_progreso"]}.
    - metadata: datos extras libres (device_id, versión de app, etc).
    - device_ts: timestamp del dispositivo offline; None si la acción fue online.
    - synced_offline: True si el cambio vino de la cola de sincronización offline.
    """
    entry = AuditLog(
        empresa_id=empresa_id,
        actor_id=actor_id,
        actor_nombre=actor_nombre,
        actor_rol=actor_rol,
        accion=accion,
        entidad_tipo=entidad_tipo,
        entidad_id=entidad_id,
        proyecto_id=proyecto_id,
        diff=diff,
        detalle=detalle,
        meta=metadata,
        folio=_next_folio(db, empresa_id),
        device_ts=device_ts,
        synced_offline=synced_offline,
    )
    db.add(entry)
    return entry


def _next_folio(db: Session, empresa_id: str) -> int:
    """Correlativo monotónico por empresa usando MAX(folio) + 1.

    CONCURRENCIA — el punto que tiene más chances de salir mal:

    SQLite (dev): safe. SQLite serializa escrituras a nivel de archivo; dos
    requests no pueden ejecutar este SELECT simultáneamente dentro del mismo
    writer lock. MAX+1 es siempre correcto en este entorno.

    Postgres (prod): race condition real. Si dos requests de la misma empresa
    calculan MAX antes de que cualquiera haga commit, ambos obtienen el mismo
    número y uno de los commits fallará con IntegrityError por el constraint
    UNIQUE(empresa_id, folio). Ese error es detectable y reportable.

    Solución para producción (CTT-49 / Alembic):
      OPCIÓN A — advisory lock:
        db.execute(text("SELECT pg_advisory_xact_lock(hashtext(:eid))"), {"eid": empresa_id})
        ... entonces MAX+1 es safe dentro de la transacción.
      OPCIÓN B — secuencia Postgres por empresa (más limpio, require DDL).
      La UNIQUE(empresa_id, folio) existente detecta colisiones hasta que se implemente.
    """
    current_max = db.scalar(
        select(func.max(AuditLog.folio)).where(AuditLog.empresa_id == empresa_id)
    )
    return (current_max or 0) + 1
