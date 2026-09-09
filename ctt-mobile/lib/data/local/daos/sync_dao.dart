/// sync_dao.dart — Acceso a la cola de sincronización offline (Drift).
///
/// Este DAO es la capa de EFECTO: traduce una [DecisionSync] (calculada por la
/// función de decisión pura, decision_sync.dart) a una escritura en Drift. No
/// decide nada por su cuenta.
library;

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:ctt_mobile/core/sync/decision_sync.dart';
import 'package:ctt_mobile/data/local/database.dart';
import 'package:ctt_mobile/domain/enums/enums_ctt.dart';

part 'sync_dao.g.dart';

@riverpod
SyncDao syncDao(SyncDaoRef ref) => SyncDao(ref.watch(baseDatosCTTProvider));

@DriftAccessor(tables: [SyncPendientesTable, SyncReconciliacionTable])
class SyncDao extends DatabaseAccessor<BaseDatosCTT>
    with _$SyncDaoMixin {
  SyncDao(super.db);

  /// Id de la fila única de estado del reconciliador (CTT-117 tramo 3).
  static const _idReconciliacion = 'singleton';

  /// Encola un nuevo cambio. Nunca falla si no hay conexión — ese es el punto.
  Future<void> encolar(SyncPendientesTableCompanion entrada) =>
      into(syncPendientesTable).insert(entrada);

  /// Pendientes ordenados por timestamp (FIFO). Excluye los que están enviándose.
  Future<List<SyncPendientesTableData>> obtenerPendientes() =>
      (select(syncPendientesTable)
            ..where((t) => t.estado.equals(EstadoSyncLocal.pendiente.valor))
            ..orderBy([(t) => OrderingTerm.asc(t.timestampDispositivo)]))
          .get();

  /// Filas parqueadas esperando resolución de conflicto. Las consume el
  /// reconciliador del tramo 3 (CTT-117) para casarlas contra
  /// GET /sync/conflictos/mios por su `conflictoId`.
  Future<List<SyncPendientesTableData>> obtenerEnEsperaResolucion() =>
      (select(syncPendientesTable)
            ..where(
              (t) => t.estado.equals(EstadoSyncLocal.esperandoResolucion.valor),
            ))
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
  /// —según la decisión y el transporte— motivo, reintentos, conflicto_id y
  /// ultimo_error (el detalle del backend; su ausencia deja el valor previo, así
  /// que en reintentos gana el ÚLTIMO intento con detalle — CTT-115).
  ///
  /// ESCRITOR ÚNICO del flag `items_cache.tiene_conflicto` (CTT-117 tramo 3), en
  /// la MISMA transacción que el estado de la cola, de forma simétrica:
  ///   - la decisión entra a esperandoResolucion            → flag = true
  ///   - sale de esperandoResolucion hacia un terminal      → flag = false
  ///   - cualquier otra transición                          → no toca el flag
  /// El id del ítem (`entidadId`) no viaja como parámetro: se lee de la fila recién
  /// escrita y pasa por Dart a propósito (opción A2) — si alguna vez `entidadId`
  /// dejara de ser el id del ítem, el update fallaría de forma visible en vez de
  /// esconderse en un subquery SQL. Si el ítem no está en caché, el update del flag
  /// es un no-op (se deja rastro observable) y la fila de la cola se cierra igual.
  ///
  /// TODO(CTT-120): este retorno NO tiene consumidor en producción (ni ciclo_sync
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
    String? detalle,
  }) =>
      transaction(() async {
        // El flag depende solo de (estadoEsperado, decisión); se resuelve antes de
        // escribir para saber si hay que leer el ítem.
        final bool? nuevoFlag;
        if (decision.nuevoEstado == EstadoSyncLocal.esperandoResolucion) {
          nuevoFlag = true;
        } else if (estadoEsperado == EstadoSyncLocal.esperandoResolucion &&
            decision.nuevoEstado.esTerminal) {
          nuevoFlag = false;
        } else {
          nuevoFlag = null;
        }

        // entidadId se lee ANTES del update: ninguna decisión lo modifica. Solo se
        // lee si el flag cambia. Si la guarda matchea (afectadas > 0), la fila
        // existía, así que su entidadId no es null cuando se usa abajo.
        final entidadId = nuevoFlag == null
            ? null
            : (await (select(syncPendientesTable)..where((t) => t.id.equals(id)))
                    .getSingleOrNull())
                ?.entidadId;

        final afectadas = await (update(syncPendientesTable)
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
            ultimoError:
                detalle != null ? Value(detalle) : const Value.absent(),
          ),
        );
        // Guarda anti-carrera: si la fila ya no estaba en estadoEsperado, no se
        // movió nada y tampoco se toca el flag.
        if (afectadas == 0) return 0;

        if (nuevoFlag != null) {
          final filasFlag = await (update(attachedDatabase.itemsCacheTable)
                ..where((t) => t.id.equals(entidadId!)))
              .write(ItemsCacheTableCompanion(
                tieneConflicto: Value(nuevoFlag),
              ),);
          if (filasFlag == 0) {
            // Ítem no cacheado: la fila de la cola se cerró igual, pero el flag no
            // tuvo dónde escribirse. NO es necesariamente anómalo: el full-replace
            // del pull puede sacar un ítem de items_cache mientras su fila sigue
            // encolada, así que este no-op es un caso esperable, no un error.
            // OJO: debugPrint es no-op en release (flutter/foundation), así que en
            // el dispositivo del trabajador este rastro NO se observa. La
            // observabilidad real de producción queda fuera del alcance del tramo 3.
            debugPrint(
              'CTT-117: tiene_conflicto=$nuevoFlag no aplicado — ítem $entidadId '
              'no está en items_cache (fila de cola $id cerrada igual).',
            );
          }
        }
        return afectadas;
      });

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

  /// Momento de la última reconciliación (o null si nunca corrió). Persistido en
  /// Drift para que el debounce coordine entre el isolate de UI y el headless.
  Future<DateTime?> ultimaReconciliacion() async {
    final row = await (select(syncReconciliacionTable)
          ..where((t) => t.id.equals(_idReconciliacion)))
        .getSingleOrNull();
    return row?.ultimaReconciliacion;
  }

  /// Registra el instante de una reconciliación efectiva (upsert de la fila única).
  Future<void> registrarReconciliacion(DateTime cuando) =>
      into(syncReconciliacionTable).insertOnConflictUpdate(
        SyncReconciliacionTableCompanion.insert(
          id: _idReconciliacion,
          ultimaReconciliacion: Value(cuando),
        ),
      );

  Future<int> contarPendientes() async {
    final count = syncPendientesTable.id.count();
    final q = selectOnly(syncPendientesTable)..addColumns([count]);
    final row = await q.getSingle();
    return row.read(count) ?? 0;
  }

}
