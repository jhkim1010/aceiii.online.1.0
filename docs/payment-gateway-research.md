# Ventago 결제 시스템 PG사 비교 리서치

작성일: 2026-04-23
작성자: Marcos.J.Kim (Claude 리서치 지원)
대상 프로젝트: ACE_online_1.0 / Ventago (api-ventago + ventago-app)

---

## 1. 제약 조건 (요구사항 요약)

| 항목 | 값 |
|---|---|
| 카드 브랜드 | Visa (Mastercard/Amex 포함 가정) |
| 시장 범위 | 남미 전반 (파라과이·브라질·아르헨티나·칠레·멕시코·콜롬비아 등) |
| 최종 정산 | Wise 다중통화 계좌 (USD/EUR 선호) |
| 시나리오 | ① Ventago POS 카드 결제 ② Ventago 매장 구독료 수금 |
| 기술 스택 | NestJS 11 / Sequelize / PostgreSQL 15 / Next.js 13 |
| 구조 | 멀티테넌트 (`store_id` 기반), JWT + SessionGuard |

---

## 2. 핵심 결론 (바쁘면 이것만)

> **"단일 PG로 남미 전반 + Wise 수취 + POS/구독 모두"는 현실적으로 불가능.**
> 권장 구조는 **Stripe (구독 + 주요 5개국 POS) + dLocal 또는 현지 PG (Stripe 미지원 국가 POS)** 조합.
> Wise 수취는 **Stripe → Wise USD 계좌** 조합이 가장 검증되어 있음 (dLocal은 Wise 직결 불명확).

---

## 3. PG사별 비교표

### 3.1 남미 커버리지

| PG사 | Brazil | Argentina | Paraguay | Chile | Mexico | Colombia | Peru | Uruguay | 비고 |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|---|
| **Stripe** | O | X | X | O | O | O | O | X | 2025 Pix 대응, but 파라과이 미지원 |
| **dLocal** | O | O | O | O | O | O | O | O | 남미 전역, 40+ 국가 |
| **EBANX** | O | O | X | O | O | O | O | O | 14개국, 파라과이 제한적 |
| **Mercado Pago** | O | O | O | O | O | O | O | O | MELI 생태계, 지역 1위 |
| **Bancard (PY)** | X | X | O | X | X | X | X | X | 파라과이 전용, SPI/카드 지원 |
| **PayPal** | O | O | O | O | O | O | O | O | 인지도는 최강, 수수료 높음 |
| **PortOne** | — | — | — | — | — | — | — | — | 한국/동남아 중심, 남미 미지원 |

> Stripe는 **파라과이·아르헨티나 미지원**이 결정적 한계.
> dLocal과 Mercado Pago가 **커버리지 관점에서 남미 원 파트너에 가장 가까움**.

### 3.2 수수료 (퍼블릭 정보 기준, 2026년 4월)

| PG사 | 대표 수수료 (카드) | 고정비 | 정산 주기 |
|---|---|---|---|
| Stripe (International) | ~3.9% + $0.30 (해외 카드) | 월 고정비 없음 | 2~7영업일 |
| dLocal | 협상 기반 (보통 4~6%) + FX 스프레드 | 협상 | 주/격주 (T+3~T+15) |
| EBANX | ~2.7% + $0.30 (과거 기준) + 월 $200 고정비 루머 | 월 고정비 있을 수 있음 | 주/격주 |
| Mercado Pago | 3.99%~6.79% (국가·즉시/지연 정산에 따라 상이) | 없음 | 즉시 or D+14 |
| Bancard | Acquirer별 다름 (협상) | 없음 | 보통 D+1 |
| PayPal | 4.4% + 고정 (국제) | 없음 | 즉시 출금 가능 |

**주의:** dLocal·EBANX는 모두 퍼블릭 가격 미공개(협상) → 영업팀 연락 필요.

### 3.3 Wise 정산 호환성 (가장 중요)

| PG사 | Wise 수취 가능성 | 근거 |
|---|---|---|
| **Stripe** | ✅ 공식 지원 | Wise가 Stripe용 수취 전용 계좌(USD 등) 제공, 다수 튜토리얼 있음 |
| **PayPal** | ✅ 가능 (우회) | Wise 로컬 계좌로 PayPal 출금 가능 |
| **dLocal** | ⚠️ 확인 필요 | 공식 파트너십 미확인, 영업팀 문의 필수 (국가별 정산 은행 계좌 요구 가능성) |
| **EBANX** | ⚠️ 확인 필요 | dLocal과 동일 — 공식 문서화되어 있지 않음 |
| **Mercado Pago** | ❌ 거의 불가 | 국가별 은행계좌(CBU·CPF 등) 강제, Wise 수취 원칙적 어려움 |
| **Bancard** | ❌ 불가 | 파라과이 현지 은행 계좌(CAEX 등) 필수 |

> Wise 수취 제약이 **PG 선정의 1차 필터**. Stripe가 가장 안전한 Wise 파트너.

### 3.4 구독(Subscription) 기능

| PG사 | 구독 내장 기능 | Ventago 구독료 수금에 적합한가 |
|---|---|---|
| Stripe Billing | ✅ 최강 — trial, proration, invoices, tax, dunning 모두 내장 | ⭐⭐⭐⭐⭐ |
| Mercado Pago Subscriptions | ✅ 있음 — 남미 카드 친화 | ⭐⭐⭐⭐ |
| dLocal | ⚠️ Recurring 지원하나 Billing UI는 약함 | ⭐⭐⭐ |
| EBANX | ⚠️ Recurring 있음 | ⭐⭐⭐ |
| PayPal | ✅ Subscriptions API | ⭐⭐⭐ |
| Bancard | ❌ 구독 기능 없음 (토큰화로 자체 구현 필요) | ⭐ |

### 3.5 NestJS/Next.js 통합 난이도 (Ventago 관점)

| PG사 | SDK 품질 | Webhook | 멀티테넌트(`store_id`) 설계 | 통합 난이도 |
|---|---|---|---|---|
| Stripe | Node SDK 최상, TS 타입 완비 | 서명 검증 내장 | Connect 계정(`stripe_account_id`) 테이블에 매핑 | 낮음 |
| Mercado Pago | Node SDK 있으나 TS 타입 불완전 | 서명 검증 있음 | `mp_user_id` 컬럼 매핑 | 중간 |
| dLocal | REST 위주 SDK | HMAC 서명 | 매장별 `dlocal_account_id` | 중간~상 |
| Bancard | SOAP/REST 혼재, 구 API 느낌 | 수동 서명 검증 | 직접 구현 | 상 |

---

## 4. 시나리오별 추천 아키텍처

### 4.1 Ventago **구독료 수금** (Marcos님이 매장 운영자에게 월 구독료 받기)

**추천: Stripe Billing + Wise USD 계좌**

이유:
- 매장 운영자는 남미 전역에 있지만, **매장 카드가 Visa이면 Stripe가 해외 카드로 처리 가능** (Stripe 계정 자체는 Brazil/Mexico/US 등에 만들 수 있음)
- Wise 수취는 Stripe와 **공식 인증된 조합**
- 구독 관리(청구 실패 retry, proration, invoice PDF)를 직접 구현 X

Wise 수취 흐름:
```
매장 Visa 카드
  → Stripe (계정: US 또는 Brazil)
  → Stripe Payout (USD)
  → Wise USD 로컬 계좌 (ACH)
  → Marcos 한국 통장 (원화 환전 필요 시)
```

주의점: **Stripe 계정을 어디에 개설하느냐**가 관건. US LLC가 있으면 가장 깔끔. 아니면 Brazil/Mexico 법인 필요.

### 4.2 Ventago **POS 카드 결제** (매장에서 실제 고객 카드 받기)

**추천: 국가별 분기**

| 고객 국가 | 추천 PG | Wise 수취 |
|---|---|---|
| Brazil, Chile, Mexico, Colombia, Peru | Stripe | ✅ |
| Paraguay | Bancard 또는 dLocal | ❌ 현지 은행 필수 |
| Argentina | Mercado Pago | ❌ 현지 은행 필수 |
| 기타 남미 | dLocal | ⚠️ 협상 |

현실적으로 **POS 정산은 Wise로 모두 모을 수 없음**. 국가별 은행계좌가 필요.
→ **POS는 매장(store)이 직접 PG 계정 소유**, Ventago는 **청구·정산 중계** 역할만 하는 구조 권장.

### 4.3 단일 PG로 시작하고 싶다면

**최소 조합:** Stripe만 연동 → 지원되는 5~6개국부터 런칭 → 나머지는 Phase 2에서 dLocal 추가.

---

## 5. Ventago 아키텍처 통합 스케치 (권장)

### 5.1 DB 스키마 추가 (초안)

```sql
-- 매장별 PG 계정 연결 (POS용)
CREATE TABLE store_payment_accounts (
  id SERIAL PRIMARY KEY,
  store_id INT NOT NULL REFERENCES stores(id),
  provider VARCHAR(20) NOT NULL,  -- 'stripe', 'dlocal', 'mercadopago', 'bancard'
  external_account_id VARCHAR(255) NOT NULL,
  country_code CHAR(2) NOT NULL,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(store_id, provider, country_code)
);

-- 결제 트랜잭션 (POS)
CREATE TABLE payment_transactions (
  id BIGSERIAL PRIMARY KEY,
  store_id INT NOT NULL REFERENCES stores(id),
  sale_id INT REFERENCES sales(id),
  provider VARCHAR(20) NOT NULL,
  provider_payment_id VARCHAR(255) NOT NULL,
  amount_cents BIGINT NOT NULL,
  currency CHAR(3) NOT NULL,
  status VARCHAR(20) NOT NULL,  -- 'pending', 'succeeded', 'failed', 'refunded'
  raw_payload JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_pt_store_created ON payment_transactions(store_id, created_at DESC);
CREATE INDEX idx_pt_provider_pid ON payment_transactions(provider, provider_payment_id);

-- Ventago 구독 (매장 월구독료)
CREATE TABLE ventago_subscriptions (
  id SERIAL PRIMARY KEY,
  store_id INT NOT NULL UNIQUE REFERENCES stores(id),
  stripe_customer_id VARCHAR(255),
  stripe_subscription_id VARCHAR(255),
  plan VARCHAR(50) NOT NULL,  -- 'basic', 'pro', 'enterprise'
  status VARCHAR(20) NOT NULL,  -- 'active', 'past_due', 'canceled'
  current_period_end TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

### 5.2 NestJS 모듈 구조 (권장)

```
api-ventago/src/app/
└── payments/
    ├── payments.module.ts
    ├── payments.controller.ts         # POS 결제 생성/조회/환불
    ├── webhooks.controller.ts         # PG별 webhook 엔드포인트
    ├── providers/
    │   ├── stripe.provider.ts
    │   ├── dlocal.provider.ts
    │   ├── mercadopago.provider.ts
    │   └── provider.interface.ts      # 공통 인터페이스
    ├── services/
    │   ├── payment-router.service.ts  # 국가·통화 기반 PG 라우팅
    │   └── subscription.service.ts    # Ventago 구독 관리
    └── dto/
```

공통 인터페이스 핵심:
```typescript
interface PaymentProvider {
  createPayment(dto: CreatePaymentDto): Promise<PaymentResult>;
  refund(providerPaymentId: string, amount?: number): Promise<RefundResult>;
  handleWebhook(rawBody: Buffer, signature: string): Promise<WebhookEvent>;
}
```

### 5.3 PostgreSQL Pool 규칙 (프로젝트 규약 준수)

- 결제 트랜잭션 처리 시 `BEGIN/COMMIT` 범위를 **최소화** (PG API 호출은 트랜잭션 밖에서)
- Webhook 핸들러는 **idempotency key**(`provider_payment_id`)로 중복 처리 방지
- Pool max=50 유지. 장시간 connection 점유하는 구독 조회는 SWR 캐시(60초)로 완화

---

## 6. 단계별 구현 로드맵 (권장)

### Phase 1 — Ventago 구독 (Marcos 수금)
1. Stripe 계정 개설 (US LLC 또는 본인 법인)
2. Wise USD 계좌 생성 → Stripe Payout 연결
3. `ventago_subscriptions` 테이블 + 구독 관리 모듈
4. 관리자 페이지(`admin/subscriptions`)에서 매장별 구독 상태/수동 청구
5. Webhook으로 실패 시 매장 비활성화

### Phase 2 — POS 카드 결제 (단일 국가부터)
1. Brazil 또는 Mexico 매장부터 Stripe Connect로 연동
2. `store_payment_accounts`에 Stripe Connected Account ID 저장
3. `nueva-venta` 페이지에 "카드 결제" 옵션 추가
4. Webhook으로 `payment_transactions` 업데이트 → `sales` 테이블 연계

### Phase 3 — 남미 확장
1. dLocal 계정 개설 + 협상 수수료 확정
2. `payment-router.service.ts`에서 국가 코드별 PG 선택
3. Paraguay는 Bancard 별도 통합 (현지 은행 필수)

---

## 7. 열린 이슈 (결정 필요)

| 이슈 | 선택지 | 영향 |
|---|---|---|
| Stripe 계정 개설 국가 | US LLC / Brazil 법인 / Mexico 법인 | 세금, Wise 수취 용이성 |
| POS 결제 소유권 | 매장이 직접 PG 계약 / Ventago가 MoR(Merchant of Record) | 법적 책임, 수수료 분배 |
| 구독 실패 시 정책 | 즉시 중지 / N일 유예 / 수동 처리 | 고객 경험, 매출 |
| 환불 정책 | 전액만 / 부분 환불 허용 | UX, 분쟁 처리 |

---

## 8. 근거 자료

- [dLocal — LATAM coverage](https://www.dlocal.com/)
- [dLocal Go — 15+ countries coverage](https://dlocalgo.com/en/coverage)
- [Rebill — Payment gateways in Latin America 2026 비교](https://www.rebill.com/en/blog/payment-gateway-latin-america)
- [Stripe — Global availability (Brazil·Chile·Mexico O / 파라과이 X)](https://stripe.com/global)
- [Stripe — Pix 확장 (Brazil/Argentina/Chile/Uruguay)](https://paymentexpert.com/2025/08/12/stripe-pix-brtazil-latin-america/)
- [Stripe Billing — Subscription 기능](https://stripe.com/billing)
- [Stripe subscriptions in LATAM — 2배 성장 전망](https://www.fintechfutures.com/press-releases/subscriptions-are-transforming-businesses-in-latin-america-stripe)
- [Wise — Stripe 수취 공식 가이드](https://wise.com/help/articles/2977935/how-do-i-receive-money-from-stripe-with-wise)
- [Wise — 수취 가능 통화 목록](https://wise.com/help/articles/2897238/which-currencies-can-i-add-keep-and-receive-in-my-wise-account)
- [EBANX — LATAM 14개국](https://www.ebanx.com/en/latin-america/)
- [EBANX vs dLocal 비교 (Rapyd)](https://www.rapyd.net/blog/ebanx-vs-dlocal-which-is-right-for-latin-american-payments/)
- [Mercado Pago — Subscriptions API](https://www.mercadopago.com.ar/developers/en/docs/subscriptions/overview)
- [Bancard (Paraguay) — 현지 인프라 설명](https://doinamerica.com/paraguay-online-payment-system-setup/)
- [PortOne — 글로벌 통합 페이지 (남미 미지원 확인)](https://portone.io/global/en)

---

## 9. 아르헨티나 사업자 관점 — 세금 현실과 돌파구

### 9.1 Mercado Pago 자동 구독 결제 — **가능합니다**

Mercado Pago Argentina는 구독(Suscripciones / `preapproval` API)을 공식 지원합니다.

| 항목 | 내용 |
|---|---|
| API | `POST /preapproval` (구독 플랜 생성), `POST /preapproval_plan` |
| 카드 토큰화 | 내장 (고객이 1회 카드 입력 → 이후 자동 청구) |
| 주기 | 주/월/연 (custom frequency 지정 가능) |
| 실패 retry | 자동 재시도 포함 |
| 정산 주기 | **2영업일 후** 계좌 반영 (AR 특수) |
| Webhook | 결제 성공·실패·구독 취소 이벤트 제공 |

→ Stripe Billing과 기능적으로 동등한 수준. 단 수수료·세금 구조가 문제.

### 9.2 아르헨티나 세금·원천징수 — **실제 부담 분석**

Marcos님이 우려하신 "50%"는 과장이 아닙니다. 아르헨티나 거주자가 MP로 구독료를 받으면 실질 부담은 다음과 같이 쌓입니다.

#### Responsable Inscripto (일반 법인·자영업자)인 경우

| 세금 항목 | 비율 | 누가 언제 징수 |
|---|---|---|
| **IVA (부가세)** | **21%** | 고객에게 21% 더 받아서 ARCA(구 AFIP)에 납부 |
| **Ganancias 원천징수 (MP)** | 1~3% | MP가 결제 시점에 차감 (연말정산 가능) |
| **IIBB 원천징수 (MP)** | 0.01~5.5% (주별) | MP가 결제 시점에 차감 (CABA ~3%, BA ~3.5%, Tucumán 5.5%) |
| **IIBB 연간 (매출세)** | 1~5% (주별) | 별도 월 신고 |
| **Impuesto a los Créditos y Débitos** | 0.6% | 자동 차감 |
| **MP 수수료** | 3.99~6.79% + IVA | 결제 시점 차감 |
| **Ganancias (법인세)** | 25~35% (이익 기준) | 연말 |

**100 페소 구독료를 받았을 때 실제 현금 흐름 시뮬레이션 (Responsable Inscripto, CABA 기준):**

```
고객 청구액 (IVA 포함):           121 (100 + 21% IVA)
MP가 고객 카드에서 결제:          121
MP 수수료 (약 5% + IVA 1.05%):   -7.32
Ganancias 원천징수 (1%):         -1.21
IIBB 원천징수 (CABA 3%):         -3.63
Impuesto Créditos/Débitos 0.6%:  -0.73
IVA 매출세 (ARCA에 납부):        -21
                                  ─────
월별 즉시 가용 현금:              약 87.11

추후 법인세 (Ganancias 25~35%):   이익의 25~35%
IIBB 월 정산:                     매출 3% 추가 (이미 원천징수분 상계)
─────────────────────────────────
**최종 손에 남는 금액: 약 45~55%** (상황에 따라 변동)
```

→ Marcos님이 "50% 이상 낸다"고 하신 감각이 **정확합니다**. 실효세율 45~55% 수준.

#### Monotributo인 경우 (소규모)

월 매출 한도가 있지만(2026년 기준 Categoría H 최대 ~월 7.7M ARS 정도), 한도 내에서는:
- **MP 원천징수 면제** (MP에 모노트리뷰 등록 시 자동 적용)
- IVA 별도 없음 (통합세 안에 포함)
- 월 고정세만 납부 (카테고리별 수만~수십만 ARS)

→ **초기 소규모로 시작한다면 Monotributo가 압도적으로 유리**하나, 매출이 커지면 강제 전환.

### 9.3 **돌파구 — 합법적인 4가지 구조**

단순히 "아르헨티나 법인으로 MP만 써서" 구독 받는 건 수익성이 안 나옵니다. 아래가 실제로 남미 SaaS 창업자들이 많이 쓰는 합법 구조입니다.

#### 옵션 A — **US LLC (Delaware/Wyoming/New Mexico) + Stripe + Wise** (가장 인기)

```
아르헨티나 고객 Visa 카드
  → Stripe (US LLC 계정) — USD 청구
  → Wise USD 계좌 (Marcos 명의)
  → 필요 시 아르헨티나로 개인 송금 (또는 개인 소득세만 신고)
```

- US LLC는 아르헨티나 거주자도 SSN 없이 개설 가능 (약 $500, 1~2주)
- Pass-through 구조 + Non-ETBUS(미국 내 사업 없음) → **미국 연방세 0%**
- W-8BEN-E 제출로 Stripe가 30% 원천징수하지 않음
- Form 5472 매년 신고 필요 (벌금 $25,000 위험 — 전문가 필수)
- **아르헨티나 IVA·IIBB·원천징수 전부 우회** (계약 주체가 미국 법인이므로)
- 다만 Marcos님이 아르헨티나 **거주자**라면 "worldwide income"으로 개인소득세(5~35%)는 신고 의무

**실효세율 예상: 15~25%** (개인 소득 신고 기준)

#### 옵션 B — **우루과이 Zona Franca SA (ZFSA)** (프리미엄)

```
아르헨티나 고객 → 우루과이 법인 → dLocal 또는 Stripe → Wise/우루과이 은행
```

- 우루과이 자유무역지역 SA 설립 → 서비스 수출 시 **법인세(IRAE) 0%, VAT 0%**
- 단, 설립 비용 $10,000~30,000 + 연간 유지비 $5,000+ + 풀타임 직원 요건
- 매출 규모 연 $500K+ 부터 경제성

**실효세율 예상: 0~10%** (우루과이 내 직원 비용 제외)

#### 옵션 C — **Argentina + Economía del Conocimiento 등록**

- 소프트웨어 개발 회사로 "Régimen de Promoción de la Economía del Conocimiento" 등록
- **수출 서비스 IVA 0%** (해외 고객 대상)
- Ganancias 최대 60% 할인
- 수출 retenciones·percepciones 면제
- 70% 이상 매출이 촉진 활동(소프트웨어)이어야 함
- **단, 아르헨티나 고객에게는 적용 안 됨** — "수출"만 해당

→ Marcos님의 **주요 고객이 아르헨티나 국내**라면 이 옵션은 도움이 제한적. 해외 고객 대상이면 강력.

#### 옵션 D — **파라과이 법인** (이웃 유리)

- 파라과이 법인세 10% + VAT 10% (남미 최저)
- 서비스 수출 시 IVA 0% 가능
- 은행 계좌·Stripe 개설은 가능(국가 지원 제한)
- Marcos님이 이미 파라과이 운영 경험(Ventago 본거지) — 가장 현실적

**실효세율 예상: 10~15%**

### 9.4 권장 결정 트리

```
Ventago 월 구독 매출은 어느 정도를 목표?

  < USD 10,000/월    →  [옵션 A] US LLC + Stripe + Wise
                        가장 빠르고 저렴, 즉시 시작 가능
                        아르헨티나 개인 소득세만 신고

  USD 10,000~50,000/월 →  [옵션 A 유지] or [옵션 D] 파라과이 법인으로 전환
                         Ventago 본거지 활용

  USD 50,000+/월      →  [옵션 B] 우루과이 ZFSA + 전문 회계법인
                         진짜 세금 최적화 단계

주요 고객이 "아르헨티나 국내"? → 옵션 C(지식경제제도) 추가 고려
주요 고객이 "남미 전역·글로벌"? → 옵션 A 또는 B 강력 추천
```

### 9.5 **Marcos님께 드리는 직접적인 권고**

1. **당장 Mercado Pago Argentina 법인으로 구독 받으시면 안 됩니다.** 실효세율 45~55%로 수익이 거의 안 남습니다.
2. **1순위 추천: US LLC + Stripe + Wise 구조.** 2~3주면 세팅되고, 아르헨티나 개인 소득세만 감당하면 됩니다. 이게 Nomad·SaaS 창업자의 표준 루트입니다.
3. **Ventago Argentina 매장의 POS 카드 결제**는 이 구조와 별도입니다. POS는 아르헨티나 매장이 **직접** Mercado Pago 계약하도록 하고, Ventago는 그 수수료의 일부를 Stripe로 청구(플랫폼 수수료 모델)하면 됩니다.
4. **세무 전문가 필수.** US LLC Form 5472 실수 시 $25,000 벌금. 처음부터 아르헨티나 + 미국 세무를 모두 아는 회계사와 계약하세요. (월 $300~500 수준)

### 9.6 업데이트된 최종 권장 아키텍처

| 시나리오 | PG | 법인 | 수취 | 실효세율(추정) |
|---|---|---|---|---|
| Ventago 구독료 (Marcos 수금) | **Stripe Billing** | **US LLC** | **Wise USD** → 한국/AR 개인 | **15~25%** |
| AR 매장 POS 결제 | Mercado Pago AR | 매장 명의 (Marcos 무관) | 매장 AR 계좌 | 매장 책임 |
| 기타 남미 매장 POS | dLocal / 현지 PG | 매장 명의 | 매장 현지 계좌 | 매장 책임 |

---

## 10. 한국 사업자 등록 경로 — 세율 비교

**중요 전제:** 이 섹션은 합법적 세무 최적화만 다룹니다. 탈세·편법은 포함하지 않습니다.

### 10.1 핵심 사실 2가지

1. **한국 법인/개인사업자는 Stripe 계정 직접 개설 불가.** 한국은 Stripe 공식 Merchant Country가 아닙니다. 2024~2025 Stripe 한국 원화 결제 지원은 "해외 Stripe 계정이 한국 고객 카드를 받을 수 있다"는 뜻이지, **"한국 사업자가 Stripe 머천트가 될 수 있다"는 뜻이 아닙니다.**
2. **한국에는 "수출 영세율" 제도가 있어 해외 SaaS 구독료에 대해 부가세 0% 적용이 가능합니다.** 단, 조건 충족과 증빙이 필수입니다.

### 10.2 한국 사업자 + 해외 결제 수취 — 실제 작동 구조

```
남미 고객 Visa 카드
  → [PG] Paddle / Lemon Squeezy (MoR) 또는 PayPal Business
  → 한국 개인사업자·법인 계좌 (KRW 환전 입금) 또는 Wise KRW
  → 국내 은행
```

또는:

```
남미 고객 Visa 카드
  → Stripe (해외 법인이 필요) ← 여기가 병목
```

**Stripe를 쓰려면 결국 해외 법인이 필요**하고, 순수 한국 사업자만으로 받으려면 **MoR(Merchant of Record) 플랫폼이 현실적**입니다.

### 10.3 한국 사업자로 직접 받는 3가지 경로

#### 경로 K1 — **Paddle / Lemon Squeezy (MoR) + 한국 사업자**

- Paddle/Lemon이 "판매자(Merchant of Record)"가 되어 세금·인보이스·환불 처리 대행
- 한국 사업자는 Paddle에서 **정산금만 KRW로 수취**
- Paddle 수수료 ~5% + $0.50 (Stripe보다 높지만 세금 부담 이전)
- **VAT·세금 처리 전부 Paddle이 떠맡음** → 한국 사업자는 그냥 매출 신고만
- 구독 기능·반복 결제·카드 토큰 전부 포함
- Stripe 계정 필요 없음 — 즉시 시작 가능

→ 한국 거주자 + 한국 사업자 신분을 유지하면서 Stripe급 경험을 얻는 **가장 현실적 옵션**.

#### 경로 K2 — **한국 개인사업자 + PayPal Business + 영세율**

- PayPal Business 한국 계정 개설 가능 (사업자등록증 필요)
- 해외 고객이 PayPal로 결제 → 한국 원화 계좌 출금
- 구독 기능(PayPal Subscriptions API) 지원
- **단, 영세율 적용을 위해서는 대금을 "외국환은행에서 원화로 수령"해야 함** — PayPal 직접 수령은 영세율 미적용 리스크
  - 해결: PayPal → 한국 외국환은행 송금 → 외화입금증명서 확보
- PayPal 수수료 ~4.4% + 고정

#### 경로 K3 — **해외 법인(US LLC 등) + 한국 거주자로 종합소득세 신고**

- US LLC가 Stripe로 받음 → Wise/은행으로 수취 → 한국 개인에게 배당·급여
- 한국 거주자는 **전 세계 소득 신고 의무** → 종합소득세 납부
- 종합소득세율 6~45% (누진), 외국납부세액공제 적용
- 한국에 **"외국법인 지분 보유 신고" (CFC 규정)** — 일정 요건 충족 시 유보소득 과세 가능성

### 10.4 한국 사업자 실효세율 시뮬레이션

**100만원 해외 SaaS 구독료 수취 기준 (개인사업자, Paddle 경로):**

```
고객 청구액:                       USD 765 ≈ KRW 1,000,000
Paddle 수수료 5% + $0.50:         약 -55,000
                                  ─────────
한국 사업자 KRW 수취:              약 945,000

부가세 (해외 수출 용역, 영세율):    0 ← 영세율!
종합소득세 (연간 누진, 가정):
  - 매출 1.2억 이하 구간 (단순경비율 가능): 순이익의 6~24%
  - 매출 7,500만원 이하 간이과세:          더 낮음
  - 중소기업 세액감면 적용 시:             50% 추가 감면

예시: 연 순이익 5천만원 → 실효세율 약 8~15%
```

**100만원 법인 기준:**

```
법인 매출 부가세 영세율:           0
법인세 (2억 이하 10%):             이익의 10%
대표 배당 / 급여 수령 시:          종합소득세 + 건강보험료
결합 실효세율 (배당 기준):         약 20~30%
결합 실효세율 (급여 기준):         약 15~25% (근로소득공제 적용)
```

### 10.5 최종 세율 비교 — **Marcos님 질문의 핵심 답변**

| 시나리오 | 실효 세율 (추정) | 설정 난이도 | 속도 |
|---|---|---|---|
| 아르헨티나 법인 + MP | **45~55%** ❌ | 쉬움 | 빠름 |
| 아르헨티나 Monotributo + MP | 10~20% (한도 내) ⚠️ | 쉬움 | 빠름 — 단 성장하면 불가 |
| 우루과이 ZFSA | 5~10% 🟢 | 매우 어려움 | 3~6개월 |
| 파라과이 법인 | 10~15% 🟢 | 중간 | 1~2개월 |
| US LLC + 아르헨티나 거주 개인소득세 | 15~25% 🟢 | 중간 | 2~4주 |
| **한국 개인사업자 + Paddle (영세율)** | **10~20%** 🟢 | **쉬움** | **1~2주** |
| **한국 법인 + Paddle (영세율)** | **15~25%** 🟢 | 중간 | 2~4주 |

### 10.6 한국 사업자 경로의 장점 — Marcos님 상황에 맞는 이유

1. **Marcos님이 한국 국적/한국 통장 보유** → 이미 기초 인프라 있음
2. **부가세 영세율** (해외 수출 용역) → 10% 절감
3. **MoR(Paddle·Lemon) 사용 시 Stripe 없이도** 남미 포함 글로벌 고객 카드 결제 가능
4. **사업자 등록 1~2일** + **Paddle 계정 2~3일** = 1주일 내 시작 가능
5. **중소기업 특별세액감면 50%** 적용 가능 (업종·지역 따라)
6. 아르헨티나 MP 원천징수·IIBB 완전 회피 (계약 주체가 한국 사업자)
7. Wise KRW 계좌로 Paddle 정산 수취 가능 → 환전 비용 절감

### 10.7 한국 사업자 경로의 주의점

- **Paddle은 Stripe보다 수수료가 1.5~2% 높음** (5% vs 3%)
- **영세율 증빙 철저히**: 외화입금증명서, 용역공급계약서, 외화획득명세서 3종 필수
- **Wise·PayPal 직접 수령은 영세율 적용 까다로움** → 외국환은행 경유 또는 Paddle KRW 직송금이 안전
- **한국 거주자면 전 세계 소득 신고 의무** (아르헨티나 체류 시 183일 룰 검토 필요)
- **한국·아르헨티나 이중거주자 문제** 회피하려면 체류일수 관리

### 10.8 **수정된 Marcos님 맞춤 권장안**

| 우선순위 | 구조 | 실효세율 | 이유 |
|---|---|---|---|
| ⭐ 1순위 | **한국 개인사업자 + Paddle + 영세율** | 10~20% | 가장 빠르게 합법적 저세율 달성 |
| 2순위 | US LLC + Stripe + Wise | 15~25% | 성장 단계에서 검토 |
| 3순위 | 한국 법인 전환 + Paddle | 15~25% | 매출 1억 이상 시 법인 전환 |
| 4순위 | 우루과이 ZFSA | 5~10% | 연매출 $500K+ 단계에서 검토 |
| ❌ 비추천 | 아르헨티나 Responsable Inscripto | 45~55% | 수익성 붕괴 |

**Marcos님이 하신 판단이 정확합니다. 한국 사업자 + MoR 구조가 현 상황에서 최적입니다.**

---

## 11. 아르헨 11개월 체류 + 한국 1개월 체류 시나리오 — 현실적 해법

### 11.1 핵심 질문 재정리

> "한국에 매년 1개월 체류, 아르헨티나 11개월 체류. 한국에 법인 설립 + 한국 세무사 고용 가능한가?"

**결론부터:**
1. **한국 법인 설립은 가능**합니다. 해외거주 비거주자도 한국 주식회사 대표이사가 될 수 있습니다.
2. 그러나 **거주자 판정 기준상 Marcos님은 "한국 비거주자 + 아르헨티나 세무 거주자"가 됩니다.**
3. **한국과 아르헨티나는 조세조약이 없습니다** — 이게 치명적입니다.
4. **"한국 법인의 배당·급여를 아르헨티나 거주자가 받으면, 아르헨티나가 전 세계 소득 과세"** 합니다.

### 11.2 거주자 판정 — 4가지 중요한 사실

#### 사실 1. 한국 세법상 거주자 기준

| 기준 | 내용 | Marcos님 해당? |
|---|---|---|
| 국내 주소 | 생활 근거지가 한국 | 아마 아님 (아르헨 거주) |
| 183일 거소 | 1과세기간 내 183일 이상 | 아님 (연 1개월) |
| **2과세기간 걸친 183일** (2026 신설) | 2년 연속 누적 183일 | 연 1개월 = 2년 60일, 아님 |
| 생계 같이하는 가족 | 한국 체류 | 상황 따라 다름 |

→ **Marcos님은 한국 세법상 "비거주자"** 입니다.

#### 사실 2. 아르헨티나 세법상 거주자 기준

- 연 **183일 초과 체류 시 자동으로 세무 거주자**
- Marcos님은 11개월(330일) 체류 → **아르헨티나 세무 거주자 확정**
- **전 세계 소득(worldwide income)에 대해 아르헨티나가 과세**

#### 사실 3. 한국·아르헨티나 조세조약 없음

- 한국은 98개국과 조세조약 체결, **아르헨티나는 제외**
- 이중과세방지 장치가 없음
- 양국이 각각 자국 법대로 세금 부과 가능
- 외국납부세액공제(foreign tax credit)는 자국 법에서 제한적으로만 허용

#### 사실 4. 한국 법인 대표이사 요건

- 비거주자 외국인·내국인 모두 대표이사 가능 (법무적 제한 없음)
- 서명증명·주소증명 본국 공증 필요
- **실무상 한국에 회계·세무 담당자 또는 세무사 위임 필수**
- 한국 법인세·부가세 신고 의무는 한국 내에서 이뤄짐

### 11.3 그래서 "한국 법인 + 세무사" 구조가 실제로 어떻게 작동하는가

```
[돈의 흐름]
남미·글로벌 고객 Visa 카드
   ↓
Paddle / Lemon Squeezy (MoR)
   ↓
한국 법인 KRW 계좌 (한국 은행)
   ↓
┌─────────────────────────────────────┐
│ 한국 법인 수준 (한국 세무사 관리)    │
│  - 부가세 영세율 (수출 용역 0%)     │
│  - 법인세 (2억 이하 10%)            │
│  - 한국 세무사에게 월 위임 OK       │
└─────────────────────────────────────┘
   ↓ (배당 또는 급여)
Marcos님 개인 (아르헨티나 거주자)
   ↓
┌─────────────────────────────────────┐
│ 아르헨티나 개인 세무 (한국 세무사 X) │
│  - 전 세계 소득 과세 대상           │
│  - 한국에서 낸 세금 공제 제한적     │
│  - 아르헨티나 Ganancias 5~35%       │
└─────────────────────────────────────┘
```

**이 구조에서의 실효세율 시뮬레이션 (한국법인 이익 1억원 → 배당 전체 아르헨티나 수취):**

```
법인 매출 (영세율):              100,000,000 (부가세 0)
법인세 10%:                      -10,000,000
법인 세후 이익:                   90,000,000

배당금 Marcos 개인 수령:          90,000,000
한국 비거주자 배당 원천징수 20%:  -18,000,000 (조세조약 없어 경감 불가)
한국 송금 후 수취:                72,000,000

아르헨티나 Ganancias 적용 (worldwide income):
  외국법인 배당 → 15~35% (이미 한국에서 낸 세금 공제 부분 가능)
  공제 후 추가 세금 약:           -7,000,000 ~ -15,000,000

실수령액:                        약 57,000,000 ~ 65,000,000
실효세율:                        약 35~43%
```

→ **한국 법인만 세우는 것으로는 원하는 만큼 세율이 낮아지지 않습니다.** 아르헨티나가 11개월 체류 → 전 세계 소득 과세하기 때문입니다.

### 11.4 근본 원인 — "거주자(체류일)"가 "법인 국적"보다 우선한다

세무는 **"돈이 어디로 들어오느냐"가 아니라 "받는 사람이 어느 나라 거주자냐"** 로 결정됩니다. 법인을 한국에 만들어도 **법인의 이익을 꺼내 쓰는 개인(=Marcos님)이 아르헨티나 거주자**인 이상, 결국 아르헨티나가 과세 핸들을 쥡니다.

### 11.5 **그럼 방법이 없나요? — 있습니다. 3가지 옵션**

#### 옵션 X — **한국 법인 + 이익을 한국에 유보 (배당하지 않기)**

- 한국 법인 이익을 **배당하지 않고 법인 내부 유보**
- 한국 법인세 10%만 내고 끝
- Marcos님 개인은 이익 실현 X → 아르헨티나 과세 대상 아님
- 돈은 한국 법인 통장에 쌓여 감 (Marcos님 개인 쓸 돈은 아니지만 회사 자산)
- 연 1개월 한국 체류 시 **한국 법인에서 급여를 합리적 수준으로 받음**
  - 한국 비거주자 근로소득 원천징수 ~22% (조세조약 없어 경감 불가)
  - 또는 1개월 체류 중 발생한 근로분만 한국 원천소득으로 신고
- 배당 시점을 **Marcos님이 한국으로 이주/귀국한 뒤** (거주자 상태)로 늦추면 조세조약·경감 활용 가능

**실효세율 (유보 전략): 10~15%** 🟢

단점: 당장 개인 현금흐름 제한. Ventago 본인 생활비는 별도로 확보 필요.

#### 옵션 Y — **한국 법인 + 파라과이/우루과이 거주 전환**

- 아르헨티나 체류를 **연 183일 이하**로 낮춰 아르헨티나 세무 거주자 탈피
- 남는 기간은 **파라과이 또는 우루과이**로 분산 체류
- 이 두 나라는 거주자 기준이 덜 엄격하고, 외국소득 과세가 약함
- Ventago 본거지 파라과이 활용 → 자연스러움

**실효세율: 10~15%** 🟢

단점: 아르헨 체류 일수 근본적 재조정 필요. 라이프스타일 변경.

#### 옵션 Z — **한국 법인 X, 그냥 한국 개인사업자 + Paddle**

- 이 경우에도 **Marcos님이 아르헨티나 세무 거주자** 이므로 아르헨티나 과세 피할 수 없음
- 다만 **개인사업자는 법인처럼 "유보" 개념이 없음** → 이익 즉시 실현 → 즉시 아르헨티나 과세
- 결국 옵션 X보다 불리

→ **법인 유보 전략(옵션 X)이 더 유리한 이유.**

### 11.6 수정된 최종 의사결정 매트릭스

| 구조 | 실효세율 | 라이프스타일 | 복잡도 | Marcos님 적합도 |
|---|---|---|---|---|
| 아르헨티나 개인사업자 + MP | 45~55% | 그대로 | 낮음 | ❌ |
| 한국 법인 + 즉시 배당 (Marcos 수령) | 35~43% | 그대로 | 중 | ⚠️ |
| **한국 법인 + 이익 유보 (옵션 X)** | **10~15%** | 그대로 | 중 | ⭐ **현실적 1순위** |
| 한국 법인 + 파라과이 거주 전환 (옵션 Y) | 10~15% | 라이프 변경 | 중 | 2순위 |
| US LLC + 아르헨 거주 | 35~43% | 그대로 | 중 | ⚠️ 동일 문제 |
| 우루과이 ZFSA | 5~10% | 라이프 변경 | 매우 복잡 | 장기 전략 |

### 11.7 **Marcos님께 드리는 구체적 권고**

**단기 (1~3개월 내):**
1. **한국에서 주식회사 설립 (대표이사 Marcos, 본인)** — 해외거주 상태로 가능
2. **한국 세무사 월 위탁 계약** — 월 20~40만원 수준
3. **Paddle 또는 Lemon Squeezy 법인 계정 개설**
4. **한국 법인 명의 Wise Business 개설 + Paddle 정산 연결**
5. **법인 통장에 이익 유보**, Marcos님 한국 체류 1개월 동안만 **합리적 근로소득(예: 월 300~500만원)** 수령

**중기 (6~12개월):**
1. 법인 자본·이익 성장 시 **한국 국민연금·건강보험 최적화** 설계
2. **파라과이 또는 우루과이 거주 이전** 검토 (아르헨티나 183일 초과 방지)
3. 필요 시 **Ventago 자산/지분을 한국 법인으로 양도** 검토

**장기 (12개월+):**
1. 매출 $500K+ 달성 시 **우루과이 ZFSA 재검토**
2. 한국 법인 유보 자금으로 **한국 내 부동산·투자** 전략적 활용
3. Marcos님 최종 귀국 시점에 **배당 실행** (거주자 전환 후 조세조약 혜택)

### 11.8 세무사 선정 기준 (매우 중요)

아무 세무사나 쓰시면 안 됩니다. 다음 3가지를 겸비한 사람이 필요합니다:

1. **수출 영세율 실무 경험** (소프트웨어·SaaS 고객 경험 필수)
2. **비거주자 대표이사 법인** 세무 경험
3. **이중거주자·외국납부세액공제** 이해

추천 업종 키워드로 검색:
- "해외 진출 기업 전문 세무사"
- "크로스보더 세무"
- "비거주자 법인 세무"
- "글로벌 SaaS 세무"

예상 비용: 법인 설정 100~200만원 + 월 30~50만원 (상담 포함)

### 11.9 ⚠️ 반드시 확인해야 할 리스크

1. **아르헨티나 CFC(Controlled Foreign Corporation) 규정**: 아르헨티나 거주자가 지배하는 외국법인의 유보이익에 대해 **실제 배당하지 않아도 과세**할 수 있는 규정이 있을 수 있음 → 아르헨티나 세무사와 반드시 확인
2. **한국 과점주주 간주배당**: 한국에서 이익 유보만 하다가 청산·이전 시 과세
3. **CRS(공통보고기준)** 하에 한국 법인 정보가 아르헨티나 세무당국에 자동 공유될 수 있음 → **숨길 수 없음**
4. **한국 국민연금·건강보험** 가입 의무 여부 검토 (대표이사 체류일 기준)

---

## 12. 다음 단계 제안

다음 중 어떤 걸 먼저 진행할지 알려주시면, 그에 맞춰 `gsd` 스킬로 Plan → Execute → Review 로 들어가겠습니다:

1. **Phase 1 아키텍처 설계서** 작성 (DB 마이그레이션 SQL + NestJS 모듈 스켈레톤)
2. **Stripe 계정 개설 가이드** (어떤 국가로 만들지, Wise 연결까지)
3. **dLocal / Mercado Pago 영업팀 컨택용 견적 요청 문서** 작성
4. **PostgreSQL 운영 pool 영향 시뮬레이션** (결제 webhook 부하 분석)
