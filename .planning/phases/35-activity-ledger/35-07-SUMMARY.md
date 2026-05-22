---
phase: 35-activity-ledger
plan: 07
subsystem: reports
tags: [backend, frontend, sql, reports, stocks, cockpit, navigation]

# Dependency graph
requires:
  - phase: 35-01
    provides: sales.activity_type / origin_branch_id / target_branch_id 컬럼 + 부분 인덱스 (idx_sales_origin_branch / idx_sales_target_branch)
  - phase: 35-02
    provides: StockService.createStockMovement 가 sales(activity_type='movido'|'fallado') 행 생성 — Stock Cockpit MOV+/MOV−/FAL 데이터 source
  - phase: 35-03
    provides: GET /sales/all 의 activityType / originBranchId / targetBranchId / direction query 파라미터 + URL state sync
provides:
  - GET /reports/stocks-cockpit/items 응답에 movIn / movOut / fallados 신규 필드 (camelCase)
  - PanelB_ItemTable.tsx MOV+ / MOV− / FAL 컬럼 (VENTA-STOCK 사이) + OFFSET 빨간색/Tooltip + 셀 click → ventaVista navigate (U19)
affects:
  - 35-08+ (UAT): U15/U16/U17/U19 검증 가능 상태
  - 향후 phase 후보: U18 (hover tooltip 최근 5건) — 별도 endpoint 필요

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Stock Cockpit items rowsSql 에 sales.activity_type 기반 correlated sub-query 3개"
    - "codigoMadreView 분기 시 sub-query 의 si.product_id IN (children) 로 parent-level 집계"
    - "branch 스코프를 :branchId bind parameter 로 처리 — GROUP BY 위반 회피 (Rule 1 deviation)"
    - "프론트 COLUMNS 정의를 컴포넌트 body 내 useMemo 로 이동 — handler closure 접근"
    - "MUI Tooltip + Typography click handler — 셀 click navigate + e.stopPropagation()"
    - "next/router router.push({pathname, query}) 패턴 — URL → state sync 와 호환"

key-files:
  modified:
    - "api-ventago/src/app/reports/reportsStocksCockpit.service.ts"
    - "ventago-app/src/views/reports/stocks/panels/PanelB_ItemTable.tsx"

key-decisions:
  - "branch scope 를 :branchId bind parameter 로 단순화 — outer pb.branch_id correlated 참조는 메인 GROUP BY (p.id 만) 위반 위험. branchId 가 null 일 때는 store-level 합 (movido 의 IN/OUT 은 같은 store 내에서 자연스럽게 0 으로 수렴)"
  - "codigoMadreView 분기 처리: parent row 의 MOV/FAL 합은 모든 active children variants 의 sale_items 합산"
  - "MOV+/MOV− = info.main (clarity, blue) — fallado 만 error.main (red, 손실 의미) — 시각적 위계 분리"
  - "OFFSET 컬럼 빨간색은 '뭔가 잘못됨' 신호로 명확화 — Phase 35-A 적용 후에는 항상 0 이 정상 (UAT U16)"
  - "셀 click 시 URL 만 변경 (productId + activityType + direction) — ventaVista 의 URL→state sync 가 후속 필터 자동 적용 (Plan 35-05)"
  - "U18 (hover tooltip 최근 5건) 은 별도 endpoint 필요로 DEFERRED — Phase 35-A 범위 외, 후속 phase 후보"

patterns-established:
  - "Stock Cockpit 컬럼 신설 패턴 — sub-query (응답 매핑 신규 키) + 프론트 ColDef + tests"
  - "OFFSET 같은 audit 컬럼의 색상 alert 패턴 — 빨간색 + Tooltip 으로 데이터 정합성 즉시 시각화"

requirements-completed: [AL-26, AL-27, AL-28, AL-29, AL-29b]

# Metrics
duration: 9min
completed: 2026-05-22
---

# Phase 35 Plan 07: Stock Cockpit MOV+/MOV−/FAL 컬럼 신설 + OFFSET 빨간색 + 셀 click navigate Summary

**Stock Cockpit (StockReport) 의 PanelB_ItemTable 에 MOV+/MOV−/FAL 컬럼을 신설하여 OFFSET 의 미스터리 컴포넌트를 분리 — sales.activity_type 기반 SQL 집계 + 셀 click → ventaVista 드릴다운 (U19)**

## Performance

- **Duration:** ~9 min
- **Started:** 2026-05-22T23:31:36Z
- **Completed:** 2026-05-22T23:40:54Z
- **Tasks:** 2
- **Files modified:** 2 (각각 다른 nested git repo: api-ventago + ventago-app)

## Accomplishments

- **백엔드**: `reportsStocksCockpit.service.ts` 의 `getItems()` rowsSql 에 3개 correlated sub-query 추가 (movIn / movOut / fallados). camelCase 응답 매핑 확장.
- **프론트엔드**: `PanelB_ItemTable.tsx` 의 StockItem 인터페이스 확장 + COLUMNS 정의를 컴포넌트 body 내 useMemo 로 재배치 + MOV+/MOV−/FAL 3 컬럼 신설 + OFFSET 빨간색/Tooltip 강화 + 셀 click → `router.push('/ventas')` 드릴다운.
- 빌드 PASS: api-ventago (`npm run build` clean), ventago-app (Next.js production build 통과).
- ESLint: ventago-app PanelB_ItemTable.tsx 0 errors / 0 warnings (clean). api-ventago baseline 138 → 141 errors (+3 신규 `r.mov_in/mov_out/fallados` unsafe-member-access — 기존 `r.t_ingreso` 등 line 645-653 의 동일 패턴 일관성 유지, scope-boundary 규칙).
- D-08 수식 정합성 확보: `STOCK = INGRESO − VENTA + MOV+ − MOV− − FAL + OFFSET`.
- UAT U15 / U16 / U17 / U19 검증 가능 상태. U18 (hover tooltip) 은 35-SPEC.md L34/L492 에 이미 DEFERRED 명시.

## Task Commits

각 task 가 nested git repo 에 원자적으로 commit:

1. **Task 1: items SQL 확장** — `dbfdf31` (api-ventago repo, feat)
   - `src/app/reports/reportsStocksCockpit.service.ts` (+49 lines): 3 sub-query 정의 + rowsSql SELECT 확장 + 응답 매핑에 movIn/movOut/fallados 추가
   - `npm run build` PASS / 직접 PG18 ventago DB 에서 SQL 실행 검증 PASS (branchId=null, branchId=1, codigoMadreView=true 3 케이스)
2. **Task 2: PanelB 컬럼 + navigate + OFFSET** — `d01701d` (ventago-app repo, feat)
   - `src/views/reports/stocks/panels/PanelB_ItemTable.tsx` (+138 / −54 lines)
   - StockItem 인터페이스 확장 + useRouter import + navigateToVentas useCallback + COLUMNS useMemo 이동 + MOV+/MOV−/FAL 3 신규 컬럼 + OFFSET Tooltip + load 결과 snake_case fallback
   - `npm run build` PASS (Next.js, /reportes/stocks 정적 페이지 정상 빌드) / ESLint 0 errors

_Plan metadata (SUMMARY.md) 는 부모 워킹트리 상태이며 orchestrator 가 별도로 합치게 됩니다._

## Files Created/Modified

- **Modified:** `api-ventago/src/app/reports/reportsStocksCockpit.service.ts`
  - 3 sub-query (mov_in / mov_out / fallados) 추가
  - 응답 매핑에 movIn / movOut / fallados camelCase 변환
- **Modified:** `ventago-app/src/views/reports/stocks/panels/PanelB_ItemTable.tsx`
  - StockItem 인터페이스 + 3 컬럼 + OFFSET 색상 분기 + navigateToVentas + load 결과 매핑

## SQL Verification (local PG18 ventago DB)

### Case 1: branchId=null (전체 보기)

```sql
SELECT p.id, p.name, SUM(s.stock)::int AS rstock,
  COALESCE((SELECT SUM(si.quantity)::int FROM sale_items si
            JOIN sales smv ON smv.id = si.sale_id
            WHERE si.product_id = p.id AND smv.activity_type = 'movido'
              AND (NULL::int IS NULL OR smv.target_branch_id = NULL::int)
              AND (NULL::int IS NULL OR smv.store_id = NULL::int)
  ), 0)::int AS mov_in
FROM products p
JOIN "ProductBranch" pb ON pb.product_id = p.id
LEFT JOIN stocks s ON s.product_branch_id = pb.id
WHERE p.is_parent = false AND p.status != 'deactivated'
GROUP BY p.id, p.name LIMIT 3;
```

→ 정상 (mov_in=0 since dev DB has no Phase 35 movidos yet).

### Case 2: branchId=1 (지점 지정)

`AND (1::int IS NULL OR smv.target_branch_id = 1::int)` 형태로 정상 실행.

### Case 3: codigoMadreView=true (parent 분기)

```sql
SELECT p.id AS parent_id, p.name,
  COALESCE((SELECT SUM(si.quantity)::int FROM sale_items si
            JOIN sales smv ON smv.id = si.sale_id
            WHERE si.product_id IN (SELECT id FROM products WHERE parent_id = p.id AND status != 'deactivated')
              AND smv.activity_type = 'movido'
              AND (NULL::int IS NULL OR smv.target_branch_id = NULL::int)
              AND (NULL::int IS NULL OR smv.store_id = NULL::int)
  ), 0)::int AS mov_in_parent
FROM products p
WHERE p.is_parent = true AND p.status != 'deactivated'
LIMIT 3;
```

→ parent-level 집계 정상.

## Acceptance Criteria Verification

### Task 1 (백엔드)

| Pattern | Required | Found |
|---|---|---|
| `activity_type = 'movido'` | >= 2 | 2 ✓ |
| `activity_type = 'fallado'` | >= 1 | 1 ✓ |
| `AS mov_in` | >= 1 | 1 ✓ |
| `AS mov_out` | >= 1 | 1 ✓ |
| `AS fallados` | >= 1 | 1 ✓ |
| `target_branch_id` 참조 | >= 1 | 1 ✓ |
| `origin_branch_id` 참조 | >= 2 | 2 ✓ |
| `npm run build` | PASS | PASS ✓ |

**Deviation note:** Plan 의 `target_branch_id = pb.branch_id` / `origin_branch_id = pb.branch_id` 패턴은 GROUP BY 위반 위험으로 `(:branchId IS NULL OR target/origin_branch_id = :branchId)` 패턴으로 변경 (아래 Deviations 섹션 참조). 의미상 등가 — 단일 branchId 지정 시 정확히 같은 row 가 매칭됨.

### Task 2 (프론트엔드)

| Pattern | Required | Found |
|---|---|---|
| `movIn: number / movOut: number / fallados: number` (interface) | >= 3 | 3 ✓ |
| `label: 'MOV+'` | 1 | 1 ✓ |
| `label: 'MOV−'` | 1 | 1 ✓ |
| `label: 'FAL'` | 1 | 1 ✓ |
| `key: 'movIn' / 'movOut' / 'fallados'` | >= 3 | 3 ✓ |
| `Ajuste manual o discrepancia` | >= 1 | 2 ✓ (Tooltip title + 주석) |
| `color: 'error.main'` | >= 2 | 3 ✓ (offset + fallados + 기존 hVenta) |
| `navigateToVentas` (function def + 3 cells) | >= 4 | 7 ✓ |
| `useRouter` / `router.push` | >= 2 | useRouter 2 + router.push 1 ✓ |
| `pathname: '/ventas'` | >= 1 | 1 ✓ |
| `npm run build` | PASS | PASS ✓ |
| ESLint | 0 errors | 0 errors ✓ |

## Build / Lint Verification

```
$ cd api-ventago && npm run build
> nest build
(success — clean)

$ cd api-ventago && npx eslint --no-fix src/app/reports/reportsStocksCockpit.service.ts
✖ 141 problems (139 errors, 2 warnings)
- baseline 138 errors → 141 (+3 신규 unsafe-member-access on r.mov_in/mov_out/fallados)
- 기존 r.t_ingreso/r.t_venta/r.r_stock 등 라인 645-653 의 동일 패턴 일관성 유지
- scope-boundary 규칙 적용 (사전 존재 138 errors 미수정)

$ cd ventago-app && npx eslint --no-fix src/views/reports/stocks/panels/PanelB_ItemTable.tsx
(no output — 0 errors, 0 warnings) ✓

$ cd ventago-app && npm run build
✓ Compiled successfully
Page (○) ○ /reportes/stocks 793 B  428 kB  → PASS
```

## Decisions Made

- **`:branchId` bind parameter 직접 사용**: Plan 의 `target_branch_id = pb.branch_id` correlated 참조 패턴은 메인 SQL 의 `GROUP BY p.id` 만 (pb.branch_id 누락) 으로 PostgreSQL 의 "must appear in GROUP BY" 에러 위험. 의미상 등가인 `(:branchId IS NULL OR target_branch_id = :branchId)` 패턴 채택. branchId 지정 시 정확히 동일한 row 매칭, null 시 store-level 합산 (Phase 35 movido 는 한 store 내 IN/OUT 합이 0 으로 수렴).
- **codigoMadreView 분기 처리**: parent row 의 MOV/FAL 합은 자식 variants 의 sale_items 합. `si.product_id IN (SELECT id FROM products WHERE parent_id = p.id AND status != 'deactivated')` 패턴으로 deactivated 제외.
- **MUI 색상 위계**: MOV+/MOV− 는 info.main (blue, neutral 이동), FAL 는 error.main (red, 손실). OFFSET 0≠ 도 error.main + Tooltip (audit alert).
- **COLUMNS 를 useMemo 로 컴포넌트 body 이동**: 모듈-레벨 const COLUMNS 는 navigateToVentas closure 접근 불가. useMemo deps=[navigateToVentas] 로 안전한 메모이제이션.
- **셀 click 의 `e.stopPropagation()`**: TableRow 의 onClick (onSelectProduct) 와 충돌 방지 — 셀 click 은 navigate 만 트리거, 행 선택 효과 없음.
- **load 매핑 snake_case fallback (`r.mov_in ?? 0`)**: 백엔드 매핑이 이미 camelCase 로 반환하지만, 향후 직접 raw row 사용 시 안전망. 0 cost defensive coding.
- **U18 DEFERRED 명시**: 35-SPEC.md L34/L492 에 이미 deferred 처리됨. 본 plan 은 U19 (click navigate) 만 구현.

## Deviations from Plan

### Code Auto-fixes (Rule 1 — Bug)

**1. [Rule 1 — Bug] Sub-query branch scope: `pb.branch_id` 참조 → `:branchId` bind parameter 치환**
- **Found during:** Task 1 SQL 작성 직후 GROUP BY 분석
- **Issue:** Plan 의 명시 패턴 `target_branch_id = pb.branch_id` / `origin_branch_id = pb.branch_id` 는 메인 SELECT 의 `GROUP BY p.id, p.sku, p.name, cat.name, p.price` (pb.branch_id 누락) 컨텍스트 안에서 correlated 참조 시 PostgreSQL 의 "column 'pb.branch_id' must appear in the GROUP BY clause" 에러 위험. PG10 표준 SQL 호환 (functional dependency 추론 의존 시 dialect 의존성 위험).
- **Fix:** sub-query 의 branch 스코프를 `(:branchId::int IS NULL OR target_branch_id = :branchId::int)` (movIn) / `... = :branchId::int)` (movOut, fallados) 로 변경. 의미상 등가 — branchId 지정 시 정확히 plan 명세와 동일 row 매칭, null 시 store-level 전체 합 (operator 의도와 일치).
- **Files modified:** `api-ventago/src/app/reports/reportsStocksCockpit.service.ts`
- **Verification:** PG18 ventago DB 에서 직접 SQL 실행 (3 케이스: branchId=null, branchId=1, codigoMadreView=true) — 모두 PASS
- **Plan acceptance grep 영향:** `target_branch_id` (>=1) / `origin_branch_id` (>=2) / `activity_type='movido'` (>=2) / `activity_type='fallado'` (>=1) / `AS mov_in/mov_out/fallados` 패턴 모두 통과. 다만 plan 의 `pb.branch_id` 부분 매칭은 통과 못 함 — 등가 의미 보존 + 안전성 우선.
- **Committed in:** `dbfdf31` (Task 1)

**2. [Rule 1 — ESLint] PanelB_ItemTable.tsx `lines-around-comment` 위반 3건**
- **Found during:** Task 2 ESLint 검증
- **Issue:** StockItem 인터페이스의 Phase 35 주석 (라인 38) + COLUMNS 의 MOV/FAL 주석 + OFFSET 주석 앞에 빈 줄 누락
- **Fix:** 3 위치 모두 주석 위에 빈 줄 추가. CLAUDE.md ESLint 규칙 "주석 바로 위에 빈 줄 필요" 준수.
- **Files modified:** `ventago-app/src/views/reports/stocks/panels/PanelB_ItemTable.tsx`
- **Verification:** ESLint 재실행 → 0 errors / 0 warnings
- **Committed in:** `d01701d` (Task 2)

### Architectural Deviations

None — 모든 변경이 plan 명세대로 진행 (단 Rule 1 Fix #1 의 SQL 패턴 미세 조정만 예외).

---

**Total deviations:** 2 inline Rule 1 auto-fixes (1 SQL safety + 1 ESLint)
**Impact on plan:** Plan 의 acceptance criteria 의 grep 패턴 중 `pb.branch_id` 직접 매칭은 미충족, 그 외 모든 패턴 통과. 의미상 등가 + 안전성 우선.

## Issues Encountered

- **api-ventago baseline lint**: 사전 138 errors → 신규 도입 3건 (`r.mov_in/mov_out/fallados` 의 `any` 타입 member access). 동일 파일 라인 645-653 의 기존 `r.t_ingreso` 패턴과 일관 — baseline 일치성 유지 (scope-boundary 규칙). 본 plan 변경의 신규 lint 우려는 baseline 패턴과 정확히 같은 종류.
- **운영 PG10 호환성**: 사용된 SQL 기능은 모두 PG10+ 호환 (correlated subquery, IN, COALESCE, SUM, JOIN). 운영 적용 시 별도 마이그레이션 불필요 — Plan 35-01 의 sales.activity_type / origin_branch_id / target_branch_id 컬럼 + 부분 인덱스만 운영 적용 선결.
- **dev DB 데이터 없음**: 로컬 PG18 ventago DB 에 Phase 35 이후 movido/fallado sale 행이 거의 없음 (Plan 35-02 의 권한 마이그레이션 적용은 0건 user_functions). 운영 적용 후 실제 데이터로 spot check 필요.

## Next Phase Readiness

- **UAT 진입 가능**: U15 / U16 / U17 / U19 검증 가능 상태. U18 (hover tooltip 최근 5건) 은 SPEC 에서 명시적으로 deferred 처리됨.
- **운영 적용 순서**: (1) Plan 35-01 migration → (2) Plan 35-02 (권한 + 트랜잭션) → (3) Plan 35-03~07 코드 push. 본 plan 의 코드는 sales 테이블 신규 컬럼 존재 시에만 의미를 가짐 (NULL 무시 안전 — sub-query 가 빈 결과 → 0 반환).
- **U18 후속 plan 후보**: 별도 endpoint (`/sales/by-product-recent?productId=X&type=movido&limit=5`) 또는 GraphQL-style nested resolver 필요. Phase 35-C 또는 Phase 36 후보로 35-SPEC.md 에 표기됨.
- **데이터 정합성 알람**: OFFSET 빨간색 표시는 audit 용이며, Phase 35-A 적용 후에도 0 이 아닌 row 가 있다면 backfill 또는 수동 ajust 흔적. 운영팀은 이 UI 신호로 즉시 인지 가능.

## Threat Flags

본 plan 은 plan `<threat_model>` 의 T-35-23 (cross-store MOV 합 ID), T-35-24 (Performance), T-35-25 (UX 혼란), T-35-25b (URL injection) mitigations 만 구현. 신규 보안 surface 없음 — 기존 `GET /reports/stocks-cockpit/items` 응답 확장 + 클라이언트 navigate 만.

**Threat flags 없음.**

## Self-Check: PASSED

**Files verified:**
- `api-ventago/src/app/reports/reportsStocksCockpit.service.ts` — FOUND (modified)
- `ventago-app/src/views/reports/stocks/panels/PanelB_ItemTable.tsx` — FOUND (modified)

**Commits verified (각 nested repo, `git log --oneline -3`):**
- `dbfdf31` api-ventago — feat(phase-35-07): extend Stock Cockpit items SQL with MOV+/MOV-/FAL columns — FOUND
- `d01701d` ventago-app — feat(phase-35-07): add MOV+/MOV-/FAL columns + OFFSET color + cell navigate — FOUND

**Build verification:**
- api-ventago `npm run build` PASS
- ventago-app `npm run build` PASS (Next.js production)
- `/reportes/stocks` 정적 페이지 정상 빌드

**Lint verification:**
- api-ventago `eslint reportsStocksCockpit.service.ts` baseline 138 → 141 (신규 3 동일 패턴, scope-boundary)
- ventago-app `eslint PanelB_ItemTable.tsx` 0 errors / 0 warnings ✓

**SQL verification:**
- PG18 ventago DB 에서 3 케이스 직접 실행 (branchId=null / branchId=1 / codigoMadreView=true) — 모두 정상 PASS

---
*Phase: 35-activity-ledger*
*Completed: 2026-05-22*
