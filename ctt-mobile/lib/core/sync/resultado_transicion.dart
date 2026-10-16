/// resultado_transicion.dart — Tipos de resultado de una transición de estado de ítem.
///
/// Permite a la UI reaccionar de forma diferente según lo que ocurrió:
/// servidor OK, sin red, rechazo de negocio, o conflicto de concurrencia.
library;

import 'package:ctt_mobile/data/local/daos/sync_dao.dart' show ResultadoEspera;
import 'package:ctt_mobile/domain/enums/enums_ctt.dart';

sealed class ResultadoTransicion {
  const ResultadoTransicion();
}

/// Mapea el resultado de la espera por fila (CTT-148) a los tipos que consume la UI
/// ACTUAL. TRANSITORIO: el commit (g) hace que la UI consuma [ResultadoEspera] directo
/// (con el código de error) y entonces esta función y los subtipos sin uso se retiran.
ResultadoTransicion resultadoTransicionDesde(ResultadoEspera e) => switch (e.estado) {
      EstadoSyncLocal.sincronizado =>
        const TransicionAplicadaOnline(<String, dynamic>{}),
      EstadoSyncLocal.rechazada =>
        TransicionRechazada(e.ultimoError ?? 'El servidor rechazó el cambio.'),
      EstadoSyncLocal.esperandoResolucion => const TransicionConConflicto(null),
      // pendiente / enviando / enRevision / descartado → "quedó encolado".
      _ => const TransicionEncoladaOffline(),
    };

/// El servidor procesó la transición con éxito (HTTP 200).
/// [itemActualizado] contiene el JSON del ítem retornado por el backend.
final class TransicionAplicadaOnline extends ResultadoTransicion {
  const TransicionAplicadaOnline(this.itemActualizado);
  final Map<String, dynamic> itemActualizado;
}

/// Sin conexión o timeout: el cambio quedó en la cola Drift para sincronizar después.
final class TransicionEncoladaOffline extends ResultadoTransicion {
  const TransicionEncoladaOffline();
}

/// El servidor rechazó la transición por regla de negocio (409 sin conflicto_id).
/// [detalle] es el mensaje legible del campo `detail` del backend.
final class TransicionRechazada extends ResultadoTransicion {
  const TransicionRechazada(this.detalle);
  final String detalle;
}

/// Conflicto de concurrencia detectado (409 con conflicto_id): requiere resolución manual.
final class TransicionConConflicto extends ResultadoTransicion {
  const TransicionConConflicto(this.conflictoId);
  final String? conflictoId;
}
