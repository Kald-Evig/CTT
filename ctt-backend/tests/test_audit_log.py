"""
test_audit_log.py — Tests para CTT-48: audit log operativo.

Cubre:
  1. Doble escritura: transición crea entrada en audit_log Y en ItemHistorial.
  2. Las 3 acciones (cambio_estado, cierre_problema, reversion_terminado).
  3. Multi-tenant: empresa A no ve audit_log de empresa B.
  4. Permiso: RESIDENTE recibe 403; COORDINADOR y ADMIN reciben 200.
  5. Filtro por proyecto_id.
  6. Folio correlativo: creciente dentro de empresa, independiente entre empresas.
  7. Actor denormalizado: actor_nombre y actor_rol correctos en la entrada.
"""

from app.enums import ItemEstado, Rol
from app.models import AuditLog, EmpresaUsuario, Item, ItemHistorial, Proyecto, Usuario


def _h(seeded, uid):
    return seeded.headers(uid, seeded.emp_a)


def _hb(seeded, uid):
    return seeded.headers(uid, seeded.emp_b)


def _get_log(client, seeded, uid=None, **params):
    return client.get(
        "/audit-log",
        headers=_h(seeded, uid or seeded.coord),
        params=params,
    )


def _transicion(client, seeded, item_id, nuevo_estado, uid=None):
    return client.post(
        f"/items/{item_id}/transicion",
        json={"nuevo_estado": nuevo_estado},
        headers=_h(seeded, uid or seeded.trab),
    )


# ── 1. Doble escritura ────────────────────────────────────────────────────────

def test_doble_escritura_transicion(client, seeded, db):
    """POST /items/{id}/transicion crea 1 entrada en audit_log Y 1 en ItemHistorial."""
    r = _transicion(client, seeded, seeded.item, "en_progreso")
    assert r.status_code == 200, r.text

    entradas_audit = db.query(AuditLog).filter(
        AuditLog.entidad_id == seeded.item,
        AuditLog.accion == "cambio_estado",
    ).all()
    entradas_hist = db.query(ItemHistorial).filter(
        ItemHistorial.item_id == seeded.item,
        ItemHistorial.accion == "cambio_estado",
    ).all()

    assert len(entradas_audit) == 1, "Esperaba 1 entrada en audit_log"
    assert len(entradas_hist) == 1, "Esperaba 1 entrada en ItemHistorial"

    audit = entradas_audit[0]
    hist = entradas_hist[0]

    # Diff del audit debe coincidir con estado_anterior/nuevo del historial
    assert audit.diff == {"estado": [hist.estado_anterior, hist.estado_nuevo]}
    assert audit.diff["estado"][0] == ItemEstado.ABIERTO.value
    assert audit.diff["estado"][1] == ItemEstado.EN_PROGRESO.value


def test_doble_escritura_diff_exacto(client, seeded, db):
    """El diff registrado en audit_log es {estado: [anterior, nuevo]} exacto."""
    r = _transicion(client, seeded, seeded.item, "en_progreso")
    assert r.status_code == 200, r.text

    audit = db.query(AuditLog).filter(
        AuditLog.entidad_id == seeded.item,
    ).first()

    assert audit is not None
    assert audit.diff == {"estado": ["abierto", "en_progreso"]}


# ── 2. Las 3 acciones ─────────────────────────────────────────────────────────

def test_accion_cambio_estado(client, seeded, db):
    """Transición normal → accion='cambio_estado' en audit_log."""
    _transicion(client, seeded, seeded.item, "en_progreso")

    audit = db.query(AuditLog).filter(
        AuditLog.entidad_id == seeded.item,
        AuditLog.accion == "cambio_estado",
    ).first()
    assert audit is not None
    assert audit.entidad_tipo == "item"
    assert audit.proyecto_id == seeded.proyecto


def test_accion_cierre_problema(client, seeded, db):
    """cerrar-problema → accion='cierre_problema'; diff refleja estado restaurado real."""
    # Llevar ítem a PROBLEMA: abierto → en_progreso → problema
    _transicion(client, seeded, seeded.item, "en_progreso")
    r = client.post(
        f"/items/{seeded.item}/transicion",
        json={"nuevo_estado": "problema", "descripcion_problema": "Falla detectada"},
        headers=_h(seeded, seeded.resid),
    )
    assert r.status_code == 200, r.text

    r = client.post(
        f"/items/{seeded.item}/cerrar-problema",
        headers=_h(seeded, seeded.resid),
    )
    assert r.status_code == 200, r.text

    audit = db.query(AuditLog).filter(
        AuditLog.entidad_id == seeded.item,
        AuditLog.accion == "cierre_problema",
    ).first()
    assert audit is not None
    # estado_previo era en_progreso → diff debe ser [problema, en_progreso]
    assert audit.diff == {"estado": ["problema", "en_progreso"]}


def test_accion_reversion_terminado(client, seeded, db):
    """revertir-terminado → accion='reversion_terminado'; diff [terminado, pendiente_revision]."""
    # Llevar ítem a TERMINADO: en_progreso → pendiente_revision → aprobado/terminado
    _transicion(client, seeded, seeded.item, "en_progreso")
    _transicion(client, seeded, seeded.item, "pendiente_revision")
    r = _transicion(client, seeded, seeded.item, "terminado", uid=seeded.resid)
    assert r.status_code == 200, r.text

    r = client.post(
        f"/items/{seeded.item}/revertir-terminado",
        params={"motivo": "Error en medición"},
        headers=_h(seeded, seeded.admin),
    )
    assert r.status_code == 200, r.text

    audit = db.query(AuditLog).filter(
        AuditLog.entidad_id == seeded.item,
        AuditLog.accion == "reversion_terminado",
    ).first()
    assert audit is not None
    assert audit.diff == {"estado": ["terminado", "pendiente_revision"]}


# ── 3. Multi-tenant ───────────────────────────────────────────────────────────

def test_multitenant_aislamiento(client, seeded, db):
    """Empresa A no ve entradas de empresa B y viceversa."""
    # Actividad en empresa A
    _transicion(client, seeded, seeded.item, "en_progreso")

    # Actividad en empresa B: necesita un TRABAJADOR (iniciar_tarea = {TRABAJADOR})
    trab_b = Usuario(firebase_uid="t-trab-b", nombre_completo="TrabB", email="trab@b.cl")
    db.add(trab_b); db.flush()
    db.add(EmpresaUsuario(empresa_id=seeded.emp_b, usuario_id=trab_b.id, rol=Rol.TRABAJADOR))
    proyecto_b = Proyecto(empresa_id=seeded.emp_b, nombre="Obra B",
                          created_by=seeded.admin_b_id)
    db.add(proyecto_b); db.flush()
    item_b = Item(proyecto_id=proyecto_b.id, nivel_profundidad=0,
                  nombre="Tarea B", asignado_a=trab_b.id,
                  estado=ItemEstado.ABIERTO, created_by=seeded.admin_b_id)
    db.add(item_b); db.commit()

    client.post(
        f"/items/{item_b.id}/transicion",
        json={"nuevo_estado": "en_progreso"},
        headers=seeded.headers(trab_b.firebase_uid, seeded.emp_b),
    )

    # Coord de empresa A solo ve sus propias entradas
    r_a = _get_log(client, seeded)
    assert r_a.status_code == 200, r_a.text
    entidades_a = {e["entidad_id"] for e in r_a.json()}
    assert seeded.item in entidades_a
    assert item_b.id not in entidades_a

    # Admin de empresa B solo ve sus propias entradas
    r_b = client.get("/audit-log", headers=_hb(seeded, seeded.admin_b))
    assert r_b.status_code == 200, r_b.text
    entidades_b = {e["entidad_id"] for e in r_b.json()}
    assert item_b.id in entidades_b
    assert seeded.item not in entidades_b


# ── 4. Permisos ───────────────────────────────────────────────────────────────

def test_residente_recibe_403(client, seeded):
    """RESIDENTE no tiene ver_audit_log → 403."""
    r = client.get("/audit-log", headers=_h(seeded, seeded.resid))
    assert r.status_code == 403, r.text


def test_coordinador_recibe_200(client, seeded):
    """COORDINADOR tiene ver_audit_log → 200."""
    r = _get_log(client, seeded, uid=seeded.coord)
    assert r.status_code == 200, r.text
    assert isinstance(r.json(), list)


def test_admin_recibe_200(client, seeded):
    """ADMIN tiene ver_audit_log → 200."""
    r = _get_log(client, seeded, uid=seeded.admin)
    assert r.status_code == 200, r.text
    assert isinstance(r.json(), list)


# ── 5. Filtro por proyecto_id ─────────────────────────────────────────────────

def test_filtro_proyecto_id(client, seeded, db):
    """?proyecto_id=X devuelve solo entradas de ese proyecto."""
    # Crear segundo proyecto con ítem en la misma empresa A
    proyecto2 = Proyecto(empresa_id=seeded.emp_a, nombre="Obra 2",
                         coordinador_principal_id=seeded.coord_id,
                         created_by=seeded.coord_id)
    db.add(proyecto2); db.flush()
    item2 = Item(proyecto_id=proyecto2.id, nivel_profundidad=0, nombre="Tarea 2",
                 asignado_a=seeded.trab_id, estado=ItemEstado.ABIERTO,
                 created_by=seeded.coord_id)
    db.add(item2); db.commit()

    # Actividad en proyecto original
    _transicion(client, seeded, seeded.item, "en_progreso")
    # Actividad en proyecto 2
    client.post(f"/items/{item2.id}/transicion",
                json={"nuevo_estado": "en_progreso"},
                headers=_h(seeded, seeded.trab))

    # Filtrar por proyecto original
    r = _get_log(client, seeded, proyecto_id=seeded.proyecto)
    assert r.status_code == 200, r.text
    datos = r.json()
    assert len(datos) >= 1
    for e in datos:
        assert e["proyecto_id"] == seeded.proyecto

    # Filtrar por proyecto2
    r2 = _get_log(client, seeded, proyecto_id=proyecto2.id)
    assert r2.status_code == 200, r2.text
    datos2 = r2.json()
    assert len(datos2) >= 1
    for e in datos2:
        assert e["proyecto_id"] == proyecto2.id


# ── 6. Folio correlativo ──────────────────────────────────────────────────────

def test_folio_correlativo_misma_empresa(client, seeded, db):
    """Dos acciones en la misma empresa generan folios crecientes (1, 2)."""
    item2 = Item(proyecto_id=seeded.proyecto, nivel_profundidad=0, nombre="Tarea 2",
                 asignado_a=seeded.trab_id, estado=ItemEstado.ABIERTO,
                 created_by=seeded.coord_id)
    db.add(item2); db.commit()

    _transicion(client, seeded, seeded.item, "en_progreso")
    client.post(f"/items/{item2.id}/transicion",
                json={"nuevo_estado": "en_progreso"},
                headers=_h(seeded, seeded.trab))

    entradas = (
        db.query(AuditLog)
        .filter(AuditLog.empresa_id == seeded.emp_a)
        .order_by(AuditLog.folio)
        .all()
    )
    assert len(entradas) == 2
    assert entradas[0].folio == 1
    assert entradas[1].folio == 2


def test_folio_independiente_entre_empresas(client, seeded, db):
    """Empresa A y empresa B tienen secuencias de folio independientes."""
    trab_b = Usuario(firebase_uid="t-trab-b2", nombre_completo="TrabB2", email="trab2@b.cl")
    db.add(trab_b); db.flush()
    db.add(EmpresaUsuario(empresa_id=seeded.emp_b, usuario_id=trab_b.id, rol=Rol.TRABAJADOR))
    proyecto_b = Proyecto(empresa_id=seeded.emp_b, nombre="Obra B",
                          created_by=seeded.admin_b_id)
    db.add(proyecto_b); db.flush()
    item_b = Item(proyecto_id=proyecto_b.id, nivel_profundidad=0,
                  nombre="Tarea B", asignado_a=trab_b.id,
                  estado=ItemEstado.ABIERTO, created_by=seeded.admin_b_id)
    db.add(item_b); db.commit()

    _transicion(client, seeded, seeded.item, "en_progreso")
    client.post(
        f"/items/{item_b.id}/transicion",
        json={"nuevo_estado": "en_progreso"},
        headers=seeded.headers(trab_b.firebase_uid, seeded.emp_b),
    )

    folio_a = db.query(AuditLog).filter(AuditLog.empresa_id == seeded.emp_a).first().folio
    folio_b = db.query(AuditLog).filter(AuditLog.empresa_id == seeded.emp_b).first().folio

    assert folio_a == 1
    assert folio_b == 1  # secuencia independiente, también empieza en 1


# ── 7. Actor denormalizado ────────────────────────────────────────────────────

def test_actor_nombre_correcto(client, seeded, db):
    """actor_nombre registra el nombre del usuario que ejecutó la acción."""
    _transicion(client, seeded, seeded.item, "en_progreso")  # actor: trab

    audit = db.query(AuditLog).filter(
        AuditLog.entidad_id == seeded.item,
    ).first()
    assert audit is not None
    assert audit.actor_nombre == "Trab"


def test_actor_rol_correcto(client, seeded, db):
    """actor_rol registra el rol del actor en la empresa activa (no el rol de otra empresa)."""
    # Residente hace una transición (marcar_problema, requiere descripcion_problema)
    _transicion(client, seeded, seeded.item, "en_progreso")
    r = client.post(
        f"/items/{seeded.item}/transicion",
        json={"nuevo_estado": "problema", "descripcion_problema": "Falla en medición"},
        headers=_h(seeded, seeded.resid),
    )
    assert r.status_code == 200, r.text

    audit = db.query(AuditLog).filter(
        AuditLog.entidad_id == seeded.item,
        AuditLog.accion == "cambio_estado",
        AuditLog.actor_rol == Rol.RESIDENTE.value,
    ).first()
    assert audit is not None
    assert audit.actor_nombre == "Resid"
    assert audit.actor_rol == "residente"


def test_actor_rol_coordinador(client, seeded, db):
    """Cuando el coordinador cierra un problema, actor_rol='coordinador'."""
    _transicion(client, seeded, seeded.item, "en_progreso")
    client.post(
        f"/items/{seeded.item}/transicion",
        json={"nuevo_estado": "problema", "descripcion_problema": "Falla detectada"},
        headers=_h(seeded, seeded.resid),
    )
    r = client.post(
        f"/items/{seeded.item}/cerrar-problema",
        headers=_h(seeded, seeded.coord),
    )
    assert r.status_code == 200, r.text

    audit = db.query(AuditLog).filter(
        AuditLog.entidad_id == seeded.item,
        AuditLog.accion == "cierre_problema",
    ).first()
    assert audit is not None
    assert audit.actor_rol == "coordinador"
    assert audit.actor_nombre == "Coord"


# ── 8. Filtro por accion ──────────────────────────────────────────────────────

def test_filtro_accion_edicion_datos(client, seeded):
    """?entidad_id=X&accion=edicion_datos devuelve solo ediciones, no cambios de estado."""
    # Genera un cambio_estado
    _transicion(client, seeded, seeded.item, "en_progreso")
    # Genera un edicion_datos
    client.put(
        f"/items/{seeded.item}",
        json={"nombre": "Tarea Editada"},
        headers=_h(seeded, seeded.coord),
    )

    r = _get_log(client, seeded,
                 entidad_id=seeded.item, accion="edicion_datos")
    assert r.status_code == 200, r.text
    datos = r.json()

    assert len(datos) == 1
    assert datos[0]["accion"] == "edicion_datos"
    assert datos[0]["entidad_id"] == seeded.item


def test_filtro_accion_excluye_otras(client, seeded):
    """?accion=edicion_datos no devuelve cambio_estado aunque existan para el mismo ítem."""
    # Solo una transición, sin edición
    _transicion(client, seeded, seeded.item, "en_progreso")

    r = _get_log(client, seeded,
                 entidad_id=seeded.item, accion="edicion_datos")
    assert r.status_code == 200, r.text
    assert r.json() == []
