/// sync_service.dart — Servicio de sincronización offline-first.
///
/// Usa WorkManager para ejecución periódica en background.
/// NUNCA foreground service para sync — solo WorkManager (restricción de diseño).
///
/// Flujo:
///   1. WorkManager despierta la tarea (mínimo 15 min, restricción Android).
///   2. Leer cola pendiente de Drift en orden FIFO (timestamp ascendente).
///   3. Enviar cada cambio al API (POST /items/{id}/transicion).
///   4. Marcar como sincronizado o en error (con reintentos).
///   5. Detectar conflictos (HTTP 409) y marcarlos para resolución manual.
library;

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:workmanager/workmanager.dart';

import 'package:ctt_mobile/core/config/environment.dart';
import 'package:ctt_mobile/core/sync/ciclo_sync.dart';
import 'package:ctt_mobile/data/local/database.dart';

// Identificadores de tareas WorkManager (públicos para el listener de conectividad).
const kTaskNameSync = 'cl.ctt.sync.periodico';
const kTaskFlushName = 'cl.ctt.sync.flush';
const _taskTagSync = 'ctt_sync';

// Claves de SecureStorage — deben coincidir con SecureStorageService.
const _claveJwt = '_ctt_jwt';
const _claveEmpresaId = '_ctt_empresa_id';

/// Inicializa WorkManager y registra la tarea periódica de sync.
/// Llamar una sola vez en main.dart después de inicializar Firebase.
Future<void> inicializarSyncService() async {
  await Workmanager().initialize(_callbackDispatcher);
  await _registrarTareaSync();
}

/// Registra (o re-registra) la tarea periódica con las constraints correctas.
Future<void> _registrarTareaSync() async {
  await Workmanager().registerPeriodicTask(
    kTaskNameSync,
    kTaskNameSync,
    tag: _taskTagSync,
    // Mínimo 15 minutos — restricción de WorkManager en Android.
    frequency: const Duration(minutes: 15),
    constraints: Constraints(
      networkType: NetworkType.connected,
      requiresBatteryNotLow: true,
    ),
    // ExistingPeriodicWorkPolicy.keep: si ya existe una tarea, no duplicar.
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
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
    if (taskName != kTaskNameSync) return true;

    try {
      await _ejecutarCicloSync();
      return true;
    } catch (_) {
      // WorkManager reintentará según su política de backoff.
      return false;
    }
  });
}

/// Ciclo principal de sync para el contexto headless de WorkManager.
///
/// Crea sus propias instancias de BD y Dio (sin Riverpod), lee credenciales
/// de SecureStorage, y delega la lógica del ciclo a [CicloSync].
Future<void> _ejecutarCicloSync() async {
  WidgetsFlutterBinding.ensureInitialized();

  final db = BaseDatosCTT();

  try {
    // Reactivar errores e ignorar si la cola está vacía antes de leer credenciales.
    await db.syncDao.reactivarErrores();
    if ((await db.syncDao.obtenerPendientes()).isEmpty) return;

    // Leer credenciales directamente desde SecureStorage (sin Riverpod).
    const secStorage = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    );
    final jwt = await secStorage.read(key: _claveJwt);
    if (jwt == null) return;
    final empresaId = await secStorage.read(key: _claveEmpresaId);

    final dioHeadless = Dio(BaseOptions(
      baseUrl: Entorno.urlBaseApi,
      connectTimeout: Entorno.timeoutConexion,
      receiveTimeout: Entorno.timeoutRecepcion,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer $jwt',
        if (empresaId != null) 'X-Empresa-Id': empresaId,
      },
    ),);

    await CicloSync(syncDao: db.syncDao, dio: dioHeadless).ejecutar();
  } finally {
    await db.close();
  }
}

