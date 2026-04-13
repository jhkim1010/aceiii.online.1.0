# Phase 15: Materia Prima Control — Context

**Gathered:** 2026-04-12
**Status:** Ready for planning
**Mode:** Refactoring — existing code → mockup-quality UI + UX improvements

<domain>
## Phase Boundary

기존 기본 MUI 구현(5개 화면)을 목업 디자인 수준으로 리팩토링. 카테고리 컬러 코딩, Dashboard 2칸 그리드, CSS 바 차트, 컴포넌트 분리, 입출고/결제 워크플로우 UX 개선. 기능 추가가 아닌 기존 코드의 디자인+UX 품질 향상.

</domain>

<decisions>
## Implementation Decisions

### Inventario 카드 디자인
- **D-01:** 카드 상단 4px 컬러바로 카테고리 식별 (Tela=#3B82F6, Boton=#8B5CF6, Cierre=#EC4899, Hilo=#F97316, Accesorio=#14B8A6)
- **D-02:** 원단(Tela) 추가 속성(색상/원산지/품질)은 코드 아래 한 줄 미니 텍스트로 표시 — "COD-T001 · Tela · Color: Blanco · Origen: Nacional"
- **D-03:** 재고 상태는 Progress bar(초록/주황/빨강) + 배지(Normal/Bajo/Agotado) + 수치 텍스트 조합
- **D-04:** 카테고리 필터는 색상 코딩된 Chip 형태 (Todos + 5개 카테고리), 선택 시 filled 스타일

### Dashboard 레이아웃
- **D-05:** 2칸 그리드 레이아웃 — KPI 4카드 → [알림 | 카테고리 분포] → [채무 요약 | 최근 이동]
- **D-06:** 카테고리 분포는 CSS 전용 바 차트 (라이브러리 의존성 없음)
- **D-07:** 공급자별 채무 요약은 가로 바 차트 + 금액 표시
- **D-08:** KPI 카드에 상단 3px 색상 인디케이터 추가 (blue/orange/green/red)

### 입출고 워크플로우
- **D-09:** 입고(Entrada) 모달: 재료 선택 + 공급자 선택 + 수량 + 단가 + 대금상태(Pendiente/Pagado/Parcial) 통합 처리
- **D-10:** 출고(Salida) 모달: WorkOrder 선택 드롭다운 OR 수동 참조번호 입력 — 두 방식 모두 지원
- **D-11:** 결제 등록 시 해당 공급자 채무에서 자동 차감, Dashboard KPI 실시간 반영

### 컴포넌트 분리
- **D-12:** components/ 디렉토리에 재사용 가능한 컴포넌트 분리 — Claude 재량으로 결정하되 최소 KpiCard, MaterialCard, StockBar, CategoryChips는 분리

### Claude's Discretion
- 컴포넌트 분리 세부 구조 (추가 컴포넌트 판단)
- 테이블 vs 카드 전환 로직 (반응형 처리)
- 알림 섹션 세부 UX (정렬, 한도 등)
- Dialog 폼 필드 validation 패턴

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### 기존 구현 (프론트엔드)
- `ventago-app/src/views/materia-prima/MateriaPrimaDashboardView.tsx` — 현재 Dashboard 구현 (리팩토링 대상)
- `ventago-app/src/views/materia-prima/InventarioView.tsx` — 현재 Inventario 구현 (리팩토링 대상)
- `ventago-app/src/views/materia-prima/ProveedoresView.tsx` — 현재 Proveedores 구현 (리팩토링 대상)
- `ventago-app/src/views/materia-prima/MovimientosView.tsx` — 현재 Movimientos 구현 (리팩토링 대상)
- `ventago-app/src/views/materia-prima/PagosView.tsx` — 현재 Pagos 구현 (리팩토링 대상)
- `ventago-app/src/views/materia-prima/components/` — 빈 디렉토리 (컴포넌트 분리 대상)
- `ventago-app/src/pages/materia-prima/` — 5개 페이지 라우트 (dashboard, inventario, movimientos, pagos, proveedores)

### 디자인 목업
- `.planning/phases/15-materia-prima/materia-prima-mockup.html` — HTML 목업 (5개 화면 전체 디자인 참조)
- `.planning/phases/15-materia-prima/15-UI-SPEC.md` — UI 스펙 (DB 스키마, UI 구조, Plan 설명)

### 기존 구현 (백엔드)
- `api-ventago/src/app/production/materials/materials.model.ts` — Material 모델
- `api-ventago/src/app/production/material-categories/material-category.model.ts` — Category 모델
- `api-ventago/src/app/production/material-movements/material-movement.model.ts` — Movement 모델
- `api-ventago/src/app/production/material-movements/material-movement.service.ts` — Movement 서비스
- `api-ventago/src/app/production/material-supplier-payments/material-supplier-payment.model.ts` — Payment 모델
- `api-ventago/src/app/production/material-supplier-payments/material-supplier-payment.service.ts` — Payment 서비스

### Phase 14 권한 시스템
- `api-ventago/src/app/auth/auth.service.ts` — /me 엔드포인트, permissions 맵
- `ventago-app/src/configs/acl.ts` — CASL ability 빌딩
- `ventago-app/src/navigation/vertical/index.ts` — 사이드바 메뉴 (권한 기반 숨김)

### 프로젝트 컨벤션
- `.planning/codebase/CONVENTIONS.md` — 코딩 컨벤션 (ESLint, 네이밍, 포매팅 규칙)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- MUI Card/Grid/Table/Chip/Dialog — 현재 모든 화면에서 사용 중
- `apiConnector` — GET/POST 호출 패턴 확립됨
- `useAuth()` 훅 — storeId 접근
- `@iconify/react` Icon 컴포넌트 — tabler 아이콘 세트
- LinearProgress, Rating — MUI 컴포넌트 이미 사용 중

### Established Patterns
- View 파일 내 인터페이스 정의 → API fetch → state 관리 패턴
- useCallback + useEffect 데이터 로딩 패턴
- Dialog 기반 CRUD 모달 패턴

### Integration Points
- 5개 페이지 라우트 이미 존재 (pages/materia-prima/)
- 백엔드 API 엔드포인트 이미 동작 중
- 사이드바 네비게이션에 이미 등록됨

</code_context>

<specifics>
## Specific Ideas

- 목업 HTML 파일의 디자인을 최대한 따를 것 (색상, 레이아웃, 간격)
- 카테고리 컬러 맵은 상수로 분리 (CATEGORY_COLORS)
- components/ 디렉토리 활용하여 View 파일 경량화
- 기존 API 엔드포인트는 유지 — 프론트엔드만 리팩토링

</specifics>

<deferred>
## Deferred Ideas

- BOM 연동 원가 계산 (별도 phase 또는 Phase 7 Fabrica에서)
- 바코드 스캔 입고 (Phase 13 Zebra Agent 이후)
- 입출고 이력 Excel 내보내기

</deferred>

---

*Phase: 15-materia-prima*
*Context gathered: 2026-04-12*
