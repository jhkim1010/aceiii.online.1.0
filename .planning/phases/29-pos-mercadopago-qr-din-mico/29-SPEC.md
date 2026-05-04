# Phase 29: POS Mercadopago — QR Dinámico — Specification

**Created:** 2026-05-05
**Ambiguity score:** 0.18
**Requirements:** 7 locked

## Goal

매장 내 결제수단 "Mercadopago" 선택 시 백엔드가 QR Dinámico 를 생성하고, 고객이 MP 앱으로 스캔/결제하면 webhook + Socket.io 를 통해 해당 terminal 에서 자동으로 "Generar Venta" 가 트리거되어 판매가 완료된다. store 단위 OAuth 계정 연결, 부분금액 split 결제, 가상 "Caja Mercadopago" 자동 정산, sandbox/production 환경 분리, 환불 자동 처리까지 포함한다.

## Background

코드베이스 현재 상태:

- `payment_methods` 테이블 시드(`api-ventago/src/app/payment-methods/seed/payment-methods.seed.ts`)에 `mercadopago` slug 가 이미 존재하지만, **placeholder 일 뿐 실제 결제 통합 없음** — 사용자가 선택해도 그냥 텍스트로 저장되고 끝.
- "Generar Venta (F2)" 버튼: `ventago-app/src/views/homes/components/ProductList/ProductList.tsx:1157` → `handleSubmit("INVOICED", paymentMethods)` 호출. 결제수단 입력 후 사용자가 직접 클릭해야 함.
- 결제 모달: `views/homes/components/ProductList/components/PaymentSummaryModal.tsx`, `PaymentSummary.tsx` — 다중 결제수단 배열 입력 가능.
- Socket.io 인프라 2개 기존: `api-ventago/src/app/print/print.gateway.ts` (print-agent 용), `common/socket/websocket.gateway.ts` (공용). 재사용 가능.
- terminal 단위로 cashRegister 분리되어 있어 push 타깃팅 가능 (`cashRegister?.terminal?.name`).
- MP 관련 통합 코드/환경변수 없음. 환경변수 prefix `MP_` 또는 `MERCADOPAGO_` 미사용.

이번 phase 가 만들 것:

- `store_mercadopago_accounts` 신규 테이블 (store_id 단위, OAuth 토큰 암호화 저장, environment toggle)
- MP OAuth 연결/해제 UI (configuracion 모듈)
- QR Dinámico 생성 + 결제 대기 상태 관리
- MP webhook 엔드포인트 (서명 검증, idempotent)
- Socket.io 게이트웨이 확장: `mercadopago:approved` 이벤트 push
- 프론트엔드 자동 Generar Venta 트리거 + 5초 polling fallback
- "Caja Mercadopago" 가상 box 자동 생성 + MP 결제 시 자동 입금
- nullifySale 시 MP REST 자동 환불 호출

## Requirements

1. **MP-POS-01 — OAuth 연결 + 가상 Caja 자동 생성**: 매장 owner 가 자신의 MP 계정을 OAuth 로 연결하고, 첫 연결 시 "Caja Mercadopago" 가상 box 가 자동 생성된다.
   - Current: `store_mercadopago_accounts` 테이블 없음. payment_methods.seed 의 `mercadopago` slug 는 placeholder. MP OAuth 흐름/UI 없음. 매장의 caja(Box) 들은 모두 물리적 현금 box.
   - Target: 신규 테이블 `store_mercadopago_accounts` (store_id UNIQUE, mp_user_id, access_token 암호화, refresh_token 암호화, public_key, environment 'sandbox'|'production', expires_at, connected_at, disconnected_at). configuracion 모듈에 "Mercadopago 연결" 화면 — OAuth authorize URL 로 redirect → callback 에서 토큰 교환 → 저장. 첫 연결 성공 시 해당 store 에 `box.type = 'mp_wallet'` 1개 자동 생성 ("Caja Mercadopago", 모든 branch 에서 공유).
   - Acceptance: sandbox MP 계정으로 OAuth 연결 완료 → DB row 1개 생성, 토큰 컬럼이 평문이 아님 (암호화 검증), 동일 store 에 `box.type = 'mp_wallet'` 1개 정확히 생성. 재연결 시 새 row 가 아니라 update + disconnected_at = NULL.

2. **MP-POS-02 — QR Dinámico 생성 + 3분 timeout + 수동 취소**: nueva-venta 결제 모달에서 Mercadopago 선택 시 백엔드가 QR Dinámico 를 생성하고, 3분 카운트다운 + 수동 취소 버튼이 표시된다.
   - Current: payment_methods 의 `mercadopago` slug 는 단순 텍스트 placeholder. QR 생성/렌더/타이머 없음. PaymentSummaryModal 은 결제수단 텍스트만 받음.
   - Target: PaymentSummaryModal 에서 "Mercadopago QR" 선택 시 backend `POST /api/mercadopago/qr` 호출 (body: storeId, amount, pendingVentaId) → MP `POST /instore/orders/qr/seller/collectors/{user_id}/pos/{pos_id}/qrs` 호출 → external_reference = pendingVentaId 주입. 응답 QR base64 또는 URL 을 모달에 표시. 3:00 → 0:00 카운트다운. "Cancelar QR" 버튼 → backend `DELETE /api/mercadopago/qr/{intentId}` → MP order cancel + DB intent status='cancelled'. 만료 시 자동 expired.
   - Acceptance: sandbox 환경에서 결제수단 = MP 선택 → QR 이미지 모달에 표시 + 카운트다운 동작 (1초 단위). 3분 후 자동 expired 상태 + 결제수단 선택 화면으로 복귀. 수동 취소 클릭 시 즉시 expired 처리.

3. **MP-POS-03 — Webhook + Socket.io 자동 Generar Venta**: MP webhook 으로 결제 승인 알림이 들어오면 서명 검증 후 Socket.io 로 해당 terminal 에 푸시하고, 프론트가 자동으로 Generar Venta 를 트리거한다.
   - Current: MP webhook endpoint 없음. "Generar Venta" 는 사용자가 F2 또는 버튼 클릭으로만 발화.
   - Target: 신규 endpoint `POST /api/mercadopago/webhook` — `x-signature` HMAC SHA256 검증 (실패 시 401), payment.id 조회 → external_reference 로 `mp_payment_intents` 매칭 → status 'approved' 일 시 Socket.io `websocket.gateway` 통해 `mercadopago:approved` 이벤트를 해당 terminal 의 room 에 emit (payload: `{ pendingVentaId, paymentId, amount, capturedAt }`). 프론트엔드 PaymentSummaryModal 이 이 이벤트 수신 시 자동으로 `handleSubmit("INVOICED", paymentMethods)` 호출 (동일 효과 = Generar Venta 클릭). 같은 webhook 이 중복 도착해도 멱등성 보장 (DB UNIQUE on payment_id).
   - Acceptance: sandbox 결제 시뮬레이션 → 5초 이내 PaymentSummaryModal 자동 닫힘 + 판매 완료 + 영수증 출력 트리거 (auto impTiq 옵션 ON 시). 동일 webhook 2회 호출에도 sale 1건만 생성됨.

4. **MP-POS-04 — Polling fallback**: webhook 지연/실패 대비 프론트엔드가 5초 간격으로 결제 상태를 polling 한다.
   - Current: 결제 대기 상태 polling 메커니즘 없음.
   - Target: PaymentSummaryModal 의 QR 활성 동안 `GET /api/mercadopago/payment-intents/{intentId}` 5초마다 호출 (SWR refreshInterval 5000). 응답이 'approved' 시 webhook 경로와 동일한 자동 Generar Venta 동작 (양 경로 멱등). 만료/취소 시 polling 중단.
   - Acceptance: webhook 인위적으로 차단(테스트) + sandbox 결제 → 10초 이내 polling 으로 결제 감지 → 자동 Generar Venta. webhook 정상 + polling 동시 도착 시 sale 중복 생성 0.

5. **MP-POS-05 — Split payment (부분금액 MP)**: 한 sale 에서 MP 와 다른 결제수단을 혼합할 수 있고, MP QR 은 해당 부분금액에 대해서만 발급된다.
   - Current: PaymentSummaryModal 은 paymentMethods 배열 (multi-payment) 이미 지원. 그러나 mercadopago 는 placeholder 라 amount 분배 의미 없음.
   - Target: PaymentSummaryModal 에서 사용자가 MP 행에 amount 입력 (예: 총 50,000 중 30,000) → QR 생성 시 amount=30,000 만 MP 로. 나머지 20,000 은 cash/credit 등 다른 행. Generar Venta 는 MP 결제 confirmed + 다른 행 입력 완료 둘 다 충족 시 trigger. MP 결제만 confirmed 되고 다른 행 미입력이면 대기 (사용자가 cash 입력 필요).
   - Acceptance: 50,000 짜리 sale 에서 MP=30,000 + Efectivo=20,000 입력 → MP QR 표시 금액 = 30,000. sandbox 결제 30,000 처리 → Efectivo 입력란 활성 (대기). Efectivo 20,000 입력 → 자동 Generar Venta. 최종 sale 의 paymentMethods = [{slug:'mercadopago', amount:30000, mp_payment_id:...}, {slug:'efectivo', amount:20000}].

6. **MP-POS-06 — Sandbox/production 환경 토글**: store 별로 sandbox 또는 production MP 환경을 선택할 수 있다.
   - Current: MP 환경 토글 없음 (통합 자체가 없으므로).
   - Target: `store_mercadopago_accounts.environment ENUM('sandbox', 'production')`. OAuth 연결 화면에서 라디오 선택 → 해당 환경의 MP authorize URL 사용. 백엔드의 모든 MP API 호출은 store 의 environment 에 따라 host/credentials 분기. sandbox 매장은 production 매장과 격리 (cross-call 불가).
   - Acceptance: store A=sandbox, store B=production → A 의 결제 호출은 MP sandbox API 만 hit, B 는 production 만. environment 변경은 재 OAuth 강제 (기존 토큰 무효화).

7. **MP-POS-07 — 환불 자동 호출 (devolución)**: nullifySale (반품) 시 MP 결제분에 대해 자동으로 MP REST 환불을 호출한다.
   - Current: nullifySale 은 sales row + variant stock 만 조정, 외부 결제 게이트웨이 호출 없음.
   - Target: nullifySale 시 sale.paymentMethods 중 slug='mercadopago' + mp_payment_id 존재하면 backend 가 `POST /v1/payments/{mp_payment_id}/refunds` 호출 → 성공 시 `mp_refunds` row 생성 (refund_id, amount, status). 실패 시 sale 은 nullified 처리되 되, 프론트에 prominent alert (인라인 + 토스트) 표시 + MP dashboard 직접 처리 안내 링크. 가상 Caja MP 잔액에서 차감.
   - Acceptance: sandbox 에서 완료된 MP sale 1건 nullifySale 호출 → MP refund_id 응답 + mp_refunds DB row 생성 + Caja MP 잔액 동일액 차감. MP API 인위적 실패 시 sale 은 nullified, alert 표시, 사용자에게 manual 처리 가이드 노출.

## Boundaries

**In scope:**
- `store_mercadopago_accounts` 테이블 + OAuth 연결/해제 UI (configuracion 모듈)
- 토큰 암호화 저장 (access_token, refresh_token)
- QR Dinámico 생성 + nueva-venta 모달 표시 (3분 카운트다운 + 수동 취소)
- MP webhook receiver + 서명 검증 + idempotency
- Socket.io 게이트웨이 확장 (`mercadopago:approved` 이벤트, terminal room)
- 프론트엔드 자동 Generar Venta 트리거 + 5초 polling fallback
- Split payment (부분금액 MP + 나머지 cash/credit)
- "Caja Mercadopago" 가상 box 자동 생성 + MP 결제 시 자동 입금 (control-de-caja 통합)
- Sandbox/production environment 토글 (store 별)
- 환불 (nullifySale) 시 MP REST 자동 호출 + 실패 fallback UX
- E2E 테스트 (sandbox 결제 → 자동 Generar Venta → Caja MP 잔액 검증)

**Out of scope:**
- **Point Smart 단말기** — Phase 30 에서 처리 (물리 NFC/카드 결제, 별도 SDK)
- **Online Checkout Pro/Bricks** — Phase 31 에서 처리 (online_orders 결제 레이어)
- **마켓플레이스 split (커미션 분할 결제)** — Phase 24 (Revendedor Marketplace) 영역
- **Subscriptions** — SaaS 구독료 청구는 별도 (admin 모듈 미래 phase)
- **다중 통화** — Argentina ARS 단일, multi-currency 미지원
- **수수료/커미션 자동 추적** — MP fees 계산은 별도 보고서로 (Phase 32+ 후보)
- **이력 마이그레이션** — 기존 placeholder mercadopago slug 로 저장된 과거 sales 는 변환하지 않음 (placeholder 였음)
- **MP Cuenta Empresa 자동 KYC** — store owner 가 사전에 MP 계정/KYC 완료한 상태 가정

## Constraints

- **MP API rate limit**: QR 생성 endpoint 는 access_token 당 ~300 req/min 제한. 매장당 분당 100건 이상 결제는 비현실적이므로 일반 운영에는 영향 없으나, 부하 테스트 시 고려.
- **Webhook 멱등성**: 동일 payment.id 가 중복 webhook 으로 도착할 수 있음. `mp_payment_intents.payment_id UNIQUE` + 트랜잭션 처리로 멱등 보장.
- **Webhook 서명 검증 필수**: `x-signature` 헤더 HMAC SHA256 검증 통과 못하면 401. MP webhook secret 은 store 별 또는 글로벌 — 글로벌로 단순화 (env `MP_WEBHOOK_SECRET`).
- **토큰 암호화 저장**: access_token / refresh_token 은 AES-256-GCM 으로 암호화 후 DB 저장 (key 는 env `MP_TOKEN_ENCRYPTION_KEY`). 평문 저장 금지.
- **PostgreSQL pool 변경 금지** (CLAUDE.md 전역 규칙): 기존 max=50 풀 사용. MP 통합용 별도 pool 생성 금지. 모든 쿼리는 효율적으로 작성, slow query (>100ms) 즉시 최적화.
- **PG10/PG15 호환**: 마이그레이션 SQL 은 운영 PG10 + 로컬 PG15 양쪽에서 동작해야 함. `GENERATED AS IDENTITY` 등 PG10 미지원 기능 사용 금지 — `SERIAL` 사용.
- **Sequelize underscored**: 모델 camelCase → DB snake_case 자동 매핑. SQL 직접 실행 시 snake_case 사용 (CLAUDE.md 규칙).
- **ESLint Warning = build error**: newline-before-return, lines-around-comment 등 빌드 에러로 처리. 모든 코드 lint 통과 필수.
- **에러 메시지 prominent 노출** (memory feedback_error_visibility): MP 환불 실패, OAuth 만료 등 모든 MP 관련 에러는 인라인 Alert + 글로벌 toast 양쪽에 표시.
- **OAuth refresh 처리** (discuss-phase 에서 세부 결정): refresh_token 만료 시 사용자에게 재연결 요구. expires_at 임박(D-7) 시 알림 — 세부 UX 는 discuss-phase.
- **결제 중 인터넷 끊김** (discuss-phase 에서 세부 결정): 고객 결제 완료 후 매장 인터넷 끊겨 webhook + polling 둘 다 실패 시 — 복구 시점에 polling 재개로 회복. 기본 정책은 "결제 자체는 MP 측 record 로 정합" — manual recovery 도구 제공 여부는 discuss-phase.
- **Sandbox/Production 키 분리**: env 변수 prefix `MP_PRODUCTION_*` / `MP_SANDBOX_*` 으로 명확히 분리.

## Acceptance Criteria

- [ ] `store_mercadopago_accounts` 테이블 마이그레이션 적용 (PG10/PG15 양쪽 검증)
- [ ] OAuth 연결: sandbox 계정으로 connect 완료 시 DB row 1개 + 토큰 암호화 저장 (평문 아님 검증)
- [ ] 첫 연결 성공 시 해당 store 에 "Caja Mercadopago" 가상 box 정확히 1개 생성
- [ ] OAuth 재연결: 새 row 아닌 update, disconnected_at NULL
- [ ] nueva-venta PaymentSummaryModal 에 "Mercadopago QR" 옵션 노출 (MP 미연결 store 는 disabled + tooltip)
- [ ] MP 선택 + 금액 입력 시 backend QR 생성 + 모달에 QR 이미지 + 3:00 카운트다운 표시
- [ ] 3분 경과 시 자동 expired + 결제수단 선택으로 복귀
- [ ] "Cancelar QR" 클릭 시 즉시 expired
- [ ] sandbox 결제 시뮬레이션 → 5초 이내 모달 자동 닫힘 + sale INVOICED 생성 + 영수증 출력 트리거
- [ ] webhook 중복 호출 (동일 payment.id 2회) → sale 1건만 생성 (멱등)
- [ ] webhook 차단 + polling 만으로도 10초 이내 결제 감지
- [ ] webhook 서명 검증 실패 시 401 반환
- [ ] split: MP=30000 + Efectivo=20000 sale 정상 생성, sale.paymentMethods 배열에 mp_payment_id 포함
- [ ] sandbox store 와 production store 의 MP API 호출 host 가 분리되어 cross-call 발생 안 함
- [ ] environment 변경 시 기존 토큰 무효화 + 재 OAuth 요구
- [ ] nullifySale (MP sale) → MP refund REST 자동 호출 + mp_refunds row 생성 + Caja MP 잔액 차감
- [ ] MP refund 실패 시 sale nullified + 인라인 Alert + 글로벌 toast + manual MP dashboard 링크 노출
- [ ] 모든 MP 관련 코드 ESLint 통과 (Warning 0)
- [ ] PostgreSQL pool 사용량 변경 없음 (max=50 유지, MP 통합 후 connection 낭비 없음 검증)
- [ ] sandbox 환경 E2E 테스트 1건 (connect → sale → MP 결제 → 자동 Generar Venta → Caja MP 검증) 통과

## Ambiguity Report

| Dimension          | Score | Min  | Status | Notes                                            |
|--------------------|-------|------|--------|--------------------------------------------------|
| Goal Clarity       | 0.90  | 0.75 | ✓      | 자동 Generar Venta + 7개 구체 요구사항             |
| Boundary Clarity   | 0.85  | 0.70 | ✓      | Split / Caja MP / Sandbox 명시. Phase 30/31 분리  |
| Constraint Clarity | 0.70  | 0.65 | ✓      | OAuth refresh / 인터넷 끊김 세부는 discuss-phase  |
| Acceptance Criteria| 0.75  | 0.70 | ✓      | 20개 pass/fail 체크박스                          |
| **Ambiguity**      | 0.18  | ≤0.20| ✓      | Gate passed                                      |

Status: ✓ = met minimum, ⚠ = below minimum (planner treats as assumption)

## Interview Log

| Round | Perspective                | Question summary                          | Decision locked                                              |
|-------|----------------------------|-------------------------------------------|--------------------------------------------------------------|
| 0     | Pre-interview (사전 합의)  | MP product / 계정 단위 / 환불 / timeout   | QR Dinámico only / store 단위 / 환불 포함 / 3분+수동취소     |
| 1     | Boundary + Failure 통합    | Split / Reconciliation / Sandbox          | Split=Yes(부분금액) / Caja MP 가상 box / Sandbox toggle 포함 |

**Pre-interview 합의** (이 spec-phase 직전 채팅에서 이미 lock):
- MP 제품: QR Dinámico 만 Phase 29 (Point 단말기 = Phase 30, Online = Phase 31)
- 계정 단위: store_id 단위 (한 store = 한 MP account, 모든 vendedor 공유)
- 환불: Phase 29 마지막 plan 에 포함 (REST 자동 환불)
- 만료/취소: 3분 timeout + 수동 취소 + webhook 실패 시 expired

**Round 1 결정**:
- Split payment: YES — 부분금액 MP QR (MP=30K + cash=20K 등 자유)
- Reconciliation: 가상 "Caja Mercadopago" box 자동 생성 + MP 입금 자동 반영
- Sandbox 환경: store_mercadopago_accounts.environment 토글 포함 (sandbox|production)

**Discuss-phase 로 위임된 세부 사항**:
- OAuth refresh_token 만료 시 UX (재연결 강제 시점, 알림 D-day)
- 결제 중 매장 인터넷 끊김 시 manual recovery 도구 (있을지/없을지)
- MP webhook secret: 글로벌 1개 vs store 별 분리

---

*Phase: 29-pos-mercadopago-qr-din-mico*
*Spec created: 2026-05-05*
*Next step: /gsd-discuss-phase 29 — implementation decisions (OAuth flow 세부, 토큰 암호화 키 관리, Caja MP 트랜잭션 패턴, webhook secret 정책 등)*
