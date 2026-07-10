# SPEC: POS 결제/배송 축 분리 (Envío=canal + 미수금 자동 Crédito + MercadoPago 100% 단축)
생성일: 2026-07-09
상태: PLAN 승인 대기(미실행)

## 목표
결제수단("어떻게 돈을 냈나")과 배송/판매채널("어떻게 물건이 나가나")을 서로 독립된 축으로 분리한다.
"Internet Envío"를 결제수단 목록에서 은퇴시키고, Envío 체크박스가 online_order 분기를 트리거하며,
미납 잔액은 자동으로 Crédito(sale_credit, cuenta corriente)로 처리하고, 메인 POS에 MercadoPago 100% 원클릭 토글을 추가한다.

## 배경 및 컨텍스트
현재(Phase 43): 결제수단 목록에 `internet_pedido` slug 가 있고, 이걸 "결제"로 선택하면
sale 대신 online_order(EnvioRegistroModal → POST /online-orders/from-pos)로 분기한다.
- 문제 1: 배송이 결제수단 자리를 차지 → 현금 완납 + 배송 동시 표현 불가.
- 문제 2: "Registrar pedido online" 버튼이 `pagadoActual === totalAmount`(전액) 강제 → seña/contra entrega 불가(정작 from-pos DTO 는 contra_entrega|prepago 지원).
- 문제 3: 미납 잔액을 담을 곳이 없어 "누가 얼마 빚졌나"가 사라짐.
- 문제 4: 결제수단 일일 리포트가 "돈이 아닌 항목"으로 오염.

재사용 자산(재구현 금지):
- FE: `EnvioRegistroModal.tsx`(guard 고객+주소, from-pos 호출), `PaymentSummaryModal.tsx`(분기/버튼), `SaleProductsContext`(paymentMethods 상태), MP: `useMpPaymentIntent`/`McdpgQrPanel`.
- BE: `online-orders.service.createFromPos`, `shipOrder`(P1 매출인식-at-ship: saldo>0 → `creditLedgerService.appendMovement({movementType:'sale_credit'})`, `assertCreditEligible` 선검증), `CuentasPorCobrarTab`.
- ★ 핵심: 미수금→sale_credit 은 이미 shipOrder(P1)에 구현됨. 현재 부족한 것은 "지금 일부만 받은 금액(seña)"을 from-pos 가 못 받아 saldo 가 all-or-nothing(prepago=0 / contra=total)인 점.

관련 파일:
- FE `ventago-app/src/views/homes/components/ProductList/components/PaymentSummaryModal.tsx` (fetchPaymentMethods ~158, internetPedidoSelected ~326, 버튼 ~910, EnvioRegistroModal ~940)
- FE `.../ProductList/components/EnvioRegistroModal.tsx` (from-pos payload ~269)
- FE `.../ProductList/ProductList.tsx` (Pagos 칩/Generar Venta ~1473,1662; paymentMethods from context)
- FE `.../homes/hook/SaleProductsContext.tsx` (paymentMethods, setPaymentMethods, resetSale)
- BE `api-ventago/src/app/online-orders/dto/create-from-pos-online-order.dto.ts`
- BE `api-ventago/src/app/online-orders/online-orders.service.ts` (createFromPos ~490, shipOrder P1 ~797~1000)

## 기술 스택
- FE: ventago-app (React + MUI + TypeScript). ESLint 설정 있음(레포 루트/ventago-app).
- BE: api-ventago (NestJS + Sequelize + pg). Pool: max=80, 현재 using=0% (건강, 로그 확인 2026-07-09).
- DB: PostgreSQL — 로컬 PG18(localhost:5432 ventago), 운영 PG10. 본 작업은 신규 DDL 없음(코드/설정만).

## 태스크 목록
### FE
- [x] TASK-1: `PaymentSummaryModal.tsx` — `fetchPaymentMethods`에서 `slug==='internet_pedido'` 항목을 `availablePaymentMethods`에서 제외(필터). (DB 행은 보존, 셀렉트에서만 숨김)
- [x] TASK-2: `PaymentSummaryModal.tsx` — 분기 트리거 교체. `internetPedidoSelected`(payments.some) → 신규 `envioChecked` 상태. 체크박스를 footer(Imprimir Ticket/Factura 옆)에 추가. 기존 guard(고객+주소)·안내 Alert·버튼 morph(Aceptar↔Registrar pedido online)·EnvioRegistroModal open 을 새 상태에 재배선.
- [x] TASK-3: `EnvioRegistroModal.tsx` — from-pos payload 에 실제 결제내역(paidNow: payments 배열 또는 amountPaidNow) 전달. `paymentMode`는 paidNow 로 파생(=total→prepago, =0→contra_entrega, 그 외→partial/seña).
- [x] TASK-4: `ProductList.tsx` (+ 필요 시 `PaymentSummary`/context) — 메인 POS "Pagos" 행에 MercadoPago 100% 원클릭 토글. 체크 시 `setPaymentMethods([{ slug:'mercadopago', title:'MercadoPago', amount: totalFactura }])`(Efectivo 치환), 해제 시 기본(Efectivo)로 복귀. Generar Venta 시 기존 MP QR 흐름 재사용(신규 QR 로직 작성 금지). Envío 와 상호 배타 아님(MP 프리페이 + 배송 가능).

### BE
- [ ] TASK-5: `create-from-pos-online-order.dto.ts` — `amountPaidNow?: number`(@IsOptional @IsNumber @Min(0), ≤ total 서비스단 검증) 추가. 또는 payments[] 형태. paymentMode 는 유지(파생값 검증용).
- [ ] TASK-6: `online-orders.service.createFromPos` — paidNow 저장 + `saldo = total - paidNow` 반영(metadata.paidNow/shipSaldo). shipOrder(P1)의 기존 saldo>0 → sale_credit 경로 재사용(신규 원장 로직 작성 금지). paidNow 는 order payment 로 기록(방식은 EXECUTE 시 기존 online_order 결제기록 방식 확인 후 결정).

### 검증
- [ ] TASK-7: ESLint — 수정 파일 전부 `npx eslint <files> --fix`, 오류 0.
- [ ] TASK-8: PostgreSQL pool 점검 — createFromPos/shipOrder 트랜잭션에서 `client.release()`가 `finally`에 있는지, Pool 신규 생성 없는지 확인. `pool.query()` 우선.
- [ ] TASK-9: 로컬 시나리오 검증(마지막 로그 확인 포함) — (a) 완납+배송=prepago 주문, (b) seña $100k+배송→ship 시 sale_credit $224k, (c) $0 contra entrega→ship 시 sale_credit 전액, (d) MP 100% 토글→QR→완납, (e) 배송 미체크 일반 판매 회귀. 각 후 combined/error 로그 신규 에러 0 확인.

## 완료 기준
- ESLint 오류 0.
- 결제수단 셀렉트에 "Internet Envío" 미노출, 리포트 오염 중단.
- 현금/MP 등 실제 결제 + Envío 동시 가능. seña 가능(버튼이 전액 강제 안 함).
- ship 시 미납분이 sale_credit 로 정확히 계상(assertCreditEligible 통과 대상만), CuentasPorCobrar 에 노출.
- 일반 presencial 판매 회귀 없음. MP 100% 원클릭 정상.
- pool release 누락 0, Pool 신규 생성 0.

## 미결정 / 승인 필요
1. 부분결제 sale_credit 계상 시점: **shipOrder(P1) 유지 권장**(매출인식 일관, 취소 안전) vs 주문 생성 즉시. → 승인 필요.
2. `assertCreditEligible` 미충족(credit_status≠active/한도초과) 고객의 seña 배송: (a) 차단 후 안내 vs (b) sale_credit 없이 online_order paymentStatus=미납(Cuentas por Cobrar)로만 관리. → 승인 필요(권장: b, 배송은 credito 한도와 별개일 수 있음).
3. MP 100% 토글이 분할결제 상태를 덮어쓸 때 UX(경고/확인). → EXECUTE 시 확정.

## 금지사항 / 주의사항
- `internet_pedido` DB 행/slug DROP 절대 금지(과거 판매·리포트 매핑). 필터/비활성만.
- 신규 QR/credit 원장 로직 재작성 금지 — 기존 `useMpPaymentIntent`/`shipOrder` P1 재사용.
- 결제수단 자동 추가·Favor/credito 자동차감 금지(기존 SPEC 규칙 유지).
- `pool.connect()`↔`client.release()` finally 필수, Pool 요청마다 생성 금지.
- 운영 DB DDL 없음. 발생 시 승인 게이트(coolsistema owner 규칙).
- 선행 미결: sellers.pin_hash 마이그레이션 로컬 미적용(별건, 본 작업과 무관하나 dev 서버 500 유발 중).

## 결정 기록 (2026-07-09 승인)
- 미수금 처리: **자격 있는 고객만 sale_credit(P1 유지)**. `assertCreditEligible` 미충족 고객은 원장 없이 online_order 미납(paymentStatus) → **Cuentas por Cobrar 로만** 관리. (shipOrder 가 non-eligible 에서 hard-throw 하지 않도록 조정 필요)
- 진행: EXECUTE 즉시 시작 승인됨.

## 추가 요구 (2026-07-09, 인식시점 — 확정 필요)
사용자 요구: "envío 등록 순간 → 재고 차감 + venta 생성. 취소 시 → negativa venta 자동 생성으로 기존 venta 를 anular."
현황 대조:
- 재고 차감: **이미 등록(생성) 시점 차감됨**(holdStock: product.stock -qty). → 요구 충족.
- venta(Ventas mirror): **현재 ship 시점 생성**(P1 recognition-at-ship, 2026-07-08 사용자 승인 `spec-recognition-at-ship.md`). 요구는 이를 **등록 시점으로 회귀**시키는 것 → 충돌.
- 취소: 현재 reverseSale(원장 역기입)/reverseToNuevo, 외상배송 취소 차단. 요구는 **음수 Ventas 행(negativa venta) append-only 상쇄** → 신규 메커니즘.
결정 필요:
  (A) 인식시점: POS-envío 만 등록시점 인식(외부채널 orders 는 ship 유지) vs 전역 회귀.
  (B) 취소 상쇄: 신규 "negativa venta"(음수 mirror + 원장/재고 역기입, append-only) vs 기존 reverseSale 재사용.

## 최종 확정 (2026-07-09)
- 용어: ship = transporte(택배) 인계 시점. deliver = 고객 수령.
- 인식시점: **POS-envío = 등록(Registrar) 시점에 venta 인식**(재고가 이미 등록 시 빠지므로 일치). 외부채널 주문은 recognition-at-ship 유지 → createFromPos 에서 commitSale+mirror+(자격시)sale_credit 즉시 수행.
- 취소: **negativa venta 신규**(음수 Ventas mirror + 재고/원장 역기입, append-only). 원본 보존, 상쇄 anular. 외상배송도 취소 가능.
- seña: envío 체크 시 현금 일부 + 나머지 자동 Crédito. paidNow=현금, saldo=나머지→(자격)sale_credit/(무자격)Cuentas por Cobrar.
- 검증환경: device VM 에 node v22/npx/python3 有 → eslint 는 device_bash 로 실행 가능. 삭제 불가(파일 격리는 _to_delete/).

## T6/T6b 백엔드 정밀설계 + 위험 (구현대기 · 서버 시나리오 검증 필수)
### 발견한 위험 (반드시 반영)
- 등록 시점 commitSale 후 shipOrder 가 commitSale 재호출(line 935, isNewMirror 가드 밖) → 재고/원장 이중계상.
  → shipOrder 판매확정 블록 전체를 `if (isNewMirror)` 게이팅 필요(현재 commitSale 만 무조건).
### T6 recognizeFromPos(order,storeId,userId,paidNow,t) — createFromPos 즉시 호출
1. metadata.received=paidNow; saldo=total-paidNow; isNewMirror=mirrorSaleId==null.
2. isNewMirror 일 때만: commitSale → createMirror(saldo>0?paidNow:undefined) → mirrorSaleId 저장.
3. saldo>0&&clientId: try{resolveStoreClientId→assertCreditEligible→appendMovement(sale_credit)} catch{미납유지(Cuentas por Cobrar)}.
4. paymentStatus=saldo<=0?PAID:유지; stockReleasedAt=now.
5. createFromPos: create() 후 별도 tx 호출(실패 시 shipOrder 폴백이 mirror 생성 — 무손실).
### T6b cancel → negativa venta(신규 append-only)
- mirrorSaleId!=null 인 POS-envío 취소: createNegativeMirror(음수 금액/수량, 원본 보존) + reverseSale(재고 복원) + credit ledger 역기입.
### 검증(T9, 서버 필요 · 이 환경 network 불가): 완납/seña/contra/취소/일반회귀 5종 DB·로그 이중계상0 확인.
