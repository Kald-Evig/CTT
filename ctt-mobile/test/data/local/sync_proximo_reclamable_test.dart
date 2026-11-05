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
  // La `secuencia` (autoincremental) sigue el orden de inserción → la 1ª fila de un ítem es su
  // cabeza FIFO. `item` permite varias filas del MISMO ítem (para probar el FIFO); por defecto
  // cada fila es su propio ítem.
  Future<void> fila(
    String estado, {
    DateTime? proximoIntentoEn,
    DateTime? tomadoHasta,
    String? item,
  }) {
    final id = 'r${seq++}';
    return db.into(db.syncPendientes).insert(SyncPendientesCompanion.insert(
          id: id,
          idempotencyKey: 'idem-$id',
          empresaId: 'emp-1',
          usuarioId: 'user-1',
          instalacionId: 'inst-1',
          tipoEntidad: 'item',
          entidadId: item ?? 'item-$id',
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

  // CTT-141: hueco de alcance — el coordinador despierta para reconciliar mientras haya filas
  // en esperando_resolucion. observarHayEnEsperaResolucion alimenta ese Timer.
  test('observarHayEnEsperaResolucion: true solo con filas en esperando_resolucion', () async {
    expect(await db.syncDao.observarHayEnEsperaResolucion().first, isFalse);
    await fila('pendiente'); // otros estados no cuentan
    await fila('sincronizado');
    expect(await db.syncDao.observarHayEnEsperaResolucion().first, isFalse);
    await fila('esperando_resolucion');
    expect(await db.syncDao.observarHayEnEsperaResolucion().first, isTrue,
        reason: 'ahora hay una fila en espera');
  });

  // ── Bug 4: el MIN se calcula SOLO sobre las cabezas FIFO ──────────────────────
  group('cabeza FIFO (bug 4)', () {
    test('A (enviando, lease a T) bloquea B (pendiente null) del mismo ítem → MIN = T, no "ya"',
        () async {
      final t = DateTime.utc(2026, 6, 1, 12);
      await fila('enviando', tomadoHasta: t, item: 'X'); // A: cabeza (secuencia menor)
      await fila('pendiente', item: 'X'); // B: posterior, proximo_intento_en NULL
      expect(await prox(), t,
          reason: 'la cabeza es A (enviando); B está bloqueada por FIFO y no cuenta como "ya"');
    });

    test('dos ítems: MIN entre las cabezas (Y pendiente a +10 s vs X enviando a +60 s)', () async {
      await fila('enviando', tomadoHasta: DateTime.utc(2026, 6, 1, 12, 1), item: 'X'); // +60 s
      await fila('pendiente',
          proximoIntentoEn: DateTime.utc(2026, 6, 1, 12, 0, 10), item: 'Y'); // +10 s
      expect(await prox(), DateTime.utc(2026, 6, 1, 12, 0, 10));
    });

    test('esperando_resolucion como cabeza NO bloquea: la fila siguiente cuenta', () async {
      await fila('esperando_resolucion', item: 'Z'); // secuencia menor, no en estadosIntencionLocal
      await fila('pendiente',
          proximoIntentoEn: DateTime.utc(2026, 6, 1, 12), item: 'Z'); // cuenta como cabeza
      expect(await prox(), DateTime.utc(2026, 6, 1, 12),
          reason: 'esperando_resolucion no bloquea el FIFO (CTT-143)');
    });

    test('el watch y reclamar comparten el predicado FIFO: la cabeza del watch es la que '
        'reclamar toma', () async {
      final ahora = DateTime.utc(2026, 6, 1, 12);
      // Ítem X: A enviando con lease VENCIDO (reclamable), B pendiente posterior (bloqueada).
      await fila('enviando',
          tomadoHasta: ahora.subtract(const Duration(minutes: 1)), item: 'X');
      await fila('pendiente', item: 'X');
      // reclamar/filasReclamables (mismo predicado _sinFilaAnteriorDelAgregado): solo la cabeza A.
      final reclamables = await db.syncDao.filasReclamables(ahora);
      expect(reclamables.map((r) => r.entidadId).toList(), ['X'],
          reason: 'solo la cabeza A es reclamable; B está bloqueada');
      // El watch apunta al instante de ESA cabeza (tomado_hasta de A), no a "ya" por B.
      expect(await prox(), ahora.subtract(const Duration(minutes: 1)),
          reason: 'misma cabeza FIFO que reclamar; B (bloqueada) se ignora en ambos');
    });
  });
}
