/// items_cache_dao.dart — Acceso a la caché local de ítems (Drift).
library;

import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:ctt_mobile/data/local/database.dart';

part 'items_cache_dao.g.dart';

@riverpod
ItemsCacheDao itemsCacheDao(ItemsCacheDaoRef ref) =>
    ItemsCacheDao(ref.watch(baseDatosCTTProvider));

@DriftAccessor(tables: [ItemsCacheTable])
class ItemsCacheDao extends DatabaseAccessor<BaseDatosCTT>
    with _$ItemsCacheDaoMixin {
  ItemsCacheDao(super.db);

  Future<List<ItemsCacheTableData>> obtenerPorProyecto(String proyectoId) =>
      (select(itemsCacheTable)
            ..where((t) => t.proyectoId.equals(proyectoId))
            ..orderBy([(t) => OrderingTerm.asc(t.updatedAt)]))
          .get();

  /// Devuelve todos los ítems asignados al usuario (para la vista del trabajador).
  Future<List<ItemsCacheTableData>> obtenerAsignadosA(String usuarioId) =>
      (select(itemsCacheTable)
            ..where((t) => t.asignadoA.equals(usuarioId))
            ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
          .get();

  Future<ItemsCacheTableData?> obtenerPorId(String itemId) =>
      (select(itemsCacheTable)..where((t) => t.id.equals(itemId)))
          .getSingleOrNull();

  /// Inserta o actualiza un ítem en caché (upsert por id).
  Future<void> guardarItem(ItemsCacheTableCompanion item) =>
      into(itemsCacheTable).insertOnConflictUpdate(item);

  /// Reemplaza todos los ítems de un proyecto (descarga completa).
  Future<void> reemplazarPorProyecto(
    String proyectoId,
    List<ItemsCacheTableCompanion> items,
  ) async {
    await (delete(itemsCacheTable)
          ..where((t) => t.proyectoId.equals(proyectoId)))
        .go();
    await batch((b) => b.insertAll(itemsCacheTable, items));
  }

  /// Actualiza el estado de un ítem cacheado y guarda el estado anterior en estadoPrevio.
  /// Permite revertir el cambio si el servidor rechaza la transición.
  Future<void> actualizarEstado(String itemId, String nuevoEstado) async {
    final actual = await obtenerPorId(itemId);
    await (update(itemsCacheTable)..where((t) => t.id.equals(itemId))).write(
      ItemsCacheTableCompanion(
        estado: Value(nuevoEstado),
        estadoPrevio: Value(actual?.estado),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  /// Revierte al estado anterior guardado en estadoPrevio.
  /// No-op si no hay estado previo registrado.
  Future<void> revertirEstado(String itemId) async {
    final actual = await obtenerPorId(itemId);
    if (actual?.estadoPrevio == null) return;
    await (update(itemsCacheTable)..where((t) => t.id.equals(itemId))).write(
      ItemsCacheTableCompanion(
        estado: Value(actual!.estadoPrevio!),
        estadoPrevio: const Value(null),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }
}
