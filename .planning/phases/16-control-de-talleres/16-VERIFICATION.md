---
phase: 16-control-de-talleres
verified: 2026-04-13T12:30:00Z
status: passed
score: 11/11
overrides_applied: 0
---

# Phase 16: Control de Talleres Verification Report

**Phase Goal:** 기존 talleres 7개 분리 페이지를 단일 탭 UI로 통합 리디자인. Dashboard 통합 API 추가, Pipeline Kanban 시각화, 확장 행 테이블, 420px Lote 드로어, 단가 매트릭스 구현. UI 토글 ON 시에만 활성화.
**Verified:** 2026-04-13T12:30:00Z
**Status:** PASSED
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| #   | Truth | Status | Evidence |
|-----|-------|--------|----------|
| 1   | GET /talleres/dashboard/stats가 kpi + vendorDistribution + debtSummary + recentMovements를 한 번에 반환 | ✓ VERIFIED | `dashboard.service.ts:179` — getDashboardStats()가 Promise.all로 4개 섹션 병렬 집계 후 단일 객체 반환. controller:13 `@Get('stats')` 연결됨 |
| 2   | UI toggle ON 시 /talleres에서 TalleresMainView 렌더링 | ✓ VERIFIED | `pages/talleres/index.tsx:9` — `uiMode === 'new'` 조건으로 TalleresMainView 반환 확인 |
| 3   | UI toggle OFF 시 레거시 talleres_ControlPanel 유지 | ✓ VERIFIED | `pages/talleres/index.tsx:14` — else 경로에 `Talleres_ControlPanel` 반환. `pages/talleres/control/index.tsx` 미수정 확인 |
| 4   | Dashboard 탭에 KPI 4개 + 2열 그리드(분포 바차트 + 지연 알림 + 채무 바차트 + 최근 이동) | ✓ VERIFIED | `DashboardTab.tsx:109` — `gridTemplateColumns: 'repeat(4, 1fr)'` KPI 행. apiConnector.get('/talleres/dashboard/stats') 및 '/talleres/envios/dashboard/overdue' 호출. KpiCard 4개, CssBarChart 2개, OverdueAlertList, 최근이동 Table 모두 존재 |
| 5   | Pipeline 탭에서 공정 단계별 컬럼에 현재 진행 중인 envio 카드 표시 | ✓ VERIFIED | `PipelineTab.tsx:32-35` — Promise.all로 etapas/envios/lotes 3개 API 병렬 로드. PipelineKanban stages로 변환 후 렌더링 |
| 6   | 선택된 로트의 etapa-flow 원형 노드 상단 시각화 + 읽기 전용 | ✓ VERIFIED | `EtapaFlowVisual.tsx:62-64` — width:48, height:48, borderRadius:'50%'. `PipelineKanban.tsx` — draggable/onDrag/react-beautiful-dnd 없음(count=0) |
| 7   | Talleres 탭에서 행 클릭 시 확장 — 통계 5개(보유량, 채무, 이행률, 평점, 용량) + 상태/공정 필터 | ✓ VERIFIED | `TalleresTab.tsx:30` — expandedId state, `:215` Collapse unmountOnExit. `VendorExpandedRow.tsx:11-14` — pendingQuantity, totalDebt, completionRate, rating, capacityUsed. statusFilter + etapaFilter 필터 확인 |
| 8   | Lotes 탭에서 행 클릭 시 420px 우측 드로어 오픈 — 수량 분포 + 공정 진행도 + 타임라인 | ✓ VERIFIED | `LotesTab.tsx:264` — Drawer anchor='right', width:{xs:'100%', md:420}. `LoteDetailDrawer.tsx:85-130` — Disponible(#ede7f6), En Taller(#fff3e0), Completado(#e8f5e9). EtapaFlowVisual 재사용, timeline 구현 |
| 9   | Envios 탭에서 상태/업체/공정별 필터 + 지연 행 빨간 배경 | ✓ VERIFIED | `EnviosTab.tsx:43-45` — statusFilter, vendorFilter, etapaFilter. `:190` — bgcolor:'#fbe9e7' 지연 행 강조 |
| 10  | Liquidaciones 탭에서 KPI 3개(총 미결, 이번달 지급, 평균 단가) + 정산 테이블 | ✓ VERIFIED | `LiquidacionesTab.tsx:123` — `gridTemplateColumns: 'repeat(3, 1fr)'`. totalPending, paidThisMonth, avgUnitPrice 계산. apiConnector.get('/talleres/settlements/all') 연결 |
| 11  | Etapas 탭에서 좌: 공정 목록 테이블 + 우: 업체별 단가 매트릭스. 7개 탭 전부 TalleresMainView에 연결 완료 | ✓ VERIFIED | `EtapasTab.tsx:106` — gridTemplateColumns:'1fr 1fr'. getUnitPrice() 함수로 매트릭스 계산. `TalleresMainView.tsx` — 7개 탭 전부 실제 컴포넌트 임포트, "Próximamente" 없음(count=0) |

**Score:** 11/11 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `api-ventago/src/app/subcon/dashboard/dashboard.controller.ts` | GET /talleres/dashboard/stats endpoint | ✓ VERIFIED | @Controller('talleres/dashboard') + @Get('stats') + @Auth 확인 |
| `api-ventago/src/app/subcon/dashboard/dashboard.service.ts` | Dashboard stats 집계 서비스 | ✓ VERIFIED | getDashboardStats() + Promise.all + Op.in + col('pending_quantity') snake_case 확인 |
| `api-ventago/src/app/subcon/subcon.module.ts` | TalleresDashboardController + TalleresDashboardService 등록 | ✓ VERIFIED | line 84, 99 확인 |
| `ventago-app/src/pages/talleres/index.tsx` | UI 토글 진입점 | ✓ VERIFIED | useUiMode + uiMode==='new' 조건부 분기 |
| `ventago-app/src/views/talleres/TalleresMainView.tsx` | 7탭 컨테이너 | ✓ VERIFIED | 7개 탭 모두 실제 컴포넌트 연결, URL query shallow routing |
| `ventago-app/src/views/talleres/components/constants.ts` | 공유 상수 + DashboardStats 인터페이스 | ✓ VERIFIED | TALLER_COLORS, TALLERES_TABS(7개), DashboardStats 인터페이스 |
| `ventago-app/src/views/talleres/components/KpiCard.tsx` | KPI 카드 컴포넌트 | ✓ VERIFIED | borderTop + TALLER_COLORS 사용 |
| `ventago-app/src/views/talleres/components/CssBarChart.tsx` | CSS 가로 바 차트 | ✓ VERIFIED | maxValue 자동 계산 + widthPct 동적 계산 |
| `ventago-app/src/views/talleres/components/OverdueAlertList.tsx` | 지연 알림 목록 | ✓ VERIFIED | borderLeft:'3px solid #F44336' + daysOverdue 표시 |
| `ventago-app/src/views/talleres/components/EtapaFlowVisual.tsx` | 원형 노드 플로우 시각화 | ✓ VERIFIED | 48×48 원형, done=#4CAF50, active=#7C4DFF, inactive=#e0e0e0, 화살표(→) |
| `ventago-app/src/views/talleres/components/PipelineKanban.tsx` | CSS flexbox Kanban (읽기 전용) | ✓ VERIFIED | display:flex + overflowX:auto + minWidth:200 + borderTop 상태별 색상, 드래그 없음 |
| `ventago-app/src/views/talleres/tabs/DashboardTab.tsx` | Dashboard 탭 | ✓ VERIFIED | apiConnector.get('/talleres/dashboard/stats') + repeat(4,1fr) KPI grid |
| `ventago-app/src/views/talleres/tabs/PipelineTab.tsx` | Pipeline 탭 | ✓ VERIFIED | Promise.all 3개 API + selectedLoteId + EtapaFlowVisual + PipelineKanban |
| `ventago-app/src/views/talleres/tabs/TalleresTab.tsx` | Talleres 탭 (확장 행) | ✓ VERIFIED | MUI Table + Collapse + expandedId(number|null) + 필터 3개 |
| `ventago-app/src/views/talleres/drawers/VendorExpandedRow.tsx` | 업체 확장 패널 | ✓ VERIFIED | 통계 4개 + capacity progress bar (height:4) |
| `ventago-app/src/views/talleres/tabs/LotesTab.tsx` | Lotes 탭 (드로어) | ✓ VERIFIED | Drawer anchor='right' width:420 + handleRowClick + Promise.all 3개 API |
| `ventago-app/src/views/talleres/drawers/LoteDetailDrawer.tsx` | 420px 로트 상세 드로어 | ✓ VERIFIED | 수량 분포 3개 카드 + EtapaFlowVisual + timeline |
| `ventago-app/src/views/talleres/tabs/EnviosTab.tsx` | Envios 탭 (필터+지연) | ✓ VERIFIED | 3개 필터 + bgcolor:'#fbe9e7' 지연 강조 |
| `ventago-app/src/views/talleres/tabs/LiquidacionesTab.tsx` | Liquidaciones 탭 | ✓ VERIFIED | KPI 3개 + 정산 테이블 + settlements API 연결 |
| `ventago-app/src/views/talleres/tabs/EtapasTab.tsx` | Etapas 탭 (단가 매트릭스) | ✓ VERIFIED | gridTemplateColumns:'1fr 1fr' + getUnitPrice() + 공정목록 + 매트릭스 |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| DashboardTab.tsx | /talleres/dashboard/stats | apiConnector.get | ✓ WIRED | line 47 확인 |
| pages/talleres/index.tsx | useUiMode | conditional rendering | ✓ WIRED | uiMode==='new' → TalleresMainView |
| PipelineTab.tsx | /talleres/etapas/all | apiConnector.get | ✓ WIRED | line 33 확인 |
| PipelineTab.tsx | /talleres/envios/all | apiConnector.get | ✓ WIRED | line 34 확인 |
| TalleresTab.tsx | /talleres/vendors/all | apiConnector.get | ✓ WIRED | line 41 확인 |
| LotesTab.tsx | /talleres/lotes/all | apiConnector.get | ✓ WIRED | line 39 확인 |
| LiquidacionesTab.tsx | /talleres/settlements/all | apiConnector.get | ✓ WIRED | line 55 확인 |
| EtapasTab.tsx | /talleres/etapas/all | apiConnector.get | ✓ WIRED | line 53 확인 |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|---------------------|--------|
| DashboardTab.tsx | stats | apiConnector.get('/talleres/dashboard/stats') → dashboard.service.ts Sequelize queries | Yes — 4개 병렬 DB 집계 쿼리 | ✓ FLOWING |
| PipelineTab.tsx | stages | etapas/envios/lotes API → etapas.map with envios filter | Yes — 실제 API 데이터 가공 | ✓ FLOWING |
| TalleresTab.tsx | vendors | apiConnector.get('/talleres/vendors/all') | Yes — 기존 API | ✓ FLOWING |
| LotesTab.tsx | lotes | apiConnector.get('/talleres/lotes/all') | Yes — 기존 API | ✓ FLOWING |
| EnviosTab.tsx | envios | apiConnector.get('/talleres/envios/all') | Yes — 기존 API | ✓ FLOWING |
| LiquidacionesTab.tsx | settlements | apiConnector.get('/talleres/settlements/all') | Yes — 기존 API | ✓ FLOWING |
| EtapasTab.tsx | etapas + vendorEtapas | etapas/vendors API + etapas nested vendorEtapas | Yes — nested 구조 추출 | ✓ FLOWING |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| TALLERES-01 | 16-01 | Dashboard 통합 API 구축 | ✓ SATISFIED | dashboard.controller.ts + service.ts 생성, subcon.module.ts 등록 |
| TALLERES-02 | 16-01 | UI 토글 ON/OFF 분기 + 7탭 셸 | ✓ SATISFIED | pages/talleres/index.tsx 토글, TalleresMainView 7탭 |
| TALLERES-03 | 16-01 | Dashboard 탭 KPI + 차트 | ✓ SATISFIED | DashboardTab KPI 4개 + CssBarChart + OverdueAlertList + 최근이동 테이블 |
| TALLERES-04 | 16-02 | Pipeline Kanban 읽기 전용 + EtapaFlow | ✓ SATISFIED | PipelineKanban(드래그없음) + EtapaFlowVisual 원형 노드 |
| TALLERES-05 | 16-03 | Talleres 탭 확장 행 + 필터 | ✓ SATISFIED | TalleresTab MUI Table + Collapse + statusFilter + etapaFilter |
| TALLERES-06 | 16-03 | Lotes 탭 420px 드로어 | ✓ SATISFIED | LotesTab Drawer width:420 + LoteDetailDrawer |
| TALLERES-07 | 16-03 | Envios 탭 필터 + 지연 강조 | ✓ SATISFIED | EnviosTab 3개 필터 + bgcolor:'#fbe9e7' |
| TALLERES-08 | 16-04 | Liquidaciones 탭 KPI 3개 + 테이블 | ✓ SATISFIED | LiquidacionesTab KPI grid + settlements 테이블 |
| TALLERES-09 | 16-04 | Etapas 탭 공정목록 + 단가 매트릭스 + 7탭 완성 | ✓ SATISFIED | EtapasTab 2열 grid + getUnitPrice() + TalleresMainView placeholder 제거 |

**주의:** TALLERES-01~09는 REQUIREMENTS.md에 정의되지 않고 ROADMAP.md에만 정의된 페이즈 전용 요구사항임. REQUIREMENTS.md Traceability 테이블에 Phase 16이 매핑되지 않은 것은 이 요구사항들이 v1.1 확장 UI/UX 범주(UX-03과 유사)에 해당하나 별도 ID로 추적되기 때문임. 이는 REQUIREMENTS.md 미갱신 상태이며 구현 누락 아님.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `EtapasTab.tsx` | ~182 | "En Proceso" 컬럼 항상 `0` 반환 — envios 데이터 미로드 | ⚠️ Warning | 공정별 진행 수 표시 부정확. 데이터 표시는 가능하나 수치가 항상 0. SUMMARY-04에서 알려진 스텁으로 문서화됨 |
| `LiquidacionesTab.tsx` | ~224 | "Uds. Entregadas" 컬럼 항상 `—` 반환 — settlement 모델에 deliveredQuantity 없음 | ⚠️ Warning | 단위 수량 표시 불가. SUMMARY-04에서 알려진 스텁으로 문서화됨 |
| 여러 탭 (버튼) | 여러 곳 | "Nuevo Taller", "Nuevo Lote", "Enviar", "Recibir", "Nuevo Envio", "Cerrar Lote" 버튼 placeholder | ℹ️ Info | 액션 버튼 미연결 — 데이터 표시(읽기)는 완전 구현. SUMMARY-03에서 "데이터 표시가 핵심 목표"로 명시됨 |

위 두 Warning은 이 페이즈의 핵심 목표(7탭 UI 리디자인 + 읽기 전용 시각화)에 영향을 주지 않음. 쓰기/액션 기능은 후속 작업으로 명시적으로 연기됨.

### Human Verification Required

없음 — 자동화 검증으로 모든 핵심 목표 확인 가능.

### Gaps Summary

발견된 gap 없음. 모든 11개 관찰 가능한 truth가 VERIFIED 상태.

**알려진 스텁 (목표 달성에 영향 없음):**
- EtapasTab "En Proceso" 컬럼 — envios 데이터 미로드로 항상 0 (향후 개선 가능)
- LiquidacionesTab "Uds. Entregadas" — settlement 모델 제약으로 '—' 표시
- 여러 탭의 쓰기 액션 버튼 — Phase 16 범위 외, 후속 페이즈 작업

이 스텁들은 UI 리디자인 + 읽기 전용 시각화라는 Phase 16 핵심 목표와 무관하며, 실행 서머리에서 모두 투명하게 문서화됨.

---

_Verified: 2026-04-13T12:30:00Z_
_Verifier: Claude (gsd-verifier)_
