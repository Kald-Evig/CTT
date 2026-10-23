/// ctt143_version_base_encolar_test.dart — CTT-143 C2 / D7: version_base al encolar.
///
/// - encolarConVersionBase estampa version_base = items_cache.version (de la base), en la
///   misma transacción; version NULL → NO encola (nunca 0 ni inventado).
/// - transicion_service.ejecutar con version NULL lanza VersionBaseNoDisponibleException y
///   no toca la cola ni dispara el ciclo.
/// - El ciclo (cola) pone version_base en el CUERPO del POST (D7).
library;

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:ctt_mobile/core/device/device_id_service.dart';
import 'package:ctt_mobile/core/security/secure_storage_service.dart';
import 'package:ctt_mobile/core/sync/ciclo_sync.dart';
import 'package:ctt_mobile/core/sync/transicion_service.dart';
import 'package:ctt_mobile/data/local/database.dart';

class _MockDio extends Mock implements Dio {}

class _MockDeviceIdService extends Mock implements DeviceIdService {}

class _MockSecureStorage extends Mock implements SecureStorageService {}

void main() {
  setUpAll(() => registerFallbackValue(Options()));

  late BaseDatosCTT db;
  setUp(() => db = BaseDatosCTT.conConexion(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> cache(String id, {int? version}) =>
      db.into(db.itemsCacheTable).insert(ItemsCacheTableCompanion.insert(
            id: id,
            proyectoId: 'p1',
            nombre: 'Item $id',
            asignadoA: const Value('user-1'),
            empresaId: const Value('emp-1'),
            estadoServidor: 'abierto',
            version: Value(version),
            updatedAt: DateTime.utc(2026, 5, 1),
            cachadoEn: DateTime.utc(2026, 5, 1),
          ));

  SyncPendientesCompanion compFila(String id, String entidadId) =>
      SyncPendientesCompanion.insert(
        id: id,
        idempotencyKey: 'idem-$id',
        empresaId: 'emp-1',
        usuarioId: 'user-1',
        instalacionId: 'inst-1',
        tipoEntidad: 'item',
        entidadId: entidadId,
        accion: 'cambio_estado_item',
        payload: '{"nuevo_estado":"en_progreso"}',
        payloadVersion: 1,
        creadoEnDispositivo: DateTime.utc(2026, 1, 1),
      );

  // ── DAO: encolarConVersionBase ──────────────────────────────────────────────

  test('encolarConVersionBase estampa version_base desde items_cache.version', () async {
    // Arma: una base con version=7. Verifica: la fila encolada lleva versionBase=7 (de la
    // base, no inventado), y encolarConVersionBase devuelve true.
    await cache('A', version: 7);
    final ok = await db.syncDao.encolarConVersionBase(compFila('f1', 'A'), 'A');
    expect(ok, isTrue);
    final fila = await (db.select(db.syncPendientes)..where((t) => t.id.equals('f1')))
        .getSingle();
    expect(fila.versionBase, 7);
  });

  test('version NULL → NO encola y devuelve false (nunca 0 ni inventado)', () async {
    // Arma: una base con version NULL (ítem migrado de v7 sin re-pull). Verifica: no encola
    // (false, cero filas).
    await cache('B');
    final ok = await db.syncDao.encolarConVersionBase(compFila('f2', 'B'), 'B');
    expect(ok, isFalse);
    expect(await db.select(db.syncPendientes).get(), isEmpty);
  });

  // ── transicion_service: version NULL → excepción, sin tocar la cola ─────────

  test('ejecutar con version NULL lanza VersionBaseNoDisponibleException, NO encola ni '
      'dispara el ciclo', () async {
    // Arma: sesión válida (mocks) + base con version NULL. Verifica: lanza la excepción,
    // la cola queda vacía y el ciclo NO se dispara.
    await cache('C');
    final sec = _MockSecureStorage();
    final dev = _MockDeviceIdService();
    when(() => sec.obtenerUsuarioId()).thenAnswer((_) async => 'user-1');
    when(() => sec.obtenerEmpresaId()).thenAnswer((_) async => 'emp-1');
    when(() => dev.obtener()).thenAnswer((_) async => 'inst-1');
    var disparado = false;
    final svc = TransicionService(
      syncDao: db.syncDao,
      deviceIdService: dev,
      secureStorage: sec,
      dispararCiclo: () async => disparado = true,
    );

    await expectLater(
      svc.ejecutar(itemId: 'C', nuevoEstado: 'en_progreso'),
      throwsA(isA<VersionBaseNoDisponibleException>()),
    );
    expect(await db.select(db.syncPendientes).get(), isEmpty);
    expect(disparado, isFalse);
  });

  // ── ciclo (cola): el POST lleva version_base (D7) ───────────────────────────

  test('ninguna ruta envía el payload sin version_base: el ciclo lo pone en el cuerpo del '
      'POST', () async {
    // Arma: base con version=3 y una fila encolada por encolarConVersionBase (versionBase=3).
    // Verifica: el cuerpo del POST capturado trae version_base=3.
    await cache('D', version: 3);
    await db.syncDao.encolarConVersionBase(compFila('f3', 'D'), 'D');
    final dio = _MockDio();
    final dev = _MockDeviceIdService();
    when(() => dev.obtener()).thenAnswer((_) async => 'inst-1');
    when(() => dio.get<List<dynamic>>(any())).thenThrow(DioException(
        requestOptions: RequestOptions(path: '/m'),
        type: DioExceptionType.connectionError));
    when(() => dio.post<Map<String, dynamic>>(any(),
            data: any(named: 'data'), options: any(named: 'options')))
        .thenAnswer((_) async => Response<Map<String, dynamic>>(
              requestOptions: RequestOptions(path: '/items/D/transicion'),
              data: {'id': 'D', 'estado': 'en_progreso'},
            ));

    final ciclo = CicloSync(
      syncDao: db.syncDao,
      dio: dio,
      deviceIdService: dev,
      isolateLabel: 'test',
      reloj: () => DateTime.utc(2026, 5, 1, 12),
    );
    await ciclo.ejecutar();

    final capt = verify(() => dio.post<Map<String, dynamic>>(any(),
        data: captureAny(named: 'data'), options: any(named: 'options'))).captured;
    final body = capt.first as Map<String, dynamic>;
    expect(body['version_base'], 3);
  });
}
