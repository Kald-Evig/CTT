/// acciones_permitidas.dart — Decide qué acciones de TRANSICIÓN ofrece la UI a partir
/// del contrato generado del backend (`domain/enums/maquina_estados_generada.dart`).
///
/// Fuente única: la máquina de estados del backend (`state_machine.py`), volcada al
/// contrato por `ctt-backend/scripts/generar_contrato_dart.py`. La UI NO decide reglas
/// por su cuenta: pide las acciones a esta función y solo elige el texto/ícono.
///
/// NO cubre comentar/adjuntar ni asignar: no son transiciones de la máquina de estados.
library;

import 'package:ctt_mobile/domain/enums/enums_ctt.dart';
import 'package:ctt_mobile/domain/enums/maquina_estados_generada.dart';

// Reexporta el enum del contrato para que los consumidores de accionesPermitidas
// (p. ej. las pantallas) puedan comparar contra AccionEspecial.cerrarProblema sin
// importar el archivo generado directamente.
export 'package:ctt_mobile/domain/enums/maquina_estados_generada.dart'
    show AccionEspecial;

/// Una acción ofrecible en la UI: una transición a [AccionTransicion.hacia] o una
/// acción especial (cerrar problema / revertir terminado).
sealed class AccionItem {
  const AccionItem();
}

/// Transición de estado permitida desde el estado actual hacia [hacia].
class AccionTransicion extends AccionItem {
  const AccionTransicion({
    required this.hacia,
    required this.requiereComentario,
    required this.requiereDescripcionProblema,
  });

  final EstadoItem hacia;
  final bool requiereComentario;
  final bool requiereDescripcionProblema;
}

/// Acción especial (fuera de la tabla de transiciones).
class AccionEspecialItem extends AccionItem {
  const AccionEspecialItem(this.accion);
  final AccionEspecial accion;
}

/// Acciones que [rol] puede ejecutar sobre un ítem en [estadoMostrado], según el
/// contrato generado del backend. [esAsignado] solo habilita las transiciones que
/// requieren asignación (hoy ABIERTO→EN_PROGRESO del Trabajador). El orden respeta
/// `kTransicionesContrato` (orden de `state_machine.TRANSICIONES`) y luego las
/// acciones especiales.
List<AccionItem> accionesPermitidas(
  EstadoItem estadoMostrado,
  RolUsuario rol, {
  required bool esAsignado,
}) {
  final acciones = <AccionItem>[];
  for (final t in kTransicionesContrato) {
    if (t.desde != estadoMostrado) continue;
    if (!t.roles.contains(rol)) continue;
    if (t.requiereAsignacion && !esAsignado) continue;
    acciones.add(AccionTransicion(
      hacia: t.hacia,
      requiereComentario: t.requiereComentario,
      requiereDescripcionProblema: t.requiereDescripcionProblema,
    ),);
  }
  for (final a in kAccionesEspecialesContrato) {
    if (a.estadoOrigen != estadoMostrado) continue;
    if (!a.roles.contains(rol)) continue;
    acciones.add(AccionEspecialItem(a.accion));
  }
  return acciones;
}
