# CTT — Backend MVP

Motor backend de **CTT**, una plataforma *offline-first* de gestión de trabajadores en terreno para obras de construcción en Chile. Este repositorio contiene el **núcleo operativo** del sistema: modelo de datos multi-tenant, máquina de estados de ítems, matriz de permisos por rol y una API REST documentada — todo testeado y ejecutable en local sin infraestructura externa.

> Qué **es** este entregable: una base sólida y verificable del lado servidor.
> Qué **no es** (todavía): la app móvil Flutter, el motor de sincronización offline en el dispositivo, y la infraestructura de nube (Firebase/AWS). Ver `DEV_DOC.md` → *Alcance y límites*.

## Requisitos

- Python 3.11 o superior (probado en 3.12).
- Sin servicios externos: usa SQLite y autenticación *mock* para la demo.

## Arranque rápido

```bash
./run.sh
```

Esto instala dependencias, siembra datos de demo en `ctt_dev.db` y levanta la API en `http://127.0.0.1:8000`.

- **Documentación interactiva (Swagger):** http://127.0.0.1:8000/docs
- **Página de estado:** http://127.0.0.1:8000/
- **Healthcheck:** http://127.0.0.1:8000/health

Arranque manual equivalente:

```bash
pip install -r requirements.txt --break-system-packages
python -m app.seed
uvicorn app.main:app --reload
```

## Autenticación (modo demo)

El modo `mock` evita montar Firebase para probar localmente: el **token _es_ el `firebase_uid`**. Se envía como `Authorization: Bearer <uid>`. Si un usuario pertenece a varias empresas, se añade el header `X-Empresa-Id`.

Tokens sembrados por `app.seed`:

| Token (Bearer)        | Persona            | Rol                          |
|-----------------------|--------------------|------------------------------|
| `uid-superadmin`      | Soporte CTT        | Super Admin (plataforma)     |
| `uid-admin-a`         | Patricia Reyes     | Admin · Empresa A            |
| `uid-coordinador-a`   | Jorge Muñoz        | Coordinador · Empresa A      |
| `uid-residente-a`     | Camila Soto        | Residente · Empresa A        |
| `uid-trabajador-1`    | Luis Fuentes       | Trabajador · Empresa A       |
| `uid-trabajador-2`    | Marcos Díaz        | Trabajador · Empresa A       |
| `uid-itinerante`      | Rosa Carrasco      | Trabajador en A / Residente en B (requiere `X-Empresa-Id`) |

Ejemplo:

```bash
curl http://127.0.0.1:8000/proyectos \
  -H "Authorization: Bearer uid-coordinador-a"
```

## Tests

```bash
python -m pytest -q
```

41 tests cubren la máquina de estados (transiciones, reglas R1/R2/R3), la matriz de permisos, el aislamiento multi-tenant y el flujo operativo completo vía HTTP.

## Estructura

```
app/
  config.py         Configuración (pydantic-settings)
  enums.py          Enumeraciones del dominio (espejo del modelo de datos)
  database.py       Engine + sesión SQLAlchemy 2.0 (síncrono)
  models.py         Modelos ORM (multi-tenant)
  permissions.py    Matriz de permisos por rol (única fuente de verdad)
  state_machine.py  Máquina de estados de ítems (pieza crítica)
  auth.py           Resolución de contexto (mock / firebase)
  tenancy.py        Aislamiento por empresa
  notifications.py  Notificaciones (in-app + stub de email)
  schemas.py        Contratos Pydantic de entrada/salida
  routers/          Endpoints (proyectos, items, sync, reportes, ...)
  main.py           App FastAPI + página de estado
  seed.py           Datos de demo (chilenos)
tests/              Suite pytest
```

Para arquitectura, decisiones de diseño, extensiones al modelo y la ruta a producción, ver **`DEV_DOC.md`**.
