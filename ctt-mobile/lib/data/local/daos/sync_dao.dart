/// sync_dao.dart — Acceso a la cola de sincronización offline (Drift).
///
/// Este DAO es la capa de EFECTO: traduce una [DecisionSync] (calculada por la
/// función de decisión pura, decision_sync.dart) a una escritura en Drift. No
/// decide nada por su cuenta.
library;

import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:ctt_mobile/core/sync/decision_sync.dart';
import 'package:ctt_mobile/data/local/database.dart';
import 'package:ctt_mobile/domain/enums/enums_ctt.dart';

part 'sync_dao.g.dart';

/// Resultado de esperar por el PRIMER intento de una fila recién encolada (CTT-148).
/// `estado` es el alcanzado; si quedó `pendiente` tras un intento fallido, trae además
/// el código/detalle del backend para que la UI muestre "no se pudo enviar (código)".
class ResultadoEspera {
  const ResultadoEspera(this.estado,
      {this.ultimoErrorCodigo, this.ultimoError, this.versionResultante});
  final EstadoSyncLocal estado;
  final int? ultimoErrorCodigo;
  final String? ultimoError;

  /// Versión del servidor tras el intento (CTT-143 C3e): ItemOut.version del 200 o
  /// version_actual del 409. La ruta del Residente la usa para que su PRÓXIMA transición
  /// salga con la base nueva (su ítem no está en items_cache). null si el intento no la
  /// trajo (p. ej. rechazo, o fila aún pendiente).
  final int? versionResultante;
}

@riverpod
SyncDao syncDao(SyncDaoRef ref) => SyncDao(ref.watch(baseDatosCTTProvider));

@DriftAccessor(tables: [SyncPendientes, SyncReconciliacionTable])
class SyncDao extends DatabaseAccessor<BaseDatosCTT>
    with _$SyncDaoMixin {
  SyncDao(super.db);

  /// Id de la fila única de estado del reconciliador (CTT-117 tramo 3).
  static const _idReconciliacion = 'singleton';

  /// Encola un nuevo cambio. Nunca falla si no hay conexión — ese es el punto.
  /// Con "encolar primero" (CTT-148) es la ÚNICA puerta de entrada a la cola: toda
  /// transición nace aquí en `pendiente` y el ciclo la envía (incluido el 409 de
  /// conflicto, que ahora llega por la cola y lo parquea [aplicarDecision]).
  Future<void> encolar(SyncPendientesCompanion entrada) =>
      into(syncPendientes).insert(entrada);

  /// Encola [entrada] estampando `version_base` desde `items_cache.version` del ítem
  /// [entidadId], en UNA transacción (CTT-143 D7/C2): la versión leída y el insert son
  /// atómicos. Si la base no tiene versión (version NULL: ítem migrado de v7 que aún no se
  /// re-pulleó, o ausente de la caché), NO encola y devuelve false — NUNCA se envía 0 ni un
  /// valor inventado. El llamador traduce el false a "sincroniza primero". Devuelve true si
  /// encoló. (La `version` NULL por ítem ES el flag de "pull de migración pendiente": el
  /// primer pull 200 la setea vía sincronizarPull.)
  Future<bool> encolarConVersionBase(
    SyncPendientesCompanion entrada,
    String entidadId,
  ) =>
      transaction(() async {
        final base = await (select(attachedDatabase.itemsCacheTable)
              ..where((t) => t.id.equals(entidadId)))
            .getSingleOrNull();
        return _encolarConVersion(entrada, base?.version);
      });

  /// Variante de [encolarConVersionBase] para la ruta del Residente (CTT-143 C2-fix): el
  /// ítem del Residente NO está en `items_cache` (se carga online como ItemResidente), así
  /// que la versión viene EXPLÍCITA de la que mostró la pantalla. [version] NULL → no encola
  /// (devuelve false). No necesita transacción: es un solo insert sin lectura previa.
  Future<bool> encolarConVersionBaseExplicita(
    SyncPendientesCompanion entrada,
    int? version,
  ) =>
      _encolarConVersion(entrada, version);

  /// Núcleo compartido: estampa `version_base` = [version] y encola; [version] NULL → NO
  /// encola y devuelve false (CTT-143 D7: nunca 0 ni inventado). Devuelve true si encoló.
  Future<bool> _encolarConVersion(
    SyncPendientesCompanion entrada,
    int? version,
  ) async {
    if (version == null) return false;
    await into(syncPendientes)
        .insert(entrada.copyWith(versionBase: Value(version)));
    return true;
  }

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

  /// No existe otra fila del MISMO agregado con `secuencia` menor en un estado que bloquee
  /// el envío: garantiza el orden FIFO por (tipo_entidad, entidad_id) — I3. C4b (21-oct):
  /// bloquean solo [estadosIntencionLocal] (pendiente/enviando); `esperandoResolucion` YA
  /// fue recibido por el servidor y NO frena a las siguientes del agregado.
  Expression<bool> _sinFilaAnteriorDelAgregado() {
    final p2 = alias(syncPendientes, 'p2');
    return notExistsQuery(
      selectOnly(p2)
        ..addColumns([p2.secuencia])
        ..where(
          p2.tipoEntidad.equalsExp(syncPendientes.tipoEntidad) &
              p2.entidadId.equalsExp(syncPendientes.entidadId) &
              p2.secuencia.isSmallerThan(syncPendientes.secuencia) &
              p2.estado.isIn(estadosIntencionLocalValores),
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

  /// Al recuperar conectividad (L3): borra el backoff (`proximo_intento_en`) de las
  /// filas pendientes cuya ÚLTIMA falla fue de RED —sin respuesta del servidor, por eso
  /// `ultimo_error_codigo` quedó NULL—, para que salgan de inmediato cuando vuelve la
  /// señal. NO toca las de backoff de servidor (5xx/408/429/otro 4xx) ni las que
  /// respetan un Retry-After: esas conservan su `proximo_intento_en`. Devuelve cuántas
  /// liberó.
  Future<int> liberarBackoffRed() => (update(syncPendientes)
        ..where((t) =>
            t.estado.equals(EstadoSyncLocal.pendiente.valor) &
            t.proximoIntentoEn.isNotNull() &
            t.ultimoErrorCodigo.isNull()))
      .write(const SyncPendientesCompanion(proximoIntentoEn: Value(null)));

  /// Fila COMPLETA (SELECT *) como Map crudo {columna: valor}, para enviarla a
  /// /sync/rescate con el MISMO formato que el flujo de pantalla
  /// ([leerFilasNoTerminalesCrudo] en apertura_base.dart): ambas usan `SELECT *`, así
  /// que las claves (nombres de columna) y los valores coinciden — incluye
  /// creado_en_dispositivo, payload_version, estado, conflicto_id, intentos_* y
  /// ultimo_error*. Devuelve null si la fila no existe. El ciclo sobrescribe los campos
  /// de la falla actual (intentos_servidor, ultimo_error, ultimo_error_codigo) antes de
  /// enviarla (CTT-103 D5).
  Future<Map<String, Object?>?> filaCrudaParaRescate(String id) async {
    final filas = await customSelect(
      'SELECT * FROM sync_pendientes WHERE id = ?1',
      variables: [Variable.withString(id)],
      readsFrom: {syncPendientes},
    ).get();
    if (filas.isEmpty) return null;
    return Map<String, Object?>.from(filas.single.data);
  }

  /// Aplica una [DecisionSync] a una entrada: solo escribe si la fila sigue en
  /// [estadoEsperado] (guarda anti-carrera) y —si se pasa [tomadoPor]— solo si el
  /// lease sigue siendo de esta corrida (cierre condicional, CTT-103 A2): un cierre
  /// tardío de una corrida que perdió el lease NO pisa a la que retomó la fila. Sin
  /// [tomadoPor] no se chequea el lease (el reconciliador no reclama lease).
  ///
  /// Escribe SIEMPRE `estado` = [DecisionSync.nuevoEstado] y `motivo` =
  /// [DecisionSync.motivo] EXACTO, incluido null (A4: una fila que llega a
  /// `sincronizado` no arrastra el motivo previo). [extra] trae el resto de los campos
  /// que calcula el ciclo (intentos_red/servidor, proximo_intento_en, conflicto_id,
  /// rechazo_id, ultimo_error, ultimo_error_codigo); NO debe traer estado/motivo (los
  /// pisa la decisión). Devuelve las filas afectadas (0 si la guarda no matcheó).
  ///
  /// Escritor ÚNICO del flag `items_cache.tiene_conflicto` (CTT-117 tramo 3), en la
  /// MISMA transacción que el estado de la cola, de forma simétrica:
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
    String? tomadoPor,
    SyncPendientesCompanion extra = const SyncPendientesCompanion(),
    String? estadoServidor,
    int? versionServidor,
    bool rebasearPosteriores = false,
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

        // La fila se lee ANTES del update: ninguna decisión toca entidad_id/secuencia/
        // version_base. Solo se lee si hay que escribir items_cache (flag/base) o rebasear.
        // Si la guarda matchea (afectadas > 0), la fila existía, así que no es null abajo.
        // El rebase lo decide el LLAMADOR (solo sabe él si este desenlace AVANZA la base):
        // 200 (sí), 409 (no, §7/C3c), resolución local/servidor (sí, P6). No se infiere del
        // estado terminal.
        final rebasear = rebasearPosteriores && versionServidor != null;
        final necesitaFila =
            nuevoFlag != null || estadoServidor != null || rebasear;
        final fila = !necesitaFila
            ? null
            : await (select(syncPendientes)..where((t) => t.id.equals(id)))
                .getSingleOrNull();
        final entidadId = fila?.entidadId;

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
          // estado y motivo los fija la decisión (motivo EXACTO, incl. null — A4);
          // el resto viene de [extra] (lo calcula el ciclo).
          extra.copyWith(
            estado: Value(decision.nuevoEstado.valor),
            motivo: Value(decision.motivo?.valor),
            // C3e: persiste la version del servidor del intento (200: ItemOut.version; 409:
            // version_actual) para que esperarResultadoFila la devuelva. La ruta del
            // Residente la usa como base de su próxima transición (su ítem no está en caché).
            versionResultante: versionServidor != null
                ? Value(versionServidor)
                : const Value.absent(),
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
          await _escribirFlagConflicto(entidadId!, nuevoFlag);
        }
        // Base del servidor (estado_servidor + version), MONÓTONA, en la MISMA transacción
        // que el estado de la cola: del ItemOut del 200 (CTT-144) o del detalle del 409 (C3c).
        if (estadoServidor != null) {
          await _escribirBaseEstado(entidadId!, estadoServidor, versionServidor);
        }
        // Rebase (C3a): la version del 200 pasa a ser version_base de las filas PENDIENTE
        // posteriores del MISMO agregado con el MISMO version_base que la fila confirmada.
        // Nunca toca enviando/esperando_resolucion/terminales. Opera sobre
        // sync_pendientes.version_base (no items_cache) → sirve también a las filas del
        // Residente, cuyo ítem no está en la caché.
        if (rebasear && fila != null && fila.versionBase != null) {
          await (update(syncPendientes)
                ..where((t) =>
                    t.tipoEntidad.equals(fila.tipoEntidad) &
                    t.entidadId.equals(fila.entidadId) &
                    t.estado.equals(EstadoSyncLocal.pendiente.valor) &
                    t.secuencia.isBiggerThanValue(fila.secuencia) &
                    t.versionBase.equals(fila.versionBase!)))
              .write(SyncPendientesCompanion(versionBase: Value(versionServidor)));
        }
        return afectadas;
      });

  /// Escribe `items_cache.tiene_conflicto` = [valor] para [entidadId]. SyncDao es el
  /// ESCRITOR ÚNICO del flag (CTT-117); lo usa [aplicarDecision] dentro de SU
  /// transacción. Si el ítem no está en caché (el full-replace del pull pudo sacarlo
  /// mientras su fila sigue encolada), deja rastro y sigue — no es error.
  Future<void> _escribirFlagConflicto(String entidadId, bool valor) async {
    final filasFlag = await (update(attachedDatabase.itemsCacheTable)
          ..where((t) => t.id.equals(entidadId)))
        .write(ItemsCacheTableCompanion(tieneConflicto: Value(valor)));
    if (filasFlag == 0) {
      debugPrint(
        'CTT-117: tiene_conflicto=$valor no aplicado — ítem $entidadId no está en '
        'items_cache.',
      );
    }
  }

  /// Escribe la BASE (`estado_servidor` + `version`) de [entidadId] de forma MONÓTONA
  /// (CTT-143 C3b): solo pisa si la `version` cacheada es NULL o <= [version] entrante — una
  /// respuesta vieja NUNCA baja la base. La invocan el 200 y el 409 (vía [aplicarDecision]),
  /// dentro de su transacción. Si [version] es null (caller sin versión), escribe solo el
  /// estado, sin gate (compat CTT-144). 0 filas = ítem no en `items_cache` (p. ej. del
  /// Residente) o versión vieja: NO es error, no se loguea (C3b).
  Future<void> _escribirBaseEstado(
      String entidadId, String estado, int? version) async {
    // version null → no se escribe NADA (C3e): sin version no se puede garantizar la
    // monotonía. En producción el 200 (B1), el 409 (B2) y la resolución (B4) SIEMPRE traen
    // version; null solo ocurriría contra un backend sin la columna → no se toca la base.
    if (version == null) return;
    await (update(attachedDatabase.itemsCacheTable)
          ..where((t) =>
              t.id.equals(entidadId) &
              (t.version.isNull() | t.version.isSmallerOrEqualValue(version))))
        .write(ItemsCacheTableCompanion(
          estadoServidor: Value(estado),
          version: Value(version),
        ));
  }

  /// Espera el resultado del PRIMER intento de la fila [filaId] (CTT-148). Completa
  /// cuando la fila SALE de `enviando` tras su intento:
  ///   - terminal (sincronizado/rechazada/descartado/en_revision) o esperandoResolucion
  ///     → devuelve ese estado;
  ///   - `pendiente` CON un intento registrado (bounce por red/servidor) → devuelve
  ///     `pendiente` + ultimo_error_codigo/ultimo_error (la UI avisa "se reintentará").
  /// Si no hay intento dentro de [timeout] (filas anteriores por FIFO, o sin red),
  /// devuelve `pendiente` SIN error. Único consumidor: TransicionService.ejecutar().
  Future<ResultadoEspera> esperarResultadoFila(
    String filaId, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final stream = (select(syncPendientes)..where((t) => t.id.equals(filaId)))
        .watchSingleOrNull();
    try {
      return await stream
          .map(_resolverEspera)
          .where((r) => r != null)
          .cast<ResultadoEspera>()
          .first
          .timeout(timeout);
    } on TimeoutException {
      final fila =
          await (select(syncPendientes)..where((t) => t.id.equals(filaId)))
              .getSingleOrNull();
      // Sin resolución a tiempo: sigue pendiente/enviando → la UI muestra "encolado".
      return _resolverEspera(fila) ??
          const ResultadoEspera(EstadoSyncLocal.pendiente);
    }
  }

  /// Traduce la fila observada a un [ResultadoEspera], o null si TODAVÍA no hay
  /// resultado del primer intento (sigue `enviando`, o `pendiente` sin intento).
  ResultadoEspera? _resolverEspera(SyncPendiente? fila) {
    if (fila == null) return null;
    final estado = EstadoSyncLocal.fromString(fila.estado);
    if (estado == EstadoSyncLocal.enviando) return null;
    if (estado == EstadoSyncLocal.pendiente) {
      if (fila.ultimoIntentoEn == null) return null; // aún no se intentó
      return ResultadoEspera(
        estado,
        ultimoErrorCodigo: fila.ultimoErrorCodigo,
        ultimoError: fila.ultimoError,
        versionResultante: fila.versionResultante,
      );
    }
    return ResultadoEspera(estado, versionResultante: fila.versionResultante);
  }

  /// Stream REACTIVO de entidad_id con sincronización pendiente (estados NO
  /// terminales). Para el indicador visual de la lista: con `.watch()` de Drift, el
  /// indicador se refresca solo cuando la cola cambia (p. ej. el ciclo foreground
  /// sincroniza y la nube se apaga), sin re-montar la pantalla. OJO: `.watch()` solo
  /// observa escrituras de ESTA conexión; no ve las del isolate headless (ver sync_dao
  /// / nota del commit D6-R).
  Stream<Set<String>> observarIdsPendienteSet() {
    // Fuente única de "no terminal": [estadosNoTerminales] (C4a).
    return (select(syncPendientes)
          ..where((t) => t.estado.isIn(estadosNoTerminalesValores)))
        .watch()
        .map((rows) => {for (final r in rows) r.entidadId});
  }

  /// Stream REACTIVO de entidad_id → estado de revisión (`rechazada` o `en_revision`);
  /// si un ítem tiene filas en ambos, gana `rechazada`. APARTE de
  /// [observarIdsPendienteSet] (CTT-103 D6 / A3: el indicador de pendientes no se toca).
  Stream<Map<String, EstadoSyncLocal>> observarEstadoRevisionPorItem() {
    return (select(syncPendientes)
          ..where((t) => t.estado.isIn([
                EstadoSyncLocal.rechazada.valor,
                EstadoSyncLocal.enRevision.valor,
              ])))
        .watch()
        .map((rows) {
      final out = <String, EstadoSyncLocal>{};
      for (final r in rows) {
        final e = EstadoSyncLocal.fromString(r.estado);
        // rechazada gana sobre en_revision; no se degrada una vez fijada.
        if (out[r.entidadId] != EstadoSyncLocal.rechazada) out[r.entidadId] = e;
      }
      return out;
    });
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

  /// Cuenta filas en estados NO terminales (pendiente / enviando / esperando_resolucion):
  /// cambios que todavía no se sincronizaron. Para la guardia de cierre de sesión
  /// (CTT-138). Fuente única de "no terminal": [estadosNoTerminales] (C4a).
  Future<int> contarNoTerminales() async {
    final count = syncPendientes.id.count();
    final q = selectOnly(syncPendientes)
      ..addColumns([count])
      ..where(syncPendientes.estado.isIn(estadosNoTerminalesValores));
    final row = await q.getSingle();
    return row.read(count) ?? 0;
  }
}
