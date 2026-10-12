library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ctt_mobile/presentation/auth/auth_notifier.dart';
import 'package:ctt_mobile/presentation/shared/mensajes.dart';

Future<void> confirmarLogout(BuildContext context, WidgetRef ref) async {
  final confirmar = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Cerrar sesión'),
      content: const Text('¿Estás seguro que deseas cerrar sesión?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('Cerrar sesión'),
        ),
      ],
    ),
  );
  if (confirmar != true) return;

  final resultado = await ref.read(authNotifierProvider.notifier).cerrarSesion();
  if (!context.mounted) return;

  switch (resultado) {
    case CierreSesionOk():
      // La navegación la maneja el cambio de estado de auth; nada que hacer.
      break;
    case CierreSesionBloqueado(:final pendientes):
      // Guardia CTT-138: sin red y con cambios en cola → no se cierra. La cola se
      // conserva; solo se avisa.
      mostrarMensaje(
        context,
        'No puedes cerrar sesión sin conexión: tienes $pendientes '
        '${pendientes == 1 ? "cambio" : "cambios"} sin sincronizar.',
      );
    case CierreSesionRequiereConfirmacion(:final pendientes):
      final forzar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cambios sin sincronizar'),
          content: Text(
            'Tienes $pendientes ${pendientes == 1 ? "cambio" : "cambios"} sin '
            'sincronizar. Se conservarán en este dispositivo. ¿Cerrar sesión igual?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Cerrar igual'),
            ),
          ],
        ),
      );
      if (forzar == true && context.mounted) {
        await ref.read(authNotifierProvider.notifier).cerrarSesion(forzar: true);
      }
  }
}
