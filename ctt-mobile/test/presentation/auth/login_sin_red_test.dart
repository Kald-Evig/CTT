/// login_sin_red_test.dart — CTT-138 commit 6 (CTT-84).
///
/// El login muestra proactivamente "El primer ingreso requiere conexión" cuando no
/// hay red, y no lo muestra cuando sí la hay.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ctt_mobile/core/sync/conectividad_listener.dart';
import 'package:ctt_mobile/presentation/auth/login_screen.dart';

Widget _app({required bool hayRed}) => ProviderScope(
      overrides: [
        hayConexionProvider.overrideWith((ref) async => hayRed),
      ],
      child: const MaterialApp(home: LoginScreen()),
    );

void main() {
  testWidgets('sin red → aviso proactivo "El primer ingreso requiere conexión"',
      (tester) async {
    await tester.pumpWidget(_app(hayRed: false));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('El primer ingreso requiere conexión'),
      findsOneWidget,
    );
  });

  testWidgets('con red → no muestra el aviso', (tester) async {
    await tester.pumpWidget(_app(hayRed: true));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('El primer ingreso requiere conexión'),
      findsNothing,
    );
  });
}
