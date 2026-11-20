/// revalidador_sesion_test.dart — CTT-157. El controlador puro con fake_async:
/// single-flight, intervalo mínimo (30 s) y sondeo periódico (60 s) en primer plano.
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';

import 'package:ctt_mobile/core/sync/revalidador_sesion.dart';

void main() {
  // T4 — single-flight + intervalo mínimo.
  test('T4: N solicitar simultáneos → 1 reResolver; 2º antes de 30 s no llama; a los 30 s sí',
      () {
    fakeAsync((async) {
      var llamadas = 0;
      final enCurso = <Completer<void>>[];
      final r = RevalidadorSesion(reResolver: () {
        llamadas++;
        final c = Completer<void>();
        enCurso.add(c);
        return c.future;
      },);
      r.alCambiarEstadoOffline(true);

      // 3 disparadores concurrentes → single-flight → exactamente 1.
      r.solicitar();
      r.solicitar();
      r.solicitar();
      async.flushMicrotasks();
      expect(llamadas, 1, reason: 'single-flight: exactamente 1 /me');

      // Termina la re-resolución en vuelo.
      enCurso.first.complete();
      async.flushMicrotasks();

      // 2º intento inmediato (< 30 s) → descartado por intervalo.
      r.solicitar();
      async.flushMicrotasks();
      expect(llamadas, 1, reason: 'intervalo: un 2º intento antes de 30 s no llama');

      // Pasados 30 s, un nuevo intento sí llama.
      async.elapse(const Duration(seconds: 30));
      r.solicitar();
      async.flushMicrotasks();
      expect(llamadas, 2, reason: 'tras 30 s sí vuelve a llamar');
      enCurso.last.complete();
      r.dispose();
    });
  });

  // T5 — sondeo periódico: offline en primer plano llama cada 60 s; en background no.
  test('T5: offline en foreground → /me cada 60 s; paused → deja de sondear', () {
    fakeAsync((async) {
      var llamadas = 0;
      final r = RevalidadorSesion(reResolver: () async => llamadas++);

      r.alCambiarEstadoOffline(true); // offline + foreground (default) → sondeo activo
      expect(r.sondeando, isTrue);

      async.elapse(const Duration(seconds: 60));
      async.flushMicrotasks();
      expect(llamadas, 1, reason: 'a los 60 s, un intento');

      async.elapse(const Duration(seconds: 60));
      async.flushMicrotasks();
      expect(llamadas, 2, reason: 'y otro a los 120 s');

      // A background: el sondeo se detiene.
      r.alCambiarCicloDeVida(AppLifecycleState.paused);
      expect(r.sondeando, isFalse);
      final antes = llamadas;
      async.elapse(const Duration(seconds: 180));
      async.flushMicrotasks();
      expect(llamadas, antes, reason: 'en background no sondea');

      r.dispose();
    });
  });

  // T5b — online nunca sondea (la guarda es offline).
  test('T5b: online (no offline) → no arranca el sondeo', () {
    fakeAsync((async) {
      var llamadas = 0;
      final r = RevalidadorSesion(reResolver: () async => llamadas++);
      r.alCambiarEstadoOffline(false); // online
      expect(r.sondeando, isFalse);
      async.elapse(const Duration(seconds: 300));
      async.flushMicrotasks();
      expect(llamadas, 0, reason: 'online: ningún /me');
      r.dispose();
    });
  });
}
