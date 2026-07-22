library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ctt_mobile/data/repositories/admin_repository.dart';
import 'package:ctt_mobile/presentation/admin/admin_providers.dart';

class CrearUsuarioScreen extends ConsumerStatefulWidget {
  const CrearUsuarioScreen({super.key});

  @override
  ConsumerState<CrearUsuarioScreen> createState() => _CrearUsuarioScreenState();
}

class _CrearUsuarioScreenState extends ConsumerState<CrearUsuarioScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _rutCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();

  String _rol = 'trabajador';
  bool _guardando = false;

  static const _roles = ['trabajador', 'residente', 'coordinador'];

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _emailCtrl.dispose();
    _rutCtrl.dispose();
    _telefonoCtrl.dispose();
    super.dispose();
  }

  String? _validarEmail(String? v) {
    if (v == null || v.trim().isEmpty) return 'El email es requerido';
    final patron = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!patron.hasMatch(v.trim())) return 'Email inválido';
    return null;
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _guardando = true);

    try {
      final resultado = await ref.read(adminRepositoryProvider).crearUsuario(
            nombre: _nombreCtrl.text.trim(),
            email: _emailCtrl.text.trim(),
            rol: _rol,
            rut: _rutCtrl.text.trim().isEmpty ? null : _rutCtrl.text.trim(),
            telefono: _telefonoCtrl.text.trim().isEmpty
                ? null
                : _telefonoCtrl.text.trim(),
          );

      if (!mounted) return;
      await _mostrarDialogoResetLink(resultado);
    } on ErrorAdmin catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.mensaje)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _mostrarDialogoResetLink(UsuarioCreado resultado) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _DialogoResetLink(resultado: resultado),
    );
    // Solo después de cerrar el diálogo: volver y refrescar la lista.
    if (!mounted) return;
    ref.invalidate(usuariosAdminProvider);
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nuevo usuario'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nombreCtrl,
              decoration: const InputDecoration(
                labelText: 'Nombre completo *',
                border: OutlineInputBorder(),
              ),
              maxLength: 255,
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'El nombre es requerido' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _emailCtrl,
              decoration: const InputDecoration(
                labelText: 'Email *',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              validator: _validarEmail,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _rol,
              decoration: const InputDecoration(
                labelText: 'Rol *',
                border: OutlineInputBorder(),
              ),
              items: _roles
                  .map((r) => DropdownMenuItem(value: r, child: Text(r),))
                  .toList(),
              onChanged: (v) => setState(() => _rol = v!),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _rutCtrl,
              decoration: const InputDecoration(
                labelText: 'RUT',
                border: OutlineInputBorder(),
                helperText: 'Opcional — ej. 12.345.678-9',
              ),
              keyboardType: TextInputType.text,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.kK-]')),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _telefonoCtrl,
              decoration: const InputDecoration(
                labelText: 'Teléfono',
                border: OutlineInputBorder(),
                helperText: 'Opcional',
              ),
              keyboardType: TextInputType.phone,
            ),
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
                  : const Text('Crear usuario'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Diálogo de reset link ─────────────────────────────────────────────────────

class _DialogoResetLink extends StatelessWidget {
  const _DialogoResetLink({required this.resultado});
  final UsuarioCreado resultado;

  @override
  Widget build(BuildContext context) {
    final link = resultado.resetLink;
    final pendiente = resultado.resetLinkPendiente;

    return AlertDialog(
      title: const Text('Usuario creado'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${resultado.usuario.nombreCompleto} fue creado con rol '
            '${resultado.usuario.rol}.',
          ),
          const SizedBox(height: 16),
          if (pendiente) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                border: Border.all(color: Colors.orange.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_outlined,
                      color: Colors.orange, size: 18,),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'La cuenta se creó pero el enlace de acceso no pudo '
                      'generarse. Regeneralo desde la consola de Firebase.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (link != null) ...[
            const Text(
              'Entregá este enlace a la persona para que cree su contraseña:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: SelectableText(
                link,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (link != null && !pendiente)
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copiar enlace'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: link));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Enlace copiado')),
              );
            },
          ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}
