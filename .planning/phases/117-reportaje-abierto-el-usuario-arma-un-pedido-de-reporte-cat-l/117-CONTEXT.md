# Phase 117: Reportaje abierto - Context

**Gathered:** 2026-10-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Nuevo menú «Reportaje abierto» dentro de Reportes: el usuario arma un **pedido de reporte** eligiendo de un
catálogo cerrado (métricas · agrupaciones · período/filtros · comparación · orden/Top N). El servidor valida el
pedido (tienda forzada por sesión, permisos, límites), lo compila a SQL parametrizado desde un catálogo semántico
(nunca SQL libre), lo ejecuta y devuelve tabla + gráfico + CSV. Los pedidos se **guardan y se vuelven a ejecutar
fácil** (pedido explícito del usuario).

Fuera: asistente IA que escribe el pedido desde lenguaje natural (fase futura, mismo JSON), reporte de stock
como tipo propio, gastos, cliente como dimensión.

</domain>

<decisions>
## Implementation Decisions

### Definición de «venta» y relación con Phase 105
- **D-01:** El **fragmento SQL común de «venta»** (principios de Phase 105 §1) se construye **dentro de 117 como primer paso** y Reportaje abierto lo usa. Migrar los reportes existentes a ese fragmento queda en Phase 105 (no en 117). Mientras 105 no esté hecha los números pueden diferir de las pantallas viejas → la pantalla muestra la definición de cada métrica.
- **D-02:** Universo de venta = Phase 105 §1: `activity_type='sale'` + status válido; movido/devuelto/fallado **no** cuentan como venta (ni monto, ni unidades, ni tickets). Fecha = día local de la tienda (DB en UTC).
- **D-03:** Devoluciones = Phase 105 D1: **Venta neta = con devoluciones restadas**; «Devoluciones» es una métrica aparte que se puede elegir.
- **D-04:** Costo/margen = Phase 105 D2: **costo por línea** (no todo-o-nada por ticket). Participación (%) siempre sobre el **total**, nunca sobre el Top N.

### Quién lo usa (permisos)
- **D-05:** **Permiso nuevo** propio (función/acción en el sistema de permisos). Por defecto **sólo admin**; la tienda puede habilitarlo a gerente u otros desde la gestión de roles. ⚠ El menú sale de `structure` → el seed va **antes** que el código ([[sidebar-derives-from-structure-seed-first]]).
- **D-06:** Alcance de sucursales = el mismo que ya aplica a ese usuario en los reportes existentes (no se inventa otra regla).
- **D-07:** **Margen y costo sólo admin.** Para otros roles la métrica aparece bloqueada con el motivo.

### Catálogo de la 1ª etapa
- **D-08:** Métricas: Venta neta · Unidades · Tickets · Ticket promedio (= SUM(neta)/SUM(tickets), recalculado por fila) · Devoluciones · **Margen (admin)**. Margen muestra además «% de la venta con costo cargado» (tiendas con costo mayormente vacío).
- **D-09:** Agrupaciones: Sucursal · Tiempo (día/semana/mes local) · Categoría · Producto/madre (**Top N obligatorio**) · **Vendedor** · **Temporada · Color · Talle** · **Medio de pago**.
- **D-10:** Medio de pago: el monto es lo **efectivamente cobrado por cada medio** (un ticket puede tener varios); con esa agrupación **Tickets y Ticket promedio quedan bloqueados** (si no, se duplican).
- **D-11:** Stock no entra al pedido de ventas (es foto, no se suma en el tiempo) — la plantilla «Stock actual» lleva a la pantalla existente.

### Pedidos guardados
- **D-12:** Al guardar: por defecto **sólo el autor**; opción **«Compartir con la tienda»** → lo ejecuta cualquiera con el permiso del menú. Siempre se **re-valida con los permisos de quien lo abre** (un pedido con margen abierto por gerente sale sin la columna margen).
- **D-13:** **Re-ejecución fácil**: los guardados aparecen en el menú lateral bajo Reportaje abierto (un clic = ejecuta). ⚠ Reportes hoy es «vista unificada» (`directPath`, sin hijos en el sidebar) → el researcher decide si van en el sidebar global o en el menú izquierdo de la vista Reportes; requisito = un clic desde la navegación.
- **D-14:** Períodos guardados **relativos** («este mes», «últimos 30 días») se resuelven el día que se ejecuta, no el día que se guardó.
- **D-15:** Gestión: renombrar · reordenar · borrar · abrir, cambiar y **«Guardar como»** (variante sin pisar el original).
- **D-16:** El pedido guardado **no** guarda store_id ni resultado de permisos; guarda versión del catálogo → si una definición cambió, aviso «definición cambió».

### Ajustes tras la investigación (117-RESEARCH-USUARIOS.md, aprobados 2026-10-17 «그대로 진행하자»)
- **D-17 (P1):** El universo de «venta» **incluye las ventas importadas del sistema legacy**. Antes de fijar el fragmento común: **medir y fijar la regla de duplicados** legacy↔POS (Cache tiene ambos el mismo día). Sin esto el 80 % de las ventas recientes de la mayoría de las tiendas desaparece.
- **D-18 (P2):** El catálogo tiene un **eje «tipo de reporte»** desde el diseño: **Ventas** (1ª etapa) → **Gastos** (siguiente) → **Facturación** (sólo cuando incluya `legacy_facturas`; si no, casi todas muestran 0 % facturado). Tipos = ledgers distintos, nunca filas mezcladas.
- **D-19 (P3):** **Disponibilidad por tienda**: una agrupación con un solo valor o todo `NONE` en esa tienda aparece **gris con el motivo** («Esta tienda no tiene categorías cargadas»). Comunes a todas: tiempo · producto · vendedor · medio de pago.
- **D-20 (P4):** Margen sigue como métrica admin pero **fuera de las plantillas por defecto**; siempre se muestra el **% de venta con costo cargado**.
- **D-21 (P5):** Con comparación activa se muestran **siempre unidades · tickets · precio promedio (AUR)** junto a los pesos (inflación). Ajuste por IPC = 2ª etapa.
- **D-22 (P6):** Filas «Sin vendedor» y «Sin medio de pago»; vendedor desde `sales.seller_id` (no `user_id`); nombres de medio de pago normalizados sólo para mostrar.
- **D-23 (P7):** Plantillas 1ª etapa: ventas por día/mes + comparación · más vendidos (madre, % sobre total) · por vendedor · por medio de pago (sólo montos) · talle × color (sólo si hay datos; talles en orden numérico, PEDIDO 40) · comparación de sucursales (sólo tiendas multi-sucursal) · día de semana/hora · devoluciones.
- **D-24 (P8):** Antes del build pesado de UI, el **usuario** muestra el mockup a 2–3 dueños (Shaple · NOIX · Cache · Cielo). Mientras tanto se avanza con el fragmento común de venta (D-01/D-17), que no depende de esa validación.

- **D-25 (plan-phase 2026-10-17):** Esta ronda de planes = **sólo servidor**: fragmento común de venta + regla de duplicados legacy↔POS + catálogo/validador/compilador + API de pedidos guardados + seed de permiso. **La UI se planifica después** de la validación con dueños (D-24), con UI-SPEC propio.

### Decisiones tras 117-RESEARCH.md (usuario, 2026-10-17)
- **D-26:** Venta neta = **devengado** (cuenta el día de la venta, aunque sea a crédito) — igual que Ganancia, distinto de Ventas › Totales (caja). La pantalla muestra la definición.
- **D-27:** Margen/costo con **función nueva sólo admin** (p.ej. `reporte-a-medida-margen`), sembrada sólo para admin; **no** se hereda de `reporte-ganancia` / `ver-costo-producto` (están dados a roles no-admin en 10 tiendas).
- **D-28:** Legacy + POS = **unión de todos los `sales.source`, sin dedupe en la consulta** (es un corte temporal por tienda, medido). Se agrega un **monitor de posibles duplicados** y desglose por origen; el par NOIX (legacy 140311 / POS 242) **se deja como está** (no se tocan datos).
- **D-29:** Nombre visible del menú: **«Reporte a medida»** (reemplaza «Reportaje abierto» en UI y textos; slugs/tablas nuevas con ese nombre).
- **D-30 (defaults aceptados de la investigación):** `NONE` y `General` cuentan como «sin valor» para D-19 · categoría/temporada = `COALESCE(hijo, madre)` · Ticket promedio bloqueado con agrupaciones de nivel ítem (producto/color/talle) · margen con el mismo tratamiento de devoluciones que Ganancia · alcance de sucursales = tienda completa (igual que los reportes actuales hoy; `resolveAllowedBranchIds` queda para después) · devoluciones sólo por sucursal y tiempo (la fila de devolución no tiene vendedor ni ítems).

### Claude's Discretion (valores de CODEX salvo que la investigación pida otro)
- Límites MVP: ≤2 agrupaciones (≤1 de «muchas filas»: producto/vendedor/color/talle según cardinalidad real) · por día ≤90 días, semana/mes ≤12 meses · pantalla ≤1.000 filas (preview 20–50) · CSV ≤10.000 · Top ≤100 · timeout 5 s (CSV 20 s), sin reintento automático · 1 ejecución a la vez por tienda y por usuario · semáforo global 4–6.
- Combinaciones prohibidas: producto×día sin Top y >31 días · producto×medio de pago · ticket/ticket promedio × medio de pago · comparación año anterior >90 días.
- Comparación: una a la vez (período anterior / mismo período año anterior).
- UX según mockup: plantillas arriba · 4 pasos · motivo visible en lo bloqueado · resumen en una frase + filas estimadas · arreglos en un clic cuando se pasa un límite · definición de cada métrica.
- Primaria (no réplica 운용3) con límites + log de lentas; medir antes de pensar en réplica.
- Formato es-AR (miles «.», decimales «,»), moneda $.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Diseño y consejo
- `.planning/mockups/2026-10-17-reportaje-abierto/mockup.html` — mockup interactivo aprobado (plantillas, 4 pasos, bloqueos con motivo, resumen, resultado, guardados)
- `.planning/mockups/2026-10-17-reportaje-abierto/CODEX.md` — consejo CODEX completo (riesgos, límites, catálogo mínimo, UX, réplica)
- `.planning/phases/117-reportaje-abierto-el-usuario-arma-un-pedido-de-reporte-cat-l/117-PREP.md` — registro y estructura acordada
- `.planning/phases/117-reportaje-abierto-el-usuario-arma-un-pedido-de-reporte-cat-l/117-RESEARCH-USUARIOS.md` — qué reportes quieren dueños (externo + datos reales); fuente de D-17..D-24
- `.planning/phases/117-reportaje-abierto-el-usuario-arma-un-pedido-de-reporte-cat-l/research/interno.md` — mediciones de prod (costo cargado, dimensiones vacías, legacy vs POS, medios de pago)

### Definición de venta (obligatorio)
- `.planning/phases/105-*/105-PLAN.md` §1 (principios) y §2 W3 (D1 devoluciones, D2 costo por línea) — universo único de venta
- `api-ventago/src/app/reports/sale-status.constants.ts` — constantes de estado existentes (el fragmento común nace aquí o al lado)

### Reglas del proyecto
- `CLAUDE.md` — rendimiento (pool max 20/worker, pgbouncer 50, p95 300 ms, pageSize ≤50, SWR), tabla 30 px (`TABLE_ROW_HEIGHT`), ESLint, migraciones (expand/contract, CONCURRENTLY), permisos (`-- perm-cache:`)
- `.claude/skills/sketch-findings-ace-online/` — tema navy + dorado

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `api-ventago/src/app/reports/*` — servicios de reportes con `@Auth(admin, gerente, superadmin)`; `reportsEnviado.service.ts` valida IANA tz y filtra por día local con `AT TIME ZONE :tz` (patrón a copiar).
- `salesDimensions.service.ts` / `reportsSalesCockpit.service.ts` — agrupaciones por dimensión ya existentes (referencia; Phase 105 los corrige).
- Front: `ventago-app/src/pages/reportes/` (vista unificada, `directPath` en `navigation/vertical/index.ts`), `FullTable` + `TABLE_ROW_HEIGHT`, `ensureAgGridInit()`.

### Established Patterns
- Multitenant: store_id desde sesión; aislamiento absoluto ([[tenant-isolation-is-absolute]]).
- Reportes los consumen también apps Flutter ([[reports-api-has-flutter-consumers]]) → endpoints nuevos, no cambiar los existentes.
- POS escribe `stocks.type` NULL; `stock_balances.total_venta` no cuenta POS ([[pos-sales-write-stocks-type-null]]) — no usarlo para ventas.
- Precios/montos double; formato es-AR.

### Integration Points
- Nuevo módulo API (catálogo + validador + compilador + guardados) y tabla de pedidos guardados (store_id, owner_user_id, shared, nombre, orden, pedido JSON, versión catálogo).
- Seed de permiso/structure del menú (antes del deploy de código).
- Vista Reportes: nueva sección + navegación de guardados.

</code_context>

<specifics>
## Specific Ideas

- Usuario: «reportaje abierto 라는 식으로 메뉴를 하나 준비하고, 거기 사용자가 정해진 주문서를 허용된 한도 내에서 만들 수 있게».
- Usuario: «생성한 reportaje abierto 를 저장했다가 다시 쉽게 실행하게 하면 좋을 것 같아» → D-12..D-16.
- Referencias de mercado: Odoo pivot + favoritos, Metabase «question builder», Looker capa semántica.

</specifics>

<deferred>
## Deferred Ideas

- Asistente IA que escribe el mismo pedido JSON desde lenguaje natural (es/ko) — fase propia; decide modelo (Ollama vs API paga).
- Migrar los reportes existentes al fragmento común de venta — Phase 105.
- Gastos como tipo de reporte propio; Cliente como dimensión (requiere permiso de datos personales); Stock como tipo propio dentro de Reportaje abierto.
- Lecturas en réplica 운용3 — Phase 115 (paso 1, read-offload) tras medir.
- Power BI — Phase 114.

</deferred>

---

*Phase: 117-reportaje-abierto*
*Context gathered: 2026-10-17*
