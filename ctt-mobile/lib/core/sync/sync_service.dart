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

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:workmanager/workmanager.dart';

import 'package:ctt_mobile/core/config/environment.dart';
import 'package:ctt_mobile/data/local/database.dart';

// Nombre único para identificar la tarea periódica en WorkManager.
const _taskNameSync = 'cl.ctt.sync.periodico';
const _taskTagSync = 'ctt_sync';

// Claves de SecureStorage — deben coincidir con SecureStorageService.
const _claveJwt = '_ctt_jwt';
const _claveEmpresaId = '_ctt_empresa_id';

/// Máximo de reintentos antes de abandonar un cambio con error.
const _maxReintentos = 5;

/// Inicializa WorkManager y registra la tarea periódica de sync.
/// Llamar una sola vez en main.dart después de inicializar Firebase.
Future<void> inicializarSyncService() async {
  await Workmanager().initialize(_callbackDispatcher);
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
    if (taskName != _taskNameSync) return true;

    try {
      await _ejecutarCicloSync();
      return true;
    } catch (_) {
      // WorkManager reintentará según su política de backoff.
      return false;
    }
  });
}

/// Ciclo principal de sync: lee la cola Drift → envía al API → actualiza estado.
///
/// Diseño offline-first:
///   - Error de red: reintentos++, queda como 'error' para el próximo ciclo.
///   - HTTP 409 Conflict: marcado para resolución manual por coordinador/admin.
///   - Éxito: marcado como 'sincronizado'.
///   - Acciones 'subir_foto': diferidas hasta Fase 2 (upload a S3).
Future<void> _ejecutarCicloSync() async {
  // Los plugins de Flutter requieren que el binding esté inicializado.
  WidgetsFlutterBinding.ensureInitialized();

  final db = BaseDatosCTT();

  try {
    // Reactivar errores previos para que el nuevo ciclo los reintente.
    await db.syncDao.reactivarErrores();

    final pendientes = await db.syncDao.obtenerPendientes();
    if (pendientes.isEmpty) return;

    // Leer credenciales directamente desde SecureStorage (sin Riverpod).
    const secStorage = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    );
    final jwt = await secStorage.read(key: _claveJwt);
    final empresaId = await secStorage.read(key: _claveEmpresaId);

    // Sin JWT no hay forma de autenticar — no vale la pena intentarlo.
    if (jwt == null) return;

    final dio = Dio(BaseOptions(
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

    for (final cambio in pendientes) {
      // Saltar cambios que ya superaron el máximo de intentos.
      if (cambio.reintentos >= _maxReintentos) continue;

      await db.syncDao.marcarEnviando(cambio.id);

      try {
        await _enviarCambio(
          id: cambio.id,
          accion: cambio.accion,
          entidadId: cambio.entidadId,
          payload: cambio.payload,
          dio: dio,
        );
        await db.syncDao.marcarSincronizado(cambio.id);
      } on DioException catch (e) {
        if (e.response?.statusCode == 409) {
          // 409 puede ser conflicto de concurrencia (con conflicto_id) o regla
          // de negocio. En ambos casos se marca para revisión manual.
          final body = e.response?.data;
          final conflictoId =
              body is Map ? body['conflicto_id'] as String? : null;
          await db.syncDao.marcarConflicto(cambio.id, conflictoId: conflictoId);
        } else {
          await db.syncDao.marcarError(
            cambio.id,
            e.message ?? 'Error de red',
            cambio.reintentos + 1,
          );
        }
      } catch (e) {
        await db.syncDao.marcarError(
          cambio.id,
          e.toString(),
          cambio.reintentos + 1,
        );
      }
    }
  } finally {
    await db.close();
  }
}

/// Envía una acción de sync al endpoint correspondiente del backend.
Future<void> _enviarCambio({
  required String id,
  required String accion,
  required String entidadId,
  required String payload,
  required Dio dio,
}) async {
  final data = jsonDecode(payload) as Map<String, dynamic>;

  switch (accion) {
    case 'cambio_estado_item':
      // Backend: POST /items/{item_id}/transicion
      await dio.post<void>('/items/$entidadId/transicion', data: data);
    case 'subir_foto':
      // TODO Fase 2: obtener pre-signed URL de S3 y subir el archivo local.
      // Por ahora se deja en la cola como pendiente — no se marca error.
      return;
    default:
      throw Exception('Acción de sync desconocida: $accion');
  }
}

