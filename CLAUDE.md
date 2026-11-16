## Regla de trabajo permanente: auditar antes de construir

Antes de cualquier desarrollo, modificación o corrección de código:

1. **Verificar contra la realidad primero.** Revisar el código actual, la BD,
   y/o los tests con comandos reales (grep, SQL, leer el archivo) para confirmar
   qué existe de verdad. Nunca asumir el estado del sistema a partir de:
   - el estado de un ticket de Jira,
   - el nombre de un modelo, clase o archivo,
   - un resumen de una sesión anterior.

2. **Reportar la evidencia y PAUSAR** antes de escribir o modificar nada.
   Mostrar qué se encontró (endpoint exacto, archivo:línea, schema real) y
   esperar confirmación antes de construir.

3. **Si una instrucción contradice lo que ya está construido, señalarlo**
   en vez de resolver la contradicción en silencio. (Ej: si se pide mantener
   un nombre de campo que ya cambió, avisar; no elegir uno por cuenta propia.)

4. **Arreglar bugs en el momento** cuando se encuentran dentro de código que ya
   se está tocando — no diferir.

5. **Al reportar resultados, mostrar evidencia cruda**: el código real (no un
   resumen parafraseado) y el output completo de los tests (no "X passed"
   reescrito). El revisor valida contra el artefacto real, no contra el resumen.

## Regla de trabajo permanente: DRY con criterio (search-first)

Antes de escribir un helper, componente, función, utilidad, clase o pantalla
NUEVA —y antes de copiar código existente para una variante— aplicar la
disciplina `dry-con-criterio`:

1. **Buscar primero (search-first).** `grep`/`Glob` del concepto en TODO el repo
   antes de crear nada: casi siempre ya existe un helper/patrón que cubre el caso
   o que conviene parametrizar.

2. **Árbol extraer-vs-duplicar.** Si hay código parecido en dos lugares, decidir
   explícitamente entre extraer una abstracción, parametrizar lo existente, o
   duplicar a propósito — no unificar por reflejo ni copiar por inercia.

3. Aplica aunque la tarea parezca chica, aunque copiar parezca más rápido, y
   aunque el código parecido "obviamente" deba unificarse.

## Regla de trabajo permanente: idioma neutro (sin voseo)

Todo texto **visible para el usuario** (Text, SnackBar, diálogos, labels,
mensajes de validación) va en **español latinoamericano NEUTRO**, usando la 2ª
persona **tú** — nunca voseo argentino:

- "tienes" (no "tenés"), "puedes" (no "podés"), "ingresa" (no "ingresá"),
  "toca" (no "tocá"), "elige" (no "elegí"), "revisa" (no "revisá").

Los **comentarios** de código quedan como estén (no son de usuario). Al escribir
o revisar strings, correr
`grep -rnE "\b(tenés|podés|querés|ingresá|tocá|elegí|revisá|intentá|hacé)\b" lib/`
y dejar el resultado vacío.

La regla **también aplica a los mensajes del agente de Code hacia Kald y a los
mensajes de commit**, no solo a los textos de la UI: "reconecta", "acepta",
"activa", "abre", "espera", "avísame", "tienes", "puedes" — nunca "reconectá",
"aceptá", "tenés", "podés".

## Entorno local de desarrollo (vigente desde el 12-nov-2026)

El disco **C: tiene poco espacio**: no generes ni descargues artefactos pesados
ahí. Todo lo pesado (AVDs, caché de Gradle, builds) va a **D:**.

- **AVDs:** `ANDROID_AVD_HOME=D:\Android\avd` (contiene `CTT_API30` y `Pixel_6`).
- **Gradle:** `GRADLE_USER_HOME=D:\Android\.gradle`.
- `C:\Users\souls\.android\avd` y `C:\Users\souls\.gradle` **ya no se usan**: no
  los recrees ni apuntes Gradle/AVDs de vuelta a C:. Si un build recrea
  `C:\Users\souls\.gradle`, es señal de que las variables no están tomando efecto
  — detente y repórtalo (no hagas workarounds en C:).
- El **Android SDK sí sigue en C:** (`sdk.dir=C:\Users\souls\AppData\Local\Android\Sdk`
  en `android/local.properties`, que es gitignored/machine-specific). El traslado
  fue solo de AVDs y de la caché de Gradle, no del SDK.
- En scripts y evidencia usa las **variables** (`$ANDROID_AVD_HOME`,
  `$GRADLE_USER_HOME`), nunca rutas absolutas de C:.
- **Precondición antes de buildear/emular:** en el shell,
  `echo $ANDROID_AVD_HOME $GRADLE_USER_HOME` debe mostrar las rutas de D:. Si salen
  vacías (un shell abierto antes del cambio no las hereda), detente y pide reiniciar
  la terminal o VS Code — no las exportes a mano como solución.
- `emulator -list-avds` debe listar `CTT_API30` y `Pixel_6`; `D:\Android\avd\*.ini`
  tiene `path=` apuntando a D:.

## Regla de trabajo permanente: encoding de las salidas guardadas

Toda salida de texto que se guarde desde **PowerShell** se escribe en **UTF-8**
(el contrato de evidencia exige UTF-8), nunca con el operador `>` ni con
`Tee-Object`/`Out-File` por defecto: en Windows PowerShell 5.1 el `>` produce
**UTF-16 LE con BOM**, que no es UTF-8.

- Texto: usar `Out-File -Encoding utf8` o `Set-Content -Encoding utf8` (o, para
  UTF-8 **sin BOM**, `[System.IO.File]::WriteAllText(path, texto, (New-Object System.Text.UTF8Encoding $false))`).
  Preferible aún: escribir los archivos de evidencia con la herramienta Write.
- **Binarios** (PNG, APK, .db): nunca redirigir la salida de un comando nativo a un
  archivo con `>` (lo corrompe). Sacarlos con `adb pull`, `Copy-Item`, o
  `[System.IO.File]::WriteAllBytes`.
- Verificar el encoding con `file <archivo>` (tool Bash) cuando importe.

Incidentes que originaron la regla:
- **CTT-142:** un screenshot capturado con `adb exec-out screencap -p > login1.png`
  quedó en UTF-16 y no era un PNG válido; hubo que recapturarlo con `adb pull`.
- **CTT-153:** `.evidencia/ctt153_pre_{cliente,backend}.txt` se guardaron con
  `Tee-Object`/`>` en UTF-16 LE y hubo que reconvertirlos a UTF-8.
