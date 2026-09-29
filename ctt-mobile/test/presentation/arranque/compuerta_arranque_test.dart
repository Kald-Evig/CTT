/// compuerta_arranque_test.dart — CTT-130 fase 4.
///
/// T6: si la compuerta de arranque falla (la base no abre/migra), la app muestra la
/// pantalla de recuperación — NUNCA el login. Es el hueco que se corrige: hoy el
/// router enmascara el fallo con valueOrNull y manda al login.
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
          // La compuerta de arranque falla (p.ej. base más nueva que la app, o
          // migración fallida): el provider queda en error.
          arranqueProvider.overrideWith(
            (ref) => Future<void>.error(
              StateError('base no pudo abrir'),
            ),
          ),
        ],
        child: const AppCTT(),
      ),
    );
    await tester.pumpAndSettle();

    // Se ve la pantalla de recuperación, con sus acciones.
    expect(find.byType(PantallaRecuperacion), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.text('Exportar cambios pendientes'), findsOneWidget);
    // Y NO el login: no aparece ningún campo de texto de credenciales.
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('Iniciar sesión'), findsNothing);
  });
}
