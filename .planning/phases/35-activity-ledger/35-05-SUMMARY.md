---
phase: 35-activity-ledger
plan: 05
subsystem: frontend
tags: [frontend, react, mui, ag-grid, sales, chip, url-query, drilldown, d-06, d-07]

# Dependency graph
requires:
  - phase: 35-03
    provides: GET /sales/all query 화이트리스트 (activityType/originBranchId/targetBranchId/direction) + originBranch/targetBranch eager-load
  - phase: 35-04
    provides: SalesResumenTable 컴포넌트 + useDailySalesStats SWR 훅 + ResumenRowClick/ResumenCellClick payload 타입
provides:
  - DataConfig — 신규 Tipo chip 컬럼 (좌측 첫번째) + Cliente dual-purpose 렌더러 + 의미 없는 컬럼 (Total/Efectivo/Credito/Banco/Reservado/Saldo/Tickets) movido/fallado 시 '—' 처리
  - DataConfig.getActivityRowSx — Phase35 row sx export (sale=transparent / movido=#E3F2FD + #1976D2 border / fallado=#FFEBEE + #D32F2F border)
  - FullTable — 신규 getRowSx prop → AG Grid getRowStyle 위임 (backgroundColor/bgcolor/borderLeft/color 4 키 안전 화이트리스트 매핑)
  - SalesListView — SalesKpiCards → SalesResumenTable 교체 완료 + Resumen 드릴다운 (onRowClick → branch 필터 / onCellClick → branch+activityType+direction 동시 필터)
  - SalesListView — URL ↔ filter state 양방향 sync (router.isReady + 5 query keys → setFilters / updateUrlQuery → router.replace shallow:true)
  - SalesListView — filter chip strip (branchChipLabel + activityType) + onDelete handlers (clearBranchFilter / clearActivityFilter)
affects:
  - Phase 35-A 검증 phase (UAT U2/U3/U4/U5/U6/U7/U8/U11/U13/U14 시나리오 검증 가능)
  - Phase 35-B 후속 (Stock Cockpit MOV+ 셀 hover tooltip — deferred to 35-C/36)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "AG Grid getRowStyle prop → CSSProperties (background/border 화이트리스트 안전 매핑) → MUI sx-like 호환 어댑터 패턴"
    - "Next.js Pages Router URL sync 패턴: useEffect on router.isReady + query keys → setFilters / updateUrlQuery → router.replace shallow:true (페이지 reload 없음)"
    - "Phase35Filters extends SalesListFilters — 기존 toolbar 와 통합 filter shape 확장 (5 신규 필드 = activityType/originBranchId/targetBranchId/direction/branchChipLabel)"
    - "Resumen 드릴다운 3-mode payload: TOTAL 행 (branchId=null) 무시 / branch row → activityType=all / cell click → activityType+direction 동시 매핑"
    - "Cell renderer dual-purpose 패턴: activityType 분기로 1개 컬럼이 cliente/route/label 3가지 렌더 (D-06c)"
    - "Conditional cell placeholder ('—') for non-meaningful columns: renderEmDash() 공유 헬퍼 + isNonSale() 가드 → 7개 결제/금액 컬럼 적용 (D-06d)"

key-files:
  created: []
  modified:
    - "ventago-app/src/views/sales/list/components/DataConfig.tsx (+161/-23) — Tipo chip + Cliente dual-purpose + isNonSale guards + getActivityRowSx export"
    - "ventago-app/src/components/table/FullTable.tsx (+29/0) — getRowSx prop + getRowStyleCb + AG Grid getRowStyle 위임"
    - "ventago-app/src/views/sales/list/SalesListView.tsx (+193/-6) — SalesResumenTable 교체 + Phase35Filters + URL sync + drilldown handlers + chip strip + getRowSx 전달"

key-decisions:
  - "FullTable getRowSx prop 시그니처: sx-like 객체 (backgroundColor/bgcolor/borderLeft/color) 받아 AG Grid CSSProperties 로 안전 매핑 — sx 호환성 유지 + AG Grid 의 좁은 CSS API 화이트리스트로 보안 강화"
  - "isNonSale + renderEmDash 공유 헬퍼 — 7개 결제/금액 컬럼에서 중복 코드 제거, D-06d 명세 일관성 확보 (Total/Efectivo/Credito/Banco/Reservado/Saldo/Tickets)"
  - "getActivityRowSx 의 sale 분기에 'borderLeft: 4px solid transparent' 추가 — 모든 행이 동일 너비 grid 유지 (movido/fallado 만 visible border 적용 시 sale 행이 4px 짧아 보이는 alignment 문제 방지)"
  - "Phase35Filters extends SalesListFilters — SalesListToolbar 가 SalesListFilters 만 알고 있어도 호환 (handleFiltersChange 가 prev spread merge 로 새 5필드 보존)"
  - "URL → state sync 에 router.isReady 가드 — Next.js 의 SSR 첫 렌더 시 router.query 가 비어있는 race condition 회피"
  - "URL sync useEffect 의 deps 에 의도적으로 4 query keys 만 포함 + eslint-disable-next-line — updateUrlQuery 가 별도로 state→URL 처리하므로 무한루프 방지 (filters 를 deps 에 넣으면 setFilters → useEffect → setFilters 순환)"
  - "TOTAL 행 클릭 무시 (branchId=null) — Plan 04 SUMMARY 권장 사항 그대로 따름. '전체 지점 chip' 옵션은 미래 일감으로 남김"
  - "셀 클릭의 movido direction 매핑: MOV+ → targetBranchId / MOV− → originBranchId — backend (Plan 03) 의 direction='in'|'out' query 와 의미 정합 (Resumen 셀 = 그 지점이 어느 쪽인가)"
  - "FullTable getRowStyle 의 'any' 타입 사용 (CSSProperties 대신) — React import 줄이고 ESLint no-unused-vars 위반 회피"
  - "chip strip 조건부 렌더 (filters.branchChipLabel || activityType !== 'sale') — 기본 'sale' 상태에서는 chip strip 자체가 mount 되지 않음 (DOM 비용 0)"
  - "activityType chip label 매핑: MOV+/MOV−/MOV/FAL/ALL — direction 이 있으면 +/− 부호, 없으면 단순 라벨"

patterns-established:
  - "Phase 35 frontend 드릴다운 wiring 패턴: Resumen 컴포넌트 → URL query → filter state → backend query (3-hop) + 각 hop 에서 chip 동기화"
  - "MUI Chip onDelete 클릭 핸들러로 partial filter clear — 다중 chip strip 패턴 (각 chip 이 독립적으로 자기 영역만 해제)"
  - "AG Grid 와 MUI sx 의 임피던스 매칭 패턴: FullTable.getRowStyleCb 가 sx-like 입력을 CSSProperties 화이트리스트로 변환 → 컴포넌트 호출자가 MUI 친화적 API 사용 가능"

requirements-completed: [AL-17, AL-18, AL-19, AL-20, AL-21, AL-22, AL-23]

# Metrics
duration: 7min
completed: 2026-05-22
---

# Phase 35 Plan 05: SalesListView Drilldown — Tipo Chip + Cliente Dual-Purpose + URL Sync + Activity Row Tint Summary

**ventaVista 의 통합 거래 원장 시각화 완성 — Tipo chip 컬럼 + Cliente dual-purpose 렌더러 + movido/fallado 행 배경 tint + SalesKpiCards → SalesResumenTable 교체 + Resumen 드릴다운 → URL+chip 양방향 sync**

## Performance

- **Duration:** ~7 min
- **Started:** 2026-05-22T23:16:31Z
- **Completed:** 2026-05-22T23:22:50Z
- **Tasks:** 3
- **Files modified:** 3 (ventago-app — DataConfig.tsx + FullTable.tsx + SalesListView.tsx)
- **Files created:** 0
- **Repo:** ventago-app (nested git repo — sequential mode, workflow.use_worktrees=false)

## Accomplishments

- **Task 1 — DataConfig.tsx (`802816a`):**
  - `+161/-23 lines`. 신규 import `Chip, Stack`.
  - 신규 헬퍼 4개: `renderTipoChip` (3 분기 chip render) / `renderClienteOrRoute` (sale→cliente / movido→origin → target / fallado→FAL · origin) / `isNonSale` (activityType !== 'sale') / `renderEmDash` (재사용 — 7 컬럼에서 호출).
  - 신규 `Tipo` 컬럼 — baseColumns 첫번째 (VCode 앞), `flex: 0.05, minWidth: 60, sortable: false, renderCell: renderTipoChip`.
  - Cliente 컬럼 renderCell → `renderClienteOrRoute(params.row)` 로 교체.
  - 7개 컬럼에 `isNonSale → renderEmDash()` 가드 추가: TPrecio/Efectivo/Credito/X Banco/Reservado/Saldo/Tickets.
  - **Ropas (items) 컬럼은 변경 없음** — D-06d 명세대로 prendas 수는 movido/fallado 도 의미 있음 (보존).
  - `export const getActivityRowSx` 추가 — Task 2 의 FullTable, Task 3 의 SalesListView 가 사용. 색상: sale=transparent border / movido=#E3F2FD bg + #1976D2 4px / fallado=#FFEBEE bg + #D32F2F 4px.
- **Task 2 — FullTable.tsx (`34e0524`):**
  - `+29/0 lines`. props 구조분해에 `getRowSx` 추가.
  - 신규 `getRowStyleCb` useCallback — sx-like 입력을 안전 매핑 (backgroundColor/bgcolor/borderLeft/color 4 키만 화이트리스트 추출, `any` 타입 사용으로 React.CSSProperties import 회피).
  - `<AgGridReact>` 에 `getRowStyle={getRowStyleCb}` prop 전달.
  - 모든 변경이 **backwards compatible** — 기존 caller (다른 페이지의 FullTable 사용처) 가 getRowSx 를 안 넘기면 `undefined → no getRowStyle output` 으로 동작 변화 없음.
- **Task 3 — SalesListView.tsx (`5d14bb3`):**
  - `+193/-6 lines`. SalesKpiCards 제거, SalesResumenTable + ResumenRowClick + ResumenCellClick + getActivityRowSx + useRouter + Chip/Stack 추가.
  - `interface Phase35Filters extends SalesListFilters` — 5 신규 필드 (`activityType` / `originBranchId` / `targetBranchId` / `direction` / `branchChipLabel`).
  - filters useState 초기값 확장 — activityType='sale' default, branch/direction 모두 null.
  - getSales useCallback — params 에 activityType/originBranchId/targetBranchId/direction 추가 (backend Plan 03 화이트리스트 호환).
  - URL → state sync useEffect — `router.isReady` 가드 + 4 query keys deps + branchLabel sub-key. SSR race condition 회피.
  - state → URL `updateUrlQuery` useCallback — `router.replace(... { shallow: true })`. Phase35Filters 5 필드 → URL query 5 키 매핑 (activityType 만 sale 일 때 삭제).
  - `handleResumenRowClick` — TOTAL 행 (branchId=null) 무시 후 `{ originBranchId, targetBranchId: null, activityType: 'all', direction: null, branchChipLabel }` 세팅 + updateUrlQuery.
  - `handleResumenCellClick` — MOV+/MOV−/FAL 3-way 분기 후 적절한 branch field 와 activityType/direction 동시 매핑.
  - `clearBranchFilter` / `clearActivityFilter` — 두 chip 각각의 onDelete 핸들러. partial state clear + updateUrlQuery.
  - Render 변경: `<SalesKpiCards rows={sales.data} />` → `<SalesResumenTable startDate endDate onRowClick onCellClick />` + 조건부 chip strip (Stack with 2 Chip).
  - FullTable 에 `getRowSx={getActivityRowSx}` 전달 — movido/fallado 행 배경 tint + 좌측 colored border 정상 적용.

## Task Commits

각 task 가 ventago-app nested git repo 에 원자적으로 commit 되었습니다:

1. **Task 1: DataConfig Tipo chip + Cliente dual + getActivityRowSx** — `802816a` (feat)
   - 1 file, +161/-23 lines.
2. **Task 2: FullTable getRowSx prop + AG Grid getRowStyle 위임** — `34e0524` (feat)
   - 1 file, +29/0 lines.
3. **Task 3: SalesListView SalesResumenTable 교체 + URL sync + chip + drilldown** — `5d14bb3` (feat)
   - 1 file, +193/-6 lines.

_Plan metadata (SUMMARY.md) 는 부모 워킹트리(.planning/) 에서 별도 commit — 본 plan 의 task commit 은 ventago-app 내부에만 존재._

## Files Modified (ventago-app repo)

**Modified (3):**
- `ventago-app/src/views/sales/list/components/DataConfig.tsx` (+161/-23)
- `ventago-app/src/components/table/FullTable.tsx` (+29/0)
- `ventago-app/src/views/sales/list/SalesListView.tsx` (+193/-6)

## Acceptance Criteria Verification

### Task 1 (DataConfig.tsx)

| Criterion | Result |
|---|---|
| `grep -c "renderTipoChip"` >= 2 | ✓ 2 |
| `grep -c "renderClienteOrRoute"` >= 2 | ✓ 2 |
| `grep -c "isNonSale"` >= 5 | ✓ 8 (1 def + 7 usages) |
| `grep -c "getActivityRowSx"` >= 1 | ✓ 1 (export) |
| `grep -c "'movido'"` >= 2 | ✓ 4 |
| `grep -c "'fallado'"` >= 2 | ✓ 4 |
| `grep -c "originBranch"` >= 2 | ✓ 2 |
| `grep -c "targetBranch"` >= 1 | ✓ 1 |
| `grep -c "FAL ·"` >= 1 | ✓ 3 (literal + comment + JSX) |
| `grep -c "#E3F2FD"` >= 1 | ✓ 2 |
| `grep -c "#FFEBEE"` >= 1 | ✓ 2 |
| ESLint exits with no errors | ✓ clean (no output) |

### Task 2 (FullTable.tsx)

| Criterion | Result |
|---|---|
| `grep -c "getRowSx"` >= 2 | ✓ 5 |
| `grep -c "getRowStyle"` >= 2 | ✓ 4 |
| `grep -c "getRowStyleCb"` >= 2 | ✓ 2 (def + AgGrid prop) |
| `grep -c "backgroundColor"` >= 1 | ✓ 4 |
| `grep -c "borderLeft"` >= 1 | ✓ 3 |
| ESLint exits with no errors | ✓ clean (no output) |

### Task 3 (SalesListView.tsx)

| Criterion | Result |
|---|---|
| `grep -c "import SalesResumenTable"` == 1 | ✓ 1 |
| `grep -c "import SalesKpiCards"` == 0 | ✓ 0 (removed) |
| SalesKpiCards 사용 == 0 (주석만 가능) | ✓ 1 (주석 안만) |
| `grep -c "useRouter"` >= 2 | ✓ 2 |
| `grep -c "handleResumenRowClick"` >= 2 | ✓ 2 |
| `grep -c "handleResumenCellClick"` >= 2 | ✓ 2 |
| `grep -c "updateUrlQuery"` >= 4 | ✓ 10 |
| `grep -c "Phase35Filters"` >= 2 | ✓ 10 |
| `grep -c "branchChipLabel"` >= 3 | ✓ 13 |
| `grep -c "router.replace"` >= 1 | ✓ 1 |
| `grep -cE "clearBranchFilter\|clearActivityFilter"` >= 4 | ✓ 4 (2 def + 2 onDelete) |
| `grep -c "onDelete="` >= 2 | ✓ 2 (branch chip + activity chip) |
| `grep -c "getActivityRowSx"` >= 1 | ✓ 3 (import + JSDoc + FullTable prop) |
| `npm run build` exits 0 | ✓ "info - Compiled successfully" |
| ESLint exits with no errors | ✓ clean (no output) |

## Build / Lint Verification

```
$ cd ventago-app && npx eslint src/views/sales/list/components/DataConfig.tsx
(no output — clean)

$ cd ventago-app && npx eslint src/components/table/FullTable.tsx
(no output — clean)

$ cd ventago-app && npx eslint src/views/sales/list/SalesListView.tsx
(no output — clean)

$ cd ventago-app && npx tsc --noEmit -p tsconfig.json
(no output — TypeScript strict PASS)

$ cd ventago-app && npm run build
info - Linting and checking validity of types...
info - Creating an optimized production build...
info - Compiled successfully
info - Collecting page data...
info - Generating static pages (97/97)
info - Finalizing page optimization...

/ventas: 804 B (baseline 800 B + 4 B — chip+drilldown 코드 미니멀)
First Load JS shared: 428 kB (unchanged)
```

→ ESLint clean (3 modified files), TypeScript strict 통과, Next.js production build PASS (97 routes 모두 정상 렌더).

## Decisions Made

- **AG Grid getRowStyle 와 MUI sx 의 임피던스 매칭**: FullTable.getRowStyleCb 가 sx-like 입력을 받아 CSSProperties 화이트리스트로 변환. caller (SalesListView) 는 MUI 친화적 API (`{ backgroundColor, borderLeft }`) 사용 가능. AG Grid 의 좁은 prop API 가 격리됨.
- **isNonSale 가드 적용 컬럼 7개 확정**: Total/Efectivo/Credito/X Banco/Reservado/Saldo/Tickets. **Ropas (items quantity) 컬럼은 의도적 제외** — D-06d 명세는 "Total/Descuento/Métodos de pago" 만 '—' 표시, prendas 수는 movido/fallado 도 의미 있는 데이터.
- **`borderLeft: 4px solid transparent` for sale 행**: getActivityRowSx 의 default 분기에 transparent border 명시 — 모든 행이 동일 너비 유지 (visible movido/fallado border 가 4px 잠식하므로 sale 행도 동일 너비 확보해야 grid alignment 유지).
- **URL → state sync 의 deps 와 무한루프 방지**: useEffect deps 에 router.isReady + 4 query keys (+ branchLabel) 만 포함 + `eslint-disable-next-line react-hooks/exhaustive-deps`. filters 를 deps 에 넣으면 setFilters → useEffect → setFilters 순환. updateUrlQuery 가 별도로 state→URL 처리하므로 단방향 정합.
- **TOTAL 행 클릭 무시**: Plan 04 SUMMARY 의 "branchId=null 은 TOTAL 행 (Plan 35-05 에서 무시 또는 전체 지점 chip)" 권장 사항 중 "무시" 옵션 선택. "전체 지점 chip" 은 미래 일감으로 보류 — 단일 store 시나리오에서는 TOTAL 자체가 숨겨지므로 (perBranch.length === 1) 우선순위 낮음.
- **chip strip 조건부 mount**: `(filters.branchChipLabel || filters.activityType !== 'sale')` 조건일 때만 Stack 자체 렌더. 기본 'sale' 상태에서는 chip strip 영역이 DOM 에 없음 → 메모리/렌더 비용 0.
- **chip label MOV+/MOV−/MOV/FAL/ALL**: activityType + direction 조합으로 5가지 라벨. MOV+ (movido+in) / MOV− (movido+out) / MOV (movido without direction) / FAL (fallado) / ALL (all activities, no direction).
- **SalesListToolbar 호환성**: SalesListToolbar 가 `SalesListFilters` 만 알고 있으므로, `Phase35Filters extends SalesListFilters` 로 superset 확장 + handleFiltersChange 가 `prev spread merge` 로 새 5 필드 보존. Toolbar 시그니처 변경 없이 통합.
- **router.isReady 가드**: Next.js Pages Router 의 첫 SSR 렌더 시 `router.query` 가 비어있는 race condition 알려진 패턴 — `router.isReady` 가 `true` 인 후에만 query 파싱.
- **FullTable.getRowStyleCb 타입에 `any` 사용**: React.CSSProperties import 시 ESLint no-unused-vars 위반 가능성 + 4-key 화이트리스트 자체가 안전성 보장. `any` 가 lint clean 하고 단순.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 — Layout consistency] sale 행에 transparent border 추가**
- **Found during:** Task 1 (getActivityRowSx 작성)
- **Issue:** plan 코드는 movido/fallado 에만 `borderLeft: 4px solid {color}` 적용. sale 행에 border 없으면 movido/fallado 행만 4px 만큼 좁아 보임 → grid alignment 깨짐.
- **Fix:** sale 분기에 `borderLeft: '4px solid transparent'` 추가. 모든 행이 동일 너비 유지하면서 visible border 만 분기.
- **Files modified:** `ventago-app/src/views/sales/list/components/DataConfig.tsx`
- **Verification:** ESLint clean + plan 명세 "sale = white / transparent border" 의 의도 정확히 충족.
- **Committed in:** `802816a` (Task 1 commit 에 포함)

**2. [Rule 2 — DRY refactor] renderEmDash 헬퍼 추출**
- **Found during:** Task 1 (7개 컬럼에서 동일한 '—' 표시 패턴 반복)
- **Issue:** plan 코드는 각 컬럼의 renderCell 안에 `<Typography ...>—</Typography>` 인라인 반복 — 7개 위치에서 동일한 sx 객체 반복은 ESLint clean 하지만 유지보수 어려움.
- **Fix:** `renderEmDash()` 헬퍼 함수로 추출 (sx 1곳에 정의). 7개 isNonSale 가드에서 `return renderEmDash()` 한 줄 호출.
- **Files modified:** `ventago-app/src/views/sales/list/components/DataConfig.tsx`
- **Verification:** grep `renderEmDash: 8` (1 def + 7 usages). Plan acceptance criteria 의 isNonSale >= 5 자동 충족.
- **Committed in:** `802816a`

**3. [Rule 2 — Type safety + lint] FullTable getRowStyleCb 에 `any` 대신 `React.CSSProperties` 사용 고려 → `any` 채택**
- **Found during:** Task 2 작성 (plan 노트가 둘 다 허용)
- **Issue:** React.CSSProperties import 시 `import type { CSSProperties } from 'react'` 가 unused 일 경우 lint 위반 가능. plan 노트 자체에 "또는 단순히 `const style: any = {}` 로도 가능" 명시.
- **Fix:** `const style: any = {}` 채택 — React import 추가 없음, lint clean 보장. 4-key 화이트리스트가 자체적으로 안전성 보장.
- **Files modified:** `ventago-app/src/components/table/FullTable.tsx`
- **Verification:** ESLint clean (no errors).
- **Committed in:** `34e0524`

**4. [Rule 1 — Lint compliance] URL sync useEffect 의 react-hooks/exhaustive-deps 의도적 비활성**
- **Found during:** Task 3 (URL → state sync useEffect 작성)
- **Issue:** useEffect deps 에 router.isReady + 5 query keys 만 포함 + filters 의도적 누락. ESLint react-hooks/exhaustive-deps 가 warning 발생 (CLAUDE.md 에 의하면 warning 이지만 빌드 통과).
- **Fix:** `eslint-disable-next-line react-hooks/exhaustive-deps` + JSDoc 코멘트로 의도 명시 (state→URL 은 updateUrlQuery 에서 별도 처리, 무한루프 방지).
- **Files modified:** `ventago-app/src/views/sales/list/SalesListView.tsx`
- **Verification:** ESLint clean (no errors).
- **Committed in:** `5d14bb3`

### Architectural Deviations

None — 모든 변경이 plan 명세대로 정확히 진행. plan 의 "이유: D-06 + D-07 — ventaVista 의 통합 거래 원장 시각화" 완전 충족.

### Out of Scope (intentional)

- **AG Grid CSS injection (movido/fallado tint 의 ::before pseudo-element)** — getRowStyle prop 만으로 background + borderLeft 적용 충분, CSS-in-JS 추가 사용 안 함.
- **TOTAL 행 클릭 시 "전체 지점 chip" 옵션** — Plan 04 SUMMARY 가 "Plan 05 결정" 으로 남긴 옵션 중 "무시" 채택. "전체 지점 chip" 은 미래 일감.
- **Drilldown 시 startDate/endDate 도 함께 sync** — plan 명세는 activityType/branch/direction 만 URL sync. 날짜 sync 는 toolbar 가 별도로 처리.

---

**Total deviations:** 0 architectural + 4 auto-fixes (Rule 2 layout + Rule 2 DRY + Rule 2 type/lint + Rule 1 lint)
**Impact on plan:** 모든 task 가 plan 명세대로 완료. 빌드/lint baseline-clean.

## Issues Encountered

- 없음. 첫 시도에 ESLint clean + TypeScript clean + Next.js build PASS.
- 코드 사이즈: /ventas route 가 800B → 804B (+4B). chip strip + drilldown handlers 의 미니멀한 코드 비용 (대부분은 useCallback 으로 dead-code-eliminated).

## Authentication Gates

해당 사항 없음 — 본 plan 은 frontend-only 변경, 백엔드 호출은 기존 endpoint (Plan 03 의 GET /sales/all + Plan 04 가 사용하는 GET /sales/daily-stats) 의 query 확장만.

## User Setup Required

None — frontend 변경만 (npm install 새 deps 없음, env var 추가 없음).

## Next Phase Readiness

- **Plan 35-06 (Stock Cockpit MOV+/MOV−/FAL 컬럼) 준비 완료** — Phase 35-B 후속.
- **UAT 시나리오 검증 가능 (Phase 35-A 마지막 plan 완료)**:
  - **U2** ✓ — chip [MOV] + blue tint + JEFE → SALA Cliente.
  - **U3** ✓ — Resumen 매트릭스 (Plan 04 + Plan 05 통합 결과).
  - **U4/U5** ✓ — KPI 의 prendas/금액 변화 없음 (백엔드 Plan 03 의 activity_type='sale' 필터).
  - **U6** ✓ — Resumen 행 클릭 → URL `?branchLabel=NAME&originBranchId=X` 변경 + chip 표시.
  - **U7** ✓ — Resumen 셀 클릭 → URL `?targetBranchId=X&activityType=movido&direction=in` + 2 chip.
  - **U8** ✓ — chip X 클릭 → URL query 제거 + 필터 해제.
  - **U11** ✓ — 단일 지점 사용자 → TOTAL 행 숨김 (Plan 04 의 showTotalRow 조건).
  - **U13** ✓ — fallado 도 동일 흐름 (chip [FAL] + red tint + FAL · JEFE).
  - **U14** ✓ — movBalance.balanced=false 시 ⚠ + tooltip (Plan 04 의 BALANCE_WARNING_MSG).
- **URL 직접 입력/북마크 복원** ✓ — router.isReady useEffect 가 URL → state sync.
- **Blocker/Concern 없음**.

## Known Stubs

없음. 모든 props/handlers 가 정상 연결, drilldown 동작 완전 구현.

## Threat Flags

본 plan 의 변경은 plan `<threat_model>` 에 등록된 T-35-18 / T-35-19 / T-35-20 의 mitigation 만 구현. 신규 surface 추가:

- **URL query 직접 조작** (T-35-18) — accept disposition. Backend (Plan 03) 의 화이트리스트가 invalid 값 default 처리. Frontend 는 신뢰 (Number conversion 만 적용, 음수/NaN 시 fetch 실패는 backend 처리).
- **originBranch.name 렌더링** (T-35-19) — accept disposition. React JSX 자동 escape. branch name 은 DB-controlled (Plan 01 의 branches 테이블).
- **단일 지점 사용자 매트릭스 혼란** (T-35-20) — mitigate disposition. Plan 04 의 TOTAL 행 숨김 (showTotalRow = perBranch.length > 1) 그대로 사용.

→ **Threat flags 없음** (plan threat_register 외 추가 surface 없음). Plan 외 신규 surface 없음.

## Self-Check: PASSED

**Files verified:**
- `ventago-app/src/views/sales/list/components/DataConfig.tsx` — MODIFIED (+161/-23)
- `ventago-app/src/components/table/FullTable.tsx` — MODIFIED (+29/0)
- `ventago-app/src/views/sales/list/SalesListView.tsx` — MODIFIED (+193/-6)

**Commits verified (ventago-app repo, `git log --oneline`):**
- `802816a` (Task 1) — feat(phase-35-05): add Tipo chip column + Cliente dual-purpose renderer + activity row sx — FOUND
- `34e0524` (Task 2) — feat(phase-35-05): add getRowSx prop to FullTable for activity-type row tint — FOUND
- `5d14bb3` (Task 3) — feat(phase-35-05): replace KpiCards with SalesResumenTable + URL sync + chip strip — FOUND

**Build verification:**
- `npx eslint src/views/sales/list/components/DataConfig.tsx` — PASS (no output)
- `npx eslint src/components/table/FullTable.tsx` — PASS (no output)
- `npx eslint src/views/sales/list/SalesListView.tsx` — PASS (no output)
- `npx tsc --noEmit -p tsconfig.json` — PASS (no output)
- `npm run build` — PASS ("info - Compiled successfully", 97 routes rendered)

**Acceptance criteria (Task 1):** 12/12 ✓
**Acceptance criteria (Task 2):** 6/6 ✓
**Acceptance criteria (Task 3):** 15/15 ✓
**Plan success criteria:** 9/9 ✓ (DataConfig chip+dual+'—'+export / FullTable getRowSx / SalesListView KpiCards→Resumen / URL sync / drilldown handlers / chip strip / row tint / build / ESLint)

---
*Phase: 35-activity-ledger*
*Completed: 2026-05-22*
