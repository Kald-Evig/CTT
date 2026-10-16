/// mensajes.dart — Mensajería efímera para la UI.
library;

import 'package:flutter/material.dart';

import 'package:ctt_mobile/data/local/daos/sync_dao.dart' show ResultadoEspera;
import 'package:ctt_mobile/domain/enums/enums_ctt.dart';

/// Muestra un SnackBar con [texto], descartando los previos.
///
/// Cubre el caso común "limpiar y mostrar un mensaje simple". Los SnackBar con
/// acción u opciones propias (color, duración) se construyen a mano en su sitio.
void mostrarMensaje(BuildContext context, String texto) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(texto)));
}

/// Frase para el usuario según el resultado de la espera por fila (CTT-148). Fuente
/// única del fraseo; la comparten el detalle del Trabajador y el del Residente. [exito]
/// personaliza el mensaje de éxito por acción (p. ej. "Ítem rechazado.").
String mensajeDeResultadoEspera(
  ResultadoEspera r, {
  String exito = 'Cambio aplicado.',
}) =>
    switch (r.estado) {
      EstadoSyncLocal.sincronizado => exito,
      EstadoSyncLocal.rechazada =>
        r.ultimoError ?? 'El servidor rechazó el cambio.',
      EstadoSyncLocal.esperandoResolucion =>
        'Hay un conflicto que un coordinador debe resolver.',
      EstadoSyncLocal.pendiente when r.ultimoErrorCodigo != null =>
        'No se pudo enviar (código ${r.ultimoErrorCodigo}); se reintentará.',
      // pendiente sin código, enviando, en_revision, descartado → quedó encolado.
      _ => 'Se encoló el cambio; se enviará cuando haya conexión.',
    };
