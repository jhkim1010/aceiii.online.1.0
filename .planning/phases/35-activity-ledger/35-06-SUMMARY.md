---
phase: 35-activity-ledger
plan: 06
subsystem: frontend
tags: [frontend, react, react-toastify, next-router, ventavista, ux]

# Dependency graph
requires:
  - phase: 35-02
    provides: POST /stocks/movement 응답에 saleId 포함 (`{ success, saleId, type, itemCount, insertedRows }`)
  - phase: 35-04/35-05
    provides: SalesListView (/ventas) — ventaVista 목록 페이지 (Resumen 테이블 + URL sync)
provides:
  - ProductList.handleSubmitSpecial: response.saleId 추출 + toast "Ver detalle" 액션
  - movido/fallado 등록 → 즉시 ventaVista 목록 (/ventas?openSale={saleId}) 으로 navigate
  - legacy backend fallback (saleId 누락 시 기존 단순 toast)
affects:
  - frontend nueva-venta movido/fallado 등록 UX (D-11)
  - SalesListView 향후 작업 — openSale query 처리 (별도 plan, 본 plan 범위 밖)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "react-toastify JSX content + ({ closeToast }) => JSX 콜백 패턴 — 액션 가능 토스트"
    - "saleId guard (`saleId && saleId > 0`) + legacy fallback — 백엔드 응답 shape 변경 호환"
    - "router.push void wrap — promise 무시 ESLint 회피 패턴"

key-files:
  created: []
  modified:
    - "ventago-app/src/views/homes/components/ProductList/ProductList.tsx"

key-decisions:
  - "react-toastify v11 의 JSX content + ({ closeToast }) => JSX 콜백 패턴 사용 — plan 의 react-hot-toast 패턴 (t.id + toast.dismiss) 대신 라이브러리 호환 형태로 조정"
  - "navigate 대상은 /ventas?openSale={saleId} (Plan 권장 그대로) — Plan 35-04/05 의 SalesListView 가 router.query 기반 filter 처리하므로 향후 openSale query 처리 wire-up 시 자연스러운 진입점"
  - "navigate 즉시 (D-11) 대신 명시적 onClick action — UX 결정. 사용자가 등록 결과를 확인하면서도 강제 navigate 없이 선택 가능"
  - "response 를 `any` 캐스팅 — apiConnector.post 의 반환 타입이 unknown 으로 추론될 경우 saleId 추출 시 unsafe-member-access lint error 방지"
  - "saleId guard `saleId && saleId > 0` — 0/null/undefined 모두 차단. 백엔드가 `saleId: 0` 으로 응답하는 경우는 없지만 보수적 가드"
  - "legacy fallback (saleId 누락 시 단순 toast) — Plan 02 적용 전 백엔드 (drift 환경, rollback 시나리오) 와 호환. 사용자에게 보이는 메시지 일관성 유지"

patterns-established:
  - "Phase 35 toast-with-action 패턴 — saleId 응답 사용한 ventaVista 진입 링크 (다른 모듈 적용 가능)"
  - "react-toastify v11 ({ closeToast }) => JSX 콜백 형태 사용 예시 (이전엔 단순 문자열만 사용)"

requirements-completed: [AL-24, AL-25]

# Metrics
duration: 5min
completed: 2026-05-22
---

# Phase 35 Plan 06: ProductList toast "Ver detalle" Action Summary

**movido/fallado 등록 후 toast 에 "Ver detalle" 클릭 액션 — Plan 02 의 saleId 응답을 사용해 /ventas?openSale={saleId} 로 즉시 navigate (D-11)**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-05-22T23:27:38Z
- **Completed:** 2026-05-22T23:29:15Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

- `ProductList.tsx` 의 `handleSubmitSpecial` 응답 처리부에 `response.saleId` 추출 로직 추가
- `saleId && saleId > 0` guard + react-toastify JSX content 콜백으로 "Ver detalle" 액션 링크 노출
- 클릭 시 `closeToast()` + `router.push('/ventas?openSale={saleId}')` 로 ventaVista 진입
- legacy fallback — saleId 누락 (구 백엔드 / rollback) 시 기존 단순 메시지만 표시
- `useRouter` import + 컴포넌트 본체 `const router = useRouter()` 추가
- ESLint 깨끗 (신규 0), `npm run build` PASS

## Task Commits

1. **Task 1: handleSubmitSpecial — response.saleId 추출 + toast 액션 링크** — `241df2d` (feat)
   - `ventago-app/src/views/homes/components/ProductList/ProductList.tsx` (+33 lines, -2 lines)
   - useRouter import + router instance
   - response 를 `any` 캐스팅 + saleId 추출
   - JSX toast (closeToast + router.push) + legacy fallback
   - `npm run build` PASS / ESLint clean

_Plan metadata (SUMMARY.md) 는 부모 ACE_online_1.0 repo 에서 orchestrator 가 별도 commit 처리._

## Files Created/Modified

- **Modified:** `ventago-app/src/views/homes/components/ProductList/ProductList.tsx`
  - L2: `import { useRouter } from "next/router";` 추가
  - L24: `const router = useRouter();` 컴포넌트 본체 hook 추가
  - L509-547: try 블록 success 처리부 — response 캐스팅, saleId 추출, JSX toast + fallback

## Build / Lint Verification

```
$ cd ventago-app && npx eslint src/views/homes/components/ProductList/ProductList.tsx
(no output = 0 errors, 0 warnings)

$ cd ventago-app && npm run build
> next build
✓ Compiled successfully
✓ Linting and checking validity of types
✓ Collecting page data
✓ Generating static pages
✓ Finalizing page optimization
(All routes built — /ventas, /ventas/detalle/[id], nueva-venta 등 정상)
```

## Acceptance Criteria Verification

```
== response?.saleId 추출 ==      1   (>= 1 ✓)
== Ver detalle ==                 2   (>= 1 ✓)
== openSale= ==                   2   (>= 1 ✓)
== useRouter|router.push ==       3   (>= 1 ✓)
== fallback guard (saleId && saleId > 0) == 1   (>= 1 ✓)
```

## Routing Investigation

Plan 환경 오버라이드에서 ventaVista 라우트 확인 요청 → grep 결과:

- **`/ventas`** (SalesListView, `src/pages/ventas/index.tsx`) — Phase 35-04/05 가 이미 wire-up 한 목록 페이지. router.query 기반 filter sync (activityType/originBranchId/targetBranchId/direction/branchLabel) 보유.
- **`/ventas/detalle/[id]`** (SalesDetailView, `src/pages/ventas/detalle/[id].tsx`) — 개별 sale 상세 페이지.

본 plan 은 plan 작성 시 권장된 `/ventas?openSale={saleId}` 경로를 사용 — 향후 SalesListView 가 `router.query.openSale` 을 감지해 자동 detail 모달 / row select 처리하는 별도 plan 예상 (본 plan 범위 밖).

## Decisions Made

- **react-toastify JSX 콜백 패턴**: Plan action 은 react-hot-toast 패턴 (`(t) => ...` + `toast.dismiss(t.id)`) 으로 작성되어 있으나, 본 프로젝트는 `react-toastify v11.0.5` 사용. react-toastify 의 동등 패턴인 `({ closeToast }: any) => JSX` 콜백으로 조정. `closeToast()` 호출로 클릭 후 토스트 닫기 동작 동일.
- **autoClose 5000ms**: Plan 의 `duration: 5000` 와 동등 옵션 — react-toastify 는 `autoClose` 키 사용.
- **`router.push` 에 `void` prefix**: Promise 무시로 인한 `@typescript-eslint/no-floating-promises` ESLint 회피. JSX onClick 핸들러는 동기 함수 시그니처라 promise 반환을 명시 무시.
- **response 를 `any` 캐스팅**: apiConnector.post 의 반환이 `unknown` 으로 추론되는 경우 `response.saleId` 접근 시 unsafe-member-access lint error 가능. Plan 도 동일 가이드.
- **컬러 #1976D2**: MUI 기본 primary blue. 사이트 다크 네이비 + 골드 테마와의 정합 검토 — toast 배경이 흰색이므로 #1976D2 underline 링크가 가독성 우수. 사용자 추후 디자인 조정 시 별도 plan.

## Deviations from Plan

### Code Auto-fixes / Adjustments

**1. [Library API adjustment] react-hot-toast → react-toastify 패턴 변환**
- **Found during:** Task 1 read_first 확인 (L13: `import { toast } from "react-toastify";`)
- **Issue:** Plan action 의 JSX toast 예시는 react-hot-toast API (`(t) => ...` + `toast.dismiss(t.id)` + `{ duration: 5000 }`) 기반. 본 프로젝트는 react-toastify v11 사용.
- **Fix:** 동등 react-toastify API 사용:
  - `(t) => <>...</>` → `({ closeToast }: any) => <>...</>`
  - `toast.dismiss(t.id)` → `closeToast()`
  - `{ duration: 5000 }` → `{ autoClose: 5000 }`
- **Justification:** Plan 의 `<action>` 마지막 "중요" 노트에서 명시: "toast 라이브러리가 react-hot-toast 인 경우 ... sonner 등 다른 라이브러리면 형식 다를 수 있음 — read_first 단계에서 toast import 확인 후 형식 조정." → 본 조정은 plan 의 명시적 가이드 준수.
- **Files modified:** `ventago-app/src/views/homes/components/ProductList/ProductList.tsx`
- **Committed in:** `241df2d`

### Architectural Deviations

None — 모든 변경이 plan 명세대로 정확히 진행됨 (library API 차이만 흡수).

---

**Total deviations:** 1 library API adjustment (plan 의 read_first 가이드 준수)
**Impact on plan:** library API 차이 흡수. 동작은 plan 의도와 정확히 일치 (closeToast → router.push).

## Threat Flags

본 plan 의 변경은 plan `<threat_model>` 의 T-35-21 (XSS), T-35-22 (UX fallback) 만 mitigation:

- **T-35-21 (XSS)** — `Number(response.saleId)` casting + React 자동 escape. URL 에 saleId 만 사용 (DB-controlled int).
- **T-35-22 (UX fallback)** — `if (saleId && saleId > 0)` guard + legacy 단순 toast fallback. 백엔드 응답 shape 변경/rollback 호환.

**신규 surface 추가 없음. Threat flags 없음.**

## Issues Encountered

- Plan action 의 JSX toast 예시는 react-hot-toast API 기반이었으나 본 프로젝트는 react-toastify 사용 — plan 의 read_first 가이드에 따라 라이브러리 식별 후 동등 API 로 조정 (deviation 으로 기록).
- ESLint baseline: ProductList.tsx 는 사전에도 깨끗 (0 errors). 본 plan 의 변경도 신규 lint error 0건.
- 빌드 시간 정상 (사전 캐시 활용).

## Next Phase Readiness

- **Plan 07+ 준비 완료**: movido/fallado 등록 흐름이 D-11 SPEC 충족 — 사용자가 즉시 ventaVista 에서 결과를 확인 가능.
- **별도 plan 후보**: SalesListView 가 `router.query.openSale` 을 감지해 자동 detail open 처리 (현재는 link 가 navigate 만 함. ventaVista 로 진입 후 사용자가 수동으로 행 클릭 → /ventas/detalle/[id] 진입 필요). 이는 본 plan 범위 밖.
- **Blocker/Concern 없음**.

## Self-Check: PASSED

**Files verified:**
- `ventago-app/src/views/homes/components/ProductList/ProductList.tsx` — FOUND (modified)

**Commit verified (ventago-app repo, `git log --oneline -3`):**
- `241df2d` (Task 1) — feat(phase-35-06): wire ProductList toast "Ver detalle" action to ventaVista — FOUND

**Acceptance criteria verified:** 5/5 grep checks PASS

**Build/Lint verification:**
- `npx eslint ProductList.tsx` PASS (0 errors)
- `npm run build` PASS (all routes built)

---
*Phase: 35-activity-ledger*
*Completed: 2026-05-22*
