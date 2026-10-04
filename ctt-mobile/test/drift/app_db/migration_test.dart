// dart format width=80
// ignore_for_file: unused_local_variable, unused_import
import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:ctt_mobile/data/local/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'generated/schema.dart';

import 'generated/schema_v6.dart' as v6;
import 'generated/schema_v7.dart' as v7;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  group('simple database migrations', () {
    // These simple tests verify all possible schema updates with a simple (no
    // data) migration. This is a quick way to ensure that written database
    // migrations properly alter the schema.
    const versions = GeneratedHelper.versions;
    for (final (i, fromVersion) in versions.indexed) {
      group('from $fromVersion', () {
        for (final toVersion in versions.skip(i + 1)) {
          test('to $toVersion', () async {
            final schema = await verifier.schemaAt(fromVersion);
            final db = BaseDatosCTT.conConexion(schema.newConnection());
            await verifier.migrateAndValidate(db, toVersion);
            await db.close();
          });
        }
      });
    }
  });

  // Fixture dorado de integridad de datos (CTT-130 / CTT-103): una base v6 real con
  // varias filas se migra a v7 y se compara fila por fila. Verifica que la migración
  // (ADD COLUMN rechazo_id) NO toca ningún dato existente, preserva `secuencia` y deja
  // `rechazo_id` null en todas.
  test('migración v6→v7 no corrompe datos: filas intactas, secuencia preservada, '
      'rechazo_id null en todas', () async {
    final creado = DateTime.utc(2026, 3, 1, 10);

    // 4 filas, 2 ítems (A: r1/r2, B: r3/r4), estados distintos.
    final oldSyncPendientesData = <v6.SyncPendientesData>[
      v6.SyncPendientesData(
        secuencia: 1, id: 'r1', idempotencyKey: 'idem-r1', empresaId: 'emp-1',
        usuarioId: 'user-1', instalacionId: 'inst-1', tipoEntidad: 'item',
        entidadId: 'item-A', accion: 'cambio_estado_item',
        payload: '{"nuevo_estado":"en_progreso"}', payloadVersion: 1,
        creadoEnDispositivo: creado, estado: 'pendiente',
        acknowledged: false, intentosRed: 0, intentosServidor: 0,
      ),
      v6.SyncPendientesData(
        secuencia: 2, id: 'r2', idempotencyKey: 'idem-r2', empresaId: 'emp-1',
        usuarioId: 'user-1', instalacionId: 'inst-1', tipoEntidad: 'item',
        entidadId: 'item-A', accion: 'cambio_estado_item',
        payload: '{"nuevo_estado":"pendiente_revision"}', payloadVersion: 1,
        creadoEnDispositivo: creado, estado: 'enviando',
        acknowledged: false, intentosRed: 3, intentosServidor: 0,
      ),
      v6.SyncPendientesData(
        secuencia: 3, id: 'r3', idempotencyKey: 'idem-r3', empresaId: 'emp-2',
        usuarioId: 'user-2', instalacionId: 'inst-1', tipoEntidad: 'item',
        entidadId: 'item-B', accion: 'cambio_estado_item',
        payload: '{"nuevo_estado":"terminado"}', payloadVersion: 1,
        creadoEnDispositivo: creado, estado: 'esperando_resolucion',
        motivo: 'conflicto', conflictoId: 'c-77',
        acknowledged: false, intentosRed: 0, intentosServidor: 0,
      ),
      v6.SyncPendientesData(
        secuencia: 4, id: 'r4', idempotencyKey: 'idem-r4', empresaId: 'emp-2',
        usuarioId: 'user-2', instalacionId: 'inst-1', tipoEntidad: 'item',
        entidadId: 'item-B', accion: 'cambio_estado_item',
        payload: '{"nuevo_estado":"en_progreso"}', payloadVersion: 1,
        creadoEnDispositivo: creado, estado: 'sincronizado',
        motivo: 'conflicto_resuelto_cliente',
        acknowledged: true, intentosRed: 0, intentosServidor: 0,
      ),
    ];
    final expectedNewSyncPendientesData = <v7.SyncPendientesData>[
      for (final f in oldSyncPendientesData)
        v7.SyncPendientesData(
          secuencia: f.secuencia, id: f.id, idempotencyKey: f.idempotencyKey,
          empresaId: f.empresaId, usuarioId: f.usuarioId,
          instalacionId: f.instalacionId, tipoEntidad: f.tipoEntidad,
          entidadId: f.entidadId, accion: f.accion, payload: f.payload,
          payloadVersion: f.payloadVersion, versionBase: f.versionBase,
          creadoEnDispositivo: f.creadoEnDispositivo, estado: f.estado,
          motivo: f.motivo, conflictoId: f.conflictoId,
          acknowledged: f.acknowledged, intentosRed: f.intentosRed,
          intentosServidor: f.intentosServidor,
          proximoIntentoEn: f.proximoIntentoEn, ultimoIntentoEn: f.ultimoIntentoEn,
          ultimoErrorCodigo: f.ultimoErrorCodigo, ultimoError: f.ultimoError,
          tomadoPor: f.tomadoPor, tomadoHasta: f.tomadoHasta,
          sincronizadoEn: f.sincronizadoEn, versionResultante: f.versionResultante,
          rechazoId: null, // la nueva columna nace null para toda fila migrada
        ),
    ];

    final cachado = DateTime.utc(2026, 3, 1, 9);
    final oldItemsCacheData = <v6.ItemsCacheData>[
      v6.ItemsCacheData(
        id: 'item-A', proyectoId: 'proy-1', proyectoNombre: 'Obra 1',
        nivelProfundidad: 0, nombre: 'Tarea A', estado: 'en_progreso',
        tieneConflicto: false, updatedAt: cachado, cachadoEn: cachado,
      ),
    ];
    final expectedNewItemsCacheData = <v7.ItemsCacheData>[
      v7.ItemsCacheData(
        id: 'item-A', proyectoId: 'proy-1', proyectoNombre: 'Obra 1',
        nivelProfundidad: 0, nombre: 'Tarea A', estado: 'en_progreso',
        tieneConflicto: false, updatedAt: cachado, cachadoEn: cachado,
      ),
    ];

    final oldUsuarioActivoData = <v6.UsuarioActivoData>[
      v6.UsuarioActivoData(
        id: 'user-1', firebaseUid: 'fb-1', nombreCompleto: 'Luis',
        email: 'luis@a.cl', rolActual: 'trabajador', empresaId: 'emp-1',
        empresaNombre: 'Empresa 1', esSuperAdmin: false,
      ),
    ];
    final expectedNewUsuarioActivoData = <v7.UsuarioActivoData>[
      v7.UsuarioActivoData(
        id: 'user-1', firebaseUid: 'fb-1', nombreCompleto: 'Luis',
        email: 'luis@a.cl', rolActual: 'trabajador', empresaId: 'emp-1',
        empresaNombre: 'Empresa 1', esSuperAdmin: false,
      ),
    ];

    final recon = DateTime.utc(2026, 3, 1, 8);
    final oldSyncReconciliacionData = <v6.SyncReconciliacionData>[
      v6.SyncReconciliacionData(id: 'singleton', ultimaReconciliacion: recon),
    ];
    final expectedNewSyncReconciliacionData = <v7.SyncReconciliacionData>[
      v7.SyncReconciliacionData(id: 'singleton', ultimaReconciliacion: recon),
    ];

    await verifier.testWithDataIntegrity(
      oldVersion: 6,
      newVersion: 7,
      createOld: v6.DatabaseAtV6.new,
      createNew: v7.DatabaseAtV7.new,
      openTestedDatabase: BaseDatosCTT.conConexion,
      createItems: (batch, oldDb) {
        batch.insertAll(oldDb.syncPendientes, oldSyncPendientesData);
        batch.insertAll(oldDb.itemsCache, oldItemsCacheData);
        batch.insertAll(oldDb.usuarioActivo, oldUsuarioActivoData);
        batch.insertAll(oldDb.syncReconciliacion, oldSyncReconciliacionData);
      },
      validateItems: (newDb) async {
        final filas = await newDb.select(newDb.syncPendientes).get();
        expect(filas, expectedNewSyncPendientesData);
        // secuencia preservada en orden y rechazo_id null en TODAS.
        expect(filas.map((f) => f.secuencia).toList(), [1, 2, 3, 4]);
        expect(filas.every((f) => f.rechazoId == null), isTrue);
        expect(await newDb.select(newDb.itemsCache).get(),
            expectedNewItemsCacheData);
        expect(await newDb.select(newDb.usuarioActivo).get(),
            expectedNewUsuarioActivoData);
        expect(await newDb.select(newDb.syncReconciliacion).get(),
            expectedNewSyncReconciliacionData);
      },
    );
  });
}
