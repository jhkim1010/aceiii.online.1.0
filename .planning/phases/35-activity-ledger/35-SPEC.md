# Phase 35: Activity Ledger — Movidos/Fallados Trace in ventaVista

**Brainstormed:** 2026-05-22
**Status:** Ready for planning
**Mode:** Interactive brainstorming (superpowers:brainstorming skill)
**Author:** junghokim10@gmail.com

---

## Phase Boundary

### 스코프

`venta nueva` 화면에서 special mode (`movidos`, `fallados`) 로 등록되는 활동은 현재 `stocks(type='adjust')` 행만 생성하고 `sales` 에는 흔적이 없음. 이 phase 는 이 활동들을 sales 테이블에 1급 시민으로 등록하고, 매장 운영자가 `ventaVista`(SalesListView) 에서 통합 거래 원장(unified transaction ledger) 으로 확인할 수 있게 함.

**포함**:

1. `sales.activity_type` 컬럼 신설 (`'sale' | 'movido' | 'fallado'`)
2. `sales.origin_branch_id`, `sales.target_branch_id` FK 신설
3. `StockService.createStockMovement` 를 단일 트랜잭션으로 재구성 (sales + sale_items + stocks 동시 INSERT)
4. 모든 기존 sales 쿼리에 default filter `WHERE activity_type='sale'` 적용
5. ventaVista 의 KPI strip 을 **per-sucursal Resumen 테이블** 로 교체
6. ventaVista 리스트 영역의 movido/fallado 행 시각 구분 (chip + tint + dual-purpose Cliente 컬럼)
7. 신규 CASL permission `stock.movement` + branch 제약
8. Stock Cockpit 컬럼 재설계 (MOV+/MOV−/FAL 신설, OFFSET 명확화) — **Phase B 로 분리**
9. Backfill SQL 스크립트 작성 (운영 실행은 별도 PR/승인)

**제외 (다른 phase)**:

- devolución (`Anulación`) 의 sale_type 재분류 — 기존 `status` 기반 로직 유지
- ajustes manuales (수동 재고 보정) UI — 별도 phase 후보
- 통계/리포트 화면의 movido 별도 집계 — Phase A 에서는 ventaVista 만, 다른 리포트는 후속
- 매장간 (다른 store) 이동 — 본 phase 는 같은 store 내 다지점 이동만
- **Stock Cockpit MOV+ 셀 hover tooltip (최근 5건 표시)** — Phase 35-A 에서 DEFERRED (별도 endpoint 필요, Phase 35-C 또는 36 후보)

### 의존

- 기존 `stocks` 테이블 + `StockService.createStockMovement` ([api-ventago/src/app/stocks/stocks.service.ts:90](api-ventago/src/app/stocks/stocks.service.ts#L90))
- 기존 `sales`, `sale_items`, `branches` 테이블
- Phase 33 (Permissions v2) — CASL 권한 시스템 (`stock.movement` 신규 permission)
- Phase 32 (stocks-historial-drawer) — 동일 데이터 source 를 다른 각도로 보여줌. 충돌 없음, 보완 관계

### 분할

- **Phase 35-A**: Schema + 백엔드 + ventaVista UI (Resumen 테이블 + 리스트 + 필터 + 권한) — 핵심 가치
- **Phase 35-B**: Stock Cockpit 컬럼 재설계 (MOV+/MOV−/FAL/OFFSET 분리) — 추가 가시성

---

## Implementation Decisions

### D-01 데이터 모델: `activity_type` 컬럼 추가 (sales 테이블 확장)

**선택**: 기존 `sales` 테이블에 `activity_type ENUM('sale','movido','fallado') DEFAULT 'sale'` 추가.

```sql
ALTER TABLE sales
  ADD COLUMN activity_type VARCHAR(16) NOT NULL DEFAULT 'sale'
    CHECK (activity_type IN ('sale','movido','fallado')),
  ADD COLUMN origin_branch_id  INTEGER NULL REFERENCES branches(id),
  ADD COLUMN target_branch_id  INTEGER NULL REFERENCES branches(id);

CREATE INDEX idx_sales_activity_date ON sales(activity_type, sale_date);
CREATE INDEX idx_sales_origin_branch ON sales(origin_branch_id)
  WHERE origin_branch_id IS NOT NULL;
CREATE INDEX idx_sales_target_branch ON sales(target_branch_id)
  WHERE target_branch_id IS NOT NULL;
```

**이유**:

- 기존 `SaleStatus` enum (`Pagado`/`Anulado`/`Anulación`) 이 이미 "비-판매 활동도 sales 테이블에 들어간다" 패턴을 정착시킴 — devolución 도 sales 행으로 처리됨
- 단일 쿼리 경로 → 정렬·페이지네이션·필터 무료
- ORM/Sequelize 매핑 단순 (별도 view 불필요)
- 향후 `ajuste_manual` 등 추가 시 enum 값만 늘리면 됨

**대안 (기각)**:

- **별도 `stock_transactions` 테이블 + DB view UNION**: 의미적 분리는 좋으나, view 페이지네이션·정렬이 무겁고 Sequelize view 매핑이 약함. 쓰기 경로 2개 유지 부담.
- **별도 테이블 + 프론트 머지**: cross-source 정렬·필터 UX 가 깨짐. 부적합.

**리스크**: 기존 sales 쿼리에 default filter `WHERE activity_type='sale'` 누락 시 매출 통계에 movido 가 섞임. → D-05 의 grep 감사 + lint rule 검토로 대응.

### D-02 백엔드 흐름: 단일 트랜잭션 sales+sale_items+stocks INSERT

**선택**: `StockService.createStockMovement()` 를 다음 순서로 재구성:

```typescript
// 단일 트랜잭션
const sale = await Sale.create({
  activityType: type,          // 'movido' | 'fallado'
  storeId,
  userId: currentUser.id,
  status: 'Pagado',
  totalAmount: 0,
  originBranchId,
  targetBranchId: type === 'movido' ? targetBranchId : null,
  saleDate: now,
  notes,
}, { transaction });

await SaleItem.bulkCreate(items.map(it => ({
  saleId: sale.id,
  productId: it.productId,
  quantity: it.quantity,
  unitPrice: 0,
  discount: 0,
})), { transaction });

// 기존 stocks INSERT (origin debit, target credit) — 변경 없음
await this.createStockRows(items, originBranchId, targetBranchId, type, transaction);

return { success: true, saleId: sale.id, type, itemCount, insertedRows };
```

**이유**:

- sales 가 "헤더", stocks 가 "원장(ledger)" 로 명확히 분리됨
- 단일 트랜잭션 → 부분 실패 시 자동 롤백
- 응답에 `saleId` 추가 → 프론트에서 즉시 상세 페이지 navigate 가능

### D-03 권한: CASL `stock.movement` + branch 제약

**선택**:

- 신규 permission `stock.movement` (Phase 33 RBAC 통합)
- 권한 보유 + `user.branchId === originBranchId OR user.branchId === targetBranchId` 인 경우만 등록 가능
- 매장 owner/admin role 은 전 지점 허용 (전역 권한)

**이유**:

- 다지점 이동은 매장 전체 재고 흐름에 영향 — 자유 접근 위험
- branch 제약은 "자기 매장 재고 일방 유출" 시나리오 차단

**구현**:
- NestJS guard 또는 `StockService.createStockMovement` 시작부 검증. 권한 실패 시 `ForbiddenException`.
- PermissionGuard 호환을 위해 controller 단의 `InjectBranchIdFromOriginGuard` 가 `body.branchId = body.originBranchId` 사전 주입 (Phase 35 Plan 02 Task 3).
- 마이그레이션 SQL 이 기존 사용자 자동 부여 (최근 90일 sale 활동 vendedor/encargado).

### D-04 sales 쿼리 default filter 강제

**선택**: 모든 기존 sales 조회 경로에 `WHERE activity_type='sale'` 추가.

**감사 대상**:

- `SalesService.findAll`, `findOne`, KPI/dashboard service 류
- `reportsStocksCockpit.service.ts` 등 sales JOIN raw SQL
- Sequelize scope 정의 시 default scope 검토
- **sales-create.service.ts L188, L379** 의 `lastSaleToday` 쿼리 (dailyNumber 계산) — 'order DESC + LIMIT 1' 패턴이므로 activityType='sale' 필터 필수. 누락 시 movido/fallado 가 dailyNumber 잠식.

**구현**:

```typescript
// sales.model.ts
@DefaultScope(() => ({
  where: { activityType: 'sale' },
}))
@Scopes(() => ({
  allActivities: { /* no where */ },
  movidos:  { where: { activityType: 'movido' } },
  fallados: { where: { activityType: 'fallado' } },
}))
```

ventaVista 백엔드 endpoint 만 `.unscoped()` 또는 `.scope('allActivities')` 사용. 그 외는 default scope 적용.

**리스크**: default scope 가 모든 곳에 자동 적용되어 의도치 않은 누락 가능. → 명시적 `WHERE` 절 추가가 더 안전할 수 있음. **PLAN 단계에서 명시적 WHERE 선택 결정 (RESOLVED — Plan 03 참조)**.

### D-05 ventaVista — KPI strip 을 per-sucursal Resumen 테이블로 교체

**선택**: 기존 `DailySalesStats.tsx` 의 KPI strip 을 다지점 매트릭스 테이블로 교체.

**컬럼**: `SUCURSAL · VENTAS (건·금액) · PRENDAS · DESC · MOV+ · MOV− · FAL · NETO`

```
┌──────────┬──────────┬─────────┬──────────┬──────┬──────┬─────┬──────┐
│ SUCURSAL │  VENTAS  │ PRENDAS │ DESC.    │ MOV+ │ MOV− │ FAL │ NETO │
├──────────┼──────────┼─────────┼──────────┼──────┼──────┼─────┼──────┤
│ JEFE     │ 12 · $4M │   30    │  -$120k  │ +5   │  -2  │  1  │  +3  │
│ SALA     │  8 · $2M │   24    │   -$80k  │ +2   │  -3  │  0  │  -1  │
├──────────┼──────────┼─────────┼──────────┼──────┼──────┼─────┼──────┤
│ Σ TOTAL  │ 20 · $6M │   54    │  -$200k  │ +7   │  -7  │  1  │   0  │
└──────────┴──────────┴─────────┴──────────┴──────┴──────┴─────┴──────┘
```

**동작**:

- VENTAS / PRENDAS / DESC: `activity_type='sale'` 만 집계 (Anulado 제외, 기존 로직 유지)
- MOV+: 그 지점이 `target_branch_id` 인 행의 prendas 합 (들어온 양)
- MOV−: 그 지점이 `origin_branch_id` 인 행의 prendas 합 (나간 양)
- FAL: `activity_type='fallado'` 행의 prendas 합 (그 지점이 origin)
- NETO: `MOV+ − MOV− − FAL` (지점 재고 순변동)
- 셀 내용: prendas 수만 (`+5`, `-2`) — 건수는 표시하지 않음

**다지점 vs 단일지점**:

- 사용자가 다지점 권한자: 모든 지점 행 + TOTAL
- 단일 지점 사용자: 자기 지점 1행만 (TOTAL 행 숨김)

**드릴다운**:

- **행 클릭** → 리스트 필터 chip `[JEFE ✕]` + URL `?branch=JEFE`
- **셀 클릭** → 다중 필터 `[JEFE ✕] [MOV+ ✕]` + URL `?branch=JEFE&type=movido&direction=in`
- 필터 chip 닫기 X 버튼으로 개별 제거

**검증 알람**: `Σ MOV+ === Σ MOV−` 여야 함 (내부 이동 합은 0). 불일치 시 TOTAL 행 셀에 ⚠ 아이콘 + tooltip "동일 store 내 이동인데 IN/OUT 합이 다릅니다 — 데이터 점검 필요".

### D-06 ventaVista — 리스트 영역의 movido/fallado 행 표시

**선택**:

**a. 기본 로드 상태**: 모든 활동 표시 (ventas + movidos + fallados 혼합)

**b. 행 구분**:

- type Chip 컬럼: `[VENTA]` (gray) / `[MOV]` (blue) / `[FAL]` (red)
- 행 배경 tint: sale=white / mov=`#E3F2FD` 미세 청색 / fal=`#FFEBEE` 미세 적색 (FullTable.getRowSx prop 으로 적용 — Plan 05 Task 2 에서 FullTable 확장)
- 좌측 4px colored border (chip 색과 동일)

**c. Cliente 컬럼 dual-purpose (Cliente/Ruta)**:

- sale 행: 기존 cliente 이름 (변경 없음)
- movido 행: `JEFE → SALA` (origin → target, 화살표 강조)
- fallado 행: `FAL · JEFE` (라벨 + origin)

**d. 의미 없는 컬럼**:

- movido/fallado 행에서 `Total`, `Descuento`, `Métodos de pago` 컬럼은 `—` 표시

**e. 필터 chip + URL query 동시 반영**:

- Resumen 행 클릭 → URL `?branch=JEFE&date=2026-05-22` + chip 표시
- chip X 클릭 → URL query 제거 → 필터 해제
- URL 직접 공유/북마크 가능

### D-07 DailySalesStats 로직 변경

**기존 코드** ([DailySalesStats.tsx:97-113](ventago-app/src/views/sales/list/components/DailySalesStats.tsx#L97)):

```typescript
const isVoid = status === 'Anulado'
if (isVoid) {
  voidSalesCount += 1
  return
}
validSalesCount += 1
totalAmount += sale.totalAmount || 0
sale.items?.forEach((item: any) => {
  totalItems += parseInt(item.quantity || 0)
})
```

**변경**:

```typescript
const isVoid = status === 'Anulado'
const isNonSale = sale.activityType !== 'sale'
if (isVoid) { voidSalesCount += 1; return }
if (isNonSale) {
  if (sale.activityType === 'movido') {
    if (sale.targetBranchId === branchId) movInPrendas += sumItems(sale)
    if (sale.originBranchId === branchId) movOutPrendas += sumItems(sale)
  }
  if (sale.activityType === 'fallado') falPrendas += sumItems(sale)
  return
}
// 기존 totalItems / totalAmount / ledger 로직 (sale 만)
```

→ KPI strip 의 `totalItems` (prendas 장수) 에 movido/fallado 가 섞이지 않음. 동시에 Resumen 테이블 의 MOV+/MOV−/FAL 셀 데이터 제공.

### D-08 Stock Cockpit 컬럼 재설계 (Phase 35-B)

**선택**: `[INGRESO · VENTA · MOV+ · MOV− · FAL · STOCK · OFFSET · % VENTA · RESERVADOS · HOY+ · HOY− · PRECIO]`

**수식**: `STOCK = INGRESO − VENTA + MOV+ − MOV− − FAL + OFFSET`

**OFFSET 의 새 역할**:

- 위 컴포넌트로 설명되지 않는 잔여 조정 (수동 ajustes, 시스템 보정 등)
- 정상 운영 시 항상 0 이 기대값
- 값이 0 이 아니면 빨간색 + tooltip "Ajuste manual o discrepancia — verificar"

**기간**: 사용자 선택 날짜 범위와 동일 (현재 INGRESO/VENTA 와 일관)

**상호작용**:

- 셀 hover → tooltip "JEFE←DEPOSITO: 2개 (2026-05-21) · ..." 최근 5건 — **DEFERRED (Phase 35-A 범위 외, 후속 phase 후보)**
- 셀 click → ventaVista navigate, `?product=X&type=movido&direction=in&date=...` — **Phase 35-A Plan 07 Task 2 에서 구현됨**

**구현 위치**: `ventago-app/src/views/reports/stocks/StocksCockpitBody.tsx` + 관련 백엔드 service.

### D-09 Backfill — 별도 승인 후 실행

**선택**: SQL 스크립트는 본 phase 에서 작성/커밋. 실제 운영 실행은 별도 PR + 사용자 검토.

**스크립트 위치**: `api-ventago/migrations/35-backfill-movidos-to-sales.sql`

**전략**:

```sql
-- 1. stocks(type='adjust', note LIKE 'movido(out%') 행을 (created_at, user_id, store_id) 기준 그룹화
-- 2. 각 그룹별 sales(activity_type='movido') 1행 + sale_items N행 INSERT
-- 3. note 파싱: 'movido(out→{branchId}): {notes}' 패턴에서 target_branchId 추출
-- 4. fallado 도 동일 패턴 (note LIKE 'fallado%')
-- 5. dry-run mode (BEGIN; ... ROLLBACK;) 로 COUNT 검증 후 운영 적용
```

**그룹화 정밀도 (INFO 2 응답)**:

`DATE_TRUNC('second', stocks.created_at)` 사용 — 동일 createStockMovement 호출이 1초 미만에 모든 stocks 행을 INSERT 완료한다는 가정.

**리스크**: 같은 초에 두 개의 독립 createStockMovement 호출이 우연히 같은 (origin, target, baseNote) 조합으로 발생하면 한 그룹으로 합쳐질 수 있음. 운영 빈도상 거의 발생 안 함이지만, 더 엄격한 정밀도 원하면 `DATE_TRUNC('millisecond', stocks.created_at)` 사용 가능.

본 phase 는 `DATE_TRUNC('second', ...)` 로 진행 (PG10 호환 + 충분 정밀도). 운영 backfill 시 위험 감지되면 millisecond 로 전환 가능.

**Dry-run 검증 SQL**:

```sql
BEGIN;
-- backfill INSERT 실행
SELECT activity_type, COUNT(*) FROM sales GROUP BY activity_type;
-- 기대: 신규 movido/fallado 행 수 == 원본 stocks 그룹 수
ROLLBACK;
```

**위험 처리**:

- note 파싱 실패 행은 별도 테이블 `backfill_failures` 에 기록, sales 미생성
- 실행 전 운영 DB 백업 필수
- PG10 호환성: `STRING_AGG`, `regexp_match` 등 사용 가능 (PG10+) — 신기능 회피

### D-10 sale_items.unit_price=0 의 통계 오염 방지

**선택**: 모든 매출 sum 쿼리는 `WHERE sales.activity_type='sale'` 로 차단되므로 sale_items 의 unit_price=0 행은 자동으로 제외됨.

**검증**: 기존 매출/평균/할인 집계 쿼리가 sale_items 단독으로 SUM 하는 곳이 있는지 grep. 있다면 sale_items → sales JOIN 으로 변경 필요.

### D-11 프론트 등록 흐름 변경 (ProductList.tsx)

**선택**: 기존 `handleSubmitSpecial` 로직은 유지. 응답에 `saleId` 가 추가되면 toast 에 "Ver detalle" 링크 추가 가능 (선택).

**Variant 확장 로직**: 변경 없음. 부모 SKU → 자식 variant 펼침이 그대로 작동.

---

## API Changes

### POST /stocks/movement (기존, 응답만 확장)

**Request** (기존 그대로):

```json
{
  "type": "movido",
  "storeId": 9,
  "originBranchId": 1,
  "targetBranchId": 2,
  "items": [{ "productId": 12345, "quantity": 2 }],
  "notes": "Movimiento entre sucursales"
}
```

**Response** (확장):

```json
{
  "success": true,
  "saleId": 78901,           // 신규
  "type": "movido",
  "itemCount": 1,
  "insertedRows": 2
}
```

### GET /sales (기존, query 확장)

**신규 query 파라미터**:

- `activityType=sale|movido|fallado|all` — default `sale`
- `originBranchId=N` — movido/fallado 출발 지점 필터
- `targetBranchId=N` — movido 도착 지점 필터
- `direction=in|out` — Resumen 셀 클릭 시 사용

**응답**: 기존 sales 응답 객체에 `activityType`, `originBranchId`, `targetBranchId`, `originBranch`, `targetBranch` (eager-loaded branch object) 추가.

### GET /sales/daily-stats (기존 또는 신규)

ventaVista Resumen 테이블 데이터 source. 응답:

```json
{
  "date": "2026-05-22",
  "perBranch": [
    {
      "branchId": 1,
      "branchName": "JEFE",
      "ventas": { "count": 12, "amount": 4000000 },
      "prendas": 30,
      "descuento": 120000,
      "movIn": 5,
      "movOut": 2,
      "fallados": 1,
      "neto": 3
    }
  ],
  "total": { "ventas": {...}, "prendas": 54, ... },
  "movBalance": { "in": 7, "out": 7, "balanced": true }
}
```

---

## UI/UX Specifications

### Resumen 테이블 (ventaVista 상단)

- **위치**: `SalesListView.tsx` 의 KPI strip 위치 (KpiCards 컴포넌트 교체)
- **컴포넌트**: 신규 `SalesResumenTable.tsx` (`ventago-app/src/views/sales/list/components/`)
- **반응형**: 모바일에서는 horizontal scroll (테이블 그대로) + 첫 컬럼 sticky
- **빈 상태**: 데이터 없을 때 "오늘 활동 없음" placeholder

### List 영역 (Resumen 아래)

- **컴포넌트**: 기존 `SalesListView.tsx` 의 AG Grid 또는 MUI DataGrid 확장
- **신규 컬럼**: `Tipo` (chip) — 가장 좌측 또는 Status 컬럼 옆
- **Cliente 컬럼 렌더러**: cell renderer 에서 activityType 분기

```typescript
const ClienteRouteCellRenderer = ({ data }) => {
  if (data.activityType === 'movido')
    return <Stack direction="row"><BranchChip name={data.originBranch.name} /><Icon icon="mdi:arrow-right" /><BranchChip name={data.targetBranch.name} /></Stack>;
  if (data.activityType === 'fallado')
    return <span>FAL · {data.originBranch.name}</span>;

  return <span>{data.client?.name ?? '—'}</span>;
};
```

### Stock Cockpit (Phase 35-B)

- **위치**: `/reportes/stocks` 의 컬럼 헤더 + cell renderer
- **신규 컬럼**: MOV+, MOV−, FAL — VENTA 와 STOCK 사이
- **OFFSET 시각**: 값 !== 0 시 빨간색 텍스트 + ⚠ 아이콘
- **Cell renderer**: hover tooltip (DEFERRED) + click navigate (Plan 07 Task 2 구현 — MUI Tooltip + Next router)

---

## Risks & Mitigations

| 리스크 | 영향 | 대응 |
|---|---|---|
| 기존 sales 쿼리에 activity_type 필터 누락 → 매출 통계에 movido 섞임 | High | grep audit + Sequelize default scope + 단위 테스트 (총매출 쿼리가 movido 행 무시하는지 검증) |
| `branch_id` 가 sales 에 없음 (CLAUDE.md 명시) → 다지점 집계 어떻게? | Med | Resumen 테이블은 `origin_branch_id` (movido/fallado) + `users.branch_id` (sale) 조합으로 집계. PLAN 에서 query 명세 확정 |
| Default scope 가 모든 곳에 자동 적용 → 의도치 않은 누락 | Med | scope 적용 vs 명시적 WHERE 절을 PLAN 단계에서 비교, 안전한 쪽 선택. → 명시적 WHERE 선택 (Plan 03) |
| 운영자 UX 변경 충격 (KPI strip → 테이블) | Low | Release note + 첫 로그인 시 changelog modal + 기존 KPI 정보는 Resumen 테이블 TOTAL 행에 모두 보존 |
| Backfill 실패로 일부 historical movido 누락 | Med | dry-run + COUNT 검증 + 운영 DB 백업 + 실패 행은 backfill_failures 테이블에 기록 |
| sale_items.unit_price=0 → 매출 평균 등 통계 왜곡 | Low | 매출 sum 쿼리 전수 감사. sale_items 단독 SUM 사용처 없으면 영향 0 |
| `stock.movement` 권한 default 가 admin only → 기존 사용자 갑자기 등록 불가 | Med | 마이그레이션: 매장 owner + 기존 movido 등록 이력이 있는 user 에게 권한 자동 부여 (Plan 02 SQL — 최근 90일 sale 활동 vendedor/encargado) |
| PermissionGuard 가 body.branchId 만 인식 → 비-privileged 사용자 false 403 | Med | controller 단 InjectBranchIdFromOriginGuard 가 body.branchId = body.originBranchId 사전 주입 (Plan 02 Task 3) |
| dailyNumber 잠식 (movido/fallado 가 sale 번호 차지) | Med | sales-create.service.ts L188/L379 의 lastSaleToday 쿼리에 activityType='sale' 필터 (Plan 03 Task 1 STEP B) |
| Backfill 그룹화 정밀도 (DATE_TRUNC second) | Low | D-09 노트 참조 — 운영 빈도상 충돌 거의 없음, 위험 감지 시 millisecond 로 전환 |

---

## UAT Criteria

### Phase 35-A 검증

- [ ] **U1**: 신규 movido 등록 → `sales` 에 activity_type='movido' 행 생성 + `sale_items` + `stocks` 모두 단일 트랜잭션으로 INSERT
- [ ] **U2**: 등록 후 ventaVista 새로고침 → 해당 movido 가 리스트에 표시 (chip `[MOV]`, blue tint, `JEFE → SALA` 라우트)
- [ ] **U3**: Resumen 테이블 → 두 지점의 MOV+ / MOV− 셀에 정확한 prendas 수 표시, Σ TOTAL MOV+ == MOV−
- [ ] **U4**: KPI 의 prendas 카운트(기존 totalItems) 가 movido 등록 후에도 변하지 않음 (오직 ventas 만 집계)
- [ ] **U5**: KPI 의 총매출 금액이 movido 등록 후 변하지 않음
- [ ] **U6**: Resumen 행 클릭 → URL `?branch=X` 변경 + 리스트 필터 + chip 표시
- [ ] **U7**: Resumen 셀 클릭 (예: SALA·MOV+) → URL `?branch=SALA&type=movido&direction=in` + 두 chip 표시
- [ ] **U8**: chip X 클릭 → URL query 제거 + 필터 해제
- [ ] **U9**: 권한 없는 사용자 → POST /stocks/movement 403 응답
- [ ] **U9b** (회귀): 비-privileged 사용자 (vendedor) + `user_functions(stock.movement)` 직접 부여 + `user.branchId === body.originBranchId` 시 → POST /stocks/movement 200 응답 (InjectBranchIdFromOriginGuard 회귀 검증)
- [ ] **U10**: 다른 지점 origin → 본인 지점 target 시도 시 (branch 제약 위반) → 403 + 적절한 에러 메시지
- [ ] **U11**: 단일 지점 사용자 ventaVista 진입 → Resumen 테이블에 1행만 표시, TOTAL 행 숨김
- [ ] **U12**: 기존 매출 보고서 (`/reportes/ventas`, `/dashboards/ventas`) → movido 등록 후에도 매출 수치 변화 없음 (activity_type 필터 정상 작동)
- [ ] **U12b** (회귀): movido 등록 후 신규 sale 의 dailyNumber 가 마지막 sale + 1 (movido 가 dailyNumber 잠식하지 않음 — sales-create.service.ts L188/L379 필터 회귀)
- [ ] **U13**: fallado 등록도 동일 흐름으로 작동 — chip `[FAL]`, red tint, `FAL · JEFE` 표시, FAL 셀에 prendas 수
- [ ] **U14**: Resumen 의 movBalance 알람 — 데이터 정합성 깨졌을 때 Σ TOTAL 행에 ⚠ 아이콘 표시

### Phase 35-B 검증

- [ ] **U15**: Stock Cockpit 에 MOV+/MOV−/FAL 컬럼 표시, 수치 정확 (sales.activity_type 기준 집계)
- [ ] **U16**: OFFSET 컬럼 — 기존 형식 데이터 변환되어 0 가 기본 (Phase 35-A 적용 후 등록되는 movido 는 모두 MOV 컬럼으로 분리)
- [ ] **U17**: STOCK = INGRESO − VENTA + MOV+ − MOV− − FAL + OFFSET 등식 검증 (수동 spot check)
- [ ] ~~**U18**: MOV+ 셀 hover → tooltip 최근 5건 표시 (origin/target/qty/date)~~ — **DEFERRED (Phase 35-A 범위 외)**
   - **사유:** 별도 endpoint (`/sales/by-product-recent?productId=X&type=movido&limit=5`) 또는 N+1 query 부담 — Phase 35-A 의 한정된 context budget 으로 무리
   - **후속 phase 후보:** Phase 35-C 또는 Phase 36 (Stock Cockpit Phase B 확장)
- [ ] **U19**: MOV+ 셀 click → ventaVista navigate + product/type/direction 필터 자동 적용 — **Plan 07 Task 2 에서 구현 완료**

### Backfill 검증 (별도 PR)

- [ ] **U20**: backfill dry-run → 생성될 sales 행 수가 stocks(type='adjust') 그룹 수와 일치
- [ ] **U21**: backfill 실행 후 → 과거 ventaVista 에 movido 흔적 표시 (sucursal/date 필터로 확인)
- [ ] **U22**: backfill 후 매출 보고서 수치 변화 없음 (activity_type='sale' 만 집계 검증)

---

## Open Questions (RESOLVED)

1. **Sequelize default scope vs 명시적 WHERE**: 둘 중 어느 방식이 안전한가? 기존 코드 영향 범위 측정 후 결정.
   - **RESOLVED:** 명시적 WHERE 절 선택 — Plan 01 (스키마) + Plan 03 (13 service 파일 명시적 필터). 이유: default scope 가 모든 곳에 자동 적용되어 의도치 않은 누락 위험 (D-04 risk 1). 명시적 WHERE 가 더 안전하고 grep 으로 감사 가능.

2. **Resumen 테이블 데이터 source**: `/sales/daily-stats` 신규 endpoint vs 기존 `/sales` + 클라이언트 집계?
   - **RESOLVED:** 신규 `/sales/daily-stats` endpoint — Plan 03 Task 3 + sales.service.getDailyStats. 이유: 클라이언트 집계는 페이지네이션과 충돌 (전체 데이터 fetch 필요), per-sucursal 매트릭스는 SQL 집계가 효율적 (단일 raw SQL CTE).

3. **`stock.movement` 권한 default**: 신규 매장에서는 누구에게 자동 부여? owner only? owner + encargado?
   - **RESOLVED:** role-based 기본 부여 (Plan 02 마이그레이션) — `store_owner`, `store_admin`, `gerente`, `admin`, `superadmin` 5개 role 자동 매핑. 추가로 기존 사용자 역호환을 위해 최근 90일 sale 활동 vendedor/encargado 에게도 user_functions 직접 부여.

4. **Phase 33 (Permissions v2) 의존**: 이미 완료/verifying 상태인가? 미완 시 본 phase 권한 부분 일부 지연 가능.
   - **RESOLVED:** Phase 33 verifying 상태 (MEMORY.md 참조). functions / role_functions / user_functions 테이블 사용 가능 — Plan 02 마이그레이션 의존성 만족.

5. **Mobile/responsive**: Resumen 테이블 모바일 sticky 컬럼 동작 검증 필요.
   - **DEFERRED:** UAT 단계 매뉴얼 검증 (35-UAT.md U11 의 단일지점 사용자 검증과 별도). 모바일 폭 < 600px 시 horizontal scroll + 첫 컬럼 sticky CSS 패턴 적용 (Plan 04 의 SalesResumenTable.tsx 구현 시 처리).
