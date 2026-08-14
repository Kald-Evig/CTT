"""
idempotency_middleware.py — Idempotencia de mutaciones (CTT-105).

Si el request trae `Idempotency-Key` y es POST, reserva la clave por empresa
(UNIQUE(empresa_id, idempotency_key) hace de toma atómica, equivalente a
`INSERT ... ON CONFLICT DO NOTHING`) y:

  - reserva nueva      -> ejecuta el endpoint. 2xx persiste status_code + body y
                          marca `completado` (replay futuro); no-2xx borra la
                          reserva (el cliente puede reintentar).
  - reserva existente  -> fingerprint distinto: 422. Completada + mismo
                          fingerprint: replay del body guardado con header
                          `Idempotent-Replayed: true`. En proceso: 409.

Genérico: no conoce ningún endpoint. No usa Depends(get_db) (no es endpoint):
abre su propia SessionLocal y la cierra en un finally.
"""

import hashlib
import json

from sqlalchemy import func
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy.exc import IntegrityError
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse, Response

from app.database import SessionLocal
from app.enums import IdempotenciaEstado
from app.models import ClaveIdempotencia, MetricaIdempotencia


class IdempotencyMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next) -> Response:
        clave = request.headers.get("idempotency-key")
        if not clave or request.method != "POST":
            return await call_next(request)

        empresa_id = request.headers.get("x-empresa-id")
        if not empresa_id:
            # La Depends de auth ya rechaza el request; el middleware no la duplica.
            return await call_next(request)

        raw = await request.body()
        fingerprint = hashlib.sha256(raw).hexdigest()

        session = SessionLocal()
        try:
            # ── Reserva atómica: el UNIQUE(empresa_id, idempotency_key) garantiza
            #    que solo una reserva concurrente gane; las demás dan IntegrityError.
            reserva = ClaveIdempotencia(
                empresa_id=empresa_id,
                idempotency_key=clave,
                endpoint=request.url.path,
                fingerprint=fingerprint,
                estado=IdempotenciaEstado.EN_PROCESO,
            )
            session.add(reserva)
            try:
                session.commit()
                reservada = True
            except IntegrityError:
                session.rollback()
                reservada = False

            if reservada:
                try:
                    response = await call_next(request)
                except Exception:
                    # Excepción no capturada: borrar la reserva y re-lanzar. Una
                    # reserva huérfana en `en_proceso` bloquearía al cliente para siempre.
                    session.delete(reserva)
                    session.commit()
                    raise

                cuerpo = b"".join([chunk async for chunk in response.body_iterator])

                if 200 <= response.status_code < 300:
                    reserva.status_code = response.status_code
                    reserva.response_body = json.loads(cuerpo) if cuerpo else None
                    reserva.estado = IdempotenciaEstado.COMPLETADO
                    session.commit()
                else:
                    # Respuesta no definitiva: liberar la reserva para permitir reintento.
                    session.delete(reserva)
                    session.commit()

                # body_iterator ya se consumió: reconstruir la respuesta idéntica.
                return Response(
                    content=cuerpo,
                    status_code=response.status_code,
                    headers=dict(response.headers),
                    media_type=response.media_type,
                )

            # ── Reserva falló: ya existe una fila para (empresa, clave). ────────
            existente = (
                session.query(ClaveIdempotencia)
                .filter_by(empresa_id=empresa_id, idempotency_key=clave)
                .one()
            )
            if existente.fingerprint != fingerprint:
                return JSONResponse(
                    status_code=422,
                    content={
                        "detail": "La clave de idempotencia ya se usó con un contenido distinto."
                    },
                )
            if existente.estado == IdempotenciaEstado.COMPLETADO:
                # Contador diario de replays (CTT-105 Parte 2): UPSERT sobre la
                # misma session ya abierta, un commit dentro del try. El insert
                # se elige por dialecto: Postgres en producción, SQLite en la
                # suite de tests; ambos soportan ON CONFLICT DO UPDATE.
                insert = (
                    sqlite_insert
                    if session.bind.dialect.name == "sqlite"
                    else pg_insert
                )
                session.execute(
                    insert(MetricaIdempotencia)
                    .values(fecha=func.current_date(), replays=1)
                    .on_conflict_do_update(
                        index_elements=["fecha"],
                        set_={"replays": MetricaIdempotencia.replays + 1},
                    )
                )
                session.commit()
                return JSONResponse(
                    status_code=existente.status_code,
                    content=existente.response_body,
                    headers={"Idempotent-Replayed": "true"},
                )
            # En proceso, mismo fingerprint: hay un request en vuelo con esta clave.
            return JSONResponse(
                status_code=409,
                content={
                    "detail": "Ya hay una solicitud en proceso con esta clave de idempotencia."
                },
            )
        finally:
            session.close()
