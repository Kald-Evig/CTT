/// dio_client.dart — Clientes HTTP configurados para la API de CTT.
///
/// Tres Dio, UNA fuente de opciones base ([opcionesBaseDio]):
///   - [dioClient]  interactivo: AuthInterceptor + ErrorInterceptor (401→logout).
///   - [dioSync]    cola de sync: AuthInterceptor, SIN ErrorInterceptor (el 401 lo
///                  pausa el ciclo, no desloguea — CTT-103 D4) y con X-Sync-Origen.
///   - [dioRescate] rescate a cuarentena (en rescate_service.dart): sin interceptores,
///                  setea Authorization a mano.
/// Logging activo solo en modo debug; en release no se registra nada de red.
library;

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
      level: Entorno.esRelease ? Level.off : Level.debug,
      printer: PrettyPrinter(
        methodCount: 0,
        dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
      ),
    );

/// Opciones base compartidas por TODOS los Dio de la app: baseUrl, timeouts y headers
/// comunes. Fuente única — no copiar esta configuración. El mapa de headers es NUEVO
/// y mutable por llamada, para que cada Dio agregue los suyos (p. ej. X-Sync-Origen
/// del sync) sin pisar a los demás.
BaseOptions opcionesBaseDio() => BaseOptions(
      baseUrl: Entorno.urlBaseApi,
      connectTimeout: Entorno.timeoutConexion,
      receiveTimeout: Entorno.timeoutRecepcion,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    );

/// Agrega el LogInterceptor solo en debug (sin body: puede traer datos sensibles).
void _agregarLogDebug(Dio dio, Logger log) {
  if (!Entorno.esDebug) return;
  dio.interceptors.add(LogInterceptor(
    requestBody: false,
    responseBody: false,
    logPrint: (obj) => log.d(obj.toString()),
  ),);
}

/// Dio INTERACTIVO (pantallas): adjunta JWT + X-Empresa-Id y, ante 401, limpia la
/// sesión (logout). NO lleva X-Sync-Origen. Su 401→logout no cambia (CTT-88/CTT-121).
@riverpod
Dio dioClient(DioClientRef ref) {
  final storage = ref.watch(secureStorageProvider);
  final log = ref.watch(loggerProvider);

  final dio = Dio(opcionesBaseDio());
  // Interceptor de auth: adjunta JWT + X-Empresa-Id.
  dio.interceptors.add(AuthInterceptor(storage));
  // Interceptor de errores: convierte HTTP errors en excepciones tipadas y, ante 401,
  // dispara logout.
  dio.interceptors.add(ErrorInterceptor(
    log,
    alCerrarSesion: () async {
      await storage.limpiarSesion();
      // TODO Fase 1.3: disparar evento de logout en el AuthNotifier de Riverpod.
    },
  ),);
  _agregarLogDebug(dio, log);
  return dio;
}

/// Dio para la COLA de sync (foreground), separado del interactivo (CTT-103 D4):
/// mismas opciones base + AuthInterceptor (JWT/empresa), PERO SIN ErrorInterceptor —
/// su efecto 401→logout no aplica al sync, que PAUSA la cola en vez de desloguear (el
/// ciclo clasifica el 401). Agrega `X-Sync-Origen: cola`, que habilita en el backend
/// la persistencia de rechazos deterministas (R2).
@riverpod
Dio dioSync(DioSyncRef ref) {
  final storage = ref.watch(secureStorageProvider);
  final log = ref.watch(loggerProvider);

  final dio = Dio(opcionesBaseDio());
  dio.options.headers['X-Sync-Origen'] = 'cola';
  dio.interceptors.add(AuthInterceptor(storage));
  // Sin ErrorInterceptor a propósito: el sync no desloguea ante 401.
  _agregarLogDebug(dio, log);
  return dio;
}
