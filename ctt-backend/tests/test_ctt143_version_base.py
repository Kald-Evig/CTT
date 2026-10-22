"""
test_ctt143_version_base.py — CTT-143 (D7/P5/D5/D9/D4) B2.

La precondición de conflicto de /items/{id}/transicion pasa de device_timestamp a
version_base:

  - D7: version_base es OBLIGATORIO; si falta → 422 (desde la cola, rechazo con rechazo_id).
  - P5: version_base > versión actual → 422 (idem).
  - D9: entre version_base y la versión actual, una transición de OTRO actor (o un
        cierre_problema/reversion_terminado/resolucion_conflicto) genera conflicto (409
        con eventos_no_vistos); una edición de datos/asignación o una transición del
        propio usuario son benignas (no hay conflicto).
  - D4: un reintento con la misma idempotency_key reusa el mismo conflicto_id.
"""

from app.enums import ConflictoEstado, RechazoMotivo
from app.models import SyncConflicto, SyncRechazo


def _conflicto_pendiente(db, item_id, usuario_id, dispositivo_id="disp-1"):
    """Siembra un SyncConflicto PENDIENTE (como el que deja el 409) y devuelve su id."""
    c = SyncConflicto(
        item_id=item_id,
        cambio_local={"estado": "problema"},
        cambio_servidor={"estado": "abierto", "version": 1, "eventos_no_vistos": []},
        dispositivo_id=dispositivo_id, usuario_id=usuario_id,
    )
    db.add(c)
    db.commit()
    return c.id


def _cola(seeded, uid, key):
    """Headers de un comando venido de la cola offline (origen cola + clave)."""
    return {
        "Authorization": f"Bearer {uid}",
        "X-Sync-Origen": "cola",
        "Idempotency-Key": key,
    }


def _transicion(client, seeded, uid, estado, version_base, **extra):
    """POST online (con empresa explícita) de una transición sobre el ítem sembrado."""
    return client.post(
        f"/items/{seeded.item}/transicion",
        json={"nuevo_estado": estado, "version_base": version_base, **extra},
        headers=seeded.headers(uid, seeded.emp_a),
    )


def _llevar_a_terminado(client, seeded):
    """Secuencia válida que deja al ítem en TERMINADO v4: trab en_progreso (v2),
    trab pendiente_revision (v3), resid aprueba terminado (v4, cambio_estado AJENO)."""
    _transicion(client, seeded, seeded.trab, "en_progreso", 1)
    _transicion(client, seeded, seeded.trab, "pendiente_revision", 2)
    _transicion(client, seeded, seeded.resid, "terminado", 3)


# ── D7: version_base obligatorio ──────────────────────────────────────────────

def test_sin_version_base_desde_cola_es_422_con_rechazo_id(client, seeded, db):
    r = client.post(
        f"/items/{seeded.item}/transicion",
        json={"nuevo_estado": "en_progreso"},   # sin version_base
        headers=_cola(seeded, seeded.trab, "k-novb"),
    )
    assert r.status_code == 422, r.text
    d = r.json()["detail"]
    assert d["tipo"] == "rechazo"
    assert d["motivo"] == "version_invalida"
    assert d["rechazo_id"]

    db.expire_all()
    f = db.query(SyncRechazo).filter_by(idempotency_key="k-novb").one()
    assert f.id == d["rechazo_id"]
    assert f.codigo_http == 422
    assert f.motivo == RechazoMotivo.VERSION_INVALIDA


def test_sin_version_base_online_es_422_sin_rechazo(client, seeded, db):
    r = client.post(
        f"/items/{seeded.item}/transicion",
        json={"nuevo_estado": "en_progreso"},
        headers={"Authorization": f"Bearer {seeded.trab}"},
    )
    assert r.status_code == 422, r.text
    assert isinstance(r.json()["detail"], str)   # fuera de la cola: 422 plano, sin fila
    db.expire_all()
    assert db.query(SyncRechazo).count() == 0


# ── P5: version_base del "futuro" ─────────────────────────────────────────────

def test_version_base_mayor_que_actual_desde_cola_es_422_con_rechazo_id(client, seeded, db):
    r = client.post(
        f"/items/{seeded.item}/transicion",
        json={"nuevo_estado": "en_progreso", "version_base": 999},
        headers=_cola(seeded, seeded.trab, "k-futura"),
    )
    assert r.status_code == 422, r.text
    d = r.json()["detail"]
    assert d["rechazo_id"]
    assert d["motivo"] == "version_invalida"
    db.expire_all()
    assert db.query(SyncRechazo).filter_by(idempotency_key="k-futura").count() == 1


# ── D9: clasificación benigno vs conflicto ────────────────────────────────────

def test_edicion_de_otro_usuario_no_genera_conflicto(client, seeded, db):
    # coord edita el ítem (edicion_datos, v1 -> v2). trab transiciona con version_base=1:
    # el evento intermedio es una edición de datos (benigna) -> NO hay conflicto.
    re = client.put(
        f"/items/{seeded.item}",
        json={"nombre": "Reeditado por coord"},
        headers=seeded.headers(seeded.coord, seeded.emp_a),
    )
    assert re.status_code == 200, re.text

    r = _transicion(client, seeded, seeded.trab, "en_progreso", 1)
    assert r.status_code == 200, r.text
    assert r.json()["estado"] == "en_progreso"
    db.expire_all()
    assert db.query(SyncConflicto).count() == 0


def test_transicion_propia_rebaseada_no_genera_conflicto(client, seeded, db):
    # D9 (10495): el envío serial con rebase NO genera conflicto. trab en_progreso (v1->v2);
    # el 200 devuelve version=2; trab rebasa y manda la siguiente con version_base=2 (la
    # versión resultante). El tramo (2,2] queda vacío -> sin conflicto.
    # Arma: una 1ra transición REAL cuyo 200 expone version=2. Verifica: la 2da con esa
    # versión da 200 y no deja conflicto (el código evalúa _hay_conflicto sobre tramo vacío).
    r1 = _transicion(client, seeded, seeded.trab, "en_progreso", 1)
    assert r1.status_code == 200, r1.text
    v = r1.json()["version"]
    assert v == 2

    r2 = _transicion(client, seeded, seeded.trab, "pendiente_revision", v)
    assert r2.status_code == 200, r2.text
    db.expire_all()
    assert db.query(SyncConflicto).count() == 0


def test_transicion_propia_con_version_base_vencido_es_409(client, seeded, db):
    # D9 (10495): SIN exención por usuario. trab en_progreso (v1->v2); luego trab, desde la
    # cola, con version_base=1 VENCIDO (rebase fallido): su PROPIO cambio_estado quedó en el
    # tramo (1,2] y ahora ES conflicto.
    # Arma: una transición propia real que deja un cambio_estado del trab en el tramo, y una
    # 2da con base vencida. Verifica: 409 con eventos_no_vistos que incluye SU propio cambio.
    r1 = _transicion(client, seeded, seeded.trab, "en_progreso", 1)
    assert r1.status_code == 200, r1.text

    r2 = client.post(
        f"/items/{seeded.item}/transicion",
        json={"nuevo_estado": "pendiente_revision", "version_base": 1},
        headers=_cola(seeded, seeded.trab, "k-vencido"),
    )
    assert r2.status_code == 409, r2.text
    d = r2.json()["detail"]
    assert d["tipo"] == "conflicto_concurrencia"
    assert d["version_actual"] == 2
    eventos = [(e["accion"], e["usuario"]) for e in d["eventos_no_vistos"]]
    assert ("cambio_estado", seeded.trab_id) in eventos   # su PROPIO cambio, igual conflicto
    db.expire_all()
    assert db.query(SyncConflicto).filter_by(item_id=seeded.item).count() == 1


def test_mismo_usuario_otro_dispositivo_base_vencida_es_409(client, seeded, db):
    # D9 (10495): tampoco hay exención por instalación. trab inicia desde el dispositivo A
    # (en_progreso, v2). Luego trab, desde OTRO dispositivo (dispositivo-B) y con base
    # vencida, intenta otra transición.
    # Arma: una transición propia real (deja cambio_estado en el tramo) y una 2da desde otro
    # dispositivo_id con base vencida. Verifica: 409 y que el conflicto registra el dispositivo B.
    r1 = _transicion(client, seeded, seeded.trab, "en_progreso", 1)
    assert r1.status_code == 200, r1.text

    r2 = client.post(
        f"/items/{seeded.item}/transicion",
        json={"nuevo_estado": "pendiente_revision", "version_base": 1,
              "dispositivo_id": "dispositivo-B"},
        headers=_cola(seeded, seeded.trab, "k-dispB"),
    )
    assert r2.status_code == 409, r2.text
    assert r2.json()["detail"]["tipo"] == "conflicto_concurrencia"
    db.expire_all()
    c = db.query(SyncConflicto).filter_by(item_id=seeded.item).one()
    assert c.dispositivo_id == "dispositivo-B"


def test_transicion_ajena_es_409_con_eventos_no_vistos(client, seeded, db):
    _llevar_a_terminado(client, seeded)   # resid aprobó en v4 (cambio_estado ajeno a trab)

    # trab, desde la cola, con version_base=3 (antes de la aprobación ajena). El conflicto
    # se detecta ANTES de la máquina de estados, así que el nuevo_estado da igual.
    r = client.post(
        f"/items/{seeded.item}/transicion",
        json={"nuevo_estado": "en_progreso", "version_base": 3},
        headers=_cola(seeded, seeded.trab, "k-ajena"),
    )
    assert r.status_code == 409, r.text
    d = r.json()["detail"]
    assert d["tipo"] == "conflicto_concurrencia"
    assert d["conflicto_id"]
    assert d["version_actual"] == 4
    assert d["estado_servidor"] == "terminado"
    eventos = [(e["accion"], e["usuario"], e["rol"], e["version"]) for e in d["eventos_no_vistos"]]
    assert ("cambio_estado", seeded.resid_id, "residente", 4) in eventos

    db.expire_all()
    assert db.query(SyncConflicto).filter_by(item_id=seeded.item).count() == 1


# ── D4: idempotencia del conflicto ────────────────────────────────────────────

def test_reintento_misma_clave_mismo_conflicto_id_una_fila(client, seeded, db):
    _llevar_a_terminado(client, seeded)
    h = _cola(seeded, seeded.trab, "k-dup")
    body = {"nuevo_estado": "en_progreso", "version_base": 3}

    r1 = client.post(f"/items/{seeded.item}/transicion", json=body, headers=h)
    assert r1.status_code == 409, r1.text
    r2 = client.post(f"/items/{seeded.item}/transicion", json=body, headers=h)
    assert r2.status_code == 409, r2.text

    assert r1.json()["detail"]["conflicto_id"] == r2.json()["detail"]["conflicto_id"]
    db.expire_all()
    assert db.query(SyncConflicto).filter_by(item_id=seeded.item).count() == 1


# ── B3: estado SUPERADO (21-oct) ──────────────────────────────────────────────

def test_transicion_propia_posterior_marca_conflicto_superado(client, seeded, db):
    # trab tiene un conflicto PENDIENTE; luego aplica una transición válida sobre el ítem.
    cid = _conflicto_pendiente(db, seeded.item, seeded.trab_id)

    r = _transicion(client, seeded, seeded.trab, "en_progreso", 1)
    assert r.status_code == 200, r.text

    db.expire_all()
    assert db.get(SyncConflicto, cid).estado == ConflictoEstado.SUPERADO

    # La bandeja del Coordinador (GET /sync/conflictos, default PENDIENTE) ya no lo muestra.
    rb = client.get("/sync/conflictos", headers=seeded.headers(seeded.coord, seeded.emp_a))
    assert rb.status_code == 200, rb.text
    assert all(x["id"] != cid for x in rb.json())


def test_transicion_no_supera_conflicto_de_otro_usuario(client, seeded, db):
    # El conflicto es del RESIDENTE; una transición del TRABAJADOR no lo toca.
    cid = _conflicto_pendiente(db, seeded.item, seeded.resid_id, dispositivo_id="disp-r")

    r = _transicion(client, seeded, seeded.trab, "en_progreso", 1)
    assert r.status_code == 200, r.text

    db.expire_all()
    assert db.get(SyncConflicto, cid).estado == ConflictoEstado.PENDIENTE


# ── B4: version capturada / resultante en la resolución ───────────────────────

def _conflicto_via_409(client, seeded):
    """Genera un conflicto REAL (409) de trab y devuelve su conflicto_id. El ítem queda
    TERMINADO v4 y el conflicto trae version_capturada=4 (lo setea el endpoint)."""
    _llevar_a_terminado(client, seeded)
    r = client.post(
        f"/items/{seeded.item}/transicion",
        json={"nuevo_estado": "en_progreso", "version_base": 3},
        headers=_cola(seeded, seeded.trab, "k-b4"),
    )
    assert r.status_code == 409, r.text
    return r.json()["detail"]["conflicto_id"]


def test_resolucion_local_valida_setea_resultantes(client, seeded, db):
    cid = _conflicto_via_409(client, seeded)   # item en v4, version_capturada=4

    # El ítem no se movió: resolver 'local' aplica el cambio en disputa (en_progreso, v5).
    r = client.post(
        f"/sync/conflictos/{cid}/resolver",
        json={"version_ganadora": "local"},
        headers=seeded.headers(seeded.coord, seeded.emp_a),
    )
    assert r.status_code == 200, r.text

    db.expire_all()
    c = db.get(SyncConflicto, cid)
    assert c.estado == ConflictoEstado.RESUELTO
    assert c.version_resultante == 5
    assert c.estado_resultante == "en_progreso"

    # ConflictoMioOut (pull de reconciliación del cliente) expone los resultantes (P6).
    rm = client.get("/sync/conflictos/mios", headers=seeded.headers(seeded.trab, seeded.emp_a))
    assert rm.status_code == 200, rm.text
    fila = next(x for x in rm.json() if x["id"] == cid)
    assert fila["version_resultante"] == 5
    assert fila["estado_resultante"] == "en_progreso"


def test_resolucion_local_obsoleta_es_409_sin_escribir(client, seeded, db):
    cid = _conflicto_via_409(client, seeded)   # version_capturada=4, ítem TERMINADO v4

    # El ítem avanza por otra vía: el admin revierte el terminado (→ pendiente_revision, v5).
    rv = client.post(
        f"/items/{seeded.item}/revertir-terminado",
        params={"motivo": "Rehacer medición"},
        headers=seeded.headers(seeded.admin, seeded.emp_a),
    )
    assert rv.status_code == 200, rv.text

    # Resolver 'local' ahora es OBSOLETO (v5 != v4 capturada) → 409, sin resolver ni escribir.
    r = client.post(
        f"/sync/conflictos/{cid}/resolver",
        json={"version_ganadora": "local"},
        headers=seeded.headers(seeded.coord, seeded.emp_a),
    )
    assert r.status_code == 409, r.text

    db.expire_all()
    c = db.get(SyncConflicto, cid)
    assert c.estado == ConflictoEstado.PENDIENTE
    assert c.version_resultante is None


# ── B5b: SUPERADO visible en /conflictos/mios (21-oct) ────────────────────────

def test_superado_aparece_en_mios(client, seeded, db):
    # trab tiene un conflicto PENDIENTE; luego aplica una transición → SUPERADO. El
    # reconciliador del cliente debe verlo en /mios para desbloquear la fila local.
    # Arma: un conflicto PENDIENTE de trab + una transición válida de trab (lo marca
    # superado). Verifica: /mios de trab lo lista con estado "superado".
    cid = _conflicto_pendiente(db, seeded.item, seeded.trab_id)
    r = _transicion(client, seeded, seeded.trab, "en_progreso", 1)
    assert r.status_code == 200, r.text

    rm = client.get("/sync/conflictos/mios", headers=seeded.headers(seeded.trab, seeded.emp_a))
    assert rm.status_code == 200, rm.text
    fila = next(x for x in rm.json() if x["id"] == cid)
    assert fila["estado"] == "superado"


def test_mios_no_muestra_superado_de_otro_usuario(client, seeded, db):
    # Un SUPERADO del RESIDENTE no aparece en el /mios del TRABAJADOR (filtro por usuario),
    # pero SÍ en el del residente (control positivo).
    c = SyncConflicto(
        item_id=seeded.item, cambio_local={"estado": "problema"},
        cambio_servidor={"estado": "abierto"}, dispositivo_id="dev-r",
        usuario_id=seeded.resid_id, estado=ConflictoEstado.SUPERADO,
    )
    db.add(c)
    db.commit()
    cid = c.id

    rm_trab = client.get("/sync/conflictos/mios",
                         headers=seeded.headers(seeded.trab, seeded.emp_a))
    assert rm_trab.status_code == 200, rm_trab.text
    assert all(x["id"] != cid for x in rm_trab.json())

    rm_resid = client.get("/sync/conflictos/mios",
                          headers=seeded.headers(seeded.resid, seeded.emp_a))
    assert rm_resid.status_code == 200, rm_resid.text
    assert any(x["id"] == cid and x["estado"] == "superado" for x in rm_resid.json())
