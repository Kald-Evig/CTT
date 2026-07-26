"""
reparar_uids.py — Reparación de firebase_uid desajustados en la tabla usuarios.

Uso:
    python reparar_uids.py            # DRY-RUN: muestra qué se haría, no modifica nada
    python reparar_uids.py --aplicar  # Ejecuta los UPDATE y confirma con diagnóstico final

Solo repara DESAJUSTADOS (email existe en Firebase, uid en base es incorrecto).
Los HUÉRFANOS (email no existe en Firebase) solo se reportan, no se tocan.
Los SANOS no se tocan.

Requiere GOOGLE_APPLICATION_CREDENTIALS seteada apuntando al service account JSON.
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

FIREBASE_TIMEOUT = 10


def inicializar_firebase():
    if not firebase_admin._apps:
        key_path = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")
        if not key_path:
            sys.exit("ERROR: GOOGLE_APPLICATION_CREDENTIALS no está seteada.")
        cred = credentials.Certificate(key_path)
        firebase_admin.initialize_app(cred)


def obtener_uid_firebase(email: str) -> tuple[str | None, str]:
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


def diagnosticar(usuarios: list) -> list[dict]:
    """Clasifica cada usuario consultando Firebase. Retorna lista de dicts con el mapa."""
    resultado = []
    for u in usuarios:
        uid_fb, estado_fb = obtener_uid_firebase(u.email)
        estado = clasificar(u.firebase_uid, uid_fb, estado_fb)
        resultado.append({
            "email": u.email,
            "uid_base": u.firebase_uid,
            "uid_firebase": uid_fb,
            "estado_fb": estado_fb,
            "estado": estado,
        })
    return resultado


def imprimir_tabla(filas: list[dict]):
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

    for f in filas:
        coincide = "SI" if f["estado"] == "SANO" else "NO"
        uid_fb_display = f["uid_firebase"] if f["uid_firebase"] else f"({f['estado_fb']})"
        print(" | ".join([
            f["email"].ljust(COL[0]),
            f["uid_base"].ljust(COL[1]),
            uid_fb_display.ljust(COL[2]),
            coincide.ljust(COL[3]),
            f["estado"].ljust(COL[4]),
        ]), flush=True)
        clave = f["estado"] if f["estado"] in conteo else "ERROR"
        conteo[clave] += 1

    print()
    print(
        f"Total: {len(filas)}  |  "
        f"SANOS: {conteo['SANO']}  |  "
        f"DESAJUSTADOS: {conteo['DESAJUSTADO']}  |  "
        f"HUÉRFANOS: {conteo['HUÉRFANO EN BASE']}  |  "
        f"ERRORES: {conteo['ERROR']}",
        flush=True,
    )


def fase_dry_run(filas: list[dict]):
    print("\n=== DRY-RUN — nada será modificado ===\n", flush=True)

    desajustados = [f for f in filas if f["estado"] == "DESAJUSTADO"]
    huerfanos    = [f for f in filas if f["estado"] == "HUÉRFANO EN BASE"]

    if desajustados:
        print("── UPDATES que se ejecutarían ──────────────────────────────────────")
        for f in desajustados:
            print(
                f"UPDATE usuarios SET firebase_uid='{f['uid_firebase']}' "
                f"WHERE email='{f['email']}'"
                f"  -- viejo: {f['uid_base']}",
                flush=True,
            )
    else:
        print("No hay DESAJUSTADOS. Nada que reparar.")

    if huerfanos:
        print("\n── HUÉRFANOS — NO se reparan (email no existe en Firebase) ────────")
        for f in huerfanos:
            sugerencia = ""
            if "soporte@ctt.cl" in f["email"]:
                sugerencia = " (¿está registrado como otro email, p.ej. ctt@ctt.cl?)"
            print(
                f"ADVERTENCIA: {f['email']} → uid en base: '{f['uid_base']}'"
                f" — sin cuenta Firebase para ese email.{sugerencia}",
                flush=True,
            )

    print(
        "\nDRY-RUN. Nada modificado. "
        "Para aplicar: python reparar_uids.py --aplicar",
        flush=True,
    )


def fase_aplicar(filas: list[dict]):
    print("\n=== APLICAR ===\n", flush=True)

    desajustados = [f for f in filas if f["estado"] == "DESAJUSTADO"]

    if not desajustados:
        print("No hay DESAJUSTADOS. Nada que reparar.", flush=True)
        return

    for f in desajustados:
        email = f["email"]

        # Verificar de nuevo que Firebase todavía tiene ese email antes de tocar la BD.
        uid_verificado, estado_verificado = obtener_uid_firebase(email)
        if uid_verificado is None:
            print(
                f"SKIP {email}: no se pudo verificar uid en Firebase "
                f"({estado_verificado}). Fila no modificada.",
                flush=True,
            )
            continue

        db = SessionLocal()
        try:
            usuario = db.query(Usuario).filter(Usuario.email == email).first()
            if usuario is None:
                print(f"SKIP {email}: no encontrado en la BD.", flush=True)
                continue

            uid_viejo = usuario.firebase_uid
            usuario.firebase_uid = uid_verificado
            db.commit()
            print(
                f"OK  {email}: firebase_uid actualizado "
                f"'{uid_viejo}' → '{uid_verificado}'",
                flush=True,
            )
        except Exception as exc:
            db.rollback()
            print(f"ERROR {email}: {exc}", flush=True)
        finally:
            db.close()

    # Diagnóstico final para confirmar que quedaron SANOS.
    print("\n── Diagnóstico post-reparación ─────────────────────────────────────", flush=True)
    db = SessionLocal()
    try:
        usuarios = db.query(Usuario).order_by(Usuario.email).all()
    finally:
        db.close()

    filas_post = diagnosticar(usuarios)
    imprimir_tabla(filas_post)


def main():
    aplicar = "--aplicar" in sys.argv

    inicializar_firebase()

    db = SessionLocal()
    try:
        usuarios = db.query(Usuario).order_by(Usuario.email).all()
    finally:
        db.close()

    if not usuarios:
        print("No hay usuarios en la base de datos.")
        sys.exit(0)

    print("Consultando Firebase para cada email...", flush=True)
    filas = diagnosticar(usuarios)
    imprimir_tabla(filas)

    if aplicar:
        fase_aplicar(filas)
    else:
        fase_dry_run(filas)


if __name__ == "__main__":
    main()
