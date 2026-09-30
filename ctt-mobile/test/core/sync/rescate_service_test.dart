/// rescate_service_test.dart — CTT-130 fase 4b (cliente).
///
/// - Envía SOLO las filas no terminales de la cola.
/// - Sin red → sinRed (para reintentar).
/// - Sin sesión (token null) → sinSesion, sin llamar a la red.
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:ctt_mobile/core/device/device_id_service.dart';
import 'package:ctt_mobile/core/sync/rescate_service.dart';
import 'package:ctt_mobile/data/local/database.dart';

class _MockDio extends Mock implements Dio {}

class _MockDeviceId extends Mock implements DeviceIdService {}

class _FakeToken implements ProveedorTokenRescate {
  _FakeToken(this._t);
  final String? _t;
  @override
  Future<String?> obtenerToken() async => _t;
}

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

  test('envía SOLO las filas no terminales', () async {
    await sembrarCola();
    final dio = _MockDio();
    final deviceId = _MockDeviceId();
    when(() => deviceId.obtener()).thenAnswer((_) async => 'inst-1');
    when(
      () => dio.post<void>(
        any(),
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenAnswer(
      (_) async => Response<void>(
        requestOptions: RequestOptions(path: '/sync/rescate'),
        statusCode: 200,
      ),
    );

    final svc = RescateService(
      dio: dio,
      proveedorToken: _FakeToken('tok'),
      deviceIdService: deviceId,
    );
    final r = await svc.rescatar();
    expect(r, ResultadoRescate.enviado);

    final data = verify(
      () => dio.post<void>(
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

  test('sin red → sinRed', () async {
    await sembrarCola();
    final dio = _MockDio();
    final deviceId = _MockDeviceId();
    when(() => deviceId.obtener()).thenAnswer((_) async => 'inst-1');
    when(
      () => dio.post<void>(
        any(),
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/sync/rescate'),
        type: DioExceptionType.connectionError,
      ),
    );

    final svc = RescateService(
      dio: dio,
      proveedorToken: _FakeToken('tok'),
      deviceIdService: deviceId,
    );
    expect(await svc.rescatar(), ResultadoRescate.sinRed);
  });

  test('sin sesión (token null) → sinSesion, sin tocar la red', () async {
    final dio = _MockDio();
    final deviceId = _MockDeviceId();
    final svc = RescateService(
      dio: dio,
      proveedorToken: _FakeToken(null),
      deviceIdService: deviceId,
    );
    expect(await svc.rescatar(), ResultadoRescate.sinSesion);
    verifyNever(
      () => dio.post<void>(
        any(),
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    );
  });
}
