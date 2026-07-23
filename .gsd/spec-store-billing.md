# SPEC: 매장 정산(Store Billing) 시스템 — 플랫폼 주인 ↔ 매장
생성일: 2026-07-22  (spec-cobros-superadmin.md 대체 — 대상 오인 정정)

## 목표
시스템 주인(superadmin)이 각 매장(tenant)에게 청구한 SaaS 구독료를 매월 자동 청구서로 생성하고,
수납(현금/MercadoPago 등)을 기록하며, 미납 매장을 관리한다. ★기존 소매고객 외상(credit_ledger)과 완전 분리.

## 배경 (조사)
- 요금표: subscription_config(id=1, 현재 enabled=false). base 60000 + extra_branch 40000 + extra_terminal 20000 + 통합 애드온 8종(30k~70k). ARS, trial 30, grace 3, gateway 'manual'.
- 매장별 요소: branches(매장별 지점 수 有), terminals(매장별 수 有, store6=13), store_integrations(현재 0행 — 통합 미사용). type_of_payer 전부 빈값. stores 9개.
- ★config 에 '기본 포함 지점/터미널 수' 필드 없음 → 신설 필요(included_branches/included_terminals, 기본 1).

## 신규 데이터 (별도 스키마, credit_ledger 무관)
- 마이그레이션: 
  - `store_billing_invoices`(id, store_id, period 'YYYY-MM', issued_at, due_date, currency, base_amount, branches_qty, branches_amount, terminals_qty, terminals_amount, integrations_amount, total_amount numeric, status 'pending|paid|partial|void', note). UNIQUE(store_id, period). ALTER OWNER coolsistema.
  - `store_billing_payments`(id, store_id, invoice_id nullable, amount numeric, method varchar(slug: mercadopago/efectivo/transferencia/...), paid_at, receipt_no, note, created_by). ALTER OWNER coolsistema.
  - subscription_config += included_branches int default 1, included_terminals int default 1.
- 매장 잔액 = Σ invoices.total(status≠void) − Σ payments.amount.

## 태스크
- [ ] TASK-M1: 마이그레이션(위 2테이블 + config 2컬럼). 운영 적용은 SSH 수동(사용자). ALTER OWNER/시퀀스 coolsistema 필수.
- [ ] TASK-B1: billing 모듈(NestJS) — models + service.
  - computeInvoiceAmount(store): base + max(0,branches-included_b)*extra_branch + max(0,terminals-included_t)*extra_terminal + Σ 활성 store_integrations 가격. 단일 SELECT 조합, pool 안전.
  - generateMonthly(period): 활성 매장별 invoice UPSERT(멱등, UNIQUE(store,period)). 상태 pending. due_date=issued+grace/기준일.
  - registerPayment(dto): SERIALIZABLE tx, invoice/store 잠금, payment INSERT + invoice.status 갱신(부분/완납). 외부호출 commit 후.
- [ ] TASK-B2: 컨트롤러(@Auth superadmin) — GET /billing/summary?period, GET /billing/debtors, GET /billing/stores/:id, POST /billing/payments, POST /billing/generate?period(수동), + cron 매월 자동.
- [ ] TASK-B3: eslint(신규 0)+tsc 통과.
- [ ] TASK-A1: 앱 billing_repository.dart + cobros_screen.dart(목업대로: 매장 KPI + 미납매장 목록 + 스와이프 수납). app_shell 내비 'Cobros'.
- [ ] TASK-A2: 러너 빌드 + Dropbox.
- [ ] TASK-DEPLOY: 마이그 적용 확인 후 백엔드 push→Jenkins 웹훅 시뮬 → 스모크. (billing enabled 토글은 사용자 결정.)

## 완료 기준
- 매월 자동 invoice 생성(멱등). 금액=config 자동계산. 수납/잔액/미납 정상. credit_ledger 무영향(별도 테이블).
- pool: report=단일 SELECT, payment=기존 패턴 tx. 추가 점유 없음.

## ★결정 필요 (사용자)
1. 기본 플랜 포함 지점/터미널 수 (제안: 지점1·터미널1, 초과분만 과금). ※store6=터미널13이면 초과 12×20k=240k — 실제 의도 확인.
2. 청구 생성일/마감(제안: 매월 1일 생성, 마감=+grace 3일... 또는 별도 지정).
3. 시작 시점 — 이번 달부터, 소급 없음(제안).
4. subscription_config.enabled 를 켤지(현재 false).

## 금지/주의
- credit_ledger/store_clients 절대 미사용(소매 외상과 분리).
- 운영 매출 시스템 → 자동청구는 pending 으로만 생성(매장 통지 없음, 주인 검토용). 금액 검증 후 확정.
