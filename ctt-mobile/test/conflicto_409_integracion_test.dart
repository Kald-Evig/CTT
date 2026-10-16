/// conflicto_409_integracion_test.dart — CTT-148: con "encolar primero" hay UN solo
/// camino al servidor (ciclo_sync). Este test verifica que el ciclo clasifica el 409 y
/// el 4xx-con-rechazo_id en la señal de dominio correcta (SenalSync → decidir →
/// aplicarDecision). El camino online directo (transicion_service._manejar409) se retiró.
///
/// Se mockea el DAO (mocktail): verificamos la DecisionSync y el companion `extra` con
/// que se aplica la entrada.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:ctt_mobile/core/device/device_id_service.dart';
import 'package:ctt_mobile/core/sync/ciclo_sync.dart';
import 'package:ctt_mobile/core/sync/decision_sync.dart';
import 'package:ctt_mobile/data/local/daos/sync_dao.dart';
import 'package:ctt_mobile/data/local/database.dart';
import 'package:ctt_mobile/domain/enums/enums_ctt.dart';

class _MockDio extends Mock implements Dio {}

class _MockSyncDao extends Mock implements SyncDao {}

class _MockDeviceIdService extends Mock implements DeviceIdService {}

/// Body 409 de concurrencia con la forma REAL de FastAPI: conflicto_id anidado en detail.
const _bodyConflicto =
    '{"detail":{"tipo":"conflicto_concurrencia","conflicto_id":"b5a160d2-d97f-411c-9ef5-0172935f6f1c","mensaje":"El ítem fue modificado en el servidor.","estado_servidor":"problema"}}';

/// detail String: rechazo no determinista de negocio SIN rechazo_id (solicitud en
/// proceso u otro 409 sin id) → transitorio (fallaServidor), nunca invisible.
const _detalleString =
    'El ítem está en PROBLEMA. Debe cerrarse el problema antes de cambiar de estado.';

/// 409 con rechazo_id: el backend, bajo X-Sync-Origen: cola, persiste la
/// TransicionInvalida y responde con rechazo_id (items.py:522-526, :603-610).
const _bodyRechazo =
    '{"detail":{"tipo":"rechazo","rechazo_id":"a1b2c3d4-0000-4000-8000-000000000009","motivo":"transicion_invalida","mensaje":"Transición inválida."}}';

DioException _err(int status, Object? data) {
  final ro = RequestOptions(path: '/items/x/transicion');
  return DioException(
    requestOptions: ro,
    response: Response<dynamic>(requestOptions: ro, statusCode: status, data: data),
    type: DioExceptionType.badResponse,
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(Options());
    registerFallbackValue(EstadoSyncLocal.pendiente);
    registerFallbackValue(const DecisionSync(nuevoEstado: EstadoSyncLocal.pendiente));
    registerFallbackValue(const SyncPendientesCompanion());
  });

  late _MockDio dio;
  late _MockSyncDao syncDao;
  late CicloSync ciclo;

  SyncPendiente entrada() => SyncPendiente(
        secuencia: 1,
        id: 'entry-1',
        idempotencyKey: 'idem-1',
        empresaId: 'emp-1',
        usuarioId: 'user-1',
        instalacionId: 'inst-1',
        tipoEntidad: 'item',
        entidadId: '82893973',
        accion: 'cambio_estado_item',
        payload: jsonEncode({'nuevo_estado': 'pendiente_revision'}),
        payloadVersion: 1,
        creadoEnDispositivo: DateTime.utc(2026, 8, 28, 22, 38, 44),
        estado: 'pendiente',
        acknowledged: false,
        intentosRed: 0,
        intentosServidor: 0,
      );

  setUp(() {
    dio = _MockDio();
    syncDao = _MockSyncDao();
    final deviceIdService = _MockDeviceIdService();
    when(() => deviceIdService.obtener()).thenAnswer((_) async => 'inst-1');
    ciclo = CicloSync(
      syncDao: syncDao,
      dio: dio,
      deviceIdService: deviceIdService,
      isolateLabel: 'test',
    );
    when(() => syncDao.filasReclamables(any()))
        .thenAnswer((_) async => [entrada()]);
    when(() => syncDao.reclamar(
          any(),
          tomadoPor: any(named: 'tomadoPor'),
          ahora: any(named: 'ahora'),
          tomadoHasta: any(named: 'tomadoHasta'),
        ),).thenAnswer((_) async => true);
    when(() => syncDao.aplicarDecision(
          any(),
          estadoEsperado: any(named: 'estadoEsperado'),
          decision: any(named: 'decision'),
          tomadoPor: any(named: 'tomadoPor'),
          extra: any(named: 'extra'),
          estadoServidor: any(named: 'estadoServidor'),
        ),).thenAnswer((_) async => 1);
    // El ciclo reconcilia (pull) al final; con la espera vacía es no-op.
    when(() => syncDao.ultimaReconciliacion()).thenAnswer((_) async => null);
    when(() => syncDao.obtenerEnEsperaResolucion()).thenAnswer((_) async => []);
  });

  /// Captura la DecisionSync y el companion [extra] con que se aplicó la entrada.
  (DecisionSync, SyncPendientesCompanion) capturarDecision() {
    final args = verify(() => syncDao.aplicarDecision(
          'entry-1',
          estadoEsperado: EstadoSyncLocal.enviando,
          decision: captureAny(named: 'decision'),
          tomadoPor: any(named: 'tomadoPor'),
          extra: captureAny(named: 'extra'),
          estadoServidor: any(named: 'estadoServidor'),
        ),).captured;
    return (args[0] as DecisionSync, args[1] as SyncPendientesCompanion);
  }

  test('409 de concurrencia: la entrada va a esperando_resolucion con el id', () async {
    when(() => dio.post<Map<String, dynamic>>(any(),
            data: any(named: 'data'), options: any(named: 'options'),),)
        .thenThrow(_err(409, jsonDecode(_bodyConflicto)));

    await ciclo.ejecutar();

    final (decision, extra) = capturarDecision();
    expect(decision.nuevoEstado, EstadoSyncLocal.esperandoResolucion);
    expect(decision.motivo, MotivoSync.conflicto);
    expect(extra.conflictoId.value, 'b5a160d2-d97f-411c-9ef5-0172935f6f1c');
  });

  test('409 con rechazo_id (transicion_invalida): rechazada terminal con rechazo_id',
      () async {
    when(() => dio.post<Map<String, dynamic>>(any(),
            data: any(named: 'data'), options: any(named: 'options'),),)
        .thenThrow(_err(409, jsonDecode(_bodyRechazo)));

    await ciclo.ejecutar();

    final (decision, extra) = capturarDecision();
    expect(decision.nuevoEstado, EstadoSyncLocal.rechazada);
    expect(decision.motivo, MotivoSync.rechazoNegocio);
    expect(extra.rechazoId.value, 'a1b2c3d4-0000-4000-8000-000000000009');
  });

  test('409 con detail string (sin conflicto_id ni rechazo_id): NO descarta → '
      'falla_servidor, pendiente, intentos_servidor++', () async {
    when(() => dio.post<Map<String, dynamic>>(any(),
            data: any(named: 'data'), options: any(named: 'options'),),)
        .thenThrow(_err(409, {'detail': _detalleString}));

    await ciclo.ejecutar();

    final (decision, extra) = capturarDecision();
    expect(decision.nuevoEstado, EstadoSyncLocal.pendiente);
    expect(decision.motivo, MotivoSync.fallaServidor);
    expect(decision.incremento, IncrementoContador.servidor);
    expect(extra.intentosServidor.value, 1);
    expect(extra.ultimoError.value, _detalleString);
  });
}
