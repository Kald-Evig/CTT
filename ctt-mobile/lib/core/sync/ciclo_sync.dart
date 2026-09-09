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
import 'package:ctt_mobile/core/sync/reconciliador_conflictos.dart';
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
  const CicloSync({
    required this.syncDao,
    required this.dio,
  });

  final SyncDao syncDao;
  final Dio dio;

  /// Lee la cola, envía cada cambio al API (push) y después reconcilia los
  /// conflictos ya resueltos server-side (pull, CTT-117 tramo 3, disparador d).
  Future<void> ejecutar() async {
    // ── Push: drenar la cola de cambios salientes. ───────────────────────────
    final pendientes = await syncDao.obtenerPendientes();
    for (final cambio in pendientes) {
      // "Claim" atómico: si otro ciclo ya tomó esta entrada, retorna false → saltar.
      final tomado = await syncDao.marcarEnviando(cambio.id);
      if (!tomado) continue;

      SenalSync senal;
      String? conflictoId;
      String? detalle;
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
        // señal de dominio y captura el detalle del backend. De acá para abajo
        // no hay HTTP.
        final clasificado = _clasificar(e);
        senal = clasificado.senal;
        conflictoId = clasificado.conflictoId;
        detalle = clasificado.detalle;
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
        detalle: detalle,
      );
    }

    // ── Pull (CTT-117 tramo 3, disparador d): cerrar los conflictos que el
    //    Coordinador ya resolvió. Debounced (no corre en cada ciclo) y
    //    best-effort: un fallo del pull no invalida el push recién hecho.
    try {
      await ReconciliadorConflictos(
        syncDao: syncDao,
        dio: dio,
      ).reconciliarSiCorresponde();
    } catch (_) {
      // El periódico y los demás disparadores reintentan.
    }
  }

  /// Traduce una excepción de envío a una [SenalSync] de dominio y, al lado de
  /// ella, la metadata de transporte que hay que persistir: el conflicto_id (si
  /// es un conflicto) y el detalle legible del backend (si es un rechazo o una
  /// falla). El detalle viaja JUNTO a la señal, no dentro: el dominio nunca lo
  /// ve. Es el único método acoplado a Dio.
  ({SenalSync senal, String? conflictoId, String? detalle}) _clasificar(
    Object error,
  ) {
    if (error is DioException) {
      final detalle = extraerDetalleBackend(error);
      final status = error.response?.statusCode;
      if (status == 409) {
        final id = extraerConflictoId(error);
        // 409 con id = conflicto de concurrencia; 409 sin id = rechazo de
        // negocio (transición inválida, estado ya avanzó). Distinguirlos es lo
        // que corrige el defecto de CTT-115.
        if (id != null) {
          return (
            senal: SenalSync.conflictoDetectado,
            conflictoId: id,
            detalle: null,
          );
        }
        return (
          senal: SenalSync.rechazoDefinitivo,
          conflictoId: null,
          detalle: detalle,
        );
      }
      if (status == 403 || status == 404 || status == 422) {
        // Rechazo permanente: no se arregla reintentando el mismo payload.
        return (
          senal: SenalSync.rechazoDefinitivo,
          conflictoId: null,
          detalle: detalle,
        );
      }
      // Transitorio: red, timeout, 5xx. Se captura el detalle igual (CTT-115):
      // si agota reintentos y cae en descartado/reintentos_agotados, el usuario
      // ve el motivo real del último intento en la bandeja del tramo 4, no un
      // "se agotaron los reintentos" sin pista.
      return (
        senal: SenalSync.fallaTransitoria,
        conflictoId: null,
        detalle: detalle,
      );
    }
    // Excepción no-Dio (p.ej. el stub UnimplementedError de subir_foto): tratar
    // como transitoria — agotará reintentos y terminará en descartado, sin limbo.
    // Sin DioException no hay detalle de backend que extraer.
    return (
      senal: SenalSync.fallaTransitoria,
      conflictoId: null,
      detalle: null,
    );
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
