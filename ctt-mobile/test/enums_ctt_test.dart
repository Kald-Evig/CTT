/// enums_ctt_test.dart — Tests de los enums del dominio.
///
/// Verifica que los valores string coincidan exactamente con los del backend
/// (app/enums.py). Si el backend cambia un valor, este test falla primero.

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

  group('EstadoSyncLocal', () {
    test('conflicto existe como estado local', () {
      // EstadoSyncLocal.conflicto NO existe en el backend — es gestión interna.
      expect(EstadoSyncLocal.conflicto.valor, 'conflicto');
    });
  });
}
