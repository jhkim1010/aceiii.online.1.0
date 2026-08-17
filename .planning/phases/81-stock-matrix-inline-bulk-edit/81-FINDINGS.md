# Phase 81 — 실측 + CODEX 교정 (2026-08-17)

전문: `.gsd/review-codex-matrix-inline-bulk-edit.md`

## 사용자 요구

매트릭스 지표 체크박스 줄(`Ingreso · Venta · Stock · HIngreso · HVenta`) 오른쪽에 **`Editar`**
체크박스. 켜면 매트릭스가 **편집 가능**해지고 각 칸에 현재 스톡이 채워진다. 아래에 **보정치(Δ)**
를 살짝 보여주고, 매트릭스 아래 오른쪽 **`Confirmar`** 로 **한 번에** 기록한다.
지금은 셀 하나씩 선택→수정→확인을 반복해야 해서 불편하다.

## F1. 현재 구조

- `SelectedCell`: `{ color, talle, stock, productBranchId, branchCount, variantSku }`
  — 기여 PB 가 **유일할 때만** `productBranchId` 가 실제 id, 아니면 **0**(조정 불가 표식).
  판정 기준은 `byBranch.length === 1`.
- 조정 API 는 **셀 하나**만 처리(`POST /reports/stocks-cockpit/adjust`).
  2026-08-17 에 권한(admin·gerente)·지점 대조·NotFound·값 검증·**트랜잭션+advisory lock**·
  `stock_balances.available` 읽기까지 적용된 상태다.
- `stocks` 는 append-only 원장. 보정은 반대 부호 행. 잔액은 트리거가 같은 트랜잭션에서 반영.

## F2. ★ `on_hand` 이 아니라 `available` (이미 확인된 함정)

운영 실측: 439 PB 중 **44건**에서 `on_hand ≠ 원장 합`, 차이는 정확히 `reservado`.
화면의 `r_stock`(=`SUM(stocks)`)과 일치하는 것은 **`available`** 이고 전 건 일치
(`v_stock_balance_drift` 0행). 배치도 반드시 `available` 을 읽는다.

---

# CODEX 교정

## C1. `expectedStock` 검증은 선택이 아니라 **필수** ★ Blocker
절대값(`realStock`)만 보내면 **화면을 연 뒤 발생한 판매·입고를 조용히 덮는다.**
```
화면 기준 10 → 사용자 8 입력 → 저장 전 판매 −2 (DB 7)
서버: 8 − 7 = +1 을 기록 → 방금 판매의 일부를 되돌린다
```
→ 항목마다 `expectedStock` 을 싣고, **락 획득 후** `current === expected` 를 먼저 검사.
하나라도 다르면 INSERT 를 시작하지 말고 **409 로 전체 거부** + 충돌 셀 목록
(`productBranchId, expectedStock, currentStock, realStock`) 반환.
★ 이 저장소에 같은 유형의 전례가 있다(메모리 `confirm-step-needs-state-not-just-verdict`).

## C2. 부분 성공 금지 — 검증과 쓰기를 섞지 않는다 ★ Blocker
한 번의 실사 입력은 **하나의 업무 동작**이다(CLAUDE.md 단일 트랜잭션 원칙).
20개 중 17개만 저장되면 사용자는 무엇이 반영됐는지 다시 대조해야 한다.
→ 순서: ①요청 검증 → ②전 대상 락 → ③전 기준값 비교 → ④부모/소유/지점 검증 →
**⑤전부 통과한 뒤에만** INSERT. 앞쪽부터 INSERT 하다 뒤에서 충돌을 발견하는 구현 금지.

## C3. 정규화 + 고정 잠금 순서 ★ Blocker
`productBranchId` 오름차순만으로는 부족하다 — variation 마다 leaf `productId` 가 다르고,
요청자가 배열 순서를 임의로 바꿀 수 있다.
→ PB 메타를 **한 번의 집합 쿼리**로 조회 후 **`product_id ASC, product_branch_id ASC`** 로
정렬해 락을 잡는다. 요청 내 **중복 PB 는 400**. (락 개수 자체는 수십 개 수준에서 문제 아님 —
위험은 **반대 순서 교착**과 무제한 배열의 **트랜잭션 장기 점유**다.)

## C4. 배치 크기·값 범위 서버 제한 ★ Blocker
`items` 비어있지 않음 · **최대 50** · 각 id/재고 `Number.isSafeInteger` · `pbId > 0` ·
`realStock >= 0` · 중복 금지 · `note` 500자 · **모든 PB 가 요청자 store 와 선택 branch 에
속하는지 집합 검증** · 화면에서 고른 제품 family 의 variation 인지도 서버가 확인.

## C5 (Should). 집합 쿼리로 — 루프 N회 금지
단일 로직을 루프로 N번 부르면 소유권·잔액·부모판정·INSERT 가 각각 반복돼 쿼리가 수십 배.
→ `WHERE pb.id IN (:ids)` / `stock_balances ... IN (...)` / 잔액 없는 PB 만 `GROUP BY` 폴백 /
부모 판정도 `productId[]` 한 번에 / INSERT 는 다중 VALUES.
**단 advisory lock 은 정렬 순서를 지키기 위해 순차 획득.**

## C6 (Should). `batchId` 를 원장에 남긴다
공통 `note` 로는 "같은 실사에서 나온 보정" 을 식별할 수 없다(note 는 설명이지 식별자가 아니다).
→ 서버가 UUID 생성해 모든 행에 기록. `stocks` 에 컬럼이 없으면 **기존 마이그레이션을 고치지 말고**
새 nullable 컬럼 또는 별도 `stock_adjust_batches` 테이블(수행자·branch·시각·note·항목 수).

## C7 (Should). 재시도 안전성
커밋 후 응답을 못 받아 재전송하면, 그 사이 판매가 있었을 때 다시 덮을 수 있다.
→ `Idempotency-Key`(또는 `requestId`) + `(store_id, request_id)` UNIQUE, 같은 키면 최초 결과 반환.
최소한 `expectedStock` 불일치로 덮어쓰기는 차단된다.

## C8 (Should). 편집 가능 여부를 **서버 응답**에 명시
부모(madre) PB 여부는 매트릭스 응답에 없어 프론트만으로는 "부모는 입력칸 없음" 을 구현할 수 없다.
→ 셀마다 `adjustment: { allowed, reason: 'AGGREGATED'|'AMBIGUOUS_PB'|'MADRE'|null }`.
**단 이건 UX 안내용이고, 배치 API 는 모든 조건을 다시 검증한다.**

## C9 (Should). 편집 중 컨텍스트 변경 방어
지금은 지점·제품 변경 시 상태가 즉시 초기화된다 → 미저장 입력이 **조용히 사라진다.**
→ 변경값 있으면 확인 후 폐기 · 저장 중에는 지점/제품/Editar 비활성 ·
새 매트릭스 응답을 **기존 입력에 자동 병합하지 않는다** · `Editar` 해제도 폐기 확인.

## C10 (Should). 큰 보정은 차단이 아니라 단계적 확인
고정 임계로 금지하면 진짜 실사도 막힌다.
→ 음수 실제 재고만 항상 차단. 변경 셀 수 · `Σ|diff|` · 최대 단일 `|diff|` 표시,
임계 초과 시 확인 대화상자에 큰 변경 셀 목록 + "변경 전 → 후".

## C11 (Should). 저장 후 갱신에서 remount 금지
현재 `refreshKey` 가 Panel B·C 의 `key` 에 들어가 **통째로 remount** 된다 —
오늘 없앤 깜빡임을 되살리고 Panel B 의 페이지·정렬·선택을 잃는다.
→ 커밋 응답값으로 Panel C 즉시 갱신 · B/C 재조회는 병렬 · `key` 대신 명시적 `reload()` ·
재조회 중 기존 데이터 유지 + 작은 표시 · 최근 저장 세대보다 오래된 응답은 폐기.

## C12 (Should). Panel D 는 **제거하지 않는다** — 역할 축소
Panel D 에는 단일 셀 SKU·이론값·차이·note·결과 표시·합산 안내가 있다. 인라인 배치는
다중 입력을 빠르게 하는 기능이지 이 정보 구조를 대체하지 않는다.
→ 일반 모드 유지 / 편집 모드에서는 비활성 또는 **배치 요약 영역으로 전환** /
제거 여부는 사용 로그를 본 뒤 별도 단계에서 판단.
★ 사용자는 "필요 없어질 것 같다" 고 했으나, **지우는 것은 되돌리기 어려운 UI 변경**이라
이번에는 숨기기까지만 한다.

## C13 (Nice). 그 외
변경 셀 강조 + Enter/Tab 이동(ESC=현재 셀 복원, 전체 폐기는 별도 버튼) ·
응답에 `batchId/adjustedCount/totalAbsoluteDiff/items[]` 요약 ·
배치 전용 회귀 테스트 목록(아래 81-04 에 그대로 반영).
