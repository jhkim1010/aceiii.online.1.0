# Ventago ↔ Mercadopago 연동 메뉴얼

POS/ERP 시스템(Ventago)과 Mercadopago(이하 MP) 결제 연동 기능의 **전체 운영 메뉴얼**.
대상: 운영 엔지니어, 매장 관리자(admin), 판매원(vendedor), 개발자.

> 구현 출처: **Phase 29 — POS Mercadopago QR Dinámico**
> 백엔드 모듈: `api-ventago/src/app/mercadopago/`
> 프론트엔드: `ventago-app/src/views/mercadopago/`, `configuracion/mercadopago`
> DB: `mp_*` 7개 테이블 (마이그레이션 `api-ventago/migrations/29-01 ~ 29-05`)

> 🇪🇸 Versión en español: [`mercadopago-manual.es.md`](mercadopago-manual.es.md)

---

## 1. 한눈에 보는 기능 요약

| 기능 | 설명 |
|------|------|
| **OAuth 계정 연결** | 매장이 자기 MP 사업자 계정을 OAuth 로 연결. store 전체용 + 각 지점(branch)별 독립 연결 가능 |
| **QR Dinámico 결제** | POS 결제 모달에서 "Mercadopago QR" 선택 → QR 생성 → 고객 스캔/결제 |
| **자동 Generar Venta** | 결제 승인되면 webhook + Socket.io 로 해당 터미널에 푸시 → 판매 자동 완료 |
| **Polling fallback** | webhook 지연/실패 시 5초 간격 polling 으로 결제 감지 |
| **Split 결제** | 한 판매에서 MP + 현금 등 혼합 결제. MP 는 부분 금액만 QR 발급 |
| **가상 Caja Mercadopago** | MP 결제 수금액을 가상 지갑(wallet)에 자동 적립. control-de-caja 에서 조회 + 현금 이체 |
| **자동 환불(devolución)** | 판매 취소(nullifySale) 시 MP 결제분 자동 환불 REST 호출 + 실패 시 재시도 UX |
| **Sandbox/Production 토글** | 계정별로 테스트/운영 환경 분리. 같은 매장 안에서도 혼합 가능 |
| **토큰 자동 갱신** | OAuth refresh_token 으로 매일 새벽 자동 갱신 |

---

## 2. 아키텍처 개요

```
┌──────────────┐     OAuth      ┌────────────────────┐
│  매장 관리자  │ ────────────▶ │  Mercadopago       │
│ (admin)      │   연결/해제    │  (auth + api)      │
└──────────────┘                └─────────┬──────────┘
                                          │
┌──────────────┐  QR 생성 요청            │ access_token (암호화 저장)
│  POS 판매원   │ ──────────┐              │
│ (vendedor)   │           ▼              ▼
└──────┬───────┘   ┌──────────────────────────────────┐
       │           │  api-ventago (NestJS)             │
       │ Socket.io │  app/mercadopago/                 │
       │◀──────────│   - OAuth / QR / Webhook / Refund │
       │ mercado   │   - Wallet / Transfer / Cron      │
       │  pago:    │   - AES-256-GCM token crypto      │
       │ approved  │   PostgreSQL: mp_* 7개 테이블      │
       │           └──────────────┬───────────────────┘
       ▼                          │ webhook (payment 승인)
┌──────────────┐                  ▼
│ 고객 휴대폰   │  QR 스캔   ┌────────────────────┐
│ (MP 앱)      │ ─────────▶│  Mercadopago        │
└──────────────┘   결제     └────────────────────┘
```

**핵심 설계 원칙**

- **MP API host 는 sandbox/production 동일** (`https://api.mercadopago.com`). 차이는 **credentials + access_token** 뿐 (`MP_SANDBOX_*` vs `MP_PRODUCTION_*`).
- **Webhook 은 신뢰하지 않고 항상 재조회**: QR notification 에는 서명 검증이 불가하므로(MP 제약), webhook 수신 시 항상 `GET /v1/payments/{id}` 로 진실을 재확인.
- **Webhook 즉시 200 응답 + 비동기 처리**: MP 22초 timeout 회피. 처리 실패해도 polling 으로 회복.
- **토큰 평문 저장 금지**: access/refresh token 은 AES-256-GCM 암호화(`iv:tag:ciphertext` 포맷)로 저장. API 응답에 절대 노출 안 됨.
- **계정 lookup precedence**: 결제 시 `branch_id` 매칭 우선 → 없으면 store-level(`branch_id NULL`) fallback.

---

## 3. 사전 준비 (Mercadopago 측)

> 상세 절차: `docs/phase29-ops-mp-app-setup.md`

1. **MP 사업자 계정**: 매장 소유자가 MP Cuenta Empresa + KYC 완료 상태여야 함.
2. **MP 운영 앱 생성** — https://www.mercadopago.com.ar/developers/panel → "Crear aplicación"
   - Solution: `Pagos online y presenciales`, Product: `QR Dinámico` + `Checkout`
   - 결과로 나오는 **Client ID / Client Secret (production)** 기록
3. **MP Sandbox 앱 / Test users 생성** — 같은 패널 → `Test users`
   - 테스트 판매자(Vendedor) + 테스트 구매자(Comprador) 계정 생성
   - sandbox Client ID / Client Secret 기록
4. **Redirect URI 등록** (운영 + sandbox 앱 양쪽 OAuth 설정)
   ```
   https://newapi.coolsistema.com/api/mercadopago/oauth/callback
   ```
5. **Webhook URL 등록** (운영 앱)
   ```
   https://newapi.coolsistema.com/api/mercadopago/webhook
   ```
   - 구독 이벤트: `payment` 만 (merchant_order 불필요)

---

## 4. 환경변수 설정 (백엔드)

`api-ventago` 컨테이너에 아래 환경변수를 주입해야 한다. 운영서버(srv803182)에서는 Docker compose env 에 설정.

| 변수 | 용도 | 비고 |
|------|------|------|
| `MP_PRODUCTION_CLIENT_ID` | 운영 앱 OAuth client id | Step 3-2 |
| `MP_PRODUCTION_CLIENT_SECRET` | 운영 앱 OAuth secret | |
| `MP_SANDBOX_CLIENT_ID` | sandbox 앱 client id | Step 3-3 |
| `MP_SANDBOX_CLIENT_SECRET` | sandbox 앱 secret | |
| `MP_TOKEN_ENCRYPTION_KEY` | 토큰 AES-256-GCM 마스터키 | **64자 hex (32바이트)**. `openssl rand -hex 32` |
| `MP_OAUTH_STATE_SECRET` | OAuth state HMAC (CSRF 방지) | `openssl rand -hex 32` |
| `MP_WEBHOOK_SECRET` | webhook HMAC secret (글로벌) | MP 패널에 있으면 입력, 없으면 빈 값 |
| `MP_NOTIFICATION_BASE_URL` | 콜백/webhook base URL | 기본값 `https://newapi.coolsistema.com/api` |

> ⚠️ **마스터키 분실 주의**: `MP_TOKEN_ENCRYPTION_KEY` 를 분실하면 저장된 모든 MP 토큰을 복호화할 수 없어 모든 매장이 재-OAuth 해야 한다. **반드시 비밀 금고(1Password/Bitwarden)에 보관.** 절대 CI/운영서버에서 생성하지 말고 ops 로컬에서만 생성.

**부팅 검증 (fail-fast)**: `MP_TOKEN_ENCRYPTION_KEY` 길이가 틀리면 백엔드가 부팅 단계에서 즉시 실패한다.
```
Error: MP_TOKEN_ENCRYPTION_KEY must be 32 bytes hex (64 hex chars)
```
확인: `docker logs api_ventago | tail -30` — 위 에러 없으면 정상.

검증 위치: `crypto/mp-token-crypto.service.ts`, `oauth/mp-oauth.service.ts`, `api-client/mp-api-client.service.ts`

---

## 5. DB 마이그레이션

> 상세 실행 가이드: `api-ventago/migrations/29-RUN.md`

**순서대로** 5개 SQL 을 적용한다 (멱등성 보장 — 재실행 안전):

```
29-01-mp-accounts.sql          # OAuth 토큰 + scope (store/branch)
29-02-mp-payment-intents.sql   # QR 결제 의도 + payment_id UNIQUE 멱등성
29-03-mp-wallets-movements.sql # 가상 Caja MP + 입출금 원장
29-04-mp-refunds.sql           # 환불 + 시도 audit
29-05-mp-transfers.sql         # MP→Caja 이체
```

운영(PG10) 적용 예 — **DDL 이므로 사용자 확인 필수**:
```bash
for f in 29-01-mp-accounts.sql 29-02-mp-payment-intents.sql \
         29-03-mp-wallets-movements.sql 29-04-mp-refunds.sql 29-05-mp-transfers.sql; do
  ssh jhkim-server "sudo -u postgres psql -d ventago -v ON_ERROR_STOP=1" \
      < api-ventago/migrations/$f && echo "✓ $f" || { echo "✗ $f"; break; }
done
```

검증 — 정확히 7개 테이블 존재 확인:
```sql
SELECT table_name FROM information_schema.tables
 WHERE table_schema='public' AND table_name LIKE 'mp_%' ORDER BY table_name;
-- mp_accounts, mp_movements, mp_payment_intents, mp_refund_attempts,
-- mp_refunds, mp_transfers, mp_wallets
```

긴급 롤백: `29-99-rollback.sql` (단, Sequelize 모델 배포 후에는 사용 금지 — DB/코드 불일치).

---

## 6. OAuth 계정 연결 (매장 관리자 절차)

**화면 위치**: 로그인(admin) → **Configuración → Mercadopago** (페이지: `configuracion/mercadopago`, 뷰: `McdpgConfigView.tsx`)
※ 2026-05-13 이후 "Preferencias" 통합 페이지 안에 포함됨.

**권한**: `admin`, `superadmin` 만 연결/해제 가능.

### 연결 절차

1. 환경 토글(라디오)에서 **sandbox** 또는 **production** 선택.
2. store 전체용으로 연결하거나, 특정 지점(branch)별 토글로 독립 연결.
3. **"Conectar cuenta Mercadopago"** 클릭.
4. 브라우저가 MP 인증 페이지(`auth.mercadopago.com.ar/authorization?...&state=<HMAC>`)로 이동.
5. MP 사업자(또는 테스트 판매자) 계정으로 로그인 + 권한 승인.
6. 콜백 후 `/configuracion/mercadopago?ok=1` 로 복귀. 계정 카드에 `✓ Conectada` (+ sandbox 면 `🧪 SANDBOX` 칩) 표시.

### 내부 동작 (콜백 시 자동 수행)

`oauth/mp-oauth.service.ts`:
- state HMAC 검증(CSRF 방지) → `/oauth/token` 으로 code↔token 교환
- access/refresh token **암호화 저장** → MP **Store/POS 등록**(`MpStorePosService`) → `external_pos_id` 확보
- 같은 (store_id, branch_id) scope 의 **`mp_wallets` 가상 지갑 1개 자동 생성** (잔액 0)

### 재연결 / 해제

- **재연결**: 같은 scope 재연결 시 새 row 가 아니라 **update** + `disconnected_at = NULL`.
- **환경 변경**: environment 를 바꾸면 기존 토큰 무효화 → 재-OAuth 필요.
- **연결 해제**: 계정 카드의 disconnect → `POST /mercadopago/oauth/disconnect/:accountId`. **soft delete** (`disconnected_at` 만 set, 데이터 보존) + Audit 로그 기록.

### 계정 scope 규칙

- store-level 1개 (`branch_id NULL`) + 지점마다 1개 가능. UNIQUE 제약: `uniq_mp_accounts_store_only`, `uniq_mp_accounts_store_branch`.
- 결제 시 lookup: **branch 매칭 우선 → store-level fallback**.

---

## 7. POS QR 결제 흐름 (판매원)

**화면**: `nueva-venta` → 결제 모달 `PaymentSummaryModal.tsx`

1. 상품을 장바구니에 담고 **Generar Venta(F2)** 또는 결제 버튼 → 결제 모달 오픈.
2. 결제수단 **"Mercadopago QR"** 선택 + 금액 입력.
   - 해당 (store, branch) scope 에 연결된 MP 계정이 없으면 옵션이 **disabled** + 안내 tooltip.
3. 백엔드가 QR 생성(`POST /mercadopago/qr`) → 모달 우측 패널에 **QR 코드 + 3:00 카운트다운** 표시.
   - sandbox 계정이면 상단에 **주황 SANDBOX 배너** + QR 모달 **주황 테두리** (`SandboxMpBanner.tsx`).
4. 고객이 MP 앱으로 QR 스캔 → 결제.
5. 결제 승인 → **자동으로 판매 완료(Generar Venta 트리거)** → 모달 자동 닫힘 + 토스트 "✓ Pago Mercadopago recibido".
6. 미결제 상태에서 **"Cancelar QR"** 클릭 또는 3분 경과 시 → intent expired/cancelled, 결제수단 선택으로 복귀.

**QR 만료**: 3분(`expires_at`). 만료 시 자동 expired 처리.

---

## 8. 자동 결제 감지 (Webhook + Polling)

두 경로가 **멱등하게** 동작하며 어느 쪽이 먼저 도착해도 판매는 1건만 생성된다.

### Webhook 경로 (주 경로, ~5초)

- `POST /mercadopago/webhook` (인증 없음 `@Public`) — MP 가 직접 호출.
- 즉시 **200 응답** + `setImmediate` 비동기 처리 (`webhook/mp-webhook.service.ts`).
- payment.id 로 `GET /v1/payments/{id}` **재조회** → `external_reference` 로 `mp_payment_intents` 매칭.
- status='approved' 시:
  - intent 갱신 + `mp_movements` credit 적립 + `mp_wallets` 잔액 증가
  - **Socket.io `mercadopago:approved` 이벤트를 해당 터미널 room(`terminal:{id}`)에 emit** (`emitToTerminal`)
- 멱등성: `mp_payment_intents.payment_id UNIQUE` 로 중복 webhook 도 sale 1건만.

### Polling 경로 (fallback, ~10초)

- 프론트가 QR 활성 동안 `GET /mercadopago/payment-intents/{id}` 를 **SWR 5초 간격** 폴링 (`useMpPaymentIntent.ts`).
- 응답이 'approved' 면 webhook 과 동일하게 자동 Generar Venta.

### 프론트 자동 트리거

`PaymentSummaryModal.tsx`:
- `useMpApprovedSocket(terminalId, onMpApproved)` — Socket.io 리스너 (터미널 room)
- `useMpPaymentIntent(...)` — polling
- 둘 중 먼저 'approved' 감지 시 `handleSubmit("INVOICED", paymentMethods)` 자동 호출.

---

## 9. Split 결제 (부분금액 MP)

한 판매에서 MP + 다른 결제수단을 혼합할 수 있다.

- 예: 총 50,000 → MP 30,000 + Efectivo 20,000.
- MP QR 은 **30,000 에 대해서만** 발급.
- MP 결제 confirmed + 나머지 행(현금 등) 입력 완료 **둘 다** 충족 시 Generar Venta 트리거.
- 최종 `sale.paymentMethods`:
  ```json
  [{ "slug": "mercadopago", "amount": 30000, "mp_payment_id": "..." },
   { "slug": "efectivo",    "amount": 20000 }]
  ```

---

## 10. 가상 Caja Mercadopago (지갑 + 이체)

MP 결제 수금액은 물리 현금함이 아니라 **가상 지갑(`mp_wallets`)** 에 적립된다.

**화면**: **control-de-caja** 목록에 "Caja Mercadopago" 행 표시.
프론트: `views/cash-control/components/McdpgWalletRow.tsx`, `McdpgDetailModal.tsx`, `McdpgTransferModal.tsx`

**권한**: `admin`, `superadmin`, `gerente` (vendedor 차단).

### 조회

- `GET /mercadopago/wallets?storeId=N` — 매장 지갑 목록 (**computed balance** 우선 — 캐시 drift 방어).
- `GET /mercadopago/wallets/:walletId/movements` — 입출금 원장 (페이지네이션, limit 최대 100).
  - movement type: `credit`(수금) / `refund_debit`(환불 차감) / `transfer_debit`(현금 이체) 등.

### MP → 현금 이체

- "MP→현금" 버튼 → `POST /mercadopago/transfers`
  - body: `{ mpWalletId, targetBoxId, amount }`
  - **트랜잭션 보장**: MP wallet debit + 물리 caja(box) credit 동시 처리.
  - 응답: `{ transferId, mpWalletBalanceAfter, boxBalanceAfter }`
  - 서비스: `wallet/mp-transfer.service.ts`. Audit 로그 기록.

---

## 11. 환불 (Devolución)

판매 취소(`nullifySale`) 시 MP 결제분이 **자동으로 환불 REST 호출**된다.

`sales/sales-create.service.ts:nullifySale()` → `MpRefundService.refundForSale(...)` (line ~548).

### 정상 흐름 (happy path)

- `sale.paymentMethods` 중 `slug='mercadopago'` + `mp_payment_id` 가 있으면:
  - `POST /v1/payments/{mp_payment_id}/refunds` 호출 (idempotency-key 사용)
  - 성공 시 `mp_refunds` row 생성 + `mp_movements` refund_debit + `mp_wallets` 잔액 차감
  - `mp_refund_attempts` 에 `attempt_no=1, status='success'` 기록

### 실패 시 핵심 정책 (D-A4-03)

> **판매는 항상 nullified 처리된다** (MP 환불 실패와 무관). 환불 실패는 `mp_refund_attempts` 에만 기록되고, 사용자에게 명확히 노출 + 재시도 수단 제공.

**SalesDetailView 의 환불 실패 UX (`McdpgRefundFailureSection.tsx`)** — 5요소:
1. 인라인 `<Alert severity="error">` "⚠️ Devolución MP fallida"
2. 에러 코드 블록 (monospace, MP API 에러 메시지)
3. 액션 버튼 3개:
   - 🔄 **Reintentar devolución** (재시도)
   - ↗ **Abrir MP Dashboard** (https://www.mercadopago.com.ar/activities)
   - **Ver historial (N intentos)**
4. 글로벌 토스트 (react-toastify, 우하단)
5. **Historial de intentos** — 시도 이력 그리드 (`#1 | FAILED | error | HH:mm:ss`)

### 재시도 / 이력 엔드포인트

- 재시도: `POST /mercadopago/refunds/:saleId/retry` — body `{ mpPaymentId, amount }`. 같은 (saleId, mpPaymentId) 묶음으로 `attempt_no` 증가.
- 이력: `GET /mercadopago/refunds/sale/:saleId/attempts`
- 권한: `admin`, `superadmin`, `gerente`.
- **중복 차감 방지**: 매 재시도마다 새 idempotency-key(`refund-{saleId}-{n}`) + `mp_refunds.refund_id UNIQUE` → 잔액 이중 차감 없음.

---

## 12. Sandbox vs Production

- 계정(`mp_accounts.environment`)별로 `'sandbox' | 'production'`.
- 같은 매장 안에서 store-level=production + branch X=sandbox 같은 **혼합 가능** (테스트용).
- 백엔드 모든 MP API 호출은 그 계정의 environment 에 따라 **credentials(`MP_SANDBOX_*` / `MP_PRODUCTION_*`) 분기** (`credentialsFor(env)`).
  - host(`api.mercadopago.com`)는 동일, **토큰만 다름** — cross-call 방지를 위해 누락 시 fail-fast.
- **시각적 구분**: sandbox 계정 사용 시 nueva-venta 상단 **주황 SANDBOX 배너** + QR 모달 주황 테두리 + 계정 카드 `🧪 SANDBOX` 칩 (`McdpgEnvironmentBadge.tsx`).

**Sandbox E2E 테스트 스크립트**: `docs/phase29-e2e.md` (연결 → 결제 → 자동 Generar Venta → 환불 → 환불 실패 UX 까지 7단계).

---

## 13. 자동화 (Cron 작업)

`@nestjs/schedule` 기반 (ScheduleModule 은 app.module 에 이미 등록됨).

| Cron | 스케줄 | 동작 | 파일 |
|------|--------|------|------|
| **토큰 자동 갱신** | 매일 04:00 | 만료 임박 access_token 을 refresh_token 으로 갱신 (둘 다 회전 재저장) | `cron/mp-token-refresh.cron.ts` |
| **지갑 정합(reconcile)** | 매일 03:00 | MP 실제 잔액과 `mp_wallets` 대조 정합 | `cron/mp-wallet-reconcile.cron.ts` |

> refresh_token 만료/실패 시 사용자에게 재연결 요구. `expires_at` 임박(D-7) 시 알림 노출.

---

## 14. API 엔드포인트 레퍼런스

베이스: 개발 `http://localhost:5002/api`, 운영 `https://newapi.coolsistema.com/api`

| Method | Path | 권한 | 설명 |
|--------|------|------|------|
| GET | `/mercadopago/oauth/start?storeId&branchId&environment` | admin, superadmin | MP authorize URL 로 302 redirect |
| GET | `/mercadopago/oauth/callback?code&state` | **Public** (HMAC state) | MP 콜백 → 토큰 교환/저장 → 프론트 redirect |
| POST | `/mercadopago/oauth/disconnect/:accountId` | admin, superadmin | 계정 soft disconnect |
| GET | `/mercadopago/accounts?storeId` | vendedor+ (본인 매장) | 매장 MP 계정 목록 (**토큰 컬럼 제외**) |
| POST | `/mercadopago/qr` | vendedor+ | QR 생성 `{storeId, amount, pendingVentaId}` → `{intentId, qrData, expiresAt}` |
| DELETE | `/mercadopago/qr/:intentId` | vendedor+ | QR/intent 취소 |
| GET | `/mercadopago/payment-intents/:id` | vendedor+ | intent 상태 polling (SWR 5초) |
| POST | `/mercadopago/webhook` | **Public** | MP 결제 알림 수신 (즉시 200 + 비동기) |
| GET | `/mercadopago/wallets?storeId` | admin, superadmin, gerente | 지갑 목록 (computed balance) |
| GET | `/mercadopago/wallets/:walletId/movements` | admin, superadmin, gerente | 입출금 원장 (페이지네이션) |
| POST | `/mercadopago/transfers` | admin, superadmin, gerente | MP→현금 이체 |
| POST | `/mercadopago/refunds/:saleId/retry` | admin, superadmin, gerente | 환불 재시도 |
| GET | `/mercadopago/refunds/sale/:saleId/attempts` | admin, superadmin, gerente | 환불 시도 이력 |

**Socket.io**: 이벤트 `mercadopago:approved`, room `terminal:{id}`, payload `{ pendingVentaId, paymentId, amount, capturedAt }`.

---

## 15. DB 테이블 레퍼런스

> 컬럼 정확명은 `.planning/intel/db-schema-tables.md` 참조 (Sequelize `underscored:true` → snake_case).

| 테이블 | 역할 | 핵심 컬럼 |
|--------|------|-----------|
| `mp_accounts` | OAuth 계정 + scope | `store_id`, `branch_id`(NULL=store-level), `mp_user_id`, `access_token`(암호화), `refresh_token`(암호화), `environment`, `external_pos_id`, `expires_at`, `connected_at`, `disconnected_at` |
| `mp_payment_intents` | QR 결제 의도/추적 | `status`(pending/approved/cancelled/expired), `qr_data`, `payment_id`(**UNIQUE** 멱등성), `external_reference`, `amount`, `expires_at`, `approved_at` |
| `mp_wallets` | 가상 Caja MP 잔액 | `mp_account_id`, `store_id`, `branch_id`, `balance`, `currency`, `last_synced_at` |
| `mp_movements` | 입출금 원장 | `mp_wallet_id`, `type`(credit/refund_debit/transfer_debit), `amount`, `sale_id`, `refund_id`, `transfer_id`, `mp_payment_id` |
| `mp_refunds` | 환불 기록 | `sale_id`, `refund_id`(**UNIQUE**), `amount`, `status` |
| `mp_refund_attempts` | 환불 시도/실패 audit | `sale_id`, `mp_payment_id`, `attempt_no`, `status`(success/failed), `error_message` |
| `mp_transfers` | MP→Caja 이체 | `mp_wallet_id`, `target_box_id`, `amount` |

---

## 16. 보안 요약

- **토큰 암호화**: access/refresh token AES-256-GCM (`iv:tag:ciphertext`). API 응답 whitelist 로 토큰 컬럼 **절대 제외** (`mercadopago.controller.ts` attributes whitelist + `toResponse` 가드).
- **IDOR 방어**: `/accounts`, `/wallets` 등은 본인 `storeId` 만 조회 (superadmin 만 cross-store).
- **OAuth CSRF**: state 에 HMAC SHA256 서명(`MP_OAUTH_STATE_SECRET`) + nonce + ts.
- **Webhook**: 서명 검증 불가(QR 한계) → 항상 MP API 재조회로 진실 확인. payment_id UNIQUE 멱등.
- **권한 분리**: 판매원(vendedor)은 QR 생성/조회만. 지갑 이체·환불 재시도·계정 연결은 관리자 이상.
- **Pool 안전**: 별도 pool 생성 금지, 기존 풀 사용. wallet 목록 N+1 은 매장당 1~5개로 제한적.

---

## 17. 트러블슈팅

| 증상 | 원인 | 해결 |
|------|------|------|
| 부팅 실패 `MP_TOKEN_ENCRYPTION_KEY must be 32 bytes hex` | 키 길이 오류 | `openssl rand -hex 32` 로 64자 hex 재생성 |
| `MP_OAUTH_STATE_SECRET env var missing` | env 누락 | OAuth state secret 설정 후 재시작 |
| 콜백 후 `?error=...` | state 만료/위조, token 교환 실패 | 시간 동기화, client secret/redirect URI 재확인 |
| QR 옵션 disabled | 해당 scope MP 계정 미연결 | Configuración→Mercadopago 에서 store/branch 연결 |
| 결제했는데 판매 자동완료 안 됨 | webhook 차단 + polling 미동작 | webhook URL/방화벽 확인. polling 은 ~10초 내 회복 |
| 환불 실패 Alert | MP 토큰 만료/네트워크/API 오류 | 재연결 또는 네트워크 복구 후 "Reintentar devolución" |
| 지갑 잔액 불일치 | 정합 지연 | reconcile cron(03:00) 또는 computed balance 확인 |
| `relation "mp_*" does not exist` | 마이그레이션 미적용 | `29-RUN.md` 순서대로 29-01~29-05 적용 |

---

## 18. 소스 파일 맵

**백엔드** (`api-ventago/src/app/mercadopago/`)
```
mercadopago.module.ts           # 모듈 등록 (모델/컨트롤러/서비스/cron)
mercadopago.controller.ts       # GET /accounts (read-only, 토큰 제외)
mp-account-resolver.service.ts  # 결제 시 계정 lookup (branch→store fallback)
crypto/mp-token-crypto.service.ts   # AES-256-GCM 암복호화
api-client/mp-api-client.service.ts # MP REST 래퍼 (credentialsFor)
api-client/mp-store-pos.service.ts  # Store/POS 등록
oauth/   mp-oauth.controller.ts  / mp-oauth.service.ts / mp-oauth-state.util.ts
qr/      mp-qr.controller.ts     / mp-qr.service.ts
intents/ mp-payment-intents.controller.ts / .service.ts   # polling
webhook/ mp-webhook.controller.ts / mp-webhook.service.ts # 자동 트리거
wallet/  mp-wallet.controller.ts / mp-wallet.service.ts / mp-transfer.service.ts
refunds/ mp-refund.controller.ts / mp-refund.service.ts
cron/    mp-token-refresh.cron.ts / mp-wallet-reconcile.cron.ts
models/  mp-account / mp-payment-intent / mp-wallet / mp-movement
         / mp-refund / mp-refund-attempt / mp-transfer .model.ts
dto/     create-mp-qr / mp-webhook / retry-refund / transfer-mp-to-cash .dto.ts
```
연동 지점: `sales/sales-create.service.ts` (`nullifySale` → 자동 환불)

**프론트엔드** (`ventago-app/src/`)
```
pages/configuracion/mercadopago/index.tsx   # 설정 페이지 진입
views/mercadopago/McdpgConfigView.tsx        # OAuth 연결/해제 UI
views/mercadopago/components/                # AccountCard, BranchToggleTable,
                                             # EnvironmentBadge, RefundFailureSection
views/mercadopago/hooks/                     # useMpAccounts, useMpWallets, useMpMovements,
                                             # useMpPaymentIntent, useMpApprovedSocket,
                                             # useMpRefundAttempts
views/homes/.../PaymentSummaryModal.tsx      # POS QR 결제 + 자동 트리거
components/banners/SandboxMpBanner.tsx        # 주황 sandbox 배너
views/cash-control/components/                # McdpgWalletRow, McdpgDetailModal, McdpgTransferModal
views/sales/details/SalesDetailView.tsx      # 환불 실패 UX
types/mercadopago.ts                          # 타입 정의
```

**운영 문서**
```
docs/phase29-ops-mp-app-setup.md   # MP 앱 생성 + env 프로비저닝 (운영 엔지니어)
docs/phase29-e2e.md                # Sandbox E2E 7단계 검증 스크립트
docs/payment-gateway-research.md   # 결제 게이트웨이 사전 리서치
api-ventago/migrations/29-RUN.md   # DB 마이그레이션 실행 가이드
```
