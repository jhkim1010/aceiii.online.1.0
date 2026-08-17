# CODEX 검토 결과 — 매트릭스 인라인 일괄 수정 (2026-08-17)

요청서: `.gsd/review-request-matrix-inline-bulk-edit.md`

## 총평

방향은 타당합니다. 특히 새 배치 엔드포인트, 단일 트랜잭션, 변경 셀만 전송, 전체 롤백, Panel D 유지 결정은 적절합니다.

다만 현재 초안 그대로 구현하면 화면을 연 뒤 발생한 판매·입고를 절대값 조정이 조용히 덮어쓸 수 있습니다. 따라서 `expectedStock` 검증과 전체 원자성은 선택 사항이 아니라 필수입니다. 또한 배치 크기 제한, 중복 PB 차단, 고정 잠금 순서, 감사용 `batchId`, 편집 중 컨텍스트 변경 방어가 설계에 포함되어야 합니다.

## 반드시 고쳐야 할 것(Blocker)

### 1. 각 항목에 `expectedStock`을 포함하고 잠금 후 비교해야 함

[근거: `api-ventago/src/app/reports/reportsStocksCockpit.service.ts:1593`]

현재 단일 조정은 advisory lock을 잡은 뒤 최신 `stock_balances.available`을 읽고 `realStock - theoretical`을 기록합니다. 배치도 `realStock`만 보내면 화면 로드 이후 판매·입고가 발생했을 때 그 변동까지 보정 행으로 상쇄합니다.

예:

- 화면 기준 재고 10
- 사용자가 실제 재고 8 입력
- 저장 전 판매 −2 발생 → DB 재고 8
- 서버가 `8 - 8 = 0`으로 처리

이 경우 입력 의도와 우연히 같아졌는지 알 수 없습니다. 더 위험한 경우 판매 후 DB가 7이면 서버가 `+1`을 기록하여 판매 변동 일부를 되돌립니다.

구체적 대안:

```ts
items: Array<{
  productBranchId: number
  expectedStock: number
  realStock: number
}>
```

서버는 모든 락을 획득한 다음 `available`을 다시 읽고 다음을 먼저 검사해야 합니다.

```ts
currentStock === expectedStock
```

하나라도 다르면 INSERT를 시작하지 말고 `409 Conflict`로 전체 요청을 거부하십시오. 응답에는 충돌 셀별로 `productBranchId`, `expectedStock`, `currentStock`, `realStock`을 반환해야 합니다.

### 2. 기준값 불일치 시 부분 성공이 아니라 전체 롤백해야 함

[근거: `CLAUDE.md:312-314`]

한 번의 실사 입력은 하나의 업무 동작입니다. 20개 중 17개만 저장하면 사용자는 어떤 값이 반영됐는지 다시 대조해야 하고, 재시도 과정에서 이미 반영된 셀과 미반영 셀이 섞입니다.

구체적 대안:

1. 요청 전체 검증
2. 모든 대상 락 획득
3. 모든 기준값 비교
4. 모든 부모/소유권/지점 검증
5. 검증이 모두 성공한 뒤에만 원장 INSERT
6. 한 항목이라도 실패하면 전체 롤백 및 `409` 또는 `400`

즉, 검증과 쓰기를 셀별로 섞지 말아야 합니다. 앞쪽 셀부터 INSERT한 뒤 뒤쪽 충돌을 발견하는 구현은 트랜잭션이 있더라도 불필요한 작업과 잠금을 만들고 설계를 복잡하게 합니다.

### 3. 요청 배열을 정규화하고 고정된 순서로 잠가야 함

[근거: `CLAUDE.md:319`]  
[근거: `api-ventago/src/app/reports/reportsStocksCockpit.service.ts:1593-1598`]

초안의 `productBranchId` 오름차순만으로는 저장소의 `productId` 오름차순 규약을 충족한다고 단정할 수 없습니다. 각 variation은 서로 다른 leaf `productId`를 가질 수 있고, 요청자가 배열 순서를 임의로 바꿀 수도 있습니다.

구체적 대안:

- 트랜잭션 전에 형식·개수·중복 ID를 검증
- PB 메타데이터를 한 번의 집합 쿼리로 조회
- `product_id ASC, product_branch_id ASC`로 정렬
- 정렬 결과대로 advisory lock 획득
- 같은 정렬 결과로 잔액 검증과 INSERT 수행
- 요청 내 동일 `productBranchId` 중복은 `400`으로 거부

`pg_advisory_xact_lock(80, pbId)`를 반복 호출하는 것 자체는 수십 개 수준에서 본질적인 문제가 아닙니다. 위험은 락 개수보다 서로 다른 요청이 반대 순서로 락을 잡는 교착과, 무제한 배열로 트랜잭션을 오래 점유하는 것입니다.

### 4. 배치 크기와 숫자 범위를 서버에서 제한해야 함

[근거: `api-ventago/src/app/reports/reports.controller.ts:1184-1201`]  
[근거: `CLAUDE.md:309-310`]

기존 단일 API는 양의 PB ID, 안전한 정수 재고, 음수 금지, note 500자를 검증합니다. 배치 API가 배열만 추가하고 동일 수준의 항목별 검증 및 개수 제한을 두지 않으면 대량 락과 대량 INSERT로 pool을 오래 점유할 수 있습니다.

구체적 대안:

- `items`는 비어 있지 않아야 함
- 최대 항목 수 명시: 우선 50 권장
- 각 ID와 재고는 `Number.isSafeInteger`
- `productBranchId > 0`
- `expectedStock`은 안전한 정수
- `realStock >= 0`
- PB 중복 금지
- `note` 최대 500자
- 요청 JSON 크기 제한 유지
- 모든 PB가 요청자의 store 및 선택한 branch에 속하는지 집합 검증
- 화면에서 선택한 제품 family의 variation인지도 서버에서 검증

## 고치는 게 좋은 것(Should)

### 1. PB별 쿼리 반복 대신 집합 쿼리를 사용해야 함

[근거: `api-ventago/src/app/reports/reportsStocksCockpit.service.ts:1524-1535`]  
[근거: `api-ventago/src/app/reports/reportsStocksCockpit.service.ts:1600-1621`]

기존 단일 처리 로직을 루프에서 그대로 N번 호출하면 20개 셀 기준으로 소유권 조회, 잔액 조회, 부모 판정, INSERT가 각각 반복되어 쿼리가 수십 배로 증가합니다.

구체적 대안:

- `WHERE pb.id IN (:pbIds)`로 PB·product·store·branch를 한 번에 조회
- `stock_balances`도 `WHERE product_branch_id IN (...)`로 한 번에 조회
- 잔액 없는 PB의 원장 합계만 한 번의 `GROUP BY product_branch_id` 쿼리로 폴백
- 부모 판정도 전체 `productId[]`를 한 번에 처리
- INSERT는 다중 VALUES 또는 동일 트랜잭션의 bulk insert 사용

단, advisory lock은 정렬 순서를 보장하기 위해 순차 획득하는 편이 안전합니다.

### 2. `batchId`를 원장 행에 남겨야 함

[근거: `api-ventago/src/app/reports/reportsStocksCockpit.service.ts:1656-1671`]  
[근거: `CLAUDE.md:314`]

공통 note만으로는 “같은 실사에서 생성된 보정들”을 안정적으로 식별할 수 없습니다. note는 사용자가 수정할 수 있는 설명이며 식별자가 아닙니다.

구체적 대안:

- 서버에서 UUID `batchId` 생성
- 모든 원장 행에 동일한 `batchId` 기록
- 공통 note를 기본으로 사용
- 특별한 요구가 확인되기 전에는 셀별 note UI를 추가하지 않음
- 응답에도 `batchId`, 변경 행 수, 총 보정량 반환

현재 `stocks`에 해당 컬럼이 없다면 기존 마이그레이션을 수정하지 말고 새 nullable 컬럼 또는 별도 `stock_adjust_batches` 테이블을 추가해야 합니다. 별도 테이블을 사용하면 수행 사용자, branch, 생성 시각, 공통 note, 항목 수를 함께 감사할 수 있습니다.

### 3. 재시도 안전성을 명시해야 함

[근거: `CLAUDE.md:317`]  
[근거: `api-ventago/src/app/reports/reportsStocksCockpit.service.ts:1624-1627`]

클라이언트가 커밋 후 응답을 받지 못해 같은 요청을 재전송할 수 있습니다. 절대값 계산은 즉시 재시도에서는 diff 0이 되지만, 재시도 사이에 판매가 발생하면 그 판매를 다시 덮을 수 있습니다.

구체적 대안:

- `Idempotency-Key` 또는 클라이언트 생성 `requestId` 지원
- `(store_id, request_id)` unique 보장
- 같은 키의 재요청에는 최초 결과 반환
- 최소한 `expectedStock` 불일치로 재시도 후 변동 덮어쓰기를 차단

### 4. 편집 가능 여부를 서버 응답으로 명시해야 함

[근거: `api-ventago/src/app/reports/reportsStocksCockpit.service.ts:1398-1408`]  
[근거: `ventago-app/src/views/reports/stocks/panels/PanelD_StockAdjust.tsx:92-125`]

현재 프론트는 `branchId`와 `productBranchId`로 합산/모호성만 판정할 수 있습니다. 부모 PB 여부는 매트릭스 응답에 없어 “부모 PB는 입력칸을 주지 않는다”는 초안을 프론트만으로 구현할 수 없습니다.

구체적 대안:

```ts
adjustment: {
  allowed: boolean
  reason: 'AGGREGATED' | 'AMBIGUOUS_PB' | 'MADRE' | null
}
```

다만 이 값은 UX 안내용일 뿐이며, 서버 배치 API는 모든 조건을 다시 검증해야 합니다.

### 5. 편집 중 컨텍스트 변경과 미저장 값 폐기를 막아야 함

[근거: `ventago-app/src/views/reports/stocks/StocksCockpitBody.tsx:100-115`]  
[근거: `ventago-app/src/views/reports/stocks/panels/PanelC_ColorMatrix.tsx:193-237`]

지점·제품 변경 시 현재 상태는 즉시 초기화됩니다. 인라인 편집값이 생기면 지점 선택, 제품 선택, 새로고침, `Editar` 해제 모두 미저장 변경을 조용히 버릴 수 있습니다.

구체적 대안:

- 변경값이 없으면 즉시 종료
- 변경값이 있으면 “변경 내용을 버릴까요?” 확인
- 저장 중에는 지점·제품·Editar 토글을 비활성화
- 제품/지점/매트릭스 요청 세대를 편집 세션 키에 포함
- 새 매트릭스 응답이 도착했다고 기존 입력 상태에 자동 병합하지 않음
- `Editar`를 끄면 값 유지보다 명시적 폐기 확인 후 종료가 안전함

### 6. 큰 보정은 차단보다 단계적 확인이 적절함

[근거: `ventago-app/src/views/reports/stocks/panels/PanelD_StockAdjust.tsx:174-205`]

고정 임계값으로 큰 조정을 금지하면 실제 실사 수정도 막을 수 있습니다. 대신 이상치를 눈에 띄게 만들고 추가 확인을 받는 편이 적절합니다.

구체적 대안:

- 음수 실제 재고는 항상 차단
- 변경 셀 수, `Σ|diff|`, 최대 단일 `|diff|` 표시
- 임계 초과 시 확인 대화상자에서 큰 변경 셀 목록 표시
- 예: 단일 셀 `|diff| >= 20` 또는 기존 재고 대비 100% 이상 변화
- 임계값은 향후 매장 설정으로 이동 가능
- 최종 확인 화면에 “변경 전 → 변경 후”를 표시

### 7. 저장 후 B/C를 remount하는 현재 방식은 깜빡임과 선택 손실을 유발함

[근거: `ventago-app/src/views/reports/stocks/StocksCockpitBody.tsx:135-148`]  
[근거: `ventago-app/src/views/reports/stocks/StocksCockpitBody.tsx:160-178`]  
[근거: `ventago-app/src/views/reports/stocks/panels/PanelC_ColorMatrix.tsx:193-230`]

현재 `refreshKey`가 Panel B와 C의 `key`에 들어가므로 조정 후 두 패널을 통째로 remount합니다. 이는 기존에 제거하려 했던 깜빡임을 다시 만들고 Panel B의 페이지·정렬·선택 상태를 잃을 수 있습니다.

구체적 대안:

- 커밋 성공 후 응답값으로 Panel C를 즉시 갱신
- B/C 재조회는 병렬 실행
- 각 패널에 요청 세대 번호 또는 AbortController 적용
- `key` remount 대신 명시적 `reload()`/캐시 갱신 사용
- 재조회 중 기존 데이터를 유지하고 작은 saving/revalidating 표시만 노출
- 가장 최근 저장 세대보다 오래된 응답은 폐기
- B와 C 모두 완료된 뒤 편집 세션을 종료하거나, 실패 패널만 재시도 가능하게 표시

### 8. Panel D는 제거하지 말고 역할을 축소해야 함

[근거: `ventago-app/src/views/reports/stocks/panels/PanelD_StockAdjust.tsx:127-223`]  
[근거: `ventago-app/src/views/reports/stocks/StocksCockpitBody.tsx:187-193`]

Panel D에는 단일 셀의 SKU·이론값·차이·note·결과 표시와 합산 화면 안내가 있습니다. 인라인 배치는 다중 입력을 빠르게 하는 기능이지 이 정보 구조 전체를 대체하지 않습니다.

구체적 대안:

- 일반 모드에서는 Panel D 유지
- 편집 모드에서는 Panel D를 비활성화하거나 배치 요약 영역으로 전환
- 단일 셀 상세 조정과 note 입력 경로 유지
- 사용 로그를 확인한 뒤 별도 단계에서 제거 여부 결정

## 선택(Nice)

### 1. 변경 셀만 강조하고 키보드 조작을 지원

[근거: `ventago-app/src/views/reports/stocks/panels/PanelC_ColorMatrix.tsx:454-563`]

변경된 셀에 테두리나 배지를 표시하고 Enter/Tab 이동을 지원하면 대량 실사 입력이 빨라집니다. ESC는 현재 셀 복원, 전체 폐기는 별도 버튼으로 분리하는 편이 안전합니다.

### 2. 서버 응답에 조정 요약을 포함

[근거: `api-ventago/src/app/reports/reportsStocksCockpit.service.ts:1624-1627`]

다음 형태가 후속 UI와 감사에 유용합니다.

```ts
{
  success: true,
  batchId,
  adjustedCount,
  unchangedCount,
  totalAbsoluteDiff,
  items: [
    { productBranchId, previousStock, realStock, diff }
  ]
}
```

### 3. 배치 전용 회귀 테스트를 추가

[근거: `api-ventago/src/app/reports/reportsStocksCockpit.adjust.spec.ts:268-357`]

최소한 다음을 고정해야 합니다.

- 한 항목 기준값 불일치 시 INSERT 0건
