/// device_id_service.dart — Identificador único y persistente del dispositivo.
///
/// Se genera una sola vez en la primera ejecución y se persiste en SecureStorage.
/// Usado por la cola de sync para identificar el origen de cada cambio offline.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';
import 'package:ctt_mobile/core/network/dio_client.dart';
import 'package:ctt_mobile/core/security/secure_storage_service.dart';

part 'device_id_service.g.dart';

@riverpod
DeviceIdService deviceIdService(DeviceIdServiceRef ref) =>
    DeviceIdService(ref.watch(secureStorageProvider));

class DeviceIdService {
  DeviceIdService(this._storage);

  final SecureStorageService _storage;
  static const _clave = '_ctt_device_id';

  Future<String> obtener() async {
    final existente = await _storage.leerClave(_clave);
    if (existente != null) return existente;
    final nuevo = const Uuid().v4();
    await _storage.escribirClave(_clave, nuevo);
    return nuevo;
  }
}
