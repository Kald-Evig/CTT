/// compuerta_arranque_test.dart — CTT-130 fase 4 / 4b.
///
/// - T6: arranque falla → pantalla de recuperación, NUNCA login.
/// - Contenido: conteo + aviso de no desinstalar, sin botón exportar.
/// - Rescate 4b: se dispara al entrar; sin sesión avisa y NO reintenta en loop;
///   sin red reintenta con backoff.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:ctt_mobile/app.dart';
import 'package:ctt_mobile/core/sync/rescate_service.dart';
import 'package:ctt_mobile/presentation/arranque/arranque_provider.dart';
import 'package:ctt_mobile/presentation/arranque/pantalla_recuperacion.dart';

class _MockRescate extends Mock implements RescateService {}

void main() {
  // Override del servicio de rescate para que la pantalla no toque red/SecureStorage.
  Override rescateOverride(_MockRescate m) =>
      rescateServiceProvider.overrideWithValue(m);

  testWidgets('T6 — arranque falla → pantalla de recuperación, NO login',
      (tester) async {
    final rescate = _MockRescate();
    when(rescate.rescatar).thenAnswer((_) async => ResultadoRescate.sinSesion);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          arranqueProvider.overrideWith(
            (ref) => Future<void>.error(StateError('base no pudo abrir')),
          ),
          conteoPendientesRescateProvider.overrideWith((ref) async => 0),
          rescateOverride(rescate),
        ],
        child: const AppCTT(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PantallaRecuperacion), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('Iniciar sesión'), findsNothing);
  });

  testWidgets('contenido: conteo + aviso de no desinstalar; sin botón exportar',
      (tester) async {
    final rescate = _MockRescate();
    when(rescate.rescatar).thenAnswer((_) async => ResultadoRescate.sinSesion);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conteoPendientesRescateProvider.overrideWith((ref) async => 3),
          rescateOverride(rescate),
        ],
        child: const MaterialApp(home: PantallaRecuperacion(error: 'x')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('3 cambios'), findsOneWidget);
    expect(find.textContaining('NO desinstales'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.textContaining('Exportar'), findsNothing);
  });

  testWidgets('rescate se dispara al entrar; sin sesión avisa y NO reintenta en loop',
      (tester) async {
    final rescate = _MockRescate();
    when(rescate.rescatar).thenAnswer((_) async => ResultadoRescate.sinSesion);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conteoPendientesRescateProvider.overrideWith((ref) async => 1),
          rescateOverride(rescate),
        ],
        child: const MaterialApp(home: PantallaRecuperacion(error: 'x')),
      ),
    );
    await tester.pumpAndSettle();

    // Se disparó al entrar.
    verify(rescate.rescatar).called(1);
    expect(
      find.textContaining('siguen guardados en el teléfono'),
      findsOneWidget,
    );

    // Pasado el backoff, NO reintenta (sin loop).
    await tester.pump(const Duration(seconds: 20));
    verifyNever(rescate.rescatar);
  });

  testWidgets('sin red reintenta con backoff; luego confirma el envío',
      (tester) async {
    final rescate = _MockRescate();
    var n = 0;
    when(rescate.rescatar).thenAnswer((_) async {
      n++;
      return n == 1 ? ResultadoRescate.sinRed : ResultadoRescate.enviado;
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conteoPendientesRescateProvider.overrideWith((ref) async => 1),
          rescateOverride(rescate),
        ],
        child: const MaterialApp(home: PantallaRecuperacion(error: 'x')),
      ),
    );
    await tester.pumpAndSettle();

    // 1er intento: sin red → mensaje de "sin señal".
    expect(find.textContaining('Sin señal'), findsOneWidget);

    // Pasado el backoff, reintenta y confirma el envío.
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();
    verify(rescate.rescatar).called(2);
    expect(find.textContaining('se enviaron'), findsOneWidget);
  });
}
