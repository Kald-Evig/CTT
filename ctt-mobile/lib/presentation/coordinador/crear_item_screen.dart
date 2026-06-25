library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ctt_mobile/data/repositories/coordinador_repository.dart';
import 'package:ctt_mobile/domain/entities/residente_models.dart';
import 'package:ctt_mobile/presentation/residente/residente_providers.dart';

class CrearItemScreen extends ConsumerStatefulWidget {
  const CrearItemScreen({super.key, required this.proyectoId});
  final String proyectoId;

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
    try {
      await ref.read(coordinadorRepositoryProvider).crearItem(
            proyectoId: widget.proyectoId,
            nombre: _nombreCtrl.text.trim(),
            parentItemId: _parentItemId,
            descripcion: _descripcionCtrl.text.trim().isEmpty
                ? null
                : _descripcionCtrl.text.trim(),
            asignadoA: _asignadoA,
            fechaLimite: _fechaLimite != null ? _formatFecha(_fechaLimite!) : null,
            duracionEstimadaHoras: _duracionCtrl.text.trim().isEmpty
                ? null
                : double.tryParse(_duracionCtrl.text.trim()),
          );
      if (!mounted) return;
      ref.invalidate(itemsProyectoProvider(widget.proyectoId, null));
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
        ref.watch(usuariosEmpresaProvider).whenOrNull(data: (us) => us) ??
            const <UsuarioEmpresa>[];

    // Ítems que pueden ser padre: nivelProfundidad < 4 (un hijo quedaría en nivel 4, el máximo).
    final itemsParent = items.where((i) => i.nivelProfundidad < 4).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo ítem')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
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
            DropdownButtonFormField<String?>(
              initialValue: _asignadoA,
              decoration: const InputDecoration(
                labelText: 'Asignar a',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('Sin asignar')),
                for (final u in usuarios)
                  DropdownMenuItem(value: u.id, child: Text(u.nombreCompleto)),
              ],
              onChanged: (v) => setState(() => _asignadoA = v),
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _guardando ? null : _guardar,
              child: _guardando
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Crear ítem'),
            ),
          ],
        ),
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
