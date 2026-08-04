---
phase: 70-stock-cache-retirement-and-backlog-cleanup
plan: 01b (단일 프로세스 계획 S2)
status: complete
date: 2026-08-04
requirements: [R1]
---

# 70-01b — 잔여 `products.stock` 읽기 경로 5곳 이관

70-01 이 남긴 범위 밖 읽기 경로를 전부 원장(`stock_balances` / 뷰)으로 옮겼다.
**70-06(트리거 폐기)의 하드 게이트**였고, 팀 실행에서 4번(010→013→015→016) 배정돼 4번 다
산출물 0 이었던 작업이다.

배포: api-ventago `aa93aae` → 루트 `2f2c2b0`. Jenkins `api-new-coolsistema` **#600 SUCCESS**,
`api_ventago` 컨테이너 13:59:26 재생성(healthy).

---

## 이관 원리 — 종전 캐시의 의미를 그대로 재현

폐기 예정 트리거 `trg_stocks_sync_product_cache` 는 원장 행이 들어올 때
**변형 행과 부모(마드레) 행 양쪽**에 같은 증분을 더했다. 따라서 `products.stock` 의 의미는
상품 종류에 따라 달랐다.

| 상품 | 종전 `products.stock` 의 의미 |
|---|---|
| 변형(hijito) | 그 변형의 전 지점 합 |
| 마드레(parent) | 자기 자신 + 모든 변형의 전 지점 합 |

새 헬퍼 `src/app/products/stock-availability.util.ts` 가 이 둘을 한 식으로 재현한다:

```sql
SUM(sb.available) WHERE sb.store_id = p.store_id
                    AND (sb.product_id = p.id OR sb.parent_id = p.id)
```

**등가성 실측**: 로컬 483개 상품 전수 대조 → 불일치 **0**.
운영에서도 마드레 70건 대조 → 불일치 **0**.

---

## 파일별 변경

| 파일 | 변경 | 비고 |
|---|---|---|
| `products/stock-availability.util.ts` | **신설** — `getAvailableByProduct(sequelize, ids, transaction?)` | 전 지점 합 전용. 지점별이 필요한 경로는 `stock_balances` 를 `branch_id` 로 직접 읽어야 한다(70-01 이 그렇게 함) |
| `revendedor/products/…service.ts` | 목록·상세의 `inStock` 판정을 원장으로 | `attributes` 에서 `'stock'` 제거. **페이지당 1쿼리**(N+1 아님) |
| `revendedor/purchase/…service.ts` | 재고 가드 출처 이관 | 트랜잭션 내 조회. `trg_stock_balances_apply` 가 원장 INSERT 와 같은 트랜잭션에서 스냅샷을 갱신하므로 같은 트랜잭션에서 읽어도 최신값 |
| `code-import/code-import.service.ts` | 보정 기준선을 **대상 지점 잔량**으로 | 아래 「동반 수정」 |
| `shop-public/shop-catalog.service.ts` | raw SQL 3곳을 `v_stock_total_madre` 조인으로 | 목록 / bestseller / 상세. 필터 `COALESCE(p.stock,0)>0` → `COALESCE(m.available,0)>0` |
| `sales/sales.service.ts` | 응답 `attributes` 의 `'stock'` 4곳 제거 | 아래 「선행 확인 1」 |
| `migrations/2026-08-04-grant-stock-view-shop-readonly.sql` | **신설** GRANT | 아래 「마이그레이션」 |

### 동반 수정 — code-import 기준선 (계획에 없던 정정)

종전: `currentStock = stockAfterImport.get(id) ?? Number(found.stock ?? 0)` — **전 지점 합**.
그런데 보정 행(`writeStockAdjustment`)은 `defaultBranchId` **한 지점**에만 쓰였다.
다지점 매장에서는 다른 지점 재고까지 얹힌 값을 빼서 delta 가 어긋났다.
→ `readBranchAvailable(productId, defaultBranchId)` 로 정정. **단일 지점 매장에서는 두 값이 같아 변화 없음.**

---

## 선행 확인 (코드 수정 전에 답을 낸 2건)

### 1. `sales.service` 의 `'stock'` 을 누가 쓰는가 → **소비처 0**

- `ventago-app`: `product.stock` 참조 0건 (`stockByVariant` 는 다른 필드), 판매 화면에도 없음
- `mobile-sales-app`: `stock_dto.dart` 는 상품 변형 매트릭스 엔드포인트용 (판매 조회 응답 아님)
- `tienda-admin-app` / `ventago-admin-app`: 참조 0건

→ 이관 대상이 아니라 **응답에서 제거**가 맞다. 판매 조회 4곳의 `attributes` 에서 뺐다.

### 2. revendedor 구매 가드와 `allowSaleWithoutStock` → **동작 변경하지 않음 (사용자 결정)**

이 가드는 매장 설정과 무관하게 재고 부족을 차단한다. CLAUDE.md 쓰기경로 규약
("차단은 `allowSaleWithoutStock=false` 매장에만")과 어긋나 보이지만,

- S2 의 범위는 **읽기 경로 이관**이고, 동작 변경은 별건이다
- 재판매자 구매는 **보류판매(suspendido) 생성**일 뿐 실제 차감은 매장이 확정할 때 일어난다

→ 출처만 바꾸고 판정식은 그대로 뒀다(`available < quantity` 면 차단). 설정 존중으로 바꿀지는
**후속 과제로 남긴다**(2026-08-04 사용자 결정: 지금은 그대로).

---

## 마이그레이션 — `2026-08-04-grant-stock-view-shop-readonly.sql`

공개몰은 전용 롤로 접속하는 raw SQL 경로라 뷰 SELECT 권한이 별도로 필요하다.
롤 존재 여부를 확인하는 DO 블록이라 양쪽 환경에서 안전하다.

| 환경 | 결과 |
|---|---|
| 로컬 5432 | `shop_readonly` 롤 존재 → **GRANT 적용됨**. `has_table_privilege = true` 확인 |
| 운영 5434 | `shop_readonly` 롤 **없음** → DO 블록 skip (no-op). 실제 접속은 `SHOP_DB_USER=coolsistema` 이고 뷰 소유자가 coolsistema 라 이미 SELECT 가능 |

뷰는 `security_invoker` 가 아니어서 정의자 권한으로 실행된다 → 하위 테이블 GRANT 불필요.

---

## 검증

| 항목 | 결과 |
|---|---|
| `tsc --noEmit -p tsconfig.build.json` | exit 0 |
| `nest build` | exit 0 |
| jest (shop-public / revendedor / code-import / sales) | **135 tests 통과**, 실패 스위트 1 = `sales.controller` (baseline pre-existing TS2554, 신규 아님) |
| 등가성 (로컬) | 상품 483건 대조 불일치 0 / 공개몰 마드레 4건 불일치 0 |
| 등가성 (운영) | 마드레 70건 대조 불일치 0 |
| 불변식 로컬 5432 | `v_stock_balance_drift` 0 / `v_stock_tenant_leak` 0 |
| 불변식 운영 5434 | `v_stock_balance_drift` 0 / `v_stock_tenant_leak` 0 |
| 운영 스모크 | `GET /api/public/shop/6/products` → **HTTP 200**, `stock` 값이 뷰와 일치(id140=76, id264=140) |
| 컨테이너 로그 | permission denied·에러 없음, healthy |

### 게이트 grep (70-06 선행 조건)

```bash
grep -rn "product\.stock\|products\.stock\|p\.stock" api-ventago/src/ | grep -v spec | grep -v diagnostics
```
남은 것은 **주석·로그 문자열뿐**이고 실코드 읽기는 **0**:
- `online-orders.service.ts:963` — 로그 메시지 문자열
- `legacy-import.service.ts:578` — CSV 필드 매핑(`fmap.stock`), `products.stock` 아님

**→ 70-06 (S3) 진행 가능.**

---

## 남은 것

- revendedor 구매 가드의 `allowSaleWithoutStock` 존중 여부 (동작 변경, 별도 검증 필요)
- 운영 `ShopReadonlyDb` 가 메인 DB 인스턴스로 폴백 중이라는 경고 — 이번 변경과 무관한 기존 사항
  (`SHOP_DB_HOST` 미도달). 공개 트래픽이 POS 커넥션을 잠식할 수 있어 별도 과제
