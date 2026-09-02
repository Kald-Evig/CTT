/// mis_items_screen.dart — Lista de ítems asignados al trabajador.
///
/// Carga desde caché local; sincroniza con la API en segundo plano al abrir.
/// Agrupa los ítems por proyecto para que el trabajador ubique sus tareas.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ctt_mobile/data/local/database.dart';
import 'package:ctt_mobile/presentation/shared/badge_estado_item.dart';
import 'package:ctt_mobile/presentation/shared/error_vista.dart';
import 'package:ctt_mobile/presentation/shared/logout_helper.dart';
import 'package:ctt_mobile/presentation/trabajador/mis_items_provider.dart';

class MisItemsScreen extends ConsumerWidget {
  const MisItemsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(misItemsProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const Icon(Icons.engineering),
        title: const Text('Mis ítems'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: () => ref.invalidate(misItemsProvider),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: () => confirmarLogout(context, ref),
          ),
        ],
      ),
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => ErrorVista(
          mensaje: 'Sin conexión. Mostrando datos en caché.',
          onReintento: () => ref.invalidate(misItemsProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const Center(
              child: Text('No tienes ítems asignados por el momento.'),
            );
          }
          return _ListaAgrupada(items: items);
        },
      ),
    );
  }
}

// ── Lista agrupada por proyecto ───────────────────────────────────────────────

class _ListaAgrupada extends StatelessWidget {
  const _ListaAgrupada({required this.items});
  final List<ItemsCacheTableData> items;

  @override
  Widget build(BuildContext context) {
    final grupos = <String, List<ItemsCacheTableData>>{};
    for (final item in items) {
      grupos.putIfAbsent(item.proyectoId, () => []).add(item);
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        for (final entrada in grupos.entries) ...[
          _CabeceraProyecto(
            proyectoNombre: entrada.value.first.proyectoNombre,
          ),
          for (final item in entrada.value) _TarjetaItem(item: item),
        ],
      ],
    );
  }
}

class _CabeceraProyecto extends StatelessWidget {
  const _CabeceraProyecto({required this.proyectoNombre});
  final String proyectoNombre;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(
          proyectoNombre.isNotEmpty ? proyectoNombre : 'Sin proyecto',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
      );
}

class _TarjetaItem extends ConsumerWidget {
  const _TarjetaItem({required this.item});
  final ItemsCacheTableData item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendientesAsync = ref.watch(itemsConSyncPendienteProvider);
    final tienePendiente = pendientesAsync.whenOrNull(
          data: (ids) => ids.contains(item.id),
        ) ??
        false;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Text(item.nombre),
      subtitle: item.descripcion != null
          ? Text(
              item.descripcion!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (tienePendiente)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(
                Icons.cloud_upload_outlined,
                size: 14,
                color: Colors.orange.shade700,
              ),
            ),
          BadgeEstadoItem(estado: item.estado),
        ],
      ),
      onTap: () => context.push('/trabajador/${item.id}'),
    );
  }
}

