# CTT — Documento de Desarrollo (Backend MVP)

**Versión:** 1.0.0-mvp · **Fecha:** junio 2026 · **Alcance:** núcleo backend ejecutable

Este documento describe lo que se construyó, lo que deliberadamente **no** se construyó en esta ronda, las decisiones de diseño que se tomaron y la ruta para llevar este núcleo a producción. Está escrito para ser leído tanto por el equipo técnico como por quien deba aprobar el avance.

---

## 1. Resumen honesto del alcance

El MVP completo descrito originalmente abarca cuatro frentes: backend, app móvil Flutter, sincronización offline con resolución de conflictos, e infraestructura en nube (Firebase + AWS). **Esos cuatro frentes no se pueden construir sin errores en una sola sesión, y menos verificar.** El más riesgoso —la sincronización offline con resolución de conflictos— no es comprobable sin dispositivos reales y pruebas de campo.

Por eso esta ronda entrega **un solo frente, completo y verificado: el motor backend.** La decisión fue construir la pieza que (a) es la base de la que dependen todas las demás, (b) concentra la lógica de negocio crítica, y (c) se puede testear de forma determinista hoy.

### Lo que SÍ está construido y probado

- Modelo de datos multi-tenant completo (empresas, usuarios, proyectos, ítems jerárquicos, problemas, evidencias, comentarios, historial, notificaciones, conflictos de sync).
- Máquina de estados de ítems con sus tres reglas de negocio, validada con 17 tests.
- Matriz de permisos por rol como única fuente de verdad.
- Aislamiento estricto entre empresas (un usuario de A no puede tocar datos de B).
- API REST completa, documentada automáticamente (Swagger en `/docs`).
- Suite de 41 tests, todos en verde.
- Datos de demo realistas (contexto chileno: MOP, RUT, obra vial).

### Lo que NO está construido (y por qué)

| Componente | Estado | Razón |
|---|---|---|
| App móvil Flutter | No iniciada | Es un proyecto en sí mismo; no es backend. |
| Motor de sync en dispositivo | Modelado, no implementado | Requiere el cliente Flutter y pruebas en campo. El backend solo expone la **cola y la resolución** de conflictos; la **ingesta** de cambios offline vive en el `SyncService` del cliente. |
| Firebase Auth real | Stub conmutable | El punto de cambio está aislado (`auth.py`); ver §6. |
| Subida binaria a S3 | Modelada como metadato | El backend registra la `s3_key`; la subida va directo del dispositivo a S3 vía *pre-signed URL*. |
| Exportación PDF / Excel de reportes | JSON sí, binarios no | Los reportes devuelven datos estructurados; el render a PDF/Excel es el paso siguiente (ver §6). |
| Dashboard web para gerencia | No construido | El DDT lo ubica en Fase 2. Ver §2. |

### Una contradicción del encargo que conviene nombrar

El MVP se definió como *mobile-first para obreros*, pero también como *"atractivo para altos mandos"*. Esas dos metas apuntan a artefactos distintos: lo primero es la app de terreno; lo segundo es un **dashboard gerencial**, que el propio DDT coloca en Fase 2. No se puede maximizar ambas en una primera entrega.

La resolución que se tomó: la cara "presentable" de **este** entregable es la **documentación interactiva Swagger** + la página de estado con identidad visual propia + datos de demo creíbles. Es honesto mostrar un backend sólido y bien documentado; sería deshonesto mostrar un dashboard a medias hecho de pantallas falsas. El dashboard real se construye sobre esta API cuando sea su turno.

---

## 2. Arquitectura

### 2.1 Stack de este prototipo

- **FastAPI** — framework HTTP; genera OpenAPI/Swagger automáticamente.
- **SQLAlchemy 2.0 (modo síncrono)** — ORM. Síncrono *a propósito*: menor superficie de error y 100% testeable hoy. La migración a `AsyncSession` es un cambio acotado (§6).
- **SQLite** — base de datos del prototipo. Se cambia a PostgreSQL por configuración, sin tocar los modelos.
- **Pydantic 2** — validación y contratos de entrada/salida.
- **Autenticación mock** — el token es el `firebase_uid`; conmutable a Firebase real.

### 2.2 Separación de responsabilidades

El código separa deliberadamente la **lógica de dominio** de la **capa HTTP**:

- `state_machine.py` y `permissions.py` no saben nada de HTTP. Se pueden testear en aislamiento y reusar desde cualquier interfaz.
- Los `routers/` traducen HTTP ↔ dominio: resuelven el contexto del usuario, aplican permisos, llaman al dominio y mapean errores de dominio a códigos HTTP (p. ej. `TransicionInvalida` → `409 Conflict`).
- `tenancy.py` es el único punto por el que se obtienen proyectos e ítems, garantizando el aislamiento por empresa: si un endpoint usa estos helpers, es imposible filtrar datos entre empresas.

Esta separación es lo que hace que el backend sea **portable**: el día que exista el dashboard web o se cambie Flutter por otra cosa, la lógica de negocio no se reescribe.

### 2.3 Modelo multi-tenant

Cada tabla de negocio lleva `empresa_id` (los ítems lo heredan vía su proyecto). El contexto de cada request resuelve *quién es el usuario, en qué empresa opera y con qué rol*, y todo el filtrado parte de ahí. El acceso cruzado entre empresas devuelve **404** (no 403) para no revelar siquiera la existencia de datos ajenos.

---

## 3. Máquina de estados (la pieza crítica)

Un error aquí corrompe el estado de una obra real, así que las transiciones se declaran **como datos** (una tabla de reglas), no como `if` dispersos, y se validan paso a paso: ¿existe la transición? ¿el rol puede ejecutarla? ¿se cumplen las condiciones (asignación, comentario, descripción)?

Estados: `ABIERTO → EN_PROGRESO → PENDIENTE_REVISION → TERMINADO`, con `PROBLEMA` como estado transversal.

Tres reglas de negocio, todas con test dedicado:

- **R1** — Un ítem en `PROBLEMA` no puede cambiar de estado hasta cerrar el problema.
- **R2** — Un ítem solo puede tener **un** problema abierto a la vez.
- **R3** — `TERMINADO` es irreversible; **solo un Admin** puede revertirlo (excepción explícita, con motivo obligatorio).

Al marcar un problema se guarda el `estado_previo`; al cerrarlo, el ítem se restaura a ese estado. Cada cambio queda en un **log de historial** (quién, cuándo, de qué estado a cuál, con qué detalle).

---

## 4. Extensiones al modelo de datos

Durante la implementación se añadieron campos/tablas que el DDT no detallaba pero que el comportamiento exigía. Se documentan aquí para que sean una decisión revisable, no un agregado silencioso:

- **`Item.estado_previo`** — necesario para restaurar el estado al cerrar un `PROBLEMA`. Sin él, la regla "volver al estado anterior" no es implementable.
- **`ItemHistorial`** — log de cambios de estado. El DDT pide "ver log de cambios" pero no modela la tabla; esta lo respalda.
- **`ItemComentario`** — comentarios por ítem (requeridos por el flujo de rechazo y por la matriz de permisos).
- **`Notificacion`** — notificaciones in-app persistidas, para soportar los eventos de notificación del DDT sin depender solo del email.

---

## 5. Ambigüedad del DDT que se resolvió por defecto

El DDT menciona una **profundidad máxima de jerarquía de ítems** sin fijar un número inequívoco. Se interpretó como **4 niveles de ítem** (índices 0 a 3), expuesto vía la configuración `MAX_NIVEL_PROFUNDIDAD = 3`. El límite de **hijos directos por ítem** se fijó en 10 (`MAX_HIJOS_DIRECTOS = 10`).

Ambos son parámetros de configuración, no constantes incrustadas: si la interpretación correcta era otra, se cambia en un solo lugar. **Conviene confirmar estos dos números con quien definió el DDT** antes de producción.

---

## 6. Ruta a producción

Cada pieza del prototipo tiene un punto de cambio acotado hacia el stack real:

1. **PostgreSQL** — cambiar `DATABASE_URL`. Los modelos no cambian. Migrar el tipo de PK a UUID nativo de Postgres si se desea.
2. **Migraciones (Alembic)** — hoy las tablas se crean con `create_all` al iniciar (apropiado para prototipo). En producción, reemplazar por migraciones versionadas.
3. **Async** — cambiar `create_engine`/`Session` por sus equivalentes async y añadir `await` en los routers. La sintaxis declarativa de los modelos es idéntica.
4. **Firebase Auth** — está aislado en `auth.py`: hay **un solo método** (`_resolver_uid`) que en modo `firebase` debe verificar el JWT con `firebase-admin`. El resto del flujo (uid → usuario → empresa → rol) ya funciona.
5. **S3 + evidencias** — generar *pre-signed URLs* para que el dispositivo suba la foto directo a S3; el endpoint de evidencias ya registra el metadato y la `s3_key`.
6. **Sincronización offline** — el backend ya modela la **cola de conflictos** y su **resolución manual** (local vs. servidor). Falta el `SyncService` del lado Flutter que ingiere los cambios encolados offline y detecta los conflictos. Es el trabajo de mayor riesgo y debe probarse en campo.
7. **Reportes PDF/Excel** — los endpoints ya devuelven los datos; añadir un render (p. ej. WeasyPrint para PDF, openpyxl para Excel) sobre esa misma data.
8. **Notificaciones** — el envío de email es hoy un stub. Conectar un proveedor real (p. ej. SES) en `notifications.py`.

---

## 7. Cómo verificar lo afirmado aquí

```bash
./run.sh                 # levanta la API con datos de demo
python -m pytest -q      # corre los 41 tests
```

Luego, en `http://127.0.0.1:8000/docs`, se puede ejecutar el ciclo completo de un ítem con los tokens de demo (ver `README.md`): crear proyecto, crear ítem, asignar, iniciar, marcar para revisión, aprobar — y comprobar que las reglas de estado y permisos se cumplen.

---

## 8. Nota sobre originalidad visual

La identidad visual (página de estado y, a futuro, el dashboard) usa una paleta **propia** —azul pizarra con ámbar de obra— y una organización que no replica la estética, los colores ni la disposición de competidores. La preocupación por evitar similitudes que deriven en disputas legales se tomó en serio: el diseño parte de cero, no de una referencia ajena.
