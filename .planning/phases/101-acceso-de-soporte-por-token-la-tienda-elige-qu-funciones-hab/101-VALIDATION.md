---
phase: 101
slug: acceso-de-soporte-por-token-la-tienda-elige-qu-funciones-hab
status: draft
nyquist_compliant: false
wave_0_complete: false
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

금지: `--findRelatedTests` · `--runInBand` · 여러 디렉터리 동시 지정. grep 은 `-a`. 출력이 비면 「안 돈 것」.

---

## Sampling Rate

- **After every task commit:** 변경 모듈 디렉터리 jest 1개 + `tsc --noEmit` (커밋 게이트가 같은 범위)
- **After every plan wave:** 위 영역 디렉터리 순차 + `bash api-ventago/scripts/mutantes-agente.sh`
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
| D-04 | 보기전용 scope 는 GET(+허용 POST 목록)만 · Public∧AgentScope 금지 · 런타임 열거(CrudController 상속 포함) | unit | `npx jest --maxWorkers=1 src/app/auth/guards/agent-readonly-scopes.spec.ts` | ❌ W0 | ⬜ pending |
| D-10 | 비밀 필드 부재(`confirmToken`·device `apiKey`·`branch.apiKey`…) + 대조군 · 제외 목록 핸들러에 scope 없음 | unit | 〃 + `src/app/online-orders` · `src/app/branch` | ❌ W0 | ⬜ pending |
| D-08/D-09 | 비-GET 중앙 차단 · 403 코드 구분(scope 밖 vs grant 무효) · 화면 안내 | unit (app, 순수 `.ts`) | `cd ventago-app && env -u NODE_OPTIONS npx jest src/__tests__/<파일>` | ❌ W0 | ⬜ pending |
| D-11 | 게이트웨이 agent join · 만료 · 철회 · 교차매장 거부 · WS 감사 이벤트 | unit (하네스) | `npx jest --maxWorkers=1 src/app/support` | ❌ W0 | ⬜ pending |
| 돌연변이 | 가드 분기 삭제·scope 를 POST 에 부착·교집합→합집합·비밀 필드 노출 4종+ | script | `bash api-ventago/scripts/mutantes-agente.sh` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `api-ventago/src/app/auth/guards/agent-readonly-scopes.spec.ts` — D-04/D-10 열거·제외·비밀
- [ ] `api-ventago/src/app/support/support.gateway.agent.spec.ts` — D-11 (Nest 하네스)
- [ ] `api-ventago/test/mutantes/agente-ver.json` + `api-ventago/scripts/mutantes-agente.sh` (`mutantes-wp.sh` 복제)
- [ ] `ventago-app/src/__tests__/` — 에이전트 403 안내·새 alcance 라벨·모드 판정 순수 함수

---

## Manual-Only Verifications

| Behavior | Decision | Why Manual | Test Instructions |
|----------|----------|------------|-------------------|
| 화면별 호출 API 인벤토리 보정 | D-07 | 실제 화면 호출에 의존 | 보기전용 grant 로 각 화면 순회 → `support_access_events` 의 `denegado` 집계 → 공통 API 누락분 반영 |
| 마이그레이션 양쪽 적용 | — | 운영 DDL 은 사용자 승인 | `\d agent_action_policies` 로컬 5432 / 운영 5434 대조 |
| 원격 세션 실사용 | D-11 | 기능 플래그가 운영에서 꺼져 있고 실사용 0건 | 플래그 켠 환경에서 매장 계정 + 에이전트로 시작→보기→15분 만료→철회 |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
