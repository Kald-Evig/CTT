/// rescate_service_test.dart — CTT-130 fase 4b (cliente).
///
/// - Envía SOLO las filas no terminales de la cola.
/// - Sin red → sinRed; 5xx/429 → errorServidor (transitorio, reintentable).
/// - 4xx → errorCliente (no reintentable, pero avisa).
/// - Rescate parcial: el servidor rechaza filas y las cuenta (sinRescatar).
/// - Sin sesión (token null) → sinSesion, sin llamar a la red.
/// - El proveedor de token se elige por AUTH_MODE (mock/firebase).
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:ctt_mobile/core/device/device_id_service.dart';
import 'package:ctt_mobile/core/network/dio_client.dart' show secureStorageProvider;
import 'package:ctt_mobile/core/security/secure_storage_service.dart';
import 'package:ctt_mobile/core/sync/rescate_service.dart';
import 'package:ctt_mobile/data/local/database.dart';

class _MockDio extends Mock implements Dio {}

class _MockDeviceId extends Mock implements DeviceIdService {}

class _MockStorage extends Mock implements SecureStorageService {}

class _FakeToken implements ProveedorTokenRescate {
  _FakeToken(this._t);
  final String? _t;
  @override
  Future<String?> obtenerToken() async => _t;
}

/// Respuesta del servidor (RescateColaOut) con los conteos por defecto en cero.
Response<Map<String, dynamic>> _resp({
  int aceptadas = 0,
  int yaAplicadas = 0,
  int duplicadas = 0,
  int rechazadasTenant = 0,
}) =>
    Response<Map<String, dynamic>>(
      requestOptions: RequestOptions(path: '/sync/rescate'),
      statusCode: 200,
      data: {
        'recibidas': aceptadas + yaAplicadas + duplicadas + rechazadasTenant,
        'aceptadas': aceptadas,
        'ya_aplicadas': yaAplicadas,
        'duplicadas': duplicadas,
        'rechazadas_tenant': rechazadasTenant,
      },
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => registerFallbackValue(Options()));

  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('ctt_rescate');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {/* handle sqlite en Windows */}
  });

  Future<void> sembrarCola() async {
    final db = BaseDatosCTT.conConexion(
      NativeDatabase(File('${tmp.path}/ctt_local.db')),
    );
    Future<void> fila(String id, String estado) => db.syncDao.encolar(
          SyncPendientesCompanion.insert(
            id: id,
            idempotencyKey: 'idem-$id',
            empresaId: 'emp-1',
            usuarioId: 'user-1',
            instalacionId: 'inst-1',
            tipoEntidad: 'item',
            entidadId: 'item-$id',
            accion: 'cambio_estado_item',
            payload: '{"k":"$id"}',
            payloadVersion: 1,
            creadoEnDispositivo: DateTime.utc(2026, 1, 1),
            estado: Value(estado),
          ),
        );
    await fila('p', 'pendiente');
    await fila('e', 'enviando');
    await fila('r', 'esperando_resolucion');
    await fila('s', 'sincronizado'); // terminal — NO debe enviarse
    await fila('d', 'descartado'); // terminal — NO debe enviarse
    await db.close();
  }

  RescateService servicio(_MockDio dio, _MockDeviceId deviceId, {String? token}) {
    when(() => deviceId.obtener()).thenAnswer((_) async => 'inst-1');
    return RescateService(
      dio: dio,
      proveedorToken: _FakeToken(token),
      deviceIdService: deviceId,
    );
  }

  void stubPost(_MockDio dio, Response<Map<String, dynamic>> resp) {
    when(
      () => dio.post<Map<String, dynamic>>(
        any(),
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenAnswer((_) async => resp);
  }

  void stubPostThrow(_MockDio dio, DioException e) {
    when(
      () => dio.post<Map<String, dynamic>>(
        any(),
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenThrow(e);
  }

  test('envía SOLO las filas no terminales', () async {
    await sembrarCola();
    final dio = _MockDio();
    final deviceId = _MockDeviceId();
    stubPost(dio, _resp(aceptadas: 3));

    final r = await servicio(dio, deviceId, token: 'tok').rescatar();
    expect(r.estado, ResultadoRescate.enviado);
    expect(r.sinRescatar, 0);

    final data = verify(
      () => dio.post<Map<String, dynamic>>(
        any(),
        data: captureAny(named: 'data'),
        options: any(named: 'options'),
      ),
    ).captured.single as Map<String, dynamic>;
    final filas = (data['filas'] as List).cast<Map<String, Object?>>();
    final ids = filas.map((f) => f['id']).toSet();
    expect(ids, {'p', 'e', 'r'}); // solo no terminales
    expect(ids.contains('s'), isFalse);
    expect(ids.contains('d'), isFalse);
    expect(data['instalacion_id'], 'inst-1');
  });

  test('rescate parcial: el servidor rechaza filas y las cuenta (sinRescatar)',
      () async {
    await sembrarCola();
    final dio = _MockDio();
    final deviceId = _MockDeviceId();
    stubPost(dio, _resp(aceptadas: 1, rechazadasTenant: 2));

    final r = await servicio(dio, deviceId, token: 'tok').rescatar();
    expect(r.estado, ResultadoRescate.enviado);
    expect(r.enviadas, 1);
    expect(r.sinRescatar, 2); // quedaron 2 sin rescatar → siguen en el teléfono
  });

  test('sin red → sinRed', () async {
    await sembrarCola();
    final dio = _MockDio();
    final deviceId = _MockDeviceId();
    stubPostThrow(
      dio,
      DioException(
        requestOptions: RequestOptions(path: '/sync/rescate'),
        type: DioExceptionType.connectionError,
      ),
    );

    final r = await servicio(dio, deviceId, token: 'tok').rescatar();
    expect(r.estado, ResultadoRescate.sinRed);
  });

  test('5xx → errorServidor (transitorio, reintentable)', () async {
    await sembrarCola();
    final dio = _MockDio();
    final deviceId = _MockDeviceId();
    stubPostThrow(
      dio,
      DioException(
        requestOptions: RequestOptions(path: '/sync/rescate'),
        type: DioExceptionType.badResponse,
        response: Response<void>(
          requestOptions: RequestOptions(path: '/sync/rescate'),
          statusCode: 503,
        ),
      ),
    );

    final r = await servicio(dio, deviceId, token: 'tok').rescatar();
    expect(r.estado, ResultadoRescate.errorServidor);
  });

  test('429 → errorServidor (reintentable)', () async {
    await sembrarCola();
    final dio = _MockDio();
    final deviceId = _MockDeviceId();
    stubPostThrow(
      dio,
      DioException(
        requestOptions: RequestOptions(path: '/sync/rescate'),
        type: DioExceptionType.badResponse,
        response: Response<void>(
          requestOptions: RequestOptions(path: '/sync/rescate'),
          statusCode: 429,
        ),
      ),
    );

    final r = await servicio(dio, deviceId, token: 'tok').rescatar();
    expect(r.estado, ResultadoRescate.errorServidor);
  });

  test('4xx → errorCliente (no reintentable, pero avisa)', () async {
    await sembrarCola();
    final dio = _MockDio();
    final deviceId = _MockDeviceId();
    stubPostThrow(
      dio,
      DioException(
        requestOptions: RequestOptions(path: '/sync/rescate'),
        type: DioExceptionType.badResponse,
        response: Response<void>(
          requestOptions: RequestOptions(path: '/sync/rescate'),
          statusCode: 400,
        ),
      ),
    );

    final r = await servicio(dio, deviceId, token: 'tok').rescatar();
    expect(r.estado, ResultadoRescate.errorCliente);
  });

  test('sin sesión (token null) → sinSesion, sin tocar la red', () async {
    final dio = _MockDio();
    final deviceId = _MockDeviceId();
    final svc = RescateService(
      dio: dio,
      proveedorToken: _FakeToken(null),
      deviceIdService: deviceId,
    );
    final r = await svc.rescatar();
    expect(r.estado, ResultadoRescate.sinSesion);
    verifyNever(
      () => dio.post<Map<String, dynamic>>(
        any(),
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    );
  });

  group('proveedor de token elegido por AUTH_MODE', () {
    test('modo firebase → TokenRescateFirebase', () {
      final c = ProviderContainer(
        overrides: [modoAuthProvider.overrideWithValue('firebase')],
      );
      addTearDown(c.dispose);
      expect(
        c.read(proveedorTokenRescateProvider),
        isA<TokenRescateFirebase>(),
      );
    });

    test('modo mock → TokenRescateSecureStorage', () {
      final c = ProviderContainer(
        overrides: [
          modoAuthProvider.overrideWithValue('mock'),
          secureStorageProvider.overrideWithValue(_MockStorage()),
        ],
      );
      addTearDown(c.dispose);
      expect(
        c.read(proveedorTokenRescateProvider),
        isA<TokenRescateSecureStorage>(),
      );
    });
  });
}
