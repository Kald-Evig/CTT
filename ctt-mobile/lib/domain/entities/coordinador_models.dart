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

// ── Dashboard (CTT-42) ────────────────────────────────────────────────────────

class DashboardProyecto {
  const DashboardProyecto({
    required this.id,
    required this.nombre,
    required this.estado,
    this.fechaInicio,
    this.fechaFinEstimada,
    required this.totalItems,
    required this.itemsTerminados,
    required this.pctCompleto,
    required this.totalHojas,
    required this.hojasTerminadas,
    required this.pctReal,
  });

  final String id;
  final String nombre;
  final String estado;
  final String? fechaInicio;
  final String? fechaFinEstimada;
  final int totalItems;
  final int itemsTerminados;
  final double pctCompleto;
  final int totalHojas;
  final int hojasTerminadas;
  final double pctReal;

  factory DashboardProyecto.fromJson(Map<String, dynamic> json) =>
      DashboardProyecto(
        id: json['id'] as String,
        nombre: json['nombre'] as String,
        estado: json['estado'] as String,
        fechaInicio: json['fecha_inicio'] as String?,
        fechaFinEstimada: json['fecha_fin_estimada'] as String?,
        totalItems: json['total_items'] as int,
        itemsTerminados: json['items_terminados'] as int,
        pctCompleto: (json['pct_completo'] as num).toDouble(),
        totalHojas: json['total_hojas'] as int,
        hojasTerminadas: json['hojas_terminadas'] as int,
        pctReal: (json['pct_real'] as num).toDouble(),
      );
}

class HistorialProyectoEntrada {
  const HistorialProyectoEntrada({
    required this.itemId,
    required this.itemNombre,
    required this.accion,
    this.estadoAnterior,
    this.estadoNuevo,
    this.detalle,
    this.usuarioId,
    this.nombreUsuario,
    required this.createdAt,
  });

  final String itemId;
  final String itemNombre;
  final String accion;
  final String? estadoAnterior;
  final String? estadoNuevo;
  final String? detalle;
  final String? usuarioId;
  final String? nombreUsuario;
  final DateTime createdAt;

  factory HistorialProyectoEntrada.fromJson(Map<String, dynamic> json) =>
      HistorialProyectoEntrada(
        itemId: json['item_id'] as String,
        itemNombre: json['item_nombre'] as String,
        accion: json['accion'] as String,
        estadoAnterior: json['estado_anterior'] as String?,
        estadoNuevo: json['estado_nuevo'] as String?,
        detalle: json['detalle'] as String?,
        usuarioId: json['usuario_id'] as String?,
        nombreUsuario: json['nombre_usuario'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
