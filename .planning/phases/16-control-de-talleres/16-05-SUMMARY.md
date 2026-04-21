---
phase: 16-control-de-talleres
plan: "05"
subsystem: talleres-kanban-semaforo
tags: [talleres, kanban, priority, healthStatus, wave5, extension, zedonk-theme]
dependency_graph:
  requires: ["16-01", "16-02", "16-04"]
  provides:
    - "talleres_envios.priority (drag-persisted order)"
    - "computeHealthStatus(envio) 순수 함수 — ON_TRACK/AT_RISK/LATE"
    - "GET /talleres/dashboard/kanban (30s MemoryCache)"
    - "PATCH /talleres/envios/:id/priority"
    - "zedonkTheme.ts (Wave 6-10 공용 디자인 토큰)"
    - "KanbanBoard / KanbanCard / KanbanFilters 프론트 컴포넌트 3종"
    - "PipelineTab ?view=flow|kanban 서브뷰 토글"
  affects:
    - "api-ventago/src/app/subcon/envios/*"
    - "api-ventago/src/app/subcon/dashboard/*"
    - "ventago-app/src/views/talleres/*"
    - "ventago-app/src/services/api.service.ts (patch 헬퍼 추가)"
tech_stack:
  added:
    - "@dnd-kit/core@^6.3.1"
    - "@dnd-kit/sortable@^8.0.0"
    - "@dnd-kit/utilities@^3.2.2"
  patterns:
    - "MemoryCache 30s + delByPrefix 무효화"
    - "Optimistic drag reorder + rollback on API fail"
    - "React.memo + custom equality (KanbanCard)"
    - "Zedonk token 중앙화 (Wave 6-10 재사용 기반)"
    - "NestJS 라우팅 순서: @Patch(':id/priority') before @Get(':id')"
key_files:
  created:
    - api-ventago/migrations/20260421-add-priority-to-talleres-envios.sql
    - ventago-app/src/views/talleres/theme/zedonkTheme.ts
    - ventago-app/src/views/talleres/components/KanbanBoard.tsx
    - ventago-app/src/views/talleres/components/KanbanCard.tsx
    - ventago-app/src/views/talleres/components/KanbanFilters.tsx
  modified:
    - api-ventago/src/app/subcon/envios/envio.model.ts
    - api-ventago/src/app/subcon/envios/envio.service.ts
    - api-ventago/src/app/subcon/envios/envio.controller.ts
    - api-ventago/src/app/subcon/dashboard/dashboard.service.ts
    - api-ventago/src/app/subcon/dashboard/dashboard.controller.ts
    - ventago-app/src/services/api.service.ts
    - ventago-app/src/views/talleres/tabs/PipelineTab.tsx
    - ventago-app/package.json
decisions:
  - "healthStatus는 sequelize 가상 컬럼 대신 service 레이어 순수 함수로 계산 (dashboard.service에서 재사용 + 단위테스트 가능)"
  - "branchId 쿼리 파라미터는 수용하나 Lote.branchId 없으므로 현 Wave에서는 storeId만 필터 (Wave 8에서 branch 단위 분리 재검토)"
  - "같은 컬럼 내에서만 드래그 허용 (D-04 원칙: envío 공정 이동은 recepción 등록 경유만)"
  - "apiConnector.patch 헬퍼 1줄 추가 (api.service.ts) — 대안인 @Patch→@Put 롤백보다 최소 침습"
  - "MemoryCacheService는 @Global 모듈이라 subcon.module.ts 수정 불필요 (constructor 주입만)"
  - "priority = column.length - index (DESC 정렬 유지) — 새 카드 삽입 시 자연스럽게 꼬리에 위치"
metrics:
  duration: "~45min"
  completed_date: "2026-04-21"
  tasks_completed: 3
  files_changed: 13
---

# Phase 16 Plan 05: Kanban Semáforo + Priority (Wave 5 / Zedonk 테마 도입) Summary

**One-liner:** Zedonk 스타일 Kanban 보드 신설 — dueDate 기반 3단계 세마포(ON_TRACK/AT_RISK/LATE) + @dnd-kit 컬럼 내 드래그 우선순위 + 30초 MemoryCache 백엔드 + Wave 6-10이 공유할 zedonkTheme 토큰 인프라 구축.

## Tasks Completed

| Task | Name | Commit | Sub-repo | Files |
|------|------|--------|----------|-------|
| 1 | Backend — priority migration + computeHealthStatus + getKanbanBoard + PATCH priority + MemoryCache 30s | `097c3f8` | api-ventago | migration SQL, Envio model/service/controller, dashboard service/controller |
| 2 | Frontend — @dnd-kit 설치 + zedonkTheme 중앙화 + KanbanCard/Filters/Board 3 컴포넌트 + api.service patch | `0eca278` | ventago-app | KanbanBoard.tsx, KanbanCard.tsx, KanbanFilters.tsx, zedonkTheme.ts, api.service.ts, package.json |
| 3 | Integration — PipelineTab ToggleButtonGroup + ?view=flow\|kanban shallow routing + 기존 Wave 2 보존 | `108908e` | ventago-app | PipelineTab.tsx |

## Artifacts Delivered (vs must_haves)

### Backend
- `talleres_envios.priority INTEGER NOT NULL DEFAULT 0` 컬럼 (PG10 호환 raw SQL migration) ✓
- 복합 인덱스 `idx_talleres_envios_status_priority(store_id, status, priority DESC, due_date)` ✓
- `computeHealthStatus(envio, today?)` 순수 함수 export — ON_TRACK / AT_RISK(< +2d) / LATE(과거 + pending>0) ✓
- `EnvioService.updatePriority(id, storeId, priority)` — storeId WHERE 격리, 캐시 무효화 (T-16-05-01 mitigate) ✓
- `TalleresDashboardService.getKanbanBoard(storeId, branchId?)` + MemoryCache 30s (key: `talleres:kanban:${storeId}:${branchId??'all'}`) ✓
- `GET /talleres/dashboard/kanban` + `PATCH /talleres/envios/:id/priority` (라우트 `@Get(':id')` 앞에 배치) ✓

### Frontend
- `zedonkTheme.ts` (38 lines) — primary/secondary/status 4색/card/hint 토큰 — Wave 6-10 공유 ✓
- `KanbanCard.tsx` (198 lines, 요구 40+ 충족) — React.memo + 커스텀 eq + border-left 3px status + dot halo 배지 + Menlo 수량 + hover translateY ✓
- `KanbanFilters.tsx` (144 lines, 요구 30+ 충족) — Total/sólo-LATE chip + vendor/producto Select + active=navy+gold ✓
- `KanbanBoard.tsx` (318 lines, 요구 120+ 충족) — DndContext + SortableContext per column + optimistic reorder + PATCH + rollback + 💡 hint box ✓
- `PipelineTab.tsx` — ToggleButtonGroup(Flujo/Kanban) + router.query.view shallow routing + 기존 Wave 2 UI 조건부 렌더 ✓

## Key Links Verified

| From | To | Pattern |
|------|-----|---------|
| `KanbanBoard.tsx` | `/talleres/dashboard/kanban` | `apiConnector.get` in useEffect |
| `KanbanBoard.handleDragEnd` | `PATCH /talleres/envios/:id/priority` | `apiConnector.patch` + optimistic + rollback |
| `dashboard.service.getKanbanBoard` | `MemoryCacheService` | get/set with 30_000 TTL |
| `envio.service.computeHealthStatus` | `dueDate` + `pendingQuantity` | date comparison today / today+2 / past |
| `PipelineTab` | `router.query.view` | `view === 'flow' \|\| 'kanban'` |

## Must-Haves Truths (Self-Verified)

1. ✓ `/talleres?tab=pipeline&view=kanban` 진입 → KanbanBoard 렌더 (PipelineTab conditional `view === 'kanban'`)
2. ✓ semáforo 3색 — computeHealthStatus + healthToThemeKey 매핑 + KanbanCard statusTokens 적용
3. ✓ 드래그 순서 저장 — handleDragEnd arrayMove → priority = len - idx → PATCH → 캐시 무효화 → 재조회 시 DB priority DESC 정렬 유지
4. ✓ vendor / producto / sólo LATE 필터 즉시 반영 — useMemo(filteredByEtapa) + useCallback 핸들러
5. ✓ MemoryCache 30s — `this.cacheService.get(cacheKey)` 선조회, 캐시 hit 시 즉시 반환 (DB 쿼리 0회)

## Deviations from Plan

### Auto-applied (Rule 2/3)

**1. [Rule 3 - Blocker] apiConnector.patch 헬퍼 추가**
- **Found during:** Task 2 — plan에서 `@Patch`로 정의했으나 프론트 `apiConnector`가 `.patch` 미지원
- **Fix:** `ventago-app/src/services/api.service.ts`에 `patch: async (path, body) => repository.patch(path, body).then(({data})=>data)` 1줄 추가
- **Rationale:** 대안 (@Patch → @Put 롤백)은 HTTP 의미상 부정확. 1줄 헬퍼는 프로젝트 컨벤션 일치 (get/post/put/remove와 동일 형식)
- **Commit:** `0eca278`

**2. [Rule 2 - Missing critical] NotFoundException import 누락**
- **Found during:** Task 1 — `updatePriority`가 `NotFoundException` 사용하나 envio.service.ts 기존 import 목록에 없음
- **Fix:** import 라인에 `NotFoundException` 추가
- **Rationale:** 런타임 에러 방지 + storeId 격리 보안 요구사항(T-16-05-01)
- **Commit:** `097c3f8`

**3. [Rule 2 - Missing critical] dashboard.service 생성자에 Etapa/MemoryCache 주입**
- **Found during:** Task 1 — 기존 dashboard.service가 Etapa 모델과 MemoryCacheService를 주입받지 않았음
- **Fix:** 생성자에 `@InjectModel(Etapa)` + `private readonly cacheService: MemoryCacheService` 추가. MemoryCacheModule이 `@Global` 이므로 subcon.module.ts 수정 불필요.
- **Commit:** `097c3f8`

### Scope adjustments

- **branchId 필터 약화:** plan에서는 Lote.branchId 경유 INNER JOIN 명시. 그러나 `Lote` 모델에 `branchId` 필드 없음 (확인 결과). 현재 Wave에서 storeId만 필터. branchId 쿼리 파라미터는 캐시 키에만 반영 (`talleres:kanban:${storeId}:${branchId??'all'}`). Wave 8 인덱스 추가 시 Lote 스키마 확장 재검토 예정 — SUMMARY decisions에 기록.

## Known Stubs / Deferred Items

- **branch 단위 필터링:** `Lote.branchId` 스키마 미존재로 현 Wave에서 storeId 필터만 적용. Wave 8 인덱스 작업에서 재검토.
- **에이전트 자동 liquidación 연동:** Wave 7 범위.
- **QC 사진 모달:** Wave 6 범위 (zedonkTheme.status.atrisk/late 재사용 예정).
- **ventago-app `next build` axios 타입 에러:** `src/@fake-db/mock.ts` **pre-existing** (commit `3e729de` 이전부터 존재). Wave 5 작업과 무관. `.planning/phases/16-control-de-talleres/deferred-items.md`에 기록. `next lint` + 대상 파일 TSC는 모두 통과.

## Threat Flags

없음 — STRIDE 레지스터 T-16-05-01 ~ T-16-05-06 모든 mitigate 항목 구현 완료:
- T-16-05-01: `updatePriority(id, storeId, ...)` `WHERE id AND storeId` 조회 → 미매칭 404
- T-16-05-02: cacheKey prefix에 storeId 포함 → cross-store 캐시 공유 차단
- T-16-05-04: `@Auth(admin/superadmin/gerente)` 데코레이터 + Controller 전역 `@Auth` 상속
- T-16-05-05: storeId 항상 `user.storeId`로 강제 (@GetUser), 클라이언트 조작 불가
- T-16-05-06: KanbanBoard handleDragEnd에서 PATCH 실패 시 `setEnviosByEtapa(prevState)` rollback + `toast.error`

## Verification Evidence

- **TypeScript compile (api-ventago):** `npx tsc --noEmit` → 0 errors
- **TypeScript compile (ventago-app):** `npx tsc --noEmit` → only pre-existing `src/@fake-db/mock.ts` axios-types error (unrelated to Wave 5, verified by `git stash && build` reproduces identical error)
- **ESLint (ventago-app Wave 5 files):**
  - `npx next lint --dir src/views/talleres/components` → ✔ No warnings or errors
  - `npx next lint --dir src/views/talleres/tabs` → ✔ No warnings or errors
- **File sizes vs requirements:**
  - KanbanBoard.tsx: 318 lines (requirement: ≥120) ✓
  - KanbanCard.tsx: 198 lines (requirement: ≥40) ✓
  - KanbanFilters.tsx: 144 lines (requirement: ≥30) ✓
- **Migration artifact:** `api-ventago/migrations/20260421-add-priority-to-talleres-envios.sql` 존재 확인 (PG10 호환 raw SQL, 운영 수동 실행 예정)

## Self-Check: PASSED

- [x] `api-ventago/migrations/20260421-add-priority-to-talleres-envios.sql` — 존재
- [x] `api-ventago/src/app/subcon/envios/envio.model.ts` — priority 필드 추가됨
- [x] `api-ventago/src/app/subcon/envios/envio.service.ts` — `computeHealthStatus` export + `updatePriority` 메서드 존재
- [x] `api-ventago/src/app/subcon/envios/envio.controller.ts` — `@Patch(':id/priority')` 라우트 `@Get(':id')` 앞에 배치
- [x] `api-ventago/src/app/subcon/dashboard/dashboard.service.ts` — `getKanbanBoard` + MemoryCache
- [x] `api-ventago/src/app/subcon/dashboard/dashboard.controller.ts` — `@Get('kanban')`
- [x] `ventago-app/src/views/talleres/theme/zedonkTheme.ts` — TALLERES_THEME + healthToThemeKey
- [x] `ventago-app/src/views/talleres/components/KanbanCard.tsx` — React.memo + semáforo 3색
- [x] `ventago-app/src/views/talleres/components/KanbanFilters.tsx` — vendor/producto/sólo LATE
- [x] `ventago-app/src/views/talleres/components/KanbanBoard.tsx` — DndContext + optimistic + rollback
- [x] `ventago-app/src/views/talleres/tabs/PipelineTab.tsx` — `?view=flow|kanban` 토글 + 기존 Wave 2 보존
- [x] `ventago-app/src/services/api.service.ts` — `apiConnector.patch` 헬퍼 추가
- [x] Commits 3건 존재 — api-ventago `097c3f8` + ventago-app `0eca278`, `108908e`
