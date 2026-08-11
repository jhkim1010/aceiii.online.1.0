# 자문 요청 — 판매 시 códigos madre 줄이 재고 원장에서 500 을 낸다

## 운영 장애 (2026-08-11, 2회: 14:29, 15:14 / 두 지점 모두)

화면: `POST /sales` → 500 `current transaction is aborted, commands ignored until end of transaction block`

**그건 증상이다.** PostgreSQL 로그의 원본 오류:
```
ERROR: stock no puede registrarse en un codigo madre:
       product_id=364 tiene 50 variantes activas (product_branch_id=601).
       Registralo en la variante.
```
`trg_stocks_leaf_only` 트리거가 부모(código madre)에 재고 기록을 거부 → 트랜잭션 사망 →
이후 모든 문장이 aborted → 500.

실측: `products.id=364` = `[POLO] 2270 KRENCIA`, `is_parent=true`, 활성 변형 **50개**.
화면 장바구니에 그 줄이 **Total $0** 으로 있었다 (변형 수량 미선택).

스택: `SalesCreateService.applyStockLedger (sales-create.service.ts:1273)` 의 `Stocks.create`,
트랜잭션 콜백은 `:570`, 진입은 `create (:441)`.

## 문제의 성격

POS 가 **변형을 고르지 않은 madre 줄**을 장바구니에 허용했고, 백엔드가 그 부모의
`product_branch_id` 로 재고 원장을 쓰려 했다.

## 내가 하려는 수정

1. **백엔드(선검증)** — `applyStockLedger` 가 쓰기를 시작하기 **전에** 대상이 leaf 인지 확인.
   변형이 있는 부모가 재고 차감 대상으로 들어오면 **400 + 스페인어 안내**로 거부한다.
   ★ 조용히 skip 하지 않는다 — 재고 차감 없이 판매가 성사되면 원래 버그보다 나쁘다.
2. **프론트** — 변형 수량 0인 madre 줄이 F2(판매확정)를 통과하지 못하게.
3. **로그** — 트랜잭션을 처음 깨뜨린 오류가 앱 로그에 안 남는다. 이번엔 PG 로그가 있어서
   찾았지만 없었으면 원인 불명으로 끝났다.

## 묻고 싶은 것

1. **부모 줄을 어떻게 처리해야 하는가?** 세 안 중 무엇이 맞는가, 아니면 다른 답이 있는가?
   (a) 400 거부 (내 안)
   (b) 변형으로 해석 — `variantQuantities` 가 있으면 그걸로 펼쳐 leaf 에 기록
   (c) 재고 기록만 skip 하고 판매는 성사
   특히 **변형이 있는데 수량이 0인 경우**와 **변형이 아예 없는 단품(is_parent=true, 변형 0)**
   을 구분해야 하는가? 후자는 트리거가 통과시킬 것 같은데 맞는가?

2. **검증을 어디에 두어야 하는가?** `applyStockLedger` 안인가, 그보다 앞(트랜잭션 진입 전
   DTO 검증)인가? 트랜잭션 안에서 던지면 롤백은 되지만 이미 여러 INSERT 를 한 뒤다.
   `sale_idempotency` 나 outbox 와의 상호작용에서 주의할 점이 있는가?

3. **이 경로로 이미 팔린 판매가 있을 수 있는가?** 즉 과거에 madre 줄이 재고 차감 없이
   성사된 케이스가 있는지 확인할 쿼리가 있는가? (데이터 정합 점검이 필요한지)

4. **로그 개선** — 트랜잭션 첫 실패를 앱에서 남기려면 어디에 무엇을 넣어야 하는가?
   Sequelize 레벨 훅? 전역 예외 필터? 과하지 않은 최소 방법은?

5. 내가 놓친 것이 있는가? 특히 **다른 쓰기 경로**(온라인주문 발송, 생산 완료, 반품)도
   같은 방식으로 부모에 원장을 쓰려 할 수 있는가?
