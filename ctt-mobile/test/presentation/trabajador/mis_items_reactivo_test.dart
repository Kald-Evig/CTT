/// mis_items_reactivo_test.dart — CTT-103 D6-R.
///
/// Reactividad de los indicadores de sync: los Stream `.watch()` de Drift que alimentan
/// la lista (itemsConSyncPendiente / itemsEnRevision) EMITEN una nueva lectura cuando
/// la cola cambia por la MISMA conexión. Acá se prueba a nivel de stream (plain test,
/// async real) porque montar la pantalla con un Stream de Drift en `testWidgets` dispara
/// `!timersPending` (incompatibilidad del binding fake-async con los timers internos de
/// Drift). El render del badge para un estado dado lo cubre mis_items_badge_sync_test.
library;

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:ctt_mobile/core/sync/decision_sync.dart';
import 'package:ctt_mobile/data/local/database.dart';
import 'package:ctt_mobile/domain/enums/enums_ctt.dart';

void main() {
  test('observarIdsPendienteSet y observarEstadoRevisionPorItem reaccionan: '
      'enviando → rechazada apaga la nube y prende el chip (misma conexión)', () async {
    final db = BaseDatosCTT.conConexion(NativeDatabase.memory());
    addTearDown(db.close);

    await db.syncDao.encolar(SyncPendientesCompanion.insert(
      id: 'f1',
      idempotencyKey: 'idem-f1',
      empresaId: 'emp-1',
      usuarioId: 'user-1',
      instalacionId: 'inst-1',
      tipoEntidad: 'item',
      entidadId: 'r',
      accion: 'cambio_estado_item',
      payload: '{}',
      payloadVersion: 1,
      creadoEnDispositivo: DateTime.utc(2026, 1, 1),
      estado: const Value('enviando'),
    ),);

    final pendientes = <Set<String>>[];
    final revision = <Map<String, EstadoSyncLocal>>[];
    final sub1 = db.syncDao.observarIdsPendienteSet().listen(pendientes.add);
    final sub2 = db.syncDao.observarEstadoRevisionPorItem().listen(revision.add);
    addTearDown(sub1.cancel);
    addTearDown(sub2.cancel);

    // 1ª emisión: 'r' está en 'enviando' → aparece como pendiente (nube), sin revisión.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(pendientes.last, {'r'});
    expect(revision.last, isEmpty);

    // La fila pasa a rechazada por la MISMA conexión → los dos streams reemiten.
    await db.syncDao.aplicarDecision(
      'f1',
      estadoEsperado: EstadoSyncLocal.enviando,
      decision: decidir(
        estadoActual: EstadoSyncLocal.enviando,
        senal: SenalSync.rechazadoPorServidor,
      ),
      extra: const SyncPendientesCompanion(rechazoId: Value('rzo-1')),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // La nube se apaga ('r' ya no es pendiente) y aparece el chip (rechazada).
    expect(pendientes.last, isEmpty);
    expect(revision.last, {'r': EstadoSyncLocal.rechazada});
  });

  // EVIDENCIA (CTT-103 D6-R, pregunta final): .watch() de Drift NO detecta escrituras
  // hechas por OTRA conexión a la misma base (p. ej. el isolate headless). NO se
  // resuelve en este commit; solo se documenta.
  test('.watch() NO ve escrituras de otra conexión a la misma base (headless)',
      () async {
    final tmp = Directory.systemTemp.createTempSync('ctt_watch');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final path = '${tmp.path}/db.sqlite';
    void setup(raw.Database d) {
      d.execute('PRAGMA journal_mode=WAL;');
      d.execute('PRAGMA busy_timeout=5000;');
    }

    final dbA = BaseDatosCTT.conConexion(NativeDatabase(File(path), setup: setup));
    final dbB = BaseDatosCTT.conConexion(NativeDatabase(File(path), setup: setup));
    addTearDown(dbA.close);
    addTearDown(dbB.close);

    final emisiones = <Set<String>>[];
    final sub = dbA.syncDao.observarIdsPendienteSet().listen(emisiones.add);
    addTearDown(sub.cancel);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(emisiones.last, isEmpty); // inicial vacío

    // Escribe por la conexión B (simula el isolate headless).
    await dbB.syncDao.encolar(SyncPendientesCompanion.insert(
      id: 'fx',
      idempotencyKey: 'idem-fx',
      empresaId: 'emp-1',
      usuarioId: 'user-1',
      instalacionId: 'inst-1',
      tipoEntidad: 'item',
      entidadId: 'x',
      accion: 'cambio_estado_item',
      payload: '{}',
      payloadVersion: 1,
      creadoEnDispositivo: DateTime.utc(2026, 1, 1),
      estado: const Value('pendiente'),
    ),);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    // El .watch() de A NO reemitió: su StreamQueryStore no recibe notificación de la
    // escritura de B (los streams de Drift son por-conexión).
    expect(emisiones.last, isEmpty,
        reason: 'drift .watch() NO observa writes de otra conexión',);
    // PERO una lectura directa por A SÍ ve la fila (está committeada en el archivo, WAL):
    // es una limitación de NOTIFICACIÓN, no de visibilidad.
    final directo = await dbA.syncDao.filaCrudaParaRescate('fx');
    expect(directo, isNotNull);
  });
}
