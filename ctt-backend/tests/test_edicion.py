"""
test_edicion.py — Tests para CTT-43: PUT /proyectos/{id} y PUT /items/{id}.

Cubre:
  1. Campo cambia → respuesta correcta + audit con diff exacto.
  2. exclude_unset: campo enviado no toca los demás.
  3. Mismo valor enviado → diff vacío → sin audit.
  4. PUT /items: 409 si el ítem está TERMINADO; ítem no se muta.
  5. Edición válida en estados no-terminados (ABIERTO, EN_PROGRESO).
  6. extra='forbid': campo no editable (estado, proyecto_id) → 422.
  7. Campo NOT NULL con null → 422.
  8. Campo nullable con null → se borra (200).
  9. Permisos: TRABAJADOR y RESIDENTE → 403.
  10. Multi-tenant: otra empresa → 404.
  11. Regresión: GET /items devuelve duracion_estimada_horas y orden reales.
"""

from app.models import AuditLog, Item


# ── Helpers ───────────────────────────────────────────────────────────────────

def _h(seeded, uid):
    return seeded.headers(uid, seeded.emp_a)


def _put_proyecto(client, seeded, proyecto_id, payload, uid=None):
    return client.put(
        f"/proyectos/{proyecto_id}",
        json=payload,
        headers=_h(seeded, uid or seeded.coord),
    )


def _put_item(client, seeded, item_id, payload, uid=None):
    return client.put(
        f"/items/{item_id}",
        json=payload,
        headers=_h(seeded, uid or seeded.coord),
    )


def _llevar_a_terminado(client, seeded, item_id):
    """Lleva un ítem ABIERTO a TERMINADO en tres transiciones."""
    client.post(f"/items/{item_id}/transicion",
                json={"nuevo_estado": "en_progreso"},
                headers=_h(seeded, seeded.trab))
    client.post(f"/items/{item_id}/transicion",
                json={"nuevo_estado": "pendiente_revision"},
                headers=_h(seeded, seeded.trab))
    client.post(f"/items/{item_id}/transicion",
                json={"nuevo_estado": "terminado"},
                headers=_h(seeded, seeded.resid))


# ── 1. Campo cambia: respuesta correcta + audit con diff exacto ───────────────

def test_put_proyecto_cambia_nombre_en_respuesta(client, seeded):
    """PUT /proyectos/{id} actualiza el campo y lo refleja en el JSON de respuesta."""
    r = _put_proyecto(client, seeded, seeded.proyecto, {"nombre": "Obra Editada"})
    assert r.status_code == 200, r.text
    assert r.json()["nombre"] == "Obra Editada"


def test_put_proyecto_audit_diff_exacto(client, seeded, db):
    """El audit registra diff {campo: [anterior, nuevo]} con los valores reales."""
    _put_proyecto(client, seeded, seeded.proyecto, {"nombre": "Obra Editada"})

    audit = db.query(AuditLog).filter(
        AuditLog.entidad_id == seeded.proyecto,
        AuditLog.accion == "edicion_datos",
        AuditLog.entidad_tipo == "proyecto",
    ).first()

    assert audit is not None
    assert audit.diff == {"nombre": ["Obra A", "Obra Editada"]}
    assert audit.proyecto_id == seeded.proyecto


def test_put_item_cambia_campos_y_audit(client, seeded, db):
    """PUT /items/{id} actualiza múltiples campos y el diff solo incluye los cambiados."""
    r = _put_item(client, seeded, seeded.item,
                  {"nombre": "Tarea Editada", "orden": 5})
    assert r.status_code == 200, r.text
    assert r.json()["nombre"] == "Tarea Editada"
    assert r.json()["orden"] == 5

    audit = db.query(AuditLog).filter(
        AuditLog.entidad_id == seeded.item,
        AuditLog.accion == "edicion_datos",
        AuditLog.entidad_tipo == "item",
    ).first()

    assert audit is not None
    # seeded.item tiene nombre="Tarea raíz" y orden=0
    assert audit.diff == {"nombre": ["Tarea raíz", "Tarea Editada"], "orden": [0, 5]}
    assert audit.proyecto_id == seeded.proyecto


# ── 2. exclude_unset: campo no enviado no se toca ────────────────────────────

def test_put_proyecto_exclude_unset_no_toca_descripcion(client, seeded):
    """Enviar solo nombre no modifica descripcion."""
    pid = client.post(
        "/proyectos",
        json={"nombre": "Proyecto Base", "descripcion": "Descripción original",
              "coordinador_principal_id": seeded.coord_id},
        headers=_h(seeded, seeded.coord),
    ).json()["id"]

    r = _put_proyecto(client, seeded, pid, {"nombre": "Nombre Nuevo"})
    assert r.status_code == 200, r.text
    assert r.json()["nombre"] == "Nombre Nuevo"
    assert r.json()["descripcion"] == "Descripción original"


def test_put_item_exclude_unset_no_toca_duracion(client, seeded):
    """Enviar solo nombre no modifica duracion_estimada_horas."""
    iid = client.post(
        "/items",
        json={"proyecto_id": seeded.proyecto, "nombre": "Ítem Base",
              "duracion_estimada_horas": 4.0},
        headers=_h(seeded, seeded.coord),
    ).json()["id"]

    r = _put_item(client, seeded, iid, {"nombre": "Nombre Nuevo"})
    assert r.status_code == 200, r.text
    assert r.json()["nombre"] == "Nombre Nuevo"
    assert r.json()["duracion_estimada_horas"] == 4.0


# ── 3. Mismo valor → diff vacío → sin audit ───────────────────────────────────

def test_put_proyecto_mismo_valor_no_genera_audit(client, seeded, db):
    """Enviar el valor actual → diff vacío → NO se crea entrada en audit_log."""
    r = _put_proyecto(client, seeded, seeded.proyecto, {"nombre": "Obra A"})
    assert r.status_code == 200, r.text

    audit = db.query(AuditLog).filter(
        AuditLog.entidad_id == seeded.proyecto,
        AuditLog.accion == "edicion_datos",
    ).first()
    assert audit is None


def test_put_item_mismo_valor_no_genera_audit(client, seeded, db):
    """Enviar el nombre actual del ítem → sin audit."""
    r = _put_item(client, seeded, seeded.item, {"nombre": "Tarea raíz"})
    assert r.status_code == 200, r.text

    audit = db.query(AuditLog).filter(
        AuditLog.entidad_id == seeded.item,
        AuditLog.accion == "edicion_datos",
    ).first()
    assert audit is None


# ── 4. PUT /items: 409 si TERMINADO; ítem no se muta ─────────────────────────

def test_put_item_terminado_devuelve_409(client, seeded):
    """PUT /items/{id} → 409 cuando el ítem está TERMINADO."""
    _llevar_a_terminado(client, seeded, seeded.item)

    r = _put_item(client, seeded, seeded.item, {"nombre": "Intento fallido"})
    assert r.status_code == 409, r.text


def test_put_item_terminado_no_muta_nombre(client, seeded, db):
    """El 409 ocurre antes de cualquier mutación; el nombre permanece intacto."""
    _llevar_a_terminado(client, seeded, seeded.item)
    _put_item(client, seeded, seeded.item, {"nombre": "Intento fallido"})

    item = db.get(Item, seeded.item)
    assert item.nombre == "Tarea raíz"


# ── 5. Edición válida en estados no-terminados ────────────────────────────────

def test_put_item_edicion_abierto_200(client, seeded):
    """Ítem en estado ABIERTO puede editarse."""
    r = _put_item(client, seeded, seeded.item, {"nombre": "Tarea Renombrada"})
    assert r.status_code == 200, r.text
    assert r.json()["nombre"] == "Tarea Renombrada"


def test_put_item_edicion_en_progreso_200(client, seeded):
    """Ítem en estado EN_PROGRESO también puede editarse."""
    client.post(f"/items/{seeded.item}/transicion",
                json={"nuevo_estado": "en_progreso"},
                headers=_h(seeded, seeded.trab))

    r = _put_item(client, seeded, seeded.item, {"nombre": "En progreso editado"})
    assert r.status_code == 200, r.text
    assert r.json()["nombre"] == "En progreso editado"


# ── 6. extra='forbid': campo no editable → 422 ───────────────────────────────

def test_put_proyecto_campo_estado_forbid_422(client, seeded):
    """Enviar 'estado' al PUT proyecto → 422 (extra='forbid')."""
    r = _put_proyecto(client, seeded, seeded.proyecto, {"estado": "cerrado"})
    assert r.status_code == 422, r.text


def test_put_item_campo_estado_forbid_422(client, seeded):
    """Enviar 'estado' al PUT ítem → 422 (extra='forbid')."""
    r = _put_item(client, seeded, seeded.item, {"estado": "terminado"})
    assert r.status_code == 422, r.text


def test_put_item_campo_proyecto_id_forbid_422(client, seeded):
    """Enviar 'proyecto_id' al PUT ítem → 422 (extra='forbid')."""
    r = _put_item(client, seeded, seeded.item, {"proyecto_id": "otro-id"})
    assert r.status_code == 422, r.text


def test_put_item_campo_asignado_a_forbid_422(client, seeded):
    """Enviar 'asignado_a' al PUT ítem → 422 (extra='forbid').

    Fija el supuesto: asignado_a NO está en ItemUpdate. Si alguien lo agrega al schema,
    este test rompe — recordatorio de que abriría un tercer camino de asignación que
    debe pasar por _validar_asignatario_trabajador y _validar_asignatario_miembro
    (CTT-96), igual que crear_item y POST /asignar.
    """
    r = _put_item(client, seeded, seeded.item, {"asignado_a": seeded.trab_id})
    assert r.status_code == 422, r.text


# ── 7. NOT NULL con null → 422 ────────────────────────────────────────────────

def test_put_proyecto_nombre_null_422(client, seeded):
    """{'nombre': null} → 422; nombre es NOT NULL."""
    r = _put_proyecto(client, seeded, seeded.proyecto, {"nombre": None})
    assert r.status_code == 422, r.text


def test_put_item_nombre_null_422(client, seeded):
    """{'nombre': null} → 422; nombre es NOT NULL."""
    r = _put_item(client, seeded, seeded.item, {"nombre": None})
    assert r.status_code == 422, r.text


def test_put_item_orden_null_422(client, seeded):
    """{'orden': null} → 422; orden es NOT NULL."""
    r = _put_item(client, seeded, seeded.item, {"orden": None})
    assert r.status_code == 422, r.text


# ── 8. Nullable con null → se borra (200) ────────────────────────────────────

def test_put_proyecto_descripcion_null_borra(client, seeded):
    """{'descripcion': null} sobre campo nullable → se borra, respuesta 200."""
    pid = client.post(
        "/proyectos",
        json={"nombre": "Proyecto Con Desc", "descripcion": "Desc temporal",
              "coordinador_principal_id": seeded.coord_id},
        headers=_h(seeded, seeded.coord),
    ).json()["id"]

    r = _put_proyecto(client, seeded, pid, {"descripcion": None})
    assert r.status_code == 200, r.text
    assert r.json()["descripcion"] is None


def test_put_item_descripcion_null_borra(client, seeded):
    """{'descripcion': null} sobre campo nullable de ítem → se borra, respuesta 200."""
    iid = client.post(
        "/items",
        json={"proyecto_id": seeded.proyecto, "nombre": "Ítem Con Desc",
              "descripcion": "Desc temporal"},
        headers=_h(seeded, seeded.coord),
    ).json()["id"]

    r = _put_item(client, seeded, iid, {"descripcion": None})
    assert r.status_code == 200, r.text
    assert r.json()["descripcion"] is None


# ── 9. Permisos: TRABAJADOR y RESIDENTE → 403 ────────────────────────────────

def test_put_proyecto_trabajador_404(client, seeded):
    r = _put_proyecto(client, seeded, seeded.proyecto, {"nombre": "Hack"}, uid=seeded.trab)
    assert r.status_code == 404, r.text


def test_put_proyecto_residente_403(client, seeded):
    r = _put_proyecto(client, seeded, seeded.proyecto, {"nombre": "Hack"}, uid=seeded.resid)
    assert r.status_code == 403, r.text


def test_put_item_trabajador_403(client, seeded):
    r = _put_item(client, seeded, seeded.item, {"nombre": "Hack"}, uid=seeded.trab)
    assert r.status_code == 403, r.text


def test_put_item_residente_403(client, seeded):
    r = _put_item(client, seeded, seeded.item, {"nombre": "Hack"}, uid=seeded.resid)
    assert r.status_code == 403, r.text


# ── 10. Multi-tenant: otra empresa no puede editar ───────────────────────────

def test_put_proyecto_otra_empresa_404(client, seeded):
    """Admin de empresa B no puede editar proyecto de empresa A."""
    r = client.put(
        f"/proyectos/{seeded.proyecto}",
        json={"nombre": "Hack"},
        headers=seeded.headers(seeded.admin_b, seeded.emp_b),
    )
    assert r.status_code == 404, r.text


def test_put_item_otra_empresa_404(client, seeded):
    """Admin de empresa B no puede editar ítem de empresa A."""
    r = client.put(
        f"/items/{seeded.item}",
        json={"nombre": "Hack"},
        headers=seeded.headers(seeded.admin_b, seeded.emp_b),
    )
    assert r.status_code == 404, r.text


# ── 11. Regresión: GET /items devuelve duracion y orden reales ────────────────

def test_listar_items_devuelve_duracion_y_orden_reales(client, seeded):
    """Regresión del fix del dict en listar_items: duracion_estimada_horas y orden
    reflejan los valores reales del ORM, no los defaults del schema (null / 0)."""
    client.post(
        "/items",
        json={
            "proyecto_id": seeded.proyecto,
            "nombre": "Ítem con datos",
            "orden": 3,
            "duracion_estimada_horas": 8.5,
        },
        headers=_h(seeded, seeded.coord),
    )

    r = client.get("/items", params={"proyecto_id": seeded.proyecto},
                   headers=_h(seeded, seeded.coord))
    assert r.status_code == 200, r.text

    items_por_nombre = {i["nombre"]: i for i in r.json()}
    assert "Ítem con datos" in items_por_nombre
    assert items_por_nombre["Ítem con datos"]["orden"] == 3
    assert items_por_nombre["Ítem con datos"]["duracion_estimada_horas"] == 8.5
