/// extraer_detalle_backend.dart — Motivo legible de un error del backend.
///
/// Único helper compartido para leer el campo `detail` de una respuesta de
/// FastAPI desde un [DioException]. Vive en core/network porque opera sobre
/// [DioException] (concern de red) y solo depende de `package:dio`, así que
/// tanto los repositorios (data/) como los servicios de core/ pueden importarlo
/// sin riesgo de dependencia circular.
///
/// Deuda (CTT-65): hoy existen cinco copias privadas de esta lógica
/// (admin_repository, coordinador_repository, transicion_service,
/// error_interceptor, item_detalle_widgets). Migran a esta función en su
/// propio ticket; este commit solo la introduce con un consumidor (ciclo_sync).
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
