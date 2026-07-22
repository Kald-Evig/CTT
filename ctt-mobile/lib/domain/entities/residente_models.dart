/// residente_models.dart — Modelos de dominio para el rol Residente.
///
/// Clases simples de deserialización JSON. El Residente trabaja siempre
/// online; no hay persistencia local (Drift) para estos datos.
library;

class ProyectoResidente {
  const ProyectoResidente({
    required this.id,
    required this.nombre,
    required this.estado,
  });

  final String id;
  final String nombre;
  final String estado;

  factory ProyectoResidente.fromJson(Map<String, dynamic> json) =>
      ProyectoResidente(
        id: json['id'] as String,
        nombre: json['nombre'] as String,
        estado: json['estado'] as String,
      );
}

class ItemResidente {
  const ItemResidente({
    required this.id,
    required this.proyectoId,
    this.parentItemId,
    required this.nivelProfundidad,
    required this.nombre,
    this.descripcion,
    this.asignadoA,
    this.asignadoNombre,
    required this.estado,
    this.fechaLimite,
    this.duracionEstimadaHoras,
    this.orden = 0,
    this.ultimaEdicionPor,
    this.ultimaEdicionEn,
  });

  final String id;
  final String proyectoId;
  final String? parentItemId;
  final int nivelProfundidad;
  final String nombre;
  final String? descripcion;
  final String? asignadoA;
  final String? asignadoNombre;
  final String estado;
  final String? fechaLimite;
  final double? duracionEstimadaHoras;
  final int orden;
  final String? ultimaEdicionPor;
  final DateTime? ultimaEdicionEn;

  factory ItemResidente.fromJson(Map<String, dynamic> json) => ItemResidente(
        id: json['id'] as String,
        proyectoId: json['proyecto_id'] as String,
        parentItemId: json['parent_item_id'] as String?,
        nivelProfundidad: json['nivel_profundidad'] as int? ?? 0,
        nombre: json['nombre'] as String,
        descripcion: json['descripcion'] as String?,
        asignadoA: json['asignado_a'] as String?,
        asignadoNombre: json['asignado_nombre'] as String?,
        estado: json['estado'] as String,
        fechaLimite: json['fecha_limite'] as String?,
        duracionEstimadaHoras:
            (json['duracion_estimada_horas'] as num?)?.toDouble(),
        orden: json['orden'] as int? ?? 0,
        ultimaEdicionPor: json['ultima_edicion_por'] as String?,
        ultimaEdicionEn: json['ultima_edicion_en'] == null
            ? null
            : DateTime.parse(json['ultima_edicion_en'] as String),
      );
}

class ComentarioItem {
  const ComentarioItem({
    required this.id,
    required this.usuarioId,
    this.nombreUsuario,
    required this.texto,
    required this.createdAt,
  });

  final String id;
  final String usuarioId;
  final String? nombreUsuario;
  final String texto;
  final DateTime createdAt;

  factory ComentarioItem.fromJson(Map<String, dynamic> json) => ComentarioItem(
        id: json['id'] as String,
        usuarioId: json['usuario_id'] as String,
        nombreUsuario: json['nombre_usuario'] as String?,
        texto: json['texto'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

class EvidenciaItem {
  const EvidenciaItem({
    required this.id,
    required this.usuarioId,
    this.s3Url,
    this.thumbnailUrl,
    required this.syncStatus,
    required this.deviceTimestamp,
    required this.createdAt,
  });

  final String id;
  final String usuarioId;
  final String? s3Url;
  final String? thumbnailUrl;
  final String syncStatus;
  final DateTime deviceTimestamp;
  final DateTime createdAt;

  factory EvidenciaItem.fromJson(Map<String, dynamic> json) => EvidenciaItem(
        id: json['id'] as String,
        usuarioId: json['usuario_id'] as String,
        s3Url: json['s3_url'] as String?,
        thumbnailUrl: json['thumbnail_url'] as String?,
        syncStatus: json['sync_status'] as String,
        deviceTimestamp: DateTime.parse(json['device_timestamp'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

class EntradaHistorial {
  const EntradaHistorial({
    required this.accion,
    this.estadoAnterior,
    this.estadoNuevo,
    this.detalle,
    this.usuarioId,
    this.nombreUsuario,
    required this.createdAt,
  });

  final String accion;
  final String? estadoAnterior;
  final String? estadoNuevo;
  final String? detalle;
  final String? usuarioId;
  final String? nombreUsuario;
  final DateTime createdAt;

  factory EntradaHistorial.fromJson(Map<String, dynamic> json) =>
      EntradaHistorial(
        accion: json['accion'] as String,
        estadoAnterior: json['estado_anterior'] as String?,
        estadoNuevo: json['estado_nuevo'] as String?,
        detalle: json['detalle'] as String?,
        usuarioId: json['usuario_id'] as String?,
        nombreUsuario: json['nombre_usuario'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

class NotificacionResidente {
  const NotificacionResidente({
    required this.id,
    required this.evento,
    required this.titulo,
    this.cuerpo,
    required this.leida,
    required this.createdAt,
  });

  final String id;
  final String evento;
  final String titulo;
  final String? cuerpo;
  final bool leida;
  final DateTime createdAt;

  factory NotificacionResidente.fromJson(Map<String, dynamic> json) =>
      NotificacionResidente(
        id: json['id'] as String,
        evento: json['evento'] as String,
        titulo: json['titulo'] as String,
        cuerpo: json['cuerpo'] as String?,
        leida: json['leida'] as bool,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

class UsuarioEmpresa {
  const UsuarioEmpresa({
    required this.id,
    required this.nombreCompleto,
    required this.email,
    required this.estado,
    required this.rol,
  });

  final String id;
  final String nombreCompleto;
  final String email;
  final String estado;
  final String rol;

  factory UsuarioEmpresa.fromJson(Map<String, dynamic> json) => UsuarioEmpresa(
        id: json['id'] as String,
        nombreCompleto: json['nombre_completo'] as String,
        email: json['email'] as String,
        estado: json['estado'] as String,
        rol: json['rol'] as String,
      );
}
