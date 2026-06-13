/// login_screen.dart — Pantalla de inicio de sesión.
///
/// Usa FirebaseAuth a través de AuthNotifier (Riverpod).
/// Los errores de autenticación se muestran en español via SnackBar.
library;

import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuthException;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ctt_mobile/presentation/auth/auth_notifier.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _mostrarPassword = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _iniciarSesion() async {
    if (!_formKey.currentState!.validate()) return;
    await ref.read(authNotifierProvider.notifier).iniciarSesion(
          email: _emailCtrl.text.trim(),
          password: _passCtrl.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final cargando = authState.isLoading;

    // Muestra error como SnackBar cuando falla el login.
    ref.listen(authNotifierProvider, (_, next) {
      if (next.hasError) {
        final msg = _mensajeFirebase(next.error);
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
            content: Text(msg),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),);
      }
    });

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Logo / título ────────────────────────────────────────
                  Icon(
                    Icons.construction_rounded,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'CTT',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                  Text(
                    'Supervisión de obras',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 40),

                  // ── Campo email ──────────────────────────────────────────
                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Correo electrónico',
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Ingresa tu correo.';
                      }
                      if (!v.contains('@')) return 'Correo inválido.';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // ── Campo contraseña ─────────────────────────────────────
                  TextFormField(
                    controller: _passCtrl,
                    obscureText: !_mostrarPassword,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => cargando ? null : _iniciarSesion(),
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      prefixIcon: const Icon(Icons.lock_outlined),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_mostrarPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,),
                        onPressed: () =>
                            setState(() => _mostrarPassword = !_mostrarPassword),
                        tooltip: _mostrarPassword
                            ? 'Ocultar contraseña'
                            : 'Mostrar contraseña',
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Ingresa tu contraseña.';
                      return null;
                    },
                  ),
                  const SizedBox(height: 28),

                  // ── Botón de ingreso ─────────────────────────────────────
                  FilledButton(
                    onPressed: cargando ? null : _iniciarSesion,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: cargando
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Ingresar', style: TextStyle(fontSize: 16)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Convierte códigos de error de Firebase Auth a mensajes en español.
String _mensajeFirebase(Object? error) {
  if (error is FirebaseAuthException) {
    return switch (error.code) {
      'invalid-credential' => 'Correo o contraseña incorrectos.',
      'user-not-found' => 'No existe una cuenta con ese correo.',
      'wrong-password' => 'Contraseña incorrecta.',
      'invalid-email' => 'El formato del correo no es válido.',
      'user-disabled' => 'Esta cuenta ha sido deshabilitada.',
      'too-many-requests' => 'Demasiados intentos. Espera unos minutos.',
      'network-request-failed' => 'Sin conexión. Verifica tu internet.',
      _ => 'Error al iniciar sesión. Intenta nuevamente.',
    };
  }
  return 'Ocurrió un error inesperado.';
}
