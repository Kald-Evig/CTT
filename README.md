# CTT — Frontend de revisión (MVP)

Cliente web para **revisar y probar end-to-end** el MVP de CTT contra el backend real. Sirve para que el equipo *vea* el sistema funcionando —roles, máquina de estados, reportes, notificaciones— sin esperar a la app móvil.

> **Qué es:** un arnés de revisión / pruebas E2E. Estética deliberadamente mínima.
> **Qué no es:** el frontend de producción. Según el DDT, el MVP de producción es **Flutter (móvil)**; la web (React) entra en Fase 2. Este cliente existe para desbloquear la revisión y las pruebas E2E hoy. Toda la lógica está en `app.js`; un dev puede reemplazar la estética sin tocarla, o usar esto como semilla del dashboard React de Fase 2.

## Requisitos

1. **El backend debe estar corriendo** (ver el README de la raíz). Por defecto en `http://127.0.0.1:8000`.
2. Datos de demo sembrados (`python -m app.seed`, ya incluido en `./run.sh`).

## Cómo ejecutarlo

Es HTML + JS plano, sin build. Dos opciones:

**A) Abrir el archivo directamente**

Abre `frontend/index.html` en el navegador (doble clic). El backend tiene CORS abierto para el MVP, así que las llamadas funcionan incluso desde `file://`.

**B) Servirlo con un servidor estático** (recomendado, evita rarezas de `file://`)

```bash
cd frontend
python -m http.server 5500
# luego abre http://127.0.0.1:5500
```

## Cómo usarlo

1. En la barra superior, confirma la **URL del backend** (default `http://127.0.0.1:8000`).
2. Elige un **usuario demo** del selector (rellena el token automáticamente) o pega un `firebase_uid`. Tokens disponibles:
   - `uid-coordinador-a` — crea proyectos e ítems, asigna, aprueba/rechaza.
   - `uid-trabajador-1` / `uid-trabajador-2` — ven sus tareas, Comenzar / Terminé / Reportar problema.
   - `uid-residente-a` — aprueba/rechaza, cierra problemas, asigna.
   - `uid-admin-a` — todo lo del coordinador + cerrar proyecto.
   - `uid-superadmin` — crear empresas (pestaña Plataforma).
   - `uid-itinerante` — pertenece a 2 empresas: requiere indicar **X-Empresa-Id**.
3. Click en **Conectar**.

La interfaz se adapta al rol (qué botones aparecen). El backend es siempre la autoridad: si una acción no está permitida, verás el error que devuelve el backend.

## Recorrido E2E sugerido (para mostrar la visión)

1. **Como `uid-coordinador-a`:** Proyectos → *Ver ítems* del proyecto "Pavimentación Ruta G-21". Crea un ítem raíz y un sub-ítem. Asigna el sub-ítem a un trabajador.
2. **Como `uid-trabajador-2`:** entra (Salir → reconectar con otro token). En su ítem asignado: **Comenzar** → **Terminé**.
3. **Como `uid-residente-a`:** el ítem aparece en *Pendiente revisión*. Pruébalo: **Rechazar** (pide comentario obligatorio) y luego, tras reenvío del trabajador, **Aprobar** → queda *Terminado*.
4. **Flujo de problema:** un trabajador en un ítem *En progreso* → **Reportar problema** (queda bloqueado). El residente → **Cerrar problema** (vuelve al estado previo).
5. **Reportes:** con un proyecto seleccionado, pestaña Reportes → Avance / Retrasos / Problemas / Actividad.
6. **Notificaciones:** revisa cómo al pasar un ítem a revisión le llega una notificación al residente.

## Estructura

```
frontend/
  index.html   Estructura + estilos mínimos + modal
  app.js       Toda la lógica (conexión, vistas, llamadas al backend)
  README.md    Este archivo
```

## Nota sobre la conexión con el backend

Para soportar este cliente, el backend incorpora dos cosas:
- **CORS abierto** (`CORS_ORIGINS=*` por defecto) — restringir al dominio real en producción.
- Un endpoint **`GET /me`** que resuelve usuario + empresa + rol, usado para adaptar la UI.

La simulación de "Foto" solo registra el metadato de evidencia; la subida binaria real va directo a S3 vía *pre-signed URL* desde el dispositivo (no aplica en este cliente de revisión).


# CTT — Backend MVP

Motor backend de **CTT**, una plataforma *offline-first* de gestión de trabajadores en terreno para obras de construcción en Chile. Este repositorio contiene el **núcleo operativo** del sistema: modelo de datos multi-tenant, máquina de estados de ítems, matriz de permisos por rol y una API REST documentada — todo testeado y ejecutable en local sin infraestructura externa.

> Qué **es** este entregable: una base sólida y verificable del lado servidor.
> Qué **no es** (todavía): la app móvil Flutter, el motor de sincronización offline en el dispositivo, y la infraestructura de nube (Firebase/AWS).

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
