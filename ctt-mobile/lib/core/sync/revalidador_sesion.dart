/// revalidador_sesion.dart — Re-resuelve la sesión offline cuando vuelve la red (CTT-157).
///
/// Controlador PURO (sin Riverpod ni Flutter salvo el enum de ciclo de vida), reloj inyectable,
/// para testearse con fake_async — igual que [CoordinadorSyncForeground] (CTT-141). El cableado
/// (provider + widget + interceptor + conectividad) vive aparte.
///
/// Mientras la sesión está `autenticadoOffline`, varios DISPARADORES (2xx del interceptor, flanco
/// de conectividad, `resumed`, sondeo periódico en primer plano) son solo INDICIOS de que la red
/// pudo volver. El único árbitro es el resultado de `/me`: [solicitar] pide una re-resolución
/// (`reResolver`), con GUARDA (solo si offline), SINGLE-FLIGHT (una a la vez, se descartan las
/// concurrentes — no se encolan) e INTERVALO mínimo entre intentos.
library;

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;

/// Intervalo mínimo entre re-resoluciones (CTT-157): un 2º intento antes de esto se descarta.
const Duration kIntervaloMinimoRevalidacion = Duration(seconds: 30);

/// Período del sondeo mientras la sesión está offline en primer plano (CTT-157, aprobado por Kald).
const Duration kIntervaloSondeoRevalidacion = Duration(seconds: 60);

class RevalidadorSesion {
  RevalidadorSesion({
    required Future<void> Function() reResolver,
    DateTime Function()? reloj,
    Duration intervaloMinimo = kIntervaloMinimoRevalidacion,
    Duration intervaloSondeo = kIntervaloSondeoRevalidacion,
  })  : _reResolver = reResolver,
        _reloj = reloj ?? clock.now,
        _intervaloMinimo = intervaloMinimo,
        _intervaloSondeo = intervaloSondeo;

  final Future<void> Function() _reResolver;
  final DateTime Function() _reloj;
  final Duration _intervaloMinimo;
  final Duration _intervaloSondeo;

  bool _offline = false;
  bool _foreground = true;
  bool _enVuelo = false;
  DateTime? _ultimoIntento;
  Timer? _timer;

  /// Solo para tests/diagnóstico.
  bool get enVuelo => _enVuelo;
  bool get sondeando => _timer != null;

  /// Pide una re-resolución si corresponde. La llaman TODOS los disparadores (indicios). Reglas:
  ///   · GUARDA: solo si la sesión está offline;
  ///   · SINGLE-FLIGHT: si hay una en vuelo, se DESCARTA (no se encola);
  ///   · INTERVALO: si el último intento fue hace menos de [_intervaloMinimo], se descarta.
  /// El árbitro final es `reResolver` (resuelve /me); su fallo por transporte vuelve a offline.
  Future<void> solicitar() async {
    if (_enVuelo) return;
    if (!_offline) return;
    final ahora = _reloj();
    if (_ultimoIntento != null &&
        ahora.difference(_ultimoIntento!) < _intervaloMinimo) {
      return;
    }
    _enVuelo = true;
    _ultimoIntento = ahora;
    try {
      await _reResolver();
    } finally {
      _enVuelo = false;
    }
  }

  /// Cambió el estado offline (lo alimenta el widget desde estadoAuth). Arranca/detiene el sondeo.
  void alCambiarEstadoOffline(bool offline) {
    if (offline == _offline) return;
    _offline = offline;
    _reevaluarSondeo();
  }

  /// Cambió el ciclo de vida. `resumed` = primer plano + disparador inmediato; paused/hidden =
  /// background (detiene el sondeo); inactive/detached se ignoran (transitorios).
  void alCambiarCicloDeVida(AppLifecycleState estado) {
    switch (estado) {
      case AppLifecycleState.resumed:
        _foreground = true;
        _reevaluarSondeo();
        solicitar();
      case AppLifecycleState.paused || AppLifecycleState.hidden:
        _foreground = false;
        _reevaluarSondeo();
      case AppLifecycleState.inactive || AppLifecycleState.detached:
        return;
    }
  }

  /// El sondeo periódico corre SOLO con sesión offline Y en primer plano.
  void _reevaluarSondeo() {
    if (_offline && _foreground) {
      _timer ??= Timer.periodic(_intervaloSondeo, (_) => solicitar());
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
