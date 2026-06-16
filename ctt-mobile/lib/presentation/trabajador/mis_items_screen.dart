/// mis_items_screen.dart — Lista de ítems asignados al trabajador.
///
/// Carga desde caché local; sincroniza con la API en segundo plano al abrir.
/// Agrupa los ítems por proyecto para que el trabajador ubique sus tareas.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ctt_mobile/data/local/database.dart';
import 'package:ctt_mobile/presentation/auth/auth_notifier.dart';
import 'package:ctt_mobile/presentation/trabajador/mis_items_provider.dart';

class MisItemsScreen extends ConsumerWidget {
  const MisItemsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(misItemsProvider);

    return Scaffold(
      appBar: AppBar(
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
            onPressed: () => _confirmarLogout(context, ref),
          ),
        ],
      ),
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorVista(
          mensaje: e.toString(),
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
    // Agrupar por proyectoId manteniendo orden de aparición.
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

class _TarjetaItem extends StatelessWidget {
  const _TarjetaItem({required this.item});
  final ItemsCacheTableData item;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(item.nombre),
        subtitle: item.descripcion != null
            ? Text(
                item.descripcion!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            : null,
        trailing: BadgeEstadoItem(estado: item.estado),
        onTap: () => context.push('/trabajador/${item.id}'),
      );
}

// ── Badge de estado (público para reutilizar en DetalleItemScreen) ───────────

class BadgeEstadoItem extends StatelessWidget {
  const BadgeEstadoItem({super.key, required this.estado});
  final String estado;

  @override
  Widget build(BuildContext context) {
    final (label, color) = _infoEstado(estado);
    return Container(
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

  (String, Color) _infoEstado(String valor) => switch (valor) {
        'abierto' => ('Abierto', Colors.blue),
        'en_progreso' => ('En progreso', Colors.orange),
        'pendiente_revision' => ('En revisión', Colors.purple),
        'terminado' => ('Terminado', Colors.green),
        'problema' => ('Problema', Colors.red),
        _ => (valor, Colors.grey),
      };
}

// ── Logout con confirmación ───────────────────────────────────────────────────

/// Muestra un diálogo de confirmación y cierra sesión si el usuario acepta.
/// El router detecta automáticamente el cambio en el stream de Firebase
/// y redirige al login — no se necesita navegación manual aquí.
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

// ── Vista de error con reintento ─────────────────────────────────────────────

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
              const Icon(Icons.wifi_off_outlined, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                'Sin conexión. Mostrando datos en caché.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
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

