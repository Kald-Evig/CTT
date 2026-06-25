library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ctt_mobile/domain/entities/residente_models.dart';
import 'package:ctt_mobile/presentation/coordinador/coordinador_providers.dart';
import 'package:ctt_mobile/presentation/residente/residente_providers.dart';
import 'package:ctt_mobile/presentation/shared/logout_helper.dart';

class CoordinadorProyectosScreen extends ConsumerWidget {
  const CoordinadorProyectosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proyectosAsync = ref.watch(proyectosResidenteProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const Icon(Icons.business_center),
        title: const Text('Proyectos'),
        actions: [
          _BadgeConflictos(
            onTap: () => context.push('/coordinador/conflictos'),
          ),
          _BadgeNotificaciones(
            onTap: () => context.push('/coordinador/notificaciones'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: () => confirmarLogout(context, ref),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/coordinador/crear-proyecto'),
        tooltip: 'Nuevo proyecto',
        child: const Icon(Icons.add),
      ),
      body: proyectosAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorVista(
          mensaje: e.toString(),
          onReintento: () => ref.invalidate(proyectosResidenteProvider),
        ),
        data: (proyectos) {
          if (proyectos.isEmpty) {
            return const Center(child: Text('No hay proyectos disponibles.'));
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(proyectosResidenteProvider),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: proyectos.length,
              itemBuilder: (_, i) => _TarjetaProyecto(proyecto: proyectos[i]),
            ),
          );
        },
      ),
    );
  }
}

class _TarjetaProyecto extends StatelessWidget {
  const _TarjetaProyecto({required this.proyecto});
  final ProyectoResidente proyecto;

  @override
  Widget build(BuildContext context) {
    final (label, color) = _infoEstado(proyecto.estado);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(
          proyecto.nombre,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        trailing: Container(
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
        ),
        onTap: () => context.push('/coordinador/${proyecto.id}/items'),
      ),
    );
  }

  (String, Color) _infoEstado(String valor) => switch (valor) {
        'activo' => ('Activo', Colors.green),
        'pausado' => ('Pausado', Colors.orange),
        'cerrado' => ('Cerrado', Colors.grey),
        _ => (valor, Colors.blue),
      };
}

class _BadgeConflictos extends ConsumerWidget {
  const _BadgeConflictos({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendientes =
        ref.watch(conflictosPendientesProvider).whenOrNull(data: (cs) => cs.length) ?? 0;
    return IconButton(
      tooltip: 'Conflictos',
      onPressed: onTap,
      icon: Badge(
        isLabelVisible: pendientes > 0,
        label: Text(pendientes > 9 ? '9+' : '$pendientes'),
        child: const Icon(Icons.merge_type_outlined),
      ),
    );
  }
}

class _BadgeNotificaciones extends ConsumerWidget {
  const _BadgeNotificaciones({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final noLeidas =
        ref.watch(notificacionesProvider).whenOrNull(
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

class _ErrorVista extends StatelessWidget {
  const _ErrorVista({required this.mensaje, required this.onReintento});
  final String mensaje;
  final VoidCallback onReintento;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                mensaje,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onReintento,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
}
