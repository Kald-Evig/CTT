/// dio_client.dart — Cliente HTTP configurado para la API de CTT.
///
/// Expuesto como provider de Riverpod para inyección de dependencias.
/// Logging activo solo en modo debug; en release no se registra nada de red.

import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:ctt_mobile/core/config/environment.dart';
import 'package:ctt_mobile/core/network/interceptors/auth_interceptor.dart';
import 'package:ctt_mobile/core/network/interceptors/error_interceptor.dart';
import 'package:ctt_mobile/core/security/secure_storage_service.dart';

part 'dio_client.g.dart';

@riverpod
SecureStorageService secureStorage(SecureStorageRef ref) =>
    SecureStorageService();

@riverpod
Logger logger(LoggerRef ref) => Logger(
      // En release suprimir output de log.
      level: Entorno.esRelease ? Level.off : Level.debug,
      printer: PrettyPrinter(methodCount: 0, printTime: true),
    );

@riverpod
Dio dioClient(DioClientRef ref) {
  final storage = ref.watch(secureStorageProvider);
  final log = ref.watch(loggerProvider);

  final dio = Dio(BaseOptions(
    baseUrl: Entorno.urlBaseApi,
    connectTimeout: Entorno.timeoutConexion,
    receiveTimeout: Entorno.timeoutRecepcion,
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    },
  ));

  // Interceptor de auth: adjunta JWT + X-Empresa-Id.
  dio.interceptors.add(AuthInterceptor(storage));

  // Interceptor de errores: convierte HTTP errors en excepciones tipadas.
  dio.interceptors.add(ErrorInterceptor(
    log,
    alCerrarSesion: () async {
      await storage.limpiarSesion();
      // TODO Fase 1.3: disparar evento de logout en el AuthNotifier de Riverpod.
    },
  ));

  // Log detallado de requests solo en debug.
  if (Entorno.esDebug) {
    dio.interceptors.add(LogInterceptor(
      requestBody: false,   // no loggear body — puede contener datos sensibles
      responseBody: false,  // ídem
      logPrint: (obj) => log.d(obj.toString()),
    ));
  }

  return dio;
}
