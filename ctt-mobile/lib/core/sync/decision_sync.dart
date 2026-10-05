/// decision_sync.dart — Función de decisión de la cola de sincronización.
///
/// Separa la DECISIÓN (a qué estado va una entrada, con qué motivo, qué contador
/// incrementa, si aplica backoff o pausa la cola) del TRANSPORTE (Dio, HTTP) y del
/// EFECTO (la escritura en Drift). Es Dart puro: NO importa `dio`, NI `drift`, NI el
/// DAO. Solo conoce el dominio (los enums). Por eso se testea sin red ni base.
///
/// El acoplamiento con el transporte queda en los llamadores (ciclo_sync._clasificar
/// y el reconciliador): ellos traducen su realidad (un `DioException`, una fila de
/// /mios) a una [SenalSync] de dominio, y recién entonces llaman a [decidir]. El
/// CÁLCULO del backoff (DateTime con jitter y Retry-After) vive en el ciclo, no acá.
library;

import 'package:ctt_mobile/domain/enums/enums_ctt.dart';

/// Tope de `intentos_servidor` antes de derivar la fila a /sync/rescate (CTT-103 D5,
/// commit siguiente). En ESTE commit, al alcanzarlo la fila sigue pendiente con el
/// backoff máximo — NUNCA se descarta.
const kTopeIntentosServidor = 6;

/// Lo que ocurrió con una operación de la cola, en términos de DOMINIO.
/// Deliberadamente SIN códigos HTTP: el mapeo vive en ciclo_sync._clasificar.
enum SenalSync {
  /// El envío se aplicó en el servidor (2xx).
  envioOk,

  /// 409 de concurrencia con conflicto_id: requiere resolución del Coordinador.
  conflictoDetectado,

  /// 4xx con `rechazo_id`: rechazo determinista persistido en el servidor. Terminal.
  rechazadoPorServidor,

  /// Falla reintentable de RED/servidor transitorio: sin red, timeout, 5xx (salvo
  /// 501), 408, 429. Backoff por `intentos_red`; NUNCA descarta.
  fallaTransitoriaRed,

  /// 4xx NO determinista (sin rechazo_id): 409 solicitud_en_proceso, 422, 501, 409
  /// sin Map, 403/404 de sesión, desconocidos. Backoff por `intentos_servidor`.
  fallaServidor,

  /// 401: sesión vencida. PAUSA la cola (la corrida aborta); la fila vuelve a
  /// pendiente sin sumar contadores.
  sesionVencida,

  /// El Coordinador resolvió el conflicto a favor del cliente (reconciliador).
  resolucionGanoCliente,

  /// El Coordinador resolvió el conflicto a favor del servidor (reconciliador).
  resolucionGanoServidor,
}

/// Qué contador de reintentos incrementa una decisión (si alguno).
enum IncrementoContador { ninguno, red, servidor }

/// Resultado puro de [decidir]: qué escribir, sin escribir nada. El llamador (a
/// través del DAO) aplica esta decisión.
class DecisionSync {
  const DecisionSync({
    required this.nuevoEstado,
    this.motivo,
    this.incremento = IncrementoContador.ninguno,
    this.aplicaBackoff = false,
    this.pausaCola = false,
  });

  /// Estado al que pasa la entrada.
  final EstadoSyncLocal nuevoEstado;

  /// Motivo EXACTO, incluido `null` (A4): una fila que llega a `sincronizado` NO
  /// arrastra un motivo previo — el DAO escribe este valor tal cual (null = limpia).
  final MotivoSync? motivo;

  /// Qué contador incrementar. El ciclo calcula el backoff a partir del nuevo valor.
  final IncrementoContador incremento;

  /// Si la fila debe recibir un `proximo_intento_en` (backoff). El valor concreto lo
  /// calcula el ciclo (jitter + Retry-After).
  final bool aplicaBackoff;

  /// 401: la corrida ABORTA tras aplicar esta decisión (no sigue con las demás filas).
  final bool pausaCola;
}

/// Decide el próximo estado y metadatos de una entrada de la cola, a partir de
/// (estado actual, señal). Lanza [StateError] ante una combinación inválida —incluido
/// cualquier intento de mover un estado TERMINAL—, lo que vuelve el grafo verificable.
DecisionSync decidir({
  required EstadoSyncLocal estadoActual,
  required SenalSync senal,
}) {
  if (estadoActual.esTerminal) {
    throw StateError(
      'Transición inválida: $estadoActual es terminal y no acepta señales '
      '(recibió $senal).',
    );
  }

  switch (estadoActual) {
    case EstadoSyncLocal.pendiente:
    case EstadoSyncLocal.enviando:
      return _desdeEnvio(senal, estadoActual);
    case EstadoSyncLocal.esperandoResolucion:
      return _desdeEspera(senal, estadoActual);
    case EstadoSyncLocal.sincronizado:
    case EstadoSyncLocal.descartado:
    case EstadoSyncLocal.rechazada:
    case EstadoSyncLocal.enRevision:
      // Inalcanzable: cubierto por el guard de esTerminal de arriba.
      throw StateError('Estado terminal no manejado: $estadoActual.');
  }
}

/// Transiciones desde una entrada que se está (o va a) enviar.
DecisionSync _desdeEnvio(SenalSync senal, EstadoSyncLocal desde) {
  switch (senal) {
    case SenalSync.envioOk:
      // A4: motivo null → limpia cualquier motivo previo al llegar a sincronizado.
      return const DecisionSync(nuevoEstado: EstadoSyncLocal.sincronizado);

    case SenalSync.conflictoDetectado:
      return const DecisionSync(
        nuevoEstado: EstadoSyncLocal.esperandoResolucion,
        motivo: MotivoSync.conflicto,
      );

    case SenalSync.rechazadoPorServidor:
      return const DecisionSync(
        nuevoEstado: EstadoSyncLocal.rechazada,
        motivo: MotivoSync.rechazoNegocio,
      );

    case SenalSync.fallaTransitoriaRed:
      // NUNCA descarta: vuelve a pendiente con backoff por intentos_red.
      return const DecisionSync(
        nuevoEstado: EstadoSyncLocal.pendiente,
        motivo: MotivoSync.errorTransitorio,
        incremento: IncrementoContador.red,
        aplicaBackoff: true,
      );

    case SenalSync.fallaServidor:
      // NUNCA descarta: vuelve a pendiente con backoff por intentos_servidor.
      return const DecisionSync(
        nuevoEstado: EstadoSyncLocal.pendiente,
        motivo: MotivoSync.fallaServidor,
        incremento: IncrementoContador.servidor,
        aplicaBackoff: true,
      );

    case SenalSync.sesionVencida:
      // Pausa: vuelve a pendiente sin contadores ni backoff; la corrida aborta.
      return const DecisionSync(
        nuevoEstado: EstadoSyncLocal.pendiente,
        pausaCola: true,
      );

    case SenalSync.resolucionGanoCliente:
    case SenalSync.resolucionGanoServidor:
      throw StateError(
        'Señal de resolución ($senal) inválida en estado $desde: solo aplica a '
        'esperandoResolucion.',
      );
  }
}

/// Transiciones desde una entrada parqueada esperando resolución de conflicto.
DecisionSync _desdeEspera(SenalSync senal, EstadoSyncLocal desde) {
  switch (senal) {
    case SenalSync.resolucionGanoCliente:
      return const DecisionSync(
        nuevoEstado: EstadoSyncLocal.sincronizado,
        motivo: MotivoSync.conflictoResueltoCliente,
      );

    case SenalSync.resolucionGanoServidor:
      return const DecisionSync(
        nuevoEstado: EstadoSyncLocal.descartado,
        motivo: MotivoSync.conflictoResueltoServidor,
      );

    case SenalSync.envioOk:
    case SenalSync.conflictoDetectado:
    case SenalSync.rechazadoPorServidor:
    case SenalSync.fallaTransitoriaRed:
    case SenalSync.fallaServidor:
    case SenalSync.sesionVencida:
      throw StateError(
        'Señal de envío ($senal) inválida en estado $desde: la fila espera '
        'resolución de conflicto, no reintento de envío.',
      );
  }
}
