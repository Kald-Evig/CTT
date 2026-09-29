/// arranque_provider.dart — CTT-130 fase 4.
///
/// Compuerta de arranque: corre la pre-apertura con sqlite3 crudo ANTES de que la
/// app llegue al router, y fuerza la apertura de Drift (que migra si toca). Si algo
/// falla, el provider queda en error y [AppCTT] muestra la pantalla de recuperación
/// — NUNCA el login (que hoy enmascara el fallo con valueOrNull).
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:ctt_mobile/data/local/apertura_base.dart';
import 'package:ctt_mobile/data/local/database.dart';

part 'arranque_provider.g.dart';

/// Ejecuta la secuencia de arranque de la base en el isolate de UI:
///   1. pre-apertura cruda: decide abrir / lanzar (base más nueva) / respaldar+migrar;
///   2. fuerza la apertura de Drift con una query trivial, que dispara la migración
///      atómica (migrarAtomico) si `user_version < schemaVersion`.
/// Lanza si la pre-apertura o la migración fallan: la UI lo captura.
@riverpod
Future<void> arranque(ArranqueRef ref) async {
  final path = await rutaBase();
  await preAbrir(
    path: path,
    schemaVersion: kSchemaVersionApp,
    esIsolateUI: true,
  );
  // Fuerza la apertura de Drift (y la migración por onUpgrade si corresponde).
  final db = ref.read(baseDatosCTTProvider);
  await db.customSelect('SELECT 1').get();
}

/// Cantidad de cambios sin sincronizar, leída con SQL crudo (sin Drift) para la
/// pantalla de recuperación: se muestra aunque Drift no pueda abrir la base.
@riverpod
Future<int> conteoPendientesRescate(ConteoPendientesRescateRef ref) async {
  final path = await rutaBase();
  return contarPendientesCrudo(path);
}
