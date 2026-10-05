/// rescate_tope_test.dart — CTT-103 D5.
///
/// Al alcanzar el tope de intentos_servidor, el ciclo deriva la fila a /sync/rescate:
/// si el servidor la acepta → en_revision; si el rescate falla (403 cuenta inactiva) →
/// la fila sigue pendiente (con backoff) y NUNCA se descarta.
library;

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:ctt_mobile/core/device/device_id_service.dart';
import 'package:ctt_mobile/core/sync/decision_sync.dart';
import 'package:ctt_mobile/core/sync/ciclo_sync.dart';
import 'package:ctt_mobile/data/local/database.dart';
import 'package:ctt_mobile/domain/enums/enums_ctt.dart';

class _MockDio extends Mock implements Dio {}

class _MockDeviceIdService extends Mock implements DeviceIdService {}

DioException _err(int status) {
  final ro = RequestOptions(path: '/x');
  return DioException(
    requestOptions: ro,
    type: DioExceptionType.badResponse,
    response: Response<dynamic>(
      requestOptions: ro,
      statusCode: status,
      data: {'detail': 'e$status'},
    ),
  );
}

void main() {
  setUpAll(() => registerFallbackValue(Options()));

  late BaseDatosCTT db;
  late _MockDio dio;
  final ahora = DateTime.utc(2026, 8, 1, 12);

  setUp(() {
    db = BaseDatosCTT.conConexion(NativeDatabase.memory());
    dio = _MockDio();
    when(() => dio.get<List<dynamic>>(any())).thenAnswer((_) async =>
        Response<List<dynamic>>(
            requestOptions: RequestOptions(path: '/m'), data: const [],),);
    // El envío (/transicion) falla con un 4xx no determinista → fallaServidor.
    when(() => dio.post<void>(any(),
            data: any(named: 'data'), options: any(named: 'options'),),)
        .thenThrow(_err(501));
  });
  tearDown(() => db.close());

  Future<void> insertar(String id, {required int intentosServidor}) =>
      db.syncDao.encolar(SyncPendientesCompanion.insert(
        id: id,
        idempotencyKey: 'idem-$id',
        empresaId: 'emp-1',
        usuarioId: 'user-1',
        instalacionId: 'inst-1',
        tipoEntidad: 'item',
        entidadId: 'item-$id',
        accion: 'cambio_estado_item',
        payload: '{"nuevo_estado":"en_progreso"}',
        payloadVersion: 1,
        creadoEnDispositivo: DateTime.utc(2026, 1, 1),
        estado: const Value('pendiente'),
        intentosServidor: Value(intentosServidor),
      ));

  Future<SyncPendiente> leer(String id) =>
      (db.select(db.syncPendientes)..where((t) => t.id.equals(id))).getSingle();

  CicloSync ciclo() {
    final dev = _MockDeviceIdService();
    when(() => dev.obtener()).thenAnswer((_) async => 'inst-1');
    return CicloSync(
      syncDao: db.syncDao,
      dio: dio,
      deviceIdService: dev,
      isolateLabel: 'test',
      reloj: () => ahora,
    );
  }

  test('al tope (intentos_servidor llega a 6): rescate aceptado → en_revision', () async {
    await insertar('r', intentosServidor: 5); // el próximo fallo lo lleva a 6 = tope
    when(() => dio.post<Map<String, dynamic>>('/sync/rescate',
            data: any(named: 'data'),),).thenAnswer((_) async =>
        Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(path: '/sync/rescate'),
          data: const {'aceptadas': 1, 'rechazadas_tenant': 0},
        ),);

    expect(kTopeIntentosServidor, 6);
    await ciclo().ejecutar();

    final f = await leer('r');
    expect(f.estado, EstadoSyncLocal.enRevision.valor);
    expect(f.intentosServidor, 6);
    verify(() => dio.post<Map<String, dynamic>>('/sync/rescate',
        data: any(named: 'data'),),).called(1);
  });

  test('al tope pero el rescate falla (403): la fila sigue pendiente, NO se descarta',
      () async {
    await insertar('r', intentosServidor: 5);
    when(() => dio.post<Map<String, dynamic>>('/sync/rescate',
            data: any(named: 'data'),),).thenThrow(_err(403));

    await ciclo().ejecutar();

    final f = await leer('r');
    expect(f.estado, EstadoSyncLocal.pendiente.valor); // NUNCA descarta
    expect(f.intentosServidor, 6); // igual contabilizó el intento
    expect(f.proximoIntentoEn, isNotNull); // con backoff para reintentar (incl. rescate)
  });
}
