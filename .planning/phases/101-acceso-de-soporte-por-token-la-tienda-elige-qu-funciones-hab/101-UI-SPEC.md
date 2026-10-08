---
phase: 101
slug: acceso-de-soporte-por-token-la-tienda-elige-qu-funciones-hab
status: approved
reviewed_at: 2026-10-08
shadcn_initialized: false
preset: none
created: 2026-10-08
---

# Phase 101 — UI Design Contract

> Contrato visual e interactivo. Texto de interfaz en español (Argentina, voseo); prosa de la spec en español/coreano.
> Fuentes: 101-CONTEXT.md (D-01..D-19, LOCKED), 101-RESEARCH.md (§2, §8, §10), sketch-findings-ace-online (tema navy+gold), vistas existentes
> (`TokenSoporteView.tsx`, `AccesoVentagoView.tsx`, `AgenteAccesoView.tsx`, `RemoteSupportLayer.tsx`, `pages/soporte/visor.tsx`).
> Principio: reutilizar componentes MUI 5 ya presentes; cambios visuales mínimos. No se re-pregunta nada de CONTEXT.

---

## Design System

| Property | Value |
|----------|-------|
| Tool | none (React/Next 13 Pages Router, **MUI 5**; no existe `components.json`; shadcn no aplica — proyecto ya tiene sistema propio) |
| Preset | not applicable |
| Component library | MUI 5 (`@mui/material`) con el tema Ventago dark navy + gold (sketch-findings: `theme.md`) |
| Icon library | `@iconify/react` con set `tabler:*` (ya usado en TokenSoporteView / RemoteSupportLayer) |
| Font | Roboto (UI) + monospace (`'JetBrains Mono', 'SF Mono', Menlo, monospace`) para códigos, hora, método/ruta |

Reglas heredadas de CLAUDE.md: páginas nuevas con `next/dynamic(..., { ssr: false })`; ESLint `newline-before-return` y `lines-around-comment`; lógica pura en `.ts` (jest de la app no importa `.tsx`); tablas MUI `size='small'` (el override de `table.ts` da la fila de 30 px — **no** fijar `rowHeight`/padding a mano).

---

## Spacing Scale

Múltiplos de 4; en MUI se expresan con `theme.spacing` (1 = 8 px).

| Token | Value | Usage |
|-------|-------|-------|
| xs | 4px | Gap icono–texto en Chip, padding interno de helper text |
| sm | 8px | Gap entre checkbox y helper; gap en filas de botones (`spacing={1}`) |
| md | 16px | Padding de Alert, gap entre grupos de checkboxes, padding horizontal del banner de modo soporte |
| lg | 24px | Padding de CardContent (`p: 3`), padding del bloque del código |
| xl | 32px | Separación entre Cards (`Stack spacing={4}`) |
| 2xl | 48px | **Alto del banner de modo soporte** (fijo) y espacio superior reservado en el layout |
| 3xl | 64px | Padding vertical del estado vacío / sin alcance (`py: 8`) |

Excepciones: banner de modo soporte = 48 px de alto (token 2xl, no cambia con breakpoint; en xs envuelve a 2 líneas y crece a `auto`, mínimo 48). Botón de icono en la tabla: `size='small'` (30 px de fila). Sin otras excepciones.

---

## Typography

Exactamente 4 tamaños y 2 pesos en toda la fase.

| Role | Size | Weight | Line Height |
|------|------|--------|-------------|
| Body (texto de cards, tabla, labels de checkbox, banner) | 14px (0.875rem) | 400 | 1.5 |
| Label / helper / caption (helper de cada propósito, chips, cabecera de tabla, fecha, detalle monospace) | 12px (0.75rem) | 400 (cabecera de tabla y chips: 600) | 1.5 |
| Heading (título de Card `h6`, título de diálogo) | 20px (1.25rem) | 600 | 1.2 |
| Display (el código de 6 dígitos «123 456») | 40px (2.5rem), monospace, `letterSpacing: 0.2em` | 600 | 1.2 |

Notas: el código actual usa peso 700/800 — pasa a **600** para respetar los 2 pesos. El 16 px de body no se usa en esta fase. Los números (mm:ss, códigos, rutas) en monospace.

---

## Color

Tema existente (no se redefine; se usa `theme.palette` salvo donde el código actual ya hardcodea navy/gold, p. ej. `AgenteAccesoView`).

| Role | Value | Usage |
|------|-------|-------|
| Dominant (60%) | `#0f0f1e` (background.default) | Fondo de página |
| Secondary (30%) | `#1a1a2e` (background.paper) / borde `#333355` | Cards, banner de modo soporte, diálogos, tabla |
| Accent (10%) | `#f5a623` (gold, primary) | Ver lista abajo |
| Destructive | `#ef4444` | Sólo «Anular», «Revocar», contador < 60 s, estado «Revocado», error de acceso terminado |

Texto: `#f4f4f8` primario, `#9999b3` secundario. Éxito (`#4ade80`) sólo para Chip «Activo». Info (`#60a5fa`) sólo para el Alert explicativo.

Accent reserved for (lista cerrada):
1. Botón primario «Generar código» y «Usar código» (variant contained).
2. Borde inferior de 2 px y nombre de tienda del banner de modo soporte.
3. Barra de progreso de vigencia del código (hasta 60 s; luego `warning`→ mismo gold, y texto del contador en `#ef4444` < 60 s).
4. Checkbox marcado y borde de la tarjeta de propósito seleccionada.
5. Botón «Salir» (outlined gold) del banner.

Nunca gold en: botones secundarios (`color='secondary'` outlined, como «Mandar Token a CoolSistema»), links de tabla, chips «Pendiente»/«Terminó» (neutral/default). «Pendiente» usa `warning` outlined (gold suave) **sólo** como chip de estado, no como acento de acción.

Prohibido: azul MUI por defecto `#1976d2`; fondo negro puro.

---

## Screen 1 — Menú unificado «Token de soporte» (tienda) — D-16/17/18/19

### Ubicación y ruteo
- Entrada: **sidebar principal › grupo Admin › «Token de soporte»** (ícono `tabler:key`). Una sola entrada. Se **quitan** «Token de soporte» y «Acceso de Ventago» de la navegación interna de Configuración › AVANZADO.
- Ruta: la ya existente de la vista unificada (planner decide slug; `pages/...` con `next/dynamic ssr:false`). Gate de pantalla = mismo origen `admin` que el guard del servidor.
- Reutiliza `AccesoVentagoView.tsx` como base (se renombra/reubica a vista «TokenSoporte»); `TokenSoporteView.tsx` queda sin uso salvo reaprovechar el bloque de código grande + countdown + «Mandar Token a CoolSistema».

### Estructura (Stack `spacing={4}`, ancho máx. de contenido 960 px)
1. **Card A — «Token de soporte»** (título 20/600) + subtítulo 14 `text.secondary`:
   «Elegí qué puede hacer el técnico de Ventago, generá un código y dictáselo. El acceso se corta solo y lo podés anular o revocar cuando quieras.»
   - **Grupo «Sólo ver (no puede cambiar nada)»**: 4 checkboxes — `Ver ventas`, `Ver productos`, `Ver facturas`, `Ver administración`.
   - **Grupo «Puede hacer cambios»**: `Importar datos del sistema anterior (legacy)`, `Renovar el certificado digital`, `Usuarios y terminales`.
   - **Grupo «Pantalla»**: `Sesión remota (ver mi pantalla)`. Se **oculta** si `REMOTE_SUPPORT_ENABLED` está apagado (la API lo informa; el servidor igual lo rechaza).
   - Cada checkbox: label 14/400 + `FormHelperText` 12 indentado 32 px (alineado al checkbox) con el texto exacto de la tabla de copy abajo. Los 3 grupos con subtítulo 12/600 `text.secondary` en mayúscula inicial, `mt: 2` entre grupos.
   - Fila inferior: `Select` «Duración» (30 min | 2 horas, `size='small'`, minWidth 180) + botón **«Generar código»** (contained, deshabilitado si no hay propósito marcado o `generando`).
   - Resumen vivo debajo (Alert `info`, `variant='outlined'`, 12 px) que se actualiza al marcar: «Con este código el técnico podrá: {lista}. {frase de límite}». Frase de límite: si **todos** los marcados son «Ver …» → «No podrá cambiar nada.»; si hay alguno de la 2ª categoría → «Podrá hacer cambios sólo en: {esos}.»; si sólo Sesión remota → «Verá tu pantalla 15 minutos; lo que escribas se oculta.»
2. **Bloque del código** (aparece dentro de Card A tras generar; borde 1 px `divider`, `p: 3`, centrado — mismo patrón que hoy):
   - Código `123 456` (Display 40/600 mono, helper `agruparCodigo`).
   - Texto 14: «Dictáselo al técnico de Ventago. Vale 15 minutos y se usa una sola vez.»
   - `LinearProgress` (altura 6, determinate) + «Vence en mm:ss» (14; rojo `error` < 60 s). Al llegar a 0: icono `tabler:clock-off` + «El código venció. Generá otro.» y el botón «Generar código» vuelve a estar activo.
   - Caption 12: `{etiquetas} · {30 min|2 horas}`.
   - Botón **«Mandar Token a CoolSistema»** (outlined, `color='secondary'`, `fullWidth`, icono `tabler:send`) — conserva comportamiento (abre el chat IA y manda el mensaje), el texto enviado incluye el **código nuevo** y los propósitos.
   - Si la API devuelve `uso`: caption «Códigos este mes: usados/límite»; `aviso` en Alert `warning`. (La regla de cobro está **pendiente** de CONTEXT; la UI sólo muestra lo que la API devuelva — no inventar precios.)
3. **Card B — «Códigos y accesos»** (una sola tabla MUI `size='small'`, **sustituye** «Accesos dados»; sin FullTable porque son pocas filas):
   - Columnas: `Estado` · `Qué incluye` · `Desde / Vence` · `Técnico` · (acciones, align right).
   - Orden: **Pendientes** primero (por vencimiento), luego activos, luego terminados/revocados (últimos 20).
   - Estados (Chip `size='small'`, 12/600): `Pendiente` (warning outlined), `Activo` (success), `Terminó` (default), `Revocado` (error), `Anulado` (default, tachado no; sólo gris).
   - Acciones por estado: Pendiente → **«Anular»** (text, `color='error'`); Activo → **«Ver qué hizo (N)»** + **«Revocar»** (error); Terminó/Revocado/Anulado → sólo «Ver qué hizo» (si hubo acciones). Pendiente: «Técnico» muestra «—» y «Desde / Vence» muestra «Vence {hora}».
   - Confirmación (Dialog `maxWidth='xs'`) para «Anular» y «Revocar» — copy en la tabla de Copywriting.
   - Auto-refresco cada 30 s mientras haya filas Pendiente/Activo; refresco inmediato tras generar, anular o revocar.
4. **Dialog «Qué hizo {técnico}»** (`maxWidth='md'`, ya existe). Cambios D-6: tabla con columnas `Cuándo` · `Qué` · `Alcance` · `Método` · `Ruta / detalle`. `Alcance` = etiqueta ES del propósito (p. ej. «Ver ventas»); `Método` en monospace 12 (`GET`, `POST`, `WS`); `Ruta` monospace 12, truncada con `title`. Eventos `denegado` se muestran con texto `error` y la leyenda «Bloqueado». Si la API agrupa lecturas repetidas, mostrar sufijo « × N». Máx. alto del contenido 60vh con scroll.

### Estados
- **Cargando lista:** 3 filas `Skeleton` en la tabla.
- **Vacío:** ver Copywriting.
- **Error de carga/generación:** Alert `error` inline **más** toast global (regla `feedback_error_visibility`); mensaje vía `mensajeError`.
- **Sin propósito marcado:** botón deshabilitado + helper 12 `text.secondary` «Marcá al menos una opción.»
- **Mobile (xs):** checkboxes en 1 columna; tabla con `overflowX: auto`.

### Accesibilidad
Checkbox con `FormControlLabel`; helper vinculado con `aria-describedby`; el código tiene `aria-live='polite'` para el countdown sólo en los hitos (60 s, 0 s), no cada segundo. Foco inicial al abrir la página en el primer checkbox; tras generar, foco al código (`tabIndex=-1`).

---

## Screen 2 — Navegación sólo lectura del agente (banner, bloqueo, 403)

### Banner persistente «Modo soporte»
- Componente único montado en el layout (visible en **todas** las pantallas mientras haya grant activo con algún `ver_*`; no aparece para cert/legacy/usuarios_terminales solos).
- Posición: `position: fixed; top: 0; left: 0; right: 0; height: 48px; zIndex: 1400` (sobre AppBar y Drawer de MUI). El layout reserva 48 px (`padding-top` vía CSS var `--modo-soporte-h`) para no tapar contenido; sin banner la var vale 0.
- Visual: fondo `#1a1a2e`, borde inferior 2 px `#f5a623`, texto `#f4f4f8` 14/400; separador `·` en `#9999b3`.
- Contenido (izq→der), en una línea: icono `tabler:eye` 20 · «**Modo soporte**» (600) · «Tienda **{nombre}**» (nombre en gold, 600) · Chip «Sólo lectura» (outlined, 12/600) · «vence en **mm:ss**» (mono; rojo `#ef4444` < 60 s) · botón **«Salir»** (outlined gold, `size='small'`, derecha).
- En xs: se parte en 2 líneas (tienda + chip arriba; vence + Salir abajo), alto `auto` ≥ 48.
- **«Salir»**: borra el modo en esta pestaña (`setAgentGrant(null)`), vuelve a `/agente/acceso` y **no** revoca el acceso en el servidor (el acceso sigue en «Mis accesos» hasta que venza o se pulse «Terminar»). Sin confirmación.
- Tooltip del chip «Sólo lectura»: «Podés mirar las pantallas de la tienda. Nada de lo que hagas modifica datos.»
- Cuenta atrás con `setInterval` 1 s; al 0 → diálogo «El acceso terminó» (abajo).

### Escrituras
- **Frontera real = 403 del servidor** (D-08). UI es ayuda:
  1. **Bloqueo central** en `apiConnector` (request interceptor): método ≠ GET y no en lista de POST-lectura → no sale a la red; Snackbar `warning` 4 s «Modo sólo lectura: no se puede cambiar nada.» (sin duplicar el toast global de error).
  2. **Ocultar** (no sólo deshabilitar) los botones primarios de escritura en las pantallas objetivo — Ventas (Anular/Nueva), Productos (Crear/Editar/Eliminar/Importar), Sucursales (Crear/Editar/Eliminar), Facturación (Emitir/Reimprimir) — mediante hook `useModoSoporte()` → `{ soloLectura: boolean }`. Cobertura 100 % de botones no es requisito de v1; todo lo no oculto cae en el bloqueo central (1).
  3. Nada se activa para usuarios normales: `soloLectura` es `false` sin grant.
- Menú lateral: sólo los módulos permitidos por los propósitos (structure sintético del servidor); items de «Configuración» no incluidos no aparecen.

### Estado 403 — «Este código no permite ver esto» (global, D-09)
Dos casos con tratamiento distinto (el servidor manda `code`):

| Caso | `code` | Tratamiento |
|------|--------|-------------|
| Fuera de alcance (acceso vigente) | `AGENT_SCOPE_DENIED` / `AGENT_NO_SCOPE` | **No fatal.** La pantalla sigue montada. La región que falló muestra el componente `<SinAlcance />`; además Snackbar `info` 4 s con el mismo texto. El grant **no** se borra. |
| Acceso inválido | `AGENT_GRANT_INVALID` | **Fatal.** Se limpia el modo y aparece Dialog modal no descartable «El acceso terminó» con botón **«Volver a Usar código»** (navega a `/agente/acceso`). |

`<SinAlcance />` (componente único, reutilizado por contenedores de datos): centrado, `py: 8` (64 px), icono `tabler:lock` 40 `#9999b3`, título 20/600 «Este código no permite ver esto», cuerpo 14 `text.secondary` «La tienda no habilitó esta parte. Pedile que genere un código nuevo con esta opción.». Sin botón de reintento (reintentar da lo mismo). Los hooks SWR que reciben 403 `SCOPE_DENIED` deben devolver estado vacío, no excepción visible por pantalla (validar ventas, productos, sucursales).

---

## Screen 3 — «Usar código» del agente (`AgenteAccesoView.tsx`)

Cambios mínimos sobre la vista actual (Stack, 3 Cards + tabs):
1. **Texto de ayuda** cambia a: «Pedile a la tienda que genere un código en Admin › Token de soporte y que te lo dicte.»
2. **Barra de acceso activo** (la ya existente navy/gold) añade: chips de propósitos (12/600) y botón **«Entrar a las pantallas»** (contained gold, sólo si hay algún `ver_*`), que activa el Modo soporte y navega a la primera pantalla permitida (orden: ventas → productos → facturación → sucursales). Se mantiene «Terminar».
3. **Tarjeta «Pantallas de la tienda»** (nueva, sólo si hay `ver_*`; dentro de las tabs/card del acceso activo): lista de accesos directos con icono, uno por propósito marcado — `Ver ventas` → /ventas, `Ver productos` → /productos, `Ver facturas` → /facturacion, `Ver administración` → /sucursales. Cada uno `ListItemButton` con subtítulo 12 «Sólo lectura». Las tabs actuales (cert / usuarios_terminales / legacy) se mantienen **sin cambio**; `ver_*` **no** generan tab.
4. **Mis accesos:** el `secondary` de cada ítem usa `etiquetasAlcances` ampliado con los 5 nuevos (ver Copywriting «Etiquetas»).
5. **Tab «Sesión remota»** (si el acceso incluye `sesion_remota`): contenido de Screen 4 (agente). 
6. La vista deja de tratar **todo** 403 como pérdida del acceso: sólo `AGENT_GRANT_INVALID` dispara `perdido()` (el evento `AGENT_GRANT_REJECTED_EVENT` pasa a `CustomEvent` con `detail.code`).

---

## Screen 4 — Sesión remota (D-11, D-14)

### Lado tienda
- Cuando existe un acceso **Activo** con «Sesión remota», Card B muestra en esa fila un botón **«Compartir mi pantalla»** (contained, `size='small'`, icono `tabler:broadcast`) que dispara el mismo `requestSupport` del `RemoteSupportLayer` (consentimiento explícito: nada se graba hasta que la tienda toca el botón). El FAB «Solicitar soporte remoto» (abajo derecha) se mantiene como segundo camino.
- Mientras la sesión corre: se **reusa tal cual** la barra roja de `RemoteSupportLayer` (zIndex 13000, «Soporte remoto activo — un agente está viendo tu pantalla» / «Soporte remoto solicitado — esperando al agente…») con botón **«Finalizar»**. No se rediseña. Se añade al texto de la barra, entre paréntesis, «(máx. 15 min)».
- Aviso inline en Card A bajo el checkbox y en la fila de la tabla: «El técnico ve tu pantalla durante 15 minutos. Los campos que escribís se ocultan (••••). No puede mover ni tocar nada.»
- Si el plano está apagado en el servidor: checkbox no se muestra (ver Screen 1).

### Lado agente (`pages/soporte/visor.tsx` en modo agente)
- El TextField «Código de sesión (UUID)» se **reemplaza** por un selector de **sesiones activas de la tienda** (`List` con `ListItemButton`: «Sesión de {usuario} · pedida hace {mm:ss}» + Chip de estado `Esperando`/`En vivo`), alimentado por `GET /support/sessions/active`. Refresco cada 5 s.
- Sin sesiones: título 14/600 «Nadie pidió soporte remoto todavía», cuerpo 12 «Pedile a la tienda que toque «Compartir mi pantalla».».
- Chip de conexión del visor se reutiliza sin cambios (`Conectado (en vivo)`, `Conectando…`, `Sesión finalizada`, `Error`, `Sin conexión`). Botones «Unirse» y «Terminar» existentes.
- Visor ocupa el contenido de la tab «Sesión remota» y también `/soporte/visor`. Banner de Modo soporte **no** se muestra solo por tener `sesion_remota` (sólo `ver_*`).
- Fin por vencimiento del acceso o revocación: Chip pasa a `Sesión finalizada` + Alert `warning` «El acceso terminó.».

---

## Copywriting Contract (es-AR, voseo)

### Propósitos (checkbox + helper — texto **exacto**, sin exagerar)

| Clave | Checkbox | Helper (qué permite / qué no) |
|-------|----------|-------------------------------|
| ver_ventas | Ver ventas | «Mira el listado y el detalle de las ventas. No puede cambiar nada.» |
| ver_productos | Ver productos | «Mira productos, precios de venta y stock. No puede cambiar nada. No ve costos ni ganancias.» |
| ver_facturas | Ver facturas | «Mira las facturas y notas emitidas. No puede emitir ni cambiar nada.» |
| ver_admin | Ver administración | «Mira sucursales, usuarios, permisos, impresoras y configuración. No puede cambiar nada ni ve contraseñas ni claves.» |
| legacy | Importar datos del sistema anterior (legacy) | «Productos, clientes, stock, ventas y gastos — quedan en esta tienda.» |
| cert | Renovar el certificado digital | «Sólo para renovar el certificado de facturación.» |
| usuarios_terminales | Usuarios y terminales | «Ver sesiones y cerrar sesiones colgadas.» |
| sesion_remota | Sesión remota (ver mi pantalla) | «El técnico ve tu pantalla durante 15 minutos. Lo que escribís se oculta. No puede tocar nada.» |

### Etiquetas cortas (para `etiquetasAlcances`, tabla, chips)
`ver_ventas`→«Ver ventas» · `ver_productos`→«Ver productos» · `ver_facturas`→«Ver facturas» · `ver_admin`→«Ver administración» · `legacy`→«Importar datos legacy» · `cert`→«Certificado digital» · `usuarios_terminales`→«Usuarios y terminales» · `sesion_remota`→«Sesión remota».

### Elementos
| Element | Copy |
|---------|------|
| Primary CTA (tienda) | **Generar código** |
| Primary CTA (agente) | **Usar código** · acceso activo: **Entrar a las pantallas** |
| Mandar a chat | **Mandar Token a CoolSistema** (mensaje enviado: «Código de soporte de Ventago: {123 456}. Permite: {propósitos}. Por favor, conectar con un técnico de CoolSistema.») |
| Empty state heading (tabla) | **Todavía no generaste ningún código** |
| Empty state body | «Marcá lo que necesita el técnico, elegí cuánto dura y tocá «Generar código».» |
| Empty agente («Mis accesos») | «No tenés accesos vigentes.» (sin cambios) |
| Empty sin sesiones remotas | «Nadie pidió soporte remoto todavía» / «Pedile a la tienda que toque «Compartir mi pantalla».» |
| Error generar | «No se pudo generar el código. Probá de nuevo; si sigue, avisanos desde el chat.» |
| Error cargar lista | «No se pudieron cargar los códigos. Actualizá la página.» |
| Error canje | «Código inválido o vencido.» (idéntico para anulado/inexistente/vencido — no revelar existencia, D-18) |
| Fuera de alcance (403 no fatal) | «Este código no permite ver esto» + «La tienda no habilitó esta parte. Pedile que genere un código nuevo con esta opción.» |
| Acceso terminó (403 fatal / vencimiento) | Título «El acceso terminó» · cuerpo «El código venció o la tienda lo revocó. Pedile uno nuevo.» · botón «Volver a Usar código» |
| Intento de escribir | «Modo sólo lectura: no se puede cambiar nada.» |
| Código venció (display) | «El código venció. Generá otro.» |
| Chips de estado | Pendiente · Activo · Terminó · Revocado · Anulado |
| Destructive: Anular | Diálogo título «Anular código», cuerpo «Este código dejará de funcionar y nadie podrá usarlo.», botones «Volver» (text) / **«Anular código»** (contained, `color='error'`) |
| Destructive: Revocar | Diálogo título «Revocar acceso», cuerpo «El técnico pierde el acceso ahora mismo. Si estaba viendo tu pantalla, se corta.», botones «Volver» / **«Revocar acceso»** (contained error) |
| Tooltip «Sólo lectura» | «Podés mirar las pantallas de la tienda. Nada de lo que hagas modifica datos.» |

Acciones destructivas de la fase: Anular código, Revocar acceso (ambas con diálogo de confirmación; «Terminar» del agente y «Salir» del banner **no** son destructivas y no piden confirmación).
Prohibido en copy: «visualizar y modificar», «acceso total», cualquier promesa de permiso no marcado.

---

## Interaction Contract resumida
- Generar: POST → muestra bloque de código; la fila Pendiente aparece de inmediato en Card B.
- Anular/Revocar: Dialog → POST → refresco de lista → Snackbar `success` «Código anulado» / «Acceso revocado».
- Agente canjea: éxito → barra de acceso activo + (si hay `ver_*`) botón «Entrar a las pantallas».
- Modo soporte activo y pestaña recargada: se recupera desde `sessionStorage` (key + tienda + alcances + hasta); si venció, no hay modo.
- Atajos de teclado: Enter en el campo de código (6 dígitos) = «Usar código» (existente). Sin atajos nuevos.

---

## Registry Safety

| Registry | Blocks Used | Safety Gate |
|----------|-------------|-------------|
| shadcn official | none (shadcn no inicializado; stack MUI 5) | not applicable |
| third-party | none | not applicable |

Sin dependencias nuevas (RESEARCH: «Package Legitimacy Audit — no aplica»).

---

## Checker Sign-Off

- [ ] Dimension 1 Copywriting: PASS
- [ ] Dimension 2 Visuals: PASS
- [ ] Dimension 3 Color: PASS
- [ ] Dimension 4 Typography: PASS
- [ ] Dimension 5 Spacing: PASS
- [ ] Dimension 6 Registry Safety: PASS

**Approval:** pending

---

## Notas para el planner (decisiones abiertas que esta spec asume por defecto)
1. Checkbox «Sesión remota» oculto si el flag está apagado (RESEARCH Q5); se asume que la API expone el flag.
2. «Compartir mi pantalla» desde la tabla (Q4 de RESEARCH sin cerrar): si se decide que la sesión no se vincula al acceso, conservar sólo el FAB existente y quitar el botón de la fila.
3. Cobro por código (límite mensual / $5.000 extra) sin decidir: la UI muestra `uso`/`aviso` sólo si la API los devuelve.
4. Ocultar botones de escritura es por pantalla objetivo (4 pantallas); el resto lo cubre el bloqueo central + 403.
5. Agrupar eventos repetidos en «Qué hizo» depende de la API (Q8); sin agrupar, usar el límite actual y el sufijo « × N» si llega.
