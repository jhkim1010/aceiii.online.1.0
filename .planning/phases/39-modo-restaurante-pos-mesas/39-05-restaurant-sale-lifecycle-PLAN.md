---
phase: 39-modo-restaurante-pos-mesas
plan: 05
type: execute
wave: 3
depends_on: [39-01, 39-02]
files_modified:
  - api-ventago/src/app/sales/restaurant-sale/restaurant-sale.service.ts
  - api-ventago/src/app/sales/restaurant-sale/restaurant-sale.controller.ts
  - api-ventago/src/app/sales/restaurant-sale/restaurant-sale.service.spec.ts
  - api-ventago/src/app/sales/sales.module.ts
autonomous: true
requirements: [REQ-6, REQ-7, REQ-8, REQ-9, REQ-10, REQ-11]
must_haves:
  truths:
    - "같은 테이블 2회+ 주문 시 단일 DRAFT sale 에 items 가 누적되고 결제 시 DRAFT→PAID 전환된다"
    - "주문 확정 시 branch:{id} room 으로 comanda print emit (새 items 만, 테이블명/웨이터/품목/수량 포함)"
    - "웨이터 버튼이 served_at/closed_at 를 sale 행에 타임스탬프로 기록한다"
    - "결제 전 cuenta(DRAFT 유지) + 결제 후 영수증(PAID 후) resumen 출력"
    - "split=단일 sale 복수 sale_payment_methods, merge=복수 sale 동시 PAID + 금액 배분"
    - "테이블 상태(libre/ocupada/por_cobrar)와 current_sale_id 가 트랜잭션으로 sale 과 동기화된다"
  artifacts:
    - path: "api-ventago/src/app/sales/restaurant-sale/restaurant-sale.service.ts"
      provides: "DRAFT 누적 + 타이밍 + comanda/resumen emit + split/merge 결제 + 상태 동기화"
      contains: "class RestaurantSaleService"
    - path: "api-ventago/src/app/sales/restaurant-sale/restaurant-sale.controller.ts"
      provides: "주문/타이밍/cuenta/결제 라우트"
      exports: ["RestaurantSaleController"]
  key_links:
    - from: "restaurant-sale.service.ts"
      to: "restaurant_tables.branch_id"
      via: "table_id → branchId 직접 해결 후 emitPrintTemp"
      pattern: "emitPrintTemp"
    - from: "restaurant-sale.service.ts"
      to: "RestaurantTablesService.syncTableStatus"
      via: "트랜잭션 내 상태 동기화"
      pattern: "syncTableStatus"
---

<objective>
식당 sale 라이프사이클 백엔드 전체: (1) DRAFT sale 누적 + comanda 증분 emit(req6/8), (2) 타이밍 마킹 PATCH(req7), (3) resumen cuenta/영수증 emit(req9), (4) split/merge 결제(req10) — 기존 sale_payment_methods + box-operation 결제 경로 경유로 매상 통계 자동 통합(req11). 모든 상태 전이는 restaurant_tables 동기화와 단일 트랜잭션.

Purpose: SalonView(39-07)의 모든 액션(주문/타이밍/cuenta/결제)이 호출하는 백엔드. drift 방지(Pitfall 3)와 매출 무오염(Pitfall 5)이 핵심.
Output: RestaurantSaleService + Controller + sales.module 등록 + spec.

NOTE (wave 3): 이 플랜은 39-02 (RestaurantTablesService.syncTableStatus + RestaurantTablesModule)를 직접 import/DI 한다. 39-02 가 wave 2 이므로 이 플랜은 wave 3 (39-02 이후 직렬). 39-01(wave 1) 컬럼/모델 + 39-02(wave 2) 서비스/모듈 산출물이 디스크에 존재해야 실행 가능.
NOTE (box-operation 전제): box-operation 금전함 기록은 **열린 cashRegister(closingTime=null)** 가 존재해야 동작한다 (sales-create.service.ts:730). 식당 결제 시 box(금전함)가 미오픈이면 금전함 기록이 스킵된다 — sale 의 DRAFT→PAID 전환과 sale_payment_methods INSERT 는 정상 수행되나 BoxOperation 행은 생성되지 않을 수 있음. 소매 결제 경로와 동일한 동작이므로 의도된 동작(우회 아님).
</objective>

<execution_context>
@/Users/marcoskim/Trabajos_Programming/ACE_online_1.0/.claude/get-shit-done/workflows/execute-plan.md
@/Users/marcoskim/Trabajos_Programming/ACE_online_1.0/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/phases/39-modo-restaurante-pos-mesas/39-SPEC.md
@.planning/phases/39-modo-restaurante-pos-mesas/39-CONTEXT.md
@.planning/phases/39-modo-restaurante-pos-mesas/39-RESEARCH.md
@CLAUDE.md

<interfaces>
<!-- 재사용 대상 컨트랙트 (코드베이스 + 39-01/39-02 산출) — 직접 사용 -->
Sale (sales.model.ts) — 39-02 추가 컬럼: tableId?, orderedAt?, servedAt?, closedAt?, lastComandaAt?
  SaleStatus.DRAFT = 'Borrador'. SaleActivityType.SALE='sale' (매출 필터 — 식당 sale 도 SALE 유지).
SalePaymentMethod (sales-payment-methods/sales-payment-method.model.ts):
  { saleId, paymentMethodId, optionId?, amount }  // 실제 모델 필드는 optionId (DB option_id 컬럼)
  split = 한 sale 에 복수 INSERT, merge = 복수 sale 에 동시 INSERT.
print.service.ts: emitPrintTemp(branchId: number, data: any): void  → branch:{id} room 'print_temp' emit.
sales-create.service.ts:830 resolveSaleBranchId(sale) — terminal→box→branch (식당은 table_id→branch 더 정확, Pitfall 4).
BoxOperationService (box-operation/box-operation.service.ts:16):
  addOperation(data, transaction?): Promise<BoxOperation>
  data = { cashRegisterId, userId, terminalId, amount, type, executionType, description }
  (sales.module.ts 에 BoxOperationModule/Service 이미 등록됨 — 재사용. 열린 cashRegister 필요.)
RestaurantTablesService (39-02): syncTableStatus(table, status, currentSaleId, {transaction}).
RestaurantTable (39-01): { branchId, status, currentSaleId } + TableStatus enum.
box-operation 결제 경로: 소매 결제가 BoxOperationService.addOperation 로 금전함 기록 → 식당도 동일 경로 경유 (Open Q3: 우회 금지, 매상 통계 통합).
</interfaces>
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: DRAFT 누적 주문 + comanda 증분 emit + 타이밍 PATCH (service 1부) + spec</name>
  <read_first>
    - api-ventago/src/app/sales/sales-create.service.ts (DRAFT 생성, SaleItem bulkCreate, resolveSaleBranchId line 830, emitPrintTemp 호출, sequelize.transaction 패턴)
    - api-ventago/src/app/sales/sales.model.ts (39-02 컬럼 + SaleStatus/SaleActivityType)
    - api-ventago/src/app/restaurant-tables/restaurant-tables.service.ts (39-02 syncTableStatus + findOne 스코프)
    - api-ventago/src/app/print/print.service.ts (emitPrintTemp signature)
    - 39-RESEARCH.md Code Examples (DRAFT 누적) + Pitfall 3/4 (drift, branchId 해결) + Open Q2 (lastComandaAt 증분 경계)
  </read_first>
  <behavior>
    - placeOrder(첫 주문): table.currentSaleId 없음 → Sale.create({status:DRAFT, activityType:'sale', tableId, sellerId, orderedAt:now}) + SaleItem.bulkCreate + table.syncTableStatus('ocupada', sale.id) — 전부 단일 TX
    - placeOrder(추가 주문): 기존 DRAFT sale 에 SaleItem.bulkCreate (단일 sale 누적, 자식 sale 금지)
    - comanda emit: branchId = table.branchId 직접 해결(terminal 경로보다 신뢰), emitPrintTemp(branchId, {kind:'comanda', tableName, sellerName, items: 새 items, qty}). 새 items = created_at > sale.lastComandaAt. emit 후 sale.lastComandaAt = now.
    - markTiming(saleId, event): event='served' → servedAt=now, event='closed' → closedAt=now + table.status='por_cobrar'. 단일 컬럼 UPDATE.
  </behavior>
  <action>
신규 폴더 api-ventago/src/app/sales/restaurant-sale/. **restaurant-sale.service.ts** (@Injectable, @InjectModel(Sale)/(SaleItem)/(RestaurantTable) + @InjectConnection sequelize + RestaurantTablesService + PrintService 주입):

`placeOrder(storeId, dto: { tableId, sellerId, items: {productId, qty, price, variant?}[] })`:
```typescript
return this.sequelize.transaction(async (t) => {
  const table = await this.tableModel.findOne({ where: { id: dto.tableId, storeId }, transaction: t });
  if (!table) throw new NotFoundException('테이블 없음');

  let sale;
  if (!table.currentSaleId) {
    // 첫 주문 — DRAFT sale 생성 (activityType SALE 유지 → 매상 통계 통합)
    sale = await this.saleModel.create({
      status: SaleStatus.DRAFT, activityType: SaleActivityType.SALE,
      tableId: table.id, sellerId: dto.sellerId, storeId, orderedAt: new Date(),
    }, { transaction: t });

    await this.tableService.syncTableStatus(table, 'ocupada', sale.id, { transaction: t });
  } else {
    sale = await this.saleModel.findByPk(table.currentSaleId, { transaction: t });
  }

  // 새 items 누적 (단일 sale — split 시 자식 sale 안 만듦)
  const created = await this.saleItemModel.bulkCreate(
    dto.items.map((i) => ({ saleId: sale.id, productId: i.productId, quantity: i.qty, price: i.price })),
    { transaction: t },
  );

  // comanda 증분 emit: branchId = table.branchId 직접 (Pitfall 4)
  this.printService.emitPrintTemp(table.branchId, {
    kind: 'comanda', tableName: table.name, sellerName: dto.sellerName,
    items: created.map((c) => ({ name: c.productId, qty: c.quantity })),
  });

  await sale.update({ lastComandaAt: new Date() }, { transaction: t });

  return sale;
});
```
(emitPrintTemp 은 fire-and-forget — TX 커밋 전 emit 되어도 OK; 엄격히 하려면 t.afterCommit 사용 가능. 우선 동작.)

`markTiming(storeId, saleId, event: 'served'|'closed')`:
```typescript
return this.sequelize.transaction(async (t) => {
  const sale = await this.saleModel.findOne({ where: { id: saleId, storeId }, transaction: t });
  if (!sale) throw new NotFoundException();
  if (event === 'served') await sale.update({ servedAt: new Date() }, { transaction: t });
  if (event === 'closed') {
    await sale.update({ closedAt: new Date() }, { transaction: t });
    const table = await this.tableModel.findByPk(sale.tableId, { transaction: t });
    if (table) await this.tableService.syncTableStatus(table, 'por_cobrar', sale.id, { transaction: t });
  }
  return sale;
});
```

**restaurant-sale.service.spec.ts** — positional args + mock(saleModel/saleItemModel/tableModel/tableService/printService/sequelize.transaction). 케이스:
- placeOrder 첫 주문 → Sale.create(status DRAFT, activityType 'sale') + syncTableStatus('ocupada')
- placeOrder 추가 주문(currentSaleId 있음) → Sale.create 미호출, bulkCreate 만 (단일 sale 누적)
- placeOrder → emitPrintTemp(table.branchId, kind:'comanda') 호출
- markTiming('served') → servedAt UPDATE
- markTiming('closed') → closedAt UPDATE + syncTableStatus('por_cobrar')

ESLint 준수, 한국어 주석.
  </action>
  <verify>
    <automated>cd /Users/marcoskim/Trabajos_Programming/ACE_online_1.0/api-ventago && npx jest restaurant-sale.service --silent 2>&1 | tail -25</automated>
  </verify>
  <acceptance_criteria>
    - restaurant-sale.service.ts 에 `class RestaurantSaleService` + placeOrder + markTiming 존재
    - placeOrder 에 `SaleStatus.DRAFT` + `SaleActivityType.SALE` + `this.sequelize.transaction` 존재
    - grep "emitPrintTemp(table.branchId" 또는 동등 (table_id→branchId 직접 해결, Pitfall 4) 존재
    - grep "lastComandaAt" restaurant-sale.service.ts (comanda 증분 경계 갱신)
    - markTiming 'closed' 경로에 syncTableStatus(..., 'por_cobrar', ...) 존재
    - `npx jest restaurant-sale.service` PASS — 첫 주문/추가 주문/comanda emit/타이밍 5+ 케이스
    - 추가 주문 케이스가 Sale.create 호출 0회 검증 (단일 DRAFT 누적 — Pitfall 5 매출 무오염)
  </acceptance_criteria>
  <done>placeOrder(누적+comanda 증분 emit) + markTiming 완성, jest green. 단일 DRAFT sale 누적 + 상태 트랜잭션 동기화.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: cuenta/영수증 resumen emit + split/merge 결제 (service 2부) + spec 보강</name>
  <read_first>
    - api-ventago/src/app/sales/sales-create.service.ts (결제 경로 — BoxOperationService 금전함 기록, DRAFT→PAID 전환, SalePaymentMethod INSERT 패턴, line 730 열린 cashRegister 전제)
    - api-ventago/src/app/box-operation/box-operation.service.ts (addOperation 시그니처 — line 16: addOperation(data, transaction?), data={cashRegisterId,userId,terminalId,amount,type,executionType,description})
    - api-ventago/src/app/sales/sales-payment-methods/sales-payment-method.model.ts (saleId/paymentMethodId/optionId/amount)
    - api-ventago/src/app/sales/restaurant-sale/restaurant-sale.service.ts (Task 1 산출)
    - 39-CONTEXT.md D-01~D-04 (split=단일 sale 복수 pm, merge=복수 sale 동시 PAID 금액 배분, reparent 금지)
    - 39-RESEARCH.md Open Q3 (box-operation 경유 — 우회 금지) + Pitfall 5 (split 매출 오염) + Security (split 합계=totalAmount 검증)
  </read_first>
  <behavior>
    - printCuenta(saleId): 결제 전 합산 내역 emitPrintTemp(kind:'cuenta'), sale 상태 DRAFT 유지 + table.status='por_cobrar'
    - paySale(saleId, payments[]): split 지원 — 한 sale 에 복수 SalePaymentMethod INSERT, 합계=sale.totalAmount 검증, DRAFT→PAID, table libre+currentSaleId=NULL, box-operation 금전함 기록, 영수증 emit(kind:'receipt')
    - payMerge(saleIds[], payments[]): 각 DRAFT sale 유지(reparent 안 함), 금액 배분해 각 sale 의 SalePaymentMethod INSERT, 각 DRAFT→PAID, 각 table 리셋 — 단일 TX
  </behavior>
  <action>
**restaurant-sale.service.ts 확장** (Task 1 파일에 추가):

`printCuenta(storeId, saleId)`:
- sale 스코프 조회 + items 합산 → emitPrintTemp(table.branchId, {kind:'cuenta', tableName, items, total}). 상태 변경 없음(DRAFT 유지) — req9. table.status='por_cobrar' 로만 표시(선택).

`paySale(storeId, saleId, payments: {paymentMethodId, optionId?, amount}[])` — 단일 TX:
```typescript
// split: payments 가 복수 행 = 한 sale 에 복수 SalePaymentMethod (자식 sale 금지 — D-01/Pitfall 5)
// sale_payment_methods.amount / sales.total_amount 는 integer → 정확 비교(!==), float 오차 없음
const sum = payments.reduce((a, p) => a + Number(p.amount), 0);
if (sum !== Number(sale.totalAmount)) throw new BadRequestException('결제 합계 불일치'); // Security
await this.pmModel.bulkCreate(payments.map((p) => ({ saleId: sale.id, ...p })), { transaction: t });
await sale.update({ status: SaleStatus.PAID, closedAt: sale.closedAt ?? new Date() }, { transaction: t });
await this.tableService.syncTableStatus(table, 'libre', null, { transaction: t }); // currentSaleId=NULL
// box-operation 금전함 기록 — 기존 결제 경로 경유 (Open Q3: 매상 통계 통합, 우회 금지)
// 열린 cashRegister(closingTime=null) 필요 — 미오픈이면 sales-create 와 동일하게 스킵됨
await this.boxOperationService.addOperation({
  cashRegisterId, userId, terminalId, amount: sale.totalAmount,
  type: 'venta', executionType, description: `식당 결제 sale#${sale.id}`,
}, t);
this.printService.emitPrintTemp(table.branchId, { kind: 'receipt', saleId: sale.id, /* ... */ }); // 영수증
```
(cashRegisterId/userId/terminalId/executionType 출처는 sales-create 결제 경로 동일 — 컨텍스트/dto 에서 해결. 핵심: 식당 결제도 BoxOperationService.addOperation 동일 경로.)

`payMerge(storeId, saleIds: number[], payments)` — 단일 TX:
- 각 saleId 의 DRAFT sale 조회(스코프). 결제 총액을 각 sale.totalAmount 비율로 배분(또는 사용자 입력 배분). 각 sale 에 SalePaymentMethod INSERT, 각 DRAFT→PAID, 각 table libre+NULL. **reparent 금지**(D-03 — 테이블별/웨이터별 매출 귀속 보존). 각 sale boxOperationService.addOperation 기록.

**spec 보강**:
- paySale split(payments 2행) → SalePaymentMethod 2 INSERT, Sale.create 0회(단일 sale), status PAID, syncTableStatus('libre', null)
- paySale 합계≠totalAmount → BadRequestException
- paySale → boxOperationService.addOperation 호출(type:'venta')
- payMerge(saleIds 2개) → 2 sale 각 PAID, 2 table 리셋, reparent(saleId 변경) 0회
- printCuenta → emitPrintTemp(kind:'cuenta') + sale 상태 DRAFT 불변

ESLint, 한국어 주석.
  </action>
  <verify>
    <automated>cd /Users/marcoskim/Trabajos_Programming/ACE_online_1.0/api-ventago && npx jest restaurant-sale.service --silent 2>&1 | tail -25</automated>
  </verify>
  <acceptance_criteria>
    - restaurant-sale.service.ts 에 printCuenta + paySale + payMerge 존재
    - paySale 에 split 합계 검증(`sum !== sale.totalAmount` 정확 비교 + BadRequestException) 존재 (Security, integer 비교)
    - paySale 에 `SaleStatus.PAID` + `syncTableStatus(table, 'libre', null` 존재
    - payMerge 가 saleIds 배열 순회하며 각 sale PAID + 각 table 리셋, reparent(saleId/tableId 재할당) 코드 0 (D-03)
    - printCuenta 가 emitPrintTemp(kind 'cuenta') 호출하고 sale.update(status...) 미호출 (DRAFT 유지 — req9)
    - grep "addOperation" restaurant-sale.service.ts (box-operation 경유 — req11 매상 통합, BoxOperationService.addOperation 실제 메서드)
    - `npx jest restaurant-sale.service` PASS — split/merge/cuenta/합계검증 케이스 포함
  </acceptance_criteria>
  <done>cuenta/영수증 emit + split(단일 sale 복수 pm) + merge(복수 sale 동시 PAID) 완성, box-operation(addOperation) 경유, jest green.</done>
</task>

<task type="auto">
  <name>Task 3: Controller (주문/타이밍/cuenta/결제 라우트) + sales.module 등록 + 회귀 확인</name>
  <read_first>
    - api-ventago/src/app/sales/sales.module.ts (providers/controllers/imports — RestaurantTablesModule import 필요, BoxOperationModule/Service 이미 등록됨, Print 의존)
    - api-ventago/src/app/sales/restaurant-sale/restaurant-sale.service.ts (Task 1/2 메서드 시그니처)
    - 39-RESEARCH.md Open Q1 (타이밍 전용 PATCH /sales/:id/timing — 라우트 순서 :id 위)
    - api-ventago/src/app/sales/sales-create.service.spec.ts (회귀 — nullable 컬럼 추가 후 기존 spec 통과 유지)
  </read_first>
  <action>
**restaurant-sale.controller.ts** — @Controller('restaurant-sale') (또는 'sales/restaurant') + @Auth. user.storeId 스코프. 라우트:
```
@Post('order')                placeOrder   → service.placeOrder(user.storeId, dto)
@Patch(':id/timing')          markTiming   → service.markTiming(user.storeId, id, body.event)  // event: served|closed
@Post(':id/cuenta')           printCuenta  → service.printCuenta(user.storeId, id)
@Post(':id/pay')              paySale      → service.paySale(user.storeId, id, body.payments)
@Post('pay-merge')            payMerge     → service.payMerge(user.storeId, body.saleIds, body.payments)
```
구체 경로(order, pay-merge)를 :id 라우트 위에 배치(라우트 우선순위). DTO class-validator(event enum 'served'|'closed', payments amount @IsNumber 등).

**sales.module.ts**:
- imports 에 RestaurantTablesModule 추가(syncTableStatus 사용). PrintModule/BoxOperationModule 의존 이미 sales 모듈에 있으면 재사용.
- providers 에 RestaurantSaleService, controllers 에 RestaurantSaleController 추가.

**회귀 확인**: 39-02 가 sales 에 nullable 컬럼 추가한 뒤 기존 `sales-create.service.spec.ts` 가 여전히 green 인지 확인 (회귀 0 — must_have).

ESLint(미사용 import 0, return 위 빈 줄). tsc + nest 부팅.
  </action>
  <verify>
    <automated>cd /Users/marcoskim/Trabajos_Programming/ACE_online_1.0/api-ventago && npx jest sales-create.service --silent 2>&1 | tail -10 && npx tsc --noEmit 2>&1 | grep -i "restaurant-sale\|sales.module" | head; echo "DONE"</automated>
  </verify>
  <acceptance_criteria>
    - restaurant-sale.controller.ts 에 @Post('order'), @Patch(':id/timing'), @Post(':id/cuenta'), @Post(':id/pay'), @Post('pay-merge') 5 라우트
    - @Post('order') 와 @Post('pay-merge') 가 @Post(':id/...') 라우트보다 위 (우선순위)
    - sales.module.ts 의 imports 에 RestaurantTablesModule, providers 에 RestaurantSaleService, controllers 에 RestaurantSaleController
    - `npx jest sales-create.service` 여전히 PASS (회귀 0 — nullable 컬럼 추가 영향 없음)
    - `npx tsc --noEmit` restaurant-sale 관련 에러 0
  </acceptance_criteria>
  <done>Controller 5 라우트 + sales.module 등록 + 소매 sales spec 회귀 0 확인. tsc 통과.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries
| Boundary | Description |
|----------|-------------|
| client → restaurant-sale API | 타 매장 sale 조작(IDOR), split 음수/초과 금액, 결제 우회 |

## STRIDE Threat Register
| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-39-10 | Tampering | paySale split 금액 | mitigate | 결제 합계 = sale.totalAmount 정확 비교(integer, sum !== total), 불일치 BadRequest |
| T-39-11 | Tampering/Info | placeOrder/paySale/markTiming | mitigate | 모든 service 쿼리 WHERE storeId 스코프 (user.storeId JWT 출처) |
| T-39-12 | Repudiation | 결제 경로 우회 | mitigate | box-operation(addOperation) 경유 강제 — 식당 결제도 금전함/매상 통계 기록 (Open Q3) |
| T-39-13 | Tampering | 테이블 상태 drift | mitigate | 주문/결제/cuenta 단일 트랜잭션 — sale 상태↔restaurant_tables 원자 동기화 (Pitfall 3) |
</threat_model>

<verification>
- npx jest restaurant-sale.service green (placeOrder/timing/cuenta/split/merge)
- npx jest sales-create.service green (소매 회귀 0)
- npx tsc --noEmit 에러 0
</verification>

<success_criteria>
- DRAFT 누적 + comanda 증분 emit + 타이밍 + cuenta/영수증 + split/merge 동작
- 매상 통계 box-operation(addOperation) 경유 통합, 소매 회귀 0
- 상태 동기화 트랜잭션 원자성
</success_criteria>

<output>
완료 후 `.planning/phases/39-modo-restaurante-pos-mesas/39-05-SUMMARY.md` 작성.
</output>
