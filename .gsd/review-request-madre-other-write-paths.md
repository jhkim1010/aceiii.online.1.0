# 자문 요청 (후속) — 부모(código madre)에 재고 원장을 쓰는 **다른 경로**가 더 있는가

이전 요청 `.gsd/review-request-sales-madre-500.md` 의 **질문 5** 만 떼어낸 후속이다.
판매 경로(`SalesCreateService.applyStockLedger`)는 이미 고쳤다(`api 3915ae4`):
쓰기 전에 leaf 여부를 확인하고, 변형이 있는 부모가 들어오면 400 으로 거부한다.
판정은 트리거와 같은 정의 — `is_parent` 플래그가 아니라 **활성 자식 수**
(`parent_id` = 이 상품 AND 같은 store AND `status <> 'deactivated'`).

## 물어보는 것

`trg_stocks_leaf_only` 는 `stocks` 에 대한 **모든** INSERT 에 걸린다.
판매 말고도 `stocks` 에 쓰는 경로가 리포에 최소 다음이 있다:

- `src/app/online-orders/online-order-stock.service.ts:321` — `Stocks.create` (온라인주문 발송)
- `src/app/sales/sales-create.service.ts:998` — `Stocks.create` (판매 취소/역분개로 보임)
- `src/app/sales/sales-create.service.ts:1273` — `applyStockLedger` (판매, **수정 완료**)
- `src/app/production/work-orders/work-order.service.ts` — 생산 완료
- `src/app/reports/reportsStocksCockpit.service.ts:1310,1319` — raw `INSERT INTO stocks`

**질문 1.** 이 중 어떤 경로가 **부모 ProductBranch** 를 대상으로 삼을 수 있는가?
즉 사용자가 변형을 고르지 않은 상태로도 그 경로에 진입할 수 있는가?
각 경로에서 `product_branch_id` 가 어디서 오는지 따라가서 판단해 달라.
(온라인주문 카트, 반품, 생산 BOM 산출물, 재고 조정 화면 각각 다르다.)

**질문 2.** 실패 시 결과가 판매와 같은가? 즉 트랜잭션이 죽고 **원본 오류가 앱 로그에
남지 않는** 같은 형태인가, 아니면 그 경로는 오류를 제대로 노출하는가?

**질문 3.** 가드를 **공용 헬퍼로 뽑아** 모든 쓰기 경로에 걸어야 하는가, 아니면
경로별로 다른 처리(400 거부 vs 변형 전개 vs 애초에 불가능)가 맞는가?
※ 직전 사례 경고: un-ship 정책을 공용 헬퍼에 넣었더니 **취소 경로가 회귀**했다.
공용화가 오히려 위험한 경우를 먼저 지적해 달라.

**질문 4.** `reportsStocksCockpit.service.ts` 의 raw INSERT 두 곳은 재고 조정으로 보이는데,
여기서 부모를 대상으로 하면 어떤 화면이 500 이 되는가? 이미 사고가 났을 수 있는가?

**질문 5.** 과거에 **부모에 재고 원장이 실제로 들어간 행**이 있는지 확인하는 쿼리를 달라
(트리거 도입 전 데이터일 수 있다). 있으면 정합성 보정이 필요하다.

## 배경 제약

- `stocks` 는 append-only 원장(`trg_stocks_immutable`). 보정은 반대 부호 행으로 한다.
- 잔액은 `trg_stock_balances_apply` 가 같은 트랜잭션에서 `stock_balances` 에 반영한다.
- `products.stock` 은 Phase 70-06 에서 강등 — 신규 경로에서 참조 금지.
- 조회·기록은 항상 `product_branch_id` 기준. `stocks.product_id` 컬럼은 **없다**.

---

# CODEX 회신 + 내 실측 검증 (2026-08-11)

## 결론: 판매 말고도 부모에 원장을 쓰는 경로가 있다. **하나는 지금 재현 가능한 500 이다.**

### ★ [HIGH] 온라인주문 — 프론트에 **명시적 부모 fallback** 이 있다 (실측 확인)

`ventago-app/.../EnvioRegistroModal.tsx:110-122` — variant 전개 결과가 0건이면
**부모 `p.id` 를 한 줄로 보낸다**:

```ts
// 분해 결과가 0개면 parent 한 건으로 fallback
return rows.length > 0 ? rows : [{ productId: p.id, ... }]
```

경로를 끝까지 따라가 확인했다:
`online_order_items.product_id`(부모)
→ `holdStock()` — **주문 생성 트랜잭션 안에서** 호출 (`online-orders.service.ts:427`)
→ `ProductBranch.findOrCreate({productId: 부모})` (`online-order-stock.service.ts:307`)
→ `Stocks.create` (`:321`) → `trg_stocks_leaf_only` 거부 → **500**

즉 판매와 **같은 결함**이고, 실패 시점은 발송이 아니라 **주문 생성**이다.
판매 쪽은 `api 3915ae4` 로 막았지만 이 경로는 열려 있다.

다만 실패 형태는 판매보다 낫다 — 서비스가 원본 오류를 ERROR 로 남기고 재전파하므로
`current transaction is aborted` 가 원인을 덮지 않는다 (`online-orders.service.ts:457`).

### [HIGH] 판매 취소/역분개 — 신규 판매는 안전, **과거 데이터는 여전히 위험**
`sales-create.service.ts:951-998`. 원본 `sale_items.product_id` 를 그대로 쓴다.
수정 전·트리거 도입 전에 만들어진 부모 품목 판매를 취소하면 같은 500 이 난다.
★ 여기서 부모를 변형으로 자동 전개하면 **안 된다** — 원본에 변형별 배분 정보가 없다.
   "legacy parent sale" 로 명시 거부하고 운영 보정 대상으로 남기는 편이 안전하다.

### [HIGH] 생산 완료 — 완제품·BOM 소비재 **양쪽** 다 부모 도달 가능
`work-order.service.ts:197`(소비재) / `:218`(완제품). `mes_work_orders.product_id` 에
leaf 제약이 없고, UI 일부(`LotesTab.tsx:89`)는 **일부러 código madre 만** 고르게 한다.
★ 여기에 400 을 걸면 생산 업무 자체가 막힐 수 있다. 변형 배분 모델이 선행돼야 한다.

### 재고 조정 — 정상 화면은 안전, API 는 무방비
`reportsStocksCockpit.service.ts:1262,1302`. 화면은 `v_product_hijo` 로 leaf PB 만
셀에 넣고 PB 가 유일하지 않으면 `productBranchId=0` 으로 조정을 막는다. 그러나 API 는
소유 매장만 확인하고 leaf 여부를 안 본다 → 직접 호출·구버전 프론트로는 500 가능.

## 공용 헬퍼 여부 — **판정만 공용, 처리는 경로별**
직전 un-ship 회귀와 같은 위험. 공용화할 것은 leaf 판정 함수뿐이고
(`parent_id = 대상 AND store_id = 대상 AND status <> 'deactivated'`),
400 거부 / 변형 전개 / 역연산 우선 중 무엇을 할지는 경로마다 다르다.
특히 online-order 의 release/reverse/un-ship 에 일괄 400 을 걸면
**이미 잡힌 hold 를 풀지 못하는 회귀**가 난다.

## 과거 데이터 — **보정 불필요 (실측)**
운영에서 "현재 부모인 상품에 붙은 원장 행"을 전수 조회했다: 9개 상품, 하지만
**net 이 전부 0** (2026-08-08 구조 전환의 `migration_transfer` 짝 보정으로 이미 상쇄).
미해소 잔액 0 → 정합성 보정 대상 없음.

## CODEX 가 추가로 지목한 미검토 경로
`code-import`, `productStock.service`, 공용 `stocks.service` 의 생성·보정·지점이동.
이번 다섯 경로만 봐서는 "모든 INSERT 선검증" 이 완성되지 않는다.

## 남은 일 (우선순위)
1. **온라인주문 프론트 부모 fallback 제거** — 가장 작고 가장 급하다. 판매와 같은 결함이고
   지금 재현 가능하다. 변형 미선택이면 전송을 막고 안내한다(조용히 skip 금지).
2. 판매 취소의 legacy 부모 품목 — 명시적 거부 + 운영 보정 목록
3. 재고 조정 API 경계에서 부모 PB 400
4. 생산 — 변형 배분 모델 설계 후 (여기만 단순 400 금지)
