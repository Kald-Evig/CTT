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

// ── Estado de sync local (cola de sincronización) ─────────────────────────────
/// Estado de un registro en la cola local de sync (no existe en backend,
/// es gestión interna del dispositivo).
enum EstadoSyncLocal {
  pendiente('pendiente'),
  enviando('enviando'),
  sincronizado('sincronizado'),
  error('error'),
  /// Conflicto detectado — requiere resolución manual por Coordinador/Admin.
  conflicto('conflicto');

  const EstadoSyncLocal(this.valor);
  final String valor;

  static EstadoSyncLocal fromString(String s) => values.firstWhere(
        (e) => e.valor == s,
        orElse: () => throw ArgumentError('EstadoSyncLocal desconocido: $s'),
      );
}
