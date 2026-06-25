library;

import 'package:flutter/material.dart';

class BadgeEstadoItem extends StatelessWidget {
  const BadgeEstadoItem({super.key, required this.estado});
  final String estado;

  @override
  Widget build(BuildContext context) {
    final (label, color) = _infoEstado(estado);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
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
