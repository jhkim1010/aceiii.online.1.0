# Phase 69 — Deferred Items (범위 밖 발견 사항)

실행자가 작업 범위 밖에서 발견했지만 수정하지 않은 항목. Scope Boundary 규칙에 따라 로그만 남기고 손대지 않음.

---

## 69-03 (2026-07-31)

### `api-ventago/src/app/products/productStock.service.spec.ts` — `createVariantsBatch` 기존 스펙 14건 실패 (pre-existing)

- **발견 위치:** `npx jest src/app/products/productStock.service.spec.ts` 전체 실행 시
- **증상:** `describe('ProductStockService — createVariantsBatch', ...)` 아래 "다중 지점(Branch) stock 생성", "SKU 생성 로직" 등 14개 `it` 이 실패 (`mockProductBranchFindOne`/`mockProductBranchCreate` 호출 0회 — 코드 주석상 `findOrCreate` 로 리팩터됐는데 테스트가 구 `findOne`/`create` 호출을 기대하는 드리프트로 추정).
- **69-03 변경과의 관계:** 무관. `git stash` 로 69-03 변경분을 제외한 baseline 에서도 동일하게 14 failed / 6 passed 로 재현됨(테스트명·실패 지점 diff 동일).
- **조치:** 수정하지 않음(Scope Boundary — `correctTodayStocks` 이외 메서드).
- **69-03 검증 결과:** 신규 6개 `correctTodayStocks` 테스트는 전부 통과, 기존 14개 실패는 그대로(회귀 아님).

### `api-ventago/src/app/products/products.service.spec.ts` — 5건 실패 (pre-existing)

- **발견 위치:** `npx jest src/app/products` 전체 실행 시
- **증상:** `products.service.ts` `create()`/`updateProductsStatus()` 관련 5개 테스트 실패(`ConflictException: Product already exists` 등 mock 데이터 드리프트로 추정).
- **69-03 변경과의 관계:** 무관. 69-03 은 `products.service.ts` 를 전혀 수정하지 않음.
- **조치:** 수정하지 않음.
