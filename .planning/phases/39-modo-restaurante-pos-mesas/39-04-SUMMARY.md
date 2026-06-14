---
phase: 39-modo-restaurante-pos-mesas
plan: 04
subsystem: backend (store config)
tags: [storeConfig, update-flag, whitelist, restaurant-mode, findOrCreate]
requires:
  - 39-01 (StoreConfig.useRestaurantMode + restaurantCategoryIds 컬럼)
provides:
  - storeConfig update-flag 화이트리스트 useRestaurantMode (@Patch + @Put)
  - PUT /store-config/:storeId/restaurant-categories 라우트
  - StoreConfigService.updateRestaurantCategories (Array.isArray + number[] 정규화)
  - findOrCreateByStoreId 폴백 (store_config 행 부재 매장 안전)
affects:
  - 39-06 configuración 식당모드 토글 UI (이 백엔드를 호출)
tech-stack:
  added: []
  patterns:
    - "update-flag allowedFields 화이트리스트 (storeConfig.controller.ts 기존 패턴 확장)"
    - "findOrCreate 폴백 — 레거시 store_config 누락 매장 방어 (Pitfall 2)"
key-files:
  created:
    - api-ventago/src/app/store/config/storeConfig.controller.spec.ts
  modified:
    - api-ventago/src/app/store/config/storeConfig.controller.ts
    - api-ventago/src/app/store/config/storeConfig.service.ts
decisions:
  - "update() 도 findOrCreateByStoreId 경유로 보강 — 토글/설정 저장 경로는 행 부재 시 자동 생성, GET(findByStoreId) 은 NotFound 유지"
  - "categoryIds 는 Number 변환 + Number.isInteger>0 필터로 정규화 후 저장 (음수/문자열/소수 차단)"
metrics:
  duration: ~7min
  completed: 2026-06-14
  tasks: 1
  files: 3
requirements: [REQ-1]
---

# Phase 39 Plan 04: storeConfig 식당모드 플래그 화이트리스트 Summary

update-flag 화이트리스트(@Patch + @Put 두 곳)에 `useRestaurantMode` 를 추가해 식당모드 토글이 BadRequestException 없이 저장되도록 하고, 식당 카테고리 id 목록 저장 라우트(`PUT /store-config/:storeId/restaurant-categories`) + `updateRestaurantCategories` 서비스 메서드를 추가했다. 추가로 `findOrCreateByStoreId` 폴백으로 store_config 행이 없는 레거시 매장의 토글 저장도 안전하게 처리한다. TDD(RED→GREEN) 로 6 케이스 spec 작성.

## What Was Built

| 항목 | 내용 |
|------|------|
| 화이트리스트 (2곳) | `updateFlagPatch` + `updateFlagPut` allowedFields 배열에 `'useRestaurantMode'` 추가 |
| 카테고리 저장 라우트 | `@Put(':storeId/restaurant-categories')` → `updateRestaurantCategories(storeId, categoryIds)` |
| 서비스 메서드 | `updateRestaurantCategories` — Array.isArray 검증 + Number 변환/정수>0 필터 + findOrCreate 후 JSONB 저장 |
| findOrCreate 폴백 | `findOrCreateByStoreId` private 헬퍼 — `update()` 와 `updateRestaurantCategories()` 가 공유. 행 부재 매장 자동 생성 (Pitfall 2) |
| spec | 6 케이스: useRestaurantMode @Patch/@Put 통과, 기존 use* 회귀, badField BadRequest ×2, restaurant-categories 호출 |

## Tasks Completed

| Task | Name | RED | GREEN | Files |
|------|------|-----|-------|-------|
| 1 | 화이트리스트 + 카테고리 라우트 + findOrCreate + spec | e3fd633 | ddcd049 | controller, service, spec |

## TDD Gate Compliance

- RED gate: `test(39-04)` commit e3fd633 — spec 작성, `updateRestaurantCategories` 부재로 TS2339 컴파일 실패 확인.
- GREEN gate: `feat(39-04)` commit ddcd049 — 구현 후 6/6 PASS.
- REFACTOR: 불필요 (구현 clean, ESLint 위반 0).

## Verification

| Check | Result |
|-------|--------|
| `npx jest storeConfig` | PASS — 6/6 |
| `npx tsc --noEmit` | PASS — exit 0, 에러 0 |
| `grep -c useRestaurantMode controller` | 2 (@Patch + @Put 둘 다) ✅ |
| `@Put(':storeId/restaurant-categories')` 존재 | ✅ line 96 |
| service `updateRestaurantCategories` + `findOrCreate` + `Array.isArray` | ✅ 모두 존재 |

## Decisions Made

- **update() 도 findOrCreate 경유**: 기존 `update()` 는 `findByStoreId` (행 없으면 NotFound) 를 호출했으나, 토글 저장 경로(update-flag)는 행 부재 시 500 이 아니라 행을 생성해야 한다(Pitfall 2). `update()` 를 `findOrCreateByStoreId` 로 전환. GET 경로(`getConfig` → `findByStoreId`)는 NotFound 동작 유지.
- **categoryIds 정규화**: `Number()` 변환 후 `Number.isInteger(id) && id > 0` 필터 — 음수/0/문자열/소수 id 를 저장 단계에서 제거 (T-39-09 Tampering 완화).

## Deviations from Plan

### Auto-fixed / 보강 (Rule 2 - missing critical functionality)

**1. [Rule 2] `update()` 도 findOrCreate 로 보강 (계획 명시 범위 확장)**
- **Found during:** Task 1 (Pitfall 2 검토)
- **Issue:** 플랜은 "토글 저장 경로 findOrCreate 폴백" 을 요구. update-flag 핸들러는 `service.update()` 를 호출하므로, 별도 메서드를 만드는 대신 `update()` 자체를 findOrCreate 로 전환하는 것이 최소 변경이며 모든 update-flag/update-digits/update-currency 경로를 동시에 방어한다.
- **Fix:** `findOrCreateByStoreId` private 헬퍼 추가 → `update()` + `updateRestaurantCategories()` 공유.
- **Files modified:** storeConfig.service.ts
- **Commit:** ddcd049

그 외 플랜과 동일하게 실행.

## Known Stubs

None — 모든 경로 실데이터 연결됨.

## Threat Flags

None — update-flag 화이트리스트(T-39-08) + categoryIds Array.isArray/number[] 정규화(T-39-09) 둘 다 plan threat_model 에 등록된 mitigation 을 구현. 신규 trust boundary 없음.

## Self-Check: PASSED

- FOUND: storeConfig.controller.spec.ts / storeConfig.controller.ts / storeConfig.service.ts
- FOUND: commit e3fd633 (RED), ddcd049 (GREEN)
- FOUND: 39-04-SUMMARY.md
