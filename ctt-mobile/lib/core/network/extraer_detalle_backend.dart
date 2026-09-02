/// extraer_detalle_backend.dart — Lectores del `detail` de un error del backend.
///
/// Helpers compartidos que leen la respuesta de FastAPI desde un [DioException]:
///   - [extraerDetalleBackend]: el motivo legible (String).
///   - [extraerConflictoId]:    el `conflicto_id` de un 409 de concurrencia.
/// Viven en core/network porque operan sobre [DioException] (concern de red) y
/// solo dependen de `package:dio`, así que tanto los repositorios (data/) como
/// los servicios de core/ pueden importarlos sin riesgo de dependencia circular.
///
/// CTT-65: única fuente del parseo del `detail`. Consumidores: ciclo_sync,
/// transicion_service, admin_repository, coordinador_repository,
/// error_interceptor e item_detalle_widgets. Ya no quedan copias privadas.
library;

import 'package:dio/dio.dart';

/// Devuelve el motivo legible del error, priorizando el `detail` del backend.
///
/// Maneja las tres formas que devuelve el backend y cae al mensaje de Dio si
/// no hay body o no hay `detail`:
///   - `detail` String                → se devuelve tal cual (403/404/409 de negocio).
///   - `detail` lista (Pydantic, 422) → resumen de los `msg`, no el objeto crudo.
///   - `detail` Map con 'mensaje'     → ese valor (error de negocio estructurado).
///   - sin body / sin detail          → `e.message ?? 'Error de red'`.
String extraerDetalleBackend(DioException e) {
  final data = e.response?.data;
  if (data is Map<String, dynamic>) {
    final detail = data['detail'];

    if (detail is String) return detail;

    // 422 de FastAPI: `detail` es una lista de errores Pydantic. Resumir los
    // `msg` en texto legible en vez de volcar el objeto crudo con toString().
    if (detail is List) {
      final mensajes = detail
          .whereType<Map<String, dynamic>>()
          .map((item) => item['msg'])
          .whereType<String>()
          .toList();
      if (mensajes.isNotEmpty) return mensajes.join('; ');
    }

    if (detail is Map<String, dynamic>) {
      final mensaje = detail['mensaje'];
      if (mensaje is String) return mensaje;
    }
  }
  return e.message ?? 'Error de red';
}

/// Devuelve el `conflicto_id` de un 409 de conflicto de concurrencia, o null.
///
/// El backend lo anida bajo `detail` (ver `transicion_item`):
///   `{"detail": {"tipo": "conflicto_concurrencia", "conflicto_id": "...", ...}}`
/// Devuelve null ante cualquier otra forma —sin body, `detail` String (rechazo
/// de negocio), `detail` lista (422 de Pydantic), o `detail` Map sin la clave—
/// para que la clasificación de la cola no distinga un rechazo de un conflicto.
String? extraerConflictoId(DioException e) {
  final data = e.response?.data;
  if (data is Map<String, dynamic>) {
    final detail = data['detail'];
    if (detail is Map<String, dynamic>) {
      final id = detail['conflicto_id'];
      if (id is String) return id;
    }
  }
  return null;
}
