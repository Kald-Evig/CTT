/// vista_vacia.dart — Estado vacío con ícono y mensaje centrados.
library;

import 'package:flutter/material.dart';

/// Ilustración de "no hay nada acá": ícono grande + mensaje, centrados.
///
/// Para las listas vacías con ícono (conflictos, notificaciones). Los vacíos de
/// una sola línea sin ícono se dejan como texto centrado en su sitio: son
/// triviales y no comparten intención con estos (éxito vs sin-datos).
class VistaVacia extends StatelessWidget {
  const VistaVacia({
    super.key,
    required this.mensaje,
    required this.icono,
    this.colorIcono = Colors.grey,
  });

  final String mensaje;
  final IconData icono;
  final Color colorIcono;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icono, size: 48, color: colorIcono),
              const SizedBox(height: 16),
              Text(
                mensaje,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
}
