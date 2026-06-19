"""
test_residente_endpoints.py — Cierre de gaps de backend para Residente (DDT 7.2):
GET /items/{id}/comentarios, GET /items/{id}/evidencias, y validación de los
campos nuevos usuario_id/nombre_usuario en HistorialOut y asignado_nombre en ItemOut.
"""


def _h(seeded, uid):
    return seeded.headers(uid, seeded.emp_a)


def _hb(seeded, uid):
    """Headers para empresa B (tests de aislamiento multi-tenant)."""
    return seeded.headers(uid, seeded.emp_b)


# ── GET /items/{id}/comentarios ───────────────────────────────────────────────

def test_listar_comentarios_con_datos(client, seeded):
    r = client.post(
        f"/items/{seeded.item}/comentarios",
        json={"texto": "Avance confirmado"},
        headers=_h(seeded, seeded.coord),
    )
    assert r.status_code == 201, r.text

    r = client.get(f"/items/{seeded.item}/comentarios", headers=_h(seeded, seeded.coord))
    assert r.status_code == 200, r.text
    data = r.json()
    assert len(data) == 1
    c = data[0]
    assert c["texto"] == "Avance confirmado"
    assert c["usuario_id"] == seeded.coord_id
    assert c["nombre_usuario"] == "Coord"
    assert "id" in c
    assert "created_at" in c


def test_listar_comentarios_vacio(client, seeded):
    r = client.get(f"/items/{seeded.item}/comentarios", headers=_h(seeded, seeded.coord))
    assert r.status_code == 200, r.text
    assert r.json() == []


def test_listar_comentarios_empresa_ajena_es_404(client, seeded):
    r = client.get(
        f"/items/{seeded.item}/comentarios",
        headers=_hb(seeded, seeded.admin_b),
    )
    assert r.status_code == 404, r.text


# ── GET /items/{id}/evidencias ────────────────────────────────────────────────

def test_listar_evidencias_con_datos(client, seeded):
    r = client.post(
        f"/items/{seeded.item}/evidencias",
        json={"s3_key": "fotos/obra/test.jpg"},
        headers=_h(seeded, seeded.trab),
    )
    assert r.status_code == 201, r.text

    r = client.get(f"/items/{seeded.item}/evidencias", headers=_h(seeded, seeded.coord))
    assert r.status_code == 200, r.text
    data = r.json()
    assert len(data) == 1
    ev = data[0]
    assert ev["usuario_id"] == seeded.trab_id
    assert ev["sync_status"] == "subida"
    assert ev["s3_url"] is None
    assert ev["thumbnail_url"] is None
    assert "device_timestamp" in ev
    assert "created_at" in ev


def test_listar_evidencias_vacio(client, seeded):
    r = client.get(f"/items/{seeded.item}/evidencias", headers=_h(seeded, seeded.coord))
    assert r.status_code == 200, r.text
    assert r.json() == []


def test_listar_evidencias_empresa_ajena_es_404(client, seeded):
    r = client.get(
        f"/items/{seeded.item}/evidencias",
        headers=_hb(seeded, seeded.admin_b),
    )
    assert r.status_code == 404, r.text


# ── HistorialOut incluye usuario_id y nombre_usuario ─────────────────────────

def test_historial_incluye_nombre_usuario(client, seeded):
    # Transición que escribe en historial (trab es el asignado → puede iniciar)
    r = client.post(
        f"/items/{seeded.item}/transicion",
        json={"nuevo_estado": "en_progreso"},
        headers=_h(seeded, seeded.trab),
    )
    assert r.status_code == 200, r.text

    r = client.get(f"/items/{seeded.item}/historial", headers=_h(seeded, seeded.coord))
    assert r.status_code == 200, r.text
    data = r.json()
    assert len(data) >= 1
    entrada = data[0]
    assert "usuario_id" in entrada
    assert "nombre_usuario" in entrada
    assert entrada["usuario_id"] == seeded.trab_id
    assert entrada["nombre_usuario"] == "Trab"


# ── ItemOut incluye asignado_nombre ──────────────────────────────────────────

def test_listar_items_incluye_asignado_nombre(client, seeded):
    r = client.get(
        f"/items?proyecto_id={seeded.proyecto}",
        headers=_h(seeded, seeded.coord),
    )
    assert r.status_code == 200, r.text
    data = r.json()
    assert len(data) >= 1
    item = next(d for d in data if d["id"] == seeded.item)
    assert item["asignado_nombre"] == "Trab"
    assert item["asignado_a"] == seeded.trab_id


def test_listar_items_sin_asignar_nombre_es_none(client, seeded, db):
    from app.models import Item
    item_libre = Item(
        proyecto_id=seeded.proyecto,
        nivel_profundidad=0,
        nombre="Sin asignar",
        created_by=seeded.coord_id,
    )
    db.add(item_libre)
    db.commit()

    r = client.get(
        f"/items?proyecto_id={seeded.proyecto}",
        headers=_h(seeded, seeded.coord),
    )
    assert r.status_code == 200, r.text
    data = r.json()
    entrada = next(d for d in data if d["id"] == item_libre.id)
    assert entrada["asignado_nombre"] is None
    assert entrada["asignado_a"] is None
