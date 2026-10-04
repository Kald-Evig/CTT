/// conflicto_online_directo_test.dart — CTT-103 L2.
///
/// El camino online de transicion_service, ante un 409 con conflicto_id, inserta la
/// fila DIRECTO en esperando_resolucion (un INSERT). Contra Drift real: la fila queda
/// en esperando_resolucion con su conflicto_id y NUNCA es elegible para reclamar()
/// (no pasa por 'pendiente', así el ciclo no la reenvía — carrera CTT-136).
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:ctt_mobile/core/device/device_id_service.dart';
import 'package:ctt_mobile/core/security/secure_storage_service.dart';
import 'package:ctt_mobile/core/sync/resultado_transicion.dart';
import 'package:ctt_mobile/core/sync/transicion_service.dart';
import 'package:ctt_mobile/data/local/database.dart';
import 'package:ctt_mobile/domain/enums/enums_ctt.dart';

class _MockDio extends Mock implements Dio {}

class _MockDeviceIdService extends Mock implements DeviceIdService {}

class _MockSecureStorage extends Mock implements SecureStorageService {}

const _conflictoId = 'b5a160d2-d97f-411c-9ef5-0172935f6f1c';
const _bodyConflicto =
    '{"detail":{"tipo":"conflicto_concurrencia","conflicto_id":"$_conflictoId",'
    '"mensaje":"El ítem fue modificado en el servidor.","estado_servidor":"problema"}}';

void main() {
  setUpAll(() => registerFallbackValue(Options()));

  late BaseDatosCTT db;
  setUp(() => db = BaseDatosCTT.conConexion(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('409 online con conflicto_id: fila DIRECTO en esperando_resolucion, nunca '
      'reclamable', () async {
    const itemId = '82893973';
    final dio = _MockDio();
    final deviceIdService = _MockDeviceIdService();
    final secureStorage = _MockSecureStorage();
    when(() => deviceIdService.obtener()).thenAnswer((_) async => 'dev-1');
    when(() => secureStorage.obtenerUsuarioId()).thenAnswer((_) async => 'user-1');
    when(() => secureStorage.obtenerEmpresaId()).thenAnswer((_) async => 'emp-1');

    final ro = RequestOptions(path: '/items/$itemId/transicion');
    when(() => dio.post<Map<String, dynamic>>(any(),
            data: any(named: 'data'), options: any(named: 'options'),),)
        .thenThrow(DioException(
      requestOptions: ro,
      response: Response<dynamic>(
        requestOptions: ro,
        statusCode: 409,
        data: jsonDecode(_bodyConflicto),
      ),
      type: DioExceptionType.badResponse,
    ),);

    final service = TransicionService(
      dio: dio,
      syncDao: db.syncDao,
      deviceIdService: deviceIdService,
      secureStorage: secureStorage,
    );

    // El ítem está en caché SIN conflicto: el camino de conflicto debe encender el flag.
    await db.into(db.itemsCacheTable).insert(ItemsCacheTableCompanion.insert(
          id: itemId,
          proyectoId: 'proy-1',
          nombre: 'Tarea',
          estado: 'en_progreso',
          updatedAt: DateTime.utc(2026, 5, 1),
          cachadoEn: DateTime.utc(2026, 5, 1),
        ),);

    final r = await service.ejecutar(itemId: itemId, nuevoEstado: 'pendiente_revision');
    expect(r, isA<TransicionConConflicto>());
    expect((r as TransicionConConflicto).conflictoId, _conflictoId);

    // La fila quedó en esperando_resolucion con el conflicto_id y el motivo que dicta
    // decidir(conflictoDetectado), en un solo INSERT.
    final filas = await (db.select(db.syncPendientes)
          ..where((t) => t.entidadId.equals(itemId)))
        .get();
    expect(filas, hasLength(1));
    expect(filas.single.estado, EstadoSyncLocal.esperandoResolucion.valor);
    expect(filas.single.conflictoId, _conflictoId);
    expect(filas.single.motivo, MotivoSync.conflicto.valor);

    // El flag de conflicto del ítem quedó encendido (SyncDao, escritor único).
    final itemCache = await (db.select(db.itemsCacheTable)
          ..where((t) => t.id.equals(itemId)))
        .getSingle();
    expect(itemCache.tieneConflicto, isTrue);

    // Nunca elegible para el ciclo: filasReclamables no la trae (no es pendiente ni
    // enviando; y no pasó por 'pendiente' en ningún momento).
    final reclamables = await db.syncDao.filasReclamables(DateTime.utc(2026, 5, 1, 12));
    expect(reclamables, isEmpty);
  });
}
