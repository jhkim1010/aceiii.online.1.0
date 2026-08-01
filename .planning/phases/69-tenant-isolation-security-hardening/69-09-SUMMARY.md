---
phase: 69-tenant-isolation-security-hardening
plan: 09
subsystem: api
tags: [jest, regression, multi-tenant, security]

# Dependency graph
requires:
  - phase: 69-01
    provides: "/realtime handshake 인증 + room 소유권 검증 (R1)"
  - phase: 69-03
    provides: "correctTodayStocks scope 필수 인자 + branchIds/variantId 전량 검증 (R2)"
  - phase: 69-05
    provides: "벤더 토큰 단일 매장 scope + 구 토큰 차단 (R3)"
  - phase: 69-06
    provides: "파생 스코프 규칙 40개 + 다중 부모 (R4)"
  - phase: 69-07
    provides: "TENANT_DERIVED_MODE 기본값 enforce (R4)"
  - phase: 69-08
    provides: "TenantContext 확정 실패 fail-closed (R5)"
provides:
  - "npm run test:tenant — R1~R5 경계를 한 번에 판정하는 관문 20종"
  - "구코드(81474ab) 17/20 실패 증거 — 관문이 실제로 회귀를 잡는다는 증명"
  - "where 절을 해석하는 테이블 mock — storeId 조건 삭제 회귀를 잡는 픽스처"
affects: [69-10]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "회귀 관문은 '구코드에서 빨간불' 을 증거로 남겨야 한다 — 초록만으로는 무엇도 증명하지 못한다"
    - "보안 테스트의 mock 은 where 를 해석해야 한다. 무조건 행을 돌려주는 mock 은 경계가 지워져도 통과한다"
    - "별도 jest 프로젝트는 확장자로 분리(.tenant-spec.ts) — 기본 npm test 와 겹치지 않는다"

key-files:
  created:
    - api-ventago/test/tenant/cross-tenant.tenant-spec.ts
    - api-ventago/test/tenant/helpers/fixtures.ts
    - api-ventago/test/tenant/jest-tenant.json
    - api-ventago/test/tenant/README.md
  modified:
    - api-ventago/package.json
---

# 69-09 — 교차매장 회귀 관문 (R1~R5)

## 문제

개별 플랜이 각자 스펙을 남겼지만 **경계 전체를 한 번에 확인하는 관문**이 없었다.
다음에 누군가 소켓 인증을 되돌리거나 `correct-today` 검증을 지워도 조용히 통과한다.

## 무엇을 했나

`npm run test:tenant` 한 줄로 R1~R5 를 판정하는 스위트 20종. 실 DB 불요.

| 요구 | 시나리오 수 | 핵심 |
|---|---|---|
| R1 `/realtime` | 5 | 미인증 join 0회 · room 소속은 **토큰 파생**(클라이언트 값 무시) · 타 매장 terminal/branch 거부 · 자기 매장 join 정상 |
| R2 `correctTodayStocks` | 4 | 타 매장 부모/branchId/variantId 각각 403 · 남의 부모의 자식은 superadmin 도 403 |
| R3 벤더 포털 | 4 | PIN 통과 매장만 토큰 · 2개 매장 통과 시 토큰 대신 매장 선택 · 구 토큰 재로그인 강제 · `vendorId+storeId` 조합 검증 |
| R4 파생 스코프 | 4 | env 없이 기본값 enforce · ProductBranch 다중 부모 · `beforeFind` INNER JOIN 주입 · observe 하향 탈출구 |
| R5 컨텍스트 | 3 | 확정 통과 · 미해석 403 · storeId 미배정 403 |

**픽스처 설계가 핵심이다.** `helpers/fixtures.ts` 의 테이블 mock 은 `where`(단순 동등 + `Op.in`)를 **실제로 해석한다.**
`findOne` 이 무조건 행을 돌려주는 mock 이면 `storeId` 조건을 지우는 회귀가 나도 테스트가 통과해 버린다.

## 검증 — 구코드에서 빨간불인가

Phase 69 직전 커밋 `81474ab` 의 소스 7개를 작업본에 되돌려 같은 스위트를 돌렸다.

1. **타입 단계에서 이미 실패** — `TS2554: Expected 4-6 arguments, but got 7`(scope 인자 부재),
   `TS2339: Property 'requiresStoreSelection' does not exist`(매장 선택 없던 시절),
   `TS2339: Property 'map' does not exist on type 'DerivedScopeRule'`(다중 부모 이전).
2. **타입 검사를 끄고 행위만** — `Tests: 17 failed, 3 passed, 20 total`.
   통과한 3개는 전부 무회귀 확인용(자기 매장 join · observe 탈출구 · 컨텍스트 확정 통과)이라 구코드 통과가 정상이다.

되돌린 파일은 `git checkout HEAD --` 로 전량 복구했고 `git status` 로 확인했다. 재현 절차는 `test/tenant/README.md` 에 있다.

## 현재 코드 검증

```
$ npm run test:tenant       → Tests: 20 passed, 20 total
$ npm run test:concurrency  → Tests: 8 passed, 8 total   (Phase 64 무회귀)
$ npx jest src/common/tenant → 13 passed
```

## 남은 것 / 알려진 사항

- `npx eslint test/tenant/**` 는 `Parsing error: ... not found by the project service` 로 실패한다.
  **기존 `test/concurrency/` 도 동일**한 사전 조건(tsconfig 가 test 를 프로젝트 서비스에 포함하지 않음)이며,
  CI 빌드는 `nest build`(src 만) 경로라 배포에 영향 없다. tsconfig 조정은 범위 밖.
- 이 스위트는 mock 레벨이라 **실제 SQL 이 매장을 넘는지**는 증명하지 않는다. 그 층은 69-10 운영 검증이 맡는다.

## Commits

- `89195af` (api-ventago) — test(security): 교차매장 회귀 관문 스위트 추가 (69-09/R1~R5)
