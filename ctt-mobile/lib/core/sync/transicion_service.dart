/// transicion_service.dart — Servicio compartido de transiciones de estado (online-first).
///
/// Único lugar donde vive la decisión online/offline para transiciones de ítems.
/// Intenta la red primero (timeout 4s); si falla por error de red, encola en Drift.
/// Usado por ItemsRepository (Trabajador) y ResidenteRepository (Residente).
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import 'package:ctt_mobile/core/device/device_id_service.dart';
import 'package:ctt_mobile/core/network/dio_client.dart';
import 'package:ctt_mobile/core/network/extraer_detalle_backend.dart';
import 'package:ctt_mobile/core/security/secure_storage_service.dart';
import 'package:ctt_mobile/core/sync/decision_sync.dart';
import 'package:ctt_mobile/core/sync/resultado_transicion.dart';
import 'package:ctt_mobile/data/local/daos/sync_dao.dart';
import 'package:ctt_mobile/data/local/database.dart';
import 'package:ctt_mobile/domain/enums/enums_ctt.dart';

part 'transicion_service.g.dart';

/// Timeout para el intento online. Si el servidor no responde, se encola offline.
const _kTimeoutTransicion = Duration(seconds: 4);

/// Se lanza cuando se intenta encolar un cambio sin sesión activa (sin usuario_id
/// o empresa_id en SecureStorage). En v6 esas columnas son NOT NULL: una fila de
/// la cola no puede existir sin dueño. NO se encola y la UI debe mostrar el fallo
/// — nunca se traga un error al capturar trabajo (CTT-130).
class SesionNoDisponibleException implements Exception {
  const SesionNoDisponibleException(this.mensaje);
  final String mensaje;
  @override
  String toString() => 'SesionNoDisponibleException: $mensaje';
}

@riverpod
TransicionService transicionService(TransicionServiceRef ref) => TransicionService(
      dio: ref.watch(dioClientProvider),
      syncDao: ref.watch(syncDaoProvider),
      deviceIdService: ref.watch(deviceIdServiceProvider),
      secureStorage: ref.watch(secureStorageProvider),
    );

class TransicionService {
  const TransicionService({
    required this.dio,
    required this.syncDao,
    required this.deviceIdService,
    required this.secureStorage,
  });

  final Dio dio;
  final SyncDao syncDao;
  final DeviceIdService deviceIdService;
  final SecureStorageService secureStorage;

  /// Ejecuta una transición de estado online-first con fallback a cola offline.
  ///
  /// Flujo de decisión:
  ///   200            → [TransicionAplicadaOnline]   (sin encolar)
  ///   error de red   → [TransicionEncoladaOffline]  (encola en Drift)
  ///   409 sin id     → [TransicionRechazada]         (sin encolar, error de negocio)
  ///   409 con id     → [TransicionConConflicto]      (encola con estado conflicto)
  ///   4xx/5xx resto  → propaga excepción             (sin encolar)
  Future<ResultadoTransicion> ejecutar({
    required String itemId,
    required String nuevoEstado,
    String? comentario,
    String? descripcionProblema,
  }) async {
    final deviceId = await deviceIdService.obtener();
    final ahora = DateTime.now().toUtc();
    // Una sola clave por invocación de ejecutar(): la comparten el POST online y
    // el encolado, para que el backend deduplique si la respuesta online se pierde
    // y el cambio se reintenta después desde la cola (CTT-105).
    final idempotencyKey = const Uuid().v4();

    try {
      final resp = await dio.post<Map<String, dynamic>>(
        '/items/$itemId/transicion',
        data: {
          'nuevo_estado': nuevoEstado,
          if (comentario != null) 'comentario': comentario,
          if (descripcionProblema != null)
            'descripcion_problema': descripcionProblema,
          'device_timestamp': ahora.toIso8601String(),
          'dispositivo_id': deviceId,
        },
        options: Options(
          sendTimeout: _kTimeoutTransicion,
          receiveTimeout: _kTimeoutTransicion,
          headers: {'Idempotency-Key': idempotencyKey},
        ),
      );
      return TransicionAplicadaOnline(resp.data!);
    } on DioException catch (e) {
      // 409 con o sin conflicto_id — distinguir tipo.
      if (e.response?.statusCode == 409) {
        return _manejar409(
          e, itemId, nuevoEstado, comentario, descripcionProblema, ahora, deviceId,
          idempotencyKey,
        );
      }

      // Error de red (sin conexión, timeout): encolar para sincronizar después.
      if (_esErrorDeRed(e)) {
        await _encolar(itemId, nuevoEstado, comentario, descripcionProblema, ahora,
            deviceId, idempotencyKey,);
        return const TransicionEncoladaOffline();
      }

      // Otros errores HTTP (401, 403, 422, 5xx): propagar — no encolar.
      rethrow;
    }
  }

  Future<ResultadoTransicion> _manejar409(
    DioException e,
    String itemId,
    String nuevoEstado,
    String? comentario,
    String? descripcionProblema,
    DateTime ahora,
    String deviceId,
    String idempotencyKey,
  ) async {
    final conflictoId = extraerConflictoId(e);

    if (conflictoId != null) {
      // Conflicto de concurrencia: encolar y parquear en esperando_resolucion
      // (no se re-envía; lo resuelve el reconciliador del tramo 3). La entrada
      // nace en 'pendiente'; la decisión pura la mueve al estado de parqueo.
      final entradaId = await _encolar(
        itemId, nuevoEstado, comentario, descripcionProblema, ahora, deviceId,
        idempotencyKey,
      );
      final decision = decidir(
        estadoActual: EstadoSyncLocal.pendiente,
        senal: SenalSync.conflictoDetectado,
        reintentos: 0,
      );
      await syncDao.aplicarDecision(
        entradaId,
        estadoEsperado: EstadoSyncLocal.pendiente,
        decision: decision,
        reintentosActuales: 0,
        conflictoId: conflictoId,
      );
      return TransicionConConflicto(conflictoId);
    }

    // Rechazo de negocio (transición inválida, estado ya avanzó, etc.).
    return TransicionRechazada(extraerDetalleBackend(e));
  }

  /// Encola el cambio en Drift y devuelve el id de la entrada creada.
  ///
  /// Completa TODOS los campos NOT NULL de v6: dueño (`usuario_id`/`empresa_id`
  /// desde SecureStorage), `instalacion_id` (DeviceIdService), `idempotency_key`,
  /// `payload_version` = 1 y `creado_en_dispositivo`. Si no hay sesión activa,
  /// lanza [SesionNoDisponibleException] y NO encola (nunca una fila sin dueño).
  Future<String> _encolar(
    String itemId,
    String nuevoEstado,
    String? comentario,
    String? descripcionProblema,
    DateTime ahora,
    String deviceId,
    String idempotencyKey,
  ) async {
    final usuarioId = await secureStorage.obtenerUsuarioId();
    final empresaId = await secureStorage.obtenerEmpresaId();
    if (usuarioId == null || empresaId == null) {
      throw const SesionNoDisponibleException(
        'No hay sesión activa (usuario_id/empresa_id nulos) al encolar el cambio.',
      );
    }

    final id = const Uuid().v4();
    await syncDao.encolar(SyncPendientesCompanion.insert(
      id: id,
      idempotencyKey: idempotencyKey,
      empresaId: empresaId,
      usuarioId: usuarioId,
      instalacionId: deviceId,
      tipoEntidad: TipoEntidad.item.valor,
      entidadId: itemId,
      accion: AccionSync.cambioEstadoItem.valor,
      payload: jsonEncode({
        'nuevo_estado': nuevoEstado,
        if (comentario != null) 'comentario': comentario,
        if (descripcionProblema != null) 'descripcion_problema': descripcionProblema,
        'device_timestamp': ahora.toIso8601String(),
        // El contrato con el servidor sigue usando 'dispositivo_id'; cambiarlo es
        // CTT-131. Acá solo se renombró la COLUMNA local a instalacion_id.
        'dispositivo_id': deviceId,
      }),
      payloadVersion: 1,
      creadoEnDispositivo: ahora,
    ),);
    return id;
  }

  bool _esErrorDeRed(DioException e) =>
      e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.receiveTimeout ||
      e.type == DioExceptionType.sendTimeout ||
      e.type == DioExceptionType.connectionError;
}
