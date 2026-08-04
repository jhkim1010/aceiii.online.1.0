---
phase: 70-stock-cache-retirement-and-backlog-cleanup
plan: 03b (단일 프로세스 계획 S4)
status: complete
date: 2026-08-04
requirements: [R3]
---

# 70-03 후속 — 상품 삭제 백엔드 하드닝 + 마드레 SKU 소급 갱신

출처: `.team/tasks/009-70-03-fk/task.md` (70-03 검수에서 백엔드 변경이 필요해 미착수로 남긴 4건).

커밋: api-ventago `a1c0fbd` / ventago-app `c3d4995` / 루트 `5ea5520`.

---

## 사용자 결정 (2026-08-04)

| 항목 | 결정 |
|---|---|
| 마드레 삭제 시 자식 처리 | **자식 있으면 거부** (일괄 삭제 아님) |
| 마드레 SKU 변경 시 자식 SKU | **소급 갱신한다** |

---

## 1. FK 거부 메시지 스페인어화

종전에는 `SequelizeForeignKeyConstraintError` 가 그대로 올라가 사용자에게
`insert or update on table ...` 같은 PG 영문 원문이 보였다.

`ProductsService.deleteChecked()` 신설 — 사전 영향 점검으로 막고, 그래도 새어 나오는 FK 위반은
`ConflictException`(409) + 스페인어로 감싼다. 컨트롤러 `DELETE /products/:id` 가 이걸 호출한다.

## 2. 마드레 삭제 시 자식 고아화 차단

`products.parent_id` 는 **ON DELETE SET NULL** 이라 삭제 자체는 성공하고, 자식이 마드레 없는
고아가 되어 목록에서 사라졌다. 프론트는 경고만 하고 막지 않았다.
→ 자식 변형이 1개라도 있으면 **거부**한다.

## 3. 마드레 SKU 소급 갱신 — `cascadeChildSkus()`

변형 SKU 는 `<부모SKU><접미>` 로 조립된다(`productStock.service` 주석: "부모-변형 SKU 정합 보장").
로컬 실측에서도 자식 SKU 는 **100% 부모 SKU 접두**였다. 부모만 바꾸면 같은 마드레 안에
두 세대 접두가 섞였다.

- 접두만 교체하고 접미(색/사이즈 조합분)는 보존
- **부모 SKU 로 시작하지 않는 자식(수동 SKU)은 건드리지 않는다** — 규칙을 추정해 바꾸면
  이미 인쇄된 라벨과 더 크게 어긋난다. 건너뛴 건 warn 로그로 남긴다
- 부모 수정 + 자식 소급 갱신을 **한 트랜잭션**으로 묶었다(부분 적용 금지)

> ⚠️ SKU 는 바코드 라벨에 인쇄된다. 소급 갱신 후 **기존 라벨은 DB 와 달라지므로 재출력이 필요**하다.
> 목록 정합을 우선한다는 결정에 따른 알려진 트레이드오프다.

## 4. 보류 판매 참조 — `GET /products/:id/delete-impact` 신설

`venta_suspendida_items.product_id` 는 SET NULL 이라 삭제는 되지만 그 보류 판매의 상품 참조가
끊긴다. 목록 API 응답에 그 정보가 없어 프론트 단독으로는 판정할 수 없었다.

새 엔드포인트가 **blockers / warnings** 를 나눠 돌려준다 (FK `delete_rule` 실측 기반):

| 구분 | 항목 | FK 규칙 |
|---|---|---|
| blocker | 자식 변형 | `products.parent_id` SET NULL → **정책상** 거부 |
| blocker | 판매 이력 `sale_items` | NO ACTION |
| blocker | 재고 원장 `stocks` (ProductBranch 경유) | NO ACTION — ProductBranch CASCADE 를 막는다 |
| blocker | `product_discounts` / `mes_bom` / `mes_work_orders` / `talleres_lotes` | NO ACTION |
| warning | `venta_suspendida_items` | SET NULL |
| warning | `mes_bom_items.sub_product_id` | SET NULL |

**프론트 연동**: `ProductParentList` 삭제 대화상자가 이 결과를 렌더하고 blockers 가 있으면
Eliminar 버튼을 비활성화한다. 추측하던 로컬 `useMemo(deleteInfo)` 는 제거했다(서버가 권위).
서버도 409 로 이중 차단한다.

---

## 검증

| 항목 | 결과 |
|---|---|
| `tsc -p tsconfig.build.json` | 0 |
| `nest build` | 0 |
| `npm run build` (프론트) | 0 |
| `eslint ProductParentList.tsx` | 0 problems |
| jest `src/app/products` | **실패 20 = baseline 동일**, 통과 93 → **96** (신규 3건 추가) |

### 도중에 실제로 깨뜨렸다가 고친 것 (기록)

첫 실행에서 baseline 대비 **신규 실패 3건**이 났다. 전부 테스트 쪽 정합 문제였고 원인은 두 가지:

1. `products.controller.spec` 의 서비스 목이 새 메서드를 몰랐다 —
   `TypeError: this.productsService.deleteChecked is not a function` (1 suite)
2. `products.service.spec` 의 `productModel` 목에 `sequelize` 가 없어
   트랜잭션 래핑이 터졌다 — `Cannot read properties of undefined (reading 'transaction')` (2 tests).
   `update()` 호출 단언도 두 번째 인자(transaction)를 기대하도록 갱신했다.

목만 맞추고 끝내지 않고 **신규 동작 3건에 테스트를 추가**했다: deleteChecked 409 전파 /
delete-impact 스코프 전달 / SKU 소급 갱신(수동 SKU 는 미변경까지 단언).

---

## 남은 것

- 브라우저 UAT: 자식 있는 마드레 삭제 시도 → 스페인어 차단 메시지 / 마드레 SKU 변경 후
  자식 목록 코드가 같이 바뀌는지 (**S5 70-07 에서 확인**)
- SKU 소급 갱신 후 **바코드 라벨 재출력 안내**를 UI 에 노출할지 — 현재는 문서에만 있다
