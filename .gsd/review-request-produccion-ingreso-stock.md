# 자문 요청 — 생산(외주 공정) 완료품이 재고에 들어오지 않는다. 적정 규모의 해법은?

앞선 자문(`review-request-madre-other-write-paths.md`) 우선순위 4번 "생산 경로 —
단순 400 금지, 변형 배분 모델 선행"의 후속이다. 그런데 실제로 코드·운영 데이터를
따라가 보니 문제가 그것보다 크고, 동시에 **이미 있는 것도 많다.**

**요청**: 과하지도 부족하지도 않은 해법을 설계해 달라. 나는 최소 범위를 원하지만
"나중에 갈아엎어야 하는 최소"는 원하지 않는다. 무엇을 **지금 하지 말아야 하는지**도
같이 지적해 달라.

---

## 1. 확인한 사실 (전부 코드 + 운영 DB 실측)

### 1-1. 생산으로 재고가 들어온 적이 한 번도 없다
운영 `stocks` 의 type 분포에 **`production` 0건**.
```
type      | count |  sum
(빈값)     |   977 |  7137
suspend   |   491 |   -39
adjust    |    70 | -2431
sale      |    31 |   -65
transfer  |     6 |     0
```

### 1-2. 경로가 둘인데 둘 다 안 된다

**(A) 외주 = talleres/subcon — 실제로 쓰는 경로. 재고 연결이 아예 없다.**
- `src/app/subcon/` 전체에서 `stocks` 에 쓰는 곳은 `subcon-material-issue.service.ts` 하나뿐인데,
  Phase 65 W2 에서 **차감을 제거**했다. 주석 그대로: 구 코드가 `stocks.productId`(미존재 컬럼)를
  조회해 항상 런타임 오류였고, "올바른 차감에는 지점(branch) 컨텍스트가 필요한데
  SubconOrder 에 branchId 가 없어 임의 기록 시 오히려 원장을 오염시킨다" → 차감 삭제, WARN 만.
- `recepcion.service.ts` (189줄)에 재고 관련 코드 **0줄**. 수령해도 아무 일도 안 일어난다.

**(B) MES = `production/work-orders` — 코드는 맞게 생겼으나 운영 0건, 게다가 부모 단위.**
- `completeWorkOrder` 는 BOM 소비(음수) + 완제품 입고(양수) 원장을 **제대로** 쓴다
  (단일 트랜잭션, productId 오름차순 락, 원장→트리거로 잔액 반영).
- 그러나 `mes_work_orders` 에 색/사이즈 컬럼이 없고 `mes_production_results` 도 수량만 있다
  → **부모 productId 한 건으로 입고** → 지금 실행하면 `trg_stocks_leaf_only` 에 막혀 500.
- 지점 해석 `resolveProductionBranchId`: 매장 지점이 정확히 1개일 때만 그 지점, 0개면 400,
  2개 이상이면 **400 ("indique la sucursal de producción")**.
- 운영 `mes_work_orders` **0건**, `mes_production_results` **0건**. 한 번도 안 쓴 모듈이다.

### 1-3. ★ 변형 배분 정보는 **이미 완비돼 있다**
`talleres_lotes.size_color_matrix` (JSONB, 타입 `SizeColorMatrix`):
```json
{ "qty": { "27": {"17": 15}, "28": {"17": 5}, "31": {"17": 5}, "14": {"17": 0} },
  "colors": [{"id":31,"name":"CELESTE"},{"id":28,"name":"ROJO"},{"id":27,"name":"NEGRO"},{"id":14,"name":"Color Único"}],
  "sizes":  [{"id":17,"name":"Talle Única"}] }
```
자식 상품이 `color_id`/`size_id` 를 갖고 있어 **추측 없이 1:1 매핑**된다:
```
parent 222 → 224(color 27,size 17) / 225(28,17) / 226(31,17) / 223(14,17)
qty[27][17]=15 → 상품 224 에 15장.  합 25 = total_quantity 일치.
```

### 1-4. ★ 최종 공정 판정 근거도 이미 있다
`talleres_lotes.routing_path` (JSONB, `RoutingStep[]`) — 로트별 공정 경로가 순서대로 동결돼 있다.
로트 10 실측:
```json
[ {"order":1,"etapaId":1,"etapaName":"corte","vendorId":null},
  {"order":2,"etapaId":3,"etapaName":"costura","vendorId":2},
  {"order":3,"etapaId":5,"etapaName":"planchero","vendorId":7} ]
```
→ `talleres_etapas` 에 `is_final` 컬럼을 새로 만들 필요가 없다. **routing_path 의 마지막 step 이
최종 공정**이다. (`talleres_etapas` 는 매장별 마스터이고 `order` 만 있다.)

### 1-5. 로트 10 은 **이미 전 공정을 마쳤는데** 재고가 0이다
```
envios: (lote 10, etapa 1, 25장, pending 0, COMPLETED)
        (lote 10, etapa 3, 25장, pending 0, COMPLETED)
        (lote 10, etapa 5, 25장, pending 0, COMPLETED)
recepciones: 3건, 각 received 25 / rejected 0 (2026-07-15)
lote.status = IN_PROGRESS,  available_quantity = 25
```
routing 3단계를 모두 돌았고 미반환 잔량도 0인데 status 는 IN_PROGRESS 로 남아 있고
`stocks` 에는 아무것도 없다. **완료 판정 자체도 자동으로 안 되고 있다.**

### 1-6. 수령 기록은 총량 하나뿐이다 (변형별이 아니다)
`talleres_recepciones`: `envio_id`, `received_quantity`(총량), `rejected_quantity`, `recepcion_date`, `store_id`.
`talleres_envios`: `lote_id`, `vendor_id`, `etapa_id`, `quantity`, `pending_quantity`, status.
**어디에도 변형(color/size) 차원이 없다.** 계획 매트릭스에만 있다.

### 1-7. 운영 규모 (지금 사실상 시범 단계)
`talleres_lotes` 5건 — **전부 store 6 (coolsistema, 사실상 테스트 매장)**.
envios 3건 / recepciones 3건(전부 로트 10). 실사용 매장(ACE=9)에는 로트 0건.

---

## 2. 조사한 업계 관행 (중견 규모 시스템)

- **재고 원장은 언제나 leaf(변형) SKU 에만.** parent-child matrix 는 입력·조회용 표현일 뿐.
  → Ventago 의 `trg_stocks_leaf_only` 는 표준과 일치. 트리거가 옳다.
- **작업지시는 변형 단위.** Katana: "MO 에는 product 또는 variant **하나만**".
  ERPNext: Work Order 는 Item(변형) 단위. Odoo: 조합별 MO 자동 생성.
  단, **의류 전용은 2계층** — cut ticket 은 스타일 단위 매트릭스, 입고는 변형 단위.
- **외주는 가상 창고/위치.** Odoo: 부품 → `Subcontracting` 위치, 완성품은 거기 있다가
  **receipt 를 validate 할 때 비로소 회사 재고로 전입**. ERPNext: 공급업체용 Warehouse.
- **공정 단계는 재고를 안 움직인다.** 의류 WIP 는 재단/봉제/마감에서 수량만 추적한다
  (bundle tracking). → Ventago 의 etapas 가 재고를 안 건드리는 건 **결함이 아니라 정상**.
- **실제 수량은 사람이 입력한다. 계획 비율 자동 배분은 어느 시스템도 안 한다.**
  Katana 부분 완료: "Completed quantity(실제로 완성된 개수)" 입력.
  자재 소비는 **부분 완료 시 계획값**, 실제 소비량은 **최종 완료 시에만** 입력.
  잔량용 문서를 새로 만들지 않고 원 문서를 "Partially complete" 로 두고 잔량 추적.

---

## 3. 물어보는 것

**Q1. 적정 범위.** "생산 완료 → 재고"를 성립시키는 **최소 구현**은 무엇인가?
그리고 지금 **하지 말아야 할 것**은? 내가 후보로 보는 것들:
  (a) 최종 공정 수령 시 변형별 실제 수량을 입력받아 leaf SKU 원장에 입고 ← 핵심
  (b) 외주업체를 가상 지점(Branch)으로 도입 ← 판매·POS·재고조회 전반 파급. 지금은 과한가?
  (c) 원자재 출고(Phase 65 W2 에서 제거) 복원
  (d) MES 모듈을 변형 단위로 재설계
  (e) `talleres_lotes.status` 자동 전이(전 공정 완료 → COMPLETED)
(a) 만으로 업무가 성립하는가, 아니면 (a) 는 (b) 없이는 반쪽인가?
특히 **입고 지점(branchId)을 어디서 얻을 것인가** — 이것이 (b) 를 강제하는가?
수령 화면에서 지점을 고르게 하면 (b) 없이 되는데, 그것이 "나중에 갈아엎을 최소"인가?

**Q2. 데이터 모델.** 변형별 수령 수량을 어디에 둘 것인가?
  (i) `talleres_recepciones` 에 JSONB 매트릭스 컬럼 추가 (lote 의 매트릭스와 같은 모양)
  (ii) 자식 테이블 `talleres_recepcion_items(recepcion_id, product_id, quantity, rejected)`
  (iii) 수령과 분리된 새 문서 `talleres_ingresos`(로트 → 재고 입고 전용, 최종 공정에만)
JSONB 는 스키마 변경이 작지만 집계·조인이 어렵고 FK 무결성이 없다. 자식 테이블은 반대다.
로트 5건 규모에서 어느 쪽이 맞는가? (iii) 처럼 **재고 입고를 수령과 분리**하는 게
개념적으로 더 맞는가, 아니면 문서를 하나 더 만드는 것이 과한가?

**Q3. 입고 시점.** `routing_path` 마지막 step 의 etapa 를 수령할 때 자동 입고인가,
아니면 사람이 명시적으로 "재고 입고" 버튼을 누르는가?
자동이면 로트 10 처럼 이미 전 공정을 마친 기존 데이터는 어떻게 되는가(소급 처리)?
`routing_path` 가 null 인 오래된 로트(로트 7·8·11·12 는 cut_date 도 없다)는?

**Q4. 멱등성·되돌리기.** `stocks` 는 append-only(`trg_stocks_immutable`) 이고 보정은
반대 부호 행으로만 한다. 같은 로트를 두 번 입고하면 재고가 두 배가 된다.
  - 무엇을 유니크 키로 잡아야 하는가(로트? 수령? 로트×변형?)
  - 입고 취소는 반대 부호 행 + 상태 되돌림인가, 아예 막는 게 맞는가?

**Q5. 계획 vs 실제 차이.** 매트릭스 계획 25 인데 실제 23 만 나오거나, 색상 배분이
다르게 나오면? 차이를 어디에 기록하는가 — 로트에? 별도 필드? 아니면 그냥 실제만 남기는가?
불량(`rejected_quantity`)은 재고에 안 들어가는 게 맞는가(폐기), 아니면 불량 창고 개념이 필요한가?
Katana 는 "부분 완료 = 계획 자재 소비, 최종 완료 = 실제 자재 소비"로 절충하는데,
Ventago 는 애초에 자재 소비를 안 하고 있어서 이 절충이 그대로 적용되진 않는다.

**Q6. MES 모듈(`mes_work_orders`) 처리.** 운영 0건이고 부모 단위라 지금 쓰면 500 이다.
이전 자문에서 "생산에 단순 400 을 걸면 생산 업무가 막힐 수 있다"고 경고했는데,
**운영 0건이라면 그 경고가 유효한가?** 선택지:
  (i) 지금 leaf 가드(400)를 걸어 다른 쓰기 경로와 규칙을 통일 — 막힐 업무가 없다
  (ii) 그대로 두고 talleres 에 흡수될 때 정리
  (iii) 변형 단위로 재설계
어느 쪽인가? (i) 을 고르면 "쓸 수 없는 기능이 명시적으로 거부한다"가 되는데,
이게 정직한 것인가 아니면 죽은 코드에 가드를 다는 낭비인가?

**Q7. 내가 놓친 것.** 위 설계에서 나중에 갈아엎게 만들 결정이 있는가?
특히 **지점(branch) 개념**을 지금 안 건드리는 선택이 부채가 되는가?

---

## 4. 제약 (반드시 지켜야 함)

- **재고 원장 규약**: `stocks` 는 append-only(`trg_stocks_immutable`), 기록·조회는 항상
  `product_branch_id` 기준(`stocks.product_id` 컬럼은 **없다**). 잔액은
  `trg_stock_balances_apply` 가 같은 트랜잭션에서 `stock_balances` 에 반영 —
  애플리케이션이 따로 맞출 캐시는 없다. `products.stock` 은 강등됨(참조 금지).
- **부모 금지**: `trg_stocks_leaf_only` — 활성 자식이 있는 상품의 PB 에는 원장 INSERT 불가
  (SQLSTATE 23514). 판정 단일 출처는 `src/app/products/madre-guard.ts`.
- **쓰기 경로 규약(Phase 64)**: 하나의 업무 동작이 만드는 모든 행은 **하나의 트랜잭션**.
  헬퍼는 `transaction` 을 **필수 인자**로 받는다. 트랜잭션 안에서 외부 I/O 금지.
  여러 상품 행을 잠그는 경로는 **productId 오름차순** 고정(판매·취소·생산 공통, 교착 방지).
  커밋 후 단계의 실패는 응답 코드를 바꾸지 않는다.
- **계층**: Store → Branch(Sucursal) → Box → Terminal. `ProductBranch(productId, branchId)`.
- **정책 공용화 금지 전례**: un-ship 정책을 공용 헬퍼에 넣었더니 취소 경로가 회귀했다.
  판정만 공용, 처리는 경로별.
- DB 는 PG18. 마이그레이션은 로컬(5432)·운영(5434) 양쪽 동시 적용하며 신규 테이블은
  owner 를 `coolsistema` 로 이전해야 한다(시퀀스 별도).
