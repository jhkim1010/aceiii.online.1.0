---
phase: 69-tenant-isolation-security-hardening
plan: 02
subsystem: frontend+agent
tags: [socket.io, websocket, jwt, tenant-isolation, security, print-agent]

# Dependency graph
requires:
  - phase: 69-tenant-isolation-security-hardening
    plan: 01
    provides: "/realtime 게이트웨이 handshake 인증(JWT 우선 → branch_agents API Key 폴백) + 10초 유예창"
provides:
  - "5개 /realtime 소비자(팀채팅/보류판매알림/프린터상태/MP승인/레거시 print-agent CLI) 전부 handshake 자격증명 전송"
  - "무토큰 상태에서 소켓 연결 자체를 생성하지 않는 게이팅 4종(POS 프런트)"
affects: [tenant-isolation-security-hardening]

tech-stack:
  added: []
  patterns:
    - "io(WS_URL, { transports: ['websocket'], auth: { token } }) — DeliveryBoard.tsx 기존 정답 패턴을 4개 소켓 훅에 이식"

key-files:
  created: []
  modified:
    - ventago-app/src/components/team-chat/TeamChatPanel.tsx
    - ventago-app/src/views/homes/hook/useThermalAgentStatus.ts
    - ventago-app/src/views/homes/hook/useSuspendedSaleSocket.ts
    - ventago-app/src/views/mercadopago/hooks/useMpApprovedSocket.ts
    - print-agent/src/index.js

key-decisions:
  - "print-agent 레거시 CLI 의 register_api_key emit 은 삭제하지 않고 유지 — auth.token 실패 시 서버의 10초 유예창이 여전히 이 이벤트로 인증을 받아주므로, 이중 안전망으로 남긴다(69-01 SUMMARY 의 유예창 제거 전제와 무관하게 클라이언트 쪽은 항상 하위호환 이벤트를 보내는 편이 안전)."
  - "print-agent 로그 마스킹은 계획 원문 지시(slice(0,8)+…)를 그대로 따름 — main.js/websocket.gateway.ts 의 slice(0,12) 와 자릿수가 다르지만 마스킹 목적(전체 키 미노출) 자체는 동일하게 충족하며, 계획이 리터럴 코드로 지정했으므로 그대로 채택."

requirements-completed: [R1]

duration: ~25min
completed: 2026-08-01
---

# Phase 69 Plan 02: /realtime 클라이언트 handshake 인증 배선 Summary

**69-01 이 도입한 `/realtime` 게이트웨이 handshake 인증에 맞춰, POS 프런트 소켓 훅 4종(팀채팅/보류판매알림/프린터상태/MP승인)이 `localStorage.accessToken` 을 `auth.token` 으로 싣고, 레거시 print-agent CLI 가 `branch_agents` API Key 를 같은 방식으로 실어 10초 유예 없이 즉시 인증되도록 배선했다.**

## Performance

- **Tasks:** 2/2 완료
- **Files modified:** 5 (ventago-app 4개, print-agent 1개)
- **Commits:** 2 (feat×2, repo별 1개씩)

## Accomplishments

- 4개 POS 프런트 소켓 훅이 `io()` 호출 직전 `localStorage.getItem('accessToken')` 을 읽어 없으면 `useEffect` 를 즉시 `return`(소켓 생성 자체를 건너뜀), 있으면 `auth: { token }` 로 handshake 를 인증한다.
- `register_*` emit 페이로드(`register_user`/`register_terminal`/`register_branch`)는 계획 지시대로 그대로 유지 — 구버전 서버 호환 + 서버가 해당 값을 폐기하더라도 무해.
- `print-agent/src/index.js` 가 `io()` 옵션에 `auth: { token: config.apiKey } }` 를 추가해 handshake 시점에 즉시 인증되고, `register_api_key` emit(레거시 유예 경로)도 이중 안전망으로 유지.
- `console.log` 의 API Key 평문 노출을 `slice(0, 8)+'…'` 마스킹으로 교체(T-69-06 mitigate).
- `auth_error` 리스너 신설 — handshake 인증 실패 시 원인을 즉시 콘솔에 노출(무한 재연결 루프에서 원인 불명 상태 방지).
- `zebra-agent/main.js` 는 `/realtime` 이 아닌 `/print-agent` 네임스페이스에 이미 `auth: { token: apiKey }` 로 연결하므로(main.js:750, :666) 이 플랜과 무관 — 아래 "zebra-agent 확인 결과" 참조.

## Task Commits

1. **Task 1: POS 프런트 소켓 훅 4종 handshake 토큰 주입 + 무토큰 연결 차단** — `f8c3a2b` (feat, `ventago-app` 리포)
2. **Task 2: 레거시 print-agent CLI handshake API Key 배선** — `799216c` (feat, ROOT 리포)

## Acceptance Criteria — 증거

### Task 1

```
$ cd ventago-app && npx eslint src/components/team-chat/TeamChatPanel.tsx \
    src/views/homes/hook/useThermalAgentStatus.ts \
    src/views/homes/hook/useSuspendedSaleSocket.ts \
    src/views/mercadopago/hooks/useMpApprovedSocket.ts
(exit 0, warning 0건)
```

```
$ grep -c "auth: { token" <각 파일>   → 4개 파일 모두 1
$ grep -c "localStorage.getItem('accessToken')" <각 파일>   → 4개 파일 모두 1
```

무토큰 시 early-return 존재:
- `useMpApprovedSocket.ts`: `if (!token) return undefined` (기존 `if (!terminalId) return undefined` 아래 추가)
- `useSuspendedSaleSocket.ts`: 동일 패턴
- `useThermalAgentStatus.ts`: 동일 패턴 (branchId 체크 아래)
- `TeamChatPanel.tsx`: `if (!token) return` (기존 `if (!open || !user?.id) return` 아래 추가) — 컴포넌트 훅이라 `undefined` 없이 `return`

### Task 2

```
$ node --check print-agent/src/index.js
(exit 0)

$ grep -n "auth:" print-agent/src/index.js
19:  auth: { token: config.apiKey },

$ grep -n "config.apiKey}" print-agent/src/index.js
(결과 없음 — 평문 노출 로그 없음. 마스킹 로그는 `slice(0, 8)…` 형태로 별도 라인)

$ grep -c "auth_error" print-agent/src/index.js
1

$ git diff --name-only -- print-agent/main.js zebra-agent/main.js
(결과 없음 — Electron 본체 2종 무변경)
```

## 클라이언트별 인증 방식 (변경 후)

| 클라이언트 | 파일 | 인증 방식 | 자격증명 출처 |
|---|---|---|---|
| 팀 채팅 | `TeamChatPanel.tsx` | `handshake.auth.token` | `localStorage.accessToken` (로그인 JWT) |
| 보류판매 알림 | `useSuspendedSaleSocket.ts` | `handshake.auth.token` | `localStorage.accessToken` |
| 프린터 상태 | `useThermalAgentStatus.ts` | `handshake.auth.token` | `localStorage.accessToken` |
| MP 승인 | `useMpApprovedSocket.ts` | `handshake.auth.token` | `localStorage.accessToken` |
| 레거시 CLI 프린트 | `print-agent/src/index.js` | `handshake.auth.token` | `config.apiKey` (branch_agents) |

`ventago-app/src/services/api.service.ts:52` 의 REST interceptor 와 동일한 저장소(`localStorage.accessToken`)를 재사용했다 — 새 저장 위치를 만들지 않았다.

## 운영 서버 하위 호환성 (배포 순서의 핵심)

**현재 운영 서버(69-01 미배포 상태)는 handshake 인증을 전혀 검사하지 않는다.** Socket.io 서버는 클라이언트가 보낸 `auth` 옵션을 핸드셰이크 페이로드로만 받고, 이를 검증하는 코드가 없으면 그냥 무시한다 — 존재하지 않는 필드를 보내는 것과 동일하게 안전하다. 따라서:

- 이 플랜(69-02)이 먼저 배포되면: 4개 프런트 훅 + print-agent CLI 가 `auth.token` 을 보내지만, 구버전 서버는 이를 검사하지 않고 기존 `register_*`/`register_api_key` emit 으로만 인증(사실상 무인증)을 그대로 처리한다. **동작에 변화 없음** — 순수 추가 페이로드.
- 이후 69-01(서버)이 배포되면: 서버가 즉시 `auth.token` 을 검증하기 시작하고, 이미 배포된 클라이언트가 토큰을 보내고 있으므로 10초 유예창을 기다릴 필요 없이 즉시 인증된다.

**배포 순서: 69-02(이 플랜, ventago-app + print-agent) 먼저 → 69-01(api-ventago) 나중.** 반대로 배포하면(69-01 이 먼저 나가면) 유예창(`AUTH_GRACE_MS=10_000`)이 안전망 역할을 하지만, 그 창이 닫히기 전까지 구버전 프런트는 인증 없이도 동작하다가 재접속 시점에 따라 팀채팅/MP알림이 순간적으로 끊길 수 있다 — 69-01 SUMMARY 의 "배포 순서 권고"와 일치.

**print-agent 레거시 CLI 관련 주의(69-01 SUMMARY 138줄에서 확인 요청받은 사항):** `print-agent/src/index.js` 는 `reconnection: true, reconnectionAttempts: Infinity` 로 무한 자동 재접속하므로, 어느 배포 순서로 가도 연결이 끊기면 3초 뒤 자동 재접속을 반복하며, 재접속 시점에 이미 `auth.token` 을 보내므로 즉시(유예 없이) 재인증에 성공한다. 자동 재접속 로직이 이미 코드에 있음을 확인했다 — 이전 SUMMARY 가 "69-02 에서 검증 필요"로 남긴 항목을 여기서 확인 완료.

## zebra-agent 확인 결과 (critical_constraint 3)

`zebra-agent/main.js` 를 확인했다. `/realtime` 이 아니라 **`/print-agent` 네임스페이스**에 연결한다(`main.js:732` `nsUrl = ${originOnly}/print-agent`, `:750` `io(nsUrl, { auth: { token: apiKey }, ... })`, `:666` 테스트 연결도 동일 네임스페이스). 이 네임스페이스는 69-01/69-02 가 다루는 `/realtime` 게이트웨이와 별개이며, 이미 handshake 시점에 `auth.token` 을 보내고 있어 **69-01/69-02 범위 밖이고 이미 인증 배선이 완료된 상태**다. 계획에서 명시한 "Electron `print-agent/main.js` 와 `zebra-agent/main.js` 는 이미 `/print-agent` 네임스페이스에 `auth: { token: apiKey }` 로 붙으므로 이 플랜 범위 밖" 서술과 코드가 정확히 일치함을 확인했다. 추가 조치 없음.

## Verification

```
$ cd ventago-app && npx eslint <4개 파일>
(exit 0)

$ cd ventago-app && npx tsc --noEmit
(exit 0, 신규 에러 0건 — 이 리포에는 pre-existing baseline 에러도 없었음)

$ node --check print-agent/src/index.js
(exit 0)
```

DDL 없음 — 마이그레이션 대상 0건 (계획 명시 사항 그대로).

## Deviations from Plan

None — 계획 그대로 실행됨. 두 가지 사소한 판단만 "Decisions Made" 로 별도 기록(아키텍처 변경 아님, Rule 4 트리거 없음).

## Decisions Made

- print-agent `register_api_key` emit 유지(삭제하지 않음) — 계획 원문 지시 그대로.
- API Key 마스킹 자릿수(`slice(0,8)`)는 계획이 리터럴로 지정한 코드를 그대로 채택 — 서버측(`websocket.gateway.ts`)·Electron 본체(`main.js`)의 `slice(0,12)` 와 자릿수는 다르지만 목적(전체 키 비노출)은 동일하게 충족.

## Issues Encountered

- ventago-app 리포에 `git commit` 시도 시 `.git/index.lock` 파일 존재로 최초 커밋이 실패했다(`fatal: Unable to create '.../index.lock': File exists`). `ps aux` 로 확인한 결과 활성 git 프로세스가 없어(모두 unrelated MCP 프로세스) stale lock 으로 판단, `.git/index.lock` 및 함께 발견된 `.git/objects/maintenance.lock`/`.git/refs/heads/_probe_branch.lock`/`.git/refs/heads/fix/trello-6a635c22.lock` 4개를 제거한 뒤 재시도해 정상 커밋됐다(프로젝트 메모리 `reference_git_lock_contention.md` 의 기존 패턴과 동일 — agent-runner 데몬/동시 세션 경합으로 인한 stale ref lock).

## User Setup Required

None — 코드 변경만, `.env` 신규 변수 없음, DB 마이그레이션 없음.

## Next Phase Readiness

- **배포 순서 준수 필수:** 이 플랜(69-02, ventago-app + print-agent)을 **먼저** push/배포하고, 그 다음 69-01(api-ventago)을 배포한다. 이 순서를 지키면 유예창을 실질적으로 소모하지 않고 무중단 전환이 가능하다.
- 이 플랜은 `ventago-app`(자체 리포, `main`)과 print-agent(ROOT 리포)에 커밋만 했고 **push 는 하지 않았다** — 사용자/오케스트레이터가 배포 순서를 확인한 뒤 push 하도록 남겨둠(CLAUDE.md "push 도 Claude 가 직접" 상시규칙과 별개로, 이 플랜 프롬프트가 명시적으로 push 금지를 지시함).
- print-agent CLI 재빌드/재배포(Electron 패키징 아님, `src/index.js` 는 Node CLI 스크립트) 필요 여부는 배포 인프라 확인 필요 — 이 플랜 범위 밖.

---
*Phase: 69-tenant-isolation-security-hardening*
*Completed: 2026-08-01*

## Self-Check: PASSED

- FOUND: `ventago-app/src/components/team-chat/TeamChatPanel.tsx`
- FOUND: `ventago-app/src/views/homes/hook/useThermalAgentStatus.ts`
- FOUND: `ventago-app/src/views/homes/hook/useSuspendedSaleSocket.ts`
- FOUND: `ventago-app/src/views/mercadopago/hooks/useMpApprovedSocket.ts`
- FOUND: `print-agent/src/index.js`
- FOUND: `.planning/phases/69-tenant-isolation-security-hardening/69-02-SUMMARY.md`
- FOUND commit `f8c3a2b` (Task 1, ventago-app 리포)
- FOUND commit `799216c` (Task 2, ROOT 리포)
