/// badge_notificaciones.dart — Campana de notificaciones con contador.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ctt_mobile/presentation/residente/residente_providers.dart';

/// Ícono de campana con [Badge] del número de notificaciones no leídas.
/// Compartido por las pantallas de Residente y Coordinador.
class BadgeNotificaciones extends ConsumerWidget {
  const BadgeNotificaciones({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final noLeidas = ref.watch(notificacionesProvider).whenOrNull(
              data: (ns) => ns.where((n) => !n.leida).length,
            ) ??
        0;
    return IconButton(
      tooltip: 'Notificaciones',
      onPressed: onTap,
      icon: Badge(
        isLabelVisible: noLeidas > 0,
        label: Text(noLeidas > 9 ? '9+' : '$noLeidas'),
        child: const Icon(Icons.notifications_outlined),
      ),
    );
  }
}
