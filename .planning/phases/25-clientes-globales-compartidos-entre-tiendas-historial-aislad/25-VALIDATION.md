---
phase: 25
slug: clientes-globales-compartidos-entre-tiendas-historial-aislad
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-23
---

# Phase 25 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Derived from 25-RESEARCH.md "Validation Architecture" section.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | jest 29.x (api-ventago) + jest 29.x (ventago-app) |
| **Config file** | `api-ventago/jest.config.js`, `ventago-app/jest.config.js` |
| **Quick run command** | `cd api-ventago && npm test -- --testPathPattern='owner-scope\|cuit-validator\|global-client'` |
| **Full suite command** | `cd api-ventago && npm test && cd ../ventago-app && npm test` |
| **Estimated runtime** | ~60 seconds (quick), ~5 min (full) |

---

## Sampling Rate

- **After every task commit:** Run quick run command (unit tests on touched areas)
- **After every plan wave:** Run full suite command
- **Before `/gsd-verify-work`:** Full suite must be green + manual UAT for import/merge flows
- **Max feedback latency:** 90 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 25-01-01 | 01 | 1 | REQ-22, D3-01 | T-25-01 | stores.owner_group_id NOT NULL after migration | migration | `psql -c "\d stores" \| grep owner_group_id` | ❌ W0 | ⬜ pending |
| 25-01-02 | 01 | 1 | REQ-22, D1-05 | — | global_clients.document UNIQUE scoped by owner_group_id | migration | `psql -c "\d global_clients"` | ❌ W0 | ⬜ pending |
| 25-01-03 | 01 | 1 | D2-02 | — | legacy clients with valid DNI/CUIT migrated to global_clients + store_clients | migration | node dry-run → ensure mapping counts match | ❌ W0 | ⬜ pending |
| 25-02-01 | 02 | 2 | REQ-8, D3-04 | T-25-02 | OwnerScopeGuard returns 403 on cross-owner access | unit | `jest owner-scope.guard.spec` | ❌ W0 | ⬜ pending |
| 25-02-02 | 02 | 2 | REQ-8 | T-25-02 | /clients/search filters by ownerGroupId | integration | `jest clients.controller.spec` | ❌ W0 | ⬜ pending |
| 25-02-03 | 02 | 2 | REQ-4, REQ-7 | T-25-03 | /sales/* enforces storeId scope for all reads | integration | `jest sales.controller.spec` | ❌ W0 | ⬜ pending |
| 25-03-01 | 03 | 3 | D1-02 | — | CUIT mod 11 checksum accepts valid, rejects check=10 | unit | `jest cuit-validator.spec` | ❌ W0 | ⬜ pending |
| 25-03-02 | 03 | 3 | D1-02 | — | DNI regex accepts 7-8 digits only | unit | `jest dni-validator.spec` | ❌ W0 | ⬜ pending |
| 25-03-03 | 03 | 3 | D1-03, D1-04 | — | Promotion flow: local client + new DNI → Global promotion | integration | `jest client-promotion.service.spec` | ❌ W0 | ⬜ pending |
| 25-03-04 | 03 | 3 | D1-03 | — | Merge proposal: conflicting fields surfaced for user resolution | integration | `jest client-merge.service.spec` | ❌ W0 | ⬜ pending |
| 25-04-01 | 04 | 4 | REQ-10, REQ-16 | — | Import happy path: 100 rows commit transactionally | integration | `jest client-import.service.spec` | ❌ W0 | ⬜ pending |
| 25-04-02 | 04 | 4 | REQ-21 | — | Import 10,000 rows < 30s | benchmark | `jest client-import.perf.spec --runInBand` | ❌ W0 | ⬜ pending |
| 25-04-03 | 04 | 4 | REQ-17 | — | Failed rows exported as CSV with row_index + error_code | integration | `jest client-import.failure.spec` | ❌ W0 | ⬜ pending |
| 25-04-04 | 04 | 4 | REQ-18, D4-06 | — | client_imports audit row written per import | integration | `jest client-import.audit.spec` | ❌ W0 | ⬜ pending |
| 25-05-01 | 05 | 5 | REQ-10, REQ-12 | — | CargaMasivaClientesView column mapping auto-detect | unit | `jest CargaMasivaClientesView.test.tsx` | ❌ W0 | ⬜ pending |
| 25-05-02 | 05 | 5 | REQ-13, D4-02 | — | Preview rows show [Global]/[Local]/[Skip] chips | unit | `jest CargaMasivaPreviewRow.test.tsx` | ❌ W0 | ⬜ pending |
| 25-06-01 | 06 | 6 | REQ-10, D4-01 | — | ClienteView top-bar "Importación masiva" button routes to carga-masiva page | e2e | manual UAT | — | ⬜ pending |
| 25-06-02 | 06 | 6 | D1-04 | — | Merge modal lets user pick per-field final value | unit | `jest MergeResolutionModal.test.tsx` | ❌ W0 | ⬜ pending |
| 25-07-01 | 07 | 7 | REQ-4, REQ-7 | T-25-03 | /reports/* respect storeId scope (no cross-store historial leak) | integration | `jest reports.controller.spec` | ❌ W0 | ⬜ pending |
| 25-07-02 | 07 | 7 | REQ-19 | — | CASL manage-clientes-import denied to vendedor role | unit | `jest casl.spec` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `api-ventago/src/app/common/guards/__tests__/owner-scope.guard.spec.ts` — OwnerScopeGuard unit test stub
- [ ] `api-ventago/src/app/shared/global-clients/__tests__/cuit-validator.spec.ts` — CUIT mod 11 checksum test stub
- [ ] `api-ventago/src/app/shared/global-clients/__tests__/dni-validator.spec.ts` — DNI regex test stub
- [ ] `api-ventago/src/app/shared/global-clients/__tests__/client-promotion.service.spec.ts` — Promotion flow test stub
- [ ] `api-ventago/src/app/shared/global-clients/__tests__/client-merge.service.spec.ts` — Merge resolution test stub
- [ ] `api-ventago/src/app/shared/client-imports/__tests__/client-import.service.spec.ts` — Import happy path test stub
- [ ] `api-ventago/src/app/shared/client-imports/__tests__/client-import.perf.spec.ts` — 10k-row benchmark stub
- [ ] `api-ventago/src/app/shared/client-imports/__tests__/client-import.audit.spec.ts` — audit row test stub
- [ ] `ventago-app/src/views/clientes-globales/__tests__/CargaMasivaClientesView.test.tsx` — frontend test stub
- [ ] `ventago-app/src/views/clientes-globales/__tests__/MergeResolutionModal.test.tsx` — merge modal test stub
- [ ] Confirm `api-ventago/jest.config.js` & `ventago-app/jest.config.js` exist. If missing, Wave 0 installs.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| ClienteView "Importación masiva" button placement + modal UX | REQ-10, D4-01 | Visual layout review | 1) Open ClienteView 2) Confirm top-bar button present 3) Click → lands on `/clientes-globales/carga-masiva` |
| CSV/Excel end-to-end upload with mixed valid/invalid/duplicate rows | REQ-10-17 | File-upload + multi-step UX | 1) Upload sample file 2) Verify column mapping 3) Confirm preview chips 4) Commit 5) Download failure report |
| Promotion: local client acquiring DNI in POS client-edit | D1-03 | Cross-screen workflow | 1) Create local client 2) Edit client, add DNI 3) Save 4) Verify promoted to Global + merge prompt if duplicate |
| Merge conflict resolution UI | D1-04 | Field-by-field decision | 1) Trigger merge via promotion 2) Select per-field winners 3) Save 4) Verify final Global record |
| 10,000-row import perf in production-like env | REQ-21 | Needs real Docker PG instance + sample file | Run `scripts/perf/gen-10k-clients.js` + upload, time end-to-end |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 90s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
