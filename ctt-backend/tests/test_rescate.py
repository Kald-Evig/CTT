"""test_rescate.py — CTT-130 fase 4b: endpoint de rescate a cuarentena.

Cubre: filas aceptadas; empresa ajena rechazada y NO almacenada; dueño ajeno
guardado con subido_por; reenvío idempotente sin duplicar; fila ya aplicada marcada;
entradas en el audit log; límites de tamaño (máx filas y máx body).
"""

from app.enums import IdempotenciaEstado, RescateEstado
from app.models import AuditLog, ClaveIdempotencia, ColaRescate


def _fila(idem, empresa_id, usuario_id, **extra):
    return {
        "id": f"row-{idem}",
        "idempotency_key": idem,
        "empresa_id": empresa_id,
        "usuario_id": usuario_id,
        "instalacion_id": "inst-1",
        "tipo_entidad": "item",
        "entidad_id": "item-x",
        "accion": "cambio_estado_item",
        "secuencia": 1,
        "payload": '{"nuevo_estado":"pendiente_revision"}',
        **extra,
    }


def _post(client, seeded, uid, filas, instalacion="inst-1"):
    return client.post(
        "/sync/rescate",
        json={"instalacion_id": instalacion, "filas": filas},
        headers=seeded.headers(uid),
    )


def test_aceptadas_van_a_cuarentena(client, seeded, db):
    r = _post(client, seeded, seeded.trab,
              [_fila("k1", seeded.emp_a, seeded.trab_id)])
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["recibidas"] == 1
    assert body["aceptadas"] == 1
    assert body["rechazadas_tenant"] == 0

    db.expire_all()
    fila = db.query(ColaRescate).filter(ColaRescate.idempotency_key == "k1").one()
    assert fila.empresa_id == seeded.emp_a
    assert fila.subido_por == seeded.trab_id
    assert fila.usuario_id == seeded.trab_id
    assert fila.subido_por_tercero is False
    assert fila.estado_revision == RescateEstado.PENDIENTE_REVISION


def test_empresa_ajena_rechazada_y_no_almacenada(client, seeded, db):
    # trab pertenece a emp_a; una fila de emp_b es de un tenant ajeno.
    r = _post(client, seeded, seeded.trab,
              [_fila("k-ajena", seeded.emp_b, seeded.trab_id)])
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["rechazadas_tenant"] == 1
    assert body["aceptadas"] == 0

    db.expire_all()
    assert db.query(ColaRescate).filter(
        ColaRescate.idempotency_key == "k-ajena").count() == 0


def test_dueno_ajeno_se_guarda_con_subido_por(client, seeded, db):
    # trab sube una fila cuyo dueño declarado es el residente (dispositivo compartido).
    r = _post(client, seeded, seeded.trab,
              [_fila("k-tercero", seeded.emp_a, seeded.resid_id)])
    assert r.status_code == 200, r.text
    assert r.json()["aceptadas"] == 1

    db.expire_all()
    fila = db.query(ColaRescate).filter(
        ColaRescate.idempotency_key == "k-tercero").one()
    assert fila.subido_por == seeded.trab_id       # quién subió
    assert fila.usuario_id == seeded.resid_id       # dueño declarado
    assert fila.subido_por_tercero is True


def test_reenvio_idempotente_no_duplica(client, seeded, db):
    f = [_fila("k-dup", seeded.emp_a, seeded.trab_id)]
    r1 = _post(client, seeded, seeded.trab, f)
    r2 = _post(client, seeded, seeded.trab, f)
    assert r1.json()["aceptadas"] == 1
    assert r2.json()["duplicadas"] == 1
    assert r2.json()["aceptadas"] == 0

    db.expire_all()
    assert db.query(ColaRescate).filter(
        ColaRescate.idempotency_key == "k-dup").count() == 1


def test_fila_ya_aplicada_marcada(client, seeded, db):
    # Simula el POST original que SÍ llegó (CTT-127): clave completada en CTT-105.
    db.add(ClaveIdempotencia(
        empresa_id=seeded.emp_a,
        idempotency_key="k-aplicada",
        endpoint="/items/item-x/transicion",
        fingerprint="deadbeef",
        estado=IdempotenciaEstado.COMPLETADO,
        status_code=200,
    ))
    db.commit()

    r = _post(client, seeded, seeded.trab,
              [_fila("k-aplicada", seeded.emp_a, seeded.trab_id)])
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["ya_aplicadas"] == 1
    assert body["aceptadas"] == 0

    db.expire_all()
    fila = db.query(ColaRescate).filter(
        ColaRescate.idempotency_key == "k-aplicada").one()
    assert fila.estado_revision == RescateEstado.YA_APLICADA


def test_audit_por_fila_guardada(client, seeded, db):
    _post(client, seeded, seeded.trab, [_fila("k-audit", seeded.emp_a, seeded.trab_id)])
    db.expire_all()
    entradas = db.query(AuditLog).filter(AuditLog.accion == "rescate_cola").all()
    assert len(entradas) == 1
    e = entradas[0]
    assert e.empresa_id == seeded.emp_a
    assert e.actor_id == seeded.trab_id
    assert e.meta["idempotency_key"] == "k-audit"


def test_limite_de_filas_422(client, seeded):
    filas = [_fila(f"k{i}", seeded.emp_a, seeded.trab_id) for i in range(501)]
    r = _post(client, seeded, seeded.trab, filas)
    assert r.status_code == 422, r.text


def test_limite_de_body_413(client, seeded):
    # Pocas filas pero body > 1 MB (campo extra grande, permitido por extra="allow").
    grande = "x" * 300_000
    filas = [_fila(f"big{i}", seeded.emp_a, seeded.trab_id, relleno=grande)
             for i in range(5)]  # ~1.5 MB, <= 500 filas
    r = _post(client, seeded, seeded.trab, filas)
    assert r.status_code == 413, r.text
