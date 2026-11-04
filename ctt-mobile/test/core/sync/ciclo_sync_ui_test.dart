/// ciclo_sync_ui_test.dart — CTT-141: guard single-flight + coalescing de la UI.
///
/// Se inyecta una "corrida real" controlable (gates por invocación) para verificar el
/// coalescing, el invariante de frescura (la re-corrida arranca DESPUÉS de la llamada) y
/// que una excepción no traba el guard.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:ctt_mobile/core/sync/ciclo_sync_ui.dart';

/// Corrida inyectable: cada invocación registra una captura de [cola] en su INICIO y queda
/// esperando un gate que el test completa (o falla) a mano.
class _CorridaFake {
  final List<Completer<void>> gates = [];
  final List<List<String>> capturasAlIniciar = [];
  final List<String> cola = [];
  int invocaciones = 0;

  Future<void> call() {
    invocaciones++;
    capturasAlIniciar.add(List.of(cola));
    final g = Completer<void>();
    gates.add(g);
    return g.future;
  }

  void completar(int i) => gates[i].complete();
  void fallar(int i, Object e) => gates[i].completeError(e);
}

void main() {
  test(
      '3 llamadas durante una corrida en vuelo generan EXACTAMENTE 1 re-corrida',
      () async {
    final c = _CorridaFake();
    final guard = CicloSyncUi(c.call);

    final f1 = guard.ejecutar(); // idle → arranca C1 (invocación 0)
    expect(c.invocaciones, 1);
    expect(guard.enVuelo, isTrue);

    final f2 = guard.ejecutar(); // en vuelo → re-corrida
    final f3 = guard.ejecutar();
    final f4 = guard.ejecutar();
    expect(c.invocaciones, 1,
        reason: 'las 3 se juntan, no lanzan corridas nuevas aún');

    c.completar(0); // C1 termina → arranca la (única) re-corrida C2
    await f1;
    expect(c.invocaciones, 2, reason: 'exactamente 1 re-corrida');

    c.completar(1); // C2 termina
    await Future.wait([f2, f3, f4]);
    expect(c.invocaciones, 2,
        reason: 'no hay más re-corridas: las 3 compartieron C2');
    expect(guard.enVuelo, isFalse);
  });

  test(
      'una fila encolada durante el vuelo la envía la RE-CORRIDA; el future de quien '
      'llamó después del encolado se completa recién al terminar la re-corrida',
      () async {
    final c = _CorridaFake();
    final guard = CicloSyncUi(c.call);

    final f1 = guard.ejecutar(); // C1 arranca con cola vacía
    expect(c.capturasAlIniciar[0], isEmpty);

    c.cola.add('r1'); // se encola una fila mientras C1 está en vuelo
    final fDespues =
        guard.ejecutar(); // llamada DESPUÉS del encolado → re-corrida
    var despuesListo = false;
    unawaited(fDespues.then((_) => despuesListo = true));

    c.completar(0); // C1 termina → arranca C2
    await f1;
    expect(c.capturasAlIniciar[1], ['r1'],
        reason:
            'la re-corrida arrancó después del encolado y ve la fila nueva');
    expect(despuesListo, isFalse,
        reason: 'el future de la llamada posterior NO se completa con C1');

    c.completar(1); // C2 termina
    await fDespues;
    expect(despuesListo, isTrue,
        reason: 'se completa al terminar la re-corrida');
  });

  group('una excepción no traba el guard', () {
    test(
        'la corrida falla → el caller recibe el error y una llamada nueva arranca fresco',
        () async {
      final c = _CorridaFake();
      final guard = CicloSyncUi(c.call);

      final f1 = guard.ejecutar();
      final esperaError = expectLater(f1, throwsA(isA<StateError>()));
      c.fallar(0, StateError('boom'));
      await esperaError;

      expect(guard.enVuelo, isFalse, reason: 'no quedó trabado');
      final f2 = guard.ejecutar(); // arranca una corrida nueva sin problema
      expect(c.invocaciones, 2);
      c.completar(1);
      await f2;
    });

    test(
        'la corrida falla con una re-corrida pendiente → la re-corrida igual se ejecuta',
        () async {
      final c = _CorridaFake();
      final guard = CicloSyncUi(c.call);

      final f1 = guard.ejecutar();
      final fRerun = guard.ejecutar(); // re-corrida pendiente
      final esperaError = expectLater(f1, throwsA(isA<StateError>()));
      c.fallar(0, StateError('boom')); // C1 falla
      await esperaError;

      expect(c.invocaciones, 2,
          reason: 'la re-corrida arrancó pese al error de C1');
      c.completar(1);
      await fRerun; // la re-corrida completa normalmente
      expect(guard.enVuelo, isFalse);
    });
  });

  test(
      'cerrarSesion: con una corrida en vuelo, el flush que espera ve la fila nueva '
      '(cuenta con datos frescos, no con la corrida en vuelo)', () async {
    // Simula el invariante del que depende cerrarSesion (auth_notifier:95-96): la cola tiene
    // una fila encolada mientras una corrida previa (que ya leyó la cola vacía) está en vuelo.
    final c = _CorridaFake();
    final guard = CicloSyncUi(c.call);

    final f1 = guard.ejecutar(); // corrida previa C1, leyó cola vacía
    expect(c.capturasAlIniciar[0], isEmpty);

    c.cola.add('r1'); // se encola una transición
    // cerrarSesion hace `await ejecutar()` y después cuenta no-terminales:
    final fFlushCierre = guard.ejecutar();
    c.completar(
        0); // C1 termina → arranca la re-corrida (el flush de cerrarSesion)
    await f1;
    // Mientras la re-corrida no termine, el await de cerrarSesion sigue pendiente.
    c.completar(1);
    await fFlushCierre;
    // La corrida que cerrarSesion esperó (C2) arrancó DESPUÉS del encolado → vio r1.
    expect(c.capturasAlIniciar[1], ['r1'],
        reason:
            'cerrarSesion contaría después de una corrida que vio la fila nueva');
    expect(c.invocaciones, 2);
  });
}
