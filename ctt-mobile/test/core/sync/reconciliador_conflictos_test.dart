/// reconciliador_conflictos_test.dart — CTT-117 tramo 3.
///
/// Ejercita el reconciliador contra una BD Drift REAL (in-memory) y un Dio
/// mockeado (la red). Verifica las TRES ramas de la regla corregida (aprobada por
/// Kald), incluida la rama 2 que NO descarta conflictos aún pendientes server-side:
///   1. conflictoId en /mios con version 'local'/'servidor' → cliente/servidor.
///   3a. conflictoId nulo (heredado sin id casable)         → heredadoIndeterminado.
///   3b. conflictoId en /mios con version null              → heredadoIndeterminado.
///   2.  conflictoId NO en /mios (sigue pendiente)          → NO-OP, fila intacta.
/// Y que apaga items_cache.tiene_conflicto solo cuando la fila llega a terminal.
library;

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:ctt_mobile/core/sync/reconciliador_conflictos.dart';
import 'package:ctt_mobile/data/local/database.dart';
import 'package:ctt_mobile/domain/enums/enums_ctt.dart';

class _MockDio extends Mock implements Dio {}

void main() {
  late BaseDatosCTT db;
  late _MockDio dio;
  late ReconciliadorConflictos reconciliador;

  setUp(() {
    db = BaseDatosCTT.conConexion(NativeDatabase.memory());
    dio = _MockDio();
    reconciliador = ReconciliadorConflictos(
      syncDao: db.syncDao,
      dio: dio,
    );
  });
  tearDown(() => db.close());

  /// Inserta una fila ya parqueada en esperando_resolucion con el conflictoId dado.
  Future<void> parquear({
    required String id,
    required String entidadId,
    String? conflictoId,
  }) =>
      db.syncDao.encolar(SyncPendientesTableCompanion.insert(
        id: id,
        tipoEntidad: 'item',
        entidadId: entidadId,
        accion: 'cambio_estado_item',
        payload: '{}',
        timestampDispositivo: DateTime.utc(2026, 1, 1),
        dispositivoId: 'dev-1',
        estado: const Value('esperando_resolucion'),
        motivo: const Value('conflicto'),
        conflictoId: Value(conflictoId),
      ),);

  /// Inserta un ítem en caché con el flag de conflicto encendido.
  Future<void> itemConConflicto(String id) =>
      db.itemsCacheDao.guardarItem(ItemsCacheTableCompanion.insert(
        id: id,
        proyectoId: 'p1',
        nombre: 'Tarea $id',
        estado: 'abierto',
        updatedAt: DateTime.utc(2026, 1, 1),
        cachadoEn: DateTime.utc(2026, 1, 1),
        tieneConflicto: const Value(true),
      ),);

  Future<SyncPendientesTableData> leer(String id) =>
      (db.select(db.syncPendientesTable)..where((t) => t.id.equals(id)))
          .getSingle();

  Future<bool> flag(String itemId) async {
    final it = await db.itemsCacheDao.obtenerPorId(itemId);
    return it!.tieneConflicto;
  }

  /// Mockea GET /mios con la lista de conflictos resueltos dada.
  void mockMios(List<Map<String, dynamic>> conflictos) {
    when(() => dio.get<List<dynamic>>('/sync/conflictos/mios')).thenAnswer(
      (_) async => Response<List<dynamic>>(
        requestOptions: RequestOptions(path: '/sync/conflictos/mios'),
        data: conflictos,
      ),
    );
  }

  test('rama 1 — version "local" → sincronizado/conflicto_resuelto_cliente, '
      'apaga el flag', () async {
    await itemConConflicto('item-A');
    await parquear(id: 'e1', entidadId: 'item-A', conflictoId: 'c-A');
    mockMios([
      {'id': 'c-A', 'version_ganadora': 'local'},
    ]);

    final consulto = await reconciliador.reconciliar();

    expect(consulto, isTrue);
    final f = await leer('e1');
    expect(f.estado, EstadoSyncLocal.sincronizado.valor);
    expect(f.motivo, MotivoSync.conflictoResueltoCliente.valor);
    expect(await flag('item-A'), isFalse);
  });

  test('rama 1 — version "servidor" → descartado/conflicto_resuelto_servidor, '
      'apaga el flag', () async {
    await itemConConflicto('item-B');
    await parquear(id: 'e2', entidadId: 'item-B', conflictoId: 'c-B');
    mockMios([
      {'id': 'c-B', 'version_ganadora': 'servidor'},
    ]);

    await reconciliador.reconciliar();

    final f = await leer('e2');
    expect(f.estado, EstadoSyncLocal.descartado.valor);
    expect(f.motivo, MotivoSync.conflictoResueltoServidor.valor);
    expect(await flag('item-B'), isFalse);
  });

  test('rama 3b — en /mios con version null → descartado/heredado_indeterminado',
      () async {
    await itemConConflicto('item-C');
    await parquear(id: 'e3', entidadId: 'item-C', conflictoId: 'c-C');
    mockMios([
      {'id': 'c-C', 'version_ganadora': null},
    ]);

    await reconciliador.reconciliar();

    final f = await leer('e3');
    expect(f.estado, EstadoSyncLocal.descartado.valor);
    expect(f.motivo, MotivoSync.heredadoIndeterminado.valor);
    expect(await flag('item-C'), isFalse);
  });

  test('rama 3a — conflictoId nulo → descartado/heredado_indeterminado', () async {
    await itemConConflicto('item-D');
    await parquear(id: 'e4', entidadId: 'item-D', conflictoId: null);
    mockMios([]); // aunque /mios traiga algo, esta fila no puede casar

    await reconciliador.reconciliar();

    final f = await leer('e4');
    expect(f.estado, EstadoSyncLocal.descartado.valor);
    expect(f.motivo, MotivoSync.heredadoIndeterminado.valor);
    expect(await flag('item-D'), isFalse);
  });

  test('rama 2 — conflictoId presente pero NO en /mios (pendiente server-side): '
      'NO-OP, la fila queda intacta y el flag encendido', () async {
    await itemConConflicto('item-E');
    await parquear(id: 'e5', entidadId: 'item-E', conflictoId: 'c-E');
    mockMios([]); // el conflicto sigue pendiente → no aparece

    final consulto = await reconciliador.reconciliar();

    expect(consulto, isTrue); // había filas parqueadas: sí consultó
    final f = await leer('e5');
    expect(f.estado, EstadoSyncLocal.esperandoResolucion.valor); // intacta
    expect(f.motivo, MotivoSync.conflicto.valor);
    expect(await flag('item-E'), isTrue); // el flag NO se apaga
  });

  test('sin filas parqueadas → devuelve false y NO consulta /mios', () async {
    final consulto = await reconciliador.reconciliar();

    expect(consulto, isFalse);
    verifyNever(() => dio.get<List<dynamic>>(any()));
  });

  group('debounce persistido (reconciliarSiCorresponde)', () {
    final t0 = DateTime.utc(2026, 5, 1, 12, 0, 0);

    test('corrida efectiva registra el reloj; una 2da dentro de la ventana NO '
        'vuelve a consultar /mios', () async {
      // Fila en rama 2 (no en /mios): la corrida es "efectiva" (había parqueadas)
      // pero deja la fila intacta. Sirve para observar el debounce sin agotar la
      // cola entre llamadas.
      await itemConConflicto('item-X');
      await parquear(id: 'x1', entidadId: 'item-X', conflictoId: 'c-X');
      mockMios([]);

      await reconciliador.reconciliarSiCorresponde(ahora: t0);
      await reconciliador.reconciliarSiCorresponde(
        ahora: t0.add(const Duration(minutes: 1)), // < 2 min
      );

      // Solo la primera consultó el servidor.
      verify(() => dio.get<List<dynamic>>('/sync/conflictos/mios')).called(1);
      // Drift devuelve DateTime en hora LOCAL (guarda epoch); se compara el
      // instante, que es lo que usa el debounce (difference() es absoluto).
      expect((await db.syncDao.ultimaReconciliacion())!.toUtc(), t0);
    });

    test('pasada la ventana, vuelve a reconciliar', () async {
      await itemConConflicto('item-Y');
      await parquear(id: 'y1', entidadId: 'item-Y', conflictoId: 'c-Y');
      mockMios([]);

      await reconciliador.reconciliarSiCorresponde(ahora: t0);
      await reconciliador.reconciliarSiCorresponde(
        ahora: t0.add(const Duration(minutes: 3)), // > 2 min
      );

      verify(() => dio.get<List<dynamic>>('/sync/conflictos/mios')).called(2);
    });

    test('corrida VACÍA no consume la ventana: no registra reloj ni consulta',
        () async {
      await reconciliador.reconciliarSiCorresponde(ahora: t0);

      expect(await db.syncDao.ultimaReconciliacion(), isNull);
      verifyNever(() => dio.get<List<dynamic>>(any()));
    });
  });

  test('mezcla: una fila casa y otra sigue pendiente en la misma corrida',
      () async {
    await itemConConflicto('item-F');
    await itemConConflicto('item-G');
    await parquear(id: 'e6', entidadId: 'item-F', conflictoId: 'c-F');
    await parquear(id: 'e7', entidadId: 'item-G', conflictoId: 'c-G');
    mockMios([
      {'id': 'c-F', 'version_ganadora': 'servidor'},
    ]); // c-G no aparece: sigue pendiente

    await reconciliador.reconciliar();

    expect((await leer('e6')).estado, EstadoSyncLocal.descartado.valor);
    expect(await flag('item-F'), isFalse);
    expect((await leer('e7')).estado, EstadoSyncLocal.esperandoResolucion.valor);
    expect(await flag('item-G'), isTrue);
  });
}
