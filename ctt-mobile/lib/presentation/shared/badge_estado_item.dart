library;

import 'package:flutter/material.dart';

import 'package:ctt_mobile/presentation/shared/chip_estado.dart';

/// Pastilla del estado de un ítem. Conserva solo el mapeo estado→(label, color) y
/// delega el render en [ChipEstado] (pastilla compartida); su aspecto no cambia.
class BadgeEstadoItem extends StatelessWidget {
  const BadgeEstadoItem({super.key, required this.estado});
  final String estado;

  @override
  Widget build(BuildContext context) {
    final (label, color) = _infoEstado(estado);
    return ChipEstado(label: label, color: color);
  }

  (String, Color) _infoEstado(String valor) => switch (valor) {
        'abierto' => ('Abierto', Colors.blue),
        'en_progreso' => ('En progreso', Colors.orange),
        'pendiente_revision' => ('En revisión', Colors.purple),
        'terminado' => ('Terminado', Colors.green),
        'problema' => ('Problema', Colors.red),
        _ => (valor, Colors.grey),
      };
}
