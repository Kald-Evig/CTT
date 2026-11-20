/// revalidador_foreground.dart — Cableado del revalidador de sesión offline (CTT-157).
///
/// Provider keepAlive que CONSTRUYE el controlador puro [RevalidadorSesion] y le inyecta la
/// re-resolución real (`ref.invalidate(perfilSesionProvider)` + esperar su future). Los
/// disparadores (interceptor 2xx y conectividad → `indicioConexion`; `resumed` y sondeo → el
/// widget) llaman a `solicitar()`. Vive en keepAlive, como [cicloSyncUi], para que el estado del
/// single-flight/intervalo sea estable toda la sesión.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:ctt_mobile/app.dart';
import 'package:ctt_mobile/core/network/indicio_conexion.dart';
import 'package:ctt_mobile/core/sync/revalidador_sesion.dart';
import 'package:ctt_mobile/presentation/auth/perfil_notifier.dart';

part 'revalidador_foreground.g.dart';

@Riverpod(keepAlive: true)
RevalidadorSesion revalidadorSesion(RevalidadorSesionRef ref) {
  final ctrl = RevalidadorSesion(
    // Mecanismo (CTT-157): invalidate = REFRESH en Riverpod 2.6 (sin flash a /cargando). Se espera
    // el future para saber cuándo terminó (single-flight). NO se agrega un watch a PerfilSesion:
    // eso sería un reload (skipLoadingOnReload=false) y mostraría la pantalla de carga.
    reResolver: () {
      ref.invalidate(perfilSesionProvider);
      return ref.read(perfilSesionProvider.future);
    },
  );
  ref.onDispose(ctrl.dispose);
  return ctrl;
}

/// Cableado delgado (como [PlanificadorForeground], CTT-141): alimenta al controlador con el ciclo
/// de vida, el estado offline (desde `estadoAuth`) y los indicios de red (`indicioConexion`:
/// disparadores 1 y 2). Los disparadores 3 (`resumed`) y 4 (sondeo) los maneja el controlador.
/// Invisible: devuelve [child]. El controlador vive en el provider keepAlive (se dispone ahí).
class RevalidadorForeground extends ConsumerStatefulWidget {
  const RevalidadorForeground({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<RevalidadorForeground> createState() => _RevalidadorForegroundState();
}

class _RevalidadorForegroundState extends ConsumerState<RevalidadorForeground>
    with WidgetsBindingObserver {
  late final RevalidadorSesion _rev;
  ProviderSubscription<EstadoAuth>? _subAuth;
  ProviderSubscription<int>? _subIndicio;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _rev = ref.read(revalidadorSesionProvider);
    _subAuth = ref.listenManual(
      estadoAuthProvider,
      (_, next) => _rev.alCambiarEstadoOffline(next == EstadoAuth.autenticadoOffline),
      fireImmediately: true,
    );
    // Disparadores 1 (2xx) y 2 (flanco de conectividad) llegan por esta señal.
    _subIndicio = ref.listenManual(
      indicioConexionProvider,
      (_, __) => _rev.solicitar(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _rev.alCambiarCicloDeVida(state);

  @override
  void dispose() {
    _subAuth?.close();
    _subIndicio?.close();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
