/// ctt145_orden_fecha_limite_test.dart — CTT-145: "Mis ítems" se ordena por `fecha_limite`
/// ASC (los sin fecha al final; desempate por nombre y luego por id), y el pull escribe
/// `fecha_limite` respetando la base monótona por `version`.
///
/// Los ítems se crean por el CAMINO REAL del pull (ItemsRepository.obtenerMisItems → dio
/// mockeado con JSON → _jsonACompanion → sincronizarPull), sin insertar filas directamente
/// para el caso de orden. Las filas "migradas" de los casos de relleno/monotonía se siembran
/// como precondición (into().insert), y el pull que las toca va por sincronizarPull.
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
const _empresa = 'emp-1';

void main() {
  late BaseDatosCTT db;
  late ItemsCacheDao cacheDao;
  late _MockDio dio;
  late ItemsRepository repo;

  setUp(() {
    db = BaseDatosCTT.conConexion(NativeDatabase.memory());
    cacheDao = ItemsCacheDao(db);
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
  tearDown(() => db.close());

  // JSON de un ítem de /mis-items (lo que consume _jsonACompanion). `fecha` es el string ISO
  // 'YYYY-MM-DD' o null, TAL CUAL llega del backend (MisItemOut.fecha_limite: date | None).
  Map<String, dynamic> j(String id, String nombre, int version, String? fecha) => {
        'id': id,
        'proyecto_id': 'proy-1',
        'nombre': nombre,
        'asignado_a': _user,
        'estado': 'abierto',
        'version': version,
        'fecha_limite': fecha,
      };

  void mockMisItems(List<Map<String, dynamic>> items) {
    when(() => dio.get<List<dynamic>>('/items/mis-items')).thenAnswer(
      (_) async => Response<List<dynamic>>(
        requestOptions: RequestOptions(path: '/items/mis-items'),
        data: items,
      ),
    );
  }

  // Siembra una fila "migrada" (precondición): existe antes del pull, con version y
  // fecha_limite dadas. Simula una fila que venía de v8 (migrada a v9 con fecha_limite NULL)
  // o ya cacheada por un pull previo.
  Future<void> sembrarFila(String id,
          {required int version, String? fecha, String nombre = 'Item'}) =>
      db.into(db.itemsCacheTable).insert(ItemsCacheTableCompanion.insert(
            id: id,
            proyectoId: 'proy-1',
            nombre: nombre,
            asignadoA: const Value(_user),
            empresaId: const Value(_empresa),
            estadoServidor: 'abierto',
            version: Value(version),
            fechaLimite: Value(fecha),
            cachadoEn: DateTime.utc(2026, 5, 1),
          ));

  // ── Orden (camino real del pull) ─────────────────────────────────────────────
  test('orden: fecha ASC, NULL al final, desempate por nombre y luego por id', () async {
    // Entregados en orden ARBITRARIO; se espera que la lista salga ordenada por el ORDER BY.
    mockMisItems([
      j('c1', 'C', 1, '2026-01-10'),
      j('z1', 'Z', 1, null),
      j('a2', 'A', 1, '2026-01-05'), // misma fecha+nombre que a1 → desempate por id
      j('b1', 'B', 1, '2026-01-05'), // misma fecha que a1/a2, nombre posterior
      j('m1', 'M', 1, null),         // sin fecha → al final, antes que z1 por nombre
      j('a1', 'A', 1, '2026-01-05'),
    ]);

    await repo.obtenerMisItems(_user, _empresa);

    final lista = await cacheDao.observarAsignadosConOverlay(_user, _empresa).first;
    expect(
      lista.map((e) => e.id).toList(),
      ['a1', 'a2', 'b1', 'c1', 'm1', 'z1'],
      reason: 'fecha asc; empatada por fecha → nombre → id; nulos al final por nombre',
    );
  });

  // ── Relleno de fecha_limite con version igual ────────────────────────────────
  test('pull con version IGUAL rellena fecha_limite sobre una fila migrada', () async {
    // Fila migrada: version=1, fecha_limite NULL (como queda tras la migración v8→v9).
    await sembrarFila('mg', version: 1, fecha: null, nombre: 'Migrado');
    expect((await cacheDao.obtenerPorId('mg'))!.fechaLimite, isNull);

    // El pull trae la MISMA version (1) y una fecha. La base monótona permite igual (no es menor)
    // → se escribe fecha_limite.
    mockMisItems([j('mg', 'Migrado', 1, '2026-02-01')]);
    await repo.obtenerMisItems(_user, _empresa);

    final fila = await cacheDao.obtenerPorId('mg');
    expect(fila!.fechaLimite, '2026-02-01');
    expect(fila.version, 1);
  });

  // ── Monotonía: version local mayor no pisa (ni la fecha) ──────────────────────
  test('pull con version local MAYOR no pisa la fila (incluida fecha_limite)', () async {
    // Fila local más nueva: version=5, fecha_limite "2026-05-05".
    await sembrarFila('hi', version: 5, fecha: '2026-05-05', nombre: 'Nuevo');

    // Pull viejo: version=3 y otra fecha. version local (5) > entrante (3) → NO se pisa nada.
    mockMisItems([j('hi', 'Nuevo', 3, '2026-03-03')]);
    await repo.obtenerMisItems(_user, _empresa);

    final fila = await cacheDao.obtenerPorId('hi');
    expect(fila!.version, 5, reason: 'base monótona: no baja la version');
    expect(fila.fechaLimite, '2026-05-05', reason: 'no se pisa la fecha con un pull viejo');
  });
}
