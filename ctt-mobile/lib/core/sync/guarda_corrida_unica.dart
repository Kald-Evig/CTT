/// guarda_corrida_unica.dart — Guard single-flight + coalescing reutilizable (CTT-141).
///
/// Serializa una corrida asíncrona (nunca dos en paralelo) y ofrece DOS entradas con
/// semántica distinta sobre el mismo estado en vuelo:
///
///   • [ejecutar]        RUN-AFTER: el future se completa con una corrida que EMPEZÓ
///                       DESPUÉS de la llamada. Si hay una en vuelo, las llamadas se juntan
///                       en UNA sola re-corrida que arranca apenas termina la actual.
///   • [unirseOIniciar]  JOIN-OR-START: si hay una en vuelo, se SUMA a ella (devuelve su
///                       future) sin lanzar otra corrida. Si no hay ninguna, inicia una.
///
/// La extracción nace de que dos llamadores necesitaban el mismo mecanismo de concurrencia
/// (CTT-141): el ciclo de sync de la UI (solo run-after, ver [CicloSyncUi]) y el reconciliador
/// de conflictos (run-after para el bypass tras un 200, join-or-start para el debounce). Es el
/// mismo CONOCIMIENTO (el baile de completers de [_finalizar]); por eso vive en un solo lugar.
///
/// Lógica pura: recibe la corrida real por constructor para testearse sin Riverpod ni Dio. El
/// estado (completers en memoria) NO puede vivir en un provider autoDispose: quien lo use debe
/// mantenerlo en un keepAlive para que todos los disparadores compartan la MISMA instancia.
library;

import 'dart:async';

class GuardaCorridaUnica {
  GuardaCorridaUnica(this._correr);

  /// La corrida real. En producción: `cicloSync.ejecutar()` o la reconciliación.
  final Future<void> Function() _correr;

  /// Completer de la corrida EN CURSO (null si no hay ninguna en vuelo).
  Completer<void>? _actual;

  /// Completer de la (única) re-corrida pendiente de [ejecutar]: varias llamadas durante el
  /// vuelo lo comparten, así se juntan en una sola re-corrida.
  Completer<void>? _siguiente;

  /// ¿Hay una corrida en vuelo?
  bool get enVuelo => _actual != null;

  /// RUN-AFTER (ver encabezado). El future se completa cuando termina una corrida que EMPEZÓ
  /// DESPUÉS de esta llamada: si hay una en vuelo, se agenda/comparte la re-corrida.
  Future<void> ejecutar() {
    if (_actual == null) {
      _actual = Completer<void>();
      _lanzar();
      return _actual!.future;
    }
    // Hay una corrida en vuelo: juntar esta llamada (y las que vengan) en una re-corrida.
    _siguiente ??= Completer<void>();
    return _siguiente!.future;
  }

  /// JOIN-OR-START (ver encabezado). Si hay una corrida en vuelo, devuelve SU future (sin
  /// lanzar otra); si no, inicia una. No crea re-corridas: se suma a lo que ya esté andando.
  Future<void> unirseOIniciar() {
    if (_actual != null) return _actual!.future;
    _actual = Completer<void>();
    _lanzar();
    return _actual!.future;
  }

  void _lanzar() {
    // Future.sync: si [_correr] lanza SINCRÓNICAMENTE, se traduce a un future fallido en vez de
    // romper el estado del guard (no queda trabado).
    Future.sync(_correr).then(
      (_) => _finalizar(null, null),
      onError: (Object e, StackTrace st) => _finalizar(e, st),
    );
  }

  void _finalizar(Object? error, StackTrace? st) {
    final terminado = _actual!;
    final siguiente = _siguiente;
    _actual = null;
    _siguiente = null;

    // La re-corrida pendiente arranca ANTES de completar a quienes esperaban la corrida que
    // recién terminó: así un `await ejecutar()` que recibió [siguiente] ve una corrida ya
    // iniciada, y la excepción de la corrida previa NO impide la re-corrida.
    if (siguiente != null) {
      _actual = siguiente;
      _lanzar();
    }

    if (error == null) {
      terminado.complete();
    } else {
      terminado.completeError(error, st ?? StackTrace.current);
    }
  }
}
