# CODEX 검토 결과 — Phase 82 Enviado 보고서 (2026-08-17)

요청서: `.gsd/review-request-phase82-enviado.md`

## 총평

방향은 타당합니다. `shipped_at`을 “Enviado”의 정본으로 고정하고, Despacho 보드와 달리 기간별 성과·병목·운송사 품질을 보여주는 구성도 적절합니다. 실제 발송 처리에서 `shipped_at`과 `dispatched_at`은 같은 트랜잭션에서 연속으로 기록되므로 현재 데이터에서는 사실상 같은 사건입니다. `[근거: api-ventago/src/app/online-orders/online-orders.service.ts:1023]`

다만 현재 계획대로 구현하면 기간별 KPI의 분모가 서로 달라지거나 미래 주문이 섞이고, 존재하지 않는 `dispatched_at → shipped_at` 구간을 별도 병목처럼 표현하며, 취소 주문이 `En tránsito`에 남는 등 “조용히 틀린 숫자”가 발생할 가능성이 큽니다. 아래 Blocker를 먼저 정의해야 합니다.

## 반드시 고쳐야 할 것(Blocker)

### 1. 기간 필터의 기준 시각과 코호트가 정의되지 않았다

[근거: .planning/phases/82-enviado-online-shipping-control-report/82-01-PLAN.md:50]

문제: `getKpis()`, `getStageBreakdown()`, `getDemorados()`, `getPorTransporte()`에 기간 필터를 어느 타임스탬프에 적용할지 없다. 예를 들어 기간 내 발송 주문을 기준으로 하면 아직 배송되지 않은 주문은 `En tránsito`에 잡히지만 정시율은 과거에 완료된 일부만 분모가 된다. 반대로 `delivered_at` 기준이면 기간 전 발송·기간 내 배달 주문이 포함되어 발송 건수와 정시율 분모가 서로 다른 코호트가 된다.

구체적 대안:

- 보고서의 기본 코호트를 `shipped_at >= :fromUtc AND shipped_at < :toExclusiveUtc`로 고정한다.
- KPI마다 `eligibleCount`와 `excludedCount`를 응답한다.
- 정시율은 해당 발송 코호트 중 `delivered_at IS NOT NULL AND cancelled_at IS NULL`만 분모로 삼는다.
- 아직 배송되지 않은 주문은 정시율 분모에서 제외됐음을 화면에 표시한다.
- 별도로 “기간 중 배송 완료 성과”가 필요하다면 같은 KPI에 섞지 말고 `delivery-cohort` 지표로 명시한다.
- 종료일은 `23:59:59.999`가 아니라 다음 날 자정 미만의 반개방 구간을 사용한다.

### 2. 계획된 4구간 중 `dispatched_at → shipped_at`은 실제로 의미 있는 단계가 아니다

[근거: .planning/phases/82-enviado-online-shipping-control-report/82-01-PLAN.md:53]  
[근거: api-ventago/src/app/online-orders/online-orders.service.ts:1023]  
[근거: api-ventago/src/app/online-orders/online-order.model.ts:162]

문제: 현재 `shipOrder()`는 `shippedAt`과 `dispatchedAt`을 같은 코드 경로에서 즉시 기록한다. 따라서 계획의 `despachado → transporte` 구간은 거의 항상 0이며, 이를 별도 평균과 “가장 느린 구간” 비교에 넣으면 실제 운영 단계가 존재하는 것처럼 오도한다. 모델 주석상 `dispatchedAt`은 새 Despacho 단계 기록이고 `shippedAt`은 레거시 발송 시각일 뿐, 고객에게 나간 서로 다른 두 사건이 아니다.

구체적 대안:

- 현 스키마에서는 3구간만 계산한다.
  - `confirmed_at → prepared_at`: 준비
  - `prepared_at → shipped_at`: 출고 준비 완료 후 실제 발송
  - `shipped_at → delivered_at`: 운송
- 4칸 UI가 필수라면 첫 구간을 `created_at → confirmed_at`으로 추가하되, “주문 접수→확인”으로 정확히 명명한다.
- `dispatched_at → shipped_at`은 두 값이 별도 업무 이벤트로 기록되기 전까지 분석 지표에서 제외한다.
- `shipped_at`을 Enviado 정본으로 쓰는 결정 자체는 유지해도 된다.

### 3. 취소 주문이 `En tránsito`와 목록에 포함되는 조건을 명시해야 한다

[근거: .planning/phases/82-enviado-online-shipping-control-report/82-01-PLAN.md:40]  
[근거: .planning/phases/82-enviado-online-shipping-control-report/82-01-PLAN.md:55]  
[근거: api-ventago/src/app/online-orders/online-orders.service.ts:1577]  
[근거: api-ventago/src/app/online-orders/online-orders.service.ts:1605]  
[근거: api-ventago/src/app/online-orders/online-orders.service.ts:1732]

문제: `발송됨 AND 미배달`만 사용하면 발송 후 취소된 주문도 `En tránsito`와 `Demorados`에 남는다. 그러나 취소 경로는 발송된 주문의 판매와 재고를 역분개하고 `stock_released_at`도 갱신한다. 따라서 이 주문은 현재 길에 묶인 재고가 아니며 일반 En tránsito 금액에 포함하면 틀린 숫자다.

구체적 대안:

- 현재 En tránsito 정의:
  `shipped_at IS NOT NULL AND delivered_at IS NULL AND cancelled_at IS NULL`
- `Demorados`, 운송사별 미배달 수도 동일한 조건을 공유한다.
- 발송 후 취소 주문은 별도 `Cancelados después del envío` 예외 건수/목록으로 노출한다.
- 데이터 이상 감시를 위해 `cancelled_at IS NOT NULL AND stock_released_at IS NULL` 건수도 별도 진단값으로 제공한다.
- 취소 주문을 정시율에서 제외한 선택은 맞다.

### 4. 매장 타임존 변환 규약이 구현 가능한 수준으로 구체화되지 않았다

[근거: .planning/phases/82-enviado-online-shipping-control-report/82-01-PLAN.md:41]  
[근거: api-ventago/src/app/reports/reportsStocksCockpit.service.ts:208]

문제: “`TODAY_SQL` 규약을 따른다”만으로는 기간 필터가 안전하지 않다. 기존 규약은 `(CURRENT_TIMESTAMP AT TIME ZONE :tz)::date`로 오늘을 계산하지만, Enviado 보고서는 사용자가 보낸 현지 날짜 범위를 UTC `TIMESTAMPTZ`와 비교해야 한다. `shipped_at::date` 또는 세션 타임존 의존 캐스팅을 쓰면 기존 17% 오차가 재발할 수 있다.

구체적 대안:

- 매장의 검증된 IANA 타임존으로 현지 `startDate 00:00`과 `endDate+1 00:00`을 UTC 경계로 변환한다.
- 컬럼에는 함수를 씌우지 않고 `shipped_at >= :fromUtc AND shipped_at < :toUtc`로 비교한다.
- “오늘 경과일”은 `(CURRENT_TIMESTAMP AT TIME ZONE :tz)::date`와 `(shipped_at AT TIME ZONE :tz)::date`의 차이로 정의한다.
- DST 및 자정 전후 주문 테스트를 추가한다.
- 모든 쿼리에 `store_id = :storeId`를 필수 조건으로 넣는다.

## 고치는 게 좋은 것(Should)

### 1. 정시율은 운송 구간과 고객 체감 구간을 분리하는 것이 좋다

[근거: api-ventago/src/app/online-orders/online-orders.service.ts:1023]  
[근거: api-ventago/src/app/online-orders/online-orders.service.ts:1305]

문제: `delivered_at − shipped_at`은 운송사 성과에는 맞지만 매장 준비 지연을 숨긴다. 이를 단순히 “정시배송률”이라고 부르면 고객이 체감하는 전체 주문 시간을 나타내는 것으로 오해할 수 있다.

구체적 대안:

- 주 KPI: `OTD transporte = delivered_at − shipped_at ≤ 5 días`
- 보조 KPI: `Tiempo total = delivered_at − confirmed_at`
- 전체 정시율에도 기준이 필요하다면 별도의 기준을 합의하기 전에는 비율로 만들지 말고 평균·P90 소요일만 표시한다.
- 운송사별 비교에는 반드시 `shipped_at` 기준만 사용한다.

### 2. 구간마다 표본 수와 전체 체인 표본을 함께 표시해야 한다

[근거: .planning/phases/82-enviado-online-shipping-control-report/82-01-PLAN.md:53]

문제: 구간별 결측 제외는 맞지만 분모가 다르므로 평균 네 개의 합이 전체 평균과 일치하지 않는다.

구체적 대안:

- 각 구간에 `avgDays`, `sampleCount`, `missingCount`를 반환한다.
- 화면에 `Promedio, n=8`처럼 표기한다.
- 구간 합계를 전체 평균으로 표시하지 않는다.
- 별도로 모든 필수 타임스탬프가 있는 주문만 사용한 `completeJourneyAvg`와 `completeJourneyCount`를 제공한다.
- 역전된 타임스탬프의 음수 구간은 평균에서 조용히 제외하지 말고 `invalidSequenceCount`로 보고한다.

### 3. “묶인 금액”을 재고가액처럼 표현하면 안 된다

[근거: api-ventago/migrations/phase27-online-orders.sql:39]  
[근거: api-ventago/src/app/online-orders/online-orders.service.ts:1118]  
[근거: api-ventago/src/app/online-orders/online-orders.service.ts:1181]

문제: `SUM(total)`은 고객 청구액/매출액이며 재고 원가가 아니다. 또한 발송 시 `mirror_sale_id`가 생성되고 재고 hold도 판매로 전환되므로 “묶인 재고 금액”이라는 표현은 회계적으로 부정확하다. 같은 보고서가 `online_orders`만 합산하면 내부적인 중복 행은 아니지만, Ventas 보고서와 합산하면 같은 거래를 이중 계상하게 된다.

구체적 대안:

- KPI 명칭을 `Valor de pedidos en tránsito` 또는 `GMV en tránsito`로 바꾼다.
- `SUM(total)`을 유지하되 판매 보고서와 합산하지 말라는 정의를 문서화한다.
- 상품가액만 원하면 `SUM(subtotal - discount)`을 검토하고, 배송비 포함 여부를 화면에 명시한다.
- 실제 재고 원가를 뜻하려면 주문 아이템과 원가 스냅샷이 필요하므로 이번 범위에서 사용하지 않는다.

### 4. 배송비 KPI의 분모와 0/NULL 처리 정의가 필요하다

[근거: api-ventago/migrations/phase27-online-orders.sql:39]  
[근거: .planning/phases/82-enviado-online-shipping-control-report/82-01-PLAN.md:51]

문제: 주문당 배송비가 취소·미발송 주문까지 포함하는지, 무료배송 `0`을 포함하는지 불명확하다. `shipping_cost / total`도 `total=0`이면 0 나눗셈이 생긴다.

구체적 대안:

- 발송 코호트의 취소 제외 주문을 분모로 고정한다.
- 무료배송 0은 실제 비용 데이터인지 고객 청구 배송비인지 구분한다. 현재 컬럼이 고객 청구액이라면 “Costo”보다 `Cargo de envío cobrado`가 정확하다.
- `SUM(shipping_cost) / NULLIF(SUM(total), 0)`으로 비율을 계산한다.
- `AVG(shipping_cost)`와 `SUM(shipping_cost)/COUNT(*)` 중 하나를 명시하고 테스트한다.

### 5. 운송사별 비율에 표본 수와 신뢰도 표시가 필요하다

[근거: .planning/phases/82-enviado-online-shipping-control-report/82-01-PLAN.md:57]  
[근거: .planning/phases/82-enviado-online-shipping-control-report/82-02-PLAN.md:27]

문제: `n=3`의 100%와 `n=14`의 71%를 동등하게 강조하거나 95% 목표선으로 색칠하면 과잉 해석을 유도한다.

구체적 대안:

- 각 운송사 행에 `delivered n / shipped n`을 표시한다.
- 정시율 분모가 10건 미만이면 회색 처리하고 `muestra pequeña` 배지를 붙인다.
- 작은 표본은 순위 산정과 최악 운송사 강조에서 제외한다.
- 95%는 외부 업계 목표가 아니라 내부 참고 목표임을 명시하거나, 근거가 확정되지 않았다면 색상 판정 기준에서 제외한다.

### 6. `hidden`은 모든 탐색 경로에서 일관되게 적용해야 한다

[근거: ventago-app/src/views/reports-v2/ReportsSidebar.tsx:101]  
[근거: ventago-app/src/views/reports-v2/ReportsSidebar.tsx:120]  
[근거: ventago-app/src/views/reports-v2/ReportsSidebar.tsx:130]

문제: 일반 목록만 필터링하면 Reservado가 최근 항목과 즐겨찾기에 계속 노출된다.

구체적 대안:

- `isVisibleReport(entry) => !entry.hidden` 공통 함수를 만들고 일반 목록·검색·최근·즐겨찾기에 모두 적용한다.
- 기존 localStorage 즐겨찾기에 남은 `reservado`도 렌더 단계에서 제거한다.
- 숨김 회귀 테스트에 세 경로를 모두 포함한다.

### 7. 직접 URL 접근 정책을 명시해야 한다

[근거: ventago-app/src/views/reports-v2/registry.ts:385]  
[근거: ventago-app/src/views/reports-v2/ReportsShell.tsx:37]

문제: `REPORTS_BY_SLUG`에는 숨긴 엔트리도 남으므로 `/reportes-v2/reservado` 직접 접근은 계속 가능하다. 현재 셸은 `hidden`이 아니라 권한만 검사한다. 이는 “메뉴에서만 숨김”이라면 정상이나 “기능 비활성화” 요구라면 불충분하다.

구체적 대안:

- 이번 요구를 “탐색 UI에서만 숨김, 기존 권한 보유자의 직접 URL 접근 허용”으로 문서화한다.
- 완전 비활성화가 목적이면 셸에서도 `hidden`을 검사해 다른 보고서로 이동시키거나 404를 표시한다.
- `reporte-reservado` 권한을 남기는 것 자체는 권한 재사용보다 안전하다. 다만 관리자 권한 화면에 폐기된 기능이 계속 나타나는지는 별도로 확인한다.

### 8. 현재 인덱스는 성장 후 발송일 중심 보고서에 부족하다

[근거: api-ventago/migrations/phase27-online-orders.sql:71]  
[근거: api-ventago/migrations/42-02-online-orders-cols.sql:30]

문제: 현재 주요 인덱스는 `(store_id, status)`, `(store_id, created_at)`, `transporte_id`다. 보고서가 `store_id + shipped_at 기간`으로 커지면 전체 매장 주문을 필터링할 수 있다. 단독 `transporte_id`도 멀티테넌트 기간 집계에는 충분하지 않다.

구체적 대안:

- 지금 12건만 보고 성급히 추가하지 말고 데이터 성장 기준과 실행계획을 기록한다.
- 필요 시 `CREATE INDEX CONCURRENTLY ... ON online_orders (store_id, shipped_at DESC) WHERE shipped_at IS NOT NULL`.
- 운송사 집계가 병목이면 `(store_id, transporte_id, shipped_at)`을 검토한다.
- 마이그레이션은 트랜잭션 밖의 `CREATE INDEX CONCURRENTLY`로 작성한다.
- `EXPLAIN`은 12건 환경의 100ms 결과만으로 장기 성능을 보장하지 못하므로 예상 행 수에서도 확인한다.

## 선택(Nice)

### 1. 평균만 아니라 P90을 함께 제공하면 지연 꼬리를 더 잘 보여준다

[근거: .planning/phases/82-enviado-online-shipping-control-report/82-01-PLAN.md:52]

구체적 대안: 평균 배송일 옆에 `P90`을 제공하되 표본이 충분할 때만 표시한다. 지연 주문 몇 건이 중요한 배송 데이터에서는 평균보다 운영적으로 유용하다.

### 2. 데이터 품질 KPI를 작게 추가하는 것이 좋다

[근거: api-ventago/src/app/online-orders/online-order.model.ts:143]

구체적 대안: 다음 이상 건수를 진단 영역에 표시한다.

- `delivered_at < shipped_at`
- `shipped_at < prepared_at`
- `shipped_at IS NOT NULL AND confirmed_at IS NULL`
- 취소됐지만 `stock_released_at IS NULL`
- `transporte_id IS NULL`인데 `shipping_carrier`만 존재
- 발송됐지만 tracking이 없고, 즉시배송 운송사도 아닌 주문

### 3. `Sin tracking`은 즉시배송 운송사를 구분해야 한다

[근거: api-ventago/src/app/online-orders/online-orders.service.ts:1029]

구체적 대안: 즉시배송은 추적번호가 본질적으로 불필요할 수 있으므로 모두 결함으로 세지 말고 `tracking required`인 운송사만 경고 대상으로 삼는다. 그렇지 않으면 정상 즉시배송 주문이 지속적으로 오류처럼 표시된다.
tokens used
60,883
## 총평

방향은 타당합니다. `shipped_at`을 “Enviado”의 정본으로 고정하고, Despacho 보드와 달리 기간별 성과·병목·운송사 품질을 보여주는 구성도 적절합니다. 실제 발송 처리에서 `shipped_at`과 `dispatched_at`은 같은 트랜잭션에서 연속으로 기록되므로 현재 데이터에서는 사실상 같은 사건입니다. `[근거: api-ventago/src/app/online-orders/online-orders.service.ts:1023]`

다만 현재 계획대로 구현하면 기간별 KPI의 분모가 서로 달라지거나 미래 주문이 섞이고, 존재하지 않는 `dispatched_at → shipped_at` 구간을 별도 병목처럼 표현하며, 취소 주문이 `En tránsito`에 남는 등 “조용히 틀린 숫자”가 발생할 가능성이 큽니다. 아래 Blocker를 먼저 정의해야 합니다.

## 반드시 고쳐야 할 것(Blocker)

### 1. 기간 필터의 기준 시각과 코호트가 정의되지 않았다

[근거: .planning/phases/82-enviado-online-shipping-control-report/82-01-PLAN.md:50]

문제: `getKpis()`, `getStageBreakdown()`, `getDemorados()`, `getPorTransporte()`에 기간 필터를 어느 타임스탬프에 적용할지 없다. 예를 들어 기간 내 발송 주문을 기준으로 하면 아직 배송되지 않은 주문은 `En tránsito`에 잡히지만 정시율은 과거에 완료된 일부만 분모가 된다. 반대로 `delivered_at` 기준이면 기간 전 발송·기간 내 배달 주문이 포함되어 발송 건수와 정시율 분모가 서로 다른 코호트가 된다.

구체적 대안:

- 보고서의 기본 코호트를 `shipped_at >= :fromUtc AND shipped_at < :toExclusiveUtc`로 고정한다.
- KPI마다 `eligibleCount`와 `excludedCount`를 응답한다.
- 정시율은 해당 발송 코호트 중 `delivered_at IS NOT NULL AND cancelled_at IS NULL`만 분모로 삼는다.
- 아직 배송되지 않은 주문은 정시율 분모에서 제외됐음을 화면에 표시한다.
- 별도로 “기간 중 배송 완료 성과”가 필요하다면 같은 KPI에 섞지 말고 `delivery-cohort` 지표로 명시한다.
- 종료일은 `23:59:59.999`가 아니라 다음 날 자정 미만의 반개방 구간을 사용한다.

### 2. 계획된 4구간 중 `dispatched_at → shipped_at`은 실제로 의미 있는 단계가 아니다

[근거: .planning/phases/82-enviado-online-shipping-control-report/82-01-PLAN.md:53]  
[근거: api-ventago/src/app/online-orders/online-orders.service.ts:1023]  
[근거: api-ventago/src/app/online-orders/online-order.model.ts:162]

문제: 현재 `shipOrder()`는 `shippedAt`과 `dispatchedAt`을 같은 코드 경로에서 즉시 기록한다. 따라서 계획의 `despachado → transporte` 구간은 거의 항상 0이며, 이를 별도 평균과 “가장 느린 구간” 비교에 넣으면 실제 운영 단계가 존재하는 것처럼 오도한다. 모델 주석상 `dispatchedAt`은 새 Despacho 단계 기록이고 `shippedAt`은 레거시 발송 시각일 뿐, 고객에게 나간 서로 다른 두 사건이 아니다.

구체적 대안:

- 현 스키마에서는 3구간만 계산한다.
  - `confirmed_at → prepared_at`: 준비
  - `prepared_at → shipped_at`: 출고 준비 완료 후 실제 발송
  - `shipped_at → delivered_at`: 운송
- 4칸 UI가 필수라면 첫 구간을 `created_at → confirmed_at`으로 추가하되, “주문 접수→확인”으로 정확히 명명한다.
- `dispatched_at → shipped_at`은 두 값이 별도 업무 이벤트로 기록되기 전까지 분석 지표에서 제외한다.
- `shipped_at`을 Enviado 정본으로 쓰는 결정 자체는 유지해도 된다.

### 3. 취소 주문이 `En tránsito`와 목록에 포함되는 조건을 명시해야 한다

[근거: .planning/phases/82-enviado-online-shipping-control-report/82-01-PLAN.md:40]  
[근거: .planning/phases/82-enviado-online-shipping-control-report/82-01-PLAN.md:55]  
[근거: api-ventago/src/app/online-orders/online-orders.service.ts:1577]  
[근거: api-ventago/src/app/online-orders/online-orders.service.ts:1605]  
[근거: api-ventago/src/app/online-orders/online-orders.service.ts:1732]

문제: `발송됨 AND 미배달`만 사용하면 발송 후 취소된 주문도 `En tránsito`와 `Demorados`에 남는다. 그러나 취소 경로는 발송된 주문의 판매와 재고를 역분개하고 `stock_released_at`도 갱신한다. 따라서 이 주문은 현재 길에 묶인 재고가 아니며 일반 En tránsito 금액에 포함하면 틀린 숫자다.

구체적 대안:

- 현재 En tránsito 정의:
  `shipped_at IS NOT NULL AND delivered_at IS NULL AND cancelled_at IS NULL`
- `Demorados`, 운송사별 미배달 수도 동일한 조건을 공유한다.
- 발송 후 취소 주문은 별도 `Cancelados después del envío` 예외 건수/목록으로 노출한다.
- 데이터 이상 감시를 위해 `cancelled_at IS NOT NULL AND stock_released_at IS NULL` 건수도 별도 진단값으로 제공한다.
- 취소 주문을 정시율에서 제외한 선택은 맞다.

### 4. 매장 타임존 변환 규약이 구현 가능한 수준으로 구체화되지 않았다

[근거: .planning/phases/82-enviado-online-shipping-control-report/82-01-PLAN.md:41]  
[근거: api-ventago/src/app/reports/reportsStocksCockpit.service.ts:208]

문제: “`TODAY_SQL` 규약을 따른다”만으로는 기간 필터가 안전하지 않다. 기존 규약은 `(CURRENT_TIMESTAMP AT TIME ZONE :tz)::date`로 오늘을 계산하지만, Enviado 보고서는 사용자가 보낸 현지 날짜 범위를 UTC `TIMESTAMPTZ`와 비교해야 한다. `shipped_at::date` 또는 세션 타임존 의존 캐스팅을 쓰면 기존 17% 오차가 재발할 수 있다.

구체적 대안:

- 매장의 검증된 IANA 타임존으로 현지 `startDate 00:00`과 `endDate+1 00:00`을 UTC 경계로 변환한다.
- 컬럼에는 함수를 씌우지 않고 `shipped_at >= :fromUtc AND shipped_at < :toUtc`로 비교한다.
- “오늘 경과일”은 `(CURRENT_TIMESTAMP AT TIME ZONE :tz)::date`와 `(shipped_at AT TIME ZONE :tz)::date`의 차이로 정의한다.
- DST 및 자정 전후 주문 테스트를 추가한다.
- 모든 쿼리에 `store_id = :storeId`를 필수 조건으로 넣는다.

## 고치는 게 좋은 것(Should)

### 1. 정시율은 운송 구간과 고객 체감 구간을 분리하는 것이 좋다

[근거: api-ventago/src/app/online-orders/online-orders.service.ts:1023]  
[근거: api-ventago/src/app/online-orders/online-orders.service.ts:1305]

문제: `delivered_at − shipped_at`은 운송사 성과에는 맞지만 매장 준비 지연을 숨긴다. 이를 단순히 “정시배송률”이라고 부르면 고객이 체감하는 전체 주문 시간을 나타내는 것으로 오해할 수 있다.

구체적 대안:

- 주 KPI: `OTD transporte = delivered_at − shipped_at ≤ 5 días`
- 보조 KPI: `Tiempo total = delivered_at − confirmed_at`
- 전체 정시율에도 기준이 필요하다면 별도의 기준을 합의하기 전에는 비율로 만들지 말고 평균·P90 소요일만 표시한다.
- 운송사별 비교에는 반드시 `shipped_at` 기준만 사용한다.

### 2. 구간마다 표본 수와 전체 체인 표본을 함께 표시해야 한다

[근거: .planning/phases/82-enviado-online-shipping-control-report/82-01-PLAN.md:53]

문제: 구간별 결측 제외는 맞지만 분모가 다르므로 평균 네 개의 합이 전체 평균과 일치하지 않는다.

구체적 대안:

- 각 구간에 `avgDays`, `sampleCount`, `missingCount`를 반환한다.
- 화면에 `Promedio, n=8`처럼 표기한다.
- 구간 합계를 전체 평균으로 표시하지 않는다.
- 별도로 모든 필수 타임스탬프가 있는 주문만 사용한 `completeJourneyAvg`와 `completeJourneyCount`를 제공한다.
- 역전된 타임스탬프의 음수 구간은 평균에서 조용히 제외하지 말고 `invalidSequenceCount`로 보고한다.

### 3. “묶인 금액”을 재고가액처럼 표현하면 안 된다

[근거: api-ventago/migrations/phase27-online-orders.sql:39]  
[근거: api-ventago/src/app/online-orders/online-orders.service.ts:1118]  
[근거: api-ventago/src/app/online-orders/online-orders.service.ts:1181]

문제: `SUM(total)`은 고객 청구액/매출액이며 재고 원가가 아니다. 또한 발송 시 `mirror_sale_id`가 생성되고 재고 hold도 판매로 전환되므로 “묶인 재고 금액”이라는 표현은 회계적으로 부정확하다. 같은 보고서가 `online_orders`만 합산하면 내부적인 중복 행은 아니지만, Ventas 보고서와 합산하면 같은 거래를 이중 계상하게 된다.

구체적 대안:

- KPI 명칭을 `Valor de pedidos en tránsito` 또는 `GMV en tránsito`로 바꾼다.
- `SUM(total)`을 유지하되 판매 보고서와 합산하지 말라는 정의를 문서화한다.
- 상품가액만 원하면 `SUM(subtotal - discount)`을 검토하고, 배송비 포함 여부를 화면에 명시한다.
- 실제 재고 원가를 뜻하려면 주문 아이템과 원가 스냅샷이 필요하므로 이번 범위에서 사용하지 않는다.

### 4. 배송비 KPI의 분모와 0/NULL 처리 정의가 필요하다

[근거: api-ventago/migrations/phase27-online-orders.sql:39]  
[근거: .planning/phases/82-enviado-online-shipping-control-report/82-01-PLAN.md:51]

문제: 주문당 배송비가 취소·미발송 주문까지 포함하는지, 무료배송 `0`을 포함하는지 불명확하다. `shipping_cost / total`도 `total=0`이면 0 나눗셈이 생긴다.

구체적 대안:

- 발송 코호트의 취소 제외 주문을 분모로 고정한다.
- 무료배송 0은 실제 비용 데이터인지 고객 청구 배송비인지 구분한다. 현재 컬럼이 고객 청구액이라면 “Costo”보다 `Cargo de envío cobrado`가 정확하다.
- `SUM(shipping_cost) / NULLIF(SUM(total), 0)`으로 비율을 계산한다.
- `AVG(shipping_cost)`와 `SUM(shipping_cost)/COUNT(*)` 중 하나를 명시하고 테스트한다.

### 5. 운송사별 비율에 표본 수와 신뢰도 표시가 필요하다

[근거: .planning/phases/82-enviado-online-shipping-control-report/82-01-PLAN.md:57]  
[근거: .planning/phases/82-enviado-online-shipping-control-report/82-02-PLAN.md:27]

문제: `n=3`의 100%와 `n=14`의 71%를 동등하게 강조하거나 95% 목표선으로 색칠하면 과잉 해석을 유도한다.

구체적 대안:

- 각 운송사 행에 `delivered n / shipped n`을 표시한다.
- 정시율 분모가 10건 미만이면 회색 처리하고 `muestra pequeña` 배지를 붙인다.
- 작은 표본은 순위 산정과 최악 운송사 강조에서 제외한다.
- 95%는 외부 업계 목표가 아니라 내부 참고 목표임을 명시하거나, 근거가 확정되지 않았다면 색상 판정 기준에서 제외한다.

### 6. `hidden`은 모든 탐색 경로에서 일관되게 적용해야 한다

[근거: ventago-app/src/views/reports-v2/ReportsSidebar.tsx:101]  
[근거: ventago-app/src/views/reports-v2/ReportsSidebar.tsx:120]  
[근거: ventago-app/src/views/reports-v2/ReportsSidebar.tsx:130]

문제: 일반 목록만 필터링하면 Reservado가 최근 항목과 즐겨찾기에 계속 노출된다.

구체적 대안:

- `isVisibleReport(entry) => !entry.hidden` 공통 함수를 만들고 일반 목록·검색·최근·즐겨찾기에 모두 적용한다.
- 기존 localStorage 즐겨찾기에 남은 `reservado`도 렌더 단계에서 제거한다.
- 숨김 회귀 테스트에 세 경로를 모두 포함한다.

### 7. 직접 URL 접근 정책을 명시해야 한다

[근거: ventago-app/src/views/reports-v2/registry.ts:385]  
[근거: ventago-app/src/views/reports-v2/ReportsShell.tsx:37]

문제: `REPORTS_BY_SLUG`에는 숨긴 엔트리도 남으므로 `/reportes-v2/reservado` 직접 접근은 계속 가능하다. 현재 셸은 `hidden`이 아니라 권한만 검사한다. 이는 “메뉴에서만 숨김”이라면 정상이나 “기능 비활성화” 요구라면 불충분하다.

구체적 대안:

- 이번 요구를 “탐색 UI에서만 숨김, 기존 권한 보유자의 직접 URL 접근 허용”으로 문서화한다.
- 완전 비활성화가 목적이면 셸에서도 `hidden`을 검사해 다른 보고서로 이동시키거나 404를 표시한다.
- `reporte-reservado` 권한을 남기는 것 자체는 권한 재사용보다 안전하다. 다만 관리자 권한 화면에 폐기된 기능이 계속 나타나는지는 별도로 확인한다.

### 8. 현재 인덱스는 성장 후 발송일 중심 보고서에 부족하다

[근거: api-ventago/migrations/phase27-online-orders.sql:71]  
[근거: api-ventago/migrations/42-02-online-orders-cols.sql:30]

문제: 현재 주요 인덱스는 `(store_id, status)`, `(store_id, created_at)`, `transporte_id`다. 보고서가 `store_id + shipped_at 기간`으로 커지면 전체 매장 주문을 필터링할 수 있다. 단독 `transporte_id`도 멀티테넌트 기간 집계에는 충분하지 않다.

구체적 대안:

- 지금 12건만 보고 성급히 추가하지 말고 데이터 성장 기준과 실행계획을 기록한다.
- 필요 시 `CREATE INDEX CONCURRENTLY ... ON online_orders (store_id, shipped_at DESC) WHERE shipped_at IS NOT NULL`.
- 운송사 집계가 병목이면 `(store_id, transporte_id, shipped_at)`을 검토한다.
- 마이그레이션은 트랜잭션 밖의 `CREATE INDEX CONCURRENTLY`로 작성한다.
- `EXPLAIN`은 12건 환경의 100ms 결과만으로 장기 성능을 보장하지 못하므로 예상 행 수에서도 확인한다.

## 선택(Nice)

### 1. 평균만 아니라 P90을 함께 제공하면 지연 꼬리를 더 잘 보여준다

[근거: .planning/phases/82-enviado-online-shipping-control-report/82-01-PLAN.md:52]

구체적 대안: 평균 배송일 옆에 `P90`을 제공하되 표본이 충분할 때만 표시한다. 지연 주문 몇 건이 중요한 배송 데이터에서는 평균보다 운영적으로 유용하다.

### 2. 데이터 품질 KPI를 작게 추가하는 것이 좋다

[근거: api-ventago/src/app/online-orders/online-order.model.ts:143]

구체적 대안: 다음 이상 건수를 진단 영역에 표시한다.

- `delivered_at < shipped_at`
- `shipped_at < prepared_at`
- `shipped_at IS NOT NULL AND confirmed_at IS NULL`
- 취소됐지만 `stock_released_at IS NULL`
- `transporte_id IS NULL`인데 `shipping_carrier`만 존재
- 발송됐지만 tracking이 없고, 즉시배송 운송사도 아닌 주문

### 3. `Sin tracking`은 즉시배송 운송사를 구분해야 한다

[근거: api-ventago/src/app/online-orders/online-orders.service.ts:1029]

구체적 대안: 즉시배송은 추적번호가 본질적으로 불필요할 수 있으므로 모두 결함으로 세지 말고 `tracking required`인 운송사만 경고 대상으로 삼는다. 그렇지 않으면 정상 즉시배송 주문이 지속적으로 오류처럼 표시된다.
