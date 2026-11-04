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
/// Clase de lógica pura (sin Flutter ni Riverpod) para testearse con fake_async. El reloj es
/// `clock.now()` (package:clock) para que fake_async controle el tiempo en los tests.
library;

import 'dart:async';

import 'package:clock/clock.dart';

class PlanificadorSync {
  PlanificadorSync({
    required Future<void> Function() ejecutar,
    required bool Function() hayCorridaEnVuelo,
    Duration piso = const Duration(seconds: 2),
  })  : _ejecutar = ejecutar,
        _enVuelo = hayCorridaEnVuelo,
        _piso = piso;

  /// Dispara el ciclo de la UI (en producción: cicloSyncUi.ejecutar(), que coalesce).
  final Future<void> Function() _ejecutar;

  /// ¿Ya hay una corrida de la UI en curso? (CicloSyncUi.enVuelo). Para no pedir una
  /// re-corrida redundante en cada tick del Timer.
  final bool Function() _enVuelo;

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
    if (_enVuelo()) {
      // Sin re-entrada (CTT-141): ya hay una corrida de la UI en curso (el guard). No se lanza
      // otra; se re-chequea en un piso. Cuando la corrida en vuelo termine moverá
      // sync_pendientes y el stream reprogramará con el MIN nuevo.
      _timer = Timer(_piso, _disparar);
      return;
    }
    _ejecutar();
    // No se reprograma acá: la corrida cambia sync_pendientes y el stream reemite el nuevo MIN,
    // que vuelve a programar el Timer (o emite null si la cola quedó sin filas no terminales).
  }

  void dispose() => desactivar();
}
