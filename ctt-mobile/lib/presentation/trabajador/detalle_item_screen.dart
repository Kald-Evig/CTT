/// detalle_item_screen.dart — Detalle de un ítem con acciones del trabajador.
///
/// Máquina de estados visible (Sección 6.2):
///   abierto → [Iniciar] → en_progreso
///   en_progreso → [Terminar] → pendiente_revision
///   en_progreso → [Reportar problema] → problema
///   problema → [Reanudar] → en_progreso
///   pendiente_revision / terminado → solo lectura para el trabajador
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ctt_mobile/core/sync/resultado_transicion.dart';
import 'package:ctt_mobile/data/local/database.dart';
import 'package:ctt_mobile/data/repositories/items_repository.dart';
import 'package:ctt_mobile/domain/enums/enums_ctt.dart';
import 'package:ctt_mobile/presentation/shared/badge_estado_item.dart';
import 'package:ctt_mobile/presentation/trabajador/mis_items_provider.dart';

class DetalleItemScreen extends ConsumerWidget {
  const DetalleItemScreen({super.key, required this.itemId});
  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemAsync = ref.watch(itemDetalleProvider(itemId));

    return Scaffold(
      appBar: AppBar(title: const Text('Detalle del ítem')),
      body: itemAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            Center(child: Text('No se pudo cargar el ítem: $e')),
        data: (item) {
          if (item == null) {
            return const Center(child: Text('Ítem no encontrado en caché.'));
          }
          return _CuerpoDetalle(item: item);
        },
      ),
    );
  }
}

// ── Cuerpo principal ──────────────────────────────────────────────────────────

class _CuerpoDetalle extends ConsumerWidget {
  const _CuerpoDetalle({required this.item});
  final ItemsCacheTableData item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = EstadoItem.fromString(item.estado);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  item.nombre,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const SizedBox(width: 8),
              BadgeEstadoItem(estado: item.estado),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            item.proyectoNombre.isNotEmpty
                ? item.proyectoNombre
                : 'Proyecto ${item.proyectoId}',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),

          if (item.descripcion != null && item.descripcion!.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Text(
              item.descripcion!,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],

          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),

          _AccionesEstado(item: item, estado: estado),
        ],
      ),
    );
  }
}

// ── Acciones por estado ──────────────────────────────────────────────────────

class _AccionesEstado extends ConsumerWidget {
  const _AccionesEstado({required this.item, required this.estado});
  final ItemsCacheTableData item;
  final EstadoItem estado;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (estado) {
      EstadoItem.abierto => _BotonPrimario(
          label: 'Iniciar trabajo',
          icono: Icons.play_arrow_rounded,
          color: Theme.of(context).colorScheme.primary,
          onTap: () => _ejecutarCambio(context, ref, EstadoItem.enProgreso),
        ),
      EstadoItem.enProgreso => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _BotonPrimario(
              label: 'Marcar como terminado',
              icono: Icons.check_circle_outline,
              color: Colors.green.shade700,
              onTap: () => _ejecutarCambio(
                context, ref, EstadoItem.pendienteRevision,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.warning_amber_outlined),
              label: const Text('Reportar problema'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red.shade700,
                side: BorderSide(color: Colors.red.shade300),
              ),
              onPressed: () => _mostrarDialogoProblema(context, ref),
            ),
          ],
        ),
      EstadoItem.problema => _BotonPrimario(
          label: 'Reanudar trabajo',
          icono: Icons.replay_rounded,
          color: Colors.orange.shade700,
          onTap: () => _ejecutarCambio(context, ref, EstadoItem.enProgreso),
        ),
      EstadoItem.pendienteRevision => const _MensajeInformativo(
          icono: Icons.hourglass_top_rounded,
          texto: 'Ítem enviado a revisión. Aguarda la confirmación del coordinador.',
        ),
      EstadoItem.terminado => const _MensajeInformativo(
          icono: Icons.verified_outlined,
          texto: 'Este ítem fue marcado como terminado.',
        ),
    };
  }

  Future<void> _ejecutarCambio(
    BuildContext context,
    WidgetRef ref,
    EstadoItem nuevoEstado,
  ) async {
    try {
      final resultado = await ref.read(itemsRepositoryProvider).cambiarEstado(
            itemId: item.id,
            nuevoEstado: nuevoEstado,
          );
      ref.invalidate(itemDetalleProvider(item.id));
      ref.invalidate(misItemsProvider);
      if (context.mounted) {
        _mostrarResultado(context, resultado);
      }
    } catch (e) {
      // El repositorio ya revirtió la caché; solo refrescar la UI.
      ref.invalidate(itemDetalleProvider(item.id));
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text('Error al guardar: $e')));
      }
    }
  }

  Future<void> _mostrarDialogoProblema(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final ctrl = TextEditingController();
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reportar problema'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            hintText: 'Describe el problema encontrado...',
          ),
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reportar'),
          ),
        ],
      ),
    );

    if (confirmado != true) return;
    final descripcion = ctrl.text.trim();
    if (descripcion.isEmpty) return;

    if (!context.mounted) return;
    try {
      final resultado = await ref.read(itemsRepositoryProvider).reportarProblema(
            itemId: item.id,
            descripcion: descripcion,
          );
      ref.invalidate(itemDetalleProvider(item.id));
      ref.invalidate(misItemsProvider);
      if (context.mounted) {
        _mostrarResultado(context, resultado);
      }
    } catch (e) {
      ref.invalidate(itemDetalleProvider(item.id));
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text('Error al reportar: $e')));
      }
    }
  }

  void _mostrarResultado(BuildContext context, ResultadoTransicion resultado) {
    final msg = switch (resultado) {
      TransicionAplicadaOnline() => 'Cambio aplicado.',
      TransicionEncoladaOffline() =>
        'Sin conexión. Se sincronizará cuando vuelva la señal.',
      TransicionRechazada(:final detalle) => detalle,
      TransicionConConflicto() =>
        'Hay un conflicto que un coordinador debe resolver.',
    };
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }
}

// ── Widgets auxiliares ────────────────────────────────────────────────────────

class _BotonPrimario extends StatelessWidget {
  const _BotonPrimario({
    required this.label,
    required this.icono,
    required this.color,
    required this.onTap,
  });
  final String label;
  final IconData icono;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
        icon: Icon(icono),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: color,
          minimumSize: const Size.fromHeight(48),
        ),
        onPressed: onTap,
      );
}

class _MensajeInformativo extends StatelessWidget {
  const _MensajeInformativo({required this.icono, required this.texto});
  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icono, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              texto,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.grey.shade700),
            ),
          ),
        ],
      );
}
