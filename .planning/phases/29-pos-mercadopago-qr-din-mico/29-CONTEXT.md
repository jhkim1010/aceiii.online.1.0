# Phase 29: POS Mercadopago — QR Dinámico - Context

**Gathered:** 2026-05-05
**Status:** Ready for planning

<domain>
## Phase Boundary

매장 내 결제수단 "Mercadopago" 선택 시 백엔드가 QR Dinámico 를 발급하고, 고객이 MP 앱으로 스캔/결제하면 webhook + Socket.io 를 통해 해당 terminal 에서 자동 Generar Venta 가 트리거된다. OAuth 계정은 store-level 또는 branch-level 로 자유롭게 설정 가능. 가상 "Caja Mercadopago" wallet 자동 정산, sandbox/production 토글, split payment, 환불 자동 호출까지 포함.

</domain>

<spec_lock>
## Requirements (locked via SPEC.md)

**7 requirements are locked.** See `29-SPEC.md` for full requirements, boundaries, and acceptance criteria.

Downstream agents (researcher, planner, verifier) MUST read `29-SPEC.md` before planning or implementing. Requirements are not duplicated here.

**In scope (from SPEC.md):**
- 신규 테이블 6종: `mp_accounts` / `mp_payment_intents` / `mp_wallets` / `mp_movements` / `mp_refunds` / `mp_refund_attempts`
- OAuth 연결/해제 UI (`configuracion/mercadopago` 신규 페이지) — store + branch 독립 설정
- 토큰 암호화 저장 (AES-256-GCM, 단일 master env key)
- QR Dinámico 생성 + nueva-venta 모달 표시 (3분 카운트다운 + 수동 취소, qr_data string + qrcode.react 렌더)
- MP webhook receiver (글로벌 secret) + 서명 검증 + payment_id UNIQUE idempotency
- websocket.gateway 신규 메서드 `emitToTerminal(terminalId, event, payload)` + 프론트 자동 `terminal:{id}` room join
- 프론트엔드 자동 Generar Venta 트리거 + SWR refreshInterval=5000 polling fallback
- Split payment (부분금액 MP + 나머지 cash/credit)
- "Caja Mercadopago" 가상 wallet 자동 생성 + control-de-caja 통합 + "MP→현금" 수동 이체 버튼
- Sandbox/production environment 토글 + nueva-venta 주황 sandbox 배너 + QR 모달 주황 테두리
- 환불 자동 호출 + 실패 시 인라인 Alert + 토스트 + 재시도 버튼 + MP Dashboard 링크 + mp_refund_attempts 기록
- Sandbox E2E 테스트

**Out of scope (from SPEC.md):**
- Point Smart 단말기 → Phase 30
- Online Checkout Pro/Bricks → Phase 31
- 마켓플레이스 split (커미션 분할) → Phase 24 영역
- Subscriptions, multi-currency, 수수료 자동 추적, MP KYC 자동화, 이력 마이그레이션

</spec_lock>

<decisions>
## Implementation Decisions

### OAuth + 토큰 인프라

- **D-A1-01**: MP Developer App 은 **통합 1개** 등록. Sandbox/Production 분기는 환경 변수 prefix `MP_PRODUCTION_*` / `MP_SANDBOX_*` 로 분리. 운영 단순화 우선.
- **D-A1-02**: OAuth 계정 단위 = **store-level 기본 + branch-level 옵션**. 신규 테이블 `mp_accounts(id, store_id NOT NULL, branch_id NULLABLE, mp_user_id, access_token, refresh_token, public_key, environment, expires_at, connected_at, disconnected_at)`. 결제 시 lookup precedence: **branch 매칭 우선 → store-level fallback**. UNIQUE 제약: `(store_id, COALESCE(branch_id, 0))`.
- **D-A1-03**: Callback URL = **공용 endpoint** `https://newapi.coolsistema.com/api/mercadopago/oauth/callback`. OAuth state 파라미터에 `(storeId, branchId|null, nonce)` HMAC 서명 → callback 에서 검증 후 적절한 mp_account row 생성/업데이트. 안티-CSRF 보장.
- **D-A1-04**: Refresh 토큰 만료 처리 = **lazy + D-7 사전 알림**. API 호출 시점에 만료/임박이면 자동 refresh 시도. 만료 D-7 시 store admin 에 in-app 알림 + email 안내. refresh 실패 시 사용자에게 재 OAuth 강제 (mp_account.disconnected_at 설정 + UI alert).
- **D-A1-05**: 토큰 암호화 = **AES-256-GCM**, master key = `MP_TOKEN_ENCRYPTION_KEY` 단일 env (Docker secret). access_token + refresh_token 컬럼은 `${iv}:${authTag}:${ciphertext}` base64 포맷. 평문 저장 금지.

### Webhook 보안 + 알림 wiring

- **D-A2-01**: Webhook secret = **글로벌 1개** (env `MP_WEBHOOK_SECRET`). MP App 의 단일 webhook secret 으로 모든 결제 webhook 검증. `x-signature` 헤더 HMAC SHA256 검증, 실패 시 401.
- **D-A2-02**: 결제 알림 emit 패턴 = **신규 메서드 `emitToTerminal(terminalId, event, payload)`** 추가 (`api-ventago/src/common/socket/websocket.gateway.ts`). 프론트는 connect 시 사용자의 cashRegister.terminal.id 로 자동 `terminal:{id}` room 에 join. webhook → 정확한 terminal 만 `mercadopago:approved` 이벤트 수신.
- **D-A2-03**: Polling fallback = **SWR `useSWR(/api/mercadopago/payment-intents/${id}, fetcher, { refreshInterval: 5000 })`**. QR 모달 unmount 시 SWR 자동 stop. webhook 도착 후엔 mutate 로 즉시 갱신.
- **D-A2-04**: 멱등성 = **`mp_payment_intents.payment_id UNIQUE` + 트랜잭션 wrapping**. webhook 핸들러와 polling 핸들러 모두 동일 SQL transaction 안에서 SELECT FOR UPDATE → status 검사 → sale 생성. 두 번째 도착 경로는 already-processed 로 즉시 종료. Redis lock 같은 추가 인프라 없이 DB 단독으로 멱등 보장.

### Caja MP 데이터 모델

- **D-A3-01**: 가상 caja 저장 = **신규 테이블 `mp_wallets`** (`id, mp_account_id FK UNIQUE, store_id, branch_id NULLABLE, balance NUMERIC(14,2) DEFAULT 0, currency='ARS', last_synced_at`). mp_accounts 와 1:1. 기존 `box` 테이블은 건드리지 않음 — `box.branchId NOT NULL` 제약과 충돌하지 않도록 분리. Area 1 의 store/branch scope 와 자연스럽게 일치.
- **D-A3-02**: MP 입출금 기록 = **신규 테이블 `mp_movements`** (`id, mp_wallet_id FK, type 'credit'|'debit', amount NUMERIC(14,2), sale_id NULLABLE FK, refund_id NULLABLE FK, mp_payment_id, transfer_id NULLABLE, note, created_at`). 기존 `movements` 테이블 (box 의존)과 분리. balance = sum(credit) − sum(debit). UI 에서는 mp_wallets.balance 캐시 컬럼 사용 + nightly reconciliation cron 으로 검증.
- **D-A3-03**: Caja MP→현금 이체 = **Phase 29 포함**. control-de-caja UI 에 "Transferir MP→Caja física" 버튼. 사용자 입력: 금액 + 대상 box_id (해당 store/branch 의 물리 caja). 트랜잭션: `mp_movements (debit, type='transfer_out')` + `movements (credit, type='mp_transfer')` + `mp_wallets.balance` / `box.balance` 동기화. 신규 테이블 `mp_transfers(id, mp_wallet_id, target_box_id, amount, user_id, transferred_at)` 으로 추적.
- **D-A3-04**: control-de-caja 리포트 표시 = **기존 표에 "Caja Mercadopago" 행 추가**. 일별 잔액/입금/출금 표시. 행 클릭 시 mp_movements 상세 모달 (sale_id 클릭으로 해당 sale 으로 navigate). 별도 reports/mercadopago 페이지는 만들지 않음 (UX 통일).

### UI 세부

- **D-A4-01**: QR 렌더 = **백엔드는 qr_data string 만 반환, 프론트가 `qrcode.react` 패키지로 렌더**. ventago-app/package.json 에 `qrcode.react` 추가. PaymentSummaryModal 안에 `<QRCodeSVG value={qrData} size={256} />` 형태로 동적 렌더. 해상도/색상/error correction 레벨 자유 조정.
- **D-A4-02**: Sandbox 시각 구분 = **이중 표시**. (1) nueva-venta 페이지 상단 주황(`#f5a623` 골드 톤 활용 가능) `<Alert severity="warning">🧪 SANDBOX MERCADOPAGO</Alert>` 배너 — sandbox mp_account 가 활성일 때만 노출. (2) QR 모달 border 색상 `warning.main`. 운영 매장이 실수로 테스트 결제 받지 않도록.
- **D-A4-03**: 환불 실패 UX = **인라인 Alert + 글로벌 Toast + 재시도 버튼 + MP Dashboard 링크 + 시도 기록**. SalesDetailView 의 nullify 결과 영역에 `<Alert severity="error">` 표시: "MP 환불 자동 호출 실패. 재시도 또는 MP Dashboard 에서 수동 처리." `<Button>Reintentar</Button>` 클릭 시 백엔드 retry endpoint 호출. `<Link href="https://www.mercadopago.com.ar/activities">MP Dashboard 열기</Link>` 외부 링크. 모든 시도는 `mp_refund_attempts(id, sale_id, mp_payment_id, attempt_no, status, error_message, attempted_at)` 에 기록 — 재시도 횟수 제한 없음 (사용자 액션).
- **D-A4-04**: OAuth 연결/해제 UI = **신규 페이지 `configuracion/mercadopago`** (사이드바 "Configuración" 하위 새 메뉴). 페이지 구조:
  - 상단: store-level MP 연결 카드 (연결 상태 / Last seen / environment 배지 / 연결-해제 버튼)
  - 중단: 각 branch 명세 표 — branch name + "Branch 전용 MP" toggle. toggle ON 시 OAuth flow 시작, branch_id 가 state 에 포함됨. OFF 시 store-level 사용.
  - 모든 mp_account row 의 expires_at D-7 이내 → 빨간 경고 배지

### Claude's Discretion

다음 항목은 planner/researcher 가 결정 가능:
- mp_payment_intents 컬럼 세부 (status enum 값, expires_at 정확 타입 등)
- websocket room 명명 규칙 (예: `terminal:{id}` vs `t:{id}`)
- qrcode.react 의 size/level 등 시각 디테일
- configuracion/mercadopago 페이지의 정확한 MUI 레이아웃 (Card vs DataGrid 등)
- mp_transfers 테이블의 status 컬럼 추가 여부 (이체 실패 처리)
- API endpoint 정확한 path 구조 (`/api/mercadopago/qr` vs `/api/mp/qr` 등)

### Folded Todos

(없음 — Phase 29 관련 todo 0건)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 29 핵심 문서
- `.planning/phases/29-pos-mercadopago-qr-din-mico/29-SPEC.md` — **Locked requirements (7개 + 21 acceptance criteria) — MUST 읽고 planning**
- `CLAUDE.md` (project root) — Ventago 아키텍처 핵심 규칙 (snake_case DB, postgres pool 변경 금지, ESLint warning=error 등)
- `~/.claude/CLAUDE.md` (global) — postgresql pool 낭비 방지 등 글로벌 규칙

### Mercadopago 외부 문서 (외부 — 작업 시 fetch)
- MP QR Dinámico API: https://www.mercadopago.com.ar/developers/es/docs/qr-payments/integration-configuration/integration-api/qr-dynamic
- MP OAuth 2.0: https://www.mercadopago.com.ar/developers/es/docs/security/oauth/landing
- MP Webhooks: https://www.mercadopago.com.ar/developers/es/docs/your-integrations/notifications/webhooks
- MP Refunds API: https://www.mercadopago.com.ar/developers/es/reference/chargebacks/_payments_id_refunds/post

### 기존 codebase 분석
- `.planning/codebase/INTEGRATIONS.md` — Socket.io gateway 패턴, MinIO 사용법
- `.planning/codebase/CONVENTIONS.md` — Sequelize underscored, ESLint 규칙
- `.planning/codebase/STRUCTURE.md` — 모듈 구성 규칙
- `.planning/codebase/STACK.md` — NestJS 11 / Sequelize / Next.js 13 버전 정보

### 마이그레이션 SQL 위치
- `api-ventago/migrations/` — Phase 29 신규 테이블 SQL 파일 위치 (PG10/PG15 양쪽 호환 필수)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **WebSocket gateway** (`api-ventago/src/common/socket/websocket.gateway.ts`): 이미 `emitToStore`, `emitToUser`, `emitToApiKey` 메서드 존재. Phase 29 는 신규 `emitToTerminal(terminalId, event, payload)` 메서드 추가만 하면 됨. 패턴 참조: `emitToApiKey` (room: `apiKey:{key}`) → 새 패턴 (room: `terminal:{id}`).
- **payment_methods 시드** (`api-ventago/src/app/payment-methods/seed/payment-methods.seed.ts`): `mercadopago` slug 가 이미 placeholder 로 시드되어 있음. Phase 29 는 그대로 재사용 — 신규 slug 추가 불필요.
- **PaymentSummaryModal** (`ventago-app/src/views/homes/components/ProductList/components/PaymentSummaryModal.tsx`): 이미 multi-payment-method 배열 구조 지원. MP 행 추가 + amount 입력 + QR 표시 영역 확장만 필요.
- **MemoryCacheService** (`api-ventago/src/common/cache/memory-cache.service.ts`): MP API rate limit 캐시 / mp_wallet.balance 캐시 등에 활용 가능 (60초 TTL).
- **handleSubmit("INVOICED", paymentMethods)** (`ProductList.tsx:1153`): "Generar Venta" 버튼이 호출하는 함수 — Socket.io 이벤트 수신 시 이 함수를 직접 호출하면 자동 Generar Venta 됨.
- **Sequelize-typescript 모델 패턴**: 6개 신규 모델 (`mp_accounts.model.ts`, `mp_payment_intents.model.ts`, `mp_wallets.model.ts`, `mp_movements.model.ts`, `mp_refunds.model.ts`, `mp_refund_attempts.model.ts`, `mp_transfers.model.ts`) 는 기존 `box.model.ts`, `terminal.model.ts` 패턴 그대로 답습.

### Established Patterns

- **DB underscored**: 모델 camelCase → DB snake_case 자동 매핑. 신규 컬럼명 모델에서 camelCase 작성. 마이그레이션 SQL 만 snake_case.
- **모듈 구조**: `api-ventago/src/app/{module-name}/` 표준. Phase 29 는 신규 모듈 `mercadopago/` 신설. `mercadopago.module.ts`, `mercadopago.service.ts`, `mercadopago.controller.ts`, `mercadopago.gateway-extension.ts` (or websocket.gateway.ts 직접 수정).
- **DTO 패턴**: `create-mp-qr.dto.ts`, `mp-webhook.dto.ts` 등 — class-validator 데코레이터로 검증.
- **에러 handling**: NestJS `BadRequestException`, `UnauthorizedException` 사용. 프론트는 `apiConnector` 의 axios interceptor 가 toast 자동 표시.
- **SWR 5분 dedup**: 참조 데이터는 5분 dedup, 결제 polling 은 5초 refreshInterval — 다른 정책.
- **MUI 기반 UI**: configuracion/mercadopago 페이지는 MUI Card + Table 조합. PaymentSummaryModal 확장도 MUI Dialog/Box 그대로.

### Integration Points

- **사이드바 네비게이션**: `ventago-app/src/navigation/vertical/index.ts` 에 "Configuración > Mercadopago" 메뉴 추가.
- **CASL 권한**: 신규 function slug `mercadopago_admin` (or 기존 `configuracion_admin` 재사용) — Phase 14 권한 시스템과 통합.
- **AuthContext + BranchContext**: branch-level OAuth 시 현재 selectedBranch 활용 (BranchContext 에서 가져옴).
- **api.service.ts apiConnector**: 모든 MP API 호출은 `apiConnector.post(...)` / `apiConnector.get(...)` 통해 수행 (자동 sessionToken 헤더 + auth).
- **migrations 폴더**: `api-ventago/migrations/29-XX-mercadopago-*.sql` 파일들. PG10/PG15 양쪽 호환 검증.

</code_context>

<specifics>
## Specific Ideas

- 사용자의 "각 store / 각 sucursal 마다 독립 토큰" 요구 → mp_accounts 의 (store_id, branch_id) 복합 scope 모델로 정확히 매핑
- nueva-venta 결제 흐름: 사용자가 강조한 핵심 UX = "MP 결제 들어오면 그냥 자동으로 Generar Venta 버튼이 눌러지게" → emitToTerminal 새 메서드 + handleSubmit("INVOICED", ...) 자동 호출 + 인라인 toast "결제 완료 — 판매 생성 중..."
- "Caja Mercadopago" 명칭은 control-de-caja 등 모든 UI 에서 동일 (Spanish 우선, 일관성)
- "Transferir MP→Caja" 이체 버튼은 admin/gerente 권한만. vendedor 는 비활성

</specifics>

<deferred>
## Deferred Ideas

- **MP 수수료 자동 추적/계산** → Phase 32+ (별도 보고서)
- **MP Cuenta Empresa 자동 KYC** → MP API scope 외, 운영 절차로 처리
- **이력 sales 마이그레이션** (placeholder mercadopago 였던 과거 sales) → 변환 안 함 (placeholder 였음)
- **Point Smart 단말기 연동** → Phase 30
- **Online Checkout Pro / Bricks** → Phase 31
- **마켓플레이스 split payment** → Phase 24 영역
- **multi-currency 지원** → out of scope, ARS only

### Reviewed Todos (not folded)

(없음 — 관련 todo 0건)

</deferred>

---

*Phase: 29-pos-mercadopago-qr-din-mico*
*Context gathered: 2026-05-05*
*Next step: /gsd-plan-phase 29 — research + plan 분해 (예상 5–7 plans)*
