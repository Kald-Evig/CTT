library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ctt_mobile/domain/entities/residente_models.dart';
import 'package:ctt_mobile/presentation/residente/residente_providers.dart';
import 'package:ctt_mobile/presentation/shared/badge_estado_item.dart';
import 'package:ctt_mobile/presentation/shared/error_vista.dart';
import 'package:ctt_mobile/presentation/trabajador/mis_items_provider.dart';

class CoordinadorItemsScreen extends ConsumerStatefulWidget {
  const CoordinadorItemsScreen({super.key, required this.proyectoId});
  final String proyectoId;

  @override
  ConsumerState<CoordinadorItemsScreen> createState() =>
      _CoordinadorItemsScreenState();
}

class _CoordinadorItemsScreenState
    extends ConsumerState<CoordinadorItemsScreen> {
  String? _estadoFiltro;

  static const _filtros = [
    (label: 'Todos', valor: null),
    (label: 'Abiertos', valor: 'abierto'),
    (label: 'En progreso', valor: 'en_progreso'),
    (label: 'En revisión', valor: 'pendiente_revision'),
    (label: 'Problema', valor: 'problema'),
    (label: 'Terminados', valor: 'terminado'),
  ];

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(
      itemsProyectoProvider(widget.proyectoId, _estadoFiltro),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Ítems')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/coordinador/${widget.proyectoId}/items/nuevo'),
        tooltip: 'Nuevo ítem',
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          _ChipsFiltro(
            seleccionado: _estadoFiltro,
            filtros: _filtros,
            onSeleccionar: (v) => setState(() => _estadoFiltro = v),
          ),
          Expanded(
            child: itemsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorVista(
                mensaje: e.toString(),
                onReintento: () => ref.invalidate(
                  itemsProyectoProvider(widget.proyectoId, _estadoFiltro),
                ),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return const Center(
                    child: Text('No hay ítems con este filtro.'),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(
                    itemsProyectoProvider(widget.proyectoId, _estadoFiltro),
                  ),
                  child: ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (_, i) => _TarjetaItem(
                      item: items[i],
                      proyectoId: widget.proyectoId,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TarjetaItem extends ConsumerWidget {
  const _TarjetaItem({required this.item, required this.proyectoId});
  final ItemResidente item;
  final String proyectoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendientesAsync = ref.watch(itemsConSyncPendienteProvider);
    final tienePendiente =
        pendientesAsync.whenOrNull(data: (ids) => ids.contains(item.id)) ??
            false;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Text(item.nombre),
      subtitle: Text(
        item.asignadoNombre != null
            ? 'Asignado: ${item.asignadoNombre}'
            : 'Sin asignar',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: item.asignadoNombre != null ? null : Colors.grey.shade500,
            ),
      ),
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
      onTap: () => context.push('/coordinador/$proyectoId/items/${item.id}'),
    );
  }
}

class _ChipsFiltro extends StatelessWidget {
  const _ChipsFiltro({
    required this.seleccionado,
    required this.filtros,
    required this.onSeleccionar,
  });
  final String? seleccionado;
  final List<({String label, String? valor})> filtros;
  final ValueChanged<String?> onSeleccionar;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          children: [
            for (final f in filtros)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  label: Text(f.label),
                  selected: seleccionado == f.valor,
                  onSelected: (_) => onSeleccionar(f.valor),
                ),
              ),
          ],
        ),
      );
}
