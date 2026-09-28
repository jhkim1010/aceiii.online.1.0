---
phase: 96
slug: notas-compartidas-del-local
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-09-28
---

# Phase 96 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Source: `96-RESEARCH.md` §Validation Architecture. Requirements = CONTEXT decisions D-01..D-19.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | jest 29 (ts-jest) — api: NestJS `Test.createTestingModule` + `getModelToken` harness; app: jest, **`.ts` only (cannot import `.tsx`)** |
| **Config file** | `api-ventago/jest.config.js`, `ventago-app/jest.config.js` (existing) |
| **Quick run command** | `cd api-ventago && npx jest src/app/notas --maxWorkers=1` · `cd ventago-app && npx jest src/__tests__/notas --maxWorkers=1` |
| **Full suite command** | Not run locally (machine freezes). Phase gate = scoped notas specs + `migration-conventions.spec.ts` + app/api `tsc --noEmit` |
| **Estimated runtime** | ~30 seconds (scoped) |

★ Always `--maxWorkers=1`. Never `--findRelatedTests`. If jest prints nothing, it did not run (NODE_OPTIONS pitfall) — treat as failure, not pass.

---

## Sampling Rate

- **After every task commit:** scoped notas jest for the side touched (api and/or app) + `tsc --noEmit` of that package
- **After every plan wave:** both scoped suites + `npx jest src/common/migrations/migration-conventions.spec.ts --maxWorkers=1` if a migration changed
- **Before `/gsd-verify-work`:** all of the above green + mutation check on visibility predicate (remove the recipient filter → D-05 test must fail)
- **Max feedback latency:** 60 seconds

---

## Per-Decision Verification Map

(Task refs filled by planner 2026-09-28 — shown in the Status column as plan/task.)

| Decision | Secure / Expected Behavior | Test Type | Automated Command | File Exists | Status |
|----------|----------------------------|-----------|-------------------|-------------|--------|
| D-05 | Personal nota not returned to store admin in list, detail, search, attachment, replies | unit (service) | `npx jest src/app/notas/notas.service.spec.ts -t "visibility" --maxWorkers=1` | ❌ W0 | ⬜ pending (96-03 T1, 96-05 T1/T2, 96-06 T2, 96-10 T1 (mutation)) |
| D-03 / D-15 | Send-to-Todos and pin on Todos require `notas-enviar-todos`; user without it gets 403 | unit (guard/service) | `npx jest src/app/notas -t "permission" --maxWorkers=1` | ❌ W0 | ⬜ pending (96-03 T2, 96-06 T1, 96-07 T1) |
| D-07 | New hire unread = pinned Todos + Todos created after `users.created_at`; still sees older Todos | unit | `npx jest src/app/notas/notas.service.spec.ts -t "unread" --maxWorkers=1` | ❌ W0 | ⬜ pending (96-03 T2, 96-05 T1) |
| D-11 | Normal → read on open; Importante/Urgente → only `ack_at` counts as read | unit | `npx jest src/app/notas/notas.service.spec.ts -t "ack" --maxWorkers=1` | ❌ W0 | ⬜ pending (96-03 T2, 96-05 T2) |
| D-10 | Read/ack list visible to sender; to admin only for Todos | unit | `npx jest src/app/notas/notas.service.spec.ts -t "reads" --maxWorkers=1` | ❌ W0 | ⬜ pending (96-03 T2, 96-05 T2) |
| D-12 | Reaction limited to the 5 fixed emoji; toggle removes | unit | `npx jest src/app/notas -t "reaction" --maxWorkers=1` | ❌ W0 | ⬜ pending (96-06 T2) |
| D-13 | Reply has no parent-reply path (one level) | unit | `npx jest src/app/notas -t "reply" --maxWorkers=1` | ❌ W0 | ⬜ pending (96-02 T1, 96-06 T2) |
| D-14 | Edit stores previous version + `edited`; archive is soft; admin can archive others' Todos only | unit | `npx jest src/app/notas -t "edit|archive" --maxWorkers=1` | ❌ W0 | ⬜ pending (96-06 T1) |
| D-16 | Expiry judged by store-local date (`stores.timezone`), not UTC | unit | `npx jest src/app/notas/notas.service.spec.ts -t "expiry" --maxWorkers=1` | ❌ W0 | ⬜ pending (96-03 T1, 96-05 T1) |
| D-17 | Attachment keys path-prefixed → rejected by public `/minio/:filename`; served only by authenticated visibility-checked route; max 5, image/PDF only | unit (with positive control) | `npx jest src/common/minio -t "isPubliclyServable" --maxWorkers=1` + `npx jest src/app/notas -t "attachment" --maxWorkers=1` | ❌ W0 | ⬜ pending (96-02 T2, 96-03 T1, 96-06 T1/T2) |
| D-18 | Search obeys visibility (search for a private title returns 0 for admin) | unit | `npx jest src/app/notas -t "search" --maxWorkers=1` | ❌ W0 | ⬜ pending (96-03 T1, 96-05 T1) |
| D-07/D-19 client | Badge count / sort (pinned → unread → newest) pure logic | unit (app `.ts`) | `cd ventago-app && npx jest src/__tests__/notas --maxWorkers=1` | ❌ W0 | ⬜ pending (96-04 T1) |
| tenant | Every new Nota* model has `storeId` and is TenantGuard-covered | unit | `npx jest src/app/notas -t "tenant" --maxWorkers=1` | ❌ W0 | ⬜ pending (96-02 T1) |
| migrations | New tables: owner DO block, lock_timeout, perm-cache comment on role_functions DML | automated | `npx jest src/common/migrations/migration-conventions.spec.ts --maxWorkers=1` | ✅ | ⬜ pending (96-01 T1/T2) |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `api-ventago/src/app/notas/notas.service.spec.ts` — visibility / unread / ack / reads / expiry / search
- [ ] `api-ventago/src/app/notas/*.spec.ts` — permission, reaction, reply, edit/archive, attachment, tenant coverage
- [ ] `api-ventago/src/common/minio/minio.controller.spec.ts` — extend/create with positive + negative control for path-prefixed keys
- [ ] `ventago-app/src/__tests__/notas-*.spec.ts` — badge/sort pure logic in a `.ts` helper
- [ ] Seed migration run **twice** locally (5432) — second run must not over-grant (manual, see below)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Seed idempotency | D-03 | SQL, not jest | `psql -p 5432 -d ventago -f api-ventago/migrations/<notas-seed>.sql` twice; row counts unchanged on 2nd run |
| Seed before code deploy | D-03 | deploy ordering | Apply seed to prod 5434 and confirm `functions` rows exist BEFORE pushing api/app |
| Toast on Notas screen, badge-only on POS | D-08/D-09 | realtime + route | Two browsers (prod build): send nota → toast on /notas, none on /nueva-venta, badge +1 on both |
| Layout B matches mockup | D-02 | visual | Compare with `.planning/sketches/notas-compartidas.html` (B · Bandeja) |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-09-28 (plan-checker: 0 blockers; wave_0 tests are written during execution)
