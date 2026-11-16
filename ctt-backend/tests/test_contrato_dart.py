"""test_contrato_dart.py — El contrato Dart generado está sincronizado con el backend.

Regenera el contenido en memoria (scripts/generar_contrato_dart.py) y lo compara con
el archivo versionado. Si difiere, falla con el comando para regenerar: así un cambio
en state_machine.py sin regenerar el contrato rompe la suite.

Comparación del CONTENIDO normalizando los finales de línea: el repo usa
core.autocrlf=true, así que el working tree puede tener CRLF aunque el generador emita
LF. Lo que importa es que el texto coincida con la fuente de verdad.
"""

import sys
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parent.parent
SCRIPTS_DIR = BACKEND_DIR / "scripts"
CONTRATO = (
    BACKEND_DIR.parent
    / "ctt-mobile"
    / "lib"
    / "domain"
    / "enums"
    / "maquina_estados_generada.dart"
)

sys.path.insert(0, str(SCRIPTS_DIR))
import generar_contrato_dart as gen  # noqa: E402

_REGEN = "python ctt-backend/scripts/generar_contrato_dart.py"


def test_contrato_dart_sincronizado():
    esperado = gen.generar_contenido().replace("\r\n", "\n")
    actual = CONTRATO.read_text(encoding="utf-8").replace("\r\n", "\n")
    assert actual == esperado, (
        "El contrato Dart (maquina_estados_generada.dart) está DESINCRONIZADO con "
        f"state_machine.py. Regenéralo con:\n    {_REGEN}"
    )


def test_contrato_no_sale_de_problema_ni_terminado():
    # El generador falla si alguna transición saliera de PROBLEMA/TERMINADO (R1/R3).
    # Aquí confirmamos que hoy NO lanza (las reglas están bien).
    gen._validar_r1_r3()
