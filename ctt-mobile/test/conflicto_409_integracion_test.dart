/// conflicto_409_integracion_test.dart — CTT-109 / CTT-115 (adaptado a v4, CTT-117 t2).
///
/// Tests de CONDUCTA (no del helper de parseo, que ya cubre
/// extraer_conflicto_id_test.dart). Verifican los dos sitios que consumen el 409,
/// ahora sobre el modelo de decisión v4 (SenalSync → decidir → aplicarDecision):
///   - Camino online: transicion_service._manejar409 — ENCOLA y parquea la fila
///     en esperando_resolucion (la rama que impedía la pérdida de trabajo).
///   - Camino cola:   ciclo_sync — clasifica el 409 en señal de dominio.
///
/// Se mockea el DAO (mocktail): BaseDatosCTT solo abre un archivo real vía
/// path_provider; verificamos las LLAMADAS al DAO, que es la conducta pedida.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:ctt_mobile/core/device/device_id_service.dart';
import 'package:ctt_mobile/core/sync/ciclo_sync.dart';
import 'package:ctt_mobile/core/sync/decision_sync.dart';
import 'package:ctt_mobile/core/sync/resultado_transicion.dart';
import 'package:ctt_mobile/core/sync/transicion_service.dart';
import 'package:ctt_mobile/data/local/daos/items_cache_dao.dart';
import 'package:ctt_mobile/data/local/daos/sync_dao.dart';
import 'package:ctt_mobile/data/local/database.dart';
import 'package:ctt_mobile/domain/enums/enums_ctt.dart';

class _MockDio extends Mock implements Dio {}

class _MockSyncDao extends Mock implements SyncDao {}

class _MockItemsCacheDao extends Mock implements ItemsCacheDao {}

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
    registerFallbackValue(EstadoSyncLocal.pendiente);
    registerFallbackValue(
      const DecisionSync(nuevoEstado: EstadoSyncLocal.pendiente),
    );
  });

  // ── Camino online: transicion_service._manejar409 ──────────────────────────
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
      when(() => syncDao.aplicarDecision(
            any(),
            estadoEsperado: any(named: 'estadoEsperado'),
            decision: any(named: 'decision'),
            reintentosActuales: any(named: 'reintentosActuales'),
            conflictoId: any(named: 'conflictoId'),
            detalle: any(named: 'detalle'),
          ),).thenAnswer((_) async => 1);
    });

    test('409 de concurrencia (body real): extrae el id, ENCOLA el cambio y '
        'lo parquea en esperando_resolucion con el conflicto_id', () async {
      when(() => dio.post<Map<String, dynamic>>(any(),
              data: any(named: 'data'), options: any(named: 'options'),),)
          .thenThrow(_err409(jsonDecode(_bodyConflicto)));

      final r = await service.ejecutar(
        itemId: '82893973',
        nuevoEstado: 'pendiente_revision',
      );

      // (1) Resultado tipado con el id extraído del detail anidado.
      expect(r, isA<TransicionConConflicto>());
      expect((r as TransicionConConflicto).conflictoId,
          'b5a160d2-d97f-411c-9ef5-0172935f6f1c',);

      // (2) El cambio QUEDÓ ENCOLADO (criterio anti-pérdida-de-trabajo).
      final capturado = verify(() => syncDao.encolar(captureAny())).captured;
      expect(capturado, hasLength(1));
      final companion = capturado.single as SyncPendientesTableCompanion;
      final idEncolado = companion.id.value;

      // (3) aplicarDecision movió esa entrada a esperando_resolucion con el id.
      final args = verify(() => syncDao.aplicarDecision(
            captureAny(),
            estadoEsperado: captureAny(named: 'estadoEsperado'),
            decision: captureAny(named: 'decision'),
            reintentosActuales: any(named: 'reintentosActuales'),
            conflictoId: captureAny(named: 'conflictoId'),
            detalle: any(named: 'detalle'),
          ),).captured;
      expect(args[0], idEncolado);
      expect(args[1], EstadoSyncLocal.pendiente); // estado esperado de la fila recién encolada
      expect((args[2] as DecisionSync).nuevoEstado,
          EstadoSyncLocal.esperandoResolucion,);
      expect((args[2] as DecisionSync).motivo, MotivoSync.conflicto);
      expect(args[3], 'b5a160d2-d97f-411c-9ef5-0172935f6f1c');
    });

    test('409 con detail string: NO encola, NO aplica decisión, '
        'devuelve TransicionRechazada', () async {
      when(() => dio.post<Map<String, dynamic>>(any(),
              data: any(named: 'data'), options: any(named: 'options'),),)
          .thenThrow(_err409({'detail': _detalleString}));

      final r = await service.ejecutar(
        itemId: '82893973',
        nuevoEstado: 'pendiente_revision',
      );

      expect(r, isA<TransicionRechazada>());
      expect((r as TransicionRechazada).detalle, _detalleString);
      verifyNever(() => syncDao.encolar(any()));
      verifyNever(() => syncDao.aplicarDecision(
            any(),
            estadoEsperado: any(named: 'estadoEsperado'),
            decision: any(named: 'decision'),
            reintentosActuales: any(named: 'reintentosActuales'),
            conflictoId: any(named: 'conflictoId'),
            detalle: any(named: 'detalle'),
          ),);
    });

    test('409 con detail objeto SIN conflicto_id: no revienta, no encola', () async {
      when(() => dio.post<Map<String, dynamic>>(any(),
              data: any(named: 'data'), options: any(named: 'options'),),)
          .thenThrow(_err409({
        'detail': {'tipo': 'otro', 'mensaje': 'algo'},
      }),);

      final r = await service.ejecutar(
        itemId: '82893973',
        nuevoEstado: 'pendiente_revision',
      );

      expect(r, isA<TransicionRechazada>());
      verifyNever(() => syncDao.encolar(any()));
    });
  });

  // ── Camino cola: ciclo_sync ────────────────────────────────────────────────
  group('camino cola — ciclo_sync', () {
    late _MockDio dio;
    late _MockSyncDao syncDao;
    late _MockItemsCacheDao itemsCacheDao;
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
          motivo: null,
          conflictoId: null,
          acknowledged: false,
        );

    setUp(() {
      dio = _MockDio();
      syncDao = _MockSyncDao();
      itemsCacheDao = _MockItemsCacheDao();
      ciclo = CicloSync(
        syncDao: syncDao,
        dio: dio,
        itemsCacheDao: itemsCacheDao,
      );
      when(() => syncDao.obtenerPendientes()).thenAnswer((_) async => [entrada()]);
      when(() => syncDao.marcarEnviando(any())).thenAnswer((_) async => true);
      when(() => syncDao.aplicarDecision(
            any(),
            estadoEsperado: any(named: 'estadoEsperado'),
            decision: any(named: 'decision'),
            reintentosActuales: any(named: 'reintentosActuales'),
            conflictoId: any(named: 'conflictoId'),
            detalle: any(named: 'detalle'),
          ),).thenAnswer((_) async => 1);
      // El ciclo ahora reconcilia (pull) al final de ejecutar (CTT-117 tramo 3).
      // Con la cola de espera vacía, el pull es un no-op (no consulta /mios): estos
      // tests solo ejercen la clasificación del push.
      when(() => syncDao.ultimaReconciliacion()).thenAnswer((_) async => null);
      when(() => syncDao.obtenerEnEsperaResolucion())
          .thenAnswer((_) async => []);
    });

    /// Captura la DecisionSync (y el conflicto_id) con que se aplicó la entrada.
    (DecisionSync, String?) capturarDecision() {
      final args = verify(() => syncDao.aplicarDecision(
            'entry-1',
            estadoEsperado: EstadoSyncLocal.enviando,
            decision: captureAny(named: 'decision'),
            reintentosActuales: any(named: 'reintentosActuales'),
            conflictoId: captureAny(named: 'conflictoId'),
            detalle: any(named: 'detalle'),
          ),).captured;
      return (args[0] as DecisionSync, args[1] as String?);
    }

    test('409 de concurrencia: la entrada va a esperando_resolucion con el id', () async {
      when(() => dio.post<void>(any(),
              data: any(named: 'data'), options: any(named: 'options'),),)
          .thenThrow(_err409(jsonDecode(_bodyConflicto)));

      await ciclo.ejecutar();

      final (decision, conflictoId) = capturarDecision();
      expect(decision.nuevoEstado, EstadoSyncLocal.esperandoResolucion);
      expect(decision.motivo, MotivoSync.conflicto);
      expect(conflictoId, 'b5a160d2-d97f-411c-9ef5-0172935f6f1c');
    });

    test('409 con detail string: es rechazo de negocio → descartado '
        '(conducta correcta; el rediseño cierra el defecto de CTT-115)', () async {
      when(() => dio.post<void>(any(),
              data: any(named: 'data'), options: any(named: 'options'),),)
          .thenThrow(_err409({'detail': _detalleString}));

      await ciclo.ejecutar();

      // Un 409 SIN conflicto_id es rechazo de negocio: la clasificación lo manda
      // a rechazoDefinitivo → descartado/rechazo_negocio. Antes (CTT-115) caía en
      // conflicto ante CUALQUIER 409; ahora se distingue por el id.
      final (decision, conflictoId) = capturarDecision();
      expect(decision.nuevoEstado, EstadoSyncLocal.descartado);
      expect(decision.motivo, MotivoSync.rechazoNegocio);
      expect(conflictoId, isNull);
    });
  });
}
