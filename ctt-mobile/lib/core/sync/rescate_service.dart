/// rescate_service.dart — CTT-130 fase 4b: rescate automático de la cola al servidor.
///
/// Cuando la app no pudo abrir la base, la pantalla de recuperación llama a este
/// servicio: lee con SQL crudo las filas NO terminales (sin Drift) y las envía a
/// POST /sync/rescate, que las guarda en cuarentena. El trabajador no toca nada.
///
/// NO escribe en la base rota. El servidor es idempotente: reenviar es seguro.
library;

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:ctt_mobile/core/config/environment.dart';
import 'package:ctt_mobile/core/device/device_id_service.dart';
import 'package:ctt_mobile/core/network/dio_client.dart' show secureStorageProvider;
import 'package:ctt_mobile/core/security/secure_storage_service.dart';
import 'package:ctt_mobile/data/local/apertura_base.dart';

part 'rescate_service.g.dart';

/// Desenlace de un intento de rescate.
enum ResultadoRescate {
  enviado, // el servidor recibió las filas
  sinRed, // error de red: reintentar (con backoff) mientras la pantalla esté abierta
  sinSesion, // no hay sesión para autenticar: NO reintentar en loop; avisar
  nadaQueEnviar, // la cola no tiene filas no terminales
}

/// Fuente del token para el rescate. Inyectable para testear sin Firebase real.
abstract class ProveedorTokenRescate {
  /// Token válido, o null si no hay sesión (no se puede rescatar).
  Future<String?> obtenerToken();
}

/// Mock/actual: el token vive en SecureStorage (en mock es el firebase_uid, no vence).
class TokenRescateSecureStorage implements ProveedorTokenRescate {
  TokenRescateSecureStorage(this._storage);
  final SecureStorageService _storage;
  @override
  Future<String?> obtenerToken() => _storage.obtenerToken();
}

/// Firebase real (A3): token fresco vía getIdToken(true), sin router ni base. Si no
/// hay sesión de Firebase (currentUser null) devuelve null → la pantalla avisa y NO
/// reintenta en loop. Se cablea cuando AUTH_MODE=firebase (hoy la app es mock).
class TokenRescateFirebase implements ProveedorTokenRescate {
  @override
  Future<String?> obtenerToken() async {
    final user = fb.FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return user.getIdToken(true);
  }
}

class RescateService {
  RescateService({
    required this.dio,
    required this.proveedorToken,
    required this.deviceIdService,
  });

  final Dio dio;
  final ProveedorTokenRescate proveedorToken;
  final DeviceIdService deviceIdService;

  /// Lee las filas no terminales de la cola y las envía a /sync/rescate.
  Future<ResultadoRescate> rescatar() async {
    final token = await proveedorToken.obtenerToken();
    if (token == null) return ResultadoRescate.sinSesion;

    final path = await rutaBase();
    final filas = leerFilasNoTerminalesCrudo(path);
    if (filas.isEmpty) return ResultadoRescate.nadaQueEnviar;

    final instalacionId = await deviceIdService.obtener();
    try {
      await dio.post<void>(
        '/sync/rescate',
        data: {'instalacion_id': instalacionId, 'filas': filas},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return ResultadoRescate.enviado;
    } on DioException catch (e) {
      if (_esErrorDeRed(e)) return ResultadoRescate.sinRed;
      rethrow; // 4xx/5xx: no es falta de red; que suba
    }
  }

  bool _esErrorDeRed(DioException e) =>
      e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.receiveTimeout ||
      e.type == DioExceptionType.sendTimeout ||
      e.type == DioExceptionType.connectionError;
}

/// Fuente del token. Default: SecureStorage (AUTH_MODE=mock actual). Cuando el
/// backend pase a AUTH_MODE=firebase, cambiar a [TokenRescateFirebase].
@riverpod
ProveedorTokenRescate proveedorTokenRescate(ProveedorTokenRescateRef ref) =>
    TokenRescateSecureStorage(ref.watch(secureStorageProvider));

/// Dio dedicado al rescate: SIN el AuthInterceptor (que pisaría el Authorization con
/// el token de SecureStorage). El rescate setea el header con el token del proveedor.
@riverpod
Dio dioRescate(DioRescateRef ref) => Dio(
      BaseOptions(
        baseUrl: Entorno.urlBaseApi,
        connectTimeout: Entorno.timeoutConexion,
        receiveTimeout: Entorno.timeoutRecepcion,
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

@riverpod
RescateService rescateService(RescateServiceRef ref) => RescateService(
      dio: ref.watch(dioRescateProvider),
      proveedorToken: ref.watch(proveedorTokenRescateProvider),
      deviceIdService: ref.watch(deviceIdServiceProvider),
    );
