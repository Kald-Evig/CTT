/// cerrar_sesion_guard_test.dart — CTT-138 commit 5.
///
/// Guardia de cerrarSesion():
///   - cola no terminal + SIN red → CierreSesionBloqueado (no se cierra).
///   - cola no terminal + CON red → flush; si quedan filas → RequiereConfirmacion.
/// (El camino OK/forzado invoca Firebase.signOut y no se ejercita acá.)
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:riverpod/riverpod.dart';

import 'package:ctt_mobile/core/sync/ciclo_sync.dart';
import 'package:ctt_mobile/core/sync/conectividad_listener.dart';
import 'package:ctt_mobile/data/local/daos/sync_dao.dart';
import 'package:ctt_mobile/presentation/auth/auth_notifier.dart';

class _MockSyncDao extends Mock implements SyncDao {}

class _MockCiclo extends Mock implements CicloSync {}

/// Contenedor con la cola (cuenta antes/después del flush) y la conectividad fijadas.
ProviderContainer _contenedor({
  required int pendientes,
  required bool hayRed,
  int? restantesTrasFlush,
  required _MockCiclo ciclo,
}) {
  final dao = _MockSyncDao();
  var llamada = 0;
  when(() => dao.contarNoTerminales()).thenAnswer((_) async {
    llamada++;
    return llamada == 1 ? pendientes : (restantesTrasFlush ?? pendientes);
  });
  when(() => ciclo.ejecutar()).thenAnswer((_) async {});
  return ProviderContainer(overrides: [
    syncDaoProvider.overrideWithValue(dao),
    cicloSyncProvider.overrideWithValue(ciclo),
    hayConexionProvider.overrideWith((ref) async => hayRed),
  ]);
}

void main() {
  test('cola no terminal + SIN red → bloqueado (y no se intenta flush)', () async {
    final ciclo = _MockCiclo();
    final c = _contenedor(pendientes: 3, hayRed: false, ciclo: ciclo);
    addTearDown(c.dispose);

    final r = await c.read(authNotifierProvider.notifier).cerrarSesion();

    expect(r, isA<CierreSesionBloqueado>());
    expect((r as CierreSesionBloqueado).pendientes, 3);
    verifyNever(() => ciclo.ejecutar()); // sin red no se flushea
  });

  test('cola no terminal + CON red: flush y si quedan filas → requiere confirmación',
      () async {
    final ciclo = _MockCiclo();
    final c = _contenedor(
      pendientes: 2,
      hayRed: true,
      restantesTrasFlush: 2, // el flush no vació la cola
      ciclo: ciclo,
    );
    addTearDown(c.dispose);

    final r = await c.read(authNotifierProvider.notifier).cerrarSesion();

    expect(r, isA<CierreSesionRequiereConfirmacion>());
    expect((r as CierreSesionRequiereConfirmacion).pendientes, 2);
    verify(() => ciclo.ejecutar()).called(1); // se intentó el flush
  });
}
