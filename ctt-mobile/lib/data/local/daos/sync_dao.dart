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

  Future<void> marcarEnviando(String id) =>
      _actualizarEstado(id, EstadoSyncLocal.enviando);

  Future<void> marcarSincronizado(String id) =>
      _actualizarEstado(id, EstadoSyncLocal.sincronizado);

  Future<void> marcarError(String id, String mensaje, int reintentos) =>
      (update(syncPendientesTable)..where((t) => t.id.equals(id))).write(
        SyncPendientesTableCompanion(
          estado: Value(EstadoSyncLocal.error.valor),
          ultimoError: Value(mensaje),
          reintentos: Value(reintentos),
        ),
      );

  Future<void> marcarConflicto(String id) =>
      _actualizarEstado(id, EstadoSyncLocal.conflicto);

  /// Reactiva entradas en error para que el próximo ciclo las reintente.
  Future<void> reactivarErrores() =>
      (update(syncPendientesTable)
            ..where((t) => t.estado.equals(EstadoSyncLocal.error.valor)))
          .write(
        SyncPendientesTableCompanion(
          estado: Value(EstadoSyncLocal.pendiente.valor),
        ),
      );

  Future<int> contarPendientes() async {
    final count = syncPendientesTable.id.count();
    final q = selectOnly(syncPendientesTable)..addColumns([count]);
    final row = await q.getSingle();
    return row.read(count) ?? 0;
  }

  Future<void> _actualizarEstado(String id, EstadoSyncLocal estado) =>
      (update(syncPendientesTable)..where((t) => t.id.equals(id))).write(
        SyncPendientesTableCompanion(estado: Value(estado.valor)),
      );
}
