/// apertura_base.dart — CTT-130 fase 4.
///
/// Pre-apertura con `sqlite3` crudo, ANTES de instanciar Drift, compartida por los
/// dos isolates (UI y headless de WorkManager). Lee `user_version` sin abrir Drift
/// y decide qué hacer. Nunca borra ni recrea la base (sin fallback destructivo).
///
/// La migración en sí la hace Drift (onUpgrade → migrarAtomico); acá solo se
/// pre-chequea la versión, se respalda antes de migrar (solo en UI) y se ofrece
/// exportar la cola leyéndola con SQL crudo, sin depender del esquema de Drift.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

/// Qué debe hacer el llamador tras la pre-apertura.
enum AccionApertura {
  /// Abrir Drift normal (versión al día, base nueva, o —en UI— lista para migrar).
  abrir,

  /// No abrir: otro isolate (el de UI) debe migrar primero. Reintentar luego.
  reintentar,
}

/// La base es de una versión MÁS NUEVA que la app (downgrade): no se abre.
class BaseMasNuevaException implements Exception {
  const BaseMasNuevaException(this.versionBase, this.versionApp);
  final int versionBase;
  final int versionApp;
  @override
  String toString() =>
      'BaseMasNuevaException: la base está en v$versionBase y la app soporta '
      'hasta v$versionApp. Actualizá la app.';
}

/// El respaldo previo a migrar no pasó `quick_check`: se aborta antes de tocar la
/// base real (sin fallback destructivo).
class RespaldoInvalidoException implements Exception {
  const RespaldoInvalidoException(this.detalle);
  final String detalle;
  @override
  String toString() => 'RespaldoInvalidoException: $detalle';
}

/// Ruta del archivo de la base (misma en ambos isolates).
Future<String> rutaBase() async {
  final dir = await getApplicationDocumentsDirectory();
  return p.join(dir.path, 'ctt_local.db');
}

/// Pre-apertura: lee `user_version` con sqlite3 crudo y decide.
///
/// - `== schemaVersion` o base nueva (0) → [AccionApertura.abrir].
/// - `> schemaVersion` → [BaseMasNuevaException].
/// - `< schemaVersion`:
///     · UI: `wal_checkpoint(TRUNCATE)`, respaldo con `VACUUM INTO` (nombre con la
///       versión), `quick_check` sobre el respaldo, y recién [AccionApertura.abrir]
///       (Drift migrará). Si el respaldo falla → [RespaldoInvalidoException].
///     · headless: [AccionApertura.reintentar] (NO migra; evita dos transacciones
///       de migración compitiendo). Solo migra el isolate de UI.
Future<AccionApertura> preAbrir({
  required String path,
  required int schemaVersion,
  required bool esIsolateUI,
}) async {
  final db = raw.sqlite3.open(path);
  try {
    final uv = db.userVersion;

    // Base nueva (0): Drift la crea con onCreate en la versión actual.
    if (uv == 0 || uv == schemaVersion) return AccionApertura.abrir;

    if (uv > schemaVersion) {
      throw BaseMasNuevaException(uv, schemaVersion);
    }

    // uv < schemaVersion → migración pendiente.
    if (!esIsolateUI) return AccionApertura.reintentar;

    // UI: consolidar el WAL, respaldar y verificar el respaldo antes de migrar.
    db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    final rutaRespaldo = '$path.bak_v$uv';
    final archivoRespaldo = File(rutaRespaldo);
    if (archivoRespaldo.existsSync()) archivoRespaldo.deleteSync();
    // VACUUM INTO escribe una copia limpia y compacta del contenido actual.
    db.execute("VACUUM INTO '${rutaRespaldo.replaceAll("'", "''")}'");

    final respaldo = raw.sqlite3.open(rutaRespaldo);
    try {
      final qc = respaldo.select('PRAGMA quick_check');
      final ok = qc.isNotEmpty && qc.first.values.first == 'ok';
      if (!ok) {
        throw RespaldoInvalidoException(
          'quick_check del respaldo devolvió ${qc.isEmpty ? "vacío" : qc.first.values.first}',
        );
      }
    } finally {
      respaldo.dispose();
    }

    return AccionApertura.abrir;
  } finally {
    db.dispose();
  }
}

/// Exporta las filas de `sync_pendientes` a JSON leyendo con SQL crudo (sin
/// depender del esquema de Drift). Sirve para la pantalla de recuperación: el
/// trabajador puede sacar su trabajo sin subir aunque Drift no pueda abrir.
/// [path] puede ser la base real o un respaldo.
String exportarColaPendienteJson(String path) {
  final db = raw.sqlite3.open(path);
  try {
    final existe = db
        .select("SELECT name FROM sqlite_master WHERE type='table' "
            "AND name='sync_pendientes'")
        .isNotEmpty;
    final filas = <Map<String, Object?>>[];
    if (existe) {
      final rs = db.select('SELECT * FROM sync_pendientes');
      for (final row in rs) {
        filas.add({for (final c in rs.columnNames) c: row[c]});
      }
    }
    return jsonEncode({'tabla': 'sync_pendientes', 'filas': filas});
  } finally {
    db.dispose();
  }
}
