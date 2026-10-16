/// espera_fila_test.dart — CTT-148: SyncDao.esperarResultadoFila espera el PRIMER
/// intento de una fila por id. Completa al salir de `enviando`; `pendiente` sin intento
/// NO resuelve (espera el timeout → pendiente sin error).
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ctt_mobile/data/local/daos/sync_dao.dart';
import 'package:ctt_mobile/data/local/database.dart';
import 'package:ctt_mobile/domain/enums/enums_ctt.dart';

void main() {
  late BaseDatosCTT db;
  setUp(() => db = BaseDatosCTT.conConexion(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> encolar(String id, String estado) =>
      db.syncDao.encolar(SyncPendientesCompanion.insert(
        id: id,
        idempotencyKey: 'idem-$id',
        empresaId: 'emp-1',
        usuarioId: 'user-1',
        instalacionId: 'inst-1',
        tipoEntidad: 'item',
        entidadId: 'item-$id',
        accion: 'cambio_estado_item',
        payload: '{"nuevo_estado":"en_progreso"}',
        payloadVersion: 1,
        creadoEnDispositivo: DateTime.utc(2026, 1, 1),
        estado: Value(estado),
      ));

  Future<void> mover(String id, SyncPendientesCompanion cambios) =>
      (db.update(db.syncPendientes)..where((t) => t.id.equals(id))).write(cambios);

  test('sale de enviando → sincronizado: devuelve sincronizado', () async {
    await encolar('r', 'enviando');
    final fut = db.syncDao
        .esperarResultadoFila('r', timeout: const Duration(seconds: 2));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await mover('r', const SyncPendientesCompanion(estado: Value('sincronizado')));
    final res = await fut;
    expect(res.estado, EstadoSyncLocal.sincronizado);
    expect(res.ultimoErrorCodigo, isNull);
  });

  test('sale de enviando → esperando_resolucion: lo devuelve', () async {
    await encolar('c', 'enviando');
    final fut = db.syncDao
        .esperarResultadoFila('c', timeout: const Duration(seconds: 2));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await mover('c',
        const SyncPendientesCompanion(estado: Value('esperando_resolucion')),);
    expect((await fut).estado, EstadoSyncLocal.esperandoResolucion);
  });

  test('pendiente TRAS un intento (bounce) → pendiente + codigo + error', () async {
    await encolar('p', 'enviando');
    final fut = db.syncDao
        .esperarResultadoFila('p', timeout: const Duration(seconds: 2));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    // fallaServidor: vuelve a pendiente con intento registrado y error del backend.
    await mover(
      'p',
      SyncPendientesCompanion(
        estado: const Value('pendiente'),
        ultimoIntentoEn: Value(DateTime.utc(2026, 5, 1, 12)),
        ultimoErrorCodigo: const Value(422),
        ultimoError: const Value('payload invalido'),
      ),
    );
    final res = await fut;
    expect(res.estado, EstadoSyncLocal.pendiente);
    expect(res.ultimoErrorCodigo, 422);
    expect(res.ultimoError, 'payload invalido');
  });

  test('timeout sin intento (pendiente, nunca enviado) → pendiente sin error',
      () async {
    await encolar('q', 'pendiente'); // nunca se reclama; sin ultimo_intento_en
    final res = await db.syncDao
        .esperarResultadoFila('q', timeout: const Duration(milliseconds: 150));
    expect(res.estado, EstadoSyncLocal.pendiente);
    expect(res.ultimoErrorCodigo, isNull);
    expect(res.ultimoError, isNull);
  });
}
