"""
normalizar_estados.py — Normaliza columnas 'estado' que quedaron en MAYÚSCULA
por haber sido insertadas antes de que existiera el wrapper SAEnum (models.py).

SQLite no enforcea tipos ENUM, así que un INSERT con 'EN_PROGRESO' no falla en
BD pero revienta al leer con SQLAlchemy (LookupError). Este script corrige todos
los valores mixtos/uppercase a su equivalente en lower() en las tablas afectadas.

Uso:
    python scripts/normalizar_estados.py                   # usa ctt_dev.db
    python scripts/normalizar_estados.py otra_bd.db        # BD arbitraria
    DATABASE_URL=sqlite:///ruta.db python scripts/normalizar_estados.py

Idempotente: correr múltiples veces no cambia nada si la BD ya está limpia.
"""

import sqlite3
import sys
import os
from pathlib import Path

# ── Resolver ruta de la BD ────────────────────────────────────────────────────

def _resolver_db() -> str:
    # 1. Argumento posicional: python normalizar_estados.py mi.db
    if len(sys.argv) > 1:
        return sys.argv[1]

    # 2. Variable de entorno DATABASE_URL (sqlite:///ruta o ruta directa)
    url = os.environ.get("DATABASE_URL", "")
    if url.startswith("sqlite:///"):
        return url[len("sqlite:///"):]
    if url and not url.startswith("sqlite"):
        return url

    # 3. Default: ctt_dev.db junto al directorio raíz del proyecto
    script_dir = Path(__file__).resolve().parent          # …/scripts/
    project_root = script_dir.parent                      # …/ctt-backend/
    return str(project_root / "ctt_dev.db")


# ── Tablas y columnas a normalizar ────────────────────────────────────────────

TABLAS = [
    "items",
    "item_problemas",
    "proyectos",
    "sync_conflictos",
]

# ── Core ──────────────────────────────────────────────────────────────────────

def normalizar(db_path: str) -> None:
    if not Path(db_path).exists():
        print(f"ERROR: BD no encontrada: {db_path}")
        sys.exit(1)

    print(f"BD: {db_path}")
    print()

    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    total = 0

    for tabla in TABLAS:
        # Verificar que la tabla y columna existen
        cur.execute(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
            (tabla,),
        )
        if not cur.fetchone():
            print(f"  {tabla:20s} — tabla no existe, omitida")
            continue

        cur.execute(f"PRAGMA table_info({tabla})")
        cols = {row[1] for row in cur.fetchall()}
        if "estado" not in cols:
            print(f"  {tabla:20s} — sin columna 'estado', omitida")
            continue

        # Contar filas afectadas antes de tocarlas
        cur.execute(
            f"SELECT COUNT(*) FROM {tabla} WHERE estado != lower(estado)"
        )
        n = cur.fetchone()[0]

        if n > 0:
            cur.execute(
                f"UPDATE {tabla} SET estado = lower(estado) "
                f"WHERE estado != lower(estado)"
            )
            print(f"  {tabla:20s} — {n} fila(s) normalizadas")
        else:
            print(f"  {tabla:20s} — 0 filas afectadas (ya limpia)")

        total += n

    conn.commit()
    conn.close()

    print()
    print(f"Total filas normalizadas: {total}")
    if total == 0:
        print("La BD ya estaba limpia — nada que hacer.")


if __name__ == "__main__":
    normalizar(_resolver_db())
