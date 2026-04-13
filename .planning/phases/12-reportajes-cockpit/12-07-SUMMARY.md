---
phase: 12-reportajes-cockpit
plan: "07"
subsystem: frontend-reports, backend-users
tags: [compare-mode, badge-system, meta-target, cockpit, reports-v2]
dependency_graph:
  requires: ["12-02", "12-03", "12-04", "12-05", "12-06"]
  provides: [compare-toggle, compare-panel, badge-rules, meta-input-dialog, users-meta-api]
  affects: [CockpitLayout, VendedorCockpitBody, users-table]
tech_stack:
  added: []
  patterns:
    - "badge rules engine — pure frontend calculation from backend data (no extra API calls)"
    - "compare panel — multi-series SVG line overlay + bar comparison"
    - "meta input — PUT /users/:id/meta with nullable DECIMAL target"
    - "DB migration — transactional addColumn with rollback script"
key_files:
  created:
    - ventago-app/src/views/reports-v2/components/BadgeRules.ts
    - ventago-app/src/views/reports-v2/components/CompareToggle.tsx
    - ventago-app/src/views/reports-v2/components/ComparePanel.tsx
    - ventago-app/src/views/reports-v2/components/MetaInputDialog.tsx
    - api-ventago/src/app/users/dto/update-meta.dto.ts
    - api-ventago/migrations/20260415-add-vendor-meta.js
  modified:
    - ventago-app/src/views/reports-v2/CockpitLayout.tsx
    - api-ventago/src/app/users/users.service.ts
    - api-ventago/src/app/users/users.controller.ts
    - api-ventago/src/app/users/users.model.ts
decisions:
  - "배지 룰은 프론트에서 계산 — 백엔드 추가 호출 없이 기존 cockpit 응답 데이터에서 파생"
  - "CompareToggle을 CockpitLayout에 통합 (optional props) — 하위 호환 유지, prop 없으면 미렌더"
  - "MetaInputDialog는 PUT /users/:id/meta 단일 endpoint 사용 — pool 절약"
  - "migration은 트랜잭션 안에서 NULL 허용 addColumn만 — 인덱스/제약 없음, 기존 행 영향 없음"
  - "ComparePanel Lista 탭 생략 — 비교 모드에서 의미 없으므로 Tendencia+Mix 2탭만"
metrics:
  duration_minutes: 35
  tasks_completed: 6
  tasks_total: 6
  files_created: 6
  files_modified: 4
  completed_date: "2026-04-13"
---

# Phase 12 Plan 07: Comparison Mode + Personalización Summary

비교 모드(CompareToggle+ComparePanel), Meta 목표 입력(MetaInputDialog+백엔드 API), 배지 룰 엔진(BadgeRules.ts)을 구현하고 CockpitLayout에 비교 토글을 통합했다.

## Tasks Completed

| Task | Description | Commit | Files |
|------|-------------|--------|-------|
| 1 | BadgeRules.ts 배지 룰 엔진 | 0ab920e | BadgeRules.ts |
| 2 | CompareToggle 컴포넌트 | a0b06d8 | CompareToggle.tsx |
| 3 | ComparePanel 컴포넌트 | ebf4167 | ComparePanel.tsx |
| 4 | MetaInputDialog 컴포넌트 | 75dacc0 | MetaInputDialog.tsx |
| 5 | 백엔드 Meta API + 마이그레이션 | 4194e59 | update-meta.dto.ts, users.service.ts, users.controller.ts, users.model.ts, migration |
| 6 | CockpitLayout compare 통합 | 7cd2b5c | CockpitLayout.tsx |

## What Was Built

### BadgeRules.ts
순수 프론트엔드 배지 룰 엔진. 백엔드 cockpit 응답 데이터를 입력으로 받아 배지를 계산한다.
- `computeFireBadges` — 최근 N기간 연속 1등 (이력 없으면 현재 1등에게만)
- `computeWarningBadges` — 할인율 ≥ 그룹 평균 × 1.5
- `computeDiamondBadges` — 객단가 ≥ 그룹 평균 × 1.3
- `computeAllBadges` — 통합 함수, `Map<sellerId, Badge[]>` 반환

### CompareToggle.tsx
⚖ 아이콘 토글 버튼. `active` prop으로 상태 반영, `onToggle` 콜백으로 상위 상태 제어.

### ComparePanel.tsx
선택된 항목(최대 4개) 비교 패널.
- Tendencia 탭: 다색 라인 오버레이 SVG 차트 (4색 팔레트: 청/적/황/녹)
- Mix 탭: 총매출 막대 비교
- 항목별 Chip 표시 + 개별 제거 버튼

### MetaInputDialog.tsx
사장이 판매원별 월 목표 매출을 설정하는 다이얼로그.
- `PUT /users/:id/meta` 호출
- 빈 값 저장 = 목표 초기화(null)
- Enter 키 저장, 에러 표시, 저장 중 스피너

### Backend Meta API
- `UpdateMetaDto` — `monthlySalesTarget?: number | null` (class-validator)
- `Users` 모델에 `monthlySalesTarget: DECIMAL(15,2) NULL` 컬럼 추가
- `UsersService.updateMeta()` — 단일 UPDATE, pool 절약
- `UsersController PUT :id/meta` — admin/superadmin/gerente 권한
- 라우트 순서: `:id/meta`를 `:id` 앞에 배치해 충돌 방지

### CockpitLayout 통합
`compareMode?: boolean` + `onCompareToggle?: () => void` props 추가.
prop이 있을 때만 Primary Area 우상단에 토글 버튼 렌더 (하위 호환).

## DB Migration

```sql
-- up: 트랜잭션 안에서 실행
ALTER TABLE users ADD COLUMN monthly_sales_target NUMERIC(15,2) NULL;

-- down: 롤백
ALTER TABLE users DROP COLUMN monthly_sales_target;
```

파일: `api-ventago/migrations/20260415-add-vendor-meta.js`
- Sequelize Migration 형식 (sequelize-cli 호환)
- `up` / `down` 모두 트랜잭션으로 감싸 안전 롤백 보장

## Pool 절약 확인

- 배지 계산: 백엔드 호출 0 (기존 데이터에서 파생)
- Meta 조회: 이번 구현에서는 PUT 저장만 구현 (조회는 12-08 백엔드 통합 API에서 JOIN으로 추가 예정)
- Meta 저장: 단일 `UPDATE users SET monthly_sales_target = $1 WHERE id = $2`

## Deviations from Plan

### Auto-adjusted: ComparePanel Mix 탭 단순화
- **Found during:** Task 3
- **Issue:** 계획에는 "카테고리 stacked bar"로 명시했으나 CompareItem 타입에 카테고리별 분해 데이터가 없음
- **Fix:** 총매출 막대 비교로 구현. 카테고리 stacked는 12-08 통합 API에서 mix 데이터를 추가한 후 확장 가능
- **Impact:** 기능 목적(비교 시각화) 달성, 세부 구현만 단순화

### Auto-adjusted: Meta JOIN 통합 미구현
- **Issue:** 계획에서 "메타 조회를 보고서 통합 쿼리에 JOIN으로 합침"을 요구했으나 해당 통합 쿼리(12-08 예정)가 아직 없음
- **Fix:** PUT 저장 API만 구현. JOIN 통합은 12-08 백엔드 통합 API 계획에서 처리
- **Impact:** 현재는 Meta 값이 UI에서 로컬 상태로만 반영됨

## Known Stubs

| Stub | File | Reason |
|------|------|--------|
| `mix` 데이터 미사용 | ComparePanel.tsx Mix 탭 | CompareItem.mix 필드는 정의되었으나 Mix 탭은 totalAmount 막대만 렌더. 12-08에서 카테고리 분해 데이터 추가 후 확장 예정 |
| Meta 초기값 로드 미구현 | MetaInputDialog.tsx | `currentMeta` prop은 상위에서 전달받아야 함. 12-08 통합 API JOIN 후 cockpit 응답에 포함 예정 |

## Self-Check: PASSED

Files exist:
- ventago-app/src/views/reports-v2/components/BadgeRules.ts — FOUND
- ventago-app/src/views/reports-v2/components/CompareToggle.tsx — FOUND
- ventago-app/src/views/reports-v2/components/ComparePanel.tsx — FOUND
- ventago-app/src/views/reports-v2/components/MetaInputDialog.tsx — FOUND
- api-ventago/migrations/20260415-add-vendor-meta.js — FOUND
- api-ventago/src/app/users/dto/update-meta.dto.ts — FOUND

Commits exist (ventago-app):
- 0ab920e — BadgeRules.ts
- a0b06d8 — CompareToggle
- ebf4167 — ComparePanel
- 75dacc0 — MetaInputDialog
- 7cd2b5c — CockpitLayout integration

Commits exist (api-ventago):
- 4194e59 — backend meta API + migration

ESLint: PASSED (no warnings or errors on all 5 modified frontend files)
