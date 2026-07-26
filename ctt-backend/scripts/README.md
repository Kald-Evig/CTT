# scripts/ — Herramientas de administración de datos

Scripts de uso manual para operaciones de mantenimiento. No forman parte de la API.
Correr siempre con el **venv activado** desde `ctt-backend/`.

Los scripts resuelven `app.*` automáticamente via `sys.path` — no hace falta
setear `PYTHONPATH` manualmente.

---

## reconciliar_uids.py — Diagnóstico de UIDs Firebase ↔ BD

**SOLO LECTURA. No modifica ningún dato.**

Compara el `firebase_uid` almacenado en la tabla `usuarios` contra el UID real
que Firebase Auth reporta para cada email. Clasifica cada fila en:

- `SANO` — uid en BD coincide con Firebase
- `DESAJUSTADO` — uid en BD es incorrecto (el email existe en Firebase bajo otro uid)
- `HUÉRFANO EN BASE` — el email no existe en Firebase Auth
- `ERROR (...)` — fallo de red o timeout al consultar Firebase

### Requisitos

- `GOOGLE_APPLICATION_CREDENTIALS` apuntando al service account JSON de Firebase Admin.
- El service account debe tener el rol **Firebase Authentication Admin** (o equivalente).
- Acceso a la base de datos PostgreSQL (`DATABASE_URL` en el entorno o default de desarrollo).

### Uso

```bash
python scripts/reconciliar_uids.py
```

### Output

```
EMAIL                                           | UID EN BASE                    | UID EN FIREBASE                | COINCIDE | ESTADO
...
Total: N  |  SANOS: N  |  DESAJUSTADOS: N  |  HUÉRFANOS: N  |  ERRORES: N
```

Imprime cada fila en el momento (flush), con timeout de 10s por llamada a Firebase.

---

## reparar_uids.py — Reparación de UIDs desajustados

> **MODIFICA DATOS.** Leer las advertencias antes de usar.

Repara los `firebase_uid` incorrectos en la tabla `usuarios` para las filas
clasificadas como `DESAJUSTADO` por `reconciliar_uids.py`.

**Nunca toca:**
- Filas `SANO` — ya están correctas.
- Filas `HUÉRFANO EN BASE` — el email no existe en Firebase; resolver manualmente.

**El cruce es siempre por EMAIL, no por uid.** El uid es exactamente lo que
puede estar mal, por eso nunca se usa como criterio de búsqueda.

### Requisitos

Mismos que `reconciliar_uids.py` (ver arriba). Requiere acceso de escritura
a la tabla `usuarios`.

### Modos de ejecución

```bash
# DRY-RUN (comportamiento por defecto) — NO modifica nada
# Muestra los UPDATE que se ejecutarían y los HUÉRFANOS que se omiten.
# Siempre correr esto primero y revisar la salida antes de aplicar.
python scripts/reparar_uids.py

# APLICAR — ejecuta los UPDATE sobre DESAJUSTADOS
# Re-verifica cada uid en Firebase justo antes de cada UPDATE.
# Muestra diagnóstico post-reparación.
python scripts/reparar_uids.py --aplicar
```

### Flujo recomendado

1. Correr `reconciliar_uids.py` para obtener el diagnóstico actual.
2. Correr `reparar_uids.py` (dry-run) y revisar los UPDATE que aparecen.
3. Si los UPDATE son correctos, correr `reparar_uids.py --aplicar`.
4. Correr `reconciliar_uids.py` de nuevo para confirmar que todo quedó `SANO`.

---

## alinear_emails.py — Renombrar emails en Firebase Auth

> **MODIFICA Firebase Auth.** La base de datos no se toca.

Renombra el email de cuentas de Firebase para que coincida con el email
registrado en la BD, **preservando el uid**. Se usa cuando el desajuste es
de email (la cuenta existe en Firebase bajo otro email) y no de uid.

**No es un script genérico.** Los pares de renombre están hardcodeados para
la operación puntual de CTT-86:

```
trabajador@ctt.cl  →  luis@andessur.cl
ctt@ctt.cl         →  soporte@ctt.cl
```

Para reutilizarlo con otros pares, editar la lista `RENOMBRES` en el script.

### Por qué no toca la BD

`auth.update_user(uid, email=nuevo_email)` cambia solo el email en Firebase.
El uid permanece igual. Como la BD cruza por uid (`firebase_uid`), ya está
correcta — no requiere ningún UPDATE.

### Verificaciones del dry-run (por cada par)

1. `email_viejo` existe en Firebase → muestra su uid.
2. `email_nuevo` **no** existe en Firebase → evita conflicto de email duplicado.
3. `email_nuevo` existe en la BD con `firebase_uid` == uid del paso 1 → confirma
   que el renombre resuelve el desajuste.

Si cualquiera falla, el script imprime `STOP:` y sale sin tocar nada.

### Requisitos

- `GOOGLE_APPLICATION_CREDENTIALS` apuntando al service account JSON de Firebase Admin.
- El service account debe tener el rol **Firebase Authentication Admin** (o equivalente).
- Acceso de lectura a la tabla `usuarios` (solo para verificar; no escribe en la BD).

### Modos de ejecución

```bash
# DRY-RUN (comportamiento por defecto) — NO modifica nada
# Corre las tres verificaciones por par y muestra qué haría.
# Revisar la salida antes de aplicar.
python scripts/alinear_emails.py

# APLICAR — ejecuta auth.update_user() en Firebase para cada par verificado
# Muestra diagnóstico post-reparación (tabla de reconciliación completa).
python scripts/alinear_emails.py --aplicar
```

### Flujo recomendado

1. Correr `reconciliar_uids.py` para confirmar qué filas son HUÉRFANO EN BASE.
2. Correr `alinear_emails.py` (dry-run) y revisar que las verificaciones pasan.
3. Que Kald autorice el `--aplicar`.
4. Correr `alinear_emails.py --aplicar`.
5. Correr `reconciliar_uids.py` de nuevo para confirmar 0 huérfanos.
