library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ctt_mobile/data/repositories/coordinador_repository.dart';
import 'package:ctt_mobile/domain/entities/coordinador_models.dart';
import 'package:ctt_mobile/presentation/coordinador/coordinador_providers.dart';
import 'package:ctt_mobile/presentation/shared/error_vista.dart';
import 'package:ctt_mobile/presentation/shared/vista_vacia.dart';

class ConflictosScreen extends ConsumerWidget {
  const ConflictosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conflictosAsync = ref.watch(conflictosPendientesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Conflictos pendientes')),
      body: conflictosAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorVista(
          mensaje: e.toString(),
          onReintento: () => ref.invalidate(conflictosPendientesProvider),
        ),
        data: (conflictos) {
          if (conflictos.isEmpty) {
            return const VistaVacia(
              mensaje: 'No hay conflictos pendientes',
              icono: Icons.check_circle_outline,
              colorIcono: Colors.green,
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(conflictosPendientesProvider),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: conflictos.length,
              itemBuilder: (_, i) => _CardConflicto(conflicto: conflictos[i]),
            ),
          );
        },
      ),
    );
  }
}

// ── Card de conflicto ─────────────────────────────────────────────────────────

class _CardConflicto extends ConsumerStatefulWidget {
  const _CardConflicto({required this.conflicto});
  final ConflictoSync conflicto;

  @override
  ConsumerState<_CardConflicto> createState() => _CardConflictoState();
}

class _CardConflictoState extends ConsumerState<_CardConflicto> {
  String? _versionEnProceso;

  Future<void> _resolver(String version) async {
    if (_versionEnProceso != null) return;
    setState(() => _versionEnProceso = version);
    try {
      await ref
          .read(coordinadorRepositoryProvider)
          .resolverConflicto(widget.conflicto.id, version);
      if (!mounted) return;
      ref.invalidate(conflictosPendientesProvider);
    } on ErrorCoordinador catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.mensaje)),
      );
      // El 409 puede significar que el conflicto ya fue resuelto por otro — refrescar.
      ref.invalidate(conflictosPendientesProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al resolver: $e')),
      );
    } finally {
      if (mounted) setState(() => _versionEnProceso = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.conflicto;
    final itemAsync = ref.watch(itemParaConflictoProvider(c.itemId));
    final nombreItem = itemAsync.maybeWhen(
      data: (item) => item?.nombre ?? c.itemId,
      orElse: () => null,
    );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(
              nombreItem: nombreItem,
              itemIdFallback: c.itemId,
              dispositivoId: c.dispositivoId,
              createdAt: c.createdAt,
            ),
            const Divider(height: 20),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _ColumnaVersion(
                      titulo: 'DISPOSITIVO (local)',
                      cambio: c.cambioLocal,
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: _ColumnaVersion(
                      titulo: 'SERVIDOR',
                      cambio: c.cambioServidor,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _versionEnProceso != null
                        ? null
                        : () => _resolver('local'),
                    child: _versionEnProceso == 'local'
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Usar local'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _versionEnProceso != null
                        ? null
                        : () => _resolver('servidor'),
                    child: _versionEnProceso == 'servidor'
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Usar servidor'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Subwidgets de la card ─────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({
    required this.nombreItem,
    required this.itemIdFallback,
    required this.dispositivoId,
    required this.createdAt,
  });

  final String? nombreItem;
  final String itemIdFallback;
  final String dispositivoId;
  final DateTime createdAt;

  @override
  Widget build(BuildContext context) {
    final dispCorto = _truncarId(dispositivoId);
    final fechaStr = _formatFecha(createdAt);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (nombreItem == null)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        itemIdFallback,
                        style: Theme.of(context).textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const SizedBox(
                      height: 12,
                      width: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    ),
                  ],
                )
              else
                Text(
                  nombreItem!,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              const SizedBox(height: 2),
              Text(
                '$fechaStr · disp: $dispCorto',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _truncarId(String id) {
    if (id.length <= 12) return id;
    return '${id.substring(0, 4)}…${id.substring(id.length - 4)}';
  }

  static String _formatFecha(DateTime dt) {
    final d = dt.toLocal();
    const meses = [
      'ene',
      'feb',
      'mar',
      'abr',
      'may',
      'jun',
      'jul',
      'ago',
      'sep',
      'oct',
      'nov',
      'dic',
    ];
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${meses[d.month - 1]} ${d.year} · $h:$m';
  }
}

class _ColumnaVersion extends StatelessWidget {
  const _ColumnaVersion({required this.titulo, this.cambio});
  final String titulo;
  final CambioConflicto? cambio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          if (cambio == null)
            Text(
              '(sin datos)',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
            )
          else ...[
            _InfoFila(etiqueta: 'Estado', valor: cambio!.estado),
            if (cambio!.comentario != null)
              _InfoFila(
                etiqueta: 'Comentario',
                valor: '"${cambio!.comentario}"',
              ),
          ],
        ],
      ),
    );
  }
}

class _InfoFila extends StatelessWidget {
  const _InfoFila({required this.etiqueta, required this.valor});
  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.bodySmall,
          children: [
            TextSpan(
              text: '$etiqueta: ',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(text: valor),
          ],
        ),
      ),
    );
  }
}
