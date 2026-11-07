/// guarda_corrida_unica_test.dart — CTT-141: primitivo single-flight + coalescing con DOS
/// entradas (ejecutar = run-after, unirseOIniciar = join-or-start) y su mezcla.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:ctt_mobile/core/sync/guarda_corrida_unica.dart';

/// Corrida inyectable: cada invocación queda esperando un gate que el test completa (o falla).
class _CorridaFake {
  final List<Completer<void>> gates = [];
  int invocaciones = 0;

  Future<void> call() {
    invocaciones++;
    final g = Completer<void>();
    gates.add(g);
    return g.future;
  }

  void completar(int i) => gates[i].complete();
  void fallar(int i, Object e) => gates[i].completeError(e);
}

void main() {
  group('ejecutar (run-after)', () {
    test('3 ejecutar durante el vuelo → EXACTAMENTE 1 re-corrida', () async {
      final c = _CorridaFake();
      final g = GuardaCorridaUnica(c.call);

      final f1 = g.ejecutar(); // idle → C1
      expect(c.invocaciones, 1);
      expect(g.enVuelo, isTrue);

      final f2 = g.ejecutar();
      final f3 = g.ejecutar();
      final f4 = g.ejecutar();
      expect(c.invocaciones, 1, reason: 'las 3 se juntan en una sola re-corrida');

      c.completar(0); // C1 termina → arranca C2 (la única re-corrida)
      await f1;
      expect(c.invocaciones, 2);

      c.completar(1);
      await Future.wait([f2, f3, f4]);
      expect(c.invocaciones, 2, reason: 'no hay más re-corridas');
      expect(g.enVuelo, isFalse);
    });
  });

  group('unirseOIniciar (join-or-start)', () {
    test('idle → inicia una corrida', () async {
      final c = _CorridaFake();
      final g = GuardaCorridaUnica(c.call);

      final f = g.unirseOIniciar();
      expect(c.invocaciones, 1);
      expect(g.enVuelo, isTrue);
      c.completar(0);
      await f;
      expect(g.enVuelo, isFalse);
    });

    test('2 unirseOIniciar durante el vuelo → se suman, NINGÚN GET extra ni re-corrida',
        () async {
      final c = _CorridaFake();
      final g = GuardaCorridaUnica(c.call);

      final f1 = g.unirseOIniciar(); // idle → C1
      final f2 = g.unirseOIniciar(); // en vuelo → se suma a C1
      final f3 = g.unirseOIniciar(); // en vuelo → se suma a C1
      expect(c.invocaciones, 1, reason: 'una sola corrida; las otras 2 se unen');

      c.completar(0);
      await Future.wait([f1, f2, f3]);
      expect(c.invocaciones, 1, reason: 'sin re-corrida: join-or-start no agenda');
      expect(g.enVuelo, isFalse);
    });
  });

  group('mezcla', () {
    test('unirseOIniciar durante un vuelo iniciado por ejecutar → se une a ese vuelo',
        () async {
      final c = _CorridaFake();
      final g = GuardaCorridaUnica(c.call);

      final fEjec = g.ejecutar(); // C1
      var unirListo = false;
      final fUnir = g.unirseOIniciar(); // se une a C1 (no agenda re-corrida)
      unawaited(fUnir.then((_) => unirListo = true));
      expect(c.invocaciones, 1, reason: 'unirseOIniciar NO lanzó otra corrida');

      c.completar(0); // C1 termina
      await fEjec;
      await fUnir;
      expect(unirListo, isTrue, reason: 'el que se unió se completa con C1');
      expect(c.invocaciones, 1, reason: 'no hubo re-corrida desde el join');
      expect(g.enVuelo, isFalse);
    });

    test('ejecutar durante un vuelo iniciado por unirseOIniciar → programa una re-corrida',
        () async {
      final c = _CorridaFake();
      final g = GuardaCorridaUnica(c.call);

      final fUnir = g.unirseOIniciar(); // C1
      var ejecListo = false;
      final fEjec = g.ejecutar(); // en vuelo → re-corrida C2
      unawaited(fEjec.then((_) => ejecListo = true));
      expect(c.invocaciones, 1, reason: 'la re-corrida aún no arrancó');

      c.completar(0); // C1 termina → arranca C2
      await fUnir;
      expect(c.invocaciones, 2, reason: 'ejecutar programó una re-corrida');
      expect(ejecListo, isFalse, reason: 'el future de ejecutar espera la re-corrida');

      c.completar(1); // C2 termina
      await fEjec;
      expect(ejecListo, isTrue);
      expect(g.enVuelo, isFalse);
    });
  });

  group('un fallo no traba el guard ni genera bucle', () {
    test('falla con quienes esperaban (ejecutar + unirseOIniciar) → todos reciben el error, '
        'se libera, y la re-corrida pendiente igual se ejecuta', () async {
      final c = _CorridaFake();
      final g = GuardaCorridaUnica(c.call);

      final f1 = g.unirseOIniciar(); // C1
      final fJoin = g.unirseOIniciar(); // se une a C1
      final fRerun = g.ejecutar(); // re-corrida pendiente C2
      final e1 = expectLater(f1, throwsA(isA<StateError>()));
      final e2 = expectLater(fJoin, throwsA(isA<StateError>()));

      c.fallar(0, StateError('boom')); // C1 falla
      await Future.wait([e1, e2]);
      expect(c.invocaciones, 2, reason: 'la re-corrida arrancó pese al error de C1');

      c.completar(1);
      await fRerun; // la re-corrida completa normalmente
      expect(g.enVuelo, isFalse, reason: 'no quedó trabado; sin re-corridas extra (no bucle)');
      expect(c.invocaciones, 2);
    });
  });
}
