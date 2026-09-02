/// item_detalle_widgets.dart — Widgets de visualización del detalle de ítem.
///
/// Compartidos entre DetalleItemResidenteScreen y CoordinadorDetalleItemScreen.
/// SOLO visualización: ninguno ejecuta acciones de negocio (transiciones,
/// aprobaciones, asignaciones). La sección de acciones la inyecta cada rol
/// mediante el parámetro [ItemDetalleCuerpo.acciones].
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ctt_mobile/core/network/extraer_detalle_backend.dart';
import 'package:ctt_mobile/domain/entities/residente_models.dart';
import 'package:ctt_mobile/presentation/residente/residente_providers.dart';
import 'package:ctt_mobile/presentation/shared/badge_estado_item.dart';

// ── Cuerpo principal ──────────────────────────────────────────────────────────

class ItemDetalleCuerpo extends StatelessWidget {
  const ItemDetalleCuerpo({
    super.key,
    required this.item,
    required this.acciones,
  });

  final ItemResidente item;

  /// Sección de acciones inyectada por el rol (Residente o Coordinador).
  final Widget acciones;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
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
            const SizedBox(height: 8),
            Text(
              item.fechaLimite != null
                  ? 'Fecha límite: ${_parseFechaLimite(item.fechaLimite!)}'
                  : 'Sin fecha límite',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: item.fechaLimite != null
                        ? null
                        : Colors.grey.shade500,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              item.duracionEstimadaHoras != null
                  ? 'Duración estimada: ${_formatDuracion(item.duracionEstimadaHoras!)} h'
                  : 'Sin estimar',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: item.duracionEstimadaHoras != null
                        ? null
                        : Colors.grey.shade500,
                  ),
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 8),
            acciones,
            const SizedBox(height: 24),
            const Divider(),
            const ItemDetalleEncabezado(
              titulo: 'Historial de cambios',
              icono: Icons.history,
            ),
            ItemDetalleHistorial(itemId: item.id),
            const SizedBox(height: 16),
            const Divider(),
            const ItemDetalleEncabezado(
              titulo: 'Comentarios',
              icono: Icons.comment_outlined,
            ),
            ItemDetalleComentarios(itemId: item.id),
            const SizedBox(height: 16),
            const Divider(),
            const ItemDetalleEncabezado(
              titulo: 'Evidencias fotográficas',
              icono: Icons.photo_library_outlined,
            ),
            ItemDetalleEvidencias(itemId: item.id),
            const SizedBox(height: 32),
          ],
        ),
      );
}

String _parseFechaLimite(String s) {
  try {
    final dt = DateTime.parse(s);
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  } catch (_) {
    return s;
  }
}

String _formatDuracion(double h) =>
    h % 1 == 0 ? h.toInt().toString() : h.toString();

// ── Encabezado de sección ─────────────────────────────────────────────────────

class ItemDetalleEncabezado extends StatelessWidget {
  const ItemDetalleEncabezado({
    super.key,
    required this.titulo,
    required this.icono,
  });

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

// ── Historial ─────────────────────────────────────────────────────────────────

class ItemDetalleHistorial extends ConsumerWidget {
  const ItemDetalleHistorial({super.key, required this.itemId});
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
              child: Text('Error: $e', style: const TextStyle(color: Colors.red)),
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
                    .map((e) => ItemDetalleEntradaTile(entrada: e))
                    .toList(),
              );
            },
          );
}

class ItemDetalleEntradaTile extends StatelessWidget {
  const ItemDetalleEntradaTile({super.key, required this.entrada});
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
          CircleAvatar(
            radius: 16,
            child: Text(inicial, style: const TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _labelAccion(entrada.accion),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
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
    return '${l.day.toString().padLeft(2, '0')}/'
        '${l.month.toString().padLeft(2, '0')}/${l.year} '
        '${l.hour.toString().padLeft(2, '0')}:'
        '${l.minute.toString().padLeft(2, '0')}';
  }
}

// ── Comentarios ───────────────────────────────────────────────────────────────

class ItemDetalleComentarios extends ConsumerWidget {
  const ItemDetalleComentarios({super.key, required this.itemId});
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
              child: Text('Error: $e', style: const TextStyle(color: Colors.red)),
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
                    .map((c) => ItemDetalleComentarioTile(comentario: c))
                    .toList(),
              );
            },
          );
}

class ItemDetalleComentarioTile extends StatelessWidget {
  const ItemDetalleComentarioTile({super.key, required this.comentario});
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
          CircleAvatar(
            radius: 16,
            child: Text(inicial, style: const TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  comentario.nombreUsuario ?? 'Usuario',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
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
    return '${l.day.toString().padLeft(2, '0')}/'
        '${l.month.toString().padLeft(2, '0')}/${l.year}';
  }
}

// ── Evidencias ────────────────────────────────────────────────────────────────

class ItemDetalleEvidencias extends ConsumerWidget {
  const ItemDetalleEvidencias({super.key, required this.itemId});
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
              child: Text('Error: $e', style: const TextStyle(color: Colors.red)),
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
                    ItemDetalleMiniaturaEvidencia(evidencia: evidencias[i]),
              );
            },
          );
}

class ItemDetalleMiniaturaEvidencia extends StatelessWidget {
  const ItemDetalleMiniaturaEvidencia({super.key, required this.evidencia});
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
          child: Icon(
            Icons.broken_image_outlined,
            color: Colors.grey.shade400,
          ),
        ),
      ),
    );
  }
}

// ── Botón de acción genérico ──────────────────────────────────────────────────

class ItemDetalleBotonAccion extends StatelessWidget {
  const ItemDetalleBotonAccion({
    super.key,
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

// ── Mensaje de estado informativo ─────────────────────────────────────────────

class ItemDetalleMensajeEstado extends StatelessWidget {
  const ItemDetalleMensajeEstado({
    super.key,
    required this.icono,
    required this.texto,
  });

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

// ── Helper de error ───────────────────────────────────────────────────────────

String itemDetalleMensajeError(Object e) {
  if (e is DioException) {
    // Prioriza el `detail` legible del backend (parseo compartido, CTT-65);
    // si no hay detail, cae a un mensaje según el status HTTP.
    final data = e.response?.data;
    final tieneDetail = data is Map<String, dynamic> && data['detail'] != null;
    if (tieneDetail) return extraerDetalleBackend(e);
    final status = e.response?.statusCode;
    return status != null
        ? 'Error $status del servidor'
        : 'Sin conexión con el servidor';
  }
  return e.toString();
}
