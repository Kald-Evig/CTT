/// chip_estado.dart — Pastilla de estado reutilizable (consolidación CTT-103).
///
/// Único lugar del patrón "pastilla de estado": fondo tenue del color, borde del color
/// y texto en el color. Consolida tres copias: [BadgeEstadoItem] (estado de ítem, 5
/// pantallas) y los `_ChipEstado` privados de admin_usuarios_screen y
/// coordinador_proyectos_screen. Estilo canónico = el de BadgeEstadoItem (el más usado):
/// padding 8/4, alpha 0.15, fontSize 11 — así BadgeEstadoItem no cambia de aspecto.
library;

import 'package:flutter/material.dart';

class ChipEstado extends StatelessWidget {
  const ChipEstado({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
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
