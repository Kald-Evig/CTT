/// extraer_conflicto_id_test.dart — CTT-109.
///
/// Verifica `extraerConflictoId`: baja a `data['detail']` y devuelve
/// `detail['conflicto_id']` solo cuando es String. El backend anida el id bajo
/// `detail` (no en la raíz); el defecto original lo leía en la raíz y siempre
/// obtenía null, clasificando un conflicto real como rechazo de negocio.
///
/// El caso 1 usa el body EXACTO que devolvió el servidor (409 sobre
/// /items/373d8055.../transicion, CTT-109 paso 1). Los casos 2-6 son controles:
/// sin ellos, un helper que devolviera siempre el mismo valor pasaría el caso 1.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ctt_mobile/core/network/extraer_detalle_backend.dart';

/// Body real del 409 de conflicto de concurrencia (CTT-109 paso 1), con acentos.
/// `jsonDecode` produce el mismo Map que Dio entrega en `e.response?.data`.
const _bodyRealPaso1 =
    '{"detail":{"tipo":"conflicto_concurrencia","conflicto_id":"3c2cb0ea-67dd-4fd9-b97c-6cc037f887ff","mensaje":"El ítem fue modificado en el servidor mientras el dispositivo estaba offline.","estado_servidor":"en_progreso"}}';

/// DioException con un `response.data` dado (simula la respuesta decodificada).
DioException _conData(dynamic data) {
  final opciones = RequestOptions(path: '/items/x/transicion');
  return DioException(
    requestOptions: opciones,
    response: Response<dynamic>(requestOptions: opciones, data: data),
  );
}

/// DioException sin response (error de red: no llegó body).
DioException _sinResponse() {
  final opciones = RequestOptions(path: '/items/x/transicion');
  return DioException(
    requestOptions: opciones,
    type: DioExceptionType.connectionError,
  );
}

void main() {
  test('1 — detail Map CON conflicto_id (body real): devuelve el id', () {
    final e = _conData(jsonDecode(_bodyRealPaso1));
    expect(
      extraerConflictoId(e),
      '3c2cb0ea-67dd-4fd9-b97c-6cc037f887ff',
    );
  });

  test('2 — detail String (rechazo de negocio): null, no revienta', () {
    final e = _conData({'detail': 'Transición no permitida: en_progreso -> terminado'});
    expect(extraerConflictoId(e), isNull);
  });

  test('3 — detail Map SIN conflicto_id: null', () {
    final e = _conData({
      'detail': {'tipo': 'otro', 'mensaje': 'algo'},
    });
    expect(extraerConflictoId(e), isNull);
  });

  test('4 — detail List (422 de Pydantic): null', () {
    final e = _conData({
      'detail': [
        {
          'loc': ['body', 'nuevo_estado'],
          'msg': 'field required',
          'type': 'value_error.missing',
        },
      ],
    });
    expect(extraerConflictoId(e), isNull);
  });

  test('5 — sin body: null', () {
    expect(extraerConflictoId(_sinResponse()), isNull);
  });

  test('6 — conflicto_id presente pero no String: null, no lanza', () {
    final e = _conData({
      'detail': {'conflicto_id': 12345},
    });
    expect(() => extraerConflictoId(e), returnsNormally);
    expect(extraerConflictoId(e), isNull);
  });
}
