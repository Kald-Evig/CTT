"""test_sync_rechazos.py — CTT-103: dead-letter de rechazos deterministas en /transicion.

Cubre:
  - Persistencia + cuerpo con rechazo_id SOLO con X-Sync-Origen: cola (gate R2).
  - Las dos rutas de I5: TransicionInvalida (409) y 403/404 de acceso.
  - Mensaje uniforme al cliente con la causa exacta oculta en detalle_interno (no oráculo).
  - Pegajosidad por (idempotency_key, usuario_id) — D2: reintento, ítem reasignado, otro usuario.
  - Aislamiento por empresa de las filas.
  - Sin header (o con header pero sin Idempotency-Key) → comportamiento de siempre, sin fila.
"""

import uuid

from app.enums import RechazoMotivo, Rol
from app.models import (
    AuditLog, EmpresaUsuario, Item, ItemHistorial, ProyectoUsuario, SyncRechazo, Usuario,
)


def _h(seeded, uid, key, empresa_id=None):
    h = {
        "Authorization": f"Bearer {uid}",
        "X-Sync-Origen": "cola",
        "Idempotency-Key": key,
    }
    if empresa_id:
        h["X-Empresa-Id"] = empresa_id
    return h


def _post(client, seeded, uid, estado, headers):
    return client.post(
        f"/items/{seeded.item}/transicion",
        json={"nuevo_estado": estado},
        headers=headers,
    )


def _trabajador_miembro_no_asignado(db, seeded):
    """Trabajador de emp_a, miembro activo del proyecto, pero NO asignado al ítem → 403."""
    u = Usuario(firebase_uid="t-trab2", nombre_completo="Trab2", email="trab2@a.cl")
    db.add(u)
    db.flush()
    db.add(EmpresaUsuario(empresa_id=seeded.emp_a, usuario_id=u.id, rol=Rol.TRABAJADOR))
    db.add(ProyectoUsuario(proyecto_id=seeded.proyecto, usuario_id=u.id,
                           rol_en_proyecto=Rol.TRABAJADOR))
    db.commit()
    return u


# ── I5a: TransicionInvalida (409) ────────────────────────────────────────────

def test_transicion_invalida_persiste_rechazo(client, seeded, db):
    # trab está asignado al ítem ABIERTO; ABIERTO -> terminado es inválido → 409.
    r = _post(client, seeded, seeded.trab, "terminado", _h(seeded, seeded.trab, "k-inv"))
    assert r.status_code == 409, r.text
    d = r.json()["detail"]
    assert d["tipo"] == "rechazo"
    assert d["motivo"] == "transicion_invalida"
    assert d["rechazo_id"]
    assert d["mensaje"]

    db.expire_all()
    filas = db.query(SyncRechazo).filter(SyncRechazo.idempotency_key == "k-inv").all()
    assert len(filas) == 1
    f = filas[0]
    assert f.id == d["rechazo_id"]
    assert f.usuario_id == seeded.trab_id
    assert f.empresa_id == seeded.emp_a
    assert f.codigo_http == 409
    assert f.motivo == RechazoMotivo.TRANSICION_INVALIDA
    assert f.tipo_entidad == "item"
    assert f.entidad_id == seeded.item


def test_transicion_invalida_no_deja_cambio_parcial(client, seeded, db):
    # F1c: con origen cola, una transición inválida persiste el rechazo pero NO deja
    # rastro de transición: estado intacto, sin ItemHistorial ni AuditLog del ítem.
    r = _post(client, seeded, seeded.trab, "terminado", _h(seeded, seeded.trab, "k-parcial"))
    assert r.status_code == 409, r.text

    db.expire_all()
    assert db.query(Item).filter(Item.id == seeded.item).one().estado.value == "abierto"
    assert db.query(ItemHistorial).filter(ItemHistorial.item_id == seeded.item).count() == 0
    assert db.query(AuditLog).filter(AuditLog.entidad_id == seeded.item).count() == 0
    assert db.query(SyncRechazo).filter(SyncRechazo.idempotency_key == "k-parcial").count() == 1


def test_reintento_misma_clave_mismo_rechazo_una_fila(client, seeded, db):
    # Con X-Empresa-Id el middleware de idempotencia TAMBIÉN interviene (borra su reserva
    # en 4xx): la pegajosidad del endpoint debe devolver el MISMO rechazo igual.
    h = _h(seeded, seeded.trab, "k-dup", empresa_id=seeded.emp_a)
    r1 = _post(client, seeded, seeded.trab, "terminado", h)
    r2 = _post(client, seeded, seeded.trab, "terminado", h)
    assert r1.status_code == 409 and r2.status_code == 409, (r1.text, r2.text)
    assert r1.json()["detail"]["rechazo_id"] == r2.json()["detail"]["rechazo_id"]

    db.expire_all()
    assert db.query(SyncRechazo).filter(SyncRechazo.idempotency_key == "k-dup").count() == 1


# ── I5b: 403/404 de acceso ───────────────────────────────────────────────────

def test_404_tenant_ajeno_mensaje_uniforme_causa_interna(client, seeded, db):
    # admin_b (emp_b) sobre un ítem de emp_a → 404 con mensaje uniforme.
    r = _post(client, seeded, seeded.admin_b, "en_progreso",
              _h(seeded, seeded.admin_b, "k-404"))
    assert r.status_code == 404, r.text
    d = r.json()["detail"]
    # El cuerpo expone SOLO estas claves: la causa exacta (detalle_interno) no viaja.
    assert set(d.keys()) == {"tipo", "rechazo_id", "motivo", "mensaje"}
    assert d["tipo"] == "rechazo"
    assert d["motivo"] == "inexistente"
    assert d["mensaje"] == "Ítem no encontrado."

    db.expire_all()
    f = db.query(SyncRechazo).filter(SyncRechazo.idempotency_key == "k-404").one()
    assert f.empresa_id == seeded.emp_b
    assert f.usuario_id == seeded.admin_b_id
    assert f.codigo_http == 404
    assert f.motivo == RechazoMotivo.INEXISTENTE
    assert "404" in f.detalle_interno and "Ítem no encontrado." in f.detalle_interno

    # No-oráculo: un item_id inexistente en TODO tenant devuelve el MISMO status y el
    # mismo detail salvo rechazo_id — admin_b no puede distinguir "existe en otra
    # empresa" (seeded.item) de "no existe" (uuid aleatorio).
    r2 = client.post(
        f"/items/{uuid.uuid4()}/transicion",
        json={"nuevo_estado": "en_progreso"},
        headers=_h(seeded, seeded.admin_b, "k-404-inex"),
    )
    assert r2.status_code == r.status_code
    d2 = r2.json()["detail"]
    assert {k: v for k, v in d2.items() if k != "rechazo_id"} == \
           {k: v for k, v in d.items() if k != "rechazo_id"}


def test_403_trabajador_no_asignado_persiste(client, seeded, db):
    u = _trabajador_miembro_no_asignado(db, seeded)
    r = _post(client, seeded, "t-trab2", "en_progreso", _h(seeded, "t-trab2", "k-403"))
    assert r.status_code == 403, r.text
    d = r.json()["detail"]
    assert d["tipo"] == "rechazo"
    assert d["motivo"] == "no_autorizado"
    assert d["rechazo_id"]
    assert d["mensaje"] == "Este ítem no está asignado a usted."

    db.expire_all()
    f = db.query(SyncRechazo).filter(SyncRechazo.idempotency_key == "k-403").one()
    assert f.motivo == RechazoMotivo.NO_AUTORIZADO
    assert f.codigo_http == 403
    assert f.usuario_id == u.id


def test_aislamiento_por_empresa_de_las_filas(client, seeded, db):
    _post(client, seeded, seeded.trab, "terminado", _h(seeded, seeded.trab, "k-a"))
    _post(client, seeded, seeded.admin_b, "en_progreso", _h(seeded, seeded.admin_b, "k-b"))

    db.expire_all()
    fa = db.query(SyncRechazo).filter(SyncRechazo.idempotency_key == "k-a").one()
    fb = db.query(SyncRechazo).filter(SyncRechazo.idempotency_key == "k-b").one()
    assert fa.empresa_id == seeded.emp_a
    assert fb.empresa_id == seeded.emp_b
    assert db.query(SyncRechazo).filter(SyncRechazo.empresa_id == seeded.emp_a).count() == 1
    assert db.query(SyncRechazo).filter(SyncRechazo.empresa_id == seeded.emp_b).count() == 1


# ── Gate R2: sin origen cola, nada cambia ────────────────────────────────────

def test_sin_header_origen_no_persiste_y_cuerpo_igual(client, seeded, db):
    r = client.post(
        f"/items/{seeded.item}/transicion",
        json={"nuevo_estado": "terminado"},
        headers={"Authorization": f"Bearer {seeded.trab}"},
    )
    assert r.status_code == 409, r.text
    assert isinstance(r.json()["detail"], str)   # como hoy: string, no Map
    db.expire_all()
    assert db.query(SyncRechazo).count() == 0


def test_origen_sin_idempotency_key_no_persiste(client, seeded, db):
    r = client.post(
        f"/items/{seeded.item}/transicion",
        json={"nuevo_estado": "terminado"},
        headers={"Authorization": f"Bearer {seeded.trab}", "X-Sync-Origen": "cola"},
    )
    assert r.status_code == 409, r.text
    assert isinstance(r.json()["detail"], str)
    db.expire_all()
    assert db.query(SyncRechazo).count() == 0


# ── D2: pegajosidad ──────────────────────────────────────────────────────────

def test_pegajoso_tras_reasignar_sigue_rechazado(client, seeded, db):
    # D2(b): 403 por no asignado → se asigna el ítem → reintento misma clave → MISMO
    # rechazo, sin aplicar el cambio.
    u = _trabajador_miembro_no_asignado(db, seeded)
    r1 = _post(client, seeded, "t-trab2", "en_progreso", _h(seeded, "t-trab2", "k-reasg"))
    assert r1.status_code == 403, r1.text
    rid = r1.json()["detail"]["rechazo_id"]

    it = db.query(Item).filter(Item.id == seeded.item).one()
    it.asignado_a = u.id
    db.commit()

    r2 = _post(client, seeded, "t-trab2", "en_progreso", _h(seeded, "t-trab2", "k-reasg"))
    assert r2.status_code == 403, r2.text     # sigue el mismo rechazo, no reevalúa
    assert r2.json()["detail"]["rechazo_id"] == rid

    db.expire_all()
    assert db.query(SyncRechazo).filter(SyncRechazo.idempotency_key == "k-reasg").count() == 1
    assert db.query(Item).filter(Item.id == seeded.item).one().estado.value == "abierto"


def test_misma_clave_otro_usuario_no_devuelve_ajeno(client, seeded, db):
    # D2(c): misma clave con OTRO usuario → cada uno su propio rechazo, no el del otro.
    r_trab = _post(client, seeded, seeded.trab, "terminado", _h(seeded, seeded.trab, "k-shared"))
    r_resid = _post(client, seeded, seeded.resid, "terminado", _h(seeded, seeded.resid, "k-shared"))
    assert r_trab.status_code == 409 and r_resid.status_code == 409, (r_trab.text, r_resid.text)
    assert r_trab.json()["detail"]["rechazo_id"] != r_resid.json()["detail"]["rechazo_id"]

    db.expire_all()
    filas = db.query(SyncRechazo).filter(SyncRechazo.idempotency_key == "k-shared").all()
    assert len(filas) == 2
    assert {f.usuario_id for f in filas} == {seeded.trab_id, seeded.resid_id}
