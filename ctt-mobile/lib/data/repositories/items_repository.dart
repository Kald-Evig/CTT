/// items_repository.dart — Acceso a ítems: API primero, caché como fallback.
///
/// Estrategia offline-first:
///   Lecturas: intenta la API; si falla, devuelve la caché local.
///   Escrituras: encola en SyncPendientes y actualiza la caché optimistamente.
library;

import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';
import 'package:ctt_mobile/core/device/device_id_service.dart';
import 'package:ctt_mobile/core/network/dio_client.dart';
import 'package:ctt_mobile/data/local/daos/items_cache_dao.dart';
import 'package:ctt_mobile/data/local/daos/sync_dao.dart';
import 'package:ctt_mobile/data/local/database.dart';
import 'package:ctt_mobile/domain/enums/enums_ctt.dart';

part 'items_repository.g.dart';

@riverpod
ItemsRepository itemsRepository(ItemsRepositoryRef ref) => ItemsRepository(
      dio: ref.watch(dioClientProvider),
      cacheDao: ref.watch(itemsCacheDaoProvider),
      syncDao: ref.watch(syncDaoProvider),
      deviceIdService: ref.watch(deviceIdServiceProvider),
    );

class ItemsRepository {
  const ItemsRepository({
    required this.dio,
    required this.cacheDao,
    required this.syncDao,
    required this.deviceIdService,
  });

  final Dio dio;
  final ItemsCacheDao cacheDao;
  final SyncDao syncDao;
  final DeviceIdService deviceIdService;

  // ── Lecturas ────────────────────────────────────────────────────────────────

  /// Ítems asignados al usuario autenticado. API primero; caché si falla.
  Future<List<ItemsCacheTableData>> obtenerMisItems(String usuarioId) async {
    try {
      final resp = await dio.get<List<dynamic>>('/items/mis-items');
      final items = (resp.data ?? [])
          .cast<Map<String, dynamic>>()
          .map(_jsonACompanion)
          .toList();
      // Actualiza la caché de todos los ítems descargados.
      for (final item in items) {
        await cacheDao.guardarItem(item);
      }
    } on DioException {
      // Sin conexión — continúa con la caché.
    }
    return cacheDao.obtenerAsignadosA(usuarioId);
  }

  /// Detalle de un ítem — busca en caché primero (ya poblada por obtenerMisItems).
  Future<ItemsCacheTableData?> obtenerDetalle(String itemId) =>
      cacheDao.obtenerPorId(itemId);

  // ── Escrituras (offline-first: cola → caché optimista) ──────────────────────

  /// Encola una transición de estado y actualiza la caché localmente.
  Future<void> cambiarEstado({
    required String itemId,
    required EstadoItem nuevoEstado,
    String? comentario,
    String? descripcionProblema,
  }) async {
    final deviceId = await deviceIdService.obtener();
    final ahora = DateTime.now().toUtc();
    final payload = jsonEncode({
      'nuevo_estado': nuevoEstado.valor,
      if (comentario != null) 'comentario': comentario,
      if (descripcionProblema != null)
        'descripcion_problema': descripcionProblema,
      // Necesarios para detección de conflictos de concurrencia en backend (Sección 8).
      'device_timestamp': ahora.toIso8601String(),
      'dispositivo_id': deviceId,
    });

    await syncDao.encolar(SyncPendientesTableCompanion.insert(
      id: const Uuid().v4(),
      tipoEntidad: TipoEntidad.item.valor,
      entidadId: itemId,
      accion: AccionSync.cambioEstadoItem.valor,
      payload: payload,
      timestampDispositivo: ahora,
      dispositivoId: deviceId,
    ),);

    // Actualización optimista: el estado cambia en UI aunque no haya conexión.
    await cacheDao.actualizarEstado(itemId, nuevoEstado.valor);
  }

  /// Encola el reporte de un problema en un ítem.
  Future<void> reportarProblema({
    required String itemId,
    required String descripcion,
  }) =>
      cambiarEstado(
        itemId: itemId,
        nuevoEstado: EstadoItem.problema,
        descripcionProblema: descripcion,
      );

  /// Encola el registro de una foto tomada offline.
  Future<void> registrarFotoLocal({
    required String itemId,
    required String rutaLocalFoto,
  }) async {
    final deviceId = await deviceIdService.obtener();
    await syncDao.encolar(SyncPendientesTableCompanion.insert(
      id: const Uuid().v4(),
      tipoEntidad: TipoEntidad.evidencia.valor,
      entidadId: itemId,
      accion: AccionSync.subirFoto.valor,
      payload: jsonEncode({
        'ruta_local': rutaLocalFoto,
        'device_timestamp': DateTime.now().toUtc().toIso8601String(),
      }),
      timestampDispositivo: DateTime.now().toUtc(),
      dispositivoId: deviceId,
    ),);
  }

  // ── Helpers de conversión ────────────────────────────────────────────────────

  ItemsCacheTableCompanion _jsonACompanion(Map<String, dynamic> json) =>
      ItemsCacheTableCompanion.insert(
        id: json['id'] as String,
        proyectoId: json['proyecto_id'] as String,
        proyectoNombre: Value(json['proyecto_nombre'] as String? ?? ''),
        parentItemId: Value(json['parent_item_id'] as String?),
        nivelProfundidad: Value(json['nivel_profundidad'] as int? ?? 0),
        nombre: json['nombre'] as String,
        descripcion: Value(json['descripcion'] as String?),
        asignadoA: Value(json['asignado_a'] as String?),
        estado: json['estado'] as String,
        estadoPrevio: const Value(null),
        updatedAt: DateTime.now().toUtc(),
        cachadoEn: DateTime.now().toUtc(),
      );
}
