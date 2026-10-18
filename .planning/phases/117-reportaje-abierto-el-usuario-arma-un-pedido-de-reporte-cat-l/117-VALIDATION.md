---
phase: 117
slug: reportaje-abierto-el-usuario-arma-un-pedido-de-reporte-cat-l
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-10-17
---

# Phase 117 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution. Source: 117-RESEARCH.md «Validation Architecture». Scope: server only (D-25). Visible name «Reporte a medida» (D-29) — module/table names follow the planner's choice.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | jest 29.7 + ts-jest; unit `*.spec.ts` (rootDir `src`); integration `*.itest.ts` via `test/itest/jest-itest.json --runInBand` against local PG18 using `test/itest/harness.ts` |
| **Config file** | `api-ventago/package.json` (jest block); `api-ventago/test/itest/jest-itest.json` |
| **Quick run command** | `cd api-ventago && npx jest <module dir> src/app/reports/venta-universe --maxWorkers=1` (no `NODE_OPTIONS`) |
| **Full suite command** | `cd api-ventago && npx jest --maxWorkers=1` + `npm run test:itest -- <module>` |
| **Estimated runtime** | quick ~10–20 s · itest ~60 s |

---

## Sampling Rate

- **After every task commit:** quick run for touched files (commit gate also runs api tsc + eslint on added lines + jest on changed module dir).
- **After every plan wave:** full unit + itest for the module + registry specs (`store-backup-coverage`, `vaciado-catalogo`, `eliminar-catalogo`, `agent-readonly-scopes`, `migration-conventions`).
- **Before `/gsd:verify-work`:** full suite green + read-only prod reconciliation (stores 26/30/19: compiled sucursal×mes venta neta vs independent hand SQL; item-grain vs header-grain within 0.5 %).
- **Max feedback latency:** 60 s.

---

## Per-Task Verification Map (by requirement; task IDs filled by planner)

| Requirement | Behavior | Test Type | Automated Command | File Exists | Status |
|---|---|---|---|---|---|
| D-01/02/26 | Fragment: store predicate, `activity_type='sale'`, statuses, accrual, local-day filter | unit + mutation | `npx jest venta-universe` | ❌ W0 | ⬜ |
| D-02 | 23:30 BA lands on BA day; NULL `sale_day_local` fallback | itest | `npm run test:itest -- <module>` | ❌ W0 | ⬜ |
| D-02 | movido/devuelto/fallado excluded | itest | idem | ❌ | ⬜ |
| D-03/30 | Devoluciones = Ganancia formula; only sucursal/tiempo | unit + itest | idem | ❌ | ⬜ |
| D-04/08/20/27 | Margin line-level; coverage %; stripped without new admin-only function | unit + itest | idem | ❌ | ⬜ |
| D-05/27 | Seed: menu function + margin function, admin-only grants | itest + SQL check | idem | ❌ | ⬜ |
| D-09/22/30 | Each dimension incl. «Sin X»; category/season COALESCE(hijo, madre); payment Σ = header Σ | itest | idem | ❌ | ⬜ |
| D-10/30 | ticket/ticket promedio × medio de pago and × item-grain rejected | unit (validator) | `npx jest order.validator` | ❌ | ⬜ |
| D-17/28 | Union of sources; duplicate monitor ≤ baseline | itest (invariant) | idem | ❌ | ⬜ |
| D-19/30 | Availability: single value / NONE / General → disabled + reason; cached 60 s | unit + itest | `npx jest availability` | ❌ | ⬜ |
| D-12..16 | Saved CRUD scoped store+owner/shared; relative period at run; catalog_version warning; cross-store id → not found | itest | idem | ❌ | ⬜ |
| Limits | each limit rejected with `fixes`; unknown key → 400 | unit | `npx jest order.validator` | ❌ | ⬜ |
| Executor | 5 s timeout → 408; store/user/global advisory lock → 429; READ ONLY blocks write | itest | idem | ❌ | ⬜ |
| Size order | numeric-first natural order | unit | `npx jest size-order` | ❌ | ⬜ |
| CSV | injection guard, quoting, BOM, row cap | unit | `npx jest csv` | ❌ | ⬜ |
| Migrations | conventions (`lock_timeout`, perm-cache note, w4-exempt) | existing spec | `npx jest migration-conventions` | ✅ | ⬜ |
| Registries | new table in backup/vaciado/eliminar catalogs; endpoints in agent scopes | existing specs | `npx jest store-backup-coverage vaciado-catalogo eliminar-catalogo agent-readonly-scopes` | ✅ (entries needed) | ⬜ |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Control groups and mutations (mandatory — a check without a control is not a check)

- **Tenant isolation:** two dummy stores with identical sales; run as A → zero rows from B. **Mutation:** remove `s.store_id = $1` → test MUST fail.
- **Injection:** `'; DROP TABLE sales;--` in every string-like field → rejected; generated SQL contains no user substring.
- **Fan-out:** sale with 3 lines + 2 payments → header venta neta = total exactly (mutation: join items before summing → fails).
- **Share %:** Top N does not change denominator (mutation: SUM(rows) → fails).
- **Non-additive:** totals tickets ≠ Σ rows when a ticket spans two categories.
- **Legacy:** legacy + pos same day → both counted; legacy sale without payment/seller/product → «Sin X», not dropped.
- **Locks:** two concurrent runs same store → exactly one 429; third succeeds after (auto-release); timeout releases lock.
- **Timeout:** pg_sleep variant → 408 in ≈5 s.
- **READ ONLY:** UPDATE through executor connection fails.
- SQL snapshots only together with behavioural itests.

---

## Wave 0 Requirements

- [ ] `reports/venta-universe.spec.ts` + module specs (validator, compiler, period, size-order, csv, availability)
- [ ] module itest with harness (`createImportHarness`, `createDummyStore`, `dropDummyStore`) and fixtures: madre/leaf category, legacy+pos, multi-payment, reversal pair, devuelto row, unit_cost mix
- [ ] migrations (permissions, table) applied locally + prod (approval) + registry entries + `db-schema.regen.sh`
- [ ] No new framework install

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|---|---|---|---|
| Prod reconciliation | D-01/D-26 | needs prod data | read-only script: stores 26/30/19, compiled vs hand SQL, ≤0.5 % |
| Owner validation of mockup | D-24 | human | user shows mockup v2 to 2–3 owners before UI planning |
