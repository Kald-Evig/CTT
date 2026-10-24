library;

import 'package:flutter/material.dart';

import 'package:ctt_mobile/presentation/shared/chip_estado.dart';

/// Pastilla del estado de un ítem. Conserva solo el mapeo estado→(label, color) y
/// delega el render en [ChipEstado] (pastilla compartida); su aspecto no cambia.
class BadgeEstadoItem extends StatelessWidget {
  const BadgeEstadoItem({super.key, required this.estado});
  final String estado;

  @override
  Widget build(BuildContext context) =>
      ChipEstado(label: etiquetaEstadoItem(estado), color: _colorEstado(estado));
}

/// Etiqueta legible de un `EstadoItem.valor` (fuente única — la usan el badge y el aviso de
/// conflicto del detalle, CTT-143 C4c). Devuelve el valor crudo si es desconocido.
String etiquetaEstadoItem(String valor) => switch (valor) {
      'abierto' => 'Abierto',
      'en_progreso' => 'En progreso',
      'pendiente_revision' => 'En revisión',
      'terminado' => 'Terminado',
      'problema' => 'Problema',
      _ => valor,
    };

Color _colorEstado(String valor) => switch (valor) {
      'abierto' => Colors.blue,
      'en_progreso' => Colors.orange,
      'pendiente_revision' => Colors.purple,
      'terminado' => Colors.green,
      'problema' => Colors.red,
      _ => Colors.grey,
    };
