/// lista_items_residente_screen.dart — Vista principal del Residente: ítems por proyecto.
///
/// Flujo: selector de proyecto (GET /proyectos) → chips de filtro por estado
/// → lista de ítems (GET /items?proyecto_id=&estado=). Sin offline-first.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ctt_mobile/domain/entities/residente_models.dart';
import 'package:ctt_mobile/presentation/residente/residente_providers.dart';
import 'package:ctt_mobile/presentation/shared/badge_estado_item.dart';
import 'package:ctt_mobile/presentation/shared/badge_notificaciones.dart';
import 'package:ctt_mobile/presentation/shared/error_vista.dart';
import 'package:ctt_mobile/presentation/shared/logout_helper.dart';
import 'package:ctt_mobile/presentation/trabajador/mis_items_provider.dart';

class ListaItemsResidenteScreen extends ConsumerStatefulWidget {
  const ListaItemsResidenteScreen({super.key});

  @override
  ConsumerState<ListaItemsResidenteScreen> createState() =>
      _ListaItemsResidenteScreenState();
}

class _ListaItemsResidenteScreenState
    extends ConsumerState<ListaItemsResidenteScreen> {
  String? _proyectoSeleccionado;
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
    final proyectosAsync = ref.watch(proyectosResidenteProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const Icon(Icons.fact_check),
        title: const Text('Ítems'),
        actions: [
          BadgeNotificaciones(
            onTap: () => context.push('/residente/notificaciones'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: () => confirmarLogout(context, ref),
          ),
        ],
      ),
      body: proyectosAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorVista(
          mensaje: e.toString(),
          onReintento: () => ref.invalidate(proyectosResidenteProvider),
        ),
        data: (proyectos) {
          if (proyectos.isEmpty) {
            return const Center(child: Text('No hay proyectos disponibles.'));
          }
          final proyectoId = _proyectoSeleccionado ?? proyectos.first.id;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SelectorProyecto(
                proyectos: proyectos,
                seleccionado: proyectoId,
                onChange: (id) => setState(() => _proyectoSeleccionado = id),
              ),
              _ChipsFiltro(
                seleccionado: _estadoFiltro,
                filtros: _filtros,
                onSeleccionar: (v) => setState(() => _estadoFiltro = v),
              ),
              Expanded(
                child: _ListaItems(
                  proyectoId: proyectoId,
                  estadoFiltro: _estadoFiltro,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Selector de proyecto ──────────────────────────────────────────────────────

class _SelectorProyecto extends StatelessWidget {
  const _SelectorProyecto({
    required this.proyectos,
    required this.seleccionado,
    required this.onChange,
  });
  final List<ProyectoResidente> proyectos;
  final String seleccionado;
  final ValueChanged<String> onChange;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: DropdownButtonFormField<String>(
          // key fuerza reconstrucción del FormField cuando el proyecto seleccionado
          // cambia desde el padre — necesario porque initialValue solo se aplica
          // al crear el FormFieldState, no en rebuilds.
          key: ValueKey(seleccionado),
          initialValue: seleccionado,
          decoration: const InputDecoration(
            labelText: 'Proyecto',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            isDense: true,
          ),
          items: proyectos
              .map(
                (p) => DropdownMenuItem(
                  value: p.id,
                  child: Text(p.nombre, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: (v) {
            if (v != null) onChange(v);
          },
        ),
      );
}

// ── Chips de filtro ───────────────────────────────────────────────────────────

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

// ── Lista de ítems ────────────────────────────────────────────────────────────

class _ListaItems extends ConsumerWidget {
  const _ListaItems({
    required this.proyectoId,
    required this.estadoFiltro,
  });
  final String proyectoId;
  final String? estadoFiltro;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync =
        ref.watch(itemsProyectoProvider(proyectoId, estadoFiltro));
    return itemsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorVista(
        mensaje: e.toString(),
        onReintento: () =>
            ref.invalidate(itemsProyectoProvider(proyectoId, estadoFiltro)),
      ),
      data: (items) {
        if (items.isEmpty) {
          return const Center(child: Text('No hay ítems con este filtro.'));
        }
        return RefreshIndicator(
          onRefresh: () async =>
              ref.invalidate(itemsProyectoProvider(proyectoId, estadoFiltro)),
          child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (_, i) => _TarjetaItem(item: items[i]),
          ),
        );
      },
    );
  }
}

class _TarjetaItem extends ConsumerWidget {
  const _TarjetaItem({required this.item});
  final ItemResidente item;

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
      onTap: () => context.push('/residente/${item.id}'),
    );
  }
}
