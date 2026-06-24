/// items_repository.dart — Acceso a ítems del Trabajador: online-first con fallback offline.
///
/// Estrategia de escritura (CTT-36):
///   Intenta el servidor primero (timeout 4s vía TransicionService).
///   Solo si hay error de red se encola en SyncPendientes (Drift).
///   Actualización optimista en caché antes del intento; revert si el servidor rechaza.
///
/// Lecturas: intenta la API; si falla, devuelve la caché local.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import 'package:ctt_mobile/core/device/device_id_service.dart';
import 'package:ctt_mobile/core/network/dio_client.dart';
import 'package:ctt_mobile/core/sync/resultado_transicion.dart';
import 'package:ctt_mobile/core/sync/transicion_service.dart';
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
      transicionService: ref.watch(transicionServiceProvider),
    );

class ItemsRepository {
  const ItemsRepository({
    required this.dio,
    required this.cacheDao,
    required this.syncDao,
    required this.deviceIdService,
    required this.transicionService,
  });

  final Dio dio;
  final ItemsCacheDao cacheDao;
  final SyncDao syncDao;
  final DeviceIdService deviceIdService;
  final TransicionService transicionService;

  // ── Lecturas ────────────────────────────────────────────────────────────────

  /// Ítems asignados al usuario autenticado. API primero; caché si falla.
  Future<List<ItemsCacheTableData>> obtenerMisItems(String usuarioId) async {
    try {
      final resp = await dio.get<List<dynamic>>('/items/mis-items');
      final items = (resp.data ?? [])
          .cast<Map<String, dynamic>>()
          .map(_jsonACompanion)
          .toList();
      for (final item in items) {
        await cacheDao.guardarItem(item);
      }
    } on DioException {
      // Sin conexión — continúa con la caché.
    }
    return cacheDao.obtenerAsignadosA(usuarioId);
  }

  /// Detalle de un ítem — busca en caché (ya poblada por obtenerMisItems).
  Future<ItemsCacheTableData?> obtenerDetalle(String itemId) =>
      cacheDao.obtenerPorId(itemId);

  // ── Escrituras (online-first con fallback offline) ───────────────────────────

  /// Transiciona el estado de un ítem.
  ///
  /// 1. Aplica el nuevo estado en la caché local de forma optimista.
  /// 2. Intenta el servidor con timeout corto via TransicionService.
  /// 3. Si el servidor rechaza o hay conflicto: revierte la caché.
  /// 4. Si hay error de red: el TransicionService encola; la caché queda con el estado optimista.
  Future<ResultadoTransicion> cambiarEstado({
    required String itemId,
    required EstadoItem nuevoEstado,
    String? comentario,
    String? descripcionProblema,
  }) async {
    // Actualización optimista: el estado cambia en UI de inmediato.
    await cacheDao.actualizarEstado(itemId, nuevoEstado.valor);

    try {
      final resultado = await transicionService.ejecutar(
        itemId: itemId,
        nuevoEstado: nuevoEstado.valor,
        comentario: comentario,
        descripcionProblema: descripcionProblema,
      );

      if (resultado is TransicionRechazada || resultado is TransicionConConflicto) {
        await cacheDao.revertirEstado(itemId);
      }

      return resultado;
    } catch (e) {
      // Error inesperado (401, 403, 5xx): revertir la caché.
      await cacheDao.revertirEstado(itemId);
      rethrow;
    }
  }

  /// Reporta un problema en un ítem (alias de cambiarEstado con estado problema).
  Future<ResultadoTransicion> reportarProblema({
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
