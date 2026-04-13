# Cockpit 패턴 — 표준 보고서 구현 가이드

**작성일:** 2026-04-13
**Phase:** 12 Wave 08
**상태:** 확정 (Phase 12 완료 기준)

---

## 개요

Ventago의 모든 보고서(`/reportes-v2`)는 "단일 통합 엔드포인트(Cockpit)" 원칙을 따른다.

- **백엔드:** 하나의 API 호출이 KPI summary + 랭킹/목록 + 차트 데이터를 모두 반환 (N+1 쿼리 금지)
- **프론트엔드:** `useCockpitCache` 훅으로 5분간 결과를 캐싱 — 동일 필터 재방문 시 API 호출 0회
- **레이아웃:** `CockpitLayout.tsx` — 56px Topbar + KPI Strip + Primary Area + 선택적 Detail/Drawer

---

## 백엔드 패턴

### 1. 서비스 파일 명명

```
api-ventago/src/app/reports/reports{Name}Cockpit.service.ts
```

예: `reportsVendedorCockpit.service.ts`, `reportsGastoCockpit.service.ts`

### 2. 서비스 클래스 구조

```typescript
@Injectable()
class Reports{Name}CockpitService {
  constructor(private readonly sequelize: Sequelize) {}

  // 메인 엔드포인트 — KPI + 목록 + 차트를 단일 응답으로
  async getCockpit(filters: {Name}CockpitFilters) {
    // 원칙: raw SQL with QueryTypes.SELECT 사용 (hydration 비용 절감)
    // 원칙: sequelize.query() 호출은 메인 엔드포인트 기준 3회 이내
    // 원칙: 별도 탭 데이터는 lazy 엔드포인트로 분리

    const result = await this.sequelize.query<Row>(SQL, {
      replacements: { storeId, startDate, endDate, ... },
      type: QueryTypes.SELECT,
    })

    return { summary: ..., items: ..., trend: ... }
  }
}
```

### 3. 필터 타입 규칙

```typescript
type {Name}CockpitFilters = {
  storeId?: number | null    // 멀티테넌트 — null 허용
  branchId?: number | null   // 지점 필터 — null = 전체
  startDate: string          // yyyy-MM-dd
  endDate: string            // yyyy-MM-dd
  filter?: string            // 텍스트 검색 (선택)
}
```

### 4. SQL 작성 규칙

- 컬럼명: **반드시 snake_case** (Sequelize `underscored: true` 매핑)
- 유효 판매 상태: `IN ('Facturado', 'Pagado', 'Pendiente por pagar')`
- 반품 집계: `status = 'Anulación'` 별도 처리
- 금액 단위: INTEGER (과라니 ₲), sale_items 금액은 NUMERIC
- CTE 사용 권장 — 서브쿼리 복잡도를 분리하여 가독성 확보

### 5. 컨트롤러 엔드포인트

```typescript
@Get('{name}-cockpit')
async get{Name}Cockpit(@Query() query: QueryDto, @Req() req: Request) {
  const storeId = req['user']?.storeId ?? null
  return this.reports{Name}CockpitService.getCockpit({ ...query, storeId })
}
```

### 6. 모듈 등록

`reports.module.ts`의 `providers` 배열에 서비스 추가:

```typescript
providers: [
  // ...기존 서비스들
  Reports{Name}CockpitService,
]
```

---

## 프론트엔드 패턴

### 1. 훅 파일 명명

```
ventago-app/src/views/reports/{name}/hooks/use{Name}Cockpit.tsx
```

### 2. 훅 구조 (캐시 없는 기본 패턴)

```typescript
const use{Name}Cockpit = (params: any) => {
  const auth = useAuth()
  const storeId = auth?.user?.storeId ?? null
  const mergedParams = useMemo(() => ({ ...(params || {}), storeId }), [params, storeId])

  const [summary, setSummary] = useState(EMPTY_SUMMARY)
  const [items, setItems] = useState([])
  const [loading, setLoading] = useState(false)

  const getData = useCallback(async () => {
    if (!mergedParams.startDate || !mergedParams.endDate) return
    setLoading(true)
    try {
      const result: any = await apiConnector.get('/reports/{name}-cockpit', mergedParams)
      setSummary(result?.summary ?? EMPTY_SUMMARY)
      setItems(Array.isArray(result?.items) ? result.items : [])
    } catch (error) {
      console.log(error)
    } finally {
      setLoading(false)
    }
  }, [mergedParams])

  useEffect(() => {
    getData()

    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [mergedParams])

  return { summary, items, loading, getData }
}
```

### 3. useCockpitCache 훅 (캐시 적용 패턴)

위 기본 패턴 대신 `useCockpitCache`를 사용하면 동일 파라미터 재방문 시 API 호출이 생략된다.

```typescript
import useCockpitCache from 'src/views/reports-v2/hooks/useCockpitCache'
import apiConnector from 'src/services/api.service'

const use{Name}CockpitCached = (params: any) => {
  const auth = useAuth()
  const storeId = auth?.user?.storeId ?? null
  const mergedParams = useMemo(
    () => ({ ...(params || {}), storeId }),
    [params, storeId]
  )

  const { data, loading, error, refresh } = useCockpitCache(
    '{name}',
    mergedParams,
    () => apiConnector.get('/reports/{name}-cockpit', mergedParams)
  )

  return {
    summary: data?.summary ?? EMPTY_SUMMARY,
    items: data?.items ?? [],
    loading,
    error,
    refresh,
  }
}
```

### 4. ESLint 필수 준수 사항

| 규칙 | 대처 |
|------|------|
| `newline-before-return` | `return` 문 바로 위에 빈 줄 |
| `lines-around-comment` | `//` 주석 바로 위에 빈 줄 |
| `no-unused-vars` | import한 변수는 반드시 사용 |

### 5. Body 컴포넌트 파일 명명

```
ventago-app/src/views/reports/{name}/{Name}CockpitBody.tsx
```

### 6. Registry 등록

`registry.ts`에 lazy import 후 `REPORTS_REGISTRY` 배열에 추가:

```typescript
const {Name}ReportBody = lazy(() => import('src/views/reports/{name}/{Name}CockpitBody'))

// REPORTS_REGISTRY 배열에:
{
  slug: '{name}',
  title: '...',
  categories: ['...'],
  filterSchema: ['sucursal', 'rangeDate'],
  cockpitLayout: { hasKpiStrip: true, hasDetail: false, hasDrawer: false },
  defaultParams: {name}DefaultParams,
  bodyComponent: {Name}ReportBody,
  legacyHref: '/reportes/{name}',
  permissionSlug: 'reporte-{name}'
}
```

---

## 레이아웃 구조

```
┌───────────────────────────────────────────────────────────────┐
│ Topbar 56px: 제목 | Sucursal · 검색 · 날짜범위 | 액션버튼     │
├───────────────────────────────────────────────────────────────┤
│ KPI Strip 80px: 4~5개 KPI 카드 (delta % 표시)                 │
├───────────────────────────────────────────────────────────────┤
│ Primary Area: 보고서별 특화 시각화                             │
│   - 카드 그리드 (vendedor)                                    │
│   - 시계열 차트 (ventas, gastos)                              │
│   - 막대 차트 (stocks, ingreso)                               │
│   - 테이블 (cheque-estado, reservado, alertas)                │
├─────────────── (선택) Detail 패널 ─────────────────────────────┤
│ Detail: 클릭 시 하단 확장 — 탭(trend / mix / ventas)           │
└───────────────────────────────────────────────────────────────┘
```

---

## Pool 안전 원칙

1. **raw SQL + QueryTypes.SELECT** — ORM hydration 오버헤드 제거
2. **메인 엔드포인트 3회 이내** — KPI, 목록, 스파크를 하나의 CTE로 묶거나 최대 3 query
3. **lazy 탭 데이터** — Detail 탭은 선택 시에만 별도 엔드포인트 호출
4. **프론트 캐시 5분** — `useCockpitCache`로 동일 요청 중복 제거
5. **측정 스크립트** — `scripts/measure-cockpit-pool.sh`로 peak connection 수 검증

---

## 신규 보고서 추가 체크리스트

- [ ] `api-ventago/src/app/reports/reports{Name}Cockpit.service.ts` 생성
- [ ] `reports.module.ts`에 서비스 등록
- [ ] `reports.controller.ts`에 `@Get('{name}-cockpit')` 엔드포인트 추가
- [ ] `ventago-app/src/views/reports/{name}/hooks/use{Name}Cockpit.tsx` 생성
- [ ] `ventago-app/src/views/reports/{name}/{Name}CockpitBody.tsx` 생성
- [ ] `registry.ts`에 entry 추가 (lazy import + REPORTS_REGISTRY)
- [ ] ESLint 통과 확인 (`npx tsc --noEmit`)
- [ ] pool 측정 (`bash scripts/measure-cockpit-pool.sh`)

---

## 현재 구현된 16개 보고서

| slug | 서비스 | 훅 | Body |
|------|--------|-----|------|
| vendedor | reportsVendedorCockpit | useVendedorCockpit | VendedorCockpitBody |
| sales | reportsSalesCockpit | useSalesCockpit | SalesCockpitBody |
| products | reportsProductsCockpit | useProductCockpit | ProductCockpitBody |
| facturacion | reportsFacturacionCockpit | useFacturacionCockpit | FacturacionCockpitBody |
| gastos | reportsGastoCockpit | useGastoCockpit | GastoCockpitBody |
| cheque-estado | reportsChequeEstadoCockpit | useChequeEstadoCockpit | ChequeEstadoCockpitBody |
| stocks | reportsStocksCockpit | useStocksCockpit | StocksCockpitBody |
| corregido | reportsCorregidoCockpit | useCorregidoCockpit | CorregidoCockpitBody |
| movidos | reportsMovidosCockpit | useMovidosCockpit | MovidosCockpitBody |
| fallados | reportsFalladosCockpit | useFalladosCockpit | FalladosCockpitBody |
| ingreso | reportsIngresoCockpit | useIngresoCockpit | IngresoCockpitBody |
| clientes-credito | reportsClientesCreditoCockpit | useClientesCreditoCockpit | ClientesCreditoCockpitBody |
| breve-venta | reportsBreveVentaCockpit | useBreveVentaCockpit | BreveVentaCockpitBody |
| reservado | reportsReservadoCockpit | useReservadoCockpit | ReservadoCockpitBody |
| alertas | reportsAlertasCockpit | useAlertasCockpit | AlertasCockpitBody |
| categoria-color-pivot | reportsCategoryColorPivot | (레거시) | CategoryColorPivotBody |

---

## 롤백 플랜

`/reportes-v2` 경로만 비활성화하면 즉시 Phase 8 레거시 셸로 복귀 가능.
레거시 훅(`useVendedorReport`, `useSalesReport` 등)은 삭제하지 않고 보존됨.
