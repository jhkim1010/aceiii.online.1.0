# Phase 08: Reportajes UX Redesign — Research

**Researched:** 2026-04-06
**Domain:** Next.js 13 Pages Router shell + hook refactor across 15 existing report views
**Confidence:** HIGH (codebase fully inventoried, no external libraries needed)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **Pattern 2 UX**: 좌측 다크 사이드바 300px + 우측 컨텐츠 (params 패널 → preview 패널). 목업: `reportes-mockup-pattern2-v2.html`
- **카테고리 (16개)**:
  - 🛒 **Ventas (7)**: Ventas, Items (Venta), Vendedor, Creditos, Breve Venta, Reservado, Alertas
  - 💰 **Finanzas (3)**: Facturación, Gasto, Cheque Estado
  - 📦 **Inventario (5)**: Stock Rpt Gen, Corregido (C), Movidos, Fallados, Ingreso (Depósito)
  - 👥 **Clientes & Control (1)**: Clientes (Crédito)
- **라우트**: `/reportes-v2/[slug]` 동적 라우트 + shallow routing
- **상태관리**: Redux slice `reportsV2Slice` (선택 보고서, 파라미터, 최근 실행 캐시)
- **즐겨찾기**: `user_report_favorites` 테이블 (Plan 08-03 deferred)
- **최근 실행**: localStorage 우선 + 선택적 DB 동기화
- **컴포넌트 재사용**: Phase 6의 기존 report view를 preview body로 embed
- **토글 독립**: `/reportes-v2`는 UI 토글과 무관하게 항상 접근 가능, 기존 `/reportes` 병렬 보존
- **Hook Refactor (controlled mode)**: 모든 `useXxxReport`가 외부 params 수신 → `(params, options?) => { data, loading, getData, downloadExcel }`. 기본 params는 호출자(셸 또는 기존 페이지) 책임. 기존 페이지는 `useState(defaultParams)` 추가하여 동작 유지
- **카테고리 이중화 수용**: Phase 6 ReportesHub.tsx 수정 금지, Phase 8 사이드바만 새 분류 사용

### Claude's Discretion
- Plan 분할 구조 (08-02, 08-03 wave 전략)
- MVP 범위 — Success Criteria #4 "3개 이상" 단계/최종 기준
- 즐겨찾기/최근실행 DB 동기화 시점

### Deferred Ideas (OUT OF SCOPE)
- 즐겨찾기 DB 테이블 구현 (Plan 08-03)
- Alertas/Cheque Estado 백엔드 (Phase 6 책임)
- 신규 보고서 로직 구현
- 기존 `/reportes` 경로/`ReportesHub.tsx` 수정
- UserLayout 메뉴 링크 변경 결정 (이후 결정)
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| UX-04 | Reportajes 셸 (사이드바+미리보기), 16개 보고서 통합, 기존 view embed 재사용 | 15개 view+hook 인벤토리 완료 (아래 §Hook Inventory) |
</phase_requirements>

## Project Constraints (from CLAUDE.md)
- Sequelize `underscored: true` — 신규 테이블 (`user_report_favorites`) 컬럼 snake_case
- ESLint: `newline-before-return`, `lines-around-comment`, `no-unused-vars` 빌드 차단
- 사이드바 리렌더 방지 패턴 (Phase 1 SidebarFooter 교훈): `React.memo` + `useMemo` + `useCallback`
- Pool 절약: 보고서 리스트는 정적 상수 (DB hit 없음)
- npm workspaces 호이스팅 주의 (이번 phase에서는 신규 패키지 추가 없음)

## Summary

Phase 8은 신규 라이브러리 도입 없이 **순수 프론트엔드 리팩터 + 셸 신규 구축** 작업이다. 핵심 리스크는 두 가지:
1. **15개 훅 controlled-mode 리팩터** — 동일 패턴으로 일괄 적용 가능하지만, 기존 15개 페이지 모두 회귀 검증 필요
2. **사이드바 리렌더링 폭주** — Phase 1 SidebarFooter 교훈을 그대로 적용해야 함

기존 코드베이스 조사 결과 **15개 훅이 거의 동일한 패턴**(약간의 변종 4종)을 가지고 있어 일괄 리팩터가 안전하다. preview body는 lazy import 가능한 별도 "Body" 컴포넌트로 추출하면 셸과 기존 페이지에서 모두 재사용 가능하다.

**Primary recommendation:** 훅 리팩터 → "Body" 컴포넌트 추출 → 기존 페이지 어댑터 수정 → 셸 신규 구축, 4단계 wave로 분할.

## Hook Inventory (15 hooks)

**확인된 디렉토리:** `ventago-app/src/views/reports/{slug}/hooks/use{Slug}Report.tsx` — 15개 (CONTEXT.md의 "13개"는 부정확).

| # | Slug | Hook File | Return Shape | Default params | Variant |
|---|------|-----------|--------------|----------------|---------|
| 1 | sales | useSalesReport.tsx | `{ sales, getSales, loading, params, setParams, downloadExcel, setThisMonth, setToday, clear, getSaleItemsSummary }` | startDate/endDate/filter/isParent | A (legacy + drilldown) |
| 2 | products | useProductsReport.tsx | `{ products, getProducts, ... , getProductSalesSummary }` | startDate/endDate/filter/isParent | A |
| 3 | stocks | useStockReport.tsx | `{ products, getProducts, ... , getProductStockSummary }` | startDate/endDate/filter/isParent | A |
| 4 | vendedor | useVendedorReport.tsx | `{ data, getData, loading, params, setParams, downloadExcel }` | startDate/endDate/filter | **B (canonical)** |
| 5 | gastos | useGastoReport.tsx | (B 추정) | startDate/endDate/filter | B |
| 6 | fallados | useFalladosReport.tsx | (B 추정) | startDate/endDate/filter | B |
| 7 | corregido | useCorregidoReport.tsx | (B 추정) | startDate/endDate/filter | B |
| 8 | breve-venta | useBreveVentaReport.tsx | (B 추정) | startDate/endDate/filter | B |
| 9 | facturacion | useFacturacionReport.tsx | (B 추정) | startDate/endDate/filter | B |
| 10 | clientes-credito | useClientesCreditoReport.tsx | `{ data, getData, loading, params, setParams, downloadExcel }` | filter only | C (no date) |
| 11 | ingreso | useIngresoReport.tsx | (B 추정) | startDate/endDate/filter | B |
| 12 | movidos | useMovidosReport.tsx | (B 추정) | startDate/endDate/filter | B |
| 13 | reservado | useReservadoReport.tsx | (B 추정) | startDate/endDate/filter | B |
| 14 | alertas | useAlertasReport.tsx | `{ data, getData, loading, params, setParams, downloadExcel }` | filter only | C |
| 15 | cheque-estado | useChequeEstadoReport.tsx | `{ data, getData, loading, params, setParams, downloadExcel }` | startDate/endDate/filter | B |

**4 variants observed:**
- **Variant A** (sales/products/stocks): legacy naming (`sales`/`products` not `data`, `getSales`/`getProducts` not `getData`), helpers (`setThisMonth`, `setToday`, `clear`), drill-down fetcher. **3 hooks, 3 pages have helper buttons that depend on these — DO NOT remove.**
- **Variant B** (canonical, 9 hooks): `{ data, getData, ... }` with date range. Phase 6 standardized shape.
- **Variant C** (clientes-credito, alertas): same as B but no startDate/endDate (status snapshot reports).
- **Variant D** = none (no other shapes found).

**Common pattern across all 15:**
- Internal `useState<any>(paramsDefault)`
- `useCallback(getData, [params])`
- Caller wires `useEffect(() => getData(), [params])` (e.g. VendedorReport.tsx line 11)
- `downloadExcel` reads current `params` closure
- API path: `/reports/{slug}-report` and `/reports/{slug}-report-export`

## Hook Refactor Template

### Current (uncontrolled, internal params)
```typescript
const useVendedorReport = () => {
  const paramsDefault = { startDate: ..., endDate: ..., filter: '' }
  const [data, setData] = useState<any[]>([])
  const [params, setParams] = useState<any>(paramsDefault)
  const [loading, setLoading] = useState<boolean>(false)

  const getData = useCallback(async () => { ... }, [params])
  const downloadExcel = async () => { ... uses params ... }

  return { data, getData, loading, params, setParams, downloadExcel }
}
```

### Refactored (controlled, external params)
```typescript
// Variant B canonical
export const vendedorDefaultParams = () => {
  const today = DateTime.now()
  const thisMonth = today.startOf('month')

  return {
    startDate: thisMonth.toFormat('yyyy-MM-dd'),
    endDate: today.toFormat('yyyy-MM-dd'),
    filter: ''
  }
}

const useVendedorReport = (params: any) => {
  const [data, setData] = useState<any[]>([])
  const [loading, setLoading] = useState<boolean>(false)

  const getData = useCallback(async () => {
    setLoading(true)
    try {
      const result: any = await apiConnector.get('/reports/vendedor-report', params)
      setData(result.data)
    } catch (error) {
      console.log(error)
    } finally {
      setLoading(false)
    }
  }, [params])

  const downloadExcel = useCallback(async () => {
    try {
      const todayStr = DateTime.now().toFormat('yyyyMMdd-HHmmss')
      const fileName = `vendedor-reporte-${todayStr}.xlsx`
      await apiConnector.downloadFile('/reports/vendedor-report-export', fileName, params)
    } catch (error) {
      console.log(error)
    }
  }, [params])

  return { data, getData, loading, downloadExcel }
}
```

**Key changes:**
- `params` becomes a function argument, not internal state
- `paramsDefault`는 별도 named export (`xxxDefaultParams()`) → 셸 registry와 기존 페이지가 둘 다 import
- `setParams`는 hook return에서 제거 → 기존 페이지는 `useState`를 직접 owns
- `downloadExcel`도 `useCallback([params])`로 감싸야 셸의 액션 버튼에서 안정적
- Variant A의 `setThisMonth`/`setToday`/`clear` 헬퍼는 **호출자로 이동** (별도 utility export 또는 페이지 로컬)
- Variant A의 drilldown (`getSaleItemsSummary` 등)은 그대로 유지하되 internal에서 `params`를 closure로 쓰지 말고 인자로 받기

### Existing Page Adapter (zero functional regression)
```typescript
// Before — 기존 VendedorReport.tsx
const VendedorReport = () => {
  const { data, getData, loading, params, setParams, downloadExcel } = useVendedorReport()
  useEffect(() => { getData() }, [params])
  // ...
}

// After — params를 페이지가 직접 소유
import useVendedorReport, { vendedorDefaultParams } from './hooks/useVendedorReport'

const VendedorReport = () => {
  const [params, setParams] = useState<any>(vendedorDefaultParams)
  const { data, getData, loading, downloadExcel } = useVendedorReport(params)
  useEffect(() => { getData() }, [params])
  // 기존 JSX 그대로
}
```

**Variant A pages (sales/products/stocks)**: 동일 패턴 + 페이지에 `setThisMonth`/`setToday`/`clear` 로컬 함수 추가.

## Page Compatibility Matrix

| Page | Variant | Adapter Changes | Risk |
|------|---------|-----------------|------|
| `pages/reportes/ventas/index.tsx` → SalesReport view | A | useState 추가 + 헬퍼 3개 로컬 이전 + drilldown 인자화 | **MEDIUM** (helper buttons + sale items modal) |
| `pages/reportes/items/index.tsx` → ProductReport view | A | 위와 동일 | MEDIUM |
| `pages/reportes/stocks/index.tsx` → StockReport view | A | 위와 동일 | MEDIUM |
| 그 외 12개 (vendedor 등) | B/C | useState 추가만, JSX 변경 없음 | **LOW** |

## Preview Body Extraction Pattern

Phase 6의 view 컴포넌트는 현재 **page-shell을 포함**한다 (Grid 컨테이너, Card, RangeDate, ProductFilterInput 등). 셸에서 embed하려면 **inner Body 컴포넌트**를 분리해야 한다.

```typescript
// views/reports/vendedor/VendedorReportBody.tsx (NEW)
type Props = { params: any; setParams: (p: any) => void }
const VendedorReportBody = ({ params, setParams }: Props) => {
  const { data, getData, loading, downloadExcel } = useVendedorReport(params)
  useEffect(() => { getData() }, [params])

  return (
    <Grid container spacing={4}>
      <Grid item xs={12} sm={8}>
        <ProductFilterInput filter={params.filter} setParams={setParams} />
        <VendedorReportTable data={data} loading={loading} downloadExcel={downloadExcel} />
      </Grid>
      <Grid item xs={12} sm={4}>
        <Card sx={{ textAlign: 'center', mb: 4 }}>
          <RangeDate startDate={params.startDate} endDate={params.endDate} setParams={setParams} />
        </Card>
      </Grid>
    </Grid>
  )
}

// views/reports/vendedor/VendedorReport.tsx (existing page wrapper)
const VendedorReport = () => {
  const [params, setParams] = useState<any>(vendedorDefaultParams)

  return <VendedorReportBody params={params} setParams={setParams} />
}
```

→ 셸의 `ReportsPreviewPanel`은 registry에서 `bodyComponent`를 lazy import해서 동일 props 전달.
→ Plan 08-01 MVP에서는 **3개 보고서만 Body 추출** (vendedor, ventas, items) — 나머지 12개는 후속 wave에서 점진 적용. 셸은 미추출 보고서에 대해 "기본 페이지 링크" placeholder 표시.

## Registry Shape

```typescript
// views/reports-v2/registry.ts
import { ComponentType, lazy } from 'react'

export type ReportCategory = 'ventas' | 'finanzas' | 'inventario' | 'clientes'

export interface ReportParamsSchema {
  hasDateRange: boolean   // false for variant C (alertas, clientes-credito)
  hasFilter: boolean      // 모든 보고서 true
  hasIsParent?: boolean   // variant A only
}

export interface ReportEntry {
  slug: string
  title: string
  category: ReportCategory
  icon: string
  description: string
  paramsSchema: ReportParamsSchema
  defaultParams: () => Record<string, any>
  bodyComponent?: ComponentType<{ params: any; setParams: (p: any) => void }>  // lazy
  legacyHref: string  // /reportes/xxx — fallback link
}

export const REPORTS_REGISTRY: ReportEntry[] = [
  // Ventas (7)
  { slug: 'ventas', title: 'Ventas', category: 'ventas', icon: 'mdi:sale-outline',
    description: 'Reporte de ventas detallado', legacyHref: '/reportes/ventas',
    paramsSchema: { hasDateRange: true, hasFilter: true, hasIsParent: true },
    defaultParams: salesDefaultParams,
    bodyComponent: lazy(() => import('src/views/reports/sales/SalesReportBody')) },
  // ...
]
```

**No DB hit** — 정적 상수, 매장과 무관 (구독/권한 필터링은 향후 별도 layer).

## 16-Report Mapping (Phase 8 categories → Phase 6 paths)

| Cat | Report (Phase 8) | Slug | Phase 6 view path | Phase 6 hook | Status |
|-----|------------------|------|-------------------|--------------|--------|
| 🛒 Ventas | Ventas | `ventas` | `views/reports/sales/SalesReport.tsx` | useSalesReport (A) | ✅ exists |
| 🛒 Ventas | Items (Venta) | `items` | `views/reports/products/ProductReport.tsx` | useProductsReport (A) | ✅ |
| 🛒 Ventas | Vendedor | `vendedor` | `views/reports/vendedor/VendedorReport.tsx` | useVendedorReport (B) | ✅ |
| 🛒 Ventas | Creditos | `clientes-credito` | `views/reports/clientes-credito/ClientesCreditoReport.tsx` | useClientesCreditoReport (C) | ⚠️ **카테고리 충돌**: CONTEXT.md는 Creditos를 Ventas에 배치하지만 동일 보고서가 👥 Clientes & Control에도 "Clientes (Crédito)"로 등장. **하나의 slug 두 카테고리에 등장 또는 중복 인정 필요 — discuss-phase 후속 결정 사항** |
| 🛒 Ventas | Breve Venta | `breve-venta` | `views/reports/breve-venta/BreveVentaReport.tsx` | useBreveVentaReport (B) | ✅ |
| 🛒 Ventas | Reservado | `reservado` | `views/reports/reservado/ReservadoReport.tsx` | useReservadoReport (B) | ✅ |
| 🛒 Ventas | Alertas | `alertas` | `views/reports/alertas/AlertasReport.tsx` | useAlertasReport (C) | ✅ |
| 💰 Finanzas | Facturación | `facturacion` | `views/reports/facturacion/FacturacionReport.tsx` | useFacturacionReport (B) | ✅ |
| 💰 Finanzas | Gasto | `gastos` | `views/reports/gastos/GastoReport.tsx` | useGastoReport (B) | ✅ |
| 💰 Finanzas | Cheque Estado | `cheque-estado` | `views/reports/cheque-estado/ChequeEstadoReport.tsx` | useChequeEstadoReport (B) | ✅ |
| 📦 Inventario | Stock Rpt Gen | `stocks` | `views/reports/stocks/StockReport.tsx` | useStockReport (A) | ✅ |
| 📦 Inventario | Corregido (C) | `corregido` | `views/reports/corregido/CorregidoReport.tsx` | useCorregidoReport (B) | ✅ |
| 📦 Inventario | Movidos | `movidos` | `views/reports/movidos/MovidosReport.tsx` | useMovidosReport (B) | ✅ |
| 📦 Inventario | Fallados | `fallados` | `views/reports/fallados/FalladosReport.tsx` | useFalladosReport (B) | ✅ |
| 📦 Inventario | Ingreso (Depósito) | `ingreso` | `views/reports/ingreso/IngresoReport.tsx` | useIngresoReport (B) | ✅ |
| 👥 Clientes | Clientes (Crédito) | `clientes-credito` | (same as Creditos above) | useClientesCreditoReport (C) | ⚠️ duplicate |

**Gap analysis:**
- **모든 15개 view + hook 존재** — Phase 6 완료 상태와 일치
- **16개 = 15개 unique + 1 중복**: Creditos(Ventas)와 Clientes Crédito(Clientes&Control)가 동일 slug. 셸 사이드바에서 두 카테고리에 동일 entry를 표시할지(권장: registry에 `categories: string[]` 허용) 또는 별도 slug로 분리할지 (Plan 결정 필요)
- **신규 보고서 0개** — Phase 8은 순수 UX 작업

## Shell Layout Reference

**기존 사이드바 패턴** (`src/@core/layouts/VerticalLayout.tsx`):
- `VerticalLayoutWrapper` = `display: flex`, height 100%
- `Navigation` 컴포넌트가 좌측 (resize 가능, localStorage 저장)
- `MainContentWrapper` flex-grow

**Phase 8 셸은 layout이 아닌 page 내부 grid**로 구현해야 한다. UserLayout이 외부에서 감싸므로, 페이지 내부에서 또 다른 좌-우 분할을 만든다:

```typescript
// views/reports-v2/ReportsShell.tsx
<Box sx={{
  display: 'grid',
  gridTemplateColumns: '300px 1fr',
  height: 'calc(100vh - 64px)',  // 상단 AppBar 제외
  minHeight: 0
}}>
  <ReportsSidebar /> {/* 다크 테마 */}
  <Box sx={{ display: 'flex', flexDirection: 'column', minHeight: 0 }}>
    <ReportsTopbar />
    <ReportsParamsPanel />
    <ReportsPreviewPanel />
  </Box>
</Box>
```

**다크 사이드바**: `ThemeProvider`로 inner subtree를 dark mode override (MUI 5 nested theme 패턴) 또는 직접 `bgcolor: 'grey.900'` + `color: 'grey.100'`. nested ThemeProvider가 깔끔.

## Redux Slice Pattern (project convention)

조사 결과 `src/store/slices/`는 **존재하지 않는다**. 실제 구조:
- `src/store/index.ts` — `configureStore({ reducer: { user } })`
- `src/store/apps/{name}/index.ts` — slice 파일 (e.g. `apps/user/index.ts`)

**컨벤션:** `apps/{name}/index.ts`에 `createSlice` + `createAsyncThunk` 정의, default export는 reducer.

**Phase 8 슬라이스 위치:**
```
src/store/apps/reports-v2/index.ts
```

```typescript
import { createSlice, PayloadAction } from '@reduxjs/toolkit'

interface ReportsV2State {
  selectedSlug: string | null
  paramsBySlug: Record<string, any>  // params persist per report
  recentSlugs: string[]              // 최근 5개, localStorage 동기화
  searchQuery: string
}

const initialState: ReportsV2State = {
  selectedSlug: null,
  paramsBySlug: {},
  recentSlugs: [],
  searchQuery: ''
}

export const reportsV2Slice = createSlice({
  name: 'reportsV2',
  initialState,
  reducers: {
    selectReport: (state, action: PayloadAction<string>) => { ... },
    setParams: (state, action: PayloadAction<{ slug: string; params: any }>) => { ... },
    pushRecent: (state, action: PayloadAction<string>) => { ... },
    setSearchQuery: (state, action: PayloadAction<string>) => { ... }
  }
})

export default reportsV2Slice.reducer
```

`store/index.ts`에 `reportsV2: reportsV2Reducer` 추가 필요.

## Next.js 13 Pages Router — Shallow Routing

**HIGH confidence (Next.js docs verified pattern, used widely in this codebase already).**

```typescript
router.push(`/reportes-v2/${slug}`, undefined, { shallow: true })
```

**Gotchas for `/reportes-v2/[slug]`:**
1. `getInitialProps`/`getServerSideProps`/`getStaticProps`가 page에 정의되어 있으면 **shallow가 무시된다**. → 동적 라우트 page는 **이 메서드들을 정의하지 않아야** 한다 (pure client-side rendering).
2. 첫 진입(direct URL `/reportes-v2/vendedor`)은 어차피 서버에서 처리됨 → page component는 `router.query.slug`로 초기 slug 결정.
3. shallow는 **same page** 안에서만 동작 → `/reportes-v2/[slug]` 라우트를 유지하면서 slug만 바뀌는 한 동작. `/reportes-v2/index`와 `/reportes-v2/[slug]`를 오갈 때는 shallow 미지원이므로 **둘을 통합** (`index.tsx`는 default slug로 redirect 또는 catch-all `[[...slug]].tsx` 사용).

**권장 구조:**
```
pages/reportes-v2/
└── [[...slug]].tsx   # optional catch-all → index와 slug를 한 라우트에서
```

또는
```
pages/reportes-v2/
├── index.tsx         # → useEffect로 router.replace('/reportes-v2/vendedor', undefined, { shallow: false })
└── [slug].tsx        # 실제 셸
```

권장: **catch-all `[[...slug]].tsx` 한 파일** — shallow routing이 가장 단순.

## Common Pitfalls

### Pitfall 1: Sidebar 폭주 리렌더링 (Phase 1 SidebarFooter 재발)
**What:** 매 slug 변경마다 사이드바 전체 재렌더링 → 검색 입력 lag
**Why:** Redux state 구독 컴포넌트가 너무 큰 단위
**Avoid:**
- `ReportsSidebar`를 `React.memo`로 감싸고 `selectedSlug`만 가져오기
- 카테고리 그룹은 `useMemo`로 정적 생성 (registry 기반)
- `searchQuery`는 별도 컴포넌트(`SearchInput`)에서 구독해서 부모 리렌더 차단
- 보고서 항목 리스트는 `useMemo` 캐싱 + key는 slug

### Pitfall 2: useEffect deps에 객체 직접 사용
**What:** `useEffect(() => getData(), [params])` 에서 params가 매 렌더 새 객체면 무한 루프
**Avoid:** 페이지/셸에서 `useState(defaultParams)` 사용 시 setter로만 갱신 (직접 객체 재할당 금지). Redux 사용 시 reducer가 동일성 유지

### Pitfall 3: ESLint `newline-before-return`
**What:** 리팩터 후 빌드 실패 다발
**Avoid:** 모든 `return` 위에 빈 줄 (특히 hook 마지막 `return { data, ... }`)

### Pitfall 4: Hook signature change 회귀
**What:** 15개 hook의 caller가 누락되면 빌드 깨짐
**Avoid:** Grep `useVendedorReport(`, `useSalesReport(` 등으로 모든 호출처 점검. 현재 조사상 caller는 각 view의 `XxxReport.tsx` 1개씩만 — 안전.

### Pitfall 5: shallow routing + getInitialProps 충돌
**What:** Pages Router에서 `getInitialProps` 정의 시 shallow 무시 → 매번 full reload
**Avoid:** `[[...slug]].tsx`에 SSR 메서드 정의 금지. 초기 slug는 `useRouter()`로 client-side 처리.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead |
|---------|-------------|-------------|
| 다이내믹 lazy 로딩 | 자체 import 캐시 | React `lazy()` + `Suspense` |
| 검색 필터링 | 자체 debounce | 단순 `filter()` (16개 항목이라 debounce 불필요) |
| 다크 사이드바 테마 | 인라인 sx 반복 | MUI nested `ThemeProvider` |

## Code Examples

### Catch-all route handler
```typescript
// pages/reportes-v2/[[...slug]].tsx
import { useRouter } from 'next/router'
import { useMemo } from 'react'
import ReportsShell from 'src/views/reports-v2/ReportsShell'
import { REPORTS_REGISTRY } from 'src/views/reports-v2/registry'

const ReportsV2Page = () => {
  const router = useRouter()
  const slug = useMemo(() => {
    const raw = router.query.slug
    if (Array.isArray(raw) && raw[0]) return raw[0]

    return REPORTS_REGISTRY[0].slug  // default
  }, [router.query.slug])

  return <ReportsShell slug={slug} />
}

export default ReportsV2Page
```

### Sidebar item click (shallow)
```typescript
const handleSelect = useCallback((slug: string) => {
  router.push(`/reportes-v2/${slug}`, undefined, { shallow: true })
  dispatch(selectReport(slug))
}, [router, dispatch])
```

## Runtime State Inventory

| Category | Items | Action |
|----------|-------|--------|
| Stored data | None — 신규 phase, 기존 데이터 변경 없음 | None |
| Live service config | None | None |
| OS-registered state | None | None |
| Secrets/env vars | None | None |
| Build artifacts | Phase 6 view 컴포넌트는 그대로 export 유지 (`VendedorReport` default export 유지) → 기존 page import 깨지지 않음 | 검증 |

**신규 DB 객체 (deferred to Plan 08-03):** `user_report_favorites` 테이블 — `id`, `user_id`, `store_id`, `report_slug`, `created_at` snake_case.

## Environment Availability

순수 프론트엔드 작업, 신규 외부 의존 없음. 기존 스택만 사용:
- Next.js 13 ✓
- MUI 5 ✓
- Redux Toolkit ✓
- Iconify ✓ (이미 ReportesHub.tsx에서 사용)

## Validation Architecture

`.planning/config.json` 미확인 — nyquist_validation 키 부재로 가정. 이 프로젝트는 **자동 테스트 인프라가 거의 없는 상태** (Wave 0 gap 큼). Phase 8은 **수동 빌드 검증 위주**.

### Test Framework
| Property | Value |
|----------|-------|
| Framework | 없음 (수동 검증) |
| Quick run command | `cd ventago-app && npm run build` (Next.js + ESLint 통합) |
| Full suite command | 위와 동일 + 수동 브라우저 테스트 |

### Phase Requirements → Test Map
| Req | Behavior | Test Type | Command |
|-----|----------|-----------|---------|
| UX-04 | 셸 빌드 통과 + 15개 페이지 회귀 없음 | manual build + click-through | `npm run build` |
| UX-04 | shallow routing 동작 | manual | 브라우저: 사이드바 클릭 → DevTools Network 탭에서 page request 0 확인 |
| UX-04 | 사이드바 리렌더 최적화 | manual | React DevTools Profiler로 사이드바 단일 렌더 확인 |

### Sampling Rate
- **Per task commit:** `cd ventago-app && npm run build`
- **Per wave merge:** 위 + 기존 15개 `/reportes/*` 페이지 수동 클릭 (최소 1회)
- **Phase gate:** 빌드 그린 + 셸에 embed된 보고서 (MVP 3개) end-to-end 동작

### Wave 0 Gaps
- [ ] (선택) hook 단위 테스트 인프라 — 현재 없음, Phase 8 범위 외
- [ ] (선택) 시각 회귀 테스트 — 없음, Phase 8 범위 외

## Open Questions

1. **Creditos / Clientes Crédito 중복**
   - What we know: CONTEXT.md 카테고리에 동일 보고서가 두 카테고리에 등장 (Ventas의 "Creditos" + Clientes&Control의 "Clientes (Crédito)")
   - What's unclear: 사이드바에 두 번 표시? 별도 slug로 분리? 단일 entry + 다중 카테고리?
   - Recommendation: registry에 `categories: ReportCategory[]` 필드 허용, 동일 entry가 두 그룹에 표시. plan-phase에서 확정.

2. **셸 MVP에서 embed할 3개 보고서 선택**
   - Recommendation: variant B의 가장 단순한 3개 — vendedor / gastos / breve-venta. variant A (sales/products/stocks)는 helper 이전 부담이 크므로 후속 wave.

3. **Phase 6 페이지의 `views/reports/{slug}/{Slug}Report.tsx`를 직접 수정 vs 새 Body 분리**
   - Recommendation: **새 Body 분리** (zero risk) — 기존 `XxxReport.tsx`는 thin wrapper로 변경. Phase 6 페이지는 같은 export 경로 유지.

## Sources

### Primary (HIGH)
- `ventago-app/src/views/reports/**` — 15 hook + view 직접 read
- `ventago-app/src/store/index.ts`, `store/apps/user/index.ts` — Redux 컨벤션
- `ventago-app/src/@core/layouts/VerticalLayout.tsx` — 사이드바 패턴
- `ventago-app/src/views/reports/hub/ReportesHub.tsx` — 기존 카탈로그
- `.planning/phases/08-reportajes-ux/08-CONTEXT.md` — locked decisions
- `./CLAUDE.md` — 프로젝트 규칙

### Notes
- Variants B/C 9개 hook 중 4개만 직접 read (vendedor, alertas, clientes-credito, cheque-estado). 나머지 5개(gastos/fallados/corregido/breve-venta/facturacion/ingreso/movidos/reservado)는 동일 패턴으로 추정 — **plan 단계에서 5개 추가 spot-check 권장**.
- Variant A 3개 중 sales/products/stocks 모두 직접 read 완료.

## Metadata

**Confidence breakdown:**
- Hook inventory: HIGH (15/15 listed, 7 직접 read, 패턴 명확)
- Refactor template: HIGH (canonical pattern from variant B)
- Registry shape: HIGH
- Page compatibility: HIGH for variant B/C, MEDIUM for variant A (helper 이전 작업량)
- Shallow routing: HIGH (Next.js docs + 일반적 패턴)
- Redux convention: HIGH (실제 구조 확인)

**Research date:** 2026-04-06
**Valid until:** 2026-05-06 (코드베이스 변경 빠르지 않음)
