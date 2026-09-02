/// coordinador_detalle_item_screen.dart — Detalle de ítem para el Coordinador.
///
/// Usa los widgets de visualización compartidos (ItemDetalleCuerpo) e inyecta
/// _AccionesCoordinador como sección de acciones propia del rol.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ctt_mobile/core/util/formato_fecha.dart';
import 'package:ctt_mobile/data/repositories/coordinador_repository.dart';
import 'package:ctt_mobile/domain/entities/coordinador_models.dart';
import 'package:ctt_mobile/domain/entities/residente_models.dart';
import 'package:ctt_mobile/presentation/coordinador/coordinador_providers.dart';
import 'package:ctt_mobile/presentation/residente/residente_providers.dart';
import 'package:ctt_mobile/presentation/shared/error_vista.dart';
import 'package:ctt_mobile/presentation/shared/item_detalle_widgets.dart';

class CoordinadorDetalleItemScreen extends ConsumerWidget {
  const CoordinadorDetalleItemScreen({
    super.key,
    required this.itemId,
    required this.proyectoId,
  });

  final String itemId;
  final String proyectoId;

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
          acciones: _AccionesCoordinador(item: item, proyectoId: proyectoId),
        ),
      ),
    );
  }
}

// ── Acciones del Coordinador ──────────────────────────────────────────────────

class _AccionesCoordinador extends StatelessWidget {
  const _AccionesCoordinador({
    required this.item,
    required this.proyectoId,
  });

  final ItemResidente item;
  final String proyectoId;

  @override
  Widget build(BuildContext context) {
    if (item.estado == 'terminado') {
      return const ItemDetalleMensajeEstado(
        icono: Icons.lock_outline,
        texto: 'Un ítem terminado no se puede editar.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (item.ultimaEdicionPor != null && item.ultimaEdicionEn != null) ...[
          _MarcaEdicion(item: item),
          const SizedBox(height: 12),
        ],
        ItemDetalleBotonAccion(
          label: 'Editar ítem',
          icono: Icons.edit_outlined,
          color: Theme.of(context).colorScheme.primary,
          filled: false,
          onTap: () => context.push(
            '/coordinador/$proyectoId/items/${item.id}/editar',
            extra: item,
          ),
        ),
        const SizedBox(height: 8),
        ItemDetalleBotonAccion(
          label: 'Reasignar trabajador',
          icono: Icons.swap_horiz_outlined,
          color: Theme.of(context).colorScheme.secondary,
          filled: false,
          onTap: () => _mostrarSelectorAsignatario(context, item, proyectoId),
        ),
      ],
    );
  }
}

class _MarcaEdicion extends StatelessWidget {
  const _MarcaEdicion({required this.item});
  final ItemResidente item;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => _mostrarHistorialEdiciones(context, item.id),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(
                Icons.edit_note_outlined,
                size: 14,
                color: Colors.grey.shade500,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Editado por ${item.ultimaEdicionPor}'
                  ' el ${fechaHora(item.ultimaEdicionEn!)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ),
              Icon(Icons.history, size: 16, color: Colors.grey.shade500),
            ],
          ),
        ),
      );
}

// ── Selector de asignatario (bottom sheet) ────────────────────────────────────

void _mostrarSelectorAsignatario(
  BuildContext context,
  ItemResidente item,
  String proyectoId,
) {
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
      builder: (_, sc) => _SelectorAsignatarioSheet(
        item: item,
        proyectoId: proyectoId,
        scrollController: sc,
      ),
    ),
  );
}

class _SelectorAsignatarioSheet extends ConsumerStatefulWidget {
  const _SelectorAsignatarioSheet({
    required this.item,
    required this.proyectoId,
    required this.scrollController,
  });

  final ItemResidente item;
  final String proyectoId;
  final ScrollController scrollController;

  @override
  ConsumerState<_SelectorAsignatarioSheet> createState() =>
      _SelectorAsignatarioSheetState();
}

class _SelectorAsignatarioSheetState
    extends ConsumerState<_SelectorAsignatarioSheet> {
  String? _asignandoId;
  String? _error;

  Future<void> _asignar(MiembroProyecto miembro) async {
    setState(() {
      _asignandoId = miembro.usuarioId;
      _error = null;
    });
    try {
      await ref
          .read(coordinadorRepositoryProvider)
          .asignarItem(widget.item.id, miembro.usuarioId);

      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      ref.invalidate(itemResidenteDetalleProvider(widget.item.id));
      ref.invalidate(itemsProyectoProvider);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(content: Text('Asignado a ${miembro.nombreCompleto}.')),
      );
    } on ErrorCoordinador catch (e) {
      if (mounted) {
        setState(() {
          _asignandoId = null;
          _error = e.mensaje;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _asignandoId = null;
          _error = 'Error al asignar. Intenta de nuevo.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final miembrosAsync =
        ref.watch(miembrosProyectoProvider(widget.proyectoId));

    return Column(
      children: [
        const _ManijaDrag(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            'Asignar trabajador',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        if (_error != null)
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.errorContainer,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Text(
              _error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
                fontSize: 13,
              ),
            ),
          ),
        const Divider(height: 1),
        Expanded(
          child: miembrosAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorVista(
              mensaje: 'No se pudo cargar los miembros: $e',
              onReintento: () =>
                  ref.invalidate(miembrosProyectoProvider(widget.proyectoId)),
            ),
            data: (miembros) {
              final trabajadores = miembros
                  .where(
                    (m) =>
                        m.rolEnProyecto == 'trabajador' && m.estado == 'activo',
                  )
                  .toList();
              if (trabajadores.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No hay trabajadores asignados al proyecto.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                );
              }
              return ListView.builder(
                controller: widget.scrollController,
                itemCount: trabajadores.length,
                itemBuilder: (_, i) {
                  final m = trabajadores[i];
                  final asignando = _asignandoId == m.usuarioId;
                  return ListTile(
                    leading: CircleAvatar(
                      child: Text(
                        m.nombreCompleto.isNotEmpty
                            ? m.nombreCompleto[0].toUpperCase()
                            : '?',
                      ),
                    ),
                    title: Text(m.nombreCompleto),
                    trailing: asignando
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : null,
                    enabled: _asignandoId == null,
                    onTap: _asignandoId == null ? () => _asignar(m) : null,
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

// ── Historial de ediciones (bottom sheet) ─────────────────────────────────────

const _kLimitEdiciones = 10;

const _etiquetasCampo = <String, String>{
  'nombre': 'Nombre',
  'descripcion': 'Descripción',
  'fecha_limite': 'Fecha límite',
  'orden': 'Orden',
  'duracion_estimada_horas': 'Duración estimada (h)',
};

void _mostrarHistorialEdiciones(BuildContext context, String itemId) {
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
      builder: (_, sc) => _HistorialEdicionesSheet(
        itemId: itemId,
        scrollController: sc,
      ),
    ),
  );
}

class _HistorialEdicionesSheet extends ConsumerStatefulWidget {
  const _HistorialEdicionesSheet({
    required this.itemId,
    required this.scrollController,
  });

  final String itemId;
  final ScrollController scrollController;

  @override
  ConsumerState<_HistorialEdicionesSheet> createState() =>
      _HistorialEdicionesSheetState();
}

class _HistorialEdicionesSheetState
    extends ConsumerState<_HistorialEdicionesSheet> {
  final List<AuditLogEntry> _entradas = [];
  bool _cargando = false;
  bool _hayMas = true;
  String? _error;
  int _offset = 0;

  @override
  void initState() {
    super.initState();
    _cargarMas();
  }

  Future<void> _cargarMas() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final nuevas =
          await ref.read(coordinadorRepositoryProvider).listarEdicionesItem(
                widget.itemId,
                limit: _kLimitEdiciones,
                offset: _offset,
              );
      setState(() {
        _entradas.addAll(nuevas);
        _offset += nuevas.length;
        _hayMas = nuevas.length == _kLimitEdiciones;
      });
    } on ErrorCoordinador catch (e) {
      setState(() => _error = e.mensaje);
    } catch (_) {
      setState(() => _error = 'Error al cargar el historial.');
    } finally {
      setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _ManijaDrag(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            'Historial de ediciones',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _buildContenido(context)),
      ],
    );
  }

  Widget _buildContenido(BuildContext context) {
    if (_entradas.isEmpty && _cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_entradas.isEmpty && _error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _cargarMas,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }
    if (_entradas.isEmpty) {
      return const Center(child: Text('Sin ediciones registradas.'));
    }

    return ListView.separated(
      controller: widget.scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _entradas.length + 1,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (_, i) {
        if (i == _entradas.length) return _buildFooter();
        return _EntradaEdicionTile(entrada: _entradas[i]);
      },
    );
  }

  Widget _buildFooter() {
    if (_cargando) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            TextButton(
              onPressed: _cargarMas,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }
    if (_hayMas) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: OutlinedButton(
            onPressed: _cargarMas,
            child: const Text('Ver más ediciones'),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

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

class _EntradaEdicionTile extends StatelessWidget {
  const _EntradaEdicionTile({required this.entrada});
  final AuditLogEntry entrada;

  @override
  Widget build(BuildContext context) {
    final camposDiff = entrada.diff?.entries.toList() ?? [];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${entrada.actorNombre} (${entrada.actorRol})'
            ' · ${fechaHora(entrada.createdAt)}',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          if (camposDiff.isEmpty)
            Text(
              'Sin campos registrados.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            )
          else
            ...camposDiff.map((e) => _LineaDiff(campo: e.key, par: e.value)),
        ],
      ),
    );
  }
}

class _LineaDiff extends StatelessWidget {
  const _LineaDiff({required this.campo, required this.par});
  final String campo;
  final dynamic par;

  @override
  Widget build(BuildContext context) {
    final etiqueta = _etiquetasCampo[campo] ?? campo;
    final lista = par is List ? par as List : <dynamic>[];
    final viejo = lista.isNotEmpty ? _formatValor(lista[0]) : '?';
    final nuevo = lista.length > 1 ? _formatValor(lista[1]) : '?';
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        '$etiqueta: $viejo → $nuevo',
        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
      ),
    );
  }

  String _formatValor(dynamic v) {
    if (v == null) return 'vacío';
    if (v is String) {
      if (v.isEmpty) return 'vacío';
      // Fechas ISO "2026-07-15" o "2026-07-15T..." → dd/MM/yyyy
      if (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(v)) {
        try {
          final dt = DateTime.parse(v);
          return '${dt.day.toString().padLeft(2, '0')}/'
              '${dt.month.toString().padLeft(2, '0')}/${dt.year}';
        } catch (_) {}
      }
      return v;
    }
    return v.toString();
  }
}
