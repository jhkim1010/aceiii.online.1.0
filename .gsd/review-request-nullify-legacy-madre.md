# 자문 요청 — 판매 취소(anulación)에 남아 있는 legacy 부모(código madre) 품목

앞선 자문(`.gsd/review-request-madre-other-write-paths.md`)에서 지목된 우선순위 2번이다.
1번(온라인주문 프론트 fallback)은 `api 986e0d0` / `front d08e2b5` 로 닫았다.

## 지금 상태

`stocks` 에는 DB 트리거 `trg_stocks_leaf_only` 가 걸려 있어 **활성 자식이 있는 부모**
ProductBranch 로는 원장 행을 쓸 수 없다. 판정 정의(트리거와 동일):

```
parent_id = 대상 상품 AND store_id = 같은 매장 AND status <> 'deactivated'  → 1건 이상이면 부모
```

판매 **생성**은 `processSaleItems` 에서 `findMadreProductIds`(`products/madre-guard.ts`)로
막았다(400). 온라인주문 생성도 같은 판정으로 막았다.

**남은 구멍: 판매 취소.** `sales-create.service.ts` `nullifySale()` (라인 909-967) 은
원본 `sale_items.product_id` 를 그대로 써서 재고를 복원한다:

```ts
const product = await this.productModel.findByPk(item.productId, { transaction: t });
if (product && !product.isGeneric) {
  const qty = Math.abs(item.quantity);
  if (restoreBranchId) {
    let pb = await ProductBranch.findOne({ where: { productId: item.productId, branchId: restoreBranchId }, transaction: t });
    if (!pb) pb = await ProductBranch.create({ productId: item.productId, branchId: restoreBranchId }, { transaction: t });
    await Stocks.create({ productBranchId: pb.id, stock: qty, note: `anulacion sale_id=${locked.id}` }, { transaction: t });
  } else {
    this.logger.error(`... branchId 미해결 → stocks 복원 미기록`);   // ← 원장 안 씀
  }
}
```

2026-08-08 구조 전환으로 **단품이던 상품이 부모로 바뀌었다.** 그 전에 팔린 판매를
지금 취소하면 부모 PB 에 원장을 쓰려다 트리거에 막혀 트랜잭션이 죽고 500 이 난다.

## 운영 실측 (오늘, 5434)

취소 가능한(= `status <> 'Anulado'` AND `nullified_sale_id IS NULL`) 판매 중
비제네릭 부모 품목을 포함한 것: **11건 / 19줄**.

| store | 매장 | 판매 수 | 부모 상품 수 | 기간 |
|---|---|---|---|---|
| 6 | coolsistema (활성, 사실상 테스트) | 6 | 6 | 05-06 ~ 08-07 |
| 11 | Asado (**status=0, 비활성 매장**) | 3 | 9 | 06-22 ~ 06-23 |
| 9 | ACE (활성, 실사용) | 2 | 2 | 04-21, 06-01 |

★ 자식 수 분포가 갈린다:
- store 11 의 9개 상품은 **활성 자식이 정확히 1개씩**이다(BEBIDAS/MINUTAS 등 식당 메뉴).
  이 상품들은 `ProductBranch` 행 자체가 없다(부모·자식 모두).
- store 9 의 2개는 자식 2개씩, store 6 은 4~16개.

부모 PB 잔액은 전부 정리돼 있다 — `stocks` net 0(2026-08-08 `migracion leaf-only`
짝 보정), `v_stock_balance_drift` 0행. 즉 **정합성 보정 대상은 없다.**

## 물어보는 것

**Q1. 정책: 전면 400 거부인가, "활성 자식이 정확히 1개면 그 자식으로 복원"을 허용하는가?**
직전 자문은 "자동 전개 금지 — 원본에 변형별 배분 정보가 없다"였다. 그 근거는 자식이
여럿일 때 성립한다. 자식이 **정확히 1개**면 목적지가 유일한데도 여전히 금지가 맞는가?
(해당 케이스가 실제로 9개 상품 = 3건 판매 있고, 전부 비활성 매장이라는 점도 감안.)
- 1-자식 전개를 허용하면 "그 자식이 원래 팔린 그 물건인가"를 보증할 수 있는가?
- 금지가 맞다면, 비활성 매장이 다시 활성화됐을 때 그 3건은 영구히 취소 불가로 남는데
  운영 보정 경로(수기 조정)로 충분한가?

**Q2. 거부 범위 — 회귀 방지.** 지금 **성공하는** 취소를 새 가드가 막으면 회귀다.
현재 원장을 아예 쓰지 않는 두 경우가 있다:
  (a) `product.isGeneric` → 복원 자체를 건너뜀
  (b) `restoreBranchId` 가 null → ERROR 로그만 남기고 원장 미기록(취소는 성공)
가드는 (a)(b) 를 통과시키고 "실제로 `Stocks.create` 에 도달할 부모 줄"만 막아야 한다는
판단인데 맞는가? 특히 (b) 는 "재고가 복원되지 않는데 취소는 된다"는 기존 결함이라
여기에 400 을 얹는 게 오히려 나은가, 아니면 별건으로 둬야 하는가?

**Q3. 부분 거부 vs 전량 거부.** 한 판매에 부모 줄 1개 + 정상 줄 3개면?
전량 거부(판매 자체를 취소 불가로)만 가능해 보인다 — 역분개는 판매 단위이고
일부 줄만 빼면 금액이 안 맞는다. 다른 선택지가 있는가?

**Q4. 가드 위치.** 트랜잭션 진입 **전**(락 없이, `original.items` 로)이 맞는가,
아니면 트랜잭션 안 락 이후가 맞는가? 진입 전이면 락을 안 잡고 빨리 끝나지만
판정과 실행 사이에 상품 구조가 바뀔 수 있다(무시 가능한 경합인가?).
판매 생성 쪽은 트랜잭션 안(읽기·검증 단계)에서 판정한다 — 일관성을 위해 맞춰야 하는가?

**Q5. 안내 문구.** 생성 경로의 `madreRejectionMessage`("Elegí color y talle…")는
취소 화면에서 뜻이 안 통한다(사용자가 고를 것이 없다). 취소 전용 문구를 따로 두는 게
맞는가? 그렇다면 운영자가 무엇을 해야 하는지(지원 문의 / 수기 재고 조정)까지
문구에 넣어야 하는가, 아니면 코드만 남기고 프론트에서 분기해야 하는가?

**Q6. 같은 형태의 다른 취소 경로가 더 있는가?** 리포에서 `Stocks.create` 는
판매 생성(1227) / 판매 취소(952) / 온라인주문(online-order-stock.service:321) 세 곳뿐이고
raw INSERT 는 `reportsStocksCockpit.service`(재고 조정) 두 곳이다. 부분 환불·반품·
`devolución` 처럼 취소와 같은 모양인데 내가 못 찾은 경로가 있는가?

**Q7. 운영 보정 목록을 코드가 남겨야 하는가?** 거부할 때마다 WARN 으로
`saleId + productIds` 를 남기면 실제 시도된 건만 모인다. 아니면 위 실측 쿼리를
`.gsd/` 문서에 남기는 것으로 충분한가?

## 제약

- `stocks` 는 append-only(`trg_stocks_immutable`). 보정은 반대 부호 행으로만.
- 잔액은 `trg_stock_balances_apply` 가 같은 트랜잭션에서 `stock_balances` 에 반영.
- `products.stock` 은 강등됨 — 신규 경로에서 참조 금지.
- 정책 공용화 금지 전례: un-ship 정책을 공용 헬퍼에 넣었더니 취소 경로가 회귀했다.
  판정(`madre-guard.ts`)만 공용, 처리는 경로별.

---

# CODEX 회신 + 내 검증 (2026-08-11)

## 결론: 전량 400 거부. 자식이 1개여도 자동 전개하지 않는다.

### Q1 정책 — 거부 (CODEX 와 같음, 근거는 내가 다시 세웠다)
"활성 자식이 정확히 1개"는 **목적지의 유일성**만 준다. 그 자식이 **과거에 팔린 그 물건**
이라는 보장이 아니다 — 판매 후 생성된 자식일 수도, 다른 자식이 비활성화되고 남은
하나일 수도, 구조 전환 과정에서 단위가 바뀌었을 수도 있다. 게다가 자식이 나중에
추가되면 **같은 과거 판매가 취소 시점에 따라 다른 상품으로 복원**된다(재현 불가능).
잘못 복원하면 조용한 재고 오염이고, 거부는 최소한 눈에 보인다.

### Q2 거부 범위 — 실제로 원장에 닿는 줄만 (회귀 방지)
`restoreBranchId` 없음 / 제네릭은 애초에 `Stocks.create` 에 닿지 않으므로 통과시킨다.
막으면 **지금 되는 취소가 안 되게 되는** 회귀다.
★ CODEX 지적 수용: `restoreBranchId` 미해결 시 "재고 복원 없이 취소 성공"은 그 자체로
결함이다. 다만 그 경우 부모만 거부할 근거가 없으므로 **별건**으로 남긴다(아래 남은 일).

### Q3 부분 거부 — 불가. 판매 단위 전량 거부.
역분개는 판매 단위이고 금액·품목 합계가 함께 움직인다. 일부 줄만 빼면 원본을
`Anulado` 로 표시하는 의미가 깨진다.

### Q4 위치 — 트랜잭션 안, 락·상태 재검사 **뒤**, 채번 **앞**
채번 뒤로 미루면 거부될 취소가 매장 advisory lock 을 잡고 번호를 하나 태운다.
경합(판정과 INSERT 사이에 자식 생성 커밋)은 일반 SELECT 로는 닫히지 않는다 →
**트리거 오류를 같은 안내로 변환**하는 최종 방어선을 같이 뒀다(`isMadreLedgerViolation`).
판정은 SQLSTATE 23514 **와** 문구 `codigo madre` 가 **둘 다** 맞을 때만 참이다 —
코드만 보면 다른 CHECK 제약을, 문구만 보면 다른 계층 오류를 덮는다.

### Q5 문구 — 취소 전용 + `code`
생성 경로의 "Elegí color y talle…" 재사용 금지(취소 화면엔 고를 입력이 없다).
`code: SALE_NULLIFY_LEGACY_PARENT_STOCK` + `productIds` 를 본문에 싣되,
`message` 만 봐도 뜻이 통하게 뒀다(구버전 프론트·직접 호출에서 설명이 사라지지 않도록).
프론트는 이미 `err.response.data.message` 를 토스트로 띄운다 — 프론트 변경 불필요.

### Q6 ★ 내 전제가 틀렸다 — 쓰기 경로는 3곳이 아니다
`Stocks.create` 만 grep 해서 3곳이라고 썼는데, 실제로는 `this.stockModel.create` /
`Stocks.bulkCreate` 로 쓰는 곳이 더 있다. 전수:

| 파일 | 성격 |
|---|---|
| `sales/sales-create.service.ts` (2) | 판매 생성 / 취소 — **가드 완료** |
| `online-orders/online-order-stock.service.ts` (1) | hold/commit/release/reverse 공용 — 생성만 가드 |
| `products/productStock.service.ts` (9) | 미검토 |
| `stocks/stocks.service.ts` (4) | 미검토 |
| `production/work-orders/work-order.service.ts` (2) | 미검토 (변형 배분 모델 선행) |
| `suspended-sales/suspended-sales.service.ts` (1, bulkCreate) | 미검토 |
| `code-import/code-import.service.ts` (1) | 미검토 |
| `reports/reportsStocksCockpit.service.ts` (2, raw INSERT) | 재고 조정 — 미검토 |

### Q7 로그 + 정본 쿼리 — 둘 다
거부 시 구조화 WARN(`sale_nullify_blocked`)을 남긴다: 실제 **시도된** 건만 모인다.
전체 backlog 의 정본은 아래 재실행 가능한 SQL 이다(로그는 보존기간이 있어 정본이 못 된다).

## 운영 보정 대상 — 정본 쿼리 (기준일 2026-08-11 / 5434)

```sql
WITH madre AS (
  SELECT DISTINCT p.parent_id AS id
    FROM products p
   WHERE p.parent_id IS NOT NULL AND p.status <> 'deactivated'
)
SELECT s.id AS sale_id, s.store_id, s.daily_number, s.sale_date::date, s.status,
       si.product_id, pr.name AS producto, si.quantity,
       (SELECT count(*) FROM products c
         WHERE c.parent_id = si.product_id AND c.status <> 'deactivated') AS hijos_activos
  FROM sales s
  JOIN sale_items si ON si.sale_id = s.id
  JOIN products  pr ON pr.id = si.product_id
  JOIN madre      m ON m.id = si.product_id
 WHERE s.status <> 'Anulado'
   AND s.nullified_sale_id IS NULL
   AND coalesce(pr.is_generic, false) = false
 ORDER BY s.store_id, s.id;
```

- 제외 조건: 이미 취소된 판매 / 역분개 판매 / 제네릭 상품.
- **지점 미해결(restoreBranchId=null) 판매는 이 목록에 있어도 실제로는 거부되지 않는다** —
  그 경로는 원장을 쓰지 않기 때문이다(별건 결함).
- 보정 완료 기대값: 0행 (또는 해당 판매가 `Anulado` 로 전이).

측정값(2026-08-11): **11건 / 19줄**
- store 6 coolsistema(사실상 테스트) 6건 · store 11 Asado(**비활성 매장**) 3건 ·
  store 9 ACE(실사용) 2건 (2026-04-21, 2026-06-01)
- 부모 PB 잔액은 이미 정리돼 있다 — `stocks` net 0(2026-08-08 `migracion leaf-only`
  짝 보정), `v_stock_balance_drift` 0행. **정합성 보정 대상은 없다.**

## 온라인주문 역방향 경로 — 위험은 실재, 현재 대상 0건 (실측)

CODEX 지적대로 `cancelOrder`→`releaseHold`/`reverseSale`, `approveReturn`→`reverseSale`,
`revertOrder`→`applyUnship` 이 전부 `online_order_items.product_id` 로 **양수** 원장을 쓴다
(`applyStockMovement` 공용). 주문 생성 당시 leaf 였던 상품이 나중에 부모가 되면 같은 500 이다.

**실측: 부모 품목을 가진 온라인주문은 0건**(전체 주문 11건). 지금 재현되지 않는다.
★ 여기에 일괄 400 을 걸면 **이미 잡힌 hold 를 풀지 못하는 회귀**가 난다(직전 un-ship 전례).
막는 것이 아니라 "뜻이 통하는 오류로 바꾸는" 쪽이 맞다 — `isMadreLedgerViolation` 을
`madre-guard.ts` 에 공용으로 뒀으므로 그때 그대로 쓸 수 있다.

## 남은 일 (이번에 하지 않은 것)

1. **지점 미해결 취소가 조용히 재고를 잃는다** — 비제네릭인데 `restoreBranchId` 가 없으면
   ERROR 로그만 남기고 취소가 성공한다. 부모/자식 구분 없는 문제라 이번 가드에 섞지 않았다.
   전체 비제네릭에 일관되게(차단 or 관리자 승인) 처리해야 한다.
2. **관리자 승인형 "재무 취소 + 재고 복원 생략"** — 위 11건이 영구 취소 불가로 남는다.
   자동 1-자식 전개 대신 운영자가 사유와 함께 명시 승인하는 경로가 필요하다.
3. **`approveReturn` 의 부분 환불 ↔ 전량 재고 복원** — `refundAmount` 는 부분일 수 있는데
   `reverseSale(order)` 는 주문 **전체** 재고를 되돌린다(코드 확인함, `:2074`/`:2077`).
   madre 와 별개 결함으로 보인다. 미확인: 부분 환불이 실제 운영에서 쓰이는지.
4. **미검토 쓰기 경로 8종** (위 표) — "모든 INSERT 선검증"은 아직 완성되지 않았다.
5. **생산 경로는 단순 400 금지** — UI 일부가 일부러 código madre 만 고르게 한다.
   변형 배분 모델이 선행돼야 한다.

## 참고: 부모 PB 에 남은 이상값 하나 (이번 범위 밖)

`ProductBranch` 249 (product 281, branch 6): `reservado = -44`, `total_traspaso = -44`,
`on_hand = -44`, `available = 0`. 원장 net 은 0 이고 `v_stock_balance_drift` 도 0행이라
불변식은 깨지지 않았지만 **음수 예약**은 정상값이 아니다. 원인 미확인.
