/// transicion_c6_test.dart — CTT-103 C6: encolado online de transitorios del servidor.
///
/// El camino online de transicion_service encola (en vez de propagar) ante 408, 429 y
/// 5xx salvo 501, con la MISMA Idempotency-Key del intento online; si viene Retry-After
/// (429/503), ese es el primer proximo_intento_en. 401/403/404/422/501 siguen
/// propagándose (no encolan).
library;

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:ctt_mobile/core/device/device_id_service.dart';
import 'package:ctt_mobile/core/security/secure_storage_service.dart';
import 'package:ctt_mobile/core/sync/resultado_transicion.dart';
import 'package:ctt_mobile/core/sync/transicion_service.dart';
import 'package:ctt_mobile/data/local/database.dart';

class _MockDio extends Mock implements Dio {}

class _MockDeviceIdService extends Mock implements DeviceIdService {}

class _MockSecureStorage extends Mock implements SecureStorageService {}

DioException _err(int status, {int? retryAfter}) {
  final ro = RequestOptions(path: '/items/x/transicion');
  return DioException(
    requestOptions: ro,
    type: DioExceptionType.badResponse,
    response: Response<dynamic>(
      requestOptions: ro,
      statusCode: status,
      data: {'detail': 'e$status'},
      headers: Headers.fromMap(
        retryAfter != null ? {'retry-after': ['$retryAfter']} : const {},
      ),
    ),
  );
}

void main() {
  setUpAll(() => registerFallbackValue(Options()));

  late BaseDatosCTT db;
  late _MockDio dio;
  late TransicionService service;

  // Reloj inyectado: 1ª llamada (inicio de ejecutar) = t0; las siguientes (instante en
  // que llega la respuesta) = tRespuesta. Así el test distingue la base del backoff.
  final t0 = DateTime.utc(2026, 7, 1, 12);
  final tRespuesta = t0.add(const Duration(seconds: 4));
  late int llamadasReloj;

  setUp(() {
    db = BaseDatosCTT.conConexion(NativeDatabase.memory());
    dio = _MockDio();
    final deviceId = _MockDeviceIdService();
    final storage = _MockSecureStorage();
    when(() => deviceId.obtener()).thenAnswer((_) async => 'dev-1');
    when(() => storage.obtenerUsuarioId()).thenAnswer((_) async => 'user-1');
    when(() => storage.obtenerEmpresaId()).thenAnswer((_) async => 'emp-1');
    llamadasReloj = 0;
    service = TransicionService(
      dio: dio,
      syncDao: db.syncDao,
      deviceIdService: deviceId,
      secureStorage: storage,
      reloj: () {
        llamadasReloj++;
        return llamadasReloj == 1 ? t0 : tRespuesta;
      },
    );
  });
  tearDown(() => db.close());

  Future<List<SyncPendiente>> filasDe(String itemId) =>
      (db.select(db.syncPendientes)..where((t) => t.entidadId.equals(itemId))).get();

  Future<void> encola(int status, {int? retryAfter}) async {
    final itemId = 'item-$status${retryAfter ?? ''}';
    when(() => dio.post<Map<String, dynamic>>(any(),
            data: any(named: 'data'), options: any(named: 'options'),),)
        .thenThrow(_err(status, retryAfter: retryAfter));

    final r = await service.ejecutar(itemId: itemId, nuevoEstado: 'en_progreso');
    expect(r, isA<TransicionEncoladaOffline>(), reason: 'status $status debe encolar');

    final filas = await filasDe(itemId);
    expect(filas, hasLength(1));
    final f = filas.single;
    expect(f.estado, 'pendiente');
    expect(f.ultimoErrorCodigo, status); // NO null → no se trata como red (L3)

    // Misma Idempotency-Key que el POST online.
    final opts = verify(() => dio.post<Map<String, dynamic>>(any(),
            data: any(named: 'data'), options: captureAny(named: 'options'),),)
        .captured
        .single as Options;
    expect(f.idempotencyKey, opts.headers!['Idempotency-Key']);

    if (retryAfter != null) {
      // primer proximo_intento_en = instante de la RESPUESTA + Retry-After (C6b):
      // tRespuesta + retryAfter, NO t0 (inicio) + retryAfter.
      expect(f.proximoIntentoEn, tRespuesta.add(Duration(seconds: retryAfter)));
      expect(f.proximoIntentoEn, isNot(t0.add(Duration(seconds: retryAfter))));
    } else {
      expect(f.proximoIntentoEn, isNull);
    }
  }

  Future<void> noEncola(int status) async {
    final itemId = 'item-$status';
    when(() => dio.post<Map<String, dynamic>>(any(),
            data: any(named: 'data'), options: any(named: 'options'),),)
        .thenThrow(_err(status));

    await expectLater(
      service.ejecutar(itemId: itemId, nuevoEstado: 'en_progreso'),
      throwsA(isA<DioException>()),
    );
    expect(await filasDe(itemId), isEmpty);
  }

  test('408 → encola', () => encola(408));
  test('429 sin Retry-After → encola sin backoff', () => encola(429));
  test('429 con Retry-After → encola con proximo_intento_en', () => encola(429, retryAfter: 120));
  test('500 → encola', () => encola(500));
  test('502 → encola', () => encola(502));
  test('503 con Retry-After → encola con proximo_intento_en', () => encola(503, retryAfter: 30));
  test('504 → encola', () => encola(504));

  test('501 → NO encola (propaga)', () => noEncola(501));
  test('403 → NO encola (propaga)', () => noEncola(403));
  test('404 → NO encola (propaga)', () => noEncola(404));
  test('422 → NO encola (propaga)', () => noEncola(422));
}
