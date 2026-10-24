/// ciclo_base_itemout_test.dart — CTT-144/CTT-148: en un envío aceptado (200), el ciclo
/// escribe la BASE `items_cache.estado` desde el `ItemOut`, en la misma transacción que
/// el estado de la cola. En un envío NO exitoso, la base no se toca.
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
    // Reconciliador al final de ejecutar(): sin red → no-op best-effort.
    when(() => dio.get<List<dynamic>>(any())).thenThrow(DioException(
        requestOptions: RequestOptions(path: '/m'),
        type: DioExceptionType.connectionError,),);
  });
  tearDown(() => db.close());

  Future<void> cacheBase(String id, String estado) =>
      db.into(db.itemsCacheTable).insert(ItemsCacheTableCompanion.insert(
            id: id,
            proyectoId: 'proy-1',
            nombre: 'Tarea',
            estadoServidor: estado,
            updatedAt: DateTime.utc(2026, 5, 1),
            cachadoEn: DateTime.utc(2026, 5, 1),
          ));

  Future<void> encolar(String id, String entidadId, String nuevoEstado) =>
      db.syncDao.encolar(SyncPendientesCompanion.insert(
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
        estado: const Value('pendiente'),
      ));

  CicloSync ciclo() => CicloSync(
        syncDao: db.syncDao,
        dio: dio,
        deviceIdService: deviceId,
        isolateLabel: 'test',
        reloj: () => DateTime.utc(2026, 5, 1, 12),
      );

  Future<String> estadoBase(String id) async =>
      (await (db.select(db.itemsCacheTable)..where((t) => t.id.equals(id)))
              .getSingle())
          .estadoServidor;

  test('200: base items_cache.estado = ItemOut.estado (misma transacción)', () async {
    await cacheBase('X', 'abierto');
    await encolar('x1', 'X', 'en_progreso');
    when(() => dio.post<Map<String, dynamic>>(any(),
            data: any(named: 'data'), options: any(named: 'options'),),)
        .thenAnswer((_) async => Response<Map<String, dynamic>>(
              requestOptions: RequestOptions(path: '/items/X/transicion'),
              data: {'id': 'X', 'estado': 'en_progreso', 'version': 2},
            ),);

    await ciclo().ejecutar();

    final fila =
        await (db.select(db.syncPendientes)..where((t) => t.id.equals('x1')))
            .getSingle();
    expect(fila.estado, EstadoSyncLocal.sincronizado.valor);
    expect(await estadoBase('X'), 'en_progreso'); // base escrita desde el ItemOut
  });

  test('envío NO exitoso (red): la base NO se toca', () async {
    await cacheBase('Y', 'abierto');
    await encolar('y1', 'Y', 'en_progreso');
    when(() => dio.post<Map<String, dynamic>>(any(),
            data: any(named: 'data'), options: any(named: 'options'),),)
        .thenThrow(DioException(
            requestOptions: RequestOptions(path: '/items/Y/transicion'),
            type: DioExceptionType.connectionError,),);

    await ciclo().ejecutar();

    final fila =
        await (db.select(db.syncPendientes)..where((t) => t.id.equals('y1')))
            .getSingle();
    expect(fila.estado, EstadoSyncLocal.pendiente.valor); // falla de red → pendiente
    expect(await estadoBase('Y'), 'abierto'); // base intacta
  });
}
