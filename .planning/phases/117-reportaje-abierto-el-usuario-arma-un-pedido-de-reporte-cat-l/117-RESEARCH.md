# Phase 117: Reportaje abierto (SERVER SIDE ONLY, D-25) - Research

**Researched:** 2026-10-17
**Domain:** NestJS 11 + Sequelize raw-SQL semantic-catalog report compiler on PostgreSQL 18 (multi-tenant POS/ERP)
**Confidence:** HIGH on repo facts and prod measurements (all measured or read in this session); MEDIUM on the concurrency design and CSV conventions (no precedent in repo); items tagged `[ASSUMED]` need user confirmation.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
(Copied from 117-CONTEXT.md; D-01..D-25. Server-side relevant ones are all of them except the UI-only parts of D-13/D-15 and the mockup validation D-24.)

- **D-01:** El **fragmento SQL común de «venta»** (principios de Phase 105 §1) se construye **dentro de 117 como primer paso** y Reportaje abierto lo usa. Migrar los reportes existentes a ese fragmento queda en Phase 105 (no en 117). Mientras 105 no esté hecha los números pueden diferir de las pantallas viejas → la pantalla muestra la definición de cada métrica.
- **D-02:** Universo de venta = Phase 105 §1: `activity_type='sale'` + status válido; movido/devuelto/fallado **no** cuentan como venta (ni monto, ni unidades, ni tickets). Fecha = día local de la tienda (DB en UTC).
- **D-03:** Devoluciones = Phase 105 D1: **Venta neta = con devoluciones restadas**; «Devoluciones» es una métrica aparte que se puede elegir.
- **D-04:** Costo/margen = Phase 105 D2: **costo por línea** (no todo-o-nada por ticket). Participación (%) siempre sobre el **total**, nunca sobre el Top N.
- **D-05:** **Permiso nuevo** propio (función/acción en el sistema de permisos). Por defecto **sólo admin**; la tienda puede habilitarlo a gerente u otros desde la gestión de roles. ⚠ El menú sale de `structure` → el seed va **antes** que el código.
- **D-06:** Alcance de sucursales = el mismo que ya aplica a ese usuario en los reportes existentes (no se inventa otra regla).
- **D-07:** **Margen y costo sólo admin.** Para otros roles la métrica aparece bloqueada con el motivo.
- **D-08:** Métricas: Venta neta · Unidades · Tickets · Ticket promedio (= SUM(neta)/SUM(tickets), recalculado por fila) · Devoluciones · **Margen (admin)**. Margen muestra además «% de la venta con costo cargado».
- **D-09:** Agrupaciones: Sucursal · Tiempo (día/semana/mes local) · Categoría · Producto/madre (**Top N obligatorio**) · **Vendedor** · **Temporada · Color · Talle** · **Medio de pago**.
- **D-10:** Medio de pago: el monto es lo **efectivamente cobrado por cada medio**; con esa agrupación **Tickets y Ticket promedio quedan bloqueados**.
- **D-11:** Stock no entra al pedido de ventas.
- **D-12:** Al guardar: por defecto **sólo el autor**; opción **«Compartir con la tienda»** → lo ejecuta cualquiera con el permiso del menú. Siempre se **re-valida con los permisos de quien lo abre**.
- **D-13:** **Re-ejecución fácil**: guardados accesibles en un clic desde la navegación (researcher decide dónde).
- **D-14:** Períodos guardados **relativos** se resuelven el día que se ejecuta.
- **D-15:** Gestión: renombrar · reordenar · borrar · abrir, cambiar y **«Guardar como»**.
- **D-16:** El pedido guardado **no** guarda store_id ni resultado de permisos; guarda versión del catálogo → aviso «definición cambió».
- **D-17 (P1):** El universo de «venta» **incluye las ventas importadas del sistema legacy**. Antes de fijar el fragmento común: **medir y fijar la regla de duplicados** legacy↔POS.
- **D-18 (P2):** Eje «tipo de reporte» desde el diseño: **Ventas** (1ª etapa) → **Gastos** → **Facturación** (sólo con `legacy_facturas`). Tipos = ledgers distintos, nunca filas mezcladas.
- **D-19 (P3):** **Disponibilidad por tienda**: agrupación con un solo valor o todo `NONE` aparece **gris con el motivo**. Comunes: tiempo · producto · vendedor · medio de pago.
- **D-20 (P4):** Margen fuera de las plantillas por defecto; siempre se muestra el % de venta con costo cargado.
- **D-21 (P5):** Con comparación activa se muestran **siempre unidades · tickets · precio promedio (AUR)** junto a los pesos.
- **D-22 (P6):** Filas «Sin vendedor» y «Sin medio de pago»; vendedor desde `sales.seller_id` (no `user_id`); nombres de medio de pago normalizados sólo para mostrar.
- **D-23 (P7):** Plantillas 1ª etapa (ventas por día/mes + comparación · más vendidos · por vendedor · por medio de pago · talle × color · comparación de sucursales · día de semana/hora · devoluciones).
- **D-24 (P8):** Mockup a dueños antes del build pesado de UI (usuario). Se avanza con el fragmento común.
- **D-25:** Esta ronda de planes = **sólo servidor**: fragmento común + regla de duplicados + catálogo/validador/compilador + API de pedidos guardados + seed de permiso. La UI se planifica después.

### Claude's Discretion (valores de CODEX salvo que la investigación pida otro)
- Límites MVP: ≤2 agrupaciones (≤1 de «muchas filas») · por día ≤90 días, semana/mes ≤12 meses · pantalla ≤1.000 filas (preview 20–50) · CSV ≤10.000 · Top ≤100 · timeout 5 s (CSV 20 s), sin reintento · 1 ejecución a la vez por tienda y por usuario · semáforo global 4–6.
- Combinaciones prohibidas: producto×día sin Top y >31 días · producto×medio de pago · ticket/ticket promedio × medio de pago · comparación año anterior >90 días.
- Comparación: una a la vez (período anterior / mismo período año anterior).
- UX según mockup (motivos visibles, resumen en una frase, filas estimadas, definiciones).
- Primaria (no réplica 운용3) con límites + log de lentas.
- Formato es-AR, moneda $.

### Deferred Ideas (OUT OF SCOPE)
- Asistente IA que escribe el pedido JSON desde lenguaje natural.
- Migrar los reportes existentes al fragmento común — Phase 105.
- Gastos como tipo propio; Cliente como dimensión; Stock como tipo propio.
- Lecturas en réplica 운용3 — Phase 115.
- Power BI — Phase 114.
</user_constraints>

<phase_requirements>
## Phase Requirements

No REQ-IDs were supplied; the CONTEXT decisions are the requirement set. Server-side mapping:

| ID | Description | Research Support |
|----|-------------|------------------|
| D-01/D-02 | Shared «venta» fragment, local day | §Shared fragment; `sale_day_local` column exists; ±1-day coarse range uses `idx_sales_store_date` |
| D-03 | Devoluciones subtracted | §Metrics: only attributable at header grain (sucursal/tiempo); `devolucionesFilasSql` exists but has a UTC-day defect |
| D-04/D-08/D-20 | Line-level cost, margin + % coverage | `sale_items.unit_cost` frozen at sale; Ganancia query is the reference |
| D-05/D-07 | New permission, margin admin-only | §Permission; **DB finding: non-admin roles hold `reporte-ganancia` in 10 stores** |
| D-06 | Branch scope = existing reports | Existing reports do NOT apply `resolveAllowedBranchIds`; see Open Question 2 |
| D-09/D-19/D-22 | Dimensions + availability + «Sin X» rows | §Dimensions mapping (category/season live on the **madre**, not the leaf) |
| D-10 | Payment-method grain | `sale_payment_methods.amount` sums to `total_amount` (0 mismatches in 90 d) |
| D-12..D-16 | Saved orders | §Saved orders table (+ backup/vaciado registration checklist) |
| D-17 | Legacy included + dedupe rule | §Legacy vs POS (measured): **no dedupe in the query; union by source** |
| D-18 | Report-type axis | §Catalog design |
| D-25 | Server only | UI placement recommendation recorded (D-13) but not planned |
</phase_requirements>

## Summary

The semantic-catalog → validated JSON → compiled SQL approach is feasible within the repo's existing primitives. The sale universe is already ~90 % encoded in `api-ventago/src/app/reports/sale-status.constants.ts` (`ACCOUNTING_SALE_STATUSES`, `SOLO_VENTA_SQL`, `saleBranchSql`, `EXCLUDE_DEUDA_PAGO_SQL`, `signedTxSql`, `devolucionesFilasSql`); the Ganancia query (`reportsGanancia.service.ts`) is a near-perfect reference for local-day, line-level cost and returns. A prototype of the heaviest realistic query (Shaple, store 26, 91 days, group by madre, items join) ran in **45 ms** on prod PG18 using only existing indexes (`idx_sales_store_date`, `idx_sale_items_sale_id`, `products_pkey`), so no new indexes are needed on the hot path and the 5 s timeout is generous.

Four findings change the plan versus what CONTEXT assumes. (1) **Legacy vs POS is a clean temporal cutover per store, not a parallel double entry** — across all prod sales since 2026-08-01 exactly **1** legacy/POS pair is a true duplicate (NOIX, ids 140311/242, identical items, 1 min apart); Cache (store 30) cut over 2026-10-14 (last legacy 11:22, first POS 11:49) with zero duplicates. Recommended rule: **union of all `source` values, no dedupe in the hot query**, plus a monitoring itest. (2) **Category and season live on the madre for variant stores** (Shaple: leaf category null 100 %, madre-or-leaf null 1 %); the existing `SALE_ITEM_DIM_CTE` reads only the leaf, so it shows «Sin categoría» for Shaple — the new catalog must `COALESCE(leaf, madre)`. (3) **Devoluciones and «venta neta con devoluciones» are only attributable at header grain** (sucursal, tiempo); the return row has total 0, no seller, no items subtotal (prod has exactly 1 `devuelto` row in history). (4) **`reporte-ganancia` is held by cashier/viewer/accountant roles in 10 stores**, so reusing it as the margin gate does not literally satisfy D-07 «sólo admin».

**Primary recommendation:** Build a new module `api-ventago/src/app/reportaje/` with a pure, unit-testable pipeline (catalog allowlist → hand-written strict order validator → pure SQL compiler over a new `reports/venta-universe.ts` fragment → executor that runs inside `READ ONLY` + `SET LOCAL statement_timeout` + `pg_try_advisory_xact_lock` for store/user/global limits). Use Sequelize `bind` (`$1…`) for all values, never string-concat user input, and keep Redis out of the concurrency path.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Catalog (metrics/dimensions/filters, versions, availability rules) | API / Backend | — | Allowlist must be server code; UI only renders what `GET /reportaje/catalog` returns |
| Order validation (limits, forbidden combos, permissions, tenant) | API / Backend | — | Security boundary; the global ValidationPipe is lenient so validation is explicit |
| SQL compilation + execution | API / Backend | Database | Pure compiler in API; DB enforces READ ONLY, timeout, advisory locks |
| Local-day / relative periods | API / Backend | Database | Store IANA tz resolved server-side; `sale_day_local` column on DB |
| Concurrency limits (store/user/global) | Database (advisory locks) | API | Crosses PM2 workers and blue/green containers without Redis |
| Saved orders persistence | Database | API | New table, store+owner scoped, re-validated on every run |
| Permission gating (menu, run, margin field gating) | API / Backend | Database (seed) | `FunctionGuard` + `isAllowedStrict`; seed precedes code |
| CSV export | API / Backend | — | Server-built, row-capped; no client-side export |
| Saved-orders navigation (D-13) | Browser / Client | — | Deferred (D-25); recommendation recorded below |
| Stock/Gastos/Facturación types | — | — | Deferred; catalog axis reserved only |

## Standard Stack

### Core (all already in the repo — no new packages)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| NestJS | 11 | Module/controller/DI | [VERIFIED: CLAUDE.md] project framework |
| sequelize + sequelize-typescript | repo | `sequelize.query(sql, {bind, type})`, transactions | Repo standard for report raw SQL |
| class-validator | ^0.14.1 | Envelope DTOs only (name, shared, position) | [VERIFIED: api-ventago/package.json] already used |
| exceljs | ^4.4.0 | Not needed for CSV (hand-written `toCsv`), kept for a future xlsx | [VERIFIED: package.json] |
| jest + ts-jest | 29.7 | Unit specs (`*.spec.ts`, rootDir `src`) | [VERIFIED: package.json] |

### Supporting
| Library | Purpose | When to Use |
|---------|---------|-------------|
| `common/cache/memory-cache.service.ts` (`getOrLoad`, 60 s TTL) | Cache D-19 availability per store | Reference-data rule in CLAUDE.md (60 s) |
| `common/constants/timezone.ts` (`DEFAULT_STORE_TZ`) | tz fallback | Same as Ganancia/Enviado |
| `common/tenant/branch-scope.util.ts` (`resolveAllowedBranchIds`) | Optional stricter branch scope | Open Question 2 |
| `auth/services/function-permission.service.ts` (`isAllowedStrict`) | Margin field gating | Mirrors `reports.controller.ts` ganancia pattern |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Hand-written order validator | zod / ajv | Not installed; adding a dependency for one JSON shape is unjustified; the validator must be catalog-driven anyway (allowed keys depend on catalog) |
| Redis lock for store/user concurrency | `pg_try_advisory_xact_lock` | Redis = extra failure mode + the «Redis must not block boot» spec; advisory xact locks auto-release on commit/rollback/crash and the repo already uses `pg_advisory_xact_lock` in 4 places |
| New read pool / replica | primary only | CODEX + D: MVP on primary with limits |

**Installation:** none. `npm view` verification not applicable (no new packages).

## Package Legitimacy Audit

No external packages are recommended in this phase. slopcheck not run (nothing to check).

**Packages removed due to slopcheck [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

## Architecture Patterns

### System Architecture Diagram

```
HTTP (JWT) ── POST /reportaje/run  { type, order }        ── POST /reportaje/export.csv
   │            │                                             (same pipeline, csv limits)
   ▼            ▼
FunctionGuard('reportaje-abierto','read')   ← seed first (functions row must exist)
   │
   ▼
Controller: storeId := storeIdOfUser(user)   (NEVER from body/query; superadmin act-as via resolveScopedStoreId pattern)
   │  marginAllowed := isAllowedStrict(user, ganancia+costo)   (field gating)
   ▼
OrderValidator (pure) ── unknown key → 400 ── limits/forbidden combos → 400 with {code, fixes[]}
   │   uses CATALOG (allowlist) + ctx {storeTz, marginAllowed, availability(store)}
   │   resolves relative period → absolute dates in store tz
   ▼
BranchValidator: branch ids ⊂ branches WHERE store_id = :store   (1 cheap query)
   ▼
Compiler (pure): grain selection → CTEs from venta-universe.ts → SELECT/GROUP BY from catalog expr
   │   output {sql, bind[], columns[], meta}  (no user text ever in sql)
   ▼
Executor:  sequelize.transaction ─┬─ SET TRANSACTION READ ONLY; SET LOCAL statement_timeout='5s'|'20s'
   (1 pooled connection)          ├─ pg_try_advisory_xact_lock(117, store)  → else 429 STORE_BUSY
                                  ├─ pg_try_advisory_xact_lock(118, user)   → else 429 USER_BUSY
                                  ├─ pg_try_advisory_xact_lock(119, slot i<N) → else 429 SERVER_BUSY
                                  ├─ main query (LIMIT cap+1 → truncated flag)
                                  └─ [comparison query, same tx]  → merge in app
   ▼
Post-process (app): size natural sort, share% over TOTAL, totals row, AUR, definitions → JSON / CSV
```

### Recommended Project Structure
```
api-ventago/src/app/reports/venta-universe.ts      # D-01: pure SQL fragment builders (next to sale-status.constants.ts)
api-ventago/src/app/reportaje/
├── reportaje.module.ts
├── reportaje.controller.ts                         # GET catalog · POST run · POST export.csv · CRUD pedidos
├── catalog/
│   ├── catalog.ts                                  # CATALOG_VERSION, REPORT_TYPES{ventas}, METRICS, DIMENSIONS, FILTERS
│   └── compat.ts                                   # grain/compatibility matrix + forbidden combos (data, not if-chains)
├── order.types.ts                                  # TS types of the order JSON
├── order.validator.ts                              # pure, strict (unknown key → error)
├── period.ts                                       # relative presets → {from,to} in store tz (pure given `today`)
├── compiler.ts                                     # pure
├── executor.service.ts                             # tx, timeout, advisory locks, comparison
├── availability.service.ts                         # D-19 (cached)
├── size-order.ts                                   # numeric-first natural comparator (PEDIDO 40)
├── csv.ts                                          # toCsv with formula-injection guard
├── saved/                                          # model, service, dto (class-validator envelope only)
└── __tests__ or *.spec.ts beside files
api-ventago/migrations/2026-10-NN-a-reportaje-permiso.sql          # function + grants (seed BEFORE code)
api-ventago/migrations/2026-10-NN-b-reportaje-pedidos.sql          # new table (expand; empty table → w4-exempt)
```

### Pattern 1: Shared «venta» fragment (D-01/D-02) — `reports/venta-universe.ts`
**What:** Pure functions returning SQL CTE text with **named bind placeholders supplied by the caller** (`$1…`), composed from the existing constants. Three grains, each one row per its natural key so joins never fan out.
**Key shape (one row per sale):**
```sql
venta AS (
  SELECT s.id AS sale_id, s.status,
         CASE WHEN s.status = 'Anulación' THEN -1 ELSE 1 END AS sgn,   -- same sign rule as signedTxSql
         s.total_amount, s.seller_id, s.source,
         <saleBranchSql('s')> AS branch_id,                            -- original's branch wins for reversals
         COALESCE(s.sale_day_local,
                  (s.sale_date AT TIME ZONE $tz)::date) AS dia         -- 23 prod rows have NULL sale_day_local
    FROM sales s
   WHERE s.store_id = $store                                           -- tenant predicate FIRST, always
     AND s.activity_type = 'sale'                                      -- SOLO_VENTA_SQL
     AND s.status IN (<ACCOUNTING_SALE_STATUSES>)                      -- originals + reversals both count, own day, own sign
     AND s.credit_payment_id IS NULL                                   -- EXCLUDE_DEUDA_PAGO_SQL (dpago not a sale)
     AND s.sale_date >= ($from::date - 1) AND s.sale_date < ($to::date + 2)   -- coarse, index-friendly
     AND COALESCE(s.sale_day_local, (s.sale_date AT TIME ZONE $tz)::date) BETWEEN $from AND $to
)
```
- Use `s.sale_date` directly in the coarse range (not `COALESCE(sale_date, created_at)` as Ganancia does) so `idx_sales_store_date (store_id, sale_date)` is used. Prod has 0 NULL `sale_date` of 359,989 rows, but the column is nullable → add an itest/monitor invariant `count(*) WHERE sale_date IS NULL = 0`, otherwise such rows are silently dropped. [VERIFIED: prod query 2026-10-17]
- `sale_day_local` mismatches the BA-tz recomputation on 1 of 359,989 rows; NULL on 23. Keep the `COALESCE` fallback (copy of Ganancia). [VERIFIED: prod]
- **Reversal pairs** (`Anulado` original + `Anulación` negative): both are counted on their own day with their own sign; items and payments of the reversal are **negative** too (prod: 222/222 legacy and 33/33 POS `Anulación` rows have negative total and negative payment; 1,173 of 1,199 reversal items have negative subtotal). So `SUM(...)` over lines/payments nets automatically — no extra sign logic at line/payment grain. Tickets use `SUM(sgn)` (header grain) or signed `COUNT(DISTINCT)` (item grain, pattern in `salesDimensions.service.ts`). [VERIFIED: prod + sale-status.constants.ts]
- **Grain CTEs**
  - Header grain: `venta` (above) optionally LEFT JOIN `items_agg` = `SELECT sale_id, SUM(quantity) units, SUM(subtotal) items_total, SUM(quantity*unit_cost) FILTER (WHERE unit_cost IS NOT NULL) costo, SUM(subtotal) FILTER (WHERE unit_cost IS NOT NULL) venta_con_costo FROM sale_items WHERE sale_id IN (SELECT sale_id FROM venta) GROUP BY sale_id`. **Pre-aggregating per sale is mandatory** — `SUM(s.total_amount)` after joining items multiplies the ticket total by the number of lines.
  - Item grain: `venta JOIN sale_items si ON si.sale_id = venta.sale_id LEFT JOIN products p ON p.id = si.product_id LEFT JOIN products m ON m.id = p.parent_id` (+ lookups). Revenue = `si.subtotal`, units = `si.quantity`.
  - Payment grain: `venta JOIN sale_payment_methods spm ON spm.sale_id = venta.sale_id`. Revenue = `spm.amount`; units/tickets blocked (D-10).
- Do **not** reuse `SALE_ITEM_DIM_CTE` (leaf-only category/season, no store predicate inside, `(s.sale_date)::date` UTC day). Reuse the *constants*, not that CTE.

### Pattern 2: Grain selection = max resolution of (metrics ∪ dimensions ∪ filters)
| Grain | Triggered by | Revenue source | Allowed metrics |
|-------|--------------|----------------|-----------------|
| header | sucursal, tiempo, vendedor (or none) | `sales.total_amount` | venta_neta (with devoluciones where attributable), unidades (via `items_agg`), tickets, ticket_promedio, devoluciones (sucursal/tiempo only), margen |
| item | categoría, producto/madre, temporada, color, talle (as dim **or** filter) | `sale_items.subtotal` | venta (sin devoluciones), unidades, tickets («con el producto», signed distinct), margen, AUR |
| payment | medio de pago | `sale_payment_methods.amount` | venta (cobrado) only |
- **item × payment is forbidden** (generalises CODEX's producto×medio de pago; there is no safe join).
- **Measured reconciliation of header vs line grain** (accrual, 2026-07-17 → 10-17, dpago excluded): Σ`items.subtotal` vs Σ`total_amount` differs by +0.27 % (coolsistema), +0.01 % (NOIX), −0.03 % (Charo), +0.03 % (Shaple), 0.00 % elsewhere; 47 of 3,128 Shaple tickets have header ≠ items. Cause: ticket-level surcharge/discount/transport. Decision for planner: keep both sources, **declare the grain in the metric definition shown to the user**, and add an itest asserting |Σ item-grain − header total| ≤ 0.5 %. [VERIFIED: prod]
- **Tickets are non-additive at item grain** (a ticket with two categories counts in both rows). The totals row must be computed by a **separate query** (or window over distinct sale ids), never `SUM(rows)`.
- **Ticket promedio at item grain** («line revenue ÷ tickets containing it») is semantically odd. Recommendation (needs user OK, see Open Question 4): allow Ticket promedio only at header grain (sucursal/tiempo/vendedor); offer AUR (= venta ÷ unidades, D-21) at item grain.

### Pattern 3: Strict validator (not the global pipe)
`LoggingValidationPipe` is `whitelist:true, forbidNonWhitelisted:false` — it **silently strips unknown DTO properties** (`main.ts:122`, `common/validation/logging-validation.pipe.ts`). The order JSON must therefore arrive as an opaque `@IsObject() order: Record<string, unknown>` and be validated by a hand-written, catalog-driven function that **rejects** unknown keys, wrong types, unknown catalog ids, and combos. class-validator is used for the envelope only (`name`, `shared`, `position`).

### Pattern 4: Executor (read-only tx + timeout + advisory locks)
```ts
// Source: precedent api-ventago/src/app/sales/sales-modify.service.ts:718 (READ ONLY + statement_timeout),
//         clients.service.ts:771 (pg_advisory_xact_lock); PG docs explicit-locking (xact locks release at tx end)
const rows = await this.sequelize.transaction(async (t) => {
  await this.sequelize.query(
    `SET TRANSACTION READ ONLY; SET LOCAL statement_timeout = '${timeoutMs}ms'`, // timeoutMs is a server constant, not user input
    { transaction: t },
  );
  const [{ ok }] = await this.sequelize.query<{ ok: boolean }>(
    `SELECT pg_try_advisory_xact_lock(117, $1::int) AS ok`, { bind: [storeId], type: QueryTypes.SELECT, transaction: t });
  if (!ok) throw new HttpException({ code: 'STORE_BUSY' }, 429);
  // …same for (118, userId); global: loop i in 0..N-1 over pg_try_advisory_xact_lock(119, i) until one succeeds
  return this.sequelize.query(sql, { bind, type: QueryTypes.SELECT, transaction: t });
});
```
- Failure mapping: PG error `57014` (query_canceled) → 408/«La consulta superó 5 s» with **no automatic retry**; log via existing slow-query pipeline (Sequelize `benchmark:true` + `pushSlowQuery` in `database.module.ts` already logs every query ≥ the existing threshold — no new logger needed, but add the compiled order id/hash to the service log line).
- One pooled connection per run (pool max 20/worker, pgbouncer 50): the lock + query share the same tx, so a run never holds 2 connections. A rejected try-lock costs one short tx. **Do not add a queue** that holds connections; return 429 with `retryAfterMs` and let the client retry (CODEX allows ≤2 waiting — implement as client-side retry, not server-side waiting).
- Global limit N: the product limit is 4–6 *across* PM2 workers (`ecosystem.config.js`: 4 workers, `exec_mode: cluster`) and across both blue/green containers during deploy. Advisory locks are global to the DB, so N=4 (env `REPORTAJE_GLOBAL_MAX`, default 4) works regardless of worker count.
- Lock key namespace: two-int form `(classId, objId)`; `classId` constants 117/118/119 avoid collisions with the repo's `hashtext(...)` single-key locks. `[ASSUMED]` that no existing code uses the two-int form with those class ids — grep found only `hashtext(...)`/`$1::int, hashtext($2)` forms (`clients.service.ts:773` uses the two-arg form with a caller-supplied int, so choose class ids and **grep again at implementation**).
- Redis: **not used.** (If a later wave wants Redis, `conectarEnSegundoPlano` + `cerrarRedis` are mandatory and `redis-no-bloquea-arranque.spec.ts` forbids `await …connect()` and `.quit()`.)

### Pattern 5: Catalog as data with a report-type axis (D-18)
```ts
export const CATALOG_VERSION = 1; // bump when ANY definition changes → saved orders show «definición cambió» (D-16)
export const REPORT_TYPES = {
  ventas: { grainSources: {header, item, payment}, metrics: [...], dimensions: [...], filters: [...] },
  // gastos / facturacion: added later as new keys with their OWN fact fragment; the order JSON has `type`
};
```
- Per-entry fields: `id`, `labelEs`, `definitionEs` (shown to the user), `grain`, `sqlExpr` (constant string), `requires` (`marginAllowed`), `blockedWith` (e.g., `ticket_promedio` blocked with `medio_pago`, with `reasonEs`), `cardinality` (`high|low`), `availabilityProbe`.
- Order JSON stores **ids only** (never SQL, never store_id, never permission results): `{ v:1, type:'ventas', metrics:['venta_neta','unidades'], groupBy:['sucursal','tiempo:mes'], period:{preset:'este_mes'}|{from,to}, compare:'periodo_anterior'|'anio_anterior'|null, filters:{sucursales:[ids]}, sort:{metric,dir}, top:20 }`. `catalog_version` is a column on the saved row, not part of the run request.

### Anti-Patterns to Avoid
- **Aggregating `total_amount` after joining items or payments** (fan-out). Pre-aggregate per sale or use the correct grain.
- **`SUM(ticket_promedio)`/averaging averages**: always `SUM(num)/NULLIF(SUM(den),0)` last.
- **Using `products.stock`/`stock_balances.total_venta` for sales** (POS writes `stocks.type NULL`; `total_venta` only counts web orders) — not used here at all.
- **Taking `store_id` from the request** or letting a saved order carry it.
- **Falling back to all branches when a branch filter can't be resolved** (`narrowing-filter-must-never-widen`).
- **Reading category/season from the leaf only** (Shaple shows 100 % «Sin categoría»).
- **Interpolating anything user-derived into SQL text** — identifiers/expressions come only from catalog constants; every value is a `bind` parameter.
- **Using `sale_date::date`** (UTC) for days — `devolucionesFilasSql` does exactly this (`(dv.sale_date)::date AS d`); do not reuse its day column.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Which sales count | New status list | `ACCOUNTING_SALE_STATUSES`, `SOLO_VENTA_SQL`, `EXCLUDE_DEUDA_PAGO_SQL`, `saleBranchSql` | A typo (`'Paid'`) once made a report count 0 in prod; one definition per concept |
| Branch of a sale | `users.branch_id` join | `saleBranchSql('s')` | 9.4 % of sales differ; reversals must follow the original |
| Store tz validation | 7th copy of `resolveStoreTz` | Extract one helper into the new module (6 copies exist in `reports/*`); test `SELECT now() AT TIME ZONE :tz` guard | Invalid IANA name raises at runtime |
| Cross-worker mutual exclusion | Redis lock / in-memory Map | `pg_try_advisory_xact_lock` | Works across 4 workers + 2 containers, auto-release on crash |
| Cache for availability | ad-hoc Map | `MemoryCacheService.getOrLoad` (60 s) | Single-flight + cross-worker invalidation exists |
| Margin gating | `if role==='admin'` | `FunctionPermissionService.isAllowedStrict` | Same pattern as `sales-cockpit` (ganancia fields removed server-side) |
| Return amount | New refund formula | Extract the `monto` expression from `devolucionesFilasSql` (credit_ledger `payment_in/favor_in` + `box_operations` `Devolución #id —%`) and make the day local | D1 says it must equal Ganancia's `reintegros` |
| Size ordering | SQL `ORDER BY name` | Shared `size-order.ts` comparator (numeric-first, then letter ladder XXS..XXXL, then name) applied in app on ≤50 rows | Prod size names mix `0`,`2XL`,`32..60`,`AZUL`,`Talle Única`, `1.2MM…55MM`, `N1..N12` (store 26 has 48 names; store 22 has `TALLE 1`, `CHICO`) |
| CSV | `join(',')` | Small `toCsv` with RFC-4180 quoting + formula-injection guard + UTF-8 BOM | Legacy product names can start with `=`/`+`/`-`/`@`; no generic CSV writer exists in the repo (only `delivery-payout-csv.service.ts`, which parses) |

**Key insight:** The risk in this phase is semantic (what a number means), not mechanical. Every existing report already disagrees with another somewhere (Phase 105 E1–E13); the only defence is one fragment + definitions shown on screen + tests that assert totals tie.

## Legacy imported sales vs POS (D-17) — measured, READ-ONLY on prod PG18 (2026-10-17)

**How legacy writes sales** `[VERIFIED: api-ventago/src/app/legacy-import/streaming/ace-sales.sql.ts]`: `INSERT INTO sales (…, source, activity_type, num_pedido, …) … 'legacy', 'sale', r.vcode` — origin marker is **`sales.source = 'legacy'`** (POS default `'pos'`, web orders `'online'`), `num_pedido` = ACE `vcode`, plus `legacy_entity_maps(store_id, entity='sale', legacy_id=vcode)` with unique index `uq_legacy_entity_maps_store_entity_legacy` (re-import cannot duplicate). Cancel flags map to `Anulado` / negative → `Anulación`; `sale_day_local` and `sale_date` are set from the store tz; items get `product_id` NULL + `custom_name` when the sku isn't found; **`sale_items.unit_cost` is NULL for 100 % of legacy items**.

**Prod facts** (sales rows: legacy 358,753 · pos 1,209 · online 10; `devuelto` 1, `fallado` 9, `movido` 7):

| Store | Legacy last sale (BA time) | First POS sale after it | Meaning |
|-------|----------------------------|--------------------------|---------|
| 30 Cache | 2026-10-14 11:22 | 2026-10-14 11:49 | clean cutover same day |
| 26 Shaple | 2026-10-12 10:10 | 2026-10-12 10:17 | clean cutover same day |
| 25 Charo | 2026-10-13 12:37 | 2026-10-13 13:35 | clean cutover |
| 6 coolsistema | 2026-10-15 11:44 | 2026-10-15 12:04 | test/dev store, both coexist (legacy rows include 89 sales from a foreign file, see migration `2026-10-17-ocultar-import-ace2-store6.sql`) |
| 19 NOIX | 2026-10-03 11:41 | 2026-10-05 09:38 | **parallel period** (legacy 40/day vs POS 3/day on 10-01..03) |
| 28 ohmydenim | 2026-10-07 | none | dormant |

- **Why Cache "has both on the same day":** only the cutover day (10-14: 23 legacy before 11:22, 56 POS from 11:49). The 399 POS vs 4,657 legacy rows in "last 30 days" is a window effect, not double entry.
- **Duplicate search** (same store, same total, |Δt| ≤ 24 h, since 2026-08-01, valid statuses): 29 candidate pairs, of which **exactly 1 has an identical item multiset** (NOIX legacy 140311 ↔ POS 242, total 38,500, 54 s apart, same 4 product×qty pairs). All Cache/Shaple candidates have different items → coincidences on round totals. Duplicate `(store_id, num_pedido)` within legacy: **0**.
- Coverage differences the compiler must tolerate (90 d window): legacy sales without payment rows: Shaple 6.0 %, Charo 1.1 %, ohmydenim 1.6 %; `seller_id` NULL: coolsistema-legacy 56 %, NOIX 9.8 %, Charo 4.9 %, ohmydenim 4.7 %, Cache 1.5 %; legacy items with `product_id` NULL: NOIX 10 %, Cache 6 %, ohmydenim 7 %, Shaple 1.6 %.

**Recommended rule (R1):** the universe is the **union of all `source` values** with **no dedupe predicate in the hot query**. Rationale: dedupe signature joins (store+total+time window+item multiset) cost a self-join per run for 1 true duplicate in ~360k rows (≈ 0.0003 %). Add: (a) an itest/monitor query that counts signature-duplicates per store and fails if > a small constant (current baseline 1, store 19); (b) `meta.fuentes` (counts per source) in the response so the screen can say «incluye N ventas importadas»; (c) do **not** mutate the NOIX pair (test-artifact rule); document it as a known 38,500-ARS overcount. If the user later wants it fixed, the safe lever is an exclusion by explicit `sale_id` list in data, not heuristics in SQL.
**Alternative rejected:** per-store cutover timestamp (`source='legacy' AND sale_date <= cutoff`) — needs a per-store config that nobody maintains and breaks NOIX/coolsistema, where both sources legitimately carry different sales.

## Dimensions mapping (D-09, D-19, D-22)

| Dimension | Grain | Key / expression (all joins keyed by store-scoped ids) | Empty-value row | D-19 availability probe (per store) |
|-----------|-------|-----------------------------------------------|-----------------|--------------------------------------|
| Sucursal | header | `saleBranchSql('s')` → `branches(id,name)`; validate filter ids `branches.store_id = :store` | — | always available if store has ≥2 branches (template «comparación de sucursales» only multi-branch: 4 stores) |
| Tiempo | header | `venta.dia`; week `date_trunc('week', dia)` (ISO Monday), month `date_trunc('month', dia)`; fill gaps with `generate_series` for day grain (≤90 rows) | — | always |
| Vendedor | header | `s.seller_id` → `"Sellers"(id, name, last_name)` (**not** `user_id`) | «Sin vendedor» (NULL seller) | always |
| Categoría | item | `COALESCE(p.category_id, m.category_id)` (leaf, then madre) → `categories.name` | NULL **or sentinel name** → «Sin categoría» | distinct non-sentinel values ≥ 2 |
| Temporada | item | `COALESCE(p.season_id, m.season_id)` → `seasons.name` | NULL/sentinel → «Sin temporada» | distinct non-sentinel ≥ 2 |
| Color | item | `p.color_id` (leaf) → `colors.name` | NULL → «Sin color» | distinct ≥ 2 |
| Talle | item | `p.size_id` (leaf) → `sizes.name`; **sort in app with `size-order.ts`** | NULL → «Sin talle» | distinct ≥ 2 |
| Producto/madre | item | `COALESCE(p.parent_id, p.id)` → madre `products(sku,name)`; Top N mandatory | `product_id` NULL → single row «Sin producto (ítem libre)» | always |
| Medio de pago | payment | `spm.payment_method_id` → `payment_methods(title, slug)`; display-normalize slug variants (`tarjeta-credito`/`tarjeta-de-credito`/`tarjeta_de_credito`) | sale with no `sale_payment_methods` → «Sin medio de pago» (LEFT JOIN from `venta`) | always |

**Prod measurements that drive this** (items of valid sales since 2026-07-17):
- Variant stores keep category/season on the **madre**: Shaple (26) category null on the leaf for 100 % of items but null on both for 1 %; ohmydenim 70 % → 7 %. Color/size are on the leaf. [VERIFIED: prod]
- **Sentinels:** `categories`/`seasons` contain rows literally named `NONE` and `General` (store 26: categories {NONE, General}; Cache seasons include NONE, General) meaning «no value». Availability and display must treat them as empty. Sentinel set `{NONE, GENERAL}` (case-insensitive) is `[ASSUMED]` — a store could legitimately name a category «General»; confirm (Open Question 3).
- Resulting availability today (distinct values among active products): Shaple categories 1 / seasons 1 / sizes 47 / colors 1 → category, season, color disabled, talle enabled; Cache seasons 6 (minus sentinels) / categories 2 / color 1 / size 1; NOIX categories 12 / color 1 / size 1; Cielo (22) colors 26 / sizes 29.
- **Cost of probe:** the catalog probe `SELECT count(DISTINCT coalesce(p.category_id,m.category_id)) …, count(DISTINCT p.size_id) … FROM products p LEFT JOIN products m ON m.id=p.parent_id WHERE p.store_id=:s AND p.status<>'deactivated'` took **8.4 ms** on Shaple (7,403 products; largest is Charo with 20,755). Run it as one query per store and cache 60 s with `MemoryCacheService`. Probe the **catalog**, not sales (cheaper and stable); `[ASSUMED]` acceptable that a value with zero sales still counts as available.

## Metrics definitions (D-08, D-21)

| Metric | Header grain | Item grain | Payment grain | Notes |
|--------|--------------|------------|---------------|-------|
| `venta_neta` | `SUM(v.total_amount) − devoluciones(branch/day attributable)` | `SUM(si.subtotal)`; **devoluciones not attributable → label «venta (sin devoluciones)»** | `SUM(spm.amount)` | Accrual (devengado), dpago excluded. **Differs from Ventas›Totales**, which is cash-basis (`creditCashAdjustmentSql`, Phase 91 ⑥) — see Open Question 1 |
| `unidades` | `SUM(items_agg.units)` | `SUM(si.quantity)` | blocked | negative quantities on reversals net out |
| `tickets` | `SUM(v.sgn)` | signed `COUNT(DISTINCT sale_id)` («con el producto», non-additive) | blocked (D-10) | |
| `ticket_promedio` | `SUM(venta)/NULLIF(SUM(tickets),0)` at the **final** step | blocked (recommended) | blocked (D-10) | |
| `aur` (precio promedio) | `SUM(venta)/NULLIF(SUM(unidades),0)` | same | blocked | Always shown with comparison (D-21) |
| `devoluciones` | sucursal/tiempo only: amounts from `credit_ledger`/`box_operations` of `activity_type='devuelto'` rows, **local day**, origin branch | units only (`sale_items.quantity` on `devuelto` rows; their `subtotal` is 0) | blocked | The return row has `total_amount=0` and no seller (prod: 1 row ever, store 6). Blocked with seller dim («la devolución no tiene vendedor»). `bo.description LIKE 'Devolución #'||id||' —%'` is not index-supported → fine at today's volume, EXPLAIN again if it grows |
| `margen` (admin) | `SUM(venta_con_costo) − SUM(qty*unit_cost)` over lines **with cost** + `cobertura = venta_con_costo / items_total` | same, per line | blocked | Line-level (D2). Margin before returns (label it); returns cost handling is Open Question 5 |

Prod cost coverage (`unit_cost IS NOT NULL` share of recent items): Cielo 39.8 %, coolsistema 2.5 %, Cache 2.3 %, **0 % for every legacy source and Shaple/NOIX/Charo/ohmydenim**. So margin is meaningful for ~1 store; the mandatory «% de venta con costo cargado» column is not optional decoration.

**Comparison (D-21):** run the second period with the same fragment in the same transaction; merge by group key in app (time: align by index offset). Compare ≤ 90 days for «año anterior». Shown columns always include `unidades`, `tickets`, `aur`.
**Share (%)** = row ÷ **grand total computed before `LIMIT`** (`SUM(SUM(x)) OVER ()` as `salesDimensions.service.ts` already does for E4). For non-additive metrics the grand total comes from a separate aggregate query.

## Compiler / validator design (§5)

- **Validation order:** envelope (class-validator) → structural (types, unknown keys) → catalog ids → permission fields (margin) → availability (D-19) → period resolution (store tz) → limits (≤2 dims, ≤1 high-cardinality, day ≤90 d, week/month ≤12 mo, Top ≤100, product requires Top, product×día needs Top and ≤31 d, compare-año-anterior ≤90 d) → forbidden combos (compat matrix) → branch ownership → estimated rows (e.g. `days × branches`, or catalog cardinality) → compile.
- **Errors are data:** `{ code, messageEs, fixes:[{label:'Reducir el período a 31 días', patch:{…}}] }` so the future UI can show one-click repairs (CODEX §4) without server rewrites.
- **Binding:** Sequelize `replacements` are **escaped and inlined client-side**; `bind` sends values separately [CITED: sequelize.org/docs/v6/core-concepts/raw-queries]. A query can use one or the other, and `bind` cannot replace identifiers. Use `bind` (`$1…`, with explicit casts like `$1::int`, `$2::date`, `$3::int[]`) for every user-derived value. Existing repo code uses `replacements`; this phase deliberately uses `bind` — the compiler must number parameters itself and return `{ sql, bind }`.
- **Allowed expressions:** only strings from `catalog.ts` constants; the compiler never receives free text. Sort column must be one of the selected metric/dimension ids; the physical `ORDER BY` uses the alias, plus a deterministic tie-break (group key) so pagination/CSV are stable.
- **Row cap:** `LIMIT cap+1` (cap 1,000 screen / 10,000 CSV) → `meta.truncated`.
- **Concurrency/timeouts:** values in Discretion (5 s / 20 s, store 1, user 1, global 4). Timeouts are enforced by PG (`SET LOCAL statement_timeout`), not by `Promise.race` (which leaves the query running and the connection busy).
- **Slow-query logging:** already global (`database.module.ts` `benchmark:true` → `pushSlowQuery`, slow_query_log table). Add a structured log line `{storeId, userId, orderHash, grain, ms, rows}` per run (never log the bind values containing PII — none expected).
- **Tenant predicate invariant:** every compiled statement must contain `s.store_id = $N` bound to the session store inside the first CTE; and every joined lookup (`products`, `categories`, `"Sellers"`, `payment_methods`, `branches`) is reached by id from already-store-filtered facts. Add a compiler unit test that parses the SQL for the predicate (see Validation).

## Saved orders table (D-12..D-16)

```sql
-- migrations/2026-10-NN-b-reportaje-pedidos.sql   (new table → no traffic; header: -- w4-exempt: tabla nueva en este archivo)
BEGIN;
SET LOCAL lock_timeout = '5s';
CREATE TABLE IF NOT EXISTS reportaje_pedidos (
  id              BIGSERIAL PRIMARY KEY,
  store_id        INTEGER NOT NULL,
  owner_user_id   INTEGER NOT NULL,
  name            VARCHAR(120) NOT NULL,
  shared          BOOLEAN NOT NULL DEFAULT false,
  position        INTEGER NOT NULL DEFAULT 0,
  report_type     VARCHAR(20) NOT NULL DEFAULT 'ventas',
  order_json      JSONB NOT NULL,           -- ids only; NO store_id, NO permission results (D-16)
  catalog_version INTEGER NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_reportaje_pedidos_store_owner ON reportaje_pedidos (store_id, owner_user_id, position);
CREATE INDEX IF NOT EXISTS ix_reportaje_pedidos_store_shared ON reportaje_pedidos (store_id, position) WHERE shared;
CREATE UNIQUE INDEX IF NOT EXISTS uq_reportaje_pedidos_owner_name ON reportaje_pedidos (store_id, owner_user_id, lower(name));
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'coolsistema') THEN
    ALTER TABLE reportaje_pedidos OWNER TO coolsistema;
    ALTER SEQUENCE reportaje_pedidos_id_seq OWNER TO coolsistema;   -- sequence owner is NOT moved by ALTER TABLE
  END IF;
END $$;
COMMIT;
```
(Template mirrors `2026-10-15-client-errors.sql`.) `ON DELETE`: no FK (like `client_errors`) or FK to `users` with `ON DELETE CASCADE` — decide in plan; a dangling owner on a `shared` order must not break listing (LEFT JOIN users). `[ASSUMED]` no-FK is acceptable because `store purge/eliminar-tienda` is table-driven (below).
- **Mandatory registrations for any new `store_id` table** (specs will fail the build otherwise): `store-backup-coverage.ts` (`SIMPLE_STORE_TABLES`, or `EXCLUDED_TABLES` with a reason), regenerate `store-backup-inventory.txt` via `scripts/regen-store-backup-inventory.sh`, `vaciado/vaciado-catalogo.ts` and `vaciado/eliminar-catalogo.ts` (`porTienda(...)`) — verified by `store-backup-coverage.spec.ts`, `vaciado-catalogo.spec.ts`, `eliminar-catalogo.spec.ts`. Recommend **SIMPLE_STORE_TABLES** (user work product, small). Also regenerate `.planning/intel/db-schema-*.md` via `./.planning/intel/db-schema.regen.sh`.
- **Relative periods (D-14):** store `period:{preset:'este_mes'|'ultimos_30_dias'|…}`; `period.ts` resolves with `today = (now() AT TIME ZONE tz)::date` obtained in the same tx (not JS `new Date()`), then limits apply to the resolved range. Absolute periods saved as `{from,to}`.
- **Re-validation on open (D-12):** run = load row (`WHERE id=:id AND store_id=:store AND (owner_user_id=:uid OR shared)`) → strip margin metrics if `!marginAllowed` (response `omitted:[{metric,reasonEs}]`) → validate → compile. Never 404/403-leak other stores' ids (always the same «not found» for wrong store).
- **Version warning (D-16):** response carries `catalogChanged: row.catalog_version < CATALOG_VERSION`.
- **Where to surface saved orders (D-13 decision, for the UI round):** put them in the **left menu of the Reportes unified view** (`ventago-app/src/views/reports-v2/ReportsSidebar.tsx`, driven by `registry.ts` with `permissionSlug`), not the global sidebar: the global sidebar comes from `modules`/`structure` rows (static, per role) and Reportes is a `directPath` app with no children (`navigation/vertical/index.ts:407`), so dynamic per-user items cannot live there without structural changes. API needs only `GET /reportaje/pedidos` (own + shared, ordered by `position`).

## Permission + menu seed (D-05, D-07)

- **Pattern to copy:** `api-ventago/migrations/2026-09-29-c-permiso-reporte-precios-fuera-de-lista.sql` (function under module `dashboard-reportes`, grants to roles, `role_function_actions` `read`), plus header comments `-- perm-cache: …` and `-- w4-exempt: sin DDL — INSERTs sobre tablas de permisos.` and `SET lock_timeout='5s'`. [VERIFIED: file read] All 24 `reporte-*` functions sit in module `dashboard-reportes` [VERIFIED: prod], so **no new `modules` row / `structure` change is needed**: Reportes entries are registry-driven (`registry.ts` `permissionSlug`). The seed still must precede the code (`FunctionGuard` rejects unknown slugs; Phase 93 P1-e).
- **Default grant: `admin` only** (`r.slug = 'admin' AND r.store_id IS NOT NULL`), as `2026-10-08-d-menu-token-soporte.sql`. The precios template grants `admin/store_admin/store_owner/gerente`; `store_admin/store_owner` were removed in Phase 93 step 4 — do not copy that role list.
- **New stores:** `storeTemplate.service.ts` creates roles per store; check how `reporte-*` functions reach a new store's `admin` (likely template-copy of `role_functions`; memory note «new-store template seeds read-only») — verify in plan; otherwise new stores get the menu only after a backfill.
- **Slug:** `reportaje-abierto` (name «Reportaje abierto»), action `read` (run/export/save own) — `[ASSUMED]` single action; sharing needs no extra permission (D-12: anyone with the menu runs shared orders).
- **perm-cache rule:** grant-only seed → `-- perm-cache: sólo otorga una función nueva (no revoca); el deploy recrea el contenedor.`
- **Margin gating (D-07) — DB finding:** `reporte-ganancia` is granted (with `read`) to `accountant` (10 stores), `cashier` (10), `gerente` (9), `inventory_clerk` (10), `viewer` (10) and `admin` (28); `ver-costo-producto` to cashier (8), gerente (27), viewer (10), etc. [VERIFIED: prod role_functions]. Reusing either slug therefore exposes margin to non-admin roles in some stores. Recommendation: **margin metric requires `isAllowedStrict(reporte-ganancia,read)` AND `isAllowedStrict(ver-costo-producto,read)`** (both are existing, store-managed knobs, consistent with `sales-cockpit`), and state in the plan that «sólo admin» holds only by default — OR add a third, new function `reportaje-margen` seeded admin-only (clean D-07, one extra knob). Needs user decision (Open Question 6). Either way enforce **server-side field gating** (strip + `omitted` reason), never UI-only.
- **Agent scope manifests:** new GET endpoints are enumerated by `auth/guards/agent-scope-enumeration.ts` against `agent-scope-manifest.*.ts` / `agent-scope-exclusions.ts`; a new controller with read-style endpoints (and `POST` run/export that *reads*) may need an explicit classification or an `EXCLUIDOS_VER` / `POSTS_QUE_LEEN` entry, otherwise `agent-readonly-scopes*.spec.ts` fails. Check by running those specs after adding the controller. (agent@app must not reach saved orders or CSV.)

## CSV export (§8)

No reusable generic CSV writer exists (`grep` hits are the delivery-payout CSV *parser* and MinIO). `ExcelService` (exceljs) handles xlsx for other reports. Recommend a small pure `csv.ts`: UTF-8 BOM, `;` delimiter, decimal comma, CRLF, quote-doubling, **neutralise leading `= + - @ \t \r`** by prefixing `'` (Excel formula injection from legacy product names), numbers emitted unformatted (not `$ 1.234,56` strings) so Excel can sum them. `[ASSUMED]` es-AR Excel expects `;` + decimal comma — confirm with a real file from Shaple (daily exporter). Limits: 10,000 rows (`LIMIT 10001` → 422 «agregá un filtro o Top N»), timeout 20 s, same executor, same locks (a CSV counts as the user's single run).

## Common Pitfalls

### Pitfall 1: Category/season «NONE» and leaf-vs-madre
**What goes wrong:** the report shows 100 % «Sin categoría» for a variant store, or a one-value dimension as if useful. **Why:** attributes on the madre; sentinel rows named `NONE`/`General`. **Avoid:** `COALESCE(leaf, madre)` + sentinel→NULL mapping + D-19 probe. **Warning:** itest: Shaple-like dummy store (madre has category, leaf null) must group under the madre's category.

### Pitfall 2: Fan-out
**What goes wrong:** `total_amount` multiplied by item count or payment count. **Avoid:** grain-specific CTEs; pre-aggregate items per sale; payment grain uses `spm.amount`. **Warning:** itest asserts Σ(payment grain) = Σ(header grain) (prod: 0 mismatches in 90 d except 4 of 7 *online* orders in store 6, avg 84,000 — online orders lack matching payment rows).

### Pitfall 3: UTC day vs local day
`devolucionesFilasSql` uses `(dv.sale_date)::date`; `salesDimensions` uses `(s.sale_date)::date`. A sale at 22:30 BA time lands on tomorrow's UTC date. **Avoid:** `sale_day_local` with tz fallback; relative periods from `(now() AT TIME ZONE tz)::date`.

### Pitfall 4: Dropped rows from NULLs
`sale_date` NULL rows vanish from the coarse range; `sale_day_local` NULL (23 rows) needs the fallback; `seller_id`/`branch_id` NULL need «Sin X» rows, not inner joins. **Avoid:** LEFT JOINs everywhere + invariants in itest.

### Pitfall 5: Lenient global pipe
Unknown keys in the order are silently dropped by `LoggingValidationPipe` → a typo'd filter widens the report. **Avoid:** opaque object + strict hand validator; unknown key = 400.

### Pitfall 6: Totals row and share% on non-additive metrics
Tickets by category and ticket promedio can't be summed. **Avoid:** separate aggregate query for the total; share% only for additive metrics (venta, unidades).

### Pitfall 7: Mixed accrual/cash basis
Ventas›Totales is cash-basis (credit sales out, collections in, returns subtracted); Ganancia is accrual; item-grain reports can't carry the cash adjustment (collections have no product). Reportaje must pick one and **say so in the metric definition**; otherwise users compare it with Totales and find a gap equal to credit movements.

### Pitfall 8: Advisory-lock and tx hygiene
Locks must be taken **inside** the same transaction as the query (xact-level), never session-level (pgbouncer would leak them). Don't `await` anything slow (HTTP, filesystem) inside the tx (CLAUDE.md «no external I/O in tx»). CSV serialisation happens **after** commit.

### Pitfall 9: Backup/vaciado registration forgotten
New `store_id` table without `store-backup-coverage` / `eliminar-catalogo` entries breaks three specs (and would silently be left behind on store deletion).

### Pitfall 10: Local DB ≠ prod
Local `ventago` (5432) is a restored backup (1,047,064 legacy sales vs 358,753 in prod) — itest counts and timings are not prod's. Use prod only for read-only measurement; assert invariants (ties, predicates), not absolute numbers.

## Code Examples

### Local-day relative period (pure, testable)
```ts
// period.ts — `today` comes from the DB in the store tz, passed in; tz validated like Ganancia's resolveStoreTz
export function resolvePeriod(p: RelativePreset | {from:string;to:string}, today: string): {from:string;to:string} { /* este_mes → [first of month, today] … */ }
```
### Sequelize bind with explicit casts (compiler output shape)
```ts
// Source: sequelize.org/docs/v6/core-concepts/raw-queries (bind: $1.., cannot replace identifiers)
await sequelize.query(sql, { bind: [storeId, tz, from, to, branchIds], type: QueryTypes.SELECT, transaction: t });
// sql contains: s.store_id = $1::int … AT TIME ZONE $2::text … BETWEEN $3::date AND $4::date … AND branch = ANY($5::int[])
```
### Prototype that was EXPLAINed on prod (Shaple, 91 d, madre grouping) — 45 ms
```sql
WITH v AS (SELECT s.id, s.sale_day_local d, s.total_amount, s.status FROM sales s
            WHERE s.store_id=26 AND s.activity_type='sale'
              AND s.status IN ('Facturado','Pagado','Pendiente por pagar','Anulado','Anulación')
              AND s.credit_payment_id IS NULL
              AND s.sale_date >= (date '2026-10-17' - 91) AND s.sale_date < (date '2026-10-17' + 2)
              AND s.sale_day_local BETWEEN date '2026-07-19' AND date '2026-10-17')
SELECT coalesce(mp.parent_id, mp.id) madre, sum(i.quantity) u, sum(i.subtotal) venta, count(distinct v.id) tk
  FROM v JOIN sale_items i ON i.sale_id=v.id LEFT JOIN products mp ON mp.id=i.product_id
 GROUP BY 1 ORDER BY venta DESC LIMIT 100;     -- parallel bitmap scan on idx_sales_store_date; 3,128 sales, 33,953 items
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| 6 copy-pasted status lists | `sale-status.constants.ts` single source | Phase 105/91 | Reuse; extend with `venta-universe.ts` |
| Ticket-level all-or-nothing cost | Line-level `unit_cost` | Phase 105 D2 | Margin = lines with cost; coverage % mandatory |
| `users.branch_id` for sale branch | `saleBranchSql` (original's branch for reversals) | 2026-09-18 | Use it |
| Replacements everywhere | `bind` for the compiler | this phase | True parameter binding for user-derived values |

**Deprecated/outdated (do not reuse):** `SALE_ITEM_DIM_CTE` category/season (leaf only); `stocks`-based sales counts; `products.stock`; the comment in `isAllowedStrict` that says unknown slug «passes» (memory: it now rejects).

## Runtime State Inventory

Not applicable — greenfield module (no rename/refactor/migration of existing strings). Existing data is only read.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Sentinel names `{NONE, GENERAL}` (case-insensitive) mean «no value» for categories/seasons | Dimensions | A store with a real «General» category is shown as empty/disabled |
| A2 | Accrual (devengado) is the right basis for Reportaje; item-grain cannot carry cash-basis credit adjustments | Metrics | Numbers differ from Ventas›Totales; user may expect equality |
| A3 | Union of sources with no dedupe is acceptable (1 known duplicate, 38,500 ARS, NOIX) | Legacy | Slight overcount for NOIX; needs explicit user OK per «propose, don't declare» |
| A4 | Ticket promedio blocked at item grain (only header grain) | Metrics | Deviates from D-08 wording; user may want it |
| A5 | Single action `read` on slug `reportaje-abierto`; sharing needs no extra permission | Permission | Finer control wanted later |
| A6 | CSV uses `;` + decimal comma + BOM for es-AR Excel | CSV | Opens as one column in some locales |
| A7 | No-FK (or FK-cascade) on `owner_user_id` and registration in `SIMPLE_STORE_TABLES` | Saved orders | Backup/restore semantics differ |
| A8 | Advisory-lock class ids 117/118/119 are unused in repo | Executor | Cross-feature lock contention (grep at implementation) |
| A9 | D-19 probe over active products (not sales) is an acceptable «available» definition | Dimensions | A dimension with values but no sales looks available but renders one row |
| A10 | New stores receive the permission via template copy (not verified) | Permission | New stores lack the menu until backfilled |
| A11 | Margin before returns is acceptable (label it) | Metrics | Ganancia-style margin (with `costoDevuelto`) differs slightly |
| A12 | Global limit 4 via advisory locks across workers is sufficient (CODEX says 4–6) | Executor | Under-utilisation or queue pressure; tune by env |

## Open Questions

1. **Accrual vs cash-basis «venta neta»** — Totales (cash) vs Ganancia (accrual). Recommendation: accrual + definition text + itest that quantifies the gap; user to confirm.
2. **D-06 branch scope** — existing report controllers apply **no** per-user branch restriction (only `storeId` scoping; `grep branch-scope` in `app/reports` = 0 hits), while Tesorería uses `resolveAllowedBranchIds`. Literal D-06 = store-wide for anyone holding the permission. Recommendation: route through one function `resolveReportBranchScope()` implemented store-wide now (plus branch-ownership validation), so tightening later is one line; ask whether a gerente assigned to one branch should be narrowed.
3. **Sentinel names** — confirm `NONE`/`General` = empty (A1).
4. **Ticket promedio at item grain** — block (recommended) or allow with «tickets con el producto» wording?
5. **Margin and returns** — include `costoDevuelto`/reintegros like Ganancia or margin-before-returns?
6. **Margin gate** — intersection of `reporte-ganancia`+`ver-costo-producto` (existing knobs) vs new admin-only `reportaje-margen`; D-07 literal «sólo admin» needs the second.
7. **NOIX duplicate 140311/242** — leave (recommended) or exclude by explicit id list?
8. **Per-run limits for CSV vs screen** — CSV counts toward the user's single concurrent run (assumed).

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Prod PG18 (read-only via `ssh jhkim-server`) | Measurements (done) | ✓ — **only with sandbox disabled** (`Network is unreachable` otherwise) | 18 (Index Searches in plans) | local restored DB (different data) |
| Local PG18 `ventago` :5432 | itests (`npm run test:itest`), migration apply | ✓ (reachable from sandbox; 1,047,064 legacy sales) | 18 | — |
| Redis | Not needed (design avoids it) | n/a | — | — |
| pgbouncer pool_mode | `SET LOCAL` / advisory xact locks safe in both modes | `/etc/pgbouncer/pgbouncer.ini` unreadable (permission denied) | — | Precedent `sales-modify.service.ts:718` already runs `SET TRANSACTION READ ONLY; SET LOCAL …` through the app path in prod |
| Mac-side migration apply | Local DB DDL | user runs `psql -p 5432 -d ventago -f …` (sandbox cannot reach Mac DB per CLAUDE.md; here local psql did respond — still follow the documented procedure) | — | — |

**Missing dependencies with no fallback:** none. **Note for planner:** production DDL/seed application needs user approval and is time-gated (08–16 h rule, ≤10 active users exception); all prod work in this research was `SELECT` inside `BEGIN READ ONLY … ROLLBACK`, nothing written.

## Validation Architecture

(`workflow.nyquist_validation` absent in `.planning/config.json` → enabled.)

### Test Framework
| Property | Value |
|----------|-------|
| Framework | jest 29.7 + ts-jest; unit `*.spec.ts` (rootDir `src`); integration `*.itest.ts` via `test/itest/jest-itest.json --runInBand` against local PG18 using `test/itest/harness.ts` |
| Config file | `api-ventago/package.json` `jest` block; `api-ventago/test/itest/jest-itest.json` |
| Quick run command | `cd api-ventago && npx jest src/app/reportaje src/app/reports/venta-universe --maxWorkers=1` (never full jest without `--maxWorkers=1`; do not set `NODE_OPTIONS` — see repo jest memory notes) |
| Full suite command | `cd api-ventago && npx jest --maxWorkers=1` (+ `npm run test:itest -- reportaje`) |

### Phase Requirements → Test Map
| Req | Behavior | Test Type | Automated Command | File Exists? |
|-----|----------|-----------|-------------------|-------------|
| D-01/02 | Fragment contains store predicate, `activity_type='sale'`, statuses, `credit_payment_id IS NULL`, coarse range + local-day filter | unit (SQL string assertions) + mutation | `npx jest venta-universe` | ❌ Wave 0 |
| D-02 | Local day: sale at 23:30 BA (02:30 UTC next day) lands on BA day; NULL `sale_day_local` fallback | itest | `npm run test:itest -- reportaje` | ❌ Wave 0 |
| D-02 | movido/devuelto/fallado excluded from units/tickets/amount | itest (dummy store, like `phase105-coherencia.itest.ts`) | idem | ❌ |
| D-03 | Devoluciones amount = Ganancia `reintegros` formula; blocked with seller/payment dims | unit (compat) + itest | idem | ❌ |
| D-04/08/20 | Margin line-level; coverage % ; stripped when `!marginAllowed` | unit + itest | idem | ❌ |
| D-05/07 | Seed: function + admin-only grant; margin field gating server-side | itest (guard override pattern) + SQL check | idem | ❌ |
| D-09/22 | Each dimension groups correctly incl. «Sin X»; category via madre; payment dim Σ = header Σ | itest | idem | ❌ |
| D-10 | ticket/ticket_promedio × medio_pago rejected | unit (validator) | `npx jest order.validator` | ❌ |
| D-17 | Union of sources; duplicate-signature monitor ≤ baseline | itest against local restored DB (invariant, not absolute) | idem | ❌ |
| D-19 | Availability: single-value/sentinel → disabled with reason; cached 60 s | unit (pure) + itest | `npx jest availability` | ❌ |
| D-12..16 | Saved orders CRUD scoped by store+owner/shared; relative period resolves at run; catalog_version warning; cross-store id → not found | itest | idem | ❌ |
| Limits | each CODEX limit rejected with `fixes`; unknown key → 400 | unit | `npx jest order.validator` | ❌ |
| Executor | 5 s timeout → 408; store/user/global lock → 429; READ ONLY blocks a forced write | itest (inject `pg_sleep`, concurrent runs) | idem | ❌ |
| Size order | `['10','2','XL','M','S','UNICO','32','1.2MM']` → numeric-first natural order | unit | `npx jest size-order` | ❌ |
| CSV | injection guard, quoting, BOM, row cap | unit | `npx jest csv` | ❌ |
| Migrations | new SQL files obey conventions (`lock_timeout`, perm-cache note, w4-exempt) | existing spec | `npx jest migration-conventions` | ✅ |
| Backup/vaciado | new table declared in all 3 catalogs | existing specs | `npx jest store-backup-coverage vaciado-catalogo eliminar-catalogo` | ✅ (need entries) |
| Agent scopes | new endpoints classified | existing specs | `npx jest agent-readonly-scopes` | ✅ (verify) |

### Sampling Rate
- **Per task commit:** the quick run command for the touched files (the commit gate already runs api tsc + eslint on added lines + jest on the changed module directory).
- **Per wave merge:** full unit + `test:itest -- reportaje` + the three registry specs above.
- **Phase gate:** full suite green; plus a **read-only prod reconciliation script** (SELECT in `BEGIN READ ONLY`) for stores 26/30/19: compiled sucursal×mes `venta_neta` (accrual) vs an independent hand SQL, and item-grain vs header-grain within 0.5 %.

### Control groups and mutations (project rule: a check without a control is not a check)
- **Tenant isolation:** two dummy stores with identical sales; run as store A; assert zero rows from B. **Mutation:** delete the `s.store_id = $1` predicate from the fragment → this test **must fail** (if it passes, the test guards nothing).
- **Compiler injection control:** feed ids/strings like `'; DROP TABLE sales;--` through every free-text-looking field (name, preset, dimension id) → validator rejects; SQL string snapshot contains **no** user substring; bind array holds them only if typed.
- **Fan-out control:** a sale with 3 lines and 2 payments: header `venta_neta` equals `total_amount` exactly (mutation: join items before summing → must fail).
- **Share% control:** Top N must not change the denominator (mutation: use `SUM(rows)` → fails).
- **Non-additive control:** totals row tickets ≠ Σ rows when a ticket spans two categories.
- **Legacy control:** dummy store with legacy-source + pos-source sales on the same day → both counted; a legacy sale without payment/seller/product → «Sin X» rows, not dropped.
- **Lock control:** two concurrent runs same store → exactly one 429 `STORE_BUSY`; after the first finishes a third succeeds (proves auto-release); a run that times out releases its lock.
- **Timeout control:** `SELECT pg_sleep(…)` variant returns 408 in ≈ 5 s, not 30.
- **READ ONLY control:** executing `UPDATE` through the executor's connection fails.
- **Snapshot tests of generated SQL** (one per grain × representative dimension) are acceptable **only together** with the behavioural itests above — snapshots alone pin text, not meaning.
- Harness usage: services are not `new`-able by hand — use `test/itest/harness.ts` (`createImportHarness`, `createDummyStore`, `dropDummyStore`); pure compiler/validator/period/size-order/csv are plain unit specs (no Nest).

### Wave 0 Gaps
- [ ] `reports/venta-universe.spec.ts` + `reportaje/*.spec.ts` (validator, compiler, period, size-order, csv, availability) — all new
- [ ] `reportaje/reportaje.itest.ts` using the harness (dummy store fixtures with: madre/leaf category, legacy+pos sources, multi-payment, reversal pair, devuelto row, unit_cost mix)
- [ ] Migrations (permiso, tabla) + local application + registry entries (`store-backup-coverage.ts`, inventory regen, `vaciado-catalogo.ts`, `eliminar-catalogo.ts`) + `db-schema.regen.sh`
- [ ] No new framework install required

## Security Domain

(`security_enforcement` absent → enabled.)

### Applicable ASVS Categories
| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | yes (inherited) | JWT via `FunctionGuard` (passport) — no new auth |
| V3 Session Management | inherited | existing `SessionGuard` conventions; not changed |
| V4 Access Control | **yes — core** | `FunctionGuard('reportaje-abierto','read')`; tenant from session; branch ownership check; margin field gating via `isAllowedStrict`; saved-order access `store_id AND (owner OR shared)`; agent@app excluded via scope manifests |
| V5 Input Validation | **yes — core** | strict catalog-driven validator (unknown key = reject); `bind` params; allowlisted SQL expressions; length caps (name ≤120, order JSON size cap e.g. 8 KB) |
| V6 Cryptography | no | none introduced |
| V7 Error handling/logging | yes | error codes without SQL text; no bind values in logs |
| V13 API | yes | rate: store/user/global locks; row caps; timeouts |

### Known Threat Patterns for NestJS + Sequelize raw SQL
| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| SQL injection via dimension/sort/filter | Tampering | catalog ids → constant expressions; values only via `bind`; compiler test with hostile strings |
| Cross-tenant read (store_id from body, id of another store's branch/saved order) | Information disclosure | session store only; branch ids verified against `branches.store_id`; saved-order lookup always includes store; uniform «not found» |
| Privilege via saved order (margin column persisted for admin, opened by cashier) | Elevation | re-validate on every run with current permissions; strip + `omitted` |
| Resource exhaustion (huge group-by, many concurrent runs, pool starvation) | DoS | limits, `statement_timeout`, advisory-lock concurrency, one pooled connection per run, row caps, no queue holding connections |
| CSV/Excel formula injection | Tampering (client-side) | prefix-neutralise `= + - @ \t \r` |
| Info leak through error messages | Info disclosure | map PG errors to codes; never echo SQL |
| Silent widening of filters | Tampering/Info disclosure | unresolved branch/ids → 400, never «all» |
| agent@app access | Elevation | scope-manifest classification; spec-enforced |
| Margin leakage via comparison/AUR/derived metrics | Info disclosure | any metric depending on cost is `requires:marginAllowed`; derived columns (`margen_pct`, `cobertura`) share the gate |

## Sources

### Primary (HIGH confidence)
- Repo code read this session: `api-ventago/src/app/reports/sale-status.constants.ts`, `reportsGanancia.service.ts`, `reportsSalesCockpit.service.ts` (summary + mix), `salesDimensions.service.ts`, `reportsEnviado.service.ts` (tz pattern), `reports.controller.ts` (guards, `resolveScopedStoreId`, ganancia gating), `legacy-import/streaming/ace-sales.sql.ts`, `auth/services/function-permission.service.ts`, `auth/decorators/function-guard.decorator.ts`, `common/validation/logging-validation.pipe.ts`, `common/redis/*`, `common/throttle/*`, `common/cache/memory-cache.service.ts`, `common/tenant/branch-scope.util.ts`, `store/store-backup-coverage.ts` (+spec), `store/vaciado/*`, `common/migrations/migration-conventions.spec.ts`, `ecosystem.config.js`, `database.module.ts` (slow-query logging).
- Migrations read: `2026-09-29-c-permiso-reporte-precios-fuera-de-lista.sql`, `2026-10-08-d-menu-token-soporte.sql`, `2026-10-15-client-errors.sql`, `2026-07-27-phase63-sale-day-local-1-column.sql`.
- Planning docs: 117-CONTEXT, 117-RESEARCH-USUARIOS, research/interno.md, CODEX.md, 117-PREP, 105-PLAN §0–§3, `.planning/intel/db-schema-tables.md`, CLAUDE.md, project memory index.
- **Prod PG18 read-only measurements, 2026-10-17** (`BEGIN READ ONLY … ROLLBACK`, aggregates only, no personal data): source/status distributions, cutover times, duplicate signature search, payment/items/header reconciliation, dimension null rates, sentinel names, role grants, indexes, EXPLAIN ANALYZE (45 ms), availability-probe timing (8.4 ms).
- PostgreSQL docs, explicit locking (transaction-level advisory locks release at transaction end): https://www.postgresql.org/docs/current/explicit-locking.html
- Sequelize v6 raw queries (replacements vs bind): https://sequelize.org/docs/v6/core-concepts/raw-queries/

### Secondary (MEDIUM confidence)
- `pg_try_advisory_xact_lock` signature/semantics taken from PG §9.28.10 (not fetched; the fetched page confirms xact-level release behaviour and points to the function list). Verify the exact function signature in `psql \df pg_try_advisory_xact_lock` at implementation.

### Tertiary (LOW confidence)
- pgbouncer `pool_mode` (file unreadable) — inferred safe from existing `SET LOCAL` precedent.
- es-AR Excel CSV conventions (A6) — training knowledge.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — everything is already in the repo; no new packages.
- Architecture: HIGH for fragment/grain/validator (measured + code read); MEDIUM for advisory-lock concurrency (new in this codebase, sound by PG docs).
- Legacy dedupe rule: HIGH on evidence (exhaustive signature search since 2026-08-01), MEDIUM on policy until the user confirms A3.
- Permissions: HIGH on facts (prod grants measured), open on policy (Q6).
- Pitfalls: HIGH.

**Research date:** 2026-10-17
**Valid until:** 2026-10-24 for prod measurements (data moves daily: cutovers, new imports); 30 days for code structure.
