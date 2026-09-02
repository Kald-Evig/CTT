/// enums_ctt.dart — Enumeraciones del dominio CTT.
///
/// Espejo EXACTO de app/enums.py del backend. Los valores string coinciden
/// con los que envía/recibe la API; fromString() permite deserialización JSON.
/// Si el backend agrega un valor nuevo, agregarlo aquí también.
library;

// ── Rol de empresa ────────────────────────────────────────────────────────────
/// Roles a nivel de empresa (tabla empresa_usuario.rol).
/// NOTA: super_admin NO es un rol de empresa; se modela como flag booleano
/// esSuperAdmin en el perfil de usuario.
enum RolUsuario {
  admin('admin'),
  coordinador('coordinador'),
  residente('residente'),
  trabajador('trabajador');

  const RolUsuario(this.valor);
  final String valor;

  static RolUsuario fromString(String s) => values.firstWhere(
        (e) => e.valor == s,
        orElse: () => throw ArgumentError('RolUsuario desconocido: $s'),
      );
}

// ── Plan de empresa ───────────────────────────────────────────────────────────
enum PlanEmpresa {
  trial('trial'),
  basic('basic'),
  pro('pro');

  const PlanEmpresa(this.valor);
  final String valor;

  static PlanEmpresa fromString(String s) => values.firstWhere(
        (e) => e.valor == s,
        orElse: () => throw ArgumentError('PlanEmpresa desconocido: $s'),
      );
}

// ── Estado de empresa ─────────────────────────────────────────────────────────
enum EstadoEmpresa {
  activo('activo'),
  suspendido('suspendido'),
  trial('trial');

  const EstadoEmpresa(this.valor);
  final String valor;

  static EstadoEmpresa fromString(String s) => values.firstWhere(
        (e) => e.valor == s,
        orElse: () => throw ArgumentError('EstadoEmpresa desconocido: $s'),
      );
}

// ── Estado de usuario ─────────────────────────────────────────────────────────
enum EstadoUsuario {
  activo('activo'),
  inactivo('inactivo');

  const EstadoUsuario(this.valor);
  final String valor;

  static EstadoUsuario fromString(String s) => values.firstWhere(
        (e) => e.valor == s,
        orElse: () => throw ArgumentError('EstadoUsuario desconocido: $s'),
      );
}

// ── Estado de proyecto ────────────────────────────────────────────────────────
enum EstadoProyecto {
  activo('activo'),
  pausado('pausado'),
  cerrado('cerrado');

  const EstadoProyecto(this.valor);
  final String valor;

  static EstadoProyecto fromString(String s) => values.firstWhere(
        (e) => e.valor == s,
        orElse: () => throw ArgumentError('EstadoProyecto desconocido: $s'),
      );
}

// ── Estado de ítem (máquina de estados Sección 6.2) ──────────────────────────
/// Estados de la máquina de estados de ítems.
/// Transiciones válidas — ver domain/state_machine_client.dart.
/// R3: TERMINADO es irreversible salvo excepción de Admin.
enum EstadoItem {
  abierto('abierto'),
  enProgreso('en_progreso'),
  pendienteRevision('pendiente_revision'),
  terminado('terminado'),
  problema('problema');

  const EstadoItem(this.valor);
  final String valor;

  static EstadoItem fromString(String s) => values.firstWhere(
        (e) => e.valor == s,
        orElse: () => throw ArgumentError('EstadoItem desconocido: $s'),
      );
}

// ── Estado de problema ────────────────────────────────────────────────────────
enum EstadoProblema {
  abierto('abierto'),
  cerrado('cerrado');

  const EstadoProblema(this.valor);
  final String valor;

  static EstadoProblema fromString(String s) => values.firstWhere(
        (e) => e.valor == s,
        orElse: () => throw ArgumentError('EstadoProblema desconocido: $s'),
      );
}

// ── Estado de sync de evidencia (fotos offline) ───────────────────────────────
enum EstadoSyncEvidencia {
  pendiente('pendiente'),
  subida('subida'),
  error('error');

  const EstadoSyncEvidencia(this.valor);
  final String valor;

  static EstadoSyncEvidencia fromString(String s) => values.firstWhere(
        (e) => e.valor == s,
        orElse: () => throw ArgumentError('EstadoSyncEvidencia desconocido: $s'),
      );
}

// ── Estado de conflicto de sync ───────────────────────────────────────────────
enum EstadoConflicto {
  pendiente('pendiente'),
  resuelto('resuelto');

  const EstadoConflicto(this.valor);
  final String valor;

  static EstadoConflicto fromString(String s) => values.firstWhere(
        (e) => e.valor == s,
        orElse: () => throw ArgumentError('EstadoConflicto desconocido: $s'),
      );
}

// ── Tipo de entidad en la cola de sync ───────────────────────────────────────
enum TipoEntidad {
  item('item'),
  evidencia('evidencia');

  const TipoEntidad(this.valor);
  final String valor;

  static TipoEntidad fromString(String s) => values.firstWhere(
        (e) => e.valor == s,
        orElse: () => throw ArgumentError('TipoEntidad desconocido: $s'),
      );
}

// ── Acción de sync en la cola ─────────────────────────────────────────────────
enum AccionSync {
  cambioEstadoItem('cambio_estado_item'),
  subirFoto('subir_foto');

  const AccionSync(this.valor);
  final String valor;

  static AccionSync fromString(String s) => values.firstWhere(
        (e) => e.valor == s,
        orElse: () => throw ArgumentError('AccionSync desconocido: $s'),
      );
}

// ── Estado de sync local (cola de sincronización) ─────────────────────────────
/// Estado de una entrada en la cola local de sync (no existe en backend, es
/// gestión interna del dispositivo).
///
/// El estado es el CICLO DE VIDA (pocos valores, gobierna transiciones). La RAZÓN
/// vive aparte, en [MotivoSync] (metadato). Precedente: Azure Service Bus separa
/// el estado dead-lettered de DeadLetterReason; IBM MQ usa un Reason en el header
/// de la DLQ. Por eso `conflicto`/`rechazado`/`error` ya NO son estados: son
/// motivos, o se absorben en `pendiente`/`descartado`/`esperandoResolucion`.
enum EstadoSyncLocal {
  /// Encolada o reintentable: el ciclo la enviará.
  pendiente('pendiente'),

  /// Reclamada por un ciclo, POST en vuelo (transitorio).
  enviando('enviando'),

  /// 409 con conflicto_id: parqueada hasta que el Coordinador resuelva. NO se
  /// re-envía (re-POSTear daría otro 409).
  ///
  /// SUMIDERO CONOCIDO hasta el tramo 3: su única salida son las señales
  /// [SenalSync.resolucionGanoCliente]/[SenalSync.resolucionGanoServidor], que
  /// las emite el reconciliador de /sync/conflictos/mios (tramo 3 de CTT-117).
  /// Hasta que ese reconciliador exista, una entrada acá no tiene salida
  /// ejercida por código de producción.
  esperandoResolucion('esperando_resolucion'),

  /// TERMINAL — éxito: la intención vive en el servidor (envío directo o
  /// conflicto ganado por el cliente).
  sincronizado('sincronizado'),

  /// TERMINAL — la intención no se aplicará. El [MotivoSync] dice por qué.
  descartado('descartado');

  const EstadoSyncLocal(this.valor);
  final String valor;

  /// Estados terminales: sin transición de salida. Una fila acá no vuelve a
  /// moverse (la función de decisión lanza StateError si se lo intenta).
  bool get esTerminal =>
      this == EstadoSyncLocal.sincronizado || this == EstadoSyncLocal.descartado;

  static EstadoSyncLocal fromString(String s) => values.firstWhere(
        (e) => e.valor == s,
        orElse: () => throw ArgumentError('EstadoSyncLocal desconocido: $s'),
      );
}

// ── Motivo de sync local (razón, no ciclo de vida) ────────────────────────────
/// Razón asociada a una entrada de la cola. Metadato, muchos valores posibles;
/// no gobierna transiciones. Se persiste en la columna `motivo` de
/// `sync_pendientes`. Complementa a [EstadoSyncLocal].
enum MotivoSync {
  /// Último intento falló pero la fila sigue reintentable (diagnóstico).
  errorTransitorio('error_transitorio'),

  /// 409 con conflicto_id, esperando resolución del Coordinador.
  conflicto('conflicto'),

  /// Conflicto resuelto a favor del cliente: su cambio es la verdad.
  conflictoResueltoCliente('conflicto_resuelto_cliente'),

  /// Conflicto resuelto a favor del servidor: el cambio local no se aplica.
  conflictoResueltoServidor('conflicto_resuelto_servidor'),

  /// 4xx de negocio definitivo: 403/404/422 y 409 sin conflicto_id.
  rechazoNegocio('rechazo_negocio'),

  /// Falla transitoria que agotó [kMaxReintentosSync] intentos.
  reintentosAgotados('reintentos_agotados'),

  /// Fila heredada cuyo terminal no pudo determinarse. Fallback del
  /// reconciliador del tramo 3 cuando /mios no tiene registro del conflicto.
  heredadoIndeterminado('heredado_indeterminado');

  const MotivoSync(this.valor);
  final String valor;

  static MotivoSync fromString(String s) => values.firstWhere(
        (e) => e.valor == s,
        orElse: () => throw ArgumentError('MotivoSync desconocido: $s'),
      );
}
