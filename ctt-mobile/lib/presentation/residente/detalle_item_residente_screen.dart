/// detalle_item_residente_screen.dart — Detalle de ítem para el Residente.
///
/// Muestra datos del ítem + historial, comentarios, y evidencias.
/// Acciones disponibles según el estado del ítem:
///   pendiente_revision → Aprobar / Rechazar (comentario obligatorio)
///   problema           → Cerrar problema
///   cualquier estado editable → Marcar problema, Asignar trabajador
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ctt_mobile/data/repositories/residente_repository.dart';
import 'package:ctt_mobile/domain/entities/residente_models.dart';
import 'package:ctt_mobile/domain/enums/enums_ctt.dart';
import 'package:ctt_mobile/presentation/residente/residente_providers.dart';
import 'package:ctt_mobile/presentation/trabajador/mis_items_screen.dart';

class DetalleItemResidenteScreen extends ConsumerWidget {
  const DetalleItemResidenteScreen({super.key, required this.itemId});
  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemAsync = ref.watch(itemResidenteProvider(itemId));

    return Scaffold(
      appBar: AppBar(title: const Text('Detalle del ítem')),
      body: itemAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('No se pudo cargar el ítem: $e'),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => ref.invalidate(itemResidenteProvider(itemId)),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
        data: (item) => _CuerpoDetalle(item: item),
      ),
    );
  }
}

// ── Cuerpo principal ──────────────────────────────────────────────────────────

class _CuerpoDetalle extends StatelessWidget {
  const _CuerpoDetalle({required this.item});
  final ItemResidente item;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabecera
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
            const SizedBox(height: 4),
            if (item.asignadoNombre != null)
              Text(
                'Asignado: ${item.asignadoNombre}',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
              )
            else
              Text(
                'Sin asignar',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Colors.grey.shade500,
                    ),
              ),
            if (item.descripcion != null && item.descripcion!.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                item.descripcion!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 8),

            // Acciones
            _AccionesResidente(item: item),

            const SizedBox(height: 24),
            const Divider(),

            // Historial
            const _EncabezadoSeccion(titulo: 'Historial de cambios', icono: Icons.history),
            _SeccionHistorial(itemId: item.id),

            const SizedBox(height: 16),
            const Divider(),

            // Comentarios
            const _EncabezadoSeccion(titulo: 'Comentarios', icono: Icons.comment_outlined),
            _SeccionComentarios(itemId: item.id),

            const SizedBox(height: 16),
            const Divider(),

            // Evidencias
            const _EncabezadoSeccion(titulo: 'Evidencias fotográficas', icono: Icons.photo_library_outlined),
            _SeccionEvidencias(itemId: item.id),

            const SizedBox(height: 32),
          ],
        ),
      );
}

class _EncabezadoSeccion extends StatelessWidget {
  const _EncabezadoSeccion({required this.titulo, required this.icono});
  final String titulo;
  final IconData icono;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icono, size: 18, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              titulo,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
          ],
        ),
      );
}

// ── Acciones por estado ───────────────────────────────────────────────────────

class _AccionesResidente extends ConsumerWidget {
  const _AccionesResidente({required this.item});
  final ItemResidente item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = EstadoItem.fromString(item.estado);

    if (estado == EstadoItem.terminado) {
      return const _MensajeEstado(
        icono: Icons.verified_outlined,
        texto: 'Este ítem fue marcado como terminado.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Aprobar / Rechazar (pendiente_revision)
        if (estado == EstadoItem.pendienteRevision) ...[
          _BotonAccion(
            label: 'Aprobar',
            icono: Icons.verified_outlined,
            color: Colors.green.shade700,
            filled: true,
            onTap: () => _aprobar(context, ref),
          ),
          const SizedBox(height: 12),
          _BotonAccion(
            label: 'Rechazar',
            icono: Icons.close,
            color: Colors.red.shade700,
            filled: false,
            onTap: () => _mostrarDialogoRechazar(context, ref),
          ),
          const SizedBox(height: 12),
        ],
        // Cerrar problema (estado = problema)
        if (estado == EstadoItem.problema) ...[
          _BotonAccion(
            label: 'Cerrar problema',
            icono: Icons.check_circle_outline,
            color: Colors.orange.shade700,
            filled: true,
            onTap: () => _cerrarProblema(context, ref),
          ),
          const SizedBox(height: 12),
        ],
        // Marcar problema (todos los estados editables excepto problema)
        if (estado != EstadoItem.problema) ...[
          _BotonAccion(
            label: 'Marcar problema',
            icono: Icons.warning_amber_outlined,
            color: Colors.red.shade700,
            filled: false,
            onTap: () => _mostrarDialogoProblema(context, ref),
          ),
          const SizedBox(height: 12),
        ],
        // Asignar (todos los estados editables)
        _BotonAccion(
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
      await ref.read(residenteRepositoryProvider).transicionarItem(
            item.id,
            EstadoItem.terminado.valor,
          );
      ref.invalidate(itemResidenteProvider(item.id));
      ref.invalidate(itemsProyectoProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ítem aprobado y marcado como terminado.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_mensajeError(e))),
        );
      }
    }
  }

  Future<void> _cerrarProblema(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(residenteRepositoryProvider).cerrarProblema(item.id);
      ref.invalidate(itemResidenteProvider(item.id));
      ref.invalidate(itemsProyectoProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Problema cerrado.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_mensajeError(e))),
        );
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
      await ref.read(residenteRepositoryProvider).transicionarItem(
            item.id,
            EstadoItem.enProgreso.valor,
            comentario: comentario,
          );
      ref.invalidate(itemResidenteProvider(item.id));
      ref.invalidate(itemsProyectoProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ítem rechazado.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_mensajeError(e))),
        );
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
      await ref.read(residenteRepositoryProvider).transicionarItem(
            item.id,
            EstadoItem.problema.valor,
            descripcionProblema: descripcion,
          );
      ref.invalidate(itemResidenteProvider(item.id));
      ref.invalidate(itemsProyectoProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Problema reportado.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_mensajeError(e))),
        );
      }
    }
  }

  Future<void> _mostrarDialogoAsignar(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final usuarioId = await showDialog<String>(
      context: context,
      // Consumer permite usar Riverpod dentro del diálogo.
      builder: (ctx) => Consumer(
        builder: (ctx, dialogRef, _) {
          final usuariosAsync = dialogRef.watch(usuariosEmpresaProvider);
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
      ref.invalidate(itemResidenteProvider(item.id));
      ref.invalidate(itemsProyectoProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ítem asignado.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_mensajeError(e))),
        );
      }
    }
  }
}

// ── Sección: historial ────────────────────────────────────────────────────────

class _SeccionHistorial extends ConsumerWidget {
  const _SeccionHistorial({required this.itemId});
  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(historialItemProvider(itemId)).when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Error: $e',
                style: const TextStyle(color: Colors.red),
              ),
            ),
            data: (entradas) {
              if (entradas.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Sin entradas en el historial.',
                    style: TextStyle(color: Colors.grey),
                  ),
                );
              }
              return Column(
                children: entradas
                    .map((e) => _EntradaHistorialTile(entrada: e))
                    .toList(),
              );
            },
          );
}

class _EntradaHistorialTile extends StatelessWidget {
  const _EntradaHistorialTile({required this.entrada});
  final EntradaHistorial entrada;

  @override
  Widget build(BuildContext context) {
    final inicial = entrada.nombreUsuario?.isNotEmpty == true
        ? entrada.nombreUsuario![0].toUpperCase()
        : '?';
    final transicion =
        entrada.estadoAnterior != null && entrada.estadoNuevo != null
            ? '${entrada.estadoAnterior} → ${entrada.estadoNuevo}'
            : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(radius: 16, child: Text(inicial, style: const TextStyle(fontSize: 12))),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _labelAccion(entrada.accion),
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                if (transicion != null)
                  Text(transicion, style: const TextStyle(fontSize: 12)),
                if (entrada.detalle != null)
                  Text(entrada.detalle!, style: const TextStyle(fontSize: 12)),
                Text(
                  '${entrada.nombreUsuario ?? "Sistema"} · ${_formatFecha(entrada.createdAt)}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _labelAccion(String accion) => switch (accion) {
        'cambio_estado' => 'Cambio de estado',
        'cierre_problema' => 'Cierre de problema',
        'reversion_terminado' => 'Reversión de terminado',
        _ => accion,
      };

  String _formatFecha(DateTime dt) {
    final l = dt.toLocal();
    return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}/${l.year} '
        '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }
}

// ── Sección: comentarios ──────────────────────────────────────────────────────

class _SeccionComentarios extends ConsumerWidget {
  const _SeccionComentarios({required this.itemId});
  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(comentariosItemProvider(itemId)).when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Error: $e',
                style: const TextStyle(color: Colors.red),
              ),
            ),
            data: (comentarios) {
              if (comentarios.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Sin comentarios.',
                    style: TextStyle(color: Colors.grey),
                  ),
                );
              }
              return Column(
                children: comentarios
                    .map((c) => _ComentarioTile(comentario: c))
                    .toList(),
              );
            },
          );
}

class _ComentarioTile extends StatelessWidget {
  const _ComentarioTile({required this.comentario});
  final ComentarioItem comentario;

  @override
  Widget build(BuildContext context) {
    final inicial = comentario.nombreUsuario?.isNotEmpty == true
        ? comentario.nombreUsuario![0].toUpperCase()
        : '?';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(radius: 16, child: Text(inicial, style: const TextStyle(fontSize: 12))),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  comentario.nombreUsuario ?? 'Usuario',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                Text(comentario.texto, style: const TextStyle(fontSize: 13)),
                Text(
                  _formatFecha(comentario.createdAt),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatFecha(DateTime dt) {
    final l = dt.toLocal();
    return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}/${l.year}';
  }
}

// ── Sección: evidencias ───────────────────────────────────────────────────────

class _SeccionEvidencias extends ConsumerWidget {
  const _SeccionEvidencias({required this.itemId});
  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(evidenciasItemProvider(itemId)).when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Error: $e',
                style: const TextStyle(color: Colors.red),
              ),
            ),
            data: (evidencias) {
              if (evidencias.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Sin evidencias.',
                    style: TextStyle(color: Colors.grey),
                  ),
                );
              }
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: evidencias.length,
                itemBuilder: (_, i) =>
                    _MiniaturaEvidencia(evidencia: evidencias[i]),
              );
            },
          );
}

class _MiniaturaEvidencia extends StatelessWidget {
  const _MiniaturaEvidencia({required this.evidencia});
  final EvidenciaItem evidencia;

  @override
  Widget build(BuildContext context) {
    final url = evidencia.thumbnailUrl ?? evidencia.s3Url;
    if (url == null) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.image_not_supported_outlined,
          color: Colors.grey.shade400,
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(
          color: Colors.grey.shade200,
          child: const Center(
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        errorWidget: (_, __, ___) => Container(
          color: Colors.grey.shade200,
          child: Icon(Icons.broken_image_outlined, color: Colors.grey.shade400),
        ),
      ),
    );
  }
}

// ── Widgets auxiliares ────────────────────────────────────────────────────────

class _BotonAccion extends StatelessWidget {
  const _BotonAccion({
    required this.label,
    required this.icono,
    required this.color,
    required this.filled,
    required this.onTap,
  });
  final String label;
  final IconData icono;
  final Color color;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (filled) {
      return FilledButton.icon(
        icon: Icon(icono),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: color,
          minimumSize: const Size.fromHeight(48),
        ),
        onPressed: onTap,
      );
    }
    return OutlinedButton.icon(
      icon: Icon(icono, color: color),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.5)),
        minimumSize: const Size.fromHeight(48),
      ),
      onPressed: onTap,
    );
  }
}

class _MensajeEstado extends StatelessWidget {
  const _MensajeEstado({required this.icono, required this.texto});
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

// ── Helper de error ──────────────────────────────────────────────────────────

/// Extrae el mensaje legible de un error Dio (incluyendo detail del backend).
String _mensajeError(Object e) {
  if (e is DioException) {
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      final detail = data['detail'];
      if (detail is String) return detail;
      // 409 de conflicto de concurrencia: detail es un Map con 'mensaje'.
      if (detail is Map<String, dynamic>) {
        final msg = detail['mensaje'];
        if (msg is String) return msg;
      }
    }
    final status = e.response?.statusCode;
    return status != null
        ? 'Error $status del servidor'
        : 'Sin conexión con el servidor';
  }
  return e.toString();
}
