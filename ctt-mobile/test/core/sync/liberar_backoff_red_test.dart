/// liberar_backoff_red_test.dart — CTT-103 L3.
///
/// Al recuperar conectividad, liberarBackoffRed() borra el proximo_intento_en SOLO de
/// las filas cuya última falla fue de red (ultimo_error_codigo NULL); respeta el
/// backoff de servidor (5xx/408/429/otro 4xx) y el Retry-After. Además: una falla sin
/// respuesta deja ultimo_error_codigo en NULL aunque un intento anterior lo haya tenido.
library;

import 'dart:math';

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

class _RandomCero implements Random {
  @override
  double nextDouble() => 0;
  @override
  int nextInt(int max) => 0;
  @override
  bool nextBool() => false;
}

DioException _err(int? status, {Object? data}) {
  final ro = RequestOptions(path: '/items/x/transicion');
  return DioException(
    requestOptions: ro,
    type: status == null
        ? DioExceptionType.connectionError
        : DioExceptionType.badResponse,
    response: status == null
        ? null
        : Response<dynamic>(requestOptions: ro, statusCode: status, data: data),
  );
}

void main() {
  setUpAll(() => registerFallbackValue(Options()));

  late BaseDatosCTT db;
  final futuro = DateTime.utc(2026, 6, 1, 13); // > ahora de cualquier test

  setUp(() => db = BaseDatosCTT.conConexion(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> ins(
    String id, {
    required DateTime? proximo,
    required int? codigo,
  }) =>
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
        proximoIntentoEn: Value(proximo),
        ultimoErrorCodigo: Value(codigo),
      ));

  Future<SyncPendiente> leer(String id) =>
      (db.select(db.syncPendientes)..where((t) => t.id.equals(id))).getSingle();

  test('libera SOLO las de falla de red (codigo NULL); respeta backoff de servidor',
      () async {
    await ins('A', proximo: futuro, codigo: null); // red: sin respuesta
    await ins('B', proximo: futuro, codigo: 503); // servidor + Retry-After
    await ins('C', proximo: futuro, codigo: 500); // servidor

    final liberadas = await db.syncDao.liberarBackoffRed();
    expect(liberadas, 1);

    expect((await leer('A')).proximoIntentoEn, isNull); // soltada
    expect((await leer('B')).proximoIntentoEn, futuro); // intacta
    expect((await leer('C')).proximoIntentoEn, futuro); // intacta

    // Solo A es reclamable ya (B y C siguen con su backoff en el futuro).
    final rec = await db.syncDao.filasReclamables(DateTime.utc(2026, 6, 1, 12));
    expect(rec.map((f) => f.id).toList(), ['A']);
  });

  test('falla 500 y luego por red: ultimo_error_codigo queda NULL → se libera',
      () async {
    // Una fila; el ciclo falla primero con 500, luego sin respuesta (red).
    await db.syncDao.encolar(SyncPendientesCompanion.insert(
      id: 'r',
      idempotencyKey: 'idem-r',
      empresaId: 'emp-1',
      usuarioId: 'user-1',
      instalacionId: 'inst-1',
      tipoEntidad: 'item',
      entidadId: 'item-r',
      accion: 'cambio_estado_item',
      payload: '{"nuevo_estado":"en_progreso"}',
      payloadVersion: 1,
      creadoEnDispositivo: DateTime.utc(2026, 1, 1),
      estado: const Value('pendiente'),
    ),);

    final ahora = DateTime.utc(2026, 6, 1, 12);
    final dio = _MockDio();
    final deviceId = _MockDeviceIdService();
    when(() => deviceId.obtener()).thenAnswer((_) async => 'inst-1');
    when(() => dio.get<List<dynamic>>(any())).thenAnswer((_) async =>
        Response<List<dynamic>>(
            requestOptions: RequestOptions(path: '/m'), data: const [],),);
    var n = 0;
    when(() => dio.post<void>(any(),
            data: any(named: 'data'), options: any(named: 'options'),),)
        .thenAnswer((_) async {
      n++;
      throw n == 1 ? _err(500, data: {'detail': 'boom'}) : _err(null);
    });

    final ciclo = CicloSync(
      syncDao: db.syncDao,
      dio: dio,
      deviceIdService: deviceId,
      isolateLabel: 'test',
      reloj: () => ahora,
      random: _RandomCero(), // backoff 0 → la fila vuelve a ser reclamable ya
    );

    await ciclo.ejecutar(); // falla 500 → codigo 500
    expect((await leer('r')).ultimoErrorCodigo, 500);
    await ciclo.ejecutar(); // falla por red → codigo NULL (no arrastra el 500)
    expect((await leer('r')).ultimoErrorCodigo, isNull);

    // Y liberarBackoffRed la reconoce como falla de red y la suelta.
    final liberadas = await db.syncDao.liberarBackoffRed();
    expect(liberadas, 1);
    expect((await leer('r')).proximoIntentoEn, isNull);
  });
}
