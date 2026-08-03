---
phase: 70-stock-cache-retirement-and-backlog-cleanup
plan: 03
subsystem: front
tags: [react, products, sku, delete, permissions, trello]

# Dependency graph
requires: []
provides:
  - "Códigos madres 목록에서 상품 삭제 (확인 대화상자 + 재고 이력/고아화 경고)"
  - "기존 상품의 SKU(código) 수정 저장"
  - "권한별 노출: eliminar-un-producto / editar-un-producto"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "권한이 없으면 액션을 숨기지 말고 칼럼 자체를 만들지 않는다 (조립 함수 + optional 콜백)"
    - "쓰기가 여러 번 나가는 핸들러는 모든 검증을 첫 쓰기보다 앞에 둔다 — 부분 쓰기 방지"
    - "엔드포인트 분할로 부분 쓰기가 불가피하면, 실패 문구에 '무엇은 이미 저장됐다'를 명시한다"

key-files:
  created: []
  modified:
    - ventago-app/src/views/products/list/components/DataConfig.tsx
    - ventago-app/src/views/products/list/components/ProductParentList.tsx
    - ventago-app/src/views/products/list/components/BasicDataCard.tsx
    - ventago-app/src/views/products/list/ProductsView.tsx
---

# 70-03 — 상품 코드 수정·삭제 UI (Trello fXUDii66)

## 문제

신고: *"no hay ninguna opcion cuando se quiere o modificar un codigo o eliminarlo"*.

**버그가 아니라 미구현이었다.** 백엔드는 처음부터 있었다 —
`products.controller.ts` 의 `PUT /products/:id`(권한 `editar-un-producto`)와
`DELETE /products/:id`(권한 `eliminar-un-producto`).
그런데 프론트 전체에 `apiConnector.remove('/products/...')` 호출이 **하나도 없었고**,
`COLUMNS_PARENT` 는 sku/name/basePrice 3칼럼뿐이라 액션 칼럼 자체가 없었다.

이번 작업은 **이미 있는 백엔드에 UI 를 연결한 것**이다. 새 엔드포인트를 만들지 않았고,
백엔드 코드는 **한 줄도 바뀌지 않았다**.

## 무엇을 했나

### 삭제 (T1·T2)

같은 화면 `columnsMadre` 의 기존 `actionCol` 패턴(폭 44, `tabler:trash` 15px,
`opacity .55 → hover #E53935`, `e.stopPropagation()`)을 **그대로 복제**했다. 새 패턴을 발명하지 않았다.

`DataConfig.tsx` 에 `parentDeleteCol()` + `buildParentColumns({ onToggleWeb, onDeleteRow })` 를 추가했다.
기존 `COLUMNS_PARENT` / `columnsParentWithWeb` 는 그대로 두고 조립 함수를 씌운 형태 —
권한·공개몰 여부에 따라 칼럼을 붙였다 뗐다 해야 해서 factory 가 필요했다.

`ProductParentList.tsx` 는 삭제 아이콘 → 확인 대화상자 → `apiConnector.remove('/products/'+id)` →
`getProducts()` 재조회. **권한이 없으면 `onDeleteRow` 자체를 넘기지 않아 칼럼이 생성되지 않는다**
(CSS 로 숨기는 게 아니라 미렌더).

### SKU 수정 (T3)

종전에는 `auto` 체크박스를 해제하는 순간 `sku: ""` 로 값을 지워버려서 **"기존 코드를 고친다"가 구조적으로 불가능**했다.
`BasicDataCard.tsx` 에서 그 비우기를 **신규 등록(`!product.id`)에만** 적용하도록 바꿨다.
SKU 입력과 `auto` 토글은 `editar-un-producto` 권한이 없으면 읽기 전용.

저장 버튼이 `ProductsView.tsx` 에 있어 이 파일도 불가피하게 수정했다
(plan 의 `files_modified` 3개보다 1개 많다 — 아래 「plan 과의 차이」 참조).
`loadedSkuRef` 스냅샷으로 SKU 변경을 감지해 확인 대화상자에 `Código (SKU)` 섹션을 띄우고
`PUT /products/:id { sku }` 를 보낸다.

**저장 경로가 두 군데인 이유**: madre 를 클릭하면 `todayHasEntries` 로 mode 가 갈린다.

- `mode === 'edit'` → `handleEdit` → 확인 → `doEdit`. 여기에 SKU diff 를 추가했다.
  종전 `doEdit` 는 지점 미선택이면 무조건 막았는데, **SKU 만 바꾼 경우엔 지점이 필요 없으므로**
  재고·가격 변경이 있을 때만 지점을 검사하도록 분기했다.
- `mode === 'add'`(부모 선택 + 오늘 입고 없음) → `doSubmit` 의 재입고 분기.
  이 경로의 `variants/batch` 는 화면의 SKU 를 **서버가 무시**한다(서버가 `parent.sku` 를 접두로 강제).
  그래서 SKU 가 바뀌었으면 batch **이전에** 부모를 먼저 `PUT` 한다 — 순서가 반대면 옛 코드로 변형이 생성된다.

SKU 중복은 `products(sku, store_id)` 유니크 제약이 거부하고,
`api.service.ts` 인터셉터가 서버 메시지를 그대로 재발행하므로 그 문자열이 토스트에 노출된다.

## 삭제가 실제로 무엇인지 — 확인하고 문구를 맞췄다

plan 이 "하드 삭제인지 status 변경인지 먼저 확인하라"고 했고, 확인 결과 **하드 삭제**다.
`Product` 모델에 `paranoid` 없음, `deleted_at` 컬럼 없음, `CrudService.delete()` → `record.destroy()`.
유일한 사전 차단은 `isGeneric` 상품.

로컬 PG18 `pg_constraint` **읽기 전용** 조회로 `products.id` 참조 FK 의 삭제 규칙을 확인했다(추측 아님):

| 참조 | ON DELETE | 결과 |
|---|---|---|
| `ProductBranch.product_id` | CASCADE | 함께 삭제 시도 |
| `stocks.product_branch_id → ProductBranch` | **NO ACTION** | 원장 행이 있으면 위 CASCADE 가 막혀 **DB 가 삭제를 거부** |
| `sale_items.product_id` | NO ACTION | 판매 이력이 있으면 거부 |
| `products.parent_id` | **SET NULL** | madre 를 지우면 자식(codigo hijito)이 **부모를 잃는다** |
| `venta_suspendida_items.product_id`, `mes_bom_items.sub_product_id` | SET NULL | 참조 끊김 |
| `prices`, `product_subcategories`, `qr_print_log`, `product_sync`, `wp_product_sync`, `product_promotions`, `style_cost_sheets` | CASCADE | 함께 삭제 |

**원장은 FK 가 지켜준다.** 코드로 `stocks` 를 건드리지 않았고 건드릴 수도 없다
(`trg_stocks_immutable` 이 UPDATE/DELETE 를 차단).
다만 **madre 자체엔 보통 원장 행이 없어 삭제가 성공**하고, 그 순간 자식이 고아가 된다.
이건 사용자가 알아야 하는 실제 결과라 대화상자에 명시했다.

대화상자(스페인어):
- `¿Eliminar el código madre?` + 상품명·SKU 박스
- `El producto se borra de forma permanente. Esta acción no se puede deshacer.` ← 하드 삭제
- 변형이 있으면 warning: 자식이 código madre 를 잃는다 ← `parent_id` SET NULL
- 재고 이력이 있으면 error 톤: 원장은 solo-agregar 라 이력은 남고, 움직임·판매가 있으면 시스템이 삭제를 거부할 수 있다

## 재고 이력 경고를 무엇으로 판단했나

plan 은 `stock_balances.movimientos > 0` 을 언급하지만 이 화면의 목록 API 에는 그 필드가 없고
**새 엔드포인트 생성이 금지**돼 있어 기존 응답만으로 판정했다.

`GET /products/by-parent?parent=false` 는 각 madre 행에 `stockByVariant[]` 를 주고,
그 집계 쿼리가 `FROM "ProductBranch" pb JOIN stocks s ON s.product_branch_id = pb.id` 다.
**JOIN 이므로 원장 행이 없으면 키 자체가 없다** → 키가 있으면 movimiento 가 있다는 뜻이고,
잔액이 0(다 팔림)이어도 키는 남는다.

```ts
Object.keys(v?.stockByBranch ?? {}).length > 0 || Number(v?.stock ?? 0) !== 0
```

`> 0` 이 아니라 `!== 0` 인 이유: `allowSaleWithoutStock=true` 매장의 **음수 재고도 이력으로 잡아야** 한다.
추가 요청 왕복 0건.

## T4 — 백엔드는 확인만 했고, 고칠 게 없었다

`PUT`/`DELETE /products/:id` 둘 다 이미 `storeId` 를 강제하고 있었다:

```ts
private getScope(user: Users) {
  const isSuperAdmin = isSuperAdminUser(user);
  return { isSuperAdmin, storeId: isSuperAdmin ? undefined : (user?.storeId ?? undefined) };
}
```

`storeId` 는 `@GetUser()` 로 얻은 **인증 주체에서만** 도출되고 요청 바디/쿼리에서 오지 않는다.
서비스 내부에서 `product.storeId !== storeId` 면 `ForbiddenException`.
→ **`api-ventago` 변경 0건.**

## 검수에서 잡힌 것 (커밋 전 수정 완료)

### major — `doEdit` 부분 쓰기

1차 구현은 SKU `PUT` 을 **지점 검증보다 먼저** 실행했다.
지점 미선택 + (SKU 변경 && 재고·가격 변경) 조합이면 SKU 는 실제로 저장됐는데
사용자에게는 `Debe seleccionar al menos una sucursal` 실패 토스트가 뜨고,
그 return 경로가 상태를 정리하지 않아 다음 저장 때 같은 SKU 를 또 PUT 했다.

**검증 → 쓰기** 순서로 뒤집었다. 지점 미선택이면 어떤 요청도 나가지 않는다.
조건은 `hasStockOrPriceChange && branchIds.length === 0` 이라 "SKU 만 변경" 은 여전히 지점 없이 저장된다.

### minor — 부분 쓰기가 불가피한 자리의 안내

`doSubmit` 재입고 분기와 `doEdit` 는 둘 다 쓰기가 두 번 나간다.
`doSubmit` 은 서버의 접두 강제 때문에 SKU PUT 이 먼저여야 하고, `doEdit` 도 엔드포인트가 둘로 나뉜다.
순서를 바꿀 수 없으므로 **실패 문구에 사실을 명시**했다 —
`skuAlreadyUpdated` 플래그를 `try` 밖에 두고 SKU PUT 이 성공한 뒤에만 세워,
catch 에서 `El código (SKU) ya fue actualizado.` 를 덧붙인다.

## plan 과의 차이

| | plan | 실제 |
|---|---|---|
| `DataConfig.tsx` | 수정 | 수정 |
| `ProductParentList.tsx` | 수정 | 수정 |
| `products.controller.ts` | 수정 | **미수정** — T4 확인 결과 `storeId` 가 이미 강제됨 |
| `BasicDataCard.tsx` | — | **추가 수정** — SKU 입력·권한 게이트가 여기 있음 |
| `ProductsView.tsx` | — | **추가 수정** — 저장 버튼과 `doEdit`/`doSubmit` 이 여기 있음 |

프론트 4파일 +261/-31, 백엔드 0파일.

## 검증

```
eslint (4파일)  0 errors, 3 warnings   exit=0
npx tsc --noEmit                        exit=0
npm run build (Next.js production)      exit=0
```

warning 3건은 `react-hooks/exhaustive-deps` 이고 **전부 diff 밖의 기존 코드**
(`ProductsView.tsx:317`, `BasicDataCard.tsx:180`, `:342`). 이번 변경이 만든 warning 0건.

jest 는 돌리지 않았다 — 변경 4파일을 import 하는 스위트가 0건이고
(유일한 문자열 매치 `src/__tests__/variant-color-size-matrix.spec.ts:42` 는 주석 언급),
Phase 70 baseline 의 기존 실패 15 suites / 33 tests 는 전부 백엔드 쪽이다.

DB 접근은 로컬 PG18(5432) `pg_constraint` / `pg_trigger` **SELECT 전용**. DDL/DML 0건. 운영 미접속.

## 남은 것

**T009 로 등록** — 백엔드 변경이 필요해 이번 plan 범위 밖:

1. FK 거부 시 PG 영문 원문이 노출된다 (`SequelizeForeignKeyConstraintError` → 스페인어 매핑 필요)
2. madre 삭제 시 자식이 고아가 된다 — 경고만 하고 차단하지 않음. 거부할지 일괄 삭제할지 제품 결정 필요
3. SKU 변경이 자식 SKU 를 소급 갱신하지 않는다 — 의도인지 확인 필요
4. `venta_suspendida_items.product_id` SET NULL — 보류 판매 참조가 끊긴다. 경고하려면 백엔드 지원 필요

**브라우저 UAT 미실행**:
- 권한 없는 계정에서 삭제 아이콘이 실제로 안 보이는가
- 중복 SKU 저장 시 서버 메시지가 그대로 뜨는가
- **지점 미선택 + SKU 만 변경** 저장이 성공하는가 (이번 major 수정의 핵심 분기)
- 삭제 후 목록이 갱신되는가

**재고 이력 경고의 false negative**: `stockByVariant` 에 안 잡힌 variant 의 원장은 경고에 반영되지 않는다.
다만 그 경우에도 삭제 자체는 `stocks.product_branch_id` NO ACTION 이 막으므로 데이터는 안전하다.
