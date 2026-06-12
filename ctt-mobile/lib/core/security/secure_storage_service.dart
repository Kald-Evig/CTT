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

  // ── Logout: limpia TODOS los datos del usuario ────────────────────────────

  /// Elimina token, empresa, usuario y firebase uid.
  /// Llamar siempre en logout — nunca dejar tokens residuales.
  Future<void> limpiarSesion() => _storage.deleteAll();
}
