/// coordinador_sync_foreground.dart — Coordina el sync de PRIMER PLANO (CTT-141).
///
/// UNA sola regla de estado: `activo = (en primer plano Y con sesión)`. Al activarse arrancan
/// el planificador (Timer al próximo reclamable) Y el sondeo de `PRAGMA data_version`; al
/// desactivarse se detienen los dos. No hay ramas por evento: cada entrada (sesión / ciclo de
/// vida) actualiza un booleano y se recomputa la regla única.
///
/// COMPONE [PlanificadorSync] (le delega activar/desactivar; no reimplementa esa lógica) y le
/// agrega el sondeo de data_version. Lógica pura (sin Flutter salvo el enum de ciclo de vida,
/// sin Riverpod) para testearse con fake_async. El widget `PlanificadorForeground` es cableado
/// delgado: listeners de providers → [actualizarMin] / [alCambiarSesion] / [alCambiarCicloDeVida].
library;

import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleState;

import 'package:ctt_mobile/core/sync/planificador_sync.dart';

class CoordinadorSyncForeground {
  CoordinadorSyncForeground({
    required PlanificadorSync planificador,
    required Future<int> Function() leerDataVersion,
    required void Function() invalidarTodo,
    Duration intervaloSondeo = const Duration(seconds: 2),
  })  : _planificador = planificador,
        _leerDataVersion = leerDataVersion,
        _invalidarTodo = invalidarTodo,
        _intervalo = intervaloSondeo;

  final PlanificadorSync _planificador;
  final Future<int> Function() _leerDataVersion;
  final void Function() _invalidarTodo;
  final Duration _intervalo;

  bool _foreground = true; // la app se monta en primer plano
  bool _haySesion = false;
  bool _activo = false;

  Timer? _poll;
  int? _ultimoDataVersion;
  bool _chequeando = false;

  /// Solo para tests/diagnóstico.
  bool get activo => _activo;
  bool get sondeando => _poll != null;

  /// El MIN de reclamables cambió (lo pasa el widget desde el stream). Se delega al
  /// planificador, que solo reprograma si está activo.
  void actualizarMin(DateTime? min) => _planificador.actualizarMin(min);

  /// Cambió la sesión (true = sesión válida para sync).
  void alCambiarSesion({required bool haySesion}) {
    _haySesion = haySesion;
    _recomputar();
  }

  /// Cambió el ciclo de vida. resumed → primer plano; paused/hidden → background; inactive
  /// (transitorio) y detached se ignoran.
  void alCambiarCicloDeVida(AppLifecycleState estado) {
    switch (estado) {
      case AppLifecycleState.resumed:
        _foreground = true;
      case AppLifecycleState.paused || AppLifecycleState.hidden:
        _foreground = false;
      case AppLifecycleState.inactive || AppLifecycleState.detached:
        return;
    }
    _recomputar();
  }

  void _recomputar() {
    final debe = _foreground && _haySesion;
    if (debe == _activo) return;
    _activo = debe;
    if (_activo) {
      _planificador.activar();
      _iniciarSondeo();
    } else {
      _planificador.desactivar();
      _detenerSondeo();
    }
  }

  void _iniciarSondeo() {
    unawaited(_chequear()); // chequeo inmediato (cubre el resumed)
    _poll = Timer.periodic(_intervalo, (_) => unawaited(_chequear()));
  }

  void _detenerSondeo() {
    _poll?.cancel();
    _poll = null;
  }

  /// Lee data_version; si cambió desde la última lectura (otra conexión escribió, p. ej. el
  /// headless) invalida TODAS las tablas. La PRIMERA lectura solo guarda el valor. Si ya hay
  /// un chequeo en curso, el tick que se superpone se descarta: nunca dos lecturas en paralelo.
  /// [_ultimoDataVersion] persiste entre activaciones, así el chequeo inmediato del resumed
  /// detecta lo que el headless escribió mientras la app estaba en background.
  Future<void> _chequear() async {
    if (_chequeando) return;
    _chequeando = true;
    try {
      final v = await _leerDataVersion();
      if (_ultimoDataVersion != null && v != _ultimoDataVersion) {
        _invalidarTodo();
      }
      _ultimoDataVersion = v;
    } finally {
      _chequeando = false;
    }
  }

  void dispose() {
    _detenerSondeo();
    _planificador.dispose();
  }
}
