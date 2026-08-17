# CODEX 검토 결과 — Phase 80 Talleres WIP 노출 (2026-08-17)

요청서: `.gsd/review-request-phase80-talleres-wip.md`

## 총평

현재 W1 초안은 그대로 구현하면 안 됩니다. 가장 큰 문제는 `열린 envío의 pending_quantity 합`이 사용자가 말한 “생산 과정에 들어간 전체 수량”과 동일하지 않고, 로트마다 공정 진행 위치와 ETA가 하나라는 전제도 분할 발송·재작업 구조에서는 성립하지 않는다는 점입니다.

권한 역시 기존 `getItems()` 응답에 필드를 무조건 추가하고 프런트에서 열만 숨기는 방식으로는 보호되지 않습니다. 서버가 권한에 따라 WIP 조회·응답·정렬·PDF를 모두 제한해야 합니다.

균등 분배 자체는 사용자 결정대로 구현할 수 있지만, API 필드와 화면 모두 “계획 수량”이 아니라 “기계적으로 나눈 추정치”임을 명시하고, 나머지 배분 규칙과 대상 지점 집합을 고정해야 합니다.

## 반드시 고쳐야 할 것(Blocker)

### 1. `wip_qty = 열린 envío.pending_quantity 합`은 요구사항의 WIP 전체 수량이 아니다

[근거: api-ventago/src/app/subcon/envios/envio.service.ts:164]  
[근거: api-ventago/src/app/subcon/recepciones/recepcion.service.ts:197]  
[근거: api-ventago/src/app/subcon/lotes/lote.model.ts:47]

발송 시 `available_quantity`가 감소하고, 수령 시 `pending_quantity`가 감소합니다. 따라서 한 공정에서 수령됐지만 다음 공정으로 아직 발송되지 않은 수량은 열린 envío 합에서 사라집니다. 그러나 그 수량은 이미 생산에 들어간 WIP입니다.

`no_iniciado = total_quantity − stocked_quantity − open_pending`도 실제로는 “미착수”가 아니라 다음 상태가 섞입니다.

- 아직 한 번도 발송되지 않은 수량
- 중간 공정에서 돌아와 다음 발송을 기다리는 수량
- 최종 수령됐지만 재고 원장 반영이 `PENDING`인 수량
- 불량 판정 후 재작업 여부가 결정되지 않은 수량

구체적 대안:

- 최소한 API 의미를 분리합니다.
  - `estimatedWipTotalQty = max(total_quantity - stocked_quantity, 0)`
  - `inWorkshopQty = 열린 envío pending 합`
  - `betweenStagesQty = estimatedWipTotalQty - inWorkshopQty`는 정확한 상태를 보장할 수 없으므로 `unassignedInProcessQty`처럼 제한적인 이름을 사용합니다.
- “생산 시작”을 최초 envío 생성으로 정의한다면 envío가 한 번이라도 존재하는 로트만 WIP 로트로 포함합니다.
- `inventory_status='PENDING'`인 최종 수령은 이미 완성됐지만 재고 미반영인 별도 상태로 노출하거나 WIP 합계에서 명시적으로 분리합니다. 해당 상태가 재고 누락을 나타낸다는 기존 정의가 있습니다. [근거: api-ventago/src/app/subcon/recepciones/recepcion.model.ts:17]
- `no_iniciado`라는 필드명은 현재 계산으로 사용하지 마십시오.

### 2. 로트마다 단일 “현재 공정”과 단일 `etapas_restantes`를 산출하면 분할 발송에서 조용히 틀린다

[근거: api-ventago/src/app/subcon/envios/envio.model.ts:56]  
[근거: api-ventago/src/app/subcon/envios/envio.model.ts:59]  
[근거: api-ventago/src/app/subcon/lotes/routing-position.ts:107]

한 로트의 서로 다른 수량 묶음이 동시에 여러 공정에 있을 수 있으므로 로트 전체의 현재 공정은 존재하지 않습니다. `MIN(order)`, `MAX(order)` 또는 가장 최근 envío 하나를 선택하면 일부 수량의 상태가 전체 수량에 적용됩니다.

구체적 대안:

- 열린 envío 각각을 `(lote_id, etapa_id, pending_quantity)` 단위의 WIP cohort로 취급합니다.
- `routing_path`는 기존 `checkRoutingCanonical()`과 동일한 조건으로 검증하고, 비정상이거나 etapa가 경로에 없으면 해당 cohort의 ETA를 `UNKNOWN`으로 둡니다. SQL에서 단순히 JSON 길이와 `order`만 신뢰하지 마십시오. [근거: api-ventago/src/app/subcon/lotes/routing-position.ts:49]
- 제품 단위 응답에는 다음처럼 상태를 보존합니다.
  - `estimatedWipQty`
  - `etaKnownQty`
  - `etaUnknownQty`
  - `estimatedReadyDate`
  - `etaStatus: KNOWN | PARTIAL | UNKNOWN | OVERDUE`
- 여러 cohort 중 하나라도 ETA를 계산할 수 없다면 전체 제품 ETA를 확정 날짜처럼 표시하지 말고 `PARTIAL` 또는 `미정 포함`으로 표시합니다.

### 3. `max(due_date)`를 완성 예정일로 사용하는 것은 의미가 맞지 않는다

[근거: api-ventago/src/app/subcon/envios/envio.model.ts:62]  
[근거: api-ventago/src/app/subcon/envios/envio.service.ts:328]

`due_date`는 현재 envío 공정의 예정 반환일입니다. 최종 공정이면 완성 예상일로 볼 수 있지만, penúltima 공정의 `due_date`는 마지막 공정 시작 전 날짜일 뿐입니다. 마지막 공정의 소요시간 데이터가 없으므로 완성일을 계산할 근거가 없습니다.

구체적 대안:

- 최종 공정의 열린 envío만 `estimatedReadyDate = due_date`로 표시합니다.
- penúltima 공정은 날짜를 보여주더라도 `Próximo hito` 또는 `Retorno de etapa`로 표시하고 “완성 예정일”로 부르지 않습니다.
- 사용자 요구상 penúltima에도 날짜가 반드시 필요하다면 필드명을 `estimatedReadyDate`로 만들지 말고 다음처럼 사실과 추정을 분리합니다.
  - `sourceDueDate`
  - `etaBasis: FINAL_STAGE_DUE | PENULTIMATE_STAGE_DUE`
  - `etaConfidence: APPROXIMATE`
- 과거 due date는 날짜를 미래 ETA처럼 출력하지 말고 `OVERDUE`와 원래 날짜를 함께 반환해 화면에서 `Atrasado desde YYYY-MM-DD`로 표시합니다.
- 여러 최종 공정 cohort가 있을 때만 `MAX(due_date)`를 “전량 완료 예상일”로 사용할 수 있습니다. 일부 cohort가 penúltima 이하 또는 due date 없음이면 전체 날짜는 `PARTIAL`입니다.

### 4. 신규 권한을 기존 엔드포인트의 단일 `@FunctionGuard`만으로 처리할 수 없다

[근거: api-ventago/src/app/reports/reports.controller.ts:1074]  
[근거: api-ventago/src/app/auth/decorators/function-guard.decorator.ts:10]  
[근거: api-ventago/src/app/reports/reports.controller.ts:1674]

기존 items 엔드포인트는 `reporte-stocks` 권한 사용자가 모두 접근합니다. 여기에 신규 WIP 필드를 무조건 반환하면 프런트 열 숨김과 무관하게 네트워크 응답에서 읽을 수 있습니다. 반대로 엔드포인트 전체에 신규 권한 guard를 붙이면 기존 Stocks 사용자가 기본 표까지 잃습니다.

또한 `FunctionGuard`는 단일 `required_function` 메타데이터만 설정하므로 데코레이터를 두 번 붙이는 방식도 안전한 AND/optional-field 권한 모델이 아닙니다.

구체적 대안:

- 가장 안전한 방식은 WIP 전용 엔드포인트를 분리하는 것입니다.
  - `/reports/stocks-cockpit/items-wip`
  - 신규 `@FunctionGuard('<wip-slug>', 'read')`
  - 기본 items 결과와 프런트에서 productId로 결합
- 한 엔드포인트를 유지하려면 서버에서 별도로 capability를 조회해 `canViewWip`을 서비스에 전달하고, false이면 WIP CTE 자체를 실행하지 않으며 응답 객체에도 해당 키를 넣지 않습니다.
- 정렬 허용 목록도 권한별로 구성해야 합니다. 무권한 사용자가 `sortBy=estimatedWipQty`를 보내 값의 상대 순서를 추론할 수 없어야 합니다.
- PDF 엔드포인트에도 신규 권한 검사를 독립 적용해야 합니다. 현재 PDF는 같은 export 조회와 고정 컬럼 정의를 사용합니다. [근거: api-ventago/src/app/reports/reports.controller.ts:1685] [근거: api-ventago/src/app/reports/reports.controller.ts:1733]
- Excel/CSV 경로가 별도로 있다면 동일하게 서버 권한을 검사해야 합니다. 프런트에서 버튼만 숨기는 것은 충분하지 않습니다.

### 5. 균등 분배의 대상 지점과 나머지 규칙을 고정하지 않으면 합계가 일치하지 않는다

[근거: api-ventago/src/app/subcon/recepciones/recepcion.model.ts:67]  
[근거: .planning/intel/db-schema-tables.md:2723]

실제 지점은 수령 시 `target_branch_id`로 처음 정해집니다. 따라서 WIP 단계의 지점별 수량은 실제 배분이 아니라 파생 추정치입니다.

구체적 대안:

- API 필드명을 `estimatedBranchWipQty`로 하고 `wipQty`처럼 사실을 암시하는 이름을 쓰지 않습니다.
- 응답에 근거를 함께 반환합니다.
  - `allocationMethod: EQUAL_ESTIMATE`
  - `allocationBranchCount`
  - `allocationAsOf`
  - `isEstimated: true`
- 대상 지점은 “해당 store의 활성 재고 지점”처럼 명시적으로 정의하고, 전체/비활성/가상 지점 포함 여부를 고정합니다.
- 정수 수량은 다음 결정적 규칙으로 나눕니다.
  - `base = floor(total / N)`
  - `remainder = total % N`
  - 안정적인 `branch_id ASC` 순서의 앞 `remainder`개 지점에 1개씩 추가
- 각 지점 API가 독립 호출되더라도 동일한 전체 지점 목록과 순위를 사용해야 합니다. 그래야 모든 지점의 합이 TOTAL과 정확히 같습니다.
- UI에는 값마다 `≈`를 붙이고 툴팁에 “Distribución estimada en partes iguales; no es una asignación confirmada”를 표시합니다.
- TOTAL 행에는 원본 수량을 표시하고 “균등 분배된 값들의 합”을 다시 합산하지 않습니다.
- `storeId=null`인 전 매장 뷰에서는 매장 경계를 넘어 지점 수를 나누지 말고 store별 계산 후 합산해야 합니다.

### 6. CodigoMadre/variant 모집단과 WIP의 `product_id`를 그대로 조인하면 누락 또는 중복될 수 있다

[근거: api-ventago/src/app/reports/reportsStocksCockpit.service.ts:745]  
[근거: api-ventago/src/app/reports/reportsStocksCockpit.service.ts:750]  
[근거: api-ventago/src/app/subcon/lotes/lote.model.ts:40]

Panel B의 한 행은 뷰에 따라 leaf 제품 또는 family 제품을 대표하며, 실제 집계 모집단은 `v_product_hijo`가 정의합니다. 반면 로트는 단일 `product_id`를 가집니다. WIP CTE를 `wip.product_id = p.id`로 단순 조인하면 CodigoMadre 뷰에서 자식 로트가 빠지거나, 데이터가 madre/leaf 양쪽에 존재할 때 결과가 불일치할 수 있습니다.

구체적 대안:

- 기존 `groupLeafIds`와 동일한 제품 모집단을 WIP에도 적용합니다.
- variante 뷰는 `lote.product_id = hijo_id`, CodigoMadre 뷰는 로트 제품을 동일 family로 정규화한 뒤 family 단위로 집계합니다.
- 로트가 madre에 직접 연결될 수 있는지 데이터 불변식을 확인하고, 가능하다면 명시적인 포함 정책과 회귀 테스트를 추가합니다.
- 테스트에는 단품, madre+여러 leaf, leaf별 로트, madre 직접 로트를 각각 포함해야 합니다.

## 고치는 게 좋은 것(Should)

### 1. 재작업 수량을 일반 진행 수량과 구분하라

[근거: api-ventago/src/app/subcon/envios/envio.model.ts:96]  
[근거: api-ventago/src/app/subcon/envios/envio.service.ts:365]

수령 시 `received + rejected`만큼 부모 envío pending이 감소하고 재작업 child envío가 생성되므로 정상 트랜잭션에서는 단순 합계가 즉시 이중 계산되지는 않습니다. 다만 재작업은 routing의 “현재 위치가 앞으로 진행한다”는 전제를 깨뜨립니다.

구체적 대안:

- `rework_order_id IS NOT NULL` 또는 재작업 연결 관계를 기준으로 `reworkQty`를 별도 집계합니다.
- 재작업 cohort는 routing 단계 수만으로 ETA 신뢰도를 높이지 말고 `etaStatus=UNKNOWN` 또는 별도 정책을 사용합니다.
- `estimatedWipQty`에는 포함하되 화면 툴팁에 `Incluye N en retrabajo`를 표시하는 것이 안전합니다.

### 2. WIP CTE는 먼저 store/product 단위로 축소한 후 본 쿼리에 조인하라

[근거: api-ventago/src/app/reports/reportsStocksCockpit.service.ts:750]  
[근거: api-ventago/src/app/reports/reportsStocksCockpit.service.ts:927]

현재 본 쿼리는 `ProductBranch × stocks`로 이미 행이 증가합니다. 여기에 envío 원본 행을 직접 LEFT JOIN하면 stocks와 envíos가 서로 곱해져 양쪽 집계가 중복될 수 있습니다.

구체적 대안:

- `talleres_envios → talleres_lotes`를 별도 CTE에서 `store_id, product_id` 또는 family 키로 먼저 한 행으로 집계합니다.
- 그 집계 결과만 본 쿼리에 LEFT JOIN합니다.
- WIP 컬럼은 본 쿼리의 `SUM()` 대상에 다시 넣지 말고 이미 집계된 값을 `MAX()` 또는 GROUP BY 값으로 취급합니다.
- rows 쿼리와 count 쿼리 중 count 쿼리에는 WIP CTE를 넣지 마십시오.

### 3. 인덱스는 운영 계획을 확인한 뒤 새 파일로 추가하라

[근거: .planning/intel/db-schema-tables.md:2690]  
[근거: .planning/intel/db-schema-tables.md:2723]

현재 규모에서는 체감 문제가 작지만 export는 최대 약 2,001행을 읽고, 앞으로 envíos가 누적되면 열린 상태 필터와 lote 조인이 병목이 됩니다. 기존 `(store_id, status, priority, due_date)` 인덱스는 `lote_id` 조인에 최적이지 않습니다.

구체적 대안:

- `EXPLAIN (ANALYZE, BUFFERS)`로 확인한 뒤 다음 형태의 부분 인덱스를 검토합니다.
  - `talleres_envios(store_id, lote_id, etapa_id) WHERE status IN ('PENDING','PARTIAL')`
  - `talleres_lotes(store_id, product_id)`
- 운영 인덱스는 새 마이그레이션에서 `CREATE INDEX CONCURRENTLY`로 생성하고 트랜잭션 블록 밖에서 실행합니다.
- 현재 5개 로트만을 근거로 인덱스를 생략하지 말고 예상 성장량과 100ms 쿼리 기준으로 판단해야 합니다.

### 4. 결측·불변식 위반을 0으로 조용히 바꾸지 마라

[근거: api-ventago/src/app/subcon/lotes/routing-position.ts:31]  
[근거: api-ventago/src/app/subcon/envios/envio.model.ts:59]

구체적 대안:

- 다음 상태는 `0`이나 정상 날짜 대신 진단 상태로 반환합니다.
  - routing 없음/비정규
  - 열린 envío의 etapa가 routing에 없음
  - `pending_quantity < 0`
  - 열린 상태인데 `pending_quantity = 0`
  - `stocked_quantity > total_quantity`
  - 열린 envío 합이 `total_quantity - stocked_quantity`보다 큼
- 응답에 내부 ID나 상세 원인을 과도하게 노출할 필요는 없지만 `dataQuality: OK | PARTIAL | INVALID` 정도는 있어야 합니다.
- INVALID 값은 화면에 `—`와 경고 툴팁으로 표시하고 운영 로그/모니터링에 남깁니다.

### 5. 권한 변경 시 프런트 캐시와 이전 응답을 고려하라

[근거: ventago-app/src/views/reports/stocks/panels/PanelB_ItemTable.tsx:110]  
[근거: ventago-app/src/views/reports/stocks/panels/PanelB_ItemTable.tsx:245]

사용 중 권한이 회수됐는데 기존 rows 상태가 남으면 화면에서 이전 민감 정보가 계속 보일 수 있습니다.

구체적 대안:

- 권한 상태가 false로 바뀌면 WIP rows/cache를 즉시 폐기합니다.
- WIP 전용 요청이 403이면 열과 관련 정렬 상태를 제거합니다.
- `localStorage`에 저장된 WIP 정렬값이 무권한 세션에서 재사용되지 않도록 기본 정렬로 복구합니다.

### 6. 테스트가 계산 정의를 고정해야 한다

구체적 대안:

- 1,000/2, 1,000/3 및 지점 비활성화 사례
- 한 로트가 두 공정에 분할되어 동시에 열려 있는 사례
- 중간 수령 후 다음 발송 전 수량
- 일반 envío와 rework envío 동시 존재
- due date 일부 NULL, 일부 과거, 일부 미래
- canonical하지 않은 routing
- 권한 없음 상태의 JSON 키 부재, 정렬 차단, PDF 컬럼 부재
- CodigoMadre/variant 양쪽 뷰의 동일 모집단
- TOTAL과 모든 지점 추정치 합의 정확한 일치

## 선택(Nice)

### 1. 날짜 하나보다 범위와 신뢰도를 표시하라

`Listo aprox.`에 단일 날짜만 보여주기보다 다음 표현이 현실에 더 맞습니다.

- `18–22 ago · estimado`
- `Atrasado desde 15 ago`
- `Parcial: 300 con fecha, 200 sin fecha`
- `Sin estimar`

### 2. 추정치의 계산 시점을 표시하라

W1도 응답 생성 시각인 `estimatedAt`을 제공하면 사용자가 오래 열린 화면의 값을 최신 정보로 오해하는 것을 줄일 수 있습니다. W2에서 수동 ETA가 추가되면 `etaUpdatedAt`과 `etaSource: MANUAL | ENVIO_DUE`를 구분하십시오.

### 3. WIP 상세 드릴다운을 제공하라

합계 옆 툴팁이나 상세창에서 `공정별 수량 / 재작업 수량 / 날짜 미정 수량`을 보여주면 단일 추정값의 오해를 줄일 수 있습니다. 단, 동일 신규 권한으로 보호해야 합니다.
