/// aislamiento_empresa_test.dart — CTT-143 (C1-fix): aislamiento por empresa de las
/// lecturas de ItemsCacheDao / ItemsRepository (opción A, multiempresa).
///
/// Con ítems del MISMO usuario en dos empresas (A y B), se recorren TODAS las lecturas:
///   - LISTADO (partición por empresa): observarAsignadosConOverlay → SOLO la empresa activa.
///   - POR ID (detalle): obtenerPorId / observarPorIdConOverlay / ItemsRepository.obtenerDetalle
///     NO filtran por empresa a propósito — se abren por un id ya conocido y único
///     (CTT-143 §6.1), no son particiones multiempresa.
///
/// obtenerMisItems de ItemsRepository ya NO devuelve una lectura (es pull-only, Future<void>);
/// el aislamiento de su RETIRO está en ctt149_retiro_pull_test.dart (§6c).
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ctt_mobile/data/local/database.dart';

const _user = 'user-1';

void main() {
  late BaseDatosCTT db;
  setUp(() => db = BaseDatosCTT.conConexion(NativeDatabase.memory()));
  tearDown(() => db.close());

  // Mismo usuario, dos empresas. itemA ∈ emp-A, itemB ∈ emp-B.
  Future<void> sembrar() async {
    for (final (id, empresa) in [('itemA', 'emp-A'), ('itemB', 'emp-B')]) {
      await db.into(db.itemsCacheTable).insert(ItemsCacheTableCompanion.insert(
            id: id,
            proyectoId: 'proy-1',
            nombre: 'Item $id',
            asignadoA: const Value(_user),
            empresaId: Value(empresa),
            estadoServidor: 'abierto',
            updatedAt: DateTime.utc(2026, 5, 1),
            cachadoEn: DateTime.utc(2026, 5, 1),
          ));
    }
  }

  test('LISTADO observarAsignadosConOverlay: devuelve SOLO la empresa activa', () async {
    await sembrar();
    final listaA =
        await db.itemsCacheDao.observarAsignadosConOverlay(_user, 'emp-A').first;
    expect(listaA.map((e) => e.id).toSet(), {'itemA'},
        reason: 'empresa activa A → solo itemA');

    final listaB =
        await db.itemsCacheDao.observarAsignadosConOverlay(_user, 'emp-B').first;
    expect(listaB.map((e) => e.id).toSet(), {'itemB'},
        reason: 'empresa activa B → solo itemB');
  });

  // Lecturas POR ID (detalle): NO filtran por empresa a propósito (id conocido y único).
  // Se documenta que devuelven el ítem pedido aunque sea de otra empresa.
  test('POR ID: obtenerPorId / observarPorIdConOverlay / obtenerDetalle no filtran empresa '
      '(detalle por id conocido — CTT-143 §6.1)', () async {
    await sembrar();
    // items_cache_dao.dart: obtenerPorId (por id), observarPorIdConOverlay (por id).
    expect((await db.itemsCacheDao.obtenerPorId('itemB'))!.empresaId, 'emp-B');
    final porId = await db.itemsCacheDao.observarPorIdConOverlay('itemB').first;
    expect(porId!.empresaId, 'emp-B');
    // items_repository.dart:74 obtenerDetalle → cacheDao.obtenerPorId (por id).
    // (No se instancia el repo acá: delega 1:1 en obtenerPorId, ya cubierto arriba.)
  });
}
