---
phase: 35-activity-ledger
plan: 04
subsystem: frontend
tags: [frontend, react, mui, swr, sales, resumen-table, d-05]

# Dependency graph
requires:
  - phase: 35-03
    provides: GET /sales/daily-stats 엔드포인트 (perBranch + total + movBalance JSON shape)
provides:
  - useDailySalesStats SWR 훅 (5분 dedup) — /sales/daily-stats?startDate=...&endDate=... 호출
  - SalesResumenTable.tsx — 8 컬럼 매트릭스 테이블 (SUCURSAL/VENTAS/PRENDAS/DESC/MOV+/MOV−/FAL/NETO)
  - TOTAL 행 조건부 렌더 (perBranch.length > 1)
  - movBalance 알람 (⚠ + tooltip 한국어 메시지)
  - onRowClick / onCellClick drilldown 콜백 props (Plan 05 에서 SalesListView 연결 예정)
affects:
  - 35-activity-ledger-plan-05 (SalesListView 가 SalesKpiCards/DailySalesStats 를 SalesResumenTable 로 교체 + drilldown 핸들러 연결)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "SWR 훅 패턴: useSWR<T>(key, fetcher, { dedupingInterval: 300000, revalidateOnFocus: false }) — CLAUDE.md SWR 5분 dedup 규약"
    - "조건부 SWR key: enabled && startDate && endDate → null (fetch 보류) — Plan 05 가 enabled prop 제어 가능"
    - "MUI Table size='small' + stickyHeader + 첫 컬럼 position:'sticky' — D-05 모바일 horizontal scroll 패턴"
    - "useCallback drilldown handler 안정화 — children TableRow/TableCell 의 onClick 재할당 방지"
    - "셀 클릭 stopPropagation — 행 클릭과 셀 클릭 분기"
    - "렌더 헬퍼 (renderMovIn/Out/Fal/Neto) 를 컴포넌트 외부 함수로 추출 — 매 렌더 재생성 방지"

key-files:
  created:
    - "ventago-app/src/hooks/api/useDailySalesStats.ts"
    - "ventago-app/src/views/sales/list/components/SalesResumenTable.tsx"
  modified: []

key-decisions:
  - "SWR 훅이 useApi 래퍼 대신 useSWR 직접 사용 — plan 명세의 fetcher + revalidateOnFocus 옵션을 명시적으로 보이게 하여 grep 감사 + acceptance criteria 만족 (전역 SWRConfig 기본값 동일하지만 명시적 선언 우선)"
  - "DailyStatsBranchRow / DailyStatsResponse 인터페이스 export — Plan 05 의 SalesListView 가 drilldown 핸들러 타입 추론 시 재사용"
  - "ResumenRowClick / ResumenCellClick 콜백 payload 타입 export — 동일 이유 (Plan 05 type-safe 핸들러)"
  - "branchId: number | null in callback payload — TOTAL 행 클릭 시 null 로 표기 (Plan 05 가 전체 지점 chip 또는 ignore 결정)"
  - "Tooltip 메시지를 BALANCE_WARNING_MSG 상수로 추출 — MOV+ / MOV− 양 셀에 동일 메시지 재사용 + 추후 i18n 시 1곳만 수정"
  - "renderMovIn / renderMovOut / renderFal / renderNeto 헬퍼를 모듈 스코프 함수로 정의 — 매 렌더 재생성 방지 + useCallback 의존성 배열 단순화"
  - "MUI Stack 으로 ⚠ icon + 숫자 inline 배치 — sx 가로 정렬 보장 + Box+Tooltip wrap 패턴 유지"
  - "TableContainer maxHeight: 200 + overflow:'auto' — KPI strip 자리 그대로 차지 (SPEC D-05 위치 명세)"

patterns-established:
  - "Phase 35 frontend Resumen 데이터 source 패턴: useDailySalesStats({ startDate, endDate, enabled }) — SWR key=null 시 fetch 보류"
  - "Plan 35 drilldown 신호 패턴: 부모 (SalesListView Plan 05) 가 onRowClick/onCellClick 으로 URL ?branch=... 변환 + chip 표시"
  - "balanced=false 경고 패턴: TOTAL 행 MOV+/MOV− 양 셀에 동일 ⚠ icon + 동일 tooltip 메시지"

requirements-completed: [AL-12, AL-13, AL-14, AL-15, AL-16]

# Metrics
duration: 18min
completed: 2026-05-22
---

# Phase 35 Plan 04: Resumen Table — useDailySalesStats SWR Hook + SalesResumenTable Component Summary

**ventaVista 의 KPI strip 을 대체할 per-sucursal Resumen 매트릭스 테이블 — SWR 훅 (5분 dedup) + 8 컬럼 MUI Table + 단일 지점 사용자 TOTAL 숨김 + movBalance 알람 + drilldown 콜백 props**

## Performance

- **Duration:** ~18 min
- **Started:** 2026-05-22T22:55:00Z (approx)
- **Completed:** 2026-05-22T23:13:08Z
- **Tasks:** 2
- **Files created:** 2 (ventago-app — useDailySalesStats.ts + SalesResumenTable.tsx)
- **Files modified:** 0
- **Repo:** ventago-app (nested git repo)

## Accomplishments

- **Task 1 — useDailySalesStats SWR 훅** (`a1c243a`):
  - 신규 파일 `ventago-app/src/hooks/api/useDailySalesStats.ts` (62 lines).
  - `DailyStatsBranchRow` / `DailyStatsResponse` 두 인터페이스 export (Plan 35-03 응답 shape 와 1:1 매핑).
  - `useDailySalesStats({ startDate, endDate, enabled? })` — `enabled && startDate && endDate` 충족 시 SWR key 생성, 그렇지 않으면 `null` 로 fetch 보류.
  - `dedupingInterval: 300000` (5분), `revalidateOnFocus: false`, `revalidateOnReconnect: false`.
  - Fetcher 는 `apiConnector.get<DailyStatsResponse>(url)` — 전역 SWRConfig 기본값과 동일하지만 명시적 선언으로 acceptance criteria + grep 감사 만족.
- **Task 2 — SalesResumenTable 컴포넌트** (`2e1b53b`):
  - 신규 파일 `ventago-app/src/views/sales/list/components/SalesResumenTable.tsx` (386 lines).
  - 8 컬럼 MUI Table: SUCURSAL · VENTAS (count·amount) · PRENDAS · DESC · MOV+ · MOV− · FAL · NETO.
  - `ResumenRowClick` / `ResumenCellClick` 타입 export — `branchId: number | null` (null = TOTAL 행).
  - `useDailySalesStats` 호출 후 4가지 분기 렌더: 로딩 (Skeleton 120h) · 빈 상태 ("오늘 활동 없음" placeholder) · perBranch rows · 조건부 TOTAL row.
  - `showTotalRow = perBranch.length > 1` — 단일 지점 사용자 TOTAL 숨김 (UAT U11 충족).
  - `balanceWarning = Boolean(movBalance && !movBalance.balanced)` — TOTAL 행 MOV+ / MOV− 양 셀에 ⚠ icon + Tooltip `BALANCE_WARNING_MSG` ("동일 store 내 이동인데 IN/OUT 합이 다릅니다 — 데이터 점검 필요") — UAT U14 충족.
  - 셀 onClick → onCellClick(branchId, type='movido'|'fallado', direction='in'|'out'?) + `e.stopPropagation()` 으로 행 클릭과 분리.
  - 행 onClick → onRowClick(branchId, branchName).
  - 색상 가이드 (SPEC D-05): MOV+/MOV− `info.main` (#1976D2 계열), FAL `error.main`, NETO 양수 `success.main` / 음수 `error.main` / 0 `text.primary`.
  - 첫 컬럼 `position: 'sticky', left: 0, bgcolor: 'background.paper'` + Table `stickyHeader` — 모바일 horizontal scroll 시 SUCURSAL 컬럼 고정.
  - `useCallback` 4개 (handleCellMovIn / MovOut / Fal / RowClickInternal) — onRowClick/onCellClick deps.
  - 렌더 헬퍼 4개 (`renderMovIn` / `renderMovOut` / `renderFal` / `renderNeto`) 를 모듈 스코프 함수로 추출.

## Task Commits

각 task 가 ventago-app nested git repo 에 원자적으로 commit 되었습니다:

1. **Task 1: useDailySalesStats SWR 훅** — `a1c243a` (feat)
   - 1 file, +62 lines.
2. **Task 2: SalesResumenTable 컴포넌트** — `2e1b53b` (feat)
   - 1 file, +386 lines.

_Plan metadata (SUMMARY.md) 는 부모 워킹트리(.planning/) 에서 별도 commit — 본 plan 의 task commit 은 ventago-app 내부에만 존재._

## Files Created (ventago-app repo)

**Created (2):**
- `ventago-app/src/hooks/api/useDailySalesStats.ts` (+62)
- `ventago-app/src/views/sales/list/components/SalesResumenTable.tsx` (+386)

## Acceptance Criteria Verification

### Task 1 (useDailySalesStats SWR 훅)

| Criterion | Result |
|---|---|
| `test -f ventago-app/src/hooks/api/useDailySalesStats.ts` | ✓ EXISTS |
| `grep -c "export const useDailySalesStats"` returns 1 | ✓ 1 |
| `grep -c "dedupingInterval: 300000"` returns 1 | ✓ 1 |
| `grep -c "/sales/daily-stats"` >= 1 | ✓ 2 |
| `grep -c "DailyStatsResponse"` >= 2 (interface + return type) | ✓ 3 |
| `grep -c "movBalance"` >= 2 | ✓ 2 |
| `grep -c "revalidateOnFocus: false"` returns 1 | ✓ 1 |
| `npx eslint src/hooks/api/useDailySalesStats.ts` exits 0 | ✓ clean (no output) |

### Task 2 (SalesResumenTable 컴포넌트)

| Criterion | Result |
|---|---|
| `test -f .../SalesResumenTable.tsx` | ✓ EXISTS |
| `grep -c "useDailySalesStats"` >= 1 | ✓ 2 |
| 8 column headers (SUCURSAL/VENTAS/PRENDAS/DESC/MOV+/MOV−/FAL/NETO) | ✓ 15 occurrences |
| `grep -c "Σ TOTAL"` >= 1 | ✓ 1 |
| `grep -c "showTotalRow"` >= 1 | ✓ 2 |
| `grep -c "movBalance.balanced\|balanceWarning"` >= 2 | ✓ 4 |
| `grep -c "onRowClick"` >= 2 | ✓ 6 |
| `grep -c "onCellClick"` >= 4 | ✓ 12 |
| `grep -c "mdi:alert-circle"` >= 1 | ✓ 2 (MOV+ + MOV− 양 셀) |
| `grep -c "동일 store 내 이동인데"` >= 1 (tooltip) | ✓ 1 (BALANCE_WARNING_MSG 상수) |
| `grep -c "오늘 활동 없음"` >= 1 (empty state) | ✓ 2 (literal + 주석 1) |
| `grep -c "export default SalesResumenTable"` >= 1 | ✓ 1 |
| `npx eslint .../SalesResumenTable.tsx` exits 0 | ✓ clean (no output) |

## Build / Lint Verification

```
$ cd ventago-app && npx eslint src/hooks/api/useDailySalesStats.ts
(no output — clean)

$ cd ventago-app && npx eslint src/views/sales/list/components/SalesResumenTable.tsx
(no output — clean)

$ cd ventago-app && npx tsc --noEmit -p tsconfig.json
(no output — type-check PASS)

$ cd ventago-app && npm run build
✓ Compiled successfully
(57 routes rendered, /ventas route at 800B + 428kB shared — unchanged baseline)
```

→ ESLint clean (신규 도입 errors 0), TypeScript strict 통과, Next.js production build PASS.

## Decisions Made

- **fetcher 명시 vs 전역 SWRConfig 기본값 의존**: 명시적 선언 선택. 전역 SWRConfig 의 기본 fetcher (`apiConnector.get(url)`) 와 동일하지만, plan acceptance criteria 의 grep 감사 (`dedupingInterval: 300000`, `revalidateOnFocus: false` 텍스트 존재 요구) 만족 + 코드 리뷰 시 데이터 source 즉시 가시화.
- **`enabled` prop 추가**: SPEC D-05 에는 명세 없지만 Plan 05 가 SalesListView 에서 date range 변경 중 또는 권한 없는 사용자에게 SWR fetch 보류할 수 있도록 추가. default `true` 로 기존 동작 보존.
- **`DailyStatsBranchRow` / `DailyStatsResponse` export**: Plan 05 의 drilldown 핸들러가 row.branchId 타입 추론 시 재사용 — internal 만 유지하면 Plan 05 가 또 정의해야 하므로 미리 export.
- **`ResumenRowClick.branchId: number | null`**: TOTAL 행 클릭 시 null. Plan 05 가 null 을 "전체 지점 chip" 또는 ignore 로 분기 가능. 디자인은 Plan 05 결정.
- **렌더 헬퍼 모듈 스코프**: `renderMovIn/Out/Fal/Neto` 4개를 컴포넌트 외부에 두어 매 렌더마다 재생성 방지. useCallback 으로 감싸야 하는 deps 가 없으므로 외부 함수가 더 간단.
- **셀 클릭 stopPropagation**: TableRow `onClick={() => handleRowClickInternal}` 와 TableCell `onClick={...}` 가 동시에 trigger 되는 것을 차단. 행 = 지점 필터, 셀 = 지점+활동 다중 필터로 의미 분리.
- **`Σ TOTAL` 행 sticky bgcolor `action.hover`**: SPEC D-05 ASCII 매트릭스의 구분선 강조. 다크 테마에서도 hover 색이 row 와 구분.
- **stickyHeader + 첫 컬럼 sticky**: SPEC D-05 "Mobile/responsive (DEFERRED)" 항목 — 모바일 폭 < 600px 시 horizontal scroll + 첫 컬럼 고정 CSS 패턴.
- **maxHeight 200**: KPI strip 자리 그대로 차지하기 위한 컴팩트 높이. perBranch 5+ 행 시 내부 scroll.

## Deviations from Plan

### Code Auto-fixes

**1. [Rule 2 — Performance hardening] 렌더 헬퍼를 컴포넌트 외부 함수로 추출**
- **Found during:** Task 2 작성 (plan 의 원본 코드는 4 helper 가 컴포넌트 내부 함수)
- **Issue:** plan 코드에서 `renderMovIn/Out/Fal/Neto` 가 SalesResumenTable 내부 const 로 정의 — 매 렌더마다 재생성, JSX prop reference 가 매번 달라져 children TableCell 의 React 재조정 비용 증가.
- **Fix:** 4 helper 를 모듈 스코프 함수로 추출. JSX 결과만 반환하므로 props/state 의존 없음.
- **Files modified:** `ventago-app/src/views/sales/list/components/SalesResumenTable.tsx`
- **Committed in:** `2e1b53b` (Task 2 commit 에 포함)
- **이유:** CLAUDE.md "성능 최적화 규약 → React.memo 고트래픽 리스트 컴포넌트" 정신 부합. ventaVista 는 매장 운영자가 하루 종일 보는 화면.

**2. [Rule 1 — JSX 정정] perBranch.map 의 `(row) =>` → `row =>`**
- **Found during:** Task 2 ESLint 검증
- **Issue:** 단일 파라미터 arrow function 의 괄호는 prettier 가 권장에 따라 제거 (`.prettierrc` 기본값).
- **Fix:** 자동 prettier 정리 — `perBranch.map(row => (`.
- **Committed in:** `2e1b53b`
- **이유:** 신규 도입 lint warnings 0 유지 (scope-boundary 정책 — Phase 35-01/02/03 동일 정책).

### Architectural Deviations

None — 모든 변경이 plan 명세대로 정확히 진행.

### Out of Scope (intentional)

- **drilldown 핸들러 (URL ?branch=... 변환 + chip 표시) — Plan 35-05 의 작업**. 본 plan 은 props 노출만.
- **SalesListView 통합 (KPI strip → SalesResumenTable 교체) — Plan 35-05**. 본 plan 은 컴포넌트 신설만.
- **`startDate !== endDate` (날짜 범위) 동작 명세 — SPEC D-05 는 "오늘" 한정**. 본 hook 은 양 끝 날짜 모두 받아 backend 위임 — Plan 03 의 getDailyStats 가 `s.sale_date BETWEEN startDate AND endDate` 처리.

---

**Total deviations:** 0 architectural + 2 auto-fixes (Rule 2 perf + Rule 1 prettier)
**Impact on plan:** 모든 task 가 plan 명세대로 완료. 빌드/lint baseline-clean.

## Issues Encountered

- 없음. 첫 시도에 ESLint clean + TypeScript clean + Next.js build PASS.
- `npm run build` 출력은 57 routes 모두 정상 렌더 — SalesResumenTable.tsx 는 아직 import 되지 않아 dead-code shaking 으로 production bundle 영향 0 (Plan 35-05 통합 후 측정 가능).

## Next Phase Readiness

- **Plan 35-05 (SalesListView KPI → Resumen 교체 + drilldown 핸들러 + 리스트 행 시각 구분) 준비 완료**:
  - `import SalesResumenTable from './components/SalesResumenTable'` 로 즉시 사용 가능.
  - props 시그니처:
    ```tsx
    <SalesResumenTable
      startDate={filters.startDate}
      endDate={filters.endDate}
      onRowClick={(e) => setFilters({ ...filters, branchId: e.branchId })}
      onCellClick={(e) => setFilters({
        ...filters,
        branchId: e.branchId,
        activityType: e.type,
        direction: e.direction
      })}
    />
    ```
  - `DailyStatsBranchRow` / `DailyStatsResponse` / `ResumenRowClick` / `ResumenCellClick` 타입 직접 import.
- **UAT U3 검증 가능**: Resumen 테이블 → 두 지점의 MOV+ / MOV− 셀에 정확한 prendas 수 표시 (Plan 03 백엔드 + Plan 04 컴포넌트 결합).
- **UAT U11 검증 가능**: 단일 지점 사용자 → TOTAL 행 숨김 (showTotalRow 조건부 렌더).
- **UAT U14 검증 가능**: movBalance.balanced=false → ⚠ + tooltip 표시 (BALANCE_WARNING_MSG).
- **UAT U6 / U7 부분 검증**: onRowClick / onCellClick 콜백이 정상 호출 — 완전한 URL+chip 검증은 Plan 35-05 후.
- **Blocker/Concern 없음**.

## Known Stubs

없음. 컴포넌트는 props 가 모두 받아져 정상 작동 — drilldown 핸들러 미연결 시 단순히 클릭 무시 (`onRowClick?.(...)` optional chaining).

## Threat Flags

본 plan 의 변경은 plan `<threat_model>` 에 등록된 T-35-15 / T-35-16 / T-35-17 의 mitigation 만 구현. 신규 surface 추가:

- **SalesResumenTable 컴포넌트** — 인증된 사용자만 SalesListView 진입 가능 (기존 가드 유지). storeId 필터링은 백엔드 `/sales/daily-stats` 가 처리 (Plan 03 사용자 storeId 강제). 프론트는 신뢰. **신규 surface 없음**.

→ **Threat flags 없음** (plan threat_register 외 추가 surface 없음).

## Self-Check: PASSED

**Files verified:**
- `ventago-app/src/hooks/api/useDailySalesStats.ts` — FOUND (created, +62 lines)
- `ventago-app/src/views/sales/list/components/SalesResumenTable.tsx` — FOUND (created, +386 lines)

**Commits verified (ventago-app repo, `git log --oneline`):**
- `a1c243a` (Task 1) — feat(phase-35-04): add useDailySalesStats SWR hook for Resumen table — FOUND
- `2e1b53b` (Task 2) — feat(phase-35-04): add SalesResumenTable per-sucursal matrix component — FOUND

**Build verification:**
- `npx eslint src/hooks/api/useDailySalesStats.ts` — PASS (no output)
- `npx eslint src/views/sales/list/components/SalesResumenTable.tsx` — PASS (no output)
- `npx tsc --noEmit -p tsconfig.json` — PASS (no output)
- `npm run build` — PASS (57 routes rendered, /ventas baseline unchanged)

**Acceptance criteria (Task 1):** 8/8 ✓
**Acceptance criteria (Task 2):** 12/12 ✓
**Plan success criteria:** 7/7 ✓ (useDailySalesStats / SalesResumenTable / TOTAL 숨김 / balanced 알람 / drilldown props / ESLint / D-05 SPEC)

---
*Phase: 35-activity-ledger*
*Completed: 2026-05-22*
