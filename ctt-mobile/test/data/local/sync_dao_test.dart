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
import 'package:flutter/foundation.dart' show debugPrint;
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
    String entidadId = 'item-1',
    String? conflictoId,
  }) async {
    await db.syncDao.encolar(SyncPendientesTableCompanion.insert(
      id: id,
      tipoEntidad: 'item',
      entidadId: entidadId,
      accion: 'cambio_estado_item',
      payload: '{}',
      timestampDispositivo: DateTime.utc(2026, 1, 1),
      dispositivoId: 'dev-1',
      estado: Value(estado),
      reintentos: Value(reintentos),
      conflictoId: Value(conflictoId),
    ),);
    return id;
  }

  Future<SyncPendientesTableData> leer(String id) =>
      (db.select(db.syncPendientesTable)..where((t) => t.id.equals(id)))
          .getSingle();

  /// Inserta un ítem en caché con el flag de conflicto en el valor dado.
  Future<void> insertarItem(String id, {required bool conflicto}) =>
      db.itemsCacheDao.guardarItem(ItemsCacheTableCompanion.insert(
        id: id,
        proyectoId: 'p1',
        nombre: 'Tarea $id',
        estado: 'abierto',
        updatedAt: DateTime.utc(2026, 1, 1),
        cachadoEn: DateTime.utc(2026, 1, 1),
        tieneConflicto: Value(conflicto),
      ),);

  Future<bool> flag(String itemId) async =>
      (await db.itemsCacheDao.obtenerPorId(itemId))!.tieneConflicto;

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

  group('(f) aplicarDecision es el escritor único de tiene_conflicto (CTT-117 t3)',
      () {
    test('entra a esperando_resolucion → enciende el flag del ítem, en la '
        'MISMA corrida', () async {
      await insertarItem('item-1', conflicto: false);
      final id = await encolar(estado: 'pendiente'); // entidadId por defecto: item-1
      final decision = decidir(
        estadoActual: EstadoSyncLocal.pendiente,
        senal: SenalSync.conflictoDetectado,
        reintentos: 0,
      );

      await db.syncDao.aplicarDecision(
        id,
        estadoEsperado: EstadoSyncLocal.pendiente,
        decision: decision,
        reintentosActuales: 0,
        conflictoId: 'c-1',
      );

      final fila = await leer(id);
      expect(fila.estado, EstadoSyncLocal.esperandoResolucion.valor);
      expect(await flag('item-1'), isTrue);
    });

    test('sale de esperando_resolucion a terminal → apaga el flag', () async {
      await insertarItem('item-2', conflicto: true);
      final id = await encolar(
        id: 'e2',
        estado: 'esperando_resolucion',
        entidadId: 'item-2',
        conflictoId: 'c-2',
      );
      final decision = decidir(
        estadoActual: EstadoSyncLocal.esperandoResolucion,
        senal: SenalSync.resolucionGanoServidor,
        reintentos: 0,
      );

      await db.syncDao.aplicarDecision(
        id,
        estadoEsperado: EstadoSyncLocal.esperandoResolucion,
        decision: decision,
        reintentosActuales: 0,
      );

      expect((await leer(id)).estado, EstadoSyncLocal.descartado.valor);
      expect(await flag('item-2'), isFalse);
    });

    test('entidadId ausente de items_cache: la fila de la cola se cierra igual '
        'Y el no-op deja rastro observable', () async {
      // Capturar el rastro de debugPrint (restaurado en tearDown).
      final trazas = <String>[];
      final debugPrintAnterior = debugPrint;
      debugPrint = (message, {wrapWidth}) => trazas.add(message ?? '');
      addTearDown(() => debugPrint = debugPrintAnterior);

      final id = await encolar(estado: 'pendiente', entidadId: 'item-fantasma');
      final decision = decidir(
        estadoActual: EstadoSyncLocal.pendiente,
        senal: SenalSync.conflictoDetectado,
        reintentos: 0,
      );

      await db.syncDao.aplicarDecision(
        id,
        estadoEsperado: EstadoSyncLocal.pendiente,
        decision: decision,
        reintentosActuales: 0,
        conflictoId: 'c-3',
      );

      // La fila de la cola se cerró igual.
      expect((await leer(id)).estado, EstadoSyncLocal.esperandoResolucion.valor);
      expect(await db.itemsCacheDao.obtenerPorId('item-fantasma'), isNull);
      // Y el no-op del flag dejó rastro (no pasó en silencio).
      expect(
        trazas.any(
          (t) => t.contains('item-fantasma') && t.contains('items_cache'),
        ),
        isTrue,
        reason: 'El update no-op de tiene_conflicto debe loguearse, trazas=$trazas',
      );
    });

    test('transición que no toca esperando_resolucion NO altera el flag', () async {
      await insertarItem('item-4', conflicto: true); // centinela
      final id = await encolar(id: 'e4', estado: 'enviando', entidadId: 'item-4');
      final decision = decidir(
        estadoActual: EstadoSyncLocal.enviando,
        senal: SenalSync.rechazoDefinitivo,
        reintentos: 0,
      );

      await db.syncDao.aplicarDecision(
        id,
        estadoEsperado: EstadoSyncLocal.enviando,
        decision: decision,
        reintentosActuales: 0,
      );

      expect((await leer(id)).estado, EstadoSyncLocal.descartado.valor);
      expect(await flag('item-4'), isTrue); // intacto
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
