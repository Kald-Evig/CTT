/// secure_storage_service.dart — Servicio de almacenamiento seguro.
///
/// Usa flutter_secure_storage con encryptedSharedPreferences en Android
/// (cifrado AES a través del Keystore del sistema).
/// NUNCA almacenar RUT ni datos personales aquí — solo credenciales de sesión.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  SecureStorageService() : _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  final FlutterSecureStorage _storage;

  static const _claveToken = '_ctt_jwt';
  static const _claveEmpresaId = '_ctt_empresa_id';
  static const _claveUsuarioId = '_ctt_usuario_id';
  static const _claveFirebaseUid = '_ctt_firebase_uid';
  static const _claveUltimoContacto = '_ctt_ultimo_contacto';

  // ── Token JWT ─────────────────────────────────────────────────────────────

  Future<void> guardarToken(String token) =>
      _storage.write(key: _claveToken, value: token);

  Future<String?> obtenerToken() => _storage.read(key: _claveToken);

  Future<void> eliminarToken() => _storage.delete(key: _claveToken);

  // ── Empresa activa (multi-empresa: header X-Empresa-Id) ───────────────────

  Future<void> guardarEmpresaId(String empresaId) =>
      _storage.write(key: _claveEmpresaId, value: empresaId);

  Future<String?> obtenerEmpresaId() => _storage.read(key: _claveEmpresaId);

  // ── Identificadores de sesión ─────────────────────────────────────────────

  Future<void> guardarUsuarioId(String usuarioId) =>
      _storage.write(key: _claveUsuarioId, value: usuarioId);

  Future<String?> obtenerUsuarioId() => _storage.read(key: _claveUsuarioId);

  Future<void> guardarFirebaseUid(String uid) =>
      _storage.write(key: _claveFirebaseUid, value: uid);

  Future<String?> obtenerFirebaseUid() => _storage.read(key: _claveFirebaseUid);

  // ── Claves genéricas (para DeviceIdService y usos internos) ─────────────────

  Future<String?> leerClave(String clave) => _storage.read(key: clave);

  Future<void> escribirClave(String clave, String valor) =>
      _storage.write(key: clave, value: valor);

  // ── Último contacto con el servidor (CTT-138: ventana offline) ─────────────

  /// Guarda el instante (UTC, ISO-8601) de la última respuesta 2xx autenticada.
  /// Lo escribe `UltimoContactoInterceptor` en cualquier 2xx del Dio interactivo o
  /// de sync; ambos isolates comparten esta clave.
  Future<void> guardarUltimoContacto(DateTime cuando) => _storage.write(
        key: _claveUltimoContacto,
        value: cuando.toUtc().toIso8601String(),
      );

  /// Último contacto con el servidor (UTC), o null si nunca hubo.
  Future<DateTime?> obtenerUltimoContacto() async {
    final raw = await _storage.read(key: _claveUltimoContacto);
    return raw == null ? null : DateTime.tryParse(raw)?.toUtc();
  }

  // ── Logout: limpia TODOS los datos del usuario ────────────────────────────

  /// Elimina token, empresa, usuario y firebase uid.
  /// Llamar siempre en logout — nunca dejar tokens residuales.
  Future<void> limpiarSesion() => _storage.deleteAll();
}
