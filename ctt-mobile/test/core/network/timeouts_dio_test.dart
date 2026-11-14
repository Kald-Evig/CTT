/// timeouts_dio_test.dart — CTT-142 fase A (commit 2): timeouts por fase y lease.
///
/// - Entorno: conexión 5 s, envío 15 s, recepción 30 s.
/// - opcionesBaseDio (fuente única) y los CUATRO Dio (interactivo, cola foreground,
///   headless vía crearDioSync, rescate) llevan los tres timeouts, incluido sendTimeout.
/// - duracionLease acota un envío COMPLETO: >= conexión + envío + recepción.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'package:ctt_mobile/core/config/environment.dart';
import 'package:ctt_mobile/core/network/dio_client.dart';
import 'package:ctt_mobile/core/security/secure_storage_service.dart';
import 'package:ctt_mobile/core/sync/ciclo_sync.dart';
import 'package:ctt_mobile/core/sync/rescate_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void verificar(BaseOptions o, String nombre) {
    expect(o.connectTimeout, const Duration(seconds: 5), reason: '$nombre connectTimeout');
    expect(o.sendTimeout, const Duration(seconds: 15), reason: '$nombre sendTimeout');
    expect(o.receiveTimeout, const Duration(seconds: 30), reason: '$nombre receiveTimeout');
  }

  test('Entorno: conexión 5 s, envío 15 s, recepción 30 s', () {
    expect(Entorno.timeoutConexion, const Duration(seconds: 5));
    expect(Entorno.timeoutEnvio, const Duration(seconds: 15));
    expect(Entorno.timeoutRecepcion, const Duration(seconds: 30));
  });

  test('opcionesBaseDio (fuente única) lleva los tres timeouts', () {
    verificar(opcionesBaseDio(), 'opcionesBaseDio');
  });

  test('los CUATRO Dio llevan connect=5, send=15, receive=30', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    verificar(c.read(dioClientProvider).options, 'interactivo');
    verificar(c.read(dioSyncProvider).options, 'cola (foreground)');
    verificar(c.read(dioRescateProvider).options, 'rescate');
    // Headless de WorkManager: usa crearDioSync directamente (sin Riverpod).
    verificar(
      crearDioSync(SecureStorageService(), Logger(level: Level.off)).options,
      'headless',
    );
  });

  test('duracionLease acota un envío completo: >= conexión + envío + recepción', () {
    final sumaTimeouts =
        Entorno.timeoutConexion + Entorno.timeoutEnvio + Entorno.timeoutRecepcion;
    expect(CicloSync.duracionLease, greaterThanOrEqualTo(sumaTimeouts));
    // 5 + 15 + 30 + margen 30 = 80 s.
    expect(CicloSync.duracionLease, const Duration(seconds: 80));
  });
}
