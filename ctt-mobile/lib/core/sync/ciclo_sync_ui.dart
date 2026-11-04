/// ciclo_sync_ui.dart — Entrada ÚNICA al ciclo de sync del isolate 'ui' (CTT-141).
///
/// Envuelve [CicloSync.ejecutar] con single-flight + COALESCING: nunca se solapan dos
/// corridas de la UI, y las llamadas que llegan mientras hay una en vuelo se juntan en
/// UNA sola re-corrida que arranca apenas termina la actual. No descarta llamadas.
///
/// Invariante clave: el future que devuelve [ejecutar] se completa cuando termina una
/// corrida que EMPEZÓ DESPUÉS de esa llamada. `cerrarSesion` (auth_notifier) cuenta las
/// filas no terminales después de `await ejecutar()`; si se le devolviera la corrida en
/// vuelo —que pudo leer la cola ANTES de una fila recién encolada— contaría con datos
/// viejos. Por eso una llamada durante el vuelo espera la re-corrida, no la actual.
///
/// La exclusión ENTRE isolates sigue siendo el lease por fila (SyncDao.reclamar): el
/// headless (sync_service.dart) NO pasa por este guard, usa [CicloSync] directo.
///
/// Vive en un provider keepAlive porque [CicloSync] (cicloSyncProvider) es autoDispose y
/// se reconstruye entre lecturas: el estado del guard no puede vivir ahí.
library;

import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:ctt_mobile/core/sync/ciclo_sync.dart';

part 'ciclo_sync_ui.g.dart';

/// Single-flight con una re-corrida pendiente (coalescing). Lógica pura: recibe la
/// corrida real por constructor para poder testearse sin Riverpod ni Dio.
class CicloSyncUi {
  CicloSyncUi(this._correr);

  /// La corrida real del ciclo. En producción: `cicloSync.ejecutar()`.
  final Future<void> Function() _correr;

  /// Completer de la corrida EN CURSO (null si no hay ninguna en vuelo).
  Completer<void>? _actual;

  /// Completer de la (única) re-corrida pendiente: varias llamadas durante el vuelo lo
  /// comparten, así se juntan en una sola re-corrida.
  Completer<void>? _siguiente;

  /// ¿Hay una corrida en vuelo? (para tests y para el guard del planificador).
  bool get enVuelo => _actual != null;

  /// Ejecuta el ciclo con coalescing. Ver el invariante en el encabezado del archivo.
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

  void _lanzar() {
    // Future.sync: si [_correr] lanza SINCRÓNICAMENTE, se traduce a un future fallido en
    // vez de romper el estado del guard (no queda trabado).
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

    // La re-corrida pendiente arranca ANTES de completar a quienes esperaban la corrida
    // que recién terminó: así un `await ejecutar()` que recibió [siguiente] ve una corrida
    // ya iniciada, y la excepción de la corrida previa NO impide la re-corrida.
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

/// Provider keepAlive: estado del guard estable toda la sesión. Cablea la corrida real al
/// ciclo foreground (cicloSyncProvider, autoDispose → se reconstruye en cada lectura, por
/// eso lee fresco en cada corrida). Los disparadores de la UI (conectividad, transición,
/// auth) y el planificador (CTT-141) llaman a ESTE, no a cicloSyncProvider.
@Riverpod(keepAlive: true)
CicloSyncUi cicloSyncUi(CicloSyncUiRef ref) =>
    CicloSyncUi(() => ref.read(cicloSyncProvider).ejecutar());
