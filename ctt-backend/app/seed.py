"""
seed.py — Carga datos de demostración con contexto chileno realista.

Ejecutar:  python -m app.seed   (recrea la BD desde cero)

Crea:
  - 1 Super Admin de plataforma.
  - 2 empresas (tenants) para demostrar aislamiento multi-tenant.
  - Usuarios por rol en la Empresa A (admin, coordinador, residente, 2 trabajadores).
  - 1 trabajador ITINERANTE que pertenece a A y a B (Sección 14.3).
  - 1 proyecto (obra de pavimentación MOP) con ítems jerárquicos asignados.

Los firebase_uid son legibles (p.ej. 'uid-coordinador-a') para poder autenticarse
en la demo con `Authorization: Bearer uid-coordinador-a`.
"""

from datetime import date, timedelta

from app.database import Base, SessionLocal, engine
from app.enums import EmpresaPlan, ItemEstado, Rol
from app.models import (
    Empresa, EmpresaUsuario, Item, Proyecto, ProyectoUsuario, Usuario,
)


def reset_db():
    """Borra y recrea todas las tablas (solo para demo)."""
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)


def run():
    reset_db()
    db = SessionLocal()
    try:
        # ── Super Admin ──────────────────────────────────────────────────────
        super_admin = Usuario(
            firebase_uid="uid-superadmin", nombre_completo="Soporte CTT",
            email="soporte@ctt.cl", es_super_admin=True,
        )
        db.add(super_admin)

        # ── Empresas (tenants) ───────────────────────────────────────────────
        emp_a = Empresa(nombre="Constructora Andes Sur SpA",
                        rut_empresa="76.123.456-7",
                        email_contacto="contacto@andessur.cl", plan=EmpresaPlan.PRO)
        emp_b = Empresa(nombre="Obras Biobío Ltda.",
                        rut_empresa="77.987.654-3",
                        email_contacto="admin@obrasbiobio.cl", plan=EmpresaPlan.BASIC)
        db.add_all([emp_a, emp_b])
        db.flush()

        # ── Usuarios de la Empresa A ─────────────────────────────────────────
        admin = Usuario(firebase_uid="uid-admin-a", nombre_completo="Patricia Reyes",
                        rut="12.345.678-9", email="patricia@andessur.cl")
        coord = Usuario(firebase_uid="uid-coordinador-a", nombre_completo="Jorge Muñoz",
                        rut="13.456.789-0", email="jorge@andessur.cl")
        resid = Usuario(firebase_uid="uid-residente-a", nombre_completo="Camila Soto",
                        rut="14.567.890-1", email="camila@andessur.cl")
        trab1 = Usuario(firebase_uid="uid-trabajador-1", nombre_completo="Luis Fuentes",
                        rut="15.678.901-2", email="luis@andessur.cl")
        trab2 = Usuario(firebase_uid="uid-trabajador-2", nombre_completo="Marcos Díaz",
                        rut="16.789.012-3", email="marcos@andessur.cl")
        # Trabajador itinerante: pertenece a A y a B (Sección 14.3).
        itiner = Usuario(firebase_uid="uid-itinerante", nombre_completo="Rosa Carrasco",
                         rut="17.890.123-4", email="rosa@especialistas.cl")
        db.add_all([admin, coord, resid, trab1, trab2, itiner])
        db.flush()

        # Membresías (empresa_usuario) con su rol.
        db.add_all([
            EmpresaUsuario(empresa_id=emp_a.id, usuario_id=admin.id, rol=Rol.ADMIN),
            EmpresaUsuario(empresa_id=emp_a.id, usuario_id=coord.id, rol=Rol.COORDINADOR),
            EmpresaUsuario(empresa_id=emp_a.id, usuario_id=resid.id, rol=Rol.RESIDENTE),
            EmpresaUsuario(empresa_id=emp_a.id, usuario_id=trab1.id, rol=Rol.TRABAJADOR),
            EmpresaUsuario(empresa_id=emp_a.id, usuario_id=trab2.id, rol=Rol.TRABAJADOR),
            # Itinerante: trabajador en A, residente en B (roles distintos por empresa).
            EmpresaUsuario(empresa_id=emp_a.id, usuario_id=itiner.id, rol=Rol.TRABAJADOR),
            EmpresaUsuario(empresa_id=emp_b.id, usuario_id=itiner.id, rol=Rol.RESIDENTE),
        ])

        # ── Proyecto de la Empresa A ─────────────────────────────────────────
        proyecto = Proyecto(
            empresa_id=emp_a.id,
            nombre="Pavimentación Ruta G-21, Tramo 3",
            descripcion="Conservación de calzada, contrato MOP.",
            ubicacion_nombre="Ruta G-21, Región Metropolitana",
            latitud=-33.35, longitud=-70.30,
            coordinador_principal_id=coord.id,
            fecha_inicio=date.today() - timedelta(days=20),
            fecha_fin_estimada=date.today() + timedelta(days=60),
            created_by=coord.id,
        )
        db.add(proyecto)
        db.flush()

        # Asignaciones al proyecto (proyecto_usuarios).
        db.add_all([
            ProyectoUsuario(proyecto_id=proyecto.id, usuario_id=resid.id, rol_en_proyecto=Rol.RESIDENTE),
            ProyectoUsuario(proyecto_id=proyecto.id, usuario_id=trab1.id, rol_en_proyecto=Rol.TRABAJADOR),
            ProyectoUsuario(proyecto_id=proyecto.id, usuario_id=trab2.id, rol_en_proyecto=Rol.TRABAJADOR),
        ])

        # ── Ítems jerárquicos ────────────────────────────────────────────────
        # Raíz (nivel 0)
        raiz = Item(proyecto_id=proyecto.id, nivel_profundidad=0,
                    nombre="Movimiento de tierras", created_by=coord.id, orden=1)
        db.add(raiz)
        db.flush()

        # Sub-ítems (nivel 1), uno ya en progreso y vencido (para reporte de retraso)
        sub1 = Item(proyecto_id=proyecto.id, parent_item_id=raiz.id, nivel_profundidad=1,
                    nombre="Excavación sector norte", asignado_a=trab1.id,
                    estado=ItemEstado.EN_PROGRESO, orden=1,
                    fecha_limite=date.today() - timedelta(days=2))  # vencido
        sub2 = Item(proyecto_id=proyecto.id, parent_item_id=raiz.id, nivel_profundidad=1,
                    nombre="Compactación base", asignado_a=trab2.id,
                    estado=ItemEstado.ABIERTO, orden=2,
                    fecha_limite=date.today() + timedelta(days=5))
        sub3 = Item(proyecto_id=proyecto.id, parent_item_id=raiz.id, nivel_profundidad=1,
                    nombre="Retiro de escombros", asignado_a=trab1.id,
                    estado=ItemEstado.TERMINADO, orden=3)
        db.add_all([sub1, sub2, sub3])

        db.commit()
        print("✓ Datos de demo cargados.")
        print("  Empresa A:", emp_a.id)
        print("  Tokens demo (Authorization: Bearer <uid>):")
        for u in (super_admin, admin, coord, resid, trab1, trab2, itiner):
            print(f"    {u.firebase_uid:20s} -> {u.nombre_completo}")
        print("  Itinerante: usar X-Empresa-Id para elegir empresa A o B.")
    finally:
        db.close()


if __name__ == "__main__":
    run()
