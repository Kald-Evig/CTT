/// red_helpers.dart — Helpers de red compartidos por los repositorios.
library;

import 'package:dio/dio.dart';

/// GET a un endpoint de lista y mapea cada elemento con [fromJson].
///
/// Fuente única del patrón "traer lista y deserializar" que antes vivía
/// duplicado como `_fetchList` en admin/coordinador/residente repositories.
Future<List<T>> fetchList<T>(
  Dio dio,
  String url,
  T Function(Map<String, dynamic>) fromJson, {
  Map<String, dynamic>? queryParameters,
}) async {
  final resp =
      await dio.get<List<dynamic>>(url, queryParameters: queryParameters);
  return (resp.data ?? []).cast<Map<String, dynamic>>().map(fromJson).toList();
}
