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
import 'package:ctt_mobile/core/network/interceptors/ultimo_contacto_interceptor.dart';
import 'package:ctt_mobile/core/security/secure_storage_service.dart';

part 'dio_client.g.dart';

@riverpod
SecureStorageService secureStorage(SecureStorageRef ref) =>
    SecureStorageService();

/// Logger de la app. Fuente ÚNICA de la config (nivel por release + printer): la usan
/// [logger] (foreground, vía Riverpod) y el isolate headless de WorkManager, que no
/// tiene ProviderScope (CTT-138 c7).
Logger crearLogger() => Logger(
      level: Entorno.esRelease ? Level.off : Level.debug,
      printer: PrettyPrinter(
        methodCount: 0,
        dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
      ),
    );

@riverpod
Logger logger(LoggerRef ref) => crearLogger();

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
  // CTT-138: registra el último contacto 2xx (ventana offline).
  dio.interceptors.add(UltimoContactoInterceptor(storage));
  _agregarLogDebug(dio, log);
  return dio;
}

/// Config ÚNICA del Dio de la COLA de sync (CTT-103 D4 + CTT-138 c7): opciones base +
/// `X-Sync-Origen: cola` + `UltimoContactoInterceptor` (renueva la ventana offline ante
/// cualquier 2xx) + log de debug. SIN ErrorInterceptor: el 401 lo PAUSA el ciclo, no
/// desloguea. La AUTENTICACIÓN se agrega aparte: [dioSync] (foreground) con
/// `AuthInterceptor`; el isolate headless de WorkManager setea Authorization/
/// X-Empresa-Id a mano. Así el 2xx de una corrida en background también actualiza
/// `ultimo_contacto_servidor`.
Dio crearDioSync(SecureStorageService storage, Logger log) {
  final dio = Dio(opcionesBaseDio());
  dio.options.headers['X-Sync-Origen'] = 'cola';
  dio.interceptors.add(UltimoContactoInterceptor(storage));
  _agregarLogDebug(dio, log);
  return dio;
}

/// Dio para la COLA de sync (foreground), separado del interactivo (CTT-103 D4).
/// Usa [crearDioSync] y le agrega `AuthInterceptor` (JWT/empresa vía Riverpod).
@riverpod
Dio dioSync(DioSyncRef ref) {
  final storage = ref.watch(secureStorageProvider);
  final dio = crearDioSync(storage, ref.watch(loggerProvider));
  dio.interceptors.add(AuthInterceptor(storage));
  return dio;
}
