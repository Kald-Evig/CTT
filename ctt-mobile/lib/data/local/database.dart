/// database.dart — Configuración de la base de datos local (Drift/SQLite).
///
/// Línea base de esquema **v6** (CTT-130 fase 3): se aplanaron v1–v5. Desde v6,
/// todo cambio de esquema sigue el flujo oficial de Drift (make-migrations →
/// stepByStep → tests con SchemaVerifier). Las fechas se guardan como TEXTO
/// (ISO-8601) por `store_date_time_values_as_text: true` en build.yaml.
///
/// La cola `sync_pendientes` ordena su envío por `secuencia` (autoincremental
/// monótona), no por reloj del dispositivo (CTT-130: el reloj no es monótono).
///
/// El cifrado en reposo (RUT/ubicación, Ley 19.628) es CTT-132, bloqueado por CTT-133.
library;

import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sqlite3/sqlite3.dart' show Database;
import 'package:ctt_mobile/data/local/daos/items_cache_dao.dart';
import 'package:ctt_mobile/data/local/daos/sync_dao.dart';
import 'package:ctt_mobile/data/local/daos/usuario_activo_dao.dart';
import 'package:ctt_mobile/data/local/database.steps.dart';
import 'package:ctt_mobile/data/local/migracion_atomica.dart';

part 'database.g.dart';

/// Versión del esquema local: **v7** (CTT-103 agregó `rechazo_id` sobre la línea
/// base v6 de CTT-130). Fuente única: la usan el getter [BaseDatosCTT.schemaVersion]
/// y la pre-apertura con sqlite3 crudo (apertura_base.dart) para decidir si migrar.
const kSchemaVersionApp = 7;

// ── Tablas ────────────────────────────────────────────────────────────────────

/// Cola de operaciones pendientes de sincronizar con el servidor (Sección 8).
///
/// Diseño v6 (CTT-130). Este ticket crea las columnas; el comportamiento de cada
/// grupo vive en otros tickets (CTT-103 backoff, CTT-127 lease de huérfanos,
/// CTT-123 dueño/tenant, CTT-121 instalación, CTT-131/CTT-104 versión de entidad).
///
/// - `secuencia` (autoincremental) es el ORDEN de envío monótono dentro de un
///   archivo. `creado_en_dispositivo` queda solo como dato de auditoría.
/// - Tabla STRICT: tipos rígidos de SQLite.
/// - `idempotency_key`, `empresa_id`, `usuario_id`, `instalacion_id`,
///   `payload_version` son NOT NULL: toda fila nace con dueño y contrato.
@DataClassName('SyncPendiente')
@TableIndex(name: 'ux_sync_idempotency', columns: {#idempotencyKey}, unique: true)
@TableIndex(name: 'ix_sync_envio', columns: {#estado, #secuencia})
@TableIndex(name: 'ix_sync_entidad', columns: {#tipoEntidad, #entidadId, #secuencia})
@TableIndex(name: 'ix_sync_usuario', columns: {#usuarioId, #estado})
class SyncPendientes extends Table {
  @override
  String get tableName => 'sync_pendientes';
  @override
  bool get isStrict => true;

  IntColumn get secuencia => integer().autoIncrement()();
  TextColumn get id => text().unique()();
  TextColumn get idempotencyKey => text().named('idempotency_key')();
  TextColumn get empresaId => text().named('empresa_id')();
  TextColumn get usuarioId => text().named('usuario_id')();
  TextColumn get instalacionId => text().named('instalacion_id')();
  TextColumn get tipoEntidad => text().named('tipo_entidad')();
  TextColumn get entidadId => text().named('entidad_id')();
  TextColumn get accion => text()();
  TextColumn get payload => text()();
  IntColumn get payloadVersion => integer().named('payload_version')();
  IntColumn get versionBase => integer().named('version_base').nullable()();
  DateTimeColumn get creadoEnDispositivo =>
      dateTime().named('creado_en_dispositivo')();
  TextColumn get estado => text().withDefault(const Constant('pendiente'))();
  TextColumn get motivo => text().nullable()();
  TextColumn get conflictoId => text().named('conflicto_id').nullable()();
  BoolColumn get acknowledged => boolean().withDefault(const Constant(false))();
  IntColumn get intentosRed =>
      integer().named('intentos_red').withDefault(const Constant(0))();
  IntColumn get intentosServidor =>
      integer().named('intentos_servidor').withDefault(const Constant(0))();
  DateTimeColumn get proximoIntentoEn =>
      dateTime().named('proximo_intento_en').nullable()();
  DateTimeColumn get ultimoIntentoEn =>
      dateTime().named('ultimo_intento_en').nullable()();
  IntColumn get ultimoErrorCodigo =>
      integer().named('ultimo_error_codigo').nullable()();
  TextColumn get ultimoError => text().named('ultimo_error').nullable()();
  TextColumn get tomadoPor => text().named('tomado_por').nullable()();
  DateTimeColumn get tomadoHasta => dateTime().named('tomado_hasta').nullable()();
  DateTimeColumn get sincronizadoEn =>
      dateTime().named('sincronizado_en').nullable()();
  IntColumn get versionResultante =>
      integer().named('version_resultante').nullable()();
  /// id del rechazo determinista del servidor (sync_rechazos, CTT-103). Presente solo
  /// en filas `rechazada`. Declarada AL FINAL a propósito: `ALTER TABLE ... ADD COLUMN`
  /// la agrega al final, así el orden de columnas coincide entre create-fresh (v7) y
  /// migrado-desde-v6 (lo verifica el SchemaVerifier de make-migrations).
  TextColumn get rechazoId => text().named('rechazo_id').nullable()();
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
  /// El ítem tiene un conflicto de sync sin resolver (CTT-117 tramo 2).
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
/// el isolate de UI y el headless de WorkManager (ambos abren el mismo archivo).
class SyncReconciliacionTable extends Table {
  @override
  String get tableName => 'sync_reconciliacion';

  TextColumn get id => text()();
  DateTimeColumn get ultimaReconciliacion => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ── Base de datos ─────────────────────────────────────────────────────────────

/// keepAlive: la base vive toda la sesión (todos los DAOs dependen de ella). Así la
/// instancia que abrió/migró en la compuerta de arranque es la MISMA que usa el
/// router. El reintento de la pantalla de recuperación la invalida explícitamente
/// para obtener una instancia fresca sin el `_migrationError` cacheado de Drift.
@Riverpod(keepAlive: true)
BaseDatosCTT baseDatosCTT(BaseDatosCTTRef ref) {
  final db = BaseDatosCTT();
  ref.onDispose(db.close);
  return db;
}

@DriftDatabase(tables: [
  SyncPendientes,
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
  /// en vez de abrir el archivo real vía path_provider.
  BaseDatosCTT.conConexion(super.executor);

  // Literal a propósito: drift_dev (make-migrations) lee schemaVersion por análisis
  // estático y NO resuelve una referencia a const. Debe coincidir con
  // kSchemaVersionApp (lo garantiza un test). Ver CTT-130 fase 7.
  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, desde, hasta) async {
          if (desde > hasta) {
            throw StateError(
              'Downgrade de esquema no soportado (from=$desde > to=$hasta): '
              'la base es más nueva que la app.',
            );
          }
          if (desde < 6) {
            // Instalación pre-baseline (v1–v5): un dispositivo olvidado en v5
            // debe fallar, NO bajar de versión por pasos que ya no existen.
            throw StateError(
              'Migración desde el esquema v$desde no soportada. La línea base es '
              'v6 (CTT-130); las versiones v1–v5 se aplanaron. Requiere '
              'reinstalación de la app.',
            );
          }
          // desde >= 6: migración real por pasos (v7 en adelante), ATÓMICA —
          // pasos + user_version en una sola transacción (CTT-130 fase 4).
          await migrarAtomico(this, from: desde, to: hasta,
              pasos: _pasosMigracion(desde, hasta),);
        },
      );

  /// Pasos de migración por rango de versiones (v7 en adelante). Cada boundary
  /// cruzada aporta sus pasos; se concatenan en orden. v6 es la línea base.
  List<PasoMigracion> _pasosMigracion(int desde, int hasta) {
    final pasos = <PasoMigracion>[];
    // v6 → v7 (CTT-103): columna rechazo_id (TEXT nullable). Se migra con el ESQUEMA
    // CONGELADO v7 que genera make-migrations (Schema7 en database.steps.dart), no con
    // la tabla viva: así el paso no se rompe si la tabla evoluciona después. El
    // Migrator genera el DDL idéntico a createAll (lo valida el SchemaVerifier). Sigue
    // corriendo dentro de migrarAtomico, que conserva la atomicidad pasos+user_version.
    if (desde < 7 && hasta >= 7) {
      pasos.add((db) async {
        final schema = Schema7(database: db);
        await Migrator(db, schema)
            .addColumn(schema.syncPendientes, schema.syncPendientes.rechazoId);
      });
    }
    return pasos;
  }

  /// Fuerza a los streams `.watch()` de `sync_pendientes` a re-consultar. Para cuando
  /// la tabla cambió FUERA de esta conexión —el isolate headless de WorkManager mientras
  /// la app estaba en background—: Drift solo notifica por escrituras de ESTA conexión,
  /// así que al volver a primer plano (app.dart, resumed) avisamos a mano y la UI
  /// refleja lo que haya escrito el headless. CTT-103 D6-R2.
  ///
  /// LÍMITE conocido: no cubre escrituras del headless MIENTRAS la app está en primer
  /// plano (no hay señal de ese isolate hacia este); se cubre al próximo resumed.
  Future<void> notificarSyncPendientesExterno() async =>
      markTablesUpdated({syncPendientes});
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
