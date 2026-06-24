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
import 'package:ctt_mobile/data/local/daos/sync_dao.dart';

part 'ciclo_sync.g.dart';

const _maxReintentos = 5;

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
      if (cambio.reintentos >= _maxReintentos) continue;

      // "Claim" atómico: si otro ciclo ya tomó esta entrada, retorna false → saltar.
      final tomado = await syncDao.marcarEnviando(cambio.id);
      if (!tomado) continue;

      try {
        await _enviarCambio(
          accion: cambio.accion,
          entidadId: cambio.entidadId,
          payload: cambio.payload,
        );
        await syncDao.marcarSincronizado(cambio.id);
      } on DioException catch (e) {
        if (e.response?.statusCode == 409) {
          final body = e.response?.data;
          final conflictoId =
              body is Map ? body['conflicto_id'] as String? : null;
          await syncDao.marcarConflicto(cambio.id, conflictoId: conflictoId);
        } else {
          await syncDao.marcarError(
            cambio.id,
            e.message ?? 'Error de red',
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
  }) async {
    final data = jsonDecode(payload) as Map<String, dynamic>;

    switch (accion) {
      case 'cambio_estado_item':
        await dio.post<void>('/items/$entidadId/transicion', data: data);
      case 'subir_foto':
        // TODO Fase 2: obtener pre-signed URL de S3 y subir el archivo local.
        return;
      default:
        throw Exception('Acción de sync desconocida: $accion');
    }
  }
}
