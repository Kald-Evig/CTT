/// indicio_conexion.dart — Señal de que la red PUDO volver (CTT-157).
///
/// Contador keepAlive que bombean, desde la capa core (sin acoplar a presentation), los INDICIOS
/// de conectividad: el 2xx de [UltimoContactoInterceptor] (Dio foreground) y el flanco
/// offline→online de [ConectividadListener]. El revalidador de sesión (presentation) lo escucha y
/// decide con su guarda (solo offline) + single-flight. El valor solo importa como "cambió".
///
/// El isolate HEADLESS no lo bombea: corre sin ProviderScope y sus Dios no reciben el callback.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'indicio_conexion.g.dart';

@Riverpod(keepAlive: true)
class IndicioConexion extends _$IndicioConexion {
  @override
  int build() => 0;

  /// Registra un indicio más de que la red pudo volver.
  void notificar() => state = state + 1;
}
