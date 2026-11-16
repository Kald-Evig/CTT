"""generar_contrato_dart.py — Generador code-first del contrato de la máquina de estados.

Fuente ÚNICA: app/state_machine.py (TRANSICIONES + ROLES_CERRAR_PROBLEMA +
ROLES_REVERTIR_TERMINADO) y app/enums.py. Escribe un archivo Dart que el cliente
consume para decidir qué transiciones ofrecer, de modo que no haya dos tablas a mano.

Uso (desde la raíz del repo):
    python ctt-backend/scripts/generar_contrato_dart.py

Solo stdlib. La salida es determinista, con finales de línea LF y UTF-8, y queda tal
cual la dejaría `dart format` (lo verifica un test). Un test de pytest
(tests/test_contrato_dart.py) regenera el contenido en memoria y lo compara byte a
byte con el archivo versionado.
"""

import os
import sys
from pathlib import Path

# Rutas (el script vive en ctt-backend/scripts/).
BACKEND_DIR = Path(__file__).resolve().parent.parent
REPO_ROOT = BACKEND_DIR.parent
SALIDA = REPO_ROOT / "ctt-mobile" / "lib" / "domain" / "enums" / "maquina_estados_generada.dart"

# Evita cualquier conexión real a la BD al importar la app (como hace conftest):
# create_engine es perezoso, pero fijamos un sqlite para no depender de Postgres.
os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")
sys.path.insert(0, str(BACKEND_DIR))

from app.enums import ItemEstado, Rol  # noqa: E402
from app.state_machine import (  # noqa: E402
    ROLES_CERRAR_PROBLEMA,
    ROLES_REVERTIR_TERMINADO,
    TRANSICIONES,
)

# Orden canónico y determinista para los roles (orden de definición del enum backend).
_ORDEN_ROL = {rol: i for i, rol in enumerate(Rol)}

# Preludio FIJO (comentarios + tipos). Sin \n inicial/final: los separadores en blanco
# los pone generar_contenido(). Formato ya "dart format"-limpio.
CABECERA = (
    "// GENERADO por ctt-backend/scripts/generar_contrato_dart.py — NO EDITAR.\n"
    "// Regenerar con: python ctt-backend/scripts/generar_contrato_dart.py\n"
    "//\n"
    "// Contrato (code-first) de la máquina de estados de ítems. Fuente única:\n"
    "// ctt-backend/app/state_machine.py (TRANSICIONES + acciones especiales). Un cambio\n"
    "// de reglas se REGENERA; no se edita a mano. Un test de pytest compara este archivo\n"
    "// byte a byte con la salida del generador.\n"
    "library;\n"
    "\n"
    "import 'package:ctt_mobile/domain/enums/enums_ctt.dart';"
)

TIPOS = """/// Acción especial fuera de la tabla de transiciones.
enum AccionEspecial { cerrarProblema, revertirTerminado }

/// Una transición permitida (espejo de state_machine.TRANSICIONES).
class TransicionContrato {
  const TransicionContrato({
    required this.desde,
    required this.hacia,
    required this.roles,
    this.requiereAsignacion = false,
    this.requiereComentario = false,
    this.requiereDescripcionProblema = false,
  });

  final EstadoItem desde;
  final EstadoItem hacia;
  final Set<RolUsuario> roles;
  final bool requiereAsignacion;
  final bool requiereComentario;
  final bool requiereDescripcionProblema;
}

/// Una acción especial con su estado de origen y roles.
class AccionEspecialContrato {
  const AccionEspecialContrato({
    required this.accion,
    required this.estadoOrigen,
    required this.roles,
  });

  final AccionEspecial accion;
  final EstadoItem estadoOrigen;
  final Set<RolUsuario> roles;
}"""


def _camel(snake: str) -> str:
    partes = snake.split("_")
    return partes[0] + "".join(p.capitalize() for p in partes[1:])


def _dart_estado(e: ItemEstado) -> str:
    return f"EstadoItem.{_camel(e.value)}"


def _dart_rol(r: Rol) -> str:
    return f"RolUsuario.{_camel(r.value)}"


def _dart_roles(roles) -> str:
    ordenados = sorted(roles, key=lambda r: _ORDEN_ROL[r])
    return "{" + ", ".join(_dart_rol(r) for r in ordenados) + "}"


def _validar_r1_r3() -> None:
    """R1/R3: ninguna transición de tabla puede salir de PROBLEMA ni de TERMINADO
    (son guards en transicionar(), no entradas de tabla). Si alguna lo hiciera, el
    cliente la ofrecería. Falla con mensaje claro."""
    invalidas = [
        t for t in TRANSICIONES
        if t.desde in (ItemEstado.PROBLEMA, ItemEstado.TERMINADO)
    ]
    if invalidas:
        detalle = ", ".join(f"{t.desde.value}->{t.hacia.value}" for t in invalidas)
        raise SystemExit(
            "ERROR: hay transiciones que salen de PROBLEMA/TERMINADO en "
            f"state_machine.TRANSICIONES ({detalle}). R1/R3 son guards; el cliente "
            "las ofrecería. Corrige state_machine.py antes de regenerar."
        )


def generar_contenido() -> str:
    """Devuelve el contenido Dart del contrato (determinista, LF, UTF-8)."""
    _validar_r1_r3()

    out: list[str] = [CABECERA, "", TIPOS, ""]
    out.append("/// Transiciones permitidas, en el orden de state_machine.TRANSICIONES.")
    out.append("const List<TransicionContrato> kTransicionesContrato = [")
    for t in TRANSICIONES:
        out.append("  TransicionContrato(")
        out.append(f"    desde: {_dart_estado(t.desde)},")
        out.append(f"    hacia: {_dart_estado(t.hacia)},")
        out.append(f"    roles: {_dart_roles(t.roles)},")
        if t.requiere_asignacion:
            out.append("    requiereAsignacion: true,")
        if t.requiere_comentario:
            out.append("    requiereComentario: true,")
        if t.requiere_descripcion_problema:
            out.append("    requiereDescripcionProblema: true,")
        out.append("  ),")
    out.append("];")

    especiales = [
        ("AccionEspecial.cerrarProblema", ItemEstado.PROBLEMA, ROLES_CERRAR_PROBLEMA),
        ("AccionEspecial.revertirTerminado", ItemEstado.TERMINADO, ROLES_REVERTIR_TERMINADO),
    ]
    out.append("")
    out.append("/// Acciones especiales (cerrar problema, revertir terminado).")
    out.append("const List<AccionEspecialContrato> kAccionesEspecialesContrato = [")
    for accion, origen, roles in especiales:
        out.append("  AccionEspecialContrato(")
        out.append(f"    accion: {accion},")
        out.append(f"    estadoOrigen: {_dart_estado(origen)},")
        out.append(f"    roles: {_dart_roles(roles)},")
        out.append("  ),")
    out.append("];")

    return "\n".join(out) + "\n"


def main() -> None:
    contenido = generar_contenido()
    SALIDA.parent.mkdir(parents=True, exist_ok=True)
    with open(SALIDA, "w", encoding="utf-8", newline="\n") as f:
        f.write(contenido)
    print(f"Escrito {SALIDA} ({len(contenido)} bytes).")


if __name__ == "__main__":
    main()
