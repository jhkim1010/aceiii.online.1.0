# Phase 32: stocks-historial-drawer - Context

**Gathered:** 2026-05-08
**Status:** Ready for planning
**Mode:** --auto (Claude picked recommended defaults for all gray areas)

<domain>
## Phase Boundary

**스코프**: Stocks 보고서(`/reportes/stocks`)에서 row 클릭 시 우측 380px drawer 슬라이드. 해당 productBranch(상품×지점)의 stock ledger 변동 이력을 chronologically 표시. 4가지 type 모두 통합:
- `movido` (지점간 이동) — origin/target 표시
- `ingreso` (입고) — 공급자/송장 표시
- `fallado` (분실/파손) — 사유 note
- `corregido` (수동 보정) — 사용자 + note

**스코프 외 (다른 phase 후보)**:
- 새 stock 변동 등록 UI (편집 기능) — 단순 historial 보기만
- 변동 사유 분석/통계 차트 — drawer는 timeline 보기만
- Stock 변동 audit/regulatory export — 별도 phase
- 지점간 audit 종합 보고서 — 이미 `/reportes/movidos`에 있음

**의존**: Phase 12 (cockpit drawer 패턴, KpiStrip/shared 컴포넌트)
</domain>

<decisions>
## Implementation Decisions

### D-01 Backend: 단일 통합 historial endpoint (자동 선택)
**선택**: 신규 endpoint `GET /reports/stocks-cockpit/historial?productBranchId=X&days=30&offset=0`

**이유**:
- pool 1 connection으로 4 type 모두 timeline 반환
- 기존 `reportsStocksCockpit.service.ts`(`api-ventago/src/app/reports/`)에 method 추가 (새 service 불필요)
- 기존 `/reports/stocks-cockpit/*` 패밀리(5 endpoint)와 일관성

**대안 (기각)**: 4개 엔드포인트(`/historial/movidos`, `/historial/ingresos`...) — 4 connections, 정렬 까다로움.

### D-02 Trigger: stocks row 클릭 (자동 선택)
**선택**: `StocksCockpitBody.tsx`(`ventago-app/src/views/reports/stocks/`)의 row click handler → drawer open

**이유**: Vendedor cockpit(`VendedorCockpitDetail.tsx`)과 동일 UX. 사용자가 이미 익숙.

**대안 (기각)**: 별도 "Historial" 컬럼 버튼 — 화면 가로 좁아짐, 우발 클릭 어려움.

### D-03 표시 범위: 30일 + "더 로드" 버튼 (자동 선택)
**선택**:
- Initial fetch: 최근 30일 (`days=30`)
- Drawer 하단에 `Cargar 30 días más` 버튼 → `offset` 증가 + 누적 표시
- 페이지네이션 X (timeline은 전체 chronological이라 page 단위가 어색)

**이유**: 평균 사용 시 최근 변동만 보면 충분. 90% 케이스 1 fetch로 끝.

**Edge case**: 100건 이상 가능 매장 → 더 로드로 점진적 노출.

### D-04 Type 인코딩: 아이콘 + 색상 (자동 선택)
**선택**:

| Type | 아이콘 | 색상 (sketch-findings 테마) | 라벨 |
|:--|:--|:--|:--|
| `movido in` (target 입장) | 📥 (`tabler:arrow-down`) | MP cyan `#5DF2FF` | "Recibido de [origen branch]" |
| `movido out` (origin 입장) | 📤 (`tabler:arrow-up`) | MP cyan `#5DF2FF` | "Enviado a [target branch]" |
| `ingreso` | 📦 (`tabler:package-import`) | success green | "Ingreso" + 송장/공급자 |
| `fallado` | ⚠ (`tabler:alert-triangle`) | error red | "Fallado" + note |
| `corregido` | ✏ (`tabler:edit`) | warning gold (Ventago 골드) | "Corrección" + note |

**Layout**: 좌측 아이콘 + signed quantity 강조(`+12` green 또는 `-3` red) + 라벨 + 부 정보(date, user, sucursal/note) — Vendedor venta drawer row와 유사 구조.

### D-05 Audit 정보: audit_logs JOIN (자동 선택)
**선택**: `Stocks` row에 `audit_logs` LEFT JOIN하여 액션 사용자 표시. JOIN 키: audit_logs는 `entityType='stock'` + `entityId=stocks.id` 매칭.

**이유**: 기존 audit 시스템(`@Audit` decorator) 활용. movidos는 `description`에 origin/target도 자동 포함 (`createStockMovement` 핸들러의 audit 데코레이터에서).

**Fallback**: audit_logs 매칭 실패 시 user는 'Sistema' 표시 (자동 처리/cron 등).

### D-06 sucursal 이름 표시 (자동 선택)
**선택**: movido out/in의 경우, `note` 컬럼의 `movido(out→{branchId})`/`movido(in←{branchId})` 패턴에서 branchId 추출 → `branches` 테이블 JOIN으로 사용자 친화적 이름 표시.

**대안 검토**: 새 컬럼 `counterparty_branch_id` 추가 — 마이그레이션 비용. note 파싱이 비용 적고 충분.

### D-07 키보드/UX (자동 선택)
**선택**:
- ESC 키로 drawer 닫기
- Drawer 외부 클릭 시 닫기 (modal mode 아닌 dismissible)
- 같은 row 재클릭 시 toggle (close)
- Loading skeleton 5행 (drawer 열리자마자 즉시 표시)

### D-08 Stock actual + 합계 헤더 (자동 선택)
**선택**: Drawer 상단 sticky 헤더에:
- 현재 stock (해당 productBranch)
- 30일 net 변동 (`+N`/`-N`/`±0`)
- variant 식별 정보 (sku, color, size, branch명)

### D-09 캐시 (자동 선택)
**선택**: 기존 `useCockpitCache` 훅(`ventago-app/src/views/reports-v2/hooks/useCockpitCache.ts`, Phase 12 Plan 08) 사용. 5분 TTL, LRU 64.

### Claude's Discretion
- Drawer 내부 컴포넌트 구조 (FlatList vs grouped by date)
- 빈 ledger 케이스 일러스트/메시지
- 정확한 SQL 인덱스 제안 (planner가 결정)
- Stocks 보고서 row의 어떤 cell에 click target을 둘지 (row 전체 vs 특정 cell)
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 12 cockpit drawer 패턴 (재사용 reference)
- `.planning/phases/12-reportajes-cockpit/12-02-SUMMARY.md` — Vendedor cockpit reference 패턴 (drawer 구조, 컴포넌트 분리)
- `ventago-app/src/views/reports/vendedor/VendedorCockpitDetail.tsx` — drawer 컴포넌트 reference
- `ventago-app/src/views/reports/shared/index.ts` — KpiStrip/Sparkline/formatters 재사용

### Stocks 영역 기존 자산
- `api-ventago/src/app/reports/reportsStocksCockpit.service.ts` — 기존 service (확장 대상)
- `api-ventago/src/app/reports/reports.controller.ts` line 770~830 — 기존 stocks-cockpit endpoint 5종
- `ventago-app/src/views/reports/stocks/StocksCockpitBody.tsx` — Stocks 보고서 body (row click handler 추가 위치)
- `ventago-app/src/views/reports-v2/registry.ts` line 265 — registry entry

### Stocks ledger 모델
- `api-ventago/src/app/stocks/stocks.model.ts` — Stocks 모델 (`stock`, `type`, `note`, `created_at`, `productBranchId`)
- `api-ventago/src/app/stocks/stocks.service.ts` — `createStockMovement` (note 형식 reference: `movido(out→X)`, `movido(in←Y)`)
- `api-ventago/src/app/products/branch/products-branch.model.ts` — ProductBranch (productId, branchId)

### Audit 시스템
- `api-ventago/src/common/decorators/audit.decorator.ts` — @Audit 데코레이터
- `api-ventago/src/common/interceptors/audit.interceptor.ts` — audit 작성 로직
- `audit_logs` 테이블 (psql `\d audit_logs` 참조)

### 디자인 / 색상
- `.claude/skills/sketch-findings-ace-online/SKILL.md` — Ventago 다크 네이비 + 골드 + MP cyan 테마
- `.planning/phases/12-reportajes-cockpit/12-04-SUMMARY.md` — error.main 빨강 사용 예시 (Gastos 차트)

### 캐시
- `ventago-app/src/views/reports-v2/hooks/useCockpitCache.ts` — Phase 12 Plan 08 LRU 5분 TTL 캐시

### 본 phase 직전 컨텍스트 (root cause 세션)
- 이번 movidos fix 세션의 진단 — `ProductList.tsx` movidos parent → variant child 펼치기 fix가 이 phase의 검증 시나리오 입력
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`VendedorCockpitDetail.tsx`** — drawer 컴포넌트 패턴, 같은 380px 우측 슬라이드 + 헤더 + 리스트 + 더 로드 패턴
- **`shared/KpiStrip.tsx` + `formatters.ts`** — 신호 지표/포맷 (fmtGs/fmtInt 등)
- **`useCockpitCache`** — drawer fetch에 사용. key는 `'stocks-historial::' + productBranchId + '::' + offset`
- **`reportsStocksCockpit.service.ts`** — 기존 service에 method 추가 (새 파일 불필요)
- **Audit 데코레이터** — 기존 stock CRUD가 이미 audit 작성 중 → JOIN 가능

### Established Patterns
- **Cockpit endpoint 명명**: `/reports/{slug}-cockpit/{detail-name}` (Phase 12 일관)
- **Detail tab/drawer lazy fetch**: 사용자 인터랙션 시점에만 fetch (pool 절약)
- **raw SQL CTE**: pool 1 connection per endpoint (Phase 12-02 패턴)
- **Note 컬럼 패턴**: `movido(out→{id})` / `movido(in←{id})` / `fallado: ...` / `corregido: ...` (이번 fix 세션의 디버그 로그에서 확인)

### Integration Points
- **Frontend**: `StocksCockpitBody.tsx`에 row click handler 추가, `StocksHistorialDrawer.tsx` 새 컴포넌트
- **Backend**: `reportsStocksCockpit.service.ts`에 `getHistorial(filters)` method 추가
- **Controller**: `reports.controller.ts`에 `@Get('stocks-cockpit/historial')` 추가, 기존 `@FunctionGuard('reporte-stocks', 'read')` 재사용
- **Module**: 변경 불필요 (기존 service 재사용)
</code_context>

<specifics>
## Specific Ideas

### 사용자 멘탈 모델 (1차 사용자 진술)
> "내 옛날 시스템에는 producto 부분에서 스톡으로 추가된 것처럼 처리했었는데"

→ Producto별 historial을 보는 패턴에 익숙. Stocks 보고서가 productBranch grain이므로 자연스럽게 매칭.

### 검증 시나리오 (사용자 합의)
1. 로컬 dev: nueva-venta → movidos ON → origin → target → 등록 (이번 movidos fix가 적용된 상태)
2. Stocks 보고서 → 방금 받은 variant SKU row 클릭
3. Drawer 열림 → 최상단에 `📥 +N movido / 받은 from [origen sucursal] / 사용자명 / 방금 시각` 행 표시
4. 같은 variant의 origin sucursal로 필터 변경 → row 클릭 → `📤 -N movido / 보낸 to [target sucursal]` 행 표시

### 디자인 인용 (sketch-findings-ace-online에서 확장)
- Drawer 헤더: 다크 네이비 배경 + 골드 액센트 (현재 stock 강조)
- Type 색상: MP cyan (movido) / success (ingreso) / error (fallado) / warning gold (corregido)
- Row hover: subtle background lift
- Sticky header: 현재 상태(stock + 30일 net)
</specifics>

<deferred>
## Deferred Ideas

### Phase 32+ 후속 후보
- **Stock 변동 인라인 편집** — drawer에서 fallado/corregido 즉시 등록 (현재 phase는 보기만)
- **CSV/Excel 내보내기** — drawer historial을 export
- **다중 variant 비교 drawer** — 2개 SKU 나란히 timeline (Phase 12-07 비교 모드와 통합)
- **변동 트렌드 차트** — drawer 안에 7/30/90일 미니 라인 차트
- **알림 통합** — fallado 임계치 초과 시 알림 (별도 alerting phase)

### Audit 정합성 (Phase 22 후속 후보)
- 과거 movido 데이터 중 parent productId로 잘못 들어간 행 audit (이번 fix 직전에 4건 DELETE했으나 더 있을 수 있음)
- ProductBranch의 `currentStock` cache column이 있다면 ledger SUM과 reconciliation 검증
</deferred>

---

*Phase: 32-stocks-historial-drawer*
*Context gathered: 2026-05-08 (auto mode)*
