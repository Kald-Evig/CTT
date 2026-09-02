/// ciclo_sync.dart — Lógica del ciclo de sincronización con dependencias inyectadas.
///
/// [CicloSync] recibe [SyncDao] y [Dio] por constructor y no instancia nada.
/// Permite que el mismo ciclo sea ejecutado desde dos caminos distintos:
///   - WorkManager (headless): SyncDao y Dio creados por sync_service.dart.
///   - Foreground (app viva): SyncDao y Dio del ProviderScope vía [cicloSyncProvider].
///
/// La CLASIFICACIÓN de la respuesta (qué señal de dominio ocurrió) es el único
/// lugar que toca Dio; la DECISIÓN de a qué estado va la entrada la toma la
/// función pura [decidir], y el EFECTO lo aplica el DAO. Ese corte es lo que
/// mantiene la lógica de estados testeable sin red.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:ctt_mobile/core/network/dio_client.dart';
import 'package:ctt_mobile/core/network/extraer_detalle_backend.dart';
import 'package:ctt_mobile/core/sync/decision_sync.dart';
import 'package:ctt_mobile/data/local/daos/sync_dao.dart';
import 'package:ctt_mobile/domain/enums/enums_ctt.dart';

part 'ciclo_sync.g.dart';

/// Provider que usa las instancias del ProviderScope (foreground).
/// El ConectividadListener lo lee para el flush inmediato al reconectar.
@riverpod
CicloSync cicloSync(CicloSyncRef ref) => CicloSync(
      syncDao: ref.watch(syncDaoProvider),
      dio: ref.watch(dioClientProvider),
    );

/// Ciclo de sincronización reutilizable.
/// No crea instancias propias — el caller provee [SyncDao] y [Dio].
class CicloSync {
  const CicloSync({required this.syncDao, required this.dio});

  final SyncDao syncDao;
  final Dio dio;

  /// Lee la cola, envía cada cambio al API y actualiza el estado en Drift.
  /// Retorno temprano si no hay pendientes — seguro de llamar sin costo.
  Future<void> ejecutar() async {
    final pendientes = await syncDao.obtenerPendientes();
    if (pendientes.isEmpty) return;

    for (final cambio in pendientes) {
      // "Claim" atómico: si otro ciclo ya tomó esta entrada, retorna false → saltar.
      final tomado = await syncDao.marcarEnviando(cambio.id);
      if (!tomado) continue;

      SenalSync senal;
      String? conflictoId;
      try {
        await _enviarCambio(
          accion: cambio.accion,
          entidadId: cambio.entidadId,
          payload: cambio.payload,
          idempotencyKey: cambio.idempotencyKey,
        );
        senal = SenalSync.envioOk;
      } catch (e) {
        // ÚNICO punto que conoce Dio: traduce la excepción de transporte a una
        // señal de dominio. De acá para abajo no hay HTTP.
        final clasificado = _clasificar(e);
        senal = clasificado.$1;
        conflictoId = clasificado.$2;
      }

      final decision = decidir(
        estadoActual: EstadoSyncLocal.enviando,
        senal: senal,
        reintentos: cambio.reintentos,
      );
      await syncDao.aplicarDecision(
        cambio.id,
        estadoEsperado: EstadoSyncLocal.enviando,
        decision: decision,
        reintentosActuales: cambio.reintentos,
        conflictoId: conflictoId,
      );
    }
  }

  /// Traduce una excepción de envío a una [SenalSync] de dominio y, si es un
  /// conflicto, su conflicto_id. Es el único método acoplado a Dio.
  (SenalSync, String?) _clasificar(Object error) {
    if (error is DioException) {
      final status = error.response?.statusCode;
      if (status == 409) {
        final id = extraerConflictoId(error);
        // 409 con id = conflicto de concurrencia; 409 sin id = rechazo de
        // negocio (transición inválida, estado ya avanzó). Distinguirlos es lo
        // que corrige el defecto de CTT-115.
        return id != null
            ? (SenalSync.conflictoDetectado, id)
            : (SenalSync.rechazoDefinitivo, null);
      }
      if (status == 403 || status == 404 || status == 422) {
        // Rechazo permanente: no se arregla reintentando el mismo payload.
        return (SenalSync.rechazoDefinitivo, null);
      }
      // Transitorio: red, timeout, 5xx.
      return (SenalSync.fallaTransitoria, null);
    }
    // Excepción no-Dio (p.ej. el stub UnimplementedError de subir_foto): tratar
    // como transitoria — agotará reintentos y terminará en descartado, sin limbo.
    return (SenalSync.fallaTransitoria, null);
  }

  Future<void> _enviarCambio({
    required String accion,
    required String entidadId,
    required String payload,
    String? idempotencyKey,
  }) async {
    final data = jsonDecode(payload) as Map<String, dynamic>;

    switch (accion) {
      case 'cambio_estado_item':
        // La clave (null en filas encoladas antes de la migración v3) va como
        // header, NO en el payload: el payload alimenta el fingerprint del
        // servidor y meterla ahí rompería la deduplicación (CTT-105).
        await dio.post<void>(
          '/items/$entidadId/transicion',
          data: data,
          options: idempotencyKey != null
              ? Options(headers: {'Idempotency-Key': idempotencyKey})
              : null,
        );
      case 'subir_foto':
        // Stub deliberado: la captura y subida de evidencia no existe todavía
        // (CTT-99). El throw es intencional para NO caer en el camino de éxito
        // sin una respuesta 2xx del servidor: se clasifica como falla
        // transitoria y, al agotar reintentos, la entrada termina en descartado.
        // Se reemplaza por la lógica de subida real (pre-signed URL de S3 +
        // upload del archivo local), NO por otro parche.
        throw UnimplementedError(
          'subir_foto: la captura y subida de evidencia no está implementada (CTT-99). '
          'La entrada NO se marca como sincronizada.',
        );
      default:
        throw Exception('Acción de sync desconocida: $accion');
    }
  }
}
