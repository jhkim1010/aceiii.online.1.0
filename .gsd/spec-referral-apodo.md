# SPEC: 가입 추천인(Referido por @apodo) + Bonificación 50% 크레딧
생성일: 2026-07-24
상태: EXECUTE 완료 (코드+ESLint) — 잔여: 마이그레이션 적용(로컬/운영) + Mac commit/push

## 추가 확정 (Execute 중 사용자 지시)
- D6: superadmin 뿐 아니라 **매장 admin 도** 자기 bonificación 을 봄 → Configuración > Referidos 탭
  (`GET /onboarding/referral/mine`, @Auth admin/gerente/superadmin) + 내 apodo 공유 카드

## 목표
신규 Tienda 가입 폼에 "¿Quién te recomendó?" 칸(@apodo de tienda)을 추가한다.
apodo 가 일치하면 그 매장 주인의 이름을 보여주고 bonificación 안내 메시지를 표시하며,
가입이 **승인 완료**되는 시점에 추천인 매장에 **1개월 사용료의 50% descuento** 를 자동 적립한다(무제한 누적).
추천인에게 Telegram 알림을 보내고, superadmin 비용 계산 페이지에 bonificación 내역을 표시한다.

## 사용자 확정 결정사항
| # | 결정 | 내용 |
|---|------|------|
| D1 | 할인 대상 | **추천인(기존 tienda)만**. 신규 가입자는 혜택 없음(알림 문구만) |
| D2 | 누적 | **무제한 누적** — 추천 1건당 반 달치 크레딧, 다음 결제월부터 순차 차감 |
| D3 | 검증 시점 | **blur 시점** (apodo 입력 후 Tab/다음 칸 이동 시 1회 조회). debounce 실시간 아님 |
| D4 | 알림 | 할인 받는 사람(추천인)에게 **Telegram 메시지** 발송 |
| D5 | Admin 노출 | superadmin **비용 계산 페이지**(admin-console 매장 목록 + StoreBillingCard)에 bonificación 표시 |

## 배경 및 컨텍스트 (조사 결과)

### 가입 흐름 (이미 구현됨 — 여기에 얹는다)
- 프론트: `ventago-app/src/views/register/components/RegisterForm.tsx` — 3단계 마법사 `datos → dni → otp`
- 백엔드: `api-ventago/src/app/onboarding/` — `pending_registrations` + `verification_codes`, 전 라우트 `@Public()`
- 승인: `onboarding-admin.controller.ts` + `OnboardingApprovalService` → 승인 시 `provisionStoreAndOwner()` 로 store/user 실생성
- **추천 크레딧 확정 시점 = 승인 시점** (pending 단계에서는 기록만; 계정이 안 만들어질 수 있으므로 fail-closed)

### apodo = stores.alias_name
- `store.model.ts` 의 `aliasName` — **DB UNIQUE 제약 없음**, 앱 레벨 중복검사만 존재(경쟁조건 취약)
- 이번 기회에 `lower(alias_name)` UNIQUE 인덱스 추가 권장 (사전 중복 데이터 점검 필수)

### 구독/청구 구조
- 가격표: `subscription_config` (단일 행) + `SubscriptionConfigService.calculateMonthlyPrice(storeId)`
- 구독 할인: **`store_billing_discounts`** (admin-console.service raw SQL, `kind='recurring'|'one_time'`, `applies_ym='YYYY-MM'`, 고정금액) — 판매용 `discounts` 테이블과 완전 별개. **referral 크레딧은 이 테이블 확장으로 통합**
- `net = max(0, gross - recurring - one_time)` 계산: `admin-console.service.ts` L297-333
- ⚠️ `store_billing_discounts` 가 운영(5434)에 실존하는지 Execute 전 확인 필요 (schema dump 미기재)

### Telegram
- 기존 `TelegramService` 있음 (온보딩 승인요청 알림에 사용 — 중앙 채널)
- 추천인 **개인** 수신에는 매장별 chat_id 가 필요 → `stores.telegram_chat_id` 컬럼 신설 (nullable)
  - chat_id 있으면 개인 발송 + 중앙 채널 병행, 없으면 중앙 채널만 (fail-safe, 발송 실패는 비치명적 — throw 금지)

## 기술 스택
- 백엔드: NestJS 11 / Sequelize (`underscored: true` → SQL 은 snake_case)
- DB: PostgreSQL 18 (로컬 5432 + 운영 5434 **동시 적용**, owner coolsistema DO 블록 필수)
- 프론트: Next.js 13 + MUI 5 + React Hook Form/Yup
- Pool: 조회 1쿼리(blur 당 1회), 승인 트랜잭션 내 INSERT — 폴링/상시연결 없음, pool 무부담

---

## 데이터 모델 (마이그레이션 1건: `api-ventago/migrations/2026-07-24-referral-apodo.sql`)

```sql
-- 1) pending_registrations 에 추천 정보
ALTER TABLE pending_registrations
  ADD COLUMN IF NOT EXISTS referred_by_apodo varchar(255),
  ADD COLUMN IF NOT EXISTS referrer_store_id integer REFERENCES stores(id);

-- 2) 추천 크레딧 원장 (감사/이력용 — 화면 표시·집계의 진실 소스)
CREATE TABLE IF NOT EXISTS referral_credits (
  id SERIAL PRIMARY KEY,
  referrer_store_id integer NOT NULL REFERENCES stores(id),
  referred_store_id integer NOT NULL REFERENCES stores(id),
  pending_registration_id integer,
  percent numeric NOT NULL DEFAULT 50,
  amount numeric NOT NULL,             -- 승인 시점 추천인 월사용료 × 50% 스냅샷
  applies_ym varchar(7),               -- 배정된 청구월 'YYYY-MM'
  status varchar(20) NOT NULL DEFAULT 'applied',  -- applied | revoked
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_referral_credits_referrer ON referral_credits(referrer_store_id);

-- 3) store_billing_discounts — ★로컬(5432)에 미존재 확인됨(2026-07-24) → CREATE 포함으로 로컬·운영 수렴
CREATE TABLE IF NOT EXISTS store_billing_discounts (
  id SERIAL PRIMARY KEY,
  store_id integer NOT NULL REFERENCES stores(id),
  amount numeric NOT NULL,
  kind varchar(20) NOT NULL,           -- recurring | one_time
  applies_ym varchar(7),
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE store_billing_discounts
  ADD COLUMN IF NOT EXISTS source varchar(20) NOT NULL DEFAULT 'manual',   -- manual | referral
  ADD COLUMN IF NOT EXISTS referral_credit_id integer;

-- 4) 추천인 개인 Telegram
ALTER TABLE stores ADD COLUMN IF NOT EXISTS telegram_chat_id varchar(64);

-- 5) apodo 유일성 (중복 사전 점검 후!)
CREATE UNIQUE INDEX IF NOT EXISTS uq_stores_alias_lower ON stores (lower(alias_name)) WHERE alias_name IS NOT NULL;

-- 6) owner 이전 (운영 필수)
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='coolsistema') THEN
    ALTER TABLE referral_credits OWNER TO coolsistema;
    ALTER SEQUENCE referral_credits_id_seq OWNER TO coolsistema;
  END IF;
END $$;
```

### 무제한 누적 배정 로직
승인 1건 = `referral_credits` 1행 + `store_billing_discounts` 1행(`kind='one_time'`, `source='referral'`).
`applies_ym` 은 **아직 referral 크레딧이 배정되지 않은 가장 이른 미래 청구월**에 순차 배정
(같은 달에 몰아넣으면 `max(0, …)` 로 초과분이 증발하므로 월별 1건씩 밀어서 배정 — 3명 추천 = 1.5개월 무료).

---

## API 설계

### 1) apodo 조회 (public, 가입 전 화면)
`GET /onboarding/referral/check?apodo=<apodo>` — `onboarding.controller.ts` 에 추가, `@Public()`
- `lower(alias_name)` 매칭, suspended 매장 제외
- 응답(정보 최소화 — enumeration 방지 위해 이름만): `{ found: true, ownerName: 'Marcos K.', storeName: 'ACE' }` / `{ found: false }`
- 성(姓)은 이니셜 처리. 간단 rate-limit(IP당 분당 N회) 고려 — 기존 onboarding 쿨다운 패턴 참조

### 2) 가입 시작 시 저장
`POST /onboarding/start` DTO 에 `referredByApodo?: string` 추가 →
서버에서 재검증 후 `pending_registrations.referred_by_apodo + referrer_store_id` 저장
(불일치면 무시하고 가입은 진행 — 추천은 부가 정보, 가입을 막지 않는다)

### 3) 승인 시 크레딧 확정 — `OnboardingApprovalService` 확장 (트랜잭션 내)
1. `referrer_store_id` 존재 시 `calculateMonthlyPrice(referrerStoreId)` × 0.5 = amount
2. `referral_credits` INSERT + `store_billing_discounts` INSERT (`source='referral'`, applies_ym 순차 배정)
3. Telegram 발송 (트랜잭션 밖, 실패 비치명적):
   - 추천인 chat_id 있으면 개인: "🎁 ¡Felicitaciones! *{신규매장}* se registró con tu recomendación (@{apodo}). Recibís una bonificación del **50% de un mes** ($ {amount}) en tu próxima factura."
   - 중앙 admin 채널에도 기록용 알림

### 4) Admin 비용 계산 페이지 노출
- `admin-console.service.ts` 매장 목록 쿼리에 referral 합계 추가: `referralBonus`(해당월 referral one_time 합), `referralCount`
- `GET /subscription-config/store/:storeId/billing` (`getStoreBillingDetail`) 에 `referralCredits[]` (신규매장명·날짜·금액·적용월) 포함
- 프론트 `StoreBillingCard.tsx` + admin 매장 목록에 "Bonificación por referidos" 행/칩 표시 (골드 강조)

---

## 프론트엔드 (RegisterForm — datos 스텝)

- 필드 추가: `referredByApodo` (optional) — label "¿Quién te recomendó? (opcional)", `@` prefix adornment
- **onBlur 시 1회** `GET /onboarding/referral/check` 호출 (D3):
  - 조회 중: 스피너
  - 일치: ✅ 초록 박스 — "Te recomendó **{ownerName}** de **{storeName}**. 🎁 Recibirá una bonificación del 50% de un mes de servicio."
  - 불일치: ⚠️ 경고 박스 — "No encontramos ninguna tienda con el apodo **@{apodo}**. Verificá que esté bien escrito." (가입 진행은 차단하지 않음 — 값 비우거나 수정 유도)
  - 빈 값: 아무 표시 없음 (optional)
- 검증 상태는 로컬 state, yup 필수화 금지

---

## 태스크 목록

- [x] TASK-1: 마이그레이션 SQL 작성 — `api-ventago/migrations/2026-07-24-referral-apodo.sql` (store_billing_discounts CREATE 포함)
- [x] TASK-2: `ReferralCredit` 모델 + onboarding 모듈 등록 — `referral-credit.model.ts`
- [x] TASK-3: `GET /onboarding/referral/check` (@Public) — `onboarding.controller.ts`, `onboarding-verification.service.ts`
- [x] TASK-4: `POST /onboarding/start` DTO/저장 확장 (referredByApodo → referrer_store_id 해석 저장)
- [x] TASK-5: 승인 시 크레딧 확정(트랜잭션) + applies_ym 순차 배정 + Telegram(개인 chatId + 중앙) — `onboarding-approval.service.ts`, `telegram.ts`(chatId 옵션)
- [x] TASK-6: admin-console 집계(referralBonus/referralCount, one_time SUM화, 수동할인 source='manual' 스코프) + billing detail referralCredits
- [x] TASK-7: RegisterForm blur 검증 UI (@ prefix, 3상태 Alert)
- [x] TASK-8: StoreBillingCard referidos 테이블 + TenantsView 🎁 칩
- [x] TASK-8b (D6): `GET /onboarding/referral/mine` + `ReferidosView.tsx` + Configuración 허브 탭
- [x] TASK-9: ESLint — api·front 변경 파일 전부 오류 0
- [ ] TASK-10: 마이그레이션 로컬(5432)+운영(5434) 적용 — ★사용자 Mac 실행 (아래 명령), **운영 적용 후에 push** (Store 모델 telegram_chat_id 때문에 코드 선배포 시 SELECT 오류)
- [ ] TASK-11: Mac commit/push (이번 작업 파일만 선별 — 다른 WIP 혼입 금지) → Jenkins 빌드 → 운영 스모크

## 완료 기준
- ESLint 오류 0개, Jenkins 빌드 통과
- blur 1회 조회 외 추가 트래픽 없음 (pool: pool.query 자동반환 패턴, release 누락 0)
- 승인 트랜잭션 실패 시 크레딧 미생성 (부분 상태 없음), Telegram 실패해도 승인은 성공
- 로컬·운영 스키마 일치, 신규 테이블 owner=coolsistema

## 금지사항 / 주의사항
- 판매용 `discounts` 테이블 건드리지 않기 (구독 할인은 `store_billing_discounts` 전용)
- 추천 불일치가 **가입을 차단하면 안 됨** (optional 필드)
- apodo 조회 응답에 이메일/전화 등 개인정보 노출 금지 (이름 이니셜 + 매장명만)
- Telegram 발송 throw 금지 (비치명적 — AFIP 자동출력 패턴과 동일)
- `stores` UNIQUE 인덱스는 운영 중복 데이터 점검 결과 확인 후에만 적용
- device VM 에서 jest 금지 — 검증은 러너 잡 / Jenkins 게이트

## 사전 검증 결과 (2026-07-24, 로컬 PG18:5432 조회)
- `store_billing_discounts`: **로컬에 미존재** → 마이그레이션에 CREATE TABLE IF NOT EXISTS 포함 (운영은 raw SQL 로 사용 중이므로 실존 추정 — Execute 시 `venpsql \d store_billing_discounts` 로 운영 컬럼 대조 필수)
- `alias_name` 중복: 로컬 0건 → UNIQUE 인덱스 안전. 운영도 동일 쿼리로 확인 후 적용
- `stores.telegram_chat_id`: 미존재 → 신설 필요 (확인됨)
- `pending_registrations`: 존재 확인, `created_store_id` 컬럼 있음 → 승인 후 신규 store 연결에 활용 가능

## 미결 사항 (Execute 전 확인)
1. `store_billing_discounts` **운영(5434)** 실존 여부·정확한 컬럼 (`venpsql \d store_billing_discounts`) — CREATE IF NOT EXISTS 와 충돌 없는지
2. 추천인 chat_id 등록 UI (Phase 2 — 우선 중앙 채널 알림으로 시작해도 되는지)
3. alias_name **운영** 중복 존재 여부 (로컬은 0건 확인)
