/// encolar_primero_test.dart — CTT-148 (casos a–e de la caracterización, reescritos a la
/// nueva semántica). TransicionService.ejecutar ENCOLA primero, dispara el ciclo (aquí un
/// CicloSync real sobre la misma base) y espera el primer intento de la fila. Un solo
/// camino al servidor; sin escritura optimista ni revert en items_cache.
library;

import 'dart:convert';

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
import 'package:ctt_mobile/domain/enums/enums_ctt.dart';

class _MockDio extends Mock implements Dio {}

class _MockDeviceIdService extends Mock implements DeviceIdService {}

class _MockSecureStorage extends Mock implements SecureStorageService {}

const _itemId = 'it-1';

DioException _err409(Object data) {
  final ro = RequestOptions(path: '/items/$_itemId/transicion');
  return DioException(
    requestOptions: ro,
    response: Response<dynamic>(requestOptions: ro, statusCode: 409, data: data),
    type: DioExceptionType.badResponse,
  );
}

void main() {
  setUpAll(() => registerFallbackValue(Options()));

  late BaseDatosCTT db;
  late _MockDio dio;
  late _MockDeviceIdService deviceId;
  late _MockSecureStorage secure;
  late TransicionService service;

  setUp(() {
    db = BaseDatosCTT.conConexion(NativeDatabase.memory());
    dio = _MockDio();
    deviceId = _MockDeviceIdService();
    secure = _MockSecureStorage();
    when(() => deviceId.obtener()).thenAnswer((_) async => 'inst-1');
    when(() => secure.obtenerUsuarioId()).thenAnswer((_) async => 'user-1');
    when(() => secure.obtenerEmpresaId()).thenAnswer((_) async => 'emp-1');
    // Reconciliador al final del ciclo: sin red → no-op.
    when(() => dio.get<List<dynamic>>(any())).thenThrow(DioException(
        requestOptions: RequestOptions(path: '/m'),
        type: DioExceptionType.connectionError,),);

    final ciclo = CicloSync(
      syncDao: db.syncDao,
      dio: dio,
      deviceIdService: deviceId,
      isolateLabel: 'test',
      reloj: () => DateTime.utc(2026, 5, 1, 12),
    );
    service = TransicionService(
      syncDao: db.syncDao,
      deviceIdService: deviceId,
      secureStorage: secure,
      dispararCiclo: ciclo.ejecutar,
      reloj: () => DateTime.utc(2026, 5, 1, 12),
      timeoutEspera: const Duration(seconds: 2),
    );
  });
  tearDown(() => db.close());

  Future<void> cacheBase(String estado) =>
      db.into(db.itemsCacheTable).insert(ItemsCacheTableCompanion.insert(
            id: _itemId,
            proyectoId: 'proy-1',
            nombre: 'Tarea',
            estado: estado,
            updatedAt: DateTime.utc(2026, 5, 1),
            cachadoEn: DateTime.utc(2026, 5, 1),
          ));

  Future<ItemsCacheTableData> leerCache() =>
      (db.select(db.itemsCacheTable)..where((t) => t.id.equals(_itemId)))
          .getSingle();

  Future<String> estadoFila() async =>
      (await (db.select(db.syncPendientes)
                ..where((t) => t.entidadId.equals(_itemId)))
              .getSingle())
          .estado;

  test('(d) 200: fila sincronizada, base = ItemOut.estado, SIN optimista previo',
      () async {
    await cacheBase('abierto');
    when(() => dio.post<Map<String, dynamic>>(any(),
            data: any(named: 'data'), options: any(named: 'options'),),)
        .thenAnswer((_) async => Response<Map<String, dynamic>>(
              requestOptions: RequestOptions(path: '/x'),
              data: {'id': _itemId, 'estado': 'en_progreso'},
            ),);

    final r = await service.ejecutar(itemId: _itemId, nuevoEstado: 'en_progreso');

    expect(r.estado, EstadoSyncLocal.sincronizado);
    expect(await estadoFila(), EstadoSyncLocal.sincronizado.valor);
    expect((await leerCache()).estado, 'en_progreso'); // base desde el ItemOut
  });

  test('(a/b) 409 con conflicto_id: fila esperando_resolucion, tieneConflicto, sin revert',
      () async {
    await cacheBase('abierto');
    when(() => dio.post<Map<String, dynamic>>(any(),
            data: any(named: 'data'), options: any(named: 'options'),),)
        .thenThrow(_err409(jsonDecode(
            '{"detail":{"tipo":"conflicto_concurrencia","conflicto_id":"c-1"}}',),),);

    final r = await service.ejecutar(itemId: _itemId, nuevoEstado: 'pendiente_revision');

    expect(r.estado, EstadoSyncLocal.esperandoResolucion);
    expect(await estadoFila(), EstadoSyncLocal.esperandoResolucion.valor);
    final cache = await leerCache();
    expect(cache.tieneConflicto, isTrue);
    expect(cache.estado, 'abierto'); // base intacta (sin revert, sin optimista)
  });

  test('(c) 409 con rechazo_id: fila rechazada; resultado rechazada', () async {
    await cacheBase('abierto');
    when(() => dio.post<Map<String, dynamic>>(any(),
            data: any(named: 'data'), options: any(named: 'options'),),)
        .thenThrow(_err409(jsonDecode(
            '{"detail":{"tipo":"rechazo","rechazo_id":"r-1","motivo":"transicion_invalida"}}',),),);

    final r = await service.ejecutar(itemId: _itemId, nuevoEstado: 'pendiente_revision');

    expect(r.estado, EstadoSyncLocal.rechazada);
    expect(await estadoFila(), EstadoSyncLocal.rechazada.valor);
    expect((await leerCache()).estado, 'abierto'); // base intacta
  });

  test('(e) error de red: fila pendiente (bounce); resultado pendiente, base intacta',
      () async {
    await cacheBase('abierto');
    when(() => dio.post<Map<String, dynamic>>(any(),
            data: any(named: 'data'), options: any(named: 'options'),),)
        .thenThrow(DioException(
            requestOptions: RequestOptions(path: '/x'),
            type: DioExceptionType.connectionError,),);

    final r = await service.ejecutar(itemId: _itemId, nuevoEstado: 'en_progreso');

    expect(r.estado, EstadoSyncLocal.pendiente);
    expect(await estadoFila(), EstadoSyncLocal.pendiente.valor);
    expect((await leerCache()).estado, 'abierto');
  });

  test('sin sesión: lanza SesionNoDisponibleException y NO encola', () async {
    when(() => secure.obtenerUsuarioId()).thenAnswer((_) async => null);
    expect(
      () => service.ejecutar(itemId: _itemId, nuevoEstado: 'en_progreso'),
      throwsA(isA<SesionNoDisponibleException>()),
    );
    final filas = await db.select(db.syncPendientes).get();
    expect(filas, isEmpty);
  });
}
