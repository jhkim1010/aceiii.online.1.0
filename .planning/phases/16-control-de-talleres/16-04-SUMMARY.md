---
phase: 16-control-de-talleres
plan: "04"
subsystem: frontend-talleres
tags: [talleres, liquidaciones, etapas, tabs, wave3]
dependency_graph:
  requires: ["16-01", "16-03"]
  provides: ["LiquidacionesTab", "EtapasTab", "7-tab-complete"]
  affects: ["ventago-app/src/views/talleres"]
tech_stack:
  added: []
  patterns: ["settlement-kpi-grid", "vendor-etapa-matrix", "tab-wiring"]
key_files:
  created:
    - ventago-app/src/views/talleres/tabs/LiquidacionesTab.tsx
    - ventago-app/src/views/talleres/tabs/EtapasTab.tsx
  modified:
    - ventago-app/src/views/talleres/TalleresMainView.tsx
decisions:
  - "settlement 상태를 OPEN/CLOSED로 처리 (모델에 PAID 없음 — CLOSED가 지급 완료 상태)"
  - "vendorEtapas는 별도 /all 엔드포인트 없어 etapas 응답의 nested vendorEtapas 배열 사용"
  - "KPI '이번달 지급' 기준을 settlementDate로 설정 (paidAt 필드 없음)"
metrics:
  duration: "~20min"
  completed_date: "2026-04-13"
  tasks_completed: 2
  files_changed: 3
---

# Phase 16 Plan 04: LiquidacionesTab + EtapasTab — Wave 3 완성 Summary

**One-liner:** Settlement KPI 3열 그리드 + 정산 테이블(업체 아바타), 공정 목록 + vendors×etapas 단가 매트릭스로 7탭 전체 완성

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | LiquidacionesTab — 정산 KPI 3개 + 테이블 | a12a2da | LiquidacionesTab.tsx (created) |
| 2 | EtapasTab + TalleresMainView 최종 연결 | 96a77b1 | EtapasTab.tsx (created), TalleresMainView.tsx (modified) |

## What Was Built

### LiquidacionesTab
- KPI 3열 그리드: 총 미결(`OPEN` status 합계), 이번달 지급(`CLOSED` + settlementDate 기준), 평균 단가
- KpiCard 컴포넌트 사용 (orange/green/teal)
- 정산 테이블: 업체 아바타(28px, vendorId % 4 색 순환, 이니셜 2글자) + Periodo(DD/MM) + 금액 + 차감액(빨간색) + Neto(bold) + Estado Chip + Acciones
- `apiConnector.get('/talleres/settlements/all')` 연결

### EtapasTab
- 2열 그리드 (`gridTemplateColumns: '1fr 1fr'`)
- 좌: 공정 목록 테이블 — #순서, 이름(이모지 매핑), 할당 업체 목록, En Proceso, isActive 상태, 편집 버튼
- 우: vendors×etapas 단가 매트릭스 — `getUnitPrice(vendorEtapas, vendorId, etapaId)` 함수, 값 있으면 `$${price}` (보라색 bold), 없으면 `—`
- `apiConnector.get('/talleres/etapas/all')` + `'/talleres/vendors/all'` 병렬 로드

### TalleresMainView 최종 연결
- LiquidacionesTab, EtapasTab import 추가
- placeholder "Próximamente" 텍스트 완전 제거
- 7개 탭 전체 실제 컴포넌트 연결 완료
- 미사용 Typography import 제거 (ESLint no-unused-vars)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] settlement 상태값 조정 — PAID 없음**
- **Found during:** Task 1
- **Issue:** 계획에서 `status === 'PAID'`로 필터링하도록 명시했으나 모델은 `ENUM('OPEN', 'CLOSED')`만 존재
- **Fix:** `CLOSED` 상태를 지급 완료로 처리, `settlementDate` 기준으로 이번달 필터링
- **Files modified:** LiquidacionesTab.tsx
- **Commit:** a12a2da

**2. [Rule 1 - Bug] vendor-etapas 별도 /all 엔드포인트 없음**
- **Found during:** Task 2
- **Issue:** 계획에서 `'/talleres/vendor-etapas/all'` 3번째 API 호출 명시했으나 컨트롤러에 `/all` 엔드포인트 없음 (vendorId 또는 etapaId 기준만 존재)
- **Fix:** etapas API 응답의 nested `vendorEtapas` 배열에서 추출 (Etapa 모델에 `@HasMany(() => VendorEtapa)` 있음)
- **Files modified:** EtapasTab.tsx
- **Commit:** 96a77b1

## Known Stubs

- **EtapasTab "En Proceso" 컬럼:** 항상 `0` 표시 — envios 데이터와 etapaId 매칭이 필요하나 현재 envios를 별도 로드하지 않음. 향후 개선 가능
- **LiquidacionesTab "Uds. Entregadas" 컬럼:** `—` 표시 — settlement 모델에 deliveredQuantity 필드 없음, subconOrder 통해 집계 필요

## Threat Flags

None — 프론트엔드 전용, 기존 API 재사용, 인증은 백엔드에서 처리됨

## Self-Check: PASSED

- LiquidacionesTab.tsx: FOUND
- EtapasTab.tsx: FOUND
- commit a12a2da: FOUND
- commit 96a77b1: FOUND
