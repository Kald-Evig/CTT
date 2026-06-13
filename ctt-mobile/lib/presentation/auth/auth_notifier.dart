/// auth_notifier.dart — Estado de autenticación Firebase y acciones de sesión.
///
/// [firebaseAuthStreamProvider] es la fuente de verdad del estado de auth.
/// [AuthNotifier] expone las acciones de inicio y cierre de sesión.
library;

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:ctt_mobile/core/network/dio_client.dart';

part 'auth_notifier.g.dart';

// ── Stream de estado Firebase ─────────────────────────────────────────────────

/// Emite el usuario Firebase actual (null = sin sesión activa).
/// Usado por [estadoAuth] en app.dart para derivar el estado de navegación.
@riverpod
Stream<fb.User?> firebaseAuthStream(FirebaseAuthStreamRef ref) {
  return fb.FirebaseAuth.instance.authStateChanges();
}

// ── Acciones de sesión ────────────────────────────────────────────────────────

@riverpod
class AuthNotifier extends _$AuthNotifier {
  @override
  Future<void> build() async {}

  /// Autentica con email y contraseña.
  /// Persiste el UID en SecureStorage para que AuthInterceptor lo use como Bearer.
  Future<void> iniciarSesion({
    required String email,
    required String password,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final credential =
          await fb.FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user!;
      final storage = ref.read(secureStorageProvider);
      // TODO backend: cambiar a user.getIdToken() cuando AUTH_MODE=firebase.
      await storage.guardarToken(user.uid);
      await storage.guardarFirebaseUid(user.uid);
    });
  }

  /// Cierra sesión en Firebase y limpia todos los datos de sesión locales.
  Future<void> cerrarSesion() async {
    state = const AsyncLoading();
    final storage = ref.read(secureStorageProvider);
    await Future.wait([
      fb.FirebaseAuth.instance.signOut(),
      storage.limpiarSesion(),
    ]);
    state = const AsyncData(null);
  }
}
