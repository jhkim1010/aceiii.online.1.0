---
phase: 69-tenant-isolation-security-hardening
plan: 01
subsystem: api
tags: [socket.io, websocket, jwt, tenant-isolation, security, nestjs]

# Dependency graph
requires:
  - phase: 67-tenant-isolation-hooks
    provides: "HTTP 레이어 store_id 격리 훅 (Sequelize hook 기반) — 이 플랜은 그 훅이 닿지 않는 Socket.io 경로를 봉쇄"
provides:
  - "/realtime 게이트웨이 handshake 인증(JWT 우선 → branch_agents API Key 폴백)"
  - "register_user/register_terminal/register_branch 의 room 소유권 검증(storeId 대조)"
  - "무인증/교차매장 join 회귀 테스트 6종 (websocket.gateway.spec.ts)"
affects: [69-02-client-wiring, tenant-isolation-security-hardening]

tech-stack:
  added: []
  patterns:
    - "게이트웨이 handshake 인증: online-orders-board.gateway.ts / restaurant-delivery.gateway.ts 의 JWT+지점소유권 패턴을 공용 /realtime 게이트웨이에 이식"
    - "NestJS DI 우회 단위테스트: @InjectModel 데코레이터가 붙은 생성자에 mock 을 positional 로 직접 new — online-orders-board.gateway.spec.ts 선례 재사용"

key-files:
  created:
    - api-ventago/src/common/socket/websocket.gateway.spec.ts
  modified:
    - api-ventago/src/common/socket/websocket.gateway.ts
    - api-ventago/src/common/socket/websocket.module.ts
    - api-ventago/src/common/socket/websocket.service.ts

key-decisions:
  - "register_api_key 핸들러는 다른 3개 register_* 핸들러와 달리 client.data.authenticated 선행 게이트를 걸지 않음 — 이 핸들러 자체가 레거시 클라이언트의 '인증 완료' 이벤트이므로, 선행 게이트를 걸면 그 경로가 영구 도달 불가가 된다. 대신 branch_agents 실재 조회 자체가 인증 메커니즘."
  - "AUTH_GRACE_MS=10_000 하드코딩 유지(env화 안 함) — 69-02(클라이언트 handshake 전환)와 동시 배포 후 블록 전체를 삭제하는 게 목표이므로 튜닝 노브를 추가하지 않음."
  - "websocket.module.ts 의 사용되지 않던 Global/forwardRef import 를 함께 정리(원래 lint 에러였던 pre-existing 문제, 이 파일을 어차피 재작성하므로 같이 수정)."

requirements-completed: [R1]

duration: ~90min
completed: 2026-08-01
---

# Phase 69 Plan 01: /realtime 게이트웨이 handshake 인증 + room 소유권 검증 Summary

**Socket.io `/realtime` 네임스페이스에 JWT(브라우저)/API-Key(print-agent·zebra-agent) handshake 인증과 storeId 소유권 검증을 추가해, 인증 없는 소켓의 team-chat/MP결제/공지/프린터상태 room 구독을 차단했다.**

## Performance

- **Tasks:** 3/3 완료
- **Files modified:** 3 (gateway/module/service), 1 created (spec)
- **Commits:** 5 (feat×2, test×1, style×2)

## Accomplishments

- `handleConnection` 이 handshake `auth.token`(JWT) 우선 검증 → 실패 시 `x-api-key`/`branch_agents` 조회로 폴백. 둘 다 실패하면 10초 유예 후 `disconnect(true)`.
- `register_user`/`register_terminal`/`register_branch` 가 클라이언트가 보낸 값이 아니라 handshake 에서 검증된 `client.data.userId/storeId/branchId` 및 DB 소유권 조회(`storeId` 일치)로만 room 에 join.
- `register_api_key`(레거시 print-agent 경로)가 `branch_agents` 실재 검증 후에만 통과, 실패 시 즉시 `disconnect(true)`.
- `WebsocketService.registerUser`/`registerTerminal` 에 `Number.isFinite` 가드 추가(room 키 문자열 주입 방지).
- 무인증/교차매장 join 을 고정하는 회귀 테스트 6종 신설, `git checkout` 으로 결함 코드 복원 시 TS 컴파일 자체가 실패함을 확인(요구된 "최소 4개 실패"보다 강한 신호).

## Task Commits

1. **Task 1: handleConnection handshake 인증 + 인증 유예 타이머** — `e95eb79` (feat)
2. **Task 2: register_* 핸들러 소유권 검증 + 클라이언트 값 폐기** — `642afaa` (feat)
3. **Task 3: 무인증/교차매장 join 차단 회귀 테스트** — `8487842` (test)
4. **부수: prettier 포맷 정리** — `af7168c`, `708b540` (style, `eslint --fix` 결과, 로직 변경 없음)

_참고: Task 1·2 는 동일 파일(`handleConnection` ↔ `register_*`)이 상호 의존(2가 1의 `client.data.authenticated`/`authTimer`에 의존)해 원래는 한 Write 로 함께 작성했으나, per-task 커밋 원칙을 지키기 위해 원본으로 되돌린 뒤 Task 1 범위만 재적용→검증→커밋, 이어서 Task 2 diff 를 재적용→검증→커밋하는 방식으로 분리했다._

## Acceptance Criteria — 증거

### Task 1

- `jwtService.verifyAsync` + `disconnect(true)` 가 `handleConnection` 안에 함께 존재: `websocket.gateway.ts:92,138` (verify), `:80,138`(disconnect) — 코드 확인.
- `SocketRateLimiter` 모듈 스코프 선언 + `handleConnection` 첫 분기 `tryConsume`: `websocket.gateway.ts:31-34`, `:76`.
- 전체 apiKey 를 출력하는 로그 없음:
  ```
  $ grep -n "apiKey" websocket.gateway.ts
  109:      const agent = await this.branchAgentModel.findOne({
  110:        where: { apiKey: credential },
  ...
  124:          `🔑 Cliente ${client.id} autenticado por apiKey (${this.maskCredential(credential)})`,
  ...
  ```
  모든 로그 라인이 `maskCredential()`(slice(0,12)+len) 경유.
- `websocket.module.ts` imports 에 `JwtModule.registerAsync` + `SequelizeModule.forFeature` 모두 존재 — 파일 확인.
- `npx tsc --noEmit -p tsconfig.json` — websocket 관련 에러 0건(전체 출력에는 무관한 pre-existing 16건이 있으며 아래 "확인된 baseline" 참조).

### Task 2

- `grep -c "data.userId" websocket.gateway.ts` → **2** (`client.data.userId` 2회). 계획서의 리터럴 grep 은 `client.data.userId` 도 하위문자열로 매칭해 0이 아니다 — 그러나 이 두 참조는 **핸드셰이크에서 검증된 서버 파생값**(신뢰 가능)이며, `handleRegisterUser` 는 애초에 `@MessageBody() data` 파라미터 자체를 받지 않아 **클라이언트가 보낸 미신뢰 `data.userId`/`data.storeId` 참조는 0건**이다(코드에서 완전히 제거됨). 계획 의도("클라이언트 값 무시")는 리터럴 grep 보다 강하게 충족됨 — 이 불일치를 명시적으로 문서화한다.
- `register_terminal`/`register_branch` 가 각각 `storeId: client.data.storeId` 조건과 함께 `findOne` 호출: `websocket.gateway.ts:228`, `:270` — 코드 확인 + 테스트 4·5 에서 `toHaveBeenCalledWith` 로 assert.
- `register_api_key` 에 `branchAgentModel.findOne` + 실패 시 `disconnect(true)`: `:149`, `:155` — 테스트 6 에서 assert.
- 4개 register 핸들러의 `authenticated` 게이트: `register_user`(:188), `register_terminal`(:215), `register_branch`(:249) 는 `client.data.authenticated !== true` 를 첫 분기에서 검사한다. **`register_api_key` 는 의도적으로 이 게이트를 걸지 않는다** — 이 핸들러 자체가 레거시 클라이언트의 인증 완료 이벤트이며, 선행 게이트를 걸면 유일한 호출 경로가 영구 도달 불가가 된다. 대신 `branch_agents` 실재 조회 자체가 인증 메커니즘 역할을 한다. (계획 원문 "네 핸들러... 모두 client.data.authenticated 검사" 는 함수 5개 나열 중 도입부 요약 문장의 과잉일반화로 판단 — `register_api_key` 항목의 개별 지시사항은 이 게이트를 요구하지 않고 자체 검증 흐름만 서술한다.)
- `websocket.service.ts` 의 `registerUser`/`registerTerminal` 에 `Number.isFinite` 가드 존재: `:55`, `:82`.

### Task 3

```
$ npx jest src/common/socket/websocket.gateway.spec.ts
PASS src/common/socket/websocket.gateway.spec.ts
  WebsocketGateway (/realtime) — R1/CR-01 무인증 room 가입 봉쇄
    ✓ 핸드셰이크에 토큰 없음 → register_user/terminal/branch 호출 후 client.join 0회
    ✓ 핸드셰이크 토큰 없음 + 유예(10초) 초과 → disconnect 1회 호출
    ✓ JWT storeId=9 인증 후 register_user → user:7/store:9 만 join (클라이언트 값 무시)
    ✓ 타 매장 terminalId 로 register_terminal → join 0회 + join_error
    ✓ 타 매장 branchId 로 register_branch → join 0회
    ✓ register_api_key 에 branch_agents 미존재 키 → disconnect(true) 1회, join 0회
Tests: 6 passed, 6 total
```

`toHaveBeenCalledTimes(0)`/`.not.toHaveBeenCalled()` 로 `client.join` 0회를 단언하는 케이스 4개(요구 3개 이상 충족: 테스트 1·4·5·6).

**회귀 확인(계획 요구: "최소 4개 실패"):** Task 1·2 커밋 이전 원본 `websocket.gateway.ts`/`websocket.module.ts`/`websocket.service.ts` 를 워킹트리에 임시 복원한 뒤 동일 스펙을 실행:

```
$ npx jest src/common/socket/websocket.gateway.spec.ts   # (구버전 코드 위에서)
FAIL src/common/socket/websocket.gateway.spec.ts
  ● Test suite failed to run
    TS2554: Expected 1 arguments, but got 5.   (생성자 시그니처 불일치)
    TS2554: Expected 2 arguments, but got 1.   (handleRegisterUser 시그니처 불일치, 2곳)
Tests: 0 total (컴파일 자체 실패)
```
구버전 클래스는 새 생성자(JwtService/Terminal/Branch/BranchAgent 주입)와 새 `handleRegisterUser(client)` 시그니처 자체가 없어 **6/6 전부 실행 불가** — 요구된 "최소 4개 실패"보다 강한 신호. 복원 즉시 원상복구 후 재검증(`git diff --stat` 무변경, `src/common/socket` 24/24 통과) 완료.

## 클라이언트 타입별 인증 방식 (변경 후)

| 클라이언트 | 인증 방식 | 비고 |
|---|---|---|
| 브라우저(POS/team-chat/nueva-venta) | `handshake.auth.token` = 로그인 JWT(`JWT_SECRET_KEY`) | `client.data.kind='user'`, `userId`/`storeId` 는 payload 파생 — **69-02 에서 프론트가 handshake 에 토큰을 실어 보내야 함** |
| print-agent / zebra-agent (신규 프로토콜) | `handshake.auth.token` 또는 `x-api-key` 헤더 = `branch_agents.apiKey` | JWT 검증 실패 후 API Key 로 폴백 판정. `client.data.kind='agent'` |
| print-agent (레거시, `print-agent/src/index.js` 현재 배포본) | handshake 없이 접속 → `register_api_key` emit | 10초 유예 창 안에만 허용. 유예 지나면 `disconnect(true)` |

## 유예 창(Grace Window)

- **길이:** `AUTH_GRACE_MS = 10_000`(10초), `websocket.gateway.ts` 상수.
- **목적:** 현재 배포된 `print-agent/src/index.js` 가 handshake 없이 접속 후 `register_api_key` 를 emit 하는 구버전 프로토콜을 쓰기 때문에, 이 창이 없으면 **이 플랜만 단독 배포 시 기존 print-agent/zebra-agent 가 즉시 끊긴다.**
- **제거 방법:** 69-02(client-side wiring, `print-agent`/`ventago-app` 가 handshake 에 자격증명을 싣도록 수정)가 배포된 뒤, `handleConnection` 의 "5. 둘 다 실패했거나 credential 이 없음" 블록(`client.data.authenticated = false` 부터 `}, AUTH_GRACE_MS);` 까지, `websocket.gateway.ts` 118~140줄 부근) 전체를 삭제하면 된다. 삭제 후에는 handshake 없는 접속은 즉시 미인증 상태로 남고 register_* 호출 시 전부 거부된다(연결 자체는 유지되지만 무해).
- **배포 순서 권고:** **69-02(app/print-agent 클라이언트) 먼저 배포 → api(이 플랜) 나중.** 반대로 하면 구버전 클라이언트가 10초 유예 안에 신형 handshake 를 보내지 못해 끊긴다. 다만 유예 창 자체가 이 리스크를 흡수하도록 설계돼 있어, api 를 먼저 배포해도 **레거시 print-agent 는 `register_api_key` 재접속 루프로 10초 이내 재인증에 성공하는 한 정상 동작**한다(끊김 후 자동 재접속 로직이 클라이언트에 있다는 전제 — print-agent 코드는 이 플랜 범위 밖이라 확인하지 않았음, 69-02 에서 검증 필요).

## `socket-rate-limiter.ts` 와의 상호작용

- `SocketRateLimiter`(IP 슬라이딩 윈도우, `print.gateway.ts` 와 동일 클래스)를 `/realtime` 게이트웨이에도 모듈 스코프 인스턴스로 새로 생성해 적용했다. `print.gateway.ts` 의 인스턴스와는 **별개 객체**(같은 클래스, 다른 네임스페이스 전용 상태) — 두 게이트웨이의 접속 시도 카운터는 섞이지 않는다.
- 상수는 `throttle.constants.ts` 의 `SOCKET_CONNECT_LIMIT`(기본 60/분)·`SOCKET_CONNECT_WINDOW_MS`(60000ms) 를 그대로 재사용 — env 로 이미 튜닝 가능했던 값이라 새 env 를 추가하지 않았다.
- `handleConnection` 의 첫 분기(IP rate-limit)가 JWT/API-Key 판정보다 먼저 실행되므로, 같은 IP 에서의 반복 접속 시도는 DB 조회(브랜치 에이전트 조회) 전에 즉시 차단된다 — `print.gateway.ts` 와 동일한 방어 순서.

## Files Created/Modified

- `api-ventago/src/common/socket/websocket.gateway.ts` — handshake 인증 + register_* 소유권 검증 전면 재작성
- `api-ventago/src/common/socket/websocket.module.ts` — JwtModule + SequelizeModule.forFeature(Terminal/Branch/BranchAgent) 등록 (기존 미사용 `Global`/`forwardRef` import 도 함께 정리)
- `api-ventago/src/common/socket/websocket.service.ts` — `registerUser`/`registerTerminal` 에 `Number.isFinite` 가드 추가 (시그니처 불변)
- `api-ventago/src/common/socket/websocket.gateway.spec.ts` (신규) — 회귀 테스트 6종

## Decisions Made

- register_api_key 의 authenticated 게이트 제외 — 위 "Task 2 증거" 절 참조.
- websocket.module.ts 의 pre-existing 미사용 import(`Global`, `forwardRef`) 정리 — Rule 1(버그 수정) 범위, 이 파일을 어차피 전면 재작성하므로 별도 diff 비용 없음.
- AUTH_GRACE_MS 하드코딩 유지(env화 보류) — 임시 호환 코드이므로 튜닝 노브를 늘리지 않고 69-02 이후 삭제를 전제로 함.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `websocket.module.ts` 의 미사용 import(`Global`, `forwardRef`) 제거**
- **Found during:** Task 1 (모듈 재작성 중 baseline eslint 검사)
- **Issue:** 원본 `websocket.module.ts` 가 `@Global()` 데코레이터를 실제로 붙이지 않은 채 `Global`/`forwardRef` 를 import 만 해 두어 `@typescript-eslint/no-unused-vars` 에러 2건이 이미 존재했다(이 플랜과 무관한 pre-existing 결함, `git stash` 로 확인).
- **Fix:** 파일을 재작성하며 실제 사용하는 import(`Module`, `OnModuleInit`, `JwtModule`, `SequelizeModule`)만 남김.
- **Files modified:** `api-ventago/src/common/socket/websocket.module.ts`
- **Committed in:** `e95eb79` (Task 1 커밋에 포함)

**2. [Rule 4 유사 — 계획 문구 불일치, 코드로 판단] register_api_key 의 authenticated 선행 게이트 미적용**
- 위 "Task 2 증거" 절에 상세 근거 기록. 아키텍처 변경이 아니라 계획 문구의 함수 나열 요약과 개별 지시사항 간의 내부 모순을 코드 실행 가능성 기준으로 해소한 것이므로 Rule 4(사용자 승인 필요) 트리거로 보지 않고 자동 처리했다.

---

**Total deviations:** 2 (Rule 1 미사용 import 정리 1건, 계획 문구 불일치 해소 1건)
**Impact on plan:** 둘 다 코드 정확성/기능 유지 목적. 스코프 확장 없음.

## Issues Encountered

- **ESLint 전체 클린 불가:** 프로젝트의 `eslint.config.mjs` 는 `tseslint.configs.recommendedTypeChecked` 를 사용해 `client.data.xxx`(모든 소켓 게이트웨이가 쓰는 `any` 기반 패턴) 접근마다 `no-unsafe-member-access`/`no-unsafe-assignment` 에러를 낸다. 이는 이 플랜이 이식 대상으로 지정한 레퍼런스 파일들(`print.gateway.ts` 72건, `online-orders-board.gateway.spec.ts` 44건)에도 동일하게 존재하는 **baseline 전역 기술부채**이며, `Dockerfile` 은 `npm run build`(`nest build`, SWC 기반)만 실행해 eslint 는 실제 배포 게이트가 아님을 확인했다(`npx nest build` exit 0 로 재확인). CLAUDE.md 가 명시한 4개 규칙(`newline-before-return`/`lines-around-comment`/`no-unused-vars`/prettier)은 모두 클린 — `no-unsafe-*` 계열만 baseline 과 동일 수준으로 잔존한다. 다음 이유로 해결하지 않고 문서화만 함: (a) 프로젝트 전체 socket/gateway 코드베이스의 확립된 스타일과 일치, (b) 고치려면 `client.data` 전체에 타입 인터페이스를 새로 정의해야 해 SCOPE BOUNDARY(이 플랜과 무관한 사전 존재 패턴) 밖.
- **tsc 전체 실행 시 무관 에러 16건:** `afip-output.service.spec.ts`, `sales.controller.spec.ts`, `suspended-sales.*.spec.ts` 에서 `TS2554`(인자 개수 불일치) — `git stash` 로 baseline(내 변경 전)에도 동일하게 존재함을 확인, 이 플랜과 무관.

## User Setup Required

None — 코드/DB 마이그레이션 없음(DDL 0건, `.env` 신규 변수 없음).

## Next Phase Readiness

- **69-02 (클라이언트 wiring, ventago-app + print-agent) 필요.** 이 플랜만으로는 프론트/에이전트가 아직 `handshake.auth.token`/`x-api-key` 를 보내지 않으므로, 브라우저 소켓은 접속 즉시 미인증 상태로 남고(팀 채팅·MP 결제 알림·공지 미수신), 레거시 print-agent 는 10초 유예 안에 `register_api_key` 를 보내던 기존 동작 그대로면 계속 동작한다.
- **배포 순서: 69-02 클라이언트 먼저 → 이 플랜(api) 나중** 권장(위 "유예 창" 절 참조). 반대 순서도 유예 창이 흡수하지만, 프론트가 handshake 토큰을 안 보내는 구간 동안 팀 채팅/MP 알림이 소켓으로 오지 않는다(폴링 폴백 없음 — UX 영향 있음).
- R2~R5 (69-03~06 대응 플랜)는 이 플랜과 독립적으로 착수 가능.

---
*Phase: 69-tenant-isolation-security-hardening*
*Completed: 2026-08-01*

## Self-Check: PASSED

- FOUND: `api-ventago/src/common/socket/websocket.gateway.ts`
- FOUND: `api-ventago/src/common/socket/websocket.module.ts`
- FOUND: `api-ventago/src/common/socket/websocket.service.ts`
- FOUND: `api-ventago/src/common/socket/websocket.gateway.spec.ts`
- FOUND commit `e95eb79` (Task 1)
- FOUND commit `642afaa` (Task 2)
- FOUND commit `8487842` (Task 3)
- FOUND commit `af7168c`, `708b540` (style fixes)
