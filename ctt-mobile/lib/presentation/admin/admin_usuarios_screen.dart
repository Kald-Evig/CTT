library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ctt_mobile/data/repositories/admin_repository.dart';
import 'package:ctt_mobile/domain/entities/residente_models.dart';
import 'package:ctt_mobile/presentation/admin/admin_providers.dart';
import 'package:ctt_mobile/presentation/shared/error_vista.dart';
import 'package:ctt_mobile/presentation/shared/layout_constants.dart';
import 'package:ctt_mobile/presentation/shared/logout_helper.dart';

class AdminUsuariosScreen extends ConsumerStatefulWidget {
  const AdminUsuariosScreen({super.key});

  @override
  ConsumerState<AdminUsuariosScreen> createState() =>
      _AdminUsuariosScreenState();
}

class _AdminUsuariosScreenState extends ConsumerState<AdminUsuariosScreen> {
  bool _incluirInactivos = false;

  @override
  Widget build(BuildContext context) {
    final usuariosAsync = ref.watch(
      usuariosAdminProvider(incluirInactivos: _incluirInactivos),
    );

    return Scaffold(
      appBar: AppBar(
        leading: const Icon(Icons.admin_panel_settings),
        title: const Text('Usuarios'),
        actions: [
          IconButton(
            icon: const Icon(Icons.lock_outline),
            tooltip: 'Cerrar proyecto',
            onPressed: () => context.push('/admin/cerrar-proyecto'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: () => confirmarLogout(context, ref),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/admin/crear-usuario'),
        tooltip: 'Nuevo usuario',
        child: const Icon(Icons.person_add_outlined),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('Activos'),
                  icon: Icon(Icons.check_circle_outline),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('Todos'),
                  icon: Icon(Icons.people_outline),
                ),
              ],
              selected: {_incluirInactivos},
              onSelectionChanged: (s) =>
                  setState(() => _incluirInactivos = s.first),
            ),
          ),
          Expanded(
            child: usuariosAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorVista(
                mensaje: e.toString(),
                onReintento: () => ref.invalidate(usuariosAdminProvider),
              ),
              data: (usuarios) {
                if (usuarios.isEmpty) {
                  return Center(
                    child: Text(
                      _incluirInactivos
                          ? 'No hay usuarios en esta empresa.'
                          : 'No hay usuarios activos.',
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(usuariosAdminProvider),
                  child: ListView.builder(
                    padding: const EdgeInsets.only(
                      top: 8,
                      bottom: kFabListPaddingBottom,
                    ),
                    itemCount: usuarios.length,
                    itemBuilder: (_, i) => _TarjetaUsuario(
                      usuario: usuarios[i],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tarjeta de usuario ────────────────────────────────────────────────────────

class _TarjetaUsuario extends ConsumerStatefulWidget {
  const _TarjetaUsuario({required this.usuario});
  final UsuarioEmpresa usuario;

  @override
  ConsumerState<_TarjetaUsuario> createState() => _TarjetaUsuarioState();
}

class _TarjetaUsuarioState extends ConsumerState<_TarjetaUsuario> {
  bool _cargando = false;

  bool get _activo => widget.usuario.estado == 'activo';

  Future<void> _toggleEstado() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_activo ? 'Desactivar usuario' : 'Reactivar usuario'),
        content: Text(
          _activo
              ? '${widget.usuario.nombreCompleto} no podrá acceder a la empresa.'
              : '${widget.usuario.nombreCompleto} recuperará el acceso a la empresa.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(_activo ? 'Desactivar' : 'Reactivar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    setState(() => _cargando = true);
    try {
      final repo = ref.read(adminRepositoryProvider);
      if (_activo) {
        await repo.desactivarUsuario(widget.usuario.id);
      } else {
        await repo.reactivarUsuario(widget.usuario.id);
      }
      if (!mounted) return;
      ref.invalidate(usuariosAdminProvider);
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

  Future<void> _cambiarRol(String nuevoRol) async {
    setState(() => _cargando = true);
    try {
      await ref.read(adminRepositoryProvider).cambiarRol(
            widget.usuario.id,
            nuevoRol,
          );
      if (!mounted) return;
      ref.invalidate(usuariosAdminProvider);
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
    final (label, color) = _infoEstado(widget.usuario.estado);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.usuario.nombreCompleto,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.usuario.email,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _ChipEstado(label: label, color: color),
                      const SizedBox(width: 8),
                      _ChipRol(rol: widget.usuario.rol),
                    ],
                  ),
                ],
              ),
            ),
            if (_cargando)
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
            else ...[
              PopupMenuButton<String>(
                tooltip: 'Cambiar rol',
                icon: const Icon(Icons.swap_horiz_outlined),
                onSelected: _cambiarRol,
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'trabajador',
                    child: Text('Trabajador'),
                  ),
                  PopupMenuItem(
                    value: 'residente',
                    child: Text('Residente'),
                  ),
                  PopupMenuItem(
                    value: 'coordinador',
                    child: Text('Coordinador'),
                  ),
                ],
              ),
              IconButton(
                icon: Icon(
                  _activo
                      ? Icons.person_off_outlined
                      : Icons.person_outlined,
                ),
                tooltip: _activo ? 'Desactivar' : 'Reactivar',
                onPressed: _toggleEstado,
              ),
            ],
          ],
        ),
      ),
    );
  }

  (String, Color) _infoEstado(String valor) => switch (valor) {
        'activo' => ('Activo', Colors.green),
        'inactivo' => ('Inactivo', Colors.grey),
        _ => (valor, Colors.blue),
      };
}

class _ChipEstado extends StatelessWidget {
  const _ChipEstado({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
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

class _ChipRol extends StatelessWidget {
  const _ChipRol({required this.rol});
  final String rol;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.secondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        rol,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }
}
