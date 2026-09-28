/// apertura_base_test.dart — CTT-130 fase 4.
///
/// T3: pre-apertura con user_version > schemaVersion → BaseMasNuevaException.
/// T4: pre-apertura en UI con migración pendiente → respaldo existe (y pasó quick_check).
/// T5: pre-apertura en headless con migración pendiente → reintentar, sin respaldo.
/// T7: exportación produce un JSON con todas las filas de la cola.
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:ctt_mobile/data/local/apertura_base.dart';
import 'package:ctt_mobile/data/local/database.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('ctt_apertura'));
  tearDown(() => tmp.deleteSync(recursive: true));

  /// Crea una base cruda vacía con el user_version dado.
  String sembrarVersion(int version) {
    final path = '${tmp.path}/seed_v$version.db';
    final s = raw.sqlite3.open(path);
    s.userVersion = version;
    s.dispose();
    return path;
  }

  test('T3 — user_version > schemaVersion → BaseMasNuevaException, sin abrir Drift',
      () async {
    final path = sembrarVersion(7);
    await expectLater(
      preAbrir(path: path, schemaVersion: 6, esIsolateUI: true),
      throwsA(isA<BaseMasNuevaException>()),
    );
  });

  test('T4 — UI con migración pendiente → abrir, y el respaldo existe', () async {
    final path = sembrarVersion(5);
    final accion = await preAbrir(path: path, schemaVersion: 6, esIsolateUI: true);
    expect(accion, AccionApertura.abrir);
    // El respaldo con la versión en el nombre existe (y pasó quick_check, o
    // preAbrir habría lanzado RespaldoInvalidoException).
    expect(File('$path.bak_v5').existsSync(), isTrue);
  });

  test('T5 — headless con migración pendiente → reintentar, sin respaldo', () async {
    final path = sembrarVersion(5);
    final accion = await preAbrir(path: path, schemaVersion: 6, esIsolateUI: false);
    expect(accion, AccionApertura.reintentar);
    expect(File('$path.bak_v5').existsSync(), isFalse);
  });

  test('base al día (== schemaVersion) → abrir', () async {
    final path = sembrarVersion(6);
    final accion = await preAbrir(path: path, schemaVersion: 6, esIsolateUI: true);
    expect(accion, AccionApertura.abrir);
  });

  test('T7 — exportación produce un JSON con todas las filas de la cola', () async {
    final path = '${tmp.path}/con_cola.db';
    final db = BaseDatosCTT.conConexion(NativeDatabase(File(path)));
    Future<void> encolar(String id) => db.syncDao.encolar(
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
          ),
        );
    await encolar('a');
    await encolar('b');
    await db.close(); // suelta el archivo para leerlo con sqlite3 crudo

    final json = exportarColaPendienteJson(path);
    final data = jsonDecode(json) as Map<String, dynamic>;
    final filas = (data['filas'] as List).cast<Map<String, dynamic>>();
    expect(filas, hasLength(2));
    final ids = filas.map((f) => f['id']).toSet();
    expect(ids, {'a', 'b'});
    // Campos clave presentes en el export crudo.
    final a = filas.firstWhere((f) => f['id'] == 'a');
    expect(a['idempotency_key'], 'idem-a');
    expect(a['usuario_id'], 'user-1');
    expect(a['empresa_id'], 'emp-1');
    expect(a['payload_version'], 1);
    expect(a['estado'], 'pendiente');
  });
}
