/// migracion_atomica_test.dart — CTT-130 fase 4.
///
/// T1 (criterio de corte): una migración de 3 pasos con falla en el paso 2, sobre
/// una base con filas en la cola, revierte pasos Y versión y no corrompe la cola.
/// T2: re-chequeo — si user_version ya está en destino, los pasos no se ejecutan.
/// (Extra) user_version es transaccional: se revierte con el ROLLBACK.
///
/// v6 es la línea base: no hay pasos reales todavía. Se inyectan pasos sintéticos.
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ctt_mobile/data/local/database.dart';
import 'package:ctt_mobile/data/local/migracion_atomica.dart';

void main() {
  late BaseDatosCTT db;

  setUp(() => db = BaseDatosCTT.conConexion(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> encolarFila(String id) => db.syncDao.encolar(
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
          creadoEnDispositivo: DateTime.utc(2026, 1, 1),
          estado: const Value('pendiente'),
          intentosRed: const Value(2),
        ),
      );

  Future<bool> existeTabla(String nombre) async {
    final r = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type='table' "
            "AND name='$nombre'")
        .get();
    return r.isNotEmpty;
  }

  test('T1 — falla en el paso 2: revierte pasos Y versión; la cola queda intacta; '
      'un segundo intento con pasos corregidos migra bien', () async {
    await encolarFila('r1');
    expect(await leerUserVersion(db), 6); // onCreate dejó v6

    // Paso 1 crea una tabla (cambio observable); paso 2 revienta; paso 3 no debería correr.
    final pasosFallidos = <PasoMigracion>[
      (d) => d.customStatement('CREATE TABLE probe_v7 (x INTEGER)'),
      (d) async => throw Exception('falla inyectada en el paso 2'),
      (d) => d.customStatement('CREATE TABLE probe_v7_b (x INTEGER)'),
    ];

    await expectLater(
      migrarAtomico(db, from: 6, to: 7, pasos: pasosFallidos),
      throwsA(isA<Exception>()),
    );

    // user_version NO avanzó.
    expect(await leerUserVersion(db), 6);
    // El cambio del paso 1 se revirtió.
    expect(await existeTabla('probe_v7'), isFalse);
    expect(await existeTabla('probe_v7_b'), isFalse);
    // La fila de la cola sigue intacta, campo por campo.
    final fila = await (db.select(db.syncPendientes)
          ..where((t) => t.id.equals('r1')))
        .getSingle();
    expect(fila.id, 'r1');
    expect(fila.idempotencyKey, 'idem-r1');
    expect(fila.empresaId, 'emp-1');
    expect(fila.usuarioId, 'user-1');
    expect(fila.instalacionId, 'inst-1');
    expect(fila.estado, 'pendiente');
    expect(fila.intentosRed, 2);
    expect(fila.payloadVersion, 1);

    // Segundo intento con pasos corregidos: migra bien.
    final pasosOk = <PasoMigracion>[
      (d) => d.customStatement('CREATE TABLE probe_v7 (x INTEGER)'),
      (d) => d.customStatement('CREATE TABLE probe_v7_b (x INTEGER)'),
    ];
    await migrarAtomico(db, from: 6, to: 7, pasos: pasosOk);
    expect(await leerUserVersion(db), 7);
    expect(await existeTabla('probe_v7'), isTrue);
    expect(await existeTabla('probe_v7_b'), isTrue);
  });

  test('T2 — re-chequeo: si user_version ya está en destino, los pasos NO corren',
      () async {
    var corrio = false;
    // to = 6 y la base ya está en 6: actual >= to → no ejecuta pasos.
    await migrarAtomico(
      db,
      from: 6,
      to: 6,
      pasos: [(d) async => corrio = true],
    );
    expect(corrio, isFalse);
    expect(await leerUserVersion(db), 6);
  });

  test('user_version es transaccional: se revierte con el ROLLBACK', () async {
    try {
      await db.transaction(() async {
        await db.customStatement('PRAGMA user_version = 99');
        throw Exception('forzar rollback');
      });
    } catch (_) {/* esperado */}
    // Si esto diera 99, user_version NO sería transaccional y el diseño caería.
    expect(await leerUserVersion(db), 6);
  });
}
