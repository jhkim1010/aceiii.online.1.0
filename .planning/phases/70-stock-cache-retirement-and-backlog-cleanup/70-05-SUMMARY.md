---
phase: 70-stock-cache-retirement-and-backlog-cleanup
plan: 05
subsystem: front
tags: [react, products, form-reset, trello]

# Dependency graph
requires: []
provides:
  - "저장 성공 시 등록 폼 초기화 (지점만 보존)"
  - "정책 역전 근거를 코드 주석에 고정 — 되돌림 방지"
affects: [70-07]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "과거 요청으로 넣은 동작을 뒤집을 때는 주석을 지우지 말고 갱신한다 — 근거가 사라지면 다음 사람이 되돌린다"

key-files:
  created: []
  modified:
    - ventago-app/src/views/products/list/ProductsView.tsx
---

# 70-05 — 연속 등록 시 이전 상품이 남는 문제 (Trello diACgk5B)

## 문제

신고: *"Al haber cargado mas de un producto, si se quiere agregar otro se mantiene.
si se selecciona otra categoria, aun se quedan el articulo cargado."*

저장 성공 경로에 폼 초기화가 **없었다.** `handleStartNewProduct` 를 호출하는 트리거는
Serial 클릭 · 서브카테고리 onFocus · 공급자 onFocus 셋뿐이라, 저장 후 그대로 다음 상품을 입력하면
이전 값이 섞인 채 생성된다.

## 왜 그렇게 돼 있었나 — 그리고 왜 뒤집었나

`ProductsView.tsx` 에 *"사용자 요청 — agregar 후 같은 지점에서 입력값 유지"* 주석이 있었다.
**값을 남기는 것 자체가 과거에 요청받아 넣은 기능**이었다. 같은 사용자가 이제 정반대를 신고했고,
2026-08-03 **안 B(저장 성공 후 항상 리셋)** 로 확정됐다.

그래서 주석을 **지우지 않고 갱신**했다 — 종전 동작이 무엇이었고 왜 뒤집혔는지(Trello diACgk5B)를
남겨야 다음 사람이 "값 유지가 요청사항인데 왜 리셋하지?" 하고 되돌리지 않는다.

## 무엇을 했나

`resetFormAfterSave()` 를 추가하고 `doSubmit` **성공 경로**에서만 호출한다.

| 항목 | 처리 |
|---|---|
| 상품 고유값 (name/sku/description/price/serial) | 비움 |
| 카테고리·서브카테고리·공급자·원산지 | **비움** — 다음 상품에 섞이는 것이 신고 내용이었다 |
| prices / variants / sizes / colors / stocks / cantidad | 비움 |
| `editingMadre`, `mode` | 초기화 (`add`) |
| **선택된 지점 (`selectedBranches`)** | **보존** — 신고는 "상품 정보가 남는다" 였지 "지점이 리셋된다" 가 아니다 |
| 저장 **실패** 경로 | 리셋하지 않음 — 입력을 날리면 재시도가 불가능하다 |

`handleStartNewProduct` 와 지우는 대상이 겹치지만 두 가지가 다르다: 카테고리 계열까지 비우고,
지점은 건드리지 않는다. 의미가 다른 동작이라 합치지 않고 별도 콜백으로 뒀다(주석에 차이를 명시).

부수적으로 쓰이지 않게 된 지역변수 3개(`savedParentId`/`createdSku`/`createdSerial`)를 제거했다 —
남겨두면 `no-unused-vars` 로 프론트 빌드가 막힌다.

## 검증

| 검증 | 결과 |
|---|---|
| `npx eslint ProductsView.tsx` | **오류 0** (경고 1건은 `handleStartNewProduct` 의 exhaustive-deps — 변경 전에도 동일, stash 대조로 확인) |
| `npx tsc --noEmit` | 오류 0 |
| 리셋 후 undefined 접근 위험 | 없음 — `product.categories`/`sku`/`price` 접근부는 전부 `&&`/`||` 가드. `setProduct({})` 는 `handleStartNewProduct` 가 만들던 부분 객체와 같은 형태다 |

## 계획 대비 차이

플랜의 `files_modified` 에 `BasicDataCard.tsx` 가 있었으나 **수정하지 않았다.**
그 파일은 "카테고리 select 에 리셋을 연결한다" 는 초기 가설(안 A)의 대상이었고,
확정된 안 B는 **저장 성공 시점**에 리셋하므로 카테고리 select 를 건드릴 필요가 없다.
호출부 한 곳만 바꿔 영향 범위를 좁혔다.

## 남은 것 (70-07 UAT 에서 확인)

- 저장 성공 → 폼이 비는가 / 지점은 남는가
- 저장 실패 → 입력이 남아 재시도 가능한가
- 연속 2건 등록 시 두 번째에 첫 번째 값이 섞이지 않는가
