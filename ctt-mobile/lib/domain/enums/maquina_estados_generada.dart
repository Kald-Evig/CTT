// GENERADO por ctt-backend/scripts/generar_contrato_dart.py — NO EDITAR.
// Regenerar con: python ctt-backend/scripts/generar_contrato_dart.py
//
// Contrato (code-first) de la máquina de estados de ítems. Fuente única:
// ctt-backend/app/state_machine.py (TRANSICIONES + acciones especiales). Un cambio
// de reglas se REGENERA; no se edita a mano. Un test de pytest compara este archivo
// byte a byte con la salida del generador.
library;

import 'package:ctt_mobile/domain/enums/enums_ctt.dart';

/// Acción especial fuera de la tabla de transiciones.
enum AccionEspecial { cerrarProblema, revertirTerminado }

/// Una transición permitida (espejo de state_machine.TRANSICIONES).
class TransicionContrato {
  const TransicionContrato({
    required this.desde,
    required this.hacia,
    required this.roles,
    this.requiereAsignacion = false,
    this.requiereComentario = false,
    this.requiereDescripcionProblema = false,
  });

  final EstadoItem desde;
  final EstadoItem hacia;
  final Set<RolUsuario> roles;
  final bool requiereAsignacion;
  final bool requiereComentario;
  final bool requiereDescripcionProblema;
}

/// Una acción especial con su estado de origen y roles.
class AccionEspecialContrato {
  const AccionEspecialContrato({
    required this.accion,
    required this.estadoOrigen,
    required this.roles,
  });

  final AccionEspecial accion;
  final EstadoItem estadoOrigen;
  final Set<RolUsuario> roles;
}

/// Transiciones permitidas, en el orden de state_machine.TRANSICIONES.
const List<TransicionContrato> kTransicionesContrato = [
  TransicionContrato(
    desde: EstadoItem.abierto,
    hacia: EstadoItem.enProgreso,
    roles: {RolUsuario.trabajador},
    requiereAsignacion: true,
  ),
  TransicionContrato(
    desde: EstadoItem.enProgreso,
    hacia: EstadoItem.pendienteRevision,
    roles: {RolUsuario.trabajador},
  ),
  TransicionContrato(
    desde: EstadoItem.enProgreso,
    hacia: EstadoItem.problema,
    roles: {RolUsuario.residente, RolUsuario.trabajador},
    requiereDescripcionProblema: true,
  ),
  TransicionContrato(
    desde: EstadoItem.pendienteRevision,
    hacia: EstadoItem.terminado,
    roles: {RolUsuario.admin, RolUsuario.coordinador, RolUsuario.residente},
  ),
  TransicionContrato(
    desde: EstadoItem.pendienteRevision,
    hacia: EstadoItem.enProgreso,
    roles: {RolUsuario.admin, RolUsuario.coordinador, RolUsuario.residente},
    requiereComentario: true,
  ),
  TransicionContrato(
    desde: EstadoItem.pendienteRevision,
    hacia: EstadoItem.problema,
    roles: {RolUsuario.residente},
    requiereDescripcionProblema: true,
  ),
];

/// Acciones especiales (cerrar problema, revertir terminado).
const List<AccionEspecialContrato> kAccionesEspecialesContrato = [
  AccionEspecialContrato(
    accion: AccionEspecial.cerrarProblema,
    estadoOrigen: EstadoItem.problema,
    roles: {RolUsuario.admin, RolUsuario.coordinador, RolUsuario.residente},
  ),
  AccionEspecialContrato(
    accion: AccionEspecial.revertirTerminado,
    estadoOrigen: EstadoItem.terminado,
    roles: {RolUsuario.admin},
  ),
];
