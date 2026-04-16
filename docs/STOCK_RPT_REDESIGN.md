# Stock Rpt — 4패널 리디자인 구현 가이드

> Phase 12 Wave 05 → Wave 05-B  
> 작성일: 2026-04-16  
> 목표: Stock Cockpit 화면을 **4패널 resizable 레이아웃**으로 재구성

---

## 1. 목표 레이아웃 구조

```
┌──────────────────────────────────────────────────────────┐  ← 전체 높이 = 6분율
│  Panel A — 전체 매장 스톡 Resumen                        │  ← 높이 1 (16.7%)
│  · 지점 1개: KPI 카드 4개                                │
│  · 지점 2개+: 비교 테이블 (첫 행 = 합계)                │
├──────────────────────────────────────────────┬───────────┤  ← 높이 4 (66.7%)
│  Panel B — 아이템별 스톡 테이블              │  Panel C  │
│  (Panel A에서 선택된 지점의 재고 목록)       │  색상×    │
│  · 클릭 → Panel C 업데이트                   │  talle    │
│  · 정렬, 칼럼 폭 조절, 저장                  │  매트릭스 │
│                                              │           │
│  ← 가로 4 비율 →                            │ ← 2 비율→│
├──────────────────────────────────────────────┴───────────┤  ← 높이 1 (16.7%)
│  Panel D — 수동 스톡 조정                                │
│  · Panel C에서 선택된 색상/talle 기준                    │
│  · 이론값 vs 실제값 차이 입력 및 저장                    │
└──────────────────────────────────────────────────────────┘
```

**리사이즈 규칙:**
- A ↔ 중간(B+C): 수직 드래그 핸들
- 중간 ↔ D: 수직 드래그 핸들
- B ↔ C: 수평 드래그 핸들
- 모든 비율은 `localStorage`에 `stock-rpt-layout-*` 키로 저장

---

## 2. UI/UX 분석 — 이미지 기반

### 현재 화면 칼럼 (그림 참조)
| 칼럼 | 설명 |
|------|------|
| Codigo | 제품 코드 |
| (name) | 제품 이름 |
| UFecha | 마지막 이동 날짜 |
| TIngreso | 총 입고 수량 |
| TVenta | 총 판매 수량 |
| Offset | 조정값 |
| TRe... | 예약 수량 |
| RStock | 실재고 (이론값) |
| Ratio | 판매 비율 % |
| HIngreso | 금일 입고 |
| HVenta | 금일 판매 |
| Precio | 가격 |

### 새로운 Panel B 권장 칼럼 구성
| 칼럼 | 표시명 | 설명 | 정렬 기본값 |
|------|--------|------|------------|
| sku | Código | 제품 코드 (monospace) | — |
| productName | Producto | 제품명 | ASC |
| uFecha | Ú.Mov | 마지막 이동일 | — |
| tIngreso | Ingreso | 총 입고 | — |
| tVenta | Venta | 총 판매 | DESC |
| rStock | Stock | 현재 재고 | ASC (기본) |
| ratio | % Venta | 판매 비율 | — |
| offset | Offset | 수동 조정 누적값 | — |
| hIngreso | Hoy +  | 금일 입고 | — |
| hVenta | Hoy −  | 금일 판매 | — |
| precio | Precio | 가격 | — |

**색상 코딩:**
- `rStock ≤ 0` → `error.main` (빨강)
- `rStock 1~5` → `warning.main` (주황)
- `rStock > 100` → `info.main` (파랑, dead stock)
- 정상 → `text.primary`

---

## 3. 새 API 엔드포인트 명세

### 3-A. 다지점 Summary
```
GET /reports/stocks-cockpit/branches
  ?storeId=1

응답:
{
  branches: [
    {
      branchId: number,
      branchName: string,
      totalSku: number,
      totalValue: number,
      outOfStock: number,
      lowStock: number,
      deadStock: number,
      stockQty: number
    }
  ],
  total: {   // 모든 지점 합계
    totalSku, totalValue, outOfStock, lowStock, deadStock, stockQty
  }
}
```

### 3-B. 아이템별 스톡 (Panel B용, 기존 확장)
```
GET /reports/stocks-cockpit/items
  ?storeId=1&branchId=2&filter=&page=0&pageSize=50
  &sortBy=rStock&sortDir=asc

응답:
{
  rows: [
    {
      productId: number,
      sku: string,
      productName: string,
      categoryName: string,
      uFecha: string | null,     // 마지막 이동일
      tIngreso: number,          // 총 입고
      tVenta: number,            // 총 판매
      rStock: number,            // 현재 재고
      offset: number,            // 수동 조정값
      ratio: number,             // tVenta / tIngreso * 100
      hIngreso: number,          // 오늘 입고
      hVenta: number,            // 오늘 판매
      precio: number             // 판매 가격
    }
  ],
  count: number,
  page: number,
  pageSize: number
}
```

### 3-C. 색상×Talle 매트릭스 (Panel C용)
```
GET /reports/stocks-cockpit/matrix
  ?productId=123&branchId=2

응답:
{
  colors: string[],          // 색상 목록
  talles: string[],          // talle(사이즈) 목록
  matrix: {
    [color: string]: {
      [talle: string]: {
        stock: number,
        productBranchId: number,
        variantSku: string
      }
    }
  }
}
```

### 3-D. 수동 스톡 조정 (Panel D용)
```
POST /reports/stocks-cockpit/adjust
Body: {
  productBranchId: number,
  realStock: number,         // 실제 재고 (사용자 입력)
  note?: string              // 메모 (선택)
}

응답:
{
  success: boolean,
  newOffset: number,         // 새로운 offset 값
  theoreticalStock: number,  // 이론값
  realStock: number          // 실제값
}
```

---

## 4. 프론트엔드 파일 구조

```
ventago-app/src/views/reports/stocks/
├── StocksRptLayout.tsx           ← NEW: 4패널 레이아웃 컨테이너
├── StocksCockpitBody.tsx         ← UPDATED: StocksRptLayout 사용
├── panels/
│   ├── PanelA_BranchSummary.tsx  ← NEW: 지점 summary 패널
│   ├── PanelB_ItemTable.tsx      ← NEW: 아이템 테이블 패널
│   ├── PanelC_ColorMatrix.tsx    ← NEW: 색상×talle 매트릭스
│   └── PanelD_StockAdjust.tsx   ← NEW: 수동 조정 패널
├── hooks/
│   ├── useStocksCockpit.tsx      ← 기존 유지
│   ├── useStocksBranches.tsx     ← NEW: 지점별 summary
│   ├── useStocksItems.tsx        ← NEW: 아이템 목록 (Panel B)
│   ├── useStocksMatrix.tsx       ← NEW: 색상×talle 매트릭스
│   └── useStockAdjust.tsx        ← NEW: 조정 API
└── components/
    ├── ResizableTable.tsx         ← NEW: 칼럼 정렬+폭 조절 테이블
    └── StockBadge.tsx             ← NEW: 재고 수준 뱃지
```

---

## 5. 레이아웃 컴포넌트 설계 (StocksRptLayout)

```typescript
// 수직 리사이즈: A | 중간 | D
// 수평 리사이즈: B | C (중간 내부)

const STORAGE = {
  vertTop: 'stock-rpt-v-top',      // Panel A 높이 % (기본 16.7)
  vertBot: 'stock-rpt-v-bot',      // Panel D 높이 % (기본 16.7)
  horizLeft: 'stock-rpt-h-left',   // Panel B 폭 % (기본 66.7)
}
```

**리사이즈 핸들 스타일:**
- 수직: `height: 5px`, `cursor: row-resize`, `bgcolor: divider`
- 수평: `width: 5px`, `cursor: col-resize`, `bgcolor: divider`
- hover: `bgcolor: primary.light`

---

## 6. Panel A — 지점 Summary 상세

### 단일 지점 모드 (KPI 카드)
```
┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐
│ Total    │ │ Valor    │ │ Sin Stock│ │ Stock    │
│ SKUs     │ │ en Stock │ │   12     │ │  Bajo    │
│  450     │ │ ₲125.5M  │ │  ●●●●   │ │   23     │
└──────────┘ └──────────┘ └──────────┘ └──────────┘
```

### 다지점 모드 (비교 테이블)
```
┌──────────┬─────────┬──────────┬──────────┬──────────┬──────────┐
│ Sucursal │  SKUs   │  Valor   │ Sin Stock│ Stock Bajo│  Qty    │
├──────────┼─────────┼──────────┼──────────┼──────────┼──────────┤
│ TOTAL ★  │   900   │ ₲251M   │    24    │    46    │  1,230  │  ← 합계행 (bold)
├──────────┼─────────┼──────────┼──────────┼──────────┼──────────┤
│ Central  │   450   │ ₲125M   │    12    │    23    │    615  │  ← 클릭 선택
│ Norte    │   450   │ ₲126M   │    12    │    23    │    615  │
└──────────┴─────────┴──────────┴──────────┴──────────┴──────────┘
```
- 클릭 시 해당 지점 선택 → Panel B 업데이트
- TOTAL 행 클릭 → 모든 지점 합산 보기

---

## 7. Panel B — 아이템 테이블 상세

### 기능
- **정렬**: 모든 칼럼 클릭 시 ASC/DESC 토글 (화살표 표시)
- **칼럼 폭**: 드래그로 조절, `localStorage`에 저장
- **행 클릭**: Panel C에 해당 제품의 색상×talle 매트릭스 표시
- **선택 강조**: 선택된 행에 `primary.light` 배경
- **페이지네이션**: 10/25/50/100 행/페이지
- **검색 필터**: 상단 필터바와 연동

### 칼럼 폭 저장 키
```
localStorage: 'stock-rpt-col-widths'
형식: { sku: 100, productName: 200, rStock: 70, ... }
```

---

## 8. Panel C — 색상×Talle 매트릭스 상세

### 레이아웃
```
[선택된 제품명] — PCMR0066RM

       XS    S     M     L     XL
NEGRO   2     5    12     8     3
BLANCO  0     1     4     2     0     ← 0: error.main 배경
ROJO    1     0     8     0     1
```

- **셀 색상**: 0 → 빨강 배경, 1~3 → 주황, 4+ → 기본
- **셀 클릭**: Panel D에 해당 색상/talle 조정 폼 표시
- **선택된 셀**: 테두리 강조

---

## 9. Panel D — 수동 스톡 조정 상세

### 레이아웃
```
[선택: NEGRO / M 사이즈]

 이론값 (Teórico)    실제값 (Real)      차이 (Diferencia)
     12               [  10  ]              -2

 메모: [________________________________]

                [저장 (Guardar)]  [취소 (Cancelar)]
```

### 동작
1. Panel C에서 셀 선택 → 이론값 자동 표시
2. 실제값 입력
3. 차이 = 실제값 - 이론값 (자동 계산)
4. 저장 → `POST /reports/stocks-cockpit/adjust`
5. 성공 후 Panel B, C 자동 갱신

---

## 10. 백엔드 SQL 가이드

### 아이템별 스톡 쿼리 (Panel B)
```sql
-- stocks 테이블의 stock 필드 = RStock (현재 재고)
-- offset은 stocks 테이블의 별도 필드 또는 stock_adjustments 테이블 참조
-- hIngreso, hVenta = 오늘 날짜 기준 stock_movements 집계
-- tIngreso, tVenta = 전체 기간 stock_movements 집계

SELECT
  p.id AS product_id,
  p.sku,
  p.name AS product_name,
  COALESCE(cat.name, 'Sin categoría') AS category_name,
  -- 마지막 이동일
  MAX(sm.created_at)::date AS u_fecha,
  -- 총 입고 / 판매
  COALESCE(SUM(CASE WHEN sm.type = 'ingreso' THEN sm.qty END), 0) AS t_ingreso,
  COALESCE(SUM(CASE WHEN sm.type = 'venta'   THEN sm.qty END), 0) AS t_venta,
  -- 현재 재고
  COALESCE(SUM(s.stock), 0) AS r_stock,
  -- offset 합계
  COALESCE(SUM(sa.offset_qty), 0) AS offset,
  -- 금일
  COALESCE(SUM(CASE WHEN sm.type='ingreso' AND sm.created_at::date = CURRENT_DATE THEN sm.qty END),0) AS h_ingreso,
  COALESCE(SUM(CASE WHEN sm.type='venta'   AND sm.created_at::date = CURRENT_DATE THEN sm.qty END),0) AS h_venta,
  p.sale_price AS precio
FROM products p
JOIN product_branches pb ON pb.product_id = p.id
LEFT JOIN stocks s ON s.product_branch_id = pb.id
LEFT JOIN categories cat ON cat.id = p.category_id
LEFT JOIN stock_movements sm ON sm.product_branch_id = pb.id
LEFT JOIN stock_adjustments sa ON sa.product_branch_id = pb.id
WHERE p.store_id = :storeId
  AND (:branchId IS NULL OR pb.branch_id = :branchId)
  AND p.is_parent = false
GROUP BY p.id, p.sku, p.name, cat.name, p.sale_price
ORDER BY r_stock ASC, p.name ASC
LIMIT :pageSize OFFSET :offset;
```

> **⚠️ 주의**: 실제 테이블명(stock_movements, stock_adjustments 등)은 기존 스키마에 맞게 조정 필요.  
> `\d stocks` 및 `\d product_branches` 로 실제 컬럼 확인 후 작성.

### 색상×Talle 매트릭스 쿼리 (Panel C)
```sql
-- is_parent=true 인 부모 제품의 variants (is_parent=false) 를 색상/talle 로 피벗
-- SKU 패턴: PCMR0066RM (부모) → PCMR0066RM-NEG-M (색상-talle 조합)
-- 실제 color/talle 칼럼이 있는지 확인 필요

SELECT
  p.id AS product_id,
  p.sku AS variant_sku,
  -- color, talle 파싱 또는 별도 칼럼 사용
  p.color,
  p.talle,
  pb.id AS product_branch_id,
  COALESCE(SUM(s.stock), 0) AS stock
FROM products p
JOIN product_branches pb ON pb.product_id = p.id
LEFT JOIN stocks s ON s.product_branch_id = pb.id
WHERE p.parent_id = :parentProductId
  AND (:branchId IS NULL OR pb.branch_id = :branchId)
GROUP BY p.id, p.sku, p.color, p.talle, pb.id
ORDER BY p.color, p.talle;
```

---

## 11. 구현 순서 (권장)

| 순서 | 파일 | 작업 |
|------|------|------|
| 1 | `reportsStocksCockpit.service.ts` | `getBranches()`, `getItems()`, `getMatrix()`, `adjustStock()` 메서드 추가 |
| 2 | `reports.controller.ts` | 4개 엔드포인트 추가 (`/branches`, `/items`, `/matrix`, `/adjust`) |
| 3 | `StocksRptLayout.tsx` | 4패널 resizable 레이아웃 신규 작성 |
| 4 | `panels/PanelA_BranchSummary.tsx` | 단일/다지점 summary UI |
| 5 | `panels/PanelB_ItemTable.tsx` | 정렬+칼럼 폭 조절 테이블 |
| 6 | `panels/PanelC_ColorMatrix.tsx` | 색상×talle 매트릭스 |
| 7 | `panels/PanelD_StockAdjust.tsx` | 수동 조정 폼 |
| 8 | `hooks/*.tsx` | 각 패널용 커스텀 훅 |
| 9 | `StocksCockpitBody.tsx` | 새 레이아웃으로 교체 |
| 10 | `registry.ts` | cockpitLayout 설정 업데이트 |

---

## 12. localStorage 키 목록

| 키 | 기본값 | 설명 |
|----|--------|------|
| `stock-rpt-v-top` | `16.7` | Panel A 높이 % |
| `stock-rpt-v-bot` | `16.7` | Panel D 높이 % |
| `stock-rpt-h-left` | `66.7` | Panel B 폭 % |
| `stock-rpt-col-widths` | `{}` | Panel B 칼럼 폭 (JSON) |
| `stock-rpt-col-sort` | `{field:'rStock',dir:'asc'}` | Panel B 정렬 상태 |
| `stock-rpt-page-size` | `50` | Panel B 페이지 크기 |

---

## 13. 체크리스트

### 백엔드
- [ ] `getBranches()` 메서드 추가 — pool 낭비 없이 단일 쿼리
- [ ] `getItems()` 메서드 추가 — 기존 `getStocks()` 확장 (정렬 파라미터 추가)
- [ ] `getMatrix()` 메서드 추가 — 색상×talle 피벗 (실제 스키마 확인 필수)
- [ ] `adjustStock()` 메서드 추가 — offset 업데이트
- [ ] Controller 4개 엔드포인트 추가
- [ ] `QuerysDto` 필드 추가 (productId, sortBy, sortDir, realStock)
- [ ] 로그 파일 확인 후 배포

### 프론트엔드
- [ ] `StocksRptLayout` resizable 4패널
- [ ] Panel A: 단일=카드, 다지점=비교 테이블
- [ ] Panel B: 정렬 + 칼럼 폭 저장 + 행 선택
- [ ] Panel C: 색상×talle 매트릭스 + 셀 선택
- [ ] Panel D: 조정 폼 + 저장 후 갱신
- [ ] 모든 레이아웃 비율 localStorage 저장
- [ ] TypeScript 에러 없음
- [ ] 모바일 반응형 (md 이하: 패널 세로 스택)

---

## 14. 참고: 기존 코드 위치

| 항목 | 경로 |
|------|------|
| 현재 Cockpit Body | `ventago-app/src/views/reports/stocks/StocksCockpitBody.tsx` |
| 기존 서비스 | `api-ventago/src/app/reports/reportsStocksCockpit.service.ts` |
| 기존 훅 | `ventago-app/src/views/reports/stocks/hooks/useStocksCockpit.tsx` |
| CockpitLayout (참고용) | `ventago-app/src/views/reports-v2/CockpitLayout.tsx` |
| 레지스트리 | `ventago-app/src/views/reports-v2/registry.ts` |
| API Controller | `api-ventago/src/app/reports/reports.controller.ts` |
