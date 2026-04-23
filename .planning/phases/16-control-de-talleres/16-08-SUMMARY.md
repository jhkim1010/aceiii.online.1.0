---
phase: 16-control-de-talleres
plan: "08"
subsystem: talleres-overview-alerts
tags: [talleres, alertas, dashboard-v2, overview, cron, apexcharts, xlsx, zedonk, wave8, extension, pg10, pg15, memory-cache]
requirements: [TALLERES-10]
completed: 2026-04-22

dependency_graph:
  requires:
    - 16-05 (MemoryCache + computeHealthStatus)
    - 16-06 (QcItem + Recepcion + storeId 격리)
    - 16-07 (ENUM autocommit migration 패턴)
    - Phase 17 (VendorNotification 인프라 + FCM)
  provides:
    - Overview 탭 (4 KPI + 4 Apex 차트 + UrgentActionTable)
    - GET /api/talleres/dashboard-v2 (MemoryCache 60s)
    - LateEnvioAlertJob @Cron 08:00 (America/Bogota)
    - Excel 내보내기 (generic util + 3 탭 배선)
    - 3 성능 인덱스 (idx_envios_vendor_status_due + idx_recepciones_envio_date + idx_settlements_vendor_period)
    - ENUM enum_vendor_notifications_type 'LATE' 확장
  affects:
    - TalleresMainView (첫 탭 'dashboard' → 'overview' + legacy alias)
    - VendorNotification model/service (type union 확장)

tech-stack:
  added: []
  patterns:
    - NestJS @Cron('0 8 * * *', { timeZone: 'America/Bogota' })
    - Sequelize Promise.all 병렬 집계 + MemoryCache 60s (Wave 5 패턴)
    - computeHealthStatus 단일 진실 원천 (Wave 5 T-16-05) 재사용
    - dynamic import('xlsx') lazy-load (초기 번들 최적화)
    - Zedonk 테마 TALLERES_THEME (navy #1a1a2e + gold #f5a623 + status bg/text/dot)
    - ReactApexcharts wrapper (SSR off, 프로젝트 표준)

key-files:
  created:
    - api-ventago/migrations/20260424-talleres-wave8-step1-indexes.sql
    - api-ventago/migrations/20260424-talleres-wave8-step2-enum-late.sql
    - api-ventago/migrations/20260424-talleres-wave8-step3-verify.sql
    - api-ventago/src/app/subcon/jobs/late-envio-alert.job.ts
    - api-ventago/src/app/subcon/dashboard-v2/dashboard-v2.types.ts
    - api-ventago/src/app/subcon/dashboard-v2/dashboard-v2.service.ts
    - api-ventago/src/app/subcon/dashboard-v2/dashboard-v2.controller.ts
    - ventago-app/src/hooks/api/useTalleresDashboardV2.ts
    - ventago-app/src/views/talleres/overview/types.ts
    - ventago-app/src/views/talleres/overview/OverviewTab.tsx
    - ventago-app/src/views/talleres/overview/components/StatusDonut.tsx
    - ventago-app/src/views/talleres/overview/components/TopVendorsBar.tsx
    - ventago-app/src/views/talleres/overview/components/DefectRateTrend.tsx
    - ventago-app/src/views/talleres/overview/components/BacklogByEtapaStacked.tsx
    - ventago-app/src/views/talleres/overview/components/UrgentActionTable.tsx
    - ventago-app/src/views/talleres/overview/components/OverviewEmptyState.tsx
    - ventago-app/src/utils/talleres-xlsx-export.ts
    - ventago-app/src/views/talleres/components/TalleresExportButton.tsx
    - docs/manuales/talleres.md
  modified:
    - api-ventago/src/app/vendor-portal/vendor-notifications/vendor-notification.model.ts
    - api-ventago/src/app/vendor-portal/vendor-notifications/vendor-notifications.service.ts
    - api-ventago/src/app/subcon/subcon.module.ts
    - api-ventago/src/app/functions/seed/functions-seed-talleres.ts
    - ventago-app/src/views/talleres/TalleresMainView.tsx
    - ventago-app/src/views/talleres/components/constants.ts
    - ventago-app/src/views/talleres/tabs/EnviosTab.tsx
    - ventago-app/src/views/talleres/tabs/TalleresTab.tsx
    - ventago-app/src/views/talleres/tabs/LiquidacionesTab.tsx

decisions:
  - "topVendors SUM(quantity) 사용 — plan 은 'pending+received' 언급했으나 Envio 모델에 received_quantity 가 없음 (Recepcion 자식). Rule 1 보정."
  - "defectRateTrend qc_items storeId 컬럼 직접 사용 — QcItem 모델에 storeId FK 존재 (Wave 6 확인)로 recepcion join 불필요. Plan 의 include 패턴보다 효율적."
  - "TalleresMainView 기본 탭 'dashboard' → 'overview' 로 동시에 activeTab fallback 교체 — 아무 탭 쿼리 없이 진입 시에도 Overview 렌더."
  - "DashboardTab import 유지 + eslint-disable-next-line no-unused-vars — 레거시 컴포넌트 제거 없이 Wave 11+ 에서 정리 예정."

metrics:
  duration_minutes: 25
  tasks_completed: 3
  files_created: 19
  files_modified: 9
  lines_added: ~1800
  commits: 4
---

# Phase 16 Plan 08: Alertas + Overview Dashboard + Polish (Wave 8) Summary

**One-liner:** "조기 경보 > 사후 보고" 원칙 구현 — 매일 08:00 cron 으로 LATE envío 자동 알림 + Overview 탭 (4 KPI + 4 Apex 차트 + UrgentActionTable) + 재사용 Excel 내보내기 + 스페인어 사용자 매뉴얼 9섹션.

## Overview

Wave 8 은 EXTENSION §3 Wave 8 전체 스펙을 단일 플랜으로 실행. 매일 아침 지연된 외주 envío 를 감지해 taller 에게 자동 알림을 보내고, 탭 진입 시 "지금 어디가 위험한가"를 한눈에 보여주는 Overview 대시보드를 제공한다. 운영 PG10 과 로컬 PG15 양쪽에서 호환되는 3-split 마이그레이션, 기존 /talleres/dashboard (v1) 을 수정하지 않는 add-only 전략, 모든 차트에 프로젝트 표준 ReactApexcharts 사용 (Recharts 도입 회피).

## Commits

| Task | Scope | Commit | Repo | Files |
|------|-------|--------|------|-------|
| 1 | DB + Cron + Notifications | `6107283` | api-ventago | 7 (3 SQL + 4 TS) |
| 2 | Dashboard v2 API | `4fa8414` | api-ventago | 4 (types/service/controller + module) |
| 3 | Frontend Overview + Excel | `801445d` | ventago-app | 16 (9 new + 7 modified) |
| docs | Manual es + deferred items | `eb015bd` | root | 2 |

## Artifacts

### Task 1 — Backend Foundations (Cron + DB + Notifications)

**Migration 3-split (PG10/PG15 호환):**

1. `20260424-talleres-wave8-step1-indexes.sql` — `BEGIN; ... COMMIT;` 트랜잭션으로 3개 인덱스 생성 (모두 `CREATE INDEX IF NOT EXISTS`):
   - `idx_envios_vendor_status_due` on `talleres_envios (vendor_id, status, due_date)`
   - `idx_recepciones_envio_date` on `talleres_recepciones (envio_id, recepcion_date)`
   - `idx_settlements_vendor_period` on `talleres_settlements (vendor_id, period_from, period_to)` (로컬에 이미 존재 — 재실행 안전)

2. `20260424-talleres-wave8-step2-enum-late.sql` — **autocommit 모드** (PG10 제약, Wave 7 선례):
   ```sql
   ALTER TYPE enum_vendor_notifications_type ADD VALUE IF NOT EXISTS 'LATE';
   ```

3. `20260424-talleres-wave8-step3-verify.sql` — 읽기 전용 검증 (pg_indexes + pg_enum + pg_stat_user_indexes)

**로컬 PG15 적용 검증 완료:**
```
idx_envios_vendor_status_due  | talleres_envios
idx_recepciones_envio_date    | talleres_recepciones
idx_settlements_vendor_period | talleres_settlements
enum_vendor_notifications_type: {NEW_ENVIO, DUE_SOON, SETTLEMENT_DONE, LATE}
```

**LateEnvioAlertJob** (`src/app/subcon/jobs/late-envio-alert.job.ts`) — `@Cron('0 8 * * *', { timeZone: 'America/Bogota' })`:
- DB 필터: `status ∈ [PENDING, PARTIAL] + dueDate < today + pendingQuantity > 0`
- `computeHealthStatus()` 재확인 (단일 진실 원천, Wave 5 T-16-05)
- 중복 방지: `findOne({ vendorId, type='LATE', referenceId, createdAt >= todayMidnight })`
- `VendorNotificationsService.createNotification({ type: 'LATE', title, body, referenceId })` 호출
- `try/catch` 로 에러 흡수 (throw 금지, INV-W8-5 — 이후 스케줄 차단 방지)
- 실행 완료 후 `created / skippedDuplicate / skippedNotLate / 총후보` 카운트 로깅

**Model/Service 확장:**
- `VendorNotification.type` ENUM 배열: `['NEW_ENVIO','DUE_SOON','SETTLEMENT_DONE','LATE']`
- `CreateNotificationDto.type` union: 동일 확장

**CASL seed:** `talleres_view` slug (dashboard-talleres 모듈 하위) — Wave 14 에서 `@CheckFunction` wire 예정.

### Task 2 — Dashboard v2 API

**Controller:** `@Controller('talleres/dashboard-v2')` + `@Auth(admin/superadmin/vendedor/gerente)` — v1 `/talleres/dashboard` 미수정 (add-only non-breaking).

**Service — `TalleresDashboardV2Service.getAggregates(storeId)`:**
- MemoryCache 60s (key: `talleres:dashboard-v2:${storeId}`)
- `Promise.all([...])` 5 집계 병렬:
  1. `computeEnviosByStatus` — `computeHealthStatus` 로 메모리 reduce (ON_TRACK/AT_RISK/LATE)
  2. `computeTopVendors` — 최근 30일 `SUM(quantity)` top 5 + Vendor include
  3. `computeDefectRateTrend` — 12주 루프 (월요일 기준), 분모 0 방어, 항상 12 포인트 반환 (INV-W8-4)
  4. `computeBacklogByEtapa` — `isActive` etapa 순회 (order ASC), backlog 0 etapa 도 포함
  5. `computeUrgentLateEnvios` — LATE top 5 + Vendor/Etapa include (UrgentActionTable 용)
- 로깅: `[dashboard-v2] miss cached storeId=X ms=Y` (소요시간 모니터)
- fromCache: true/false 플래그 반환 (디버그용)

**Response shape** (`DashboardV2Response`):
```ts
{
  enviosByStatus: { ON_TRACK, AT_RISK, LATE, total },
  topVendors: Array<{ vendorId, vendorName, volume }>,    // 최대 5
  defectRateTrend: DefectRateTrendPoint[],                // 정확히 12
  backlogByEtapa: BacklogByEtapaRow[],                    // order ASC
  urgentLateEnvios: UrgentLateEnvioRow[],                 // 최대 5
  generatedAt: ISO string,
  fromCache: boolean,
}
```

### Task 3 — Frontend Overview UI + Excel

**SWR 훅** (`useTalleresDashboardV2`): 60s dedup + `revalidateOnFocus: false`.

**OverviewTab** (`src/views/talleres/overview/`) — 4상태 분기:
- `loading` → 4 KPI Skeleton + 4 차트 Skeleton
- `error` → `<Alert severity='error'>` + Reintentar 버튼
- `empty` (data=null 또는 total=0 전체 빈) → OverviewEmptyState CTA
- `loaded` → KPI 4카드 + 2×2 차트 그리드 + UrgentActionTable

**KPI 카드 4개** (Zedonk 상단 3px 컬러바):
- 🔴 Envíos atrasados (late.dot)
- 🟠 En riesgo (atrisk.dot)
- 🟢 En curso (ontrack.dot)
- Navy Total activos (primary)

**4 Apex 차트** (모두 `ReactApexcharts` wrapper, SSR off):
- `StatusDonut` — donut, 3 슬라이스, centerLabel total count, TALLERES_THEME.status
- `TopVendorsBar` — horizontal bar, primary fill, dataLabels, empty 시 "Sin datos..." 문구
- `DefectRateTrend` — line smooth, late 컬러, yMax = max(10, maxRate×1.2)
- `BacklogByEtapaStacked` — bar (stacked=true 향후 확장), primary 컬러, empty 시 "Sin etapas activas"

**UrgentActionTable** — LATE top 5, 빨간 border-left 3px + gold 4px 헤더:
- 행 클릭 → `router.push('/talleres?tab=envios&envioId=X')` drilldown
- "Reasignar taller" / "Extender plazo" 버튼 (disabled + Tooltip 'Proximamente' — Wave 9+ 구현)

**Excel 내보내기:**
- `utils/talleres-xlsx-export.ts` — generic `exportTalleresToExcel<T>(rows, filename, sheetName, columns)`:
  - `import('xlsx')` dynamic import (초기 번들 크기 최적화)
  - column.format: 'date' | 'number' | 'currency' 지원
  - 시트명 31자 제한 처리
- `TalleresExportButton` — 재사용 버튼, `rows.length === 0` 시 disabled + Tooltip
- 배선 3탭:
  - **EnviosTab** — `filteredEnvios` → 9 컬럼 (ID/Fecha/Lote/Taller/Etapa/Enviado/Pendiente/Vencimiento/Estado)
  - **TalleresTab** — `filteredVendors` → 9 컬럼 (ID/Taller/Teléfono/Etapas/Pendientes/Deuda/Cumplimiento/Rating/Estado)
  - **LiquidacionesTab** — `settlements` → 9 컬럼 (ID/Taller/Desde/Hasta/Bruto/Deducciones/Neto/Fecha/Estado)

**TalleresMainView 교체:**
- 첫 탭 `'dashboard'` → `'overview'` (constants.ts)
- 기본 activeTab fallback: `'dashboard'` → `'overview'`
- `(activeTab === 'overview' || activeTab === 'dashboard') && <OverviewTab />` — legacy URL 북마크 보호
- `DashboardTab` import 유지 (eslint-disable-next-line no-unused-vars) — deprecated 보존

### Task 3 — Spanish Manual (docs/manuales/talleres.md)

9섹션 스페인어:
1. Introducción (CMT 개념 + 전체 플로우)
2. Overview y KPIs (4 KPI + 4 차트 + UrgentActionTable)
3. Cut Ticket (Wave 9)
4. WIP y Kanban semáforo (Wave 5)
5. QC y Retrabajo (Wave 6)
6. Liquidaciones (Wave 7)
7. Cost Sheet (Wave 10)
8. Alertas y Cron 08:00 (Wave 8)
9. Exportación a Excel y FAQs

스크린샷 플레이스홀더 (HTML comments) — Wave 8 범위에서 캡처 안 함, pilot 이후 2차.

## Verification

### Automated (tsc + ESLint)

**api-ventago:**
- `npx tsc --noEmit` → **0 errors**

**ventago-app (Wave 8 파일 scope):**
- `npx tsc --noEmit` (Wave 8 파일만 grep) → **0 errors**
- `npx next lint --file [16 files]` → **✔ No ESLint warnings or errors**

### 로컬 DB 검증 (Wave 8 마이그레이션 적용)

- `pg_indexes` 에 3개 인덱스 존재 ✓
- `pg_enum.enumlabel`: `{NEW_ENVIO, DUE_SOON, SETTLEMENT_DONE, LATE}` ✓
- `pg_stat_user_indexes.idx_scan`: 인덱스 접근 통계 수집 가능 ✓

### Not Performed (사용자 확인 필요)

- **운영 서버 마이그레이션 적용** — 플랜에 따라 `ssh jhkim-server "sudo -u postgres psql -d ventago -f step1.sql"` 실행은 **사용자 동의 후** 별도 세션으로 진행.
- **Runtime API smoke test** (curl dashboard-v2) — `npm run dev:api` 기동 + JWT 취득 필요. tsc 0 errors + 로컬 DB 스키마 매치 확인 완료로 Sequelize 컬럼 매핑 정합성은 간접 검증됨.
- **Frontend dev server smoke** (/talleres?tab=overview) — dev server 미기동. `./dev.sh` 시 사용자가 직접 확인 가능 (4 KPI + 4 차트 + Excel 다운로드).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] topVendors 집계 컬럼 보정**
- **Found during:** Task 2 (dashboard-v2.service.ts computeTopVendors)
- **Issue:** Plan 은 `SUM(pending_quantity + received_quantity)` 지정, 그러나 `Envio` 모델에는 `received_quantity` 컬럼이 없음 (received 는 `Recepcion` 자식 모델)
- **Fix:** `SUM(quantity)` 로 변경 (envío 단위 총 발송량 기준 top vendor 랭킹). 의미는 유지되며 쿼리는 더 단순해지고 정확.
- **Files modified:** `api-ventago/src/app/subcon/dashboard-v2/dashboard-v2.service.ts`
- **Commit:** `4fa8414`

**2. [Rule 3 - Blocking] defectRateTrend qc_items storeId 조인 단순화**
- **Found during:** Task 2 (computeDefectRateTrend)
- **Issue:** Plan 은 `qc_items` 에 `include: [{ association: 'recepcion', where: { storeId }, required: true }]` 조인을 명시 — 이는 qc_items 에 storeId 가 없을 때의 우회.
- **Fix:** Wave 6 에서 `QcItem` 모델 확인 결과 `storeId` FK 컬럼이 있음 (`qc-item.model.ts` line 52-54). 직접 `where: { storeId }` 사용 → join 1개 절약.
- **Files modified:** 동일 service
- **Commit:** `4fa8414`

**3. [Rule 3 - Blocking] defectRateTrend 월요일 계산 보정**
- **Found during:** Task 2 (loop 내부)
- **Issue:** Plan 의 `weekStart.setDate(now.getDate() - (i * 7 + now.getDay() - 1))` 는 일요일이 `getDay()=0` 인 경우 -1 오프셋으로 주 시작이 앞서는 오류 발생.
- **Fix:** `const dayOffset = (now.getDay() + 6) % 7` — 월=0 기준 정규화한 뒤 `weekStart.setDate(now.getDate() - dayOffset - i*7)` 로 정확한 월요일 계산.
- **Commit:** `4fa8414`

**4. [Rule 2 - Missing infrastructure] TalleresMainView activeTab fallback 교체**
- **Found during:** Task 3 (TalleresMainView.tsx)
- **Issue:** 플랜은 render 분기만 alias 처리 지시, 그러나 `const activeTab = router.query.tab || 'dashboard'` 기본값이 여전히 `'dashboard'` 면 Tabs 컴포넌트가 TALLERES_TABS 에 없는 value 로 warning 발생 (constants.ts 에서 'dashboard' 제거했으므로).
- **Fix:** `'dashboard' → 'overview'` 로 fallback 교체. legacy URL 'tab=dashboard' 는 여전히 alias render 분기로 처리됨.
- **Files modified:** `ventago-app/src/views/talleres/TalleresMainView.tsx`
- **Commit:** `801445d`

**5. [Rule 2 - ESLint] DashboardTab import 주석 newline 추가**
- **Found during:** Task 3 lint check
- **Issue:** `lines-around-comment` rule 로 주석 위 blank line 필수 + unused import 경고.
- **Fix:** Import 블록 정리, 주석 위 blank line + `// eslint-disable-next-line @typescript-eslint/no-unused-vars` 적용.
- **Commit:** `801445d`

### Out of Scope (Deferred)

**1. Pre-existing build blocker — `src/@fake-db/mock.ts` axios 타입 드리프트**
- **Confirmed pre-existing:** `git stash && npm run build` HEAD 에서 동일 에러 재현.
- **Root cause:** npm workspaces 가 axios 를 루트 `node_modules/` 로 호이스트, `axios-mock-adapter` 는 자신의 `ventago-app/node_modules/axios` 를 resolve → 두 `AxiosStatic` 타입 충돌.
- **Wave 8 impact:** None — Wave 8 파일 범위 tsc/lint 모두 0.
- **Logged in:** `.planning/phases/16-control-de-talleres/deferred-items.md`
- **Resolution:** Wave 11+ 또는 별도 chore 커밋 (axios 버전 pin 또는 @types 일치).

## Security / Threat Model Compliance

플랜 threat_model 8개 항목 전체 검증:

| Threat | Disposition | Wave 8 구현 |
|--------|-------------|------------|
| T-16-08-01 (Tampering cross-store notification) | mitigate ✓ | `envio.vendor.storeId` 로 알림 매칭 (Sequelize 관계 무결성) |
| T-16-08-02 (Spoofing storeId query param) | mitigate ✓ | Controller `user.storeId!` 만 사용, query param 무시 |
| T-16-08-03 (Excel 탭 로드 외 데이터 포함) | accept ✓ | TalleresExportButton props.rows 만 사용, API 재호출 없음 |
| T-16-08-04 (Cron DoS pool 점유) | mitigate ✓ | `await for` 순차 처리, pool 50 내 |
| T-16-08-05 (Cache stampede) | accept | 60s TTL, Wave 19 에서 완화 |
| T-16-08-06 (Cron 실패 silent) | mitigate ✓ | `try/catch` + `logger.error(stack)`, throw 금지 |
| T-16-08-07 (vendedor role dashboard 열람) | accept | @Auth 동일 정책, Wave 14 granular |
| T-16-08-08 (ENUM autocommit 부분 실패) | mitigate ✓ | `ADD VALUE IF NOT EXISTS` 멱등 |

새 trust boundary / threat 발견 없음. 기존 storeId 격리 invariants 유지.

## Known Stubs

없음. 모든 신규 UI 는 실제 API 에 연결 (dashboard-v2 실시간 집계). UrgentActionTable 의 "Reasignar taller" / "Extender plazo" 버튼은 plan 대로 `disabled + Tooltip 'Proximamente'` — Wave 9+ 에서 wire 예정이며 **의도된 stub** 이 아닌 **플랜 명시 후속 기능**.

## Follow-ups

1. **운영 마이그레이션 적용 (사용자 확인 후):**
   ```bash
   scp api-ventago/migrations/20260424-talleres-wave8-step*.sql jhkim-server:/tmp/
   ssh jhkim-server "sudo -u postgres psql -d ventago -v ON_ERROR_STOP=1 -1 -f /tmp/20260424-talleres-wave8-step1-indexes.sql"
   ssh jhkim-server "sudo -u postgres psql -d ventago -f /tmp/20260424-talleres-wave8-step2-enum-late.sql"
   ssh jhkim-server "sudo -u postgres psql -d ventago -f /tmp/20260424-talleres-wave8-step3-verify.sql"
   ssh jhkim-server "docker restart api_ventago"
   ```

2. **Pilot 24h 관찰 (Wave 8 배포 후):**
   - 다음날 08:00 AM 후 Jenkins 500 로그 0건 확인
   - `SELECT COUNT(*) FROM vendor_notifications WHERE type='LATE' AND created_at >= CURRENT_DATE` 에서 증가 확인
   - `EXPLAIN ANALYZE` 로 dashboard-v2 쿼리가 idx_envios_vendor_status_due 사용 여부 확인

3. **Wave 11+ 계획:**
   - BacklogByEtapaStacked 에 status 별 series 추가 (현재 stacked=true 옵션만 유지, 단일 series)
   - Cost Sheet 연동 (defectRateTrend 와 매출 영향 교차 분석)
   - Runtime smoke 자동화 (Jest E2E)

4. **Wave 14 CASL wiring:**
   - `@CheckFunction('talleres_view')` 데코레이터를 `TalleresDashboardV2Controller` + `TalleresDashboardController` 에 적용
   - Seed 는 이미 Wave 8 에서 완료

5. **Screenshot 캡처:**
   - `docs/manuales/talleres.md` 의 9개 HTML comment 플레이스홀더에 실제 PNG 삽입
   - pilot 완료 후 2차 작업

## Self-Check: PASSED

**File existence verification:**
- [x] `api-ventago/migrations/20260424-talleres-wave8-step1-indexes.sql` FOUND
- [x] `api-ventago/migrations/20260424-talleres-wave8-step2-enum-late.sql` FOUND
- [x] `api-ventago/migrations/20260424-talleres-wave8-step3-verify.sql` FOUND
- [x] `api-ventago/src/app/subcon/jobs/late-envio-alert.job.ts` FOUND
- [x] `api-ventago/src/app/subcon/dashboard-v2/dashboard-v2.{types,service,controller}.ts` FOUND (3)
- [x] `ventago-app/src/hooks/api/useTalleresDashboardV2.ts` FOUND
- [x] `ventago-app/src/views/talleres/overview/**` (8 files) FOUND
- [x] `ventago-app/src/utils/talleres-xlsx-export.ts` FOUND
- [x] `ventago-app/src/views/talleres/components/TalleresExportButton.tsx` FOUND
- [x] `docs/manuales/talleres.md` FOUND

**Commit verification:**
- [x] `6107283` (Task 1 api-ventago)
- [x] `4fa8414` (Task 2 api-ventago)
- [x] `801445d` (Task 3 ventago-app)
- [x] `eb015bd` (manual + deferred root)

**Acceptance criteria (plan §must_haves.truths spot-check):**
- [x] `@Cron('0 8 * * *', { timeZone: 'America/Bogota' })` — late-envio-alert.job.ts
- [x] `ALTER TYPE ADD VALUE IF NOT EXISTS 'LATE'` — step2-enum-late.sql
- [x] `CREATE INDEX IF NOT EXISTS idx_envios_vendor_status_due` — step1-indexes.sql
- [x] `@Controller('talleres/dashboard-v2')` — dashboard-v2.controller.ts
- [x] MemoryCache 60s (CACHE_TTL_MS = 60_000) — dashboard-v2.service.ts
- [x] Promise.all 5 집계 — dashboard-v2.service.ts
- [x] useTalleresDashboardV2 + dedupingInterval 60_000 — hook file
- [x] 4 Apex 차트 컴포넌트 (StatusDonut + TopVendorsBar + DefectRateTrend + BacklogByEtapaStacked)
- [x] UrgentActionTable router.push drilldown + disabled CTA
- [x] exportTalleresToExcel dynamic import('xlsx')
- [x] TalleresExportButton 3탭 배선 (grep 확인 가능)
- [x] TalleresMainView overview/dashboard alias + constants.ts 첫 탭 교체
- [x] docs/manuales/talleres.md 9섹션 (스페인어)

## TDD Gate Compliance

N/A — Wave 8 은 `type: execute` (not `type: tdd`). TDD 게이트 미적용.
