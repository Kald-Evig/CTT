"""
routers/proyectos.py — Endpoints de proyectos.

Cubre: crear proyecto, listar proyectos de la empresa, cerrar proyecto.
Permisos según matriz 2.2; aislamiento por empresa según tenancy.py.
"""

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.audit import a_serializable, record_audit
from app.auth import (
    AuthContext,
    actor_de,
    exigir_permiso,
    get_current_context,
    requiere_empresa,
)
from app.authz import scope_orm, scope_sql, require_project_manage, require_project_read
from app.database import get_db
from app.enums import ItemEstado, ProyectoEstado, Rol, UsuarioEstado
from app.models import Item, ItemHistorial, Proyecto, ProyectoUsuario, Usuario
from app.schemas import (
    AsignarUsuarioProyectoIn, DashboardProyectoOut, ProyectoCreate,
    ProyectoHistorialEntradaOut, ProyectoOut, ProyectoUpdate, ProyectoUsuarioOut,
)
from app.tenancy import get_usuario_de_empresa

router = APIRouter(prefix="/proyectos", tags=["Proyectos"])


@router.post("", response_model=ProyectoOut, status_code=201)
def crear_proyecto(
    body: ProyectoCreate,
    ctx: AuthContext = Depends(get_current_context),
    db: Session = Depends(get_db),
):
    """Crea un proyecto en la empresa activa (Coordinador o Admin)."""
    empresa_id = requiere_empresa(ctx)
    exigir_permiso(ctx, "crear_editar_proyecto", "Su rol no puede crear proyectos.")

    # Derivar coordinador_principal_id:
    # body explícito → respetar.  Sin body + Coordinador → auto-asignarse.
    # Sin body + Admin → null (Admin pasa por bypass de factory; asigna coordinador luego).
    coord_id = body.coordinador_principal_id
    if coord_id is None and ctx.rol == Rol.COORDINADOR:
        coord_id = ctx.usuario.id

    if coord_id:
        get_usuario_de_empresa(db, coord_id, empresa_id)

    proyecto = Proyecto(
        empresa_id=empresa_id,
        nombre=body.nombre,
        descripcion=body.descripcion,
        ubicacion_nombre=body.ubicacion_nombre,
        latitud=body.latitud,
        longitud=body.longitud,
        coordinador_principal_id=coord_id,
        fecha_inicio=body.fecha_inicio,
        fecha_fin_estimada=body.fecha_fin_estimada,
        created_by=ctx.usuario.id,
    )
    db.add(proyecto)
    db.commit()
    db.refresh(proyecto)
    return proyecto


@router.get("", response_model=list[ProyectoOut])
def listar_proyectos(
    ctx: AuthContext = Depends(get_current_context),
    db: Session = Depends(get_db),
):
    """Lista los proyectos visibles al rol del usuario (filtrado por empresa y rol)."""
    empresa_id = requiere_empresa(ctx)
    q = db.query(Proyecto).filter(Proyecto.empresa_id == empresa_id)
    q = scope_orm(q, ctx)
    return q.order_by(Proyecto.created_at.desc()).all()


# ── IMPORTANTE: /dashboard y /{id}/historial deben preceder a cualquier ruta
# ── /{proyecto_id} para que FastAPI no interprete "dashboard" como un id. ────

_DASHBOARD_SQL_TMPL = """
SELECT
    p.id,
    p.nombre,
    p.estado,
    p.fecha_inicio,
    p.fecha_fin_estimada,
    p.created_at,
    COUNT(i.id)                                                              AS total_items,
    COALESCE(SUM(CASE WHEN i.estado = 'terminado' THEN 1 ELSE 0 END), 0)   AS items_terminados,
    COALESCE(SUM(CASE
        WHEN i.id IS NOT NULL
         AND i.id NOT IN (
             SELECT DISTINCT parent_item_id FROM items i2
             WHERE i2.proyecto_id = p.id
               AND i2.parent_item_id IS NOT NULL
         )
        THEN 1 ELSE 0 END), 0)                                              AS total_hojas,
    COALESCE(SUM(CASE
        WHEN i.estado = 'terminado'
         AND i.id IS NOT NULL
         AND i.id NOT IN (
             SELECT DISTINCT parent_item_id FROM items i2
             WHERE i2.proyecto_id = p.id
               AND i2.parent_item_id IS NOT NULL
         )
        THEN 1 ELSE 0 END), 0)                                              AS hojas_terminadas
FROM proyectos p
LEFT JOIN items i ON i.proyecto_id = p.id
WHERE p.empresa_id = :empresa_id{scope}
GROUP BY p.id, p.nombre, p.estado, p.fecha_inicio, p.fecha_fin_estimada, p.created_at
ORDER BY p.created_at DESC
"""


@router.get("/dashboard", response_model=list[DashboardProyectoOut])
def dashboard_proyectos(
    ctx: AuthContext = Depends(get_current_context),
    db: Session = Depends(get_db),
):
    """Lista de proyectos de la empresa con métricas de avance (CTT-42).

    Devuelve en una sola query (sin N+1):
    - pct_completo: terminados / todos los ítems del árbol × 100.
    - pct_real: hojas terminadas / hojas totales × 100.
      Una hoja es un ítem que no es padre de ningún otro.
      El filtro AND parent_item_id IS NOT NULL en el subquery evita el bug
      clásico de NOT IN con NULLs (que daría 0 hojas en proyectos jerárquicos).
    """
    empresa_id = requiere_empresa(ctx)
    exigir_permiso(ctx, "acceso_reportes", "Su rol no tiene acceso al dashboard.")

    scope_clause, scope_params = scope_sql(ctx)
    sql = text(_DASHBOARD_SQL_TMPL.format(scope=scope_clause))
    rows = db.execute(sql, {"empresa_id": empresa_id, **scope_params}).mappings().all()

    resultado = []
    for r in rows:
        total = r["total_items"]
        terminados = r["items_terminados"]
        hojas = r["total_hojas"]
        hojas_term = r["hojas_terminadas"]
        resultado.append(DashboardProyectoOut(
            id=r["id"],
            nombre=r["nombre"],
            estado=r["estado"],
            fecha_inicio=r["fecha_inicio"],
            fecha_fin_estimada=r["fecha_fin_estimada"],
            total_items=total,
            items_terminados=terminados,
            pct_completo=round(terminados / total * 100, 1) if total else 0.0,
            total_hojas=hojas,
            hojas_terminadas=hojas_term,
            pct_real=round(hojas_term / hojas * 100, 1) if hojas else 0.0,
        ))
    return resultado


@router.get("/{proyecto_id}/historial", response_model=list[ProyectoHistorialEntradaOut])
def historial_proyecto(
    proyecto: Proyecto = Depends(require_project_read),
    ctx: AuthContext = Depends(get_current_context),
    db: Session = Depends(get_db),
):
    """Log cronológico de todos los ítems del proyecto (CTT-42).

    Agrega el historial de cambios de estado de todos los ítems del proyecto,
    incluyendo el nombre del ítem y del usuario que realizó el cambio.
    """
    exigir_permiso(ctx, "ver_log_cambios", "Su rol no puede ver el log de cambios.")

    rows = (
        db.query(ItemHistorial, Item.nombre, Usuario.nombre_completo)
        .join(Item, ItemHistorial.item_id == Item.id)
        .outerjoin(Usuario, ItemHistorial.usuario_id == Usuario.id)
        .filter(Item.proyecto_id == proyecto.id)
        .order_by(ItemHistorial.created_at)
        .all()
    )
    return [
        {
            "item_id": h.item_id,
            "item_nombre": item_nombre,
            "accion": h.accion,
            "estado_anterior": h.estado_anterior,
            "estado_nuevo": h.estado_nuevo,
            "detalle": h.detalle,
            "usuario_id": h.usuario_id,
            "nombre_usuario": nombre_usuario,
            "created_at": h.created_at,
        }
        for h, item_nombre, nombre_usuario in rows
    ]


def _miembro_dict(fila, nombre) -> dict:
    """Serializa un ProyectoUsuario + nombre a la forma de ProyectoUsuarioOut."""
    return {
        "usuario_id": fila.usuario_id,
        "nombre_completo": nombre,
        "rol_en_proyecto": fila.rol_en_proyecto,
        "estado": fila.estado,
    }


@router.get("/{proyecto_id}/usuarios", response_model=list[ProyectoUsuarioOut])
def listar_miembros(
    incluir_inactivos: bool = Query(default=False),
    proyecto: Proyecto = Depends(require_project_read),
    db: Session = Depends(get_db),
):
    """Miembros del proyecto (ADMIN, coordinador_principal, residente miembro)."""
    q = (
        db.query(ProyectoUsuario, Usuario.nombre_completo)
        .join(Usuario, ProyectoUsuario.usuario_id == Usuario.id)
        .filter(ProyectoUsuario.proyecto_id == proyecto.id)
    )
    if not incluir_inactivos:
        q = q.filter(ProyectoUsuario.estado == UsuarioEstado.ACTIVO)
    filas = q.order_by(Usuario.nombre_completo).all()
    return [_miembro_dict(pu, nombre) for pu, nombre in filas]


@router.post("/{proyecto_id}/usuarios", response_model=ProyectoUsuarioOut, status_code=201)
def asignar_miembro(
    body: AsignarUsuarioProyectoIn,
    proyecto: Proyecto = Depends(require_project_manage),
    ctx: AuthContext = Depends(get_current_context),
    db: Session = Depends(get_db),
):
    """Asigna un usuario al proyecto. Deriva rol_en_proyecto de empresa_usuario (B-como-caché)."""
    empresa_id = proyecto.empresa_id
    # Valida membresía activa en empresa y deriva rol; 404 si no es miembro activo.
    membresia = get_usuario_de_empresa(db, body.usuario_id, empresa_id)
    rol_derivado = membresia.rol

    existente = (
        db.query(ProyectoUsuario)
        .filter(
            ProyectoUsuario.proyecto_id == proyecto.id,
            ProyectoUsuario.usuario_id == body.usuario_id,
        )
        .first()
    )

    if existente is None:
        fila = ProyectoUsuario(
            proyecto_id=proyecto.id,
            usuario_id=body.usuario_id,
            rol_en_proyecto=rol_derivado,
        )
        db.add(fila)
        db.flush()
    elif existente.estado == UsuarioEstado.ACTIVO:
        raise HTTPException(status_code=409,
                            detail="El usuario ya es miembro activo del proyecto.")
    else:
        # INACTIVO: re-derivar rol (puede haber cambiado durante la inactividad).
        existente.rol_en_proyecto = rol_derivado
        existente.estado = UsuarioEstado.ACTIVO
        fila = existente
        db.flush()

    record_audit(
        db,
        empresa_id=empresa_id,
        **actor_de(ctx),
        accion="asignacion_usuario",
        entidad_tipo="proyecto_usuario",
        entidad_id=fila.id,
        proyecto_id=proyecto.id,
    )
    db.commit()
    db.refresh(fila)

    nombre = (
        db.query(Usuario.nombre_completo)
        .filter(Usuario.id == fila.usuario_id)
        .scalar()
    )
    return _miembro_dict(fila, nombre)


@router.delete("/{proyecto_id}/usuarios/{usuario_id}", response_model=ProyectoUsuarioOut)
def desasignar_miembro(
    usuario_id: str,
    proyecto: Proyecto = Depends(require_project_manage),
    ctx: AuthContext = Depends(get_current_context),
    db: Session = Depends(get_db),
):
    """Soft-delete de membresía: estado → INACTIVO. 404 si no existe o ya inactivo."""
    fila = (
        db.query(ProyectoUsuario)
        .filter(
            ProyectoUsuario.proyecto_id == proyecto.id,
            ProyectoUsuario.usuario_id == usuario_id,
            ProyectoUsuario.estado == UsuarioEstado.ACTIVO,
        )
        .first()
    )
    if fila is None:
        raise HTTPException(status_code=404,
                            detail="El usuario no es miembro activo del proyecto.")

    # Regla 3: bloquear si hay ítems activos asignados al usuario en este proyecto.
    bloqueantes = (
        db.query(Item)
        .filter(
            Item.asignado_a == usuario_id,
            Item.proyecto_id == proyecto.id,
            Item.estado != ItemEstado.TERMINADO,
        )
        .all()
    )
    if bloqueantes:
        raise HTTPException(
            status_code=409,
            detail={
                "code": "USUARIO_CON_ITEMS_ACTIVOS",
                "mensaje": "El usuario tiene ítems activos asignados en este proyecto.",
                "blockingItems": [{"id": i.id, "nombre": i.nombre} for i in bloqueantes],
            },
        )

    fila.estado = UsuarioEstado.INACTIVO
    record_audit(
        db,
        empresa_id=proyecto.empresa_id,
        **actor_de(ctx),
        accion="desasignacion_usuario",
        entidad_tipo="proyecto_usuario",
        entidad_id=fila.id,
        proyecto_id=proyecto.id,
    )
    db.commit()
    db.refresh(fila)

    nombre = (
        db.query(Usuario.nombre_completo)
        .filter(Usuario.id == fila.usuario_id)
        .scalar()
    )
    return _miembro_dict(fila, nombre)


@router.get("/{proyecto_id}", response_model=ProyectoOut)
def obtener_proyecto(
    proyecto: Proyecto = Depends(require_project_read),
):
    """Devuelve un proyecto por id (multi-tenant; 404 si no pertenece a la empresa activa)."""
    return proyecto


@router.put("/{proyecto_id}", response_model=ProyectoOut)
def editar_proyecto(
    body: ProyectoUpdate,
    proyecto: Proyecto = Depends(require_project_manage),
    ctx: AuthContext = Depends(get_current_context),
    db: Session = Depends(get_db),
):
    """Edita datos de un proyecto (Coordinador/Admin). No modifica el estado."""
    exigir_permiso(ctx, "crear_editar_proyecto", "Su rol no puede editar proyectos.")

    empresa_id = proyecto.empresa_id
    cambios = body.model_dump(exclude_unset=True)
    if not cambios:
        return proyecto

    # Validar coordinador si se está asignando a alguien (null = quitar coordinador, es válido).
    if cambios.get("coordinador_principal_id") is not None:
        get_usuario_de_empresa(db, cambios["coordinador_principal_id"], empresa_id)

    # Diff de solo los campos que realmente cambian de valor.
    diff: dict = {}
    for campo, valor_nuevo in cambios.items():
        valor_actual = getattr(proyecto, campo)
        if valor_actual != valor_nuevo:
            diff[campo] = [a_serializable(valor_actual), a_serializable(valor_nuevo)]
            setattr(proyecto, campo, valor_nuevo)

    if not diff:
        return proyecto

    record_audit(
        db,
        empresa_id=empresa_id,
        **actor_de(ctx),
        accion="edicion_datos",
        entidad_tipo="proyecto",
        entidad_id=proyecto.id,
        proyecto_id=proyecto.id,
        diff=diff,
    )
    db.commit()
    db.refresh(proyecto)
    return proyecto


@router.post("/{proyecto_id}/cerrar", response_model=ProyectoOut)
def cerrar_proyecto(
    proyecto: Proyecto = Depends(require_project_manage),
    ctx: AuthContext = Depends(get_current_context),
    db: Session = Depends(get_db),
):
    """Cierra un proyecto definitivamente (solo Admin — Sección 2.2)."""
    exigir_permiso(ctx, "cerrar_proyecto", "Solo un Admin puede cerrar proyectos.")
    proyecto.estado = ProyectoEstado.CERRADO
    db.commit()
    db.refresh(proyecto)
    return proyecto
