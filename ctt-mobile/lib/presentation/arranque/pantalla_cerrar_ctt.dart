/// pantalla_cerrar_ctt.dart — CTT-147. Pantalla bloqueante de la fase 1 de la defensa.
///
/// Se muestra cuando se detectó el estado roto de Firebase Auth (sesión irrecuperable). Borrar
/// los archivos con el proceso vivo no sirve (ctt147_exp i): hay que cerrar la app y que la
/// fase 2 (en `main()`, antes de `Firebase.initializeApp`) los borre en el próximo arranque.
/// Por eso el único camino es cerrar el proceso.
///
/// El botón espera a que no haya una corrida de sync en curso (reusa [CicloSyncUi.enVuelo]; no
/// duplica la guarda) y recién ahí termina el proceso. Mientras espera, queda deshabilitado con
/// su indicador.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ctt_mobile/core/sync/ciclo_sync_ui.dart';

/// Permite terminar el proceso sin matar el runner de los tests. En producción = `exit(0)`.
typedef TerminadorProceso = void Function();

class PantallaCerrarCtt extends ConsumerStatefulWidget {
  const PantallaCerrarCtt({super.key, this.terminar});

  /// Inyectable para tests; por defecto cierra el proceso con `exit(0)`.
  final TerminadorProceso? terminar;

  @override
  ConsumerState<PantallaCerrarCtt> createState() => _PantallaCerrarCttState();
}

class _PantallaCerrarCttState extends ConsumerState<PantallaCerrarCtt> {
  /// Intervalo del sondeo de "¿sigue corriendo el sync?" y tope de espera antes de cerrar
  /// igual (no colgar al usuario si el guard se quedara en vuelo).
  static const _intervalo = Duration(milliseconds: 200);
  static const _topeEspera = Duration(seconds: 10);

  bool _cerrando = false;

  Future<void> _cerrar() async {
    if (_cerrando) return;
    setState(() => _cerrando = true);

    // Espera a que no haya una corrida de sync en curso (hasta un tope).
    final limite = DateTime.now().add(_topeEspera);
    while (ref.read(cicloSyncUiProvider).enVuelo &&
        DateTime.now().isBefore(limite)) {
      await Future<void>.delayed(_intervalo);
    }

    (widget.terminar ?? () => exit(0))();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.refresh, size: 64),
              const SizedBox(height: 16),
              Text(
                'Recupera tu sesión',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'Para recuperar tu sesión, CTT necesita cerrarse. Toca Cerrar CTT '
                'y vuelve a abrirla desde el ícono.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _cerrando ? null : _cerrar,
                child: _cerrando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Cerrar CTT'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
