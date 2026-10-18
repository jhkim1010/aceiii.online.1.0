---
phase: 117
slug: reportaje-abierto-el-usuario-arma-un-pedido-de-reporte-cat-l
status: approved
reviewed_at: 2026-10-18
shadcn_initialized: false
preset: none
created: 2026-10-18
---

# Phase 117 — UI Design Contract: «Reporte a medida»

> Contrato visual y de interacción de la ronda de front (D-25). Fuente de verdad visual: mockup v4 aprobado el 2026-10-18 (D-24) en `.planning/mockups/2026-10-17-reportaje-abierto/mockup.html` (+ `shot-*.png`). **Layout, copy y flujo del mockup están cerrados**; este documento los traduce a MUI 5 / Next 13 Pages Router y fija lo que el mockup no decía (placement, estados, mapeo a la API real, accesibilidad). Texto de UI en español rioplatense (voseo), nombre visible **«Reporte a medida»** (D-29), «Promedio por ticket» y «Precio por unidad» (D-32).
>
> Regla de lectura: donde este documento y el mockup difieren, la diferencia está listada en «Desvíos mockup → implementación» y es deliberada.

---

## Design System

| Property | Value |
|----------|-------|
| Tool | none (shadcn no aplica: proyecto MUI 5, sin `components.json`; decisión del proyecto, no se inicializa) |
| Preset | not applicable |
| Component library | Material-UI 5 (`@mui/material`), tema oscuro Ventago ya cargado (`sketch-findings-ace-online` → `references/theme.md`) |
| Icon library | `@iconify/react` (set `tabler:*`), igual que `ReportsSidebar` / `ReportsShellNuevo`. Los glifos 🔒 ⊘ ∅ ⏳ del mockup se sustituyen por íconos tabler (ver «Bloqueos») |
| Tabla | `FullTable` (AG Grid) con `TABLE_ROW_HEIGHT` (30 px) de `src/components/table/table-density.ts`; **no** pasar `rowHeight` |
| Gráficos | `react-apexcharts` (ya en `package.json`), `next/dynamic` con `ssr:false` |
| Datos | `apiConnector` (`src/services/api.service.ts`) + SWR para `GET catalogo` y `GET pedidos` (5 min dedup); `ejecutar` / `validar` / CSV son acciones, **no** SWR |
| Font | Roboto (texto) + JetBrains Mono (toda cifra, fecha y monto de la tabla, resumen «Filas», tooltips de gráfico) |
| Permisos | CASL / `permissionSlug` `reporte-a-medida` (menú, acción `read`). El margen se decide en el **servidor** (catálogo devuelve `bloqueada`); el front nunca usa un flag propio como frontera |

---

## Ubicación y navegación (D-13, decisión del researcher)

El menú lateral global **no cambia** (Reportes sigue siendo `directPath` → `/reportes-v2`, sin hijos). «Reporte a medida» es **un reporte más del shell de Reportes**, con una página propia y los guardados dentro de la vista de Reportes. Un clic desde la navegación en ambos diseños.

| Pieza | Contrato |
|-------|----------|
| Ruta | `/reportes-v2/reporte-a-medida` (catch-all existente `pages/reportes-v2/[[...slug]].tsx`; **no** crear página nueva). Abrir un guardado: `/reportes-v2/reporte-a-medida?pedido={id}` (shallow). El `id` en query es sólo una referencia; el servidor revalida todo |
| Registry (diseño clásico) | Nueva `ReportEntry` en `views/reports-v2/registry.ts`: `slug:'reporte-a-medida'`, `title:'Reporte a medida'`, `categories:['ventas']`, `icon:'tabler:adjustments-horizontal'`, `permissionSlug:'reporte-a-medida'`, `paramsSchema:{hasDateRange:false,hasFilter:false}`, `filterSchema:[]`, sin `cockpitLayout`, `bodyComponent` = `lazy(() => import('src/views/reports-v2/a-medida/ReporteMedidaBody'))`. Va **primero o último** de «🛒 Ventas» con badge **NUEVO** (chip dorado, 12px/700) hasta que `novedades.ts` lo retire |
| «Mis reportes» (diseño clásico) | `ReportsSidebar`: grupo nuevo **«Mis reportes»** debajo de las categorías (sólo si hay ≥1 guardado y el usuario tiene el permiso). Ítems = nombre del pedido, ícono `tabler:bookmark`, un clic → navega a `?pedido={id}` y **ejecuta**. Fuente: SWR `GET /reporte-medida/pedidos`. Máx. 10 visibles + «Ver todos (n)» que abre la tabla «Mis reportes guardados» de la página |
| Sección (diseño «Nuevo»: `nuevo/secciones.ts`) | Extender `SeccionKey` con `'a-medida'`: título **«A medida»**, ícono `tabler:adjustments-horizontal`, pregunta «¿Qué querés ver, a tu manera?», una sola pestaña **«Reporte a medida»** (slug `reporte-a-medida`). Aparece sólo si `puede('reporte-a-medida')` |
| «Mis reportes» (diseño «Nuevo») | Sin sidebar: en la cabecera de la página, botón **«Mis reportes (n)»** (MUI `Menu`, `startIcon tabler:bookmark`) a la izquierda de «Guardar reporte…»; mismo contenido que el grupo clásico. Un clic = ejecuta |
| Cuerpo | Único `ReporteMedidaBody` para ambos diseños (no duplicar). Se monta dentro del layout del shell sin `ReportsTopbar` de filtros (este reporte trae su propio Paso 3). Verificar en implementación que `ReportsTopbar`/`CockpitLayout` toleran `filterSchema:[]`; si no, el entry usa un wrapper que renderiza el cuerpo a pantalla completa (`contentHeightFixed` ya lo da el shell) |
| Plantilla «Stock actual ↗» | Navega a `/reportes-v2/stocks` (campo `enlace` de la plantilla en el catálogo); no ejecuta nada |
| Code splitting | `next/dynamic`/`lazy` obligatorio (CLAUDE.md). Gráfico y `FullTable` también diferidos hasta el primer resultado |

---

## Estructura de la página (mockup v4, de arriba a abajo)

**Punto focal:** antes de ejecutar, la barra sticky «Tu reporte» con el botón dorado **Ver reporte**; una vez que hay datos, la Card «Resultado» (titular de comparación y tabla).

Contenedor: ancho completo del shell, padding `md`(16) , scroll vertical de la página; la barra «Tu reporte» es **sticky inferior**.

1. **Encabezado**: `h1` «Reporte a medida» (20/700) + subtítulo 12/400 `text.secondary`: «Armá tu propio reporte eligiendo de una lista, dentro de los límites del local.» A la derecha: «Mis reportes (n)» (sólo diseño «Nuevo») .
2. **Selector de tipo** — «¿Con qué datos armás el reporte?» + 3 `Chip` seleccionables: **Datos de ventas** (activo, `tiposReporte[ventas]`), **Datos de gastos** y **Datos de facturación** (deshabilitados, sufijo «próximamente»; `aria-disabled`, tooltip con `motivoEs` del catálogo).
3. **Plantillas** (Card): título «Empezar desde una plantilla» + cap «— completa los pasos y muestra el resultado; después podés cambiar cualquier cosa.»; carrusel horizontal de tarjetas de 200 px con flechas ‹ › (`aria-label` «Plantillas anteriores» / «Más plantillas», scroll 420 px). Origen: `catalogo.plantillas`. Plantilla no disponible → opacidad .45, `cursor:not-allowed`, texto «No disponible en esta tienda» + `title`=`motivoEs`. «Stock actual ↗»: borde punteado.
4. **Grilla 2×2 de pasos** (2 columnas ≥981 px; 1 columna ≤980): Paso 1 «¿Qué querés ver?» · Paso 2 «¿Cómo lo separamos?» · Paso 3 «Período y filtros» · Paso 4 «¿Comparar?». Cada Card: círculo numerado 20 px dorado + título 14/700 + cap 12 `text.secondary`.
5. **Barra «Tu reporte»** (Card sticky `bottom:0`, sombra `0 -8px 20px rgba(0,0,0,.45)`, z-index 5): resumen en una frase + meta (filas estimadas + estado), alertas con arreglos, pie con «Se ejecuta con tus permisos y sólo con datos de tu local. Tiempo máximo 5 s.» y botones **Guardar reporte…** (outlined) y **Ver reporte** (contained, primario).
6. **Resultado** (Card): título + chip de meta + botón **Descargar CSV**; cuerpo: estados vacío/cargando/error/resultado.
7. **Mis reportes guardados** (Card): tabla Nombre · Qué muestra · Compartido · Estado · acciones; panel «Qué cambió» (diff) expandible; nota de revalidación.

Responsive: ≤980 px la columna lateral desaparece (sólo existe en diseño clásico) y todo apila en 1 columna; la tabla de resultados hace scroll horizontal.

---

## Paso 1 — Métricas (`opts` → MUI `Chip` seleccionable, `clickable`, variant outlined→filled gold-soft)

- Fuente: `catalogo.metricas` (id, `labelEs`, `definicionEs`, `formato`, `bloqueada`, `motivoEs`, `bloqueos[]`). Orden fijo del catálogo.
- Máximo **4 elegidas** (límite de UI del mockup). Las columnas **auto** (Unidades, Tickets, Precio por unidad al comparar, D-21) se muestran como chips punteados con prefijo «+» y **no cuentan** para el máximo. *(El límite de 6 del servidor aplica sólo a las métricas elegidas; las automáticas de comparación se agregan aparte. Si aun así devuelve `DEMASIADAS_METRICAS`, mostrar el error normal con sus arreglos.)*
- Subtítulo bajo el nombre en 2 chips (12px): «Promedio por ticket» → «cuánto gasta cada cliente»; «Precio por unidad» → «cuánto vale cada prenda».
- Tocar un chip alterna selección **y** muestra su definición en el recuadro `def` (borde izq. `info` #60a5fa 3 px, fondo `s2`) con `definicionEs` del catálogo. Esta definición permanece visible (D-01/D-26: la pantalla muestra la definición de cada métrica). Texto inicial: definición de Venta neta.
- Margen: si el usuario lo elige, línea de advertencia dorada «⚠ Sólo el {n} % de la venta tiene costo cargado: el margen se calcula sobre esa parte.» con `n` = `totales.cobertura_costo` (fracción) de la respuesta de `ejecutar`. **Desvío respecto de D-08/D-20 («siempre se muestra»):** ni el catálogo ni `validar` exponen la cobertura (sólo existe en el resultado ejecutado), y no se inventa un endpoint. Antes de ejecutar se muestra «⚠ El margen se calcula sólo sobre la parte de la venta con costo cargado; el porcentaje exacto aparece al ver el reporte.»; tras ejecutar, el porcentaje real, siempre visible en el recuadro de resultado mientras Margen esté en el reporte. Margen **nunca** en plantillas por defecto (D-20).
- Pista bajo los chips: «Ya elegiste 4 medidas (el máximo).» (tono `#ffd28a`) y «Las medidas con «+» se agregan solas porque estás comparando; no cuentan para el máximo de 4.»

## Paso 2 — Agrupaciones

- Fuente: `catalogo.dimensiones` (`grupo`, `disponible`, `motivoEs`, `cardinalidad`). Chips: Sucursal · Tiempo · Categoría · Producto · Vendedor · Temporada · Color · Talle · Medio de pago · **Cliente** (chip estático bloqueado: «son datos personales: necesita un permiso especial (no está en esta etapa)»; no viene del catálogo).
- «Tiempo» agrupa `dia|semana|mes|dia_semana|hora`. Al elegirlo aparece `Select` **«Tiempo por»**: Día · Semana · Mes · Día de la semana · Hora del día → `groupBy` toma el id correspondiente.
- Máx. 2 clasificaciones; máx. 1 de alta cardinalidad (Producto/Color/Talle); sólo un tiempo.
- Pista: «Podés agregar una clasificación más.» / «Ya tenés 2 clasificaciones (el máximo).» / «Producto, Color y Talle: ya usaste la única permitida.»
- Leyenda de íconos al pie del paso, sólo con los íconos presentes: bloqueo por permiso · máximo o combinación no permitida · tienda sin esos datos.

## Paso 3 — Período, filtros, orden y filas

- **Período** `Select`: presets de `catalogo.presetsPeriodo` (Hoy, Ayer, Esta semana, Semana pasada, Este mes, Mes pasado, Últimos 7/30/90 días, Últimos 12 meses). El mockup sólo mostraba 6; se muestran **todos** los del catálogo (default aceptado). Opción final «Rango de fechas…» → dos `DatePicker` (es-AR, `dd/MM/yyyy`) → `period:{from,to}`. Guardar un preset guarda el **preset** (D-14, relativo).
- Línea de rango: «Del **{rango}** · {n} días» + si el período incluye hoy: «· mes en curso (parcial)» en dorado.
- **Filtros**: `Select` «Sólo la sucursal» (visible sólo si hay ≥2 sucursales: `sucursalesCount`). Resto de filtros del catálogo (`filtros`: vendedores, medios de pago, categorías, temporadas, colores, talles) en un `Accordion` colapsado **«Más filtros»** con `Autocomplete multiple` (máx. 50 ids, `limites.maxIdsPorFiltro`); las listas de valores se piden con los hooks SWR de referencia existentes (`useSuppliersByStore`, etc., `src/hooks/api/`); si un filtro no tiene hook, se omite en esta ronda y se anota (no inventar endpoint).
- **Ordenar por** `Select`: «Fecha (orden natural)» / «Orden natural» (sólo con tiempo, sin dimensiones o con Talle) + cada métrica elegida «(mayor a menor)». Se oculta si sólo hay una opción.
- **Filas** `Select`: «Todas (en pantalla hasta 1.000 · CSV hasta 10.000)», Top 10, 20, 50, 100.
- Nota fija: «Fechas en hora del local (Buenos Aires). Ventas anuladas no cuentan. Incluye ventas importadas del sistema anterior.» (la zona se toma del local; no hardcodear «Buenos Aires» si la tienda tiene otra tz).

## Paso 4 — Comparación

3 chips exclusivos: **Sin comparar** · **Período anterior** · **Mismo período del año anterior** (`compare: null | 'periodo_anterior' | 'anio_anterior'`). Texto explicativo bajo los chips, con el rango comparado calculado como en el servidor (D-31/D-31a): rodante → «Contra el {rango} (mismos días de la semana, para que un sábado se compare con un sábado).» ; calendario → «(mismas fechas del mes)»; año anterior rodante → «52 semanas antes, mismos días de la semana» ; calendario → «mismas fechas del año anterior». Más: «Con inflación los pesos solos engañan: se agregan Unidades, Tickets y Precio por unidad (marcados con «+» en el paso 1).» *(El rango mostrado es orientativo; el rango real viene en `comparacion.desde/hasta` tras ejecutar y prevalece.)*

---

## Bloqueos con motivo (D-19, D-07, D-10 — requisito transversal)

Todo chip bloqueado: estilo `off` (texto `text.disabled`, borde punteado, `cursor:not-allowed`), **sigue visible**, `aria-disabled="true"`, ícono tabler al final y el motivo escrito en la lista «razones» debajo del paso (agrupada por motivo: «🔒 Margen — Sólo el administrador ve margen y costo»). Nunca `title` como único canal (accesibilidad táctil). Íconos: permiso `tabler:lock`, máximo/combinación `tabler:ban`, tienda sin datos `tabler:database-off`, próximamente `tabler:clock`.

Motivos (copy literal; cuando el catálogo trae `motivoEs`, éste gana):
| Caso | Copy |
|------|------|
| Margen sin permiso | «Sólo el administrador ve margen y costo» (catálogo) |
| Tickets / Promedio por ticket con Medio de pago | «Con «Medio de pago» no se puede: un ticket pagado con 2 medios contaría 2 veces.» |
| 2 clasificaciones ya elegidas | «Ya elegiste 2 clasificaciones (máximo). Quitá una para elegir otra.» |
| 2ª de alta cardinalidad | «Sólo una clasificación con muchísimos valores (Producto, Color o Talle) a la vez.» |
| Producto × Medio de pago | «Producto × Medio de pago no está disponible: el pago es del ticket, no de cada producto.» |
| Sucursal en tienda de 1 sucursal | «Esta tienda tiene una sola sucursal.» |
| Categoría sin datos | «Esta tienda no tiene categorías cargadas (todas «NONE»).» |
| Color con un solo valor | «Esta tienda tiene un solo color cargado («Color Único»).» |
| Cliente | «son datos personales: necesita un permiso especial (no está en esta etapa).» |

Al elegir Medio de pago estando Tickets/Promedio por ticket seleccionados: se quitan solos y aparece un `info` «Quitamos {métricas}: con Medio de pago un ticket pagado con 2 medios contaría 2 veces.»

---

## Barra «Tu reporte»: resumen, validación, arreglos

- **Resumen** (frase, 14/400, negritas en métricas y dimensión): «**Venta neta, Unidades** por **día**, del 19 sep–18 oct 2026, comparado con el período anterior, sólo los 20 primeros.» Sin dimensiones: «por **total del local**». Meta (12, mono en el número): «Filas: 30 (+ subtotales) · listo para ejecutar» (verde `#4ade80`) o «corregí lo marcado para poder ejecutar» (rojo `#ff8a80`). Texto del resumen: preferir `resumenEs` + `filasEstimadas` de `POST /validar`; el cálculo local sólo cubre el instante hasta que responda.
- **Validación**: `POST /reporte-medida/validar` con debounce 300 ms tras cada cambio (cancelar la anterior). Respuesta `{ok:false, errores:[{code,messageEs,fixes:[{labelEs,patch}]}]}` → una fila `Alert severity=error` por error con `messageEs` y un botón pequeño por `fix` (**«arreglo en un clic»**): aplicar = fusionar `fix.patch` en el pedido (`Object.assign` sobre el nivel raíz) y revalidar. Mientras haya error: **Ver reporte** y **Guardar reporte…** `disabled`.
- Copy de errores/arreglos conocidos (el servidor es la fuente; estos son los de los límites del mockup, coherentes con `LIMITES`): «Por día se puede ver hasta 90 días.» [Cambiar a «por semana» · Últimos 90 días] · «Por hora se puede ver hasta 31 días.» · «Producto tiene cientos de valores: elegí un Top (máx. 100).» [Aplicar Top 20] · «Producto × día: hasta 31 días.» · «Comparar con el año anterior: hasta 90 días.» · «Saldrían ~{n} filas (máximo 1.000 en pantalla).» [Aplicar Top 50] · «Elegí al menos una medida en el paso 1.» Mapeo de `code` a estos mensajes **no** se duplica en el front: se muestra `messageEs`.
- `info` (azul `#bcd7ff`/`infoS`): avisos no bloqueantes (métricas quitadas, «Este reporte incluye Margen, que no ves con tu permiso: se muestra sin esa columna.», `meta.omitidas[].motivoEs`).
- Errores de red/500/timeout se tratan como en «Estados» (no son validación).

---

## Resultado

**Ejecución**: `POST /reporte-medida/ejecutar {order}` (o `POST /pedidos/:id/ejecutar` para un guardado). Una ejecución a la vez por usuario (botón en estado «Ejecutando…» con `CircularProgress` 16 px, deshabilitado; sin reintento automático). Si el pedido cambia después de ejecutar → el resultado se marca **obsoleto**: cuerpo con opacidad .45 + grayscale, chip dorado «el reporte cambió — tocá «Ver reporte» otra vez»; **Descargar CSV** deshabilitado hasta re-ejecutar.

**Meta** (chip gris junto al título): «{desde}–{hasta} · {filas} filas». Si `meta.truncado`: chip dorado «mostrando las primeras 1.000 filas — el CSV trae todas (hasta 10.000)».

**Titular de comparación** (sólo con comparación): fondo `s2`, 14: «Total del período: **Venta neta ▲ +12 %** · Unidades ▼ −4 % — mirá el total; día por día la variación es más ruidosa.» Fuente: `comparacion.variacionTotal.{venta_neta,unidades}.varPct`; si `parcial:true` mostrar «hasta {hastaComparable}» y la nota «período en curso: se compara sólo hasta ayer»; si todo `null`: no mostrar titular.

**Tabla** (`FullTable`, `TABLE_ROW_HEIGHT`): columnas = `columnas[]` de la respuesta (dimensiones a la izquierda, texto; métricas a la derecha, alineadas a la derecha, mono 12). Formatos es-AR: moneda `$ 1.234.567` (sin decimales salvo `decimal`), enteros con `.` de miles, porcentaje desde **fracción** (0,25 → «25 %»; con coma decimal si hace falta «25,5 %»). Columnas `*_comp` y `*_var_pct` ocultas por defecto en columnas sueltas y mostradas como **«Var. venta» / «Var. unid.»** (▲ verde `#4ade80` / ▼ rojo `#ff8a80`, siempre con signo y flecha, nunca sólo color). Columnas auto al comparar: encabezado en cursiva con « ·» y `title` «agregada al comparar». Fila `parcial:true`: etiqueta dorada «parcial» junto al valor de tiempo y la celda de variación dice «parcial · sin comparar». Fila final fija **«Total»** (`totales`, borde superior 2 px dorado, 700). Filas «Sin vendedor», «Sin medio de pago», «Sin categoría» tal cual vienen (D-22). Con 2 dimensiones: la 1ª dimensión repite «〃» en filas consecutivas iguales (sin filas de subtotal, ver desvíos). Participación % (cuando `participacion` / plantilla «Más vendidos»): columna `{m}_pct`. Paginación cliente de **50 filas** (≤1.000), nota «Página 1 de N (de a 50 filas) — el CSV trae todas.»

**Notas al pie de la tabla** (12, `text.secondary`): una por condición presente — columnas con « ·» se agregan solas; «Promedio por ticket = venta ÷ tickets de cada fila; Precio por unidad = venta ÷ unidades.»; ««parcial» = período todavía en curso: no se compara con uno completo.»; `meta.notasEs[]`; definición de venta `meta.definicionVentaEs` en un `Accordion` «¿Cómo se calcula la venta?» (D-01/D-26).

**Gráfico** (ApexCharts, panel `s2`; a la derecha ≥981 px, debajo en menos; si hay >6 columnas ocupa una sola columna y el gráfico va debajo con máx. 520 px):
- Con Tiempo: líneas (1 serie por métrica elegida en pestañas `ctab`, o por valor de la otra dimensión, máx. 5 series — nota «Se muestran las 5 primeras; el resto está en la tabla.»). Comparación: línea gris punteada `#a3a3bd` = período comparado (nota «Línea gris punteada = período comparado.»). Buckets parciales: tramo punteado + punto hueco, nota «Tramo punteado y punto hueco = período en curso (parcial), no es una caída ni una suba real.»
- Sin Tiempo: barras verticales doradas, máx. 10 elementos.
- Pestañas por métrica (`Chip` pequeños `ctab`) si hay >1 métrica; Margen sólo para quien lo ve.
- Ejes en formato corto es-AR («$ 1,2 M», «$ 380 mil»). Paleta series: `#f5a623 #60a5fa #4ade80 #f472b6 #a78bfa`. Tooltip con valor completo. `role="img"` + `aria-label` con el resumen; la tabla es la alternativa accesible.

**CSV**: botón «Descargar CSV» → `POST /exportar-csv` (o `/pedidos/:id/exportar-csv`) con `responseType: blob`; nombre de archivo = `Content-Disposition`. Error `422 CSV_DEMASIADAS_FILAS` → `Alert` con `messageEs` y los `fixes` («Agregar un Top N», «Acotar el período») como botones que **llevan el foco al control correspondiente** (no traen `patch`). Timeout CSV 20 s.

---

## Guardar y gestionar pedidos (D-12..D-16)

- **Guardar reporte…** abre `Dialog` (md 480 px): `TextField` «Nombre del reporte» (1–120, requerido, autofocus, prellenado con un nombre sugerido tipo «Venta neta por día»), `Switch` **«Compartir con la tienda»** con ayuda «Lo puede ejecutar cualquiera que tenga el permiso de este menú. Siempre se revisa con los permisos de quien lo abre.» (default apagado: «sólo yo»), botones **Cancelar** / **Guardar reporte**. `POST /pedidos {name, shared, order}`. Éxito: toast «Guardado en «Mis reportes»: un clic lo vuelve a ejecutar con las fechas del día.» y el guardado aparece en la lista/sidebar (mutate SWR).
- **Tabla «Mis reportes guardados»** (`FullTable` 30 px): Nombre (con autor si no es mío: «de {autorNombre}») · Qué muestra (métricas · por dimensiones) · Compartido (`Chip` «con la tienda» / «sólo yo») · Estado (`Chip` verde «vigente» / dorado «definición cambió») · acciones: **Ejecutar** (contained, pequeño) · **Ver qué cambió** (sólo si `catalogoCambio`) · **Renombrar** (inline, `PATCH`) · **Guardar como…** (diálogo con nombre «{nombre} (copia)», crea nuevo, no pisa) · **Compartir/Dejar de compartir** (`PATCH shared`) · **Eliminar**. Sólo el autor ve Renombrar/Compartir/Eliminar/pisar (`esMio`); los compartidos ajenos ofrecen Ejecutar y Guardar como…
- **Reordenar**: arrastrar la fila por un asa `tabler:grip-vertical` (y alternativa con teclado: botones «Subir»/«Bajar» en el menú de la fila) → `PUT /pedidos/orden {ids}` con la lista completa en el nuevo orden, optimista con rollback si falla.
- **Abrir, cambiar, actualizar**: abrir un guardado carga sus pasos (los datos vienen de `GET /pedidos/:id`, `order`), ejecuta (`POST /pedidos/:id/ejecutar`) y muestra encima del paso 1 una franja «Estás viendo «{nombre}»» con acciones **Guardar cambios** (`PATCH order`) y **Guardar como…**. Si se cambia algo, la franja indica «cambios sin guardar».
- **Definición cambió (D-16)**: `meta.catalogoCambio` o `catalogoCambio` del listado → chip dorado + panel `diff` (borde dorado) «**Qué cambió en «{métrica}»** (versión del catálogo {a} → {b}, {fecha})»; líneas «Antes:» (rojo, tachado) y «Ahora:» (verde), nota «Los números de meses anteriores pueden bajar respecto de lo que viste antes. El reporte guardado no se modifica: se calcula con la definición actual.» y botón **Entendido** (descarta el aviso en el cliente; la lista sigue marcando hasta guardar de nuevo). *El texto «Antes/Ahora» sale de las notas de versión del catálogo; si el servidor no las entrega, mostrar sólo la nota genérica y el link a la definición actual — no inventar.*
- **Margen en guardado abierto por no-admin**: el servidor ya lo omite; mostrar `info` «Este reporte incluye Margen, que no ves con tu permiso: se muestra sin esa columna.» (`meta.omitidas`).
- Nota fija bajo la tabla: «Al abrir un reporte guardado se vuelve a validar con los permisos de quien lo abre (si lo abre un gerente, el margen no aparece). Los períodos como «este mes» se calculan el día que lo ejecutás.»
- **Eliminar** (única acción destructiva): `Dialog` «Eliminar «{nombre}»» / «Se borra el reporte guardado{ y deja de verlo la tienda si estaba compartido}. Esta acción no se puede deshacer.» / botones **Cancelar** y **Eliminar reporte** (rojo). Sin undo.

---

## Estados

| Estado | Contrato |
|--------|----------|
| Carga inicial del catálogo | `Skeleton` en plantillas y en los 4 pasos (chips fantasma); nada interactivo hasta tener `catalogo`. SWR 5 min dedup; objetivo ≤300 ms hasta pintar el esqueleto |
| Sin permiso al menú | El shell ya muestra «Sin permiso para este reporte» (candado + botón); no reimplementar |
| Resultado sin ejecutar | Caja punteada: «Elegí qué ver y tocá **Ver reporte**. El resultado aparece acá.» |
| Ejecutando | `Skeleton` de tabla (6 filas de 30 px) + chip «Ejecutando…»; botón con spinner; `aria-busy` en el cuerpo |
| Sin datos (0 filas) | Caja punteada: «No hay ventas en este período con estos filtros.» + cuerpo «Probá con otro período o quitá algún filtro.» + botón «Cambiar período» (foco en el Select de período). Distinguir de error |
| Resultado obsoleto | Ver «Resultado» |
| Error 400/422 de validación en ejecutar | Mismo `Alert` rojo que en la barra, con arreglos |
| Timeout 5 s / 500 | `Alert` rojo en el panel de resultado + toast global (doble señal, regla del proyecto): «No pudimos armar el reporte a tiempo. Probá con un período más corto o un Top, y volvé a tocar **Ver reporte**.» Botón **Reintentar** (acción del usuario; **sin reintento automático**) |
| 429 / ya hay una ejecución | «Ya hay un reporte en curso. Esperá a que termine para pedir otro.» |
| 403 (sin permiso / margen) | «No tenés permiso para esto. Pedile acceso al administrador del local.»; margen: «Sólo el administrador ve margen y costo.» |
| Guardado inexistente / borrado (404) | `Alert` «Ese reporte guardado ya no existe.» + volver a la lista |
| CSV demasiado grande (422) | Ver «CSV» |
| Offline / red | `Alert` «Sin conexión. Revisá tu internet y volvé a intentar.» |

---

## Spacing Scale

Declared values (múltiplos de 4; `theme.spacing(n)` = 8n):

| Token | Value | Usage |
|-------|-------|-------|
| xs | 4px | Separación ícono–texto, gap interno de chips, padding de badges |
| sm | 8px | Gap entre chips/opciones, padding de celdas y alertas, gap de botones |
| md | 16px | Padding interno de Cards, separación entre campos, márgenes de la grilla |
| lg | 24px | Separación entre Cards/secciones |
| xl | 32px | Márgenes de página en pantallas ≥1280 |
| 2xl | 48px | Vacíos/empty states (padding vertical) |
| 3xl | 64px | No se usa en esta pantalla |

Exceptions:
- Filas de tabla: **30 px** (`TABLE_ROW_HEIGHT`; el encabezado también 30 como en el mockup).
- Círculo de paso: 20 px; íconos 16/20 px; chips pequeños de altura 24 px; toque mínimo de controles interactivos sueltos (flechas del carrusel, asa de arrastre) 32 px.
- Tarjetas de plantilla: ancho fijo 200 px; gap 8 px.
- El mockup usa paddings de 14/10/6 px: se redondean a 16/8/8 al implementar (sin espacio de 6/10/14 en el código).

---

## Typography

Cuatro tamaños (3 de uso + 1 solo para el título), dos pesos (400 y 700). Los 11/11.5/12.5/13/13.5/14.5 px del mockup se normalizan así:

| Role | Size | Weight | Line Height |
|------|------|--------|-------------|
| Body (texto, chips, selects, botones, celdas de tabla, resumen) | 14px | 400 | 1.5 |
| Label (captions, ayudas, motivos, notas, encabezados de tabla, meta, badges, ejes del gráfico) | 12px | 400 (encabezados de tabla y chips seleccionados 700) | 1.4 |
| Heading (título de Card/paso, «Tu reporte», «Resultado») | 16px | 700 | 1.2 |
| Display (título de página «Reporte a medida») | 20px | 700 | 1.2 |

Notas: Heading = 16 px/700 (se corrige el 14 del mockup para separarlo del body, que también es 14). Cifras, fechas, montos y «Filas: n» en JetBrains Mono 12–14 px/400 (700 en fila Total y en el titular de variación). El peso 800 del mockup (badge NUEVO, paso, total) pasa a 700.

---

## Color

Tema Ventago oscuro (locked, `sketch-findings-ace-online`); usar **tokens del tema MUI** (`theme.palette.*`), no hex sueltos, salvo los marcados.

| Role | Value | Usage |
|------|-------|-------|
| Dominant (60%) | `#0f0f1e` (bg) / `#1a1a2e` (paper) | Fondo de página y Cards |
| Secondary (30%) | `#232342` (`s2`) / `#2a2a4a` (`s3`) / borde `#333355` | Chips sin seleccionar, tarjetas de plantilla, panel de gráfico, caja de resumen, encabezados de tabla, fila Total |
| Accent (10%) | `#f5a623` (gold) / soft `rgba(245,166,35,.12)` / borde `rgba(245,166,35,.35)` | Ver lista cerrada abajo |
| Destructive | `#ef4444` (texto `#ff8a80`, fondo `rgba(239,68,68,.14)`) | Errores bloqueantes, ▼ de variaciones negativas, botón «Eliminar reporte» |

Semánticos auxiliares (no son acento): ok `#4ade80` (▲, «listo para ejecutar», chip «vigente»); info `#60a5fa` (recuadro de definición, avisos informativos). Aviso cercano-al-límite `#ffd28a` sobre fondo dorado suave.

Accent reserved for (lista cerrada):
1. Botón primario **Ver reporte** (contained) y **Guardar reporte** en el diálogo.
2. Chip **seleccionado** (métrica, dimensión, comparación, tipo de datos, preset activo) — borde + texto + fondo soft + ✓ prefijo.
3. Círculo numerado de los pasos 1–4.
4. Ítem activo del menú de Reportes (borde izq. 3 px) y badge **NUEVO**.
5. Etiqueta «parcial» y chip «definición cambió» y «mostrando las primeras 1.000 filas».
6. Borde superior de la fila **Total** y borde de la caja de resumen.
7. Serie principal del gráfico (primer color de la paleta).
8. Botón secundario outlined (Guardar reporte…, Descargar CSV) usa borde/texto dorado **sólo en reposo**, sin relleno.

Todo lo demás (texto, íconos neutros, bordes, botones de texto, links) usa `text.primary/secondary` o el gris del tema. Contraste mínimo AA: texto `#a3a3bd` sobre `#1a1a2e` ≥4.5:1 (verificar `#7d7d98` sólo para texto ≥14 px bold o decorativo; para ayudas de 12 px usar `#a3a3bd`).

---

## Copywriting Contract

| Element | Copy |
|---------|------|
| Primary CTA | **Ver reporte** |
| Secondary CTA | **Guardar reporte…** (abre diálogo) · **Descargar CSV** |
| Título de página | Reporte a medida |
| Subtítulo | Armá tu propio reporte eligiendo de una lista, dentro de los límites del local. |
| Empty state (sin ejecutar) heading | Todavía no hay resultado |
| Empty state (sin ejecutar) body | Elegí qué ver y tocá **Ver reporte**. El resultado aparece acá. |
| Empty state (0 filas) heading | No hay ventas en este período con estos filtros |
| Empty state (0 filas) body | Probá con otro período o quitá algún filtro. |
| Empty state (sin guardados) | «Todavía no guardaste ningún reporte. Armá uno y tocá **Guardar reporte…** para volver a verlo con un clic.» |
| Error state (timeout/500) | No pudimos armar el reporte a tiempo. Probá con un período más corto o un Top, y volvé a tocar **Ver reporte**. |
| Error state (permiso) | No tenés permiso para esto. Pedile acceso al administrador del local. |
| Destructive confirmation | **Eliminar reporte guardado**: «Se borra «{nombre}»{ y deja de verlo la tienda si estaba compartido}. Esta acción no se puede deshacer.» → [Cancelar] [Eliminar reporte] |
| Destructive: pisar guardado | **Guardar cambios**: «Vas a reemplazar «{nombre}». Si querés conservar el original, usá **Guardar como…**.» → [Cancelar] [Guardar cambios] |
| Guardado OK (toast) | Guardado en «Mis reportes»: un clic lo vuelve a ejecutar con las fechas del día. |
| Pie de barra | Se ejecuta con tus permisos y sólo con datos de tu local. Tiempo máximo 5 s. |

Acciones destructivas de la fase: **Eliminar** guardado (confirmación obligatoria) y **pisar** un guardado con «Guardar cambios» (confirmación). «Guardar como…», «Compartir» y reordenar no son destructivas. Voseo en todo el texto («Armá», «Elegí», «Probá», «Tocá», «Pedile»); sin emojis en la UI (los del mockup pasan a íconos tabler).

Nombres de columnas/métricas: usar `labelEs` del catálogo, que ya incorpora D-32. No hardcodear etiquetas de métricas en el front.

---

## Accesibilidad e interacción

- Chips seleccionables: `role="checkbox"` (métricas, dimensiones) / `role="radio"` dentro de `radiogroup` (comparación, tipo de datos), `aria-checked`, `aria-disabled` + `aria-describedby` apuntando al motivo; foco visible 2 px dorado; Enter/Espacio alterna.
- Contenedores de alertas: `role="alert"` para errores, `role="status"` para info y para el resumen (anuncia cambios con `aria-live="polite"`).
- El color nunca es el único canal: ▲/▼ con signo, bloqueo con ícono + texto, parcial con etiqueta.
- Orden de tabulación = orden visual (tipo → plantillas → pasos 1–4 → barra → resultado → guardados). Al ejecutar, el foco pasa al título «Resultado» y la página hace `scrollIntoView` sólo si el resultado queda fuera de pantalla.
- Reordenar guardados operable con teclado (Subir/Bajar).
- Atajos globales: ninguno nuevo (no colisionar con los Alt+letra de `layouts/menu-atajos.ts`).

---

## Registro / Dependencias

| Registry | Blocks Used | Safety Gate |
|----------|-------------|-------------|
| shadcn official | none (no aplica) | not required |
| Third-party | none | not applicable — sin registries de terceros; sin dependencias nuevas (MUI, Iconify, react-apexcharts, FullTable ya instalados) |

---

## Desvíos mockup → implementación (deliberados)

1. **Sin filas de subtotal** con 2 dimensiones: la API no las entrega y sumar en el cliente es incorrecto para ratios (Promedio por ticket, Precio por unidad, Margen). Se agrupa visualmente con «〃». Si más adelante se quiere, se pide al servidor.
2. **Todos los presets** del catálogo (10) en lugar de los 6 del mockup; más «Rango de fechas…».
3. **Filtros extra** (vendedores, medios de pago, etc.) en «Más filtros» colapsado; el mockup sólo tenía Sucursal.
4. **Máximo de 4 métricas** en UI se conserva; el servidor admite 6 `maxMetricas` contando las auto. El front envía sólo las elegidas y deja que el servidor agregue las auto/omita con `omitidas`.
5. **Selector «Ver como» / «Tienda de ejemplo»** del mockup eran herramientas de demo: **no** se implementan; rol y tienda salen de la sesión.
6. **Guardados**: renombrar, compartir, reordenar y «Guardar como…» ya eran requisito (D-15) y se detallan aquí; el mockup sólo mostraba Ejecutar / Ver qué cambió / Guardar como.
7. Glifos emoji → íconos tabler; pesos 800 → 700; tamaños de fuente normalizados a 12/14/16/20.
8. Cliente se muestra como chip bloqueado estático (no está en el catálogo del servidor).

---

## Contrato de datos consumidos (resumen para el planner)

| Uso | Endpoint | Notas |
|-----|----------|-------|
| Catálogo, plantillas, disponibilidad, bloqueos | `GET /reporte-medida/catalogo` | SWR 5 min; incluye `limites`, `presetsPeriodo`, `tiposReporte`, `filtros`, `version` |
| Validar / resumen / filas estimadas | `POST /reporte-medida/validar {order}` | `{ok, resumenEs, filasEstimadas}` o `{ok:false, errores[{code,messageEs,fixes[{labelEs,patch}]}]}` |
| Ejecutar | `POST /reporte-medida/ejecutar {order}` | `{columnas, filas, totales, comparacion, meta}`; porcentajes como fracción |
| CSV | `POST /reporte-medida/exportar-csv {order}` | `text/csv` adjunto; 422 `CSV_DEMASIADAS_FILAS` |
| Guardados | `GET/POST /pedidos` · `GET/PATCH/DELETE /pedidos/:id` · `PUT /pedidos/orden` · `POST /pedidos/:id/ejecutar` · `POST /pedidos/:id/exportar-csv` | `esMio`, `autorNombre`, `catalogoCambio`, `shared`, `position` |

Pedido JSON v1: `{v:1,type:'ventas',metrics[],groupBy[],period:{preset}|{from,to},compare,filters?,sort?{by,dir},top?,participacion?}`. El front **no** manda `store_id` ni permisos (D-16).

---

## Checker Sign-Off

- [ ] Dimension 1 Copywriting: PASS
- [ ] Dimension 2 Visuals: PASS
- [ ] Dimension 3 Color: PASS
- [ ] Dimension 4 Typography: PASS
- [ ] Dimension 5 Spacing: PASS
- [ ] Dimension 6 Registry Safety: PASS

**Approval:** pending
