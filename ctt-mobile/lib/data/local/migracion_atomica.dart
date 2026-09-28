/// migracion_atomica.dart — CTT-130 fase 4.
///
/// Migración atómica DENTRO de Drift: los pasos y el `PRAGMA user_version` van en
/// un único `transaction()`. Si un paso falla, se revierten los pasos Y la versión
/// — la app nunca queda a medio migrar (el hallazgo de fase 1). La escritura de
/// user_version de Drift (engines.dart:517, después de onUpgrade) repite el mismo
/// número: inocua.
///
/// Conserva el flujo oficial de Drift (stepByStep): NO se migra con SQL a mano
/// fuera de Drift.
library;

import 'package:drift/drift.dart';

/// Un paso de migración. En producción son los pasos generados por `stepByStep`;
/// en los tests se inyectan pasos sintéticos.
typedef PasoMigracion = Future<void> Function(GeneratedDatabase db);

/// Lee el `PRAGMA user_version` de la conexión actual (dentro o fuera de una
/// transacción, según el contexto de Drift).
Future<int> leerUserVersion(GeneratedDatabase db) async {
  final row = await db.customSelect('PRAGMA user_version').getSingle();
  return row.read<int>('user_version');
}

/// Migra de [from] a [to] ejecutando [pasos] y fijando `user_version = to`, todo
/// en una sola transacción:
///   a. relee `user_version`; si ya es >= [to], no hace nada (otro proceso migró);
///   b. ejecuta los pasos;
///   c. escribe `PRAGMA user_version = to`.
/// Si cualquier paso lanza, la transacción revierte pasos y versión.
Future<void> migrarAtomico(
  GeneratedDatabase db, {
  required int from,
  required int to,
  required List<PasoMigracion> pasos,
}) {
  return db.transaction(() async {
    // Re-chequeo dentro de la transacción: si otro isolate/proceso ya migró, no
    // repetir los pasos (idempotencia ante carrera).
    final actual = await leerUserVersion(db);
    if (actual >= to) return;

    for (final paso in pasos) {
      await paso(db);
    }

    // Misma transacción que los pasos: si algo falló arriba, esto no corre y la
    // versión no avanza. `user_version` es transaccional en SQLite (vive en el
    // header, se revierte con el ROLLBACK).
    await db.customStatement('PRAGMA user_version = $to');
  });
}
