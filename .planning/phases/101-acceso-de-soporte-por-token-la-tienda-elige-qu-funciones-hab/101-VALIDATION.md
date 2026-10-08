---
phase: 101
slug: acceso-de-soporte-por-token-la-tienda-elige-qu-funciones-hab
status: planned
nyquist_compliant: true
wave_0_complete: false
revised: 2026-10-08
created: 2026-10-08
---

# Phase 101 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution. 근거: 101-RESEARCH.md «Validation Architecture».

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | jest 29 + ts-jest (api) · jest (app) |
| **Config file** | `api-ventago/package.json` `"jest"` · `ventago-app/package.json` `"jest"` |
| **Quick run command** | `cd api-ventago && env -u NODE_OPTIONS npx jest --maxWorkers=1 <모듈 디렉터리 하나>` |
| **Full suite command** | 로컬에서 돌리지 않는다(메모리 폭주). 영역 디렉터리 순차: `src/app/auth/guards` · `src/app/agente` · `src/common/tenant` · `src/app/support` · `src/app/online-orders` · `src/app/branch` |
| **Estimated runtime** | 디렉터리당 ~10–30 s |

금지: `--findRelatedTests` · `--runInBand`(itest 설정 `test/itest/jest-itest.json` 제외) · 여러 디렉터리 동시 지정. grep 은 `-a`. 출력이 비면 「안 돈 것」.
★ 검증 명령은 **jest 종료코드로 판정**한다 — `| grep "Tests:"` 파이프 금지(파이프가 실패를 덮는다, verify-build-by-exit-code-not-grep).
  여러 명령은 `&&` 로 잇는다. jest 는 실패 시·테스트 0건 시 ≠0 으로 끝난다(`--passWithNoTests` 금지).

---

## Sampling Rate

- **After every task commit:** 변경 모듈 디렉터리 jest 1개 + `tsc --noEmit` (커밋 게이트가 같은 범위)
- **After every plan wave (wave 2 부터):** 위 영역 디렉터리 순차 + `bash api-ventago/scripts/mutantes-agente.sh` — 스크립트는 **101-03 Task 3(wave 2)** 에서 생긴다(초기 돌연변이 8개). wave 1 뒤에는 돌연변이를 돌리지 않는다(대상 가드가 아직 없다). 101-18 이 ≥18 개로 채운다. 스크립트는 생존·미적용·컴파일 실패가 있으면 exit ≠0
- **Before `/gsd:verify-work`:** 위 전부 green + 로컬/운영 마이그레이션 양쪽 확인 + 에이전트 계정 동적 화면 순회
- **Max feedback latency:** 30 s

---

## Per-Task Verification Map

| Decision | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|----------|-----------------|-----------|-------------------|-------------|--------|
| D-01/D-03 | 미표시 핸들러 403 · `X-Store-Id` 동시 400 · request.user 매장 치환 | unit | `npx jest --maxWorkers=1 src/app/auth/guards` | ✅ `jwt-global.guard.spec.ts` 확장 | ⬜ pending |
| D-02 | 새 alcance 도 교집합 | unit | `npx jest --maxWorkers=1 src/app/agente` | ✅ `agente.spec.ts` 확장 | ⬜ pending |
| D-05 | 다중 scope — 일부 일치로 통과, 일치 목록 반환 | unit | `npx jest --maxWorkers=1 src/common/tenant` | ✅ `agent-grant.spec.ts` 갱신 | ⬜ pending |
| D-01+FG | `FunctionPermissionGuard` 에이전트 분기 + 대조군(grant 없는 에이전트 403) | unit | `npx jest --maxWorkers=1 src/app/auth/guards` | ✅ 확장 | ⬜ pending |
| D-04 | 보기전용 scope 는 GET(+허용 POST 목록)만 · Public∧AgentScope 금지 · 런타임 열거(CrudController 상속 포함) | unit | `npx jest --maxWorkers=1 src/app/auth/guards/agent-readonly-scopes.spec.ts` | 101-03 Task 2 가 만든다 | ⬜ pending |
| D-10 | 비밀 필드 부재(`confirmToken`·`branch.apiKey`·`branch_agents.api_key`(printers/thermal-agents)·`pinHash`…) + 대조군 · 제외 목록 핸들러에 scope 없음 | unit | 영역 spec(`agent-readonly-scopes.{venta,comunes,comunes-operacion,admin-config,admin}.spec.ts`) + `src/app/online-orders` · `src/app/branch` · `src/app/print` | 101-04 · 101-05~09 가 만든다 | ⬜ pending |
| D-22 | AFIP 회계 다운로드(iibb·xlsx·excel·iva-digital)는 ver_facturas 없음 · grant 유효 에이전트 → 403 `AGENT_SCOPE_DENIED` | unit | `npx jest --maxWorkers=1 src/app/auth/guards/agent-readonly-scopes.venta.spec.ts` | 101-05 Task 2 | ⬜ pending |
| D-18 | anular·canjear 단일 조건부 UPDATE · 동시 실행 시 한쪽만 효과 | itest(PG 로컬) | `npx jest --config ./test/itest/jest-itest.json --runInBand src/app/agente/agente-anular-canje.itest.ts` | 101-10 Task 2 | ⬜ pending |
| D-19 | 메뉴 기능은 admin 역할만(기존 seed·신규 매장·/me 백필) | unit | `npx jest --maxWorkers=1 src/app/store` | 101-02 Task 3 | ⬜ pending |
| D-08/D-09 | 비-GET 중앙 차단 · 403 코드 구분(scope 밖 vs grant 무효) · 화면 안내 | unit (app, 순수 `.ts`) | `cd ventago-app && env -u NODE_OPTIONS npx jest src/__tests__/<파일>` | 101-12 가 만든다 | ⬜ pending |
| D-11/D-23 | 게이트웨이 agent join · 만료 · 철회 · 교차매장 거부 · WS 감사 이벤트 · FAB 세션(grant_id NULL) 비노출 | unit (하네스) | `npx jest --maxWorkers=1 src/app/support` | 101-11 가 만든다 | ⬜ pending |
| 돌연변이 | 가드 분기 삭제·scope 를 POST 에 부착·교집합→합집합·비밀 필드 노출·원자성·메뉴 seed 등 ≥18 | script | `bash api-ventago/scripts/mutantes-agente.sh` (exit ≠0 = 실패) | 101-03 Task 3 (8개) → 101-18 (≥18) | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

별도 wave 0 은 두지 않는다 — 각 spec 은 그것을 필요로 하는 계획의 첫 TDD task 가 만든다(아래 위치). `wave_0_complete` 는 실행 전이라 false.
- [ ] `api-ventago/src/app/auth/guards/agent-readonly-scopes.spec.ts` — D-04/D-10 열거·제외·비밀 → **101-03 Task 2 (wave 2)**, 영역 spec 들(101-05~09)보다 먼저
- [ ] `api-ventago/src/app/support/support.gateway.agent.spec.ts` — D-11 (Nest 하네스) → **101-11 Task 2 (wave 2)**
- [ ] `api-ventago/test/mutantes/agente-ver.json` + `api-ventago/scripts/mutantes-agente.sh` (`mutantes-wp.sh` 복제) → **101-03 Task 3 (wave 2)** — 종전엔 마지막 wave 에 있어 「wave 마다 돌연변이」 요건과 모순이었다
- [ ] `ventago-app/src/__tests__/` — 에이전트 403 안내·새 alcance 라벨·모드 판정 순수 함수 → **101-12 (wave 1)**
- [ ] `api-ventago/src/app/agente/agente-anular-canje.itest.ts` — D-18 경합 → **101-10 Task 2 (wave 2)**

---

## Manual-Only Verifications

| Behavior | Decision | Why Manual | Test Instructions |
|----------|----------|------------|-------------------|
| 화면별 호출 API 인벤토리 보정 | D-07 | 실제 화면 호출에 의존 | 보기전용 grant 로 각 화면 순회 → `support_access_events` 의 `denegado` 집계 → 공통 API 누락분 반영 |
| 마이그레이션 양쪽 적용 | — | 운영 DDL 은 사용자 승인 | `\d agent_action_policies` 로컬 5432 / 운영 5434 대조 |
| 원격 세션 실사용 | D-11 | 기능 플래그가 운영에서 꺼져 있고 실사용 0건 | 플래그 켠 환경에서 매장 계정 + 에이전트로 시작→보기→15분 만료→철회 |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify (checkpoints: grep sobre su SUMMARY) — revisado 2026-10-08
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Cada referencia MISSING tiene el plan/task que la crea (lista de arriba)
- [x] No watch-mode flags; verify por exit code (sin `| grep`)
- [ ] Feedback latency < 30s (se mide en ejecución)
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
