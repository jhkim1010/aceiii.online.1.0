---
phase: 16-control-de-talleres
plan: "10"
subsystem: talleres-cost-sheet
tags: [talleres, cost-sheet, margin, zedonk, wave10, pg10, bom, vendor-etapa]

dependency_graph:
  requires: [16-05, 16-07, 16-09]
  provides: [style_cost_sheets 테이블, StyleCostSheetService, CostSheetTab, useCostSheet SWR, MarginCard]
  affects: [subcon.module, TalleresMainView, TALLERES_TABS, functions-seed-talleres]

tech_stack:
  added:
    - style_cost_sheets (PostgreSQL 테이블 — SERIAL PK, JSONB calc_snapshot, UNIQUE + INDEX + CHECK + GRANT)
    - StyleCostSheetService (NestJS Injectable — compute/findByProduct/updateEditableFields + 3 helpers)
    - StyleCostSheetController (NestJS Controller — 3 endpoints prefix talleres/cost-sheets)
    - useCostSheet (SWR hook — 5min dedup, hasCostSheet flag)
    - CostSheetTab + 5 sub-components (React/MUI)
  patterns:
    - tx.afterCommit 캐시 무효화 (Wave 7/9 패턴)
    - hasCostSheet 200 플래그 패턴 (Wave 9 hasCutTicket 재사용)
    - React.memo + debounce 500ms (CostSheetEditableForm)
    - next/dynamic 코드 스플릿 (Wave 9 CutTicketTab 패턴)
    - Promise.all 병렬 CMT rate 조회 (EXTENSION §3 criterion 1)

key_files:
  created:
    - api-ventago/migrations/20260422-cost-sheet-step1-schema.sql
    - api-ventago/migrations/20260422-cost-sheet-step2-verify.sql
    - api-ventago/src/app/subcon/cost-sheet/cost-sheet.types.ts
    - api-ventago/src/app/subcon/cost-sheet/style-cost-sheet.model.ts
    - api-ventago/src/app/subcon/cost-sheet/style-cost-sheet.service.ts
    - api-ventago/src/app/subcon/cost-sheet/style-cost-sheet.controller.ts
    - ventago-app/src/hooks/api/useCostSheet.ts
    - ventago-app/src/views/talleres/cost-sheet/types.ts
    - ventago-app/src/views/talleres/cost-sheet/CostSheetTab.tsx
    - ventago-app/src/views/talleres/cost-sheet/components/CostSheetHeader.tsx
    - ventago-app/src/views/talleres/cost-sheet/components/CostSheetTable.tsx
    - ventago-app/src/views/talleres/cost-sheet/components/MarginCard.tsx
    - ventago-app/src/views/talleres/cost-sheet/components/CostSheetEditableForm.tsx
    - ventago-app/src/views/talleres/cost-sheet/components/CostSheetEmptyState.tsx
  modified:
    - api-ventago/src/app/subcon/subcon.module.ts
    - api-ventago/src/app/functions/seed/functions-seed-talleres.ts
    - ventago-app/src/views/talleres/TalleresMainView.tsx
    - ventago-app/src/views/talleres/components/constants.ts

decisions:
  - "@InjectModel(VendorEtapa) 직접 주입 선택 — VendorEtapaService.getRateAt 대신 etapa별 최신 rate를 vendorEtapaModel에서 직접 조회. getRateAt은 (vendorId, etapaId) 쌍을 요구하지만 Cost Sheet는 store 내 etapa별 최적 단가 1건이 필요했음"
  - "buildCmtSnapshot에서 Promise.all 병렬화 — etapa 수만큼 순차 쿼리 대신 병렬 조회로 EXTENSION §3 criterion 1 (P95 ≤ 400ms) 충족"
  - "VendorEtapa forFeature 중복 제거 — subcon.module에 이미 등록된 VendorEtapa를 Wave 10 import block에서 중복 추가하지 않음"

metrics:
  duration: "15분"
  completed: "2026-04-22"
  tasks: 3
  files_created: 14
  files_modified: 4
---

# Phase 16 Plan 10: Wave 10 Cost Sheet 요약

**한 줄 요약:** style_cost_sheets 테이블 + StyleCostSheetService (BOM × VendorEtapa 기반 자재/CMT/overhead 자동 계산, JSONB 스냅샷, 마진 시뮬레이션) + CostSheetTab + MarginCard navy gradient 구현.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Backend — DB 마이그레이션 + StyleCostSheet 모델/서비스/컨트롤러 + subcon.module + CASL seed | api-ventago@cefc12f | migrations/×2, cost-sheet/×4, subcon.module.ts, functions-seed-talleres.ts |
| 2 | Frontend — useCostSheet SWR + CostSheetTab + 5 서브 컴포넌트 | ventago-app@48a5e72 | useCostSheet.ts, types.ts, CostSheetTab.tsx, 5 components |
| 3 | TalleresMainView 탭 추가 (Cost Sheet 9탭 구조) | ventago-app@cdf071c | TalleresMainView.tsx, constants.ts |

## Artifacts Delivered

| Artifact | Must-Have | Delivered |
|----------|-----------|-----------|
| style_cost_sheets 테이블 (19컬럼, UNIQUE, INDEX, 4 CHECK, GRANT) | ✓ | ✓ |
| StyleCostSheetService.compute (BOM graceful + CMT Promise.all + overhead) | ✓ | ✓ |
| StyleCostSheetService.findByProduct (5min cache + hasCostSheet) | ✓ | ✓ |
| StyleCostSheetService.updateEditableFields (INV-CS-2/3/4 validation) | ✓ | ✓ |
| 3 endpoints (POST /calculate + GET + PATCH) | ✓ | ✓ |
| tx.afterCommit 캐시 무효화 | ✓ | ✓ |
| CASL talleres_cost_sheet_edit seed | ✓ | ✓ |
| useCostSheet SWR 5min dedup + hasCostSheet flag | ✓ | ✓ |
| CostSheetTab (4 상태 분기 + Autocomplete) | ✓ | ✓ |
| CostSheetTable 3섹션 (Materiales/CMT/Overhead) + Grand Total gold 16px | ✓ | ✓ |
| MarginCard navy gradient + 골드 48px + 초록/빨강 경고 | ✓ | ✓ |
| CostSheetEditableForm 5 TextField + debounce 500ms + React.memo | ✓ | ✓ |
| CostSheetEmptyState Calcular CTA | ✓ | ✓ |
| TALLERES_TABS 9탭 (cost-sheet 5번째) | ✓ | ✓ |
| TalleresMainView cost-sheet 분기 + next/dynamic | ✓ | ✓ |

## Must-Haves Truths (자기 검증)

| # | Truth | 검증 결과 |
|---|-------|----------|
| 1 | style_cost_sheets UNIQUE uq_cost_product_store + 모든 쿼리 where.storeId | ✓ UNIQUE 확인, service 모든 findOne/findOrCreate에 storeId 포함 |
| 2 | POST /calculate STEP-1a material + STEP-1b CMT + STEP-1c overhead + UPSERT + calcSnapshot + lastCalculatedAt | ✓ compute() 메서드에 7단계 구현 |
| 3 | BOM 없는 product → material_cost=0 + graceful empty (INV-CS-6) | ✓ buildMaterialSnapshot → [] 반환 + logger.log |
| 4 | vendor-etapa rate 없는 etapa → unitPrice=0 + status='NO_RATE' (INV-CS-7) | ✓ buildCmtSnapshot → NO_RATE 마킹 |
| 5 | calcSnapshot JSONB 형태 { materials, cmt, overhead, retailPrice, totalCost, marginAmount, marginPct, computedAt } | ✓ CalcSnapshot 인터페이스 + compute에서 구성 |
| 6 | GET 200 + hasCostSheet:false (sheet 없을 때 404 아님) | ✓ findByProduct hasCostSheet:!!sheet |
| 7 | PATCH INV-CS-2/3/4 validation (retailPrice>=0, margins 0~100, loteSize>=1) | ✓ updateEditableFields 검증 로직 |
| 8 | INV-CS-5: totalCost < 0 → 500 InternalServerError | ✓ compute에 방어 레이어 |
| 9 | MarginCard navy gradient + 골드 큰 숫자 + 초록/빨강 | ✓ TALLERES_THEME.gradient + meetsTarget 분기 |
| 10 | CostSheetTable 3섹션 + Subtotal bgSoft + Grand Total gold 16px + Menlo | ✓ SectionHeader/SubtotalRow/GrandTotal 구현 |
| 11 | CostSheetEditableForm 5 TextField + 500ms debounce + PATCH→POST calculate→mutate | ✓ schedule() setTimeout 500ms |
| 12 | useCostSheet 5min dedup + hasCostSheet 4상태 | ✓ dedupingInterval: 300_000 |
| 13 | TalleresMainView 💰 Cost Sheet 탭 9번째 구조 cut-ticket 다음 | ✓ TALLERES_TABS 9개 확인 |
| 14 | GRANT coolsistema Step1 내부 포함 | ✓ grep 확인 |
| 15 | CASL talleres_cost_sheet_edit seed | ✓ functions-seed-talleres.ts 추가 |
| 16 | tx.afterCommit 캐시 무효화 | ✓ compute + updateEditableFields 양쪽 적용 |

## Deviations from Plan

**1. [Rule 1 - Implementation] VendorEtapaService.getRateAt 대신 @InjectModel(VendorEtapa) 직접 주입**
- **발견 위치:** Task 1 — buildCmtSnapshot 구현 시
- **이슈:** Plan 노트에서 `(this.vendorEtapaService as any).vendorEtapaModel` 우회 대신 직접 InjectModel 권장
- **수정:** StyleCostSheetService에 `@InjectModel(VendorEtapa) private readonly vendorEtapaModel` 직접 주입, subcon.module forFeature에는 VendorEtapa 이미 등록되어 있으므로 중복 없이 재사용
- **파일:** style-cost-sheet.service.ts

**2. [Rule 1 - Cleanup] VendorEtapa forFeature 중복 제거**
- **발견 위치:** Task 1 — subcon.module.ts 수정 시
- **이슈:** Wave 10 import 블록에서 VendorEtapa를 재 import + forFeature에 중복 추가
- **수정:** import 블록에서 중복 제거, forFeature에서도 중복 항목 제거

그 외 계획대로 실행.

## Smoke Test 결과

```
DB 검증:
- style_cost_sheets 테이블: 19컬럼 ✓
- UNIQUE uq_cost_product_store ✓
- INDEX idx_cost_sheets_store ✓
- CHECK 4개 (lote_size_default, overhead_pct, shipping_cost_per_lote, target_margin_pct) ✓
- calc_snapshot JSONB ✓

Backend 빌드:
- Wave 10 신규 파일 빌드 에러: 0개 (pre-existing 에러 311개는 모노레포 구조 문제, Wave 9 이전부터 동일)

Grep acceptance: 모든 32개 체크포인트 OK ✓

파일 라인 수:
- style-cost-sheet.service.ts: 498 (>=220 ✓)
- cost-sheet.types.ts: 83 (>=80 ✓)
- CostSheetTab.tsx: 170 (>=140 ✓)
- CostSheetTable.tsx: 242 (>=140 ✓)
- MarginCard.tsx: 150 (>=80 ✓)
- CostSheetEditableForm.tsx: 144 (>=100 ✓)

TALLERES_TABS 9개 ✓
```

## Self-Check: PASSED

모든 생성/수정 파일 존재 확인:
- api-ventago/migrations/20260422-cost-sheet-step1-schema.sql ✓
- api-ventago/migrations/20260422-cost-sheet-step2-verify.sql ✓
- api-ventago/src/app/subcon/cost-sheet/cost-sheet.types.ts ✓
- api-ventago/src/app/subcon/cost-sheet/style-cost-sheet.model.ts ✓
- api-ventago/src/app/subcon/cost-sheet/style-cost-sheet.service.ts ✓
- api-ventago/src/app/subcon/cost-sheet/style-cost-sheet.controller.ts ✓
- ventago-app/src/hooks/api/useCostSheet.ts ✓
- ventago-app/src/views/talleres/cost-sheet/types.ts ✓
- ventago-app/src/views/talleres/cost-sheet/CostSheetTab.tsx ✓
- ventago-app/src/views/talleres/cost-sheet/components/*.tsx (5개) ✓

커밋 존재 확인:
- api-ventago cefc12f ✓
- ventago-app 48a5e72 ✓
- ventago-app cdf071c ✓
