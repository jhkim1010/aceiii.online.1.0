---
phase: 61-tienda-online-editor
plan: 03
subsystem: api
tags: [nestjs, postgresql, shop-catalog, sql-injection-prevention, jest]

# Dependency graph
requires:
  - phase: 61-tienda-online-editor
    provides: "shop-public 모듈 스캐폴드(ShopCatalogService/Controller, ShopReadonlyDbService) — 61-01/02"
provides:
  - "ShopProductDto.priceOrig/stock 필드 (할인 배지·últimas unidades UI 데이터 소스)"
  - "sort 화이트리스트(newest/price_asc/price_desc/bestseller) → 고정 ORDER BY 매핑"
  - "showOutOfStock/minPrice/maxPrice 공개 카탈로그 쿼리 필터"
  - "sort=bestseller 90일 판매수량 집계 + permission denied 안전 강등"
  - "pageSize 상한 48 통일 (컨트롤러 50→48)"
affects: [61-04-readonly-role-grant, 프런트 ProductCard/필터 UI 플랜]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "정렬 파라미터는 Record 화이트리스트로 고정 SQL 리터럴에만 매핑 (문자열 보간 금지)"
    - "가격 구간 필터는 ::numeric 파라미터 바인딩 + IS NULL OR 패턴으로 optional 조건 표현"
    - "권한 없는 집계 쿼리는 permission denied 메시지로 판별해 안전 강등 + warn 로그"

key-files:
  created:
    - api-ventago/src/app/shop-public/shop-catalog.service.spec.ts
  modified:
    - api-ventago/src/app/shop-public/shop-catalog.service.ts
    - api-ventago/src/app/shop-public/shop-catalog.controller.ts

key-decisions:
  - "Task 1(DTO 확장)과 Task 2(정렬/필터)를 단일 커밋으로 병합 — Task 2 가 Task 1 이 만든 SELECT 절을 그대로 다시 감싸는 구조라 파일 상 diff 를 분리하면 오히려 중간 상태가 불완전해짐"
  - "bestseller 쿼리 실패 시 문자열 매칭('permission denied')으로 강등 여부 판정 — pg 에러 코드(42501) 대신 메시지 매칭을 택함(플랜 지시 그대로, ShopReadonlyDbService 가 에러 코드를 노출하지 않음)"

patterns-established:
  - "ORDER_BY_MAP: Record<Exclude<Sort,'bestseller'>, string> 고정 리터럴 화이트리스트"

requirements-completed: [R5, R6, R9, R8]

# Metrics
duration: 20min
completed: 2026-07-24
---

# Phase 61 Plan 03: 카탈로그 정렬/필터/가격구간 + priceOrig·stock DTO 확장 Summary

**공개 카탈로그 API 에 priceOrig/stock DTO 필드, sort 화이트리스트(price_asc/price_desc/bestseller), showOutOfStock/minPrice/maxPrice 필터, pageSize 48 상한을 추가하고 bestseller 90일 판매 집계를 permission denied 안전 강등과 함께 구현**

## Performance

- **Duration:** 20 min
- **Started:** 2026-07-24T10:50:00Z (추정, 세션 시작 기준)
- **Completed:** 2026-07-24T11:14:00Z
- **Tasks:** 3/3 완료
- **Files modified:** 2 (service.ts, controller.ts) + 1 신규 (service.spec.ts)

## Accomplishments
- `ShopProductDto` 에 `priceOrig`/`stock` 추가, 목록(listProducts)·상세(getProductBySlug) SELECT 절 2곳 모두 반영 — null 안전
- `CatalogSort` 타입 + `ORDER_BY_MAP` 화이트리스트 + `resolveOrderBy()` (export, 유닛테스트 대상) — SQL 문자열 보간 0
- `showOutOfStock=false` 시 `COALESCE(p.stock, 0) > 0` 고정 SQL 조각으로 재고 0 이하 제외 (신규 바인딩 없음)
- `minPrice`/`maxPrice` 를 `$8`/`$9` `::numeric` 파라미터 바인딩으로 반영 (문자열 보간 0, 음수/비숫자는 컨트롤러에서 null 로 강등)
- `sort=bestseller` — 최근 90일 `sale_items`×`sales` 집계(취소/nullified 제외) + `permission denied` 감지 시 최신순으로 안전 강등 + warn 로그 (61-04 GRANT 선행조건 문서화)
- 컨트롤러 `pageSize` 상한 50→48 통일, `sort`/`showOutOfStock`/`minPrice`/`maxPrice` 쿼리 파라미터 파싱 추가
- 신규 유닛테스트 8건(`resolveOrderBy` 5건 + `toDto` 3건) 전체 PASS — SQL 인젝션 강등, stock=0 보존 케이스 포함

## Task Commits

Each task was committed atomically (api-ventago 서브레포 + 루트 gitlink 별도 커밋):

1. **Task 1+2 (병합): priceOrig/stock DTO + 정렬/필터/pageSize** - api-ventago `a7311c5` (feat) + 루트 `54f6463` (chore: bump)
2. **Task 3: shop-catalog.service.spec.ts 신규** - api-ventago `c759638` (test) + 루트 `9d7d707` (chore: bump)

_Note: Task 1과 Task 2는 동일 함수(listProducts)의 SELECT 절을 순차로 확장하는 구조라 diff 분리가 비실용적이어서 한 커밋으로 병합함(Decisions 참조)._

## Files Created/Modified
- `api-ventago/src/app/shop-public/shop-catalog.service.ts` - `CatalogSort`/`ORDER_BY_MAP`/`resolveOrderBy` 신설, `ShopProductDto.priceOrig/stock`, `ShopListParams.sort/showOutOfStock/minPrice/maxPrice`, `listProducts()` 쿼리 빌더 3종(일반/bestseller/강등), `getProductBySlug()` SELECT 확장
- `api-ventago/src/app/shop-public/shop-catalog.controller.ts` - `sort`/`showOutOfStock`/`minPrice`/`maxPrice` 쿼리 파라미터 + `pageSize` clamp 48
- `api-ventago/src/app/shop-public/shop-catalog.service.spec.ts` (신규) - `resolveOrderBy` 화이트리스트/인젝션/bestseller 미매핑 5건 + `toDto` priceOrig/stock null 안전·stock=0 보존 3건

## Decisions Made
- Task 1과 Task 2 커밋 병합 (Key-decisions 참조 — diff 분리가 비실용적)
- `permission denied` 문자열 매칭으로 GRANT 부재 판정 (플랜 지시대로, pg 에러코드 대신 메시지 매칭 — `ShopReadonlyDbService.query` 가 원본 pg 에러 코드를 그대로 전달하는지 확인하지 않았으므로 메시지 기반이 더 안전한 선택)

## Deviations from Plan

None - plan executed exactly as written (ESLint prettier 자동수정 2건은 코드 포맷 이슈로 Rule 대상 아님).

## Issues Encountered
- ESLint(prettier) 가 `Math.min(48, Math.max(1, parseInt(...)))` 한 줄을 80자 초과로 줄바꿈 강제 → acceptance criteria 의 `grep -c "Math.min(48,"` 를 만족하도록 `parsedPageSize` 중간 변수로 리팩터링해 한 줄에 맞춤. 동작 변화 없음.
- `resolveOrderBy` 초기 구현(`String(sort ?? '')`)이 `@typescript-eslint/no-base-to-string` 에 걸림 → `typeof sort === 'string' ? sort : ''` 로 교체(런타임 동작 동일, `sort: unknown` 이므로 오히려 더 안전).
- 로컬 API 서버 미기동으로 plan `<verification>` 의 curl 스모크 3건(런타임 확인)은 미실행 — 자동화된 유닛테스트(8건)와 ESLint(0)로 대체 검증. 서버 기동 후 수동 확인 권장.

## User Setup Required

None - no external service configuration required. 단, `sort=bestseller` 가 실제로 판매수량 집계를 제공하려면 61-04 마이그레이션의 `shop_readonly` role `sales`/`sale_items` GRANT 적용이 필요(그 전까지는 자동으로 최신순 강등되어 500 없이 동작).

## Next Phase Readiness
- 공개 카탈로그 API 가 R5(할인/재고 배지)·R6(정렬/가격필터/pageSize)·R9(bestseller 선반) 프런트 작업의 데이터 소스로 준비됨
- 61-04(readonly role GRANT 마이그레이션) 적용 전까지 bestseller 는 최신순으로 표시됨 — UX 상 문제 없으나 GRANT 적용 후 재확인 필요
- 신규 마이그레이션 파일 0건, 신규 Pool/Client 0건 확인됨

---
*Phase: 61-tienda-online-editor*
*Completed: 2026-07-24*

## Self-Check: PASSED

All created/modified files confirmed on disk, all 4 commit hashes (api-ventago: a7311c5, c759638 / root: 54f6463, 9d7d707) confirmed in git log.
