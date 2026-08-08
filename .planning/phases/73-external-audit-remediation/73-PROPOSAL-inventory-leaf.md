# 제안 — 재고는 leaf 에만 붙는다 (madre PB 문제의 구조적 해결)

> **[2026-08-07 집행 완료]** 사용자 승인("아직 아무도 안 쓴다, 지금 다 고치자") 하에
> **A + B 를 배포했다** (api #639·#641). 남은 것은 §9 참조.
>
> | 항목 | 상태 |
> |---|---|
> | `is_parent` 정정 (자식 0 → leaf) | ✅ 양쪽 DB, UPDATE 4행 |
> | 트리거 `trg_stocks_leaf_only` | ✅ 양쪽 DB (매장 스코프) |
> | 전환 가드 (leaf→madre, 잔량 있으면 거부) | ✅ api #639 |
> | 탐지기 `v_stock_on_non_leaf` | ✅ 현재 10행 (legacy) |
> | MOV± 모집단을 rowsJoin 과 일치 | ✅ api #641 → **전 조합 항등식 위반 0** |
> | `operation_date` 매장 영업일 트리거 | ✅ 양쪽 DB + api #641 |
> | `stocks.source` + Offset 판정 | ✅ 양쪽 DB + api #641 |
> | 제품 family 불변식 (§11) | ✅ 양쪽 DB — 자기참조/깊이2/크로스매장 금지 + `v_product_hijo` |
> | 리포트 뷰 leaf 필터 (§12) | ✅ 양쪽 DB — **틀린 숫자 4건 정정** |
> | legacy 원장 중립화 (§12) | ✅ 양쪽 DB — 보정행 5건, **탐지기 0 달성** |
> | **리포트를 `v_product_hijo` 위로 리팩터** (§11 끝) | ⏳ 정확성 아닌 재발방지 — 다음 세션 |
> | **D (default variant 강제)** | ⏳ 별도 phase |


작성 2026-08-07. 근거: 운영 실측 + 업계 표준 조사 + CODEX 자문.
발단: 사용자 질문 "각 매장에서 위반건은 없는가" → cod.madre 뷰 ±40 항등식 위반 발견(§1-sexies).

---

## 1. 지금 구조

```
products (id, sku, is_parent BOOLEAN, parent_id → products.id)   ← madre 와 hijo 가 같은 테이블
    ↑ ProductBranch(product_id → products.id, branch_id)          ← is_parent 무관하게 붙는다
        ↑ stocks(product_branch_id)                               ← append-only 원장
```

`products_parent_id_fkey` 는 **자기참조**, madre/hijo 구분은 `is_parent` **불리언 플래그** 뿐이다.
`ProductBranch_product_id_fkey` 가 `products(id)` 전체를 가리키므로 **madre 에도 PB 가 붙는다.**

## 2. 실측된 피해

madre 자신의 PB 에 쓰인 원장 (전수):

| type | 행 | net | 제품 | 기간 |
|---|---|---|---|---|
| NULL (판매/입고) | 21 | −64 | 9 | 2026-04-21 ~ **2026-08-07 (오늘)** |
| suspend (예약) | 18 | +44 | 3 | |
| transfer (movido) | 2 | 0 | 1 | ← ±40 항등식 위반의 직접 원인 |
| suspend(online) | 1 | −1 | 1 | |

9개 중 **7개는 활성 자식이 있는데도** madre PB 에 기록됐다.
2개(`251532001`, `25193444001`)는 활성 자식 0 → madre 가 **정상 판매 단위**다.

쓰기 경로에 `is_parent` 가드가 **하나도 없다**. PB 온디맨드 생성 22곳 / 9개 서비스.

## 3. 업계는 어떻게 하나

| 시스템 | 재고가 붙는 곳 | 핵심 장치 |
|---|---|---|
| **Shopify** | `InventoryItem` ↔ `ProductVariant` **1:1**. 제품 레벨 재고 없음 | 모든 제품에 최소 1개 variant("Default Title") |
| **Odoo** | `stock.quant` → `product.product`(variant). template 수량은 **계산된 합계** | 모든 template 에 최소 1개 variant |
| **Magento** | configurable 은 재고 없음, **simple SKU** 가 판매·재고 단위 | |
| **WooCommerce** | 부모/variation 재고 **혼용 허용** ← 예외 | 그 유연성이 우리 문제와 같은 유형 |

공통 패턴: **재고는 언제나 leaf 에만 붙고, leaf 는 항상 존재한다.**

## 4. ★ CODEX 의 핵심 지적 — 테이블 분리만으로는 부족하다

> 진짜 결함은 단일 테이블이 아니라 **재고 FK 가 leaf 판매 단위로 제한되지 않은 것**이다.
> 테이블을 분리해도 `stocks`/`PB` 가 madre 를 참조하면 재발한다.

그리고 근본 원인을 이렇게 짚었다 — 나도 동의한다:

> **"자식 0 madre 는 판매 단위, 자식 생성 후에는 집계 노드"** — 시간에 따라 정체성이 바뀌는
> 하이브리드가 근본 원인이다.

업계가 이걸 피하는 방법이 바로 **default variant 자동 생성**이다. 단품도 leaf 를 하나 갖게 해서
"madre 가 판매 단위인 경우"를 아예 없앤다.

## 5. 선택지와 권고

| | 내용 | 비용 | 재발 차단 |
|---|---|---|---|
| **A** | 리포트만 정합화 — cod.madre 뷰가 madre PB + 자식 PB 를 **모든 컬럼**에서 함께 집계 | 낮음 | ✗ |
| **B** | A + 쓰기 가드 (서비스 + DB 트리거: 활성 자식 있으면 원장 거부) | 중간 | ○ |
| **C** | madre/hijo **테이블 분리** (사용자 제안) | 높음 | △ |
| **D** | 모든 판매 가능 제품에 **default variant 강제** → 재고는 항상 leaf 에만 | 높음 | ◎ |

**CODEX 권고 순서: A → B → D.** C 는 비용이 크면서 핵심 불변식을 자동 보장하지 않아 우선순위가 낮다.

- A 는 즉시 ±40 을 복구하지만 **잘못된 쓰기를 계속 허용**하므로 종착점이 될 수 없다.
- B 는 긴급 봉쇄. 단 "활성 자식 존재" 검사와 자식 활성화·재고 쓰기를 **같은 잠금 규약으로 직렬화**해야
  TOCTOU 가 없다. `CHECK` 제약은 다른 테이블의 자식 존재를 못 보므로 부적합 → **트리거**.
- D 가 최종형. SKU·PB·재고·판매·이동이 **오직 variant 만** 참조한다.

### 최소 불변식 (CODEX)

> 모든 stock event 는 **정확히 하나의 inventory leaf** 를 가리킨다.
> leaf 는 자식을 가질 수 없고, catalog parent 는 **절대** PB/stock event 를 가질 수 없다.
> 일반 상품도 정확히 하나의 default leaf 를 갖는다.
> leaf→parent 전환은 기존 잔량을 원장 이전하는 **같은 트랜잭션에서만** 허용한다.

## 6. D 이관 전략 (append-only 를 지킨다)

1. 쓰기 일시 차단
2. default variant + PB 생성
3. madre 별 순잔량 산출
4. **madre 에 반대 부호 보정행**, **default variant 에 동액 이전행** — 같은 트랜잭션
5. `UPDATE`/`DELETE` 금지(`trg_stocks_immutable`). `migration_transfer` 같은 상호 참조
   보정 이벤트로 감사 추적성 보존

**위험**: 기준시점 동시 쓰기 / 중복 실행 / 음수잔량 정책 / 원가·lot·serial 귀속 /
**과거 리포트 의미 변경**. 사전·사후 family 합계 대사가 필수.
자동 이관은 "어느 자식에 귀속할지" 근거가 없으므로, 활성 자식이 있는 7개는
**수동 매핑**이 필요하다(CODEX). 자식 0 인 2개는 정상 판매 단위이므로 예외 유지.

## 7. 내 권고

**A 를 먼저 하되 단독으로 끝내지 않는다. B 를 같은 주에 붙인다.**
D 는 별도 phase 로 계획한다 — 이관 위험이 실제 재고 숫자에 닿기 때문이다.

C(테이블 분리)는 사용자 직관이 **방향은 맞다**. 다만 업계도 "두 테이블"이 아니라
**"재고는 leaf 에만"** 을 지키는 방식으로 푼다 — 그게 D 다. C 를 하더라도 D 의 불변식이 없으면
같은 문제가 재발한다.

## 8. 미해결 (같이 결정할 것)

- `stocks.operation_date` DB DEFAULT 가 `CURRENT_DATE`(UTC) — 현지 저녁 입고가 다음 날로 저장될 수 있다
  (실측 오염 22행). §1-quater 참조
- Offset 의 `source` 컬럼 — note 접두어는 약한 식별자다. §1-quinquies 참조

세 건 모두 **쓰기 경로/스키마** 라 함께 결정하는 것이 좋다.

---

출처: [Odoo 18 Product variants](https://www.odoo.com/documentation/18.0/applications/sales/sales/products_prices/products/variants.html) ·
[Shopify ProductVariant](https://shopify.dev/docs/api/admin-rest/latest/resources/product-variant) ·
[Shopify: 1-1 relation between inventory item and variant](https://community.shopify.dev/t/1-1-relation-between-inventory-item-and-variant/35875)

---

## 9. ⏳ 남은 것 — legacy 원장 이관 (승인 대기)

`v_stock_on_non_leaf` 가 **10 (제품×지점) 행**을 잡고 있다. 활성 자식이 있는 제품의
madre PB 에 남은 과거 원장이다. 트리거는 **앞으로만** 막으므로 이 행들은 그대로다.

| 매장 | SKU | 지점 | 잔량 | 성격 |
|---|---|---|---|---|
| 6 | `251843001` | 6 / 16 | −40 / +40 | movido sale#28 이 madre 에 기록됨 |
| 6 | `2542001` | 6 | +44 | suspend(예약) hold/release 불균형 |
| 9 | `25193443001` | 14 | −10 | POS 판매가 madre 에 차감됨 |
| 9 | `25193545001` | 15 | −10 | 〃 |
| 6 | 나머지 6행 | | 0 | 제품 생성 시 남은 0-재고 행 |

**지금 화면에는 영향이 없다.** 두 리포트 뷰 모두 madre PB 를 안 읽고, MOV± 도 이제
자식만 세므로 **전 조합 항등식 위반 0** 이다. 즉 이 행들은 "보이지 않는 고아 원장" 이다.

이관하려면 재고 숫자가 바뀌므로 승인이 필요하다. 선택지:

- **(가) 중립화** — madre PB 에 반대 부호 보정행을 append 해 잔량 0 으로.
  화면 값은 안 바뀐다(이미 안 읽으므로). 탐지기가 0행이 된다.
  단 −10 두 건은 **실제 판매 차감**이라, 중립화하면 그만큼 재고가 되살아난다.
- **(나) 자식으로 이전** — madre 잔량을 특정 variant 로 옮긴다.
  물리적으로 맞지만 **어느 자식인지 근거가 없다**(CODEX: 자동 귀속 위험). 수동 매핑 필요.
- **(다) 보존** — 그대로 두고 탐지기로만 감시. 화면 영향 0이므로 실무상 무해.

절차는 어느 쪽이든 append-only 를 지킨다:
`SET LOCAL ventago.allow_madre_stock='on'` (트리거 우회) +
`SET LOCAL ventago.stocks_maintenance='on'` 은 **쓰지 않는다**(UPDATE/DELETE 금지).
`source='migration_transfer'` 로 태깅해 감사 추적성을 남긴다.

## 10. ⏳ D (default variant 강제) — 별도 phase

B 로 **재발은 막혔다**(트리거 + 전환 가드). D 는 "madre 가 판매 단위인 경우" 자체를
없애는 최종형이다. 지금은 자식 0 인 제품이 leaf 로 인정되므로 불변식은 성립하지만,
`is_parent` 플래그와 실제 leaf 여부가 여전히 두 개념으로 남아 있다.
D 를 하면 그 둘이 하나가 된다. 이관 위험이 실제 재고에 닿으므로 별도 계획이 맞다.

---

## 11. [2026-08-08] 사용자 규칙 채택 — "madre 와 hijo 는 같을 수 있다. 거래는 hijo 로만."

사용자 제안:
> codigo madre 와 hijo 가 **동일할 수 있다** 는 조건을 걸고, **판매·재고 추가·이동은
> 반드시 hijo 로만** 할 수 있다는 조건을 주면 로직이 간단해지지 않나?

**맞다.** 그리고 ②는 `trg_stocks_leaf_only` 로 이미 강제되고 있었다.
이 규칙의 진짜 값어치는 **리포트가 단순해진다**는 데 있다.

### 왜 단순해지나

지금 `getItems` 는 두 뷰의 **FROM/JOIN 구조 자체가 다르다**:

```
cod.madre : FROM products p JOIN products child ON child.parent_id=p.id
                            JOIN "ProductBranch" pb ON pb.product_id=child.id
variante  : FROM products p JOIN "ProductBranch" pb ON pb.product_id=p.id
```
게다가 MOV± 는 `productScope`, Ingreso 는 `pbScope` 로 **또 다른 모집단**을 쓴다.
**오늘의 ±40 버그가 정확히 이 불일치에서 나왔다.**

규칙을 받아들이면:
- 모든 거래는 hijo 행만 참조 (트리거가 강제)
- family key = `COALESCE(parent_id, id)`
- variante 뷰 = hijo 행 그대로 / cod.madre 뷰 = **같은 hijo 행을 family key 로 GROUP BY**
- → **FROM 절이 하나가 되고 모집단 불일치가 구조적으로 불가능해진다**

### 배포한 것 — `2026-08-08-product-family-invariants.sql` (양쪽 DB)

`COALESCE(parent_id, id)` 는 **깊이 1 에서만** 안전하다(CODEX). 그래서 전제를 제약으로 굳혔다:

| 제약 | 내용 |
|---|---|
| `products_parent_not_self` CHECK | 자기참조 금지. "자기 자신이 hijo" 는 `parent_id IS NULL` 로 표현한다 (CODEX #2) |
| `trg_products_family_depth` | 부모는 반드시 루트(깊이 1) + **부모·자식 매장 일치** |
| `v_product_hijo` 뷰 | 거래 가능 단위. `hijo_id` / `family_id` / `es_producto_simple` |

★ `v_product_hijo` 는 `is_parent` 플래그를 **쓰지 않는다.** 진실 원천은 `EXISTS(활성 자식)` 다
(CODEX #9 — 플래그와 실제가 어긋나는 게 오늘 버그의 한 축이었다).

검증: 로컬에서 자기참조·깊이2·크로스매장 전부 거부 확인.
운영 실측 — hijo 222 / 활성제품 277 / family 71 / **단품(자기 자신이 hijo) 16**.
적용 전 데이터도 전제를 이미 만족했다(자기참조 0 · 깊이2 0 · 크로스매장 0 · 플래그 불일치 0).

### 다음 단계 — 리포트를 `v_product_hijo` 위로 옮긴다 (아직 안 함)

지금 리포트는 **정확하다**(전 조합 항등식 0). 이 리팩터는 정확성이 아니라 **재발 방지**가 목적이다.

```sql
-- 목표 형태: FROM 절 하나, GROUP BY 만 다르다
FROM v_product_hijo h
JOIN "ProductBranch" pb ON pb.product_id = h.hijo_id
LEFT JOIN stocks s ON s.product_branch_id = pb.id
GROUP BY  (cod.madre 면) h.family_id   /  (variante 면) h.hijo_id
```
→ `rowsJoin`/`countJoin`/`childStatusFilter`/`productScope`/`pbScope` 5개 분기가 사라진다.

★ CODEX 경고 (리팩터 시 지킬 것):
- **비활성 자식**은 family 에는 남기되 거래 모집단에서는 제외한다. "활성 자식 존재"와
  "과거 거래 집계"의 상태 기준을 섞으면 다시 불일치한다 (#4)
- 자동으로 "유일한 hijo" 를 고르지 말고 **요청자가 leaf id 를 명시**하게 한다 —
  자식이 추가되는 순간 같은 요청의 의미가 바뀐다 (#12)
- 공통 resolver `(storeId, branchId, productId) → sellable ProductBranch` 를 상품 도메인에 두고
  22개 쓰기 경로를 수렴시킨다. 단 **앱 resolver 만으로는 우회되므로**
  `stocks`·`sale_items` 각각 DB 트리거가 최종 방어선이어야 한다 (#10, #11)

### 장기 — Shopify 식(별도 default variant)과의 비교

CODEX: 지금 코드베이스에는 **독립 leaf 방식(현재 채택)이 변경량·운영 위험이 작다.**
다만 장기 정체성 안정성은 Shopify 방식이 우세하다 — 상품(family) id 와 판매단위(variant) id 가
처음부터 분리되기 때문이다. 단품이 실제 madre 가 되는 순간 기존 id 의 의미가
sellable→non-sellable 로 바뀌는 문제가 남는다(지금은 전환 가드로 막고 있다).
→ **신규 상품부터 default variant 를 만드는 방향**을 별도 phase 로 검토한다.

---

## 12. [2026-08-08] legacy 정리 완료 — 그 과정에서 **틀린 숫자**를 찾았다

사용자 판단: "일을 덜 하는 것보다 장차 완결성을 위해 더 많이 투자하는 쪽."

### ★ 내 앞선 판단이 틀렸다 — "화면 영향 0" 은 Cockpit 만 본 말이었다

`stock_balances` 를 읽는 리포트 뷰 3개(`v_stock_sucursal_variante` / `_madre` /
`v_stock_total_variante`)가 제품 구분 없이 집계하고 있었다. 고아 madre 잔량이 그대로 섞였다.

특히 `v_stock_sucursal_madre` 는 family key 를 `COALESCE(parent_id, product_id)` 로 쓰는데
**madre 자신의 잔액 행도 같은 key 로 접혀 자기 family 합계에 이중으로** 들어갔다:

| 지점 | SKU | 표시값 | 실제(leaf 합) |
|---|---|---|---|
| coolsistema | `251843001` | **276** | 316 |
| HELGUERA | `251843001` | **56** | 16 |
| JEFE | `25193443001` | **19** | 29 |
| SALA | `25193545001` | **49** | 59 |

즉 **Cockpit 의 cod.madre 값과 StockVistas 리포트가 서로 다른 값을 말하고 있었다.**
variante 뷰에는 madre 가 중복 SKU 줄로 뜨고 `on_hand −40` 같은 음수 재고까지 보였다.

교훈(오늘 두 번째): **"영향 없다" 를 한 소비자만 보고 말하지 마라.**
§1-sexies 에서 "각 매장 위반 없나" 로 한 번 걸렸고, 여기서 "다른 리포트는?" 로 또 걸렸다.

### 수정 — `2026-08-08-stock-views-leaf-only.sql`

`v_stock_balances_leaf` 하나를 만들고 세 뷰가 그것을 읽는다(규칙을 세 곳에 복제하지 않는다).
- `v_stock_balance_drift`(불변식 탐지기)는 **바꾸지 않았다** — 탐지기는 전부 봐야 한다
- 필터는 "활성 자식 존재" 하나. 행 자신의 status 는 안 건드린다(CODEX #4)
- 자식 판정은 같은 매장 안에서만

### 중립화 — `2026-08-08-neutralize-non-leaf-ledger.sql`

뷰 필터 후에는 화면 영향이 0 이다. 그런데도 하는 이유는 하나:
★ **탐지기가 상시 0 이 아니면 새 위반이 거기 묻힌다.** 바닥이 10 이면 11 이 돼도 모른다.

탐지기 정의도 함께 고쳤다 — 종전에는 **행 수**를 세어 append-only 원장에서 영원히 0 이
안 됐다. `HAVING SUM(stock) <> 0` 으로 "non-leaf 가 재고를 들고 있는가" 를 묻게 했다.

보정행 5건 append(`source='migration_transfer'`, UPDATE/DELETE 없음):
`251843001` br6 +40 / br16 −40 · `25193443001` br14 +10 · `25193545001` br15 +10 ·
`2542001` br6 −44

★ 정직하게: `25193443001`/`25193545001` 의 −10 은 **실제 POS 판매 차감**이었다.
중립화로 그 10장이 장부상 되살아난다. 다만 어느 variant 에도 반영된 적 없고 실물 대사도
안 된 데이터다. 실물과 맞추려면 **Panel D 실사 보정(Offset)** 이 맞는 경로다.

### 최종 상태 (운영 실측)

```
v_stock_on_non_leaf     0        (non-leaf 가 든 재고 없음)
v_stock_balance_drift   0
v_stock_tenant_leak     0
항등식 위반             0        전 매장 × {variante, cod.madre} × {전 지점, 지점 선택}
StockVistas ↔ Cockpit   일치     316 / 16 / 29 / 59
테스트                  176 green (reports·products·stocks)
```
