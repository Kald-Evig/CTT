"""
test_idempotencia.py — Middleware de idempotencia (CTT-105).

Se ejercita sobre POST /items/{id}/transicion (el ítem sembrado está ABIERTO y
asignado al trabajador, así que abierto→en_progreso es válido para `trab`).
"""

from app.enums import IdempotenciaEstado, ItemEstado
from app.models import AuditLog, ClaveIdempotencia, Item


def _headers_key(seeded, uid, empresa_id, key):
    h = seeded.headers(uid, empresa_id)
    h["Idempotency-Key"] = key
    return h


# 1 — NO-REGRESIÓN: sin header, el endpoint se comporta como antes.
def test_sin_header_comportamiento_normal(client, seeded, db):
    r = client.post(
        f"/items/{seeded.item}/transicion",
        json={"nuevo_estado": "en_progreso"},
        headers=seeded.headers(seeded.trab, seeded.emp_a),
    )
    assert r.status_code == 200, r.text
    db.expire_all()
    item = db.query(Item).filter_by(id=seeded.item).one()
    assert item.estado == ItemEstado.EN_PROGRESO
    # Sin Idempotency-Key el middleware no toca la tabla.
    assert db.query(ClaveIdempotencia).count() == 0


# 2 — FUNCIONALIDAD: misma clave + mismo body, dos veces → la 2da es replay.
def test_misma_clave_mismo_body_replay(client, seeded, db):
    h = _headers_key(seeded, seeded.trab, seeded.emp_a, "k-replay")
    payload = {"nuevo_estado": "en_progreso"}

    r1 = client.post(f"/items/{seeded.item}/transicion", json=payload, headers=h)
    assert r1.status_code == 200, r1.text
    assert "idempotent-replayed" not in {k.lower() for k in r1.headers}

    r2 = client.post(f"/items/{seeded.item}/transicion", json=payload, headers=h)
    assert r2.status_code == 200, r2.text
    assert r2.headers.get("Idempotent-Replayed") == "true"
    assert r2.json() == r1.json()  # misma respuesta, servida desde caché

    db.expire_all()
    # El estado del ítem cambió UNA sola vez.
    item = db.query(Item).filter_by(id=seeded.item).one()
    assert item.estado == ItemEstado.EN_PROGRESO
    # UNA entrada de audit_log de cambio_estado, no dos.
    n_audit = (
        db.query(AuditLog)
        .filter_by(entidad_id=seeded.item, accion="cambio_estado")
        .count()
    )
    assert n_audit == 1
    # La clave quedó completada.
    ci = db.query(ClaveIdempotencia).filter_by(idempotency_key="k-replay").one()
    assert ci.estado == IdempotenciaEstado.COMPLETADO
    assert ci.status_code == 200


# 3 — misma clave + body distinto → 422, sin ejecutar.
def test_misma_clave_body_distinto_422(client, seeded, db):
    h = _headers_key(seeded, seeded.trab, seeded.emp_a, "k-distinto")

    r1 = client.post(
        f"/items/{seeded.item}/transicion",
        json={"nuevo_estado": "en_progreso"},
        headers=h,
    )
    assert r1.status_code == 200, r1.text

    r2 = client.post(
        f"/items/{seeded.item}/transicion",
        json={"nuevo_estado": "problema", "descripcion_problema": "otra cosa"},
        headers=h,
    )
    assert r2.status_code == 422, r2.text

    db.expire_all()
    item = db.query(Item).filter_by(id=seeded.item).one()
    assert item.estado == ItemEstado.EN_PROGRESO  # el 2do no ejecutó


# 4 — CONTROL: scope por empresa a nivel de MODELO (no de endpoint).
def test_scope_empresa_nivel_modelo(db, seeded):
    db.add(ClaveIdempotencia(
        empresa_id=seeded.emp_a, idempotency_key="misma-clave",
        endpoint="/x", fingerprint="f"))
    db.add(ClaveIdempotencia(
        empresa_id=seeded.emp_b, idempotency_key="misma-clave",
        endpoint="/x", fingerprint="f"))
    db.commit()  # no debe violar el UNIQUE(empresa_id, idempotency_key)
    n = db.query(ClaveIdempotencia).filter_by(idempotency_key="misma-clave").count()
    assert n == 2


# 5 — CONTROL: no-2xx no persiste reserva y el mismo request es reintentable.
def test_no_2xx_no_persiste_y_reintentable(client, seeded, db):
    h = _headers_key(seeded, seeded.trab, seeded.emp_a, "k-409")
    # abierto → terminado es una transición inválida → 409 de la máquina de estados.
    payload = {"nuevo_estado": "terminado"}

    r1 = client.post(f"/items/{seeded.item}/transicion", json=payload, headers=h)
    assert r1.status_code == 409, r1.text
    db.expire_all()
    assert db.query(ClaveIdempotencia).filter_by(idempotency_key="k-409").count() == 0

    # Reintento con la misma clave: la reserva se re-crea y se vuelve a borrar.
    r2 = client.post(f"/items/{seeded.item}/transicion", json=payload, headers=h)
    assert r2.status_code == 409, r2.text
    db.expire_all()
    assert db.query(ClaveIdempotencia).filter_by(idempotency_key="k-409").count() == 0

    item = db.query(Item).filter_by(id=seeded.item).one()
    assert item.estado == ItemEstado.ABIERTO  # nunca cambió
