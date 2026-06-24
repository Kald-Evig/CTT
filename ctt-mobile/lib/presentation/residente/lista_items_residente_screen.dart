/// lista_items_residente_screen.dart — Vista principal del Residente: ítems por proyecto.
///
/// Flujo: selector de proyecto (GET /proyectos) → chips de filtro por estado
/// → lista de ítems (GET /items?proyecto_id=&estado=). Sin offline-first.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ctt_mobile/domain/entities/residente_models.dart';
import 'package:ctt_mobile/presentation/auth/auth_notifier.dart';
import 'package:ctt_mobile/presentation/residente/residente_providers.dart';
import 'package:ctt_mobile/presentation/trabajador/mis_items_provider.dart';
import 'package:ctt_mobile/presentation/trabajador/mis_items_screen.dart';

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
        title: const Text('Ítems'),
        actions: [
          _BadgeNotificaciones(
            onTap: () => context.push('/residente/notificaciones'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: () => _confirmarLogout(context, ref),
          ),
        ],
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
    final itemsAsync = ref.watch(itemsProyectoProvider(proyectoId, estadoFiltro));
    return itemsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorVista(
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

// ── Badge de notificaciones ──────────────────────────────────────────────────

class _BadgeNotificaciones extends ConsumerWidget {
  const _BadgeNotificaciones({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final noLeidas = ref
            .watch(notificacionesProvider)
            .whenOrNull(data: (ns) => ns.where((n) => !n.leida).length) ??
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

// ── Logout ───────────────────────────────────────────────────────────────────

Future<void> _confirmarLogout(BuildContext context, WidgetRef ref) async {
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
  if (confirmar == true) {
    await ref.read(authNotifierProvider.notifier).cerrarSesion();
  }
}

// ── Vista de error ───────────────────────────────────────────────────────────

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
