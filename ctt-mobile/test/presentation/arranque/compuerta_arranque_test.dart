/// compuerta_arranque_test.dart — CTT-130 fase 4.
///
/// T6: si la compuerta de arranque falla, la app muestra la pantalla de recuperación
/// — NUNCA el login (el router enmascaraba el fallo con valueOrNull).
/// + contenido de la pantalla: conteo de cambios + aviso de no desinstalar, sin
/// botón de exportar (decisión: el trabajador no maneja archivos; rescate = fase 4b).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ctt_mobile/app.dart';
import 'package:ctt_mobile/presentation/arranque/arranque_provider.dart';
import 'package:ctt_mobile/presentation/arranque/pantalla_recuperacion.dart';

void main() {
  testWidgets('T6 — arranque falla → pantalla de recuperación, NO login',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          arranqueProvider.overrideWith(
            (ref) => Future<void>.error(StateError('base no pudo abrir')),
          ),
          conteoPendientesRescateProvider.overrideWith((ref) async => 0),
        ],
        child: const AppCTT(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PantallaRecuperacion), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    // NO el login.
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('Iniciar sesión'), findsNothing);
  });

  testWidgets('pantalla de recuperación: muestra el conteo y el aviso de no '
      'desinstalar; NO hay botón de exportar', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conteoPendientesRescateProvider.overrideWith((ref) async => 3),
        ],
        child: const MaterialApp(
          home: PantallaRecuperacion(error: 'x'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Conteo de cambios en juego.
    expect(find.textContaining('3 cambios'), findsOneWidget);
    // Aviso de NO desinstalar / borrar datos.
    expect(find.textContaining('NO desinstales'), findsOneWidget);
    // Reintentar sí; exportar NO.
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.textContaining('Exportar'), findsNothing);
  });
}
