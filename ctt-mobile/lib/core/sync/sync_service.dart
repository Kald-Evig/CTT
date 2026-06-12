/// sync_service.dart — Servicio de sincronización offline-first.
///
/// Usa WorkManager para ejecución periódica en background.
/// NUNCA foreground service para sync — solo WorkManager (restricción de diseño).
///
/// Flujo:
///   1. WorkManager despierta la tarea (mínimo 15 min, restricción Android).
///   2. Leer cola pendiente de Drift en orden FIFO (timestamp ascendente).
///   3. Enviar cada cambio al API.
///   4. Marcar como sincronizado o aplicar backoff exponencial en error.
///   5. Detectar conflictos (HTTP 409 del backend) y marcarlos para resolución.
library;

import 'dart:math';
import 'package:workmanager/workmanager.dart';

// Nombre único para identificar la tarea periódica en WorkManager.
const _taskNameSync = 'cl.ctt.sync.periodico';
const _taskTagSync = 'ctt_sync';

/// Máximo de reintentos antes de abandonar un cambio con error.
const _maxReintentos = 5;

/// Inicializa WorkManager y registra la tarea periódica de sync.
/// Llamar una sola vez en main.dart después de inicializar Firebase.
Future<void> inicializarSyncService() async {
  await Workmanager().initialize(
    _callbackDispatcher,
    // isInDebugMode muestra notificaciones de WorkManager en Android —
    // útil durante desarrollo, desactivar en release.
    isInDebugMode: false,
  );

  await _registrarTareaSync();
}

/// Registra (o re-registra) la tarea periódica con las constraints correctas.
Future<void> _registrarTareaSync() async {
  await Workmanager().registerPeriodicTask(
    _taskNameSync,
    _taskNameSync,
    tag: _taskTagSync,
    // Mínimo 15 minutos — restricción de WorkManager en Android.
    frequency: const Duration(minutes: 15),
    constraints: Constraints(
      networkType: NetworkType.connected,
      requiresBatteryNotLow: true,
    ),
    // ExistingWorkPolicy.keep: si ya existe una tarea registrada, no duplicar.
    existingWorkPolicy: ExistingWorkPolicy.keep,
  );
}

/// Cancela todos los jobs de sync — llamar siempre al hacer logout.
Future<void> cancelarSyncAlLogout() async {
  await Workmanager().cancelByTag(_taskTagSync);
}

/// Callback que ejecuta WorkManager en background (proceso aislado).
/// @pragma necesario para que el tree-shaker de Flutter no elimine esta función.
@pragma('vm:entry-point')
void _callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName != _taskNameSync) return Future.value(true);

    try {
      await _ejecutarCicloSync();
      return true;
    } catch (e) {
      // WorkManager reintentará según su política de backoff.
      return false;
    }
  });
}

/// Ciclo principal de sync: lee la cola Drift → envía al API → actualiza estado.
/// TODO Fase 1.3: inyectar dependencias reales (DAO, DioClient) cuando estén listos.
Future<void> _ejecutarCicloSync() async {
  // TODO Fase 1.3: implementar ciclo completo:
  //   1. final pendientes = await syncDao.obtenerPendientesOrdenados();
  //   2. for (final cambio in pendientes) {
  //        if (cambio.reintentos >= _maxReintentos) continue;
  //        final espera = _backoffExponencial(cambio.reintentos);
  //        await Future<void>.delayed(espera);
  //        await _enviarCambio(cambio);
  //      }
}

/// Calcula espera de backoff exponencial con jitter para evitar thundering herd.
// ignore: unused_element
Duration _backoffExponencial(int reintentos) {
  // Acotar reintentos al máximo para evitar esperas astronómicas.
  final intentos = reintentos.clamp(0, _maxReintentos);
  final base = Duration(seconds: 10 * pow(2, intentos).toInt());
  final jitter = Duration(milliseconds: Random().nextInt(1000));
  // Máximo 10 minutos para no bloquear sync demasiado tiempo.
  return base + jitter > const Duration(minutes: 10)
      ? const Duration(minutes: 10)
      : base + jitter;
}
