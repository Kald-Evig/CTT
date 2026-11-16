/// acciones_permitidas_test.dart — CTT-153: regresiones de accionesPermitidas.
///
/// Expectativas ESCRITAS A MANO (no derivadas de la tabla generada, que sería
/// tautológico): fijan el comportamiento observable que el ticket pide.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:ctt_mobile/domain/acciones_permitidas.dart';
import 'package:ctt_mobile/domain/enums/enums_ctt.dart';

List<EstadoItem> _haciaDe(List<AccionItem> acciones) => [
      for (final a in acciones)
        if (a is AccionTransicion) a.hacia,
    ];

bool _tieneEspecial(List<AccionItem> acciones, AccionEspecial e) => acciones
    .any((a) => a is AccionEspecialItem && a.accion == e);

void main() {
  group('Trabajador', () {
    test('en problema → ninguna transición (R1: solo el Residente cierra)', () {
      final acciones = accionesPermitidas(
        EstadoItem.problema,
        RolUsuario.trabajador,
        esAsignado: true,
      );
      expect(acciones, isEmpty);
    });

    test('en abierto, NO asignado → ninguna transición', () {
      final acciones = accionesPermitidas(
        EstadoItem.abierto,
        RolUsuario.trabajador,
        esAsignado: false,
      );
      expect(acciones, isEmpty);
    });

    test('en abierto, asignado → solo iniciar (abierto→en_progreso)', () {
      final acciones = accionesPermitidas(
        EstadoItem.abierto,
        RolUsuario.trabajador,
        esAsignado: true,
      );
      expect(_haciaDe(acciones), [EstadoItem.enProgreso]);
    });

    test('en en_progreso → terminar y reportar problema', () {
      final acciones = accionesPermitidas(
        EstadoItem.enProgreso,
        RolUsuario.trabajador,
        esAsignado: true,
      );
      expect(
        _haciaDe(acciones),
        containsAll([EstadoItem.pendienteRevision, EstadoItem.problema]),
      );
    });
  });

  group('Residente', () {
    test('en abierto → ninguna transición (no se ofrece "Marcar problema")', () {
      final acciones = accionesPermitidas(
        EstadoItem.abierto,
        RolUsuario.residente,
        esAsignado: false,
      );
      expect(_haciaDe(acciones), isEmpty);
    });

    test('en en_progreso → sí puede marcar problema', () {
      final acciones = accionesPermitidas(
        EstadoItem.enProgreso,
        RolUsuario.residente,
        esAsignado: false,
      );
      expect(_haciaDe(acciones), contains(EstadoItem.problema));
    });

    test('en pendiente_revision → aprobar, rechazar y marcar problema', () {
      final acciones = accionesPermitidas(
        EstadoItem.pendienteRevision,
        RolUsuario.residente,
        esAsignado: false,
      );
      expect(
        _haciaDe(acciones),
        containsAll([
          EstadoItem.terminado,
          EstadoItem.enProgreso,
          EstadoItem.problema,
        ]),
      );
    });

    test('en problema → cerrar problema (acción especial)', () {
      final acciones = accionesPermitidas(
        EstadoItem.problema,
        RolUsuario.residente,
        esAsignado: false,
      );
      expect(_tieneEspecial(acciones, AccionEspecial.cerrarProblema), isTrue);
      expect(_haciaDe(acciones), isEmpty);
    });
  });
}
