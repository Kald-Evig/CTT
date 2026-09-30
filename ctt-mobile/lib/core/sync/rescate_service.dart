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
  enviado, // el servidor recibió el envío (puede haber rechazos parciales: ver sinRescatar)
  sinRed, // error de red: reintentar (con backoff) mientras la pantalla esté abierta
  errorServidor, // 5xx/429: falla transitoria del servidor → reintentar igual que sinRed (CTT-103)
  errorCliente, // 4xx u otro no reintentable: NO reintentar, pero avisar (nunca silencio)
  sinSesion, // no hay sesión para autenticar: NO reintentar en loop; avisar
  nadaQueEnviar, // la cola no tiene filas no terminales
}

/// Resultado de un rescate: el desenlace más los conteos que devolvió el servidor.
/// [sinRescatar] son filas que el servidor NO aceptó (p.ej. empresa ajena): siguen
/// guardadas en el teléfono, hay que avisarlo (rescate parcial).
class RescateResultado {
  const RescateResultado(
    this.estado, {
    this.enviadas = 0,
    this.sinRescatar = 0,
  });

  final ResultadoRescate estado;
  final int enviadas;
  final int sinRescatar;
}

/// Fuente del token para el rescate. Inyectable para testear sin Firebase real.
abstract class ProveedorTokenRescate {
  /// Token válido, o null si no hay sesión (no se puede rescatar).
  Future<String?> obtenerToken();
}

/// Modo mock (AUTH_MODE=mock): el token vive en SecureStorage (es el firebase_uid).
class TokenRescateSecureStorage implements ProveedorTokenRescate {
  TokenRescateSecureStorage(this._storage);
  final SecureStorageService _storage;
  @override
  Future<String?> obtenerToken() => _storage.obtenerToken();
}

/// Modo firebase (AUTH_MODE=firebase): token fresco vía getIdToken(true), sin router
/// ni base. Si no hay sesión de Firebase (currentUser null) devuelve null → la
/// pantalla avisa y NO reintenta en loop.
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
  Future<RescateResultado> rescatar() async {
    final token = await proveedorToken.obtenerToken();
    if (token == null) return const RescateResultado(ResultadoRescate.sinSesion);

    final path = await rutaBase();
    final filas = leerFilasNoTerminalesCrudo(path);
    if (filas.isEmpty) {
      return const RescateResultado(ResultadoRescate.nadaQueEnviar);
    }

    final instalacionId = await deviceIdService.obtener();
    try {
      final resp = await dio.post<Map<String, dynamic>>(
        '/sync/rescate',
        data: {'instalacion_id': instalacionId, 'filas': filas},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = resp.data ?? const {};
      // Rescate parcial: el servidor rechaza las filas de empresa ajena y las cuenta.
      final sinRescatar = (data['rechazadas_tenant'] as int?) ?? 0;
      final enviadas = ((data['aceptadas'] as int?) ?? 0) +
          ((data['ya_aplicadas'] as int?) ?? 0) +
          ((data['duplicadas'] as int?) ?? 0);
      return RescateResultado(
        ResultadoRescate.enviado,
        enviadas: enviadas,
        sinRescatar: sinRescatar,
      );
    } on DioException catch (e) {
      if (_esErrorDeRed(e)) {
        return const RescateResultado(ResultadoRescate.sinRed);
      }
      // 5xx/429 son fallas transitorias del servidor (el mismo caso que CTT-103
      // marca en la cola): se reintentan igual que la falta de red.
      final status = e.response?.statusCode ?? 0;
      if (status == 429 || status >= 500) {
        return const RescateResultado(ResultadoRescate.errorServidor);
      }
      // 4xx: no reintentar, pero avisar que no se pudo enviar (nunca silencio).
      return const RescateResultado(ResultadoRescate.errorCliente);
    }
  }

  bool _esErrorDeRed(DioException e) =>
      e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.receiveTimeout ||
      e.type == DioExceptionType.sendTimeout ||
      e.type == DioExceptionType.connectionError;
}

/// Modo de autenticación configurado (Entorno / AUTH_MODE). Provider para poder
/// overridearlo en tests sin depender de un dart-define.
@riverpod
String modoAuth(ModoAuthRef ref) => Entorno.modoAuth;

/// Fuente del token, elegida por el modo de autenticación configurado (no por un
/// default que alguien tenga que acordarse de cambiar): mock → SecureStorage;
/// firebase → getIdToken(true).
@riverpod
ProveedorTokenRescate proveedorTokenRescate(ProveedorTokenRescateRef ref) =>
    ref.watch(modoAuthProvider) == 'firebase'
        ? TokenRescateFirebase()
        : TokenRescateSecureStorage(ref.watch(secureStorageProvider));

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
