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

@DriftAccessor(tables: [SyncPendientes, SyncReconciliacionTable])
class SyncDao extends DatabaseAccessor<BaseDatosCTT>
    with _$SyncDaoMixin {
  SyncDao(super.db);

  /// Id de la fila única de estado del reconciliador (CTT-117 tramo 3).
  static const _idReconciliacion = 'singleton';

  /// Encola un nuevo cambio. Nunca falla si no hay conexión — ese es el punto.
  Future<void> encolar(SyncPendientesCompanion entrada) =>
      into(syncPendientes).insert(entrada);

  /// Pendientes ordenados por `secuencia` ASC (FIFO por orden de encolado, no por
  /// reloj del dispositivo — CTT-130: `secuencia` es monótona, el reloj no).
  /// Excluye los que están enviándose.
  Future<List<SyncPendiente>> obtenerPendientes() =>
      (select(syncPendientes)
            ..where((t) => t.estado.equals(EstadoSyncLocal.pendiente.valor))
            ..orderBy([(t) => OrderingTerm.asc(t.secuencia)]))
          .get();

  /// Filas parqueadas esperando resolución de conflicto. Las consume el
  /// reconciliador del tramo 3 (CTT-117) para casarlas contra
  /// GET /sync/conflictos/mios por su `conflictoId`.
  Future<List<SyncPendiente>> obtenerEnEsperaResolucion() =>
      (select(syncPendientes)
            ..where(
              (t) => t.estado.equals(EstadoSyncLocal.esperandoResolucion.valor),
            ))
          .get();

  /// Estados que BLOQUEAN el envío de filas POSTERIORES del mismo agregado
  /// (tipo_entidad, entidad_id): mientras una fila anterior esté en uno de estos,
  /// las siguientes del mismo ítem no son elegibles (FIFO por agregado — CTT-103 I3).
  List<String> get _estadosBloqueantes => [
        EstadoSyncLocal.pendiente.valor,
        EstadoSyncLocal.enviando.valor,
        EstadoSyncLocal.esperandoResolucion.valor,
      ];

  /// Una fila es ELEGIBLE para claim (I4):
  ///   - pendiente y (sin `proximo_intento_en` o ya vencido), o
  ///   - enviando y (sin `tomado_hasta` —huérfana pre-lease, CTT-127— o lease vencido).
  Expression<bool> _elegible(DateTime ahora) {
    final pend = syncPendientes.estado.equals(EstadoSyncLocal.pendiente.valor) &
        (syncPendientes.proximoIntentoEn.isNull() |
            syncPendientes.proximoIntentoEn.isSmallerOrEqualValue(ahora));
    final env = syncPendientes.estado.equals(EstadoSyncLocal.enviando.valor) &
        (syncPendientes.tomadoHasta.isNull() |
            syncPendientes.tomadoHasta.isSmallerThanValue(ahora));
    return pend | env;
  }

  /// No existe otra fila del MISMO agregado con `secuencia` menor en un estado
  /// bloqueante: garantiza el orden FIFO por (tipo_entidad, entidad_id) — I3.
  Expression<bool> _sinFilaAnteriorDelAgregado() {
    final p2 = alias(syncPendientes, 'p2');
    return notExistsQuery(
      selectOnly(p2)
        ..addColumns([p2.secuencia])
        ..where(
          p2.tipoEntidad.equalsExp(syncPendientes.tipoEntidad) &
              p2.entidadId.equalsExp(syncPendientes.entidadId) &
              p2.secuencia.isSmallerThan(syncPendientes.secuencia) &
              p2.estado.isIn(_estadosBloqueantes),
        ),
    );
  }

  /// Filas candidatas a reclamar, en orden de `secuencia`. Mismo criterio que el
  /// claim; [reclamar] re-verifica atómicamente (otra corrida pudo ganarlas).
  Future<List<SyncPendiente>> filasReclamables(DateTime ahora) =>
      (select(syncPendientes)
            ..where((t) => _elegible(ahora) & _sinFilaAnteriorDelAgregado())
            ..orderBy([(t) => OrderingTerm.asc(t.secuencia)]))
          .get();

  /// CLAIM atómico (I4): UN solo UPDATE condicional. Toma la fila [id] para esta
  /// corrida ([tomadoPor]) si sigue [_elegible] y [_sinFilaAnteriorDelAgregado],
  /// fijando estado='enviando' y el lease [tomadoHasta]. Devuelve true si ESTA
  /// corrida ganó la fila (1 fila afectada); false si otra la tomó, si su lease
  /// sigue vigente o si dejó de ser elegible. Cierra CTT-127: una fila en 'enviando'
  /// con lease vencido (o nulo) vuelve a ser reclamable.
  Future<bool> reclamar(
    String id, {
    required String tomadoPor,
    required DateTime ahora,
    required DateTime tomadoHasta,
  }) async {
    final afectadas = await (update(syncPendientes)
          ..where((t) =>
              t.id.equals(id) &
              _elegible(ahora) &
              _sinFilaAnteriorDelAgregado()))
        .write(SyncPendientesCompanion(
      estado: Value(EstadoSyncLocal.enviando.valor),
      tomadoPor: Value(tomadoPor),
      tomadoHasta: Value(tomadoHasta),
    ));
    return afectadas > 0;
  }

  /// Aplica una [DecisionSync] a una entrada, en profundidad: solo escribe si la
  /// fila sigue en [estadoEsperado] (guarda anti-carrera) y —si se pasa [tomadoPor]—
  /// solo si el lease sigue siendo de esta corrida (cierre condicional, CTT-103 A2):
  /// un cierre tardío de una corrida que perdió el lease NO pisa el resultado de la
  /// que retomó la fila. Sin [tomadoPor] no se chequea el lease (p. ej. el camino de
  /// conflicto online y el reconciliador, que no reclaman lease).
  ///
  /// Devuelve las filas afectadas (0 si otro ciclo ya la movió). Escribe estado y
  /// —según la decisión y el transporte— motivo, `intentos_red`, conflicto_id y
  /// ultimo_error (el detalle del backend; su ausencia deja el valor previo, así
  /// que en reintentos gana el ÚLTIMO intento con detalle — CTT-115).
  ///
  /// `intentos_servidor` NO se toca acá: su tope y su semántica son de CTT-103.
  ///
  /// ESCRITOR ÚNICO del flag `items_cache.tiene_conflicto` (CTT-117 tramo 3), en
  /// la MISMA transacción que el estado de la cola, de forma simétrica:
  ///   - la decisión entra a esperandoResolucion            → flag = true
  ///   - sale de esperandoResolucion hacia un terminal      → flag = false
  ///   - cualquier otra transición                          → no toca el flag
  ///
  /// TODO(CTT-120): este retorno NO tiene consumidor en producción. Si la guarda
  /// de [estadoEsperado] se desalinea, la escritura se vuelve un no-op y un 0
  /// inesperado pasa desapercibido. Falta un chequeo del retorno; se ticketea aparte.
  Future<int> aplicarDecision(
    String id, {
    required EstadoSyncLocal estadoEsperado,
    required DecisionSync decision,
    required int reintentosActuales,
    String? tomadoPor,
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
            : (await (select(syncPendientes)..where((t) => t.id.equals(id)))
                    .getSingleOrNull())
                ?.entidadId;

        final afectadas = await (update(syncPendientes)
              ..where((t) {
                final base =
                    t.id.equals(id) & t.estado.equals(estadoEsperado.valor);
                // Cierre condicional (A2): si se pasó tomadoPor, solo escribir si el
                // lease sigue siendo de esta corrida.
                return tomadoPor == null
                    ? base
                    : base & t.tomadoPor.equals(tomadoPor);
              }))
            .write(
          SyncPendientesCompanion(
            estado: Value(decision.nuevoEstado.valor),
            motivo: decision.motivo != null
                ? Value(decision.motivo!.valor)
                : const Value.absent(),
            intentosRed: decision.incrementaReintentos
                ? Value(reintentosActuales + 1)
                : const Value.absent(),
            conflictoId:
                conflictoId != null ? Value(conflictoId) : const Value.absent(),
            ultimoError:
                detalle != null ? Value(detalle) : const Value.absent(),
          ),
        );
        // Guarda anti-carrera / cierre condicional: si la fila ya no estaba en
        // estadoEsperado (o el lease ya no es de esta corrida), no se movió nada y
        // tampoco se toca el flag.
        if (afectadas == 0) {
          if (tomadoPor != null) {
            debugPrint(
              'CTT-103: cierre ignorado — la corrida "$tomadoPor" ya no tiene el '
              'lease de la fila $id (otra corrida la retomó o cambió de estado).',
            );
          }
          return 0;
        }

        if (nuevoFlag != null) {
          final filasFlag = await (update(attachedDatabase.itemsCacheTable)
                ..where((t) => t.id.equals(entidadId!)))
              .write(ItemsCacheTableCompanion(
                tieneConflicto: Value(nuevoFlag),
              ),);
          if (filasFlag == 0) {
            // Ítem no cacheado: la fila de la cola se cerró igual, pero el flag no
            // tuvo dónde escribirse. Caso esperable (el full-replace del pull puede
            // sacar un ítem mientras su fila sigue encolada), no un error.
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
  Future<Set<String>> obtenerIdsPendienteSet() async {
    final noTerminales = [
      EstadoSyncLocal.pendiente.valor,
      EstadoSyncLocal.enviando.valor,
      EstadoSyncLocal.esperandoResolucion.valor,
    ];
    final rows = await (select(syncPendientes)
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
    final count = syncPendientes.id.count();
    final q = selectOnly(syncPendientes)..addColumns([count]);
    final row = await q.getSingle();
    return row.read(count) ?? 0;
  }
}
