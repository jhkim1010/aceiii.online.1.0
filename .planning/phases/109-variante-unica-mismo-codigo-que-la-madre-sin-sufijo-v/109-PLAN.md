# Phase 109 — Variante única = mismo código que la madre (sin sufijo `-V`)

## 요청 (2026-10-14 사용자)
> 「Color único, taller unico의 경우 부모 코디고와 자식 코디고가 일치해야 해」
> 「절대 맘대로 추가하지 않도록」

발단: Cielo(22)가 등록한 상품의 자식 코드가 `25942379103-V` 로 바뀌어 보였다.

## 현재 — 왜 `-V` 가 붙는가
- DB 인덱스 `uq_products_sku_store` = `UNIQUE(sku, store_id)` — 한 매장에서 같은 코드 2행 불가.
- Color Único + Talle Única 자식은 번호를 안 붙이면 부모와 코드가 같아진다 → 2026-04-20(e6ddb120)부터
  `parent.sku + '-V'` 로 피해 왔다 (`productStock.service.ts:907-911`, `variante-unica.ts:29`).
- 운영 실측: **273행** — Cielo 203 · NOIX 19 · ACE 16 · store 11: 14 · coolsistema 13 · 17: 5 · 10: 2 · 30: 1.
- 「sin color y talle」 지점(`branches.vende_sin_variantes`) 기능이 `-V` 를 식별자로 쓴다 — 운영에서 켠 지점 **0개**.

## 영향 조사 (코드 전수, 2026-10-14)
부모와 자식이 같은 코드를 가지면 **「코드로 상품 찾기」 가 2행을 돌려준다.** 순서 없는 조회는 아무 쪽이나 고른다.

### 깨지는 곳 (14)
| # | 위치 | 깨짐 |
|---|---|---|
| 1 | `migrations/2026-10-03-sucursal-sin-variantes.sql:44` 트리거 | `sku = madre||'-V'` 만 허용 → 재고 입력 예외 |
| 2 | `variante-unica.ts:182-204, 307-314` | Map 이 부모/자식 아무거나 → `conflicto` → 판매·재고 400 (호출 7곳) |
| 3 | `productStock.service.ts:287-319` 마드레 전환 | `findOne({sku})` 가 부모를 잡으면 「Ya existe…」 |
| 4 | `productStock.service.ts:907-911` | `-V` 생성기 자체 |
| 5 | `productStock.service.ts:2246, 2293` POS 카탈로그 | 기본 자식을 `-V` 로 알아봄 → 매트릭스에 「Color Único/Talle Única」 칸이 보임 |
| 6 | `branch-sin-variantes.service.ts:92,119,144,200` | 기본 자식을 일반 변형으로 보고 `-V` 를 새로 만든다 |
| 7 | `import/import.service.ts:181-188` | 부모를 찾고 자식 생성을 건너뜀 |
| 8 | `code-import.service.ts:637-647, 729-852` CodigoHijitos | **부모를 자기 자신의 자식으로 갱신**(parentId=자기) |
| 9 | `code-import.service.ts:417-497` CodigoMadres | 부모 이름·가격이 자식에 써짐 |
| 10 | `legacy-import/streaming/ace-sales.sql.ts:738` | **판매 줄이 2배로 INSERT** |
| 11 | `legacy-import/streaming/sales.mapper.ts:648` | 미리보기 수치 부풀림 |
| 12 | `legacy-import/streaming/ace-ingresos.sql.ts:114` | 입고가 부모를 가리킴 |
| 13 | `mobile-catalog.service.ts:220-250` 스캔 | 항상 `SCAN_AMBIGUOUS` 409 |
| 14 | `work-order.service.ts:163-166` 생산 | 부모에 재고 소비 → 트리거 예외 |

### 모호 (결과는 맞지만 우연) — 같이 고정
`products.service.ts:219` 중복검사 · `cascadeChildSkus:813` · WP `sku-matcher:73` · `wp-webhook:713` ·
**WP `pushVariable:726`(부모·자식 같은 SKU 로 보내 WooCommerce 가 거부할 가능성)** · `photo-library-rules:87` ·
POS 스캐너 `codigo-escaneado.ts:58-87` · `catalogo-pos.ts:154` · `sku-escaneado.ts:13` · `store-restore-catalog.ts:94`.

### 시험 (`-V` 를 단언) — 고쳐 써야 함
`productStock.service.spec.ts:548` · `test/family/transfer-default-variant.family-spec.ts` · `branch-sin-variantes.itest.ts:127` 외 픽스처 4.

**규칙(전체 적용):** 코드로 찾는 모든 곳에 결정적 우선순위 — 재고·판매·스캔은 **자식(`parent_id IS NOT NULL`)**, 카탈로그 편집은 **부모(`isParent`)**.

## DB 설계 (권고)
`UNIQUE(sku, store_id)` 를 다음으로 바꾼다:
```sql
-- 부모·단독 상품끼리 중복 금지
CREATE UNIQUE INDEX CONCURRENTLY uq_products_sku_store_raiz ON products (store_id, sku) WHERE parent_id IS NULL;
-- 자식끼리 중복 금지
CREATE UNIQUE INDEX CONCURRENTLY uq_products_sku_store_hijo ON products (store_id, sku) WHERE parent_id IS NOT NULL;
```
+ 트리거(자식 INSERT/UPDATE): **자식 코드가 다른 부모·단독 상품의 코드와 같으면, 그것은 자기 부모여야 한다**
(부모 행을 `FOR KEY SHARE` 로 잠그고 확인). → 남의 마드레 코드를 자식이 가로채는 것을 DB 가 막는다.
- CODEX 는 복합 FK `(parent_id, store_id, sku) → (id, store_id, sku)` 를 권했지만, 이것은 **모든** 자식에게
  부모 코드를 강제한다(사이즈·색상 번호가 붙는 일반 자식이 못 들어감) → 쓰지 않는다.
- 순서: ① 새 인덱스 2개 CONCURRENTLY ② 트리거 ③ 옛 인덱스 DROP — 옛 인덱스가 살아 있는 동안은 지금과 같다(무중단).
- 코드 조회 정렬 수정이 **먼저 배포**돼야 한다. 인덱스를 먼저 풀고 같은 코드 2행이 생기면 위 14곳이 그때부터 깨진다.

## 결정 필요
- **D1. 기존 273행 `-V` 를 부모 코드로 바꿀까?** (권고: 바꾼다)
  ⚠ 매장에 이미 붙어 있는 `…-V` 바코드 라벨이 있다. 바꾸면 그 라벨이 안 읽힌다 →
  **스캐너가 끝의 `-V` 를 떼고 찾게** 한동안 유지(권고). 운영 DML(273행)은 SQL·행 수를 보여드리고 승인 후.
- **D2. WooCommerce:** Color/Talle único 마드레는 **단순 상품(simple)** 으로 보낸다(권고) — 변형 1개짜리 가변 상품을 부모와 같은 SKU 로 보내면 WC 가 거부할 수 있다. Cielo 는 WC 연동 중이므로 배포 전 실측.
- **D3. 「sin color y talle」 지점 기능(켠 곳 0개):** `-V` 대신 「Color Único+Talle Única 자식」 으로 식별하도록 함께 옮긴다(권고). 또는 기능 자체를 내린다.

## 웨이브
1. **W1 (코드, 배포 1):** 코드 조회 14+10곳에 결정적 우선순위(같은 코드 2행이 와도 맞는 쪽을 고름) ·
   `-V` 를 식별자로 쓰던 곳을 「Color Único+Talle Única 자식」 판정으로 · 스캐너 `-V` 별칭 · 시험 갱신 + 돌연변이.
   이 단계에선 아직 `-V` 가 만들어진다(옛 인덱스가 같은 코드를 막으므로) — 동작 변화 없음.
2. **W2 (DB, 승인 후):** 인덱스 2개 + 트리거 → 옛 인덱스 DROP (로컬 5432 + 운영 5434).
3. **W3 (코드, 배포 2):** 생성기가 **부모 코드 그대로** 만든다. 충돌하면 **저장을 막고 알린다**(접미사로 피하지 않는다).
4. **W4 (데이터, 승인 후):** 273행 `-V` → 부모 코드. 매장별로 쪼개서, WC 연동 매장(Cielo)은 동기화 확인 후.

## 규모 · 위험
- 규모 **L** (api 20여 곳 · app 3곳 · DB · 데이터 · WC).
- 위험 최고점: 레거시 임포트 판매 줄 2배(#10), CodigoHijitos 가 부모를 자기 자식으로 바꿈(#8) — W1 이 배포되기 전에 W2(인덱스 완화)를 하면 안 된다.
