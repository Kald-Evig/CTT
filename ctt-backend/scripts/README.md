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
