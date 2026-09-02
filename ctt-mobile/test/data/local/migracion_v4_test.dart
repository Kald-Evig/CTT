/// migracion_v4_test.dart — CTT-117 tramo 2 (+ CTT-103 pto 4).
///
/// Demuestra que la migración a v4 cubre el 100% de las filas desde CUALQUIER
/// versión de origen (v1, v2, v3), no solo la inmediata anterior: un dispositivo
/// que se salteó actualizaciones migra de v1/v2 directo a v4. El patrón
/// `if (desde < N)` encadenado debería cubrirlo — acá se DEMUESTRA, no se supone.
///
/// El criterio central: tras migrar, EstadoSyncLocal.fromString / MotivoSync.fromString
/// no lanzan sobre NINGUNA fila (riesgo 6: un valor viejo sin mapear reventaría la
/// primera lectura).
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:ctt_mobile/data/local/database.dart';
import 'package:ctt_mobile/domain/enums/enums_ctt.dart';

/// DDL de `sync_pendientes` e `items_cache` tal como existían en cada versión.
/// Solo las columnas presentes en esa versión; la migración agrega el resto.
void _crearEsquema(raw.Database db, int version) {
  // sync_pendientes — columnas base (v1). idempotency_key llega en v3.
  db.execute('''
    CREATE TABLE sync_pendientes (
      id TEXT NOT NULL PRIMARY KEY,
      tipo_entidad TEXT NOT NULL,
      entidad_id TEXT NOT NULL,
      accion TEXT NOT NULL,
      payload TEXT NOT NULL,
      timestamp_dispositivo INTEGER NOT NULL,
      dispositivo_id TEXT NOT NULL,
      reintentos INTEGER NOT NULL DEFAULT 0,
      estado TEXT NOT NULL DEFAULT 'pendiente',
      ultimo_error TEXT
      ${version >= 3 ? ", idempotency_key TEXT" : ""}
    )''');

  // items_cache — proyecto_nombre llega en v2.
  db.execute('''
    CREATE TABLE items_cache (
      id TEXT NOT NULL PRIMARY KEY,
      proyecto_id TEXT NOT NULL,
      ${version >= 2 ? "proyecto_nombre TEXT NOT NULL DEFAULT '', " : ""}
      parent_item_id TEXT,
      nivel_profundidad INTEGER NOT NULL DEFAULT 0,
      nombre TEXT NOT NULL,
      descripcion TEXT,
      asignado_a TEXT,
      estado TEXT NOT NULL,
      estado_previo TEXT,
      updated_at INTEGER NOT NULL,
      cachado_en INTEGER NOT NULL
    )''');

  // usuario_activo — no la toca la migración, pero se crea para reflejar una BD real.
  db.execute('''
    CREATE TABLE usuario_activo (
      id TEXT NOT NULL PRIMARY KEY,
      firebase_uid TEXT NOT NULL,
      nombre_completo TEXT NOT NULL,
      email TEXT NOT NULL,
      rol_actual TEXT NOT NULL,
      empresa_id TEXT NOT NULL,
      empresa_nombre TEXT NOT NULL,
      es_super_admin INTEGER NOT NULL DEFAULT 0
    )''');

  db.execute('PRAGMA user_version = $version');
}

/// Inserta una fila en sync_pendientes con el estado viejo dado.
void _insertarSync(
  raw.Database db, {
  required String id,
  required String estado,
  int reintentos = 0,
  String? ultimoError,
  String entidadId = 'item-x',
}) {
  db.execute(
    "INSERT INTO sync_pendientes (id, tipo_entidad, entidad_id, accion, payload, "
    "timestamp_dispositivo, dispositivo_id, reintentos, estado, ultimo_error) "
    "VALUES (?, 'item', ?, 'cambio_estado_item', '{}', 0, 'dev', ?, ?, ?)",
    [id, entidadId, reintentos, estado, ultimoError],
  );
}

void _insertarItem(raw.Database db, String id) {
  db.execute(
    "INSERT INTO items_cache (id, proyecto_id, nombre, estado, updated_at, cachado_en) "
    "VALUES (?, 'p1', 'Tarea', 'abierto', 0, 0)",
    [id],
  );
}

/// Abre la BD pre-sembrada con Drift (dispara la migración a v4) y devuelve las
/// filas de sync_pendientes ya migradas.
Future<List<Map<String, Object?>>> _migrarYleer(String path) async {
  final db = BaseDatosCTT.conConexion(NativeDatabase(File(path)));
  try {
    final filas = await db
        .customSelect('SELECT id, estado, motivo, conflicto_id, reintentos, '
            'acknowledged FROM sync_pendientes ORDER BY id')
        .get();
    return filas.map((r) => r.data).toList();
  } finally {
    await db.close();
  }
}

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('ctt_mig'));
  tearDown(() => tmp.deleteSync(recursive: true));

  /// Verifica que NINGÚN estado/motivo resultante rompa fromString.
  void assertSinValoresHuerfanos(List<Map<String, Object?>> filas) {
    for (final f in filas) {
      final estado = f['estado'] as String;
      expect(() => EstadoSyncLocal.fromString(estado), returnsNormally,
          reason: 'estado "$estado" quedó sin mapear (fila ${f['id']})',);
      final motivo = f['motivo'] as String?;
      if (motivo != null) {
        expect(() => MotivoSync.fromString(motivo), returnsNormally,
            reason: 'motivo "$motivo" inválido (fila ${f['id']})',);
      }
    }
  }

  test('desde v3 (con filas en los SEIS estados viejos) → v4 sin huérfanos', () async {
    final path = '${tmp.path}/v3.db';
    final seed = raw.sqlite3.open(path);
    _crearEsquema(seed, 3);
    _insertarSync(seed, id: 'a', estado: 'pendiente');
    _insertarSync(seed, id: 'b', estado: 'enviando');
    _insertarSync(seed, id: 'c', estado: 'sincronizado');
    _insertarSync(seed, id: 'd', estado: 'error', reintentos: 1);
    _insertarSync(seed, id: 'e', estado: 'error', reintentos: 5); // agotado
    _insertarSync(seed, id: 'f', estado: 'rechazado');
    _insertarSync(seed, id: 'g', estado: 'conflicto',
        ultimoError: 'conflicto_id:abc-123', entidadId: 'item-conf',);
    _insertarItem(seed, 'item-conf');
    seed.dispose();

    final filas = await _migrarYleer(path);
    assertSinValoresHuerfanos(filas);

    Map<String, Object?> row(String id) => filas.firstWhere((f) => f['id'] == id);

    // Mapeos puntuales.
    expect(row('a')['estado'], 'pendiente');
    expect(row('b')['estado'], 'pendiente'); // enviando huérfano rescatado
    expect(row('c')['estado'], 'sincronizado');
    expect(row('d')['estado'], 'pendiente');
    expect(row('d')['motivo'], 'error_transitorio');
    expect(row('e')['estado'], 'descartado'); // fix CTT-103
    expect(row('e')['motivo'], 'reintentos_agotados');
    expect(row('f')['estado'], 'descartado');
    expect(row('f')['motivo'], 'rechazo_negocio');
    expect(row('g')['estado'], 'esperando_resolucion');
    expect(row('g')['motivo'], 'conflicto');
    expect(row('g')['conflicto_id'], 'abc-123'); // rescatado de ultimo_error

    // acknowledged = false (0) en TODAS las heredadas (decisión 5).
    expect(filas.every((f) => f['acknowledged'] == 0), isTrue);

    // El flag del ítem conflictuado quedó marcado.
    final db2 = BaseDatosCTT.conConexion(NativeDatabase(File(path)));
    try {
      final item = await db2
          .customSelect("SELECT tiene_conflicto FROM items_cache "
              "WHERE id = 'item-conf'")
          .getSingle();
      expect(item.data['tiene_conflicto'], 1);
    } finally {
      await db2.close();
    }
  });

  test('desde v2 → v4 sin huérfanos (salta idempotency_key + v4)', () async {
    final path = '${tmp.path}/v2.db';
    final seed = raw.sqlite3.open(path);
    _crearEsquema(seed, 2);
    _insertarSync(seed, id: 'a', estado: 'conflicto',
        ultimoError: 'conflicto_id:xyz',);
    _insertarSync(seed, id: 'b', estado: 'error', reintentos: 9);
    _insertarSync(seed, id: 'c', estado: 'rechazado');
    seed.dispose();

    final filas = await _migrarYleer(path);
    assertSinValoresHuerfanos(filas);
    expect(filas.firstWhere((f) => f['id'] == 'a')['conflicto_id'], 'xyz');
    expect(filas.firstWhere((f) => f['id'] == 'b')['estado'], 'descartado');
  });

  test('desde v1 → v4 sin huérfanos (salta proyecto_nombre + idempotency_key + v4)',
      () async {
    final path = '${tmp.path}/v1.db';
    final seed = raw.sqlite3.open(path);
    _crearEsquema(seed, 1);
    _insertarSync(seed, id: 'a', estado: 'pendiente');
    _insertarSync(seed, id: 'b', estado: 'conflicto',
        ultimoError: 'conflicto_id:qwe',);
    _insertarSync(seed, id: 'c', estado: 'error', reintentos: 2);
    seed.dispose();

    final filas = await _migrarYleer(path);
    assertSinValoresHuerfanos(filas);
    expect(filas.firstWhere((f) => f['id'] == 'b')['estado'],
        'esperando_resolucion',);
    expect(filas.firstWhere((f) => f['id'] == 'c')['motivo'],
        'error_transitorio',);
  });
}
