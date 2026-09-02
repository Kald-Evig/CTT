/// sync_dao.dart — Acceso a la cola de sincronización offline (Drift).
///
/// Este DAO es la capa de EFECTO: traduce una [DecisionSync] (calculada por la
/// función de decisión pura, decision_sync.dart) a una escritura en Drift. No
/// decide nada por su cuenta.
library;

import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:ctt_mobile/core/sync/decision_sync.dart';
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

  /// Aplica una [DecisionSync] a una entrada, en profundidad: solo escribe si la
  /// fila sigue en [estadoEsperado] (guarda anti-carrera, igual que marcarEnviando).
  ///
  /// Devuelve las filas afectadas (0 si otro ciclo ya la movió). Escribe estado y
  /// —solo cuando la decisión lo indica— motivo, reintentos y conflicto_id.
  ///
  /// TODO(CTT-117): este retorno NO tiene consumidor en producción (ni ciclo_sync
  /// ni transicion_service lo miran). Si la guarda de [estadoEsperado] se vuelve a
  /// desalinear con el estado real de la fila, la escritura se convierte en un
  /// no-op y un 0 inesperado pasa desapercibido — el mismo modo de falla silenciosa
  /// que el defecto 2 de CTT-115. Falta un chequeo del retorno; se ticketea aparte.
  Future<int> aplicarDecision(
    String id, {
    required EstadoSyncLocal estadoEsperado,
    required DecisionSync decision,
    required int reintentosActuales,
    String? conflictoId,
  }) =>
      (update(syncPendientesTable)
            ..where(
              (t) =>
                  t.id.equals(id) &
                  t.estado.equals(estadoEsperado.valor),
            ))
          .write(
        SyncPendientesTableCompanion(
          estado: Value(decision.nuevoEstado.valor),
          motivo: decision.motivo != null
              ? Value(decision.motivo!.valor)
              : const Value.absent(),
          reintentos: decision.incrementaReintentos
              ? Value(reintentosActuales + 1)
              : const Value.absent(),
          conflictoId:
              conflictoId != null ? Value(conflictoId) : const Value.absent(),
        ),
      );

  /// IDs de entidades con sincronización pendiente (estados NO terminales).
  /// Usado para el indicador visual en la lista de ítems.
  ///
  /// Whitelist explícita de no-terminales (no blacklist): si mañana se agrega un
  /// estado terminal al enum, no se contará por error como pendiente. Incluye
  /// `esperandoResolucion` porque el cambio del usuario todavía no aterrizó.
  Future<Set<String>> obtenerIdsPendienteSet() async {
    final noTerminales = [
      EstadoSyncLocal.pendiente.valor,
      EstadoSyncLocal.enviando.valor,
      EstadoSyncLocal.esperandoResolucion.valor,
    ];
    final rows = await (select(syncPendientesTable)
          ..where((t) => t.estado.isIn(noTerminales)))
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
