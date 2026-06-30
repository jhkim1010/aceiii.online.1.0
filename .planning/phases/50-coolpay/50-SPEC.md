# SPEC: Phase 50 — CoolPay (자체 결제·자금관리 시스템)
생성일: 2026-06-29
성격: **기획/준비 문서** (코드 착수 전 게이트 보유). 상세 배경은 `50-CONTEXT.md`.

## 목표

Ventago 결제를 외부 의존(MP)에서 점진적으로 **자체 결제·정산·자금관리(CoolPay)** 로 전환한다.
단, 규제 자격 없이 갈 수 있는 단계(Stage 0/1)를 먼저 완성·검증하고, 가치가 증명되면
PSPCP 등록(Stage 2)으로 진입한다. 모든 단계의 공통 기반은 **이중기입 append-only 원장**이다.

## 비목표 (Non-goals, 현 시점)

- 무자격 자금 보관/잔액 (Stage 2 라이선스 전까지 금지)
- 카드 망 직접 가입(어콰이어링) — 초기엔 PSP 경유
- 암호화폐/크로스보더 (별도 검토)

## 기술 스택 (예정)

- NestJS 11 + TypeScript + Sequelize (PG10/15 호환 마이그레이션)
- 결제 추상화: 기존 `PaymentProvider`(`api-ventago/src/app/payments/`) 확장
- 원장: PostgreSQL, append-only, 멱등키, 트랜잭션 정합 (pool 낭비 금지 규약 준수)
- 외부: MP(Stage 0/1) + 라이선스드 PSP(Stage 1) 어댑터

## 결정 게이트 (Gates)

- **G0 (착수 전)**: BCRA PSP 전문 로펌 1차 자문 — 자본·임원요건·Stage 1 합법 범위 확인. *통과 못하면 Stage 0 까지만.*
- **G1 (Stage 0→1)**: Split 분할정산 실거래 + 가맹점 수요 검증.
- **G2 (Stage 1→2)**: 거래량/마진이 PSPCP 등록·자본·컴플라이언스 비용을 정당화하는가 → go/no-go.

## 태스크 목록 (Waves)

### Wave 50-00 — 법무·규제 선상담 ⬜ (G0)
- [ ] BCRA PSP/PSPCP 전문 로펌 자문(자본·임원·정보보고·AML 요건, "PSPCP como Servicio" 적용 여부)
- [ ] Stage 1(어그리게이터) 합법 경계 확인 — 자금 비보관 구조의 적법성
- [ ] go/no-go 메모 + 자본/타임라인 추정

### Wave 50-01 — 이중기입 원장 v1 (Stage 0 기반) ⬜
- [ ] 스키마 설계(아래 §원장 스키마) — `coolpay_accounts`, `coolpay_ledger_entries`, `coolpay_payments`, `coolpay_settlements`, `coolpay_payouts`
- [ ] **append-only** 보장(UPDATE/DELETE 금지, 정정은 역분개), 멱등키 UNIQUE
- [ ] 마이그레이션(PG10/15) + 모델 + 읽기 리포트(잔액/정산 view)
- [ ] 모든 자금 이동 더블엔트리(차변/대변) 기록

### Wave 50-02 — MP Split 분할정산 + 자체 원장 연결 (Stage 0) ⬜
- [ ] 기존 MP OAuth Split 으로 판매자별 자동 분할정산(자금은 MP 보관)
- [ ] Split 결과를 원장에 기입(수수료/정산 차변·대변) — 멱등(webhook 재처리 안전)
- [ ] 가맹점별 정산 리포트(읽기)

### Wave 50-03 — PaymentProvider 추상화 확장 + payments append-only ⬜
- [ ] `PaymentProvider` 에 정산/환불/조회 계약 보강(CoolPay/MP 공통)
- [ ] `coolpay_payments` append-only + 멱등키(webhook/재시도 정합)
- [ ] provider 라우팅(어떤 결제사로 보낼지) 정책

### Wave 50-04 — 멀티 PSP 어그리게이터(결제 라우터) (Stage 1) ⬜ (G1 후)
- [ ] `PspAdapter` 포트(MP + 카드 PSP) — 자금은 라이선스드 PSP 가 커스터디
- [ ] 정산/수수료 엔진(자체 원장 기준) + 가맹점 대시보드
- [ ] 대사(reconciliation): PSP 보고 ↔ 자체 원장 일치 검증 잡

### Wave 50-05 — AML/KYC 데이터 모델(준비만) ⬜
- [ ] 거래·고객 식별 데이터 구조 설계(향후 의무화 대비) — *수집/시행은 Stage 2*
- [ ] 의심거래 모니터링 훅 지점 정의(미구현, 설계만)

### Wave 50-06 — (G2 통과 시) PSPCP 등록 + 자체 지갑/잔액 (Stage 2) ⬜
- [ ] BCRA PSPCP 등록 절차(임원 서류·자본·정보보고)
- [ ] `coolpay_wallets` 잔액(원장 파생) + payout(이체) — 라이선스 발효 후에만
- [ ] 관측성/감사/장애 자금 복구 런북

## 원장 스키마 스케치 (Wave 50-01, append-only 더블엔트리)

```
coolpay_accounts        -- 원장 계정(가맹점/수수료/MP중간/대기 등)
  id, store_id?, type('merchant'|'fee'|'gateway'|'suspense'), currency, created_at

coolpay_ledger_entries  -- append-only 분개 (변경 금지, 정정=역분개)
  id, txn_group_id, account_id, direction('debit'|'credit'),
  amount NUMERIC, currency, ref_type, ref_id, idempotency_key UNIQUE, created_at
  -- 같은 txn_group_id 의 debit 합 == credit 합 (불변식)

coolpay_payments        -- 결제 원천(주문↔결제사) append-only
  id, online_order_id, provider, external_ref, status, amount, idempotency_key UNIQUE, created_at

coolpay_settlements     -- 가맹점 정산 배치
  id, merchant_account_id, period, gross, fees, net, status, created_at

coolpay_payouts         -- (Stage 2) 실제 이체 — 라이선스 후에만
  id, merchant_account_id, amount, status, external_ref, created_at
```

## 완료 기준 (단계별)

- **Stage 0**: MP Split 분할정산 1건 이상이 원장에 더블엔트리로 정확히 기록 + 멱등(중복 webhook 무해) + 정산 리포트.
- **Stage 1**: PSP 라우터로 2개 이상 결제사 추상화 + 대사 잡이 불일치 0 검증.
- **Stage 2**: (라이선스 발효 후) 자체 잔액·payout 가 원장과 일치, 감사 통과.

## 금지사항 / 주의사항

- **라이선스 없이 타인 자금 보관 금지** (Stage 2 전까지 자금은 MP/PSP 가 커스터디).
- 원장은 **append-only** — UPDATE/DELETE 금지, 정정은 역분개. 멱등키 누락 금지.
- 돈 관련 모든 async 에 에러핸들링·재처리 안전(멱등) — 무관용.
- PostgreSQL pool 낭비 금지(워커 동시성으로 제어, pool 과 분리) — 프로젝트 규약.
- 규제·세금·정산 수치는 법무/회계 검증 전 확정 금지.

## 의존/연계

- 선행: 공개몰 결제(MP Checkout) 운영 + `PaymentProvider` 추상화(이미 존재).
- 연계: online_orders(주문), mercadopago(Split/Wallet/Transfer 재사용).
- 로드맵: `future proyect/00-expansion-strategy-roadmap.md` 방향 ③.
