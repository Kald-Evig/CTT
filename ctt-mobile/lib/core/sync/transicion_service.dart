/// transicion_service.dart — Encola la transición y dispara el ciclo (CTT-148).
///
/// "Lazy writes" (encolar primero): TODA transición se ENCOLA en `sync_pendientes`
/// dentro de una escritura, y el envío al servidor lo hace SIEMPRE el ciclo
/// (`ciclo_sync`) — único camino, que maneja 409, rechazos, idempotencia y
/// version_base/rebase (CTT-143). Tras encolar, dispara el ciclo en el isolate de la UI
/// y espera ~4 s el resultado del PRIMER intento de ESA fila (ver
/// [SyncDao.esperarResultadoFila]). Usado por ItemsRepository (Trabajador) y
/// ResidenteRepository (Residente).
library;

import 'dart:async';
import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import 'package:ctt_mobile/core/device/device_id_service.dart';
import 'package:ctt_mobile/core/network/dio_client.dart' show secureStorageProvider;
import 'package:ctt_mobile/core/security/secure_storage_service.dart';
import 'package:ctt_mobile/core/sync/ciclo_sync.dart';
import 'package:ctt_mobile/data/local/daos/sync_dao.dart';
import 'package:ctt_mobile/data/local/database.dart';
import 'package:ctt_mobile/domain/enums/enums_ctt.dart';

part 'transicion_service.g.dart';

/// Reloj por defecto (UTC). Top-level para poder ser default const del constructor.
DateTime _ahoraUtcTransicion() => DateTime.now().toUtc();

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
      syncDao: ref.watch(syncDaoProvider),
      deviceIdService: ref.watch(deviceIdServiceProvider),
      secureStorage: ref.watch(secureStorageProvider),
      // Único camino al servidor: el ciclo foreground (mismo dioSync con X-Sync-Origen).
      dispararCiclo: () => ref.read(cicloSyncProvider).ejecutar(),
    );

class TransicionService {
  const TransicionService({
    required this.syncDao,
    required this.deviceIdService,
    required this.secureStorage,
    required this.dispararCiclo,
    this.reloj = _ahoraUtcTransicion,
    this.timeoutEspera = const Duration(seconds: 4),
  });

  final SyncDao syncDao;
  final DeviceIdService deviceIdService;
  final SecureStorageService secureStorage;

  /// Dispara el ciclo de envío (único camino al servidor). En foreground:
  /// `cicloSyncProvider.ejecutar()`.
  final Future<void> Function() dispararCiclo;

  /// Reloj inyectable (UTC). Default: reloj del sistema.
  final DateTime Function() reloj;

  /// Cuánto espera la UI el primer intento de la fila antes de devolver `pendiente`.
  final Duration timeoutEspera;

  /// Encola la transición y dispara el envío. Devuelve el resultado del PRIMER intento
  /// de la fila (terminal / esperando_resolucion, o `pendiente` si no se intentó a
  /// tiempo). Lanza [SesionNoDisponibleException] si no hay sesión (no encola).
  Future<ResultadoEspera> ejecutar({
    required String itemId,
    required String nuevoEstado,
    String? comentario,
    String? descripcionProblema,
  }) async {
    final deviceId = await deviceIdService.obtener();
    final ahora = reloj();
    final idempotencyKey = const Uuid().v4();
    final fila = await _prepararFila(
      itemId, nuevoEstado, comentario, descripcionProblema, ahora, deviceId,
      idempotencyKey,
    );
    // Encolar primero (lazy writes): la intención queda en la cola ANTES de enviar.
    await syncDao.encolar(fila.companion);
    // Disparar el ciclo en la UI. Fire-and-forget: la fila ya está encolada, así que si
    // el disparo falla o ya hay un ciclo corriendo, el lease (CTT-127) + el FIFO la
    // envían en esa corrida o una encadenada; los disparadores de reconexión / periódico
    // la reintentan (CTT-141).
    unawaited(dispararCiclo().catchError((_) {}));
    // Esperar el resultado del primer intento de ESTA fila.
    return syncDao.esperarResultadoFila(fila.id, timeout: timeoutEspera);
  }

  /// Arma el companion BASE de la fila (estado 'pendiente' por defecto) con un id nuevo.
  /// Completa TODOS los campos NOT NULL de v6: dueño (`usuario_id`/`empresa_id` desde
  /// SecureStorage), `instalacion_id` (DeviceIdService), `idempotency_key`,
  /// `payload_version` = 1 y `creado_en_dispositivo`. Si no hay sesión activa, lanza
  /// [SesionNoDisponibleException] y NO toca la cola (nunca una fila sin dueño).
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
        kPayloadNuevoEstado: nuevoEstado,
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
}
