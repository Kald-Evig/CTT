"""
permissions.py — Matriz de permisos (Sección 2.2 del DDT) como única fuente de verdad.

En vez de dispersar `if rol == ...` por el código, la matriz vive aquí como un
diccionario {accion: {roles permitidos}}. Cualquier endpoint pregunta `puede(...)`.
Esto hace el control de acceso auditable y testeable contra la tabla del DDT.

Super Admin: actúa a nivel de PLATAFORMA. Sus acciones (crear empresa, gestionar
usuarios) se modelan aparte; no participa en operaciones de obra, por lo que NO
aparece en las acciones de ítem/proyecto.
"""

from app.enums import Rol

# Cada acción mapea al conjunto de roles de EMPRESA que pueden ejecutarla.
# Espejo directo de la matriz de la Sección 2.2.
MATRIZ_PERMISOS: dict[str, set[Rol]] = {
    # Acción                          Roles permitidos
    "ver_tareas":            {Rol.TRABAJADOR, Rol.RESIDENTE, Rol.COORDINADOR, Rol.ADMIN},
    "iniciar_tarea":         {Rol.TRABAJADOR},
    "marcar_pendiente_revision": {Rol.TRABAJADOR},
    "marcar_problema":       {Rol.TRABAJADOR, Rol.RESIDENTE},
    "aprobar_item":          {Rol.RESIDENTE, Rol.COORDINADOR, Rol.ADMIN},
    "rechazar_item":         {Rol.RESIDENTE, Rol.COORDINADOR, Rol.ADMIN},
    "cerrar_problema":       {Rol.RESIDENTE, Rol.COORDINADOR, Rol.ADMIN},
    "agregar_comentario":    {Rol.TRABAJADOR, Rol.RESIDENTE, Rol.COORDINADOR, Rol.ADMIN},
    "subir_foto":            {Rol.TRABAJADOR, Rol.RESIDENTE},
    "asignar_item":          {Rol.RESIDENTE, Rol.COORDINADOR, Rol.ADMIN},
    "crear_editar_item":     {Rol.COORDINADOR, Rol.ADMIN},
    "crear_editar_proyecto": {Rol.COORDINADOR, Rol.ADMIN},
    "cerrar_proyecto":       {Rol.ADMIN},
    "crear_usuarios":        {Rol.ADMIN},            # + super_admin (manejado aparte)
    "gestionar_roles":       {Rol.ADMIN},            # + super_admin
    # Residente tiene acceso PARCIAL a reportes (Sección 2.2). Se concede acceso y
    # el alcance "parcial" se filtra a nivel de datos (solo sus proyectos).
    "acceso_reportes":       {Rol.RESIDENTE, Rol.COORDINADOR, Rol.ADMIN},
    "resolver_conflictos_sync": {Rol.COORDINADOR, Rol.ADMIN},
    "ver_log_cambios":       {Rol.RESIDENTE, Rol.COORDINADOR, Rol.ADMIN},
}

# Acciones exclusivas de plataforma (Super Admin).
ACCIONES_SUPER_ADMIN: set[str] = {
    "crear_empresa", "suspender_empresa", "soporte_lectura",
    "crear_usuarios", "gestionar_roles",
}


def puede(rol: Rol, accion: str, es_super_admin: bool = False) -> bool:
    """¿El rol (o super admin) puede ejecutar la acción?

    Args:
        rol: rol del usuario en la empresa activa.
        accion: clave de la acción (debe existir en la matriz).
        es_super_admin: si el usuario es Super Admin de plataforma.

    Returns:
        True si está permitido.
    """
    if es_super_admin and accion in ACCIONES_SUPER_ADMIN:
        return True
    return rol in MATRIZ_PERMISOS.get(accion, set())
