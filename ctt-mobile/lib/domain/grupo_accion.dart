/// grupo_accion.dart — Grupo de acción de un ítem en "Mis ítems" (CTT-162).
///
/// El grupo se DERIVA de [accionesPermitidas] (contrato generado del backend, CTT-153),
/// NO de un CASE en SQL: cuando CTT-159 cambie los roles, el grupo los sigue sin una
/// segunda fuente que mantener. Función PURA y con tipos primitivos (no importa de `data/`):
/// el ordenamiento sobre `ItemConOverlay` vive en el provider (opción A, CTT-162 §G1).
///
/// El conflicto abierto (C4c) NO cambia el grupo: una transición del Trabajador parte del
/// estado base y deja el conflicto en SUPERADO (items.py:781-790), así que el ítem queda en
/// el grupo que le toca por su estado. El chip "En revisión por el Coordinador" lo pinta la
/// lista aparte, sin tocar el grupo.
library;

import 'package:ctt_mobile/domain/acciones_permitidas.dart';
import 'package:ctt_mobile/domain/enums/enums_ctt.dart';

/// Los tres grupos de "Mis ítems", EN ORDEN de presentación (el `.index` da el orden).
enum GrupoAccion {
  /// Hay al menos una acción permitida para el rol (hoy: abierto, en_progreso).
  leTocaAlTrabajador,

  /// Sin acciones y no terminado (hoy: pendiente_revision, problema).
  esperaAOtros,

  /// Estado terminado.
  terminadosRecientes,
}

/// Etiqueta de usuario del encabezado de grupo. Fuente ÚNICA (español neutro).
extension GrupoAccionEtiqueta on GrupoAccion {
  String get etiqueta => switch (this) {
        GrupoAccion.leTocaAlTrabajador => 'Le toca a ti',
        GrupoAccion.esperaAOtros => 'Esperando a otros',
        GrupoAccion.terminadosRecientes => 'Terminados recientes',
      };
}

/// Grupo de un ítem según su [estadoMostrado]. Depende SOLO de [accionesPermitidas] y de si
/// el estado es terminado (CTT-162): el conflicto no entra acá.
GrupoAccion grupoAccion(
  EstadoItem estadoMostrado, {
  required RolUsuario rol,
  required bool esAsignado,
}) {
  if (estadoMostrado == EstadoItem.terminado) {
    return GrupoAccion.terminadosRecientes;
  }
  return accionesPermitidas(estadoMostrado, rol, esAsignado: esAsignado).isEmpty
      ? GrupoAccion.esperaAOtros
      : GrupoAccion.leTocaAlTrabajador;
}
