/// claim_lease_test.dart — CTT-103 I3/I4/A2.
///
/// Claim atómico + lease + cierre condicional, contra Drift REAL:
///  - FIFO por agregado (tipo_entidad, entidad_id): una fila no es elegible si hay
///    otra anterior del mismo ítem en pendiente/enviando/esperando_resolucion.
///  - proximo_intento_en vencido / lease (tomado_hasta) vencido → elegible.
///  - Dos conexiones concurrentes: ninguna fila se toma dos veces, ni fuera de orden.
///  - Cierre condicional: una corrida que perdió el lease no pisa a la que retomó.
library;

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:ctt_mobile/core/sync/decision_sync.dart';
import 'package:ctt_mobile/data/local/daos/sync_dao.dart';
import 'package:ctt_mobile/data/local/database.dart';
import 'package:ctt_mobile/domain/enums/enums_ctt.dart';

void main() {
  late BaseDatosCTT db;
  final ahora = DateTime.utc(2026, 5, 1, 12);
  const lease = Duration(seconds: 90);
  final leaseHasta = ahora.add(lease);

  setUp(() => db = BaseDatosCTT.conConexion(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> insertar(
    SyncDao dao,
    String id,
    String entidad, {
    String estado = 'pendiente',
    DateTime? proximoIntentoEn,
    String? tomadoPor,
    DateTime? tomadoHasta,
    String? conflictoId,
  }) =>
      dao.encolar(SyncPendientesCompanion.insert(
        id: id,
        idempotencyKey: 'idem-$id',
        empresaId: 'emp-1',
        usuarioId: 'user-1',
        instalacionId: 'inst-1',
        tipoEntidad: 'item',
        entidadId: entidad,
        accion: 'cambio_estado_item',
        payload: '{"k":"$id"}',
        payloadVersion: 1,
        creadoEnDispositivo: DateTime.utc(2026, 1, 1),
        estado: Value(estado),
        proximoIntentoEn: Value(proximoIntentoEn),
        tomadoPor: Value(tomadoPor),
        tomadoHasta: Value(tomadoHasta),
        conflictoId: Value(conflictoId),
      ));

  Future<SyncPendiente> leer(SyncDao dao, String id) =>
      (dao.select(dao.syncPendientes)..where((t) => t.id.equals(id))).getSingle();

  // a) A1 pendiente con proximo_intento_en futuro → A2 NO elegible; B1 sí.
  test('a) proximo_intento_en futuro bloquea su agregado; otro ítem sí es elegible',
      () async {
    final dao = db.syncDao;
    await insertar(dao, 'A1', 'item-A',
        proximoIntentoEn: ahora.add(const Duration(hours: 1)),); // seq 1
    await insertar(dao, 'A2', 'item-A'); // seq 2
    await insertar(dao, 'B1', 'item-B'); // seq 3

    final rec = await dao.filasReclamables(ahora);
    expect(rec.map((f) => f.id).toList(), ['B1']);

    expect(await dao.reclamar('A2',
            tomadoPor: 'r', ahora: ahora, tomadoHasta: leaseHasta,),
        isFalse,); // bloqueada por A1 (pendiente, secuencia menor)
    expect(await dao.reclamar('B1',
            tomadoPor: 'r', ahora: ahora, tomadoHasta: leaseHasta,),
        isTrue,);
  });

  // b) A1 en esperando_resolucion → A2 bloqueada.
  test('b) esperando_resolucion bloquea la siguiente del mismo ítem', () async {
    final dao = db.syncDao;
    await insertar(dao, 'A1', 'item-A',
        estado: 'esperando_resolucion', conflictoId: 'c1',); // seq 1
    await insertar(dao, 'A2', 'item-A'); // seq 2
    await insertar(dao, 'B1', 'item-B'); // seq 3

    final rec = await dao.filasReclamables(ahora);
    expect(rec.map((f) => f.id).toList(), ['B1']);
    expect(await dao.reclamar('A2',
            tomadoPor: 'r', ahora: ahora, tomadoHasta: leaseHasta,),
        isFalse,);
  });

  // c) A1 sincronizado (terminal) → A2 elegible.
  test('c) un terminal (sincronizado) NO bloquea la siguiente del mismo ítem',
      () async {
    final dao = db.syncDao;
    await insertar(dao, 'A1', 'item-A', estado: 'sincronizado'); // seq 1
    await insertar(dao, 'A2', 'item-A'); // seq 2

    final rec = await dao.filasReclamables(ahora);
    expect(rec.map((f) => f.id).toList(), ['A2']);
    expect(await dao.reclamar('A2',
            tomadoPor: 'r', ahora: ahora, tomadoHasta: leaseHasta,),
        isTrue,);
  });

  // d) Dos conexiones concurrentes a la misma base: nada se toma dos veces ni fuera
  //    de orden.
  test('d) dos conexiones: ninguna fila se reclama dos veces; A2 no sale antes que A1',
      () async {
    final tmp = Directory.systemTemp.createTempSync('ctt_claim');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final path = '${tmp.path}/claim.db';
    void setup(raw.Database d) {
      d.execute('PRAGMA journal_mode=WAL;');
      d.execute('PRAGMA busy_timeout=5000;');
    }

    final db1 = BaseDatosCTT.conConexion(NativeDatabase(File(path), setup: setup));
    final db2 = BaseDatosCTT.conConexion(NativeDatabase(File(path), setup: setup));
    addTearDown(db1.close);
    addTearDown(db2.close);

    await insertar(db1.syncDao, 'A1', 'item-A'); // seq 1
    await insertar(db1.syncDao, 'A2', 'item-A'); // seq 2
    await insertar(db1.syncDao, 'B1', 'item-B'); // seq 3

    // Las dos corridas intentan A1: exactamente una gana.
    final a1 = [
      await db1.syncDao.reclamar('A1',
          tomadoPor: 'run1', ahora: ahora, tomadoHasta: leaseHasta,),
      await db2.syncDao.reclamar('A1',
          tomadoPor: 'run2', ahora: ahora, tomadoHasta: leaseHasta,),
    ];
    expect(a1.where((x) => x).length, 1);

    // A2 no es reclamable por ninguna: A1 quedó en 'enviando' (bloquea el agregado).
    expect(await db1.syncDao.reclamar('A2',
            tomadoPor: 'run1', ahora: ahora, tomadoHasta: leaseHasta,),
        isFalse,);
    expect(await db2.syncDao.reclamar('A2',
            tomadoPor: 'run2', ahora: ahora, tomadoHasta: leaseHasta,),
        isFalse,);

    // B1 (otro ítem) es independiente: exactamente una lo gana.
    final b1 = [
      await db1.syncDao.reclamar('B1',
          tomadoPor: 'run1', ahora: ahora, tomadoHasta: leaseHasta,),
      await db2.syncDao.reclamar('B1',
          tomadoPor: 'run2', ahora: ahora, tomadoHasta: leaseHasta,),
    ];
    expect(b1.where((x) => x).length, 1);
  });

  // e) Lease vencido → se retoma con la MISMA idempotency_key.
  test('e) lease vencido: la fila se retoma y conserva su idempotency_key', () async {
    final dao = db.syncDao;
    await insertar(dao, 'A1', 'item-A',
        estado: 'enviando',
        tomadoPor: 'viejo',
        tomadoHasta: ahora.subtract(const Duration(minutes: 1)),);
    final idemAntes = (await leer(dao, 'A1')).idempotencyKey;

    expect(await dao.reclamar('A1',
            tomadoPor: 'nuevo', ahora: ahora, tomadoHasta: leaseHasta,),
        isTrue,);
    final f = await leer(dao, 'A1');
    expect(f.tomadoPor, 'nuevo');
    expect(f.idempotencyKey, idemAntes);
  });

  // f) Cierre tardío de la corrida que perdió el lease NO pisa a la que retomó.
  test('f) cierre condicional: la corrida que perdió el lease no pisa el resultado',
      () async {
    final dao = db.syncDao;
    await insertar(dao, 'A1', 'item-A',
        estado: 'enviando',
        tomadoPor: 'run1',
        tomadoHasta: ahora.subtract(const Duration(minutes: 1)),);

    // run2 retoma (lease de run1 vencido).
    expect(await dao.reclamar('A1',
            tomadoPor: 'run2', ahora: ahora, tomadoHasta: leaseHasta,),
        isTrue,);

    // run1, tardío, intenta cerrar: el guard por tomado_por da 0 y no escribe.
    final decisionRun1 = decidir(
      estadoActual: EstadoSyncLocal.enviando,
      senal: SenalSync.fallaTransitoria,
      reintentos: 0,
    );
    final n1 = await dao.aplicarDecision(
      'A1',
      estadoEsperado: EstadoSyncLocal.enviando,
      decision: decisionRun1,
      reintentosActuales: 0,
      tomadoPor: 'run1',
    );
    expect(n1, 0);
    var f = await leer(dao, 'A1');
    expect(f.estado, EstadoSyncLocal.enviando.valor); // intacta
    expect(f.tomadoPor, 'run2');

    // run2 cierra con éxito.
    final decisionRun2 = decidir(
      estadoActual: EstadoSyncLocal.enviando,
      senal: SenalSync.envioOk,
      reintentos: 0,
    );
    final n2 = await dao.aplicarDecision(
      'A1',
      estadoEsperado: EstadoSyncLocal.enviando,
      decision: decisionRun2,
      reintentosActuales: 0,
      tomadoPor: 'run2',
    );
    expect(n2, 1);
    f = await leer(dao, 'A1');
    expect(f.estado, EstadoSyncLocal.sincronizado.valor);
  });

  // g) Lease vigente de otra corrida → no se retoma.
  test('g) lease vigente de otra corrida: no se retoma', () async {
    final dao = db.syncDao;
    await insertar(dao, 'A1', 'item-A',
        estado: 'enviando',
        tomadoPor: 'run1',
        tomadoHasta: ahora.add(const Duration(minutes: 5)),);

    expect(await dao.reclamar('A1',
            tomadoPor: 'run2', ahora: ahora, tomadoHasta: leaseHasta,),
        isFalse,);
    expect((await leer(dao, 'A1')).tomadoPor, 'run1');
  });
}
