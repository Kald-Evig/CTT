/// mensajes.dart — Mensajería efímera para la UI.
library;

import 'package:flutter/material.dart';

/// Muestra un SnackBar con [texto], descartando los previos.
///
/// Cubre el caso común "limpiar y mostrar un mensaje simple". Los SnackBar con
/// acción u opciones propias (color, duración) se construyen a mano en su sitio.
void mostrarMensaje(BuildContext context, String texto) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(texto)));
}
