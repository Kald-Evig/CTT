/// ciclo_sync.dart — Lógica del ciclo de sincronización con dependencias inyectadas.
///
/// [CicloSync] recibe [SyncDao] y [Dio] por constructor y no instancia nada.
/// Permite que el mismo ciclo sea ejecutado desde dos caminos distintos:
///   - WorkManager (headless): SyncDao y Dio creados por sync_service.dart.
///   - Foreground (app viva): SyncDao y Dio del ProviderScope vía [cicloSyncProvider].
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:ctt_mobile/core/network/dio_client.dart';
import 'package:ctt_mobile/core/network/extraer_detalle_backend.dart';
import 'package:ctt_mobile/data/local/daos/sync_dao.dart';

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
    await syncDao.reactivarErrores();
    final pendientes = await syncDao.obtenerPendientes();
    if (pendientes.isEmpty) return;

    for (final cambio in pendientes) {
      // Defensa en profundidad: hoy inalcanzable, porque reactivarErrores ya no
      // revive las entradas agotadas (reintentos >= kMaxReintentosSync) y
      // obtenerPendientes solo trae 'pendiente'. Se conserva por si el filtro
      // SQL de reactivarErrores se afloja y una agotada vuelve a la cola.
      if (cambio.reintentos >= kMaxReintentosSync) continue;

      // "Claim" atómico: si otro ciclo ya tomó esta entrada, retorna false → saltar.
      final tomado = await syncDao.marcarEnviando(cambio.id);
      if (!tomado) continue;

      try {
        await _enviarCambio(
          accion: cambio.accion,
          entidadId: cambio.entidadId,
          payload: cambio.payload,
          idempotencyKey: cambio.idempotencyKey,
        );
        await syncDao.marcarSincronizado(cambio.id);
      } on DioException catch (e) {
        final status = e.response?.statusCode;
        if (status == 409) {
          final body = e.response?.data;
          final conflictoId =
              body is Map ? body['conflicto_id'] as String? : null;
          await syncDao.marcarConflicto(cambio.id, conflictoId: conflictoId);
        } else if (status == 403 || status == 404 || status == 422) {
          // Rechazo permanente: permiso denegado, recurso inexistente o datos
          // inválidos. No se arregla reintentando — estado terminal, sin tocar
          // reintentos. El 422 (validación de datos) es permanente por
          // naturaleza: reintentar el mismo payload da el mismo error (CTT-102).
          await syncDao.marcarRechazado(cambio.id, extraerDetalleBackend(e));
        } else {
          // Transitorio (red, timeout, 5xx): reintentar en ciclos futuros con
          // el motivo real del backend cuando lo haya.
          await syncDao.marcarError(
            cambio.id,
            extraerDetalleBackend(e),
            cambio.reintentos + 1,
          );
        }
      } catch (e) {
        await syncDao.marcarError(
          cambio.id,
          e.toString(),
          cambio.reintentos + 1,
        );
      }
    }
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
        // (CTT-99). El throw es intencional para NO caer en marcarSincronizado
        // sin una respuesta 2xx del servidor: cae en el catch genérico y la
        // entrada queda en `error` con motivo. Se reemplaza por la lógica de
        // subida real (pre-signed URL de S3 + upload del archivo local), NO
        // por otro parche.
        throw UnimplementedError(
          'subir_foto: la captura y subida de evidencia no está implementada (CTT-99). '
          'La entrada NO se marca como sincronizada.',
        );
      default:
        throw Exception('Acción de sync desconocida: $accion');
    }
  }
}
