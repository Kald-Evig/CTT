/// notificaciones_screen.dart — Bandeja de notificaciones del Residente.
///
/// Lista todas las notificaciones. Las no leídas se muestran en negrita.
/// Al tocar una notificación no leída se marca como leída inmediatamente.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ctt_mobile/data/repositories/residente_repository.dart';
import 'package:ctt_mobile/domain/entities/residente_models.dart';
import 'package:ctt_mobile/presentation/residente/residente_providers.dart';

class NotificacionesResidenteScreen extends ConsumerWidget {
  const NotificacionesResidenteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifAsync = ref.watch(notificacionesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Notificaciones')),
      body: notifAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 48, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  'No se pudieron cargar las notificaciones.\n$e',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => ref.invalidate(notificacionesProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
        data: (notificaciones) {
          if (notificaciones.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.notifications_none, size: 48, color: Colors.grey),
                    SizedBox(height: 16),
                    Text(
                      'Sin notificaciones.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(notificacionesProvider),
            child: ListView.separated(
              itemCount: notificaciones.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) => _TarjetaNotificacion(
                notificacion: notificaciones[i],
                onMarcarLeida: () async {
                  await ref
                      .read(residenteRepositoryProvider)
                      .marcarNotificacionLeida(notificaciones[i].id);
                  ref.invalidate(notificacionesProvider);
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TarjetaNotificacion extends StatelessWidget {
  const _TarjetaNotificacion({
    required this.notificacion,
    required this.onMarcarLeida,
  });
  final NotificacionResidente notificacion;
  final VoidCallback onMarcarLeida;

  @override
  Widget build(BuildContext context) {
    final noLeida = !notificacion.leida;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Icon(
        noLeida ? Icons.notifications_active : Icons.notifications_outlined,
        color: noLeida ? Theme.of(context).colorScheme.primary : Colors.grey,
      ),
      title: Text(
        notificacion.titulo,
        style: TextStyle(
          fontWeight: noLeida ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (notificacion.cuerpo != null)
            Text(
              notificacion.cuerpo!,
              style: TextStyle(
                color: noLeida ? null : Colors.grey.shade600,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            _formatFechaRelativa(notificacion.createdAt),
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
        ],
      ),
      // Punto indicador de no leída
      trailing: noLeida
          ? const CircleAvatar(radius: 5, backgroundColor: Colors.blue)
          : null,
      onTap: noLeida ? onMarcarLeida : null,
    );
  }

  String _formatFechaRelativa(DateTime dt) {
    final ahora = DateTime.now();
    final local = dt.toLocal();
    final diff = ahora.difference(local);

    if (diff.inMinutes < 1) return 'Ahora mismo';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Hace ${diff.inHours} h';
    if (diff.inDays == 1) return 'Ayer';
    if (diff.inDays < 7) return 'Hace ${diff.inDays} días';

    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/'
        '${local.year}';
  }
}
