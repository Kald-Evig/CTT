#!/usr/bin/env bash
# run.sh — Levanta el backend de CTT en local (demo/UAT).
#
# Uso:
#   ./run.sh            # instala deps (si faltan), siembra datos y arranca la API
#   ./run.sh --no-seed  # arranca sin re-sembrar (conserva ctt_dev.db existente)
#
# Requisitos: Python 3.11+ (probado en 3.12).

set -euo pipefail
cd "$(dirname "$0")"

# 1) Dependencias (idempotente).
echo "→ Instalando dependencias..."
pip install -q -r requirements.txt --break-system-packages

# 2) Datos de demo (a menos que se pida lo contrario).
if [[ "${1:-}" != "--no-seed" ]]; then
  echo "→ Sembrando datos de demo (ctt_dev.db)..."
  python -m app.seed
fi

# 3) Servidor.
echo "→ Iniciando API en http://127.0.0.1:8000  (Swagger en /docs)"
exec uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
