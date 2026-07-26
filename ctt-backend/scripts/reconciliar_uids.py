"""
reconciliar_uids.py — Diagnóstico de solo lectura: compara firebase_uid en la BD
contra el uid real de Firebase para cada email.

Uso:
    (activar venv)
    python reconciliar_uids.py

Requiere GOOGLE_APPLICATION_CREDENTIALS seteada apuntando al service account JSON.
NO modifica ningún dato.
"""

import os
import sys
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FuturesTimeout
from pathlib import Path

# Permite correr desde scripts/ sin PYTHONPATH=.. explícito.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import firebase_admin
from firebase_admin import auth, credentials

from app.database import SessionLocal
from app.models import Usuario

FIREBASE_TIMEOUT = 10  # segundos por llamada


def inicializar_firebase():
    if not firebase_admin._apps:
        key_path = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")
        if not key_path:
            sys.exit("ERROR: GOOGLE_APPLICATION_CREDENTIALS no está seteada.")
        cred = credentials.Certificate(key_path)
        firebase_admin.initialize_app(cred)


def obtener_uid_firebase(email: str) -> tuple[str | None, str]:
    """
    Retorna (uid_real, estado):
      "ok"        -> encontrado
      "no_existe" -> email no existe en Firebase
      "timeout"   -> la llamada superó FIREBASE_TIMEOUT segundos
      "error:..."  -> error inesperado
    """
    with ThreadPoolExecutor(max_workers=1) as executor:
        future = executor.submit(auth.get_user_by_email, email)
        try:
            user = future.result(timeout=FIREBASE_TIMEOUT)
            return user.uid, "ok"
        except FuturesTimeout:
            return None, "timeout"
        except auth.UserNotFoundError:
            return None, "no_existe"
        except Exception as exc:
            return None, f"error:{exc}"


def clasificar(uid_base: str, uid_firebase: str | None, estado_fb: str) -> str:
    if estado_fb == "no_existe":
        return "HUÉRFANO EN BASE"
    if estado_fb in ("timeout",) or estado_fb.startswith("error"):
        return f"ERROR ({estado_fb})"
    if uid_base == uid_firebase:
        return "SANO"
    return "DESAJUSTADO"


def main():
    inicializar_firebase()

    db = SessionLocal()
    try:
        usuarios = db.query(Usuario).order_by(Usuario.email).all()
    finally:
        db.close()

    if not usuarios:
        print("No hay usuarios en la base de datos.")
        sys.exit(0)

    COL = [46, 30, 30, 9, 18]
    sep = "-+-".join("-" * c for c in COL)
    header = " | ".join([
        "EMAIL".ljust(COL[0]),
        "UID EN BASE".ljust(COL[1]),
        "UID EN FIREBASE".ljust(COL[2]),
        "COINCIDE".ljust(COL[3]),
        "ESTADO".ljust(COL[4]),
    ])

    print()
    print(header, flush=True)
    print(sep, flush=True)

    conteo = {"SANO": 0, "DESAJUSTADO": 0, "HUÉRFANO EN BASE": 0, "ERROR": 0}

    for u in usuarios:
        uid_fb, estado_fb = obtener_uid_firebase(u.email)
        estado = clasificar(u.firebase_uid, uid_fb, estado_fb)
        coincide = "SI" if estado == "SANO" else "NO"
        uid_fb_display = uid_fb if uid_fb else f"({estado_fb})"

        print(" | ".join([
            u.email.ljust(COL[0]),
            u.firebase_uid.ljust(COL[1]),
            uid_fb_display.ljust(COL[2]),
            coincide.ljust(COL[3]),
            estado.ljust(COL[4]),
        ]), flush=True)

        clave = estado if estado in conteo else "ERROR"
        conteo[clave] += 1

    print()
    print(f"Total: {len(usuarios)}  |  "
          f"SANOS: {conteo['SANO']}  |  "
          f"DESAJUSTADOS: {conteo['DESAJUSTADO']}  |  "
          f"HUÉRFANOS: {conteo['HUÉRFANO EN BASE']}  |  "
          f"ERRORES: {conteo['ERROR']}", flush=True)


if __name__ == "__main__":
    main()
