"""
test_ultima_edicion.py — CTT-43 PASO A2: campo ultima_edicion_por/en en ItemOut.

Cubre:
  1. Ítem nunca editado → null en GET /items y GET /items/{id}.
  2. Ítem editado una vez → actor y fecha del PUT.
  3. CLAVE: dos ediciones por actores distintos → ambos endpoints muestran el
     SEGUNDO (más reciente). Si el query mezcla rows o hace GROUP BY arbitrario,
     traería el primer editor — este test lo detecta.
  4. Aislamiento: GET /items/{id} reescrito con join(Proyecto).filter(empresa_id);
     ítem de otra empresa sigue devolviendo 404.
  5. Regresión: orden, duracion_estimada_horas y demás campos siguen correctos.
"""

from app.models import AuditLog


# ── Helpers ───────────────────────────────────────────────────────────────────

def _h(seeded, uid=None):
    return seeded.headers(uid or seeded.coord, seeded.emp_a)


def _get_detalle(client, seeded, item_id, uid=None):
    return client.get(f"/items/{item_id}", headers=_h(seeded, uid))


def _get_lista(client, seeded, uid=None):
    return client.get("/items", params={"proyecto_id": seeded.proyecto},
                      headers=_h(seeded, uid))


def _put_item(client, seeded, item_id, payload, uid=None):
    return client.put(f"/items/{item_id}", json=payload, headers=_h(seeded, uid))


# ── 1. Ítem nunca editado → null en ambos endpoints ──────────────────────────

def test_nunca_editado_detalle_null(client, seeded):
    """GET /items/{id}: ítem sin edición previa → ambos campos null."""
    r = _get_detalle(client, seeded, seeded.item)
    assert r.status_code == 200, r.text
    assert r.json()["ultima_edicion_por"] is None
    assert r.json()["ultima_edicion_en"] is None


def test_nunca_editado_lista_null(client, seeded):
    """GET /items: ítem sin edición → ambos campos null en el dict de lista."""
    r = _get_lista(client, seeded)
    assert r.status_code == 200, r.text
    por_id = {i["id"]: i for i in r.json()}
    assert por_id[seeded.item]["ultima_edicion_por"] is None
    assert por_id[seeded.item]["ultima_edicion_en"] is None


# ── 2. Ítem editado una vez → actor y fecha del PUT ──────────────────────────

def test_editado_una_vez_detalle(client, seeded):
    """GET /items/{id}: después de un PUT muestra nombre del editor y timestamp."""
    _put_item(client, seeded, seeded.item, {"nombre": "Editado v1"})

    r = _get_detalle(client, seeded, seeded.item)
    assert r.status_code == 200, r.text
    data = r.json()
    # "Coord" es el nombre_completo del coordinador sembrado en conftest.
    assert data["ultima_edicion_por"] == "Coord"
    assert data["ultima_edicion_en"] is not None


def test_editado_una_vez_lista(client, seeded):
    """GET /items: mismo resultado en el endpoint de lista."""
    _put_item(client, seeded, seeded.item, {"nombre": "Editado v1"})

    r = _get_lista(client, seeded)
    assert r.status_code == 200, r.text
    por_id = {i["id"]: i for i in r.json()}
    assert por_id[seeded.item]["ultima_edicion_por"] == "Coord"
    assert por_id[seeded.item]["ultima_edicion_en"] is not None


# ── 3. CLAVE: dos ediciones, actores distintos → muestra el MÁS RECIENTE ─────

def test_dos_ediciones_detalle_muestra_segundo_editor(client, seeded, db):
    """GET /items/{id}: el segundo PUT (admin) pisa al primero (coord).

    Si el query usara MAX+GROUP BY sin unir por id, podría traer el actor de
    cualquier fila del grupo, no necesariamente el de la más reciente.
    Este test lo detecta verificando ACTOR y FECHA por separado.
    """
    # Edición 1: coordinador cambia nombre
    _put_item(client, seeded, seeded.item, {"nombre": "Por coord"}, uid=seeded.coord)

    # Verificamos que hay exactamente 1 audit (sanidad)
    audits_post_1 = (
        db.query(AuditLog)
        .filter(AuditLog.entidad_id == seeded.item, AuditLog.accion == "edicion_datos")
        .all()
    )
    assert len(audits_post_1) == 1
    assert audits_post_1[0].actor_nombre == "Coord"

    # Edición 2: admin cambia nombre de nuevo (diferente valor → genera audit)
    _put_item(client, seeded, seeded.item, {"nombre": "Por admin"}, uid=seeded.admin)

    # Debe haber 2 audits ahora
    audits_post_2 = (
        db.query(AuditLog)
        .filter(AuditLog.entidad_id == seeded.item, AuditLog.accion == "edicion_datos")
        .order_by(AuditLog.created_at.asc())
        .all()
    )
    assert len(audits_post_2) == 2
    assert audits_post_2[0].actor_nombre == "Coord"   # el primero
    assert audits_post_2[1].actor_nombre == "Admin"   # el segundo

    # El endpoint debe mostrar el SEGUNDO editor
    r = _get_detalle(client, seeded, seeded.item)
    assert r.status_code == 200, r.text
    data = r.json()
    assert data["ultima_edicion_por"] == "Admin", (
        f"Esperado 'Admin' (segundo editor), obtenido '{data['ultima_edicion_por']}'. "
        f"El query probablemente trae el primer editor o mezcla rows."
    )
    assert data["ultima_edicion_en"] is not None


def test_dos_ediciones_lista_muestra_segundo_editor(client, seeded):
    """GET /items: el mismo escenario de dos editores en el endpoint de lista."""
    _put_item(client, seeded, seeded.item, {"nombre": "Por coord"}, uid=seeded.coord)
    _put_item(client, seeded, seeded.item, {"nombre": "Por admin"}, uid=seeded.admin)

    r = _get_lista(client, seeded)
    assert r.status_code == 200, r.text
    por_id = {i["id"]: i for i in r.json()}

    assert por_id[seeded.item]["ultima_edicion_por"] == "Admin", (
        f"Lista devuelve '{por_id[seeded.item]['ultima_edicion_por']}' en vez de 'Admin'."
    )
    assert por_id[seeded.item]["ultima_edicion_en"] is not None


# ── 4. Aislamiento: GET /items/{id} con ítem de otra empresa → 404 ────────────

def test_detalle_item_otra_empresa_404(client, seeded):
    """Admin de empresa B no puede acceder al ítem de empresa A.

    El nuevo detalle_item usa join(Proyecto).filter(empresa_id) en vez de
    get_item_de_empresa — confirmamos que el aislamiento sigue intacto.
    """
    r = client.get(
        f"/items/{seeded.item}",
        headers=seeded.headers(seeded.admin_b, seeded.emp_b),
    )
    assert r.status_code == 404, r.text


# ── 5. Regresión: campos existentes siguen correctos con el nuevo query ───────

def test_regresion_campos_detalle(client, seeded):
    """GET /items/{id}: orden, duracion y asignado_nombre correctos tras el refactor."""
    iid = client.post(
        "/items",
        json={
            "proyecto_id": seeded.proyecto,
            "nombre": "Ítem regresión detalle",
            "orden": 7,
            "duracion_estimada_horas": 3.5,
        },
        headers=_h(seeded, seeded.coord),
    ).json()["id"]

    r = _get_detalle(client, seeded, iid)
    assert r.status_code == 200, r.text
    d = r.json()
    assert d["nombre"] == "Ítem regresión detalle"
    assert d["orden"] == 7
    assert d["duracion_estimada_horas"] == 3.5
    assert d["nivel_profundidad"] == 0
    assert d["estado"] == "abierto"
    assert d["ultima_edicion_por"] is None   # nunca editado
    assert d["ultima_edicion_en"] is None


def test_regresion_campos_lista(client, seeded):
    """GET /items: todos los campos del dict manual siguen presentes y correctos."""
    iid = client.post(
        "/items",
        json={
            "proyecto_id": seeded.proyecto,
            "nombre": "Ítem regresión lista",
            "orden": 4,
            "duracion_estimada_horas": 6.0,
        },
        headers=_h(seeded, seeded.coord),
    ).json()["id"]

    r = _get_lista(client, seeded)
    assert r.status_code == 200, r.text
    por_id = {i["id"]: i for i in r.json()}
    assert iid in por_id
    d = por_id[iid]
    assert d["nombre"] == "Ítem regresión lista"
    assert d["orden"] == 4
    assert d["duracion_estimada_horas"] == 6.0
    assert d["nivel_profundidad"] == 0
    assert d["estado"] == "abierto"
    assert d["ultima_edicion_por"] is None
    assert d["ultima_edicion_en"] is None
