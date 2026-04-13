# Phase 16: Control de Talleres — Context

**Gathered:** 2026-04-13
**Status:** Ready for planning
**Mode:** UI 리팩토링 + Dashboard 통합 API 추가

<domain>
## Phase Boundary

기존 talleres 화면 7개(ControlPanel, Vendors, Lotes, Envíos, Pedidos, Etapas, Dashboard)를 목업 수준 UI/UX로 리디자인. 탭 네비게이션 통합, Pipeline Kanban 시각화 추가, Dashboard 통합 API 신규 구축. 기존 백엔드 CRUD API는 유지하되 Dashboard용 통합 엔드포인트 1개 추가.

</domain>

<decisions>
## Implementation Decisions

### 페이지 구조
- **D-01:** 단일 진입점 + 상단 탭 네비게이션으로 7개 화면 통합 (Dashboard, Pipeline, Talleres, Lotes, Envíos, Liquidaciones, Etapas)
- **D-02:** 기존 pages/talleres/ 라우트는 유지하되 메인 탭 페이지에서 shallow routing으로 전환
- **D-03:** UI 토글 ON 시에만 새 탭 UI 활성화, OFF 시 기존 페이지 유지

### Pipeline 시각화
- **D-04:** Pipeline(Kanban)은 읽기 전용 시각화 — 드래그&드롭 없음
- **D-05:** 공정 단계별 컬럼에 현재 진행 중인 로트/발송 카드 표시
- **D-06:** 개별 로트 선택 시 공정 진행도(원형 노드 플로우) 시각화

### Taller(Vendor) 목록
- **D-07:** 테이블 + 확장 행 패턴 — 행 클릭 시 확장되어 상세 통계(보유량, 채무, 이행률, 평점, 용량) 표시
- **D-08:** 필터: 상태(활성/비활성), 담당 공정별

### Lote 상세
- **D-09:** 우측 420px 드로어 — 수량 분포(가용/재고/완료) + 공정 진행도 + 타임라인
- **D-10:** 테이블에서 행 클릭 시 드로어 오픈

### 백엔드
- **D-11:** 새 `/talleres/dashboard/stats` 통합 API 추가 — KPI(총 보유량, 활성 업체, 오픈 로트, 지연건) + 업체별 분포 + 채무 요약 + 최근 이동을 한 번에 응답
- **D-12:** 기존 CRUD API 변경 없음

### 구현 우선순위
- **D-13:** Wave 1: Dashboard + Pipeline 우선 구현
- **D-14:** Wave 2: Talleres(테이블+확장행) + Lotes(드로어) + Envíos
- **D-15:** Wave 3: Liquidaciones + Etapas(단가 매트릭스)

### Claude's Discretion
- 컴포넌트 분리 세부 구조 (Phase 15 패턴 따라 components/ 활용)
- 탭 상태 관리 방식 (URL query vs local state)
- 테이블 확장 행 애니메이션/트랜지션
- Dashboard 통합 API 내부 쿼리 최적화 (CTE/JOIN 구조)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### 디자인 목업
- `.planning/phases/16-control-de-talleres/talleres-mockup.html` — HTML 목업 (7개 탭 전체 디자인 참조)

### 기존 구현 (프론트엔드)
- `ventago-app/src/views/talleres/control/talleres_ControlPanel.tsx` — 현재 Dashboard (리팩토링 대상)
- `ventago-app/src/views/talleres/vendors/talleres_VendorsListView.tsx` — Vendors 목록
- `ventago-app/src/views/talleres/vendors/components/talleres_VendorDetailPanel.tsx` — Vendor 상세
- `ventago-app/src/views/talleres/vendors/components/talleres_VendorFormDrawer.tsx` — Vendor 폼
- `ventago-app/src/views/talleres/lotes/talleres_LotesListView.tsx` — Lotes 목록
- `ventago-app/src/views/talleres/envios/talleres_EnviosListView.tsx` — Envíos 목록
- `ventago-app/src/views/talleres/pedidos/talleres_PedidosListView.tsx` — Pedidos 목록
- `ventago-app/src/views/talleres/etapas/talleres_EtapasListView.tsx` — Etapas 목록
- `ventago-app/src/pages/talleres/` — 7개 페이지 라우트

### 기존 구현 (백엔드)
- `api-ventago/src/app/subcon/subcon.module.ts` — Subcon 모듈 전체 (12 controllers/services)
- `api-ventago/src/app/subcon/envios/envio.model.ts` — Envio 모델 (상태: PENDING/PARTIAL/COMPLETED/CANCELLED)
- `api-ventago/src/app/subcon/envios/envio.controller.ts` — Envio API (dashboard/vendor-pending, dashboard/overdue 포함)
- `api-ventago/src/app/subcon/lotes/lote.model.ts` — Lote 모델 (상태: OPEN/IN_PROGRESS/COMPLETED/CLOSED)
- `api-ventago/src/app/subcon/vendors/vendor.model.ts` — Vendor 모델
- `api-ventago/src/app/subcon/etapas/etapa.model.ts` — Etapa 모델 (공정 단계)
- `api-ventago/src/app/subcon/vendor-etapas/vendor-etapa.model.ts` — Vendor-Etapa 단가 매핑
- `api-ventago/src/app/subcon/recepciones/recepcion.model.ts` — Recepcion 모델
- `api-ventago/src/app/subcon/subcon-orders/subcon-order.model.ts` — SubconOrder 모델
- `api-ventago/src/app/subcon/subcon-settlements/subcon-settlement.model.ts` — Settlement 모델
- `api-ventago/src/app/subcon/subcon-payments/subcon-payment.model.ts` — Payment 모델

### Phase 15 참조 (컴포넌트 패턴)
- `ventago-app/src/views/materia-prima/components/` — KpiCard, StockBar, MaterialCard 등 분리 패턴
- `.planning/phases/15-materia-prima/materia-prima-mockup.html` — Phase 15 목업 (스타일 일관성 참조)

### 권한 시스템
- `api-ventago/src/app/functions/seed/functions-seed-talleres.ts` — Talleres 권한 함수 시드
- `ventago-app/src/navigation/vertical/index.ts` — 사이드바 앱 순서 (talleres 등록됨)

### 프로젝트 컨벤션
- `.planning/codebase/CONVENTIONS.md` — 코딩 컨벤션

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- Phase 15 컴포넌트 패턴 (KpiCard, CSS 바 차트) — 동일 스타일로 재사용
- `FullTable` 래퍼 — 기존 테이블 뷰에서 사용 중
- `CardFilter` 컴포넌트 — 필터 UI
- `apiConnector` — GET/POST 호출 패턴
- `useAuth()` 훅 — storeId 접근
- MUI Drawer 컴포넌트 — Lote 상세에 활용

### Established Patterns
- View 파일 내 인터페이스 정의 → API fetch → state 관리 패턴
- 상태 Chip 컬러 매핑 (envioStatusConfig, statusConfig 등)
- Dialog 기반 CRUD 모달 패턴

### Integration Points
- 7개 페이지 라우트 이미 존재 (pages/talleres/)
- 사이드바 네비게이션에 talleres 앱 이미 등록됨
- 백엔드 envio.controller에 dashboard/vendor-pending, dashboard/overdue API 이미 존재

</code_context>

<specifics>
## Specific Ideas

- 목업 HTML 파일의 디자인을 최대한 따를 것 (색상, 레이아웃, 간격)
- Phase 15와 동일한 KPI 카드 스타일 (상단 3px 컬러바)
- CSS 전용 바 차트 (카테고리 분포, 채무 요약)
- Pipeline Kanban은 CSS flexbox 기반, 라이브러리 없이 구현
- 공정 진행도는 원형 노드 + 화살표 플로우 (목업의 etapa-flow 참조)
- 테이블 확장 행은 MUI Collapse 활용

</specifics>

<deferred>
## Deferred Ideas

- 드래그&드롭 Pipeline (Phase 17 Portal에서 검토)
- 업체별 성과 리포트/그래프 (Reportajes 확장으로)
- 자재 연동 입출고 (Phase 15 materia-prima와 cross-link)

</deferred>

---

*Phase: 16-control-de-talleres*
*Context gathered: 2026-04-13*
