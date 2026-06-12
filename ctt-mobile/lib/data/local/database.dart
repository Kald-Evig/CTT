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
  TextColumn get parentItemId => text().nullable()();
  IntColumn get nivelProfundidad => integer().withDefault(const Constant(0))();
  TextColumn get nombre => text()();
  TextColumn get descripcion => text().nullable()();
  TextColumn get asignadoA => text().nullable()();
  /// EstadoItem.valor — ver enums_ctt.dart.
  TextColumn get estado => text()();
  TextColumn get estadoPrevio => text().nullable()();
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

// ── Base de datos ─────────────────────────────────────────────────────────────

@DriftDatabase(tables: [
  SyncPendientesTable,
  ItemsCacheTable,
  UsuarioActivoTable,
],)
class BaseDatosCTT extends _$BaseDatosCTT {
  BaseDatosCTT() : super(_abrirConexion());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, desde, hasta) async {
          // TODO: agregar migraciones incrementales al subir schemaVersion.
        },
      );
}

/// LazyDatabase: abre el archivo en el primer acceso, no en el constructor.
/// Necesario porque path_provider es async y no puede llamarse en constructor.
LazyDatabase _abrirConexion() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final archivo = File(p.join(dir.path, 'ctt_local.db'));
    return NativeDatabase.createInBackground(archivo);
  });
}
