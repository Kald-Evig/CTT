/// transicion_service.dart — Servicio compartido de transiciones de estado (online-first).
///
/// Único lugar donde vive la decisión online/offline para transiciones de ítems.
/// Intenta la red primero (timeout 4s); si falla por error de red, encola en Drift.
/// Usado por ItemsRepository (Trabajador) y ResidenteRepository (Residente).
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import 'package:ctt_mobile/core/device/device_id_service.dart';
import 'package:ctt_mobile/core/network/dio_client.dart';
import 'package:ctt_mobile/core/network/extraer_detalle_backend.dart';
import 'package:ctt_mobile/core/sync/resultado_transicion.dart';
import 'package:ctt_mobile/data/local/daos/sync_dao.dart';
import 'package:ctt_mobile/data/local/database.dart';
import 'package:ctt_mobile/domain/enums/enums_ctt.dart';

part 'transicion_service.g.dart';

/// Timeout para el intento online. Si el servidor no responde, se encola offline.
const _kTimeoutTransicion = Duration(seconds: 4);

@riverpod
TransicionService transicionService(TransicionServiceRef ref) => TransicionService(
      dio: ref.watch(dioClientProvider),
      syncDao: ref.watch(syncDaoProvider),
      deviceIdService: ref.watch(deviceIdServiceProvider),
    );

class TransicionService {
  const TransicionService({
    required this.dio,
    required this.syncDao,
    required this.deviceIdService,
  });

  final Dio dio;
  final SyncDao syncDao;
  final DeviceIdService deviceIdService;

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
    final body = e.response?.data;
    final conflictoId = extraerConflictoId(e);

    if (conflictoId != null) {
      // Conflicto de concurrencia: encolar con estado conflicto para resolución manual.
      final entradaId = await _encolar(
        itemId, nuevoEstado, comentario, descripcionProblema, ahora, deviceId,
        idempotencyKey,
      );
      await syncDao.marcarConflicto(entradaId, conflictoId: conflictoId);
      return TransicionConConflicto(conflictoId);
    }

    // Rechazo de negocio (transición inválida, estado ya avanzó, etc.).
    return TransicionRechazada(_extraerDetail(body));
  }

  /// Encola el cambio en Drift y devuelve el id de la entrada creada.
  Future<String> _encolar(
    String itemId,
    String nuevoEstado,
    String? comentario,
    String? descripcionProblema,
    DateTime ahora,
    String deviceId,
    String idempotencyKey,
  ) async {
    final id = const Uuid().v4();
    await syncDao.encolar(SyncPendientesTableCompanion.insert(
      id: id,
      tipoEntidad: TipoEntidad.item.valor,
      entidadId: itemId,
      accion: AccionSync.cambioEstadoItem.valor,
      payload: jsonEncode({
        'nuevo_estado': nuevoEstado,
        if (comentario != null) 'comentario': comentario,
        if (descripcionProblema != null) 'descripcion_problema': descripcionProblema,
        'device_timestamp': ahora.toIso8601String(),
        'dispositivo_id': deviceId,
      }),
      timestampDispositivo: ahora,
      dispositivoId: deviceId,
      idempotencyKey: Value(idempotencyKey),
    ),);
    return id;
  }

  bool _esErrorDeRed(DioException e) =>
      e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.receiveTimeout ||
      e.type == DioExceptionType.sendTimeout ||
      e.type == DioExceptionType.connectionError;

  String _extraerDetail(dynamic body) {
    if (body is Map<String, dynamic>) {
      final detail = body['detail'];
      if (detail is String) return detail;
      if (detail is Map<String, dynamic>) {
        final msg = detail['mensaje'];
        if (msg is String) return msg;
      }
    }
    return 'Transición rechazada por el servidor.';
  }
}
