# Phase 102: Asistente IA bilingüe de consultas operativas (es/ko) - Context

**Gathered:** 2026-10-12
**Status:** Ready for planning

<domain>
## Phase Boundary

Que el asistente IA dentro de Ventago responda bien las **dudas de uso del sistema** en español y
coreano, **sólo con base en los manuales** (sin inventar). Incluye: modelo más capaz en Ollama,
búsqueda que funcione para preguntas en coreano sobre manuales en español, manuales completados
según las preguntas reales sin respuesta, una forma fácil de reforzar el manual desde la pantalla
«Preguntas sin respuesta», y la prueba fija ampliada a coreano.

NO incluye: consultas de datos de la tienda («¿cuántas ventas hicimos hoy?» sigue siendo pregunta
que se rechaza), canales WhatsApp/Telegram/Codex worker (Phase 100), API paga.

**Ya en producción (no rehacer, no re-decidir)** — api `043677ed` · app `6196c9d0`:
idioma de la respuesta lo decide el servidor (el modelo sólo devuelve `NO_ENCONTRADO`); sin
documentos no se llama al modelo; historial 30 min misma tienda vía `/api/chat`; códigos de soporte
(HMAC contra `support_tokens`) + aviso Telegram al grupo Pedidos; `GET /chat/sin-respuesta`
(superadmin) + `PreguntasSinRespuesta.tsx`; prueba fija 31 preguntas (línea base prod **22/31**,
búsqueda 19/28).

</domain>

<decisions>
## Implementation Decisions

### Modelo y costo
- **D-01:** Se **mantiene Ollama** (sin API paga). Se sube el modelo de `qwen2.5:3b` a uno más
  grande (clase ~7B) que corra en srv2 `74.208.60.137` (CPU, compartido, vía túnel).
- **D-02:** Tope **60 s** por respuesta, y **streaming**: el texto aparece en pantalla mientras se
  genera (el usuario no espera la respuesta completa). El chat_slot_limiter existente se respeta.
- **D-03:** Si srv2 no alcanza (memoria) o el modelo grande pasa los 60 s: **parar y reportar con
  mediciones** (RAM, s/pregunta, puntaje en la prueba) — no elegir otro camino por cuenta propia
  (ni API paga ni quedarse en 3b sin preguntar).

### Respuesta en coreano
- **D-04:** El que pregunta en coreano es sobre todo el **dueño/administrador coreano** de la
  tienda → más preguntas de pantallas de gestión (stock, precios, informes, talleres) que de caja.
- **D-05:** **Un solo manual, en español.** Las preguntas en coreano buscan en los manuales en
  español (p. ej. tabla de términos coreano→español para la búsqueda: 판매→venta, 재고→stock…) y el
  modelo responde en coreano. No se escriben manuales coreanos paralelos.
- **D-06:** `manuales/soporte_remoto_ko.md` **se deja como está** (excepción existente, no se
  fusiona ni se borra).

### Refuerzo de manuales
- **D-07:** Los temas que faltan los escribe **Claude como borrador en español leyendo el código y
  las pantallas reales → el usuario revisa → recién ahí entra**. Un manual equivocado produce
  respuestas equivocadas; la revisión es obligatoria.
- **D-08:** Orden: **primero lo que de verdad no se pudo contestar** — `GET /chat/sin-respuesta`
  (chat_messages de producción) y las 9 preguntas que fallan en la prueba fija.
- **D-09 (pedido del usuario: «una forma fácil de reforzar el manual cada vez»):** en la pantalla
  «Preguntas sin respuesta» (superadmin) cada pregunta tiene un botón **«Responder»**. El usuario
  escribe unas líneas (en español **o en coreano**); el sistema lo reescribe como sección de manual
  en español con el formato de `manuales/` y muestra una **vista previa**; al «Guardar» entra al
  conocimiento **al instante, sin deploy**.
- **D-10:** Fuente única: lo guardado desde la pantalla vive **en la DB primero**; luego (de noche)
  Claude junta esos agregados en el `.md` correspondiente con un commit, y después del deploy se
  limpian los agregados de la DB. El original final sigue siendo **un solo `.md`**. Hasta la
  fusión no puede haber dos versiones del mismo tema compitiendo en la búsqueda.

### Meta y prueba
- **D-11:** La fase se da por terminada por **preguntas reales de producción, no por un número**:
  tras el deploy, juntar 1–2 semanas de preguntas reales en una tabla (pregunta · respuesta ·
  sección de manual usada · juicio de Claude) y **el usuario decide** si alcanza. La prueba fija
  sirve para detectar retrocesos.
- **D-12:** **Inventar = 0, sin excepción.** Si alguna pregunta que no debe contestarse
  (mundial, receta, datos de ventas) recibe una respuesta inventada en la prueba, **no se
  despliega**.
- **D-13:** Las preguntas en español de la prueba se agregan **también en coreano**, dichas como
  las diría un dueño coreano (no traducción literal) → ~60 preguntas. Se mide español y coreano por
  separado.
- **D-14:** La prueba con modelo comparte el Ollama de producción (30–60 s/pregunta en CPU; con 7B
  y ~60 preguntas, más de 1 h) → correrla sólo **fuera del horario de tiendas** (después de las 16 h
  ART / de noche).

### Claude's Discretion
- Cómo nombrar pantallas/menús/botones dentro de una respuesta en coreano (el usuario no tuvo
  preferencia). Por defecto: **nombres en español tal como aparecen en pantalla**
  (p. ej. «Nueva venta», «Cobrar» (F9)), porque la app está en español.
- Qué modelo exacto (qwen2.5:7b u otro) — según medición en srv2 y D-01~D-03.
- Mecanismo de la tabla de términos ko→es y de la reescritura en D-09 (qué LLM la hace).
- Quién puede usar «Responder»: superadmin (igual que la pantalla actual).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Estado del asistente (punto de partida)
- `.planning/HANDOFF-2026-10-12.md` §1 fila «AI 도우미» y §2 punto 2 — qué se desplegó y por qué esta fase existe
- `.planning/ROADMAP.md` — Phase 102 (meta, línea base 22/31)
- `api-ventago/src/app/chat/asistente-reglas.ts` — idioma, `NO_ENCONTRADO`, `FRASES_SIN_RESPUESTA`
- `api-ventago/src/app/chat/chat.service.ts` — flujo búsqueda → modelo → limpieza, historial, códigos de soporte
- `api-ventago/src/app/chat/eval/preguntas-asistente.ts` — prueba fija (reglas: no copiar títulos del manual en la pregunta)
- `api-ventago/src/app/chat/eval/evaluar-asistente.ts` — cómo correr la prueba con modelo (dentro del contenedor)

### Conocimiento
- `api-ventago/manuales/` (11 `.md`) + `api-ventago/manuales/README.txt` — reglas de redacción
- `api-ventago/src/app/chat/knowledge/manual-sync.service.ts` — sync al arrancar; **borra las `source` que ya no están en archivos** (orphan cleanup)
- `api-ventago/src/app/chat/knowledge/knowledge-search.ts` — `rankDocuments` (keyword, sin acentos, top 2)

### Mockup del refuerzo de manual (D-09/D-10)
- https://claude.ai/artifact/2XK1yXSCcFzw43jrNAmqt3 — 5 pasos: Lista → Responder → Vista previa + probar (es/ko) → Guardado (al instante) → Fusión nocturna por Telegram. **Pendiente de confirmar:** si la fusión nocturna pide «Aprobar» en Telegram o se commitea/deploya sola.

### Contexto relacionado
- `.planning/phases/100-soporte-ia-ventago-whatsapp-en-espa-ol-telegram-admin-codex-/100-PREP.md` — Phase 100 (canales); qué NO es esta fase
- `.planning/SETUP-2026-08-26-servidor2-74.208.60.137.md` — srv2 donde corre Ollama

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `llm/` provider abstraction (ollama/claude/groq/openai, un solo prompt): cambiar modelo = `OLLAMA_MODEL`; streaming hay que agregarlo (hoy respuesta completa).
- `chat-slot-limiter.ts`: limita llamadas simultáneas al Ollama compartido.
- `GET /chat/sin-respuesta` + `ventago-app/src/components/chat/PreguntasSinRespuesta.tsx`: base para el botón «Responder» (D-09).
- `manual-sections.ts` `parseMarkdownSections`: mismo formato para la vista previa y para la fusión nocturna (D-10).
- `soporte-aviso.service.ts`: aviso Telegram existente.

### Established Patterns
- Frases fijas visibles las pone el servidor; al modelo sólo marcadores — el 3B copiaba frases del prompt (memoria `small-llm-copies-prompt-phrases`).
- Sin documentos → no se llama al modelo.
- `/chat/knowledge`, `sync-*` sólo superadmin (filas globales `allowGlobalRows`).

### Integration Points
- ★ `manual-sync` borra filas cuya `source` no existe en `manuales/*.md`: los agregados de D-09 necesitan un `source` propio (prefijo distinto) para no ser borrados al arrancar, y la fusión de D-10 los tiene que retirar después del deploy.
- Ollama en srv2 vía túnel; el contenedor `api_ventago` lo usa. Medir RAM de srv2 antes de elegir modelo.
- Deploy en producción sólo después de las 16 h ART (o ≤5 usuarios activos) — regla del proyecto.

</code_context>

<specifics>
## Specific Ideas

- El usuario quiere poder reforzar el manual en español **cada vez que haga falta, de forma fácil** — sin abrir una sesión de Claude ni esperar un deploy (→ D-09/D-10).
- Puede escribir el agregado en coreano; el sistema lo guarda en español.

</specifics>

<deferred>
## Deferred Ideas

- Consultas de datos de la tienda por IA («¿cuántas ventas hoy?») — capacidad nueva; hoy se rechaza a propósito.
- Responder agregados desde Telegram (opción descartada para D-09; posible más adelante con Phase 100).
- API paga (Claude Haiku) — descartada por ahora; vuelve a la mesa sólo si D-03 dispara.

</deferred>

---

*Phase: 102-asistente-ia-bilingue-de-consultas-operativas-es-ko*
*Context gathered: 2026-10-12*
