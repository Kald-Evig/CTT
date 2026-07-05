# CTT — Marco Normativo LGUC/OGUC y Jerarquía Real de Cargos en Obra (Chile)

**Fecha:** 2026-07-02
**Origen:** Entrevista a ingeniero de obras públicas + investigación normativa.
**Propósito:** Corregir dos supuestos erróneos del proyecto y fijar el marco de referencia para el desarrollo futuro. Este documento debe leerse antes de tocar el modelo de roles, la Bitácora de Obra (Fase 2) o el posicionamiento comercial.

---

## 1. Corrección de supuestos (léase primero)

| # | Supuesto previo del proyecto | Realidad |
|---|---|---|
| 1 | CTT opera en el mundo MOP; la normativa relevante es la del MOP (LOD, bases de licitación). | El mundo MOP es la **excepción** normativa. El art. 116 de la LGUC exige permiso de la Dirección de Obras Municipales (DOM) para toda construcción, urbana o rural, y exime precisamente a las obras de infraestructura que ejecuta el Estado. Toda obra privada, municipal o SERVIU se rige por **LGUC (DFL 458/1975) + OGUC (D.S. 47/1992 MINVU)**. Si CTT vende a contratistas que hacen ambos tipos de obra, ambos marcos aplican. |
| 2 | El Residente "vive en terreno", hace "supervisión in-situ diaria" y podría además ejecutar labores de trabajador. | El Residente **no ejecuta partidas** — es un profesional (ingeniero, constructor civil, arquitecto) con rango y responsabilidad técnica distintos. Además, la permanencia diaria es propia de contratos MOP (donde el Profesional Residente tiene permanencia obligatoria en faena); en obra privada menor el profesional visita periódicamente (~cada 3 días según entrevista) y el día a día en terreno lo lleva el **jefe de obra / capataz**. El DDT v1.0 (secciones 2.1 y 7.2) mezcla ambos contextos. |

**Regla derivada:** los 5 roles de CTT son **roles de permisos de la app**, no cargos laborales. No confundir de nuevo. El cargo laboral (capataz, maestro 1ª, jornal…) es un **atributo** del usuario, no un rol nuevo.

---

## 2. LGUC + OGUC: qué regula y qué le importa a CTT

### 2.1 Estructura normativa

- **LGUC** — DFL N°458 (V. y U.) de 1975: la ley. Artículos clave para CTT: 18, 116, 116 bis, 142–146.
- **OGUC** — D.S. N°47 (MINVU) de 1992: el reglamento. Aplicación obligatoria en todo el país por todas las DOM. Artículos clave: 1.1.2 (definiciones), 1.2.7, 1.3.2, 5.1.16, 5.2.5–5.2.6, 5.8.3–5.8.5.
- Fiscaliza la **DOM** de cada comuna (art. 142 LGUC). Las infracciones se sancionan vía Juzgado de Policía Local (arts. 20–21 LGUC).

### 2.2 El Libro de Obras (art. 143 LGUC / arts. 1.1.2 y 1.2.7 OGUC) — CRÍTICO PARA CTT

Es la figura normativa que más se parece a lo que CTT ya construye (audit log + comentarios + historial). Requisitos legales:

1. **Obligatorio en toda obra con permiso DOM.** Debe mantenerse **en el lugar de la obra**, permanente y actualizado, durante toda la ejecución.
2. **Definición OGUC 1.1.2:** documento con **páginas numeradas** que forma parte del expediente oficial de la obra, donde consignan instrucciones y observaciones: profesionales competentes, instaladores autorizados, el ITO, el revisor independiente cuando corresponda, e inspectores de la DOM u organismos que autorizan instalaciones. Bomberos también puede dejar constancia (art. 142 LGUC).
3. **Responsable directo: el constructor a cargo de la obra** (OGUC 1.2.7). Formato tradicional: hojas originales + 2 copias, numeración correlativa (manifold triplicado).
4. **Carátula obligatoria (OGUC 1.2.7):** individualización del proyecto; número y fecha del permiso municipal; nombre del propietario; arquitecto; calculista; constructor a cargo; ITO si lo hubiere; revisor independiente si lo hubiere; revisor de cálculo estructural cuando corresponda; proyectistas de instalaciones/especialidades al iniciarse las obras respectivas. Cambios de propietario o de profesionales deben quedar registrados (+ procedimiento art. 5.1.20 OGUC).
5. **Cada anotación:** firmada, fechada y con identificación plena de quien la realiza.
6. **Cierre:** nota de cierre al terminar la obra, con firmas de los profesionales responsables. El **original se entrega a la DOM** al solicitar la Recepción Definitiva y queda archivado.
7. **Sanciones (OGUC 1.3.2):** son infracciones la inexistencia del Libro, sus adulteraciones, la omisión de firmas, o el incumplimiento injustificado de instrucciones.
8. **Paralización (art. 146 LGUC / 5.1.21 OGUC):** la DOM puede paralizar la obra si no se mantiene a la vista el legajo del art. 5.1.16 OGUC — que incluye el Libro de Obras y el documento de Medidas de Gestión y Control de Calidad.

**Formato digital — advertencia honesta:** la norma describe un documento físico foliado. Existen libros digitales con validez (LOD del MOP, LOD Codelco, ambos con firma electrónica avanzada), pero para obras DOM el estándar referenciado sigue siendo el libro físico y la aceptación de un formato digital varía por DOM. **CTT no debe venderse como reemplazo legal del Libro de Obras DOM** sin firma electrónica avanzada y validación caso a caso. Posicionamiento correcto: *registro operativo complementario, trazable y exportable*, que alimenta y respalda el libro oficial.

### 2.3 Medidas de Gestión y Control de Calidad — MGCC (art. 143 LGUC / 5.8.3–5.8.5 OGUC)

- Documento obligatorio, mantenido en obra durante toda la ejecución, a disposición de profesionales, ITO e inspectores DOM.
- Contenido mínimo: medidas técnicas y de seguridad de ejecución/demolición/excavación; ensayes y certificaciones obligatorias; autorizaciones especiales de faenas; mitigación de ruido y polvo; acopio de materiales; aseo de obra y espacio público; **programa de trabajo y horarios**.
- Al terminar, el constructor presenta **declaración jurada** de que las medidas fueron aplicadas. El informe MGCC es requisito de la Recepción Definitiva.
- Relevancia CTT: el "programa de trabajo" y los registros de ejecución que CTT ya captura (ítems, estados, fechas, evidencia fotográfica) son exactamente el tipo de respaldo que un constructor necesita para sostener su declaración jurada.

### 2.4 Actores que la LGUC define y CTT no modela

| Actor LGUC | Qué es | Relación con CTT |
|---|---|---|
| **Constructor a cargo de la obra** | Profesional responsable de la ejecución y de las MGCC (art. 143). Su designación formal ante la DOM es requisito; una obra **sin constructor a cargo puede ser paralizada** (art. 146). | Es el cliente natural de CTT (la constructora / su profesional responsable). En el modelo actual mapea aproximadamente a Admin/Coordinador. |
| **ITO — Inspector Técnico de Obra** (art. 18 y 143 LGUC, Ley 20.703) | Supervisa que la obra se ejecute conforme a normas, permiso y proyectos. **Independiente del constructor.** Obligatorio en edificios de uso público. Registro Nacional (MINVU / Instituto de la Construcción). Debe registrar en el Libro de Obras la supervisión de partidas. Responsabilidad subsidiaria con el constructor. | **No existe en CTT y es un problema de modelo multi-tenant:** el ITO no es empleado de la constructora (tenant), es un tercero con derecho a leer y anotar. Fase 2+: actor externo con acceso de lectura/anotación acotado a una obra. |
| **Revisor Independiente** (art. 116 bis, Ley 20.703) | Revisa el proyecto; contratación generalmente voluntaria (con rebaja de derechos municipales), obligatoria en uso público. Libre acceso a la obra durante ejecución. | Mismo patrón que ITO: tercero externo. No requiere modelado en MVP. |
| **Inspectores DOM / Bomberos** | Fiscalizadores con derecho a dejar constancia en el Libro de Obras. | Solo relevante si CTT llega a implementar Libro de Obras con validez: sus anotaciones deben poder existir. |
| **Proyectistas** (arquitecto, calculista, especialidades) | Anotan en el Libro cambios, aclaraciones de planimetría, recepción conforme de etapas de estructura (OGUC 1.2.14). | Ídem: actores externos con derecho de anotación. |

**Patrón de diseño que esto revela:** el sistema hoy asume que todo usuario pertenece al tenant. La normativa privada gira en torno a **actores externos e independientes** con derecho de lectura/anotación sobre una obra específica. No implementar en MVP; **no diseñar nada que lo haga imposible** (p. ej., no acoplar permisos exclusivamente a `empresa_id` en la futura Bitácora).

### 2.5 Recepción Definitiva (art. 144 LGUC / 5.2.5–5.2.6 OGUC)

Al cierre de obra se exige, entre otros: informe del arquitecto (y del revisor independiente si lo hubo) certificando ejecución conforme al permiso; **informe del ITO** si lo hubo; **informe MGCC** suscrito por el constructor; **Libro de Obras** con carátula conforme, firmas en cada anotación y nota de cierre. La DOM revisa solo normas urbanísticas; el resto queda bajo responsabilidad de los profesionales (arts. 17, 18, 20 LGUC).

**Oportunidad de producto (Fase 2):** "expediente de recepción" — exportar desde CTT el paquete cronológico (historial + evidencia + comentarios) en PDF con formato compatible con lo que la DOM espera ver.

---

## 3. Jerarquía real de cargos en una obra chilena

Línea de mando típica de una constructora (edificación/OO.CC.); en obras pequeñas una persona acumula varios cargos:

```
OFICINA / EMPRESA
├── Gerente de operaciones / Visitador de obra   (varias obras)
├── Administrador de Obra (o de Contrato)        (responsable del contrato: costos, plazos, cliente)
│
TERRENO — PROFESIONALES / MANDO MEDIO
├── Profesional Residente / Jefe de Terreno      (responsable técnico de ejecución; en MOP: permanencia
│                                                 obligatoria en faena; en obra privada menor: visitas
│                                                 periódicas ~cada 2-3 días)
├── Jefe de Obra                                  (mando medio calificado: interpreta, controla y organiza
│                                                 la ejecución según EE.TT., bajo supervisión de un
│                                                 profesional superior — presencia diaria)
├── Capataz                                       (conduce cuadrillas por sector u oficio; presencia diaria;
│                                                 puede haber varios por obra)
├── Supervisor de terreno / Sobrestante           (variante o apoyo del anterior según empresa)
│
TERRENO — MANO DE OBRA (oficios)
├── Maestro Mayor / Maestro técnico               (especialista instalador: closets, ascensores, clima…)
├── Maestro de Primera                            (oficio consolidado, terminaciones de calidad y precisión,
│                                                 lee planos: carpintero, albañil, enfierrador, ceramista,
│                                                 gásfiter, eléctrico, trazador…)
├── Maestro de Segunda                            (obra gruesa, menor precisión requerida)
├── Ayudante                                      (asiste a un maestro, en formación de oficio)
└── Jornal                                        (labores no especializadas: excavación, demolición,
                                                  andamios, aseo, picado)

APOYO (no línea de mando de ejecución)
├── Prevencionista de riesgos (PdR)
├── Oficina técnica (cubicaciones, EE.TT., programación)
└── Bodeguero / Almacenista
```

Notas:
- "Jefe de Terreno" y "Jefe de Obra" se usan a veces como sinónimos; en empresas grandes el Jefe de Terreno es profesional (reporta al Administrador de Obra y tiene a capataces bajo su mando) y el Jefe de Obra es mando medio de origen obrero calificado (formación tipo ENOC U. de Chile).
- El oficio absorbe el título: un maestro especializado se nombra por su oficio ("el enfierrador", "el carpintero"), no como "maestro".
- **El Residente/profesional no ejecuta partidas.** Aprobación técnica, instrucciones, Libro de Obras: sí. Mezcla de hormigón: no.

### 3.1 Mapeo cargos reales → roles de app CTT

| Cargo real | Rol de permisos CTT | Comentario |
|---|---|---|
| Gerente / Visitador / Administrador de Obra | **Coordinador** (o Admin) | Coincide con "oficina, múltiples proyectos". |
| Profesional Residente / Jefe de Terreno | **Residente** | El nombre CTT se mantiene (reconocible en el mercado MOP), pero documentar que en obra privada equivale a "profesional a cargo / jefe de terreno" y que su presencia puede ser periódica, no diaria. |
| Jefe de Obra / Capataz / Supervisor | **Hoy no existe** → hoy caería en Trabajador o Residente, ambos incorrectos | Ver decisión pendiente §4.2. |
| Maestros (mayor/1ª/2ª), Ayudante, Jornal | **Trabajador** | Correcto. El detalle del cargo es un atributo, no un rol. |
| ITO, Revisor Independiente, DOM, proyectistas | **No existen** (externos al tenant) | Fase 2+, ver §2.4. |

---

## 4. Decisiones e impactos en el proyecto

### 4.1 Cambios de documentación (ahora, costo ~0)

- **DDT §2.1:** corregir "El Residente vive en terreno / supervisión in-situ diaria" → "El Residente es el responsable técnico in-situ. En contratos MOP su permanencia en faena es obligatoria; en obra privada su presencia puede ser periódica, delegando el día a día en jefes de obra y capataces". Eliminar toda implicación de que el Residente ejecuta labores de trabajador.
- **DEV_DOC.md:** referenciar este documento como fuente de verdad sobre cargos y normativa.
- Ancla actualizada: **Residente = responsable técnico de terreno (no operario, no necesariamente diario). Coordinador = oficina.**

### 4.2 Decisión pendiente de producto — figura del Capataz/Jefe de Obra

La entrevista revela que quien está **todos los días** en terreno no es el Residente sino el capataz/jefe de obra. Opciones:

- **(a) MVP, sin cambio de esquema:** un capataz se registra como Trabajador; el Residente le asigna ítems como a cualquiera. Limitación: no puede reasignar ítems de su cuadrilla ni hacer verificación de primer nivel.
- **(b) Fase 2 — rol intermedio "Capataz":** puede ver los ítems de su(s) proyecto(s) asignado(s), reasignar dentro de su cuadrilla y marcar "verificado en terreno" (paso previo, no sustituto, de la aprobación del Residente). Encaja con la máquina de estados existente sin nuevo estado obligatorio.
- **Recomendación: (a) ahora + validar (b) con el ingeniero entrevistado y con Jorge Muñoz antes de comprometerlo.** No agregar roles por especulación — cada rol nuevo multiplica la matriz de permisos y los tests.

### 4.3 Cambio de esquema barato — atributo `cargo`

Agregar a `usuarios` un campo **`cargo`** (VARCHAR/enum, NULLABLE): `administrador_obra | jefe_terreno | jefe_obra | capataz | maestro_mayor | maestro_primera | maestro_segunda | ayudante | jornal | prevencionista | bodeguero | otro`. Es informativo (reportes, futura Bitácora, futura integración RR.HH. vía RUT), **no afecta permisos**. Programar junto con CTT-49 (Alembic) para no generar migración suelta.

### 4.4 Bitácora de Obra (Fase 2) — ahora con especificación legal

La feature ya marcada como alta prioridad deja de ser genérica: si apunta a obras LGUC debe cumplir OGUC 1.2.7 —

- Carátula con los campos del §2.2.4 (incluye número/fecha de permiso DOM → **nuevos campos en `proyectos`**: `permiso_dom_numero`, `permiso_dom_fecha`, `propietario`, y registro de profesionales de la obra).
- Anotaciones **inmutables, foliadas, fechadas y con identidad plena del autor** → la arquitectura `audit_log` append-only + folio ya apunta en esta dirección; el race condition del folio (CTT-49/CTT-51) pasa de "deuda técnica" a **requisito de integridad legal**.
- Registro de cambios de profesionales/propietario durante la obra.
- Nota de cierre con firmas al término.
- Export PDF del libro completo para entrega a la DOM.
- Anotaciones de actores externos (ITO, DOM, proyectistas) → requiere el modelo de actor externo del §2.4.
- **Sin firma electrónica avanzada, se comercializa como registro operativo complementario, no como Libro de Obras legal.**

### 4.5 Posicionamiento comercial

- El mercado direccionable es mayor al asumido: no solo contratistas MOP, sino toda constructora con permisos DOM (edificación privada, SERVIU, municipal). El discurso de venta cambia de "cumplimiento MOP/LOD" a "trazabilidad exigida por LGUC/OGUC + operación offline".
- Riesgo del claim: nunca prometer "reemplaza el Libro de Obras". Prometer "respalda tu Libro de Obras y tu declaración jurada de MGCC con evidencia trazable".

### 4.6 Qué NO cambia

- La matriz de permisos del MVP y la máquina de estados quedan intactas.
- Los 5 roles de permisos se mantienen. No se crean roles nuevos en MVP.
- El foco MVP (mobile, offline, sync) no se toca.

---

## 5. Preguntas abiertas (validar con el ingeniero entrevistado / Jorge Muñoz)

1. En las obras objetivo (contratistas pequeños/medianos), ¿quién llenarría CTT a diario en la práctica: el capataz, el jefe de obra o el propio trabajador? (Define si la opción (b) del §4.2 es necesaria.)
2. ¿Los clientes objetivo hacen mayormente obra MOP, obra DOM, o mixto? (Define prioridad entre integración LOD-MOP vs. formato Libro de Obras OGUC.)
3. ¿Alguna DOM de las comunas objetivo acepta libro digital hoy? (Evidencia real antes de invertir en firma electrónica avanzada.)
4. ¿El campo `cargo` debe ser enum cerrado o texto libre con sugerencias? (Los cargos varían por empresa.)

---

## 6. Fuentes

- LGUC — DFL 458/1975, texto actualizado MINVU (enero 2025): minvu.gob.cl (Ley General)
- OGUC — D.S. 47/1992 MINVU, texto actualizado: minvu.gob.cl / bcn.cl (idNorma=8201)
- Art. 143 LGUC (Libro de Obras, MGCC, ITO): leyes-cl.com/aprueba_nueva_ley_general_de_urbanismo_y_construcciones/143.htm
- Guía Libro de Obras, DOM Las Condes (2021): archivos.lascondes.cl (RD-GUIA-LIBRO-DE-OBRAS)
- DDU 273 MINVU (Ley 20.703, ITO y revisores): minvu.gob.cl/wp-content/uploads/2019/06/DDU-273.pdf
- Requisitos Recepción Definitiva, DOM Las Condes: archivos.lascondes.cl (RD-LISTADO-RECEPCION-DEFINITIVA)
- FAQ DOM Pucón (paralización art. 146, legajo 5.1.16): municipalidadpucon.cl
- Libro de Obras — consideraciones: arqydom.cl / chilecubica.com / arquitectosrevisores.cl
- Mano de obra y oficios en Chile (maestros 1ª/2ª, ayudantes, jornales): chilecubica.com/estudio-costos/mano-de-obra/
- Perfil Jefe de Terreno (línea de mando: Administrador de Obra → Jefe de Terreno → capataces): munipuchuncavi.cl (perfil de cargo)
- Jefe de Obra como mando medio calificado: ENOC, FAU Universidad de Chile (fau.uchile.cl/cursos/166146)
- Estudio Cargos Críticos para Productividad en Edificación (Construye2025/CChC): construye2025.cl
- LOD MOP: dgop.mop.gob.cl/carpeta-digital · LOD Codelco: codelco.com/proveedores/libro-de-obra-digital-lod
