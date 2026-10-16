/// items_cache_dao.dart — Acceso a la caché local de ítems (Drift).
library;

import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:ctt_mobile/data/local/database.dart';
import 'package:ctt_mobile/domain/enums/enums_ctt.dart';

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

  // ── Estado MOSTRADO = base + overlay (CTT-144) ───────────────────────────────

  /// Columnas de `items_cache` (alias `ic`) con `estado` reemplazado por el OVERLAY:
  /// el `nuevo_estado` de la última fila `pendiente`/`enviando` del ítem
  /// ([estadosIntencionLocal]), o la base (`ic.estado`) si no hay ninguna.
  /// `esperandoResolucion` y las terminales NO entran: el servidor ya respondió.
  ///
  /// La clave del payload es [kPayloadNuevoEstado].
  /// DUPE: el mismo conocimiento ("nuevo_estado vive en payload") lo ESCRIBE
  /// transicion_service.dart (_prepararFila) con jsonEncode. Consolidar si cambia el
  /// contrato del payload.
  String get _columnasConOverlay {
    final estados = estadosIntencionLocal.map((e) => "'${e.valor}'").join(', ');
    return '''
      ic.id AS id, ic.proyecto_id AS proyecto_id, ic.proyecto_nombre AS proyecto_nombre,
      ic.parent_item_id AS parent_item_id, ic.nivel_profundidad AS nivel_profundidad,
      ic.nombre AS nombre, ic.descripcion AS descripcion, ic.asignado_a AS asignado_a,
      COALESCE(
        (SELECT json_extract(sp.payload, '\$.$kPayloadNuevoEstado')
           FROM sync_pendientes sp
          WHERE sp.tipo_entidad = '${TipoEntidad.item.valor}'
            AND sp.entidad_id = ic.id
            AND sp.estado IN ($estados)
          ORDER BY sp.secuencia DESC LIMIT 1),
        ic.estado) AS estado,
      ic.estado_previo AS estado_previo, ic.tiene_conflicto AS tiene_conflicto,
      ic.updated_at AS updated_at, ic.cachado_en AS cachado_en
    ''';
  }

  Set<ResultSetImplementation<dynamic, dynamic>> get _tablasOverlay =>
      {attachedDatabase.itemsCacheTable, attachedDatabase.syncPendientes};

  /// Ítems asignados al usuario con el estado mostrado (base + overlay). Stream
  /// REACTIVO: reacciona a cambios en `items_cache` Y en `sync_pendientes`.
  Stream<List<ItemsCacheTableData>> observarAsignadosConOverlay(String usuarioId) =>
      customSelect(
        'SELECT $_columnasConOverlay FROM items_cache ic '
        'WHERE ic.asignado_a = ?1 ORDER BY ic.updated_at DESC',
        variables: [Variable.withString(usuarioId)],
        readsFrom: _tablasOverlay,
      ).watch().map((filas) => filas
          .map((f) => attachedDatabase.itemsCacheTable.map(f.data))
          .toList(),);

  /// Un ítem por id con el estado mostrado (base + overlay). Stream REACTIVO.
  Stream<ItemsCacheTableData?> observarPorIdConOverlay(String itemId) =>
      customSelect(
        'SELECT $_columnasConOverlay FROM items_cache ic WHERE ic.id = ?1',
        variables: [Variable.withString(itemId)],
        readsFrom: _tablasOverlay,
      ).watch().map((filas) => filas.isEmpty
          ? null
          : attachedDatabase.itemsCacheTable.map(filas.first.data),);

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
