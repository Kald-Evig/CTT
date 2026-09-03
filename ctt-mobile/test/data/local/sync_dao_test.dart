/// sync_dao_test.dart — CTT-117 tramo 2.
///
/// Ejercita aplicarDecision contra una BD Drift REAL (in-memory), no un mock.
/// Un mock prueba que el método se llamó; esto prueba que la FILA se movió — que
/// es lo que el criterio 2 del ticket exige (una transición de salida ejercida
/// por el código). Cubre además la guarda anti-carrera (el modo de falla del
/// defecto 2 de CTT-115) y el incremento de reintentos, que hasta ahora solo
/// estaba probado en la función pura y no en quien lo escribe: el DAO.
library;

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:ctt_mobile/core/sync/ciclo_sync.dart';
import 'package:ctt_mobile/core/sync/decision_sync.dart';
import 'package:ctt_mobile/data/local/database.dart';
import 'package:ctt_mobile/domain/enums/enums_ctt.dart';

class _MockDio extends Mock implements Dio {}

/// DioException con statusCode y body dados (forma de FastAPI: `{"detail": ...}`).
DioException _err(int status, Object? data) {
  final ro = RequestOptions(path: '/items/x/transicion');
  return DioException(
    requestOptions: ro,
    response: Response<dynamic>(
      requestOptions: ro,
      statusCode: status,
      data: data,
    ),
    type: DioExceptionType.badResponse,
  );
}

void main() {
  late BaseDatosCTT db;

  setUpAll(() => registerFallbackValue(Options()));
  setUp(() => db = BaseDatosCTT.conConexion(NativeDatabase.memory()));
  tearDown(() => db.close());

  /// Inserta una fila en un estado/reintentos dados y devuelve su id.
  Future<String> encolar({
    String id = 'e1',
    String estado = 'pendiente',
    int reintentos = 0,
  }) async {
    await db.syncDao.encolar(SyncPendientesTableCompanion.insert(
      id: id,
      tipoEntidad: 'item',
      entidadId: 'item-1',
      accion: 'cambio_estado_item',
      payload: '{}',
      timestampDispositivo: DateTime.utc(2026, 1, 1),
      dispositivoId: 'dev-1',
      estado: Value(estado),
      reintentos: Value(reintentos),
    ),);
    return id;
  }

  Future<SyncPendientesTableData> leer(String id) =>
      (db.select(db.syncPendientesTable)..where((t) => t.id.equals(id)))
          .getSingle();

  test('(a) guarda coincide: retorna 1, mueve la fila y escribe motivo + '
      'conflicto_id', () async {
    final id = await encolar(estado: 'pendiente');
    final decision = decidir(
      estadoActual: EstadoSyncLocal.pendiente,
      senal: SenalSync.conflictoDetectado,
      reintentos: 0,
    );

    final afectadas = await db.syncDao.aplicarDecision(
      id,
      estadoEsperado: EstadoSyncLocal.pendiente,
      decision: decision,
      reintentosActuales: 0,
      conflictoId: 'conf-123',
    );

    expect(afectadas, 1);
    final fila = await leer(id);
    expect(fila.estado, EstadoSyncLocal.esperandoResolucion.valor);
    expect(fila.motivo, MotivoSync.conflicto.valor);
    expect(fila.conflictoId, 'conf-123');
  });

  test('(b) guarda NO coincide (defecto 2 de CTT-115): retorna 0 y la fila NO '
      'se mueve', () async {
    final id = await encolar(estado: 'pendiente');

    // Igual que el bug viejo: se espera 'enviando' pero la fila está 'pendiente'.
    final afectadas = await db.syncDao.aplicarDecision(
      id,
      estadoEsperado: EstadoSyncLocal.enviando,
      decision: const DecisionSync(
        nuevoEstado: EstadoSyncLocal.descartado,
        motivo: MotivoSync.rechazoNegocio,
      ),
      reintentosActuales: 0,
    );

    expect(afectadas, 0);
    final fila = await leer(id);
    expect(fila.estado, EstadoSyncLocal.pendiente.valor); // intacta
    expect(fila.motivo, isNull);
  });

  group('(c) incremento de reintentos lo escribe el DAO', () {
    test('incrementaReintentos: true deja N+1', () async {
      final id = await encolar(estado: 'enviando', reintentos: 2);

      await db.syncDao.aplicarDecision(
        id,
        estadoEsperado: EstadoSyncLocal.enviando,
        decision: const DecisionSync(
          nuevoEstado: EstadoSyncLocal.pendiente,
          motivo: MotivoSync.errorTransitorio,
          incrementaReintentos: true,
        ),
        reintentosActuales: 2,
      );

      expect((await leer(id)).reintentos, 3);
    });

    test('incrementaReintentos: false deja los reintentos intactos', () async {
      final id = await encolar(estado: 'enviando', reintentos: 2);

      await db.syncDao.aplicarDecision(
        id,
        estadoEsperado: EstadoSyncLocal.enviando,
        decision: const DecisionSync(nuevoEstado: EstadoSyncLocal.sincronizado),
        reintentosActuales: 2,
      );

      expect((await leer(id)).reintentos, 2);
    });
  });

  // ── Camino de la COLA contra Drift real (CTT-115) ────────────────────────────
  // Se maneja CicloSync con un SyncDao real (no mock) y un Dio mockeado (la red).
  // Un mock del DAO probaría que se llamó; esto prueba que la fila QUEDÓ escrita
  // en ultimo_error — que es lo que la regresión perdía.
  group('(d/e) ciclo_sync persiste el detalle del backend en ultimo_error', () {
    late _MockDio dio;
    late CicloSync ciclo;

    setUp(() {
      dio = _MockDio();
      ciclo = CicloSync(syncDao: db.syncDao, dio: dio);
    });

    test('(d) rechazo de negocio (409 con detail string) por la cola: la fila '
        'termina descartada, motivo rechazo_negocio y ultimo_error con el '
        'mensaje del backend', () async {
      const detalle = 'El ítem está en PROBLEMA. Debe cerrarse el problema '
          'antes de cambiar de estado.';
      final id = await encolar(estado: 'pendiente');
      when(() => dio.post<void>(any(),
              data: any(named: 'data'), options: any(named: 'options'),),)
          .thenThrow(_err(409, {'detail': detalle}));

      await ciclo.ejecutar();

      final fila = await leer(id);
      expect(fila.estado, EstadoSyncLocal.descartado.valor);
      expect(fila.motivo, MotivoSync.rechazoNegocio.valor);
      expect(fila.ultimoError, detalle);
    });

    test('(e) falla transitoria: ultimo_error refleja el detalle del ÚLTIMO '
        'intento, no el del primero', () async {
      final id = await encolar(estado: 'pendiente', reintentos: 0);
      // Dos ciclos, dos mensajes distintos. Value(detalle) en aplicarDecision
      // sobrescribe cuando no es null → debe ganar el segundo.
      final mensajes = ['503 intento-1', '503 intento-2'];
      var i = 0;
      when(() => dio.post<void>(any(),
              data: any(named: 'data'), options: any(named: 'options'),),)
          .thenAnswer((_) async {
        final msg = mensajes[i];
        i++;
        throw _err(503, {'detail': msg});
      });

      await ciclo.ejecutar(); // intento 1 → pendiente, reintentos=1, ultimo=intento-1
      await ciclo.ejecutar(); // intento 2 → pendiente, reintentos=2, ultimo=intento-2

      final fila = await leer(id);
      expect(fila.estado, EstadoSyncLocal.pendiente.valor);
      expect(fila.reintentos, 2);
      expect(fila.ultimoError, '503 intento-2'); // el último, no 'intento-1'
    });
  });
}
