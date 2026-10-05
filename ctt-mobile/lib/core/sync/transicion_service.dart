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
import 'package:ctt_mobile/core/security/secure_storage_service.dart';
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
  ///   200                  → [TransicionAplicadaOnline]   (sin encolar)
  ///   error de red         → [TransicionEncoladaOffline]  (encola en Drift)
  ///   408/429/5xx (≠501)   → [TransicionEncoladaOffline]  (encola; Retry-After = 1er
  ///                                                        proximo_intento_en — C6)
  ///   409 sin id           → [TransicionRechazada]        (sin encolar, error de negocio)
  ///   409 con id           → [TransicionConConflicto]     (inserta en esperando_resolucion)
  ///   401/403/404/422/501  → propaga excepción            (sin encolar)
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

      // Error de red (sin conexión, timeout): encolar sin backoff ni código (falla de
      // red: ultimo_error_codigo queda NULL → liberarBackoffRed la soltará, L3).
      if (_esErrorDeRed(e)) {
        await _encolar(itemId, nuevoEstado, comentario, descripcionProblema, ahora,
            deviceId, idempotencyKey,);
        return const TransicionEncoladaOffline();
      }

      // C6: 408/429/5xx (salvo 501) son transitorios del servidor — encolar en vez de
      // propagar. Si viene Retry-After (429/503), ese es el primer proximo_intento_en
      // (piso del backoff del ciclo); se guarda el código para que NO se trate como red.
      final status = e.response?.statusCode;
      if (_esServidorReintentable(status)) {
        final retryAfter = extraerRetryAfter(e);
        await _encolar(
          itemId, nuevoEstado, comentario, descripcionProblema, ahora, deviceId,
          idempotencyKey,
          proximoIntentoEn: retryAfter != null ? ahora.add(retryAfter) : null,
          ultimoError: extraerDetalleBackend(e),
          ultimoErrorCodigo: status,
        );
        return const TransicionEncoladaOffline();
      }

      // 401/403/404/422/501: propagar — no encolar.
      rethrow;
    }
  }

  /// Status de servidor transitorio que el online encola en vez de propagar (C6):
  /// 408 (timeout), 429 (rate limit) y 5xx salvo 501 (no implementado).
  bool _esServidorReintentable(int? status) =>
      status == 408 ||
      status == 429 ||
      (status != null && status >= 500 && status != 501);

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
      // Conflicto de concurrencia: el DAO inserta la fila DIRECTO en
      // esperando_resolucion con su conflicto_id y enciende el flag de conflicto del
      // ítem, todo en UNA transacción (estado y motivo los dicta decidir()). No pasa
      // por 'pendiente': así el ciclo (que reclama filas 'pendiente') nunca la toma ni
      // la reenvía en esa ventana (carrera CTT-136); y no depende del lease. Lo
      // resuelve el reconciliador (CTT-117 tramo 3).
      final fila = await _prepararFila(
        itemId, nuevoEstado, comentario, descripcionProblema, ahora, deviceId,
        idempotencyKey,
      );
      await syncDao.encolarEnConflicto(fila.companion, conflictoId: conflictoId);
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
  /// Lee el dueño de SecureStorage y arma el companion BASE de la fila (estado
  /// 'pendiente' por defecto, sin conflicto_id) con un id nuevo. Si no hay sesión
  /// activa, lanza [SesionNoDisponibleException] y NO toca la cola. Fuente única de
  /// construcción de la fila: la usan el camino offline ([_encolar]) y el de conflicto
  /// (que la inserta vía syncDao.encolarEnConflicto).
  Future<({String id, SyncPendientesCompanion companion})> _prepararFila(
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
    final companion = SyncPendientesCompanion.insert(
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
    );
    return (id: id, companion: companion);
  }

  /// Encola el cambio en 'pendiente' y devuelve el id. Camino offline (red caída) y
  /// C6 (408/429/5xx). [proximoIntentoEn]/[ultimoError]/[ultimoErrorCodigo] son
  /// opcionales: el camino de red los deja en null (falla sin respuesta); el de C6
  /// pasa el código y, si hubo Retry-After, el primer proximo_intento_en.
  Future<String> _encolar(
    String itemId,
    String nuevoEstado,
    String? comentario,
    String? descripcionProblema,
    DateTime ahora,
    String deviceId,
    String idempotencyKey, {
    DateTime? proximoIntentoEn,
    String? ultimoError,
    int? ultimoErrorCodigo,
  }) async {
    final fila = await _prepararFila(
      itemId, nuevoEstado, comentario, descripcionProblema, ahora, deviceId,
      idempotencyKey,
    );
    final companion = fila.companion.copyWith(
      proximoIntentoEn:
          proximoIntentoEn != null ? Value(proximoIntentoEn) : const Value.absent(),
      ultimoError: ultimoError != null ? Value(ultimoError) : const Value.absent(),
      ultimoErrorCodigo: ultimoErrorCodigo != null
          ? Value(ultimoErrorCodigo)
          : const Value.absent(),
    );
    await syncDao.encolar(companion);
    return fila.id;
  }

  bool _esErrorDeRed(DioException e) =>
      e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.receiveTimeout ||
      e.type == DioExceptionType.sendTimeout ||
      e.type == DioExceptionType.connectionError;
}
