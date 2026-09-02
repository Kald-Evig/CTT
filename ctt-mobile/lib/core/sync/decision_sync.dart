/// decision_sync.dart — Función de decisión de la cola de sincronización.
///
/// Separa la DECISIÓN (a qué estado va una entrada y con qué motivo) del
/// TRANSPORTE (Dio, HTTP, la respuesta del servidor) y del EFECTO (la escritura
/// en Drift). Es Dart puro: NO importa `dio`, NI `drift`, NI el DAO. Solo conoce
/// el dominio (los enums). Por eso se testea sin red ni base de datos.
///
/// El acoplamiento con el transporte queda en los llamadores (ciclo_sync,
/// transicion_service y —en el tramo 3— el reconciliador de /sync/conflictos/mios):
/// ellos traducen su realidad (un `DioException`, un status 409, una fila de
/// /mios) a una [SenalSync] de dominio, y recién entonces llaman a [decidir].
library;

import 'package:ctt_mobile/domain/enums/enums_ctt.dart';

/// Tope de reintentos de una entrada antes de considerarla agotada.
/// Fuente única del número: lo usa [decidir] para decidir si una falla
/// transitoria vuelve a `pendiente` o termina en `descartado`, y la migración
/// v3→v4 para mapear las filas `error` heredadas.
const kMaxReintentosSync = 5;

/// Lo que ocurrió con una operación de la cola, en términos de DOMINIO.
///
/// Deliberadamente SIN códigos HTTP: el mapeo `409→conflictoDetectado`,
/// `403/404/422→rechazoDefinitivo`, `timeout/5xx→fallaTransitoria` vive en la
/// capa de transporte, no acá.
enum SenalSync {
  /// El envío se aplicó en el servidor (2xx).
  envioOk,

  /// Falla reintentable: sin red, timeout, 5xx.
  fallaTransitoria,

  /// Rechazo de negocio definitivo: 4xx que no se arregla reintentando
  /// (403/404/422 y 409 sin conflicto_id).
  rechazoDefinitivo,

  /// Conflicto de concurrencia (409 con conflicto_id): requiere resolución
  /// manual del Coordinador. No se reintenta por envío.
  conflictoDetectado,

  /// El Coordinador resolvió el conflicto a favor del cliente: su cambio es la
  /// verdad. Emitida por el reconciliador del tramo 3.
  resolucionGanoCliente,

  /// El Coordinador resolvió el conflicto a favor del servidor: el cambio local
  /// no se aplica. Emitida por el reconciliador del tramo 3.
  resolucionGanoServidor,
}

/// Resultado puro de [decidir]: qué escribir, sin escribir nada.
///
/// El llamador (a través del DAO) aplica esta decisión. Separar decisión de
/// efecto permite testear el grafo de transiciones sin tocar Drift.
class DecisionSync {
  const DecisionSync({
    required this.nuevoEstado,
    this.motivo,
    this.incrementaReintentos = false,
    this.registraDescarte = false,
  });

  /// Estado al que pasa la entrada.
  final EstadoSyncLocal nuevoEstado;

  /// Motivo asociado, o null en el camino feliz sin incidencia.
  final MotivoSync? motivo;

  /// True solo cuando una falla transitoria NO agotada vuelve a `pendiente`.
  final bool incrementaReintentos;

  /// True en los terminales negativos (descartes). Señal para la telemetría y
  /// la bandeja del usuario (tramo 4): hubo trabajo que no se aplicará.
  final bool registraDescarte;
}

/// Decide el próximo estado y motivo de una entrada de la cola.
///
/// No conoce Dio, HTTP ni el origen de la señal. Lanza [StateError] ante una
/// combinación (estado, señal) inválida —incluido cualquier intento de mover un
/// estado TERMINAL—, lo que convierte el grafo de transiciones en algo
/// verificable (ver decision_sync_test.dart).
DecisionSync decidir({
  required EstadoSyncLocal estadoActual,
  required SenalSync senal,
  required int reintentos,
  int maxReintentos = kMaxReintentosSync,
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
      return _desdeEnvio(senal, reintentos, maxReintentos, estadoActual);
    case EstadoSyncLocal.esperandoResolucion:
      return _desdeEspera(senal, estadoActual);
    case EstadoSyncLocal.sincronizado:
    case EstadoSyncLocal.descartado:
      // Inalcanzable: cubierto por el guard de esTerminal de arriba.
      throw StateError('Estado terminal no manejado: $estadoActual.');
  }
}

/// Transiciones desde una entrada que se está (o va a) enviar.
DecisionSync _desdeEnvio(
  SenalSync senal,
  int reintentos,
  int maxReintentos,
  EstadoSyncLocal desde,
) {
  switch (senal) {
    case SenalSync.envioOk:
      return const DecisionSync(nuevoEstado: EstadoSyncLocal.sincronizado);

    case SenalSync.rechazoDefinitivo:
      return const DecisionSync(
        nuevoEstado: EstadoSyncLocal.descartado,
        motivo: MotivoSync.rechazoNegocio,
        registraDescarte: true,
      );

    case SenalSync.conflictoDetectado:
      return const DecisionSync(
        nuevoEstado: EstadoSyncLocal.esperandoResolucion,
        motivo: MotivoSync.conflicto,
      );

    case SenalSync.fallaTransitoria:
      final agotado = reintentos + 1 >= maxReintentos;
      if (agotado) {
        return const DecisionSync(
          nuevoEstado: EstadoSyncLocal.descartado,
          motivo: MotivoSync.reintentosAgotados,
          registraDescarte: true,
        );
      }
      return const DecisionSync(
        nuevoEstado: EstadoSyncLocal.pendiente,
        motivo: MotivoSync.errorTransitorio,
        incrementaReintentos: true,
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
        registraDescarte: true,
      );

    case SenalSync.envioOk:
    case SenalSync.fallaTransitoria:
    case SenalSync.rechazoDefinitivo:
    case SenalSync.conflictoDetectado:
      throw StateError(
        'Señal de envío ($senal) inválida en estado $desde: la fila espera '
        'resolución de conflicto, no reintento de envío.',
      );
  }
}
