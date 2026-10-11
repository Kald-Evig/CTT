/// ventana_offline.dart — Ventana de sesión offline por rol (CTT-138).
///
/// Mientras la sesión está `autenticadoOffline`, el Trabajador/Residente puede operar
/// hasta un tope medido desde el último contacto con el servidor. Al vencer, la UI
/// bloquea la captura (botones de transición) y muestra "Conéctate para seguir"; la
/// cola NO se toca. Defaults locales hasta CTT-139 (que los traerá del servidor).
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:ctt_mobile/app.dart';
import 'package:ctt_mobile/core/network/dio_client.dart';

part 'ventana_offline.g.dart';

/// Tope de sesión offline por rol. Solo Trabajador y Residente tienen sesión offline.
const _ventanasPorRol = <String, Duration>{
  'trabajador': Duration(days: 14),
  'residente': Duration(days: 3),
};

/// Ventana del rol, o null si el rol no tiene sesión offline.
Duration? ventanaPorRol(String rol) => _ventanasPorRol[rol];

/// true si la ventana offline del rol venció. Conservador: sin último contacto o rol
/// sin ventana → vencida (se bloquea la captura).
bool ventanaVencida({
  required String rol,
  required DateTime? ultimoContacto,
  required DateTime ahora,
}) {
  final v = ventanaPorRol(rol);
  if (v == null || ultimoContacto == null) return true;
  return ahora.difference(ultimoContacto) > v;
}

/// Estado de la sesión offline para la UI (banner + gating de la captura).
class EstadoVentanaOffline {
  const EstadoVentanaOffline({
    required this.esOffline,
    this.verificadoHace,
    this.vencida = false,
  });

  /// La sesión se está sirviendo desde Drift (autenticadoOffline).
  final bool esOffline;

  /// `ahora - ultimoContacto`, para el banner "verificado hace X".
  final Duration? verificadoHace;

  /// La ventana se superó → bloquear la captura.
  final bool vencida;
}

@riverpod
Future<EstadoVentanaOffline> estadoVentanaOffline(
  EstadoVentanaOfflineRef ref,
) async {
  final auth = ref.watch(estadoAuthProvider);
  if (auth != EstadoAuth.autenticadoOffline) {
    return const EstadoVentanaOffline(esOffline: false);
  }
  final rol = ref.watch(rolUsuarioActualProvider) ?? '';
  final ultimo = await ref.read(secureStorageProvider).obtenerUltimoContacto();
  final ahora = DateTime.now().toUtc();
  return EstadoVentanaOffline(
    esOffline: true,
    verificadoHace: ultimo == null ? null : ahora.difference(ultimo),
    vencida: ventanaVencida(rol: rol, ultimoContacto: ultimo, ahora: ahora),
  );
}

/// "hace X" legible para el banner.
/// DUPE: misma idea de tiempo relativo que notificaciones_screen.dart:113-116. La
/// convención del repo (formato_fecha.dart:4) es tener "hace X" por pantalla;
/// consolidar si aparece una 3ra copia.
String verificadoHaceTexto(Duration? d) {
  if (d == null) return 'sin registro';
  if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
  if (d.inHours < 24) return 'hace ${d.inHours} h';
  return 'hace ${d.inDays} d';
}
