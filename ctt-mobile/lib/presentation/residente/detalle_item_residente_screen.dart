/// detalle_item_residente_screen.dart — Detalle de ítem para el Residente.
///
/// Muestra datos del ítem + historial, comentarios, y evidencias (widgets
/// compartidos vía ItemDetalleCuerpo). Los botones de TRANSICIÓN salen de
/// `accionesPermitidas` sobre el contrato generado del backend; la UI solo elige el
/// texto/ícono. "Asignar a trabajador" NO es una transición y se mantiene aparte.
///   pendiente_revision → Aprobar / Rechazar (comentario obligatorio) / Marcar problema
///   en_progreso        → Marcar problema
///   problema           → Cerrar problema
///   abierto            → (sin transiciones; CTT-153: ya no se ofrece "Marcar problema")
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ctt_mobile/data/local/daos/sync_dao.dart' show ResultadoEspera;
import 'package:ctt_mobile/data/repositories/residente_repository.dart';
import 'package:ctt_mobile/domain/acciones_permitidas.dart';
import 'package:ctt_mobile/domain/entities/residente_models.dart';
import 'package:ctt_mobile/domain/enums/enums_ctt.dart';
import 'package:ctt_mobile/presentation/residente/residente_providers.dart';
import 'package:ctt_mobile/presentation/shared/error_vista.dart';
import 'package:ctt_mobile/presentation/shared/item_detalle_widgets.dart';
import 'package:ctt_mobile/presentation/shared/mensajes.dart';

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
          onReintento: () =>
              ref.invalidate(itemResidenteDetalleProvider(itemId)),
        ),
        data: (item) => ItemDetalleCuerpo(
          item: item,
          acciones:
              GateCapturaOffline(acciones: _AccionesResidente(item: item)),
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

    // Los botones de TRANSICIÓN salen del contrato generado del backend. El Residente
    // no es el asignado (esAsignado solo habilita ABIERTO→EN_PROGRESO del Trabajador).
    final acciones =
        accionesPermitidas(estado, RolUsuario.residente, esAsignado: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final accion in acciones) ...[
          _botonAccion(context, ref, accion),
          const SizedBox(height: 12),
        ],
        // "Asignar a trabajador" NO es una transición de la máquina de estados: se
        // mantiene aparte, independiente del contrato.
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

  /// Botón para una acción del contrato. El texto/ícono los elige la UI; la
  /// disponibilidad ya la decidió [accionesPermitidas].
  Widget _botonAccion(BuildContext context, WidgetRef ref, AccionItem accion) {
    if (accion is AccionTransicion) {
      return switch (accion.hacia) {
        EstadoItem.terminado => ItemDetalleBotonAccion(
            label: 'Aprobar',
            icono: Icons.verified_outlined,
            color: Colors.green.shade700,
            filled: true,
            onTap: () => _aprobar(context, ref),
          ),
        EstadoItem.enProgreso => ItemDetalleBotonAccion(
            label: 'Rechazar',
            icono: Icons.close,
            color: Colors.red.shade700,
            filled: false,
            onTap: () => _mostrarDialogoRechazar(context, ref),
          ),
        EstadoItem.problema => ItemDetalleBotonAccion(
            label: 'Marcar problema',
            icono: Icons.warning_amber_outlined,
            color: Colors.red.shade700,
            filled: false,
            onTap: () => _mostrarDialogoProblema(context, ref),
          ),
        _ => const SizedBox.shrink(),
      };
    }
    if (accion is AccionEspecialItem &&
        accion.accion == AccionEspecial.cerrarProblema) {
      return ItemDetalleBotonAccion(
        label: 'Cerrar problema',
        icono: Icons.check_circle_outline,
        color: Colors.orange.shade700,
        filled: true,
        onTap: () => _cerrarProblema(context, ref),
      );
    }
    // revertir_terminado no es del Residente (solo Admin, fuera de alcance CTT-153).
    return const SizedBox.shrink();
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
        mostrarMensaje(context, 'Problema cerrado.');
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
            validator: (v) => v == null || v.trim().isEmpty
                ? 'El motivo es obligatorio'
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
          final usuariosAsync = dialogRef
              .watch(usuariosEmpresaPorRolesProvider(const ['trabajador']));
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
      await ref
          .read(residenteRepositoryProvider)
          .asignarItem(item.id, usuarioId);
      ref.invalidate(itemResidenteDetalleProvider(item.id));
      ref.invalidate(itemsProyectoProvider);
      if (context.mounted) {
        mostrarMensaje(context, 'Ítem asignado.');
      }
    } catch (e) {
      if (context.mounted) {
        _mostrarError(context, e);
      }
    }
  }

  void _mostrarResultado(
    BuildContext context,
    ResultadoEspera resultado, {
    String mensajeExito = 'Cambio aplicado.',
  }) {
    mostrarMensaje(
      context,
      mensajeDeResultadoEspera(resultado, exito: mensajeExito),
    );
  }

  void _mostrarError(BuildContext context, Object e) {
    mostrarMensaje(context, itemDetalleMensajeError(e));
  }
}
