# CTT — Marco Normativo Complementario: RCOP/MOP, Registro de Contratistas, Normativa Laboral y SERVIU

**Fecha:** 2026-07-02
**Documento hermano de:** `NORMATIVA_LGUC_Y_CARGOS_OBRA.md` (que cubre LGUC/OGUC y jerarquía de cargos).
**Propósito:** Cerrar los cuatro huecos normativos identificados el 02-jul-2026. Este documento es material de consulta para decisiones futuras de producto, no genera trabajo de desarrollo inmediato salvo lo indicado en §6.
**Ticket asociado:** CTT-55 (registro de decisión).

---

## 0. Resumen ejecutivo — lo que cambia para CTT

1. **El nombre y rol "Residente" de CTT proviene del ecosistema MOP** (RCOP + LOD), donde el "profesional residente" es la contraparte formal del Inspector Fiscal. En obra privada LGUC esa figura no existe con ese nombre. Ya documentado en el doc hermano; aquí se agrega la base normativa MOP.
2. **Existen al menos TRES "libros" oficiales distintos según el mandante** (LOD-MOP, Libro de Obras LGUC, Libro de Inspección SERVIU). La Bitácora de CTT debe ser agnóstica del libro oficial: registro operativo que alimenta a cualquiera de ellos, nunca reemplazo de ninguno.
3. **El riesgo normativo más filoso para CTT no es de construcción sino LABORAL:** la Resolución Exenta N°38/2024 de la Dirección del Trabajo regula todo sistema electrónico que sirva —directa o **indirectamente**— para obtener información de asistencia y horas de trabajo, y exige autorización previa de la DT. Dos features del roadmap de CTT (GPS tracking Fase 2; "asistencia y permanencia por centro de costo" del pitch minero) chocan de frente con esto si no se diseñan con cuidado.
4. **Ley 20.123 (subcontratación) convierte al mandante en fiscalizador de sus contratistas** para bajar su responsabilidad de solidaria a subsidiaria. Eso es una oportunidad de producto para la Fase 2 minera (el módulo de "control de contratistas" tiene demanda legal real), pero también implica que CTT-como-empleador debe cumplirla cuando crezca.

---

## 1. Frente 1 — RCOP: Reglamento para Contratos de Obras Públicas (D.S. MOP N°75/2004)

### 1.1 Naturaleza y alcance

- El RCOP **forma parte integrante de todos los contratos de ejecución de obras del MOP**, sus Direcciones Generales y Servicios, y de las instituciones que se relacionan con el Estado por su intermedio (art. 1). No es una guía: es cláusula contractual automática.
- Para contratar cualquier obra deben existir previamente: autorización de fondos, **bases administrativas, bases de prevención de riesgo y medioambientales, especificaciones técnicas, planos y presupuesto** — todos esos documentos forman parte del contrato, con orden de precedencia fijado en las bases (art. 2).
- Consecuencia práctica: **el detalle operativo (perfil del residente, permanencia exigida, multas específicas, plazos) vive en las Bases Administrativas de cada contrato**, no en el RCOP mismo. El RCOP da el marco; las bases lo concretan. Por eso "¿cuánto debe estar el Residente en obra?" no tiene una respuesta única MOP — depende de las bases del contrato.

### 1.2 Libro de Obras MOP (art. 4 N°44 y arts. 110+)

- Definición RCOP (art. 4, texto vigente tras D.S. 810): libro que contiene **toda comunicación que el Inspector Fiscal dirija al contratista** en relación al cumplimiento del contrato, además de las anotaciones del desarrollo: resolución de adjudicación, **identificación del Inspector Fiscal, del profesional residente, subcontratistas autorizados, especialistas, prevencionista de riesgos**, etc.
- **Puede sustentarse en soporte papel o digital, según lo establezcan las Bases Administrativas del contrato.** Esta es la puerta legal del LOD.
- El detalle operativo del LOD (folios inalterables, FEA, libro maestro unidireccional donde solo escribe el IF, acuse de lectura del Residente, libros auxiliares por especialidad) ya está documentado en `Audit_Log_Operativo...md` (Res. DGOP N°258/2009 + documentación SGO). No se duplica aquí.

### 1.3 Roles contractuales MOP (contraste con roles CTT)

| Rol contractual MOP | Quién es | Contraparte en CTT |
|---|---|---|
| **Inspector Fiscal (IF)** | Funcionario/representante del MOP que fiscaliza el contrato. Único que escribe en el libro maestro del LOD. Su cambio es un acto administrativo registrado. | **No existe y no debe existir como usuario del tenant.** Es el "cliente del cliente". Si algún día CTT integra con LOD, el IF es un actor externo de solo lectura/referencia. |
| **Profesional Residente** | Representante técnico del contratista en la obra, contraparte del IF. En el LOD, deja constancia de lectura de folios con FEA. Identificado nominalmente en el Libro de Obras. | **Residente** de CTT. El nombre calza; la formalidad no está modelada (CTT no registra quién es "el" residente oficial de un proyecto ante el mandante — hoy puede haber varios residentes sin jerarquía). |
| **Prevencionista de riesgos** | Identificado en el Libro de Obras; exigido en el Registro de Contratistas para 2ª y 3ª categoría (contrato al menos part-time de 1 año). | No existe. Candidato natural para el atributo `cargo` (ya incluido en la lista de CTT-55). |
| **Subcontratistas autorizados** | Deben constar en el Libro con sus autorizaciones. | No modelado. Relevante para Fase 2 minera (ver §3). |

**Implicación de producto (diferir, anotar):** si CTT quiere ser útil en obra MOP, el proyecto debería poder registrar metadata contractual: N° de contrato/resolución, Inspector Fiscal (texto), profesional residente oficial, subcontratistas. Cabe en el `metadata` JSONB extensible ya previsto en el diseño del audit log — no requiere schema nuevo.

### 1.4 Multas, estados de pago, recepciones (nivel de conciencia, no de implementación)

- El ciclo económico MOP opera vía **Estados de Pago** (avance físico y financiero, anticipos, reajustes, retenciones, multas asociadas, liquidación), administrado por el MOP según su Manual de Contratos. Las multas específicas se fijan en bases; el RCOP regula el marco (p. ej. multas por participación de contratistas relacionados, art. 68).
- **Oportunidad Fase 2+:** el % de avance por partida que CTT ya calcula es exactamente el insumo del Estado de Pago. Un export "avance físico por partida para Estado de Pago" sería un gancho de venta concreto para contratistas MOP. No comprometer aún; validar con clientes reales.

---

## 2. Frente 2 — Registro General de Contratistas del MOP

Regulado en el propio RCOP (arts. 5 a 42+). Define **quién es el cliente MOP de CTT y qué presiones tiene**:

- **Un registro común y único** para todas las Direcciones y Servicios MOP, dependiente de la DGOP, dividido en **Registro de Obras Mayores y Registro de Obras Menores** (art. 5+), con especialidades y **categorías (1ª, 2ª, 3ª A y B)** según experiencia acreditada (Cuadros N°1 y N°2 del documento "Registro de Contratistas - Categorías y Especialidades", arts. 17-19).
- **Equipo gestor con calidad profesional obligatoria** (arts. 30-33): para 1ª categoría en Obras Civiles/Montaje, al menos un ingeniero civil con ≥5 años de ejercicio (o arquitecto ≥5 años para Obras de Arquitectura, ingenieros constructores/constructores civiles según registro).
- **Art. 37 — dato clave para entender al cliente:** el personal profesional inscrito en cualquier categoría debe tener contrato de trabajo con el contratista por un **plazo mínimo de un año de permanencia ininterrumpida, jornada completa**, acreditado por declaración jurada notarial. El prevencionista de 2ª/3ª categoría puede ser part-time (mínimo un año).
- La **experiencia por obra se reparte con porcentajes máximos**: contratista 100%; equipo gestor 100% en total; **profesionales residentes a cargo de la obra 100%; profesional ayudante residente 30%; profesional responsable técnico de varias obras 20%** — un profesional no puede sumar más de un porcentaje por obra. Nótese que el propio RCOP reconoce la figura del "responsable técnico de varias obras" (≈ el patrón "residente que visita cada 3 días" de la entrevista) como distinta del residente a cargo.
- Los contratistas deben **informar al Registro dentro de 30 días** los cambios en constitución legal, experiencia, equipo gestor o staff profesional, bajo sanción.

**Implicaciones para CTT:**
1. **El cliente MOP tiene una obligación permanente de trazabilidad de su experiencia por obra y por profesional** (para mantener/subir categoría). CTT ya guarda por proyecto quién hizo qué y cuándo — un reporte "historial de obras y profesionales para acreditación de experiencia en el Registro" es una feature barata de alto valor percibido. Anotar para backlog Fase 2, validar demanda.
2. La distinción RCOP residente-a-cargo (100%) vs. responsable-técnico-de-varias-obras (20%) **valida normativamente** la corrección de roles hecha en el doc hermano: son figuras distintas con presencia distinta.
3. Las 636 empresas del Registro (dato del Research Report) se segmentan por categoría; las de 2ª/3ª son las PYME objetivo del pitch.

---

## 3. Frente 3 — Normativa laboral aplicable a la supervisión de trabajadores

Este frente es el que menos tiene que ver con "construcción" y el que más puede morder a CTT, porque CTT es literalmente **software de supervisión de labor en terreno**.

### 3.1 Ley 20.123 — Subcontratación (arts. 183-A y ss. del Código del Trabajo)

- **Definición (art. 183-A):** trabajo realizado por un trabajador para un empleador (contratista/subcontratista) que, por acuerdo contractual, ejecuta obras o servicios **por su cuenta y riesgo y con trabajadores bajo su dependencia**, para una empresa principal dueña de la obra o faena. Si los requisitos no se cumplen o hay mera intermediación de personas, **se entiende que el empleador es el dueño de la obra** (sanción a la simulación).
- **Regla general: responsabilidad SOLIDARIA de la empresa principal** (art. 183-B) por las obligaciones laborales y previsionales de dar de sus contratistas, incluidas indemnizaciones por término de relación laboral, limitada al período de servicios en la faena.
- **La solidaridad baja a SUBSIDIARIA solo si la empresa principal ejerce activamente los derechos de información y retención** (arts. 183-C y 183-D): pedir acreditación del cumplimiento laboral/previsional (en la práctica, certificados F30/F30-1 de la DT) y retener pagos ante incumplimiento. La jurisprudencia y la práctica confirman que **no basta la recepción pasiva del certificado — la fiscalización debe ser activa, constante y documentada**.
- **Deber de protección (art. 183-E):** la empresa principal debe proteger eficazmente la vida y salud de **todos** los trabajadores de su obra o faena, cualquiera sea su dependencia (propios, de contratistas y de subcontratistas). Su reglamento (D.S. 76/2006, que implementa el art. 66 bis de la Ley 16.744) exige a la empresa principal, entre otras cosas, mantener un registro actualizado de contratistas/subcontratistas en la faena y, sobre ciertos umbrales de dotación, un sistema de gestión de SST de faena. *(Verificar detalle del D.S. 76 contra texto vigente antes de construir features sobre él.)*

**Implicaciones para CTT:**
1. **El módulo minero de Fase 2 ("control de contratistas") tiene demanda legal, no solo operativa.** El mandante minero necesita fiscalización *documentada* de sus contratistas para mantener responsabilidad subsidiaria. Un registro trazable de qué contratista, con qué trabajadores, hizo qué y cuándo en la faena es evidencia útil para ese expediente. Esto refuerza la tesis del pitch — anotarlo como argumento de venta con base normativa.
2. **Advertencia de alcance:** CTT no debe prometer "cumplimiento Ley 20.123" (eso implica gestión documental F30-1, previsional, etc. — otro producto, y hay competidores dedicados a ello). Prometer: "trazabilidad de presencia y ejecución en faena que respalda tu expediente de fiscalización".
3. **CTT-la-empresa** también será empresa principal cuando subcontrate (desarrollo, soporte). Irrelevante hoy; anotado.

### 3.2 Resolución Exenta N°38/2024 de la Dirección del Trabajo — EL RIESGO MÁS DIRECTO

Contexto: la Ley 21.561 (40 horas) sustituyó el art. 33 del Código del Trabajo; el empleador debe controlar asistencia mediante libro, reloj control **o un sistema electrónico de registro**, cuyas condiciones fija una resolución del Director del Trabajo. Esa resolución es la **Res. Ex. N°38, publicada el 09-may-2024**, que establece los requisitos obligatorios y el procedimiento de autorización de los sistemas electrónicos de registro y control de asistencia.

Puntos que afectan a CTT:

- **Ámbito amplio:** aplica a toda plataforma, dispositivo o aplicación que **directa o indirectamente se utilice o sirva para obtener información sobre asistencia, horas trabajadas y/o descansos, aunque esa no sea su finalidad principal.** Leer eso dos veces: un software de gestión de obra que registra a qué hora el trabajador "COMENZÓ" y "TERMINÓ" cada tarea, con timestamps por RUT, produce indirectamente información de jornada.
- **Autorización previa de la DT por sistema** (no por empresa usuaria): el proveedor solicita, una empresa certificadora independiente valida técnicamente, la DT emite un Ordinario; existe un listado público de sistemas autorizados; las autorizaciones duran dos años.
- Requisitos técnicos: identidad inequívoca del trabajador, **inalterabilidad con checksum/hash por marcación, transmisión en línea a base central, portal de fiscalización accesible para la DT, empleador y trabajador**, respaldos, reportes, idioma castellano, protección de datos (Ley 19.628, y desde dic-2026 la 21.719).
- **Geolocalización está contemplada como componente opcional regulado** del sistema (herramienta para determinar la ubicación del trabajador al momento de marcar).
- **Uso de teléfonos:** si el registro se hace desde el teléfono personal del trabajador, se requiere consentimiento escrito y el empleador debe asumir/pagar los costos (plan de datos, etc.); si no está pagado, el trabajador no está obligado a marcar. CTT corre en los teléfonos de los trabajadores.

**Análisis de exposición de CTT (posición honesta):**

- **CTT hoy NO es un sistema de control de asistencia** y no debe presentarse como tal: registra estados de tareas, no entrada/salida de jornada. Esa distinción es defendible mientras el producto no ofrezca ni promocione funciones de asistencia/jornada.
- **PERO tres elementos del roadmap cruzan la línea si se implementan sin diseño legal:**
  1. *"GPS tracking en background para registro de presencia en terreno"* (Fase 2, DDT §11) — "registro de presencia" es lenguaje de asistencia. Además la vigilancia por geolocalización de trabajadores está limitada por el art. 5 del CT (dignidad) y jurisprudencia administrativa de la DT sobre medios de control (deben ser generales, conocidos, incorporados a reglamento interno, no persecutorios). *(Verificar dictámenes DT vigentes sobre geolocalización antes de diseñar la feature.)*
  2. *"Acreditación, asistencia y permanencia por centro de costo"* (pitch, módulo minero) — la palabra "asistencia" en material comercial es una autoinculpación en la definición de la Res. 38.
  3. *"Integración con sistemas de RRHH y remuneraciones vía RUT"* (Fase 2) — si CTT alimenta remuneraciones con horas derivadas de sus timestamps, se vuelve fuente indirecta de determinación de horas de trabajo.
- **Decisiones recomendadas (registrar ahora, decidir al llegar a Fase 2):**
  - **Opción A (recomendada corto plazo): mantenerse explícitamente fuera.** Disclaimer en producto y contratos: "CTT no es un sistema de registro y control de asistencia según art. 33 CT / Res. Ex. 38; los timestamps de tareas no constituyen registro de jornada". Reescribir el pitch minero: "permanencia por centro de costo" → "trazabilidad de actividad en faena". Rediseñar/renombrar el GPS Fase 2 como georreferencia de *evidencia* (foto/ítem con ubicación) y no rastreo de *personas*.
  - **Opción B (largo plazo, si el mercado lo pide): certificarse.** Entrar al listado de la DT como sistema autorizado. Es una barrera de entrada real (certificación técnica de tercero, portal de fiscalización, hash por marcación) — nótese que el diseño de audit log de CTT (append-only, hash-ready, server_ts) ya apunta en la dirección técnica correcta, igual que para el LOD. Sería un diferenciador fuerte, pero es un producto regulado: no subestimar el costo.
  - Lo que NO es opción: implementar registro de presencia/jornada "de facto" sin autorización. Los registros no tendrían validez legal y expondrían a los clientes a multas de la DT.

### 3.3 D.S. 594 (condiciones sanitarias y ambientales básicas en lugares de trabajo)

Marco de higiene y seguridad de toda faena (agua, servicios higiénicos, comedores, EPP, agentes de riesgo). No genera requisitos de software para CTT. Relevancia acotada: los checklists de seguridad del módulo minero de Fase 2 tendrían al D.S. 594 (y a la normativa SERNAGEOMIN, no investigada aquí) como contenido de referencia. Anotar: **la normativa minera (Reglamento de Seguridad Minera, D.S. 132) queda como hueco pendiente para cuando se active la Fase 2 minera.**

---

## 4. Frente 4 — SERVIU/MINVU como mandante (D.S. 236/2002 V. y U.)

- Las **Bases Generales Reglamentarias de Contratación de Obras** para los SERVIU (D.S. 236/2002, modificado sustantivamente por el D.S. 34/2023) regulan y **forman parte integrante de los contratos de construcción que celebren los SERVIU** — el equivalente MINVU del RCOP.
- **Cambios del D.S. 34/2023 relevantes:** se elimina el concepto "Administrador del Contrato"; la "Inspección Técnica de la Obra (ITO)" pasa a llamarse **"Fiscalización Técnica de la Obra (FTO)"** (funcionarios profesionales designados por el Director del SERVIU); se incorpora formalmente el **Libro de Inspección**.
- **Libro de Inspección ≠ Libro de Obras LGUC.** El propio D.S. 236 lo define como "medio de comunicación oficial entre la FTO, proyectistas y contratistas, **distinto del Libro de Obras establecido en la Ley General de Urbanismo y Construcciones**". En él la FTO anota observaciones y órdenes al contratista, con fecha y firma (art. 69). Es decir: **una obra SERVIU lleva simultáneamente el Libro de Inspección (comunicación mandante-contratista) Y el Libro de Obras LGUC (expediente DOM)**.
- Los contratos SERVIU incorporan expresamente la LGUC, la OGUC y el **Manual de Inspección Técnica de Obras (D.S. 85/2007 V. y U.)** entre su normativa aplicable (art. 44) — confirma que el mundo MINVU es LGUC-céntrico, a diferencia del MOP.
- **Registro propio:** los contratistas SERVIU se inscriben en el **RENAC** (Registro Nacional de Contratistas del MINVU, D.S. 127/1977), con categorías por capacidad económica — registro DISTINTO del Registro de Contratistas MOP. Un contratista que trabaja para ambos mandantes mantiene dos inscripciones.
- Sistemas de contratación: propuesta pública (regla), privada y trato directo (excepciones tasadas, con umbral de 10.000 UF para emergencias que requiere autorización ministerial); modalidades suma alzada, serie de precios unitarios y administración delegada.

**Implicaciones para CTT:**
1. **Un mismo contratista PYME puede vivir en tres regímenes a la vez** (obra MOP + obra SERVIU + obra privada DOM), cada uno con su libro y su fiscalizador. Esto refuerza la decisión ya registrada: la Bitácora de CTT es **una** fuente operativa interna que exporta hacia el formato que el mandante exija — nunca tres bitácoras distintas.
2. El vocabulario del sector cambió: en obras SERVIU nuevas es **FTO**, no ITO. Cuidado con el copy de producto y ventas.
3. SERVIU es un mandante masivo para las PYME regionales (pavimentación participativa, vivienda, mejoramiento de barrios) — probablemente más accesible que el MOP para los primeros clientes de CTT. Anotar para la estrategia comercial.

---

## 5. Mapa consolidado: "libros" y fiscalizadores por tipo de mandante

| Mandante / régimen | Norma madre | Libro(s) oficial(es) | Fiscalizador | Registro de contratistas |
|---|---|---|---|---|
| **MOP** | RCOP D.S. 75/2004 + Bases Adm. | Libro de Obras MOP → **LOD** (papel o digital según bases; Res. DGOP 258/2009) | **Inspector Fiscal** | Registro General de Contratistas MOP (Obras Mayores/Menores, cat. 1ª-3ª) |
| **Privado / municipal (permiso DOM)** | LGUC DFL 458 + OGUC D.S. 47 | **Libro de Obras LGUC** (art. 143 / 1.2.7 OGUC) | DOM, ITO (si corresponde), revisor independiente | No aplica (patente + profesionales) |
| **SERVIU** | D.S. 236/2002 (+D.S. 34/2023) — y además LGUC/OGUC | **Libro de Inspección** (FTO↔contratista) **+ Libro de Obras LGUC** | **FTO** (ex ITO SERVIU) | **RENAC** (D.S. 127/1977 MINVU) |
| **Minería (privado)** | Contractual (p. ej. LOD Codelco) + Reglamento de Seguridad Minera (pendiente de investigar) | LOD contractual del mandante | Administrador de contrato del mandante | Acreditación HSE por faena |

**Regla de diseño derivada (permanente):** ningún artefacto de CTT debe asumir un único libro, un único fiscalizador ni un único registro. `metadata` JSONB extensible + folio por tenant + actor con rol denormalizado (ya en el diseño del audit log) siguen siendo la arquitectura correcta.

---

## 6. Acciones y decisiones

**Ahora (costo ~0):**
- Incorporar este MD al project knowledge y a `docs/` del repo (junto al hermano LGUC).
- Corregir en el pitch minero la palabra "asistencia" → "trazabilidad de actividad en faena" (§3.2). Es un cambio de una línea que elimina una exposición regulatoria gratuita.
- Agregar en CTT-55 un comentario enlazando este documento (lo hace Kald, según flujo acordado).

**Antes de diseñar cualquier feature de Fase 2 que toque presencia, GPS o RRHH:**
- Releer §3.2 y decidir formalmente Opción A vs. B.
- Verificar dictámenes DT vigentes sobre geolocalización de trabajadores y texto vigente del D.S. 76/2006.

**Cuando se active la Fase 2 minera:**
- Investigar Reglamento de Seguridad Minera (D.S. 132) y requisitos de acreditación de contratistas en faenas (SERNAGEOMIN + estándares de mandantes).

**No hacer:**
- No prometer cumplimiento de Ley 20.123, ni reemplazo de LOD/Libro de Obras/Libro de Inspección, ni funciones de control de asistencia, en ningún material comercial, hasta que exista una decisión formal en contrario.

---

## 7. Preguntas abiertas (validar con el ingeniero entrevistado / clientes potenciales)

1. De los contratistas objetivo, ¿qué proporción trabaja con SERVIU vs. MOP vs. privado puro? (Define si el vocabulario y los exports priorizan FTO/Libro de Inspección o IF/LOD.)
2. ¿Los contratistas PYME sienten dolor real en la acreditación de experiencia ante el Registro MOP / RENAC? (Valida la feature de §2.1.)
3. ¿Algún cliente potencial espera que CTT registre jornada/asistencia? Si la respuesta es sí y es frecuente, la Opción B de §3.2 deja de ser teórica y hay que costearla.
4. En faenas mineras objetivo, ¿el mandante exige un sistema propio de control de acceso/asistencia (lo usual) o esperaría que el contratista traiga el suyo? (Determina si el módulo minero necesita integrarse o mantenerse fuera.)

---

## 8. Fuentes

- RCOP — D.S. MOP N°75/2004, texto oficial DGOP: dgop.mop.gob.cl/uploads/sites/5/2025/03/DTO-75_01-DIC-2004.pdf · BCN: bcn.cl/leychile (idNorma=233103)
- Instructivo Registro de Contratistas Obras Mayores, MOP (2021): mop.gob.cl/archivos/2021/10/Instructivo_Contratistas_Obras_Mayores.pdf
- Manual de Contratos, DGOP (2024): dgop.mop.gob.cl/uploads/sites/5/2024/08/MANUAL-DE-CONTRATOS.pdf
- Modificación RCOP 2024 (empresas relacionadas): Diario Oficial 16-abr-2024, CVE 2479734
- Ley 20.123 / subcontratación — DT: dt.gob.cl/portal/1626/w3-article-93827.html · SUSESO dictamen 56340/2006: suseso.cl/612/w3-article-34282.html · análisis responsabilidad solidaria/subsidiaria: aguilaycia.cl (2025), derechopedia.cl/Subcontratación
- Res. Ex. N°38/2024 DT — Diario Oficial 09-may-2024, CVE 2489163: diariooficial.interior.gob.cl · listado de sistemas autorizados: dt.gob.cl/portal/1626/w3-article-124477.html · análisis: microjuris (10-may-2024), rkabogados.cl, rexmas.com
- D.S. 236/2002 V. y U. — MINVU texto actualizado: minvu.gob.cl/wp-content/uploads/2019/05/DS_236_02_ACT_24_04_09.pdf · BCN: leychile.cl (idNorma=211854) · D.S. 34/2023 (FTO, Libro de Inspección): vlex.cl (Decreto 34, D.O. 03-08-2023)
- RENAC: D.S. 127/1977 MINVU (referenciado en resoluciones SERVIU, p. ej. licitación SERVIU Los Ríos 23/2025, documentos.minvu.cl)
- Documentos internos CTT: `NORMATIVA_LGUC_Y_CARGOS_OBRA.md`, `Audit_Log_Operativo...md` (base normativa LOD: RCOP art. 4 N°44 y 110+; Res. DGOP 258/2009), `Research_Report.md`, `CTT_Pitch_Financiamiento.docx`
