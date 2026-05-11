# Product Promotions — Design Spec

**Date:** 2026-05-11
**Status:** Draft — pending user approval
**Phase target:** Phase A (Buy X get Y + Bulk tier + Time-based flag)
**Out of scope:** Combo promos (cart-level, deferred to next phase)

---

## 1. 목적 (Goal)

Precios 페이지 우측 패널에 3번째 탭 `🎁 Promociones`를 추가하여 매장이 **개별 제품 단위**로 특별 할인을 설정하고, POS(`nueva-venta`) 화면에서 카트 라인 아래 인라인 힌트로 upsell/적용 결과를 노출한다.

### 사용자 시나리오

- **시나리오 1 (Buy X get Y):** 카호가 Coca 1.5L를 2개 카트에 담음 → 라인 아래 골드 배너 "+1 más y llevás 1 GRATIS 🎁". 카호가 +1 누름 → 자동으로 무료 라인 1개 추가, 가격 $0.
- **시나리오 2 (Bulk tier):** 카호가 Vino Reserva 10개 담음 → "+2 más → precio Mayorista $4.000/u, Ahorrarías $12.000". 12개로 늘리면 자동으로 unitPrice가 Mayorista 가격으로 변경.

---

## 2. 결정사항 요약 (사용자 답변 기반)

| 결정 | 값 | 출처 |
|---|---|---|
| 적용 단위 | 개별 제품 고정 | Q1 |
| MVP 타입 | Buy X get Y, Bulk tier, Time-based 플래그 | Q2 + Q3 |
| Combo 제외 | Phase B로 연기 | Q3 |
| POS UX | 카트 라인 아래 인라인 힌트 + 자동 적용 | Q4 |
| 적용 방식 | 자동 적용 + 명시적 표시 | Q5 |
| UI 구조 | 옵션 A: Wizard 카드 리스트 | UI 옵션 |
| Evaluator 공유 | 코드 복제 + 양쪽 단위 테스트 | Evaluator 옵션 |

---

## 3. 데이터 모델

### 3.1 새 테이블 `product_promotions`

```sql
CREATE TABLE product_promotions (
  id            SERIAL PRIMARY KEY,
  store_id      INTEGER NOT NULL REFERENCES stores(id),
  product_id    INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  type          VARCHAR(20) NOT NULL,
  is_active     BOOLEAN NOT NULL DEFAULT TRUE,

  -- buy_x_get_y 전용
  min_qty       INTEGER,
  bonus_qty     INTEGER,

  -- bulk_tier 전용
  threshold_qty INTEGER,
  target_price_type_id INTEGER REFERENCES price_types(id),

  -- 공통 time-based (NULL = 무제한)
  starts_at     TIMESTAMPTZ,
  ends_at       TIMESTAMPTZ,

  label         VARCHAR(120),
  priority      INTEGER NOT NULL DEFAULT 0,

  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at    TIMESTAMPTZ
);

CREATE INDEX idx_pp_store_product
  ON product_promotions(store_id, product_id)
  WHERE deleted_at IS NULL AND is_active = TRUE;

CREATE INDEX idx_pp_active_range
  ON product_promotions(store_id, starts_at, ends_at)
  WHERE is_active = TRUE AND deleted_at IS NULL;
```

**제약:** `type ∈ {'buy_x_get_y', 'bulk_tier'}`. Time-only은 별도 type이 아니라 위 두 타입 + starts_at/ends_at 조합으로 표현.

### 3.2 `sale_items` 테이블 ALTER

```sql
ALTER TABLE sale_items
  ADD COLUMN is_promo_free  BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN promotion_id   INTEGER NULL REFERENCES product_promotions(id),
  ADD COLUMN promo_group_id UUID NULL;

CREATE INDEX idx_sale_items_promo_group
  ON sale_items(promo_group_id)
  WHERE promo_group_id IS NOT NULL;
```

`promo_group_id`는 §7.1 환불 방어 로직에서 promo 적용으로 묶인 sale_items(유료 + 무료)를 단일 그룹으로 추적하기 위함. sale 생성 시 evaluator가 같은 promotionId 적용한 라인들에 동일 UUID v4 부여.

### 3.3 PG10 호환성

- `SERIAL` 사용 (`GENERATED AS IDENTITY` 회피)
- `TIMESTAMPTZ` 모두 지원
- 부분 인덱스 `WHERE` 절 모두 PG10 지원

### 3.4 설계 근거

- **단일 테이블 + type**: 향후 Combo 추가 시 같은 테이블 컬럼 확장 또는 `promo_combo_items` 자식 테이블만 신설하면 됨. CRUD 코드 재사용.
- **soft-delete**: 이미 판매된 ticket이 promo 참조 가능해야 함.
- **priority**: 같은 product에 시즌 promo 2개일 때 결정적 적용.

---

## 4. 백엔드 API

### 4.1 모듈 구조

```
api-ventago/src/app/promotions/
├── promotions.module.ts
├── promotion.model.ts             # Sequelize @Table + @Column
├── promotions.controller.ts
├── promotions.service.ts          # CRUD + active 필터
├── promotion-evaluator.service.ts # 순수 함수 — DB 접근 없음
└── dto/
    ├── create-promotion.dto.ts
    ├── update-promotion.dto.ts
    └── evaluate-cart.dto.ts
```

### 4.2 엔드포인트

| Method | Path | 용도 | Guards |
|---|---|---|---|
| GET | `/promotions?storeId=&active=true` | 목록 (Precios UI) | JWT |
| GET | `/promotions/by-product/:productId` | 특정 product의 active promo | JWT |
| POST | `/promotions` | 생성 | JWT + SessionGuard |
| PUT | `/promotions/:id` | 전체 수정 | JWT + SessionGuard |
| PATCH | `/promotions/:id/toggle` | is_active on/off | JWT + SessionGuard |
| DELETE | `/promotions/:id` | soft-delete | JWT + SessionGuard |
| POST | `/promotions/evaluate-cart` | 카트 평가 (서버 검증용) | JWT |

### 4.3 `/promotions/evaluate-cart` 계약

**Request:**
```ts
{
  storeId: number,
  lines: Array<{
    productId: number,
    qty: number,
    unitPrice: number,
    priceTypeId: number
  }>
}
```

**Response:**
```ts
{
  appliedPromotions: Array<{
    lineIndex: number,
    promotionId: number,
    type: 'buy_x_get_y' | 'bulk_tier',
    label: string,
    bonusQty?: number,         // buy_x_get_y
    newUnitPrice?: number,     // bulk_tier
    oldUnitPrice?: number
  }>,
  suggestions: Array<{
    lineIndex: number,
    promotionId: number,
    type: 'buy_x_get_y' | 'bulk_tier',
    message: string,           // 다국어 키 또는 ES 텍스트
    needMore: number
  }>
}
```

### 4.4 PromotionEvaluatorService (순수 함수)

```ts
class PromotionEvaluatorService {
  evaluate(
    lines: CartLine[],
    promos: Promotion[],
    now: Date = new Date()
  ): EvalResult {
    // 1. 기간 필터링 (starts_at/ends_at)
    // 2. 라인별 매칭 promo 찾기 → priority 최고 1개
    // 3. type별 분기 처리
    //    - buy_x_get_y: floor(qty / min_qty) * bonus_qty
    //    - bulk_tier: qty >= threshold_qty 시 newUnitPrice 산출
    // 4. target nivel이 현재보다 비싸면 무시
    // 5. suggestion 생성 규칙 (§4.4.1 참조)
    return { appliedPromotions, suggestions };
  }
}
```

#### 4.4.1 Suggestion 임계값 규칙

미충족 promo에 대한 upsell suggestion은 다음 규칙으로 결정:

- **`buy_x_get_y`**: `qty >= ceil(min_qty / 2)` AND `qty < min_qty` → suggest. `needMore = min_qty - qty`
  - 예 3+1 (min_qty=3): qty 2 → suggest "+1 más", qty 1 → suggest 안 함 (너무 멀음)
- **`bulk_tier`**: `qty >= max(1, threshold_qty - 3)` AND `qty < threshold_qty` → suggest. `needMore = threshold_qty - qty`
  - 예 12u Mayorista: qty 9~11 → suggest, qty 8 이하 → 안 함

이 임계값(절반 / -3)은 evaluator 상수로 둠 (`SUGGESTION_NEAR_RATIO = 0.5`, `BULK_NEAR_DELTA = 3`). 향후 매장 설정으로 만들 수 있음 (Phase B).

### 4.5 Evaluator 코드 공유 정책

- `api-ventago/src/app/promotions/promotion-evaluator.service.ts`
- `ventago-app/src/utils/promotionEvaluator.ts` ← **동일 로직 복제**
- 양쪽 동일한 Jest 테스트 케이스 보유 (`*.spec.ts`)
- 변경 시 양쪽 동기화 필수 (PR 체크리스트)

### 4.6 POS 평가 전략

- 매장 진입 시 SWR로 active promotions GET 1회 (5분 dedup)
- 카트 변경 시 **클라이언트 evaluator 즉시 실행** (0ms 지연, 300ms 타겟 준수)
- sale 생성 시 백엔드도 동일 evaluator 실행 → 차이 시 409 (race condition 방어)

---

## 5. 프론트엔드 UI — Precios 페이지 (3번째 탭)

### 5.1 탭 추가

`CodigoVistaView.tsx:1041-1044`에 Tab 추가:
```tsx
<Tabs value={activeTab} onChange={(_, v) => setActiveTab(v)} variant="fullWidth" ...>
  <Tab label="⚖️ Niveles de Precio" />
  <Tab label="📈 Ajuste Global" />
  <Tab label="🎁 Promociones" />   {/* 신규 */}
</Tabs>
```

### 5.2 탭 3 콘텐츠 (카드 리스트)

```
┌─ Tab 3: 🎁 Promociones ────────────────────┐
│ ℹ️ Promociones activas por producto         │
│ [+ Nueva promoción]                          │
│ ─────────────────────────────────────────── │
│ ┌─ Coca 1.5L · 3+1 GRATIS ────────[● on]──┐│
│ │ 🎁 Compra 3 → Lleva 4                   ││
│ │ Sin vigencia                            ││
│ │ Prioridad: 0 · [✏️] [📋] [🗑]            ││
│ └──────────────────────────────────────────┘│
│ ┌─ Vino Reserva · Mayorista 12u ──[● on]──┐│
│ │ 📊 ≥ 12u → P3 (Mayorista)               ││
│ │ 01/Jun – 30/Jun · ⏰ 20 días restantes   ││
│ └──────────────────────────────────────────┘│
└─────────────────────────────────────────────┘
```

**컴포넌트:**
- `PromotionList.tsx` — 카드 렌더 + 토글
- `PromotionCard.tsx` — 개별 카드 (Niveles 카드 스타일 반영, `CodigoVistaView.tsx:1059-1097` 패턴)
- `PromotionDialog.tsx` — 신규/편집 다이얼로그

### 5.3 PromotionDialog

```
╔══ Nueva promoción ════════════════════╗
║ Producto:  [⌕ Coca 1.5L ▾]            ║
║ Etiqueta:  [Promo Verano___________]   ║
║                                        ║
║ Tipo:                                  ║
║  ( ) 🎁 Compra X, lleva Y gratis      ║
║  (●) 📊 Mayoreo: ≥ N unidades         ║
║                                        ║
║ ── Mayoreo (conditional) ──────────    ║
║ Cantidad mín: [ 12 ]                  ║
║ Nivel destino: [P3 Mayorista ▾]       ║
║                                        ║
║ ── Vigencia ──────────────────────    ║
║ [☐] Solo en fechas específicas        ║
║   Desde: [—]   Hasta: [—]             ║
║                                        ║
║ Prioridad: [ 0 ]  ⓘ                   ║
║                                        ║
║          [Cancelar]  [Guardar promo]  ║
╚════════════════════════════════════════╝
```

- 타입 라디오 변경 시 아래 필드 conditional 렌더 (`infMode` 분기 패턴 참조)
- Producto Autocomplete: 좌측 테이블 선택 행 prefill
- 색상 톤: 골드 `#f5a623` (sketch-findings 테마)

### 5.4 좌측 테이블 변경

product 행의 code 칼럼 옆에 🎁 아이콘 (active promo 있을 때만, tooltip으로 label):
```tsx
{p.hasActivePromo && (
  <Tooltip title={p.promoLabel}>
    <Icon icon="tabler:gift" width={14} style={{ color: '#f5a623' }} />
  </Tooltip>
)}
```

`hasActivePromo`는 새 SWR 훅 `usePromotionsByStore(storeId)`에서 derived state로 계산.

### 5.5 신규 SWR 훅

`ventago-app/src/hooks/api/usePromotionsByStore.ts` — 5분 dedup, store 단위 캐시 (CLAUDE.md 성능 규약).

---

## 6. 프론트엔드 UI — POS(nueva-venta) 통합

### 6.1 인라인 힌트 (카트 라인 아래)

**Case 1 — Buy X get Y, 미충족:**
```
🎁 +1 más y llevás 1 GRATIS    (골드 배너)
```

**Case 2 — Buy X get Y, 충족:**
```
+ 1 unidad GRATIS 🎁
1 × $0 (Promo Verano)          (회색+골드 무료 라인)
```

**Case 3 — Bulk tier, 미충족:**
```
📊 +2 más → precio Mayorista $4.000/u    (시안 배너)
   Ahorrarías $12.000
```

**Case 4 — Bulk tier, 충족:**
```
✅ Mayorista aplicado · ahorro $12.000   (녹색 배너)
```

### 6.2 `SaleProductsContext` 변경

```ts
// 신규 상태
const [promotions, setPromotions] = useState<Promotion[]>([]);
const [promoResult, setPromoResult] = useState<EvalResult>({
  applied: [], suggestions: []
});

// 매장 진입 시 1회 로드
const { promotions: storePromos } = usePromotionsByStore(storeId);
useEffect(() => setPromotions(storePromos), [storePromos]);

// products 변경 시 자동 재평가
useEffect(() => {
  const r = evaluatePromotions(products, promotions, new Date());
  setPromoResult(r);
}, [products, promotions]);
```

**중요:** `products[]` 배열은 카호 입력 그대로 유지. 적용된 promo는 `promoResult`에서 derived 렌더. 이렇게 해야 cart 상태가 단순 유지되고 promo on/off가 즉각 반영.

### 6.3 자동 적용 promo 라인 처리

| 항목 | 처리 |
|---|---|
| 카트 표시 | 부모 라인 아래 들여쓰기, 회색+골드 톤 |
| 가격 | bonus는 $0, bulk_tier는 unitPrice 변경 |
| 재고 차감 | 차감함 (실 상품 출고), `is_promo_free = true` 플래그 |
| 단독 편집 | 불가 (read-only) |
| 단독 삭제 | 불가, 부모 qty 변경으로만 제어 |
| 환불 | 부모 환불 시 자동 환불 + 재고 복구 |

### 6.4 sale 생성 시 payload

```ts
{
  items: [
    { productId, qty: 3, unitPrice: 1500, isPromoFree: false },
    { productId, qty: 1, unitPrice: 0, isPromoFree: true, promotionId: 42 }
  ],
  appliedPromotions: [{ promotionId: 42, lineIndex: 0 }]
}
```

### 6.5 SaleReviewPanel 추가 표시

```
─────────────────────────────────
Subtotal:           $4.500
🎁 Promos aplicadas:    -$1.500
  ↳ Coca 1.5L 3+1 (-$1.500)
─────────────────────────────────
TOTAL:              $3.000
```

`SaleReviewPanel.tsx`에 promo 섹션 추가.

---

## 7. Edge Cases

| # | 케이스 | 처리 |
|---|---|---|
| 1 | 동일 product에 active promo 2개 | priority 높은 1개. 동순위 → 더 큰 할인 |
| 2 | bulk_tier target이 현재보다 비쌈 | promo 무시 |
| 3 | starts_at 미래 / ends_at 과거 | evaluator 단계에서 제외, UI는 ⏰ 표시 |
| 4 | 같은 product 다른 priceTypeId 라인 2개 | 각 라인 독립 평가 |
| 5 | qty 변경으로 promo 사라짐 | 무료 라인 자동 제거 + 토스트 "Promo removida" |
| 6 | promo 라인 가격/수량 수정 시도 | read-only, 부모 라인 변경만 허용 |
| 7 | 결제 직전 promo 토글 off | 서버 재검증 → 409 → 클라 재평가 + 토스트 |
| 8 | 환불 시 promo 라인 | §7.1 환불 방어 로직 참조 |
| 9 | 재고 부족 (3+1인데 재고 3) | 자동 적용 안 함, alert "Stock insuficiente para promo" |
| 10 | 시즌 promo 자정 경계 | evaluate 시점 `new Date()` 기준 |

### 7.1 환불 방어 로직 (Refund Defense)

**문제:** 카호/고객이 promo로 무료로 가져간 N개를 단독 환불 요청 시 부정 사용 가능. 또는 유료 부분만 환불해서 promo 임계점 깨고 무료 항목 보존 시 부정 이득.

**정책 (사용자 결정: "무료 항목 단독 환불 금지"):**

#### Rule R1 — 무료 라인 단독 환불 차단

`is_promo_free = true` 인 sale_item만 환불 요청 시 → **422 Unprocessable Entity**
```json
{
  "code": "PROMO_FREE_REFUND_BLOCKED",
  "message": "Los items promocionales gratuitos no se pueden devolver por separado. Debe devolver la promoción completa (los X pagados + los N gratis)."
}
```

#### Rule R2 — Promo 그룹 묶음 환불 (정상 경로)

부모 유료 라인 + 모든 자식 무료 라인을 동시 환불하는 경우 → 정상 처리.
- 유료 라인: 원가 환불
- 무료 라인: $0 환불 (재고만 복구)
- `sale.refundedAmount` 정확히 계산

UI는 환불 화면에서 promo 그룹을 시각적으로 묶어 표시 (체크박스 그룹화). 부모 체크 시 자식 자동 체크.

#### Rule R3 — 부분 환불로 promo 임계점 깨지는 경우

예: 3+1 promo로 4개 (3 유료 + 1 무료) 구입. 고객이 유료 1개만 환불 요청.

→ 남은 항목: 유료 2개 + 무료 1개 = 2개에 대해서만 돈 냈는데 3개 보유. 부정 이득.

**처리:**
1. 환불 요청 검증 시 "남은 promo 그룹이 minimum 조건을 만족하는가?" 체크
2. 만족 안 하면 **422** 반환:
   ```json
   {
     "code": "PROMO_THRESHOLD_BROKEN",
     "message": "Al devolver estos items, la promoción 'X+Y' deja de ser válida. Debe devolver también los items gratis o desistir de la devolución parcial.",
     "requiredAlsoRefund": [
       { "saleItemId": 789, "qty": 1, "reason": "promo bonus tied to this group" }
     ]
   }
   ```
3. 카호는 두 가지 선택:
   - (a) `requiredAlsoRefund` 항목도 함께 환불 (재고만 돌려받음, 돈은 0 환불)
   - (b) 환불 자체를 취소

#### Rule R4 — sale_items 모델 보강

```sql
-- promo 그룹 추적을 위한 컬럼 추가
ALTER TABLE sale_items
  ADD COLUMN promo_group_id UUID NULL;
-- 같은 promo 적용으로 묶인 라인들은 동일 promo_group_id를 가짐
-- 예: 3 유료 라인 + 1 무료 라인 모두 같은 promo_group_id
```

서버 측에서 sale 생성 시 promo가 적용된 라인은 동일 `promo_group_id` (UUID v4) 부여. 환불 시 그룹 단위 검증에 사용.

#### Rule R5 — 검증 위치 (현재 코드 기준)

**현 시스템 환불 흐름:**
- POS 판매 취소: `api-ventago/src/app/sales/sales-create.service.ts`의 `nullifySale(saleId, userId)` — **전체 sale 역분개**. 부분 item 환불 미지원.
- 온라인 반품: `/online-returns/:id/approve` — `refundAmount` 단일 금액으로 처리.

**Phase A 구현 범위:**
1. `nullifySale`: 전체 sale 역분개이므로 promo 그룹 정합성 자동 보장 (모든 promo 라인이 함께 reversal됨). 단, reversal sale_items에 `is_promo_free`, `promo_group_id` 복사 + Winston 로그(R6) 추가.
2. **부분 item 환불 핸들러는 현재 없음** — R1/R3은 미래 부분환불 핸들러 신설 시 적용 의무 (스펙으로 남김).
3. 온라인 반품 `approve`: `refundAmount` 계산 시 `is_promo_free=true` 라인은 제외 (이미 $0). 단, 부분 반품으로 promo 깨지면 R3 검증 추가.

**Phase B에서 partial refund 추가 시:**
- 신설 핸들러는 `PromotionRefundGuardService.validate(saleId, requestedItemIds[])` 통과 필수
- 위 서비스가 R1/R3 검증 + 422 응답 생성
- 프론트는 환불 UI에서 사전 검증 + 경고 표시하되 서버가 최종 결정
- 422 응답 시 카호용 인라인 Alert + 토스트 (CLAUDE.md `feedback_error_visibility.md`)

#### Rule R6 — 감사 로그

모든 promo 관련 환불 거절/허용은 Winston으로 로그:
```
{ event: 'promo_refund_attempt', saleId, promoGroupId, decision: 'blocked'|'allowed', reason, userId, at }
```
부정 시도 패턴 추적용.

---

## 8. Error Handling

### Backend

- 동일 store+product+type 중복 promo → 409 "Ya existe promo activa de este tipo para este producto"
- 삭제는 soft-delete (`deleted_at` 설정)
- `evaluate-cart` 실패 → 빈 결과 + Winston 로그. POS는 promo 없는 모드로 fallback. **절대 결제 차단하지 않음.**

### Frontend

- promo API 호출 실패 → 인라인 Alert + 글로벌 토스트 (CLAUDE.md `feedback_error_visibility.md`)
- `usePromotionsByStore` 실패 → 빈 배열 fallback, POS 정상 동작
- evaluator 예외 → try/catch + Winston 로그, `promoResult: { applied: [], suggestions: [] }`

---

## 9. 테스트 전략

### Backend (Jest)

1. `PromotionEvaluatorService` 단위 테스트:
   - 3+1 정확 충족 → 무료 라인 1개
   - 3+1 6개 → 무료 2개
   - 3+1 2개 → suggestion `needMore: 1`
   - bulk_tier 임계값 도달 → newUnitPrice 산출
   - bulk_tier 미달 → 차액 정확
   - priority 충돌
   - 기간 경계 (시작 직전/직후, 종료 직전/직후)
   - active=false 무시
   - target nivel이 더 비싸면 무시
2. `PromotionsService` 통합 테스트:
   - CRUD + soft-delete
   - 중복 409
3. `/promotions/evaluate-cart` E2E (Supertest)
4. **환불 방어 로직 테스트 (`SalesService.refundSaleItems()`)**:
   - R1: 무료 라인 단독 환불 → 422 `PROMO_FREE_REFUND_BLOCKED`
   - R2: promo 그룹 묶음 환불 → 정상, 유료 환불 + 무료 재고 복구
   - R3: 부분 유료 환불로 임계점 깨짐 → 422 `PROMO_THRESHOLD_BROKEN` + `requiredAlsoRefund` 페이로드
   - R3 추가: 임계점 안 깨지는 부분 환불 (예: 6+2 promo에서 1개만 환불) → 정상 (남은 5+2도 promo 조건 만족)
   - R6: 환불 시도(차단/허용) 모두 Winston 로그 기록 확인

### Frontend (RTL + Jest)

1. `evaluatePromotions` 동일 단위 테스트 (코드 복제 정책)
2. `PromotionDialog` 폼 검증:
   - 타입 변경 시 conditional 필드
   - min_qty / bonus_qty ≤ 0 disable submit
3. `usePromotionsByStore` SWR 캐시
4. `SaleProductsContext` 통합:
   - 카트 변경 → promoResult 갱신
   - bonus 라인 read-only

### 수동 UAT (CLAUDE.md 권장)

- POS에서 3+1 실 결제 → ticket에 무료 라인
- 환불 → 무료 라인 동시 환불
- 시즌 promo on/off → 즉시 UI 반영

---

## 10. 성능 검증

| 항목 | 타겟 |
|---|---|
| `/promotions/evaluate-cart` p95 | ≤ 50ms |
| 클라이언트 evaluator (50 라인) | < 5ms |
| `GET /promotions` | SWR 5분 캐시, 페이지 진입당 1회 |
| POS 카트 변경 → 인라인 힌트 노출 | < 50ms (클라 즉시) |

---

## 11. 마이그레이션 / 배포 순서

1. `api-ventago/migrations/YYYYMMDD_create_product_promotions.sql` 작성 (PG10 호환)
2. `api-ventago/migrations/YYYYMMDD_alter_sale_items_promo.sql` 작성
3. 백엔드 코드 배포 (테이블 없어도 fallback 동작)
4. 운영 DB 마이그레이션 실행 (사용자 승인 필수)
5. 프론트 코드 배포
6. 첫 매장에서 promo 1개 테스트 → 전체 매장 공개

---

## 12. 향후 확장 (Out of Scope)

- **Combo (제품 A + B = 특별가)**: cart-level engine 필요, 별도 phase
- **카테고리 단위 promo**: scope 확장, `category_id` 컬럼 추가 + evaluator 분기
- **고객별 promo**: customer_id 매핑, CRM 통합
- **promo 사용 횟수 제한**: usage_count 컬럼 + 트랜잭션

---

## 13. 파일 변경 요약

### 신규

- `api-ventago/migrations/YYYYMMDD_create_product_promotions.sql`
- `api-ventago/migrations/YYYYMMDD_alter_sale_items_promo.sql`
- `api-ventago/src/app/promotions/promotions.module.ts`
- `api-ventago/src/app/promotions/promotion.model.ts`
- `api-ventago/src/app/promotions/promotions.controller.ts`
- `api-ventago/src/app/promotions/promotions.service.ts`
- `api-ventago/src/app/promotions/promotion-evaluator.service.ts`
- `api-ventago/src/app/promotions/promotion-evaluator.service.spec.ts`
- `api-ventago/src/app/promotions/dto/*.dto.ts`
- `ventago-app/src/hooks/api/usePromotionsByStore.ts`
- `ventago-app/src/utils/promotionEvaluator.ts`
- `ventago-app/src/utils/promotionEvaluator.spec.ts`
- `ventago-app/src/views/codigo-vista/PromotionsTab.tsx`
- `ventago-app/src/views/codigo-vista/PromotionCard.tsx`
- `ventago-app/src/views/codigo-vista/PromotionDialog.tsx`

### 수정

- `api-ventago/src/app/sales/sale-items.model.ts` — `isPromoFree`, `promotionId`, `promoGroupId` 컬럼
- `api-ventago/src/app/sales/sales-create.service.ts` — sale 생성 시 evaluator 재검증 + `promoGroupId` UUID 부여 + `nullifySale` 시 promo 라인도 reversal 포함 + Winston R6 로그
- `api-ventago/src/app/sales/sales.controller.ts` — (Phase B) 부분환불 핸들러 추가 시 422 응답 (`PROMO_FREE_REFUND_BLOCKED`, `PROMO_THRESHOLD_BROKEN`)
- `api-ventago/src/app/online-returns/online-returns.service.ts` — `approve` 시 `is_promo_free` 라인 refundAmount 제외 + R3 임계점 검증
- `api-ventago/src/app/app.module.ts` — PromotionsModule import
- `ventago-app/src/views/codigo-vista/CodigoVistaView.tsx` — 3번째 탭 추가, 좌측 테이블 🎁 칩
- `ventago-app/src/views/homes/hook/SaleProductsContext.tsx` — promoResult 상태 + evaluator 통합
- `ventago-app/src/views/homes/components/ProductList/ProductList.tsx` — 인라인 힌트 + 무료 라인 렌더
- `ventago-app/src/views/homes/components/ProductList/components/PaymentSummary.tsx` — promo 섹션
- `ventago-app/src/views/homes/components/SaleReview/SaleReviewPanel.tsx` — promo 섹션
- `ventago-app/src/views/sales/details/SalesDetailView.tsx` — `nullifySale` 시 promo 그룹 묶음 시각화 (Phase A — read-only 정보 표시)
- `ventago-app/src/views/ventas-online/ReturnsTab.tsx` — `approve` 시 promo 그룹 묶음 표시 + R3 위반 시 422 응답 처리 (인라인 Alert)
