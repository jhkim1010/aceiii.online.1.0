---
phase: 111
slug: app-m-vil-ventago-vender-desde-el-celular-con-factura-electr
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-10-15
---

# Phase 111 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Source: `111-RESEARCH.md` § Validation Architecture (requirement → test map lives there; the planner fills the per-task map).

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | API: jest 29 (ts-jest) + `*.itest.ts` (DB) · App: `flutter_test` · Web: tsc + eslint + jest (`src/__tests__/*.spec.ts`, `.ts` only) |
| **Config file** | `api-ventago/package.json` (jest), `api-ventago/test/itest/jest-itest.json`, new app `pubspec.yaml` (Wave 0) |
| **Quick run command** | `cd api-ventago && npx jest src/app/mobile --maxWorkers=1` |
| **Full suite command** | `cd api-ventago && npx jest src/app/mobile src/app/sales src/app/afip src/app/cashRegister src/app/products src/app/stocks src/app/auth src/app/mercadopago src/app/session src/common/migrations --maxWorkers=1` + `cd ventago-app && npx jest src/__tests__/celulares.spec.ts --maxWorkers=1` + `flutter analyze && flutter test` |
| **Estimated runtime** | quick ~15 s · wave ~3 min |

★ Never bare `jest` (memory: 20 GB blow-up). Always `--maxWorkers=1`. Empty output = did not run.

---

## Sampling Rate

- **After every task commit:** module-directory jest (what the commit gate runs) + `tsc`.
- **After every plan wave:** full suite command above + migration conventions spec (`src/app/auth` added to the API suite for Plan 18).
- **App phase gate (slow, not per task):** `cd ventago-movil && flutter build ios --debug --no-codesign` after Plan 02 and again in Plan 20.
- **Push:** none until Plan 14 (all other plans are commit-only; order migration → api → web → app; active users re-measured right before EACH push and before prod DDL in Plan 01 Task 3). Plan 20 pushes only the private app repo.
- **Before `/gsd:verify-work`:** full suite green + manual UAT below.
- **Mutation spot-checks:** remove `suppressAutoPrint` · remove box-open pre-check · move findByKey after the pre-check · drop store filter on device lookup · drop mobileSession.userId === req.user.id check · drop terminal filter on MP intent lookup · delete `assertRutaPermitida` call in JwtStrategy · prefix check without trailing slash · drop `type:null` on ingreso — each must kill ≥1 test ("Tests: 0" = compile error, not survival).
- **Max feedback latency:** 60 s.

---

## Per-Task Verification Map

*Filled by the planner from `111-RESEARCH.md` § Phase Requirements → Test Map (D-03 … D-22). Revised 2026-10-15: Plan 03 split into 03 + 15, Plan 10 into 10 + 16, Plan 13 into 13 + 19; new Plans 17 (MP QR, D-21) and 18 (D-06 login + D-22 token confinement). Revision 3 (2026-10-15): Plan 02 Task 2 split (now T2+T3, CI = T4); Plan 14 split into 14 (ship + UAT sheet, autonomous) + 20 (release builds, TestFlight, UAT run); GET /mobile/pos/fiscal/opciones (Plan 06) and context.branches (Plan 04). Waves 1–11.*

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 111-01-T1 | 01 | 1 | D-17, D-15, D-04, D-21 | T-111-01, T-111-05c | expand-only DDL, lock_timeout, CONCURRENTLY idx, FK NOT VALID + VALIDATE | migration spec + psql | `cd api-ventago && npx jest src/common/migrations/migration-conventions.spec.ts --maxWorkers=1` | ✅ spec exists | ⬜ pending |
| 111-01-T2 | 01 | 1 | D-17 | T-111-01 | prod DDL only after user approval | checkpoint | `ssh read-only pg_stat_activity count` | n/a | ⬜ pending |
| 111-01-T3 | 01 | 1 | D-17, D-08, D-12, D-21 | T-111-02, T-111-04, T-111-05b | active users + long-tx re-measured right before prod DDL (not reused from T2); owner coolsistema; unique MP-intent index valid; models after prod DDL; commit only | tsc + jest | `cd api-ventago && npx tsc --noEmit -p tsconfig.json && npx jest src/app/sales/sales-create.service.spec.ts --maxWorkers=1` | ✅ | ⬜ pending |
| 111-02-T1 | 02 | 1 | D-19, D-02 | — | names fixed before creation | checkpoint | `gh repo view` | n/a | ⬜ pending |
| 111-02-T2 | 02 | 1 | D-01, D-02, D-19 | T-111-SC, T-111-06 | private repo; submodule; empty scaffold compiles | flutter | `cd ventago-movil && flutter pub get && flutter analyze && flutter test` | ❌ W0 (created here) | ⬜ pending |
| 111-02-T3 | 02 | 1 | D-01, D-02 | T-111-09 | tokens in secure storage; prod BASE_URL https; money es-AR | flutter unit | `cd ventago-movil && flutter analyze && flutter test` | ❌ W0 | ⬜ pending |
| 111-02-T4 | 02 | 1 | D-02 | T-111-07, T-111-08 | HTTPS only; secrets gitignored (iOS compile in plan gate) | flutter + yaml | `cd ventago-movil && flutter analyze && flutter test` + yaml parse | ❌ W0 | ⬜ pending |
| 111-18-T1 | 18 | 1 | D-22 | T-111-80..84 | ventago-movil token only on /mobile/pos/* (HTTP + 4 sockets); old app/web unchanged; mutations ×3 | unit + mutation | `cd api-ventago && npx jest src/app/auth/token-client.spec.ts src/app/auth/strategies src/app/auth/guards --maxWorkers=1` | ❌ W0 | ⬜ pending |
| 111-18-T2 | 18 | 1 | D-06 | T-111-86 | admin/gerente login w/o branch scope; old login byte-identical | unit | `cd api-ventago && npx jest src/app/mobile/auth --maxWorkers=1` | ✅ base spec exists | ⬜ pending |
| 111-03-T1 | 03 | 2 | D-03, D-12, D-16, D-21 | T-111-12, T-111-12b | storeId mandatory; store-TZ day; sin-emitir no window by default | unit | `cd api-ventago && npx jest src/app/mobile/pos/shared --maxWorkers=1` | ❌ W0 | ⬜ pending |
| 111-03-T2 | 03 | 2 | D-03 | — | module shells boot (incl. PosMpModule) | tsc + jest | `cd api-ventago && npx tsc --noEmit -p tsconfig.json && npx jest src/app/mobile --maxWorkers=1` | ✅ | ⬜ pending |
| 111-15-T1 | 15 | 3 | D-04, D-22 | T-111-10, T-111-11, T-111-14, T-111-15, T-111-10c | approve only into own-store box; approve/revoke clear guard cache; revoke deletes sessions in tx; phone terminals not movable by web (SessionModule forFeature MobileDevice) | unit | `cd api-ventago && npx jest src/app/mobile/devices src/app/session --maxWorkers=1` | ❌ W0 | ⬜ pending |
| 111-15-T2 | 15 | 3 | D-03, D-04, D-06, D-22 | T-111-12, T-111-13, T-111-10b, T-111-10c | approved same-store device only; session userId must equal JWT user; only approved results cached; admin empty scope passes; revoked session → 401 next request; mutations: drop store filter, drop userId check | unit + mutation | `cd api-ventago && npx jest src/app/mobile/guards src/app/mobile/devices src/app/auth/guards --maxWorkers=1` | ❌ W0 | ⬜ pending |
| 111-04-T1 | 04 | 4 | D-03, D-07 | T-111-20, T-111-22 | prices = web list price; stock from stock_balances; 404 foreign ids | unit | `cd api-ventago && npx jest src/app/mobile/pos/context src/app/mobile/stock src/app/mobile/catalog --maxWorkers=1` | ❌ W0 | ⬜ pending |
| 111-04-T2 | 04 | 4 | D-05, D-06, D-07, D-12, D-18, D-21 | T-111-18, T-111-19, T-111-21, T-111-23, T-111-23b | caja by box; never 2nd session; sinEmitir no window; mpQrDisponible; branches (store-only, for reports selector); no attendance gate (Q5) | unit | `cd api-ventago && npx jest src/app/mobile/pos/context src/app/payment-methods --maxWorkers=1` | ❌ W0 | ⬜ pending |
| 111-06-T1 | 06 | 4 | D-11 | T-111-34 | never writes global_clients; fiscal/opciones (provinces DB ids + web IVA strings, fs-read control group); fiscal check before cobro | unit | `cd api-ventago && npx jest src/app/mobile/pos/fiscal/pos-clients.service.spec.ts --maxWorkers=1` | ❌ W0 | ⬜ pending |
| 111-06-T2 | 06 | 4 | D-10, D-12 | T-111-32, T-111-35 | no re-issue after uncertainty; emit accepts no_solicitada; sin-emitir list no window | unit | `cd api-ventago && npx jest src/app/mobile/pos/fiscal/fiscal-estado.spec.ts src/app/mobile/pos/fiscal/pos-fiscal.service.spec.ts --maxWorkers=1` | ❌ W0 | ⬜ pending |
| 111-06-T3 | 06 | 4 | D-11, D-13, D-14 | T-111-33, T-111-36, T-111-38 | PDF only with CAE; non-fiscal legend; IDOR 404; fiscal/opciones route guarded crear-venta/create | unit | `cd api-ventago && npx jest src/app/mobile/pos/fiscal --maxWorkers=1` | ❌ W0 | ⬜ pending |
| 111-07-T1 | 07 | 4 | D-15 | T-111-41 | type NULL expressible; existing callers unchanged; mutation ?? | unit + mutation | `cd api-ventago && npx jest src/app/products/productStock.ingreso-productos.spec.ts --maxWorkers=1` | ✅ base spec exists | ⬜ pending |
| 111-07-T2 | 07 | 4 | D-06, D-15 | T-111-39, T-111-40, T-111-42, T-111-42b, T-111-43 | step 0 read-only prod count of delete-without-update grants (0 on 2026-10-15; non-zero → user decision, no seed); tenant check, idempotent, editar-stock-de-producto/update | unit | `cd api-ventago && npx jest src/app/mobile/pos/stock --maxWorkers=1` | ❌ W0 | ⬜ pending |
| 111-07-T3 | 07 | 4 | D-15 | T-111-39, T-111-40 | ledger type NULL + view counts; mutation type:null | itest + mutation | `cd api-ventago && npx jest --config ./test/itest/jest-itest.json --runInBand src/app/mobile/pos/stock/pos-stock.itest.ts` | ❌ W0 | ⬜ pending |
| 111-08-T1 | 08 | 4 | D-12, D-16 | T-111-45, T-111-48 | store-TZ day (22:30 BA); day report sin-emitir per day (explicit window); same services as web | unit | `cd api-ventago && npx jest src/app/mobile/pos/reports/pos-reports.service.spec.ts --maxWorkers=1` | ❌ W0 | ⬜ pending |
| 111-08-T2 | 08 | 4 | D-06, D-16 | T-111-46, T-111-47 | saldoFinal not recomputed; guards = web | unit | `cd api-ventago && npx jest src/app/mobile/pos/reports --maxWorkers=1` | ❌ W0 | ⬜ pending |
| 111-09-T1 | 09 | 4 | D-04 | T-111-53 | pure helpers; SWR hooks for devices/boxes/branch agents (reference data not via useEffect+get) | web jest | `cd ventago-app && npx jest src/__tests__/celulares.spec.ts --maxWorkers=1` | ❌ W0 | ⬜ pending |
| 111-09-T2 | 09 | 4 | D-04, D-14 | T-111-50, T-111-51, T-111-52 | server 403 shown; confirm revoke | tsc + eslint + jest | `cd ventago-app && npx tsc --noEmit -p tsconfig.json && npx eslint <touched files> --max-warnings=0 && npx jest src/__tests__/celulares.spec.ts --maxWorkers=1` | n/a | ⬜ pending |
| 111-17-T1 | 17 | 4 | D-07, D-08, D-21 | T-111-90..95 | MP QR via web's MpQrService with device scope; store+terminal filter; one-sale check; no auto-cancel | unit | `cd api-ventago && npx jest src/app/mobile/pos/mp/pos-mp.service.spec.ts --maxWorkers=1` | ❌ W0 | ⬜ pending |
| 111-17-T2 | 17 | 4 | D-06, D-21 | T-111-91, T-111-96 | web-equal roles; mutation: drop terminal filter | unit + mutation | `cd api-ventago && npx jest src/app/mobile/pos/mp src/app/mercadopago --maxWorkers=1` | ❌ W0 | ⬜ pending |
| 111-05-T1 | 05 | 5 | D-08, D-12, D-17, D-21 | T-111-26 | audit cols + mpPaymentIntentId + invoice_pending_at in same tx; web unchanged (control) | unit + mutation | `cd api-ventago && npx jest src/app/sales/sales-create.service.spec.ts src/app/sales/sale-idempotency.service.spec.ts src/app/sales/sales-create-payment-boundary.spec.ts --maxWorkers=1` | ✅ base specs exist | ⬜ pending |
| 111-05-T2 | 05 | 5 | D-03, D-05, D-08, D-10, D-14, D-21 | T-111-24..31d | replay before pre-checks with defined REPLAY_OPTS (no MP validation on completed keys); price/total re-check; MP intent validated; no promo/source override (Q10/Q11); suppressAutoPrint | unit | `cd api-ventago && npx jest src/app/mobile/pos/sales --maxWorkers=1` | ❌ W0 | ⬜ pending |
| 111-05-T3 | 05 | 5 | D-03, D-05, D-08, D-21 | T-111-25, T-111-27, T-111-30, T-111-31b, T-111-31c, T-111-31d | 2-box drawer proof; no print; MP single use; replay after caja close; MP sale replay = same sale; mutations ×4 | itest + mutation | `cd api-ventago && npx jest --config ./test/itest/jest-itest.json --runInBand src/app/mobile/pos/sales/pos-sales.itest.ts` | ❌ W0 | ⬜ pending |
| 111-10-T1 | 10 | 5 | D-09, D-11, D-21 | T-111-54, T-111-57, T-111-57b | 401 never wipes drafts; offline ≠ business error; unknown MP status ≠ approved; FiscalOpcionesResponse + context.branches parsed | flutter | `cd ventago-movil && flutter test test/api_error_test.dart test/contracts_parse_test.dart` | ❌ W0 | ⬜ pending |
| 111-10-T2 | 10 | 5 | D-05, D-06, D-12 | T-111-56 | header caja/conexión/sin-emitir (no day); perm-aware tabs | flutter widget | `cd ventago-movil && flutter test test/home_shell_test.dart` | ❌ W0 | ⬜ pending |
| 111-16-T1 | 16 | 6 | D-04, D-06, D-09 | T-111-55, T-111-58, T-111-58c | app flag on login; no branch screen; pending→approved without relogin; drafts kept | flutter widget | `cd ventago-movil && flutter test test/device_flow_test.dart` | ❌ W0 | ⬜ pending |
| 111-16-T2 | 16 | 6 | D-22 | T-111-58b | app calls only /mobile/auth/login + /mobile/pos/* (gate with control groups) | flutter | `cd ventago-movil && flutter analyze && flutter test` | ❌ W0 | ⬜ pending |
| 111-11-T1 | 11 | 7 | D-09 | T-111-60 | cart persists across kill; int centavos | flutter unit | `cd ventago-movil && flutter test test/cart_model_test.dart test/cart_store_test.dart` | ❌ W0 | ⬜ pending |
| 111-11-T2 | 11 | 7 | D-07, D-09 | T-111-59, T-111-62 | server cart check before cobro | flutter | `cd ventago-movil && flutter analyze && flutter test` | ❌ W0 | ⬜ pending |
| 111-11-T3 | 11 | 7 | D-11 | T-111-61 | Cobrar gated by server fiscal/check; province/IVA options only from /mobile/pos/fiscal/opciones (no web /provinces) | flutter | `cd ventago-movil && flutter analyze && flutter test` | ❌ W0 | ⬜ pending |
| 111-12-T1 | 12 | 8 | D-15, D-09 | T-111-63, T-111-64 | key persisted before POST; by-key recovery; 2 s repeat | flutter unit | `cd ventago-movil && flutter test test/ingreso_model_test.dart` | ❌ W0 | ⬜ pending |
| 111-12-T2 | 12 | 8 | D-16 | T-111-66 | captions per number; branch selector from context.branches (not stock/branches) | flutter unit | `cd ventago-movil && flutter test test/reportes_parse_test.dart` | ❌ W0 | ⬜ pending |
| 111-13-T1 | 13 | 8 | D-08, D-21 | T-111-67, T-111-67b, T-111-67c | kill-after-send → same sale; EN_CURSO/CLAVE_CONFLICTO/unknown keep key; MP QR machine; kill-after-MP-approval → one sale | flutter unit | `cd ventago-movil && flutter test test/payment_math_test.dart test/checkout_machine_test.dart test/mp_qr_machine_test.dart` | ❌ W0 | ⬜ pending |
| 111-13-T2 | 13 | 8 | D-05, D-07, D-08, D-09, D-18, D-21 | T-111-72, T-111-72b | confirm only when closed+online+caja open; MP panel (no Verificada); recovery list; no QR package | flutter + grep | `cd ventago-movil && flutter analyze && flutter test` | ❌ W0 | ⬜ pending |
| 111-19-T1 | 19 | 9 | D-10, D-12 | T-111-68 | no 2nd CAE; no_solicitada → Emitir; unknown → verificar | flutter unit | `cd ventago-movil && flutter test test/fiscal_state_test.dart` | ❌ W0 | ⬜ pending |
| 111-19-T2 | 19 | 9 | D-10, D-12, D-13, D-14 | T-111-69, T-111-70 | /invoice and /print only from onPressed; temp PDF deleted; no wa.me; sin-emitir list w/o day | flutter + grep | `cd ventago-movil && flutter test && ! grep -rn 'wa.me' lib` | ❌ W0 | ⬜ pending |
| 111-14-T1 | 14 | 10 | D-03..D-22 (ship) | T-111-76, T-111-78, T-111-78b, T-111-78c | gate (indexes valid, no pending permission decision, CODEX read, tests); users measured right before; api pushed; SHA in successful Jenkins build; prod routes 401 not 404 | curl | `curl -s -o /dev/null -w '%{http_code}' https://newapi.coolsistema.com/api/mobile/pos/context` (401) + `/nope` (404) | n/a | ⬜ pending |
| 111-14-T2 | 14 | 10 | D-04 (web) | T-111-76, T-111-78 | web only after API_LIVE; users re-measured; app repo + gitlink pushed in order | git + chunk grep | `git -C ventago-app log origin/main -1` + chunk grep `mobile/devices` | n/a | ⬜ pending |
| 111-14-T3 | 14 | 10 | D-03..D-22 | T-111-77 | UAT sheet: 14 steps + 14b degraded MP path × 2 platforms, decisions, read-only SQL | grep | `for n in 1..14 14b: grep -q "Step $n " 111-UAT.md` | n/a | ⬜ pending |
| 111-20-T1 | 20 | 11 | D-02 | T-111-73, T-111-75 | keystore outside repo; signed APK; iOS release compiles; no secrets in git | flutter + shell | `cd ventago-movil && flutter test && test -f build/app/outputs/flutter-apk/app-release.apk` | n/a | ⬜ pending |
| 111-20-T2 | 20 | 11 | D-20 | T-111-74 | user signs; no credentials in repo | checkpoint | `ls ventago-movil/build/ios/ipa/*.ipa` | n/a | ⬜ pending |
| 111-20-T3 | 20 | 11 | D-03..D-22 | T-111-77, T-111-79 | UAT on real devices (incl. D-21 MP, 14b degraded path, D-22 revoked token curl) | manual + read-only SQL | `grep -c '| pass' 111-UAT.md` | n/a | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `api-ventago/src/app/mobile/devices/*.spec.ts`, `guards/mobile-terminal.guard.spec.ts`
- [ ] `api-ventago/src/app/mobile/pos/*.spec.ts` incl. `pos/mp/*.spec.ts` (+ one `*.itest.ts` for drawer/terminal/MP single use)
- [ ] `api-ventago/src/app/auth/token-client.spec.ts`, `auth/strategies/jwt.strategy.spec.ts`
- [ ] Migration SQL (D-17 columns + device table) applied local 5432 + prod 5434, schema intel regenerated
- [ ] Flutter project scaffold (new private repo, submodule — D-19) with `flutter test` + CI job
- [ ] Fixtures: store/branch with ≥2 boxes; one store with `allowSaleWithoutStock=false`

---

## Manual-Only Verifications

See `111-RESEARCH.md` § Manual UAT (12 steps) as extended to 14 steps + 14b (sheet written in Plan 14 Task 3, run in Plan 20 Task 3): device approval, PC session untouched, caja open/closed, mixed payment, kill-after-confirm, AFIP emit/reject/retry, share PDF (Android + iPhone), print once, ingreso, reports vs web after 21:00 BA, revoke → cut off on the next request + phone token refused on web routes by curl (D-22), role matrix incl. admin/gerente login (D-06), MP dynamic QR sale + expire/cancel (D-21), kill after MP approval → one sale (D-21); 14b degraded path: app data lost after MP approval → «Avisá al encargado», no second charge.
Staging is NOT a prod copy — money/schema checks are not passed on staging alone.

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references (each ❌ file is created by the task that lists it)
- [x] No watch-mode flags
- [ ] Feedback latency < 60s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
