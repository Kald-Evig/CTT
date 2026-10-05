/// clasificador_ciclo_test.dart — CTT-103: clasificador I2 + backoff + 401.
///
/// Ejercita ciclo_sync.ejecutar() contra Drift REAL (in-memory) y un Dio mockeado:
/// una rama por caso de la tabla de clasificación, el backoff determinista (Random
/// inyectado + Retry-After como piso) y el aborto de corrida en 401.
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

/// Random con nextDouble() fijo, para un backoff determinista.
class _RandomFijo implements Random {
  _RandomFijo(this._v);
  final double _v;
  @override
  double nextDouble() => _v;
  @override
  int nextInt(int max) => 0;
  @override
  bool nextBool() => false;
}

DioException _err(
  int? status, {
  Object? data,
  Map<String, List<String>>? headers,
}) {
  final ro = RequestOptions(path: '/items/x/transicion');
  return DioException(
    requestOptions: ro,
    type: status == null
        ? DioExceptionType.connectionError
        : DioExceptionType.badResponse,
    response: status == null
        ? null
        : Response<dynamic>(
            requestOptions: ro,
            statusCode: status,
            data: data,
            headers: Headers.fromMap(headers ?? const {}),
          ),
  );
}

void main() {
  setUpAll(() => registerFallbackValue(Options()));

  late BaseDatosCTT db;
  late _MockDio dio;
  final ahora = DateTime.utc(2026, 6, 1, 12);

  setUp(() {
    db = BaseDatosCTT.conConexion(NativeDatabase.memory());
    dio = _MockDio();
    // El reconciliador del final de ejecutar() consulta /mios: stub vacío → no-op.
    when(() => dio.get<List<dynamic>>(any())).thenAnswer(
      (_) async => Response<List<dynamic>>(
        requestOptions: RequestOptions(path: '/sync/conflictos/mios'),
        data: const [],
      ),
    );
  });
  tearDown(() => db.close());

  Future<void> insertar(String id, String entidad) =>
      db.syncDao.encolar(SyncPendientesCompanion.insert(
        id: id,
        idempotencyKey: 'idem-$id',
        empresaId: 'emp-1',
        usuarioId: 'user-1',
        instalacionId: 'inst-1',
        tipoEntidad: 'item',
        entidadId: entidad,
        accion: 'cambio_estado_item',
        payload: '{"nuevo_estado":"en_progreso"}',
        payloadVersion: 1,
        creadoEnDispositivo: DateTime.utc(2026, 1, 1),
        estado: const Value('pendiente'),
      ));

  Future<SyncPendiente> leer(String id) =>
      (db.select(db.syncPendientes)..where((t) => t.id.equals(id))).getSingle();

  CicloSync ciclo({Random? random, void Function()? alSesionVencida}) => CicloSync(
        syncDao: db.syncDao,
        dio: dio,
        deviceIdService: (() {
          final m = _MockDeviceIdService();
          when(() => m.obtener()).thenAnswer((_) async => 'inst-1');
          return m;
        })(),
        isolateLabel: 'test',
        reloj: () => ahora,
        random: random ?? _RandomFijo(0),
        alSesionVencida: alSesionVencida,
      );

  void stubPost(Object error) {
    when(() => dio.post<void>(any(),
            data: any(named: 'data'), options: any(named: 'options'),),)
        .thenThrow(error);
  }

  test('2xx → sincronizado', () async {
    await insertar('r', 'item-A');
    when(() => dio.post<void>(any(),
            data: any(named: 'data'), options: any(named: 'options'),),)
        .thenAnswer((_) async => Response<void>(
              requestOptions: RequestOptions(path: '/'),
            ),);

    await ciclo().ejecutar();
    final f = await leer('r');
    expect(f.estado, EstadoSyncLocal.sincronizado.valor);
    expect(f.motivo, isNull); // A4: no arrastra motivo
  });

  test('409 conflicto_concurrencia + conflicto_id → esperando_resolucion', () async {
    await insertar('r', 'item-A');
    stubPost(_err(409, data: {
      'detail': {'tipo': 'conflicto_concurrencia', 'conflicto_id': 'c-1'},
    }),);

    await ciclo().ejecutar();
    final f = await leer('r');
    expect(f.estado, EstadoSyncLocal.esperandoResolucion.valor);
    expect(f.conflictoId, 'c-1');
    expect(f.motivo, MotivoSync.conflicto.valor);
  });

  test('4xx con rechazo_id → rechazada (terminal), guarda rechazo_id + motivo', () async {
    await insertar('r', 'item-A');
    stubPost(_err(409, data: {
      'detail': {
        'tipo': 'rechazo',
        'rechazo_id': 'rzo-9',
        'motivo': 'transicion_invalida',
        'mensaje': 'no válida',
      },
    }),);

    await ciclo().ejecutar();
    final f = await leer('r');
    expect(f.estado, EstadoSyncLocal.rechazada.valor);
    expect(f.rechazoId, 'rzo-9');
    expect(f.motivo, MotivoSync.rechazoNegocio.valor);
    expect(f.ultimoError, contains('transicion_invalida'));
    expect(f.ultimoErrorCodigo, 409);
  });

  test('409 solicitud_en_proceso → transitorio PERO suma intentos_servidor (A1)',
      () async {
    await insertar('r', 'item-A');
    stubPost(_err(409, data: {
      'detail': {'tipo': 'solicitud_en_proceso', 'mensaje': 'en vuelo'},
    }),);

    await ciclo().ejecutar();
    final f = await leer('r');
    expect(f.estado, EstadoSyncLocal.pendiente.valor);
    expect(f.motivo, MotivoSync.fallaServidor.valor);
    expect(f.intentosServidor, 1);
    expect(f.intentosRed, 0);
  });

  test('409 sin Map (detail string) → otro 4xx → intentos_servidor', () async {
    await insertar('r', 'item-A');
    stubPost(_err(409, data: {'detail': 'texto plano'}));

    await ciclo().ejecutar();
    final f = await leer('r');
    expect(f.estado, EstadoSyncLocal.pendiente.valor);
    expect(f.intentosServidor, 1);
  });

  test('501 → otro 4xx-ish → intentos_servidor (NO transitorio de red)', () async {
    await insertar('r', 'item-A');
    stubPost(_err(501, data: {'detail': 'no implementado'}));

    await ciclo().ejecutar();
    final f = await leer('r');
    expect(f.estado, EstadoSyncLocal.pendiente.valor);
    expect(f.intentosServidor, 1);
    expect(f.intentosRed, 0);
  });

  test('500 → transitorio de red → intentos_red', () async {
    await insertar('r', 'item-A');
    stubPost(_err(500, data: {'detail': 'boom'}));

    await ciclo().ejecutar();
    final f = await leer('r');
    expect(f.estado, EstadoSyncLocal.pendiente.valor);
    expect(f.intentosRed, 1);
    expect(f.intentosServidor, 0);
  });

  test('sin respuesta (red/timeout) → transitorio de red → intentos_red', () async {
    await insertar('r', 'item-A');
    stubPost(_err(null));

    await ciclo().ejecutar();
    final f = await leer('r');
    expect(f.estado, EstadoSyncLocal.pendiente.valor);
    expect(f.intentosRed, 1);
  });

  test('429 SIN Retry-After → intentos_red, backoff con jitter (Random=0.5)', () async {
    await insertar('r', 'item-A');
    stubPost(_err(429, data: {'detail': 'slow down'}));

    await ciclo(random: _RandomFijo(0.5)).ejecutar();
    final f = await leer('r');
    expect(f.intentosRed, 1);
    // n=1 → cap = min(30s·2^1, 30min) = 60s; jitter 0.5 → 30s.
    expect(f.proximoIntentoEn, ahora.add(const Duration(seconds: 30)));
  });

  test('429 CON Retry-After: Retry-After es el PISO del backoff', () async {
    await insertar('r', 'item-A');
    stubPost(_err(429,
        data: {'detail': 'slow down'},
        headers: {'retry-after': ['120']},),);

    // jitter 0.5 daría 30s, pero Retry-After=120s es mayor → gana el piso.
    await ciclo(random: _RandomFijo(0.5)).ejecutar();
    final f = await leer('r');
    expect(f.proximoIntentoEn, ahora.add(const Duration(seconds: 120)));
  });

  test('401 → PAUSA: fila a pendiente sin contadores, corrida ABORTA (≥3 filas)',
      () async {
    // 3 ítems distintos → 3 filas reclamables. La 2ª (por secuencia) da 401.
    await insertar('A', 'item-A'); // secuencia 1
    await insertar('B', 'item-B'); // secuencia 2
    await insertar('C', 'item-C'); // secuencia 3

    var n = 0;
    when(() => dio.post<void>(any(),
            data: any(named: 'data'), options: any(named: 'options'),),)
        .thenAnswer((_) async {
      n++;
      if (n == 1) return Response<void>(requestOptions: RequestOptions(path: '/'));
      throw _err(401, data: {'detail': 'token vencido'});
    });

    var sesionVencida = false;
    await ciclo(alSesionVencida: () => sesionVencida = true).ejecutar();

    expect(n, 2, reason: 'solo A y B se enviaron; C no (la corrida abortó)');
    expect(sesionVencida, isTrue);
    expect((await leer('A')).estado, EstadoSyncLocal.sincronizado.valor);
    // B: 401 → vuelve a pendiente SIN sumar contadores.
    final b = await leer('B');
    expect(b.estado, EstadoSyncLocal.pendiente.valor);
    expect(b.intentosRed, 0);
    expect(b.intentosServidor, 0);
    expect(b.proximoIntentoEn, isNull); // sin backoff: reintenta al volver la sesión
    // C: ni se tocó.
    final c = await leer('C');
    expect(c.estado, EstadoSyncLocal.pendiente.valor);
    expect(c.intentosRed, 0);
  });

  test('A4: una fila con motivo previo llega a sincronizado SIN motivo', () async {
    await db.syncDao.encolar(SyncPendientesCompanion.insert(
      id: 'r',
      idempotencyKey: 'idem-r',
      empresaId: 'emp-1',
      usuarioId: 'user-1',
      instalacionId: 'inst-1',
      tipoEntidad: 'item',
      entidadId: 'item-A',
      accion: 'cambio_estado_item',
      payload: '{"nuevo_estado":"en_progreso"}',
      payloadVersion: 1,
      creadoEnDispositivo: DateTime.utc(2026, 1, 1),
      estado: const Value('pendiente'),
      motivo: const Value('error_transitorio'), // motivo de un intento anterior
      intentosRed: const Value(2),
    ),);
    when(() => dio.post<void>(any(),
            data: any(named: 'data'), options: any(named: 'options'),),)
        .thenAnswer((_) async => Response<void>(
              requestOptions: RequestOptions(path: '/'),
            ),);

    await ciclo().ejecutar();
    final f = await leer('r');
    expect(f.estado, EstadoSyncLocal.sincronizado.valor);
    expect(f.motivo, isNull); // A4: NO arrastra el motivo previo
  });
}
