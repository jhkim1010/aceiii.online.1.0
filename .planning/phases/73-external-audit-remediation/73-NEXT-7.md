# 73 후속 7 — D phase Part 2 배포 + 운영 500 하나 (새 세션용)

앞선 문서: `73-NEXT.md` ~ `73-NEXT-6.md`. 이 문서는 **2026-08-08 저녁** 작업분.

---

## 0. 먼저 읽을 것 (73-NEXT-6 §0 에 더해)

- ★ **테스트가 통과했다고 검증된 것이 아니다. 오늘만 두 번 공허하게 통과했다.**
  둘 다 변이 검사로 잡았다. 새 테스트를 쓰면 **일부러 깨뜨려 실패를 확인하기 전에는
  green 을 근거로 쓰지 마라.** §5-B, §7 참조.
- ★ 통합 스위트가 `npm run test:family` 5파일 45건으로 늘었다. 새 하네스
  `test/family/helpers/orm.ts` 는 **서비스를 실 Sequelize + 실 PG 위에서 그대로 태운다.**

---

## 1. 무엇을 했나

| # | 내용 | 배포 |
|---|---|---|
| 1 | D phase Part 2 종단 테스트 + CODEX 지적 5건 수정 | api #650 |
| 2 | `stock_balances` 에서 Traspaso 를 사람 Offset 과 분리 (DDL 양쪽 적용) | api #650 |
| 3 | `Stocks` 집계의 `stock` 컬럼 한정 — 운영 500 (ambiguous) 해소 | api #651 |

세 빌드 전부 SUCCESS + 컨테이너 재생성 + 배포 번들 확인.

---

## 2. 종단 테스트 하네스 (`test/family/helpers/orm.ts`)

§16-C 가 배포를 막아둔 이유가 이것이었다. 그때까지 검증된 것은 둘뿐이었다:
① 서비스 분기(유닛 — 모델 전부 mock) ② 이관 원장이 **이미 있을 때** 리포트가
Traspaso 로 잡는 것(통합 — raw SQL). 빠진 것은 그 사이, 즉 **서비스가 그 원장을
올바르게 쓰는가** 였다.

`stocks` 는 UPDATE·DELETE 가 둘 다 막혀 있어(`trg_stocks_immutable`) **커밋 후
정리 경로가 존재하지 않는다.** 그래서 전부 한 트랜잭션에서 돌리고 통째로 되감는다.

### 2-A. ★ 하네스가 스스로 만든 거짓 안심 두 개

이걸 안 잡았으면 이 스위트는 **없느니만 못했다.**

**① Sequelize v6 가 부모 트랜잭션의 `name` 을 자식 이름으로 덮어쓴다.**

`query-interface.js` `startTransaction` 에 이 줄이 있다:

```js
options.transaction.name = transaction.parent ? transaction.name : void 0;
//     ^^^ 부모 객체다
```

즉 자식 savepoint 가 하나 열리는 순간 **부모의 name 이 자식 이름으로 바뀐다.**
그 뒤 부모가 롤백하면 `ROLLBACK TO SAVEPOINT <자식이름>` 이 나가고, 부모가 그 전에
쓴 행들이 **살아남는다.** `Model.findOrCreate` 는 외부 트랜잭션을 받아도 savepoint 를
하나 열고 release 하지 않으므로(`internalTransaction=false`) 이 경로를 항상 밟는다.

실제로 "부분 커밋 금지" 테스트가 이것 때문에 **운영에 없는 실패**를 보고했다
(운영에선 서비스 트랜잭션이 진짜 루트라 `ROLLBACK;` 이 나가고 name 이 안 쓰인다).
같은 메커니즘이 반대 방향, 즉 **진짜 결함을 통과시키는** 쪽으로도 똑같이 작동한다.

→ savepoint 이름을 전역 유일로 짓고 commit/rollback 직전에 자기 이름을 되돌린다.

**② CLS 를 켜면 `transaction` 인자 누락이 안 보인다.**

이 리포의 1번 쓰기 규약이 "모든 문장에 transaction 을 넘겨라" 인데,
`Sequelize.useCLS()` 를 켜면 인자를 빠뜨린 문장도 자동 주입돼 **테스트가 통과한다.**
이관 원장 INSERT 두 곳에서 `{ transaction: t }` 를 지우는 변이가 12건 전부 green 이었다.

→ CLS 를 끄고 **우리가 연 트랜잭션만** AsyncLocalStorage 로 들고 다니며 중첩
`sequelize.transaction()` 의 부모로만 쓴다. pool 을 1 로 잡아 인자를 빠뜨린 문장이
곧바로 acquire 타임아웃으로 드러나게 했다. 지금은 그 변이가 실패한다.

### 2-B. 여전히 재현 못 하는 것

**동시성.** 커넥션이 1개라 두 트랜잭션의 경합(락 대기·교착·UNIQUE 경합)은 여기서
재현할 수 없다. 검증되는 것은 **순차 재호출(멱등성)** 뿐이다. 착각하지 마라.

---

## 3. 서비스 수정 (CODEX 지적)

| 등급 | 지적 | 조치 |
|---|---|---|
| CRITICAL | `createVariantsBatch` 의 트랜잭션 경계가 갈라져 이관만 먼저 커밋 → 뒤가 실패하면 −N/+N 원장과 `is_parent` 가 **영구히** 남는다(append-only 라 복구 불가) | 전체를 하나의 트랜잭션으로(`createVariantsBatchInTx`) |
| CRITICAL | 하네스가 그 결함을 정확히 숨긴다 | §2-A ① 로 해소. 지금은 실패 주입 테스트가 있다 |
| HIGH | `store_entity_id` 누락 → notNull 위반 | `findOrCreateStoreEntity` 로 MAX+1 부여 |
| HIGH | advisory lock 을 부모 행 잠금 **뒤**에 잡아 교착 가능 | advisory 를 앞으로. §3-A |
| HIGH | `stock_balances.total_ajuste` 가 이관을 사람 Offset 으로 집계 | §4 |
| MEDIUM | `-V` 재사용 가드가 축을 안 본다 | color/size/isParent 추가 |
| MEDIUM | 비활성 Color/Size 재사용 | `status=1` 로 재활성화 (참조 목록은 `is_active` 가 아니라 `status` 로 거른다) |

### 3-A. 교착 시나리오 (왜 순서가 중요한가)

자식 INSERT 경로는 트리거가 **먼저 advisory 를 잡고**, 그 다음 FK
(`products_parent_id_fkey`) 검사가 부모 행에 **FOR KEY SHARE** 를 건다.
전환이 부모를 `FOR UPDATE` 로 먼저 잡고 advisory 를 기다리면 정확히 반대 순서다:

```
T1: 부모행 보유 → advisory 대기
T2: advisory 보유 → 부모행(KEY SHARE) 대기
```

"트리거와 같은 키를 쓴다" 는 교착을 막지 못한다. 같아야 하는 것은 **순서**다.
→ 잠금 없이 읽어 `store_id` 만 얻고 → advisory → `FOR UPDATE` 재조회 + 재검증.

### 3-B. `store_entity_id` — 종단 테스트가 잡은 결함

`colors`/`sizes` 의 `store_entity_id` 는 **NOT NULL 인데 DB 기본값이 없다.**
매장 안에서 1부터 매기는 번호이고 `colors.service`/`sizes.service` 가 MAX+1 로 준다.
브랜치 코드는 `findOrCreate` 에 이걸 안 넣어서, 그 이름이 아직 없는 매장에서
곧바로 `notNull Violation` 으로 전환 전체가 500 이었다.

**운영 매장 12(millstream)가 정확히 그 상태다** — Color Único·Talle Única 가 둘 다
없다(나머지 9개 매장은 있다). 유닛으로는 절대 안 잡힌다.

---

## 4. `stock_balances` Traspaso 분리 (DDL, 양쪽 적용 완료)

`stock_balances_apply()` 가 `source` 를 안 보고 "anulacion ingreso" 가 아닌 모든
adjust 를 `total_ajuste` 로 셌다. 그래서 같은 원장 행이 화면마다 다른 이름이었다 —
**§1 이 통째로 없애려던 그 상황이다:**

```
Cockpit            Traspaso 13
StockVistas/Excel  Ajuste 13     ("Offset 은 100% 사람이 넣은 값" 규칙 위반)
```

운영 5행은 전부 non-leaf PB 라 `v_stock_balances_leaf` 가 걸러 화면에 안 보였다.
그러나 Part 2 가 배포되면 **받는 쪽(+N)이 leaf** 라 그 순간부터 보인다. 배포 전에 닫았다.

- `migrations/2026-08-08-stock-balances-traspaso.sql`
- 정의는 Cockpit 과 글자 그대로 같다: `SUM(stock) WHERE source='migration_transfer'` (type 조건 없음)
- **`porcentaje_vendido` 분모에 traspaso 를 넣었다.** 빼기만 하면 이관으로 받은
  variant 의 분모가 0 이 되어 % 가 사라지거나 100 을 넘는다 — §1-B "Ratio 115%" 와 같은 착시.
- 양쪽 적용 완료, `prosrc md5 = 5ce48ecefacf51cb31e36348fa76b6ff` 일치.
  백필 각 5행(PB 86/137/138/143/249), `ajuste → traspaso` 이동만이고 `on_hand` 는 안 건드렸다.
- 탐지기 `v_stock_balance_drift` / `v_stock_tenant_leak` / `v_stock_on_non_leaf` 전부 0 (양쪽).

---

## 5. 운영 500 — `column reference "stock" is ambiguous`

사용자 신고("venta 지점에서 수량 기록·수정·편집 시 오류")를 계기로 운영 로그를 뒤져
찾은 **확정 결함**. 신고 내용과 같은 것인지는 아직 확인 못 했다(§8).

```
/api/dashboards/products/less-stock     500  ×10
/api/dashboards/products/newly-created  500  ×10
매장 6·15, 2026-08-03 부터 반복 (store_error_log 실측)
```

원인: `Stocks` 는 자기 `store_id` 로 안 거르고 **파생 스코프**로 걸린다
(`DERIVED_SCOPE.Stocks = productBranch → product`). 격리 훅이 붙으면 쿼리에
`products` 가 JOIN 되는데 **products 에도 `stock` 컬럼이 있다**(Phase 70-06 에서
강등됐지만 롤백 여지로 남긴 그 컬럼). `col('stock')` 는 한정자가 없어 모호해진다.

같은 형태가 **네 곳**이었다 — dashboards 1 / stock-resolver 2 / wp-sync 1.
지금 터진 건 대시보드뿐이지만 나머지도 같은 조건에서 터진다. 전부 한정했다.

### 5-B. ★ 이 회귀 테스트도 처음엔 공허하게 통과했다

`installTenantGuard()` 만 호출하고 끝냈더니 변이(한정자 제거)가 **통과했다.**
훅은 **테넌트 컨텍스트가 없으면 스코프를 안 건다** → 파생 JOIN 자체가 안 생긴다.
`TenantContext.runPending()` 안에서 돌리도록 고친 뒤에야 변이가 실패한다.

---

## 6. 검증

```
tsc                      무에러
통합 test:family         45 green (5파일 — 신규 transfer 12 + stocks-aggregate 2)
유닛                     1159 green
                         (suite 12개가 load 실패 — jest.mock 호이스팅 문제로 **이번 변경 전부터** 있던 것.
                          브랜치 base 로 되돌려도 동일하게 실패하는 것을 확인했다)
운영 DDL                 양쪽 prosrc md5 일치 / 백필 5행 / 탐지기 3종 0
배포 번들                transferBalanceToDefaultVariant 3 / createVariantsBatchInTx 2 /
                         total_traspaso 9 / Stocks.stock 1 / 기동 에러 0
로컬 DB 잔여물           0 (FAMILY-TEST 매장 0, SOLO 제품 0)
```

### 변이 검사 (전부 실패 확인)

| 변이 | 결과 |
|---|---|
| 이관을 Ingreso(type NULL)로 기록 | 3건 실패 |
| 음수 잔량 가드 무력화 | 1건 실패 |
| 지점을 첫 지점으로 뭉갬 | 2건 실패 |
| `store_entity_id` 제거 | 7건 실패 |
| `-V` 재사용 가드 무력화 | 2건 실패 |
| `transaction` 인자 누락 | acquire 타임아웃으로 실패 |
| `col('stock')` 한정자 제거 | 1건 실패 |

---

## 7. 함정 추가 (73-NEXT-6 §17 에 이어)

25. **Sequelize v6 는 중첩 savepoint 에서 부모의 `name` 을 자식 이름으로 덮어쓴다.**
    깊이 1(서비스 트랜잭션이 루트)이면 `ROLLBACK;` 이라 안 드러나고, 테스트 하네스가
    깊이를 하나 늘리는 순간 **롤백이 엉뚱한 곳으로 간다.** §2-A ①.
26. **테스트에서 CLS 를 켜면 `transaction` 인자 누락이 안 보인다.** 이 리포의 1번
    쓰기 규약이 바로 그것이라, 그걸 검증해야 할 스위트에서 CLS 는 독이다. §2-A ②.
27. **격리 훅은 테넌트 컨텍스트가 없으면 아무 일도 안 한다.** 훅이 만드는 JOIN 을
    검증하려면 `TenantContext.runPending()` 안에서 돌려야 한다. 안 그러면 공허하게 통과한다. §5-B.
28. **`products.stock` 은 아직 살아 있다.** 강등됐을 뿐 컬럼은 남아서, `stocks` 와
    같이 JOIN 되는 쿼리에서 `stock` 을 한정 없이 쓰면 모호해진다. §5.
29. **eslint `--fix` 가 필요한 타입 단언을 지운다.** `no-unnecessary-type-assertion` 이
    `(await query(...)) as Array<{...}>` 를 3곳에서 제거해 tsc 가 깨졌다.
    `--fix` 후에는 반드시 tsc 를 돌려라.
30. **참조 데이터의 "보임" 판정은 `is_active` 가 아니라 `status = 1` 이다**
    (`colors.service.findAll`). 두 컬럼이 다 있어서 헷갈린다.

---

## 8. 남은 것 (우선순위 순)

1. ★ **POS 수정 확인 필요 (front #578 배포됨) — §9 참조.**
   "Nueva venta 에서 여러 개의 codigo madre 수량 기록·수정·편집 시 오류" 를
   코드 경로로 특정해 고쳤지만 **재현은 못 했다.** 사용자 확인이 필요하다.
2. **0잔량 전환의 동시성 창** (CODEX HIGH, 사용자 결정: **한계로 기록만**).
   잔량을 읽은 시점과 자식이 생기는 시점 사이에 부모 PB 로 판매가 들어오면 그 잔량이
   non-leaf 에 고립된다(§1 에서 40행 나왔던 유형). 한 트랜잭션으로 묶어 창은 좁아졌다.
   완전히 닫으려면 `trg_stocks_leaf_only` 에 제품 단위 shared advisory lock 이 필요한데
   판매 핫패스라 비용 검증이 먼저다. 탐지기 `v_stock_balance_drift` 가 감시한다.
3. **매장 8 CAMPERA 4건은 이 처방이 안 맞는다** — 이름에 이미 색/사이즈가 있는
   **고아 variant** 라 재부모화가 맞다(73-NEXT-6 §12-C). 배포해도 안 풀린다.
   재부모화 경로는 지금 앱에 없다.
4. **비활성 부모 + 활성 자식** (73-NEXT-6 §10-2). 운영 실측 0건, `[의도된 한계]` 테스트가 고정.
5. **브라우저·앱 사람 확인** — 73-NEXT-6 §6 이 그대로 남아 있다. 특히:
   - Flutter 관리자앱 Reportes > Stocks (중복 카드 제거 / Vendidos 감소)
   - StockVistas 화면에 새 `Traspaso` 컬럼이 뜨는지
   - 대시보드 "재고 적은 상품" / "신규 등록 상품" 카드가 이제 뜨는지 (§5 수정 확인)

### 유닛 스위트 12개 load 실패 (이번 변경과 무관, 별건)

`jest.mock` 호이스팅 때문에 `INGRESO_LEDGER_NOTE_PREFIXES` 가 undefined 로 도착해
구조분해에서 죽는다(`sales-stock-guard.spec.ts` 등). 테스트 1159건은 전부 green 이고
**브랜치 base 로 되돌려도 동일하게 실패**하는 것을 확인했다. 정리는 별도 작업.


---

## 9. [2026-08-08 밤] POS — 다른 코드마드레의 variant 그리드가 남던 문제 (front #578)

사용자 신고: "Nueva venta 에서 **여러 개의** codigo madre 에 수량을 기록·수정·편집할 때
오류가 많이 발생한다." → `store_error_log` 에는 흔적이 없다(프론트에서 막히는 오류라
서버까지 안 간다). 코드 경로로 특정했다.

### 9-A. 구조

그리드 데이터 `sizes` / `colors` / `stockByVariant` 는 `SaleProductsContext` 에
**한 벌만** 있다. 즉 화면 전체가 "지금 편집 중인 코드마드레 하나" 만 표현할 수 있다.
`VariantsStockVenta` 는 이 세 값의 **교집합**으로 축을 만든다.

`handleParentRowClicked` 는 `productOptions.find(p => p.id === rowData.id)` 로 찾은
**경우에만** 그 한 벌을 갱신했다. 못 찾으면 `if (parentProduct)` 를 통째로 건너뛰어
**직전 코드마드레의 그리드가 그대로 남았다.**

### 9-B. 왜 "여러 개" 일 때만 나타나나

```
madre A 선택 → context = A → 수량 입력 (A 의 colorId-sizeId 키로 저장)  ✔
madre B 선택 → context = B → 수량 입력                                   ✔
A 행을 다시 클릭 → productOptions 에서 A 를 못 찾으면 → context 는 여전히 B
  → 화면엔 B 의 색·사이즈가 뜨고, 입력한 수량이 **A 의 variantQuantities 에
     B 의 키로** 저장된다
전송 → 확장 로직이 그 키를 A 의 stockByVariant 에서 못 찾음
  → "Variant productId 해석 실패 (N건)" 토스트, 판매 차단
```

코드마드레가 하나면 절대 안 나타난다. 그래서 재현이 어렵다.

★ 남아 있던 디버그 로그에 `foundInProductOptions` 플래그가 이미 있었다 —
누가 이 경로를 의심하고 있었다는 뜻이다.

### 9-C. 수정

출처를 3단으로 두고 **어느 것도 못 구하면 비운다.**

| 순위 | 출처 |
|---|---|
| ① | `productOptions` (서버 최신) |
| ② | 카트 행이 들고 있는 메타 — `Fix C` 가 stockByVariant/sizes/colors 를 채워둔다 |
| ③ | `stockByVariant` 에 박혀 있는 `color`/`size` 객체로 축을 역산 |

**빈 그리드가 남의 그리드보다 안전하다** — 잘못된 조합에 수량이 기록되지 않는다.
찾은 경우의 동작은 종전과 완전히 같다(같은 값을 같은 순서로 set)이라 회귀 위험이 낮다.

진단용 `gridSourceUsed`(`'productOptions'|'row'|'none'`)를 로그에 남겼다.
`'row'`/`'none'` 이 자주 찍히면 목록 로딩(`/products/by-parent?pageSize=1000`) 쪽을 봐야 한다.

### 9-D. 사람이 확인할 것

1. madre A 선택 → 수량 입력 → madre B 선택 → **A 행 다시 클릭** →
   그리드가 **A 의 색·사이즈**인지 (종전엔 B 가 떴다)
2. 그 상태로 판매 전송이 통과하는지 ("Variant productId 해석 실패" 가 안 뜨는지)
3. 콘솔의 `[handleParentRowClicked] gridSourceUsed` 값
4. **배포 직후 화면이 이상하면 하드 리프레시** — stale HTML/청크 문제일 수 있다

### 9-E. 아직 안 본 것

`productOptions` 에서 왜 못 찾는지 **근본 원인은 아직 모른다.**
`rawProducts` 는 `?parent=${!showParentsState}&pageSize=1000` 으로 받는데,
`showParentsState` 를 토글하면 madre ↔ hijo 로 목록이 통째로 바뀐다.
그 시점에 카트의 madre 행을 클릭하면 목록에 없다 — 유력 후보다.
`gridSourceUsed` 로그가 `'row'` 로 자주 찍히면 여기부터 보면 된다.


---

## 10. [2026-08-09] ★ POS 에서 제품이 사라졌던 회귀 — 근본 원인 (api #652)

§9 는 증상(그리드 잔류)을 막은 것이고, **이것이 근본 원인**이다.
§9-E 에 "productOptions 에서 왜 못 찾는지 모른다" 고 적어둔 그 답이기도 하다.

### 10-A. 무슨 일이 있었나

`2026-08-07-stock-leaf-only.sql` ① 이 "활성 자식이 0 이면 부모가 아니다" 로
`is_parent` 4행을 false 로 정정했다. **리포트 관점에서는 맞는 정정이었다.**

그런데 POS 상품 목록이 그 **플래그**로 모집단을 정의하고 있었다:

| 목록 | 조건 | 정정된 제품은 |
|---|---|---|
| `parent=false` (Productos padres) | `is_parent = true` | 탈락 |
| `parent=true` (hijos) | `parent_id IS NOT NULL` | 역시 탈락 |

두 목록 어디에도 없다. POS 검색과 바코드 스캔은 **둘 다 이 목록을 클라이언트에서
필터링**하므로(서버 조회 폴백이 없다) 어느 쪽으로도 못 고른다.
→ **팔 수 있는 제품이 POS 에서 통째로 사라졌다.**

### 10-B. 실측

`251532001`(JEAN 2 FLORES)은 2026-08-07 까지 POS 로 팔리고 있었다
(`sales.source='pos'`, 08-07 에 2건). 그 뒤 원장이 끊긴다.

| 매장 | 종전 | 지금 | 돌아온 것 |
|---|---|---|---|
| 6 | 15 | 19 | 251532001 외 |
| 8 | **1** | 5 | CAMPERA 4종 — **재고 40개가 판매 불가였다** |
| 9 | 14 | 18 | 25193444001 외 |
| 13 | **0** | 1 | 목록이 **아예 비어 있었다** |
| 14 | **0** | 1 | 같음 |
| 15 | 5 | 6 | |

매장 공통으로 제네릭 제품 `GEN-0001` 도 안 보이고 있었다.

### 10-C. 수정

그 마이그레이션 주석이 이미 답을 적어놨다 —
**"자식이 0 인 제품은 그 자체가 판매 단위이다"**, 그리고
**"is_parent 는 시간에 따라 바뀌므로 판정 기준으로 부적합하다"**.

그래서 모집단을 플래그가 아니라 **구조**로 정의한다: `parent_id IS NULL`.
73-NEXT-6 §9·§14 에서 리포트 모집단에 적용한 것과 **글자 그대로 같은 교훈**인데,
그때 리포트만 고치고 POS 목록은 안 봤다.

부수: 삭제된 제품(`status='deactivated'`)을 두 목록에서 제외했다 — 종전에는 status
필터가 아예 없어 삭제한 제품도 판매 목록에 떴다(운영 각 1행).

### 10-D. 하네스 — `joinReads` opt-in

조회 전용 서비스(`findByParentFlag`)는 `transaction` 인자를 안 받는다. 기본 하네스는
CLS 를 꺼두므로(§2-A ②) 그 쿼리들이 커넥션을 못 얻어 acquire 타임아웃이 난다.
그래서 **그 호출에서만** Sequelize 쿼리 주입을 켜는 `joinReads` 를 넣었다.

★ **쓰기 경로 테스트에서는 절대 켜지 마라.** 켜는 순간 `transaction` 인자 누락이
안 보인다 — 그 함정으로 변이 12건이 통째로 green 이었다.

★ 함정: `Sequelize._cls` 를 직접 대입하면 **sequelize-typescript 하위 클래스**에
own property 가 생길 뿐이고, 주입 코드는 lib 안의 **기반 클래스**를 본다.
설정은 `useCLS()`, 해제는 `require('sequelize').Sequelize._cls` 삭제로 해야 한다.
이걸 몰라서 raw `sequelize.query` 만 주입을 못 받는 현상을 한참 봤다.

---

## 11. 함정 추가 (§7 에 이어)

31. **DB 를 정정하는 마이그레이션은 그 컬럼을 읽는 곳을 전부 grep 해라.**
    `is_parent` 를 "옳게" 고쳤더니 POS 상품 목록이 그 플래그로 모집단을 정의하고 있어
    제품이 사라졌다. 리포트만 보고 판매 화면을 안 봤다. §10.
32. **모집단은 플래그가 아니라 구조로 정의해라.** `is_parent`(상태) 대신
    `parent_id IS NULL`(구조). 리포트에서 배운 교훈인데 POS 에 적용을 안 했다.
33. **POS 검색·바코드는 서버 조회 폴백이 없다.** 둘 다 `/products/by-parent` 로 받은
    목록을 클라이언트에서 필터링할 뿐이라, 그 목록에서 빠지면 **어떤 방법으로도**
    제품을 고를 수 없다.
34. **`Sequelize._cls` 는 기반 클래스에 있다.** sequelize-typescript 의 `Sequelize` 에
    대입하면 조용히 아무 효과가 없다. §10-D.
