/// database.dart — Configuración de la base de datos local (Drift/SQLite).
///
/// Tablas iniciales del MVP. Todas las escrituras van primero a SyncPendientes
/// (offline-first) antes de intentar sincronizar con el servidor.
///
/// TODO Fase 1.5: integrar SQLCipher cuando se almacenen RUT y ubicación
/// de trabajadores — datos personales que exigen cifrado en reposo (Ley 19.628).
/// Ver: https://drift.simonbinder.eu/docs/platforms/encryption/
library;

import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sqlite3/sqlite3.dart' show Database;
import 'package:ctt_mobile/core/sync/decision_sync.dart' show kMaxReintentosSync;
import 'package:ctt_mobile/data/local/daos/items_cache_dao.dart';
import 'package:ctt_mobile/data/local/daos/sync_dao.dart';
import 'package:ctt_mobile/data/local/daos/usuario_activo_dao.dart';

part 'database.g.dart';

// ── Tablas ────────────────────────────────────────────────────────────────────

/// Cola de operaciones pendientes de sincronizar con el servidor (Sección 8).
/// Orden de envío: timestampDispositivo ASC (FIFO estricto).
class SyncPendientesTable extends Table {
  @override
  String get tableName => 'sync_pendientes';

  TextColumn get id => text()();
  TextColumn get tipoEntidad => text()();
  TextColumn get entidadId => text()();
  TextColumn get accion => text()();
  /// Payload JSON del cambio — lo que se enviará al endpoint.
  TextColumn get payload => text()();
  DateTimeColumn get timestampDispositivo => dateTime()();
  TextColumn get dispositivoId => text()();
  IntColumn get reintentos => integer().withDefault(const Constant(0))();
  /// EstadoSyncLocal.valor — ver enums_ctt.dart.
  TextColumn get estado => text().withDefault(const Constant('pendiente'))();
  TextColumn get ultimoError => text().nullable()();
  /// Clave de idempotencia (CTT-105). Nullable: las filas encoladas antes de
  /// esta versión no la tienen y no se puede inventar una retroactivamente.
  TextColumn get idempotencyKey => text().nullable()();
  /// MotivoSync.valor — razón asociada al estado (ver enums_ctt.dart). Nullable:
  /// null en el camino feliz (pendiente/enviando/sincronizado directo).
  TextColumn get motivo => text().nullable()();
  /// conflicto_id del backend para las filas en conflicto (CTT-117 tramo 2).
  /// Lo consume el reconciliador del tramo 3 para casar con /sync/conflictos/mios.
  /// Antes vivía string-encodeado en ultimoError; ahora tiene columna propia.
  TextColumn get conflictoId => text().nullable()();
  /// El usuario ya vio el desenlace terminal de esta entrada (para la bandeja
  /// del tramo 4). Default false: un terminal recién escrito aún no se mostró.
  BoolColumn get acknowledged => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Caché local de ítems descargados del servidor.
/// Solo campos esenciales para el modo offline. El árbol completo se carga online.
class ItemsCacheTable extends Table {
  @override
  String get tableName => 'items_cache';

  TextColumn get id => text()();
  TextColumn get proyectoId => text()();
  TextColumn get proyectoNombre => text().withDefault(const Constant(''))();
  TextColumn get parentItemId => text().nullable()();
  IntColumn get nivelProfundidad => integer().withDefault(const Constant(0))();
  TextColumn get nombre => text()();
  TextColumn get descripcion => text().nullable()();
  TextColumn get asignadoA => text().nullable()();
  /// EstadoItem.valor — ver enums_ctt.dart.
  TextColumn get estado => text()();
  TextColumn get estadoPrevio => text().nullable()();
  /// El ítem tiene un conflicto de sync sin resolver (CTT-117 tramo 2). La
  /// migración lo puebla para los ítems con fila en conflicto; el runtime que lo
  /// pone/limpia en caliente es del tramo 3 (disparadores) / tramo 4 (UI).
  BoolColumn get tieneConflicto =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime()();
  /// Cuando se descargó del servidor por última vez.
  DateTimeColumn get cachadoEn => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Perfil del usuario autenticado en el dispositivo.
/// Solo un registro a la vez (la sesión activa).
class UsuarioActivoTable extends Table {
  @override
  String get tableName => 'usuario_activo';

  TextColumn get id => text()();
  TextColumn get firebaseUid => text()();
  TextColumn get nombreCompleto => text()();
  TextColumn get email => text()();
  /// RolUsuario.valor del rol en la empresa activa.
  TextColumn get rolActual => text()();
  TextColumn get empresaId => text()();
  TextColumn get empresaNombre => text()();
  BoolColumn get esSuperAdmin =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Estado del reconciliador de conflictos (CTT-117 tramo 3). Fila única (id fijo).
/// Guarda cuándo corrió la última reconciliación, para el DEBOUNCE compartido entre
/// el isolate de UI (arranque, resumed, conectividad) y el headless de WorkManager.
/// Ambos abren el mismo archivo SQLite (CTT-105): una variable en memoria no
/// coordinaría entre los dos isolates.
class SyncReconciliacionTable extends Table {
  @override
  String get tableName => 'sync_reconciliacion';

  TextColumn get id => text()();
  DateTimeColumn get ultimaReconciliacion => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ── Base de datos ─────────────────────────────────────────────────────────────

@riverpod
BaseDatosCTT baseDatosCTT(BaseDatosCTTRef ref) {
  final db = BaseDatosCTT();
  ref.onDispose(db.close);
  return db;
}

@DriftDatabase(tables: [
  SyncPendientesTable,
  ItemsCacheTable,
  UsuarioActivoTable,
  SyncReconciliacionTable,
], daos: [
  SyncDao,
  ItemsCacheDao,
  UsuarioActivoDao,
],)
class BaseDatosCTT extends _$BaseDatosCTT {
  BaseDatosCTT() : super(_abrirConexion());

  /// Constructor para tests: inyecta un [QueryExecutor] (p.ej. una BD in-memory)
  /// en vez de abrir el archivo real vía path_provider. Permite ejercer las
  /// migraciones sin dispositivo.
  BaseDatosCTT.conConexion(super.executor);

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, desde, hasta) async {
          if (desde < 2) {
            await m.addColumn(itemsCacheTable, itemsCacheTable.proyectoNombre);
          }
          if (desde < 3) {
            await m.addColumn(
                syncPendientesTable, syncPendientesTable.idempotencyKey,);
          }
          if (desde < 4) {
            await _migrarV3aV4(m);
          }
          if (desde < 5) {
            await _migrarV4aV5(m);
          }
        },
      );

  /// Migración v3→v4 (CTT-117 tramo 2 + CTT-103 pto 4).
  ///
  /// Separa estado de motivo: `error`/`conflicto`/`rechazado` dejan de ser
  /// estados. Mapea el CASO GENERAL de las filas heredadas —este código corre en
  /// dispositivos reales, no solo en dev—, sin afirmar falsamente que se descartó
  /// trabajo del usuario.
  Future<void> _migrarV3aV4(Migrator m) async {
    // 1. Columnas nuevas.
    await m.addColumn(itemsCacheTable, itemsCacheTable.tieneConflicto);
    await m.addColumn(syncPendientesTable, syncPendientesTable.motivo);
    await m.addColumn(syncPendientesTable, syncPendientesTable.conflictoId);
    await m.addColumn(syncPendientesTable, syncPendientesTable.acknowledged);

    // 2. Rescatar el conflicto_id que vivía string-encodeado en ultimo_error
    //    ('conflicto_id:<uuid>', 13 chars de prefijo) a su columna propia.
    await customStatement(
      "UPDATE sync_pendientes "
      "SET conflicto_id = substr(ultimo_error, length('conflicto_id:') + 1) "
      "WHERE estado = 'conflicto' AND ultimo_error LIKE 'conflicto_id:%'",
    );

    // 3. Marcar el flag en los ítems que tienen una fila en conflicto.
    await customStatement(
      "UPDATE items_cache SET tiene_conflicto = 1 "
      "WHERE id IN (SELECT entidad_id FROM sync_pendientes "
      "WHERE estado = 'conflicto')",
    );

    // 4. Mapeo de estados viejos → (estado nuevo, motivo). De lo específico a lo
    //    general para que las condiciones no se pisen.
    // 4a. error AGOTADO (reintentos >= max) → descartado/reintentos_agotados.
    //     Este es el fix del limbo de CTT-103: la fila deja de quedar atrapada.
    await customStatement(
      "UPDATE sync_pendientes "
      "SET estado = 'descartado', motivo = 'reintentos_agotados' "
      "WHERE estado = 'error' AND reintentos >= $kMaxReintentosSync",
    );
    // 4b. error reintentable → pendiente/error_transitorio.
    await customStatement(
      "UPDATE sync_pendientes "
      "SET estado = 'pendiente', motivo = 'error_transitorio' "
      "WHERE estado = 'error'",
    );
    // 4c. rechazado → descartado/rechazo_negocio.
    await customStatement(
      "UPDATE sync_pendientes "
      "SET estado = 'descartado', motivo = 'rechazo_negocio' "
      "WHERE estado = 'rechazado'",
    );
    // 4d. conflicto → esperando_resolucion/conflicto. NO se decide el terminal
    //     acá: version_ganadora vive en el backend y esta migración corre
    //     offline. El reconciliador del tramo 3 (pull de /mios) lo resolverá a
    //     sincronizado (ganó cliente) o descartado (ganó servidor); si /mios no
    //     tiene registro, cae en heredado_indeterminado. Mapear todo a descartado
    //     acá afirmaría falsamente que se descartó trabajo del usuario.
    await customStatement(
      "UPDATE sync_pendientes "
      "SET estado = 'esperando_resolucion', motivo = 'conflicto' "
      "WHERE estado = 'conflicto'",
    );
    // 4e. enviando huérfano (app muerta a mitad de POST) → pendiente. Hoy queda
    //     atascado porque marcarEnviando exige 'pendiente'. Re-encolar es lo
    //     seguro; el Idempotency-Key (CTT-105) mitiga el doble-apply, y una 2da
    //     aplicación sobre un estado ya cambiado la rechaza la máquina de estados.
    await customStatement(
      "UPDATE sync_pendientes SET estado = 'pendiente' WHERE estado = 'enviando'",
    );

    // 'pendiente' y 'sincronizado' siguen siendo válidos: no se tocan.
    // acknowledged queda en su default (false) para TODAS las filas heredadas:
    // marcar como reconocido afirmaría que el usuario ya vio el desenlace.
  }

  /// Migración v4→v5 (CTT-117 tramo 3): agrega la tabla del debounce persistido
  /// del reconciliador. Tabla nueva y vacía — no hay datos que mover.
  Future<void> _migrarV4aV5(Migrator m) async {
    await m.createTable(syncReconciliacionTable);
  }
}

/// Top-level para que sea enviable al isolate de background de createInBackground.
/// Drift la ejecuta en ese isolate antes de correr migraciones.
void _configurarPragmas(Database db) {
  db.execute('PRAGMA journal_mode=WAL;');
  db.execute('PRAGMA busy_timeout=5000;');
}

/// LazyDatabase: abre el archivo en el primer acceso, no en el constructor.
/// Necesario porque path_provider es async y no puede llamarse en constructor.
LazyDatabase _abrirConexion() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final archivo = File(p.join(dir.path, 'ctt_local.db'));
    return NativeDatabase.createInBackground(archivo, setup: _configurarPragmas);
  });
}
