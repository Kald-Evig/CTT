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
from sqlalchemy.orm import Session

from app.auth import AuthContext, get_current_context, requiere_empresa
from app.config import settings
from app.database import get_db
from app.enums import EvidenciaSyncStatus, ItemEstado, Rol
from app.models import (
    Item, ItemComentario, ItemEvidencia, ItemHistorial, Proyecto, ProyectoUsuario,
    Usuario,
)
from app.notifications import notificar
from app.permissions import puede
from app.schemas import (
    AsignarItemIn, ComentarioIn, EvidenciaIn, HistorialOut, ItemCreate, ItemOut,
    TransicionIn,
)
from app.state_machine import (
    TransicionInvalida, cerrar_problema, revertir_terminado, transicionar,
)
from app.tenancy import get_item_de_empresa, get_proyecto_de_empresa

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
                ProyectoUsuario.rol_en_proyecto == Rol.RESIDENTE)
        .all()
    )
    ids.update(r.usuario_id for r in residentes)
    if not ids:
        return []
    return db.query(Usuario).filter(Usuario.id.in_(ids)).all()


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
    q = db.query(Item).filter(Item.proyecto_id == proyecto_id)
    if estado is not None:
        q = q.filter(Item.estado == estado)
    return q.order_by(Item.orden).all()


@router.get("/{item_id}", response_model=ItemOut)
def detalle_item(
    item_id: str,
    ctx: AuthContext = Depends(get_current_context),
    db: Session = Depends(get_db),
):
    empresa_id = requiere_empresa(ctx)
    return get_item_de_empresa(db, item_id, empresa_id)


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
    try:
        cerrar_problema(db, item, rol=ctx.rol, usuario_id=ctx.usuario.id)
    except TransicionInvalida as e:
        raise HTTPException(status_code=409, detail=str(e))
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
    return (
        db.query(ItemHistorial)
        .filter(ItemHistorial.item_id == item.id)
        .order_by(ItemHistorial.created_at)
        .all()
    )
