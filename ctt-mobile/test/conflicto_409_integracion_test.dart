/// conflicto_409_integracion_test.dart — CTT-109.
///
/// Tests de CONDUCTA (no del helper de parseo, que ya cubre
/// extraer_conflicto_id_test.dart). Verifican los dos sitios que consumen el 409:
///   - Camino online: transicion_service._manejar409 — que ENCOLA el cambio y
///     llama a marcarConflicto (la rama que impedía la pérdida de trabajo).
///   - Camino cola:   ciclo_sync — clasificación del 409.
///
/// Se mockea el DAO (mocktail) porque BaseDatosCTT solo abre un archivo real vía
/// path_provider y no expone un constructor in-memory; verificamos las LLAMADAS
/// al DAO, que es la conducta que 2.1/2.2 piden. No se toca código de producción.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:ctt_mobile/core/device/device_id_service.dart';
import 'package:ctt_mobile/core/sync/ciclo_sync.dart';
import 'package:ctt_mobile/core/sync/resultado_transicion.dart';
import 'package:ctt_mobile/core/sync/transicion_service.dart';
import 'package:ctt_mobile/data/local/daos/sync_dao.dart';
import 'package:ctt_mobile/data/local/database.dart';

class _MockDio extends Mock implements Dio {}

class _MockSyncDao extends Mock implements SyncDao {}

class _MockDeviceIdService extends Mock implements DeviceIdService {}

/// Body 409 de concurrencia con la forma REAL que emite FastAPI:
/// detail es un objeto con conflicto_id anidado.
const _bodyConflicto =
    '{"detail":{"tipo":"conflicto_concurrencia","conflicto_id":"b5a160d2-d97f-411c-9ef5-0172935f6f1c","mensaje":"El ítem fue modificado en el servidor mientras el dispositivo estaba offline.","estado_servidor":"problema"}}';

/// detail String: rechazo de la máquina de estados (items.py:453).
const _detalleString =
    'El ítem está en PROBLEMA. Debe cerrarse el problema antes de cambiar de estado.';

DioException _err409(Object? data) {
  final ro = RequestOptions(path: '/items/x/transicion');
  return DioException(
    requestOptions: ro,
    response: Response<dynamic>(requestOptions: ro, statusCode: 409, data: data),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      SyncPendientesTableCompanion.insert(
        id: 'fallback',
        tipoEntidad: 'item',
        entidadId: 'x',
        accion: 'cambio_estado_item',
        payload: '{}',
        timestampDispositivo: DateTime.utc(2020),
        dispositivoId: 'x',
      ),
    );
    registerFallbackValue(Options());
  });

  // ── 2.1 — Camino online: transicion_service._manejar409 ────────────────────
  group('camino online — _manejar409', () {
    late _MockDio dio;
    late _MockSyncDao syncDao;
    late _MockDeviceIdService deviceIdService;
    late TransicionService service;

    setUp(() {
      dio = _MockDio();
      syncDao = _MockSyncDao();
      deviceIdService = _MockDeviceIdService();
      service = TransicionService(
        dio: dio,
        syncDao: syncDao,
        deviceIdService: deviceIdService,
      );
      when(() => deviceIdService.obtener()).thenAnswer((_) async => 'device-test');
      when(() => syncDao.encolar(any())).thenAnswer((_) async {});
      when(() => syncDao.marcarConflicto(any(),
          conflictoId: any(named: 'conflictoId'))).thenAnswer((_) async {});
    });

    test('409 de concurrencia (body real): extrae el id, ENCOLA el cambio y '
        'llama marcarConflicto con el id encolado', () async {
      when(() => dio.post<Map<String, dynamic>>(any(),
              data: any(named: 'data'), options: any(named: 'options')))
          .thenThrow(_err409(jsonDecode(_bodyConflicto)));

      final r = await service.ejecutar(
        itemId: '82893973',
        nuevoEstado: 'pendiente_revision',
      );

      // (1) Resultado tipado con el id extraído del detail anidado.
      expect(r, isA<TransicionConConflicto>());
      expect((r as TransicionConConflicto).conflictoId,
          'b5a160d2-d97f-411c-9ef5-0172935f6f1c');

      // (2) El cambio QUEDÓ ENCOLADO (criterio anti-pérdida-de-trabajo).
      final capturado = verify(() => syncDao.encolar(captureAny())).captured;
      expect(capturado, hasLength(1));
      final companion = capturado.single as SyncPendientesTableCompanion;
      final idEncolado = companion.id.value;

      // (3) marcarConflicto se llamó con el entradaId recién encolado + el uuid.
      verify(() => syncDao.marcarConflicto(idEncolado,
          conflictoId: 'b5a160d2-d97f-411c-9ef5-0172935f6f1c')).called(1);
    });

    test('409 con detail string: NO encola, NO marca conflicto, '
        'devuelve TransicionRechazada', () async {
      when(() => dio.post<Map<String, dynamic>>(any(),
              data: any(named: 'data'), options: any(named: 'options')))
          .thenThrow(_err409({'detail': _detalleString}));

      final r = await service.ejecutar(
        itemId: '82893973',
        nuevoEstado: 'pendiente_revision',
      );

      expect(r, isA<TransicionRechazada>());
      expect((r as TransicionRechazada).detalle, _detalleString);
      verifyNever(() => syncDao.encolar(any()));
      verifyNever(() => syncDao.marcarConflicto(any(),
          conflictoId: any(named: 'conflictoId')));
    });

    test('409 con detail objeto SIN conflicto_id: no revienta, no encola', () async {
      when(() => dio.post<Map<String, dynamic>>(any(),
              data: any(named: 'data'), options: any(named: 'options')))
          .thenThrow(_err409({
        'detail': {'tipo': 'otro', 'mensaje': 'algo'},
      }));

      final r = await service.ejecutar(
        itemId: '82893973',
        nuevoEstado: 'pendiente_revision',
      );

      expect(r, isA<TransicionRechazada>());
      verifyNever(() => syncDao.encolar(any()));
    });
  });

  // ── 2.2 — Camino cola: ciclo_sync ──────────────────────────────────────────
  group('camino cola — ciclo_sync', () {
    late _MockDio dio;
    late _MockSyncDao syncDao;
    late CicloSync ciclo;

    SyncPendientesTableData entrada() => SyncPendientesTableData(
          id: 'entry-1',
          tipoEntidad: 'item',
          entidadId: '82893973',
          accion: 'cambio_estado_item',
          payload: jsonEncode({
            'nuevo_estado': 'pendiente_revision',
            'device_timestamp': '2026-08-28T22:38:44.000Z',
            'dispositivo_id': 'dev-1',
          }),
          timestampDispositivo: DateTime.utc(2026, 8, 28, 22, 38, 44),
          dispositivoId: 'dev-1',
          reintentos: 0,
          estado: 'pendiente',
          ultimoError: null,
          idempotencyKey: 'idem-1',
        );

    setUp(() {
      dio = _MockDio();
      syncDao = _MockSyncDao();
      ciclo = CicloSync(syncDao: syncDao, dio: dio);
      when(() => syncDao.reactivarErrores()).thenAnswer((_) async {});
      when(() => syncDao.obtenerPendientes()).thenAnswer((_) async => [entrada()]);
      when(() => syncDao.marcarEnviando(any())).thenAnswer((_) async => true);
      when(() => syncDao.marcarSincronizado(any())).thenAnswer((_) async {});
      when(() => syncDao.marcarConflicto(any(),
          conflictoId: any(named: 'conflictoId'))).thenAnswer((_) async {});
      when(() => syncDao.marcarRechazado(any(), any())).thenAnswer((_) async {});
      when(() => syncDao.marcarError(any(), any(), any())).thenAnswer((_) async {});
    });

    test('409 de concurrencia: la entrada se marca conflicto con el uuid', () async {
      when(() => dio.post<void>(any(),
              data: any(named: 'data'), options: any(named: 'options')))
          .thenThrow(_err409(jsonDecode(_bodyConflicto)));

      await ciclo.ejecutar();

      verify(() => syncDao.marcarConflicto('entry-1',
          conflictoId: 'b5a160d2-d97f-411c-9ef5-0172935f6f1c')).called(1);
      verifyNever(() => syncDao.marcarRechazado(any(), any()));
    });

    test('409 con detail string DEBE quedar rechazada, no en conflicto '
        '(conducta correcta — FALLA con el código actual, documenta el defecto '
        'de ciclo_sync.dart:64-66)', () async {
      when(() => dio.post<void>(any(),
              data: any(named: 'data'), options: any(named: 'options')))
          .thenThrow(_err409({'detail': _detalleString}));

      await ciclo.ejecutar();

      // Conducta CORRECTA: un 409 sin conflicto_id es rechazo de negocio y debe
      // marcarse rechazado. El código actual llama marcarConflicto ante CUALQUIER
      // 409, así que esta verificación falla: es la evidencia del defecto.
      verify(() => syncDao.marcarRechazado('entry-1', any())).called(1);
      verifyNever(() => syncDao.marcarConflicto(any(),
          conflictoId: any(named: 'conflictoId')));
    }, skip: 'Falla por CTT-115 — remover el skip al arreglar ese ticket');
  });
}
