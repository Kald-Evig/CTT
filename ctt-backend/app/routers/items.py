"""
routers/items.py — Endpoints de ítems (el núcleo operativo).

Incluye:
  - Creación jerárquica con validación de profundidad y máx. hijos (Sección 5.3).
  - Asignación de ítem a trabajador.
  - Transiciones de estado vía la máquina de estados (Sección 6).
  - Cierre de problemas y reversión excepcional de TERMINADO.
  - Comentarios, evidencias (registro) e historial (log de cambios).
  - Notificaciones de los eventos de la Sección 9.2.
"""

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select
from sqlalchemy.orm import Session, aliased

from app.audit import a_serializable, record_audit
from app.auth import AuthContext, actor_de, get_current_context, requiere_empresa
from app.config import settings
from app.database import get_db
from app.enums import EvidenciaSyncStatus, ItemEstado, Rol, UsuarioEstado
from app.models import (
    AuditLog, Item, ItemComentario, ItemEvidencia, ItemHistorial,
    Proyecto, ProyectoUsuario, SyncConflicto, Usuario,
)
from app.notifications import notificar
from app.permissions import puede
from app.schemas import (
    AsignarItemIn, ComentarioIn, ComentarioOut, EvidenciaIn, EvidenciaOut,
    HistorialOut, ItemCreate, ItemOut, ItemUpdate, MisItemOut, TransicionIn,
)
from app.state_machine import (
    TransicionInvalida, cerrar_problema, revertir_terminado, transicionar,
)
from app.tenancy import get_item_de_empresa, get_proyecto_de_empresa, get_usuario_de_empresa

router = APIRouter(prefix="/items", tags=["Ítems"])


# ── Helper de notificación a supervisores del proyecto ───────────────────────
def _supervisores_del_proyecto(db: Session, proyecto: Proyecto) -> list[Usuario]:
    """Residentes asignados + coordinador principal del proyecto (Sección 9.2)."""
    ids: set[str] = set()
    if proyecto.coordinador_principal_id:
        ids.add(proyecto.coordinador_principal_id)
    residentes = (
        db.query(ProyectoUsuario)
        .filter(ProyectoUsuario.proyecto_id == proyecto.id,
                ProyectoUsuario.rol_en_proyecto == Rol.RESIDENTE,
                ProyectoUsuario.estado == UsuarioEstado.ACTIVO)
        .all()
    )
    ids.update(r.usuario_id for r in residentes)
    if not ids:
        return []
    return db.query(Usuario).filter(Usuario.id.in_(ids)).all()


# ── Validación de asignatario ────────────────────────────────────────────────
def _validar_asignatario_trabajador(db: Session, usuario_id: str, empresa_id: str) -> None:
    """Verifica que el asignatario existe en la empresa y tiene rol trabajador.

    El Residente es responsable técnico y no ejecuta partidas ni es asignatario
    de ítems (NORMATIVA_LGUC_Y_CARGOS_OBRA.md §1 y §3).
    """
    eu = get_usuario_de_empresa(db, usuario_id, empresa_id)
    if eu.rol != Rol.TRABAJADOR:
        raise HTTPException(
            422,
            "El asignatario debe tener rol trabajador. El Residente es responsable "
            "técnico y no ejecuta partidas (NORMATIVA_LGUC_Y_CARGOS_OBRA.md §1 y §3).",
        )


# ── Crear ítem ───────────────────────────────────────────────────────────────
@router.post("", response_model=ItemOut, status_code=201)
def crear_item(
    body: ItemCreate,
    ctx: AuthContext = Depends(get_current_context),
    db: Session = Depends(get_db),
):
    """Crea un ítem (o sub-ítem) validando la jerarquía (Coordinador/Admin)."""
    empresa_id = requiere_empresa(ctx)
    if not puede(ctx.rol, "crear_editar_item"):
        raise HTTPException(403, "Su rol no puede crear ítems.")

    proyecto = get_proyecto_de_empresa(db, body.proyecto_id, empresa_id)

    nivel = 0
    if body.parent_item_id:
        padre = get_item_de_empresa(db, body.parent_item_id, empresa_id)
        if padre.proyecto_id != proyecto.id:
            raise HTTPException(400, "El ítem padre pertenece a otro proyecto.")
        nivel = padre.nivel_profundidad + 1
        # Sección 5.3: profundidad máxima.
        if nivel > settings.MAX_NIVEL_PROFUNDIDAD:
            raise HTTPException(
                400,
                f"Profundidad máxima excedida (máx {settings.MAX_NIVEL_PROFUNDIDAD + 1} "
                f"niveles de ítem).",
            )
        # Sección 5.3: máx 10 hijos directos por padre.
        n_hijos = db.query(Item).filter(Item.parent_item_id == padre.id).count()
        if n_hijos >= settings.MAX_HIJOS_DIRECTOS:
            raise HTTPException(
                400, f"Máximo {settings.MAX_HIJOS_DIRECTOS} sub-ítems por ítem padre.")

    # Validar que el asignatario pertenece a la empresa y tiene rol trabajador.
    if body.asignado_a:
        _validar_asignatario_trabajador(db, body.asignado_a, empresa_id)

    item = Item(
        proyecto_id=proyecto.id,
        parent_item_id=body.parent_item_id,
        nivel_profundidad=nivel,
        nombre=body.nombre,
        descripcion=body.descripcion,
        asignado_a=body.asignado_a,
        fecha_limite=body.fecha_limite,
        duracion_estimada_horas=body.duracion_estimada_horas,
        orden=body.orden,
        created_by=ctx.usuario.id,
    )
    db.add(item)
    db.commit()
    db.refresh(item)
    return item


# ── Helper: subquery ID de la última edicion_datos en audit_log ───────────────

def _ult_edit_id_correlado() -> object:
    """Subquery correlado a Item.id: devuelve el id de la fila más reciente de
    edicion_datos en audit_log para cada ítem del query externo.

    Se usa en LEFT JOIN ... ON audit_log.id = <este_subquery>.
    Al unir por id de fila (no por MAX+GROUP), actor_nombre y created_at
    siempre provienen de la MISMA fila — no hay mezcla de actores.
    """
    al_sq = aliased(AuditLog, name="al_sq")
    return (
        select(al_sq.id)
        .where(
            al_sq.entidad_id == Item.id,   # correlación al items externo
            al_sq.accion == "edicion_datos",
            al_sq.entidad_tipo == "item",
        )
        .order_by(al_sq.created_at.desc(), al_sq.id.desc())
        .limit(1)
        .correlate(Item)
        .scalar_subquery()
    )


def _ult_edit_id_fijo(item_id: str) -> object:
    """Subquery no correlado para un item_id concreto (GET /{item_id})."""
    return (
        select(AuditLog.id)
        .where(
            AuditLog.entidad_id == item_id,
            AuditLog.accion == "edicion_datos",
            AuditLog.entidad_tipo == "item",
        )
        .order_by(AuditLog.created_at.desc(), AuditLog.id.desc())
        .limit(1)
        .scalar_subquery()
    )


def _item_dict(item: Item, asignado_nombre, ult_actor, ult_fecha) -> dict:
    return {
        "id": item.id,
        "proyecto_id": item.proyecto_id,
        "parent_item_id": item.parent_item_id,
        "nivel_profundidad": item.nivel_profundidad,
        "nombre": item.nombre,
        "descripcion": item.descripcion,
        "asignado_a": item.asignado_a,
        "asignado_nombre": asignado_nombre,
        "estado": item.estado,
        "fecha_limite": item.fecha_limite,
        "duracion_estimada_horas": item.duracion_estimada_horas,
        "orden": item.orden,
        "ultima_edicion_por": ult_actor,
        "ultima_edicion_en": ult_fecha,
    }


# ── Listar / detalle ─────────────────────────────────────────────────────────
@router.get("", response_model=list[ItemOut])
def listar_items(
    proyecto_id: str = Query(...),
    estado: ItemEstado | None = Query(default=None),
    ctx: AuthContext = Depends(get_current_context),
    db: Session = Depends(get_db),
):
    """Lista los ítems de un proyecto, opcionalmente filtrados por estado."""
    empresa_id = requiere_empresa(ctx)
    get_proyecto_de_empresa(db, proyecto_id, empresa_id)  # valida pertenencia

    al_ult = aliased(AuditLog, name="al_ult")
    q = (
        db.query(Item, Usuario.nombre_completo, al_ult.actor_nombre, al_ult.created_at)
        .outerjoin(Usuario, Item.asignado_a == Usuario.id)
        .outerjoin(al_ult, al_ult.id == _ult_edit_id_correlado())
        .filter(Item.proyecto_id == proyecto_id)
    )
    if estado is not None:
        q = q.filter(Item.estado == estado)
    rows = q.order_by(Item.orden).all()
    return [
        _item_dict(item, asignado_nombre, ult_actor, ult_fecha)
        for item, asignado_nombre, ult_actor, ult_fecha in rows
    ]


@router.get("/mis-items", response_model=list[MisItemOut])
def mis_items(
    ctx: AuthContext = Depends(get_current_context),
    db: Session = Depends(get_db),
):
    """Ítems asignados al usuario autenticado en la empresa activa.

    Incluye proyecto_nombre para que el cliente pueda agrupar sin consultas
    adicionales. Devuelve todos los estados (el cliente filtra según vista).
    """
    empresa_id = requiere_empresa(ctx)
    filas = (
        db.query(Item, Proyecto.nombre)
        .join(Proyecto, Item.proyecto_id == Proyecto.id)
        .filter(
            Proyecto.empresa_id == empresa_id,
            Item.asignado_a == ctx.usuario.id,
        )
        .order_by(Item.orden, Item.created_at)
        .all()
    )
    return [
        MisItemOut(
            id=item.id,
            proyecto_id=item.proyecto_id,
            proyecto_nombre=nombre,
            parent_item_id=item.parent_item_id,
            nivel_profundidad=item.nivel_profundidad,
            nombre=item.nombre,
            descripcion=item.descripcion,
            asignado_a=item.asignado_a,
            estado=item.estado,
            fecha_limite=item.fecha_limite,
        )
        for item, nombre in filas
    ]


@router.get("/{item_id}", response_model=ItemOut)
def detalle_item(
    item_id: str,
    ctx: AuthContext = Depends(get_current_context),
    db: Session = Depends(get_db),
):
    empresa_id = requiere_empresa(ctx)
    al_ult = aliased(AuditLog, name="al_ult")
    row = (
        db.query(Item, Usuario.nombre_completo, al_ult.actor_nombre, al_ult.created_at)
        .join(Proyecto, Item.proyecto_id == Proyecto.id)
        .outerjoin(Usuario, Item.asignado_a == Usuario.id)
        .outerjoin(al_ult, al_ult.id == _ult_edit_id_fijo(item_id))
        .filter(Item.id == item_id, Proyecto.empresa_id == empresa_id)
        .first()
    )
    if row is None:
        raise HTTPException(404, "Ítem no encontrado.")
    item, asignado_nombre, ult_actor, ult_fecha = row
    return _item_dict(item, asignado_nombre, ult_actor, ult_fecha)


# ── Editar ítem ──────────────────────────────────────────────────────────────
@router.put("/{item_id}", response_model=ItemOut)
def editar_item(
    item_id: str,
    body: ItemUpdate,
    ctx: AuthContext = Depends(get_current_context),
    db: Session = Depends(get_db),
):
    """Edita datos de un ítem (Coordinador/Admin). Bloquea con 409 si está terminado."""
    empresa_id = requiere_empresa(ctx)
    if not puede(ctx.rol, "crear_editar_item"):
        raise HTTPException(403, "Su rol no puede editar ítems.")

    item = get_item_de_empresa(db, item_id, empresa_id)

    # Bloqueo ANTES de cualquier mutación.
    if item.estado == ItemEstado.TERMINADO:
        raise HTTPException(409, "No se puede editar un ítem terminado.")

    cambios = body.model_dump(exclude_unset=True)
    if not cambios:
        return item

    # Diff de solo los campos que realmente cambian de valor.
    diff: dict = {}
    for campo, valor_nuevo in cambios.items():
        valor_actual = getattr(item, campo)
        if valor_actual != valor_nuevo:
            diff[campo] = [a_serializable(valor_actual), a_serializable(valor_nuevo)]
            setattr(item, campo, valor_nuevo)

    if not diff:
        return item

    record_audit(
        db,
        empresa_id=empresa_id,
        **actor_de(ctx),
        accion="edicion_datos",
        entidad_tipo="item",
        entidad_id=item.id,
        proyecto_id=item.proyecto_id,
        diff=diff,
    )
    db.commit()
    db.refresh(item)
    return item


# ── Asignar ──────────────────────────────────────────────────────────────────
@router.post("/{item_id}/asignar", response_model=ItemOut)
def asignar_item(
    item_id: str,
    body: AsignarItemIn,
    ctx: AuthContext = Depends(get_current_context),
    db: Session = Depends(get_db),
):
    """Asigna el ítem a un trabajador (Residente/Coordinador/Admin)."""
    empresa_id = requiere_empresa(ctx)
    if not puede(ctx.rol, "asignar_item"):
        raise HTTPException(403, "Su rol no puede asignar ítems.")
    item = get_item_de_empresa(db, item_id, empresa_id)
    # Validar que el asignatario pertenece a la empresa y tiene rol trabajador.
    _validar_asignatario_trabajador(db, body.usuario_id, empresa_id)
    item.asignado_a = body.usuario_id

    # Notificación: ítem asignado a trabajador (Sección 9.2).
    destino = db.query(Usuario).filter(Usuario.id == body.usuario_id).first()
    if destino:
        notificar(db, empresa_id=empresa_id, usuario_id=destino.id,
                  evento="item_asignado", titulo=f"Nueva tarea: {item.nombre}",
                  cuerpo="Se te asignó una nueva tarea.", email_destino=destino.email)
    db.commit()
    db.refresh(item)
    return item


# ── Transición de estado ─────────────────────────────────────────────────────
@router.post("/{item_id}/transicion", response_model=ItemOut)
def transicion_item(
    item_id: str,
    body: TransicionIn,
    ctx: AuthContext = Depends(get_current_context),
    db: Session = Depends(get_db),
):
    """Aplica una transición de estado (Sección 6). La autorización fina por
    transición la resuelve la máquina de estados."""
    empresa_id = requiere_empresa(ctx)
    item = get_item_de_empresa(db, item_id, empresa_id)
    proyecto = db.query(Proyecto).filter(Proyecto.id == item.proyecto_id).first()

    # ── Detección de conflicto de concurrencia (Sección 8) ───────────────────
    # Si el cliente envía device_timestamp y el ítem fue modificado en el
    # servidor después de que el dispositivo tomó su snapshot, hay un conflicto.
    if body.device_timestamp and item.updated_at > body.device_timestamp.replace(tzinfo=None):
        conflicto = SyncConflicto(
            item_id=item.id,
            cambio_local={
                "estado": body.nuevo_estado.value,
                "comentario": body.comentario,
            },
            cambio_servidor={"estado": item.estado.value},
            dispositivo_id=body.dispositivo_id or "desconocido",
            usuario_id=ctx.usuario.id,
        )
        db.add(conflicto)
        db.commit()
        raise HTTPException(
            status_code=409,
            detail={
                "tipo": "conflicto_concurrencia",
                "conflicto_id": conflicto.id,
                "mensaje": "El ítem fue modificado en el servidor mientras el dispositivo estaba offline.",
                "estado_servidor": item.estado.value,
            },
        )

    estado_anterior = item.estado.value  # capturar ANTES de que transicionar() mute item.estado
    try:
        transicionar(
            db, item, body.nuevo_estado,
            rol=ctx.rol, usuario_id=ctx.usuario.id,
            comentario=body.comentario,
            descripcion_problema=body.descripcion_problema,
        )
    except TransicionInvalida as e:
        # 409 Conflict: el estado actual no permite la transición pedida.
        raise HTTPException(status_code=409, detail=str(e))

    # ── Notificaciones según el nuevo estado (Sección 9.2) ───────────────────
    if body.nuevo_estado == ItemEstado.PENDIENTE_REVISION:
        for sup in _supervisores_del_proyecto(db, proyecto):
            notificar(db, empresa_id=empresa_id, usuario_id=sup.id,
                      evento="item_pendiente_revision",
                      titulo=f"Revisión pendiente: {item.nombre}",
                      email_destino=sup.email)
    elif body.nuevo_estado == ItemEstado.TERMINADO and item.asignado_a:
        dest = db.query(Usuario).filter(Usuario.id == item.asignado_a).first()
        if dest:
            notificar(db, empresa_id=empresa_id, usuario_id=dest.id,
                      evento="item_aprobado", titulo=f"Aprobado: {item.nombre}",
                      email_destino=dest.email)
    elif body.nuevo_estado == ItemEstado.EN_PROGRESO and item.asignado_a:
        # Llegar a EN_PROGRESO desde PENDIENTE_REVISION = rechazo.
        dest = db.query(Usuario).filter(Usuario.id == item.asignado_a).first()
        if dest:
            notificar(db, empresa_id=empresa_id, usuario_id=dest.id,
                      evento="item_rechazado", titulo=f"Rechazado: {item.nombre}",
                      cuerpo=body.comentario, email_destino=dest.email)
    elif body.nuevo_estado == ItemEstado.PROBLEMA:
        for sup in _supervisores_del_proyecto(db, proyecto):
            notificar(db, empresa_id=empresa_id, usuario_id=sup.id,
                      evento="problema_marcado",
                      titulo=f"Problema: {item.nombre}",
                      cuerpo=body.descripcion_problema, email_destino=sup.email)

    # ── Audit log (CTT-48) — misma transacción que ItemHistorial y el cambio ──
    # device_timestamp presente → cambio vino de la cola offline del SyncService.
    record_audit(
        db,
        empresa_id=empresa_id,
        **actor_de(ctx),
        accion="cambio_estado",
        entidad_tipo="item",
        entidad_id=item.id,
        proyecto_id=item.proyecto_id,
        diff={"estado": [estado_anterior, body.nuevo_estado.value]},
        detalle=body.comentario or body.descripcion_problema,
        device_ts=body.device_timestamp,
        synced_offline=body.device_timestamp is not None,
    )

    db.commit()
    db.refresh(item)
    return item


# ── Cerrar problema ──────────────────────────────────────────────────────────
@router.post("/{item_id}/cerrar-problema", response_model=ItemOut)
def cerrar_problema_item(
    item_id: str,
    ctx: AuthContext = Depends(get_current_context),
    db: Session = Depends(get_db),
):
    """Cierra el problema abierto y restaura el estado previo (Sección 6.2)."""
    empresa_id = requiere_empresa(ctx)
    if not puede(ctx.rol, "cerrar_problema"):
        raise HTTPException(403, "Su rol no puede cerrar problemas.")
    item = get_item_de_empresa(db, item_id, empresa_id)
    # Capturar estado_previo ANTES de cerrar_problema() — la función lo borra (→ None).
    estado_restaurado = (item.estado_previo or ItemEstado.EN_PROGRESO).value
    try:
        cerrar_problema(db, item, rol=ctx.rol, usuario_id=ctx.usuario.id)
    except TransicionInvalida as e:
        raise HTTPException(status_code=409, detail=str(e))
    record_audit(
        db,
        empresa_id=empresa_id,
        **actor_de(ctx),
        accion="cierre_problema",
        entidad_tipo="item",
        entidad_id=item.id,
        proyecto_id=item.proyecto_id,
        diff={"estado": [ItemEstado.PROBLEMA.value, estado_restaurado]},
        detalle="Problema cerrado; estado restaurado.",
    )
    db.commit()
    db.refresh(item)
    return item


# ── Revertir terminado (excepción Admin) ─────────────────────────────────────
@router.post("/{item_id}/revertir-terminado", response_model=ItemOut)
def revertir_terminado_item(
    item_id: str,
    motivo: str = Query(..., min_length=1),
    ctx: AuthContext = Depends(get_current_context),
    db: Session = Depends(get_db),
):
    """Reversión excepcional de un ítem TERMINADO (solo Admin — Sección 5.3)."""
    empresa_id = requiere_empresa(ctx)
    item = get_item_de_empresa(db, item_id, empresa_id)
    try:
        revertir_terminado(db, item, rol=ctx.rol, usuario_id=ctx.usuario.id, motivo=motivo)
    except TransicionInvalida as e:
        raise HTTPException(status_code=409, detail=str(e))
    record_audit(
        db,
        empresa_id=empresa_id,
        **actor_de(ctx),
        accion="reversion_terminado",
        entidad_tipo="item",
        entidad_id=item.id,
        proyecto_id=item.proyecto_id,
        diff={"estado": [ItemEstado.TERMINADO.value, ItemEstado.PENDIENTE_REVISION.value]},
        detalle=f"Reversión excepcional (Admin): {motivo.strip()}",
    )
    db.commit()
    db.refresh(item)
    return item


# ── Comentarios ──────────────────────────────────────────────────────────────
@router.post("/{item_id}/comentarios", status_code=201)
def agregar_comentario(
    item_id: str,
    body: ComentarioIn,
    ctx: AuthContext = Depends(get_current_context),
    db: Session = Depends(get_db),
):
    """Agrega un comentario (todos los roles de obra — nunca genera conflicto)."""
    empresa_id = requiere_empresa(ctx)
    if not puede(ctx.rol, "agregar_comentario"):
        raise HTTPException(403, "Su rol no puede comentar.")
    item = get_item_de_empresa(db, item_id, empresa_id)
    c = ItemComentario(item_id=item.id, usuario_id=ctx.usuario.id, texto=body.texto)
    db.add(c)
    db.commit()
    return {"id": c.id, "texto": c.texto}


@router.get("/{item_id}/comentarios", response_model=list[ComentarioOut])
def listar_comentarios(
    item_id: str,
    ctx: AuthContext = Depends(get_current_context),
    db: Session = Depends(get_db),
):
    """Lista comentarios del ítem ordenados cronológicamente (todos los roles)."""
    empresa_id = requiere_empresa(ctx)
    item = get_item_de_empresa(db, item_id, empresa_id)
    rows = (
        db.query(ItemComentario, Usuario.nombre_completo)
        .outerjoin(Usuario, ItemComentario.usuario_id == Usuario.id)
        .filter(ItemComentario.item_id == item.id)
        .order_by(ItemComentario.created_at)
        .all()
    )
    return [
        {
            "id": c.id,
            "usuario_id": c.usuario_id,
            "nombre_usuario": nombre,
            "texto": c.texto,
            "created_at": c.created_at,
        }
        for c, nombre in rows
    ]


# ── Evidencias (registro de foto) ────────────────────────────────────────────
@router.post("/{item_id}/evidencias", status_code=201)
def registrar_evidencia(
    item_id: str,
    body: EvidenciaIn,
    ctx: AuthContext = Depends(get_current_context),
    db: Session = Depends(get_db),
):
    """Registra una evidencia fotográfica (Trabajador/Residente).

    La subida binaria real va directo a S3 vía pre-signed URL (Sección 4.4);
    aquí solo se registra el metadato y la clave S3.
    """
    empresa_id = requiere_empresa(ctx)
    if not puede(ctx.rol, "subir_foto"):
        raise HTTPException(403, "Su rol no puede subir fotos.")
    item = get_item_de_empresa(db, item_id, empresa_id)
    ev = ItemEvidencia(
        item_id=item.id,
        usuario_id=ctx.usuario.id,
        s3_key=body.s3_key,
        device_timestamp=body.device_timestamp or datetime.now(timezone.utc),
        sync_status=EvidenciaSyncStatus.SUBIDA if body.s3_key else EvidenciaSyncStatus.PENDIENTE,
        server_timestamp=datetime.now(timezone.utc),
    )
    db.add(ev)
    db.commit()
    return {"id": ev.id, "sync_status": ev.sync_status.value}


@router.get("/{item_id}/evidencias", response_model=list[EvidenciaOut])
def listar_evidencias(
    item_id: str,
    ctx: AuthContext = Depends(get_current_context),
    db: Session = Depends(get_db),
):
    """Lista evidencias fotográficas del ítem ordenadas cronológicamente."""
    empresa_id = requiere_empresa(ctx)
    item = get_item_de_empresa(db, item_id, empresa_id)
    return (
        db.query(ItemEvidencia)
        .filter(ItemEvidencia.item_id == item.id)
        .order_by(ItemEvidencia.created_at)
        .all()
    )


# ── Historial (log de cambios) ───────────────────────────────────────────────
@router.get("/{item_id}/historial", response_model=list[HistorialOut])
def historial_item(
    item_id: str,
    ctx: AuthContext = Depends(get_current_context),
    db: Session = Depends(get_db),
):
    """Devuelve el log cronológico de cambios del ítem (Sección 10)."""
    empresa_id = requiere_empresa(ctx)
    if not puede(ctx.rol, "ver_log_cambios"):
        raise HTTPException(403, "Su rol no puede ver el log de cambios.")
    item = get_item_de_empresa(db, item_id, empresa_id)
    rows = (
        db.query(ItemHistorial, Usuario.nombre_completo)
        .outerjoin(Usuario, ItemHistorial.usuario_id == Usuario.id)
        .filter(ItemHistorial.item_id == item.id)
        .order_by(ItemHistorial.created_at)
        .all()
    )
    return [
        {
            "accion": h.accion,
            "estado_anterior": h.estado_anterior,
            "estado_nuevo": h.estado_nuevo,
            "detalle": h.detalle,
            "usuario_id": h.usuario_id,
            "nombre_usuario": nombre,
            "created_at": h.created_at,
        }
        for h, nombre in rows
    ]
