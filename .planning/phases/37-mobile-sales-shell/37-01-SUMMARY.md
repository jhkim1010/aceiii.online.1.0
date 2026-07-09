---
phase: 37-mobile-sales-shell
plan: 01
subsystem: backend-auth-scope
tags: [mobile, auth, scope-guard, sessions, sequelize, nestjs]
requires:
  - Phase 33 user_branches (multi-branch RBAC)
  - phase37-mobile-access-function.sql (mobile.access — pre-existing)
  - phase37-user-branches-mobile-terminal.sql (mobile_terminal_id — pre-existing)
provides:
  - mobile_sessions table (desktop active_sessions 와 분리)
  - users.mobile_pin column (UI-D3 PIN 로그인)
  - MobileAuthService (PIN login + scope 결정 + session UPSERT)
  - MobileScopeGuard (x-mobile-session-token → scope 강제 + mid-session STORE_SUSPENDED)
  - POST /mobile/auth/login, GET /mobile/me, POST /mobile/auth/set-pin
affects:
  - src/app.module.ts (MobileModule 등록)
  - src/app/users/users.model.ts (mobilePin 매핑 추가)
tech-stack:
  added: []
  patterns:
    - scope-from-DB-not-JWT (JwtStrategy 가 payload 를 버리므로 mobile_sessions 가 authoritative)
    - mid-session store lifecycle re-check via MemoryCacheService (60s, pool 보호)
    - find-or-update session UPSERT keyed on (user_id, device_fingerprint)
key-files:
  created:
    - api-ventago/migrations/phase37-mobile-sessions.sql
    - api-ventago/migrations/phase37-users-mobile-pin.sql
    - api-ventago/migrations/phase37-vendedor-user-branches-backfill.sql
    - api-ventago/src/app/mobile/models/mobile-session.model.ts
    - api-ventago/src/app/mobile/dto/mobile-login.dto.ts
    - api-ventago/src/app/mobile/dto/mobile-set-pin.dto.ts
    - api-ventago/src/app/mobile/mobile-store-status.util.ts
    - api-ventago/src/app/mobile/auth/mobile-auth.service.ts
    - api-ventago/src/app/mobile/auth/mobile-auth.service.spec.ts
    - api-ventago/src/app/mobile/guards/mobile-scope.guard.ts
    - api-ventago/src/app/mobile/guards/mobile-scope.guard.spec.ts
    - api-ventago/src/app/mobile/auth/mobile-auth.controller.ts
    - api-ventago/src/app/mobile/mobile.module.ts
  modified:
    - api-ventago/src/app.module.ts
    - api-ventago/src/app/users/users.model.ts
decisions:
  - "scope 는 JWT payload 가 아니라 mobile_sessions row 에서 읽는다 (JwtStrategy.validate 가 payload 를 버리므로). x-mobile-session-token 헤더로 조회 (x-session-token 패턴 대칭)."
  - "STORE_SUSPENDED 를 로그인 전용에서 매 요청(mid-session)으로 강화 — MemoryCacheService 60s 로 store status 캐시하여 pool 부담 0."
  - "mobile_pin 은 Users 모델 컬럼으로 추가 (ORM read/write 필요) — 계획 files_modified 외 필수 변경 (Rule 3)."
metrics:
  tasks: 3
  files-created: 14
  files-modified: 2
  tests: 18 passed
  duration: ~40m
  completed: 2026-07-08
---

# Phase 37 Plan 01: Mobile Backend Auth & Scope Foundation Summary

PIN 기반 모바일 로그인 + DB 권위(mobile_sessions) scope 강제 레이어. 모든 `/mobile/*`
엔드포인트의 보안 기반 — vendedor 는 자기 지점만 보고/팔며 URL 파라미터 조작이 불가능하고,
모바일 세션은 데스크탑 active_sessions 와 분리되어 동시 접속을 허용한다.

## What Was Built

- **3 migrations (local PG18 적용 + idempotent 검증):** `mobile_sessions`(app-level UUID,
  UNIQUE(user_id,device_fingerprint) + UNIQUE(active_session_token), INT[] scope), `users.mobile_pin`,
  vendedor `user_branches` backfill (2번째 실행 시 INSERT 0 — idempotent).
- **MobileSession 모델** — sequelize-typescript, `DataType.ARRAY(INTEGER)` scope 컬럼, UUID id/token.
- **MobileAuthService** — Usuario(username|email) + PIN(bcrypt) 로그인, 활성/매장상태 검증,
  vendedor scope 해석(user_branches → branchId[], fallback users.branch_id), mobile_sessions UPSERT
  (재로그인 시 토큰 회전), `setMobilePin`(admin), `getMe`. **SessionService 미사용(D-06)**.
- **MobileScopeGuard** — `x-mobile-session-token` → mobile_sessions 조회, mid-session 매장 상태
  재확인(MemoryCache 60s), `?branchId/?storeId` scope 교차검증, last_seen_at heartbeat, `req.scope` 주입.
- **MobileAuthController + MobileModule** — 3개 라우트, app.module.ts 등록.
- **Jest specs** — 18 케이스 전부 green (RED→GREEN TDD gate 준수).

## must_haves Truths — Status

| Truth | Status | Evidence |
|-------|--------|----------|
| vendedor Usuario+PIN 로그인 → accessToken + mobileSessionToken (UI-D3) | ✅ | spec: 유효 vendedor 로그인 케이스 + JWT payload 케이스 |
| scope 비어있으면 401 VENDEDOR_SCOPE_NOT_DEFINED (criterion 3) | ✅ | spec: user_branches 0 + branch_id NULL 케이스 |
| 모바일 로그인이 데스크탑 세션 유지 (mobile_sessions 분리, criterion 1) | ✅ | 별도 테이블 + SessionService 미주입 (spec: sessionService undefined) |
| ?branchId 범위 밖 → 403 SCOPE_VIOLATION (criterion 4) | ✅ | guard spec: branchId 99 not in [5] |
| 동일 fingerprint 재로그인 → 이전 세션 무효 → 401 MOBILE_SESSION_EXPIRED (criterion 12) | ✅ | service spec: 재로그인 토큰 회전 + guard spec: 없는 토큰 401 |
| mid-session 매 요청 STORE_SUSPENDED 재확인, MemoryCache 60s (criterion 9 강화) | ✅ | guard spec: SUSPENDED 401 + 2번째 요청 캐시 hit(findByPk 1회) |

## Verification Results (honest)

- `npx jest mobile-auth.service.spec mobile-scope.guard.spec` → **18 passed / 18** ✅
- `npx eslint src/app/mobile` → **0 errors** (1 warning: no-unsafe-argument on Sequelize create, 'warn' 레벨 — exit 0) ✅
- `npx tsc --noEmit` (src/app/mobile) → **0 errors** ✅
- 마이그레이션 local PG18 적용 + 재실행 idempotent 확인 (`\d mobile_sessions` UNIQUE 인덱스/제약 확인, users.mobile_pin 존재) ✅
- `grep "new Pool" src/app/mobile` → 0 (신규 Pool 없음, pool-safe) ✅

## Deviations from Plan

### Auto-fixed / Auto-added (Rules 1-3)

**1. [Rule 3 - Blocking] users.model.ts 에 `mobilePin` 컬럼 매핑 추가**
- **Found during:** Task 2 (MobileAuthService bcrypt.compare)
- **Issue:** `phase37-users-mobile-pin.sql` 이 DB 컬럼을 추가하지만 Sequelize 모델은 선언된 컬럼만
  read/write 한다. `user.mobilePin` 이 undefined → PIN 검증 불가.
- **Fix:** `Users` 모델에 `@Column mobilePin: string | null` 추가 (underscored → mobile_pin).
- **Files modified:** api-ventago/src/app/users/users.model.ts
- **Commit:** 30e5bae

**2. [Rule 3 - Blocking] `mobile-store-status.util.ts` 공유 헬퍼 신규**
- **Found during:** Task 2
- **Issue:** 매장 차단 판정 규칙이 로그인(service)과 mid-session(guard) 두 곳에서 일치해야 하며
  어긋나면 보안 구멍. 계획 files_modified 에는 없던 파일.
- **Fix:** `isStoreBlocked(status)` 단일 헬퍼로 SUSPENDED/ARCHIVED/DELETED 판정을 공유.
- **Commit:** e97ce9d

**3. [Rule 3 - Blocking] `phase37-users-mobile-pin.sql` — 계획엔 있으나 SPEC DDL 초안엔 없던 PIN 컬럼**
- 계획 files_modified 에 명시되어 있어 정상 범위. UI-D3(PIN 로그인) 충족을 위해 생성.

### Design notes

- **store status 해석:** 운영/로컬 `stores.status` 값이 혼재(`'0'/'1'/'active'/'ACTIVE'`)하고 명시적
  'SUSPENDED'/'ARCHIVED' 문자열은 아직 데이터에 없다. `isStoreBlocked` 는 SUSPENDED/ARCHIVED/DELETED
  (대소문자 무시)만 차단하고 정상 상태는 통과 → 베타 매장 회귀 없음. 매장 lifecycle 이 명시 문자열로
  전이될 때 즉시 발효.
- **guard 의 storeId 출처:** `req.user.storeId` (AuthGuard('jwt') 후행이라 항상 존재). mobile_sessions
  에 store_id 컬럼을 추가하지 않고 재사용 → 요청당 추가 쿼리 없음.
- **JwtModule 는 MobileModule 에 로컬 등록** (AuthModule 이 JwtService 를 export 하지 않으므로).

## Known Stubs

- **revendedor scope 해석** — Wave 5(Phase 24 게이트)까지 의도적 stub. revendedor role 로그인 시
  `RESELLER_SCOPE_NOT_DEFINED` 401 반환 (CONTEXT D-07). vendedor MVP 범위 밖으로 계획대로 지연.

## Deferred / Out-of-scope (기록만)

- 사전 존재하던 tsc 에러 2건: `src/app/mercadopago/webhook/mp-webhook.service.spec.ts` (생성자 인자
  9 vs 7) — 이 플랜과 무관, 손대지 않음.
- 사전 존재하던 working-tree 수정 `src/app/print/print.controller.ts` — 커밋에 포함하지 않음(무관).
- 운영 PG10 마이그레이션 적용은 별도 RUNBOOK 단계 (Phase 35/36 게이트 확인 후 사용자 승인). 본 플랜은
  local PG18 검증까지만.

## TDD Gate Compliance

- RED: `test(37-01): failing specs ... (RED)` — e97ce9d
- GREEN: `feat(37-01): MobileAuthService + MobileScopeGuard (GREEN)` — 30e5bae
- 순서 준수 ✅ (RED 커밋이 GREEN 커밋보다 선행).

## Commits (api-ventago submodule, base a900340)

- `d8b9f43` feat(37-01): migrations + MobileSession model
- `e97ce9d` test(37-01): failing specs (RED)
- `30e5bae` feat(37-01): MobileAuthService + MobileScopeGuard (GREEN)
- `c5af09d` feat(37-01): controller + module wiring + ESLint clean

## Self-Check: PASSED
