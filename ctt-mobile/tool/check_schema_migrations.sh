#!/usr/bin/env bash
# check_schema_migrations.sh — CTT-130 fase 7 (chequeo manual; NO hay CI en el repo).
#
# Verifica que el esquema exportado (drift_schemas/) y los tests de migración
# (test/drift/) estén al día con las tablas Drift: corre make-migrations y falla si
# quedó algo sin exportar/commitear. Es el guard que impide cambiar una tabla sin
# regenerar el esquema.
#
# Uso (desde ctt-mobile/):
#   bash tool/check_schema_migrations.sh
#
# Cuando exista un pipeline de CI (ticket aparte), este mismo comando es el paso a
# agregar. Arrancar CI no es parte de CTT-130.
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> dart run drift_dev make-migrations"
dart run drift_dev make-migrations

echo "==> git diff --exit-code sobre drift_schemas/ y test/drift/"
if ! git diff --exit-code -- drift_schemas/ test/drift/; then
  echo ""
  echo "ERROR: el esquema exportado o los tests de migración están desactualizados."
  echo "Cambiaste una tabla Drift sin regenerar el esquema. Corré:"
  echo "    dart run drift_dev make-migrations"
  echo "y commiteá los cambios en drift_schemas/ y test/drift/."
  exit 1
fi

echo "OK: drift_schemas/ y test/drift/ están al día."
