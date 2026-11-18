/// grupo_accion_test.dart — CTT-162: el grupo de "Mis ítems" se deriva de
/// accionesPermitidas (rol Trabajador, esAsignado: true) + si el estado es terminado.
/// El conflicto NO entra (grupoAccion no lo recibe).
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:ctt_mobile/domain/enums/enums_ctt.dart';
import 'package:ctt_mobile/domain/grupo_accion.dart';

GrupoAccion _grupo(EstadoItem e) =>
    grupoAccion(e, rol: RolUsuario.trabajador, esAsignado: true);

void main() {
  group('grupoAccion (Trabajador, esAsignado: true)', () {
    test('abierto y en_progreso → grupo 1 (Le toca al Trabajador)', () {
      expect(_grupo(EstadoItem.abierto), GrupoAccion.leTocaAlTrabajador);
      expect(_grupo(EstadoItem.enProgreso), GrupoAccion.leTocaAlTrabajador);
    });

    // Esta expectativa es la que cae si grupoAccion dejara de mirar accionesPermitidas
    // (p. ej. devolviendo siempre grupo 1 para lo no terminado): ver el red-break de G3.
    test('pendiente_revision y problema → grupo 2 (Espera a otros)', () {
      expect(_grupo(EstadoItem.pendienteRevision), GrupoAccion.esperaAOtros);
      expect(_grupo(EstadoItem.problema), GrupoAccion.esperaAOtros);
    });

    test('terminado → grupo 3 (Terminados recientes)', () {
      expect(_grupo(EstadoItem.terminado), GrupoAccion.terminadosRecientes);
    });

    test('las etiquetas son las definidas por Kald, en un solo lugar', () {
      expect(GrupoAccion.leTocaAlTrabajador.etiqueta, 'Le toca a ti');
      expect(GrupoAccion.esperaAOtros.etiqueta, 'Esperando a otros');
      expect(GrupoAccion.terminadosRecientes.etiqueta, 'Terminados recientes');
    });

    test('el orden de los grupos (index) es 1 → 2 → 3', () {
      expect(GrupoAccion.leTocaAlTrabajador.index, 0);
      expect(GrupoAccion.esperaAOtros.index, 1);
      expect(GrupoAccion.terminadosRecientes.index, 2);
    });
  });
}
