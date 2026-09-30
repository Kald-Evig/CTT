/// pantalla_recuperacion.dart — CTT-130 fase 4 / 4b.
///
/// Se muestra cuando la base local no pudo abrirse o migrarse. NUNCA el login: el
/// trabajador tiene que saber que su trabajo no se perdió y qué NO hacer.
///
/// El trabajador NO maneja archivos (decisión Kald). Al entrar, la app RESCATA sola
/// la cola al servidor (fase 4b): lee las filas no terminales con SQL crudo y las
/// envía. Sin señal reintenta con backoff mientras la pantalla esté abierta; sin
/// sesión avisa y NO reintenta en loop. No hay botón de exportar.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ctt_mobile/core/sync/rescate_service.dart';
import 'package:ctt_mobile/data/local/database.dart';
import 'package:ctt_mobile/presentation/arranque/arranque_provider.dart';

class PantallaRecuperacion extends ConsumerStatefulWidget {
  const PantallaRecuperacion({super.key, required this.error});

  final Object error;

  @override
  ConsumerState<PantallaRecuperacion> createState() =>
      _PantallaRecuperacionState();
}

class _PantallaRecuperacionState extends ConsumerState<PantallaRecuperacion> {
  /// Backoff entre reintentos de rescate ante falta de red (solo mientras la
  /// pantalla esté abierta).
  static const _backoff = Duration(seconds: 15);

  RescateResultado? _resultado;
  bool _rescatando = false;
  Timer? _reintento;

  @override
  void initState() {
    super.initState();
    // Dispara el rescate al entrar (post-frame para no bloquear el primer render).
    WidgetsBinding.instance.addPostFrameCallback((_) => _intentarRescate());
  }

  @override
  void dispose() {
    _reintento?.cancel();
    super.dispose();
  }

  Future<void> _intentarRescate() async {
    if (!mounted) return;
    setState(() => _rescatando = true);
    RescateResultado resultado;
    try {
      resultado = await ref.read(rescateServiceProvider).rescatar();
    } catch (_) {
      // Falla inesperada (no es un DioException que el servicio ya clasifica):
      // no reintentar en loop, pero avisar (nunca silencio).
      if (!mounted) return;
      setState(() {
        _resultado = const RescateResultado(ResultadoRescate.errorCliente);
        _rescatando = false;
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _resultado = resultado;
      _rescatando = false;
    });
    // Reintentan (con backoff, mientras la pantalla viva) la falta de red y las
    // fallas transitorias del servidor (5xx/429). Los 4xx NO reintentan.
    if (resultado.estado == ResultadoRescate.sinRed ||
        resultado.estado == ResultadoRescate.errorServidor) {
      _reintento = Timer(_backoff, _intentarRescate);
    }
  }

  String _mensajeRescate() {
    if (_rescatando) return 'Enviando tus cambios a tu supervisor…';
    final r = _resultado;
    if (r == null) return '';
    return switch (r.estado) {
      // Rescate parcial: si el servidor dejó filas sin rescatar, decir cuántas y
      // que siguen guardadas — nunca un "se enviaron" a secas.
      ResultadoRescate.enviado when r.sinRescatar > 0 =>
        'Se enviaron ${r.enviadas} cambio${r.enviadas == 1 ? '' : 's'}. '
            'Quedaron ${r.sinRescatar} sin enviar; siguen guardados en el teléfono. '
            'Avisá a tu supervisor.',
      ResultadoRescate.enviado =>
        'Listo: tus cambios se enviaron a tu supervisor.',
      ResultadoRescate.nadaQueEnviar => 'No hay cambios sin enviar.',
      ResultadoRescate.sinRed =>
        'Sin señal. Tus cambios están guardados y se reintentará solo.',
      ResultadoRescate.errorServidor =>
        'El servidor no está disponible ahora. Tus cambios están guardados y se '
            'reintentará solo.',
      ResultadoRescate.errorCliente =>
        'No se pudieron enviar tus cambios. Siguen guardados en el teléfono. '
            'Avisá a tu supervisor.',
      ResultadoRescate.sinSesion =>
        'Tus cambios siguen guardados en el teléfono. Avisá a tu supervisor.',
    };
  }

  @override
  Widget build(BuildContext context) {
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
              const SizedBox(height: 12),
              // Estado del rescate automático (fase 4b).
              Text(
                _mensajeRescate(),
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'Tu trabajo NO se perdió. Para no perderlo, NO desinstales la app '
                'ni borres sus datos. Avisá a tu supervisor.',
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
