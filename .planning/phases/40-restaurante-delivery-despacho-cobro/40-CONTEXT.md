# Phase 40: Restaurante Delivery — Despacho y Cobro - Context

**Gathered:** 2026-06-16
**Status:** Ready for planning

<domain>
## Phase Boundary

식당모드(`use_restaurant_mode=true`) 매장의 인터넷 배달 주문 라이프사이클(접수→주방→배차→배달→**수금→정산 마감**) 통제 레이어. 직원이 WhatsApp·전화·배달앱(PedidosYa/Rappi) 주문을 내부 콘솔로 접수, 라이더로 배차, 현장 현금/QR/배달앱 수금, 카하 정산까지. 핵심 불변식: *배달 완료(Entregado) ≠ 주문 종료* — 현금 contra entrega 는 라이더 정산금이 caja(box) movement 로 입금(`Liquidado`)될 때까지 "열린 미수금(Por cobrar)"으로 추적. 신규 delivery 레이어 + 기존 `Sale` 백본 재사용(C안). 소매 `online-orders` 미재사용(도메인 충돌).

본 CONTEXT 는 SPEC.md 가 잠근 9개 요구사항(WHAT)의 **구현 방식(HOW)**만 다룬다. 논의한 회색지대: Sale 결제상태↔배달 라이프사이클 동기화 · 배차 보드 실시간 채널 · 라이더 정산→caja 매핑 · 배달앱 CSV 업로드/파싱.

</domain>

<spec_lock>
## Requirements (locked via SPEC.md)

**9 requirements are locked.** See `40-SPEC.md` for full requirements, boundaries, and acceptance criteria.

Downstream agents MUST read `40-SPEC.md` before planning or implementing. Requirements are not duplicated here.

**In scope (from SPEC.md):**
- 신규 엔티티 3개: Repartidor, RestaurantDelivery(Sale 1:1), RiderSettlement(+ Item)
- `SaleSource` 에 `'delivery'` 추가 (DB CHECK 마이그레이션 PG10/PG15 호환)
- 화면 4개: 설정>Repartidores 카드(식당모드 on), 주문 접수 모달(Delivery/Para llevar), 배차 보드 칸반, 라이더 정산
- 수금 3종: 현금 contra entrega(라이더→caja), QR(MP webhook 자동), 배달앱(L1 CSV 대조)
- 경과시간 타이머 표시(고정 임계값, 시각 보조), comanda 출력(print-agent 재사용), Socket.io 실시간 보드, delivery sale 매출 보고서 자동 반영

**Out of scope (from SPEC.md):**
- 고객용 공개 추적 링크, 배달앱 L2 완전 API 동기화, 라이더 모바일 전용 화면, GPS 추적, 외상(fiado), SLA 설정·알림, 금액 tolerance 매칭, 소매 online-orders 통합

</spec_lock>

<decisions>
## Implementation Decisions

### Sale 결제상태 ↔ 배달 라이프사이클 동기화
- **D-01 (매출 귀속 시점):** delivery Sale 은 **배달완료(`Entregado`) 시 DRAFT→PAID 전환 + `SalePaymentMethod`(선택한 paymentMode 행) 기록** → 매출 즉시 인식. "돈이 아직 카하에 안 들어옴"은 SaleStatus 가 아니라 **RestaurantDelivery.status(Por cobrar→Liquidado) + RiderSettlement** 가 별도 추적하는 **수금축**으로 분리. 식당 회계 자연스러움 + 매출 무오염(activityType='sale' 유지). 단, 현금 주문은 Sale PAID 시점 ≠ box movement 시점(box movement 는 라이더 정산 시 — D-05) — 이 갭이 곧 "Por cobrar" 개념.
- **D-02 (취소 처리):** 배달완료 전(DRAFT)이면 **Sale 소프트삭제/무효 + 재고 복원 + RestaurantDelivery status=cancelado**. 이미 PAID(Entregado 이후)면 **기존 anular(역분개 nullify) 흐름 재사용**(nullifySale 패턴 — Phase 29/35 선례).
- **참고:** Phase 39 mesa 는 "결제 시 PAID"였으나 delivery 는 "배달완료=결제(귀속)"로 의미 차이 — paymentMode 가 주문 시 이미 확정되므로 Entregado 에서 SalePaymentMethod 확정 가능.

### 배차 보드 실시간 채널 (Socket.io)
- **D-03 (채널):** **신규 namespace 게이트웨이(예: `/restaurant`) + `branch:{id}` room** 신설. 브라우저 보드 클라이언트(JWT/session 인증)와 print-agent(Electron API키 에이전트) 관심사 분리 — 기존 `/print-agent` 게이트웨이는 확장하지 않음. room 구조는 `emitPrintTemp` 의 `branch:{id}` 패턴 동일 적용.
- **D-04 (이벤트 입니어):** 상태 전이 시 **변경된 delivery 카드 payload 를 emit(card-level)**, 클라이언트가 보드에 병합. 신호만 보내고 전체 재조회하는 방식 회피 → 추가 쿼리 0, pool 절약(300ms 타겟). comanda 출력은 별개로 기존 `emitPrintTemp(branchId, data)` fire-and-forget 재사용.

### 라이더 정산 → caja(box) 매핑
- **D-05 (box movement 입니어):** RiderSettlement **close 시 receivedCash 합계를 box movement 1건(집계)으로 입금**. "교대 마감" 모델과 일치, caja 항목 깔끔(주문당 소액 다수 회피). `box-operation.service.addOperation` 재사용(Phase 39 P05 선례 패턴).
- **D-06 (caja 미오픈 처리):** 정산 시 **열린 cashRegister(closingTime=null) 가 없으면 정산 차단** — 먼저 caja 오픈 요구(명확한 안내). 현금이 반드시 caja 로 들어가 control-de-caja 마감과 일치 보장. Phase 39 결제의 "미오픈 시 box-op 스킵"과 달리 **delivery 정산은 더 엄격**(통제 원칙 — 현금 미수금 추적의 핵심 종착점).

### 배달앱 L1 정산 CSV 대조
- **D-07 (업로드/저장):** payout CSV 는 **MinIO 저장 + 서버 파싱**. 정산 원본 파일을 보관해 감사 추적(주 단위 배달앱 정산 대조 이력). `MinioService.uploadFile` 재사용.
- **D-08 (포맷):** **단일 고정 스키마(템플릿)** — 운영자가 CSV 를 정의된 템플릿(externalRef·금액 컬럼 고정)으로 정규화해 업로드. 매칭 = `RestaurantDelivery.externalRef`(주문 접수 시 기록한 배달앱 주문번호) + 금액 일치. 매칭건 자동 Conciliado, 미매칭/금액 불일치만 빨강(금액 tolerance 매칭은 SPEC out-of-scope — 정확 일치).

### Claude's Discretion
- **프론트 Delivery 진입점:** SPEC/Phase 39 패턴상 `ventago-app/src/views/restaurante/` 아래 신규 `DeliveryBoard`(칸반) 컴포넌트로, SalonView 옆 탭/세그먼트 전환(둘 다 식당모드 매장 전용). nueva-venta 또는 전용 라우트 분기는 plan 단계에서 SalonView 분기 패턴(`next/dynamic`, ssr:false) 재사용해 결정.
- **주문번호 식별:** 보드 카드 식별자는 기존 Sale 식별 체계(dailyNumber 등) 재사용 우선 검토, 부족 시 RestaurantDelivery 자체 sequence. 신규 컬럼 최소화 원칙.
- **상태 enum 명칭:** RestaurantDelivery.status 값(`nuevo/en_cocina/listo/en_camino/entregado/por_cobrar/conciliacion/liquidado/cancelado`)의 정확한 string/CHECK 동기화는 plan 단계 — SaleStatus/SaleActivityType enum↔DB CHECK 동기화 선례(sales.model.ts) 따름.
- **타이밍 타임스탬프:** orderedAt/readyAt/dispatchedAt/deliveredAt/settledAt 는 상태 전이 트랜잭션에서 기록(Phase 39 ordered_at/served_at/closed_at 패턴 동일).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase spec (locked requirements)
- `.planning/phases/40-restaurante-delivery-despacho-cobro/40-SPEC.md` — 9 locked requirements, boundaries, acceptance criteria. **MUST read before planning or implementing.**

### 설계 문서 (아키텍처 합의)
- `docs/superpowers/specs/2026-06-16-restaurant-delivery-design.md` — C안 합의(신규 delivery 레이어 + Sale 재사용), 상태머신, 데이터 모델 3 엔티티, 화면 4개, 수금 연동, 범위 밖

### 직전 Phase 컨텍스트 (식당모드 기반 — 패턴 일관성 필수)
- `.planning/phases/39-modo-restaurante-pos-mesas/39-CONTEXT.md` — D-01(split=단일 DRAFT+복수 sale_payment_methods), D-05/D-07(명시 status+sale FK 둘 다 저장 트랜잭션 동기화), 매출 무오염, emitPrintTemp 재사용
- `.planning/phases/39-modo-restaurante-pos-mesas/39-SPEC.md` — 식당모드 11 요구사항(use_restaurant_mode, restaurant_tables, 식당 sale 컬럼)

### DB schema reference (SQL/migration 작성 전 필수 — 추측 금지)
- `.planning/intel/db-schema-tables.md` — 133개 테이블 전체 컬럼 (타입/NOT NULL/default)
- `.planning/intel/db-schema-fks.md` — 모든 외래 키 관계

### Backend 재사용 대상 (확장 only)
- `api-ventago/src/app/sales/sales.model.ts` — `Sale`. SaleStatus(DRAFT='Borrador'...PAID='Pagado', NULLIFIED/NULLIFICATION), **SaleSource(pos/online/factura) → `delivery` 추가**, SaleActivityType(sale 유지), tableId nullable + BelongsTo constraints:false 선례 → delivery 컬럼 동일 패턴
- `api-ventago/src/app/sales/restaurant-sale/restaurant-sale.service.ts` — Phase 39 RestaurantSaleService(placeOrder/comanda/box-operation/MP 결제 라이프사이클). delivery 서비스가 따를 트랜잭션 동기화 패턴(sale↔meta 단일 TX, branchId 직접 해결, addOperation 경유)
- `api-ventago/src/app/sales/sales-payment-methods/sales-payment-method.model.ts` — `SalePaymentMethod`(saleId+paymentMethodId+optionId+amount). Entregado 시 paymentMode 행 INSERT
- `api-ventago/src/app/box-operation/box-operation.service.ts` — `addOperation()` 라이더 정산 입금(D-05). closingTime=null cashRegister findOne 패턴
- `api-ventago/src/app/print/print.gateway.ts` + `print.service.ts` — `@WebSocketGateway(namespace:'/print-agent')` + `emitPrintTemp(branchId,data)` `branch:{id}` room. **신규 `/restaurant` 게이트웨이(D-03)가 이 room 패턴 모방**, comanda 출력은 emitPrintTemp 직접 재사용
- `api-ventago/src/app/clients/` (whatsapp 컬럼 — Phase 34) — 고객 자동완성/주소 기억, click-to-chat
- `api-ventago/src/app/mercadopago/` — QR intents/webhook. paymentMode=qr 배달 주문 자동 확인
- `api-ventago/src/app/store/config/storeConfig.model.ts` — `use_restaurant_mode` 게이팅(Repartidores 카드 노출)
- MinioService/MinioModule — payout CSV 저장(D-07)
- `api-ventago/migrations/` — 신규 테이블 3개 + sales SaleSource CHECK ALTER, PG10/PG15 호환(SERIAL, CREATE UNIQUE INDEX ... WHERE, EXECUTE PROCEDURE)

### Frontend 재사용/분기 대상
- `ventago-app/src/views/restaurante/SalonView.tsx` — Phase 39 식당 뷰. 신규 `DeliveryBoard`(칸반) 가 옆에 위치(탭/세그먼트)
- `ventago-app/src/views/configuracion/restaurante/SalonEditor.tsx` — configuración 식당 영역. Repartidores 카드 진입점 인접
- `ventago-app/src/hooks/api/useSalonSummary.ts` — SWR 훅 선례(보드/라이더/정산 데이터 훅 패턴)
- `ventago-app/src/services/api.service.ts` — apiConnector(get/post/put/remove/sendFile). CSV 업로드=sendFile
- 결제 모달/MP QR side-panel(Phase 29) — 주문 접수 모달 Cobro QR 흐름 재사용

### 프로젝트 규약
- `CLAUDE.md` — Sequelize underscored(snake_case), PG10/PG15 호환, pool min=10/max=80, 300ms 타겟+코드스플리팅, SWR 훅, ESLint(newline-before-return/lines-around-comment/no-unused-vars), apiConnector.remove()
- `.claude/skills/sketch-findings-ace-online/SKILL.md` — Ventago 다크 네이비+골드 테마, MUI 5 매핑 (보드/정산 UI 작업 시 참조)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`Sale` 백본**: SaleSource enum 확장(`delivery`) + nullable 컬럼 추가 선례(tableId/storeClientId). delivery sale = `source='delivery'`, `activityType='sale'`, `tableId=null` → 매출 보고서 자동 포함
- **RestaurantSaleService(Phase 39)**: placeOrder→comanda→box-operation→결제 트랜잭션 동기화 패턴. delivery 서비스가 동일 불변식(sale↔meta 단일 TX, branchId 직접 해결) 따름
- **SalePaymentMethod**: Entregado 시 paymentMode 행 INSERT (split 불필요 — 배달은 단일 결제수단)
- **box-operation.addOperation**: 라이더 정산 집계 입금(D-05). cashRegister closingTime=null findOne
- **print.gateway `/print-agent` + emitPrintTemp**: comanda 출력 직접 재사용. 신규 `/restaurant` 게이트웨이는 room 패턴만 모방
- **clients.whatsapp(Phase 34)**: 고객 자동완성 + click-to-chat
- **mercadopago webhook**: QR 배달 주문 자동 결제 확인
- **MinioService**: payout CSV 저장(D-07)

### Established Patterns
- **단일 WebSocket 게이트웨이만 존재**(`/print-agent`, Electron API키). 보드 실시간은 신규 namespace 필요(D-03) — 폴링 아님(Phase 39 보드는 폴링이었으나 SPEC 40 은 push 요구)
- **매출 무오염**: 모든 매출 쿼리 `activity_type='sale'` 명시 필터. delivery sale 유지 → 자동 통합
- **store→branch 스코프**: 신규 테이블 전부 store_id FK, 식당모드 매장 전용(store 단위 배타)
- **SWR 참조 데이터 캐시**: 라이더 목록/보드 데이터 SWR 훅(5분 dedup, useSalonSummary 선례)
- **마이그레이션 PG10/PG15 호환**: snake_case, GENERATED AS IDENTITY 회피, CHECK 제약 = enum 동기화

### Integration Points
- **DB 마이그레이션**: `api-ventago/migrations/` — 신규 `repartidores`/`restaurant_deliveries`/`rider_settlements`/`rider_settlement_items` + `sales` SaleSource CHECK ALTER
- **신규 Socket.io `/restaurant` 게이트웨이**: branch:{id} room, JWT/session 인증, deliveryUpdated 카드 payload emit(D-03/D-04)
- **caja(control-de-caja)**: 라이더 정산 입금 = box movement → 마감 일치(D-05/D-06)
- **configuración**: Repartidores 카드(use_restaurant_mode 게이팅), SalonEditor 인접
- **nueva-venta/restaurante 뷰**: DeliveryBoard 진입점(SalonView 옆), next/dynamic ssr:false 코드스플리팅

</code_context>

<specifics>
## Specific Ideas

- 상태머신: `Nuevo → En cocina → Listo → En camino → Entregado → Liquidado`(설계 §4). 수금축 병렬: efectivo→Por cobrar→Liquidado / qr→webhook 자동 종료 / app→Conciliación→CSV 대조
- 보드 칸반 컬럼: Nuevo·En cocina·Listo·En camino·Por cobrar(+ app 전용 Conciliación). Por cobrar(빨강)=통제 핵심(현금 미수금만 잔류, QR/app 미경유)
- 카드: 주문번호·고객·주소·경과시간 타이머(고정 임계값 시각 보조)·총액·수금모드 뱃지(색=모드)·라이더 칩
- 정산 화면: 라이더별 efectivo a rendir(강조), rendido 체크, Esperado vs Recibido → Diferencia, "Registrar rendición en caja" + "Guardar parcial"
- 주문 접수 모달: Tipo(Delivery=주소·라이더 / Para llevar=생략), Canal 칩, 전화번호 기존 고객 자동완성, mesa OrderModal 동일 메뉴 피커, Cobro 모드

</specifics>

<deferred>
## Deferred Ideas

- **고객용 공개 주문 추적 링크** — WhatsApp 상태 메시지 확장, 후속 phase (SPEC out-of-scope)
- **배달앱 L2 완전 API 양방향 동기화** — 플랫폼 파트너 API 확보 후 별도 phase
- **라이더 모바일 전용 앱/화면** — 후속
- **GPS 실시간 위치 추적** — 별도 phase
- **외상(fiado) 배달** — credit 모듈 통합 별도
- **금액 tolerance CSV 매칭** — L1 은 정확 일치만, tolerance 는 후속
- **배달앱 플랫폼별 자동 파서** — 단일 고정 템플릿(D-08)으로 시작, 플랫폼별 파서는 운영 부담 검증 후 후속
- **item 단위 split 결제** — 배달은 단일 결제수단이라 미해당(mesa Phase 39 deferred 와 동일 사유)

</deferred>

---

*Phase: 40-restaurante-delivery-despacho-cobro*
*Context gathered: 2026-06-16*
