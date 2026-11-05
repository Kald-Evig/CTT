/// planificador_sync.dart — Planificador de sync en PRIMER PLANO (CTT-141).
///
/// En vez de sondear la cola, agenda UN Timer al próximo instante en que alguna fila vuelve
/// a ser reclamable (SyncDao.observarProximoReclamable): pendiente→proximo_intento_en,
/// enviando→tomado_hasta. Al cambiar ese MIN, cancela y reprograma. El delay tiene un PISO de
/// 2 s (evita disparos en ráfaga). Al disparar llama al ciclo (vía el guard single-flight).
///
/// Vive SOLO en el isolate 'ui' y SOLO con sesión válida en primer plano: se activa en
/// resumed+sesión, se desactiva en paused/hidden y en logout. El headless no usa esto.
///
/// Clase de lógica pura (sin widgets ni Riverpod; solo `debugPrint`) para testearse con
/// fake_async. El reloj es `clock.now()` (package:clock) para que fake_async controle el tiempo.
library;

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart' show debugPrint;

class PlanificadorSync {
  PlanificadorSync({
    required Future<void> Function() ejecutar,
    Duration piso = const Duration(seconds: 2),
  })  : _ejecutar = ejecutar,
        _piso = piso;

  /// Dispara el ciclo de la UI (en producción: cicloSyncUi.ejecutar(), que COALESCE: si ya
  /// hay una corrida en curso, junta esta en una re-corrida en vez de solaparse).
  final Future<void> Function() _ejecutar;

  /// Piso del delay del Timer (decisión de Kald: 2 s).
  final Duration _piso;

  Timer? _timer;
  DateTime? _min;
  bool _activo = false;

  /// Solo para tests/diagnóstico.
  bool get activo => _activo;
  bool get tieneTimer => _timer != null;

  /// Nuevo MIN del stream de reclamables (null = no hay filas no terminales → sin Timer).
  void actualizarMin(DateTime? min) {
    _min = min;
    _reprogramar();
  }

  /// Primer plano CON sesión: arranca/rearma el Timer según el último MIN.
  void activar() {
    if (_activo) return;
    _activo = true;
    _reprogramar();
  }

  /// paused/hidden o logout: cancela el Timer y queda inactivo. No se reactiva sin [activar].
  void desactivar() {
    _activo = false;
    _timer?.cancel();
    _timer = null;
  }

  void _reprogramar() {
    _timer?.cancel();
    _timer = null;
    if (!_activo || _min == null) return;
    final falta = _min!.difference(clock.now());
    final delay = falta < _piso ? _piso : falta; // piso de 2 s
    _timer = Timer(delay, _disparar);
  }

  void _disparar() {
    _timer = null;
    if (!_activo) return;
    // La re-entrada la maneja el guard (cicloSyncUi): si ya hay una corrida en curso, esta
    // llamada se coalesce en una re-corrida en vez de solaparse. Por eso el planificador NO
    // necesita su propio chequeo "en vuelo" ni re-agendar al piso — eso generaba un sondeo de
    // 2 s DURANTE cada corrida. CTT-141 (revisión de Chat).
    // ejecutar() (el guard) puede completar con error (p. ej. deviceIdService.obtener falla); al
    // no esperarse, escaparía como error asíncrono sin capturar. Se loguea y se traga: el próximo
    // MIN del stream reprograma; no hace falta reintentar acá.
    unawaited(_ejecutar().catchError((Object e, StackTrace st) {
      debugPrint('CTT-141: el ciclo disparado por el planificador falló: $e\n$st');
    }));
    // No se reprograma acá: la corrida cambia sync_pendientes y el stream reemite el nuevo MIN,
    // que vuelve a programar el Timer (o emite null si la cola quedó sin filas no terminales).
  }

  void dispose() => desactivar();
}
