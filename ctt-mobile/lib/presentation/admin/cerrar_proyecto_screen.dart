library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ctt_mobile/data/repositories/admin_repository.dart';
import 'package:ctt_mobile/data/repositories/coordinador_repository.dart';
import 'package:ctt_mobile/domain/entities/coordinador_models.dart';
import 'package:ctt_mobile/presentation/shared/error_vista.dart';

/// Lista los proyectos de la empresa y permite cerrar cualquiera.
/// Solo accesible desde Admin (cerrar_proyecto: {Rol.ADMIN} en permissions.py).
class CerrarProyectoScreen extends ConsumerWidget {
  const CerrarProyectoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proyectosAsync = ref.watch(_proyectosAdminProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cerrar proyecto'),
      ),
      body: proyectosAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorVista(
          mensaje: e.toString(),
          onReintento: () => ref.invalidate(_proyectosAdminProvider),
        ),
        data: (proyectos) {
          final abiertos = proyectos
              .where((p) => p.estado != 'cerrado')
              .toList();
          if (abiertos.isEmpty) {
            return const Center(
              child: Text('No hay proyectos activos para cerrar.'),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: abiertos.length,
            itemBuilder: (_, i) => _TarjetaProyectoAdmin(proyecto: abiertos[i]),
          );
        },
      ),
    );
  }
}

// ── Provider local: reutiliza el repo del coordinador, mismo endpoint ─────────

final _proyectosAdminProvider =
    FutureProvider<List<DashboardProyecto>>((ref) {
  return ref.watch(coordinadorRepositoryProvider).listarDashboard();
});

// ── Tarjeta de proyecto con botón cerrar ─────────────────────────────────────

class _TarjetaProyectoAdmin extends ConsumerStatefulWidget {
  const _TarjetaProyectoAdmin({required this.proyecto});
  final DashboardProyecto proyecto;

  @override
  ConsumerState<_TarjetaProyectoAdmin> createState() =>
      _TarjetaProyectoAdminState();
}

class _TarjetaProyectoAdminState
    extends ConsumerState<_TarjetaProyectoAdmin> {
  bool _cargando = false;

  Future<void> _cerrar() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar proyecto'),
        content: Text(
          '¿Cerrar "${widget.proyecto.nombre}"?\n\n'
          'Esta acción es irreversible. El proyecto quedará bloqueado para '
          'nuevas transiciones.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cerrar proyecto'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    setState(() => _cargando = true);
    try {
      await ref
          .read(adminRepositoryProvider)
          .cerrarProyecto(widget.proyecto.id);
      if (!mounted) return;
      ref.invalidate(_proyectosAdminProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${widget.proyecto.nombre}" cerrado.'),
        ),
      );
    } on ErrorAdmin catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.mensaje)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ListTile(
        title: Text(widget.proyecto.nombre),
        subtitle: Text(
          '${widget.proyecto.pctCompleto.toStringAsFixed(0)}% completo · '
          '${widget.proyecto.estado}',
        ),
        trailing: _cargando
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : IconButton(
                icon: Icon(
                  Icons.lock_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
                tooltip: 'Cerrar proyecto',
                onPressed: _cerrar,
              ),
      ),
    );
  }
}
