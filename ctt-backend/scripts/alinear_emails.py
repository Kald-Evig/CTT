"""
alinear_emails.py — Renombra emails en Firebase Auth para alinearlos con la BD.

Los usuarios "huérfanos" existen en Firebase bajo un email diferente al que
registra la BD. Este script renombra el email en Firebase preservando el uid.
La BD no necesita cambios porque el uid permanece igual.

Pares a renombrar (operación única CTT-86):
    trabajador@ctt.cl  →  luis@andessur.cl
    ctt@ctt.cl         →  soporte@ctt.cl

Uso:
    python scripts/alinear_emails.py            # DRY-RUN: verifica y muestra qué haría
    python scripts/alinear_emails.py --aplicar  # Ejecuta los renombres en Firebase
"""

import os
import sys
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FuturesTimeout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import firebase_admin
from firebase_admin import auth, credentials

from app.database import SessionLocal
from app.models import Usuario

FIREBASE_TIMEOUT = 10

RENOMBRES = [
    ("trabajador@ctt.cl", "luis@andessur.cl"),
    ("ctt@ctt.cl",        "soporte@ctt.cl"),
]


def inicializar_firebase():
    if not firebase_admin._apps:
        key_path = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")
        if not key_path:
            sys.exit("ERROR: GOOGLE_APPLICATION_CREDENTIALS no está seteada.")
        firebase_admin.initialize_app(credentials.Certificate(key_path))


def _get_user_by_email_safe(email: str):
    """Llama auth.get_user_by_email con timeout. Retorna (UserRecord|None, estado)."""
    with ThreadPoolExecutor(max_workers=1) as ex:
        future = ex.submit(auth.get_user_by_email, email)
        try:
            return future.result(timeout=FIREBASE_TIMEOUT), "ok"
        except FuturesTimeout:
            return None, "timeout"
        except auth.UserNotFoundError:
            return None, "no_existe"
        except Exception as exc:
            return None, f"error:{exc}"


def verificar_par(email_viejo: str, email_nuevo: str, db) -> tuple[str | None, list[str]]:
    """
    Verifica que el par es seguro para renombrar. Retorna (uid, errores).
    Si errores no está vacío, no ejecutar el renombre.
    """
    errores = []

    # 1. email_viejo debe existir en Firebase.
    fb_viejo, estado = _get_user_by_email_safe(email_viejo)
    if estado != "ok":
        errores.append(
            f"STOP: '{email_viejo}' no existe en Firebase ({estado}) — nada que renombrar"
        )
        return None, errores
    uid = fb_viejo.uid
    print(f"  Firebase '{email_viejo}' → uid={uid}  ✓ existe", flush=True)

    # 2. email_nuevo NO debe existir en Firebase (evitar conflicto de email duplicado).
    fb_nuevo, estado_nuevo = _get_user_by_email_safe(email_nuevo)
    if estado_nuevo == "ok":
        errores.append(
            f"STOP: '{email_nuevo}' ya existe en Firebase con uid={fb_nuevo.uid} — "
            "renombrar causaría conflicto de email duplicado"
        )
        return uid, errores
    if estado_nuevo not in ("no_existe",):
        errores.append(
            f"STOP: error al verificar '{email_nuevo}' en Firebase ({estado_nuevo})"
        )
        return uid, errores
    print(f"  Firebase '{email_nuevo}' → no existe  ✓ sin conflicto", flush=True)

    # 3. email_nuevo debe existir en la BD y su firebase_uid debe coincidir con uid.
    usuario = db.query(Usuario).filter(Usuario.email == email_nuevo).first()
    if usuario is None:
        errores.append(
            f"STOP: '{email_nuevo}' no existe en la tabla usuarios — "
            "no hay fila a alinear"
        )
        return uid, errores
    if usuario.firebase_uid != uid:
        errores.append(
            f"STOP: usuarios.firebase_uid para '{email_nuevo}' es '{usuario.firebase_uid}', "
            f"pero la cuenta Firebase tiene uid='{uid}' — "
            "el renombre no resolvería el desajuste"
        )
        return uid, errores
    print(f"  BD '{email_nuevo}' → firebase_uid={usuario.firebase_uid}  ✓ coincide con uid", flush=True)

    return uid, []


def _obtener_uid_firebase(email: str) -> tuple[str | None, str]:
    fb_user, estado = _get_user_by_email_safe(email)
    if estado == "ok":
        return fb_user.uid, "ok"
    return None, estado


def _clasificar(uid_base: str, uid_firebase: str | None, estado_fb: str) -> str:
    if estado_fb == "no_existe":
        return "HUÉRFANO EN BASE"
    if estado_fb in ("timeout",) or estado_fb.startswith("error"):
        return f"ERROR ({estado_fb})"
    if uid_base == uid_firebase:
        return "SANO"
    return "DESAJUSTADO"


def diagnostico_post(db):
    """Imprime la tabla de reconciliación después de aplicar los renombres."""
    usuarios = db.query(Usuario).order_by(Usuario.email).all()
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
        uid_fb, estado_fb = _obtener_uid_firebase(u.email)
        estado = _clasificar(u.firebase_uid, uid_fb, estado_fb)
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
    print(
        f"Total: {len(usuarios)}  |  "
        f"SANOS: {conteo['SANO']}  |  "
        f"DESAJUSTADOS: {conteo['DESAJUSTADO']}  |  "
        f"HUÉRFANOS: {conteo['HUÉRFANO EN BASE']}  |  "
        f"ERRORES: {conteo['ERROR']}",
        flush=True,
    )


def main():
    aplicar = "--aplicar" in sys.argv

    inicializar_firebase()
    db = SessionLocal()
    try:
        planes: list[tuple[str, str, str]] = []
        hay_bloqueo = False

        for email_viejo, email_nuevo in RENOMBRES:
            print(
                f"\n── '{email_viejo}' → '{email_nuevo}' "
                + "─" * max(0, 60 - len(email_viejo) - len(email_nuevo)),
                flush=True,
            )
            uid, errores = verificar_par(email_viejo, email_nuevo, db)
            if errores:
                for e in errores:
                    print(f"  {e}", flush=True)
                hay_bloqueo = True
            else:
                planes.append((email_viejo, email_nuevo, uid))
                print("  → listo para renombrar", flush=True)

        print(flush=True)

        if hay_bloqueo:
            print("BLOQUEADO: uno o más pares tienen errores. No se ejecuta nada.", flush=True)
            sys.exit(1)

        if not aplicar:
            print("=== DRY-RUN — nada será modificado ===\n", flush=True)
            for email_viejo, email_nuevo, uid in planes:
                print(
                    f"  auth.update_user('{uid}', email='{email_nuevo}')"
                    f"  # '{email_viejo}' → '{email_nuevo}'",
                    flush=True,
                )
            print(
                "\nDRY-RUN. Nada modificado. "
                "Para aplicar: python scripts/alinear_emails.py --aplicar",
                flush=True,
            )
            return

        # --- APLICAR ---
        print("=== APLICAR ===\n", flush=True)
        for email_viejo, email_nuevo, uid in planes:
            try:
                auth.update_user(uid, email=email_nuevo)
                print(f"  OK  '{email_viejo}' → '{email_nuevo}'  (uid={uid})", flush=True)
            except Exception as exc:
                print(f"  ERROR '{email_viejo}': {exc}", flush=True)

        print(
            "\n── Diagnóstico post-reparación ─────────────────────────────────────",
            flush=True,
        )
        diagnostico_post(db)

    finally:
        db.close()


if __name__ == "__main__":
    main()
