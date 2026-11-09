/// defensa_sesion_io.dart — CTT-147. Implementaciones de sistema de archivos para la
/// defensa ([DefensaSesion]). Separadas del controlador puro: acá vive el dart:io, los
/// tests del controlador usan fakes y no tocan esto.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:ctt_mobile/core/security/defensa_sesion.dart';

/// Marcas como archivos en el directorio de soporte de la app. Síncrono (existsSync/
/// createSync/deleteSync): se lee en `main()` antes de `Firebase.initializeApp` y sin
/// SecureStorage. El directorio de soporte es privado de la app y, con las reglas nuevas
/// de CTT-147, no se respalda.
class MarcasDefensaArchivo implements MarcasDefensa {
  MarcasDefensaArchivo(this._dir);

  final Directory _dir;

  File get _sanar => File(p.join(_dir.path, 'ctt_defensa_sanar'));
  File get _recienSanado => File(p.join(_dir.path, 'ctt_defensa_recien_sanado'));

  @override
  bool get haySanar => _sanar.existsSync();

  @override
  bool get hayRecienSanado => _recienSanado.existsSync();

  @override
  void marcarSanar() => _crear(_sanar);

  @override
  void quitarSanar() => _borrar(_sanar);

  @override
  void marcarRecienSanado() => _crear(_recienSanado);

  @override
  void quitarRecienSanado() => _borrar(_recienSanado);

  void _crear(File f) {
    if (!f.existsSync()) f.createSync(recursive: true);
  }

  void _borrar(File f) {
    if (f.existsSync()) f.deleteSync();
  }
}

/// Acceso real a `shared_prefs/`. La ruta se deriva del directorio de la app (hermano de
/// `app_flutter/`), NO se escribe a mano.
class ArchivosSharedPrefsIo implements ArchivosSharedPrefs {
  ArchivosSharedPrefsIo(this._dir);

  final Directory _dir;

  @override
  List<String> nombres() => _dir.existsSync()
      ? _dir
          .listSync()
          .whereType<File>()
          .map((f) => p.basename(f.path))
          .toList()
      : const [];

  @override
  void borrar(String nombre) {
    final f = File(p.join(_dir.path, nombre));
    if (f.existsSync()) f.deleteSync();
  }
}

/// Bundle resuelto de la defensa (controlador + sus dependencias IO).
class DefensaSesionIo {
  DefensaSesionIo({
    required this.defensa,
    required this.archivos,
  });

  final DefensaSesion defensa;
  final ArchivosSharedPrefs archivos;
}

/// Resuelve los directorios (soporte para las marcas; `shared_prefs/` para la fase 2) y
/// arma el controlador. Las marcas van al directorio de soporte; `shared_prefs/` es hermano
/// de `app_flutter/` (= getApplicationDocumentsDirectory), así que se deriva de su padre.
Future<DefensaSesionIo> crearDefensaSesionIo() async {
  final soporte = await getApplicationSupportDirectory();
  final docs = await getApplicationDocumentsDirectory(); // .../app_flutter
  final sharedPrefs = Directory(p.join(docs.parent.path, 'shared_prefs'));
  return DefensaSesionIo(
    defensa: DefensaSesion(MarcasDefensaArchivo(soporte)),
    archivos: ArchivosSharedPrefsIo(sharedPrefs),
  );
}
