/// enums_ctt_test.dart — Tests de los enums del dominio.
///
/// Verifica que los valores string coincidan exactamente con los del backend
/// (app/enums.py). Si el backend cambia un valor, este test falla primero.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ctt_mobile/domain/enums/enums_ctt.dart';

void main() {
  group('RolUsuario', () {
    test('valores coinciden con el backend', () {
      expect(RolUsuario.admin.valor, 'admin');
      expect(RolUsuario.coordinador.valor, 'coordinador');
      expect(RolUsuario.residente.valor, 'residente');
      expect(RolUsuario.trabajador.valor, 'trabajador');
    });

    test('fromString deserializa correctamente', () {
      expect(RolUsuario.fromString('admin'), RolUsuario.admin);
      expect(RolUsuario.fromString('trabajador'), RolUsuario.trabajador);
    });

    test('fromString lanza ArgumentError para valor desconocido', () {
      expect(() => RolUsuario.fromString('superadmin'), throwsArgumentError);
    });
  });

  group('EstadoItem', () {
    test('valores coinciden con el backend', () {
      expect(EstadoItem.abierto.valor, 'abierto');
      expect(EstadoItem.enProgreso.valor, 'en_progreso');
      expect(EstadoItem.pendienteRevision.valor, 'pendiente_revision');
      expect(EstadoItem.terminado.valor, 'terminado');
      expect(EstadoItem.problema.valor, 'problema');
    });

    test('fromString deserializa enProgreso correctamente', () {
      // "en_progreso" tiene underscore — verificar que no se confunda.
      expect(EstadoItem.fromString('en_progreso'), EstadoItem.enProgreso);
    });
  });

  group('PlanEmpresa', () {
    test('valores coinciden con el backend', () {
      expect(PlanEmpresa.trial.valor, 'trial');
      expect(PlanEmpresa.basic.valor, 'basic');
      expect(PlanEmpresa.pro.valor, 'pro');
    });
  });

  group('EstadoSyncLocal (v4 — ciclo de vida)', () {
    test('el conjunto de estados es exactamente el rediseñado', () {
      // Gestión interna del dispositivo — no existe en el backend. conflicto,
      // rechazado y error DEJARON de ser estados (ahora son MotivoSync).
      expect(
        EstadoSyncLocal.values.map((e) => e.valor).toSet(),
        {'pendiente', 'enviando', 'esperando_resolucion', 'sincronizado',
         'descartado',},
      );
    });

    test('solo sincronizado y descartado son terminales', () {
      final terminales =
          EstadoSyncLocal.values.where((e) => e.esTerminal).toSet();
      expect(terminales,
          {EstadoSyncLocal.sincronizado, EstadoSyncLocal.descartado},);
    });

    test('fromString lanza para los valores viejos ya retirados', () {
      for (final viejo in ['conflicto', 'rechazado', 'error']) {
        expect(() => EstadoSyncLocal.fromString(viejo), throwsArgumentError,
            reason: '$viejo ya no es un estado',);
      }
    });
  });

  group('MotivoSync', () {
    test('valores de los motivos', () {
      expect(MotivoSync.conflicto.valor, 'conflicto');
      expect(MotivoSync.conflictoResueltoCliente.valor,
          'conflicto_resuelto_cliente',);
      expect(MotivoSync.conflictoResueltoServidor.valor,
          'conflicto_resuelto_servidor',);
      expect(MotivoSync.rechazoNegocio.valor, 'rechazo_negocio');
      expect(MotivoSync.reintentosAgotados.valor, 'reintentos_agotados');
      expect(MotivoSync.errorTransitorio.valor, 'error_transitorio');
      expect(MotivoSync.heredadoIndeterminado.valor, 'heredado_indeterminado');
    });
  });
}
