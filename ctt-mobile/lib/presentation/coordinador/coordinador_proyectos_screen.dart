library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ctt_mobile/data/repositories/coordinador_repository.dart';
import 'package:ctt_mobile/domain/entities/coordinador_models.dart';
import 'package:ctt_mobile/presentation/coordinador/coordinador_providers.dart';
import 'package:ctt_mobile/presentation/shared/badge_notificaciones.dart';
import 'package:ctt_mobile/presentation/shared/error_vista.dart';
import 'package:ctt_mobile/presentation/shared/layout_constants.dart';
import 'package:ctt_mobile/presentation/shared/logout_helper.dart';

class CoordinadorProyectosScreen extends ConsumerStatefulWidget {
  const CoordinadorProyectosScreen({super.key});

  @override
  ConsumerState<CoordinadorProyectosScreen> createState() =>
      _CoordinadorProyectosScreenState();
}

class _CoordinadorProyectosScreenState
    extends ConsumerState<CoordinadorProyectosScreen> {
  bool _mostrarReal = false;

  @override
  Widget build(BuildContext context) {
    final dashboardAsync = ref.watch(dashboardProyectosProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const Icon(Icons.business_center),
        title: const Text('Proyectos'),
        actions: [
          _BadgeConflictos(
            onTap: () => context.push('/coordinador/conflictos'),
          ),
          BadgeNotificaciones(
            onTap: () => context.push('/coordinador/notificaciones'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: () => confirmarLogout(context, ref),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/coordinador/crear-proyecto'),
        tooltip: 'Nuevo proyecto',
        child: const Icon(Icons.add),
      ),
      body: dashboardAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorVista(
          mensaje: e.toString(),
          onReintento: () => ref.invalidate(dashboardProyectosProvider),
        ),
        data: (proyectos) {
          if (proyectos.isEmpty) {
            return const Center(child: Text('No hay proyectos disponibles.'));
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      label: Text('% Completo'),
                      icon: Icon(Icons.bar_chart_outlined),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text('% Real (hojas)'),
                      icon: Icon(Icons.account_tree_outlined),
                    ),
                  ],
                  selected: {_mostrarReal},
                  onSelectionChanged: (s) =>
                      setState(() => _mostrarReal = s.first),
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async =>
                      ref.invalidate(dashboardProyectosProvider),
                  child: ListView.builder(
                    padding: const EdgeInsets.only(
                      top: 8,
                      bottom: kFabListPaddingBottom,
                    ),
                    itemCount: proyectos.length,
                    itemBuilder: (_, i) => _TarjetaProyecto(
                      proyecto: proyectos[i],
                      mostrarReal: _mostrarReal,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Tarjeta de proyecto con avance ────────────────────────────────────────────

class _TarjetaProyecto extends ConsumerStatefulWidget {
  const _TarjetaProyecto({
    required this.proyecto,
    required this.mostrarReal,
  });

  final DashboardProyecto proyecto;
  final bool mostrarReal;

  @override
  ConsumerState<_TarjetaProyecto> createState() => _TarjetaProyectoState();
}

class _TarjetaProyectoState extends ConsumerState<_TarjetaProyecto> {
  bool _loadingEditar = false;

  Future<void> _abrirEditar() async {
    setState(() => _loadingEditar = true);
    try {
      final proyecto = await ref
          .read(coordinadorRepositoryProvider)
          .getProyecto(widget.proyecto.id);
      if (mounted) {
        context.push(
          '/coordinador/${widget.proyecto.id}/editar',
          extra: proyecto,
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo cargar el proyecto. Intenta de nuevo.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingEditar = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (label, color) = _infoEstado(widget.proyecto.estado);
    final pct = widget.mostrarReal
        ? widget.proyecto.pctReal
        : widget.proyecto.pctCompleto;
    final sufijo = widget.mostrarReal ? 'real' : 'completo';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/coordinador/${widget.proyecto.id}/items'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.proyecto.nombre,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _ChipEstado(label: label, color: color),
                  if (_loadingEditar)
                    const SizedBox(
                      width: 40,
                      height: 40,
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      tooltip: 'Editar proyecto',
                      visualDensity: VisualDensity.compact,
                      onPressed: _abrirEditar,
                    ),
                  IconButton(
                    icon: const Icon(Icons.history_outlined, size: 20),
                    tooltip: 'Ver historial',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => context
                        .push('/coordinador/${widget.proyecto.id}/historial'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.group_outlined, size: 20),
                    tooltip: 'Miembros',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => context
                        .push('/coordinador/${widget.proyecto.id}/miembros'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: pct / 100,
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
              const SizedBox(height: 4),
              Text(
                '${pct.toStringAsFixed(1)}% $sufijo',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  (String, Color) _infoEstado(String valor) => switch (valor) {
        'activo' => ('Activo', Colors.green),
        'pausado' => ('Pausado', Colors.orange),
        'cerrado' => ('Cerrado', Colors.grey),
        _ => (valor, Colors.blue),
      };
}

class _ChipEstado extends StatelessWidget {
  const _ChipEstado({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      );
}

// ── AppBar: badges ────────────────────────────────────────────────────────────

class _BadgeConflictos extends ConsumerWidget {
  const _BadgeConflictos({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendientes = ref
            .watch(conflictosPendientesProvider)
            .whenOrNull(data: (cs) => cs.length) ??
        0;
    return IconButton(
      tooltip: 'Conflictos',
      onPressed: onTap,
      icon: Badge(
        isLabelVisible: pendientes > 0,
        label: Text(pendientes > 9 ? '9+' : '$pendientes'),
        child: const Icon(Icons.merge_type_outlined),
      ),
    );
  }
}
