/// guarda_reconciliacion.dart — Entrada ÚNICA a la reconciliación de conflictos del isolate UI.
///
/// Igual que [CicloSyncUi] es la entrada única al ciclo de sync, esto es la entrada única a la
/// reconciliación: serializa con [GuardaCorridaUnica] para que los múltiples disparadores
/// (arranque, resume, conectividad, timer del coordinador, bypass del ciclo) NUNCA lancen GET
/// /sync/conflictos/mios concurrentes (hallazgo R4/R5: dos disparadores pasaban el debounce
/// porque la marca se escribía DESPUÉS del GET).
///
///   • reconciliarSiCorresponde() : con debounce; si hay una reconciliación EN VUELO se SUMA a
///                                  ella (join) y no lanza otro GET.
///   • reconciliarAhora()         : bypass RUN-AFTER (tras un 200 que supera un conflicto): una
///                                  consulta que EMPIEZA DESPUÉS de la llamada; si hay una en
///                                  vuelo, agenda una (única) re-corrida. Motivo: un GET que
///                                  salió antes de que el servidor marque el conflicto como
///                                  superado trae datos viejos (el aviso de R3 quedaría 2 min).
///
/// Vive en un provider keepAlive porque el estado en vuelo es un Completer en memoria y tiene que
/// compartirse entre todos los disparadores; re-lee el reconciliador (autoDispose) en cada corrida
/// para no quedarse con un Dio/DAO viejo tras un cambio de sesión (mismo motivo que CicloSyncUi).
///
/// El headless (sync_service / ciclo con instancia fresca) NO pasa por acá: tiene su propio
/// reconciliador y la idempotencia ENTRE isolates la da `aplicarDecision` condicional (SyncDao:
/// UPDATE ... WHERE estado = esperando_resolucion; una segunda aplicación es no-op).
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:ctt_mobile/core/sync/guarda_corrida_unica.dart';
import 'package:ctt_mobile/core/sync/reconciliador_conflictos.dart';
import 'package:ctt_mobile/data/local/daos/sync_dao.dart';

part 'guarda_reconciliacion.g.dart';

DateTime _ahoraUtcPorDefecto() => DateTime.now().toUtc();

/// Guard de reconciliación: single-flight + coalescing (vía [GuardaCorridaUnica]) con debounce.
/// Lógica pura (recibe las operaciones por constructor) para testearse sin Riverpod ni Dio.
class GuardaReconciliacion {
  GuardaReconciliacion({
    required Future<bool> Function() reconciliar,
    required Future<DateTime?> Function() ultimaReconciliacion,
    required Future<void> Function(DateTime) registrarReconciliacion,
    DateTime Function()? reloj,
    Duration ventanaDebounce = ReconciliadorConflictos.ventanaDebounce,
  })  : _reconciliar = reconciliar,
        _ultimaReconciliacion = ultimaReconciliacion,
        _registrar = registrarReconciliacion,
        _reloj = reloj ?? _ahoraUtcPorDefecto,
        _ventana = ventanaDebounce;

  final Future<bool> Function() _reconciliar;
  final Future<DateTime?> Function() _ultimaReconciliacion;
  final Future<void> Function(DateTime) _registrar;
  final DateTime Function() _reloj;
  final Duration _ventana;

  late final GuardaCorridaUnica _guarda = GuardaCorridaUnica(_correrYRegistrar);

  /// ¿Hay una reconciliación en vuelo? (tests/diagnóstico).
  bool get enVuelo => _guarda.enVuelo;

  // DUPE: el debounce (ventana) + "registrar si consultó" también viven en
  // ReconciliadorConflictos.reconciliarSiCorresponde (reconciliador_conflictos.dart), que usa el
  // headless con instancia fresca y SIN este guard. El valor de la ventana es único
  // (ReconciliadorConflictos.ventanaDebounce). Consolidar exigiría un solo op en GuardaCorridaUnica,
  // pero hay dos semánticas (con debounce = reconciliarSiCorresponde; sin debounce = reconciliarAhora),
  // así que se duplican ~3 líneas a propósito. A diferencia del reconciliador, acá el bypass
  // (reconciliarAhora) SÍ registra la ventana: una reconciliación efectiva debe avanzar el reloj
  // compartido para que el próximo disparador con debounce no vuelva a consultar enseguida.
  Future<void> _correrYRegistrar() async {
    final consulto = await _reconciliar();
    if (consulto) await _registrar(_reloj());
  }

  /// Con debounce + join-in-flight. Si hay una reconciliación en vuelo, se suma a ella (sin lanzar
  /// otro GET); si no, aplica el debounce (no consulta si no pasó la ventana desde la última).
  Future<void> reconciliarSiCorresponde() async {
    if (_guarda.enVuelo) return _guarda.unirseOIniciar();
    final ultima = await _ultimaReconciliacion();
    if (ultima != null && _reloj().difference(ultima) < _ventana) return;
    return _guarda.unirseOIniciar();
  }

  /// Bypass run-after (ver encabezado): una consulta que EMPIEZA DESPUÉS de esta llamada.
  Future<void> reconciliarAhora() => _guarda.ejecutar();
}

/// Provider keepAlive: el estado del guard es estable toda la sesión. Cada operación re-lee su
/// provider (autoDispose) para usar el Dio/DAO fresco (igual que cicloSyncUi con cicloSync).
@Riverpod(keepAlive: true)
GuardaReconciliacion guardaReconciliacion(GuardaReconciliacionRef ref) =>
    GuardaReconciliacion(
      reconciliar: () => ref.read(reconciliadorConflictosProvider).reconciliar(),
      ultimaReconciliacion: () => ref.read(syncDaoProvider).ultimaReconciliacion(),
      registrarReconciliacion: (t) =>
          ref.read(syncDaoProvider).registrarReconciliacion(t),
    );
