/// detalle_item_residente_screen.dart — Detalle de ítem para el Residente.
///
/// Muestra datos del ítem + historial, comentarios, y evidencias (widgets
/// compartidos vía ItemDetalleCuerpo). Acciones disponibles según estado:
///   pendiente_revision → Aprobar / Rechazar (comentario obligatorio)
///   problema           → Cerrar problema
///   cualquier estado editable → Marcar problema, Asignar trabajador
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ctt_mobile/core/sync/resultado_transicion.dart';
import 'package:ctt_mobile/data/repositories/residente_repository.dart';
import 'package:ctt_mobile/domain/entities/residente_models.dart';
import 'package:ctt_mobile/domain/enums/enums_ctt.dart';
import 'package:ctt_mobile/presentation/residente/residente_providers.dart';
import 'package:ctt_mobile/presentation/shared/error_vista.dart';
import 'package:ctt_mobile/presentation/shared/item_detalle_widgets.dart';

class DetalleItemResidenteScreen extends ConsumerWidget {
  const DetalleItemResidenteScreen({super.key, required this.itemId});
  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemAsync = ref.watch(itemResidenteDetalleProvider(itemId));

    return Scaffold(
      appBar: AppBar(title: const Text('Detalle del ítem')),
      body: itemAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorVista(
          mensaje: 'No se pudo cargar el ítem: $e',
          onReintento: () => ref.invalidate(itemResidenteDetalleProvider(itemId)),
        ),
        data: (item) => ItemDetalleCuerpo(
          item: item,
          acciones: _AccionesResidente(item: item),
        ),
      ),
    );
  }
}

// ── Acciones por estado ───────────────────────────────────────────────────────

class _AccionesResidente extends ConsumerWidget {
  const _AccionesResidente({required this.item});
  final ItemResidente item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = EstadoItem.fromString(item.estado);

    if (estado == EstadoItem.terminado) {
      return const ItemDetalleMensajeEstado(
        icono: Icons.verified_outlined,
        texto: 'Este ítem fue marcado como terminado.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (estado == EstadoItem.pendienteRevision) ...[
          ItemDetalleBotonAccion(
            label: 'Aprobar',
            icono: Icons.verified_outlined,
            color: Colors.green.shade700,
            filled: true,
            onTap: () => _aprobar(context, ref),
          ),
          const SizedBox(height: 12),
          ItemDetalleBotonAccion(
            label: 'Rechazar',
            icono: Icons.close,
            color: Colors.red.shade700,
            filled: false,
            onTap: () => _mostrarDialogoRechazar(context, ref),
          ),
          const SizedBox(height: 12),
        ],
        if (estado == EstadoItem.problema) ...[
          ItemDetalleBotonAccion(
            label: 'Cerrar problema',
            icono: Icons.check_circle_outline,
            color: Colors.orange.shade700,
            filled: true,
            onTap: () => _cerrarProblema(context, ref),
          ),
          const SizedBox(height: 12),
        ],
        if (estado != EstadoItem.problema) ...[
          ItemDetalleBotonAccion(
            label: 'Marcar problema',
            icono: Icons.warning_amber_outlined,
            color: Colors.red.shade700,
            filled: false,
            onTap: () => _mostrarDialogoProblema(context, ref),
          ),
          const SizedBox(height: 12),
        ],
        ItemDetalleBotonAccion(
          label: 'Asignar a trabajador',
          icono: Icons.person_add_outlined,
          color: Theme.of(context).colorScheme.primary,
          filled: false,
          onTap: () => _mostrarDialogoAsignar(context, ref),
        ),
      ],
    );
  }

  Future<void> _aprobar(BuildContext context, WidgetRef ref) async {
    try {
      final resultado = await ref
          .read(itemResidenteDetalleProvider(item.id).notifier)
          .transicionar(nuevoEstado: EstadoItem.terminado.valor);
      if (context.mounted) {
        _mostrarResultado(
          context,
          resultado,
          mensajeExito: 'Ítem aprobado y marcado como terminado.',
        );
      }
    } catch (e) {
      if (context.mounted) {
        _mostrarError(context, e);
      }
    }
  }

  Future<void> _cerrarProblema(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(residenteRepositoryProvider).cerrarProblema(item.id);
      ref.invalidate(itemResidenteDetalleProvider(item.id));
      ref.invalidate(itemsProyectoProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(const SnackBar(content: Text('Problema cerrado.')));
      }
    } catch (e) {
      if (context.mounted) {
        _mostrarError(context, e);
      }
    }
  }

  Future<void> _mostrarDialogoRechazar(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final formKey = GlobalKey<FormState>();
    final ctrl = TextEditingController();
    final comentario = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rechazar ítem'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: ctrl,
            decoration: const InputDecoration(
              hintText: 'Motivo del rechazo (obligatorio)...',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
            autofocus: true,
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'El motivo es obligatorio' : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, ctrl.text.trim());
              }
            },
            child: const Text('Rechazar'),
          ),
        ],
      ),
    );
    if (comentario == null || !context.mounted) return;
    try {
      final resultado = await ref
          .read(itemResidenteDetalleProvider(item.id).notifier)
          .transicionar(
            nuevoEstado: EstadoItem.enProgreso.valor,
            comentario: comentario,
          );
      if (context.mounted) {
        _mostrarResultado(context, resultado, mensajeExito: 'Ítem rechazado.');
      }
    } catch (e) {
      if (context.mounted) {
        _mostrarError(context, e);
      }
    }
  }

  Future<void> _mostrarDialogoProblema(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final formKey = GlobalKey<FormState>();
    final ctrl = TextEditingController();
    final descripcion = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Marcar problema'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: ctrl,
            decoration: const InputDecoration(
              hintText: 'Descripción del problema (obligatoria)...',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
            autofocus: true,
            validator: (v) => v == null || v.trim().isEmpty
                ? 'La descripción es obligatoria'
                : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, ctrl.text.trim());
              }
            },
            child: const Text('Reportar'),
          ),
        ],
      ),
    );
    if (descripcion == null || !context.mounted) return;
    try {
      final resultado = await ref
          .read(itemResidenteDetalleProvider(item.id).notifier)
          .transicionar(
            nuevoEstado: EstadoItem.problema.valor,
            descripcionProblema: descripcion,
          );
      if (context.mounted) {
        _mostrarResultado(
          context,
          resultado,
          mensajeExito: 'Problema reportado.',
        );
      }
    } catch (e) {
      if (context.mounted) {
        _mostrarError(context, e);
      }
    }
  }

  Future<void> _mostrarDialogoAsignar(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final usuarioId = await showDialog<String>(
      context: context,
      builder: (ctx) => Consumer(
        builder: (ctx, dialogRef, _) {
          final usuariosAsync = dialogRef.watch(usuariosEmpresaPorRolesProvider(const ['trabajador']));
          return AlertDialog(
            title: const Text('Asignar a trabajador'),
            content: SizedBox(
              width: double.maxFinite,
              child: usuariosAsync.when(
                loading: () => const SizedBox(
                  height: 100,
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Text('Error al cargar usuarios: $e'),
                data: (usuarios) {
                  if (usuarios.isEmpty) {
                    return const Text('No hay usuarios disponibles.');
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: usuarios.length,
                    itemBuilder: (_, i) {
                      final u = usuarios[i];
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(u.nombreCompleto[0].toUpperCase()),
                        ),
                        title: Text(u.nombreCompleto),
                        subtitle: Text(u.email),
                        onTap: () => Navigator.pop(ctx, u.id),
                      );
                    },
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
            ],
          );
        },
      ),
    );
    if (usuarioId == null || !context.mounted) return;
    try {
      await ref.read(residenteRepositoryProvider).asignarItem(item.id, usuarioId);
      ref.invalidate(itemResidenteDetalleProvider(item.id));
      ref.invalidate(itemsProyectoProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(const SnackBar(content: Text('Ítem asignado.')));
      }
    } catch (e) {
      if (context.mounted) {
        _mostrarError(context, e);
      }
    }
  }

  void _mostrarResultado(
    BuildContext context,
    ResultadoTransicion resultado, {
    String mensajeExito = 'Cambio aplicado.',
  }) {
    final msg = switch (resultado) {
      TransicionAplicadaOnline() => mensajeExito,
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

  void _mostrarError(BuildContext context, Object e) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(itemDetalleMensajeError(e))));
  }
}
