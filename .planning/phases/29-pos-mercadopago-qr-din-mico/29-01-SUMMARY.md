---
phase: 29-pos-mercadopago-qr-din-mico
plan: 01
subsystem: payments
tags: [mercadopago, qr-dynamic, oauth, aes-256-gcm, env-vars, jest-fixtures, axios-mock, qrcode-react, ops-docs]

requires: []

provides:
  - "qrcode.react@4.2.0 frontend dependency for QR rendering (PaymentSummaryModal in Plan 07)"
  - "8 MP_* env vars documented in api-ventago/.env.example (boot-time validation contract for Plan 02b MpTokenCryptoService)"
  - "MP webhook envelope fixture (mp-webhook-payload.json) — Plan 05 webhook spec input"
  - "MP /v1/payments approved fixture (mp-payment-approved.json) — Plans 03/04/05/09 spec input"
  - "MP QR creation response fixture (mp-qr-response.json) — Plan 04 QR spec input"
  - "axios mock helper (mock-mp-api.ts) with 4 exports: resetMpMocks, mockMpGet, mockMpPost, mockMpFailure — Plans 03/04/05/09 share this surface"
  - "Sandbox E2E procedure (docs/phase29-e2e.md) — Plan 09 Task 4 executes this script"
  - "Ops MP App provisioning guide (docs/phase29-ops-mp-app-setup.md) — operator dependency before Wave 6"

affects:
  - "29-02-PLAN.md (DB models reference fixtures)"
  - "29-02b-PLAN.md (MpTokenCryptoService boot validation reads MP_TOKEN_ENCRYPTION_KEY)"
  - "29-03-PLAN.md (MpApiClientService + OAuth services use mock-mp-api.ts)"
  - "29-04-PLAN.md (MpQrService spec uses mp-qr-response.json + mock-mp-api.ts)"
  - "29-05-PLAN.md (webhook + wallet specs use mp-webhook-payload.json + mp-payment-approved.json)"
  - "29-07-PLAN.md (PaymentSummaryModal imports QRCodeSVG from qrcode.react)"
  - "29-09-PLAN.md (refund spec + E2E executor)"

tech-stack:
  added:
    - "qrcode.react@4.2.0 (frontend QR rendering, ~115KB unpacked, React 18 compatible)"
  patterns:
    - "axios mock registry pattern: regex pathPattern → response/status, jest.mock('axios') with reset helper between tests"
    - "MP env contract: 8 MP_* vars documented with format hints + openssl generation commands inline in .env.example"
    - "Test fixture co-location: api-ventago/test/fixtures/ for JSON payloads, api-ventago/test/helpers/ for shared TypeScript helpers (jest rootDir=src so these are NOT auto-discovered as tests)"

key-files:
  created:
    - "api-ventago/test/fixtures/mp-webhook-payload.json (MP webhook envelope, type=payment, action=payment.updated)"
    - "api-ventago/test/fixtures/mp-payment-approved.json (MP /v1/payments/{id} approved response, ARS 30000)"
    - "api-ventago/test/fixtures/mp-qr-response.json (MP QR creation response with EMV qr_data)"
    - "api-ventago/test/helpers/mock-mp-api.ts (jest axios mock registry — 4 helpers)"
    - "docs/phase29-e2e.md (95-line, 7-step sandbox E2E script)"
    - "docs/phase29-ops-mp-app-setup.md (86-line, 8-step ops procedure)"
  modified:
    - "ventago-app/package.json (qrcode.react@^4.2.0 added)"
    - "package-lock.json (npm workspaces hoisted resolution at root)"
    - "api-ventago/.env.example (appended Phase 29 block — 8 MP_* vars + comments)"

key-decisions:
  - "Mock helper TypeScript verification uses --skipLibCheck (matches project tsconfig); raw plan command without flags surfaces 13 unrelated node_modules type warnings — false positives"
  - "Pre-existing 31 react-hooks/exhaustive-deps warnings in ventago-app are out of plan scope; CLAUDE.md explicitly classifies them as warnings (not blocking errors)"
  - "Smoke test for SSR compat (qr-smoke.tsx) created + linted clean + deleted in same task — no temporary files committed"
  - "package-lock.json change committed in ROOT repo (npm workspaces hoists), package.json change committed in ventago-app sub-repo (separate remote per CLAUDE.md)"

patterns-established:
  - "MP fixture naming: mp-{purpose}-{state}.json (mp-webhook-payload, mp-payment-approved, mp-qr-response). Future MP-related fixtures should follow."
  - "MP env var prefix discipline: MP_PRODUCTION_*, MP_SANDBOX_*, MP_TOKEN_*, MP_OAUTH_*, MP_WEBHOOK_*, MP_NOTIFICATION_* — each subsystem owns its prefix."
  - "Ops doc anatomy: numbered steps + verification command per step + rollback note at the end (re-usable for Phase 30/31 MP point + checkout setup docs)."

requirements-completed: []
# Note: Plan 01 frontmatter lists MP-POS-01..07 because this is the foundational
# plan for all 7 requirements. No requirement is COMPLETED by Plan 01 alone —
# each requirement closes when the corresponding implementation plan finishes
# (per VALIDATION.md per-task map). Mark-complete is deferred to those plans.

duration: 8min
completed: 2026-05-05
---

# Phase 29 Plan 01: Wave 0 Pre-flight Summary

**Installed qrcode.react@4.2.0 on the frontend, locked the 8-variable MP env contract in api-ventago/.env.example, scaffolded 3 MP test fixtures + 4-export axios mock helper, and shipped two ops-facing docs (sandbox E2E procedure + MP App provisioning guide) — eliminating the cascading "MP_TOKEN_ENCRYPTION_KEY missing at boot" failure mode for every downstream wave.**

## Performance

- **Duration:** ~8 min
- **Started:** 2026-05-05T03:19:12Z
- **Completed:** 2026-05-05T03:27:09Z
- **Tasks:** 3 auto + 1 checkpoint pending (4 total)
- **Files modified:** 8 (1 frontend dep, 1 env template, 4 test assets, 2 docs — package-lock.json hoisted at root)

## Accomplishments

- qrcode.react@4.2.0 installed in ventago-app, SSR compat verified via temporary smoke component (deleted after lint), package.json + root package-lock.json updated.
- 8 MP_* env vars (`MP_PRODUCTION_CLIENT_ID/SECRET`, `MP_SANDBOX_CLIENT_ID/SECRET`, `MP_TOKEN_ENCRYPTION_KEY`, `MP_OAUTH_STATE_SECRET`, `MP_WEBHOOK_SECRET`, `MP_NOTIFICATION_BASE_URL`) documented in api-ventago/.env.example with inline `openssl rand -hex 32` generation commands and rotation warnings.
- Three MP API fixture JSON files (webhook envelope, approved payment, QR creation response) created — all parse as valid JSON; `mp-payment-approved.json` carries `status='approved'` for happy-path test paths.
- Axios mock helper `test/helpers/mock-mp-api.ts` with 4 exports (`resetMpMocks`, `mockMpGet`, `mockMpPost`, `mockMpFailure`) — TypeScript-clean against project tsconfig (skipLibCheck).
- Sandbox E2E script (`docs/phase29-e2e.md`, 95 lines, 7 steps) covers: OAuth connect → sandbox banner observation → QR generation → payment simulation (real MP test app scan OR `/v1/payments` curl fallback) → auto Generar Venta → polling fallback → refund → refund failure UX. Each step includes DB SELECT verifications.
- Ops MP App setup guide (`docs/phase29-ops-mp-app-setup.md`, 86 lines, 8 steps) covers: production + sandbox MP Apps creation, OAuth redirect URI, webhook URL, AES-256-GCM key generation, OAuth state HMAC secret, env var provisioning on srv803182, boot verification, key rotation note.

## Task Commits

Each task was committed atomically (multi-repo: ventago-app + api-ventago + root, per CLAUDE.md monorepo rule):

1. **Task 1a: qrcode.react dependency in ventago-app/package.json** — `be2b786` (chore, ventago-app sub-repo)
2. **Task 1b: package-lock.json hoist at root** — `111126a` (chore, root repo)
3. **Task 2: MP env template + 3 fixtures + axios mock helper in api-ventago** — `d78f238` (chore, api-ventago sub-repo)
4. **Task 3: docs/phase29-e2e.md + docs/phase29-ops-mp-app-setup.md in root** — `f9ce55e` (docs, root repo)

**Plan metadata commit:** to be created after this SUMMARY (root repo, includes SUMMARY.md + STATE.md + ROADMAP.md + REQUIREMENTS.md updates).

## Files Created/Modified

**Created (root repo):**
- `docs/phase29-e2e.md` — 7-step sandbox E2E procedure
- `docs/phase29-ops-mp-app-setup.md` — 8-step ops MP App provisioning procedure

**Created (api-ventago sub-repo):**
- `api-ventago/test/fixtures/mp-webhook-payload.json` — sample MP webhook envelope (`type=payment`, `data.id` pointer)
- `api-ventago/test/fixtures/mp-payment-approved.json` — sample MP `/v1/payments/{id}` approved response (ARS 30000, account_money)
- `api-ventago/test/fixtures/mp-qr-response.json` — sample MP QR creation response with EMV `qr_data`
- `api-ventago/test/helpers/mock-mp-api.ts` — jest axios mock registry exporting `resetMpMocks` / `mockMpGet` / `mockMpPost` / `mockMpFailure`

**Modified (api-ventago sub-repo):**
- `api-ventago/.env.example` — appended Phase 29 block with 8 MP_* env vars + format hints + generation commands

**Modified (ventago-app sub-repo):**
- `ventago-app/package.json` — added `qrcode.react: ^4.2.0` to dependencies

**Modified (root repo, npm workspaces hoist):**
- `package-lock.json` — qrcode.react@4.2.0 resolution recorded at root

## Decisions Made

- **Smoke file lifecycle:** SSR compatibility check used a temporary `qr-smoke.tsx` that was lint-checked and deleted in the same task. No throwaway files committed. ESLint on the file alone produced 0 issues.
- **Pre-existing lint warnings:** ventago-app baseline has 31 `react-hooks/exhaustive-deps` warnings unrelated to qrcode.react. `npm run lint` exit code = 0 (warnings don't block per CLAUDE.md note "Warning이므로 빌드는 통과하나 주의 필요"). Plan's `--max-warnings=0` over-strict requirement deferred per Scope Boundary rule.
- **Mock helper TS verification:** raw `npx tsc --noEmit test/helpers/mock-mp-api.ts` (no flags) reports 13 errors in unrelated `node_modules/@types/*` packages because `skipLibCheck` defaults off. With project tsconfig flags (`--skipLibCheck`), 0 errors. Project-wide `npx tsc --noEmit -p tsconfig.json` shows 0 errors involving mock-mp-api.ts. Treated as verification pass.
- **Multi-repo commit routing:** package.json change committed in `ventago-app/` (separate remote), root `package-lock.json` committed in root repo (npm workspaces hoist target), api-ventago files in `api-ventago/` sub-repo, docs/ in root.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Plan's `--max-warnings=0` lint constraint vs. 31 pre-existing exhaustive-deps warnings**
- **Found during:** Task 1 (smoke test lint step)
- **Issue:** Plan specifies `cd ventago-app && npm run lint -- --max-warnings=0` must pass. The `ventago-app` baseline has 31 pre-existing `react-hooks/exhaustive-deps` warnings across 17+ files (talleres, reports, sales, products) — completely unrelated to qrcode.react. Fixing them is out of plan scope (Scope Boundary rule: "Only auto-fix issues DIRECTLY caused by the current task's changes").
- **Fix:** Ran two checks instead — (a) `npx eslint --fix src/views/_smoke/qr-smoke.tsx` → 0 issues on the file we created; (b) `npm run lint` (without `--max-warnings=0`) → exit code 0 (warnings don't block). Confirmed CLAUDE.md rule "react-hooks/exhaustive-deps Warning이므로 빌드는 통과하나 주의 필요". Pre-existing warnings logged here for future cleanup phase, not addressed in Plan 29-01.
- **Files modified:** None (no fix applied to pre-existing files).
- **Verification:** Lint exit code 0; the smoke file alone is clean.
- **Committed in:** N/A (no source change required).

---

**Total deviations:** 1 auto-handled (Rule 3 — boundary clarification, no source change)
**Impact on plan:** Zero scope creep. Plan-file's `--max-warnings=0` flag is over-strict relative to the existing baseline; documented for the verifier and for a future ESLint-cleanup phase.

## Issues Encountered

- **Pre-existing modified files in sub-repos** (`ventago-app/src/views/sales/list/components/{DailySalesStats,SalesListToolbar}.tsx` + `api-ventago/src/app/sales/sales.service.ts`) — left untouched. Staged Phase 29 files individually (no `git add -A`) per the Task Commit Protocol.
- **api-ventago `.env.example` was minimal** (16 lines, only DB/JWT/Telegram). Phase 29 block was *appended* (not replaced) so existing entries survived.

## User Setup Required

**External services require manual configuration before Wave 6 deployment.** See `docs/phase29-ops-mp-app-setup.md` for the full 8-step procedure. Summary:

- Create MP Production App at https://www.mercadopago.com.ar/developers/panel
- Create MP Sandbox test users (vendedor + comprador for E2E)
- Configure OAuth redirect URI in BOTH apps: `https://newapi.coolsistema.com/api/mercadopago/oauth/callback`
- Configure webhook URL in production app: `https://newapi.coolsistema.com/api/mercadopago/webhook` (subscribe to `payment` events)
- Generate `MP_TOKEN_ENCRYPTION_KEY` via `openssl rand -hex 32` → store in password vault
- Generate `MP_OAUTH_STATE_SECRET` via `openssl rand -hex 32` → store in password vault
- Provision 8 MP_* env vars on srv803182 → restart api_ventago container

The Plan 01 checkpoint (`checkpoint:human-action`) blocks until operator confirms.

## Next Phase Readiness

- **Plan 29-02 (DB tables)**: ready — fixtures in place to underpin schema-aware integration tests in Plan 29-02b.
- **Plan 29-02b (crypto service + module wiring)**: ready — `MP_TOKEN_ENCRYPTION_KEY` env contract documented, `mock-mp-api.ts` available for service tests.
- **Plans 29-03..05**: ready — all axios-based MP API services can `import { mockMpGet, mockMpPost } from '../../test/helpers/mock-mp-api'` and consume the 3 fixtures.
- **Plan 29-07 (UI)**: ready — `qrcode.react` resolves; `import { QRCodeSVG } from 'qrcode.react'` works in TSX.
- **Plan 29-09 (E2E)**: blocked on Plan 01 checkpoint operator approval (real MP Apps must exist).
- **Wave 6 deploy**: blocked on Plan 01 checkpoint (real secrets must be provisioned on srv803182).

## Threat Surface Scan

No new security-relevant surface introduced beyond the threats already documented in Plan 01 frontmatter. Mitigations applied:

- T-29-02 (`.env.example` info disclosure): empty values only (`MP_TOKEN_ENCRYPTION_KEY=` with no value); ops doc explicitly says "save in password vault, not in repo".
- T-29-08 (ops doc info disclosure): doc references generation procedure (`openssl rand -hex 32`) but never embeds a literal key.
- T-29-08-rotation: rotation procedure documented in ops doc §Rollback section, flagged as out of Phase 29 scope per RESEARCH §A8.

## Self-Check: PASSED

All claimed files exist on disk:
- ventago-app/package.json — qrcode.react@^4.2.0 entry present
- package-lock.json — root hoist present
- api-ventago/.env.example — 8 MP_* vars present
- api-ventago/test/fixtures/mp-webhook-payload.json — valid JSON
- api-ventago/test/fixtures/mp-payment-approved.json — valid JSON, status=approved
- api-ventago/test/fixtures/mp-qr-response.json — valid JSON
- api-ventago/test/helpers/mock-mp-api.ts — TS-clean
- docs/phase29-e2e.md — 95 lines, 7 steps
- docs/phase29-ops-mp-app-setup.md — 86 lines, 8 steps
- .planning/phases/29-pos-mercadopago-qr-din-mico/29-01-SUMMARY.md — this file

All claimed commits exist in git log:
- be2b786 (ventago-app): chore(phase-29): add qrcode.react@^4.2.0 dependency
- 111126a (root): chore(phase-29): bump root package-lock for qrcode.react@4.2.0
- d78f238 (api-ventago): chore(phase-29): add MP env template + test fixtures + axios mock helper
- f9ce55e (root): docs(phase-29): add sandbox E2E test script + ops MP App setup guide

---
*Phase: 29-pos-mercadopago-qr-din-mico*
*Completed: 2026-05-05*
