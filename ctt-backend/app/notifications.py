"""
notifications.py — Disparo de notificaciones (Sección 9 del DDT).

In-app: siempre se crea una fila en `notificaciones`.
Email: en este prototipo se MARCA como enviado sin llamar a SendGrid (no hay
credenciales en demo). En producción, reemplazar `_enviar_email` por la llamada
real a la API de SendGrid (free tier 100 emails/día, Sección 9.1).

Los eventos que disparan notificación están en la tabla de la Sección 9.2.
"""

from sqlalchemy.orm import Session

from app.models import Notificacion


def _enviar_email(destinatario_email: str, titulo: str, cuerpo: str) -> bool:
    """Stub de envío de email. Devuelve True simulando éxito.

    PRODUCCIÓN: integrar SendGrid aquí. Mantener la firma para no tocar llamadores.
    """
    return True  # mock


def notificar(
    db: Session,
    *,
    empresa_id: str,
    usuario_id: str,
    evento: str,
    titulo: str,
    cuerpo: str | None = None,
    enviar_email: bool = True,
    email_destino: str | None = None,
) -> Notificacion:
    """Crea una notificación in-app y, opcionalmente, dispara el email.

    No hace commit: el llamador controla la transacción.
    """
    email_ok = False
    if enviar_email and email_destino:
        email_ok = _enviar_email(email_destino, titulo, cuerpo or "")

    notif = Notificacion(
        empresa_id=empresa_id,
        usuario_id=usuario_id,
        evento=evento,
        titulo=titulo,
        cuerpo=cuerpo,
        email_enviado=email_ok,
    )
    db.add(notif)
    return notif
