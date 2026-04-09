# Phase 8: Reportajes UX Redesign (Sidebar + Preview) - Context

**Gathered:** 2026-04-06
**Status:** Ready for planning
**Source:** Conversation-derived (Pattern 2 목업 확정, 사용자 승인 2026-04-06)
**Parent dependency:** Phase 6 (Reportajes 백엔드/데이터 레이어)

<domain>
## Phase Boundary

Phase 6은 15개 보고서의 **백엔드 서비스 + 기존 단순 페이지** 구현에 집중.
Phase 8은 그 위에 얹는 **완전히 새로운 프론트엔드 UX 셸(shell)** — "좌측 사이드바 + 우측 파라미터/미리보기" 구조.

- 충돌 방지: Phase 6은 `pages/reportes/*` 의 기존 페이지를 유지/확장
- Phase 8은 신규 라우트 `pages/reportes-v2/` (또는 UI 토글 ON 시 전환)로 먼저 구축
- 토글 OFF → 기존 Phase 6 페이지, 토글 ON → Phase 8 셸 사용 (Phase 1 UI 토글 활용)

</domain>

<decisions>
## Locked Decisions

### UX 패턴 (Locked 2026-04-06)
- **Pattern 2 채택**: 좌측 다크 사이드바(300px) + 우측 컨텐츠 영역
- 좌측: 검색창 + 카테고리 그룹 + 보고서 목록
- 우측 상단: breadcrumb + 제목 + 설명 + 액션 버튼(⭐ PDF Excel ▶Ejecutar)
- 우측 본문: Parámetros 패널 → Vista previa 패널 (KPI + 차트 + 테이블)
- 목업 파일: `reportes-mockup-pattern2-v2.html`

### 카테고리 재분류 (Locked 2026-04-06)

**🛒 Ventas (7)**
- Ventas — 일자별/기간별 매출
- Items (Venta) — 상품별 판매
- Vendedor — 판매원 실적
- Creditos — 외상 판매 상황
- Breve Venta — 간이 매출 요약
- Reservado — 인터넷 예약 주문 진행상황 (대금·운송업자 인수 확인)
- Alertas — Caja 의심행동 자동 감지 (anulación 반복, 비정상 할인, 영업외 개폐 등)

**💰 Finanzas (3)**
- Facturación — 세금계산서
- Gasto — 비용
- Cheque Estado — 수표 상태

**📦 Inventario (5)**
- Stock Rpt Gen — 재고 현황
- Corregido (C) — 정정 내역 (감사 로그)
- Movidos — 지점 간 재고 이동
- Fallados — 불량/손실
- Ingreso (Depósito) — 입고 내역 (날짜·수량·단가·공급처)

**👥 Clientes & Control (1)**
- Clientes (Crédito) — 고객별 전체 거래 + 외상

**총 16개** (Phase 6 기존 15개 + Reservado/Alertas 재분류 반영)

### 기술 결정 (Locked)
- 라우트: `/reportes-v2/[slug]` 동적 라우트 (사이드바 클릭 시 shallow routing)
- 상태관리: Redux slice `reportsV2Slice` — 선택된 보고서, 파라미터, 최근 실행 캐시
- 즐겨찾기: `user_report_favorites` 테이블 (userId, reportSlug, createdAt)
- 최근 실행: localStorage (사용자별) + 선택적 DB 동기화
- 컴포넌트 재사용: Phase 6의 기존 report view 컴포넌트를 "미리보기 본문"으로 embed

### 추가 결정 (2026-04-06 discuss-phase)

#### 토글 독립 라우트 (Locked)
- `/reportes-v2`는 **UI 토글과 무관하게 항상 접근 가능한 별도 라우트**
- 기존 `/reportes`와 Phase 6 hub/페이지는 수정하지 않음 (병렬 보존)
- UserLayout 메뉴는 이후 결정: 기본 링크를 `/reportes-v2`로 돌리거나, 두 링크 병기
- 사용자는 언제든 구/신 UX 비교 가능 (점진적 마이그레이션)

#### Phase 6 view embed 전략: Hook Refactor (Locked)
- **모든 `useXxxReport` 훅을 controlled 모드로 리팩터**
  - 현재: 훅 내부에서 `params`/`setParams` 소유 + `useEffect`로 fetch
  - 변경: 훅은 `(params, options?) => { data, loading, getData, downloadExcel }` 시그니처로 외부 params 수신
  - 기본 params는 호출자(셸 또는 기존 페이지) 책임
- **기존 Phase 6 페이지 동시 수정**:
  - `VendedorReport.tsx` 등 기존 page 컴포넌트는 내부에 `useState(defaultParams)` 추가 후 훅에 주입 → 외부 동작은 동일 유지
  - 빌드 회귀 없도록 Phase 6 페이지들도 함께 검증
- **Phase 8 셸 활용**:
  - `ReportsParamsPanel`이 params 상태 소유 (Redux 또는 로컬)
  - `ReportsPreviewPanel`이 선택된 slug에 해당하는 훅을 호출하면서 params 주입
  - 기존 `VendedorReportTable` 등 하위 컴포넌트는 그대로 재사용
- **리스크**: Phase 6의 13개 훅 전부 수정 필요 → 작업량 증가, ESLint 회귀 주의

#### 카테고리 전략: 각자 유지 (Locked)
- Phase 6 hub는 **수정하지 않음** (기존 ReportesHub.tsx 그대로)
- Phase 8 사이드바는 **새 분류 (Ventas 7 / Finanzas 3 / Inventario 5 / Clientes 1)** 적용
- 토글과 무관하게 두 라우트가 각자의 분류 체계 사용
- 사용자 멘탈 모델: `/reportes-v2`가 최신 UX이므로 카테고리 불일치는 마이그레이션 기간의 과도기로 수용

#### Deferred (향후 논의 필요)
- Plan 분할 구조 (08-02, 08-03) — 현재 08-01만 존재. 16개 보고서 전부 embed까지의 wave 전략은 plan-phase에서 결정
- MVP 범위 — Success Criteria #4 "3개 이상"이 단계 기준인지 최종 기준인지 미정
- 즐겨찾기/최근실행 DB 동기화 시점

</decisions>

<data>
## Data Dependencies

- Phase 6 Wave 1~3 백엔드 API 이미 완료 (13개 보고서)
- Phase 6 Wave 4 (Alertas, Cheque Estado) 백엔드 필요 → Phase 6에서 선행 완료되어야 함
- 신규 테이블: `user_report_favorites` (id, user_id, store_id, report_slug, created_at) — pool 낭비 없도록 읽기는 캐시, 쓰기는 토글 시에만
- `/me` 응답에 최근 보고서 slug 3개 포함 고려 (추가 쿼리 없이)

</data>

<constraints>
## Constraints

- **Phase 6 페이지 비침투 원칙 완화**: Hook refactor 결정으로 인해 `views/reports/*/hooks/` 는 수정 필요. 단, `pages/reportes/*` 라우트와 `ReportesHub.tsx`는 수정 금지.
- **토글 독립**: Phase 1 ui_mode와 무관하게 `/reportes-v2` 항상 접근 가능
- **Phase 6 회귀 방지**: 훅 수정 후 기존 `/reportes/vendedor` 등 페이지 빌드/동작 검증 필수
- **Connection pool**: 보고서 리스트는 /me 응답에 embed하거나 정적 상수로 관리 (DB hit 없음)
- **Sequelize underscored**: 신규 테이블 snake_case 컬럼 준수
- **ESLint**: newline-before-return, lines-around-comment 준수

</constraints>
