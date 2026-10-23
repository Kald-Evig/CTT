/// items_repository.dart — Acceso a ítems del Trabajador: online-first con fallback offline.
///
/// Estrategia de escritura (CTT-36):
///   Intenta el servidor primero (timeout 4s vía TransicionService).
///   Solo si hay error de red se encola en SyncPendientes (Drift).
///   Actualización optimista en caché antes del intento; revert si el servidor rechaza.
///
/// Lecturas: intenta la API; si falla, devuelve la caché local.
library;

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:ctt_mobile/core/device/device_id_service.dart';
import 'package:ctt_mobile/core/network/dio_client.dart';
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

  /// Ítems asignados al usuario autenticado en [empresaId] (la empresa activa). API
  /// primero; caché si falla.
  Future<List<ItemsCacheTableData>> obtenerMisItems(
    String usuarioId,
    String empresaId,
  ) async {
    try {
      final resp = await dio.get<List<dynamic>>('/items/mis-items');
      final items = (resp.data ?? [])
          .cast<Map<String, dynamic>>()
          .map(_jsonACompanion)
          .toList();
      // CTT-149 (opción A): UPSERT (estampando la empresa activa) + RETIRO de ausentes
      // dentro de (usuario, empresa) sin cola no terminal, en UNA transacción, SOLO en el
      // camino 200. La rama DioException NO retira nada.
      await cacheDao.sincronizarPull(usuarioId, empresaId, items);
    } on DioException {
      // Sin conexión — no se retira nada; continúa con la caché.
    }
    return cacheDao.obtenerAsignadosA(usuarioId);
  }

  /// Detalle de un ítem — busca en caché (ya poblada por obtenerMisItems).
  Future<ItemsCacheTableData?> obtenerDetalle(String itemId) =>
      cacheDao.obtenerPorId(itemId);

  // ── Escrituras (online-first con fallback offline) ───────────────────────────

  /// Transiciona el estado de un ítem (CTT-148 "encolar primero"): delega en
  /// [TransicionService.ejecutar], que ENCOLA la intención y dispara el ciclo. NO hay
  /// escritura optimista ni revert en `items_cache`: el estado mostrado sale del overlay
  /// (base + última fila pendiente/enviando, CTT-144). Devuelve el [ResultadoEspera] del
  /// primer intento de la fila.
  Future<ResultadoEspera> cambiarEstado({
    required String itemId,
    required EstadoItem nuevoEstado,
    String? comentario,
    String? descripcionProblema,
  }) =>
      transicionService.ejecutar(
        itemId: itemId,
        nuevoEstado: nuevoEstado.valor,
        comentario: comentario,
        descripcionProblema: descripcionProblema,
      );

  /// Reporta un problema en un ítem (alias de cambiarEstado con estado problema).
  Future<ResultadoEspera> reportarProblema({
    required String itemId,
    required String descripcion,
  }) =>
      cambiarEstado(
        itemId: itemId,
        nuevoEstado: EstadoItem.problema,
        descripcionProblema: descripcion,
      );

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
        // La base = estado del servidor (antes `estado`). version la trae ItemOut/MisItemOut
        // (B1); NULL si el backend aún no la expone. empresa_id NO se estampa aquí: lo hace
        // sincronizarPull con la empresa activa (CTT-149 / opción A, C0).
        estadoServidor: json['estado'] as String,
        version: Value(json['version'] as int?),
        updatedAt: DateTime.now().toUtc(),
        cachadoEn: DateTime.now().toUtc(),
      );
}
