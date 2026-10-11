/// auth_notifier.dart — Estado de autenticación Firebase y acciones de sesión.
///
/// [firebaseAuthStreamProvider] es la fuente de verdad del estado de auth.
/// [AuthNotifier] expone las acciones de inicio y cierre de sesión.
library;

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:ctt_mobile/core/network/dio_client.dart';
import 'package:ctt_mobile/core/sync/ciclo_sync.dart';
import 'package:ctt_mobile/core/sync/conectividad_listener.dart';
import 'package:ctt_mobile/data/local/daos/sync_dao.dart';

part 'auth_notifier.g.dart';

// ── Resultado del cierre de sesión (CTT-138) ──────────────────────────────────

/// Desenlace de [AuthNotifier.cerrarSesion].
sealed class ResultadoCierreSesion {
  const ResultadoCierreSesion();
}

/// Sesión cerrada.
class CierreSesionOk extends ResultadoCierreSesion {
  const CierreSesionOk();
}

/// No se cerró: sin red y con [pendientes] cambios sin sincronizar.
class CierreSesionBloqueado extends ResultadoCierreSesion {
  const CierreSesionBloqueado(this.pendientes);
  final int pendientes;
}

/// Tras el flush quedan [pendientes] cambios; la UI debe confirmar antes de forzar.
class CierreSesionRequiereConfirmacion extends ResultadoCierreSesion {
  const CierreSesionRequiereConfirmacion(this.pendientes);
  final int pendientes;
}

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
    try {
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
      // Invalida el notifier — build() reinicia el estado sin "Future already completed".
      ref.invalidateSelf();
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  /// Cierra sesión con guardia de cola pendiente (CTT-138):
  ///   - con filas no terminales y SIN red → bloqueado (no se cierra).
  ///   - con filas y CON red → se intenta un flush; si quedan filas → requiere
  ///     confirmación del usuario antes de cerrar.
  ///   - cola vacía o `forzar=true` → cierra (signOut de Firebase + limpiar locales).
  /// La cola NO se toca: bloquear/confirmar protege los cambios, no los descarta.
  Future<ResultadoCierreSesion> cerrarSesion({bool forzar = false}) async {
    if (!forzar) {
      final syncDao = ref.read(syncDaoProvider);
      final pendientes = await syncDao.contarNoTerminales();
      if (pendientes > 0) {
        final hayRed = await ref.read(hayConexionProvider.future);
        if (!hayRed) return CierreSesionBloqueado(pendientes);
        // Con red: intentar sincronizar antes de cerrar.
        await ref.read(cicloSyncProvider).ejecutar();
        final restantes = await syncDao.contarNoTerminales();
        if (restantes > 0) return CierreSesionRequiereConfirmacion(restantes);
      }
    }
    final storage = ref.read(secureStorageProvider);
    await Future.wait([
      fb.FirebaseAuth.instance.signOut(),
      storage.limpiarSesion(),
    ]);
    ref.invalidateSelf();
    return const CierreSesionOk();
  }
}
