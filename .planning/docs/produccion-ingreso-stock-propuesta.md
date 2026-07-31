# 생산 완료 → 매장 입고 → 판매 가능 흐름 (개념 + UI 제안)

작성 2026-07-30 · 대상 트랙: **외주 talleres (lote)** · 입고 목적지: **창고/매장 선택** · 자동화: **QC 통과 시 자동 제안 → 1클릭 확정**

목업: `.planning/mockups/produccion-ingreso-stock.html`

---

## 0. 한 줄 요약

지금 시스템에는 "생산이 끝났다"를 **판정하는 코드가 없습니다**. `ingreso-stock` 버튼은 존재하지만 아무 시점에나 누를 수 있고, 누르지 않으면 아무 일도 일어나지 않습니다. 제안의 핵심은 **판정(자동) + 관문(1클릭) + 판매준비 검증** 세 가지를 넣는 것입니다.

---

## 1. 현재 상태 (코드 실측)

### 1.1 이미 있는 것 — 재사용 가능

| 자산 | 위치 | 상태 |
|---|---|---|
| 로트 → 재고 입고 API | `subcon/lotes/lote.service.ts:77` `ingresarAStock()` | 동작. 단일 트랜잭션 |
| 재고 원장 기록 | `products/productStock.service.ts:36` `ingresarStockPorMatrix()` | `product_branch_id` 원장 + `products.stock` 캐시, 락 순서 고정 |
| 입고 UI | `views/talleres/drawers/IngresoStockDialog.tsx` | 목적지 선택(창고 기본값), 날짜 |
| 부분입고 (백엔드) | `quantities` 파라미터 + `stockedQuantity` 누적 | 백엔드만 지원, **프론트 미사용** |
| 지점 간 이동 | `POST /stocks/movement` (`type:'movido'`, `STOCK_TYPE.TRANSFER`) | end-to-end 완성. 감사로그·권한 가드 포함 |
| 라우팅 진행상태 조회 | `lote.service.ts:1272` `getRoutingStatus()` | etapa별 FREE/IN_PROGRESS/COMPLETED |
| 창고 구분 | `branch.isWarehouse` | 존재 |

### 1.2 없는 것 — 이번에 만들 것

1. **"마지막 공정 완료" 판정이 없음.** `routingPath`는 `{order, etapaId, vendorId}` 설계 데이터만 담고 진행상태 필드가 없습니다. `isLast`/`routing.at(-1)` 류 코드가 subcon 전체에 0건입니다.
2. **`LoteStatus.COMPLETED`를 세팅하는 코드가 0건.** enum에만 존재합니다.
3. **QC 통과 수량 집계가 없음.** `QcAction.ACCEPT`는 아무 동작도 하지 않고, `receivedQuantity`와 QC 아이템 수량 사이의 정합성 검증도 없습니다.
4. **입고 이력이 없음.** `stockedQuantity` 스칼라 하나만 덮어씁니다 → 부분입고 되돌리기·감사 불가.
5. **판매 준비 검증이 없음.**

### 1.3 선결해야 할 기존 결함 (이 기능의 전제)

| # | 결함 | 위치 | 영향 |
|---|---|---|---|
| D1 | `ingresarAStock`의 lote 조회에 `FOR UPDATE` 없음 | `lote.service.ts:104` | 동시 입고 시 `totalQuantity` 초과 입고 |
| D2 | 입고해도 `availableQuantity`가 안 줄어듦 | 갱신 지점 전수 확인함 | **이미 재고화한 수량을 다시 taller로 발송 가능** |
| D3 | envio가 전부 `CANCELLED`여도 `COMPLETED`로 판정 | `lote.service.ts:1307` | 자동 트리거가 취소된 공정을 완료로 오인 |
| D4 | vendor-portal 수령 경로가 `availableQuantity` 미갱신 | `vendor-portal/vendor-recepciones/vendor-recepciones.service.ts:63` | 입구에 따라 재고가 달라짐 |
| D5 | `createRecepcion`의 lote 갱신에 락 없음 (read-modify-write) | `recepcion.service.ts:117` | lost update |
| D6 | QC `REWORK` 시 불량분이 available에 이중 계상 | `qc-item.service.ts:150` | 입고 가능 수량 과대 |
| D7 | `stocks.stock`이 `integer` | `stocks` 테이블 | 의류는 정수라 무해. 원단(MES) 쪽에서만 문제 |

> D1·D2·D3는 자동 트리거를 켜기 전에 **반드시** 고쳐야 합니다. 나머지는 같은 Wave에서 묶어 처리하는 것을 권장합니다.

### 1.4 가장 큰 함정 — "판매 가능"의 실체

POS 상품 조회(`productStock.service.ts:940` `findByParentFlag`)의 where 조건은 **`storeId`와 `parentId` 뿐**입니다. `isActive`, 가격 존재, 재고, ProductBranch 존재 어느 것도 필터가 아닙니다. 판매 생성(`sales-create.service.ts`)에서도 `allowSaleWithoutStock=false`인 매장만 재고를 봅니다(기본값 true).

즉 **입고만 하면 판매는 이미 됩니다.** 진짜 위험은 반대쪽입니다:

> 가격이 없는 변형은 `prices` → `products.price` → **0원** 폴백으로 카트에 담깁니다. 아무도 막지 않습니다.

그래서 "판매될 수 있게"의 실질 요건은 재고가 아니라 **가격·활성·지점 슬롯**이며, 이것을 입고 시점에 검증하는 것이 이 제안의 절반입니다.

---

## 2. 개념 설계

### 2.1 수량 4개의 정의를 확정한다

현재 `totalQuantity` / `availableQuantity` / `stockedQuantity` 세 개의 의미가 흐릿합니다. 아래로 고정합니다.

| 이름 | 정의 | 불변식 |
|---|---|---|
| `totalQuantity` | 재단 수량(계획). 변하지 않음 | — |
| `availableQuantity` | **손안에 있고 아직 어디에도 안 나간 수량** | `+수령`, `−발송`, `−scrap`, **`−입고`(D2 신규)** |
| `qcOkQuantity` (신규 파생) | QC 통과 누계 = Σ`receivedQuantity` − Σ`QcItem(SCRAP,REWORK)` | 입고 상한의 진짜 기준 |
| `stockedQuantity` | 재고 원장에 올라간 누계 | `stockedQuantity ≤ qcOkQuantity ≤ totalQuantity` |

**입고 가능 수량 = `qcOkQuantity − stockedQuantity`.** 현재 상한이 `totalQuantity`인 것은 불량품까지 입고 가능하다는 뜻이라 틀렸습니다.

### 2.2 상태 머신

```
OPEN ──1차 발송──▶ IN_PROGRESS ──마지막 etapa COMPLETED + QC 처리완료──▶ READY_TO_STOCK
                                                                          │ 부분입고
                                                                          ▼
                                        COMPLETED ◀──saldo 0── PARTIALLY_STOCKED
                                            │ 수동
                                            ▼
                                         CLOSED
```

- `READY_TO_STOCK` / `PARTIALLY_STOCKED` 2개를 enum에 추가.
- `COMPLETED` 판정 = `stockedQuantity >= qcOkQuantity` **AND** 미결 envio 0건.
- `CLOSED`는 기존대로 사람이 누르는 회계 마감.

### 2.3 자동 트리거 — pool을 쓰지 않는 방식

**폴링 스케줄러를 만들지 않습니다.** 매장 수 × 로트 수만큼 커넥션을 갉아먹습니다.

트리거 지점은 딱 하나: `recepcion.service.ts` `createRecepcion()`의 **같은 트랜잭션 안**에서 판정하고, 알림·캐시 무효화만 `afterCommit`으로 뺍니다.

```
createRecepcion(tx)
  └ 기존 로직 (envio 갱신, lote available, QC)
  └ [신규] evaluateLoteReadiness(loteId, tx)      ← 쿼리 2개, 같은 커넥션 재사용
        ├ routingPath 마지막 order의 etapa에 대한 envio가 모두 COMPLETED 인가?
        │   (CANCELLED만 있는 경우는 미완료로 본다 — D3)
        ├ 해당 envio에 미처리 REWORK child가 없는가?
        └ 예 → lote.status = READY_TO_STOCK
  └ afterCommit
        ├ cacheService.delByPrefix('talleres:kanban:${storeId}:')
        └ 알림 1건 (VendorNotifications 패턴 재사용) — 실패해도 throw 금지
```

`subcon`에는 socket도 `sync_outbox`도 없으므로 새 인프라를 끌어오지 않고 기존 `afterCommit` + 캐시 무효화 패턴을 그대로 씁니다. 프론트는 SWR 5분 dedup에 얹어 Ingresos 탭 진입 시 갱신.

> 외부 I/O(프린터·소켓)는 CLAUDE.md 규약대로 **커밋 후**에만 합니다.

### 2.4 입고 트랜잭션 (커밋 경계)

```
BEGIN
  SET LOCAL lock_timeout='3s'; statement_timeout='15s'
  lote FOR UPDATE                                  ← D1
  가드: Σ요청 ≤ qcOkQuantity − stockedQuantity
  가드: 목적지 branch.storeId == user.storeId       ← 현재 미검증
  ingresarStockPorMatrix(destino별)                ← productId 오름차순 락 (기존)
    · stocks INSERT (type='production')
    · products.stock INCREMENT + updateMotherStock
  lote_ingresos INSERT (이력 1행/목적지)            ← 신규
  lote.stockedQuantity += Σ
  lote.availableQuantity -= Σ                      ← D2
  lote.status = COMPLETED | PARTIALLY_STOCKED
COMMIT
  → (선택) Zebra 라벨 출력 dispatch
  → 캐시 무효화
```

`skipped > 0`(변형 미존재)이면 지금처럼 전체 롤백 — 부분 반영으로 재고가 어긋나는 것보다 낫습니다.

> **`stocks`는 DB 트리거로 append-only가 강제되어 있습니다** (`2026-07-28-phase65-w2-stocks-immutable-trigger.sql`, `stocks_immutable_guard`). UPDATE/DELETE는 500이 납니다. 입고 취소/정정은 **반드시 반대 부호 보정 행 INSERT**로만 구현하십시오. 우회(`SET LOCAL ventago.stocks_maintenance='on'`)는 매장 퍼지용이므로 이 경로에서 쓰지 않습니다.

> **프리플라이트의 재고 판정은 정본 VIEW를 씁니다.** `2026-07-30-product-stock-views-v2-per-branch.sql`의 `v_product_branch_stock`이 지점별 on-hand / reserved / available 3값의 단일 출처입니다. 새로 SUM 쿼리를 짜지 말고 이 VIEW를 조회하십시오(쿼리 중복 = 드리프트 원인).

### 2.5 창고 → 매장은 신규 개발이 아니다

`POST /stocks/movement`(`movido`)가 이미 origin `−qty` / target `+qty` 두 행을 한 트랜잭션에 쓰고, 감사로그와 지점 권한 가드까지 갖췄습니다. 다만 현재 진입점이 **POS 화면의 체크박스**뿐이라 발견되지 않습니다. 입고 직후 이어지는 "배분" 화면을 만들되 **백엔드는 그대로 재사용**합니다.

---

## 2.6 ★ 멀티테넌트 격리 — 이 경로의 실제 방어선

Phase 67의 4중 방어가 입고 경로에 **어디까지 닿는지** 실측했습니다. 결론부터: **가장 취약한 연결고리가 정확히 이 경로입니다.**

### 방어선 현황 (실측 2026-07-30, 로컬 5432)

| 지점 | L1 ctx | L2 훅 | L4 트리거 | 판정 |
|---|---|---|---|---|
| `Lote` / `Envio` / `Recepcion` / `QcItem` 조회·생성 | ○ | ○ store_id 보유 | ✕ 없음 | **보호됨** |
| `Product` 조회 (`ingresarStockPorMatrix`의 `parentId` 검색) | ○ | ○ | ○ `trg_tenant_products_parent` | **보호됨** |
| `ingresarAStock`의 **`targetBranchId` 소속 검증** | — | — | — | **✕ 뚫림** |
| `ProductBranch.findOrCreate` (신규) | — | ✕ store_id 없음 | ○ `trg_tenant_productbranch_store` | 트리거만이 방어 |
| 기존 오염 `ProductBranch` 재사용 → `stocks` INSERT | — | ✕ | ✕ (UPDATE 트리거는 FK 변경 시만 발동) | **✕ 뚫림** |
| `stocks` 테이블 | — | ✕ store_id 없음 | ✕ 트리거 없음 | 방어 없음 |
| vendor-portal 수령 경로 (`@Public()`) | **✕ resolve 안 함** | ✕ 전면 no-op | — | `vendorIds` 앱 체크만 |

핵심 구조: **"제외 69개"는 명시 목록이 아니라 `store_id` 컬럼이 없어서 자동으로 빠진 것**입니다(`tenant-scope.registry.ts:86` `resolveModelPolicy`, `EXEMPT_TABLES`는 6개뿐). `installForModel`은 `!policy.guarded`면 첫 줄에서 `return null` — 부모 join으로 유도하는 코드는 **존재하지 않습니다**. `ProductBranch`·`Stocks`·`Prices` 셋이 여기 해당합니다.

로컬 실측: 테넌트 트리거 **21개 전부 존재**, 교차오염 `ProductBranch` **0행**.

### 왜 `stocks`에 트리거를 달면 안 되는가

`stocks`는 **판매 1건마다 INSERT되는 핫패스**입니다. 여기에 join 2개짜리 트리거를 달면 판매 지연과 pool 점유가 늘어납니다. 그럴 필요가 없습니다 —

> **불변식:** `stocks` 행은 반드시 `ProductBranch`를 참조하고, `ProductBranch`는 INSERT/FK-UPDATE 시점에 `products.store_id = branches.store_id`가 트리거로 강제됩니다.
> 따라서 **`ProductBranch`에 오염 0이면 `stocks`는 전이적으로 깨끗합니다.**

남은 유일한 구멍은 "Phase 67 이전에 만들어져 이미 오염된 `ProductBranch` 행"입니다. 로컬 0행이므로, **운영 0행만 확인하면 `stocks` 트리거는 불필요**합니다. 핫패스를 건드리지 않는 것이 정답입니다.

### 그래서 추가할 방어 4가지

**G1 · `assertBranchInStore()` — 앱 레이어 게이트 (필수)**

`ingresarAStock`의 `targetBranchId`는 지금 **존재 여부만** 검사합니다(`lote.service.ts:94`). L1·L2·L3 어디에도 걸리지 않고 곧장 `ProductBranch.findOrCreate`로 흘러갑니다. DB 트리거가 마지막에 잡아주긴 하지만, 트리거가 던지는 에러는 사용자에게 의미 없는 500입니다.

```ts
// 입고 목적지가 호출자 매장 소속인지 확인한다. tx 는 선택이 아닌 필수.
private async assertBranchInStore(branchId: number, storeId: number, tx: Transaction) {
  const branch = await this.branchModel.findOne({
    where: { id: branchId, storeId },
    attributes: ['id'],
    transaction: tx,
  });

  if (!branch) throw new BadRequestException('Destino inválido para esta tienda');
}
```

다중 목적지 배분을 넣으므로 **목적지 하나하나에** 적용합니다. 이 한 함수가 새 UI가 여는 공격면 전부를 덮습니다.

**G2 · 신규 테이블도 방어선에 등록**

`talleres_lote_ingresos`는 `store_id NOT NULL`로 만들어 L2 보호 대상이 되게 하고(컬럼이 없으면 조용히 제외됩니다), `branch_id`·`lote_id` 2개를 L4 동적 루프에 추가합니다. 저빈도 테이블이라 트리거 비용이 무의미합니다.

```sql
-- 기존 tenant-crossstore-triggers.sql 의 동적 루프 배열에 2줄 추가
--   ('talleres_lote_ingresos','branch_id','branches')
--   ('talleres_lote_ingresos','lote_id','talleres_lotes')
```

**G3 · superadmin이 큐를 열면 전 매장이 섞인다**

`allowedStores()`는 `ctx.isSuperAdmin`이면 **null을 반환해 L2를 전면 no-op**시킵니다. 새로 만드는 `GET /talleres/lotes/ingreso-queue`를 superadmin이 호출하면 **모든 매장의 로트가 한 화면에 나옵니다.** Phase 67-B가 정확히 이 NULL 탈출구를 봉쇄한 이유입니다.

- 큐·프리플라이트·입고 3개 엔드포인트 모두 `storeIdOfUser(user)`로 매장을 확정하고, **NULL이면 400**으로 거절합니다.
- superadmin이 대신 처리해야 하면 `X-Store-Id` 대행 헤더를 쓰게 합니다(`act-as-store.ts:28`). 대행 시 `TenantContext`가 `isSuperAdmin=false`로 확정되어 L2가 정상 작동합니다.
- **`user.roles`는 `string[]`입니다.** `r.slug`로 읽으면 superadmin 판정이 조용히 실패합니다(Phase 67에서 실제로 그랬습니다). 반드시 `isSuperAdminUser(user)` (`tenant-user.util.ts:26`)를 씁니다.

**G4 · 자동 트리거를 vendor-portal 경로에 그대로 얹지 말 것**

D4(vendor 수령 경로를 공통 서비스로 수렴)를 실행할 때가 가장 위험합니다. `vendor-recepciones.controller.ts`는 `@Public()`이고, `JwtGlobalGuard`는 public이면 `TenantContext.resolve()`를 **호출하지 않고 즉시 return true** 합니다. 컨텍스트가 `resolved:false`로 남아 **L2가 전면 no-op**입니다.

즉 vendor 수령에서 `evaluateLoteReadiness(loteId, tx)`를 그냥 부르면 **타 매장 로트의 상태를 바꿀 수 있습니다.**

- 대책: 공통 서비스는 `storeId`를 **선택이 아닌 필수 인자**로 받고, 모든 조회에 `where: { storeId }`를 **명시**합니다(훅에 기대지 않습니다).
- vendor 경로의 storeId는 `envio.vendor.storeId`에서 유도하되(`vendor-recepciones.service.ts:82` 기존 방식), `vendorIds` 소유 검증(`:49`) 이후에만 신뢰합니다.
- 더 나은 방법: vendor 경로에서 `TenantContext.runWithStore(storeId, () => ...)`로 컨텍스트를 명시적으로 세워 L2를 되살리는 것. 공개 엔드포인트 전반에 재사용 가능한 패턴이라 별도 검토 가치가 있습니다.

### 배포 전 검증 쿼리 (로컬·운영 양쪽)

```sql
-- ① 교차오염 ProductBranch — 반드시 0
SELECT count(*) FROM "ProductBranch" pb
  JOIN products p ON p.id = pb.product_id
  JOIN branches b ON b.id = pb.branch_id
 WHERE p.store_id IS DISTINCT FROM b.store_id;

-- ② 교차오염 stocks (①이 0이면 자동 0이어야 함)
SELECT count(*) FROM stocks s
  JOIN "ProductBranch" pb ON pb.id = s.product_branch_id
  JOIN products p ON p.id = pb.product_id
  JOIN branches b ON b.id = pb.branch_id
 WHERE p.store_id IS DISTINCT FROM b.store_id;

-- ③ 테넌트 트리거 21개 존재 확인
SELECT c.relname, t.tgname FROM pg_trigger t
  JOIN pg_class c ON c.oid = t.tgrelid
 WHERE NOT t.tgisinternal AND t.tgname LIKE 'trg_tenant%' ORDER BY 1,2;

-- ④ 로트와 목적지 지점의 매장 일치 (입고 이력 도입 후 상시 감시)
SELECT count(*) FROM talleres_lote_ingresos i
  JOIN branches b ON b.id = i.branch_id
 WHERE b.store_id IS DISTINCT FROM i.store_id;
```

로컬은 ①③ 검증 완료(0행 / 21개). **운영 5434는 미확인** — Wave A 착수 전 첫 작업입니다.

### ★ 운영 실측 (2026-07-30, PG18 5434) — 오염 2건 발견

```
lote_vs_product      2   ← ★ 발견
envio_vs_lote        0
recepcion_vs_envio   0
productbranch        0
stocks_via_pb        0
products_parent      0
```

| lote_id | lote_number | lote.store_id | product_id | product.store_id | sku | 상태 |
|---|---|---|---|---|---|---|
| 1 | LOT-2026-001 | **6** | 1 | **3** | CAMP0261 | OPEN, envío 0건, 2026-04-21 |
| 9 | LOT-2026-004 | **6** | 6 | **3** | 25041020001 | OPEN, envío 0건, 2026-04-28 |

운영 로트 총 6건 전부 store 6 소속인데, 그 중 2건이 **store 3의 상품을 가리키고 있습니다.**
두 로트 모두 발송·수령 이력이 0건이고 `available = total`이라 **아직 물건이 움직이지 않았습니다.**
`ProductBranch`·`stocks` 오염이 0인 이유가 이것입니다 — 운이 좋았을 뿐, 구조적으로 막힌 게 아닙니다.

**만약 이 로트에 「Ingresar」를 눌렀다면:** store 3 상품의 재고가 store 6 지점에 생성됩니다.
`trg_tenant_productbranch_store`가 최후에 잡아 500을 던지겠지만, 사용자에게는 원인 불명의 오류이고
그 전까지의 트랜잭션 작업이 전부 낭비됩니다. **DB가 마지막에 막는 것은 설계가 아니라 안전망입니다.**

### 진짜 구멍은 컬럼이 아니라 CHECK 부재

talleres 핵심 테이블 8개는 **이미 `store_id`를 가지고 있습니다** — `talleres_lotes`, `talleres_envios`,
`talleres_recepciones`, `talleres_qc_items`, `talleres_orders`, `talleres_vendors`, `talleres_etapas`,
`talleres_rework_orders`, `talleres_settlement_lines`. 즉 "order가 storeId를 들고 다닌다"는 요건은 충족됩니다.

문제는 **그 `store_id`가 부모의 `store_id`와 같은지 아무도 검사하지 않는다**는 것입니다.
L4 테넌트 트리거 21개 목록에 **`talleres_*`가 단 하나도 없습니다** (실측 확인).
`lote.store_id = 6`은 스스로를 신고할 뿐, `product_id = 1`이 남의 매장 것이어도 침묵합니다.

### G5 · talleres 계열 L4 트리거 추가 (신규 · 최우선)

기존 `tenant_chk_child_parent_same_store()` 범용 함수와 동적 루프 패턴을 그대로 재사용합니다.
전부 저빈도 테이블이라 **핫패스 비용이 0**입니다.

| 자식 테이블 | FK | 부모 |
|---|---|---|
| `talleres_lotes` | `product_id` | `products` | ★ 이번 오염 2건의 지점 |
| `talleres_envios` | `lote_id` / `vendor_id` / `etapa_id` | lotes / vendors / etapas |
| `talleres_recepciones` | `envio_id` | envios |
| `talleres_qc_items` | `recepcion_id` | recepciones |
| `talleres_orders` | `vendor_id` / `product_id` | vendors / products |
| `talleres_rework_orders` | `lote_id` | lotes |
| `talleres_settlement_lines` | `recepcion_id` / `envio_id` / `etapa_id` | — |
| `talleres_lote_ingresos` (신규) | `branch_id` / `lote_id` | branches / lotes |

`talleres_vendor_etapas`는 `store_id`가 없어 동적 루프가 `CONTINUE`로 건너뜁니다
(`tenant-crossstore-triggers.sql:244`). 부모 2개(`vendor`·`etapa`)의 매장 일치를 보는 전용 트리거가 별도로 필요합니다.

> **taller 전용 앱을 만들 때 이 트리거가 방어선의 전부가 됩니다.** vendor-portal은 `@Public()`이라
> L1이 서지 않고 L2가 전면 no-op이기 때문입니다(G4). 앱을 붙이기 **전에** G5를 넣어야 합니다.

### 요구 검증 — "매장 1은 매장 2가 taller A에 보낸 물건을 절대 못 본다"

같은 taller가 두 매장을 상대하는 시나리오(매장1→A·B, 매장2→A·C)로 전 경로를 감사했습니다.

**성립하는 곳 (매장 사용자 관점)**

| 경로 | 명시 storeId | L2 훅 | 판정 |
|---|---|---|---|
| `envio.service.ts` `findFiltered` / `getVendorPendingSummary` / `getOverdueEnvios` | ○ | ○ | **보호됨** |
| `dashboard.service.ts` `getKanbanBoard` (캐시키에도 storeId) | ○ | ○ | **보호됨** |
| `dashboard-v2.service.ts` 전 함수 | ○ | ○ | **보호됨** |
| subcon raw SQL 10곳 전수 | ○ 전부 `:storeId` 바인딩 | — | **보호됨** |

칸반·대시보드·발송목록은 요구를 만족합니다. taller A가 두 매장에 걸쳐 있어도 `vendorId`가 매장별 별도 행이라 교집합이 비어 있습니다.

**성립하지 않는 곳 2군데 (둘 다 현재 잠복 — 데이터가 아직 없을 뿐)**

**G6 · `talleres_settlements` 정산 헤더가 전 매장 노출**

`subcon-settlement.model.ts`에 **`store_id` 컬럼이 없습니다** → `resolveModelPolicy`가 unguarded 판정 → **L2 훅 미설치**. 그 상태에서 `findFiltered`(`subcon-settlement.service.ts:604-612`)가 `SubconOrder` include에 `required: false`를 줍니다. LEFT JOIN이므로 storeId 조건이 ON 절로 내려가고, **`subcon_order_id IS NULL`인 정산은 매장 무관하게 전부 반환**됩니다. Wave 7의 vendor 기반 정산이 정확히 `subconOrderId: null`로 생성됩니다(`:276`).

노출 항목: vendorId, 기간, 총액, 공제, 순액, status, notes.

> 운영 실측: `talleres_settlements` **0행** → 아직 안 터졌습니다. 정산 기능을 쓰기 시작하는 순간 터집니다.

같은 이유로 L2 사각지대인 subcon 모델 7개: `settlements`, `payments`, `deliveries`, `defects`, `material_issues`, `vendor_etapas`, `envio_materiales`. 이 중 **`subcon-payments`는 `CrudController`를 오버라이드 없이 상속**하고 있어 별도 검증이 필요합니다.

조치: 업무 객체인 `settlements`·`payments`·`deliveries`에 `store_id NOT NULL` 추가(§2.6의 분류 기준상 이들은 "업무 객체") + `required: true` 수정. `vendor_etapas`·`envio_materiales`는 연결 테이블이므로 부모 유도 유지.

**G7 · vendor-portal이 매장 경계를 넘는 통로 (★ taller 앱의 실제 관문)**

vendor 로그인은 `phone + PIN`입니다(`vendor-auth.service.ts:13-62`).

1. `Vendor.findAll({ where: { phone, isActive: true } })` — **storeId 조건 없이 전 매장 스캔**
2. PIN 검증이 **`vendors[0].pinHash` 한 건에만** 수행(`:34-42`). `ORDER BY`가 없어 `vendors[0]`이 어느 매장 행인지 **비결정적**
3. `talleres_vendors.phone`에 **UNIQUE 없음**
4. 발급 토큰의 `vendorIds`에 **양쪽 매장 vendor 행이 모두** 들어감
5. 조회 시 **"이 storeId가 내 vendorIds 소속인가"를 검증하는 코드가 한 줄도 없음**

**공격 경로:** 매장 1 관리자가 자기 vendor 행에 **매장 2의 taller 전화번호**를 적고 PIN을 설정합니다. 그 PIN으로 vendor-portal에 로그인하면 `vendorIds`에 매장 2의 taller A 행이 함께 들어오고, `storeId=2`로 조회해 **매장 2의 envío·정산·알림을 봅니다.**

`vendor-notifications`는 `storeId`가 **옵셔널**이라 아예 생략하면 전 매장 알림이 반환됩니다(`:34-40`). 알림 본문에 `Envío #id`·수량·납기가 들어갑니다.

그리고 **vendor-portal 4개 컨트롤러 전부 `@Public()`** 이라 `JwtGlobalGuard`가 `TenantContext.resolve()`를 호출하지 않습니다 → **L2 훅 보호가 0**. 서비스의 명시 `where`만이 유일한 방어선입니다.

> 운영 실측: vendor 7개 **전부 store 6**, phone 중복 **0건** → 아직 안 터졌습니다.
> **매장이 2개 이상 talleres를 쓰기 시작하거나 taller 전용 앱을 붙이는 순간 터집니다.**

조치 (taller 앱 착수 **전** 필수):

- `phone`을 `(store_id, phone)` 복합 UNIQUE로. 전역 UNIQUE는 정당한 멀티스토어 taller를 막으므로 안 됩니다.
- PIN을 **후보 vendor 행 전부에 대해** 검증하고, **일치한 행의 매장만** `vendorIds`에 담습니다. 여러 매장에 걸치려면 **각 매장에서 같은 PIN을 설정**해야 하도록 — 즉 **양쪽 매장의 동의가 암묵적 전제**가 되게 합니다.
- 모든 vendor-portal 엔드포인트에 `assertStoreOwned(storeId, req.user.vendors)` 게이트. `vendor-notifications`의 `storeId`는 **필수**로 승격.
- `VendorJwtGuard` 안에서 검증 통과한 storeId로 `TenantContext`를 명시 확정 → **L2 훅을 되살립니다.** 공개 엔드포인트 전반에 재사용 가능한 패턴입니다.
- 참고로 잘 되어 있는 점: `vendor-jwt.strategy.ts:24-40`이 토큰의 `vendorIds`를 믿지 않고 phone으로 DB 재조회합니다 → 토큰 위조로 vendorIds를 늘리는 공격은 이미 차단됩니다.

### 왜 `ProductBranch`·`Stocks`·`Prices`에는 `store_id`를 붙이지 않는가

이 원칙은 **파생 테이블 3개에만** 적용됩니다. talleres 계열과는 무관합니다.

`stocks`에 `store_id` 컬럼을 붙인다고 가정해 봅니다. 그러면 한 행이 이렇게 될 수 있습니다:

```
stocks.store_id = 6          ← 컬럼이 주장하는 매장
  └ product_branch → product.store_id = 3   ← 관계가 말하는 매장
```

**어느 쪽이 진실입니까?** 가드는 컬럼(6)을 보고 통과시키고, 실제 관계는 교차 상태로 남습니다.
오염이 사라지는 게 아니라 **가드 뒤에 숨습니다.** 지금은 `stocks` 행이 자기 매장에 대해
거짓말할 방법이 없습니다 — 의견이 없고, 답은 항상 join으로 유도되기 때문입니다.

반대로 `talleres_lotes`는 **업무 객체**입니다. "이 로트는 6번 매장의 생산 지시"라는 사실이
상품과 독립적으로 존재해야 합니다(상품이 나중에 바뀌어도, 삭제돼도). 그래서 `store_id`를 갖는 게 맞고,
**대신 부모와의 일치를 트리거로 강제해야** 합니다. 컬럼을 갖는 순간 검증 의무가 따라옵니다 — 그게 G5입니다.

정리하면:

| 유형 | 예 | store_id | 격리 방법 |
|---|---|---|---|
| **업무 객체** (독립적 정체성) | lotes, envios, orders, recepciones | **가진다** | 컬럼 + **부모 일치 트리거(G5)** |
| **파생/연결 테이블** (부모 없이 무의미) | ProductBranch, Stocks, Prices | **안 가진다** | 부모에서 유도 + 관계 트리거 |

> Phase 67 메모의 원칙 그대로입니다: **오염 ≠ 누수.** 83개 테이블에 `store_id`가 없는 게 정상 설계입니다.
> 붙이면 진실의 원천이 둘이 되어 새 오염 경로가 생깁니다.

---

## 3. UI 제안

### 3.1 Talleres에 「Ingresos」 탭 신설

기존 탭(Lotes / Envíos / Recepciones / Liquidaciones / Defectos) 옆에 배지 달린 탭 하나. 배지 숫자 = `READY_TO_STOCK` + `PARTIALLY_STOCKED` 로트 수.

카드 1장에 담을 것:

- 로트번호 · 스타일 · 시즌 · **마지막 공정명 + 벤더 + 수령일** (신뢰의 근거)
- 진행 게이지: QC OK / Scrap / 미수령 / 이미 입고
- 숫자 4칸: 재단 · QC OK · 이미 입고 · **입고 가능**
- 주 버튼 하나: **`Ingresar 264 u.`** (수량이 버튼에 박혀 있어야 오조작이 줄어듭니다)
- 상태별 좌측 컬러 바: 초록=바로 가능 / 파랑=부분 / 노랑=차단(가격 누락 등)

이 화면이 요구사항의 "자동" 부분입니다. 사람이 찾아다니지 않고 **일이 사람에게 옵니다.**

### 3.2 입고 다이얼로그를 3단계로 개편

현재 `IngresoStockDialog`는 목적지+날짜만 받고 전량 입고합니다. 3단계로:

**① 목적지** — 여러 목적지 동시 배분 허용(창고 200 + 센트로 64). `isWarehouse` 우선 정렬은 유지.

**② 수량 매트릭스** — 사이즈×컬러 표를 그대로 편집 가능하게. 이게 백엔드의 `quantities` 파라미터를 드디어 쓰는 지점입니다. 하단에 잔량 요약(재단/QC OK/scrap/미수령) 항상 노출.

**③ 판매 준비 프리플라이트** — 이번 제안의 핵심 차별점.

| 체크 | 실패 시 |
|---|---|
| 매트릭스의 모든 talle×color 변형이 카탈로그에 존재 | 차단(현재도 롤백) |
| 목적지 지점의 `ProductBranch` | 자동 생성 (안내만) |
| **가격 > 0** (`prices` 또는 `products.price`) | **차단 + 인라인 가격 입력** |
| `isActive = true` | 경고 + 일괄 활성 체크박스 |
| 목적지가 창고면 "판매 안 됨" 고지 | 배분 화면 자동 연결 제안 |

가격 검증은 넣지 않으면 **0원 판매**로 새어나갑니다. 재고보다 이쪽이 실질 리스크입니다.

### 3.3 입고 후 배분 화면

원본 = 창고, 대상 = 매장들. 최근 30일 판매 비중 기반 **추천 수량**을 미리 채워 두고 사람이 조정. 확정 시 `POST /stocks/movement`를 지점 수만큼 호출(또는 bulk 엔드포인트 1개 신설 — 왕복 절약).

### 3.4 로트 상세 드로어 보강

`LoteDetailDrawer`에 「입고 이력」 섹션 추가 — 일시 / 목적지 / 수량 / 조작자. 현재는 스칼라 하나뿐이라 "누가 언제 어디로 넣었나"에 답할 수 없습니다.

---

## 4. 변경 목록

### DB (마이그레이션 1개)

> **선결 확인 (실측 2026-07-30)**: 로컬 PG18(5432)에 `talleres_lotes.stocked_quantity` **컬럼이 없습니다.**
> `api-ventago/migrations/2026-07-14-lote-stocked-quantity.sql` 파일은 있으나 로컬에 적용되지 않았습니다.
> 운영(5434) 적용 여부를 먼저 대조한 뒤, 미적용 쪽에 이 파일을 먼저 돌려야 합니다.
> (로컬 로트 3건 = 시드 수준이므로 로컬 적용 위험은 사실상 없습니다.)

```sql
-- 1) 상태 값 추가 — ★ ALTER TYPE 불필요.
--    talleres_lotes.status 는 PG enum 이 아니라 character varying(20) 이다 (실측).
--    'READY_TO_STOCK'(14자) / 'PARTIALLY_STOCKED'(17자) 둘 다 20자 안에 들어간다.
--    → 모델(TS) enum 만 확장하면 되고 DDL 변경 없음.

-- 2) 입고 이력
CREATE TABLE talleres_lote_ingresos (
  id            SERIAL PRIMARY KEY,
  lote_id       INTEGER NOT NULL REFERENCES talleres_lotes(id),
  branch_id     INTEGER NOT NULL REFERENCES branches(id),
  quantity      NUMERIC(12,2) NOT NULL,
  matrix        JSONB,
  operation_date DATE NOT NULL,
  created_by    INTEGER REFERENCES users(id),
  store_id      INTEGER NOT NULL REFERENCES stores(id),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_lote_ingresos_lote ON talleres_lote_ingresos(lote_id);
CREATE INDEX idx_lote_ingresos_store ON talleres_lote_ingresos(store_id);

-- 3) owner 이전 (운영 필수 — 누락 시 앱 500)
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='coolsistema') THEN
    ALTER TABLE talleres_lote_ingresos OWNER TO coolsistema;
    ALTER SEQUENCE talleres_lote_ingresos_id_seq OWNER TO coolsistema;
  END IF;
END $$;
```

로컬(5432) + 운영(5434) **양쪽 동시 적용**.

### 백엔드

| 파일 | 변경 |
|---|---|
| `subcon/lotes/lote.model.ts` | status enum 2값 추가 |
| `subcon/lotes/lote-ingreso.model.ts` | 신규 모델 |
| `subcon/lotes/lote.service.ts` | `ingresarAStock`: FOR UPDATE(D1), available 차감(D2), qcOk 상한, 다중 목적지, 이력 INSERT, 상태 전이 |
| `subcon/lotes/lote.service.ts` | **`assertBranchInStore()` 신규 (G1)** — 목적지마다 호출 |
| `subcon/lotes/lote.service.ts` | `getRoutingStatus`: 전부 CANCELLED → COMPLETED 아님(D3) |
| `subcon/lotes/lote.service.ts` | `evaluateLoteReadiness(loteId, tx)` 신규 |
| `subcon/lotes/lote.service.ts` | `getIngresoQueue(storeId)` 신규 — Ingresos 탭용 |
| `subcon/lotes/lote.controller.ts` | `GET /talleres/lotes/ingreso-queue`, `GET /:id/ingreso-preflight`, `GET /:id/ingresos` |
| `subcon/recepciones/recepcion.service.ts` | lote FOR UPDATE(D5) + `evaluateLoteReadiness` 호출 |
| `vendor-portal/vendor-recepciones/vendor-recepciones.service.ts` | 공통 경로로 수렴(D4) |
| `subcon/qc-items/qc-item.service.ts` | REWORK 이중계상 정리(D6) |
| `stocks/stocks.controller.ts` | (선택) `POST /stocks/movement/bulk` |

**pool 원칙:** 신규 쿼리는 전부 기존 트랜잭션의 `tx`를 필수 인자로 받습니다. 트리거는 이벤트 기반이며 스케줄러를 추가하지 않습니다.

### 프론트엔드

| 파일 | 변경 |
|---|---|
| `pages/talleres/ingresos/index.tsx` | 신규 — `next/dynamic({ssr:false})` |
| `views/talleres/tabs/IngresosTab.tsx` | 신규 — 큐 카드 |
| `views/talleres/drawers/IngresoStockDialog.tsx` | 3단계 개편, `quantities` 전송, 다중 목적지 |
| `views/talleres/dialogs/PreflightVentaStep.tsx` | 신규 |
| `views/talleres/dialogs/DistribucionDialog.tsx` | 신규 |
| `views/talleres/drawers/LoteDetailDrawer.tsx` | 입고 이력 섹션 |
| `hooks/api/useIngresoQueue.ts` | 신규 SWR 훅 |

ESLint: `newline-before-return`, `lines-around-comment` 주의.

---

## 5. 단계별 실행안

| Wave | 내용 | 산출 | 위험 |
|---|---|---|---|
| **0** | 운영 검증 ✔완료 · 오염 2행 **삭제 완료(2026-07-30)** · **G5 talleres 트리거** · `stocked_quantity` 마이그 정합 | 출발선 확정 | 낮음 |
| **G** | **G6 settlements 격리 + G7 vendor-portal 게이트** — taller 앱 착수 전 필수 | 매장 간 절대격리 완성 | 중 — 정산 0행이라 지금이 최적 타이밍 |
| **A** | 결함 D1~D6 + **G1 `assertBranchInStore`** + 마이그레이션(G2) | 동시성·정합성·격리 정상화 | 낮음. 기존 동작 유지 |
| **B** | `evaluateLoteReadiness` + 상태 2개 + `ingreso-queue` API (**G3 적용**) | 큐가 자동으로 채워짐 | 낮음 |
| **C** | Ingresos 탭 + 3단계 다이얼로그(부분입고) | 사용자 체감 변화 | 중 — UI 회귀 |
| **D** | 판매준비 프리플라이트 + 가격 인라인 | 0원 판매 차단 | 중 — 차단이 업무를 막을 수 있어 "무시하고 진행" 경로 필수 |
| **E** | 배분 화면 (movido 재사용) | 창고→매장 완결 | 낮음 |
| **F** | D4 수렴 + **G4 vendor-portal 컨텍스트** | 입구 단일화 | **높음** — `@Public()` 경로라 L2가 없음. 단독 Wave로 분리 |

Wave 0·A는 이 기능과 무관하게 **지금 실재하는 재고 오차·격리 구멍**이므로 단독 배포 가치가 있습니다.
Wave F를 A~E와 섞지 마십시오 — vendor-portal은 유일하게 훅이 꺼져 있는 구간이라, 다른 변경과 함께 배포하면 사고 원인을 분리할 수 없습니다.

---

## 6. 빠지기 쉬운 함정 3가지

1. **"자동 입고"를 완전 자동으로 만들고 싶어지는 것.** QC 반품·수량 정정이 나중에 들어오면 `stocks`는 append-only라 보정 행으로만 되돌릴 수 있습니다. 보정 행이 쌓이면 원장이 읽기 어려워집니다. 1클릭 확정을 유지하는 이유가 이것입니다.
2. **입고 상한을 `totalQuantity`로 두는 것(현행).** 불량품까지 판매 재고가 됩니다. 상한은 `qcOkQuantity`여야 합니다.
3. **창고 입고를 매장 입고로 착각하는 것.** 창고에 넣고 "왜 안 팔리지"가 반복됩니다 — 실제로는 팔리긴 하지만 재고 위치가 틀립니다. 다이얼로그에서 창고 선택 시 명시 고지 + 배분 화면 연결이 필요합니다.
4. **"Phase 67이 다 막아줬겠지"라고 가정하는 것.** 입고 경로의 핵심 3개 모델(`ProductBranch`·`Stocks`·`Prices`)은 `store_id` 컬럼이 없어 **L2 훅이 조용히 skip**합니다. 제외 목록에 넣어서가 아니라 컬럼이 없어서 빠진 것이라, 부팅 로그에서도 `skipped` 카운터에 묻혀 보이지 않습니다. 새 엔드포인트를 추가할 때마다 "이 모델이 guarded인가"를 직접 확인해야 합니다.

## 7. 점검 포인트

- **1주** — Wave A 배포 후 `stockedQuantity > qcOk`인 로트 0건, `availableQuantity < 0` 0건 확인
- **1개월** — 입고까지 걸린 리드타임(마지막 수령 → 입고 확정) 중앙값, 프리플라이트 차단 건수 대비 우회 건수
- **3개월** — 가격 0원 판매 건수 0 유지 여부, 창고 잔류 재고 비율

---

## 8. 열어둔 결정

1. `qcOkQuantity`를 **컬럼으로 저장**할지 **매번 파생 계산**할지. 저장하면 빠르지만 D4·D6 같은 우회 경로가 남아 있으면 드리프트합니다. 우선 파생 권장.
2. MES 트랙(`mes_work_orders`)도 같은 게이트에 얹을지. 지금은 `mes_work_orders`에 `branch_id`가 없어 다지점 매장은 생산 완료가 **항상 400**입니다 — 별도 Wave가 필요합니다.
3. Zebra 라벨 자동 출력을 입고 확정에 붙일지(커밋 후 dispatch, 실패 비치명적).
