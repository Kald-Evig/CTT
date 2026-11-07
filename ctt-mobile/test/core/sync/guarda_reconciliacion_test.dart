/// guarda_reconciliacion_test.dart — CTT-141: el guard de reconciliación no lanza GET
/// /sync/conflictos/mios concurrentes (hallazgo R4/R5). "GET" = invocación de reconciliar().
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:ctt_mobile/core/sync/guarda_reconciliacion.dart';

/// reconciliar() falso: cada invocación (= un GET) queda esperando un gate que el test resuelve.
class _ReconFake {
  final List<Completer<bool>> gates = [];
  int gets = 0;

  Future<bool> call() {
    gets++;
    final g = Completer<bool>();
    gates.add(g);
    return g.future;
  }

  void completar(int i, {bool consulto = true}) => gates[i].complete(consulto);
  void fallar(int i, Object e) => gates[i].completeError(e);
}

/// Deja avanzar la cola de microtasks (p. ej. el await de ultimaReconciliacion y el arranque
/// del GET) sin usar timers.
Future<void> _pump() => Future<void>.delayed(Duration.zero);

void main() {
  final t0 = DateTime.utc(2026, 5, 1, 12, 0, 0);

  GuardaReconciliacion armar(
    _ReconFake r, {
    DateTime? ultima,
    DateTime Function()? reloj,
    List<DateTime>? registros,
  }) =>
      GuardaReconciliacion(
        reconciliar: r.call,
        ultimaReconciliacion: () async => ultima,
        registrarReconciliacion: (t) async => registros?.add(t),
        reloj: reloj ?? () => t0,
      );

  test('2 reconciliarSiCorresponde con un GET en vuelo → 1 solo GET', () async {
    final r = _ReconFake();
    final g = armar(r);

    final f1 = g.reconciliarSiCorresponde(); // arranca GET1 (tras el await de ultima)
    await _pump();
    expect(r.gets, 1);
    expect(g.enVuelo, isTrue);

    final f2 = g.reconciliarSiCorresponde(); // en vuelo → se une (sin GET nuevo)
    await _pump();
    expect(r.gets, 1, reason: 'el 2do se sumó, no lanzó otro GET');

    r.completar(0);
    await Future.wait([f1, f2]);
    expect(r.gets, 1);
    expect(g.enVuelo, isFalse);
  });

  test('reconciliarAhora durante un vuelo → 1 GET adicional que EMPIEZA después del primero',
      () async {
    final r = _ReconFake();
    final g = armar(r);

    final f1 = g.reconciliarSiCorresponde();
    await _pump();
    expect(r.gets, 1);

    final fA = g.reconciliarAhora(); // run-after → re-corrida
    await _pump();
    expect(r.gets, 1, reason: 'la re-corrida NO arrancó mientras GET1 sigue en vuelo');

    r.completar(0); // GET1 termina → arranca GET2 (después)
    await f1;
    await _pump();
    expect(r.gets, 2, reason: 'exactamente 1 GET adicional, iniciado tras el primero');

    r.completar(1);
    await fA;
    expect(g.enVuelo, isFalse);
  });

  test('3 reconciliarAhora durante un vuelo → 1 sola re-corrida', () async {
    final r = _ReconFake();
    final g = armar(r);

    final f1 = g.reconciliarSiCorresponde();
    await _pump();
    expect(r.gets, 1);

    final fs = [g.reconciliarAhora(), g.reconciliarAhora(), g.reconciliarAhora()];
    await _pump();
    expect(r.gets, 1);

    r.completar(0);
    await f1;
    await _pump();
    expect(r.gets, 2, reason: 'las 3 directas se juntaron en una sola re-corrida');

    r.completar(1);
    await Future.wait(fs);
    expect(r.gets, 2);
    expect(g.enVuelo, isFalse);
  });

  test('un fallo del GET con alguien esperando → todos reciben el error, el siguiente '
      'funciona y no hay bucle', () async {
    final r = _ReconFake();
    final g = armar(r);

    final f1 = g.reconciliarSiCorresponde();
    await _pump();
    final f2 = g.reconciliarSiCorresponde(); // se une a GET1
    final e1 = expectLater(f1, throwsA(isA<StateError>()));
    final e2 = expectLater(f2, throwsA(isA<StateError>()));

    r.fallar(0, StateError('sin red'));
    await Future.wait([e1, e2]);
    expect(g.enVuelo, isFalse, reason: 'se liberó');

    // El siguiente intento funciona (sin re-corridas fantasma = sin bucle).
    final f3 = g.reconciliarSiCorresponde();
    await _pump();
    expect(r.gets, 2);
    r.completar(1);
    await f3;
    expect(g.enVuelo, isFalse);
  });

  group('debounce + registro', () {
    test('corrida efectiva registra la ventana con el reloj', () async {
      final r = _ReconFake();
      final registros = <DateTime>[];
      final g = armar(r, registros: registros);

      final f = g.reconciliarSiCorresponde();
      await _pump();
      r.completar(0, consulto: true);
      await f;
      expect(registros, [t0], reason: 'registró con el reloj al consultar');
    });

    test('corrida sin filas (consulto=false) NO registra', () async {
      final r = _ReconFake();
      final registros = <DateTime>[];
      final g = armar(r, registros: registros);

      final f = g.reconciliarSiCorresponde();
      await _pump();
      r.completar(0, consulto: false);
      await f;
      expect(registros, isEmpty);
    });

    test('dentro de la ventana NO consulta; pasada la ventana sí', () async {
      final r = _ReconFake();
      // ultima = t0; reloj dentro de la ventana (t0 + 1 min < 2 min).
      final gDentro = armar(r, ultima: t0, reloj: () => t0.add(const Duration(minutes: 1)));
      await gDentro.reconciliarSiCorresponde();
      expect(r.gets, 0, reason: 'el debounce bloqueó el GET');

      final gFuera = armar(r, ultima: t0, reloj: () => t0.add(const Duration(minutes: 3)));
      final f = gFuera.reconciliarSiCorresponde();
      await _pump();
      expect(r.gets, 1, reason: 'pasada la ventana, consulta');
      r.completar(0);
      await f;
    });
  });
}
