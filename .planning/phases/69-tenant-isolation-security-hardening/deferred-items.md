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

---

## 69-07 (2026-08-01)

### 파생 스코프 미등록 모델 6개 — 엔진 보강 필요 (사용자 결정: Phase 69 범위 밖으로 defer)

69-06 감사(`69-DERIVED-MODEL-AUDIT.md`)에서 "미결" 로 분류된 6개. enforce 승격 후에도 **격리 사각지대로 남는다.**

| 모델 | 막힌 이유 | 필요한 엔진 보강 |
|---|---|---|
| `QrPrintLog` | 모델에 `@BelongsTo(() => Branch)` 자체가 없음 | 모델에 association 추가 후 재분류 |
| `UserRole` | 부모(`roles`)에 전역 행(store_id NULL)이 있어 INNER JOIN 시 표준 role 이 사라짐 | `DerivedScopeRule.allowGlobalRows` — `buildDerivedInclude` 가 부모 전역 행을 union |
| `RoleFunctionAction` | 상동 | 상동 |
| `PaymentMethodsOption` | 상동 | 상동 |
| `SubconSettlement` | 부모가 OR 관계(둘 중 하나만 있으면 성립) | 엔진에 `anyOf` 규칙 추가 vs 파생 컬럼 도입 — 설계 논의 필요 |
| `SubconPayment` | 상동 | 상동 |

- **조치:** 수정하지 않음. 무회귀 보안 교정이라는 Phase 69 성격을 벗어나 엔진(`tenant-hooks.buildDerivedInclude`) 구조 변경이 필요하다.
- **후속:** 별도 phase 로. 그 전까지 이 6개 테이블은 store_id 경계 없이 조회된다.

### `BranchPrinterConfig` — 사문(dead) 모델에 걸린 파생 규칙 (no-op)

- `tenant-scope.registry.ts:168` 에 규칙이 있으나 모델이 어느 모듈의 `SequelizeModule.forFeature` 에도 등록돼 있지 않다
  (`src/app/print/branch-printer-config.model.ts` 를 import 하는 코드 0건 — 프린터 인증은 `BranchAgent` 로 대체).
- 훅이 설치되지 않아 규칙은 no-op. 부팅 로그 `대상=39` (레지스트리 40) 의 차이가 이 1건이다.
- **조치:** 수정하지 않음. 모델 삭제 여부는 print 모듈 정리 시 함께 판단.
