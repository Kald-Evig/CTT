library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ctt_mobile/data/repositories/coordinador_repository.dart';
import 'package:ctt_mobile/domain/entities/residente_models.dart';
import 'package:ctt_mobile/presentation/coordinador/coordinador_providers.dart';
import 'package:ctt_mobile/presentation/residente/residente_providers.dart';

class CrearProyectoScreen extends ConsumerStatefulWidget {
  const CrearProyectoScreen({super.key});

  @override
  ConsumerState<CrearProyectoScreen> createState() => _CrearProyectoScreenState();
}

class _CrearProyectoScreenState extends ConsumerState<CrearProyectoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _descripcionCtrl = TextEditingController();
  final _ubicacionCtrl = TextEditingController();

  DateTime? _fechaInicio;
  DateTime? _fechaFin;
  String? _coordinadorId;
  bool _guardando = false;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _descripcionCtrl.dispose();
    _ubicacionCtrl.dispose();
    super.dispose();
  }

  String _formatFecha(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _elegirFecha({required bool esFin}) async {
    final primera = esFin ? (_fechaInicio ?? DateTime.now()) : DateTime.now();
    final inicial = esFin ? (_fechaFin ?? primera) : (_fechaInicio ?? primera);
    final fecha = await showDatePicker(
      context: context,
      initialDate: inicial,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (fecha == null || !mounted) return;
    setState(() {
      if (esFin) {
        _fechaFin = fecha;
      } else {
        _fechaInicio = fecha;
        if (_fechaFin != null && _fechaFin!.isBefore(fecha)) _fechaFin = null;
      }
    });
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _guardando = true);
    try {
      await ref.read(coordinadorRepositoryProvider).crearProyecto(
            nombre: _nombreCtrl.text.trim(),
            descripcion: _descripcionCtrl.text.trim().isEmpty
                ? null
                : _descripcionCtrl.text.trim(),
            ubicacionNombre: _ubicacionCtrl.text.trim().isEmpty
                ? null
                : _ubicacionCtrl.text.trim(),
            coordinadorPrincipalId: _coordinadorId,
            fechaInicio: _fechaInicio != null ? _formatFecha(_fechaInicio!) : null,
            fechaFinEstimada: _fechaFin != null ? _formatFecha(_fechaFin!) : null,
          );
      if (!mounted) return;
      ref.invalidate(proyectosResidenteProvider);
      ref.invalidate(dashboardProyectosProvider);
      context.pop();
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
    final usuarios = ref.watch(usuariosEmpresaProvider).whenOrNull(data: (u) => u) ??
        const <UsuarioEmpresa>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo proyecto')),
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
            TextFormField(
              controller: _ubicacionCtrl,
              decoration: const InputDecoration(
                labelText: 'Ubicación',
                border: OutlineInputBorder(),
              ),
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 8),
            _CampoFecha(
              label: 'Fecha de inicio',
              fecha: _fechaInicio,
              onTap: () => _elegirFecha(esFin: false),
              onClear: _fechaInicio != null ? () => setState(() => _fechaInicio = null) : null,
            ),
            const SizedBox(height: 12),
            _CampoFecha(
              label: 'Fecha fin estimada',
              fecha: _fechaFin,
              onTap: () => _elegirFecha(esFin: true),
              onClear: _fechaFin != null ? () => setState(() => _fechaFin = null) : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String?>(
              initialValue: _coordinadorId,
              decoration: const InputDecoration(
                labelText: 'Coordinador principal',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('Sin asignar')),
                for (final u in usuarios)
                  DropdownMenuItem(value: u.id, child: Text(u.nombreCompleto)),
              ],
              onChanged: (v) => setState(() => _coordinadorId = v),
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
                  : const Text('Crear proyecto'),
            ),
          ],
        ),
      ),
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
