/// ciclo_multipasada_test.dart — CTT-103: el ciclo drena TODA la cola elegible en una
/// sola corrida (re-consulta filasReclamables hasta que no queden filas sin intentar),
/// no una fila por agregado. Y sella sincronizado_en / ultimo_intento_en con el reloj
/// POST-respuesta.
///
/// Arnés igual a ciclo_lease_test: MockDio + reloj inyectado + Drift real en memoria.
/// Random fake (nextDouble=1.0 → backoff máximo determinista) para que una fila que
/// falla por red quede con proximo_intento_en claramente futuro.
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

class _MockDio extends Mock implements Dio {}

class _MockDeviceIdService extends Mock implements DeviceIdService {}

/// nextDouble constante = backoff máximo (sin azar) para fallas de red deterministas.
class _FakeRandom extends Fake implements Random {
  @override
  double nextDouble() => 1.0;
}

void main() {
  setUpAll(() => registerFallbackValue(Options()));

  late BaseDatosCTT db;
  setUp(() => db = BaseDatosCTT.conConexion(NativeDatabase.memory()));
  tearDown(() => db.close());

  // entidadId = agregado; `k` en el payload identifica la fila para el mock.
  Future<void> insertar(String id, String agregado) =>
      db.syncDao.encolar(SyncPendientesCompanion.insert(
        id: id,
        idempotencyKey: 'idem-$id',
        empresaId: 'emp-1',
        usuarioId: 'user-1',
        instalacionId: 'inst-1',
        tipoEntidad: 'item',
        entidadId: agregado,
        accion: 'cambio_estado_item',
        payload: '{"nuevo_estado":"en_progreso","k":"$id"}',
        payloadVersion: 1,
        creadoEnDispositivo: DateTime.utc(2026, 1, 1),
        estado: const Value('pendiente'),
      ),);

  Future<SyncPendiente> leer(String id) =>
      (db.select(db.syncPendientes)..where((t) => t.id.equals(id))).getSingle();

  /// Construye el ciclo con un MockDio cuyo POST: avanza el reloj [pasoReloj],
  /// registra el `k` enviado en [orden] y lanza DioException de red para los `k`
  /// en [fallanRed].
  ({CicloSync ciclo, List<String> orden}) armar({
    required DateTime Function() reloj,
    required void Function(Duration) avanzar,
    Duration pasoReloj = const Duration(seconds: 1),
    Set<String> fallanRed = const {},
  }) {
    final orden = <String>[];
    final dio = _MockDio();
    final deviceIdService = _MockDeviceIdService();
    when(() => deviceIdService.obtener()).thenAnswer((_) async => 'inst-1');
    when(() => dio.post<void>(any(),
        data: any(named: 'data'),
        options: any(named: 'options'),),).thenAnswer((inv) async {
      final data = inv.namedArguments[#data] as Map<String, dynamic>;
      final k = data['k'] as String;
      orden.add(k);
      avanzar(pasoReloj); // tiempo transcurrido durante el request
      if (fallanRed.contains(k)) {
        throw DioException(
          requestOptions: RequestOptions(path: '/'),
          type: DioExceptionType.connectionError,
        );
      }
      return Response<void>(requestOptions: RequestOptions(path: '/'));
    });
    final ciclo = CicloSync(
      syncDao: db.syncDao,
      dio: dio,
      deviceIdService: deviceIdService,
      isolateLabel: 'test',
      reloj: reloj,
      random: _FakeRandom(),
    );
    return (ciclo: ciclo, orden: orden);
  }

  test(
      'a) 3 filas del mismo agregado → 1 corrida, 3 envíos en orden de secuencia',
      () async {
    await insertar('a1', 'item-A');
    await insertar('a2', 'item-A');
    await insertar('a3', 'item-A');

    var t = DateTime.utc(2026, 5, 1, 12);
    final h = armar(reloj: () => t, avanzar: (d) => t = t.add(d));
    await h.ciclo.ejecutar();

    expect(h.orden, ['a1', 'a2', 'a3']); // orden de secuencia, una sola corrida
    for (final id in ['a1', 'a2', 'a3']) {
      expect((await leer(id)).estado, 'sincronizado');
    }
  });

  test('b) la 2ª del agregado falla por red → la 3ª NO se envía', () async {
    await insertar('a1', 'item-A');
    await insertar('a2', 'item-A');
    await insertar('a3', 'item-A');

    var t = DateTime.utc(2026, 5, 1, 12);
    final h =
        armar(reloj: () => t, avanzar: (d) => t = t.add(d), fallanRed: {'a2'});
    await h.ciclo.ejecutar();

    expect(h.orden, ['a1', 'a2']); // a3 nunca se intentó
    expect((await leer('a1')).estado, 'sincronizado');
    final a2 = await leer('a2');
    expect(a2.estado, 'pendiente');
    expect(a2.intentosRed, 1);
    expect(a2.proximoIntentoEn, isNotNull); // quedó con backoff
    final a3 = await leer('a3');
    expect(a3.estado, 'pendiente');
    expect(a3.intentosRed, 0); // nunca se intentó
  });

  test('c) tope de 50 pasadas: no hay bucle infinito con más filas que el tope',
      () async {
    // 60 filas del MISMO agregado: cada pasada drena 1 (FIFO por agregado) → el tope
    // de 50 corta la corrida con 50 sincronizadas y 10 aún pendientes.
    for (var i = 0; i < 60; i++) {
      await insertar('x${i.toString().padLeft(2, '0')}', 'item-X');
    }

    var t = DateTime.utc(2026, 5, 1, 12);
    final h = armar(reloj: () => t, avanzar: (d) => t = t.add(d));
    await h.ciclo.ejecutar(); // debe TERMINAR (sin colgarse)

    expect(h.orden.length, CicloSync.kMaxPasadasPorCorrida); // 50 envíos
    final sinc = await (db.select(db.syncPendientes)
          ..where((t) => t.estado.equals('sincronizado')))
        .get();
    final pend = await (db.select(db.syncPendientes)
          ..where((t) => t.estado.equals('pendiente')))
        .get();
    expect(sinc.length, 50);
    expect(pend.length, 10);
  });

  test(
      'd) dos agregados, la 2ª de A falla: las 2 de B sincronizan en la MISMA '
      'corrida; A no intenta una 3ª', () async {
    await insertar('a1', 'item-A'); // seq 1
    await insertar('b1', 'item-B'); // seq 2
    await insertar('a2', 'item-A'); // seq 3
    await insertar('b2', 'item-B'); // seq 4

    var t = DateTime.utc(2026, 5, 1, 12);
    final h =
        armar(reloj: () => t, avanzar: (d) => t = t.add(d), fallanRed: {'a2'});
    await h.ciclo.ejecutar();

    // Pasada 1: a1,b1 (primeras de cada agregado). Pasada 2: a2 (falla),b2.
    expect(h.orden, ['a1', 'b1', 'a2', 'b2']);
    expect((await leer('b1')).estado, 'sincronizado');
    expect((await leer('b2')).estado, 'sincronizado');
    expect((await leer('a1')).estado, 'sincronizado');
    final a2 = await leer('a2');
    expect(a2.estado, 'pendiente');
    expect(a2.intentosRed, 1);
  });

  test(
      'e) sincronizado_en y ultimo_intento_en = reloj POST-respuesta, no el del '
      'reclamo', () async {
    await insertar('u1', 'item-U');

    final t0 = DateTime.utc(2026, 5, 1, 12);
    var t = t0;
    // El reclamo ocurre en t0; el POST avanza el reloj 5s antes de responder.
    final h = armar(
        reloj: () => t,
        avanzar: (d) => t = t.add(d),
        pasoReloj: const Duration(seconds: 5),);
    await h.ciclo.ejecutar();

    final u1 = await leer('u1');
    expect(u1.estado, 'sincronizado');
    final esperado =
        t0.add(const Duration(seconds: 5)); // instante post-respuesta
    expect(u1.sincronizadoEn, esperado);
    expect(u1.ultimoIntentoEn, esperado);
    expect(u1.sincronizadoEn, isNot(t0)); // NO es el instante del reclamo
  });
}
