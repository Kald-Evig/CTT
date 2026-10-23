/// ctt143_rebase_base_test.dart — CTT-143 C3 (a) rebase al 200 y (b) base monótona.
///
/// - R3bis (Trabajador y Residente): dos transiciones offline del mismo ítem; el 200 de la
///   primera devuelve version+1 y la SEGUNDA sale con la version_base REBASEADA (no fijada a
///   mano: sale del rebase sobre sync_pendientes.version_base).
/// - Una fila con otro version_base NO se rebasea.
/// - Base monótona: una version vieja (del 200 o del pull) NO pisa la base cacheada.
library;

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:ctt_mobile/core/device/device_id_service.dart';
import 'package:ctt_mobile/core/sync/ciclo_sync.dart';
import 'package:ctt_mobile/data/local/database.dart';
import 'package:ctt_mobile/domain/enums/enums_ctt.dart';

class _MockDio extends Mock implements Dio {}

class _MockDeviceIdService extends Mock implements DeviceIdService {}

void main() {
  setUpAll(() => registerFallbackValue(Options()));

  late BaseDatosCTT db;
  late _MockDio dio;
  late _MockDeviceIdService dev;
  setUp(() {
    db = BaseDatosCTT.conConexion(NativeDatabase.memory());
    dio = _MockDio();
    dev = _MockDeviceIdService();
    when(() => dev.obtener()).thenAnswer((_) async => 'inst-1');
    // Reconciliador al final de ejecutar(): sin red → no-op.
    when(() => dio.get<List<dynamic>>(any())).thenThrow(DioException(
        requestOptions: RequestOptions(path: '/m'),
        type: DioExceptionType.connectionError));
  });
  tearDown(() => db.close());

  Future<void> cache(String id, {required int? version, String estado = 'abierto'}) =>
      db.into(db.itemsCacheTable).insert(ItemsCacheTableCompanion.insert(
            id: id,
            proyectoId: 'p1',
            nombre: 'Item $id',
            asignadoA: const Value('user-1'),
            empresaId: const Value('emp-1'),
            estadoServidor: estado,
            version: Value(version),
            updatedAt: DateTime.utc(2026, 5, 1),
            cachadoEn: DateTime.utc(2026, 5, 1),
          ));

  // Encola una fila pendiente con un version_base dado (directo, sin pasar por la caché).
  Future<void> encolar(String id, String entidadId, String nuevoEstado, int versionBase,
          {int seq = 0}) =>
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
            versionBase: Value(versionBase),
          ));

  CicloSync ciclo() => CicloSync(
        syncDao: db.syncDao,
        dio: dio,
        deviceIdService: dev,
        isolateLabel: 'test',
        reloj: () => DateTime.utc(2026, 5, 1, 12),
      );

  // El servidor acepta y devuelve version=2 para toda transición.
  void stubPost200v2() {
    when(() => dio.post<Map<String, dynamic>>(any(),
            data: any(named: 'data'), options: any(named: 'options')))
        .thenAnswer((inv) async {
      final path = inv.positionalArguments.first as String;
      return Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(path: path),
        data: {'id': 'x', 'estado': 'en_progreso', 'version': 2},
      );
    });
  }

  Future<List<int?>> versionBaseDeCadaPost() async {
    final capt = verify(() => dio.post<Map<String, dynamic>>(any(),
            data: captureAny(named: 'data'), options: any(named: 'options')))
        .captured;
    return capt
        .map((d) => (d as Map<String, dynamic>)['version_base'] as int?)
        .toList();
  }

  test('R3bis Trabajador: la 2da transición sale con la version_base REBASEADA por el 200 '
      'de la 1ra', () async {
    // Arma: ítem en caché version=1; dos filas encoladas con version_base=1 (como las dejaría
    // el encolado desde la base). El 200 de la 1ra devuelve version=2.
    await cache('X', version: 1);
    await encolar('f1', 'X', 'en_progreso', 1);
    await encolar('f2', 'X', 'pendiente_revision', 1);
    stubPost200v2();

    await ciclo().ejecutar();

    // En DB la 2da quedó rebaseada a 2 (NO se fijó a mano).
    final f2 = await (db.select(db.syncPendientes)..where((t) => t.id.equals('f2')))
        .getSingle();
    expect(f2.versionBase, 2);
    // Y su POST (el 2do) llevó version_base=2.
    final versiones = await versionBaseDeCadaPost();
    expect(versiones, [1, 2]); // 1ra con la base original, 2da rebaseada
  });

  test('R3bis Residente: ítem NO en caché; la 2da sale rebaseada (el rebase opera sobre '
      'sync_pendientes, no items_cache)', () async {
    // Arma: SIN fila en items_cache (ruta del Residente). Dos filas con version_base=1.
    await encolar('r1', 'R', 'en_progreso', 1);
    await encolar('r2', 'R', 'pendiente_revision', 1);
    stubPost200v2();

    await ciclo().ejecutar();

    final r2 = await (db.select(db.syncPendientes)..where((t) => t.id.equals('r2')))
        .getSingle();
    expect(r2.versionBase, 2);
    expect(await versionBaseDeCadaPost(), [1, 2]);
  });

  test('una fila con OTRO version_base NO se rebasea', () async {
    await cache('Y', version: 1);
    await encolar('g1', 'Y', 'en_progreso', 1);
    await encolar('g2', 'Y', 'pendiente_revision', 5); // version_base distinto
    stubPost200v2();

    await ciclo().ejecutar();

    final g2 = await (db.select(db.syncPendientes)..where((t) => t.id.equals('g2')))
        .getSingle();
    expect(g2.versionBase, 5, reason: 'distinto version_base → el rebase no la toca');
  });

  test('base monótona (200): un 200 con version MENOR que la cacheada NO pisa la base',
      () async {
    // Arma: caché con version=5 / 'terminado'. Se envía una fila (version_base=5) y el 200
    // responde con version=3 (vieja). Verifica: la base NO baja.
    await cache('Z', version: 5, estado: 'terminado');
    await encolar('z1', 'Z', 'en_progreso', 5);
    when(() => dio.post<Map<String, dynamic>>(any(),
            data: any(named: 'data'), options: any(named: 'options')))
        .thenAnswer((_) async => Response<Map<String, dynamic>>(
              requestOptions: RequestOptions(path: '/items/Z/transicion'),
              data: {'id': 'Z', 'estado': 'abierto', 'version': 3},
            ));

    await ciclo().ejecutar();

    final z = await (db.select(db.itemsCacheTable)..where((t) => t.id.equals('Z')))
        .getSingle();
    expect(z.version, 5, reason: 'version vieja (3) no pisa 5');
    expect(z.estadoServidor, 'terminado', reason: 'estado tampoco se pisa');
  });

  test('base monótona (pull): sincronizarPull con version MENOR NO pisa la base', () async {
    await cache('W', version: 5, estado: 'terminado');
    // Un pull trae W con version=3 (respuesta vieja) y estado 'abierto'.
    final viejo = ItemsCacheTableCompanion.insert(
      id: 'W',
      proyectoId: 'p1',
      nombre: 'Item W',
      asignadoA: const Value('user-1'),
      estadoServidor: 'abierto',
      version: const Value(3),
      updatedAt: DateTime.utc(2026, 5, 2),
      cachadoEn: DateTime.utc(2026, 5, 2),
    );
    await db.itemsCacheDao.sincronizarPull('user-1', 'emp-1', [viejo]);

    final w = await (db.select(db.itemsCacheTable)..where((t) => t.id.equals('W')))
        .getSingle();
    expect(w.version, 5, reason: 'pull viejo (3) no baja la base 5');
    expect(w.estadoServidor, 'terminado');
  });

  test('409 conflicto_concurrencia: escribe la base (estado_servidor + version_actual) al '
      'parquear; la fila queda esperando_resolucion', () async {
    // Arma: caché version=1/'abierto', fila encolada (version_base=1). El 409 trae
    // version_actual=4 y estado_servidor='terminado'. Verifica: fila en esperando_resolucion,
    // base subida a v4/'terminado' (monótona) y tiene_conflicto=true.
    await cache('C', version: 1, estado: 'abierto');
    await encolar('c1', 'C', 'en_progreso', 1);
    when(() => dio.post<Map<String, dynamic>>(any(),
            data: any(named: 'data'), options: any(named: 'options')))
        .thenThrow(DioException(
      requestOptions: RequestOptions(path: '/items/C/transicion'),
      response: Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(path: '/items/C/transicion'),
        statusCode: 409,
        data: {
          'detail': {
            'tipo': 'conflicto_concurrencia',
            'conflicto_id': 'cf-1',
            'version_actual': 4,
            'estado_servidor': 'terminado',
          },
        },
      ),
    ));

    await ciclo().ejecutar();

    final fila = await (db.select(db.syncPendientes)..where((t) => t.id.equals('c1')))
        .getSingle();
    expect(fila.estado, EstadoSyncLocal.esperandoResolucion.valor);
    expect(fila.conflictoId, 'cf-1');
    final c = await (db.select(db.itemsCacheTable)..where((t) => t.id.equals('C')))
        .getSingle();
    expect(c.version, 4, reason: 'version_actual del 409 escribe la base');
    expect(c.estadoServidor, 'terminado');
    expect(c.tieneConflicto, isTrue);
  });
}
