/// planificador_sync_test.dart — CTT-141: planificador de sync en primer plano (fake_async).
library;

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ctt_mobile/core/sync/planificador_sync.dart';

void main() {
  test('una fila a +10 s → ejecutar() a los 10 s, no antes', () {
    fakeAsync((async) {
      var n = 0;
      final p = PlanificadorSync(
        ejecutar: () async => n++,      )..activar();
      p.actualizarMin(clock.now().add(const Duration(seconds: 10)));

      async.elapse(const Duration(seconds: 9));
      expect(n, 0, reason: 'no dispara antes');
      async.elapse(const Duration(seconds: 1));
      expect(n, 1, reason: 'dispara a los 10 s');
    });
  });

  test('un lease vencido a +5 s (enviando) → ejecutar() a los 5 s', () {
    fakeAsync((async) {
      var n = 0;
      final p = PlanificadorSync(
        ejecutar: () async => n++,      )..activar();
      p.actualizarMin(clock.now().add(const Duration(seconds: 5)));

      async.elapse(const Duration(seconds: 5));
      expect(n, 1);
    });
  });

  test('un MIN en el pasado o a +0,1 s → se respeta el piso de 2 s', () {
    fakeAsync((async) {
      var n = 0;
      final p = PlanificadorSync(
        ejecutar: () async => n++,      )..activar();
      p.actualizarMin(clock.now().subtract(const Duration(seconds: 30))); // ya vencido

      async.elapse(const Duration(milliseconds: 1900));
      expect(n, 0, reason: 'no dispara antes del piso');
      async.elapse(const Duration(milliseconds: 100));
      expect(n, 1, reason: 'dispara al cumplirse el piso de 2 s');
    });
  });

  test('encolar una fila con un MIN menor reprograma el Timer', () {
    fakeAsync((async) {
      var n = 0;
      final p = PlanificadorSync(
        ejecutar: () async => n++,      )..activar();
      p.actualizarMin(clock.now().add(const Duration(seconds: 60)));

      async.elapse(const Duration(seconds: 3));
      // Llega un MIN menor (una fila nueva reclamable antes): a +5 s del inicio → +2 s de ahora.
      p.actualizarMin(clock.now().add(const Duration(seconds: 2)));
      async.elapse(const Duration(seconds: 2));
      expect(n, 1, reason: 'disparó por el MIN nuevo (+2 s), no esperó los 60 s');

      // El disparo armó la red de seguridad (30 s); simular que la corrida procesó la fila
      // (emisión del stream → cola vacía) cancela ese rearme y aísla este test.
      p.actualizarMin(null);
      async.elapse(const Duration(seconds: 60));
      expect(n, 1, reason: 'sin más MIN, no hay más disparos');
    });
  });

  test('paused cancela el Timer; resumed lo rearma', () {
    fakeAsync((async) {
      var n = 0;
      final p = PlanificadorSync(
        ejecutar: () async => n++,      )..activar();
      p.actualizarMin(clock.now().add(const Duration(seconds: 10)));

      p.desactivar(); // paused/hidden
      async.elapse(const Duration(seconds: 30));
      expect(n, 0, reason: 'paused canceló el Timer: no dispara');

      p.activar(); // resumed: el MIN quedó en el pasado → piso de 2 s
      async.elapse(const Duration(seconds: 2));
      expect(n, 1, reason: 'resumed rearmó y disparó');
    });
  });

  test('después del logout (desactivar) ningún Timer dispara ejecutar()', () {
    fakeAsync((async) {
      var n = 0;
      final p = PlanificadorSync(
        ejecutar: () async => n++,      )..activar();
      p.actualizarMin(clock.now().add(const Duration(seconds: 5)));

      p.desactivar(); // logout: cancela y queda inactivo
      // Aunque llegue un MIN nuevo (p. ej. el stream emite una última vez), no se reactiva.
      p.actualizarMin(clock.now());
      async.elapse(const Duration(minutes: 10));
      expect(n, 0, reason: 'sin activar() de nuevo, ningún Timer dispara');
      expect(p.tieneTimer, isFalse);
    });
  });

  test('si ejecutar() falla, el planificador no deja un error asíncrono sin capturar', () {
    final errores = <Object>[];
    late int llamadas;
    runZonedGuarded(() {
      fakeAsync((async) {
        var n = 0;
        final p = PlanificadorSync(
          ejecutar: () async {
            n++;
            throw Exception('deviceId falló');
          },
        )..activar();
        p.actualizarMin(clock.now()); // reclamable ya → dispara al piso (2 s)
        async.elapse(const Duration(seconds: 5));
        llamadas = n;
      });
    }, (e, st) => errores.add(e));
    expect(errores, isEmpty,
        reason: 'el catchError del planificador evita el error sin capturar');
    expect(llamadas, 1, reason: 'disparó una vez');
  });

  test('red de seguridad: si tras un disparo el MIN sigue en el pasado sin emisión, rearma a '
      '30 s (backoffBase), no al piso de 2 s', () {
    fakeAsync((async) {
      var n = 0;
      final p = PlanificadorSync(ejecutar: () async => n++)..activar();
      // MIN "ya" (reclamable ahora): dispara al piso de 2 s.
      p.actualizarMin(DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
      async.elapse(const Duration(seconds: 2));
      expect(n, 1, reason: 'primer disparo al piso de 2 s');

      // NO llega una emisión nueva (ejecutar() no cambió nada). No rearma a 2 s:
      async.elapse(const Duration(seconds: 29));
      expect(n, 1, reason: 'no rearma al piso de 2 s');
      async.elapse(const Duration(seconds: 1)); // +30 s desde el disparo
      expect(n, 2, reason: 'rearma a backoffBase (30 s)');
      // Y sigue reintentando a 30 s mientras no haya emisión.
      async.elapse(const Duration(seconds: 30));
      expect(n, 3);
    });
  });

  test('red de seguridad: una emisión nueva (cola vacía) cancela el rearme de seguridad', () {
    fakeAsync((async) {
      var n = 0;
      final p = PlanificadorSync(ejecutar: () async => n++)..activar();
      p.actualizarMin(DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
      async.elapse(const Duration(seconds: 2));
      expect(n, 1);

      p.actualizarMin(null); // la corrida vació la cola → emisión null
      async.elapse(const Duration(minutes: 5));
      expect(n, 1, reason: 'la emisión null canceló el rearme de seguridad');
      expect(p.tieneTimer, isFalse);
    });
  });
}
