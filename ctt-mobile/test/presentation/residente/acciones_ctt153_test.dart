/// acciones_ctt153_test.dart — CTT-153: el Residente ya no ve "Marcar problema" en
/// abierto (ABIERTO→PROBLEMA no existe en el contrato). "Asignar a trabajador" sigue
/// (no es una transición).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:ctt_mobile/data/repositories/residente_repository.dart';
import 'package:ctt_mobile/domain/entities/residente_models.dart';
import 'package:ctt_mobile/presentation/residente/detalle_item_residente_screen.dart';

class _FakeResidenteRepo extends Mock implements ResidenteRepository {}

ItemResidente _item(String estado) => ItemResidente(
      id: 'it-1',
      proyectoId: 'p1',
      nivelProfundidad: 0,
      nombre: 'Tarea',
      estado: estado,
      version: 1,
    );

void main() {
  testWidgets('Residente en abierto: no se ve "Marcar problema"', (tester) async {
    final repo = _FakeResidenteRepo();
    when(() => repo.obtenerItem('it-1'))
        .thenAnswer((_) async => _item('abierto'));
    when(() => repo.listarComentarios('it-1')).thenAnswer((_) async => []);
    when(() => repo.listarEvidencias('it-1')).thenAnswer((_) async => []);
    when(() => repo.listarHistorial('it-1')).thenAnswer((_) async => []);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [residenteRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(
          home: DetalleItemResidenteScreen(itemId: 'it-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Marcar problema'), findsNothing);
    // "Asignar a trabajador" NO es transición: sigue disponible.
    expect(find.text('Asignar a trabajador'), findsOneWidget);
  });
}
