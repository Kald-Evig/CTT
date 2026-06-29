"""
test_coordinador_dashboard.py — Tests para CTT-42: GET /proyectos/dashboard
y GET /proyectos/{id}/historial.

Molde: test_residente_endpoints.py (client + seeded fixtures, misma convención
de headers y aislamiento multi-tenant).
"""

from app.enums import ItemEstado
from app.models import Item, ItemHistorial, Proyecto


def _h(seeded, uid):
    return seeded.headers(uid, seeded.emp_a)


def _hb(seeded, uid):
    return seeded.headers(uid, seeded.emp_b)


# ── GET /proyectos/dashboard ──────────────────────────────────────────────────

def test_dashboard_proyecto_plano(client, seeded):
    """Proyecto sin jerarquía: todas las raíces son hojas → pct_completo == pct_real."""
    r = client.get("/proyectos/dashboard", headers=_h(seeded, seeded.coord))
    assert r.status_code == 200, r.text
    data = r.json()
    p = next(d for d in data if d["id"] == seeded.proyecto)

    assert p["total_items"] == 1
    assert p["items_terminados"] == 0
    assert p["pct_completo"] == 0.0
    assert p["total_hojas"] == 1       # raíz sin hijos = hoja
    assert p["hojas_terminadas"] == 0
    assert p["pct_real"] == 0.0
    assert p["pct_completo"] == p["pct_real"]


def test_dashboard_proyecto_jerarquico(client, seeded, db):
    """Proyecto con padre + 2 hijos: padre excluido de hojas; pct_real > pct_completo."""
    padre = Item(proyecto_id=seeded.proyecto, nivel_profundidad=0, nombre="Agrupador",
                 created_by=seeded.coord_id)
    db.add(padre); db.flush()
    hijo1 = Item(proyecto_id=seeded.proyecto, parent_item_id=padre.id,
                 nivel_profundidad=1, nombre="Hijo terminado",
                 estado=ItemEstado.TERMINADO, created_by=seeded.coord_id)
    hijo2 = Item(proyecto_id=seeded.proyecto, parent_item_id=padre.id,
                 nivel_profundidad=1, nombre="Hijo abierto",
                 estado=ItemEstado.ABIERTO, created_by=seeded.coord_id)
    db.add_all([hijo1, hijo2]); db.commit()

    r = client.get("/proyectos/dashboard", headers=_h(seeded, seeded.coord))
    assert r.status_code == 200, r.text
    p = next(d for d in r.json() if d["id"] == seeded.proyecto)

    # seeded root (ABIERTO) + padre + hijo1 (TERMINADO) + hijo2 (ABIERTO)
    assert p["total_items"] == 4
    assert p["items_terminados"] == 1
    assert p["pct_completo"] == round(1 / 4 * 100, 1)   # 25.0

    # Hojas: seeded root + hijo1 + hijo2 (padre excluido porque tiene hijos)
    assert p["total_hojas"] == 3
    assert p["hojas_terminadas"] == 1
    assert p["pct_real"] == round(1 / 3 * 100, 1)       # 33.3

    assert p["pct_real"] > p["pct_completo"]


def test_dashboard_null_safe_hojas(client, seeded, db):
    """Regresión: NOT IN con NULLs daría total_hojas=0 en proyecto jerárquico.

    Sin el filtro AND parent_item_id IS NOT NULL en el subquery, el SELECT DISTINCT
    parent_item_id incluiría NULLs → `i.id NOT IN (..., NULL)` evalúa a NULL para
    todas las filas → CASE → 0 siempre. Con el filtro, el subquery solo contiene
    ids reales → evaluación correcta.
    """
    hijo = Item(proyecto_id=seeded.proyecto, parent_item_id=seeded.item,
                nivel_profundidad=1, nombre="Hijo de raiz",
                estado=ItemEstado.ABIERTO, created_by=seeded.coord_id)
    db.add(hijo); db.commit()

    r = client.get("/proyectos/dashboard", headers=_h(seeded, seeded.coord))
    assert r.status_code == 200, r.text
    p = next(d for d in r.json() if d["id"] == seeded.proyecto)

    assert p["total_items"] == 2
    # seeded.item ahora es padre → no es hoja; hijo es la única hoja
    assert p["total_hojas"] == 1    # BUG sin IS NOT NULL: devolvería 0
    assert p["hojas_terminadas"] == 0


def test_dashboard_empresa_ajena_invisible(client, seeded, db):
    """Multi-tenant: coord de empresa A no ve proyectos de empresa B y viceversa."""
    proyecto_b = Proyecto(empresa_id=seeded.emp_b, nombre="Proyecto B",
                          created_by=seeded.admin_b_id)
    db.add(proyecto_b); db.commit()

    r_a = client.get("/proyectos/dashboard", headers=_h(seeded, seeded.coord))
    assert r_a.status_code == 200, r_a.text
    ids_a = {d["id"] for d in r_a.json()}
    assert seeded.proyecto in ids_a
    assert proyecto_b.id not in ids_a

    r_b = client.get("/proyectos/dashboard", headers=_hb(seeded, seeded.admin_b))
    assert r_b.status_code == 200, r_b.text
    ids_b = {d["id"] for d in r_b.json()}
    assert proyecto_b.id in ids_b
    assert seeded.proyecto not in ids_b


# ── GET /proyectos/{id}/historial ─────────────────────────────────────────────

def test_historial_proyecto_agrega_items(client, seeded, db):
    """El historial del proyecto incluye entradas de todos sus ítems."""
    item2 = Item(proyecto_id=seeded.proyecto, nivel_profundidad=0, nombre="Tarea 2",
                 asignado_a=seeded.trab_id, estado=ItemEstado.ABIERTO,
                 created_by=seeded.coord_id)
    db.add(item2); db.commit()

    # Transicionar ambos ítems para generar entradas de historial
    client.post(f"/items/{seeded.item}/transicion",
                json={"nuevo_estado": "en_progreso"},
                headers=_h(seeded, seeded.trab))
    client.post(f"/items/{item2.id}/transicion",
                json={"nuevo_estado": "en_progreso"},
                headers=_h(seeded, seeded.trab))

    r = client.get(f"/proyectos/{seeded.proyecto}/historial",
                   headers=_h(seeded, seeded.coord))
    assert r.status_code == 200, r.text
    data = r.json()

    item_ids = {e["item_id"] for e in data}
    assert seeded.item in item_ids
    assert item2.id in item_ids
    assert len(data) >= 2

    entrada = data[0]
    assert "item_id" in entrada
    assert "item_nombre" in entrada
    assert "accion" in entrada
    assert "estado_anterior" in entrada
    assert "estado_nuevo" in entrada
    assert "usuario_id" in entrada
    assert "nombre_usuario" in entrada
    assert "created_at" in entrada


def test_historial_empresa_ajena_es_404(client, seeded, db):
    """Multi-tenant: historial de proyecto ajeno → 404."""
    proyecto_b = Proyecto(empresa_id=seeded.emp_b, nombre="Proyecto B secret",
                          created_by=seeded.admin_b_id)
    db.add(proyecto_b); db.commit()

    r = client.get(f"/proyectos/{proyecto_b.id}/historial",
                   headers=_h(seeded, seeded.coord))
    assert r.status_code == 404, r.text
