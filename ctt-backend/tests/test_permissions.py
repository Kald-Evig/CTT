"""
test_permissions.py — Tests unitarios de la matriz de permisos (Sección 2.2).

Valida `puede()` contra la tabla del DDT, incluyendo el caso del Super Admin
(que actúa a nivel de plataforma, no de obra).
"""

from app.enums import Rol
from app.permissions import puede


# ── Acciones de obra por rol ─────────────────────────────────────────────────
def test_trabajador_inicia_pero_no_aprueba():
    assert puede(Rol.TRABAJADOR, "iniciar_tarea") is True
    assert puede(Rol.TRABAJADOR, "aprobar_item") is False


def test_solo_coordinador_y_admin_crean_items():
    assert puede(Rol.COORDINADOR, "crear_editar_item") is True
    assert puede(Rol.ADMIN, "crear_editar_item") is True
    assert puede(Rol.RESIDENTE, "crear_editar_item") is False
    assert puede(Rol.TRABAJADOR, "crear_editar_item") is False


def test_aprobar_rechazar_lo_pueden_residente_coordinador_admin():
    for accion in ("aprobar_item", "rechazar_item"):
        assert puede(Rol.RESIDENTE, accion) is True
        assert puede(Rol.COORDINADOR, accion) is True
        assert puede(Rol.ADMIN, accion) is True
        assert puede(Rol.TRABAJADOR, accion) is False


def test_cerrar_proyecto_solo_admin():
    assert puede(Rol.ADMIN, "cerrar_proyecto") is True
    assert puede(Rol.COORDINADOR, "cerrar_proyecto") is False
    assert puede(Rol.RESIDENTE, "cerrar_proyecto") is False
    assert puede(Rol.TRABAJADOR, "cerrar_proyecto") is False


def test_marcar_problema_trabajador_y_residente():
    assert puede(Rol.TRABAJADOR, "marcar_problema") is True
    assert puede(Rol.RESIDENTE, "marcar_problema") is True
    assert puede(Rol.COORDINADOR, "marcar_problema") is False


def test_subir_foto_trabajador_y_residente():
    assert puede(Rol.TRABAJADOR, "subir_foto") is True
    assert puede(Rol.RESIDENTE, "subir_foto") is True
    assert puede(Rol.COORDINADOR, "subir_foto") is False
    assert puede(Rol.ADMIN, "subir_foto") is False


def test_ver_log_cambios_excluye_trabajador():
    assert puede(Rol.TRABAJADOR, "ver_log_cambios") is False
    assert puede(Rol.RESIDENTE, "ver_log_cambios") is True


# ── Acciones de plataforma (Super Admin) ─────────────────────────────────────
def test_super_admin_crea_empresa_pero_rol_de_obra_no():
    # El flag super_admin habilita acciones de plataforma...
    assert puede(Rol.ADMIN, "crear_empresa", es_super_admin=True) is True
    # ...y sin el flag, ningún rol de empresa puede crear empresas.
    assert puede(Rol.ADMIN, "crear_empresa", es_super_admin=False) is False


def test_super_admin_no_obtiene_permisos_de_obra_por_el_flag():
    # El flag NO debe colar permisos de obra que no estén en ACCIONES_SUPER_ADMIN.
    assert puede(Rol.TRABAJADOR, "aprobar_item", es_super_admin=True) is False


def test_crear_usuarios_admin_o_super_admin():
    assert puede(Rol.ADMIN, "crear_usuarios") is True
    assert puede(Rol.COORDINADOR, "crear_usuarios") is False
    # Super Admin también puede crear usuarios (acción compartida).
    assert puede(Rol.TRABAJADOR, "crear_usuarios", es_super_admin=True) is True


# ── Acciones inexistentes ────────────────────────────────────────────────────
def test_accion_desconocida_siempre_falsa():
    assert puede(Rol.ADMIN, "accion_que_no_existe") is False
