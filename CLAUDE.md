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
