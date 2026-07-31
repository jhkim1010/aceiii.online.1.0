# products.stock 캐시 유도화 (B) — 감사 결과와 설계

작성 2026-07-30. A 단계(정본 VIEW + 드리프트 감시, api-ventago `b7641aa`) 완료 후 착수.

## 목표

`products.stock` 을 앱이 직접 증감시키지 않고 `stocks` 원장에서 자동 유도한다.
쓰기 경로를 추가할 때 캐시 갱신을 잊는 것이 구조적으로 불가능해진다
(실제 사고: online_order ship 경로 madre 갱신 누락 → `68404be`).

`stocks` 는 append-only(`trg_stocks_immutable`)이므로 증분 트리거가 전체 집계와
수학적으로 동등하며 O(1) 이다.

## B0 감사 결과 — 쓰기 지점 21곳

당초 14곳으로 파악했으나 `stocks.service` 3곳, `work-order.service` 2곳, `sales-create` 1곳을
빠뜨렸다. 실제 21곳이다.

| 파일 | 라인 | 성격 |
|---|---|---|
| `online-orders/online-order-stock.service.ts` | 342 | madre 원장 합 재계산 (트리거 도입 시 불필요) |
| `online-orders/online-order-stock.service.ts` | 467 | `adjustProductStock` 델타 |
| `products/productStock.service.ts` | 112, 382, 617, 644, 922, 1552, 1591, 1657 | 입고·보정·variant 생성 델타 |
| `products/productStock.service.ts` | 413 | `updateMotherStock` 재계산 (불필요해짐) |
| `sales/sales-create.service.ts` | 1021, 1027 | 판매 취소 복원 델타 |
| `sales/sales-create.service.ts` | **1236** | **초과판매 방어와 융합된 차감** ← 핵심 제약 |
| `sales/sales-create.service.ts` | 1249 | 일반 판매 차감 델타 |
| `stocks/stocks.service.ts` | 97, 159, 445 | 이동 생성·보정·지점 간 이동 델타 |
| `stocks/stocks.service.ts` | 496 | madre 재계산 사본 (불필요해짐) |
| `production/work-orders/work-order.service.ts` | 216, 241 | 자재 소비·완제품 입고 델타 |

**21곳 전부 같은 트랜잭션에서 `stocks` 행을 INSERT 한다.** 원장 없이 캐시만 바꾸는 지점은
없다 → 트리거로 대체 가능하다.

## 핵심 제약 — 판매 차감이 초과판매 방어와 한 문장이다

`sales-create.service.ts:1233~1247` (`allowSaleWithoutStock = false` 인 매장):

```sql
UPDATE products SET stock = stock - $1
  WHERE id = $2 AND stock >= $1
RETURNING id
```

영향 행이 0이면 `BadRequestException`. Phase 64 W8/R10 에서 **검사와 차감을 한 문장으로 합쳐
TOCTOU 를 막은 것**이다 (종전에는 `processSaleItems` 검사와 차감이 떨어져 동시 판매가 둘 다 통과했다).

즉 `products.stock` 은 읽기 캐시이면서 **동시성 제어 카운터**를 겸한다.
이 UPDATE 를 단순히 지우고 트리거에 맡기면 방어가 사라진다. 트리거는 원장 INSERT 이후에
발화하므로 거부 시점이 늦고, 트리거에서 막으면 이동·보정 같은 정상 음수 이동까지 걸린다.

### 해결안 (B-β) — 락+검증은 앱, 차감은 트리거

```ts
// allowSaleWithoutStock = false && strict 인 경우
const [row] = await sequelize.query(
  `SELECT stock FROM products WHERE id = $1 FOR UPDATE`, ...);   // 행 락 유지
if (row.stock < qty) throw new BadRequestException(...);          // 앱 에러 의미 유지
// 이후 stocks 행 INSERT → 트리거가 차감
```

행 락을 커밋까지 유지하므로 원자성은 동일하다. `BadRequestException` 메시지·상태코드가
그대로 보존된다(트리거 `RAISE` 로 옮기면 500 매핑 문제가 생긴다).
CLAUDE.md 락 순서 규약(productId 오름차순)을 유지한다.

## 재검토 필요 — `products.stock` 의 의미

사용자 결정은 "가용(available)"이었다. 그런데 **`stocks.model.ts:36~44` 에 Phase 65 W4 가
이미 3값 단일 출처를 확정해 두었다**:

```
on-hand(물리)  = SUM(stock WHERE type IS NULL OR type <> 'suspend')
                → products.stock 잔액 캐시가 캐싱하는 값
reserved(예약) = -SUM(stock WHERE type = 'suspend')
available(가용) = SUM(stock 전체) = on-hand − reserved
                → 판매 검증·live-stock·코크핏 rStock·오프라인 스냅샷이 쓰는 값
is_active 는 정의에 포함하지 않는다
```

A 단계에서 만든 VIEW 정의는 이 on-hand 정의와 일치한다(우연이 아니라 같은 실측 근거).

`products.stock` 을 available 로 바꾸면 이 확정 정의와 충돌한다. available 이 필요한 경로는
이미 별도 계산 경로를 갖고 있다. 따라서 **on-hand 유지를 권고**하며, 트리거 필터는
`type IS NULL OR type <> 'suspend'` 를 쓴다. (사용자 재확인 대기)

on-hand 를 유지하면 A 단계 VIEW·드리프트 cron·T10 판정 기준을 그대로 쓸 수 있고,
madre 규약도 이미 on-hand 라 변경이 없다.

## 확인된 불일치 (별건, 라이브 영향 없음)

W4 주석은 available 을 "판매 검증이 쓰는 값"이라 하지만, 실제 판매 검증은 on-hand 를 쓴다:

- `processSaleItems`: `product.stock <= 0` 로 차단 (on-hand)
- 원자 방어: `WHERE stock >= qty` (on-hand)

`allowSaleWithoutStock = false` 매장에서 on-hand 5 / reserved 5 (available 0) 상품이
팔릴 수 있다. 다만 2026-07-30 실측으로 **on-hand > 0 이면서 available ≤ 0 인 상품은 0건**이라
현재 노출은 없다. 주석을 코드에 맞출지, 코드를 주석에 맞출지 별도 결정이 필요하다.

## 실행 순서

1. **B0 감사** — 완료 (위)
2. `products.stock` 의미 재확인 (on-hand 권고)
3. 트리거 마이그레이션 + 기준 재계산 + A 단계 VIEW 정합성 확인
4. 앱 쓰기 21곳 제거 + 판매 경로 B-β 적용 — **3번과 같은 배포** (반만 적용하면 이중 카운팅)
5. 사문화되는 재계산 헬퍼 3개 제거 (`updateMotherStock`, `refreshMotherCacheFromLedger`, `refreshMotherCaches`)
6. 회귀: T1(보류→F2), T9(envío 5단계), T10(전수 드리프트) + 이동·보정·생산·취소·반품 경로

4번이 판매 핫패스를 건드리므로 staging 회귀 후 배포한다.


---

# 진행 상태 — B단계 완료 (2026-07-30)

## 완료
- **B0 감사** — 쓰기 21곳 확정. 실제로는 **22곳**이었다(아래 참조)
- **정의 VIEW 화** — `v_product_branch_stock` / `v_product_stock_canonical` / `v_product_stock_drift`
- **중복 정리** — `ProductStockDriftCron` 제거, `StockDriftService` 를 VIEW 로 수렴
- **앱 쓰기 22곳 제거 + 사문화 헬퍼 3개 제거** — `64dc5e3`
- **판매 방어 B-β** — `SELECT … FOR UPDATE` + 앱 검증. 라인 합산 검사 추가
- **배포** — Jenkins api **#576 SUCCESS** → `api_ventago` healthy (4워커)
- **마이그레이션 적용** — 운영 5434 `UPDATE 37` / 로컬 5432 `UPDATE 28`. 양쪽 드리프트 **0행**
- **트리거 실발화 검증** — 운영에서 ROLLBACK 리허설: 원장 −3 → 자식 1→−2, 부모 4→1 (한 문장)

## ★ 22번째 쓰기 경로 — 미해결 관측의 정체

`code-import/code-import.service.ts` (엑셀 일괄 가져오기).
원장 없이 `products.stock` 을 **절대값으로 덮어쓰고** 있었다:
- L726 `patch.stock = row.stock` → `found.update(patch)` — **동적 patch 객체라 종전 감사 grep
  (`.update({stock})` 패턴)에 안 걸렸다.** 이것이 21곳으로 세어진 이유다
- L763 신규 variant `stock: row.stock ?? 0` — 원장 0행

2026-07-30 11:40:57 UTC 에 products 1·2·3·4 가 한 문장으로 갱신되고 감사로그 0행이던 관측과
패턴이 일치한다. 마이그레이션 기준 재계산에서 product 1 캐시가 **−20 → 4** 로 교정됐다.

조치: `writeStockAdjustment()` — 목표 절대값과 현재값의 차이를 `adjust` 원장 행으로 남긴다.
같은 SKU 가 시트에 두 번 나오면 진행값(`stockAfterImport`)을 추적해 이중 적용을 막는다.

## 그 외 계획 밖 조치 2건

1. **야간 드리프트 크론의 madre 재계산 제거** (`stock-drift.service.ts`)
   트리거 도입 후 불필요하고, 남겨두면 **트리거 결함을 매일 밤 조용히 덮는다**.
   탐지 전용으로 환원했다 — drift 가 잡히면 고칠 버그이지 지울 흔적이 아니다.
2. **신규 매장 제네릭 상품 시드 999999 → 0** (`storeTemplate.service.ts`)
   원장 없는 캐시라 배포 후 즉시 드리프트 경보가 난다. 운영 6개 매장의 제네릭 상품은
   이미 전부 0 이었다.

## 설계 판단 — 원장 기록 위치를 커밋 직전으로 이동

원장 INSERT 가 곧 트리거의 `products` 행 UPDATE 다. 따라서 기록을 종전 위치(결제·할인 이전)에
두면 행 락을 그 구간 내내 쥐게 되어 **Phase 63 B-0c 의 락 단축이 통째로 회귀한다.**
`applyStockLedger` 가 검증과 원장 기록을 함께 커밋 직전에 수행한다.

## 의미 변경의 사용자 가시 효과

`products.stock` 이 on-hand → **available** 이 되면서 화면 재고가 보류(suspendido) 수량만큼
낮아진다. 운영 37행 중 32행이 이 경우다(예: PANT MEZCLILLA 234→210, FRONT CAT 474→468).
물리 현재고가 필요하면 `v_product_branch_stock.on_hand` / `v_product_stock_canonical.on_hand`.

## 검증 결과

- `tsc --noEmit` 신규 오류 0 (잔여 16건은 기존 spec 시그니처 — 빌드 무영향)
- lint 436 → 432 (신규 0)
- 재고 경로 spec 40 passed. 잔여 1건 `adjust — 반대 부호 보정 행…` 은 HEAD 에서도 실패하는 기존 건
- 구 계약을 고정하던 spec 4건은 새 불변식으로 재작성:
  "앱은 products.stock 을 쓰지 않는다" + "원장 기록 순서가 productId 오름차순"
- 배포·마이그레이션 후 api error 0, TenantGuard 경고 0

## 남은 것

1. **회귀 실측** — T1(보류→F2) · T9(envío 5단계) · T10(전수 드리프트 0행) +
   이동·보정·생산·취소·반품 각 1건. 실제 화면 조작이 필요하다
2. `stocks.model.ts:36` 3값 주석을 가용 기준으로 갱신
3. 영업시간 관측 — 드리프트가 0 을 유지하는지:
   ```bash
   ssh jhkim-server "sudo -u postgres psql -p 5434 -d ventago -c 'SELECT count(*) FROM v_product_stock_drift;'"
   ```
   0 이 아니면 그건 트리거가 못 잡는 쓰기 경로가 남았다는 뜻이다(23번째)
