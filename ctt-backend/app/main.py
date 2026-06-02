"""
main.py — Punto de entrada de la API CTT.

- Crea las tablas al iniciar (en prototipo; en producción esto lo hace Alembic).
- Monta todos los routers.
- Expone una página raíz con la identidad visual propia de CTT (NO se inspira en
  ningún competidor): paleta azul pizarra + ámbar de obra, sobria y para gerencia.
- La documentación interactiva (Swagger) queda en /docs — es la cara "presentable"
  de este entregable de backend.
"""

from fastapi import FastAPI
from fastapi.responses import HTMLResponse

from app.config import settings
from app.database import Base, engine
# Importar modelos registra las tablas en la metadata de Base.
from app import models  # noqa: F401
from app.routers import (
    items, notificaciones, plataforma, proyectos, reportes, sync, usuarios,
)

app = FastAPI(
    title=settings.APP_NAME,
    version=settings.APP_VERSION,
    description=(
        "API del MVP de CTT — plataforma offline-first de gestión de trabajadores "
        "en terreno para obras de construcción en Chile. "
        "Modo de autenticación actual: **%s**." % settings.AUTH_MODE
    ),
)

# Crear el esquema en la BD. En producción se reemplaza por migraciones Alembic.
Base.metadata.create_all(bind=engine)

# Montaje de routers.
for r in (plataforma.router, usuarios.router, proyectos.router, items.router,
          sync.router, reportes.router, notificaciones.router):
    app.include_router(r)


@app.get("/health", tags=["Sistema"])
def health():
    """Healthcheck para balanceadores / monitoreo."""
    return {"status": "ok", "app": settings.APP_NAME, "version": settings.APP_VERSION}


@app.get("/", response_class=HTMLResponse, tags=["Sistema"])
def root():
    """Página de estado con identidad visual propia de CTT (paleta original)."""
    return f"""<!doctype html>
<html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{settings.APP_NAME}</title>
<style>
  :root {{ --pizarra:#16263b; --pizarra-2:#21384f; --ambar:#f0a323; --niebla:#eef2f6; --texto:#0d1b2a; }}
  * {{ box-sizing:border-box; }}
  body {{ margin:0; font-family:'Segoe UI',system-ui,sans-serif; color:var(--texto);
          background:linear-gradient(160deg,var(--pizarra),var(--pizarra-2)); min-height:100vh; }}
  .wrap {{ max-width:760px; margin:0 auto; padding:64px 24px; color:var(--niebla); }}
  .logo {{ display:inline-flex; align-items:center; gap:14px; margin-bottom:8px; }}
  .mark {{ width:44px; height:44px; border-radius:10px; background:var(--ambar);
           display:grid; place-items:center; font-weight:800; color:var(--pizarra); font-size:22px; }}
  h1 {{ font-size:30px; margin:18px 0 4px; letter-spacing:-.5px; }}
  .sub {{ opacity:.8; margin:0 0 32px; }}
  .card {{ background:rgba(255,255,255,.06); border:1px solid rgba(255,255,255,.12);
           border-radius:14px; padding:22px 24px; margin-bottom:14px; }}
  .card h2 {{ font-size:15px; text-transform:uppercase; letter-spacing:1px;
              color:var(--ambar); margin:0 0 10px; }}
  a {{ color:var(--ambar); font-weight:600; text-decoration:none; }}
  a:hover {{ text-decoration:underline; }}
  .pill {{ display:inline-block; font-size:12px; padding:3px 10px; border-radius:999px;
           background:rgba(240,163,35,.18); color:var(--ambar); margin-left:8px; }}
  code {{ background:rgba(0,0,0,.25); padding:2px 7px; border-radius:6px; }}
</style></head>
<body><div class="wrap">
  <div class="logo"><div class="mark">C</div>
    <strong style="font-size:20px;">CTT</strong>
    <span class="pill">MVP · v{settings.APP_VERSION}</span></div>
  <h1>Field Service Management</h1>
  <p class="sub">Backend operativo. Gestión de obra offline-first para Chile.</p>
  <div class="card"><h2>API en línea</h2>
    <p>Documentación interactiva: <a href="/docs">/docs</a> · Esquema: <a href="/openapi.json">/openapi.json</a></p></div>
  <div class="card"><h2>Autenticación (demo)</h2>
    <p>Modo <code>{settings.AUTH_MODE}</code>. Envíe <code>Authorization: Bearer &lt;firebase_uid&gt;</code>.
    Si pertenece a varias empresas, agregue <code>X-Empresa-Id</code>.</p></div>
  <div class="card"><h2>Estado</h2><p>Servicio saludable · <a href="/health">/health</a></p></div>
</div></body></html>"""
