library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ctt_mobile/data/repositories/coordinador_repository.dart';
import 'package:ctt_mobile/domain/entities/coordinador_models.dart';
import 'package:ctt_mobile/domain/entities/residente_models.dart';
import 'package:ctt_mobile/presentation/coordinador/coordinador_providers.dart';
import 'package:ctt_mobile/presentation/residente/residente_providers.dart';
import 'package:ctt_mobile/presentation/shared/layout_constants.dart';

class MiembrosProyectoScreen extends ConsumerWidget {
  const MiembrosProyectoScreen({super.key, required this.proyectoId});
  final String proyectoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final miembrosAsync = ref.watch(miembrosProyectoProvider(proyectoId));

    return Scaffold(
      appBar: AppBar(title: const Text('Miembros del proyecto')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _mostrarSelectorUsuario(context, proyectoId),
        tooltip: 'Asignar miembro',
        child: const Icon(Icons.person_add_outlined),
      ),
      body: miembrosAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('No se pudo cargar los miembros: $e'),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () =>
                      ref.invalidate(miembrosProyectoProvider(proyectoId)),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
        data: (miembros) {
          if (miembros.isEmpty) {
            return const Center(
              child: Text(
                'Sin miembros asignados a este proyecto.',
                style: TextStyle(color: Colors.grey),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(miembrosProyectoProvider(proyectoId)),
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: kFabListPaddingBottom),
              itemCount: miembros.length,
              itemBuilder: (_, i) => _MiembroTile(
                miembro: miembros[i],
                proyectoId: proyectoId,
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Rol label (compartido por tile y selector) ────────────────────────────────

String _labelRol(String rol) => switch (rol) {
      'coordinador' => 'Coordinador',
      'residente' => 'Residente',
      'trabajador' => 'Trabajador',
      'admin' => 'Admin',
      _ => rol,
    };

// ── Tile de miembro con acción quitar ─────────────────────────────────────────

class _MiembroTile extends ConsumerStatefulWidget {
  const _MiembroTile({required this.miembro, required this.proyectoId});
  final MiembroProyecto miembro;
  final String proyectoId;

  @override
  ConsumerState<_MiembroTile> createState() => _MiembroTileState();
}

class _MiembroTileState extends ConsumerState<_MiembroTile> {
  bool _quitando = false;

  Future<void> _desasignar() async {
    setState(() => _quitando = true);
    try {
      await ref
          .read(coordinadorRepositoryProvider)
          .desasignarMiembro(widget.proyectoId, widget.miembro.usuarioId);

      if (!mounted) return;
      // Capturar antes de invalidar: el tile se eliminará en el siguiente frame.
      final container = ProviderScope.containerOf(context);
      final messenger = ScaffoldMessenger.of(context);
      final proyectoId = widget.proyectoId;
      final usuarioId = widget.miembro.usuarioId;
      final nombre = widget.miembro.nombreCompleto;

      ref.invalidate(miembrosProyectoProvider(proyectoId));

      messenger.showSnackBar(
        SnackBar(
          content: Text('$nombre fue quitado del proyecto'),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Deshacer',
            onPressed: () async {
              try {
                await container
                    .read(coordinadorRepositoryProvider)
                    .asignarMiembro(proyectoId, usuarioId);
                container.invalidate(miembrosProyectoProvider(proyectoId));
              } catch (_) {}
            },
          ),
        ),
      );
    } on ErrorMiembroConItems catch (e) {
      if (!mounted) return;
      setState(() => _quitando = false);
      _mostrarItmsActivos(context, widget.miembro, widget.proyectoId, e.blockingItems);
    } on ErrorCoordinador catch (e) {
      if (!mounted) return;
      setState(() => _quitando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.mensaje)),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _quitando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error al quitar. Intenta de nuevo.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final inicial = widget.miembro.nombreCompleto.isNotEmpty
        ? widget.miembro.nombreCompleto[0].toUpperCase()
        : '?';
    return ListTile(
      leading: CircleAvatar(child: Text(inicial)),
      title: Text(widget.miembro.nombreCompleto),
      subtitle: Text(
        '${_labelRol(widget.miembro.rolEnProyecto)} · ${_labelEstado(widget.miembro.estado)}',
      ),
      trailing: _quitando
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : IconButton(
              icon: const Icon(Icons.person_remove_outlined),
              tooltip: 'Quitar del proyecto',
              onPressed: _desasignar,
            ),
    );
  }

  String _labelEstado(String estado) => switch (estado) {
        'activo' => 'Activo',
        'inactivo' => 'Inactivo',
        _ => estado,
      };
}

// ── Selector de usuario (asignar) ─────────────────────────────────────────────

void _mostrarSelectorUsuario(BuildContext context, String proyectoId) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (_, sc) => _SelectorMiembroSheet(
        proyectoId: proyectoId,
        scrollController: sc,
      ),
    ),
  );
}

class _SelectorMiembroSheet extends ConsumerStatefulWidget {
  const _SelectorMiembroSheet({
    required this.proyectoId,
    required this.scrollController,
  });

  final String proyectoId;
  final ScrollController scrollController;

  @override
  ConsumerState<_SelectorMiembroSheet> createState() =>
      _SelectorMiembroSheetState();
}

class _SelectorMiembroSheetState extends ConsumerState<_SelectorMiembroSheet> {
  String? _asignandoId;
  String? _errorAsignar;

  Future<void> _asignar(UsuarioEmpresa usuario) async {
    setState(() {
      _asignandoId = usuario.id;
      _errorAsignar = null;
    });
    try {
      await ref
          .read(coordinadorRepositoryProvider)
          .asignarMiembro(widget.proyectoId, usuario.id);
      ref.invalidate(miembrosProyectoProvider(widget.proyectoId));
      if (mounted) Navigator.of(context).pop();
    } on ErrorCoordinador catch (e) {
      if (mounted) setState(() { _asignandoId = null; _errorAsignar = e.mensaje; });
    } catch (_) {
      if (mounted) {
        setState(() {
          _asignandoId = null;
          _errorAsignar = 'Error al asignar. Intenta de nuevo.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final usuariosAsync = ref.watch(usuariosEmpresaProvider);

    return Column(
      children: [
        const _ManijaDrag(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            'Seleccionar usuario',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        if (_errorAsignar != null)
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.errorContainer,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Text(
              _errorAsignar!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
                fontSize: 13,
              ),
            ),
          ),
        const Divider(height: 1),
        Expanded(
          child: usuariosAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('No se pudo cargar los usuarios: $e'),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => ref.invalidate(usuariosEmpresaProvider),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            ),
            data: (usuarios) {
              if (usuarios.isEmpty) {
                return const Center(child: Text('Sin usuarios disponibles.'));
              }
              return ListView.builder(
                controller: widget.scrollController,
                itemCount: usuarios.length,
                itemBuilder: (_, i) {
                  final u = usuarios[i];
                  final asignando = _asignandoId == u.id;
                  return ListTile(
                    leading: CircleAvatar(
                      child: Text(
                        u.nombreCompleto.isNotEmpty
                            ? u.nombreCompleto[0].toUpperCase()
                            : '?',
                      ),
                    ),
                    title: Text(u.nombreCompleto),
                    subtitle: Text(_labelRol(u.rol)),
                    trailing: asignando
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : null,
                    enabled: _asignandoId == null,
                    onTap: _asignandoId == null ? () => _asignar(u) : null,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Sheet de ítems activos (409 al quitar) ────────────────────────────────────

void _mostrarItmsActivos(
  BuildContext context,
  MiembroProyecto miembro,
  String proyectoId,
  List<ItemBloqueante> blockingItems,
) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (_, sc) => _ItmsActivosSheet(
        miembro: miembro,
        proyectoId: proyectoId,
        blockingItems: blockingItems,
        scrollController: sc,
      ),
    ),
  );
}

class _ItmsActivosSheet extends ConsumerStatefulWidget {
  const _ItmsActivosSheet({
    required this.miembro,
    required this.proyectoId,
    required this.blockingItems,
    required this.scrollController,
  });

  final MiembroProyecto miembro;
  final String proyectoId;
  final List<ItemBloqueante> blockingItems;
  final ScrollController scrollController;

  @override
  ConsumerState<_ItmsActivosSheet> createState() => _ItmsActivosSheetState();
}

class _ItmsActivosSheetState extends ConsumerState<_ItmsActivosSheet> {
  late List<ItemBloqueante> _items;
  bool _reintentando = false;

  @override
  void initState() {
    super.initState();
    _items = widget.blockingItems;
  }

  Future<void> _reintentar() async {
    setState(() => _reintentando = true);
    try {
      await ref
          .read(coordinadorRepositoryProvider)
          .desasignarMiembro(widget.proyectoId, widget.miembro.usuarioId);

      if (!mounted) return;
      final container = ProviderScope.containerOf(context);
      final messenger = ScaffoldMessenger.of(context);
      final proyectoId = widget.proyectoId;
      final usuarioId = widget.miembro.usuarioId;
      final nombre = widget.miembro.nombreCompleto;

      ref.invalidate(miembrosProyectoProvider(proyectoId));
      Navigator.of(context).pop();

      messenger.showSnackBar(
        SnackBar(
          content: Text('$nombre fue quitado del proyecto'),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Deshacer',
            onPressed: () async {
              try {
                await container
                    .read(coordinadorRepositoryProvider)
                    .asignarMiembro(proyectoId, usuarioId);
                container.invalidate(miembrosProyectoProvider(proyectoId));
              } catch (_) {}
            },
          ),
        ),
      );
    } on ErrorMiembroConItems catch (e) {
      if (!mounted) return;
      setState(() {
        _items = e.blockingItems;
        _reintentando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _reintentando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error al quitar. Intenta de nuevo.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final nombre = widget.miembro.nombreCompleto;
    final conteo = _items.length;

    return Column(
      children: [
        const _ManijaDrag(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            '$nombre tiene $conteo ${conteo == 1 ? 'ítem activo' : 'ítems activos'}',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            controller: widget.scrollController,
            itemCount: _items.length,
            itemBuilder: (_, i) {
              final item = _items[i];
              return ListTile(
                leading: const Icon(Icons.task_outlined),
                title: Text(item.nombre),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).pop();
                  context.push(
                    '/coordinador/${widget.proyectoId}/items/${item.id}',
                  );
                },
              );
            },
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _reintentando ? null : _reintentar,
              icon: _reintentando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.delete_outline),
              label: const Text('Reintentar quitar'),
            ),
          ),
        ),
        SizedBox(height: MediaQuery.of(context).padding.bottom),
      ],
    );
  }
}

// ── Widget compartido: manija del bottom sheet ────────────────────────────────

class _ManijaDrag extends StatelessWidget {
  const _ManijaDrag();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      );
}
