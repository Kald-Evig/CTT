library;

class CambioConflicto {
  const CambioConflicto({required this.estado, this.comentario});

  final String estado;
  final String? comentario;

  factory CambioConflicto.fromJson(Map<String, dynamic> json) =>
      CambioConflicto(
        estado: json['estado'] as String? ?? '',
        comentario: json['comentario'] as String?,
      );
}

class ConflictoSync {
  const ConflictoSync({
    required this.id,
    required this.itemId,
    this.cambioLocal,
    this.cambioServidor,
    required this.dispositivoId,
    required this.estado,
    this.resueltoPor,
    required this.createdAt,
  });

  final String id;
  final String itemId;
  final CambioConflicto? cambioLocal;
  final CambioConflicto? cambioServidor;
  final String dispositivoId;
  final String estado;
  final String? resueltoPor;
  final DateTime createdAt;

  factory ConflictoSync.fromJson(Map<String, dynamic> json) => ConflictoSync(
        id: json['id'] as String,
        itemId: json['item_id'] as String,
        cambioLocal: json['cambio_local'] != null
            ? CambioConflicto.fromJson(json['cambio_local'] as Map<String, dynamic>)
            : null,
        cambioServidor: json['cambio_servidor'] != null
            ? CambioConflicto.fromJson(json['cambio_servidor'] as Map<String, dynamic>)
            : null,
        dispositivoId: json['dispositivo_id'] as String,
        estado: json['estado'] as String,
        resueltoPor: json['resuelto_por'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

class ProyectoCoordinador {
  const ProyectoCoordinador({
    required this.id,
    required this.nombre,
    required this.estado,
    this.descripcion,
    this.ubicacionNombre,
    this.latitud,
    this.longitud,
    this.coordinadorPrincipalId,
    this.fechaInicio,
    this.fechaFinEstimada,
  });

  final String id;
  final String nombre;
  final String estado;
  final String? descripcion;
  final String? ubicacionNombre;
  final double? latitud;
  final double? longitud;
  final String? coordinadorPrincipalId;
  final String? fechaInicio;
  final String? fechaFinEstimada;

  factory ProyectoCoordinador.fromJson(Map<String, dynamic> json) =>
      ProyectoCoordinador(
        id: json['id'] as String,
        nombre: json['nombre'] as String,
        estado: json['estado'] as String,
        descripcion: json['descripcion'] as String?,
        ubicacionNombre: json['ubicacion_nombre'] as String?,
        latitud: (json['latitud'] as num?)?.toDouble(),
        longitud: (json['longitud'] as num?)?.toDouble(),
        coordinadorPrincipalId: json['coordinador_principal_id'] as String?,
        fechaInicio: json['fecha_inicio'] as String?,
        fechaFinEstimada: json['fecha_fin_estimada'] as String?,
      );
}
