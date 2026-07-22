"""
logging_middleware.py — Middleware de logging HTTP para depuración en desarrollo.

SEGURIDAD — reglas del proyecto (nunca violar):
  - Authorization se loguea siempre como "Bearer [REDACTED]", nunca el token real.
  - Los campos firebase_uid, rut y password del body se enmascaran antes de escribir.

ACTIVACIÓN — solo cuando LOG_REQUESTS=true en settings (default en AUTH_MODE=mock).
Para desactivar en producción: LOG_REQUESTS=false en las variables de entorno.

Archivos de salida (ignorados por git):
  logs/ctt_dev.log    — requests y responses (INFO+)
  logs/ctt_errors.log — errores con stack trace completo (ERROR+)
"""

import json
import logging
import time
from logging.handlers import RotatingFileHandler
from pathlib import Path

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response

_CAMPOS_SENSIBLES = frozenset({
    "firebase_uid", "rut", "password", "token", "uid",
    # Campos que pueden aparecer en responses de auth (reset link, OOB codes).
    # Un reset_link en un log es una credencial filtrada.
    "authorization", "jwt", "cookie", "oobCode", "oob_code", "reset_link", "link",
})
_LIMITE_BODY = 800  # caracteres máximos del body redactado en el log


def _redactar_auth(valor: str) -> str:
    if valor.lower().startswith("bearer "):
        return "Bearer [REDACTED]"
    return "[REDACTED]"


def _redactar_body(raw: bytes) -> str:
    try:
        data = json.loads(raw)
        if isinstance(data, dict):
            redactado = {
                k: "[REDACTED]" if k in _CAMPOS_SENSIBLES else v
                for k, v in data.items()
            }
            texto = json.dumps(redactado, ensure_ascii=False)
        else:
            texto = raw.decode("utf-8", errors="replace")
    except (json.JSONDecodeError, UnicodeDecodeError):
        texto = "<no-JSON>"
    return texto[:_LIMITE_BODY]


class LoggingMiddleware(BaseHTTPMiddleware):
    def __init__(
        self,
        app,
        log_requests: logging.Logger,
        log_errors: logging.Logger,
    ) -> None:
        super().__init__(app)
        self._req = log_requests
        self._err = log_errors

    async def dispatch(self, request: Request, call_next) -> Response:
        inicio = time.perf_counter()
        auth = request.headers.get("authorization", "")
        auth_log = _redactar_auth(auth) if auth else "-"
        content_type = request.headers.get("content-type", "")

        # Loguear body solo en mutaciones JSON (Starlette cachea el resultado).
        body_log = ""
        if request.method in ("POST", "PUT", "PATCH") and "application/json" in content_type:
            try:
                raw = await request.body()
                if raw:
                    body_log = f" body={_redactar_body(raw)}"
            except Exception:
                body_log = " body=<error-lectura>"

        try:
            response = await call_next(request)
        except Exception:
            ms = (time.perf_counter() - inicio) * 1000
            self._err.exception(
                "EXCEPCIÓN no capturada | %s %s (%.0f ms) auth=%s",
                request.method,
                request.url.path,
                ms,
                auth_log,
            )
            raise

        ms = (time.perf_counter() - inicio) * 1000
        nivel = logging.WARNING if response.status_code >= 400 else logging.INFO
        self._req.log(
            nivel,
            "%s %s → %d (%.0f ms) auth=%s%s",
            request.method,
            request.url.path,
            response.status_code,
            ms,
            auth_log,
            body_log,
        )

        if response.status_code >= 500:
            self._err.error(
                "HTTP %d | %s %s",
                response.status_code,
                request.method,
                request.url.path,
            )

        return response


def configurar_logging(ruta_logs: Path) -> tuple[logging.Logger, logging.Logger]:
    """Crea la carpeta logs/ e inicializa los dos loggers de archivo."""
    ruta_logs.mkdir(parents=True, exist_ok=True)

    fmt = logging.Formatter(
        "%(asctime)s %(levelname)-8s %(message)s",
        datefmt="%Y-%m-%dT%H:%M:%S",
    )

    def _handler(archivo: Path, nivel: int) -> RotatingFileHandler:
        h = RotatingFileHandler(
            archivo,
            maxBytes=5 * 1024 * 1024,  # 5 MB por archivo
            backupCount=3,
            encoding="utf-8",
        )
        h.setLevel(nivel)
        h.setFormatter(fmt)
        return h

    log_req = logging.getLogger("ctt.requests")
    log_req.setLevel(logging.INFO)
    if not log_req.handlers:
        log_req.addHandler(_handler(ruta_logs / "ctt_dev.log", logging.INFO))
    log_req.propagate = False

    log_err = logging.getLogger("ctt.errors")
    log_err.setLevel(logging.ERROR)
    if not log_err.handlers:
        log_err.addHandler(_handler(ruta_logs / "ctt_errors.log", logging.ERROR))
    log_err.propagate = False

    return log_req, log_err
