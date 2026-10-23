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

  /// Sincroniza la caché con el pull COMPLETO de /mis-items (CTT-149, opción A): UPSERT de
  /// todos los [items] devueltos (estampando [empresaId] = la empresa activa, que el JSON no
  /// trae) y RETIRO de los asignados a [usuarioId] EN [empresaId] que ya NO vinieron en el
  /// pull Y que NO tienen filas no terminales en `sync_pendientes` ([estadosNoTerminales]);
  /// esos se conservan y se retiran cuando su cola termine. Todo en UNA transacción. El
  /// llamador lo invoca SOLO tras un pull 200 (nunca en la rama de error de red), para no
  /// vaciar la caché cuando no hay servidor. El retiro NO toca ítems de OTRA empresa del
  /// mismo usuario (multiempresa).
  Future<void> sincronizarPull(
    String usuarioId,
    String empresaId,
    List<ItemsCacheTableCompanion> items,
  ) =>
      transaction(() async {
        for (final it in items) {
          await into(itemsCacheTable)
              .insertOnConflictUpdate(it.copyWith(empresaId: Value(empresaId)));
        }
        final presentes = items.map((i) => i.id.value).toSet();
        final sp = attachedDatabase.syncPendientes;
        final conCola = (await (selectOnly(sp)
                  ..addColumns([sp.entidadId])
                  ..where(sp.tipoEntidad.equals(TipoEntidad.item.valor) &
                      sp.estado.isIn(estadosNoTerminalesValores)))
                .map((r) => r.read(sp.entidadId))
                .get())
            .whereType<String>()
            .toSet();
        final conservar = {...presentes, ...conCola}.toList();
        // Scope del retiro: (usuario, empresa activa). Un ítem de la empresa B del mismo
        // usuario NO se retira al hacer pull de la empresa A.
        await (delete(itemsCacheTable)
              ..where((t) =>
                  t.asignadoA.equals(usuarioId) &
                  t.empresaId.equals(empresaId) &
                  t.id.isNotIn(conservar)))
            .go();
      });

  // ── Estado MOSTRADO = base + overlay (CTT-144) ───────────────────────────────

  /// Columnas de `items_cache` (alias `ic`): TODAS las de la tabla (para reconstruir la
  /// base con `itemsCacheTable.map`, tipos y fechas incluidos) MÁS `estado_mostrado`, el
  /// OVERLAY = `nuevo_estado` de la última fila `pendiente`/`enviando` del ítem
  /// ([estadosIntencionLocal]), o la base (`ic.estado_servidor`) si no hay ninguna.
  /// `esperandoResolucion` y las terminales NO entran: el servidor ya respondió.
  ///
  /// CTT-143 §6.2: la base (`estado_servidor`) y lo mostrado (`estado_mostrado`) van como
  /// columnas SEPARADAS en [ItemConOverlay] (el aviso de conflicto de C4 necesita ambas);
  /// NO se colapsan en el mapper de la tabla, que solo tiene una columna de estado.
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
      ic.empresa_id AS empresa_id, ic.estado_servidor AS estado_servidor,
      ic.version AS version, ic.tiene_conflicto AS tiene_conflicto,
      ic.updated_at AS updated_at, ic.cachado_en AS cachado_en,
      COALESCE(
        (SELECT json_extract(sp.payload, '\$.$kPayloadNuevoEstado')
           FROM sync_pendientes sp
          WHERE sp.tipo_entidad = '${TipoEntidad.item.valor}'
            AND sp.entidad_id = ic.id
            AND sp.estado IN ($estados)
          ORDER BY sp.secuencia DESC LIMIT 1),
        ic.estado_servidor) AS estado_mostrado
    ''';
  }

  Set<ResultSetImplementation<dynamic, dynamic>> get _tablasOverlay =>
      {attachedDatabase.itemsCacheTable, attachedDatabase.syncPendientes};

  /// Reconstruye la base con el mapper de la tabla (tipos y fechas correctos) y le agrega
  /// `estado_mostrado` leído de la fila cruda.
  ItemConOverlay _aItemConOverlay(QueryRow f) => ItemConOverlay(
        base: attachedDatabase.itemsCacheTable.map(f.data),
        estadoMostrado: f.read<String>('estado_mostrado'),
      );

  /// Ítems del usuario en la EMPRESA ACTIVA con el estado mostrado (base + overlay). Stream
  /// REACTIVO (reacciona a `items_cache` Y `sync_pendientes`). Filtra por (usuario, empresa)
  /// — opción A, CTT-143 §6.1.
  Stream<List<ItemConOverlay>> observarAsignadosConOverlay(
    String usuarioId,
    String empresaId,
  ) =>
      customSelect(
        'SELECT $_columnasConOverlay FROM items_cache ic '
        'WHERE ic.asignado_a = ?1 AND ic.empresa_id = ?2 ORDER BY ic.updated_at DESC',
        variables: [Variable.withString(usuarioId), Variable.withString(empresaId)],
        readsFrom: _tablasOverlay,
      ).watch().map((filas) => filas.map(_aItemConOverlay).toList());

  /// Un ítem por id con el estado mostrado (base + overlay). Stream REACTIVO. Por id global
  /// (el detalle se abre por id; NO filtra empresa — CTT-143 §6.1).
  Stream<ItemConOverlay?> observarPorIdConOverlay(String itemId) =>
      customSelect(
        'SELECT $_columnasConOverlay FROM items_cache ic WHERE ic.id = ?1',
        variables: [Variable.withString(itemId)],
        readsFrom: _tablasOverlay,
      ).watch().map(
          (filas) => filas.isEmpty ? null : _aItemConOverlay(filas.first));

  /// Inserta o actualiza un ítem en caché (upsert por id).
  Future<void> guardarItem(ItemsCacheTableCompanion item) =>
      into(itemsCacheTable).insertOnConflictUpdate(item);
}

/// Fila de `items_cache` CON el estado MOSTRADO ya calculado (base + overlay de la cola).
/// Lleva [estadoServidor] (la base = último estado conocido del servidor) y [estadoMostrado]
/// (lo que ve el usuario) por SEPARADO: el aviso de conflicto (C4) necesita ambos. [base] es
/// la fila cruda de la tabla; los getters delegan para que la UI lea `item.nombre`,
/// `item.estadoMostrado`, etc., sin desenvolver [base].
class ItemConOverlay {
  const ItemConOverlay({required this.base, required this.estadoMostrado});

  /// Fila cruda de `items_cache` (ya con tipos correctos vía el mapper de la tabla).
  final ItemsCacheTableData base;

  /// `EstadoItem.valor` mostrado: `nuevo_estado` de la última fila pendiente/enviando del
  /// ítem, o [estadoServidor] si no hay ninguna.
  final String estadoMostrado;

  String get id => base.id;
  String get proyectoId => base.proyectoId;
  String get proyectoNombre => base.proyectoNombre;
  String? get parentItemId => base.parentItemId;
  int get nivelProfundidad => base.nivelProfundidad;
  String get nombre => base.nombre;
  String? get descripcion => base.descripcion;
  String? get asignadoA => base.asignadoA;
  String? get empresaId => base.empresaId;

  /// Último estado conocido del servidor (la base).
  String get estadoServidor => base.estadoServidor;
  int? get version => base.version;
  bool get tieneConflicto => base.tieneConflicto;
  DateTime get updatedAt => base.updatedAt;
  DateTime get cachadoEn => base.cachadoEn;
}
