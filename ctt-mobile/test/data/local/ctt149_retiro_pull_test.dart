/// ctt149_retiro_pull_test.dart — CTT-149: el pull completo de /mis-items retira de
/// items_cache los ítems del usuario que ya no vinieron, EXCEPTO los que tienen filas no
/// terminales en sync_pendientes (se retiran cuando la cola termina). Solo en el camino
/// 200; un pull fallido (DioException) no retira nada.
library;

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:ctt_mobile/core/device/device_id_service.dart';
import 'package:ctt_mobile/core/security/secure_storage_service.dart';
import 'package:ctt_mobile/core/sync/transicion_service.dart';
import 'package:ctt_mobile/data/local/daos/items_cache_dao.dart';
import 'package:ctt_mobile/data/local/daos/sync_dao.dart';
import 'package:ctt_mobile/data/local/database.dart';
import 'package:ctt_mobile/data/repositories/items_repository.dart';

class _MockDio extends Mock implements Dio {}

class _MockDeviceIdService extends Mock implements DeviceIdService {}

class _MockSecureStorage extends Mock implements SecureStorageService {}

const _user = 'user-1';

void main() {
  late BaseDatosCTT db;
  late ItemsCacheDao cacheDao;
  setUp(() {
    db = BaseDatosCTT.conConexion(NativeDatabase.memory());
    cacheDao = ItemsCacheDao(db);
  });
  tearDown(() => db.close());

  Future<void> cache(String id,
          {String asignadoA = _user,
          String estado = 'abierto',
          String empresaId = 'emp-1'}) =>
      db.into(db.itemsCacheTable).insert(ItemsCacheTableCompanion.insert(
            id: id,
            proyectoId: 'proy-1',
            nombre: 'Item $id',
            asignadoA: Value(asignadoA),
            empresaId: Value(empresaId),
            estadoServidor: estado,
            updatedAt: DateTime.utc(2026, 5, 1),
            cachadoEn: DateTime.utc(2026, 5, 1),
          ));

  // El companion del pull NO trae empresa_id: sincronizarPull lo estampa (opción A).
  ItemsCacheTableCompanion comp(String id, {String asignadoA = _user}) =>
      ItemsCacheTableCompanion.insert(
        id: id,
        proyectoId: 'proy-1',
        nombre: 'Item $id',
        asignadoA: Value(asignadoA),
        estadoServidor: 'abierto',
        updatedAt: DateTime.utc(2026, 5, 2),
        cachadoEn: DateTime.utc(2026, 5, 2),
      );

  Future<void> cola(String id, String entidadId, String estadoFila) =>
      db.syncDao.encolar(SyncPendientesCompanion.insert(
        id: id,
        idempotencyKey: 'idem-$id',
        empresaId: 'emp-1',
        usuarioId: _user,
        instalacionId: 'inst-1',
        tipoEntidad: 'item',
        entidadId: entidadId,
        accion: 'cambio_estado_item',
        payload: '{"nuevo_estado":"en_progreso"}',
        payloadVersion: 1,
        creadoEnDispositivo: DateTime.utc(2026, 1, 1),
        estado: Value(estadoFila),
      ));

  Future<Set<String>> idsEnCache() async =>
      (await db.select(db.itemsCacheTable).get()).map((r) => r.id).toSet();

  test('retira el ítem ausente sin cola; conserva los presentes', () async {
    await cache('A');
    await cache('B');
    await cache('C'); // será reasignado → no viene en el pull
    await cacheDao.sincronizarPull(_user, 'emp-1', [comp('A'), comp('B')]);
    expect(await idsEnCache(), {'A', 'B'}); // C retirado
  });

  test('conserva el ausente con fila NO terminal; lo retira al terminar la cola',
      () async {
    await cache('A');
    await cache('C');
    await cola('c1', 'C', 'pendiente'); // C tiene cola no terminal
    await cacheDao.sincronizarPull(_user, 'emp-1', [comp('A')]);
    expect(await idsEnCache(), {'A', 'C'}, reason: 'C se conserva: cola pendiente');

    // La cola de C termina (sincronizado) → el siguiente pull sí lo retira.
    await (db.update(db.syncPendientes)..where((t) => t.id.equals('c1')))
        .write(const SyncPendientesCompanion(estado: Value('sincronizado')));
    await cacheDao.sincronizarPull(_user, 'emp-1', [comp('A')]);
    expect(await idsEnCache(), {'A'}, reason: 'C retirado al terminar su cola');
  });

  test('esperando_resolucion también conserva (no terminal)', () async {
    await cache('A');
    await cache('C');
    await cola('c1', 'C', 'esperando_resolucion');
    await cacheDao.sincronizarPull(_user, 'emp-1', [comp('A')]);
    expect(await idsEnCache(), {'A', 'C'});
  });

  test('no toca ítems de OTRO usuario ausentes del pull', () async {
    await cache('A');
    await cache('X', asignadoA: 'user-2'); // de otro usuario, no asignado a user-1
    await cacheDao.sincronizarPull(_user, 'emp-1', [comp('A')]);
    expect(await idsEnCache(), {'A', 'X'}, reason: 'X es de user-2, no se retira');
  });

  // ── Opción A (multiempresa, CTT-143 §6c) ────────────────────────────────────

  test('un pull en la empresa B no retira ítems de la empresa A (mismo usuario)',
      () async {
    await cache('A', empresaId: 'emp-A');
    await cache('B', empresaId: 'emp-B');
    // Pull de la empresa B (solo trae B). A es de emp-A: fuera del scope del retiro.
    await cacheDao.sincronizarPull(_user, 'emp-B', [comp('B')]);
    expect(await idsEnCache(), {'A', 'B'},
        reason: 'A (emp-A) no se retira en un pull de emp-B');
  });

  test('la lista (overlay) de la empresa A no muestra ítems de la empresa B', () async {
    await cache('A', empresaId: 'emp-A');
    await cache('B', empresaId: 'emp-B');
    final lista = await cacheDao.observarAsignadosConOverlay(_user, 'emp-A').first;
    expect(lista.map((e) => e.id).toSet(), {'A'},
        reason: 'el listado filtra por la empresa activa');
  });

  group('repositorio — solo retira en 200', () {
    late _MockDio dio;
    late ItemsRepository repo;
    setUp(() {
      dio = _MockDio();
      final dev = _MockDeviceIdService();
      final sec = _MockSecureStorage();
      repo = ItemsRepository(
        dio: dio,
        cacheDao: cacheDao,
        syncDao: SyncDao(db),
        deviceIdService: dev,
        transicionService: TransicionService(
          syncDao: SyncDao(db),
          deviceIdService: dev,
          secureStorage: sec,
          dispararCiclo: () async {},
        ),
      );
    });

    test('pull fallido (DioException) NO retira nada', () async {
      await cache('A');
      await cache('C');
      when(() => dio.get<List<dynamic>>('/items/mis-items')).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/items/mis-items'),
          type: DioExceptionType.connectionError,
        ),
      );
      await repo.obtenerMisItems(_user, 'emp-1');
      expect(await idsEnCache(), {'A', 'C'}, reason: 'sin 200 no se retira');
    });

    test('pull 200 sin C → C se retira', () async {
      await cache('A');
      await cache('C');
      when(() => dio.get<List<dynamic>>('/items/mis-items')).thenAnswer(
        (_) async => Response<List<dynamic>>(
          requestOptions: RequestOptions(path: '/items/mis-items'),
          data: [
            {'id': 'A', 'proyecto_id': 'proy-1', 'nombre': 'Item A', 'asignado_a': _user, 'estado': 'abierto'},
          ],
        ),
      );
      await repo.obtenerMisItems(_user, 'emp-1');
      expect(await idsEnCache(), {'A'});
    });
  });
}
