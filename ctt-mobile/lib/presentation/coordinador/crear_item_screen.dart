library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ctt_mobile/data/repositories/coordinador_repository.dart';
import 'package:ctt_mobile/domain/entities/residente_models.dart';
import 'package:ctt_mobile/presentation/residente/residente_providers.dart';

class CrearItemScreen extends ConsumerStatefulWidget {
  const CrearItemScreen({
    super.key,
    required this.proyectoId,
    this.itemParaEditar,
  });
  final String proyectoId;

  /// null → modo crear · non-null → modo editar (precarga los campos).
  final ItemResidente? itemParaEditar;

  @override
  ConsumerState<CrearItemScreen> createState() => _CrearItemScreenState();
}

class _CrearItemScreenState extends ConsumerState<CrearItemScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _descripcionCtrl = TextEditingController();
  final _duracionCtrl = TextEditingController();

  DateTime? _fechaLimite;
  String? _parentItemId;
  String? _asignadoA;
  bool _guardando = false;

  bool get _editando => widget.itemParaEditar != null;

  @override
  void initState() {
    super.initState();
    final it = widget.itemParaEditar;
    if (it != null) {
      _nombreCtrl.text = it.nombre;
      _descripcionCtrl.text = it.descripcion ?? '';
      if (it.duracionEstimadaHoras != null) {
        _duracionCtrl.text = it.duracionEstimadaHoras!.toString();
      }
      _fechaLimite =
          it.fechaLimite != null ? DateTime.parse(it.fechaLimite!) : null;
      // parentItemId y asignadoA no son editables — el backend los rechazaría
      // con 422 (extra='forbid'). Los omitimos del form de edición.
    }
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _descripcionCtrl.dispose();
    _duracionCtrl.dispose();
    super.dispose();
  }

  String _formatFecha(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _elegirFechaLimite() async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: _fechaLimite ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (fecha == null || !mounted) return;
    setState(() => _fechaLimite = fecha);
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _guardando = true);
    final repo = ref.read(coordinadorRepositoryProvider);
    final nombre = _nombreCtrl.text.trim();
    final descripcion = _descripcionCtrl.text.trim().isEmpty
        ? null
        : _descripcionCtrl.text.trim();
    final fechaLimite =
        _fechaLimite != null ? _formatFecha(_fechaLimite!) : null;
    final duracion = _duracionCtrl.text.trim().isEmpty
        ? null
        : double.tryParse(_duracionCtrl.text.trim());

    try {
      if (_editando) {
        await repo.editarItem(
          id: widget.itemParaEditar!.id,
          nombre: nombre,
          descripcion: descripcion,
          fechaLimite: fechaLimite,
          duracionEstimadaHoras: duracion,
        );
        if (!mounted) return;
        ref.invalidate(itemsProyectoProvider(widget.proyectoId, null));
        ref.invalidate(itemResidenteDetalleProvider(widget.itemParaEditar!.id));
      } else {
        await repo.crearItem(
          proyectoId: widget.proyectoId,
          nombre: nombre,
          parentItemId: _parentItemId,
          descripcion: descripcion,
          asignadoA: _asignadoA,
          fechaLimite: fechaLimite,
          duracionEstimadaHoras: duracion,
        );
        if (!mounted) return;
        ref.invalidate(itemsProyectoProvider(widget.proyectoId, null));
      }
      context.pop();
    } on ErrorCoordinador catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.mensaje)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items =
        ref.watch(itemsProyectoProvider(widget.proyectoId, null)).whenOrNull(data: (is_) => is_) ??
            const <ItemResidente>[];
    final usuarios =
        ref.watch(usuariosEmpresaPorRolesProvider(const ['trabajador'])).whenOrNull(data: (us) => us) ??
            const <UsuarioEmpresa>[];

    // Ítems que pueden ser padre: nivelProfundidad < 4 (un hijo quedaría en nivel 4, el máximo).
    final itemsParent = items.where((i) => i.nivelProfundidad < 4).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(_editando ? 'Editar ítem' : 'Nuevo ítem'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_editando) ...[
              const _AdvertenciaEdicion(
                mensaje:
                    'Un cambio radical debería ser una tarea nueva, no una edición.',
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _nombreCtrl,
              decoration: const InputDecoration(
                labelText: 'Nombre *',
                border: OutlineInputBorder(),
              ),
              maxLength: 255,
              textCapitalization: TextCapitalization.sentences,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'El nombre es requerido' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descripcionCtrl,
              decoration: const InputDecoration(
                labelText: 'Descripción',
                border: OutlineInputBorder(),
              ),
              maxLength: 2000,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 16),
            if (!_editando) ...[
              DropdownButtonFormField<String?>(
                initialValue: _parentItemId,
                decoration: const InputDecoration(
                  labelText: 'Ítem padre',
                  border: OutlineInputBorder(),
                  helperText: 'Opcional — dejá vacío para crear como ítem raíz',
                ),
                isExpanded: true,
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Sin padre (ítem raíz)'),
                  ),
                  for (final item in itemsParent)
                    DropdownMenuItem<String?>(
                      value: item.id,
                      child: _EtiquetaItemPadre(item: item),
                    ),
                ],
                onChanged: (v) => setState(() => _parentItemId = v),
              ),
              const SizedBox(height: 16),
            ],
            _CampoFecha(
              label: 'Fecha límite',
              fecha: _fechaLimite,
              onTap: _elegirFechaLimite,
              onClear: _fechaLimite != null ? () => setState(() => _fechaLimite = null) : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _duracionCtrl,
              decoration: const InputDecoration(
                labelText: 'Duración estimada (horas)',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                if (double.tryParse(v.trim()) == null) return 'Ingresá un número válido';
                return null;
              },
            ),
            const SizedBox(height: 16),
            if (!_editando) ...[
              DropdownButtonFormField<String?>(
                initialValue: _asignadoA,
                decoration: const InputDecoration(
                  labelText: 'Asignar a',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Sin asignar'),
                  ),
                  for (final u in usuarios)
                    DropdownMenuItem(
                      value: u.id,
                      child: Text(u.nombreCompleto),
                    ),
                ],
                onChanged: (v) => setState(() => _asignadoA = v),
              ),
              const SizedBox(height: 28),
            ] else
              const SizedBox(height: 28),
            FilledButton(
              onPressed: _guardando ? null : _guardar,
              child: _guardando
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(_editando ? 'Guardar cambios' : 'Crear ítem'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdvertenciaEdicion extends StatelessWidget {
  const _AdvertenciaEdicion({required this.mensaje});
  final String mensaje;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.secondaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outline.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 16, color: cs.onSecondaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              mensaje,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _EtiquetaItemPadre extends StatelessWidget {
  const _EtiquetaItemPadre({required this.item});
  final ItemResidente item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: item.nivelProfundidad * 12.0),
      child: Text(item.nombre, overflow: TextOverflow.ellipsis),
    );
  }
}

class _CampoFecha extends StatelessWidget {
  const _CampoFecha({
    required this.label,
    required this.fecha,
    required this.onTap,
    this.onClear,
  });

  final String label;
  final DateTime? fecha;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: fecha != null
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: onClear,
                )
              : const Icon(Icons.calendar_today, size: 18),
        ),
        child: Text(
          fecha != null
              ? '${fecha!.day.toString().padLeft(2, '0')}/${fecha!.month.toString().padLeft(2, '0')}/${fecha!.year}'
              : 'Sin fecha',
          style: fecha == null
              ? Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey)
              : Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}
