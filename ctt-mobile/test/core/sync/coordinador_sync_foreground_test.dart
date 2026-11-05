/// coordinador_sync_foreground_test.dart — CTT-141 (revisión de Chat): el coordinador de
/// primer plano, con fake_async. Gating por (primer plano Y sesión), sondeo de data_version
/// y su detección.
library;

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';

import 'package:ctt_mobile/core/sync/coordinador_sync_foreground.dart';
import 'package:ctt_mobile/core/sync/planificador_sync.dart';

/// data_version inyectable: cuenta lecturas y, opcionalmente, deja la lectura "colgada" (gate)
/// para el test de solapamiento.
class _FakeDataVersion {
  int valor = 1;
  int lecturas = 0;
  Completer<int>? gate;
  bool lanza = false;

  Future<int> leer() {
    lecturas++;
    if (lanza) return Future.error(StateError('base cerrándose'));
    if (gate != null) return gate!.future;
    return Future.value(valor);
  }
}

void main() {
  CoordinadorSyncForeground armar(
    _FakeDataVersion dv, {
    PlanificadorSync? plan,
    void Function()? invalidar,
    Duration intervalo = const Duration(seconds: 2),
    Future<DateTime?> Function()? ultimaReconciliacion,
    Future<void> Function()? reconciliarSiCorresponde,
  }) =>
      CoordinadorSyncForeground(
        planificador: plan ?? PlanificadorSync(ejecutar: () async {}),
        leerDataVersion: dv.leer,
        invalidarTodo: invalidar ?? () {},
        ultimaReconciliacion: ultimaReconciliacion ?? () async => null,
        reconciliarSiCorresponde: reconciliarSiCorresponde ?? () async {},
        intervaloSondeo: intervalo,
      );

  test('paused: el sondeo deja de leer (0 lecturas en 10 s) y el planificador se desactiva', () {
    fakeAsync((async) {
      final dv = _FakeDataVersion();
      final plan = PlanificadorSync(ejecutar: () async {});
      final coord = armar(dv, plan: plan);

      coord.alCambiarSesion(haySesion: true); // primer plano por defecto → activo
      async.flushMicrotasks();
      expect(coord.activo, isTrue);
      expect(plan.activo, isTrue);
      final lecturasAntes = dv.lecturas;

      coord.alCambiarCicloDeVida(AppLifecycleState.paused);
      expect(coord.activo, isFalse);
      expect(plan.activo, isFalse, reason: 'el planificador también se desactiva');
      expect(coord.sondeando, isFalse);

      async.elapse(const Duration(seconds: 10));
      expect(dv.lecturas, lecturasAntes, reason: 'el sondeo se detuvo: 0 lecturas nuevas');
    });
  });

  test('resumed con sesión: chequeo inmediato y luego uno cada 2 s', () {
    fakeAsync((async) {
      final dv = _FakeDataVersion();
      final coord = armar(dv);

      coord.alCambiarSesion(haySesion: true);
      async.flushMicrotasks();
      coord.alCambiarCicloDeVida(AppLifecycleState.paused); // a background
      final antes = dv.lecturas;

      coord.alCambiarCicloDeVida(AppLifecycleState.resumed);
      async.flushMicrotasks();
      expect(dv.lecturas, antes + 1, reason: 'resumed hace un chequeo inmediato');

      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(dv.lecturas, antes + 2, reason: 'y luego uno cada 2 s');
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(dv.lecturas, antes + 3);
    });
  });

  test('logout en primer plano detiene ambos; resumed sin sesión no arranca nada', () {
    fakeAsync((async) {
      final dv = _FakeDataVersion();
      final plan = PlanificadorSync(ejecutar: () async {});
      final coord = armar(dv, plan: plan);

      coord.alCambiarSesion(haySesion: true);
      async.flushMicrotasks();
      expect(coord.activo, isTrue);

      coord.alCambiarSesion(haySesion: false); // logout
      expect(coord.activo, isFalse);
      expect(plan.activo, isFalse);
      expect(coord.sondeando, isFalse);
      final antes = dv.lecturas;
      async.elapse(const Duration(seconds: 10));
      expect(dv.lecturas, antes, reason: 'sin sesión no sondea');

      coord.alCambiarCicloDeVida(AppLifecycleState.resumed); // resumed SIN sesión
      expect(coord.activo, isFalse);
      expect(coord.sondeando, isFalse);
      async.elapse(const Duration(seconds: 10));
      expect(dv.lecturas, antes, reason: 'resumed sin sesión no arranca el sondeo');
    });
  });

  test('detección: la primera lectura no invalida; distinto invalida una vez; igual no invalida',
      () {
    fakeAsync((async) {
      final dv = _FakeDataVersion()..valor = 5;
      var invalidaciones = 0;
      final coord = armar(dv, invalidar: () => invalidaciones++);

      coord.alCambiarSesion(haySesion: true);
      async.flushMicrotasks(); // inmediato: lee 5 (primera) → NO invalida
      expect(invalidaciones, 0, reason: 'la primera lectura solo guarda el valor');

      dv.valor = 6; // otra conexión escribió
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks(); // lee 6 != 5 → invalida
      expect(invalidaciones, 1);

      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks(); // lee 6 == 6 → no invalida
      expect(invalidaciones, 1, reason: 'mismo valor no invalida');

      dv.valor = 7;
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks(); // lee 7 != 6 → invalida
      expect(invalidaciones, 2);
    });
  });

  test('un chequeo en curso descarta el tick que se superpone (nunca dos lecturas en paralelo)',
      () {
    fakeAsync((async) {
      final dv = _FakeDataVersion();
      final coord = armar(dv, intervalo: const Duration(seconds: 1));

      dv.gate = Completer<int>(); // la lectura queda colgada
      coord.alCambiarSesion(haySesion: true);
      async.flushMicrotasks();
      expect(dv.lecturas, 1, reason: 'chequeo inmediato en curso (colgado)');

      async.elapse(const Duration(seconds: 3)); // 3 ticks mientras sigue en curso
      expect(dv.lecturas, 1, reason: 'los ticks que se superponen se descartan');

      dv.gate!.complete(1);
      dv.gate = null;
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(dv.lecturas, 2, reason: 'liberado, el siguiente tick sí lee');
    });
  });

  group('reconciliación programada (filas en esperando_resolucion)', () {
    test('1 fila en espera, última = ahora-30 s → reconcilia a los 90 s, no antes', () {
      fakeAsync((async) {
        final dv = _FakeDataVersion();
        var ultima = clock.now().subtract(const Duration(seconds: 30));
        var llamadas = 0;
        final coord = armar(
          dv,
          ultimaReconciliacion: () async => ultima,
          reconciliarSiCorresponde: () async {
            llamadas++;
            ultima = clock.now(); // como registrarReconciliacion en producción
          },
        );
        coord.alCambiarSesion(haySesion: true);
        coord.alCambiarEnEspera(hay: true);
        async.flushMicrotasks(); // programa: lee última, agenda a +90 s
        expect(coord.reconciliando, isTrue);

        async.elapse(const Duration(seconds: 89));
        async.flushMicrotasks();
        expect(llamadas, 0, reason: 'no antes de los 90 s');
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(llamadas, 1, reason: 'reconcilia a última+ventanaDebounce = 90 s');
      });
    });

    test('si la fila sigue en espera: una nueva llamada 2 min después', () {
      fakeAsync((async) {
        final dv = _FakeDataVersion();
        var ultima = clock.now().subtract(const Duration(seconds: 30));
        var llamadas = 0;
        final coord = armar(
          dv,
          ultimaReconciliacion: () async => ultima,
          reconciliarSiCorresponde: () async {
            llamadas++;
            ultima = clock.now();
          },
        );
        coord.alCambiarSesion(haySesion: true);
        coord.alCambiarEnEspera(hay: true);
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 90));
        async.flushMicrotasks();
        expect(llamadas, 1);
        async.elapse(const Duration(seconds: 120));
        async.flushMicrotasks();
        expect(llamadas, 2, reason: 'reprograma a última+debounce (2 min)');
      });
    });

    test('sin filas en espera: 0 llamadas en 10 min', () {
      fakeAsync((async) {
        final dv = _FakeDataVersion();
        var llamadas = 0;
        final coord = armar(dv, reconciliarSiCorresponde: () async => llamadas++);
        coord.alCambiarSesion(haySesion: true);
        async.flushMicrotasks();
        expect(coord.reconciliando, isFalse);
        async.elapse(const Duration(minutes: 10));
        async.flushMicrotasks();
        expect(llamadas, 0);
      });
    });

    test('paused y logout cancelan la reconciliación programada (0 llamadas)', () {
      fakeAsync((async) {
        final dv = _FakeDataVersion();
        final ultima = clock.now().subtract(const Duration(seconds: 30));
        var llamadas = 0;
        final coord = armar(
          dv,
          ultimaReconciliacion: () async => ultima,
          reconciliarSiCorresponde: () async => llamadas++,
        );
        coord.alCambiarSesion(haySesion: true);
        coord.alCambiarEnEspera(hay: true);
        async.flushMicrotasks();
        expect(coord.reconciliando, isTrue);

        coord.alCambiarCicloDeVida(AppLifecycleState.paused);
        expect(coord.reconciliando, isFalse);
        async.elapse(const Duration(minutes: 10));
        async.flushMicrotasks();
        expect(llamadas, 0, reason: 'paused canceló');

        coord.alCambiarCicloDeVida(AppLifecycleState.resumed);
        async.flushMicrotasks();
        expect(coord.reconciliando, isTrue);
        coord.alCambiarSesion(haySesion: false); // logout
        expect(coord.reconciliando, isFalse);
        async.elapse(const Duration(minutes: 10));
        async.flushMicrotasks();
        expect(llamadas, 0, reason: 'logout también canceló');
      });
    });

    test('cuando la última fila sale de espera, el Timer se cancela', () {
      fakeAsync((async) {
        final dv = _FakeDataVersion();
        final ultima = clock.now().subtract(const Duration(seconds: 30));
        var llamadas = 0;
        final coord = armar(
          dv,
          ultimaReconciliacion: () async => ultima,
          reconciliarSiCorresponde: () async => llamadas++,
        );
        coord.alCambiarSesion(haySesion: true);
        coord.alCambiarEnEspera(hay: true);
        async.flushMicrotasks();
        expect(coord.reconciliando, isTrue);

        coord.alCambiarEnEspera(hay: false); // la última fila salió de espera
        expect(coord.reconciliando, isFalse);
        async.elapse(const Duration(minutes: 10));
        async.flushMicrotasks();
        expect(llamadas, 0);
      });
    });
  });

  group('tolerancia a fallos (CTT-141, revisión de Chat)', () {
    test('reconciliar falla repetidamente: los intentos van a 2 min, nunca cada 2 s', () {
      fakeAsync((async) {
        final dv = _FakeDataVersion();
        // debounce ya elapsado → el 1er intento cae al piso (2 s); los siguientes, a +2 min.
        final ultima = clock.now().subtract(const Duration(minutes: 2));
        var llamadas = 0;
        final coord = armar(
          dv,
          ultimaReconciliacion: () async => ultima, // NO avanza (todo falla)
          reconciliarSiCorresponde: () async {
            llamadas++;
            throw Exception('GET /mios sin red');
          },
        );
        coord.alCambiarSesion(haySesion: true);
        coord.alCambiarEnEspera(hay: true);
        async.flushMicrotasks();

        async.elapse(const Duration(minutes: 10));
        async.flushMicrotasks();
        // Intentos a ~2 s, 2:02, 4:02, 6:02, 8:02 → ~5 en 10 min. Si cayera cada 2 s serían ~300.
        expect(llamadas, lessThanOrEqualTo(6),
            reason: 'tras el fallo reprograma a +ventana (2 min), no cada 2 s');
        expect(llamadas, greaterThanOrEqualTo(4),
            reason: 'y sí reintenta (no se muere): ~5 en 10 min');
      });
    });

    test('un fallo seguido de un éxito vuelve a la regla normal (ultima solo en éxito)', () {
      fakeAsync((async) {
        final dv = _FakeDataVersion();
        var ultima = clock.now().subtract(const Duration(minutes: 2)); // debounce elapsado
        var llamadas = 0;
        var fallaProxima = true;
        final coord = armar(
          dv,
          ultimaReconciliacion: () async => ultima,
          reconciliarSiCorresponde: () async {
            llamadas++;
            if (fallaProxima) {
              fallaProxima = false;
              throw Exception('sin red');
            }
            ultima = clock.now(); // ÉXITO: avanza, como registrarReconciliacion
          },
        );
        coord.alCambiarSesion(haySesion: true);
        coord.alCambiarEnEspera(hay: true);
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 2)); // 1er intento → FALLA
        async.flushMicrotasks();
        expect(llamadas, 1);
        final ultimaTrasFallo = ultima; // no avanzó

        async.elapse(const Duration(minutes: 2)); // +ventana → 2º intento → ÉXITO
        async.flushMicrotasks();
        expect(llamadas, 2);
        expect(ultima, isNot(ultimaTrasFallo), reason: 'el éxito escribió ultima');

        // Regla normal: el 3er intento llega a ultima(nuevo)+ventana, nada antes.
        async.elapse(const Duration(minutes: 1));
        async.flushMicrotasks();
        expect(llamadas, 2, reason: 'no hay intento antes de ultima+ventana');
        async.elapse(const Duration(minutes: 1));
        async.flushMicrotasks();
        expect(llamadas, 3, reason: 'el 3er intento a ultima+ventana (regla normal)');
      });
    });

    test('un fallo de reconciliar no deja errores asíncronos sin capturar', () {
      final errores = <Object>[];
      runZonedGuarded(() {
        fakeAsync((async) {
          final dv = _FakeDataVersion();
          final ultima = clock.now().subtract(const Duration(minutes: 2));
          final coord = armar(
            dv,
            ultimaReconciliacion: () async => ultima,
            reconciliarSiCorresponde: () async => throw Exception('sin red'),
          );
          coord.alCambiarSesion(haySesion: true);
          coord.alCambiarEnEspera(hay: true);
          async.elapse(const Duration(minutes: 10));
        });
      }, (e, st) => errores.add(e));
      expect(errores, isEmpty,
          reason: 'el catch del coordinador evita el error sin capturar');
    });

    test('el sondeo de data_version que falla no deja error sin capturar y sigue sondeando', () {
      final errores = <Object>[];
      late bool sondeandoFinal;
      late int invalidacionesFinal;
      late int lecturasFinal;
      runZonedGuarded(() {
        fakeAsync((async) {
          final dv = _FakeDataVersion()..lanza = true;
          var inval = 0;
          final coord = armar(dv, invalidar: () => inval++);
          coord.alCambiarSesion(haySesion: true);
          async.elapse(const Duration(minutes: 10));
          sondeandoFinal = coord.sondeando;
          invalidacionesFinal = inval;
          lecturasFinal = dv.lecturas;
        });
      }, (e, st) => errores.add(e));
      expect(errores, isEmpty, reason: 'el catch del sondeo evita el error sin capturar');
      expect(sondeandoFinal, isTrue, reason: 'el poll sigue vivo pese a los fallos');
      expect(invalidacionesFinal, 0, reason: 'cada lectura falló → nunca invalida');
      expect(lecturasFinal, greaterThan(1), reason: 'reintenta cada 2 s');
    });
  });
}
