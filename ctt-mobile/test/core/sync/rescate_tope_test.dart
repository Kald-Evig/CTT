/// rescate_tope_test.dart — CTT-103 D5.
///
/// Al alcanzar el tope de intentos_servidor, el ciclo deriva la fila a /sync/rescate
/// con la fila COMPLETA (mismo formato que el flujo de pantalla, con los campos de la
/// falla actual sobreescritos): si el servidor la acepta → en_revision; si el rescate
/// falla (403) → la fila sigue pendiente y NUNCA se descarta.
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:ctt_mobile/core/device/device_id_service.dart';
import 'package:ctt_mobile/core/sync/ciclo_sync.dart';
import 'package:ctt_mobile/core/sync/decision_sync.dart';
import 'package:ctt_mobile/data/local/apertura_base.dart';
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
      requestOptions: ro, statusCode: status, data: {'detail': 'e$status'},),
  );
}

void main() {
  setUpAll(() => registerFallbackValue(Options()));

  late _MockDio dio;
  final ahora = DateTime.utc(2026, 8, 1, 12);

  setUp(() {
    dio = _MockDio();
    when(() => dio.get<List<dynamic>>(any())).thenAnswer((_) async =>
        Response<List<dynamic>>(
            requestOptions: RequestOptions(path: '/m'), data: const [],),);
    // El envío (/transicion) falla con 501 → fallaServidor (incrementa servidor).
    when(() => dio.post<void>(any(),
            data: any(named: 'data'), options: any(named: 'options'),),)
        .thenThrow(_err(501));
  });

  BaseDatosCTT abrirArchivo(String path) {
    void setup(raw.Database d) {
      d.execute('PRAGMA journal_mode=WAL;');
      d.execute('PRAGMA busy_timeout=5000;');
    }
    return BaseDatosCTT.conConexion(NativeDatabase(File(path), setup: setup));
  }

  Future<void> insertar(BaseDatosCTT db, String id, {required int intentosServidor}) =>
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
        creadoEnDispositivo: DateTime.utc(2026, 1, 1, 9),
        estado: const Value('pendiente'),
        intentosServidor: Value(intentosServidor),
      ));

  CicloSync ciclo(BaseDatosCTT db) {
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

  test('tope → rescate aceptado → en_revision; payload = fila COMPLETA con la falla '
      'actual sobreescrita', () async {
    final tmp = Directory.systemTemp.createTempSync('ctt_rescate');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final path = '${tmp.path}/db.sqlite';
    final db = abrirArchivo(path);
    addTearDown(db.close);

    await insertar(db, 'r', intentosServidor: 5); // el 6º fallo = tope
    // Claves esperadas: una fila completa de leerFilasNoTerminalesCrudo (pendiente).
    final clavesEsperadas =
        leerFilasNoTerminalesCrudo(path).single.keys.toSet();

    when(() => dio.post<Map<String, dynamic>>('/sync/rescate',
            data: any(named: 'data'),),).thenAnswer((_) async =>
        Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(path: '/sync/rescate'),
          data: const {'aceptadas': 1, 'rechazadas_tenant': 0},
        ),);

    await ciclo(db).ejecutar();

    final f = await (db.select(db.syncPendientes)
          ..where((t) => t.id.equals('r')))
        .getSingle();
    expect(f.estado, EstadoSyncLocal.enRevision.valor);
    expect(f.intentosServidor, 6);

    // La fila que recibió el servidor: mismas claves que leerFilasNoTerminalesCrudo,
    // con creado_en_dispositivo y los valores de la 6ª falla.
    final data = verify(() => dio.post<Map<String, dynamic>>('/sync/rescate',
        data: captureAny(named: 'data'),),).captured.single as Map<String, dynamic>;
    final enviada = (data['filas'] as List).single as Map<String, Object?>;
    expect(enviada.keys.toSet(), clavesEsperadas);
    expect(enviada['creado_en_dispositivo'], isNotNull);
    expect(enviada['intentos_servidor'], 6);
    expect(enviada['ultimo_error_codigo'], 501);
    expect(enviada['ultimo_error'], 'e501');
  });

  test('tope pero rescate 403: la fila sigue pendiente, NO se descarta', () async {
    final db = BaseDatosCTT.conConexion(NativeDatabase.memory());
    addTearDown(db.close);
    await insertar(db, 'r', intentosServidor: 5);
    when(() => dio.post<Map<String, dynamic>>('/sync/rescate',
            data: any(named: 'data'),),).thenThrow(_err(403));

    await ciclo(db).ejecutar();

    final f = await (db.select(db.syncPendientes)
          ..where((t) => t.id.equals('r')))
        .getSingle();
    expect(f.estado, EstadoSyncLocal.pendiente.valor); // NUNCA descarta
    expect(f.intentosServidor, 6);
    expect(f.proximoIntentoEn, isNotNull); // con backoff para reintentar
  });
}
