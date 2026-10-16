/// items_cache_overlay_test.dart — CTT-144: estado mostrado = base + overlay.
///
/// El overlay toma el `nuevo_estado` de la última fila `pendiente`/`enviando` del ítem
/// (estadosIntencionLocal); `esperandoResolucion` y las terminales NO entran (se muestra
/// la base). Drift real en memoria; json_extract sobre el payload.
library;

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ctt_mobile/data/local/database.dart';

void main() {
  late BaseDatosCTT db;
  setUp(() => db = BaseDatosCTT.conConexion(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> cache(String id, String estado, {String asignadoA = 'user-1'}) =>
      db.into(db.itemsCacheTable).insert(ItemsCacheTableCompanion.insert(
            id: id,
            proyectoId: 'proy-1',
            nombre: 'Tarea $id',
            asignadoA: Value(asignadoA),
            estado: estado,
            updatedAt: DateTime.utc(2026, 5, 1),
            cachadoEn: DateTime.utc(2026, 5, 1),
          ));

  // Inserta una fila de cola para [entidadId] con el `nuevo_estado` dado. `id` controla
  // la secuencia (autoincremental) por orden de inserción.
  Future<void> cola(String id, String entidadId, String estadoFila,
          String nuevoEstado) =>
      db.into(db.syncPendientes).insert(SyncPendientesCompanion.insert(
            id: id,
            idempotencyKey: 'idem-$id',
            empresaId: 'emp-1',
            usuarioId: 'user-1',
            instalacionId: 'inst-1',
            tipoEntidad: 'item',
            entidadId: entidadId,
            accion: 'cambio_estado_item',
            payload: '{"nuevo_estado":"$nuevoEstado"}',
            payloadVersion: 1,
            creadoEnDispositivo: DateTime.utc(2026, 1, 1),
            estado: Value(estadoFila),
          ));

  Future<String?> estadoMostrado(String id) async =>
      (await db.itemsCacheDao.observarPorIdConOverlay(id).first)?.estado;

  test('sin filas en la cola → muestra la base', () async {
    await cache('A', 'abierto');
    expect(await estadoMostrado('A'), 'abierto');
  });

  test('fila pendiente → muestra su nuevo_estado (overlay)', () async {
    await cache('B', 'abierto');
    await cola('b1', 'B', 'pendiente', 'en_progreso');
    expect(await estadoMostrado('B'), 'en_progreso');
  });

  test('fila enviando → también cuenta como intención local', () async {
    await cache('C', 'abierto');
    await cola('c1', 'C', 'enviando', 'pendiente_revision');
    expect(await estadoMostrado('C'), 'pendiente_revision');
  });

  test('gana la ÚLTIMA (mayor secuencia) entre pendiente/enviando', () async {
    await cache('D', 'abierto');
    await cola('d1', 'D', 'pendiente', 'en_progreso');
    await cola('d2', 'D', 'pendiente', 'pendiente_revision'); // secuencia mayor
    expect(await estadoMostrado('D'), 'pendiente_revision');
  });

  test('solo esperando_resolucion → muestra la base (overlay la excluye)', () async {
    await cache('E', 'en_progreso');
    await cola('e1', 'E', 'esperando_resolucion', 'pendiente_revision');
    expect(await estadoMostrado('E'), 'en_progreso');
  });

  test('solo filas terminales → muestra la base', () async {
    await cache('F', 'abierto');
    await cola('f1', 'F', 'sincronizado', 'en_progreso');
    await cola('f2', 'F', 'rechazada', 'pendiente_revision');
    expect(await estadoMostrado('F'), 'abierto');
  });

  test('pendiente gana aunque haya una terminal posterior de otra intención', () async {
    // f terminal (sec 1) + pendiente vigente (sec 2): manda la pendiente.
    await cache('G', 'abierto');
    await cola('g1', 'G', 'sincronizado', 'en_progreso');
    await cola('g2', 'G', 'pendiente', 'pendiente_revision');
    expect(await estadoMostrado('G'), 'pendiente_revision');
  });

  test('lista por usuario: overlay aplicado a cada ítem, base cuando no hay cola',
      () async {
    await cache('H', 'abierto');
    await cache('I', 'abierto');
    await cola('h1', 'H', 'pendiente', 'en_progreso');
    final lista = await db.itemsCacheDao.observarAsignadosConOverlay('user-1').first;
    final porId = {for (final it in lista) it.id: it.estado};
    expect(porId['H'], 'en_progreso'); // overlay
    expect(porId['I'], 'abierto'); // base
  });
}
