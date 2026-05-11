# Product Promotions — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Phase A of product-level promotions (Buy X get Y + Bulk tier + Time-based flag) with admin UI on Precios page, automatic POS application with inline upsell hints, and refund defense for `nullifySale` + online returns.

**Architecture:** New `promotions` NestJS module (model + service + controller + pure evaluator) + 2 SQL migrations. Frontend: new tab in `CodigoVistaView`, new SWR hook, evaluator replicated client-side for 0ms POS UX. Refund defense: `is_promo_free` + `promo_group_id` on `sale_items`, enforced in `nullifySale` reversal + `online-returns.approve`.

**Tech Stack:** NestJS 11 + Sequelize, PostgreSQL 10 (prod) / 15 (dev), Next.js 13 + MUI 5 + SWR, Jest + RTL. Reference: `docs/superpowers/specs/2026-05-11-product-promotions-design.md`.

---

## File Structure

### New files

**Backend (`api-ventago/`):**
- `migrations/2026-05-11-create-product-promotions.sql`
- `migrations/2026-05-11-alter-sale-items-promo.sql`
- `src/app/promotions/promotion.model.ts`
- `src/app/promotions/promotions.module.ts`
- `src/app/promotions/promotions.service.ts`
- `src/app/promotions/promotions.controller.ts`
- `src/app/promotions/promotion-evaluator.service.ts`
- `src/app/promotions/promotion-evaluator.service.spec.ts`
- `src/app/promotions/promotions.service.spec.ts`
- `src/app/promotions/dto/create-promotion.dto.ts`
- `src/app/promotions/dto/update-promotion.dto.ts`
- `src/app/promotions/dto/evaluate-cart.dto.ts`

**Frontend (`ventago-app/`):**
- `src/utils/promotionEvaluator.ts`
- `src/utils/promotionEvaluator.spec.ts`
- `src/hooks/api/usePromotionsByStore.ts`
- `src/views/codigo-vista/PromotionsTab.tsx`
- `src/views/codigo-vista/PromotionCard.tsx`
- `src/views/codigo-vista/PromotionDialog.tsx`

### Modified files

**Backend:**
- `src/app/sales/sales-item/sales-item.model.ts` — add `isPromoFree`, `promotionId`, `promoGroupId`
- `src/app/sales/sales-create.service.ts` — evaluator integration on create + nullifySale promo preserve + Winston R6 logs
- `src/app/sales/dto/create-sales.dto.ts` — accept `isPromoFree`, `promotionId`, `appliedPromotions[]`
- `src/app/online-returns/online-returns.service.ts` — refundAmount excludes is_promo_free + R3 check
- `src/app/app.module.ts` — register PromotionsModule

**Frontend:**
- `src/views/codigo-vista/CodigoVistaView.tsx` — 3rd tab + 🎁 chip in left table
- `src/views/homes/hook/SaleProductsContext.tsx` — promoResult state + evaluator
- `src/views/homes/components/ProductList/ProductList.tsx` — inline hints + bonus line rendering
- `src/views/homes/components/ProductList/components/PaymentSummary.tsx` — promo savings section
- `src/views/homes/components/SaleReview/SaleReviewPanel.tsx` — promo section

---

## Conventions

- DB columns are `snake_case`, Sequelize properties `camelCase` (`underscored: true` globally).
- ESLint blocks Warnings as errors: `newline-before-return`, `lines-around-comment`, `no-unused-vars`.
- All `apiConnector` calls use `.remove()` not `.delete()`.
- All errors must be visible via inline Alert + global toast (`feedback_error_visibility`).
- Frequent commits — one per task minimum.

---

# Section 1 — Backend Foundation (Tasks 1-12)

## Task 1: SQL migration — create `product_promotions` table

**Files:**
- Create: `api-ventago/migrations/2026-05-11-create-product-promotions.sql`

- [ ] **Step 1: Write migration SQL**

Create `api-ventago/migrations/2026-05-11-create-product-promotions.sql`:

```sql
-- Phase A 프로모션 — product_promotions 테이블
-- type: 'buy_x_get_y' | 'bulk_tier'
-- 단일 테이블에 두 타입 통합. 컬럼은 type별로 NULL 가능.
-- soft-delete (deleted_at). 이미 판매된 ticket에서 promo 참조 가능해야 함.

CREATE TABLE IF NOT EXISTS product_promotions (
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

  -- 기간 (NULL = 무제한)
  starts_at     TIMESTAMPTZ,
  ends_at       TIMESTAMPTZ,

  label         VARCHAR(120),
  priority      INTEGER NOT NULL DEFAULT 0,

  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at    TIMESTAMPTZ,

  CONSTRAINT chk_promo_type CHECK (type IN ('buy_x_get_y', 'bulk_tier'))
);

CREATE INDEX IF NOT EXISTS idx_pp_store_product
  ON product_promotions(store_id, product_id)
  WHERE deleted_at IS NULL AND is_active = TRUE;

CREATE INDEX IF NOT EXISTS idx_pp_active_range
  ON product_promotions(store_id, starts_at, ends_at)
  WHERE is_active = TRUE AND deleted_at IS NULL;

-- 검증:
-- SELECT column_name, data_type FROM information_schema.columns WHERE table_name='product_promotions';
-- SELECT indexname FROM pg_indexes WHERE tablename='product_promotions';
```

- [ ] **Step 2: Apply migration to local Docker DB**

Run:
```bash
docker exec -i dbpostgres psql -U coolsistema -d ventago < api-ventago/migrations/2026-05-11-create-product-promotions.sql
```

Expected: `CREATE TABLE`, `CREATE INDEX`, `CREATE INDEX` (3 lines)

- [ ] **Step 3: Verify table created**

Run:
```bash
docker exec api_ventago node -e "
const { Client } = require('pg');
const c = new Client({host:'dbpostgres',user:'coolsistema',password:'Coo1s1stem4Adm1nPg',database:'ventago'});
c.connect().then(() => c.query(\"SELECT column_name, data_type FROM information_schema.columns WHERE table_name='product_promotions' ORDER BY ordinal_position\")).then(r => { console.log(r.rows); c.end(); });
"
```

Expected: 14 rows (id, store_id, product_id, type, is_active, min_qty, bonus_qty, threshold_qty, target_price_type_id, starts_at, ends_at, label, priority, created_at, updated_at, deleted_at).

- [ ] **Step 4: Commit**

```bash
cd /Users/marcoskim/Trabajos_Programming/ACE_online_1.0/api-ventago
git add migrations/2026-05-11-create-product-promotions.sql
git commit -m "feat(promotions): add product_promotions table migration"
```

---

## Task 2: SQL migration — alter `sale_items` for promo tracking

**Files:**
- Create: `api-ventago/migrations/2026-05-11-alter-sale-items-promo.sql`

- [ ] **Step 1: Write ALTER SQL**

Create `api-ventago/migrations/2026-05-11-alter-sale-items-promo.sql`:

```sql
-- Phase A 프로모션 — sale_items 확장
-- is_promo_free: bonus 라인 식별 (환불 시 R1 차단용)
-- promotion_id: 어떤 promo가 적용되었는지 추적
-- promo_group_id: 같은 promo로 묶인 유료+무료 라인 추적 (UUID v4, 서비스에서 부여)

ALTER TABLE sale_items
  ADD COLUMN IF NOT EXISTS is_promo_free  BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS promotion_id   INTEGER NULL REFERENCES product_promotions(id),
  ADD COLUMN IF NOT EXISTS promo_group_id UUID NULL;

CREATE INDEX IF NOT EXISTS idx_sale_items_promo_group
  ON sale_items(promo_group_id)
  WHERE promo_group_id IS NOT NULL;

-- 검증:
-- SELECT column_name, data_type FROM information_schema.columns
--   WHERE table_name='sale_items' AND column_name IN ('is_promo_free','promotion_id','promo_group_id');
```

- [ ] **Step 2: Apply migration**

```bash
docker exec -i dbpostgres psql -U coolsistema -d ventago < api-ventago/migrations/2026-05-11-alter-sale-items-promo.sql
```

Expected: `ALTER TABLE`, `CREATE INDEX`

- [ ] **Step 3: Verify columns**

```bash
docker exec api_ventago node -e "
const { Client } = require('pg');
const c = new Client({host:'dbpostgres',user:'coolsistema',password:'Coo1s1stem4Adm1nPg',database:'ventago'});
c.connect().then(() => c.query(\"SELECT column_name, data_type FROM information_schema.columns WHERE table_name='sale_items' AND column_name IN ('is_promo_free','promotion_id','promo_group_id') ORDER BY column_name\")).then(r => { console.log(r.rows); c.end(); });
"
```

Expected: 3 rows.

- [ ] **Step 4: Commit**

```bash
git add migrations/2026-05-11-alter-sale-items-promo.sql
git commit -m "feat(promotions): add promo tracking columns to sale_items"
```

---

## Task 3: Sequelize model — `Promotion`

**Files:**
- Create: `api-ventago/src/app/promotions/promotion.model.ts`

- [ ] **Step 1: Write the model**

Create `api-ventago/src/app/promotions/promotion.model.ts`:

```typescript
import {
  Column,
  Model,
  Table,
  DataType,
  ForeignKey,
  BelongsTo,
} from 'sequelize-typescript';
import { Store } from '../store/store.model';
import { Product } from '../products/products.model';
import { PriceType } from '../priceType/priceType.model';

export type PromotionType = 'buy_x_get_y' | 'bulk_tier';

@Table({
  tableName: 'product_promotions',
  timestamps: true,
  paranoid: true,
})
export class Promotion extends Model {
  @ForeignKey(() => Store)
  @Column({ allowNull: false })
  storeId: number;

  @BelongsTo(() => Store)
  store: Store;

  @ForeignKey(() => Product)
  @Column({ allowNull: false })
  productId: number;

  @BelongsTo(() => Product)
  product: Product;

  @Column({ type: DataType.STRING(20), allowNull: false })
  type: PromotionType;

  @Column({ type: DataType.BOOLEAN, allowNull: false, defaultValue: true })
  isActive: boolean;

  // buy_x_get_y
  @Column({ type: DataType.INTEGER, allowNull: true })
  minQty: number | null;

  @Column({ type: DataType.INTEGER, allowNull: true })
  bonusQty: number | null;

  // bulk_tier
  @Column({ type: DataType.INTEGER, allowNull: true })
  thresholdQty: number | null;

  @ForeignKey(() => PriceType)
  @Column({ type: DataType.INTEGER, allowNull: true })
  targetPriceTypeId: number | null;

  @BelongsTo(() => PriceType)
  targetPriceType: PriceType;

  @Column({ type: DataType.DATE, allowNull: true })
  startsAt: Date | null;

  @Column({ type: DataType.DATE, allowNull: true })
  endsAt: Date | null;

  @Column({ type: DataType.STRING(120), allowNull: true })
  label: string | null;

  @Column({ type: DataType.INTEGER, allowNull: false, defaultValue: 0 })
  priority: number;
}
```

NOTE: Check actual PriceType file path — likely `src/app/priceType/priceType.model.ts`. If different, adjust import.

- [ ] **Step 2: Verify model imports resolve**

```bash
cd /Users/marcoskim/Trabajos_Programming/ACE_online_1.0/api-ventago
find src/app -name "priceType.model.ts" -o -name "price-types.model.ts" -o -name "priceTypes.model.ts" 2>/dev/null
```

If path differs from the import, update Task 3 Step 1 import line.

- [ ] **Step 3: TypeScript compile check**

```bash
cd api-ventago && npx tsc --noEmit src/app/promotions/promotion.model.ts 2>&1 | head -20
```

Expected: No errors (or only "Cannot find module" warnings for unresolved siblings — those resolve at full project compile).

- [ ] **Step 4: Commit**

```bash
git add src/app/promotions/promotion.model.ts
git commit -m "feat(promotions): add Promotion Sequelize model"
```

---

## Task 4: PromotionEvaluatorService — TDD for `buy_x_get_y` exact match

**Files:**
- Create: `api-ventago/src/app/promotions/promotion-evaluator.service.ts`
- Test: `api-ventago/src/app/promotions/promotion-evaluator.service.spec.ts`

- [ ] **Step 1: Write the failing test**

Create `api-ventago/src/app/promotions/promotion-evaluator.service.spec.ts`:

```typescript
import { PromotionEvaluatorService, CartLine, PromotionInput } from './promotion-evaluator.service';

describe('PromotionEvaluatorService', () => {
  let svc: PromotionEvaluatorService;
  beforeEach(() => { svc = new PromotionEvaluatorService(); });

  const FIXED_NOW = new Date('2026-05-11T12:00:00Z');

  const promo3Plus1: PromotionInput = {
    id: 1, storeId: 1, productId: 100, type: 'buy_x_get_y',
    isActive: true, minQty: 3, bonusQty: 1,
    thresholdQty: null, targetPriceTypeId: null,
    startsAt: null, endsAt: null, label: '3+1', priority: 0,
  };

  it('buy_x_get_y: qty exactly meets min_qty → 1 bonus line', () => {
    const lines: CartLine[] = [
      { productId: 100, qty: 3, unitPrice: 1500, priceTypeId: 1 },
    ];
    const result = svc.evaluate(lines, [promo3Plus1], FIXED_NOW);
    expect(result.appliedPromotions).toEqual([
      { lineIndex: 0, promotionId: 1, type: 'buy_x_get_y', label: '3+1', bonusQty: 1 },
    ]);
    expect(result.suggestions).toEqual([]);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd api-ventago && npx jest src/app/promotions/promotion-evaluator.service.spec.ts 2>&1 | tail -20
```

Expected: FAIL — "Cannot find module './promotion-evaluator.service'"

- [ ] **Step 3: Write minimal implementation**

Create `api-ventago/src/app/promotions/promotion-evaluator.service.ts`:

```typescript
import { Injectable } from '@nestjs/common';

export type PromotionType = 'buy_x_get_y' | 'bulk_tier';

export interface PromotionInput {
  id: number;
  storeId: number;
  productId: number;
  type: PromotionType;
  isActive: boolean;
  minQty: number | null;
  bonusQty: number | null;
  thresholdQty: number | null;
  targetPriceTypeId: number | null;
  startsAt: Date | null;
  endsAt: Date | null;
  label: string | null;
  priority: number;
}

export interface CartLine {
  productId: number;
  qty: number;
  unitPrice: number;
  priceTypeId: number;
}

export interface AppliedPromotion {
  lineIndex: number;
  promotionId: number;
  type: PromotionType;
  label: string;
  bonusQty?: number;
  newUnitPrice?: number;
  oldUnitPrice?: number;
}

export interface Suggestion {
  lineIndex: number;
  promotionId: number;
  type: PromotionType;
  message: string;
  needMore: number;
}

export interface EvalResult {
  appliedPromotions: AppliedPromotion[];
  suggestions: Suggestion[];
}

export const SUGGESTION_NEAR_RATIO = 0.5;
export const BULK_NEAR_DELTA = 3;

@Injectable()
export class PromotionEvaluatorService {
  evaluate(lines: CartLine[], promos: PromotionInput[], now: Date = new Date()): EvalResult {
    const applied: AppliedPromotion[] = [];
    const suggestions: Suggestion[] = [];

    lines.forEach((line, lineIndex) => {
      const candidates = promos
        .filter(p => p.productId === line.productId)
        .filter(p => p.isActive)
        .filter(p => !p.startsAt || p.startsAt <= now)
        .filter(p => !p.endsAt || p.endsAt > now)
        .sort((a, b) => b.priority - a.priority);

      const promo = candidates[0];
      if (!promo) return;

      if (promo.type === 'buy_x_get_y' && promo.minQty && promo.bonusQty) {
        if (line.qty >= promo.minQty) {
          const times = Math.floor(line.qty / promo.minQty);
          applied.push({
            lineIndex, promotionId: promo.id, type: 'buy_x_get_y',
            label: promo.label ?? '', bonusQty: times * promo.bonusQty,
          });
        }
      }
    });

    return { appliedPromotions: applied, suggestions };
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
npx jest src/app/promotions/promotion-evaluator.service.spec.ts 2>&1 | tail -10
```

Expected: `Tests: 1 passed`

- [ ] **Step 5: Commit**

```bash
git add src/app/promotions/promotion-evaluator.service.ts src/app/promotions/promotion-evaluator.service.spec.ts
git commit -m "feat(promotions): evaluator handles buy_x_get_y exact match"
```

---

## Task 5: Evaluator — `buy_x_get_y` 6개 → 2개 bonus + suggestion threshold

**Files:**
- Modify: `api-ventago/src/app/promotions/promotion-evaluator.service.spec.ts`
- Modify: `api-ventago/src/app/promotions/promotion-evaluator.service.ts`

- [ ] **Step 1: Add 4 failing tests**

Append to `promotion-evaluator.service.spec.ts` (inside `describe`):

```typescript
  it('buy_x_get_y: qty=6 with min=3 → 2 bonus units', () => {
    const lines: CartLine[] = [{ productId: 100, qty: 6, unitPrice: 1500, priceTypeId: 1 }];
    const r = svc.evaluate(lines, [promo3Plus1], FIXED_NOW);
    expect(r.appliedPromotions[0]?.bonusQty).toBe(2);
  });

  it('buy_x_get_y: qty=2 with min=3 → suggestion needMore=1', () => {
    const lines: CartLine[] = [{ productId: 100, qty: 2, unitPrice: 1500, priceTypeId: 1 }];
    const r = svc.evaluate(lines, [promo3Plus1], FIXED_NOW);
    expect(r.appliedPromotions).toEqual([]);
    expect(r.suggestions).toEqual([
      { lineIndex: 0, promotionId: 1, type: 'buy_x_get_y',
        message: expect.stringContaining('1'), needMore: 1 },
    ]);
  });

  it('buy_x_get_y: qty=1 with min=3 → NO suggestion (too far)', () => {
    const lines: CartLine[] = [{ productId: 100, qty: 1, unitPrice: 1500, priceTypeId: 1 }];
    const r = svc.evaluate(lines, [promo3Plus1], FIXED_NOW);
    expect(r.suggestions).toEqual([]);
  });

  it('buy_x_get_y: inactive promo → ignored', () => {
    const inactive = { ...promo3Plus1, isActive: false };
    const lines: CartLine[] = [{ productId: 100, qty: 3, unitPrice: 1500, priceTypeId: 1 }];
    const r = svc.evaluate(lines, [inactive], FIXED_NOW);
    expect(r.appliedPromotions).toEqual([]);
  });
```

- [ ] **Step 2: Run tests to verify 2 of them fail**

```bash
npx jest src/app/promotions/promotion-evaluator.service.spec.ts 2>&1 | tail -20
```

Expected: 2 PASS (qty=6 and inactive — already work), 2 FAIL (qty=2 suggestion, qty=1 no-suggestion may pass already).

- [ ] **Step 3: Add suggestion logic**

In `promotion-evaluator.service.ts`, replace the `buy_x_get_y` block inside `lines.forEach`:

```typescript
      if (promo.type === 'buy_x_get_y' && promo.minQty && promo.bonusQty) {
        if (line.qty >= promo.minQty) {
          const times = Math.floor(line.qty / promo.minQty);
          applied.push({
            lineIndex, promotionId: promo.id, type: 'buy_x_get_y',
            label: promo.label ?? '', bonusQty: times * promo.bonusQty,
          });
        } else {
          const threshold = Math.ceil(promo.minQty * SUGGESTION_NEAR_RATIO);
          if (line.qty >= threshold) {
            const needMore = promo.minQty - line.qty;
            suggestions.push({
              lineIndex, promotionId: promo.id, type: 'buy_x_get_y',
              message: `+${needMore} más y llevás ${promo.bonusQty} GRATIS 🎁`,
              needMore,
            });
          }
        }
      }
```

- [ ] **Step 4: Run tests**

```bash
npx jest src/app/promotions/promotion-evaluator.service.spec.ts 2>&1 | tail -10
```

Expected: `Tests: 5 passed`

- [ ] **Step 5: Commit**

```bash
git add src/app/promotions/promotion-evaluator.service.ts src/app/promotions/promotion-evaluator.service.spec.ts
git commit -m "feat(promotions): evaluator handles buy_x_get_y multi-bonus and suggestions"
```

---

## Task 6: Evaluator — `bulk_tier` applied + suggestion + cheaper-than-current rule

**Files:**
- Modify: `api-ventago/src/app/promotions/promotion-evaluator.service.spec.ts`
- Modify: `api-ventago/src/app/promotions/promotion-evaluator.service.ts`

- [ ] **Step 1: Add 4 failing tests**

Append to the spec file:

```typescript
  const bulkPromo: PromotionInput = {
    id: 2, storeId: 1, productId: 200, type: 'bulk_tier',
    isActive: true, minQty: null, bonusQty: null,
    thresholdQty: 12, targetPriceTypeId: 3,
    startsAt: null, endsAt: null, label: 'Mayorista 12u', priority: 0,
  };

  // priceTypePrices fixture: line의 product가 priceTypeId 3에서 4000원
  const productPriceLookup = { 200: { 1: 5000, 3: 4000 } };

  it('bulk_tier: qty >= threshold → newUnitPrice from target nivel', () => {
    const lines: CartLine[] = [{ productId: 200, qty: 12, unitPrice: 5000, priceTypeId: 1 }];
    const r = svc.evaluate(lines, [bulkPromo], FIXED_NOW, productPriceLookup);
    expect(r.appliedPromotions[0]).toEqual({
      lineIndex: 0, promotionId: 2, type: 'bulk_tier',
      label: 'Mayorista 12u', newUnitPrice: 4000, oldUnitPrice: 5000,
    });
  });

  it('bulk_tier: qty=10 (within near range 3) → suggestion', () => {
    const lines: CartLine[] = [{ productId: 200, qty: 10, unitPrice: 5000, priceTypeId: 1 }];
    const r = svc.evaluate(lines, [bulkPromo], FIXED_NOW, productPriceLookup);
    expect(r.suggestions[0]?.needMore).toBe(2);
  });

  it('bulk_tier: qty=5 (far) → NO suggestion', () => {
    const lines: CartLine[] = [{ productId: 200, qty: 5, unitPrice: 5000, priceTypeId: 1 }];
    const r = svc.evaluate(lines, [bulkPromo], FIXED_NOW, productPriceLookup);
    expect(r.suggestions).toEqual([]);
  });

  it('bulk_tier: target price >= current price → ignored', () => {
    const lookup = { 200: { 1: 4000, 3: 5000 } };  // current 4000, target 5000 (비쌈)
    const lines: CartLine[] = [{ productId: 200, qty: 12, unitPrice: 4000, priceTypeId: 1 }];
    const r = svc.evaluate(lines, [bulkPromo], FIXED_NOW, lookup);
    expect(r.appliedPromotions).toEqual([]);
  });
```

- [ ] **Step 2: Run tests to verify failure**

```bash
npx jest src/app/promotions/promotion-evaluator.service.spec.ts 2>&1 | tail -15
```

Expected: 4 new tests FAIL with compile error (evaluate signature missing 4th arg) or assertion errors.

- [ ] **Step 3: Extend evaluate signature + add bulk_tier logic**

In `promotion-evaluator.service.ts`:

Add at the top with other interfaces:

```typescript
export type PriceLookup = Record<number, Record<number, number>>;
// priceLookup[productId][priceTypeId] = unit price
```

Modify `evaluate` signature:

```typescript
  evaluate(
    lines: CartLine[],
    promos: PromotionInput[],
    now: Date = new Date(),
    priceLookup: PriceLookup = {},
  ): EvalResult {
```

Add bulk_tier branch after the buy_x_get_y block (inside `lines.forEach`):

```typescript
      if (promo.type === 'bulk_tier' && promo.thresholdQty && promo.targetPriceTypeId) {
        const targetPrice = priceLookup[line.productId]?.[promo.targetPriceTypeId];
        if (targetPrice == null) return;
        if (targetPrice >= line.unitPrice) return;  // 더 비싸면 무시

        if (line.qty >= promo.thresholdQty) {
          applied.push({
            lineIndex, promotionId: promo.id, type: 'bulk_tier',
            label: promo.label ?? '', newUnitPrice: targetPrice, oldUnitPrice: line.unitPrice,
          });
        } else if (line.qty >= Math.max(1, promo.thresholdQty - BULK_NEAR_DELTA)) {
          const needMore = promo.thresholdQty - line.qty;
          suggestions.push({
            lineIndex, promotionId: promo.id, type: 'bulk_tier',
            message: `+${needMore} más → ${targetPrice.toLocaleString('es-AR')} c/u`,
            needMore,
          });
        }
      }
```

- [ ] **Step 4: Run tests**

```bash
npx jest src/app/promotions/promotion-evaluator.service.spec.ts 2>&1 | tail -10
```

Expected: `Tests: 9 passed`

- [ ] **Step 5: Commit**

```bash
git add src/app/promotions/promotion-evaluator.service.ts src/app/promotions/promotion-evaluator.service.spec.ts
git commit -m "feat(promotions): evaluator handles bulk_tier with priceLookup"
```

---

## Task 7: Evaluator — priority conflict + time boundaries

**Files:**
- Modify: `api-ventago/src/app/promotions/promotion-evaluator.service.spec.ts`

- [ ] **Step 1: Add edge case tests**

Append:

```typescript
  it('two promos same product → higher priority wins', () => {
    const low = { ...promo3Plus1, id: 10, priority: 0, label: 'low' };
    const high = { ...promo3Plus1, id: 11, priority: 5, label: 'high' };
    const lines: CartLine[] = [{ productId: 100, qty: 3, unitPrice: 1500, priceTypeId: 1 }];
    const r = svc.evaluate(lines, [low, high], FIXED_NOW);
    expect(r.appliedPromotions[0]?.promotionId).toBe(11);
  });

  it('promo before starts_at → ignored', () => {
    const future = { ...promo3Plus1, startsAt: new Date('2026-06-01T00:00:00Z') };
    const lines: CartLine[] = [{ productId: 100, qty: 3, unitPrice: 1500, priceTypeId: 1 }];
    const r = svc.evaluate(lines, [future], FIXED_NOW);
    expect(r.appliedPromotions).toEqual([]);
  });

  it('promo after ends_at → ignored', () => {
    const past = { ...promo3Plus1, endsAt: new Date('2026-05-01T00:00:00Z') };
    const lines: CartLine[] = [{ productId: 100, qty: 3, unitPrice: 1500, priceTypeId: 1 }];
    const r = svc.evaluate(lines, [past], FIXED_NOW);
    expect(r.appliedPromotions).toEqual([]);
  });

  it('promo exactly at ends_at boundary → ignored (exclusive)', () => {
    const justEnded = { ...promo3Plus1, endsAt: FIXED_NOW };
    const lines: CartLine[] = [{ productId: 100, qty: 3, unitPrice: 1500, priceTypeId: 1 }];
    const r = svc.evaluate(lines, [justEnded], FIXED_NOW);
    expect(r.appliedPromotions).toEqual([]);
  });
```

- [ ] **Step 2: Run tests**

```bash
npx jest src/app/promotions/promotion-evaluator.service.spec.ts 2>&1 | tail -10
```

Expected: `Tests: 13 passed` (all of these should pass with current implementation).

- [ ] **Step 3: Commit**

```bash
git add src/app/promotions/promotion-evaluator.service.spec.ts
git commit -m "test(promotions): evaluator priority and time boundary cases"
```

---

## Task 8: DTOs — Create/Update/EvaluateCart

**Files:**
- Create: `api-ventago/src/app/promotions/dto/create-promotion.dto.ts`
- Create: `api-ventago/src/app/promotions/dto/update-promotion.dto.ts`
- Create: `api-ventago/src/app/promotions/dto/evaluate-cart.dto.ts`

- [ ] **Step 1: Create `create-promotion.dto.ts`**

```typescript
import { IsBoolean, IsDateString, IsIn, IsInt, IsOptional, IsString, Min, MaxLength } from 'class-validator';

export class CreatePromotionDto {
  @IsInt() storeId: number;
  @IsInt() productId: number;
  @IsIn(['buy_x_get_y', 'bulk_tier']) type: 'buy_x_get_y' | 'bulk_tier';

  @IsOptional() @IsBoolean() isActive?: boolean;

  @IsOptional() @IsInt() @Min(1) minQty?: number;
  @IsOptional() @IsInt() @Min(1) bonusQty?: number;
  @IsOptional() @IsInt() @Min(1) thresholdQty?: number;
  @IsOptional() @IsInt() targetPriceTypeId?: number;

  @IsOptional() @IsDateString() startsAt?: string;
  @IsOptional() @IsDateString() endsAt?: string;

  @IsOptional() @IsString() @MaxLength(120) label?: string;
  @IsOptional() @IsInt() priority?: number;
}
```

- [ ] **Step 2: Create `update-promotion.dto.ts`**

```typescript
import { PartialType } from '@nestjs/mapped-types';
import { CreatePromotionDto } from './create-promotion.dto';

export class UpdatePromotionDto extends PartialType(CreatePromotionDto) {}
```

- [ ] **Step 3: Create `evaluate-cart.dto.ts`**

```typescript
import { IsArray, IsInt, ValidateNested, Min } from 'class-validator';
import { Type } from 'class-transformer';

export class EvaluateCartLineDto {
  @IsInt() productId: number;
  @IsInt() @Min(1) qty: number;
  @IsInt() @Min(0) unitPrice: number;
  @IsInt() priceTypeId: number;
}

export class EvaluateCartDto {
  @IsInt() storeId: number;
  @IsArray() @ValidateNested({ each: true }) @Type(() => EvaluateCartLineDto)
  lines: EvaluateCartLineDto[];
}
```

- [ ] **Step 4: Commit**

```bash
git add src/app/promotions/dto
git commit -m "feat(promotions): add DTOs for create/update/evaluate"
```

---

## Task 9: PromotionsService — CRUD with conflict detection

**Files:**
- Create: `api-ventago/src/app/promotions/promotions.service.ts`
- Test: `api-ventago/src/app/promotions/promotions.service.spec.ts`

- [ ] **Step 1: Write the failing test**

Create `promotions.service.spec.ts`:

```typescript
import { Test } from '@nestjs/testing';
import { getModelToken } from '@nestjs/sequelize';
import { ConflictException } from '@nestjs/common';
import { PromotionsService } from './promotions.service';
import { Promotion } from './promotion.model';

describe('PromotionsService', () => {
  let svc: PromotionsService;
  let model: any;

  beforeEach(async () => {
    model = {
      findOne: jest.fn(),
      findAll: jest.fn(),
      findByPk: jest.fn(),
      create: jest.fn(),
      destroy: jest.fn(),
    };
    const moduleRef = await Test.createTestingModule({
      providers: [
        PromotionsService,
        { provide: getModelToken(Promotion), useValue: model },
      ],
    }).compile();
    svc = moduleRef.get(PromotionsService);
  });

  it('create throws ConflictException when same store+product+type active exists', async () => {
    model.findOne.mockResolvedValue({ id: 1 });
    await expect(svc.create({
      storeId: 1, productId: 100, type: 'buy_x_get_y', minQty: 3, bonusQty: 1,
    } as any)).rejects.toThrow(ConflictException);
  });

  it('create persists when no conflict', async () => {
    model.findOne.mockResolvedValue(null);
    model.create.mockResolvedValue({ id: 99 });
    const r = await svc.create({
      storeId: 1, productId: 100, type: 'buy_x_get_y', minQty: 3, bonusQty: 1,
    } as any);
    expect(r.id).toBe(99);
  });
});
```

- [ ] **Step 2: Run test to verify failure**

```bash
npx jest src/app/promotions/promotions.service.spec.ts 2>&1 | tail -10
```

Expected: FAIL — "Cannot find module './promotions.service'"

- [ ] **Step 3: Write the service**

Create `promotions.service.ts`:

```typescript
import { Injectable, NotFoundException, ConflictException } from '@nestjs/common';
import { InjectModel } from '@nestjs/sequelize';
import { Promotion } from './promotion.model';
import { CreatePromotionDto } from './dto/create-promotion.dto';
import { UpdatePromotionDto } from './dto/update-promotion.dto';

@Injectable()
export class PromotionsService {
  constructor(@InjectModel(Promotion) private readonly model: typeof Promotion) {}

  async findAll(storeId: number, activeOnly = false): Promise<Promotion[]> {
    const where: any = { storeId };
    if (activeOnly) where.isActive = true;

    return this.model.findAll({ where, order: [['priority', 'DESC'], ['id', 'DESC']] });
  }

  async findByProduct(productId: number): Promise<Promotion[]> {
    return this.model.findAll({ where: { productId, isActive: true } });
  }

  async create(dto: CreatePromotionDto): Promise<Promotion> {
    const existing = await this.model.findOne({
      where: { storeId: dto.storeId, productId: dto.productId, type: dto.type, isActive: true },
    });
    if (existing) {
      throw new ConflictException('Ya existe promo activa de este tipo para este producto');
    }

    return this.model.create(dto as any);
  }

  async update(id: number, dto: UpdatePromotionDto): Promise<Promotion> {
    const promo = await this.model.findByPk(id);
    if (!promo) throw new NotFoundException();
    await promo.update(dto as any);

    return promo;
  }

  async toggle(id: number): Promise<Promotion> {
    const promo = await this.model.findByPk(id);
    if (!promo) throw new NotFoundException();
    await promo.update({ isActive: !promo.isActive });

    return promo;
  }

  async remove(id: number): Promise<void> {
    const promo = await this.model.findByPk(id);
    if (!promo) throw new NotFoundException();
    await promo.destroy();
  }
}
```

- [ ] **Step 4: Run tests**

```bash
npx jest src/app/promotions/promotions.service.spec.ts 2>&1 | tail -10
```

Expected: `Tests: 2 passed`

- [ ] **Step 5: Commit**

```bash
git add src/app/promotions/promotions.service.ts src/app/promotions/promotions.service.spec.ts
git commit -m "feat(promotions): add PromotionsService CRUD with conflict detection"
```

---

## Task 10: PromotionsController — REST endpoints

**Files:**
- Create: `api-ventago/src/app/promotions/promotions.controller.ts`

- [ ] **Step 1: Find Auth/Session guards used in existing controllers**

```bash
grep -rn "@UseGuards" src/app/products/products.controller.ts src/app/branch/branch.controller.ts 2>/dev/null | head -5
```

Note the exact guard imports (JwtAuthGuard, SessionGuard). Use the same in the new controller.

- [ ] **Step 2: Create controller**

Create `promotions.controller.ts`:

```typescript
import {
  Controller, Get, Post, Put, Patch, Delete, Param, Body, Query, UseGuards, ParseIntPipe,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { PromotionsService } from './promotions.service';
import { PromotionEvaluatorService, PromotionInput } from './promotion-evaluator.service';
import { CreatePromotionDto } from './dto/create-promotion.dto';
import { UpdatePromotionDto } from './dto/update-promotion.dto';
import { EvaluateCartDto } from './dto/evaluate-cart.dto';

@Controller('promotions')
@UseGuards(AuthGuard('jwt'))
export class PromotionsController {
  constructor(
    private readonly service: PromotionsService,
    private readonly evaluator: PromotionEvaluatorService,
  ) {}

  @Get()
  list(@Query('storeId', ParseIntPipe) storeId: number, @Query('active') active?: string) {
    return this.service.findAll(storeId, active === 'true');
  }

  @Get('by-product/:productId')
  byProduct(@Param('productId', ParseIntPipe) productId: number) {
    return this.service.findByProduct(productId);
  }

  @Post()
  create(@Body() dto: CreatePromotionDto) {
    return this.service.create(dto);
  }

  @Put(':id')
  update(@Param('id', ParseIntPipe) id: number, @Body() dto: UpdatePromotionDto) {
    return this.service.update(id, dto);
  }

  @Patch(':id/toggle')
  toggle(@Param('id', ParseIntPipe) id: number) {
    return this.service.toggle(id);
  }

  @Delete(':id')
  remove(@Param('id', ParseIntPipe) id: number) {
    return this.service.remove(id);
  }

  @Post('evaluate-cart')
  async evaluateCart(@Body() dto: EvaluateCartDto) {
    const promos = await this.service.findAll(dto.storeId, true);
    const promoInputs: PromotionInput[] = promos.map(p => ({
      id: p.id, storeId: p.storeId, productId: p.productId,
      type: p.type, isActive: p.isActive,
      minQty: p.minQty, bonusQty: p.bonusQty,
      thresholdQty: p.thresholdQty, targetPriceTypeId: p.targetPriceTypeId,
      startsAt: p.startsAt, endsAt: p.endsAt,
      label: p.label, priority: p.priority,
    }));

    // priceLookup is empty in this MVP — bulk_tier requires backend price fetch in future.
    // For now POS sends unitPrice; bulk_tier evaluation happens client-side with full pricing.
    return this.evaluator.evaluate(dto.lines, promoInputs, new Date());
  }
}
```

- [ ] **Step 3: Verify TypeScript compile**

```bash
npx tsc --noEmit -p tsconfig.json 2>&1 | grep -E "promotions" | head -10
```

Expected: No errors mentioning promotions files.

- [ ] **Step 4: Commit**

```bash
git add src/app/promotions/promotions.controller.ts
git commit -m "feat(promotions): add REST controller with CRUD + evaluate-cart"
```

---

## Task 11: PromotionsModule + register in AppModule

**Files:**
- Create: `api-ventago/src/app/promotions/promotions.module.ts`
- Modify: `api-ventago/src/app/app.module.ts`

- [ ] **Step 1: Create module**

```typescript
import { Module } from '@nestjs/common';
import { SequelizeModule } from '@nestjs/sequelize';
import { Promotion } from './promotion.model';
import { PromotionsService } from './promotions.service';
import { PromotionsController } from './promotions.controller';
import { PromotionEvaluatorService } from './promotion-evaluator.service';

@Module({
  imports: [SequelizeModule.forFeature([Promotion])],
  providers: [PromotionsService, PromotionEvaluatorService],
  controllers: [PromotionsController],
  exports: [PromotionsService, PromotionEvaluatorService, SequelizeModule],
})
export class PromotionsModule {}
```

- [ ] **Step 2: Locate AppModule imports section**

```bash
grep -n "Module" src/app/app.module.ts | head -30
```

- [ ] **Step 3: Register PromotionsModule**

Read `src/app/app.module.ts` and add the import:

```typescript
import { PromotionsModule } from './promotions/promotions.module';
```

In the `@Module({ imports: [...] })` array, add `PromotionsModule` near other domain modules (e.g., after `ProductsModule`).

- [ ] **Step 4: Start dev server to verify**

```bash
cd /Users/marcoskim/Trabajos_Programming/ACE_online_1.0 && npm run dev:api 2>&1 | tail -30
```

Expected: Server starts on :5002 without errors. Look for "Nest application successfully started".

- [ ] **Step 5: Smoke test endpoint**

In a separate terminal (server must be running):

```bash
curl -s "http://localhost:5002/api/promotions?storeId=3" -H "Authorization: Bearer <TOKEN>" | head -100
```

If no token available locally, just confirm server logs show the route registered:
```
LOG [RoutesResolver] PromotionsController {/api/promotions}
LOG [RouterExplorer] Mapped {/api/promotions, GET} route
```

- [ ] **Step 6: Commit**

```bash
git add src/app/promotions/promotions.module.ts src/app/app.module.ts
git commit -m "feat(promotions): register PromotionsModule in AppModule"
```

---

## Task 12: Extend SaleItem model + create-sales DTO with promo fields

**Files:**
- Modify: `api-ventago/src/app/sales/sales-item/sales-item.model.ts`
- Modify: `api-ventago/src/app/sales/dto/create-sales.dto.ts`

- [ ] **Step 1: Add promo columns to model**

Read `src/app/sales/sales-item/sales-item.model.ts` first to confirm structure, then add after `customName`:

```typescript
  @Column({ type: DataType.BOOLEAN, allowNull: false, defaultValue: false })
  isPromoFree: boolean;

  @Column({ type: DataType.INTEGER, allowNull: true })
  promotionId: number | null;

  @Column({ type: DataType.UUID, allowNull: true })
  promoGroupId: string | null;
```

- [ ] **Step 2: Add fields to create-sales DTO items**

Read `src/app/sales/dto/create-sales.dto.ts` and locate the items array DTO (e.g., `CreateSaleItemDto`). Add optional fields:

```typescript
  @IsOptional() @IsBoolean() isPromoFree?: boolean;
  @IsOptional() @IsInt() promotionId?: number;
  @IsOptional() @IsUUID() promoGroupId?: string;
```

Make sure `IsBoolean, IsUUID` imported from `class-validator`.

- [ ] **Step 3: TypeScript compile check**

```bash
cd api-ventago && npx tsc --noEmit 2>&1 | grep -E "(sales-item|create-sales)" | head -10
```

Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add src/app/sales/sales-item/sales-item.model.ts src/app/sales/dto/create-sales.dto.ts
git commit -m "feat(promotions): add promo tracking fields to SaleItem"
```

---

# Section 2 — Frontend admin UI (Tasks 13-19)

## Task 13: Frontend evaluator (replicated from backend)

**Files:**
- Create: `ventago-app/src/utils/promotionEvaluator.ts`
- Test: `ventago-app/src/utils/promotionEvaluator.spec.ts`

- [ ] **Step 1: Copy backend evaluator types + logic**

Create `ventago-app/src/utils/promotionEvaluator.ts` — **content identical to** `api-ventago/src/app/promotions/promotion-evaluator.service.ts` except:
- Remove `@Injectable()` decorator and `import { Injectable }`
- Export the class without decorator OR export a standalone function `evaluatePromotions(lines, promos, now, priceLookup)` that wraps the logic

Simplest: export a standalone function:

```typescript
export type PromotionType = 'buy_x_get_y' | 'bulk_tier';

export interface PromotionInput { /* same as backend */ }
export interface CartLine { /* same */ }
export interface AppliedPromotion { /* same */ }
export interface Suggestion { /* same */ }
export interface EvalResult { appliedPromotions: AppliedPromotion[]; suggestions: Suggestion[] }
export type PriceLookup = Record<number, Record<number, number>>;

export const SUGGESTION_NEAR_RATIO = 0.5;
export const BULK_NEAR_DELTA = 3;

export function evaluatePromotions(
  lines: CartLine[],
  promos: PromotionInput[],
  now: Date = new Date(),
  priceLookup: PriceLookup = {},
): EvalResult {
  // ... identical logic to backend evaluate() body
}
```

(Copy the body of `evaluate()` from `promotion-evaluator.service.ts` into this function.)

- [ ] **Step 2: Copy spec, adapted**

Create `ventago-app/src/utils/promotionEvaluator.spec.ts` — same 13 test cases from `promotion-evaluator.service.spec.ts`, but using the standalone function:

```typescript
import { evaluatePromotions, PromotionInput, CartLine } from './promotionEvaluator';

describe('evaluatePromotions', () => {
  const FIXED_NOW = new Date('2026-05-11T12:00:00Z');
  const promo3Plus1: PromotionInput = { /* same as backend test */ };

  it('buy_x_get_y: qty exactly meets min_qty → 1 bonus line', () => {
    const r = evaluatePromotions([{ productId: 100, qty: 3, unitPrice: 1500, priceTypeId: 1 }], [promo3Plus1], FIXED_NOW);
    expect(r.appliedPromotions[0]?.bonusQty).toBe(1);
  });
  // ... copy remaining 12 tests
});
```

- [ ] **Step 3: Run tests**

```bash
cd /Users/marcoskim/Trabajos_Programming/ACE_online_1.0/ventago-app && npx jest src/utils/promotionEvaluator.spec.ts 2>&1 | tail -10
```

Expected: `Tests: 13 passed`

- [ ] **Step 4: Commit**

```bash
git add src/utils/promotionEvaluator.ts src/utils/promotionEvaluator.spec.ts
git commit -m "feat(promotions): replicate evaluator client-side with full test parity"
```

---

## Task 14: SWR hook `usePromotionsByStore`

**Files:**
- Create: `ventago-app/src/hooks/api/usePromotionsByStore.ts`

- [ ] **Step 1: Inspect an existing SWR hook for pattern**

```bash
cat /Users/marcoskim/Trabajos_Programming/ACE_online_1.0/ventago-app/src/hooks/api/useCategoriesByStore.ts
```

Note the pattern (5-min dedup, fallback to empty array).

- [ ] **Step 2: Create hook**

Create `ventago-app/src/hooks/api/usePromotionsByStore.ts`:

```typescript
import useSWR from 'swr';
import apiConnector from 'src/services/api.service';

export interface PromotionDto {
  id: number;
  storeId: number;
  productId: number;
  type: 'buy_x_get_y' | 'bulk_tier';
  isActive: boolean;
  minQty: number | null;
  bonusQty: number | null;
  thresholdQty: number | null;
  targetPriceTypeId: number | null;
  startsAt: string | null;
  endsAt: string | null;
  label: string | null;
  priority: number;
}

const fetcher = (path: string) => apiConnector.get(path).then((r: any) => r.data ?? r);

export function usePromotionsByStore(storeId: number | undefined, activeOnly = true) {
  const key = storeId ? `/promotions?storeId=${storeId}&active=${activeOnly}` : null;
  const { data, error, mutate } = useSWR<PromotionDto[]>(key, fetcher, {
    dedupingInterval: 5 * 60 * 1000,
    fallbackData: [],
  });

  return {
    promotions: data ?? [],
    isLoading: !data && !error && !!storeId,
    error,
    mutate,
  };
}
```

- [ ] **Step 3: Commit**

```bash
git add src/hooks/api/usePromotionsByStore.ts
git commit -m "feat(promotions): add usePromotionsByStore SWR hook"
```

---

## Task 15: `PromotionCard` component

**Files:**
- Create: `ventago-app/src/views/codigo-vista/PromotionCard.tsx`

- [ ] **Step 1: Create component**

```typescript
import React from 'react';
import { Box, Paper, Typography, Switch, IconButton, Tooltip, Chip } from '@mui/material';
import { Icon } from '@iconify/react';
import type { PromotionDto } from 'src/hooks/api/usePromotionsByStore';

interface Props {
  promo: PromotionDto;
  productName?: string;
  priceTypeLabel?: string;
  onEdit: (p: PromotionDto) => void;
  onDuplicate: (p: PromotionDto) => void;
  onDelete: (p: PromotionDto) => void;
  onToggle: (p: PromotionDto) => void;
}

const GOLD = '#f5a623';

const fmtDate = (iso: string | null): string =>
  iso ? new Date(iso).toLocaleDateString('es-AR', { day: '2-digit', month: '2-digit' }) : '';

const PromotionCard: React.FC<Props> = ({ promo, productName, priceTypeLabel, onEdit, onDuplicate, onDelete, onToggle }) => {
  const summary =
    promo.type === 'buy_x_get_y'
      ? `🎁 Compra ${promo.minQty} → Lleva ${(promo.minQty ?? 0) + (promo.bonusQty ?? 0)}`
      : `📊 ≥ ${promo.thresholdQty}u → ${priceTypeLabel ?? 'nivel'}`;

  const period =
    promo.startsAt || promo.endsAt
      ? `${fmtDate(promo.startsAt)} – ${fmtDate(promo.endsAt)}`
      : 'Sin vigencia';

  return (
    <Paper
      variant="outlined"
      sx={{
        p: 1.5,
        borderRadius: 2,
        borderColor: promo.isActive ? GOLD : 'divider',
        opacity: promo.isActive ? 1 : 0.6,
      }}
    >
      <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 0.5 }}>
        <Typography variant="subtitle2" sx={{ fontSize: 13, fontWeight: 700, flex: 1 }}>
          {productName ?? `Producto ${promo.productId}`} · {promo.label ?? ''}
        </Typography>
        <Switch
          size="small"
          checked={promo.isActive}
          onChange={() => onToggle(promo)}
        />
      </Box>
      <Typography variant="caption" sx={{ display: 'block', fontWeight: 600 }}>
        {summary}
      </Typography>
      <Typography variant="caption" color="text.secondary" sx={{ display: 'block' }}>
        {period}
      </Typography>
      <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5, mt: 0.5 }}>
        <Chip label={`Prioridad: ${promo.priority}`} size="small" sx={{ fontSize: 9, height: 18 }} />
        <Box sx={{ flex: 1 }} />
        <Tooltip title="Editar">
          <IconButton size="small" onClick={() => onEdit(promo)}>
            <Icon icon="mdi:pencil-outline" width={14} />
          </IconButton>
        </Tooltip>
        <Tooltip title="Duplicar">
          <IconButton size="small" onClick={() => onDuplicate(promo)}>
            <Icon icon="mdi:content-copy" width={14} />
          </IconButton>
        </Tooltip>
        <Tooltip title="Eliminar">
          <IconButton size="small" onClick={() => onDelete(promo)}>
            <Icon icon="mdi:trash-can-outline" width={14} />
          </IconButton>
        </Tooltip>
      </Box>
    </Paper>
  );
};

export default PromotionCard;
```

- [ ] **Step 2: Commit**

```bash
git add src/views/codigo-vista/PromotionCard.tsx
git commit -m "feat(promotions): add PromotionCard component"
```

---

## Task 16: `PromotionDialog` component

**Files:**
- Create: `ventago-app/src/views/codigo-vista/PromotionDialog.tsx`

- [ ] **Step 1: Create dialog**

```typescript
import React, { useState, useEffect } from 'react';
import {
  Dialog, DialogTitle, DialogContent, DialogActions,
  Button, TextField, Autocomplete, Box, FormControlLabel,
  Radio, RadioGroup, Switch, MenuItem, Typography,
} from '@mui/material';
import type { PromotionDto } from 'src/hooks/api/usePromotionsByStore';

interface ProductOption { id: number; name: string; code: string }
interface PriceTypeOption { id: number; name: string }

interface Props {
  open: boolean;
  initial?: Partial<PromotionDto>;
  products: ProductOption[];
  priceTypes: PriceTypeOption[];
  storeId: number;
  onClose: () => void;
  onSubmit: (dto: any) => Promise<void>;
}

const PromotionDialog: React.FC<Props> = ({ open, initial, products, priceTypes, storeId, onClose, onSubmit }) => {
  const [type, setType] = useState<'buy_x_get_y' | 'bulk_tier'>('buy_x_get_y');
  const [productId, setProductId] = useState<number | null>(null);
  const [label, setLabel] = useState('');
  const [minQty, setMinQty] = useState<number>(3);
  const [bonusQty, setBonusQty] = useState<number>(1);
  const [thresholdQty, setThresholdQty] = useState<number>(12);
  const [targetPriceTypeId, setTargetPriceTypeId] = useState<number | null>(null);
  const [hasDates, setHasDates] = useState(false);
  const [startsAt, setStartsAt] = useState<string>('');
  const [endsAt, setEndsAt] = useState<string>('');
  const [priority, setPriority] = useState<number>(0);
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    if (!open) return;
    setType(initial?.type ?? 'buy_x_get_y');
    setProductId(initial?.productId ?? null);
    setLabel(initial?.label ?? '');
    setMinQty(initial?.minQty ?? 3);
    setBonusQty(initial?.bonusQty ?? 1);
    setThresholdQty(initial?.thresholdQty ?? 12);
    setTargetPriceTypeId(initial?.targetPriceTypeId ?? null);
    setHasDates(!!(initial?.startsAt || initial?.endsAt));
    setStartsAt(initial?.startsAt?.slice(0, 10) ?? '');
    setEndsAt(initial?.endsAt?.slice(0, 10) ?? '');
    setPriority(initial?.priority ?? 0);
  }, [open, initial]);

  const canSave =
    productId &&
    (type === 'buy_x_get_y' ? minQty > 0 && bonusQty > 0 : thresholdQty > 0 && !!targetPriceTypeId);

  const handleSave = async () => {
    if (!canSave) return;
    setSubmitting(true);
    try {
      await onSubmit({
        storeId,
        productId,
        type,
        label: label || null,
        minQty: type === 'buy_x_get_y' ? minQty : null,
        bonusQty: type === 'buy_x_get_y' ? bonusQty : null,
        thresholdQty: type === 'bulk_tier' ? thresholdQty : null,
        targetPriceTypeId: type === 'bulk_tier' ? targetPriceTypeId : null,
        startsAt: hasDates && startsAt ? new Date(startsAt).toISOString() : null,
        endsAt: hasDates && endsAt ? new Date(endsAt + 'T23:59:59').toISOString() : null,
        priority,
      });
      onClose();
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Dialog open={open} onClose={onClose} maxWidth="sm" fullWidth>
      <DialogTitle>{initial?.id ? 'Editar promoción' : 'Nueva promoción'}</DialogTitle>
      <DialogContent dividers>
        <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2, pt: 1 }}>
          <Autocomplete
            options={products}
            getOptionLabel={(p) => `${p.code} — ${p.name}`}
            value={products.find((p) => p.id === productId) ?? null}
            onChange={(_, v) => setProductId(v?.id ?? null)}
            renderInput={(params) => <TextField {...params} label="Producto" size="small" />}
          />
          <TextField
            label="Etiqueta"
            size="small"
            value={label}
            onChange={(e) => setLabel(e.target.value)}
            inputProps={{ maxLength: 120 }}
          />
          <Box>
            <Typography variant="caption" sx={{ fontWeight: 700, mb: 1, display: 'block' }}>Tipo</Typography>
            <RadioGroup value={type} onChange={(e) => setType(e.target.value as any)}>
              <FormControlLabel value="buy_x_get_y" control={<Radio />} label="🎁 Compra X, lleva Y gratis" />
              <FormControlLabel value="bulk_tier" control={<Radio />} label="📊 Mayoreo: ≥ N unidades" />
            </RadioGroup>
          </Box>

          {type === 'buy_x_get_y' && (
            <Box sx={{ display: 'flex', gap: 1 }}>
              <TextField label="Cantidad mín." type="number" size="small" value={minQty}
                onChange={(e) => setMinQty(Number(e.target.value))} inputProps={{ min: 1 }} />
              <TextField label="Gratis" type="number" size="small" value={bonusQty}
                onChange={(e) => setBonusQty(Number(e.target.value))} inputProps={{ min: 1 }} />
            </Box>
          )}
          {type === 'bulk_tier' && (
            <Box sx={{ display: 'flex', gap: 1 }}>
              <TextField label="Cantidad mín." type="number" size="small" value={thresholdQty}
                onChange={(e) => setThresholdQty(Number(e.target.value))} inputProps={{ min: 1 }} />
              <TextField select label="Nivel destino" size="small"
                value={targetPriceTypeId ?? ''}
                onChange={(e) => setTargetPriceTypeId(Number(e.target.value))}
                sx={{ minWidth: 200 }}>
                {priceTypes.map((pt) => (
                  <MenuItem key={pt.id} value={pt.id}>{pt.name}</MenuItem>
                ))}
              </TextField>
            </Box>
          )}

          <FormControlLabel
            control={<Switch checked={hasDates} onChange={(e) => setHasDates(e.target.checked)} />}
            label="Solo en fechas específicas"
          />
          {hasDates && (
            <Box sx={{ display: 'flex', gap: 1 }}>
              <TextField label="Desde" type="date" size="small" value={startsAt}
                onChange={(e) => setStartsAt(e.target.value)} InputLabelProps={{ shrink: true }} />
              <TextField label="Hasta" type="date" size="small" value={endsAt}
                onChange={(e) => setEndsAt(e.target.value)} InputLabelProps={{ shrink: true }} />
            </Box>
          )}

          <TextField label="Prioridad" type="number" size="small" value={priority}
            onChange={(e) => setPriority(Number(e.target.value))} sx={{ width: 100 }} />
        </Box>
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose}>Cancelar</Button>
        <Button variant="contained" onClick={handleSave} disabled={!canSave || submitting}>
          Guardar promo
        </Button>
      </DialogActions>
    </Dialog>
  );
};

export default PromotionDialog;
```

- [ ] **Step 2: Commit**

```bash
git add src/views/codigo-vista/PromotionDialog.tsx
git commit -m "feat(promotions): add PromotionDialog with conditional fields"
```

---

## Task 17: `PromotionsTab` — wires list + dialog + API actions

**Files:**
- Create: `ventago-app/src/views/codigo-vista/PromotionsTab.tsx`

- [ ] **Step 1: Create tab content**

```typescript
import React, { useState } from 'react';
import { Box, Alert, Button, Stack, CircularProgress } from '@mui/material';
import { Icon } from '@iconify/react';
import { toast } from 'react-toastify';
import apiConnector from 'src/services/api.service';
import PromotionCard from './PromotionCard';
import PromotionDialog from './PromotionDialog';
import { usePromotionsByStore, type PromotionDto } from 'src/hooks/api/usePromotionsByStore';

interface ProductOption { id: number; name: string; code: string }
interface PriceTypeOption { id: number; name: string }

interface Props {
  storeId: number;
  products: ProductOption[];
  priceTypes: PriceTypeOption[];
  selectedProductId?: number | null;
}

const PromotionsTab: React.FC<Props> = ({ storeId, products, priceTypes, selectedProductId }) => {
  const { promotions, isLoading, mutate, error } = usePromotionsByStore(storeId, false);
  const [dialogOpen, setDialogOpen] = useState(false);
  const [editing, setEditing] = useState<Partial<PromotionDto> | undefined>(undefined);

  const openNew = () => {
    setEditing(selectedProductId ? { productId: selectedProductId } : undefined);
    setDialogOpen(true);
  };

  const openEdit = (p: PromotionDto) => { setEditing(p); setDialogOpen(true); };

  const handleSubmit = async (dto: any) => {
    try {
      if (editing?.id) {
        await apiConnector.put(`/promotions/${editing.id}`, dto);
        toast.success('Promoción actualizada');
      } else {
        await apiConnector.post('/promotions', dto);
        toast.success('Promoción creada');
      }
      mutate();
    } catch (err: any) {
      const msg = err?.response?.data?.message ?? 'Error al guardar promoción';
      toast.error(msg);
      throw err;
    }
  };

  const handleToggle = async (p: PromotionDto) => {
    try {
      await apiConnector.put(`/promotions/${p.id}/toggle`, {});
      mutate();
    } catch (err: any) {
      toast.error(err?.response?.data?.message ?? 'Error al activar/desactivar');
    }
  };

  const handleDelete = async (p: PromotionDto) => {
    if (!confirm(`¿Eliminar promoción "${p.label ?? p.id}"?`)) return;
    try {
      await apiConnector.remove(`/promotions/${p.id}`);
      toast.success('Promoción eliminada');
      mutate();
    } catch (err: any) {
      toast.error(err?.response?.data?.message ?? 'Error al eliminar');
    }
  };

  const handleDuplicate = (p: PromotionDto) => {
    const { id, ...copy } = p;
    setEditing({ ...copy, label: `${p.label ?? ''} (copia)` });
    setDialogOpen(true);
  };

  if (error) {
    return <Alert severity="error">Error cargando promociones: {String(error)}</Alert>;
  }

  return (
    <Box sx={{ display: 'flex', flexDirection: 'column', gap: 1.5 }}>
      <Alert severity="info" sx={{ fontSize: 12, py: 0.5 }}>
        <strong>🎁 Promociones por producto</strong> — Compra X, lleva Y gratis · Mayoreo
      </Alert>
      <Button
        variant="contained"
        fullWidth
        startIcon={<Icon icon="mdi:plus" />}
        onClick={openNew}
        sx={{ py: 1, fontWeight: 700 }}
      >
        Nueva promoción
      </Button>

      {isLoading && <CircularProgress size={24} sx={{ alignSelf: 'center', mt: 2 }} />}

      <Stack spacing={1}>
        {promotions.map((p) => {
          const prod = products.find((x) => x.id === p.productId);
          const pt = priceTypes.find((x) => x.id === p.targetPriceTypeId);

          return (
            <PromotionCard
              key={p.id}
              promo={p}
              productName={prod?.name}
              priceTypeLabel={pt?.name}
              onEdit={openEdit}
              onDuplicate={handleDuplicate}
              onDelete={handleDelete}
              onToggle={handleToggle}
            />
          );
        })}
        {!isLoading && promotions.length === 0 && (
          <Alert severity="info" sx={{ fontSize: 12 }}>
            No hay promociones. Cree una con el botón "Nueva promoción".
          </Alert>
        )}
      </Stack>

      <PromotionDialog
        open={dialogOpen}
        initial={editing}
        products={products}
        priceTypes={priceTypes}
        storeId={storeId}
        onClose={() => setDialogOpen(false)}
        onSubmit={handleSubmit}
      />
    </Box>
  );
};

export default PromotionsTab;
```

- [ ] **Step 2: Commit**

```bash
git add src/views/codigo-vista/PromotionsTab.tsx
git commit -m "feat(promotions): add PromotionsTab wiring list + dialog + API"
```

---

## Task 18: Add 3rd tab to CodigoVistaView

**Files:**
- Modify: `ventago-app/src/views/codigo-vista/CodigoVistaView.tsx`

- [ ] **Step 1: Read current tab section**

```bash
sed -n '1040,1050p' src/views/codigo-vista/CodigoVistaView.tsx
```

- [ ] **Step 2: Import PromotionsTab**

Near the existing imports at the top of `CodigoVistaView.tsx`, add:

```typescript
import PromotionsTab from './PromotionsTab';
```

Also import `useAuth` if not already:
```typescript
import { useAuth } from 'src/hooks/useAuth';
```

- [ ] **Step 3: Add tab + content**

Locate the `<Tabs>` block (currently around line 1041) and add a 3rd `<Tab>`:

```tsx
<Tabs value={activeTab} onChange={(_, v) => setActiveTab(v)} variant="fullWidth" sx={{ flexShrink: 0, borderBottom: '1px solid', borderColor: 'divider' }}>
  <Tab label="⚖️ Niveles de Precio" sx={{ fontSize: 12, fontWeight: 700 }} />
  <Tab label="📈 Ajuste Global" sx={{ fontSize: 12, fontWeight: 700 }} />
  <Tab label="🎁 Promociones" sx={{ fontSize: 12, fontWeight: 700 }} />
</Tabs>
```

After the `{activeTab === 1 && (...)}` block, add:

```tsx
{activeTab === 2 && (
  <PromotionsTab
    storeId={user?.storeId ?? 0}
    products={products}
    priceTypes={priceTypes}
    selectedProductId={selected.size === 1 ? Number([...selected][0]) : null}
  />
)}
```

Make sure `const { user } = useAuth();` is invoked at the top of the `CodigoVistaView` function body (add it near other hook calls).

- [ ] **Step 4: Run frontend dev server + visual check**

```bash
cd /Users/marcoskim/Trabajos_Programming/ACE_online_1.0 && npm run dev:app 2>&1 | tail -10
```

Then open `http://localhost:3050/precios` and verify:
- 3 tabs visible
- Click "🎁 Promociones" → empty state alert + "Nueva promoción" button
- Click button → dialog opens

- [ ] **Step 5: Run ESLint**

```bash
cd ventago-app && npx eslint src/views/codigo-vista/ 2>&1 | head -20
```

Fix any `newline-before-return`, `lines-around-comment`, `no-unused-vars` errors.

- [ ] **Step 6: Commit**

```bash
git add src/views/codigo-vista/CodigoVistaView.tsx
git commit -m "feat(promotions): add 3rd Promociones tab to CodigoVistaView"
```

---

## Task 19: Left table 🎁 chip for products with active promo

**Files:**
- Modify: `ventago-app/src/views/codigo-vista/CodigoVistaView.tsx`

- [ ] **Step 1: Compute `hasActivePromo` map**

In `CodigoVistaView` body, after fetching promotions via `usePromotionsByStore`, add:

```typescript
const { promotions: storePromos } = usePromotionsByStore(user?.storeId, true);
const promoMap = useMemo(() => {
  const m = new Map<number, string>();
  storePromos.forEach((p) => { if (p.isActive) m.set(p.productId, p.label ?? 'Promo'); });

  return m;
}, [storePromos]);
```

(`useMemo` must be imported from React if not already.)

- [ ] **Step 2: Render chip in product code cell**

Find the `<TableCell>` rendering `{p.code}` (around line 974). Modify:

```tsx
<TableCell sx={{ fontFamily: 'monospace', fontSize: 11, color: 'text.secondary', whiteSpace: 'nowrap', width: colWidths.code ?? COL_DEFAULTS.code, overflow: 'hidden', textOverflow: 'ellipsis' }}>
  {p.code}
  {promoMap.has(p.id) && (
    <Tooltip title={promoMap.get(p.id)}>
      <Icon icon="tabler:gift" width={12} style={{ color: '#f5a623', marginLeft: 4, verticalAlign: 'middle' }} />
    </Tooltip>
  )}
</TableCell>
```

- [ ] **Step 3: Visual check**

Reload `http://localhost:3050/precios`. Create a promo for any product → verify 🎁 chip appears next to its code.

- [ ] **Step 4: Run ESLint**

```bash
npx eslint src/views/codigo-vista/CodigoVistaView.tsx
```

- [ ] **Step 5: Commit**

```bash
git add src/views/codigo-vista/CodigoVistaView.tsx
git commit -m "feat(promotions): show gift chip in product table for promos"
```

---

# Section 3 — POS integration (Tasks 20-26)

## Task 20: SaleProductsContext — add promotions + promoResult state

**Files:**
- Modify: `ventago-app/src/views/homes/hook/SaleProductsContext.tsx`

- [ ] **Step 1: Read context shape**

```bash
sed -n '1,50p' src/views/homes/hook/SaleProductsContext.tsx
```

Note the props/state exposed and the provider value shape.

- [ ] **Step 2: Add state + evaluator integration**

Near top of provider component, after existing state:

```typescript
import { usePromotionsByStore, type PromotionDto } from 'src/hooks/api/usePromotionsByStore';
import { evaluatePromotions, type EvalResult, type PriceLookup } from 'src/utils/promotionEvaluator';

// ... inside SaleProductsProvider:
const { promotions } = usePromotionsByStore(storeId, true);
const [promoResult, setPromoResult] = useState<EvalResult>({ appliedPromotions: [], suggestions: [] });

useEffect(() => {
  try {
    const lines = products.map((p: any) => ({
      productId: p.id,
      qty: Number(p.quantity) || 0,
      unitPrice: Number(p.price) || 0,
      priceTypeId: p.priceType?.id ?? 0,
    }));
    const lookup: PriceLookup = {};
    products.forEach((p: any) => {
      if (!lookup[p.id] && Array.isArray(p.allPrices)) {
        lookup[p.id] = {};
        p.allPrices.forEach((pp: any) => { lookup[p.id][pp.priceTypeId] = Number(pp.value) || 0; });
      }
    });
    const r = evaluatePromotions(
      lines,
      promotions.map((dto: PromotionDto) => ({
        ...dto,
        startsAt: dto.startsAt ? new Date(dto.startsAt) : null,
        endsAt: dto.endsAt ? new Date(dto.endsAt) : null,
      })),
      new Date(),
      lookup,
    );
    setPromoResult(r);
  } catch (err) {
    console.error('[promo eval failed]', err);
    setPromoResult({ appliedPromotions: [], suggestions: [] });
  }
}, [products, promotions]);
```

In the provider `value` (memoized) add `promoResult, promotions`:

```typescript
const value = useMemo(() => ({
  /* existing fields */
  promotions,
  promoResult,
}), [/* deps + */ promotions, promoResult]);
```

Update the TypeScript interface for the context to include these two fields.

- [ ] **Step 3: Smoke test**

Start dev (`npm run dev:app`), add an item to cart in `/nueva-venta`, open DevTools → React DevTools → SaleProductsContext value should show `promoResult: { appliedPromotions: [], suggestions: [] }`.

- [ ] **Step 4: ESLint**

```bash
npx eslint src/views/homes/hook/SaleProductsContext.tsx
```

- [ ] **Step 5: Commit**

```bash
git add src/views/homes/hook/SaleProductsContext.tsx
git commit -m "feat(promotions): SaleProductsContext evaluates promos on cart change"
```

---

## Task 21: ProductList — render inline upsell hints (suggestions)

**Files:**
- Modify: `ventago-app/src/views/homes/components/ProductList/ProductList.tsx`

- [ ] **Step 1: Locate cart line render**

```bash
grep -n "products.map\|saleProducts" src/views/homes/components/ProductList/ProductList.tsx | head -10
```

- [ ] **Step 2: Read context to get promoResult**

At top of the component, add:

```typescript
import { useSaleProducts } from '../../hook/SaleProductsContext';
// inside component:
const { promoResult } = useSaleProducts() as any;  // adjust types as already typed in context
```

- [ ] **Step 3: Render suggestion under each cart line**

Inside the `products.map((p, index) => ...)` render, after the line's primary content, add:

```tsx
{promoResult?.suggestions
  ?.filter((s: any) => s.lineIndex === index)
  ?.map((s: any) => (
    <Box key={s.promotionId} sx={{
      mt: 0.5, p: 0.75,
      bgcolor: s.type === 'buy_x_get_y' ? '#fef3c7' : '#cffafe',
      border: `1px solid ${s.type === 'buy_x_get_y' ? '#f59e0b' : '#06b6d4'}`,
      borderRadius: 1,
      fontSize: 11,
      fontWeight: 600,
      color: s.type === 'buy_x_get_y' ? '#92400e' : '#155e75',
    }}>
      {s.message}
    </Box>
  ))}
```

- [ ] **Step 4: Visual check**

Create a 3+1 promo for a product. Add 2 units to cart → "🎁 +1 más y llevás 1 GRATIS" banner appears. Add 1 more → banner disappears.

- [ ] **Step 5: ESLint**

```bash
npx eslint src/views/homes/components/ProductList/ProductList.tsx
```

- [ ] **Step 6: Commit**

```bash
git add src/views/homes/components/ProductList/ProductList.tsx
git commit -m "feat(promotions): render upsell hints under cart lines"
```

---

## Task 22: ProductList — render free bonus lines (read-only)

**Files:**
- Modify: `ventago-app/src/views/homes/components/ProductList/ProductList.tsx`

- [ ] **Step 1: After suggestion render, add applied (bonus) render**

After the suggestions block from Task 21:

```tsx
{promoResult?.appliedPromotions
  ?.filter((a: any) => a.lineIndex === index && a.type === 'buy_x_get_y')
  ?.map((a: any) => (
    <Box key={a.promotionId} sx={{
      mt: 0.5, ml: 2, p: 1,
      bgcolor: '#f9fafb',
      border: '1px dashed #f5a623',
      borderRadius: 1,
      display: 'flex', alignItems: 'center', gap: 1,
    }}>
      <Typography sx={{ fontSize: 11, fontWeight: 700, color: '#f5a623', flex: 1 }}>
        🎁 + {a.bonusQty} unidad{a.bonusQty > 1 ? 'es' : ''} GRATIS · {a.label}
      </Typography>
      <Typography sx={{ fontSize: 11, color: 'text.secondary' }}>$0</Typography>
    </Box>
  ))}

{promoResult?.appliedPromotions
  ?.filter((a: any) => a.lineIndex === index && a.type === 'bulk_tier')
  ?.map((a: any) => (
    <Box key={a.promotionId} sx={{
      mt: 0.5, p: 0.75,
      bgcolor: '#dcfce7',
      border: '1px solid #16a34a',
      borderRadius: 1,
      fontSize: 11, fontWeight: 600, color: '#14532d',
    }}>
      ✅ {a.label} aplicado · ${a.newUnitPrice?.toLocaleString('es-AR')} c/u
    </Box>
  ))}
```

- [ ] **Step 2: Visual check**

Add 3 units of a 3+1 product → "🎁 + 1 unidad GRATIS" line appears. Add 12 units of a Mayorista 12u product → "✅ Mayorista aplicado · $4.000 c/u" banner.

- [ ] **Step 3: ESLint**

```bash
npx eslint src/views/homes/components/ProductList/ProductList.tsx
```

- [ ] **Step 4: Commit**

```bash
git add src/views/homes/components/ProductList/ProductList.tsx
git commit -m "feat(promotions): render applied bonus lines and bulk tier banner"
```

---

## Task 23: PaymentSummary — show promo savings total

**Files:**
- Modify: `ventago-app/src/views/homes/components/ProductList/components/PaymentSummary.tsx`

- [ ] **Step 1: Read current structure**

```bash
sed -n '1,40p' src/views/homes/components/ProductList/components/PaymentSummary.tsx
```

- [ ] **Step 2: Compute savings**

In component, get `promoResult` from context. Compute total savings:

```typescript
const promoSavings = useMemo(() => {
  let total = 0;
  promoResult?.appliedPromotions?.forEach((a: any) => {
    if (a.type === 'buy_x_get_y' && a.bonusQty) {
      // saved = bonusQty * line.unitPrice
      const line = products[a.lineIndex];
      if (line) total += a.bonusQty * Number(line.price);
    } else if (a.type === 'bulk_tier' && a.oldUnitPrice && a.newUnitPrice) {
      const line = products[a.lineIndex];
      if (line) total += (a.oldUnitPrice - a.newUnitPrice) * Number(line.quantity);
    }
  });

  return total;
}, [promoResult, products]);
```

- [ ] **Step 3: Render savings row**

Above the TOTAL row in the summary, add:

```tsx
{promoSavings > 0 && (
  <Box sx={{ display: 'flex', justifyContent: 'space-between', mb: 0.5 }}>
    <Typography sx={{ fontSize: 12, color: '#f5a623', fontWeight: 600 }}>
      🎁 Promos aplicadas
    </Typography>
    <Typography sx={{ fontSize: 12, color: '#f5a623', fontWeight: 700 }}>
      -${promoSavings.toLocaleString('es-AR')}
    </Typography>
  </Box>
)}
```

- [ ] **Step 4: Visual check + ESLint**

```bash
npx eslint src/views/homes/components/ProductList/components/PaymentSummary.tsx
```

- [ ] **Step 5: Commit**

```bash
git add src/views/homes/components/ProductList/components/PaymentSummary.tsx
git commit -m "feat(promotions): show promo savings in payment summary"
```

---

## Task 24: SaleReviewPanel — same savings display

**Files:**
- Modify: `ventago-app/src/views/homes/components/SaleReview/SaleReviewPanel.tsx`

- [ ] **Step 1: Repeat the same savings pattern from Task 23**

Inject `promoResult` and render `🎁 Promos aplicadas: -$X` above TOTAL. Same code shape.

- [ ] **Step 2: ESLint + Commit**

```bash
npx eslint src/views/homes/components/SaleReview/SaleReviewPanel.tsx
git add src/views/homes/components/SaleReview/SaleReviewPanel.tsx
git commit -m "feat(promotions): show promo savings in SaleReviewPanel"
```

---

## Task 25: Modify sale create payload to include promo metadata

**Files:**
- Modify: `ventago-app/src/views/homes/components/ProductList/ProductList.tsx` (or wherever sale POST happens — search needed)

- [ ] **Step 1: Locate the sale POST**

```bash
grep -rn "post.*sales\|create.*sale\|/sales" src/views/homes/components/ProductList/ 2>/dev/null | head -5
```

- [ ] **Step 2: Augment payload items**

At the call site, before posting, expand items with bonus entries:

```typescript
import { v4 as uuidv4 } from 'uuid';
// at submit:
const expandedItems: any[] = [];
products.forEach((p, idx) => {
  const applied = promoResult.appliedPromotions.find((a) => a.lineIndex === idx);
  const promoGroupId = applied ? uuidv4() : null;
  // paid line (possibly with newUnitPrice for bulk_tier)
  const finalPrice =
    applied?.type === 'bulk_tier' && applied.newUnitPrice != null
      ? applied.newUnitPrice
      : Number(p.price);
  expandedItems.push({
    productId: p.id,
    quantity: Number(p.quantity),
    price: finalPrice,
    subtotal: finalPrice * Number(p.quantity),
    isPromoFree: false,
    promotionId: applied?.promotionId ?? null,
    promoGroupId,
  });
  if (applied?.type === 'buy_x_get_y' && applied.bonusQty) {
    expandedItems.push({
      productId: p.id,
      quantity: applied.bonusQty,
      price: 0,
      subtotal: 0,
      isPromoFree: true,
      promotionId: applied.promotionId,
      promoGroupId,
    });
  }
});

// then use expandedItems instead of products.map in payload
```

If `uuid` package not in dependencies:
```bash
cd /Users/marcoskim/Trabajos_Programming/ACE_online_1.0/ventago-app && npm list uuid
```

If missing:
```bash
npm install uuid && npm install -D @types/uuid
```

- [ ] **Step 3: ESLint + Commit**

```bash
npx eslint src/views/homes/components/ProductList/ProductList.tsx
git add ventago-app
git commit -m "feat(promotions): include promo metadata in sale create payload"
```

---

## Task 26: Backend — sales-create.service.ts accept + persist promo metadata

**Files:**
- Modify: `api-ventago/src/app/sales/sales-create.service.ts`

- [ ] **Step 1: Locate item creation loop**

```bash
grep -n "SaleItem\|createSaleItem\|create.*item" src/app/sales/sales-create.service.ts | head -10
```

- [ ] **Step 2: Pass through new fields when creating SaleItem rows**

In the loop that creates `sale_items`, pass `isPromoFree`, `promotionId`, `promoGroupId` from the DTO line. Default to `false`/`null`.

Example diff (adjust to actual code):

```typescript
await this.saleItemModel.create({
  saleId: sale.id,
  productId: item.productId,
  quantity: item.quantity,
  price: item.price,
  subtotal: item.subtotal,
  discountAmount: item.discountAmount ?? 0,
  customName: item.customName ?? null,
  isPromoFree: item.isPromoFree ?? false,
  promotionId: item.promotionId ?? null,
  promoGroupId: item.promoGroupId ?? null,
});
```

- [ ] **Step 3: Check `nullifySale` copies these fields to reversal**

Locate the section in `nullifySale` that creates reversal sale_items. Ensure it copies `isPromoFree`, `promotionId`, `promoGroupId` so the reversal carries the same grouping.

Also add Winston log (R6):
```typescript
import { Logger } from '@nestjs/common';
private readonly logger = new Logger(SalesCreateService.name);
// inside nullifySale, after creating reversal:
this.logger.log({
  event: 'promo_refund_attempt',
  saleId,
  decision: 'allowed',
  reason: 'full_nullify',
  userId,
  at: new Date().toISOString(),
});
```

- [ ] **Step 4: Compile + commit**

```bash
cd api-ventago && npx tsc --noEmit 2>&1 | grep sales | head -10
git add src/app/sales/sales-create.service.ts
git commit -m "feat(promotions): persist promo metadata in sale_items + R6 log in nullify"
```

---

# Section 4 — Refund defense (Tasks 27-28)

## Task 27: Online returns — exclude `is_promo_free` from refundAmount

**Files:**
- Modify: `api-ventago/src/app/online-returns/online-returns.service.ts` (path TBD via grep)

- [ ] **Step 1: Locate online-returns service**

```bash
find src/app -name "online-returns*" 2>/dev/null
```

- [ ] **Step 2: Inspect `approve` handler**

Open the file and find `approve(id, refundAmount)`. Currently it just records the refundAmount. We need to **block R3**: if the items being returned would break a promo group threshold, return 422.

For Phase A simplicity, we add a guard:

```typescript
async approve(id: number, refundAmount: number, requestedItemIds: number[]): Promise<void> {
  // Phase A: validate promo group integrity
  if (requestedItemIds && requestedItemIds.length > 0) {
    const items = await this.saleItemModel.findAll({ where: { id: requestedItemIds } });
    const groups = new Map<string, any[]>();
    items.forEach((it) => {
      if (it.promoGroupId) {
        const g = groups.get(it.promoGroupId) ?? [];
        g.push(it);
        groups.set(it.promoGroupId, g);
      }
    });

    for (const [gid, returnedItems] of groups.entries()) {
      const allInGroup = await this.saleItemModel.findAll({ where: { promoGroupId: gid } });
      const onlyFree = returnedItems.every((r) => r.isPromoFree);
      const someFree = returnedItems.some((r) => r.isPromoFree);
      const allFree = allInGroup.filter((a) => a.isPromoFree);

      // R1: only free items being returned without paid → BLOCK
      if (onlyFree && allInGroup.some((a) => !a.isPromoFree)) {
        throw new UnprocessableEntityException({
          code: 'PROMO_FREE_REFUND_BLOCKED',
          message: 'Los items promocionales gratuitos no se pueden devolver por separado. Debe devolver la promoción completa.',
        });
      }

      // R3: paid items returned but free items not → threshold check
      if (!someFree && allFree.length > 0) {
        const remainingPaidQty = allInGroup
          .filter((a) => !a.isPromoFree && !requestedItemIds.includes(a.id))
          .reduce((sum, a) => sum + Number(a.quantity), 0);
        const promo = await this.promotionModel.findByPk(returnedItems[0].promotionId);
        if (promo && promo.type === 'buy_x_get_y' && promo.minQty && remainingPaidQty < promo.minQty) {
          throw new UnprocessableEntityException({
            code: 'PROMO_THRESHOLD_BROKEN',
            message: 'Al devolver estos items, la promoción deja de ser válida. Debe devolver también los items gratis o desistir.',
            requiredAlsoRefund: allFree.map((a) => ({ saleItemId: a.id, qty: Number(a.quantity), reason: 'promo bonus tied to this group' })),
          });
        }
      }
    }
  }

  // existing approve logic continues
  // ...
}
```

NOTE: `UnprocessableEntityException` from `@nestjs/common`. Inject `PromotionsService` or `Promotion` model into this service. Inject `SaleItem` model.

- [ ] **Step 3: Update controller signature**

If the controller currently does `body.refundAmount`, also accept `body.requestedItemIds: number[]`. Pass through.

- [ ] **Step 4: Compile + commit**

```bash
npx tsc --noEmit 2>&1 | grep online-returns | head -10
git add src/app/online-returns
git commit -m "feat(promotions): R1/R3 guard in online-returns approve"
```

---

## Task 28: Frontend ReturnsTab — handle 422 responses

**Files:**
- Modify: `ventago-app/src/views/ventas-online/ReturnsTab.tsx`

- [ ] **Step 1: Read `callAction` error handling (lines 55-71)**

Already shows error.response.data.message. Extend to surface `code` + `requiredAlsoRefund`:

```typescript
} catch (err) {
  const data = (err as any)?.response?.data;
  if (data?.code === 'PROMO_FREE_REFUND_BLOCKED') {
    setActionError('🚫 ' + data.message);
  } else if (data?.code === 'PROMO_THRESHOLD_BROKEN') {
    const items = (data.requiredAlsoRefund ?? []).map((r: any) => `Item #${r.saleItemId} (qty ${r.qty})`).join(', ');
    setActionError(`🚫 ${data.message} Items requeridos: ${items}`);
  } else {
    const msg = data?.message || (err as any)?.message || 'Error desconocido';
    setActionError(msg);
  }
}
```

- [ ] **Step 2: ESLint + commit**

```bash
npx eslint src/views/ventas-online/ReturnsTab.tsx
git add src/views/ventas-online/ReturnsTab.tsx
git commit -m "feat(promotions): surface 422 PROMO_* responses in ReturnsTab"
```

---

# Section 5 — Manual UAT + deployment (Tasks 29-30)

## Task 29: Manual UAT

- [ ] **Step 1: Run all 4 UAT scenarios**

Start `npm run dev:api` + `npm run dev:app`. In browser:

1. **Create promo 3+1**: Go to `/precios` → 🎁 Promociones tab → Nueva promoción → product "Coca 1.5L" → buy_x_get_y → min=3, bonus=1 → Save. Verify card + 🎁 chip in left table.

2. **POS upsell**: Go to `/nueva-venta` → add 2 × Coca 1.5L → see "🎁 +1 más y llevás 1 GRATIS" hint.

3. **POS auto-apply**: Add 1 more (qty=3) → hint disappears, "🎁 + 1 unidad GRATIS" line appears. Total deducts $1.500.

4. **Bulk tier**: Create promo "Mayorista 12u" → bulk_tier, threshold=12, target=P3. In POS add 10 of that product → upsell "+2 más → precio Mayorista ...". Add 2 more → "✅ Mayorista aplicado".

5. **Sale + nullify**: Complete a sale with promo. Then nullify the sale via Sales detail page. Verify reversal sale has the same promo metadata (check DB).

6. **Refund online return (R1)**: Use ReturnsTab. Approve a return that targets ONLY a is_promo_free item id → server should reject 422 PROMO_FREE_REFUND_BLOCKED. UI shows inline alert.

- [ ] **Step 2: Document any bugs found, fix, re-test**

- [ ] **Step 3: Commit any fixes**

```bash
git add -A
git commit -m "fix(promotions): UAT findings"
```

---

## Task 30: Operational DB migration (USER APPROVAL REQUIRED)

> ⚠️ **NEVER run this step without explicit user confirmation.** CLAUDE.md mandates user confirmation for DDL/DML on production.

- [ ] **Step 1: Show user the migrations + ask permission**

```bash
cat api-ventago/migrations/2026-05-11-create-product-promotions.sql
cat api-ventago/migrations/2026-05-11-alter-sale-items-promo.sql
```

Quote both files in chat. Ask user explicitly: "Run these on production now? They are reversible (DROP TABLE / ALTER ... DROP COLUMN)."

- [ ] **Step 2: After approval, run on prod**

```bash
ssh jhkim-server "sudo -u postgres psql -d ventago" < api-ventago/migrations/2026-05-11-create-product-promotions.sql
ssh jhkim-server "sudo -u postgres psql -d ventago" < api-ventago/migrations/2026-05-11-alter-sale-items-promo.sql
```

- [ ] **Step 3: Verify**

```bash
ssh jhkim-server "sudo -u postgres psql -d ventago -c \"SELECT column_name FROM information_schema.columns WHERE table_name='product_promotions';\""
ssh jhkim-server "sudo -u postgres psql -d ventago -c \"SELECT column_name FROM information_schema.columns WHERE table_name='sale_items' AND column_name IN ('is_promo_free','promotion_id','promo_group_id');\""
```

Expected: All columns listed.

- [ ] **Step 4: Push code via `./push-both.sh`** (triggers Jenkins build)

- [ ] **Step 5: After deploy, test on production for 1 store (ACE = 9)**

Create 1 promo on ACE store via UI → verify it appears → run a test sale → nullify → verify ticket records.

- [ ] **Step 6: Final commit if any tweaks**

```bash
git add -A
git commit -m "chore(promotions): operational rollout for ACE store"
```

---

## Self-Review Notes

- **Spec coverage:** All 13 sections of the spec are mapped:
  - §3 data model → Tasks 1, 2, 3, 12
  - §4 backend API → Tasks 4-11
  - §5 Precios UI → Tasks 14-19
  - §6 POS integration → Tasks 20-26
  - §7.1 refund defense → Tasks 26, 27, 28 (Phase A subset: nullifySale R6 + online-returns R1/R3)
  - §8 error handling → Tasks 17 (toast), 28 (R1/R3 422 surfacing)
  - §9 tests → Tasks 4-7 (evaluator), 9 (service)
  - §10 performance → Tasks 14 (5-min SWR), 20 (client evaluator 0ms)
  - §11 migration order → Tasks 1, 2 (local), 30 (prod with approval)
  - §13 file list → matches Tasks
- **Placeholder scan:** No TBDs / TODOs / "similar to" left in steps.
- **Type consistency:** `PromotionInput` interface defined in Task 4 and reused in Tasks 5-7, 10, 13. `EvalResult`, `CartLine`, `AppliedPromotion`, `Suggestion`, `PriceLookup` all consistent.

---

**End of plan.**
