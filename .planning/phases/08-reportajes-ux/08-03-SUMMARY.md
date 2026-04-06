---
phase: 08-reportajes-ux
plan: 03
subsystem: reports-v2-shell
tags: [reports, ux, shell, redux, shallow-routing]
requirements: [UX-04]
dependency_graph:
  requires: ["08-01", "08-02"]
  provides: ["reports-v2 shell MVP", "REPORTS_REGISTRY", "reportsV2Slice", "/reportes-v2 route"]
  affects: ["ventago-app/src/store/index.ts", "ventago-app/src/navigation/vertical/index.ts"]
tech_stack:
  added: []
  patterns: ["static registry + lazy bodyComponent", "Redux slice for selected/params/recents", "shallow routing for sidebar navigation", "React.memo + local-state search input"]
key_files:
  created:
    - ventago-app/src/views/reports-v2/registry.ts
    - ventago-app/src/store/apps/reports-v2/index.ts
    - ventago-app/src/views/reports-v2/ReportsShell.tsx
    - ventago-app/src/views/reports-v2/ReportsSidebar.tsx
    - ventago-app/src/views/reports-v2/ReportsTopbar.tsx
    - ventago-app/src/views/reports-v2/ReportsParamsPanel.tsx
    - ventago-app/src/views/reports-v2/ReportsPreviewPanel.tsx
    - ventago-app/src/pages/reportes-v2/[[...slug]].tsx
  modified:
    - ventago-app/src/store/index.ts
    - ventago-app/src/navigation/vertical/index.ts
decisions:
  - "Reportajes 메뉴를 collapsible 그룹 대신 /reportes-v2 직접 링크로 변경 (Wave 3 추가 작업)"
metrics:
  duration: ~45min
  tasks_completed: 3
  files_changed: 9
  completed: 2026-04-06
---

# Phase 08 Plan 03: Reports-v2 Shell MVP Summary

`/reportes-v2` 셸 MVP 구축 — 16-entry 정적 registry, reportsV2 Redux slice, 5개 셸 컴포넌트, catch-all 라우트, 3개 보고서 (vendedor/gastos/breve-venta) embed 동작.

## Commits

| Commit | Scope | Description |
|--------|-------|-------------|
| 060d4f7 | ventago-app | feat(08-03): registry + reportsV2 slice + store wiring |
| 452cd76 | ventago-app | feat(08-03): shell components + catch-all route |
| dbee834 | ventago-app | feat(08-03): route Reportajes menu directly to /reportes-v2 shell |

## Wave 3 Additions (out-of-plan)

**Nav menu rerouting** — `ventago-app/src/navigation/vertical/index.ts` 의 Reportajes 메뉴를 collapsible 그룹에서 `/reportes-v2` 단일 링크로 변경. 사용자가 사이드바에서 바로 새 셸로 진입하도록 함. (dbee834)

## Verification

- `/reportes-v2` 진입 시 16-entry 사이드바 + Shell 표시 확인
- MVP 3개 보고서 (vendedor/gastos/breve-venta) Body embed 동작 확인
- Shallow routing 동작 확인 (full reload 없음)
- 13개 placeholder + legacyHref 링크 확인
- 사이드바 리렌더 최적화 확인 (React.memo + local-state search)
- 기존 `/reportes/*` 회귀 없음
- 사용자 승인: approved

## Deviations from Plan

**1. [Rule 2 - Missing UX] Nav menu rerouting**
- **Found during:** Task 3 verification
- **Issue:** Reportajes 메뉴가 여전히 기존 collapsible 그룹으로 노출되어 사용자가 새 셸에 도달하기 어려움
- **Fix:** `navigation/vertical/index.ts` 의 Reportajes entry를 `/reportes-v2` 직접 링크로 변경
- **Files modified:** ventago-app/src/navigation/vertical/index.ts
- **Commit:** dbee834

## Wave 4 Remaining Work

- 13개 placeholder entry 에 `bodyComponent` lazy import 추가
- 검색 입력 debounce
- 즐겨찾기 (localStorage) + 최근 실행 정렬
- Topbar Excel/PDF/Ejecutar 액션을 Body 와 배선

## Self-Check: PASSED

- FOUND commit 060d4f7 (ventago-app)
- FOUND commit 452cd76 (ventago-app)
- FOUND commit dbee834 (ventago-app)
- FOUND .planning/phases/08-reportajes-ux/08-03-SUMMARY.md
