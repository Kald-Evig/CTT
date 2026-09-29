/// pantalla_recuperacion.dart — CTT-130 fase 4.
///
/// Se muestra cuando la base local no pudo abrirse o migrarse. NUNCA el login: el
/// trabajador tiene que saber que su trabajo no se perdió y qué NO hacer.
///
/// Decisión de diseño (Kald): el trabajador NO maneja archivos. El rescate de datos
/// es automático (fase 4b) y por soporte, como en CommHCare/DHIS2 — no un "exportá el
/// archivo" que el usuario no puede alcanzar. Por eso NO hay botón de exportar acá;
/// la pantalla solo informa, muestra cuánto hay en juego y ofrece Reintentar.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ctt_mobile/data/local/database.dart';
import 'package:ctt_mobile/presentation/arranque/arranque_provider.dart';

class PantallaRecuperacion extends ConsumerWidget {
  const PantallaRecuperacion({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conteo = ref.watch(conteoPendientesRescateProvider);

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.shield_outlined, size: 64),
              const SizedBox(height: 16),
              Text(
                'No pudimos abrir la app',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              // Conteo de trabajo en juego (crudo, sin Drift). Mientras carga o si
              // no se puede leer, el mensaje igual asegura que el trabajo está a salvo.
              Text(
                switch (conteo) {
                  AsyncData(:final value) when value > 0 =>
                    'Tenés $value cambio${value == 1 ? '' : 's'} guardado'
                        '${value == 1 ? '' : 's'} en el teléfono, sin enviar.',
                  _ => 'Tus cambios guardados en el teléfono están a salvo.',
                },
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'Tu trabajo NO se perdió. Para no perderlo, NO desinstales la app '
                'ni borres sus datos. Avisá a tu supervisor para que te ayude a '
                'recuperarlo.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
                // Instancia FRESCA de la base: Drift cachea _migrationError en la
                // instancia y lo relanza en cada apertura del mismo proceso
                // (engines.dart:462-479). Sin invalidar baseDatosCTTProvider, el
                // reintento reusaría la instancia rota y no serviría hasta reiniciar.
                onPressed: () {
                  ref.invalidate(baseDatosCTTProvider);
                  ref.invalidate(arranqueProvider);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
