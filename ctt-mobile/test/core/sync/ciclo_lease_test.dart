/// ciclo_lease_test.dart — CTT-103 L1: lease calculado POR FILA en el ciclo.
///
/// Con envíos secuenciales largos, el lease debe calcularse con el instante real de
/// cada reclamo (no una vez al inicio de la corrida). Reloj inyectado que avanza 60s
/// por cada envío (Dio fake); se verifica, contra Drift real, que el tomado_hasta
/// escrito al reclamar cada fila == su instante de reclamo + duracionLease.
library;

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:ctt_mobile/core/device/device_id_service.dart';
import 'package:ctt_mobile/core/sync/ciclo_sync.dart';
import 'package:ctt_mobile/data/local/database.dart';

class _MockDio extends Mock implements Dio {}

class _MockDeviceIdService extends Mock implements DeviceIdService {}

void main() {
  setUpAll(() => registerFallbackValue(Options()));

  late BaseDatosCTT db;
  setUp(() => db = BaseDatosCTT.conConexion(NativeDatabase.memory()));
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

  test('el lease se calcula por fila: tomado_hasta == instante del reclamo + '
      'duracionLease, y nunca <= ese instante', () async {
    // Tres ítems distintos → las tres filas son reclamables en la misma corrida.
    await insertar('A', 'item-A'); // secuencia 1
    await insertar('B', 'item-B'); // secuencia 2
    await insertar('C', 'item-C'); // secuencia 3

    final t0 = DateTime.utc(2026, 5, 1, 12);
    var t = t0;
    final dio = _MockDio();
    final deviceIdService = _MockDeviceIdService();
    when(() => deviceIdService.obtener()).thenAnswer((_) async => 'inst-1');
    // Cada envío tarda 60s: avanza el reloj. Devuelve 2xx → envioOk.
    when(() => dio.post<void>(any(),
            data: any(named: 'data'), options: any(named: 'options'),),)
        .thenAnswer((_) async {
      t = t.add(const Duration(seconds: 60));
      return Response<void>(requestOptions: RequestOptions(path: '/'));
    });

    final ciclo = CicloSync(
      syncDao: db.syncDao,
      dio: dio,
      deviceIdService: deviceIdService,
      isolateLabel: 'test',
      reloj: () => t,
    );

    await ciclo.ejecutar();

    // Instante de reclamo de cada fila: A en t0, B en t0+60s, C en t0+120s (cada
    // envío previo avanzó el reloj 60s). tomado_hasta = instante + duracionLease.
    final lease = CicloSync.duracionLease;
    for (final (i, id) in ['A', 'B', 'C'].indexed) {
      final instanteReclamo = t0.add(Duration(seconds: 60 * i));
      final fila = await leer(id);
      expect(fila.estado, 'sincronizado'); // se envió OK
      expect(fila.tomadoHasta, instanteReclamo.add(lease),
          reason: 'tomado_hasta de $id debe ser su instante de reclamo + lease',);
      expect(fila.tomadoHasta!.isAfter(instanteReclamo), isTrue,
          reason: 'el lease de $id no puede nacer ya vencido',);
    }
  });
}
