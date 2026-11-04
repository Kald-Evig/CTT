/// ctt141_reconciliacion_inmediata_test.dart — CTT-141: un 200 sobre un ítem con
/// tiene_conflicto=1 reconcilia YA (sin debounce) al final de la corrida; un 200 sobre un
/// ítem sin conflicto mantiene el debounce de 2 min.
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
  late _MockDeviceIdService deviceId;

  setUp(() {
    db = BaseDatosCTT.conConexion(NativeDatabase.memory());
    dio = _MockDio();
    deviceId = _MockDeviceIdService();
    when(() => deviceId.obtener()).thenAnswer((_) async => 'inst-1');
    // POST de la transición → 200 con ItemOut.
    when(() => dio.post<Map<String, dynamic>>(any(),
            data: any(named: 'data'), options: any(named: 'options')))
        .thenAnswer((_) async => Response<Map<String, dynamic>>(
              requestOptions: RequestOptions(path: '/t'),
              data: {'id': 'X', 'estado': 'en_progreso', 'version': 3},
            ));
    // GET por defecto (p. ej. /mios) → lista vacía, para no lanzar MissingStubError.
    when(() => dio.get<List<dynamic>>(any())).thenAnswer((_) async =>
        Response<List<dynamic>>(
            requestOptions: RequestOptions(path: '/m'), data: const []));
  });
  tearDown(() => db.close());

  Future<void> cache(String id, {required bool conflicto}) =>
      db.into(db.itemsCacheTable).insert(ItemsCacheTableCompanion.insert(
            id: id,
            proyectoId: 'proy-1',
            nombre: 'Tarea',
            estadoServidor: 'pendiente_revision',
            version: const Value(2),
            tieneConflicto: Value(conflicto),
            cachadoEn: DateTime.utc(2026, 5, 1),
          ));

  Future<void> parquear(String id, String entidadId, String conflictoId) =>
      db.into(db.syncPendientes).insert(SyncPendientesCompanion.insert(
            id: id,
            idempotencyKey: 'idem-$id',
            empresaId: 'emp-1',
            usuarioId: 'user-1',
            instalacionId: 'inst-1',
            tipoEntidad: 'item',
            entidadId: entidadId,
            accion: 'cambio_estado_item',
            payload: '{"nuevo_estado":"terminado"}',
            payloadVersion: 1,
            creadoEnDispositivo: DateTime.utc(2026, 1, 1),
            estado: const Value('esperando_resolucion'),
            conflictoId: Value(conflictoId),
          ));

  Future<void> encolar(String id, String entidadId) =>
      db.syncDao.encolar(SyncPendientesCompanion.insert(
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
        estado: const Value('pendiente'),
      ));

  CicloSync ciclo() => CicloSync(
        syncDao: db.syncDao,
        dio: dio,
        deviceIdService: deviceId,
        isolateLabel: 'test',
      );

  test('200 sobre un ítem con tiene_conflicto=1 reconcilia YA aunque el debounce esté activo',
      () async {
    await db.syncDao.registrarReconciliacion(DateTime.now().toUtc()); // debounce ACTIVO
    await cache('X', conflicto: true);
    await parquear('p1', 'X', 'c1'); // fila parqueada (esperando_resolucion)
    await encolar('e1', 'X'); // nueva transición pendiente
    when(() => dio.get<List<dynamic>>('/sync/conflictos/mios')).thenAnswer((_) async =>
        Response<List<dynamic>>(
          requestOptions: RequestOptions(path: '/sync/conflictos/mios'),
          data: [
            {'id': 'c1', 'estado': 'superado', 'version_ganadora': null},
          ],
        ));

    await ciclo().ejecutar();

    verify(() => dio.get<List<dynamic>>('/sync/conflictos/mios')).called(1);
    // La fila parqueada se cerró (superado → descartado): la reconciliación corrió sin debounce.
    final parked =
        await (db.select(db.syncPendientes)..where((t) => t.id.equals('p1')))
            .getSingle();
    expect(parked.estado, EstadoSyncLocal.descartado.valor);
  });

  test('200 sobre un ítem SIN conflicto no consulta /mios dentro del debounce', () async {
    await db.syncDao.registrarReconciliacion(DateTime.now().toUtc()); // debounce ACTIVO
    await cache('Y', conflicto: false);
    await encolar('e2', 'Y');

    await ciclo().ejecutar();

    verifyNever(() => dio.get<List<dynamic>>('/sync/conflictos/mios'));
  });
}
