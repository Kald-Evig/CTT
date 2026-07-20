"""test_desasignar_miembro.py — DELETE /proyectos/{id}/usuarios/{uid} (CTT-44 capa 3b).

Cubre:
  - desasigna miembro sin ítems activos → 200, estado inactivo
  - ítems activos → 409 Y la fila SIGUE ACTIVA (bloqueo efectivo, no cosmético)
  - ítem TERMINADO NO bloquea (puede desasignarse)
  - no-miembro → 404 · ya-inactivo → 404 · coord-ajeno → 404
  - crea audit_log con actor_rol
"""

import pytest

from app.enums import ItemEstado, Rol, UsuarioEstado
from app.models import (
    AuditLog, EmpresaUsuario, Item, ProyectoUsuario, Usuario,
)


# ── Fixture ───────────────────────────────────────────────────────────────────

@pytest.fixture()
def datos_delete(seeded, db, client):
    """Extiende seeded con actores y escenarios para tests de desasignación.

    Actores:
      bloqueado     — miembro ACTIVO con ítem EN_PROGRESO (bloqueo regla 3)
      con_terminado — miembro ACTIVO con ítem TERMINADO (no bloquea)
      inactivo      — miembro ya INACTIVO (→ 404)
      no_miembro    — en empresa pero sin fila en proyecto_usuarios (→ 404)
      coord_otro    — COORDINADOR que no es coordinador_principal (→ 404)
    seeded.resid    — miembro ACTIVO sin ítems → candidato limpio para delete/audit
    """
    bloqueado = Usuario(firebase_uid="d-bloqueado", nombre_completo="Bloqueado",
                        email="bloqueado@a.cl")
    db.add(bloqueado); db.flush()
    db.add(EmpresaUsuario(empresa_id=seeded.emp_a, usuario_id=bloqueado.id,
                          rol=Rol.TRABAJADOR))
    db.add(ProyectoUsuario(proyecto_id=seeded.proyecto, usuario_id=bloqueado.id,
                           rol_en_proyecto=Rol.TRABAJADOR))
    db.add(Item(proyecto_id=seeded.proyecto, nivel_profundidad=0,
                nombre="Item activo bloqueado", asignado_a=bloqueado.id,
                estado=ItemEstado.EN_PROGRESO, created_by=seeded.coord_id))

    con_terminado = Usuario(firebase_uid="d-terminado", nombre_completo="Con Terminado",
                            email="terminado@a.cl")
    db.add(con_terminado); db.flush()
    db.add(EmpresaUsuario(empresa_id=seeded.emp_a, usuario_id=con_terminado.id,
                          rol=Rol.TRABAJADOR))
    db.add(ProyectoUsuario(proyecto_id=seeded.proyecto, usuario_id=con_terminado.id,
                           rol_en_proyecto=Rol.TRABAJADOR))
    db.add(Item(proyecto_id=seeded.proyecto, nivel_profundidad=0,
                nombre="Item terminado", asignado_a=con_terminado.id,
                estado=ItemEstado.TERMINADO, created_by=seeded.coord_id))

    inactivo = Usuario(firebase_uid="d-inactivo", nombre_completo="Inactivo",
                       email="inactivo@a.cl")
    db.add(inactivo); db.flush()
    db.add(EmpresaUsuario(empresa_id=seeded.emp_a, usuario_id=inactivo.id,
                          rol=Rol.RESIDENTE))
    db.add(ProyectoUsuario(proyecto_id=seeded.proyecto, usuario_id=inactivo.id,
                           rol_en_proyecto=Rol.RESIDENTE,
                           estado=UsuarioEstado.INACTIVO))

    no_miembro = Usuario(firebase_uid="d-no-miembro", nombre_completo="No Miembro",
                         email="nomiembro@a.cl")
    db.add(no_miembro); db.flush()
    db.add(EmpresaUsuario(empresa_id=seeded.emp_a, usuario_id=no_miembro.id,
                          rol=Rol.TRABAJADOR))

    coord_otro = Usuario(firebase_uid="d-coord-otro", nombre_completo="Coord Otro D",
                         email="coord.otro.d@a.cl")
    db.add(coord_otro); db.flush()
    db.add(EmpresaUsuario(empresa_id=seeded.emp_a, usuario_id=coord_otro.id,
                          rol=Rol.COORDINADOR))

    db.commit()

    return {
        "client":         client,
        "db":             db,
        "seeded":         seeded,
        "bloqueado_id":   bloqueado.id,
        "con_terminado_id": con_terminado.id,
        "inactivo_id":    inactivo.id,
        "no_miembro_id":  no_miembro.id,
        "coord_otro_uid": "d-coord-otro",
    }


# ── Tests ─────────────────────────────────────────────────────────────────────

def test_delete_desasigna_miembro_sin_items_activos(datos_delete):
    d = datos_delete
    s = d["seeded"]
    # resid está en proyecto_usuarios (ACTIVO) y no tiene ítems asignados.
    r = d["client"].delete(f"/proyectos/{s.proyecto}/usuarios/{s.resid_id}",
                           headers=s.headers(s.admin))
    assert r.status_code == 200
    body = r.json()
    assert body["estado"] == "inactivo"
    assert body["usuario_id"] == s.resid_id


def test_delete_con_items_activos_409_y_fila_sigue_activa(datos_delete):
    """409 cuando hay ítems activos Y la fila NO debe quedar INACTIVA (bloqueo efectivo)."""
    d = datos_delete
    s = d["seeded"]
    db = d["db"]
    bloqueado_id = d["bloqueado_id"]
    r = d["client"].delete(f"/proyectos/{s.proyecto}/usuarios/{bloqueado_id}",
                           headers=s.headers(s.admin))
    assert r.status_code == 409
    # Verificar que la fila sigue ACTIVA — el 409 no debe haberla desactivado.
    db.expire_all()
    fila = (
        db.query(ProyectoUsuario)
        .filter(ProyectoUsuario.proyecto_id == s.proyecto,
                ProyectoUsuario.usuario_id == bloqueado_id)
        .first()
    )
    assert fila is not None
    assert fila.estado == UsuarioEstado.ACTIVO


def test_delete_terminado_no_bloquea(datos_delete):
    """Ítem en estado TERMINADO no impide la desasignación."""
    d = datos_delete
    s = d["seeded"]
    r = d["client"].delete(f"/proyectos/{s.proyecto}/usuarios/{d['con_terminado_id']}",
                           headers=s.headers(s.admin))
    assert r.status_code == 200
    assert r.json()["estado"] == "inactivo"


def test_delete_no_miembro_404(datos_delete):
    d = datos_delete
    s = d["seeded"]
    r = d["client"].delete(f"/proyectos/{s.proyecto}/usuarios/{d['no_miembro_id']}",
                           headers=s.headers(s.admin))
    assert r.status_code == 404


def test_delete_ya_inactivo_404(datos_delete):
    d = datos_delete
    s = d["seeded"]
    r = d["client"].delete(f"/proyectos/{s.proyecto}/usuarios/{d['inactivo_id']}",
                           headers=s.headers(s.admin))
    assert r.status_code == 404


def test_delete_coord_ajeno_404(datos_delete):
    d = datos_delete
    s = d["seeded"]
    r = d["client"].delete(f"/proyectos/{s.proyecto}/usuarios/{s.resid_id}",
                           headers=s.headers(d["coord_otro_uid"]))
    assert r.status_code == 404


def test_delete_crea_audit_log(datos_delete):
    d = datos_delete
    s = d["seeded"]
    db = d["db"]
    r = d["client"].delete(f"/proyectos/{s.proyecto}/usuarios/{s.resid_id}",
                           headers=s.headers(s.admin))
    assert r.status_code == 200
    db.expire_all()
    entrada = (
        db.query(AuditLog)
        .filter(
            AuditLog.accion == "desasignacion_usuario",
            AuditLog.entidad_tipo == "proyecto_usuario",
            AuditLog.proyecto_id == s.proyecto,
        )
        .first()
    )
    assert entrada is not None
    assert entrada.actor_rol == "admin"
