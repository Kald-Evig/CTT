/// planificador_sync_test.dart — CTT-141: planificador de sync en primer plano (fake_async).
library;

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ctt_mobile/core/sync/planificador_sync.dart';

void main() {
  test('una fila a +10 s → ejecutar() a los 10 s, no antes', () {
    fakeAsync((async) {
      var n = 0;
      final p = PlanificadorSync(
        ejecutar: () async => n++,
        hayCorridaEnVuelo: () => false,
      )..activar();
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
        ejecutar: () async => n++,
        hayCorridaEnVuelo: () => false,
      )..activar();
      p.actualizarMin(clock.now().add(const Duration(seconds: 5)));

      async.elapse(const Duration(seconds: 5));
      expect(n, 1);
    });
  });

  test('un MIN en el pasado o a +0,1 s → se respeta el piso de 2 s', () {
    fakeAsync((async) {
      var n = 0;
      final p = PlanificadorSync(
        ejecutar: () async => n++,
        hayCorridaEnVuelo: () => false,
      )..activar();
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
        ejecutar: () async => n++,
        hayCorridaEnVuelo: () => false,
      )..activar();
      p.actualizarMin(clock.now().add(const Duration(seconds: 60)));

      async.elapse(const Duration(seconds: 3));
      // Llega un MIN menor (una fila nueva reclamable antes): a +5 s del inicio → +2 s de ahora.
      p.actualizarMin(clock.now().add(const Duration(seconds: 2)));
      async.elapse(const Duration(seconds: 2));
      expect(n, 1, reason: 'disparó por el MIN nuevo, no esperó los 60 s');

      async.elapse(const Duration(seconds: 60));
      expect(n, 1, reason: 'el Timer viejo de 60 s fue cancelado');
    });
  });

  test('paused cancela el Timer; resumed lo rearma', () {
    fakeAsync((async) {
      var n = 0;
      final p = PlanificadorSync(
        ejecutar: () async => n++,
        hayCorridaEnVuelo: () => false,
      )..activar();
      p.actualizarMin(clock.now().add(const Duration(seconds: 10)));

      p.desactivar(); // paused/hidden
      async.elapse(const Duration(seconds: 30));
      expect(n, 0, reason: 'paused canceló el Timer: no dispara');

      p.activar(); // resumed: el MIN quedó en el pasado → piso de 2 s
      async.elapse(const Duration(seconds: 2));
      expect(n, 1, reason: 'resumed rearmó y disparó');
    });
  });

  test('sin re-entrada: con una corrida en vuelo no se lanza otra; se re-chequea al piso', () {
    fakeAsync((async) {
      var n = 0;
      var enVuelo = true;
      final p = PlanificadorSync(
        ejecutar: () async => n++,
        hayCorridaEnVuelo: () => enVuelo,
      )..activar();
      p.actualizarMin(clock.now()); // reclamable ya → dispara al piso (2 s)

      async.elapse(const Duration(seconds: 2));
      expect(n, 0, reason: 'hay una corrida en vuelo: no se lanza otra');

      enVuelo = false; // la corrida en vuelo terminó
      async.elapse(const Duration(seconds: 2)); // re-chequeo al piso
      expect(n, 1, reason: 'sin corrida en vuelo, dispara en el próximo re-chequeo');
    });
  });

  test('después del logout (desactivar) ningún Timer dispara ejecutar()', () {
    fakeAsync((async) {
      var n = 0;
      final p = PlanificadorSync(
        ejecutar: () async => n++,
        hayCorridaEnVuelo: () => false,
      )..activar();
      p.actualizarMin(clock.now().add(const Duration(seconds: 5)));

      p.desactivar(); // logout: cancela y queda inactivo
      // Aunque llegue un MIN nuevo (p. ej. el stream emite una última vez), no se reactiva.
      p.actualizarMin(clock.now());
      async.elapse(const Duration(minutes: 10));
      expect(n, 0, reason: 'sin activar() de nuevo, ningún Timer dispara');
      expect(p.tieneTimer, isFalse);
    });
  });
}
