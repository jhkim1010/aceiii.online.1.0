---
phase: 69-tenant-isolation-security-hardening
plan: 08
subsystem: api
tags: [nestjs, security, multi-tenant, fail-closed]

# Dependency graph
requires:
  - phase: 67
    provides: "JwtGlobalGuard 에서 TenantContext.resolve() 로 인증 후 매장 컨텍스트 확정"
  - phase: 69-07
    provides: "파생 스코프 enforce — 격리가 실제로 차단하는 상태여야 fail-closed 가 의미를 갖는다"
provides:
  - "TenantContext 확정 실패 시 403 + 보안 로그 (fail-open 제거)"
  - "resolved 여부 사후 검사 — 예외 없이 미해석으로 남는 경로까지 차단"
  - "storeId 미배정 비-superadmin 요청 차단 (allowedStores() null → 격리 no-op 구멍)"
  - "회귀 테스트 6종 + store_id NULL 사용자 실측 문서"
affects: [69-09, 69-10]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "보안 경계의 catch 는 fail-closed — 삼키면 격리 훅 전체가 no-op 이 된 채 요청이 통과한다"
    - "TenantContext.resolve() 는 ALS 스코프가 없으면 조용히 무시하므로 예외 처리만으로는 부족 → resolved 값을 사후 검사"

key-files:
  created:
    - api-ventago/src/app/auth/guards/jwt-global.guard.spec.ts
    - .planning/phases/69-tenant-isolation-security-hardening/69-NULL-STORE-SURVEY.md
  modified:
    - api-ventago/src/app/auth/guards/jwt-global.guard.ts
---

# 69-08 — TenantContext 확정 실패를 fail-closed 로 (R5 / WR-02)

## 문제

`jwt-global.guard.ts` 는 인증 후 `TenantContext.resolve(...)` 전체를 빈 `catch {}` 로 감싸고,
주석으로 "컨텍스트 확정 실패가 인증 결과를 바꾸지 않는다 (격리는 미해석=no-op 로 폴백)" 이라고 못 박았다.

예외가 나면 `resolved=false` 가 유지되고 **모든 Sequelize 격리 훅이 no-op 이 된 채 요청이 통과**한다.
그 요청은 매장 필터 없이 DB 를 훑는다. 보안 경계의 실패 정책이 명시적으로 fail-open 이었다.

같은 계열의 두 번째 구멍: `resolved=true` 인데 `storeId === null` + `isSuperAdmin === false` +
`system === false` 인 상태. `tenant-hooks.allowedStores()` 가 `null` 을 돌려줘 역시 격리가 전부 꺼진다.

## 무엇을 했나

**1) catch 를 fail-closed 로** — 로그 남기고 `ForbiddenException`.

**2) 확정 여부 사후 검사** — `resolve()` 는 ALS 스코프가 없으면 **조용히 무시**하므로(`if (!ctx) return`)
예외만 잡아서는 미해석 상태를 못 잡는다. `TenantContext.get()?.resolved` 를 직접 확인한다.
`TenantContextMiddleware` 가 `forRoutes('*')` 라 정상 HTTP 요청에는 항상 컨텍스트가 있다.

**3) storeId 미배정 차단** — `!isSuperAdmin && !system && typeof storeId !== 'number'` 이면 403.

`@Public` 라우트는 이 검사들 **앞에서** 이미 반환되므로 영향 없다.

## 실측 — 누가 막히는가

`69-NULL-STORE-SURVEY.md`. 운영(5434)·로컬(5432) 양쪽에서 `store_id IS NULL` 인 계정은
**superadmin 1명뿐**이고, 가드가 `isSuperAdmin` 을 먼저 확인해 통과시킨다.
**fail-closed 로 막히는 정상 사용자 0명.**

## 검증

- 회귀 테스트 6종 전부 통과 — 확정 통과 / 스코프 없음 403 / resolve 예외 403 / `@Public` 통과 /
  storeId 없는 일반 사용자 403 / superadmin 통과
- `nest build` + `node dist/main.js` 부팅 확인
- 운영 배포(`0e385e4`, 빌드 #590) 후 화면 8종 순회 + API 4종 호출:
  `TENANT-CTX` 차단 로그 **0건**, 신규 403 **0건**

## 남은 것

`users.store_id` 는 스키마상 nullable 이라 앞으로 매장 미배정 계정이 생길 수 있다.
그 계정은 로그인은 되지만 매장 데이터 요청에서 403 을 받는다 — 격리가 꺼진 채 전 매장을
훑는 것보다 안전한 실패다. 로그(`[TENANT-CTX] 매장 미배정 사용자`)로 즉시 식별된다.

## 계획 대비 차이

플랜의 `files_modified` 에 `tenant-context.ts` 가 있었으나 **수정하지 않았다** —
`resolve()` 의 "컨텍스트 없으면 무시" 동작은 미들웨어 미적용 경로(크론·워커)에서 필요하고,
가드 쪽 사후 검사로 같은 목적을 달성했기 때문이다. 호출부 한 곳만 바꿔 영향 범위를 좁혔다.
