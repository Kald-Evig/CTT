/// sync_proximo_reclamable_test.dart — CTT-141: SyncDao.observarProximoReclamable()
/// sobre una BD sqlite real (verifica el SQL y el parseo de la fecha de texto de Drift).
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ctt_mobile/data/local/database.dart';

void main() {
  late BaseDatosCTT db;
  setUp(() => db = BaseDatosCTT.conConexion(NativeDatabase.memory()));
  tearDown(() => db.close());

  var seq = 0;
  Future<void> fila(
    String estado, {
    DateTime? proximoIntentoEn,
    DateTime? tomadoHasta,
  }) {
    final id = 'r${seq++}';
    return db.into(db.syncPendientes).insert(SyncPendientesCompanion.insert(
          id: id,
          idempotencyKey: 'idem-$id',
          empresaId: 'emp-1',
          usuarioId: 'user-1',
          instalacionId: 'inst-1',
          tipoEntidad: 'item',
          entidadId: 'item-$id',
          accion: 'cambio_estado_item',
          payload: '{}',
          payloadVersion: 1,
          creadoEnDispositivo: DateTime.utc(2026, 1, 1),
          estado: Value(estado),
          proximoIntentoEn: Value(proximoIntentoEn),
          tomadoHasta: Value(tomadoHasta),
        ));
  }

  Future<DateTime?> prox() => db.syncDao.observarProximoReclamable().first;

  test('sin filas pendiente/enviando → null', () async {
    expect(await prox(), isNull);
    await fila('sincronizado');
    await fila('esperando_resolucion');
    await fila('descartado');
    expect(await prox(), isNull, reason: 'terminales y esperando_resolucion se excluyen');
  });

  test('pendiente sin proximo_intento_en → reclamable YA (epoch)', () async {
    await fila('pendiente');
    expect(await prox(), DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
  });

  test('pendiente con proximo_intento_en futuro → ese instante', () async {
    final t = DateTime.utc(2026, 5, 1, 12, 30);
    await fila('pendiente', proximoIntentoEn: t);
    expect(await prox(), t);
  });

  test('enviando con tomado_hasta futuro → ese instante (el lease)', () async {
    final t = DateTime.utc(2026, 6, 2, 8, 15);
    await fila('enviando', tomadoHasta: t);
    expect(await prox(), t);
  });

  test('enviando con tomado_hasta NULL (huérfana pre-lease) → reclamable YA', () async {
    await fila('enviando');
    expect(await prox(), DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
  });

  test('MIN entre varias: gana el instante más temprano', () async {
    await fila('pendiente', proximoIntentoEn: DateTime.utc(2026, 5, 10));
    await fila('enviando', tomadoHasta: DateTime.utc(2026, 5, 3));
    await fila('pendiente', proximoIntentoEn: DateTime.utc(2026, 5, 20));
    expect(await prox(), DateTime.utc(2026, 5, 3));
  });

  test('una fila reclamable YA domina sobre otras futuras', () async {
    await fila('pendiente', proximoIntentoEn: DateTime.utc(2026, 5, 10));
    await fila('pendiente'); // sin proximo_intento_en → YA
    expect(await prox(), DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
  });

  test('reactivo: encolar una fila con instante menor reemite', () async {
    await fila('pendiente', proximoIntentoEn: DateTime.utc(2026, 5, 10));
    final stream = db.syncDao.observarProximoReclamable();
    final emisiones = <DateTime?>[];
    final sub = stream.listen(emisiones.add);
    await pumpEventQueue();
    await fila('pendiente', proximoIntentoEn: DateTime.utc(2026, 5, 2));
    await pumpEventQueue();
    await sub.cancel();
    expect(emisiones.first, DateTime.utc(2026, 5, 10));
    expect(emisiones.last, DateTime.utc(2026, 5, 2),
        reason: 'el watch reemite al cambiar sync_pendientes');
  });
}
