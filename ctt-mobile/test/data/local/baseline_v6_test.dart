/// baseline_v6_test.dart — CTT-130 fase 3 (línea base v6).
///
/// - Fixture dorado de sync_pendientes: una fila por cada estado, verificada
///   campo por campo tras insertarla y leerla.
/// - Orden de la cola: obtenerPendientes devuelve por `secuencia` (orden de
///   encolado), NO por `creado_en_dispositivo` (el reloj no es monótono, CTT-130).
/// - onUpgrade: from > to y from < 6 lanzan (no hay migración desde v1–v5).
library;

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:ctt_mobile/data/local/database.dart';

void main() {
  late BaseDatosCTT db;
  late Directory tmp;

  setUp(() {
    db = BaseDatosCTT.conConexion(NativeDatabase.memory());
    tmp = Directory.systemTemp.createTempSync('ctt_v6');
  });
  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  /// Base de campos NOT NULL comunes; cada fila sobreescribe lo que necesita.
  SyncPendientesCompanion fila(
    String id,
    String estado, {
    String? motivo,
    String? conflictoId,
    bool acknowledged = false,
    int intentosRed = 0,
    int intentosServidor = 0,
    int? ultimoErrorCodigo,
    String? ultimoError,
    DateTime? creadoEnDispositivo,
  }) =>
      SyncPendientesCompanion.insert(
        id: id,
        idempotencyKey: 'idem-$id',
        empresaId: 'emp-1',
        usuarioId: 'user-1',
        instalacionId: 'inst-1',
        tipoEntidad: 'item',
        entidadId: 'item-$id',
        accion: 'cambio_estado_item',
        payload: '{"k":"$id"}',
        payloadVersion: 1,
        creadoEnDispositivo:
            creadoEnDispositivo ?? DateTime.utc(2026, 1, 1, 12, 0, 0),
        estado: Value(estado),
        motivo: Value(motivo),
        conflictoId: Value(conflictoId),
        acknowledged: Value(acknowledged),
        intentosRed: Value(intentosRed),
        intentosServidor: Value(intentosServidor),
        ultimoErrorCodigo: Value(ultimoErrorCodigo),
        ultimoError: Value(ultimoError),
      );

  Future<SyncPendiente> leer(String id) =>
      (db.select(db.syncPendientes)..where((t) => t.id.equals(id))).getSingle();

  test('schemaVersion (literal, para make-migrations) coincide con kSchemaVersionApp',
      () {
    expect(db.schemaVersion, kSchemaVersionApp);
  });

  group('fixture dorado — una fila por estado, campo por campo', () {
    test('pendiente (defaults) preserva todos los campos', () async {
      await db.syncDao.encolar(fila('r-pend', 'pendiente'));
      final f = await leer('r-pend');
      expect(f.id, 'r-pend');
      expect(f.idempotencyKey, 'idem-r-pend');
      expect(f.empresaId, 'emp-1');
      expect(f.usuarioId, 'user-1');
      expect(f.instalacionId, 'inst-1');
      expect(f.tipoEntidad, 'item');
      expect(f.entidadId, 'item-r-pend');
      expect(f.accion, 'cambio_estado_item');
      expect(f.payload, '{"k":"r-pend"}');
      expect(f.payloadVersion, 1);
      expect(f.versionBase, isNull);
      expect(f.creadoEnDispositivo, DateTime.utc(2026, 1, 1, 12, 0, 0));
      expect(f.estado, 'pendiente');
      expect(f.motivo, isNull);
      expect(f.conflictoId, isNull);
      expect(f.acknowledged, isFalse);
      expect(f.intentosRed, 0);
      expect(f.intentosServidor, 0);
      expect(f.ultimoErrorCodigo, isNull);
      expect(f.ultimoError, isNull);
      expect(f.secuencia, greaterThan(0)); // autoincremental asignado
    });

    test('enviando con intentos_red', () async {
      await db.syncDao.encolar(fila('r-env', 'enviando', intentosRed: 2));
      final f = await leer('r-env');
      expect(f.estado, 'enviando');
      expect(f.intentosRed, 2);
      expect(f.intentosServidor, 0);
    });

    test('esperando_resolucion con motivo + conflicto_id', () async {
      await db.syncDao.encolar(fila('r-esp', 'esperando_resolucion',
          motivo: 'conflicto', conflictoId: 'c-1',),);
      final f = await leer('r-esp');
      expect(f.estado, 'esperando_resolucion');
      expect(f.motivo, 'conflicto');
      expect(f.conflictoId, 'c-1');
    });

    test('sincronizado con acknowledged=true', () async {
      await db.syncDao.encolar(fila('r-sinc', 'sincronizado',
          motivo: 'conflicto_resuelto_cliente', acknowledged: true,),);
      final f = await leer('r-sinc');
      expect(f.estado, 'sincronizado');
      expect(f.motivo, 'conflicto_resuelto_cliente');
      expect(f.acknowledged, isTrue);
    });

    test('descartado con intentos_servidor + ultimo_error_codigo/ultimo_error',
        () async {
      await db.syncDao.encolar(fila('r-desc', 'descartado',
          motivo: 'reintentos_agotados',
          intentosServidor: 3,
          ultimoErrorCodigo: 409,
          ultimoError: 'boom',),);
      final f = await leer('r-desc');
      expect(f.estado, 'descartado');
      expect(f.motivo, 'reintentos_agotados');
      expect(f.intentosServidor, 3);
      expect(f.ultimoErrorCodigo, 409);
      expect(f.ultimoError, 'boom');
    });
  });

  test('orden de la cola: obtenerPendientes ordena por secuencia, NO por '
      'creado_en_dispositivo (reloj invertido)', () async {
    // A se encola PRIMERO pero con fecha POSTERIOR; B después con fecha ANTERIOR.
    // Si ordenara por reloj daría [B, A]; por secuencia (encolado) da [A, B].
    await db.syncDao.encolar(fila('A', 'pendiente',
        creadoEnDispositivo: DateTime.utc(2026, 2, 2),),);
    await db.syncDao.encolar(fila('B', 'pendiente',
        creadoEnDispositivo: DateTime.utc(2026, 1, 1),),);

    final pend = await db.syncDao.obtenerPendientes();
    expect(pend.map((e) => e.id).toList(), ['A', 'B']);
    // Y la secuencia de A es menor que la de B (monotonía por encolado).
    final a = await leer('A');
    final b = await leer('B');
    expect(a.secuencia, lessThan(b.secuencia));
    // Sanity: por reloj, A es POSTERIOR a B (el orden que NO se usó).
    expect(a.creadoEnDispositivo.isAfter(b.creadoEnDispositivo), isTrue);
  });

  group('onUpgrade — no hay migración desde v1–v5', () {
    String seedAt(int version) {
      final path = '${tmp.path}/seed_v$version.db';
      final s = raw.sqlite3.open(path);
      s.execute('PRAGMA user_version = $version');
      s.dispose();
      return path;
    }

    Future<void> abrir(int version) async {
      final d = BaseDatosCTT.conConexion(NativeDatabase(File(seedAt(version))));
      try {
        // La primera query dispara la apertura y la migración.
        await d.customSelect('SELECT 1').get();
      } finally {
        await d.close();
      }
    }

    test('from < 6 (dispositivo en v5) lanza, no migra', () async {
      await expectLater(abrir(5), throwsA(isA<StateError>()));
    });

    test('from > to (base más nueva que la app) lanza', () async {
      await expectLater(abrir(7), throwsA(isA<StateError>()));
    });
  });
}
