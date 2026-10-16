/// ciclo_encolar_concurrente_test.dart — CTT-148 (garantía del punto 3). Una fila recién
/// encolada mientras OTRA del mismo agregado está `enviando` (lease vigente = un ciclo en
/// curso, CTT-127) NO se envía fuera de orden: el FIFO por agregado la bloquea. Cuando la
/// anterior termina, una corrida ENCADENADA la envía. Así se garantiza que la fila se
/// intente en esa corrida o en la siguiente, sin romper el orden.
library;

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

void main() {
  setUpAll(() => registerFallbackValue(Options()));

  late BaseDatosCTT db;
  late _MockDio dio;
  var posts = 0;

  setUp(() {
    db = BaseDatosCTT.conConexion(NativeDatabase.memory());
    dio = _MockDio();
    posts = 0;
    when(() => dio.get<List<dynamic>>(any())).thenThrow(DioException(
        requestOptions: RequestOptions(path: '/m'),
        type: DioExceptionType.connectionError,),);
    when(() => dio.post<Map<String, dynamic>>(any(),
            data: any(named: 'data'), options: any(named: 'options'),),)
        .thenAnswer((inv) async {
      posts++;
      final data = inv.namedArguments[#data] as Map<String, dynamic>;
      return Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(path: '/x'),
          data: {'estado': data['nuevo_estado']},);
    });
  });
  tearDown(() => db.close());

  CicloSync ciclo() {
    final deviceId = _MockDeviceIdService();
    when(() => deviceId.obtener()).thenAnswer((_) async => 'inst-1');
    return CicloSync(
      syncDao: db.syncDao,
      dio: dio,
      deviceIdService: deviceId,
      isolateLabel: 'test',
      reloj: () => DateTime.utc(2026, 5, 1, 12),
    );
  }

  Future<void> insertar(String id, int secuencia, String estado,
          {DateTime? tomadoHasta}) =>
      db.into(db.syncPendientes).insert(SyncPendientesCompanion.insert(
            id: id,
            idempotencyKey: 'idem-$id',
            empresaId: 'emp-1',
            usuarioId: 'user-1',
            instalacionId: 'inst-1',
            tipoEntidad: 'item',
            entidadId: 'item-A',
            accion: 'cambio_estado_item',
            payload: '{"nuevo_estado":"en_progreso"}',
            payloadVersion: 1,
            creadoEnDispositivo: DateTime.utc(2026, 1, 1),
            estado: Value(estado),
            secuencia: Value(secuencia),
            tomadoHasta:
                tomadoHasta != null ? Value(tomadoHasta) : const Value.absent(),
            tomadoPor: tomadoHasta != null
                ? const Value('otra-corrida')
                : const Value.absent(),
          ));

  Future<String> estado(String id) async =>
      (await (db.select(db.syncPendientes)..where((t) => t.id.equals(id)))
              .getSingle())
          .estado;

  test('fila nueva bloqueada por una anterior en enviando (lease vigente); se envía '
      'en la corrida encadenada al terminar la anterior', () async {
    // A1: enviando con lease vigente (ciclo en curso). A2: recién encolada, pendiente.
    await insertar('A1', 1, 'enviando',
        tomadoHasta: DateTime.utc(2026, 5, 1, 12, 30),);
    await insertar('A2', 2, 'pendiente');

    // Corrida 1: A1 no es reclamable (lease vigente) y A2 está bloqueada por FIFO.
    await ciclo().ejecutar();
    expect(posts, 0, reason: 'A2 no se envía fuera de orden');
    expect(await estado('A1'), 'enviando');
    expect(await estado('A2'), 'pendiente');

    // La otra corrida termina A1 (p. ej. 200). Ahora A2 se desbloquea.
    await (db.update(db.syncPendientes)..where((t) => t.id.equals('A1')))
        .write(const SyncPendientesCompanion(estado: Value('sincronizado')));

    // Corrida encadenada: A2 ya es reclamable → se envía.
    await ciclo().ejecutar();
    expect(posts, 1);
    expect(await estado('A2'), 'sincronizado');
  });
}
