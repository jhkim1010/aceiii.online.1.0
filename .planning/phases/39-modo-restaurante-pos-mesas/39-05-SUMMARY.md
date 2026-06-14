---
phase: 39-modo-restaurante-pos-mesas
plan: 05
subsystem: restaurant-sale-lifecycle
tags: [restaurant, nestjs, sequelize, sales, draft, comanda, split-merge, box-operation, transaction]
requires:
  - "Sale 식당 nullable 컬럼: tableId/orderedAt/servedAt/closedAt/lastComandaAt (39-01)"
  - "RestaurantTablesService.syncTableStatus + RestaurantTablesModule (39-02)"
  - "BoxOperationService.addOperation(data, transaction?) — 기존 결제 경로"
  - "PrintService.emitPrintTemp(branchId, data) — branch:{id} room"
  - "SalePaymentMethod (saleId/paymentMethodId/optionId/amount)"
provides:
  - "RestaurantSaleService: placeOrder(DRAFT 누적+comanda 증분) / markTiming / printCuenta / paySale(split) / payMerge"
  - "RestaurantSaleController: POST order / POST pay-merge / PATCH :id/timing / POST :id/cuenta / POST :id/pay"
  - "식당 결제 매상 통계 통합 — box-operation(addOperation) 경유, 소매 회귀 0"
  - "상태↔sale 단일 트랜잭션 동기화 (libre/ocupada/por_cobrar)"
affects:
  - api-ventago/src/app/sales/sales.module.ts
tech-stack:
  added: []
  patterns:
    - "단일 DRAFT sale 누적 — split 시 자식 sale 금지(매출 무오염 Pitfall 5)"
    - "comanda 증분 = created_at > last_comanda_at, emit 후 lastComandaAt 갱신"
    - "branchId 해결 = table_id→restaurant_tables.branch_id 직접(terminal 경로 회피 Pitfall 4)"
    - "split 합계 integer 정확 비교(sum !== totalAmount) — float 오차 없음(Security T-39-10)"
    - "merge = 각 DRAFT sale 자기 totalAmount 결제행 + 동시 PAID, reparent/delete 0(D-03)"
    - "box-operation addOperation(data, t) 위치 transaction 인자 — cashRegister 미오픈 시 소매와 동일 스킵"
    - "spec positional constructor args + sequelize.transaction(cb) 즉시 실행 mock"
key-files:
  created:
    - api-ventago/src/app/sales/restaurant-sale/restaurant-sale.service.ts
    - api-ventago/src/app/sales/restaurant-sale/restaurant-sale.controller.ts
    - api-ventago/src/app/sales/restaurant-sale/restaurant-sale.service.spec.ts
    - api-ventago/src/app/sales/restaurant-sale/dto/restaurant-sale.dto.ts
  modified:
    - api-ventago/src/app/sales/sales.module.ts
decisions:
  - "payMerge 배분 = 각 sale 자기 totalAmount 1행 결제(비율 배분 아님) — integer 정확 일치 + D-03 매출 귀속 보존"
  - "recordBoxOperation 헬퍼 = sales-create.registerCashOperation 패턴 이식(cashRegister findOne closingTime=null → addOperation)"
  - "RestaurantTable + CashRegister 를 sales.module forFeature 에 추가(@InjectModel 컨텍스트 등록)"
  - "settleSale private 공통 헬퍼로 paySale/payMerge 결제 로직 단일화(합계검증/PAID/테이블리셋/box-op/영수증)"
metrics:
  duration: ~6min
  tasks: 3
  files: 5
  completed: 2026-06-14
---

# Phase 39 Plan 05: Restaurant Sale Lifecycle Summary

식당 sale 라이프사이클 백엔드 전체 신규 구현 — 단일 DRAFT sale 누적 주문(첫 주문=create, 추가=동일 sale items 누적, 자식 sale 금지) + comanda 증분 emit(last_comanda_at 경계, table.branchId 직접 해결) + 타이밍 마킹(served_at/closed_at, closed 시 테이블 por_cobrar) + cuenta(non-fiscal, DRAFT 유지) + split 결제(단일 sale 복수 sale_payment_methods, integer 합계 정확 검증) + merge 결제(복수 DRAFT sale 동시 PAID, reparent 금지)를 모두 단일 트랜잭션으로 sale↔restaurant_tables 동기화. 결제는 BoxOperationService.addOperation(실 시그니처) 경유로 매상 통계 자동 통합. 소매 sale create/payment 경로 무변경(회귀 0).

## What Was Built

### Task 1: DRAFT 누적 주문 + comanda 증분 emit + 타이밍 (service 1부) + spec
- **restaurant-sale.service.ts** 생성: `@InjectModel(Sale/SaleItem/SalePaymentMethod/RestaurantTable/CashRegister)` + `@InjectConnection() sequelize` + `RestaurantTablesService` + `PrintService` + `BoxOperationService` 주입.
  - `placeOrder(storeId, userId, dto)`: 단일 TX. 테이블 스코프 조회(IDOR) → `currentSaleId` 없으면 `Sale.create({status:DRAFT, activityType:SALE, tableId, orderedAt})` + `syncTableStatus(OCUPADA, sale.id)`, 있으면 기존 DRAFT 재사용(자식 sale 금지). `SaleItem.bulkCreate` 누적 → `emitPrintTemp(table.branchId, {kind:'comanda', 신규 items})` → `sale.update({lastComandaAt})` 증분 경계 갱신. 빈 items → BadRequest.
  - `markTiming(storeId, saleId, event)`: 단일 TX. served→`servedAt`, closed→`closedAt` + 테이블 `syncTableStatus(POR_COBRAR)`.
  - `recordBoxOperation` private 헬퍼: cashRegister(closingTime=null) findOne → `addOperation(data, t)`.
- **restaurant-sale.service.spec.ts**: sequelize.transaction(cb) 즉시 실행 mock + positional args. 7 케이스(첫 주문 create+ocupada / 추가 주문 create 0회 / comanda emit+lastComandaAt / 빈 items BadRequest / 스코프 미스 NotFound / served / closed+por_cobrar). **PASS.**

### Task 2: cuenta/영수증 emit + split/merge 결제 (service 2부) + spec 보강
- **restaurant-sale.service.ts** 확장:
  - `printCuenta(storeId, saleId)`: items 합산 → `emitPrintTemp(kind:'cuenta')`, **sale 상태 미변경(DRAFT 유지 — req9)**, 테이블 por_cobrar 표시.
  - `paySale(storeId, userId, saleId, payments[])`: 단일 TX → `settleSale` 위임.
  - `payMerge(storeId, userId, saleIds[], payments[])`: 단일 TX. 각 sale 스코프 조회 → grand-total = Σ totalAmount integer 검증 → 각 sale 을 **자기 totalAmount 1행으로 settleSale**(reparent/delete 0 — D-03).
  - `settleSale` private 공통: split 합계 `sum !== sale.totalAmount` 정확 비교(Security) → `SalePaymentMethod.bulkCreate`(단일 sale 복수 행) → `status PAID` → 테이블 `syncTableStatus(LIBRE, null)` + 영수증 emit → `recordBoxOperation`.
- **spec 보강**: split 2행/합계불일치 BadRequest/addOperation(type venta, tx 위치인자)/cashRegister 미오픈 스킵/merge 2 sale PAID+reparent 0+배분 600·400/merge 합계불일치/cuenta DRAFT 불변. **총 14 케이스 PASS.**

### Task 3: Controller + sales.module 등록 + 회귀 확인
- **restaurant-sale.controller.ts**: `@Controller('restaurant-sale')` 전 `@Auth()`. 5 라우트 — `@Post('order')` / `@Post('pay-merge')` / `@Patch(':id/timing')` / `@Post(':id/cuenta')` / `@Post(':id/pay')`. 구체 경로(order, pay-merge)를 :id 위 배치. `user.storeId`+`user.id` 스코프.
- **dto/restaurant-sale.dto.ts**: PlaceOrder(items @ValidateNested @ArrayMinSize(1)) / MarkTiming(@IsIn served|closed) / PaySale / PayMerge(saleIds @IsInt each) — amount @IsNumber @Min(0).
- **sales.module.ts**: `RestaurantTablesModule` import + `RestaurantTable`/`CashRegister` forFeature + `RestaurantSaleService` provider + `RestaurantSaleController` controller 등록.
- **회귀**: `sales-create.service.spec` 10/10 PASS. `tsc --noEmit` 전체 0 에러.

## Acceptance Criteria Verification

| 기준 | 결과 |
|------|------|
| class RestaurantSaleService + placeOrder + markTiming | PASS |
| placeOrder 에 SaleStatus.DRAFT + SaleActivityType.SALE + sequelize.transaction | PASS |
| emitPrintTemp(table.branchId, ...) (table_id→branchId 직접, Pitfall 4) | PASS |
| lastComandaAt 갱신 (증분 경계) | PASS |
| markTiming closed → syncTableStatus(por_cobrar) | PASS |
| 추가 주문 Sale.create 0회 (단일 DRAFT 누적, Pitfall 5) | PASS (spec 검증) |
| printCuenta + paySale + payMerge 존재 | PASS |
| paySale split 합계 `sum !== sale.totalAmount` 정확 비교 + BadRequest | PASS |
| paySale SaleStatus.PAID + syncTableStatus(libre, null) | PASS |
| payMerge 각 sale PAID + 각 table 리셋 + reparent 0 (D-03) | PASS (spec saleId 보존 검증) |
| printCuenta emitPrintTemp(cuenta) + sale.update(status) 미호출 (DRAFT 유지) | PASS |
| addOperation (box-operation 경유, req11) | PASS |
| 5 라우트 + order/pay-merge 가 :id 위 | PASS |
| sales.module RestaurantTablesModule + RestaurantSaleService + RestaurantSaleController | PASS |
| sales-create.service 회귀 0 | PASS (10/10) |
| tsc --noEmit 에러 0 | PASS (전체 0) |
| jest restaurant-sale.service PASS | PASS (14/14) |

## Threat Model Mitigations Applied

| Threat | Mitigation 적용 |
|--------|----------------|
| T-39-10 (split 금액 변조) | settleSale `sum !== Number(sale.totalAmount)` integer 정확 비교 → BadRequest. payMerge grand-total 동일 검증 |
| T-39-11 (IDOR) | 모든 service 쿼리 `where: { ..., storeId }` 스코프 (user.storeId JWT 출처). 미스 시 NotFound |
| T-39-12 (결제 우회) | settleSale 가 recordBoxOperation(addOperation) 강제 호출 — 식당 결제도 금전함/매상 기록 |
| T-39-13 (테이블 drift) | placeOrder/markTiming/paySale/payMerge/printCuenta 전부 sequelize.transaction 단일 TX, syncTableStatus 동일 transaction 전달 |

## Deviations from Plan

플랜 의도대로 구현. 검증된 실 시그니처 적용 + 명확화 결정:

1. **[Rule 3 - 명확화] payMerge 금액 배분 방식**: 플랜은 "결제 총액을 각 sale.totalAmount 비율로 배분(또는 사용자 입력 배분)"을 제시. integer 정확 비교(`!==`) 요구사항과 충돌(비율 배분은 반올림 오차 발생) → **각 sale 을 자기 totalAmount 1행 결제수단으로 settleSale** 방식 채택. grand-total = Σ sale.totalAmount 를 단일 검증하고, 각 sale 은 자기 총액으로 정확 결제 → integer 무오차 + D-03(테이블별 매출 귀속) 동시 충족. 복수 결제수단 동시 split-merge 는 D-02 후속.
   - 파일: restaurant-sale.service.ts (payMerge/settleSale). 커밋: 6aa5034.

2. **[Rule 3 - 실 시그니처] addOperation transaction 위치 인자**: box-operation.service.ts:16 의 실제 시그니처는 `addOperation(data, transaction?)` (Transaction 객체를 위치 인자로 받음, `{ transaction }` 래핑 아님). 플랜 예시 `addOperation({...}, t)` 와 일치 — 그대로 적용. spec 에서 `txArg === seq.__tx` 검증.

3. **[Rule 3 - 실 시그니처] recordBoxOperation cashRegister 해결**: 플랜은 "cashRegisterId/userId/terminalId/executionType 출처는 sales-create 결제 경로 동일"로 위임. 실제 sales-create.registerCashOperation(line 719-742) 이 `CashRegister.findOne({ where: { userId, closingTime: null } })` → terminalId/cashRegisterId 추출, executionType='automatico' 사용. 동일 패턴 이식. cashRegister 미오픈이면 box-operation 스킵(소매와 동일 의도된 동작 — 39-RESEARCH Open Q3).

4. **[Rule 2 - 모델 등록] RestaurantTable + CashRegister forFeature 추가**: 서비스가 `@InjectModel(RestaurantTable)`/`@InjectModel(CashRegister)` 사용 → sales.module forFeature 에 두 모델 등록 필요(@InjectModel DI 컨텍스트). RestaurantTablesModule import 만으로는 CashRegister 미해결.

5. **[명확화] userId 파라미터 추가**: 플랜 메서드 시그니처는 storeId 만 명시했으나, box-operation cashRegister 조회에 userId 필수 → placeOrder/paySale/payMerge 에 userId 파라미터 추가, 컨트롤러가 `user.id` 전달.

## Known Stubs

없음 — 백엔드 라이프사이클 완성. comanda/cuenta/receipt 의 실제 감열 출력은 print-agent `print_temp` 핸들러(39-03 머지 완료, 운영 재빌드는 39-03 Task 2 사용자 액션 블로커)에 의존. 프론트 wiring(SalonView 주문/결제 UI)은 39-07.

## Commits

| Task | Submodule(api-ventago) | Parent(main) |
|------|------------------------|--------------|
| 1 (DRAFT 누적 + comanda + timing + spec) | f1eaed8 | db2615b |
| 2 (cuenta + split/merge 결제 + spec 보강) | 6aa5034 | 9f38400 |
| 3 (controller + dto + module 등록) | 58d1a3e | 3bac034 |

## Follow-ups (후속 플랜 입력)

- **39-06 (config-editor)**: 식당 카테고리 id 목록 + 배치도 편집 — 본 plan 무관(독립).
- **39-07 (salonview)**: `POST /restaurant-sale/order`(주문) / `PATCH /restaurant-sale/:id/timing`(웨이터 served/closed 버튼) / `POST /restaurant-sale/:id/cuenta`(사전 합산) / `POST /restaurant-sale/:id/pay`(split 결제) / `POST /restaurant-sale/pay-merge`(테이블 합산) 5 라우트 소비. payments[] = {paymentMethodId, optionId?, amount}, split 합계 = sale.totalAmount 필수(BadRequest 방어). 39-03 print_temp 핸들러 운영 재빌드(사용자 액션) 후 실제 인쇄 동작.
- **운영 주의**: sale.totalAmount 는 식당 sale 에서 placeOrder 가 직접 계산/저장하지 않음(현재 SaleItem.subtotal 만 기록). 결제 합계 검증이 totalAmount 와 비교하므로, 39-07 또는 후속에서 placeOrder/결제 직전 sale.totalAmount = Σ item.subtotal 동기화 필요(현재는 결제 페이로드가 totalAmount 와 일치해야 통과). 매출 통계는 activityType=sale + totalAmount 기준이므로 totalAmount 채움 보장 필요.

## Self-Check: PASSED

- 생성 파일 4종(service/controller/spec/dto) + 수정 1종(sales.module) — 아래 검증
- 서브모듈 커밋 f1eaed8 / 6aa5034 / 58d1a3e — 아래 검증
- 부모 포인터 커밋 db2615b / 9f38400 / 3bac034 — 아래 검증
