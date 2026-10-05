/// chip_estado.dart — Pastilla de estado reutilizable (CTT-117 T4-1 / CTT-103).
///
/// Único lugar del patrón "pastilla de estado": fondo tenue del color, borde del color
/// y texto en el color. Antes estaba duplicado como `_ChipEstado` privado en
/// admin_usuarios_screen y coordinador_proyectos_screen (auditoría 5 de CTT-117); se
/// consolidó acá al aparecer un tercer consumidor (el badge de sync, CTT-103 D6).
library;

import 'package:flutter/material.dart';

class ChipEstado extends StatelessWidget {
  const ChipEstado({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      );
}
