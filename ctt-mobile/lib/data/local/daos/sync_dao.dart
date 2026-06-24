/// sync_dao.dart — Acceso a la cola de sincronización offline (Drift).
library;

import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:ctt_mobile/data/local/database.dart';
import 'package:ctt_mobile/domain/enums/enums_ctt.dart';

part 'sync_dao.g.dart';

@riverpod
SyncDao syncDao(SyncDaoRef ref) => SyncDao(ref.watch(baseDatosCTTProvider));

@DriftAccessor(tables: [SyncPendientesTable])
class SyncDao extends DatabaseAccessor<BaseDatosCTT>
    with _$SyncDaoMixin {
  SyncDao(super.db);

  /// Encola un nuevo cambio. Nunca falla si no hay conexión — ese es el punto.
  Future<void> encolar(SyncPendientesTableCompanion entrada) =>
      into(syncPendientesTable).insert(entrada);

  /// Pendientes ordenados por timestamp (FIFO). Excluye los que están enviándose.
  Future<List<SyncPendientesTableData>> obtenerPendientes() =>
      (select(syncPendientesTable)
            ..where((t) => t.estado.equals(EstadoSyncLocal.pendiente.valor))
            ..orderBy([(t) => OrderingTerm.asc(t.timestampDispositivo)]))
          .get();

  /// Intenta transicionar de 'pendiente' → 'enviando'.
  /// Devuelve true si esta llamada ganó la entrada (1 fila afectada),
  /// false si otro ciclo ya la tomó primero (0 filas afectadas).
  Future<bool> marcarEnviando(String id) async {
    final count = await (update(syncPendientesTable)
          ..where(
            (t) =>
                t.id.equals(id) &
                t.estado.equals(EstadoSyncLocal.pendiente.valor),
          ))
        .write(
      SyncPendientesTableCompanion(
        estado: Value(EstadoSyncLocal.enviando.valor),
      ),
    );
    return count > 0;
  }

  /// Guarda en profundidad: solo actualiza si la fila sigue en 'enviando'.
  Future<void> marcarSincronizado(String id) =>
      (update(syncPendientesTable)
            ..where(
              (t) =>
                  t.id.equals(id) &
                  t.estado.equals(EstadoSyncLocal.enviando.valor),
            ))
          .write(
        SyncPendientesTableCompanion(
          estado: Value(EstadoSyncLocal.sincronizado.valor),
        ),
      );

  /// Guarda en profundidad: solo actualiza si la fila sigue en 'enviando'.
  Future<void> marcarError(String id, String mensaje, int reintentos) =>
      (update(syncPendientesTable)
            ..where(
              (t) =>
                  t.id.equals(id) &
                  t.estado.equals(EstadoSyncLocal.enviando.valor),
            ))
          .write(
        SyncPendientesTableCompanion(
          estado: Value(EstadoSyncLocal.error.valor),
          ultimoError: Value(mensaje),
          reintentos: Value(reintentos),
        ),
      );

  /// Guarda en profundidad: solo actualiza si la fila sigue en 'enviando'.
  /// Si el backend devolvió un conflicto_id, se guarda en ultimoError para diagnóstico.
  Future<void> marcarConflicto(String id, {String? conflictoId}) =>
      (update(syncPendientesTable)
            ..where(
              (t) =>
                  t.id.equals(id) &
                  t.estado.equals(EstadoSyncLocal.enviando.valor),
            ))
          .write(
        SyncPendientesTableCompanion(
          estado: Value(EstadoSyncLocal.conflicto.valor),
          ultimoError: conflictoId != null
              ? Value('conflicto_id:$conflictoId')
              : const Value.absent(),
        ),
      );

  /// Reactiva entradas en error para que el próximo ciclo las reintente.
  Future<void> reactivarErrores() =>
      (update(syncPendientesTable)
            ..where((t) => t.estado.equals(EstadoSyncLocal.error.valor)))
          .write(
        SyncPendientesTableCompanion(
          estado: Value(EstadoSyncLocal.pendiente.valor),
        ),
      );

  /// IDs de entidades con sincronización pendiente (no sincronizadas todavía).
  /// Usado para el indicador visual en la lista de ítems.
  Future<Set<String>> obtenerIdsPendienteSet() async {
    final rows = await (select(syncPendientesTable)
          ..where((t) => t.estado.isNotIn([EstadoSyncLocal.sincronizado.valor])))
        .get();
    return {for (final r in rows) r.entidadId};
  }

  Future<int> contarPendientes() async {
    final count = syncPendientesTable.id.count();
    final q = selectOnly(syncPendientesTable)..addColumns([count]);
    final row = await q.getSingle();
    return row.read(count) ?? 0;
  }

}
