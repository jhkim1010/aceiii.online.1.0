# Phase 6: Reportajes (15개 보고서 시스템) - Research

**Researched:** 2026-04-06
**Domain:** NestJS reports module + Next.js report views — query patterns, Excel export, navigation seed
**Confidence:** HIGH (모든 핵심 소스 직접 확인)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- 기존 보고서 패턴 따름: Frontend Hook → Backend Service → Excel Export
- 백엔드: `api-ventago/src/app/reports/` 모듈에 서비스 추가
- 프론트엔드: `ventago-app/src/views/reports/` 에 뷰 추가, `ventago-app/src/pages/reportes/` 에 페이지 추가
- 모든 보고서는 QuerysDto 패턴 사용 (startDate, endDate, filter, branchId 등)
- Wave 1: Vendedor, Gasto, Fallados, Corregido + 보고서 허브 페이지 (기존 데이터만)
- Wave 2: Breve Venta, Facturacion, Clientes Credito
- Wave 3: Ingreso Deposito, Movidos, Reservado
- Wave 4: Alertas, Cheque Estado + 대시보드 통합
- 공통: 기간별/지점별 필터링, Excel 내보내기, 텍스트 검색, 0.5초 debounce
- UI: CardFilter(showFilterButton=false), FullTable, 검색 input을 actions에 배치
- /reportes/ 허브 페이지: 15개 링크 그리드

### Claude's Discretion
- 각 보고서의 세부 테이블 컬럼 구성
- Alertas 보고서의 알림 조건 (재고 부족 기준값 등)
- Cheque Estado 모델 설계 (필요 시)
- 대시보드 차트 종류 및 배치

### Deferred Ideas (OUT OF SCOPE)
- 보고서 PDF 내보내기 (현재는 Excel만)
- 보고서 자동 이메일 발송 (스케줄링)
- 보고서 커스텀 템플릿
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| FEAT-05 | Reportajes — 15개 보고서 시스템 (Ventas✅, Items✅, StockRpt✅, Vendedor, Gasto, Fallados, Corregido, Breve Venta, Facturacion, Clientes Credito, Ingreso Deposito, Movidos, Reservado, Alertas, Cheque Estado) | 기존 3개 보고서 패턴 완전 확인. 12개 신규 보고서에 필요한 모든 데이터 모델 존재 확인 (Cheque Estado 제외). 정확한 구현 패턴 도출. |
</phase_requirements>

---

## Summary

기존 보고서 시스템(Ventas, Items/Productos, StockRpt Gen)은 `api-ventago/src/app/reports/` 모듈에 완전히 구현되어 있다. 패턴은 명확하고 일관적이다: `QuerysDto` → `Service.getReportXData()` → `Service.generalReport()` → `ExcelService.generateExcelReport()`. 12개 신규 보고서 중 11개는 기존 모델(Sale, Expenses, StoreClient, SuspendedSale, Stocks, Movements, BoxOperation)만으로 구현 가능하다. Cheque Estado만 새 모델이 필요하다.

네비게이션은 DB 기반 동적 구조다. `modules.seed.ts`의 `reportes` appSlug 아래에 새 모듈을 추가하면 사이드바에 자동 등록된다. 현재 seed에 Gastos와 Cuentas가 이미 등록되어 있어 Wave 1-2 보고서 일부는 URL만 추가하면 된다.

프론트엔드는 Hook → View → Page의 3계층 구조다. 각 보고서는 `useXReport.tsx` 훅 → `XReport.tsx` 뷰 → `pages/reportes/x/index.tsx` 페이지 순으로 구현한다. `ProductFilterInput` + `RangeDate` 컴포넌트가 공통 필터 UI를 제공하며, `SalesReportTable` 패턴(CardHeader + DownloadExcel 버튼 + FullTable)이 각 보고서 테이블의 표준 구조다.

**Primary recommendation:** 기존 3개 보고서(reportsSales.service.ts, reportsProducts.service.ts, reportsStocks.service.ts)를 정확히 복제하는 방식으로 12개를 추가한다. ReportsModule의 providers/exports 배열에 서비스 등록, ReportsController에 엔드포인트 추가, QuerysDto 확장만 필요하다.

---

## Standard Stack

### Core (이미 설치됨 — 추가 설치 불필요)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| exceljs | (설치됨) | Excel 파일 생성 | ExcelService에서 사용 중 |
| sequelize-typescript | (설치됨) | ORM 쿼리 | 전체 프로젝트 표준 |
| @nestjs/common | 11.x | NestJS 기본 | 프로젝트 표준 |
| luxon | (설치됨) | 날짜 포맷 | 훅에서 사용 중 |
| @mui/x-data-grid | (설치됨) | 테이블 컴포넌트 | FullTable이 사용 |

### Installation
추가 패키지 설치 불필요. 모든 의존성이 이미 설치되어 있다.

---

## Architecture Patterns

### 백엔드 — 보고서 추가 패턴

**1단계: 서비스 파일 생성**

```
api-ventago/src/app/reports/
├── querys.dto.ts              ← 필요 시 필드 추가 (storeId, sellerId, status 등)
├── reports.controller.ts      ← GET + GET export 엔드포인트 추가
├── reports.module.ts          ← providers + exports 배열에 추가
├── reportsProducts.service.ts ← 기존 (Items 보고서)
├── reportsSales.service.ts    ← 기존 (Ventas 보고서)
├── reportsStocks.service.ts   ← 기존 (StockRpt 보고서)
├── reportsVendedor.service.ts ← 신규 (Wave 1)
├── reportsGasto.service.ts    ← 신규 (Wave 1)
├── reportsFallados.service.ts ← 신규 (Wave 1)
├── reportsCorregido.service.ts← 신규 (Wave 1)
└── ...
```

**2단계: 서비스 구조 (모든 보고서 동일)**

```typescript
// Source: api-ventago/src/app/reports/reportsSales.service.ts 패턴
@Injectable()
class ReportsXService {
  constructor(private readonly excelService: ExcelService) {}

  // Excel 헤더 정의 + excelService.generateExcelReport() 호출
  async generalReport(data: any): Promise<ArrayBuffer> {
    const header = [
      { header: '컬럼명', key: 'fieldKey', width: 20 },
      // ...
    ];
    return await this.excelService.generateExcelReport(header, data);
  }

  // Sequelize findAll + filter 적용 + map
  async getReportXData(filters: any) {
    const { filter, startDate, endDate, branchId, storeId } = filters;
    const where: any = {};
    // 필터 조건 추가
    if (startDate && endDate) where.createdAt = { [Op.between]: [startDate, endDate] };
    if (storeId) where.storeId = storeId;

    const results = await Model.findAll({ where, include: [...] });
    return results.map(r => ({ /* 매핑 */ }));
  }
}
```

**3단계: 컨트롤러 엔드포인트 패턴 (2개/보고서)**

```typescript
// Source: api-ventago/src/app/reports/reports.controller.ts 패턴
@Get('x-report')
async getXReport(@Query() query: QuerysDto) {
  const data = await this.reportsXService.getReportXData(query);
  return { data };
}

@Get('x-report-export')
async exportXReport(@Query() query: QuerysDto, @Res() res: Response) {
  const data = await this.reportsXService.getReportXData(query);
  const buffer = await this.reportsXService.generalReport(data);
  await this.excelService.download(res, 'x_report.xlsx', buffer);
}
```

**4단계: ReportsModule 등록**

```typescript
// Source: api-ventago/src/app/reports/reports.module.ts
@Module({
  imports: [ExcelModule],
  controllers: [ReportsController],
  providers: [
    ExcelService,
    ReportsScheduleService,
    ReportsProductsService,
    ReportsStocksService,
    ReportsSalesService,
    ReportsVendedorService,  // 추가
    // ...
  ],
  exports: [/* 필요한 것만 */],
})
```

### 프론트엔드 — 보고서 추가 패턴

**파일 구조**

```
ventago-app/src/
├── views/reports/
│   ├── sales/              ← 기존 (Ventas)
│   ├── products/           ← 기존 (Items)
│   ├── stocks/             ← 기존 (StockRpt)
│   ├── hub/                ← 신규 (허브 페이지)
│   ├── vendedor/           ← 신규 (Wave 1)
│   │   ├── VendedorReport.tsx
│   │   ├── components/
│   │   │   ├── DataConfig.tsx
│   │   │   └── VendedorReportTable.tsx
│   │   └── hooks/
│   │       └── useVendedorReport.tsx
│   └── ...
└── pages/reportes/
    ├── index.tsx           ← 신규 (허브 페이지, 15개 링크 그리드)
    ├── ventas/index.tsx    ← 기존
    ├── items/index.tsx     ← 기존
    ├── stocks/index.tsx    ← 기존
    ├── dashboards/index.tsx← 기존 (빈 페이지)
    ├── vendedor/index.tsx  ← 신규 (Wave 1)
    ├── gastos/index.tsx    ← 신규 (Wave 1, /reportes/gastos — /gastos와 별개)
    ├── fallados/index.tsx  ← 신규 (Wave 1)
    ├── corregido/index.tsx ← 신규 (Wave 1)
    ├── breve-venta/index.tsx ← 신규 (Wave 2)
    ├── facturacion/index.tsx ← 신규 (Wave 2)
    ├── clientes-credito/index.tsx ← 신규 (Wave 2)
    ├── ingreso/index.tsx   ← 신규 (Wave 3)
    ├── movidos/index.tsx   ← 신규 (Wave 3)
    ├── reservado/index.tsx ← 신규 (Wave 3)
    ├── alertas/index.tsx   ← 신규 (Wave 4)
    └── cheque-estado/index.tsx ← 신규 (Wave 4)
```

**훅 패턴 (모든 보고서 동일)**

```typescript
// Source: ventago-app/src/views/reports/sales/hooks/useSalesReport.tsx 패턴
const useXReport = () => {
  const today = DateTime.now();
  const paramsDefault = {
    startDate: today.startOf("month").toFormat('yyyy-MM-dd'),
    endDate: today.toFormat('yyyy-MM-dd'),
    filter: '',
  };
  const [data, setData] = useState<any[]>([]);
  const [params, setParams] = useState<any>(paramsDefault);
  const [loading, setLoading] = useState(false);

  const getData = useCallback(async () => {
    setLoading(true);
    try {
      const result: any = await apiConnector.get('/reports/x-report', params);
      setData(result.data);
    } catch (e) { console.log(e); }
    finally { setLoading(false); }
  }, [params]);

  const downloadExcel = async () => {
    const fileName = `x-report-${DateTime.now().toFormat('yyyyMMdd-HHmmss')}.xlsx`;
    await apiConnector.downloadFile('/reports/x-report-export', fileName, params);
  };

  return { data, getData, loading, params, setParams, downloadExcel };
};
```

**페이지 패턴 (pages/reportes/x/index.tsx)**

```typescript
// Source: ventago-app/src/pages/reportes/ventas/index.tsx 패턴
import WithAccess from "src/configs/withAccess";
import XReport from "src/views/reports/x/XReport";

const ReportX = () => (
  <WithAccess allowedApps={["reportes"]} allowedModules={["ver-reportes-de-x"]}>
    <XReport />
  </WithAccess>
);

export default ReportX;
```

### 네비게이션 seed 업데이트 패턴

```typescript
// Source: api-ventago/src/app/modules/seed/modules.seed.ts
// reportes appSlug 아래에 추가
{
  appSlug: 'reportes',
  modules: [
    { name: 'Dashboard', slug: 'dashboard-reportes', url: '/reportes/dashboards', isMain: true, ... },
    { name: 'Ventas', slug: 'ventas-reportes', url: '/reportes/ventas', ... },
    // 기존 항목들...
    // 신규 추가:
    { name: 'Vendedor', slug: 'vendedor-reportes', url: '/reportes/vendedor', icon: 'tabler:user', isMain: false },
    { name: 'Gasto', slug: 'gasto-reportes', url: '/reportes/gastos', icon: 'mdi:cash-minus', isMain: false },
    { name: 'Fallados', slug: 'fallados-reportes', url: '/reportes/fallados', icon: 'tabler:x', isMain: false },
    // ...
  ]
}
```

**중요:** seed는 `findOrCreate` + `update` 패턴이므로 재실행 시 기존 데이터를 덮어씀. `npm run seed` 또는 서버 시작 시 자동 실행.

### Anti-Patterns to Avoid

- **별도 모듈 생성 금지:** 새 보고서는 기존 `ReportsModule`에 서비스만 추가한다. 새 모듈/컨트롤러를 만들지 않는다.
- **직접 DB 쿼리 금지:** 모든 데이터는 Sequelize 모델을 통해 조회한다.
- **storeId 필터 누락 금지:** 멀티테넌트 구조상 모든 쿼리에 storeId 또는 branchId 필터를 적용한다.
- **QuerysDto 우회 금지:** 새 파라미터가 필요하면 `querys.dto.ts`에 `@IsOptional()` 필드를 추가한다.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Excel 파일 생성 | 직접 스프레드시트 | `ExcelService.generateExcelReport(headers, data)` | 이미 구현됨 |
| Excel 다운로드 응답 | `res.send(buffer)` 직접 | `ExcelService.download(res, filename, buffer)` | Content-Type/Header 처리 포함 |
| 파일 다운로드 (프론트) | 직접 Blob 처리 | `apiConnector.downloadFile(path, fileName, params)` | blob/URL 생성/click 처리 포함 |
| 날짜 포맷 | 직접 문자열 조작 | `DateTime.now().toFormat('yyyy-MM-dd')` (luxon) | 이미 사용 패턴 확립됨 |
| 지점 목록 선택 | 직접 API 호출 | `useBranch()` 훅 + `ProductFilterInput` 컴포넌트 | 기존 컴포넌트 재사용 |
| 날짜 범위 선택 | 직접 구현 | `RangeDate` 컴포넌트 | react-datepicker 래퍼 이미 구현됨 |
| 데이터 그리드 | 직접 테이블 | `FullTable` 컴포넌트 | esES locale, 서버 페이지네이션 포함 |

---

## Data Model Inventory (12개 신규 보고서)

### Wave 1 — 기존 데이터만 활용 (모델 변경 불필요)

#### Vendedor (판매원별 실적)
- **소스 모델:** `Sale` (sellerId FK → Users)
- **필터:** Sale.storeId, Sale.saleDate 범위, Sale.sellerId
- **집계:** GROUP BY sellerId → totalSales, totalAmount
- **include:** `Users as seller` (attributes: ['name'])
- **Sale.status 필터:** 정상 판매만 (Borrador, Facturado, Pendiente por pagar, Pagado)

#### Gasto (비용 보고서)
- **소스 모델:** `Expenses` (amount, description, date, userId, branchId, storeId)
- **include:** `Users` (name), `ExpensesSubcategories` → `ExpensesCategories` (이름)
- **필터:** Expenses.storeId, Expenses.date 범위
- **주의:** Expenses.date는 Date 타입 (saleDate가 아님)

#### Fallados (취소/실패 판매)
- **소스 모델:** `Sale` with `status = SaleStatus.NULLIFIED` (`'Anulado'`)
- **include:** `Clients as client`, `Users as seller`, `SalePaymentMethod`
- **Sale enum 값:** `SaleStatus.NULLIFIED = 'Anulado'`
- **필터:** Sale.storeId, Sale.saleDate 범위 + `where.status = 'Anulado'`

#### Corregido (수정 판매)
- **소스 모델:** `Sale` with `status = SaleStatus.NULLIFICATION` (`'Anulación'`)
- **Sale enum 값:** `SaleStatus.NULLIFICATION = 'Anulación'`
- **nullifiedSaleId 필드:** 원본 판매 ID 참조 가능 (원본 연결 표시에 활용)
- **필터:** Sale.storeId, Sale.saleDate 범위 + `where.status = 'Anulación'`

### Wave 2 — 매출 데이터 확장 집계

#### Breve Venta (간략 매출 요약)
- **소스 모델:** `Sale` (Facturado, Pagado, Pendiente por pagar 상태)
- **집계 방식:** Sequelize로 날짜별/시간대별 GROUP BY 또는 JS에서 집계
- **권장:** JS 집계 (기존 패턴과 일관성)

#### Facturacion (청구서 현황)
- **소스 모델:** `Sale` with `status = SaleStatus.INVOICED` (`'Facturado'`)
- **include:** `Clients as client`, `Users as seller`, `SalePaymentMethod`

#### Clientes Credito (고객 외상)
- **소스 모델:** `StoreClient` (balance, creditLimit, isActive)
  - **경로:** `api-ventago/src/app/shared/store-clients/store-clients.model.ts`
  - **storeId 필터 필수** (데이터 격리 핵심)
- **include:** `GlobalClient` (fullname, document, phone)
  - **경로:** `api-ventago/src/app/shared/global-clients/global-clients.model.ts`
- **필터 조건:** balance > 0 (외상 잔액이 있는 고객만)
- **주의:** `Clients` 모델이 아닌 `StoreClient` + `GlobalClient` 모델 사용

### Wave 3 — 재고/보류 데이터

#### Ingreso Deposito (입고/입금 내역)
- **소스 모델 1 (재고 입고):** `Stocks` (stock > 0인 레코드) → `ProductBranch` → `Product`
- **소스 모델 2 (입금):** `BoxOperation` (type = 'ingreso')
  - **경로:** `api-ventago/src/app/box-operation/box-operation.model.ts`
  - **include:** `Users`, `CashRegister`
- **권장:** 두 소스를 통합하거나 탭으로 분리

#### Movidos (재고 이동)
- **소스 모델:** `Stocks` (모든 레코드 — 양수=입고, 음수=출고)
  - `stock > 0`: INCOME (입고)
  - `stock < 0`: OUTFLOW/판매에 의한 출고
  - **경로:** `api-ventago/src/app/stocks/stocks.model.ts`
- **include:** `ProductBranch` → `Product` (sku, name) + `Branch` (name)
- **날짜 필터:** `Stocks.createdAt`

#### Reservado (보류 판매)
- **소스 모델:** `SuspendedSale`
  - **경로:** `api-ventago/src/app/suspended-sales/suspended-sales.model.ts`
  - **tableName:** `ventas_suspendidas`
- **include:** `Clients as client` (fullname), `Users as user` (name)
- **필터:** SuspendedSale.storeId, SuspendedSale.saleDate 범위
- **주의:** `underscored: true` 설정. Item FK는 `venta_suspendida_id`

### Wave 4 — 신규 로직

#### Alertas (재고 부족 알림)
- **소스 모델:** `ProductBranch` + `Stocks` (집계)
- **로직:** 상품별 현재 재고(SReal) < 임계값 → 알림 생성
- **임계값:** Claude's Discretion (예: SReal <= 0 또는 SReal <= 최소재고 설정값)
- **기존 참조:** `reportsStocks.service.ts`의 SReal 계산 로직 재활용

#### Cheque Estado (수표/결제 상태)
- **현황:** 기존 모델 없음. `PaymentMethod` 모델은 방법 종류만 저장, 수표 추적 없음
- **방법 1 (신규 모델):** `ChequePayment` 모델 생성 (금액, 발행인, 만기일, 상태 등)
- **방법 2 (SalePaymentMethod 확장):** 기존 결제 방법 데이터에서 'cheque' slug 필터링
- **권장 (Wave 4 진입 시 확정):** PaymentMethod slug로 'cheque' 결제만 조회하는 방법부터 시도

---

## Sale Status Enum (확인됨)

```typescript
// Source: api-ventago/src/app/sales/sales.model.ts
export enum SaleStatus {
  DRAFT = 'Borrador',
  INVOICED = 'Facturado',
  PENDING_PAYMENT = 'Pendiente por pagar',
  PAID = 'Pagado',
  NULLIFIED = 'Anulado',       // Fallados 보고서
  NULLIFICATION = 'Anulación', // Corregido 보고서
}
```

---

## QuerysDto Extension (필요 시)

현재 `QuerysDto`에 없는 필드 중 신규 보고서에 필요한 것:

```typescript
// 추가 필요 필드 (querys.dto.ts에 추가)
@IsOptional()
@IsString()
status?: string;  // Fallados/Corregido/Facturacion용 (이미 reportsSales.service에서 사용 중)

@IsOptional()
@Type(() => Number)
@IsNumber()
storeId?: number; // 일부 보고서는 storeId 직접 사용
```

**참고:** `storeId`는 현재 QuerysDto에 없지만 `reportsSales.service.ts`에서 `filters.storeId`로 이미 사용 중. QuerysDto에 추가 필요.

---

## Navigation Seed Analysis

현재 `reportes` appSlug 모듈 목록:

| slug | name | url | 상태 |
|------|------|-----|------|
| dashboard-reportes | Dashboard | /reportes/dashboards | 기존 (빈 페이지) |
| ventas-reportes | Ventas | /reportes/ventas | 기존 (완료) |
| gastos-reportes | Gastos | /reportes/gastos | 기존 seed (페이지 미구현) |
| stocks-reportes | Stocks | /reportes/stocks | 기존 (완료) |
| cuentas-reportes | Cuentas | /reportes/cuentas | 기존 seed (페이지 미구현) |

Wave 1에서 추가할 slug: `vendedor-reportes`, `gasto-reportes-rpt`(또는 기존 gastos-reportes URL 활용), `fallados-reportes`, `corregido-reportes`

**중요:** `/gastos`는 `hiddenModuleUrls`에 포함되어 사이드바에서 숨겨짐. 보고서용 가스토는 `/reportes/gastos` 경로 사용. 기존 seed의 `gastos-reportes` slug가 이미 `/reportes/gastos`를 등록했으므로 페이지(`pages/reportes/gastos/index.tsx`)만 구현하면 된다.

---

## Common Pitfalls

### Pitfall 1: storeId 미필터링
**What goes wrong:** 멀티테넌트 구조에서 storeId 없이 전체 데이터 반환
**Why it happens:** 기존 코드 중 일부가 storeId를 쿼리에 포함하지 않음
**How to avoid:** 모든 service.getReport*() 메서드에 `if (storeId) where.storeId = storeId;` 명시
**Warning signs:** 다른 매장 데이터가 보고서에 표시됨

### Pitfall 2: QuerysDto에 없는 파라미터 사용
**What goes wrong:** `@Query() query: QuerysDto`에서 새 파라미터가 undefined 반환
**Why it happens:** class-validator의 타입 검증이 미선언 필드를 무시
**How to avoid:** `querys.dto.ts`에 `@IsOptional()` 필드 추가 후 사용
**Warning signs:** 필터가 작동하지 않음

### Pitfall 3: Sequelize `underscored: true`와 직접 SQL 혼용
**What goes wrong:** Stocks 또는 SuspendedSale 쿼리 시 컬럼명 불일치
**Why it happens:** `ventas_suspendidas` 테이블은 `underscored: true`로 설정됨
**How to avoid:** 직접 SQL 대신 항상 Sequelize 모델 사용. 불가피하면 snake_case 사용

### Pitfall 4: `Clients` 모델과 `GlobalClient/StoreClient` 혼동
**What goes wrong:** Clientes Credito 보고서에서 잘못된 모델 사용
**Why it happens:** 두 가지 고객 모델 존재 — 구형 `Clients`, 신형 `GlobalClient+StoreClient`
**How to avoid:** balance/creditLimit 데이터는 `StoreClient` 모델에만 있음. `StoreClient.include(GlobalClient)` 패턴 사용

### Pitfall 5: ProductBranch 없이 Stocks 직접 조회
**What goes wrong:** 상품 정보 없이 재고 수치만 반환
**Why it happens:** `Stocks`는 `productBranchId`만 가짐, 상품명 없음
**How to avoid:** `Stocks.include(ProductBranch.include(Product, Branch))` 체인 필요
**참조:** `reportsStocks.service.ts`의 기존 조회 패턴

### Pitfall 6: ESLint newline-before-return / lines-around-comment
**What goes wrong:** 빌드 실패 (Warning이 Error로 처리됨)
**Why it happens:** 이 프로젝트의 ESLint 설정
**How to avoid:** `return` 문 위 빈 줄, `//` 주석 위 빈 줄 필수

---

## Code Examples

### Backend Service 기본 구조 (Vendedor 예시)

```typescript
// Source: reportsSales.service.ts 패턴 기반

import { Injectable } from "@nestjs/common";
import { Op } from "sequelize";
import ExcelService from "src/common/excel/excel.service";
import { Sale, SaleStatus } from "src/app/sales/sales.model";
import { Users } from "src/app/users/users.model";

@Injectable()
class ReportsVendedorService {
  constructor(private readonly excelService: ExcelService) {}

  async generalReport(data: any): Promise<ArrayBuffer> {
    const header = [
      { header: 'Vendedor', key: 'sellerName', width: 25 },
      { header: 'Total Ventas', key: 'totalSales', width: 15 },
      { header: 'Total Monto', key: 'totalAmount', width: 15 },
    ];

    return await this.excelService.generateExcelReport(header, data);
  }

  async getReportVendedorData(filters: any) {
    const { filter, startDate, endDate, storeId, branchId } = filters;
    const where: any = {
      status: { [Op.in]: [SaleStatus.INVOICED, SaleStatus.PAID, SaleStatus.PENDING_PAYMENT] }
    };

    if (startDate && endDate) where.saleDate = { [Op.between]: [startDate, endDate] };
    if (storeId) where.storeId = storeId;

    const sales = await Sale.findAll({
      where,
      include: [{ model: Users, as: 'seller', attributes: ['name'] }],
    });

    // JS에서 sellerId별 집계
    const sellerMap: Record<number, { sellerName: string; totalSales: number; totalAmount: number }> = {};
    for (const sale of sales) {
      const id = sale.sellerId ?? 0;
      if (!sellerMap[id]) sellerMap[id] = { sellerName: (sale as any).seller?.name ?? 'Sin asignar', totalSales: 0, totalAmount: 0 };
      sellerMap[id].totalSales += 1;
      sellerMap[id].totalAmount += sale.totalAmount ?? 0;
    }

    return Object.values(sellerMap).sort((a, b) => b.totalAmount - a.totalAmount);
  }
}

export default ReportsVendedorService;
```

### StoreClient + GlobalClient 조인 (Clientes Credito)

```typescript
// Source: store-clients.model.ts + global-clients.model.ts 기반
import { StoreClient } from "src/app/shared/store-clients/store-clients.model";
import { GlobalClient } from "src/app/shared/global-clients/global-clients.model";
import { Op } from "sequelize";

async getReportClientesCreditoData(filters: any) {
  const { storeId } = filters;
  const where: any = {
    storeId,
    balance: { [Op.gt]: 0 }
  };

  const storeClients = await StoreClient.findAll({
    where,
    include: [{ model: GlobalClient, attributes: ['fullname', 'document', 'phone'] }],
  });

  return storeClients.map((sc: any) => ({
    id: sc.id,
    fullname: sc.globalClient?.fullname ?? '',
    document: sc.globalClient?.document ?? '',
    phone: sc.globalClient?.phone ?? '',
    balance: sc.balance,
    creditLimit: sc.creditLimit,
  }));
}
```

### ExcelService 사용 (확인됨)

```typescript
// Source: api-ventago/src/common/excel/excel.service.ts
// exceljs Workbook + Worksheet 패턴
async generateExcelReport(headers: any[], data: any[]): Promise<ArrayBuffer> {
  // headers: [{ header: '표시명', key: 'dataKey', width: 20 }, ...]
  // data: 각 행의 객체 배열 (key가 header의 key와 매칭)
}

async download(res: Response, filename: string, buffer: ArrayBuffer): Promise<void> {
  // Content-Disposition + application/vnd.openxmlformats-officedocument.spreadsheetml.sheet 헤더 설정
}
```

### 프론트엔드 — 보고서 허브 페이지 패턴

```typescript
// pages/reportes/index.tsx
// 15개 보고서 링크를 MUI Grid로 배치
import { Grid, Card, CardContent, Typography, Button } from '@mui/material';
import { Icon } from '@iconify/react';
import { useRouter } from 'next/router';

const REPORTS = [
  { name: 'Ventas', url: '/reportes/ventas', icon: 'mdi:sale-outline' },
  { name: 'Items', url: '/reportes/items', icon: 'ant-design:product-outlined' },
  // ... 15개
];

// Grid xs=12 sm=6 md=4 lg=2.4 (5열)로 5x3 배치
```

---

## Environment Availability

Step 2.6: SKIPPED — 이 phase는 기존 프로젝트 내 코드/서비스 추가이며, 새로운 외부 의존성 없음. 모든 필요 라이브러리(exceljs, sequelize, MUI 등)가 이미 설치되어 있음.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Jest (api-ventago/test/) |
| Config file | api-ventago/package.json `jest` 설정 |
| Quick run command | `cd api-ventago && npm test` |
| Full suite command | `cd api-ventago && npm run test:cov` |

**현황:** 프로젝트에 기존 unit test 파일 없음 (`test/app.e2e-spec.ts`만 존재). 프론트엔드에도 테스트 설정 없음. 이 phase에서는 수동 검증(브라우저 확인 + Excel 다운로드)이 주 검증 방법.

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| FEAT-05 | 15개 보고서 API 응답 | smoke | `curl localhost:5002/api/reports/vendedor-report?startDate=2026-01-01&endDate=2026-04-06&storeId=1` | ❌ Wave 0 불필요 (수동) |
| FEAT-05 | Excel 다운로드 정상 | manual | 브라우저에서 직접 확인 | ❌ manual-only |
| FEAT-05 | 지점별 필터 동작 | smoke | API 파라미터 변경으로 확인 | ❌ manual-only |

### Wave 0 Gaps
기존 테스트 인프라가 없으므로 새 테스트 파일 생성은 이 phase 범위 밖. 각 Wave 완료 시 브라우저 수동 검증으로 대체.

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| 보고서 허브 없음 | /reportes/ 페이지에 15개 링크 그리드 | Phase 6에서 신규 | 사용자 접근성 향상 |
| Clients 모델 단일 | GlobalClient + StoreClient 분리 | 기존 아키텍처 | Clientes Credito는 StoreClient 사용 필수 |
| hiddenModuleUrls '/gastos' | 보고서 Gastos는 /reportes/gastos | 기존 설정 | seed slug 'gastos-reportes' 재사용 가능 |

---

## Open Questions

1. **Cheque Estado 구현 방법**
   - What we know: 기존 PaymentMethod 모델은 방법 이름(title, slug)만 저장. 개별 수표 추적 테이블 없음.
   - What's unclear: 'cheque' slug PaymentMethod로 결제된 SalePaymentMethod 레코드를 조회하는 것만으로 충분한가, 아니면 수표 번호/만기일 등 별도 모델이 필요한가?
   - Recommendation: Wave 4 진입 시 기존 sale_payment_methods 테이블에 'cheque' slug 데이터가 있는지 먼저 확인. 없으면 Wave 4에서 ChequePayment 모델 신규 설계.

2. **Ingreso Deposito 통합 방식**
   - What we know: 재고 입고(Stocks, stock > 0)와 현금 입금(BoxOperation, type='ingreso')은 별개 모델.
   - What's unclear: 하나의 보고서에 두 데이터를 통합할지, 탭으로 분리할지.
   - Recommendation: Wave 3 진입 시 사용자 요구사항 확인. 기본은 탭 분리가 단순.

3. **Breve Venta 집계 단위**
   - What we know: '간략 매출 요약' — 일별/시간대별 집계.
   - What's unclear: 집계 단위(시간대별 vs 일별 vs 주별)와 표시 방식(차트 vs 테이블).
   - Recommendation: 일별 집계 테이블로 시작 (기존 패턴과 일관성).

---

## Sources

### Primary (HIGH confidence — 직접 파일 확인)
- `api-ventago/src/app/reports/reportsSales.service.ts` — 보고서 서비스 패턴 (쿼리, 매핑, Excel)
- `api-ventago/src/app/reports/reports.controller.ts` — 엔드포인트 패턴 (GET + GET-export)
- `api-ventago/src/app/reports/reports.module.ts` — 모듈 등록 패턴
- `api-ventago/src/app/reports/querys.dto.ts` — 파라미터 DTO (branchId, filter, startDate, endDate, isParent, productId, saleId, priceTypeId)
- `api-ventago/src/app/sales/sales.model.ts` — SaleStatus enum (Borrador, Facturado, Pendiente por pagar, Pagado, Anulado, Anulación)
- `api-ventago/src/app/expenses/expenses.model.ts` — Expenses 모델 (amount, description, date, userId, branchId, storeId)
- `api-ventago/src/app/suspended-sales/suspended-sales.model.ts` — SuspendedSale 모델 (ventas_suspendidas 테이블)
- `api-ventago/src/app/stocks/stocks.model.ts` — Stocks 모델 (stock, productBranchId, createdAt)
- `api-ventago/src/app/shared/store-clients/store-clients.model.ts` — StoreClient 모델 (balance, creditLimit, storeId, globalClientId)
- `api-ventago/src/app/shared/global-clients/global-clients.model.ts` — GlobalClient 모델 (fullname, document, phone)
- `api-ventago/src/app/box-operation/box-operation.model.ts` — BoxOperation 모델 (type: 'gasto'|'venta'|'ingreso'|'retiro')
- `api-ventago/src/app/movements/movements.model.ts` — Movements 모델 (type: SELL|INCOME|OUTFLOW|SPENDING)
- `api-ventago/src/common/excel/excel.service.ts` — ExcelService (generateExcelReport, download)
- `api-ventago/src/app/modules/seed/modules.seed.ts` — 네비게이션 seed (reportes appSlug 모듈 목록)
- `ventago-app/src/views/reports/sales/hooks/useSalesReport.tsx` — 프론트엔드 훅 패턴
- `ventago-app/src/views/reports/sales/SalesReport.tsx` — 프론트엔드 뷰 패턴
- `ventago-app/src/navigation/vertical/index.ts` — 동적 네비게이션 (DB 기반, hiddenModuleUrls)
- `ventago-app/src/components/cards/CardFilter.tsx` — CardFilter 컴포넌트 (showFilterButton prop)
- `ventago-app/src/components/table/FullTable.tsx` — FullTable 컴포넌트 (DataGrid 래퍼)
- `ventago-app/src/views/reports/products/components/ProductFilterInput.tsx` — 지점 선택 + 텍스트 필터 컴포넌트
- `ventago-app/src/views/reports/products/components/RangeDate.tsx` — 날짜 범위 선택 컴포넌트

---

## Metadata

**Confidence breakdown:**
- Standard Stack: HIGH — 모든 파일 직접 확인
- Architecture: HIGH — 기존 보고서 3개의 완전한 구현 패턴 확인
- Data Models: HIGH — 필요한 모든 모델 파일 직접 확인 (Cheque Estado 제외 LOW)
- Pitfalls: HIGH — 코드에서 직접 발견된 패턴

**Research date:** 2026-04-06
**Valid until:** 2026-07-06 (stable stack — 90일)
