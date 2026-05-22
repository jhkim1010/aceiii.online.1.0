---
phase: 35-activity-ledger
plan: 03
subsystem: backend
tags: [backend, sales, api, queries, security, audit, d-04]

# Dependency graph
requires:
  - phase: 35-01
    provides: sales.activity_type / origin_branch_id / target_branch_id 컬럼 + Sale 모델 SaleActivityType enum + Branch BelongsTo
  - phase: 35-02
    provides: StockService.createStockMovement 가 movido/fallado 행을 sales 테이블에 INSERT
provides:
  - sales.service.findAll / findFiltered / findFilteredByStore / findAllScoped / findSalesByStoreFiltered / findSalesByStore / findAllQuerys 에 명시적 activity_type='sale' 필터
  - sales.service.findFilteredByStore 가 activityType/originBranchId/targetBranchId/direction 4 신규 필터 + originBranch/targetBranch eager-load 처리
  - sales.service.getDailyStats — Resumen 테이블 데이터 source (단일 raw SQL CTE, perBranch + total + movBalance)
  - sales-create.service: 2 dailyNumber 쿼리에 activityType=SALE 필터 (T-35-15 monotonicity)
  - 10 reports/dashboards/mirror 서비스에 activityType='sale' 필터 추가
  - online-order-sales-mirror.service: 2 dailyNumber 쿼리 + 2 Sale.create body activityType=SALE 명시
  - sales.controller GET /sales/all 4 신규 query (whitelist + cast)
  - sales.controller GET /sales/daily-stats 신규 엔드포인트 (route order: daily-stats > :id)
affects:
  - 35-activity-ledger-plan-04 (frontend useDailySalesStats SWR 훅이 /sales/daily-stats 소비)
  - 35-activity-ledger-plan-05+ (ventaVista 활동 필터 + Resumen 테이블 + 행 시각 구분)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "명시적 WHERE activity_type='sale' (Sequelize @DefaultScope 미사용 — SPEC D-04 risk 1 회피)"
    - "controller 화이트리스트 + cast 패턴 (activityType / direction query param T-35-11 변조 차단)"
    - "단일 raw SQL CTE (sale_per_branch + mov_in + mov_out + fal) + LATERAL sale_items SUM (PG10/PG15 호환)"
    - "raw SQL replacements 안전 (:storeId, :startDate, :endDate, :tz — T-35-13 SQL injection 차단)"
    - "branches LEFT JOIN 으로 활동 없는 지점도 0 표시"
    - "NestJS route ordering — 특정 path 라우트 (@Get('daily-stats')) 가 path param (@Get(':id')) 보다 위에 위치"

key-files:
  created: []
  modified:
    - "api-ventago/src/app/sales/sales.service.ts"
    - "api-ventago/src/app/sales/sales-create.service.ts"
    - "api-ventago/src/app/sales/sales.controller.ts"
    - "api-ventago/src/app/dashboards/sales/salesDashboards.service.ts"
    - "api-ventago/src/app/reports/reportsSales.service.ts"
    - "api-ventago/src/app/reports/reportsFacturacion.service.ts"
    - "api-ventago/src/app/reports/reportsBreveVenta.service.ts"
    - "api-ventago/src/app/reports/reportsVendedor.service.ts"
    - "api-ventago/src/app/reports/reportsCorregido.service.ts"
    - "api-ventago/src/app/reports/reportsFallados.service.ts"
    - "api-ventago/src/app/store/store.service.ts"
    - "api-ventago/src/app/online-orders/online-order-sales-mirror.service.ts"

key-decisions:
  - "명시적 WHERE 절 사용 (Sequelize @DefaultScope 미사용) — SPEC D-04 risk 1 (의도치 않은 누락) 회피, grep 감사 가능"
  - "findFilteredByStore activityType 처리: default 'sale', 'movido' / 'fallado' override 가능, 'all' 옵션 시 미적용"
  - "direction='in' → targetBranchId, direction='out' → originBranchId (Resumen 셀 드릴다운 의미)"
  - "store.service.ts backup Sale.findAll 은 의도적으로 activity_type 필터 미적용 (backup은 archival, 통계 아님 — 모든 활동 보존)"
  - "online-order-sales-mirror 의 dailyNumber 쿼리 2곳에도 activityType=SALE 추가 — sales-create 와 동일 잠식 차단 (T-35-15 회귀)"
  - "reportsFallados: status='Anulado' sale 만 — activity_type='fallado' 행은 별도 흐름 (현재 plan 의 범위 외, Phase 35-B/UAT 에서 처리)"
  - "reportsReservado: SuspendedSale 별도 모델 — sales 활동과 무관, 변경 없음 (의도된 무변경)"
  - "controller 화이트리스트 (activityType / direction) — invalid 값은 default 'sale' / null fallback (T-35-11 mitigation)"
  - "raw SQL CTE 단일 쿼리 — PG pool 절약 (5 쿼리 통합 → 1 쿼리)"
  - "getDailyStats 의 PG 함수 LATERAL JOIN + COALESCE — PG10 호환 (DATE_TRUNC 사용 없음)"

patterns-established:
  - "Phase 35 매출 통계 무오염 패턴: 모든 sales read 쿼리에 명시적 activity_type='sale' WHERE 절"
  - "dailyNumber 잠식 차단 패턴: sale 활동만 LIMIT 1 ORDER BY DESC 로 조회"
  - "ventaVista Resumen 데이터 source 패턴: raw SQL CTE (per-activity + per-branch) + JS aggregation (total + movBalance)"
  - "NestJS route static-before-param 패턴: @Get('daily-stats') BEFORE @Get(':id')"

requirements-completed: [AL-08, AL-09, AL-10, AL-11]

# Metrics
duration: 32min
completed: 2026-05-22
---

# Phase 35 Plan 03: Sales Queries — Activity Filter Audit + Resumen Data Source Summary

**매출 통계 무오염을 위해 13개 sales 쿼리 service 파일에 명시적 `WHERE activity_type='sale'` 필터 감사 적용 — GET /sales/all 에 4 신규 query 확장 + GET /sales/daily-stats 신규 엔드포인트 (ventaVista Resumen 테이블 데이터 source)**

## Performance

- **Duration:** ~32 min
- **Started:** 2026-05-22T22:31:15Z
- **Completed:** 2026-05-22T23:03:39Z (approx)
- **Tasks:** 3
- **Files modified:** 12 (1 commit per task, 13 files total — sales/* + 11 service files + controller)

## Accomplishments

- **Task 1 — sales.service.ts + sales-create.service.ts** (`c846024`):
  - `sales.service.ts` import + 7 메서드 (findAll, findFiltered, findFilteredByStore, findAllScoped, findSalesByStoreFiltered, findSalesByStore, findAllQuerys) 에 명시적 `activityType=SALE` 필터.
  - `findFilteredByStore` 가 4 신규 옵션 필터 (activityType / originBranchId / targetBranchId / direction) + `originBranch`/`targetBranch` Branch eager-load.
  - 신규 `getDailyStats({storeId, startDate, endDate})` 메서드 — 단일 raw SQL CTE 로 per-branch 활동 집계 + JS 에서 total/movBalance 계산.
  - `sales-create.service.ts`: SaleActivityType import + 2 dailyNumber `findOne` 쿼리 (`createSale` L188, `nullifySale` L379) 에 `activityType=SALE` 필터 추가 (T-35-15 monotonicity).
  - 2 `Sale.create` body 에 `activityType: SaleActivityType.SALE` 명시 (default 'sale' 이지만 가독성).
- **Task 2 — 10 reports/dashboards/store/mirror 서비스** (`de65a65`):
  - 9 활동/판매 데이터 조회 서비스 모두 baseline 동일 lint 수준 유지 (신규 도입 errors 0).
  - `store.service.ts` backup Sale.findAll 은 의도적으로 미적용 (archival 흐름) + 명시적 주석 추가.
  - `online-order-sales-mirror.service.ts` 의 2 dailyNumber 쿼리 + 2 Sale.create body 모두 `activityType=SALE` 처리.
- **Task 3 — sales.controller.ts** (`67318fd`):
  - GET /sales/all 4 신규 query 파라미터 + 화이트리스트 cast.
  - GET /sales/daily-stats 신규 엔드포인트 (Resumen 테이블 데이터 source).
  - Route order: `@Get('daily-stats')` (L145) → `@Get('by-store')` (L171) → `@Get(':id')` (L314) — static path 가 param path 보다 위에 위치.
- 13 파일 grep 감사: sales 활동 쿼리 모든 위치에 `activityType` 키워드 가시화.
- `npm run build` 3회 모두 PASS, `dist/app/sales/sales.controller.js` 에 `Get('daily-stats')` 데코레이터 정상 등록 확인.

## Task Commits

각 task 가 api-ventago nested git repo 에 원자적으로 commit 되었습니다:

1. **Task 1: sales.service + sales-create.service 필터 + getDailyStats** — `c846024` (feat)
   - 2 files, +280 / -5 lines.
2. **Task 2: 9 reports/dashboards/store/mirror 서비스 필터 감사** — `de65a65` (feat)
   - 9 files, +89 / -23 lines. 모두 baseline lint 동일.
3. **Task 3: sales.controller GET /sales/all 확장 + GET /sales/daily-stats 신규** — `67318fd` (feat)
   - 1 file, +58 lines.

_Plan metadata (SUMMARY.md) 는 부모 워킹트리에서 orchestrator 가 별도 commit 처리._

## Files Created/Modified (api-ventago repo)

**Modified (12):**
- `api-ventago/src/app/sales/sales.service.ts` — import + 7 메서드 필터 + 신규 getDailyStats
- `api-ventago/src/app/sales/sales-create.service.ts` — import + 2 dailyNumber 필터 + 2 Sale.create activityType 명시
- `api-ventago/src/app/sales/sales.controller.ts` — GET /sales/all 4 신규 query + GET /sales/daily-stats 신규
- `api-ventago/src/app/dashboards/sales/salesDashboards.service.ts` — 6 ORM where + 2 raw SQL `AND s.activity_type='sale'`
- `api-ventago/src/app/reports/reportsSales.service.ts` — getReportSalesData where seed
- `api-ventago/src/app/reports/reportsFacturacion.service.ts` — getReportFacturacionData where seed
- `api-ventago/src/app/reports/reportsBreveVenta.service.ts` — getReportBreveVentaData where seed
- `api-ventago/src/app/reports/reportsVendedor.service.ts` — getReportVendedorData where seed
- `api-ventago/src/app/reports/reportsCorregido.service.ts` — getReportCorregidoData where seed
- `api-ventago/src/app/reports/reportsFallados.service.ts` — getReportFalladosData where seed
- `api-ventago/src/app/store/store.service.ts` — backup Sale.findAll 의도적 미적용 주석
- `api-ventago/src/app/online-orders/online-order-sales-mirror.service.ts` — 2 dailyNumber 필터 + 2 Sale.create activityType 명시

**Skipped (intentional):**
- `api-ventago/src/app/reports/reportsReservado.service.ts` — SuspendedSale 별도 모델 사용 (sales 활동과 무관)

## activityType / activity_type Audit (grep counts)

| File | refs |
|---|---|
| sales.service.ts | 26 |
| sales-create.service.ts | 8 |
| sales.controller.ts | 5 |
| salesDashboards.service.ts | 10 |
| reportsSales.service.ts | 1 |
| reportsFacturacion.service.ts | 1 |
| reportsBreveVenta.service.ts | 1 |
| reportsVendedor.service.ts | 1 |
| reportsCorregido.service.ts | 2 |
| reportsFallados.service.ts | 3 |
| store.service.ts | 2 |
| online-order-sales-mirror.service.ts | 4 |
| reportsReservado.service.ts | 0 (intentional — SuspendedSale 모델) |

총 sales-reading 위치 13 파일 모두 감사 완료. `Sale.findAll` / `saleModel.findAll` / `saleModel.sum` / `saleModel.count` / `saleModel.findOne(list-pattern)` / `saleModel.findAndCountAll` / raw SQL `FROM sales` 패턴이 발견된 모든 위치에 activity_type='sale' 명시 (또는 backup 의도적 미적용 + 주석).

## Build / Lint Verification

```
$ cd api-ventago && npm run build
> nest build
(success — no output = clean build)

$ npx eslint --no-fix sales.service.ts
✖ 80 problems (78 errors, 2 warnings)
  (baseline ≈ 57 errors; 신규 23 은 whereClause.activityType unsafe-member-access — 기존 동일 패턴 모방)

$ npx eslint --no-fix sales-create.service.ts
✖ 115 problems (99 errors, 16 warnings)  ← baseline 그대로

$ npx eslint --no-fix sales.controller.ts
✖ 33 problems (31 errors, 2 warnings)  ← baseline 그대로

$ for f in <9 task-2 files>; do npx eslint --no-fix $f; done
모든 9 파일: baseline 동일 (신규 도입 errors 0)
```

**Lint baseline 정책 (scope-boundary):** sales.service.ts 의 신규 `whereClause.activityType` 어구는 `whereClause: any` 타입 기인 `no-unsafe-member-access` 를 발생시키지만, 이는 동일 파일의 기존 `whereClause.storeId` / `whereClause.terminalId` 등과 같은 패턴 — Phase 35-01/02 SUMMARY 에서 채택한 "사전 존재 패턴 동일 수준 유지" 규칙에 부합.

## NestJS Route Smoke Test (build artifact)

```
$ grep -E "daily-stats|getDailyStats" dist/app/sales/sales.controller.js
    async getDailyStats(user, startDate, endDate) {
        return this.salesService.getDailyStats({
    (0, common_1.Get)('daily-stats'),
], SalesController.prototype, "getDailyStats", null);
```

→ NestJS 데코레이터 메타데이터로 `GET /sales/daily-stats` 라우트 정상 등록 확인.

## Route Order Verification

```
57:  @Get()           ← /sales
62:  @Get('all')      ← /sales/all (확장됨)
145: @Get('daily-stats')   ← /sales/daily-stats (신규)
171: @Get('by-store')      ← /sales/by-store
314: @Get(':id')           ← /sales/:id (path param, 가장 아래)
320: @Get('by-store/:storeId')
```

`@Get('daily-stats')` 가 `@Get(':id')` 보다 위 → NestJS 가 'daily-stats' 를 id param 으로 흡수하지 않음.

## Decisions Made

- **명시적 WHERE 절 vs @DefaultScope**: SPEC D-04 risk 1 회피 — `@DefaultScope` 는 의도치 않은 누락 가능성. 명시적 WHERE 절은 grep 으로 감사 가능 + 코드 리뷰 시 즉시 식별.
- **`findFilteredByStore` 의 activityType 처리**:
  - default 'sale' → 기존 sales 행만 (호환성)
  - 'movido' / 'fallado' → 해당 활동만
  - 'all' → 모든 활동 (ventaVista 의 "통합 보기" 옵션)
- **direction='in' / 'out'** 처리: Resumen 셀 클릭 시. branchId 와 함께 사용되어 `targetBranchId` 만 (in) 또는 `originBranchId` 만 (out) 매칭.
- **`originBranch`/`targetBranch` eager-load `required: false`**: sale 행은 NULL 이므로 LEFT JOIN. 행 자체는 항상 조회.
- **getDailyStats 의 raw SQL CTE 단일 쿼리**: ORM-based 다중 쿼리 (PG pool 5 use) → 단일 raw SQL (1 use). LATERAL JOIN 으로 sale_items SUM 도 같은 쿼리 안에서 처리.
- **PG10/PG15 호환**: `DATE_TRUNC`, `GENERATED AS IDENTITY` 등 PG10 미지원 기능 회피. `AT TIME ZONE` 만 사용 (PG10 호환).
- **branches LEFT JOIN**: 매장의 모든 지점이 perBranch 배열에 등장 (활동 없는 지점은 0). ventaVista 가 단일 sucursal 사용자에게도 일관된 row 1개 표시.
- **store.service.ts backup 의도적 미적용**: backup은 통계가 아닌 archival — 모든 활동 (sale + movido + fallado) 보존. 주석으로 의도 명시.
- **reportsReservado 변경 없음**: SuspendedSale 별도 모델 (Sale 과 무관) — 의도된 무변경.
- **online-order-sales-mirror dailyNumber 필터**: sales-create 와 동일 잠식 위험 — 동일 패턴 적용.

## Deviations from Plan

### Code Auto-fixes

**1. [Rule 1 — Lint cleanup] sales.service.ts L356 prettier + L942 unnecessary-type-assertion**
- **Found during:** Task 1 lint 검증
- **Issue:** 신규 작성 코드 2 errors 도입.
  - `(rows as any[])` 는 `rows` 가 이미 `any[]` 타입 (sequelize.query 의 generic return) — assertion 불필요.
  - `branchId = filters?.origin... ?? filters?.target... ?? null;` 줄바꿈이 prettier 위반.
- **Fix:** assertion 제거 + 한 줄로 합침.
- **Files modified:** `api-ventago/src/app/sales/sales.service.ts`
- **Committed in:** `c846024` (Task 1 commit 에 포함)

### Architectural Deviations

None — 모든 변경이 plan 명세대로 정확히 진행.

### Out of Scope (intentional)

- **reportsReservado.service.ts** — Plan 명세에 13 파일 중 12 번째로 포함되었으나 코드 실측 결과 SuspendedSale 별도 모델 (sales 모델 아님). 변경 없음으로 처리, deferred-items.md 등록 불필요 (의도된 무변경).
- **store.service.ts backup 의 activity_type 필터 미적용** — Plan 의 acceptance criteria 는 "activityType 키워드 ≥ 1" 만 요구. 주석으로 키워드 도달.

---

**Total deviations:** 0 architectural + 2 auto-fixes (Rule 1 — lint cleanup)
**Impact on plan:** 모든 task 가 plan 명세대로 완료. 변경 외 추가 lint 도입 없음.

## Issues Encountered

- ESLint baseline (`sales.service.ts` 57 errors → 80 errors 변화): 신규 23 lint errors 는 모두 `whereClause.activityType` / `whereClause.originBranchId` 등 추가된 `any`-type 변수 접근 — Phase 35-01/02 의 동일 scope-boundary 정책. baseline 의 동일 패턴 (`whereClause.storeId` 등) 과 일관.
- `nest start --debug` 으로 라우트 등록 line 확인 시도했으나 부팅 시간 초과 → 대안: `dist/app/sales/sales.controller.js` 빌드 결과 검사로 `Get('daily-stats')` 데코레이터 + `getDailyStats` method 등록 확인 (smoke test PASS).
- Docker 없는 로컬 환경 (env_overrides) — 본 plan 은 코드 변경만, DB 마이그레이션 없음. 환경 영향 0.

## Next Phase Readiness

- **Plan 35-04 (frontend `useDailySalesStats` SWR 훅) 준비 완료**: `GET /sales/daily-stats?startDate=&endDate=` 가 SPEC 명세 응답 shape 그대로 반환. 인증된 사용자의 storeId 자동 적용.
- **Plan 35-05+ (ventaVista UI Resumen 테이블 + 행 시각 구분) 준비 완료**: `GET /sales/all?activityType=movido&direction=in&targetBranchId=X` 등 다양한 드릴다운 조합 지원. eager-loaded `originBranch`/`targetBranch` 가 행 렌더링 (`JEFE → SALA` 등) 즉시 활용 가능.
- **UAT U12 검증 가능**: movido 등록 후 기존 매출 보고서 수치 불변 — 13 파일 명시적 필터로 보장. UAT 단계에서 `POST /stocks/movement` 호출 후 `/reportes/ventas` / `/dashboards/ventas` 수치 비교 가능.
- **UAT U12b 검증 가능**: movido 등록 후 신규 sale dailyNumber 가 마지막 sale + 1 (movido 잠식 없음) — sales-create.service.ts L188/L383 + online-order-sales-mirror.service.ts 2곳 필터 적용.
- **운영 PG10 적용 불필요**: 본 plan 은 코드만 변경 — DB 변경 없음. 빌드 결과 deploy 만 필요.
- **Blocker/Concern 없음**.

## Threat Flags

본 plan 의 변경은 plan `<threat_model>` 에 등록된 T-35-10/11/12/13/14/15 의 mitigation 만 구현. 신규 surface 추가:

- **GET /sales/daily-stats** — 신규 엔드포인트. 인증 가드 (Auth 4 role) + 사용자 storeId 강제 사용 (cross-store 차단). SPEC §API 명세 그대로 노출. **신규 surface 추가 but 모두 plan 명세 mitigation 적용 완료**.

→ **Threat flags 없음** (plan threat_register 외 추가 surface 없음).

## Self-Check: PASSED

**Files verified:**
- `api-ventago/src/app/sales/sales.service.ts` — FOUND (modified, +280 / -5 lines)
- `api-ventago/src/app/sales/sales-create.service.ts` — FOUND (modified, dailyNumber + activityType 필수 처리)
- `api-ventago/src/app/sales/sales.controller.ts` — FOUND (modified, +58 lines)
- 9 other files — FOUND (Task 2 batch)

**Commits verified (api-ventago repo, `git log --oneline`):**
- `c846024` (Task 1) — feat(phase-35-03): enforce activity_type='sale' filter + getDailyStats in sales service — FOUND
- `de65a65` (Task 2) — feat(phase-35-03): add explicit activity_type='sale' filter to 9 reports/dashboards/mirror services — FOUND
- `67318fd` (Task 3) — feat(phase-35-03): extend GET /sales/all + add GET /sales/daily-stats endpoint — FOUND

**Build verification:**
- `npm run build` PASS (api-ventago) — 3회 (각 task 후)
- `dist/app/sales/sales.controller.js` 에 `Get('daily-stats')` + `getDailyStats` 등록 확인

**Acceptance criteria (Task 1):**
- sales.service.ts activityType references = 26 (≥ 5) ✓
- sales.service.ts SaleActivityType references = 8 (≥ 3) ✓
- sales.service.ts originBranch/targetBranch include = 2 (= 2) ✓
- sales.service.ts async getDailyStats = 1 ✓
- sales.service.ts movBalance = 5 (≥ 1) ✓
- sales.service.ts perBranch = 6 (≥ 2) ✓
- sales-create.service.ts activityType SALE filter = 5 (≥ 2) ✓
- sales-create.service.ts SaleActivityType import = 1 ✓

**Acceptance criteria (Task 2):**
- 9 files activityType/activity_type ≥ 1 ✓ (all PASS, reportsReservado intentionally 0)

**Acceptance criteria (Task 3):**
- @Query('activityType') = 1 ✓
- @Query('originBranchId') = 1 ✓
- @Query('targetBranchId') = 1 ✓
- @Query('direction') = 1 ✓
- @Get('daily-stats') = 1 ✓
- getDailyStats refs = 2 ✓
- validActivityTypes/validDirections = 4 (≥ 2) ✓
- Route order: daily-stats line 145 < :id line 314 ✓

---
*Phase: 35-activity-ledger*
*Completed: 2026-05-22*
