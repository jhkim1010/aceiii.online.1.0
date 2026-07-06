# SPEC: Trello 가격 버그 묶음 (B1/B2/B7)
생성일: 2026-07-05
Trello: G3sAmi93 (B1) · Rzc8NjfE (B2) · 3heUO9iG (B7)

## 목표
상품 폼/설정에서 가격 레벨이 (1) 누락되지 않고 (2) 0으로 저장되지 않으며 (3) 고정금액/활성상태가 올바르게 표시·저장되게 한다.

## 배경 및 컨텍스트 (검증된 원인)

**데이터 관행 (로컬 DB 확인):** `price_types.increase_value` 는 percentage 일 때 배수%(121=기준가의 121%). 0 = 수동 입력 레벨. `PRECIO 1` 은 모든 매장에서 increase_value=0 → product.price(precio base) 와 동일 개념 (codigo-vista fallback 로직이 이 관행을 확인해줌).

1. **B1 (Precio 1 미표시):** `BasicDataCard.tsx:111`, `ProductsView.tsx:450`, `ProductsList.tsx:60` 의 `Number(pt.increaseValue) !== 0` 필터가 increaseValue=0 인 **모든** 레벨(수동 레벨 포함)을 숨김. PRECIO 1 뿐 아니라 매장이 만든 수동 PRECIO 2~5 도 사라짐.
2. **B2 (신규 가격 0 저장):** 수동 레벨이 폼에서 숨겨져 amount 입력 불가 → Price 레코드가 0/누락 → 판매 $0. 추가로 `ProductsView.tsx:566-590` 자동계산이 increaseType 무시: 'amount'(고정) 레벨도 `base*value/100` 으로 계산.
3. **B7 (고정금액→%, 활성→비활성 표시, precio base 2회):**
   - `BasicDataCard.tsx:947-956` 배지가 increaseType 무시하고 항상 `+X%`
   - 설정 목록 `DataConfig.tsx:35-37` Estado 컬럼이 `row.isActive` 참조 — 백엔드는 `status`(number)만 반환 → 항상 비활성 표시. `PriceTypesList.tsx:74-99` 토글도 동일.
   - `ModalPriceType.tsx` 편집 시 `reset(priceType)` — isActive 필드 없음 → yup required 실패 가능. 저장 시 isActive 전송 → 백엔드 무시(모델에 status 만 존재).
   - "precio base 2번": 하드코딩 'Precio base' 박스 + base 성격 레벨(PRECIO 1)이 동시에 노출될 때 중복.

## 기술 스택
- 프론트만 수정 (ventago-app, Next.js 13 + MUI). 백엔드/DB 변경 없음 → api 재배포 불필요.
- ESLint: newline-before-return, lines-around-comment, no-unused-vars 준수.

## 태스크 목록
- [ ] TASK-1: `src/utils/price-types.ts` 신규 — `isBaseLikePriceType(pt)` (이름 /^precio\s*(1|base)\b/i && increaseValue==0) + `filterVisiblePriceTypes(list, storeId)` 공용 헬퍼
- [ ] TASK-2: BasicDataCard.tsx — 필터를 헬퍼로 교체(수동 레벨 표시), 배지 increaseType 분기(percentage `X%` / amount `+$X` / 0 `manual`), 'Precio base' 라벨을 base 레벨 이름(PRECIO 1)으로 표시
- [ ] TASK-3: ProductsView.tsx — 필터 교체 + 자동계산 수정: percentage→`base*value/100`(기존 유지), amount→`base+value`, increaseValue=0 수동 레벨은 입력값 보존(0으로 덮어쓰지 않음)
- [ ] TASK-4: ProductsList.tsx — 컬럼 필터를 base-like 제외로 교체 (수동 레벨 컬럼 표시)
- [ ] TASK-5: price-types 설정 — DataConfig Estado 컬럼 `status===1` 기준, PriceTypesList 토글/액션 `status` 기준, ModalPriceType 편집 로드 시 `isActive: status===1` 매핑 + 저장 시 `status` 전송
- [ ] TASK-6: ESLint 검증 (사용자 Mac 실행 명령 전달)
- [ ] TASK-7: 로컬 커밋 (ventago-app 서브모듈, 브랜치 fix/trello-price-levels)

## 완료 기준
- 수동 레벨(PRECIO 2~5, increaseValue=0)이 상품 폼에 입력 가능하게 표시
- base-like 레벨(PRECIO 1)은 'Precio base' 박스와 중복 표시되지 않고, 박스 라벨이 해당 이름으로 표시
- 고정금액 레벨: 배지 `+$X`, 자동계산 `base+X`
- 설정 목록에서 활성 레벨이 활성으로 표시, 토글 정상 동작
- ESLint 오류 0

## 금지사항
- 백엔드/DB/판매(sales) 화면 로직 변경 금지 (범위 밖)
- codigo-vista 의 fallback 로직 변경 금지 (관행 유지)
- push 금지 — 로컬 커밋까지만
