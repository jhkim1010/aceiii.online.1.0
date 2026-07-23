# SPEC: superadmin 앱 Cobros(수금) 기능
생성일: 2026-07-22

## 목표
superadmin 안드로이드 앱(ventago-admin-app)에 매장별 "Cobros(수금)" 화면 추가 — 총 수령액/MercadoPago/미수금 KPI + 미납자 목록 + 카드 오른쪽 스와이프로 "현금 수령 OK" 등록(날짜+금액 기록, 잔액 차감).

## 배경 (조사 결과 — 기존 인프라 최대 재사용)
- ★수금 등록: `POST /api/credit/payments` (CreditPaymentService.registerPayment) — SERIALIZABLE tx + store_client FOR UPDATE + FIFO(payment_in), pool 안전(외부호출 commit 후). DTO: {storeClientId,storeId,totalAmount,paymentMethodId,optionId?,receiptNo,paymentKind,branchId?,userId?,note?}. paymentKind='credit_payment'.
- ★미납자: `GET /api/credit/reports/top-debtors?limit` → {store_client_id, fullname, document, credit_balance(=sc.balance), senia_balance, favor_balance, oldest_due_date}. 잔액 진실 = store_clients.balance.
- 고객요약/원장: `GET /credit/clients/:id/summary`·`/ledger`.
- 결제수단: payment_methods.slug ('efectivo','mercadopago','credito',...), 전역+매장별. 분할결제 금액 = sale_payment_methods.amount.
- movement_type: 'sale_credit'|'payment_in'|'favor_in'|'favor_apply'.
- ★제약: 기존 credit 엔드포인트는 user.storeId! 사용 → superadmin(storeId=null) 은 storeId 지정 필요.

## 기술 스택
- 백엔드 api-ventago(NestJS+Sequelize, PG18:5434, pgbouncer). ESLint 有(no-unsafe-* 기존부채 다수 — 신규만 0).
- 앱 Flutter(Riverpod+dio). 스와이프=Dismissible(내장, 신규 의존성 X).

## 태스크
- [ ] TASK-B1: superadmin storeId 오버라이드 — POST /credit/payments, GET /credit/reports/top-debtors, GET /credit/clients/:id/summary 에 optional storeId 허용. 가드: superadmin 만 오버라이드 가능(비-superadmin 은 user.storeId 강제). 파일: credit-payment.controller.ts, credit-report.controller.ts.
- [ ] TASK-B2: 신규 `GET /api/credit/reports/received-summary?storeId=&from=` — 단일 raw SELECT(pool 1점유). 반환: { totalReceived, byMethod:[{slug,title,total,clients}], mercadopago:{total,clients}, pending:{total,debtors} }. "받은 돈"=sale_payment_methods(slug∉credito,favor,vale_*) 합 + credit_payments 합. pending=SUM/COUNT store_clients.balance>0. 파일: credit-report.service.ts(+controller).
- [ ] TASK-B3: eslint(신규 파일 0) + tsc(-p tsconfig.build.json) 통과.
- [ ] TASK-A1: cobros_repository.dart — getReceivedSummary/getDebtors/registerCashPayment(storeId 전달). 파일 신규.
- [ ] TASK-A2: cobros_screen.dart — 매장 셀렉터(기본 store 6) + KPI 카드 3 + 미납자 Dismissible(startToEnd) → confirmDismiss 로 "현금 수령 OK" 다이얼로그(금액 기본=잔액, 편집가능) → registerCashPayment → 목록 새로고침. 파일 신규.
- [ ] TASK-A3: app_shell.dart 에 'Cobros' 내비 추가.
- [ ] TASK-A4: 러너 flutter-admin-apk 빌드 + Dropbox 복사.
- [ ] TASK-DEPLOY: 백엔드 커밋+push → Jenkins 웹훅 시뮬레이션(api-new-coolsistema) → 스모크(엔드포인트 401·login 200).

## 완료 기준
- 신규 코드 eslint 0, tsc 통과. 미납자 목록/수금등록/KPI 정상. store_clients.balance 정합(기존 registerPayment 재사용, 수동 잔액계산 금지).
- pool: 신규 report=단일 SELECT, 수금=기존 tx 서비스. 추가 커넥션 점유 없음.

## 금지/주의
- credit_ledger/credit_payments 쓰기 로직 신규작성 금지 — registerPayment 그대로 호출.
- storeId 오버라이드 가드 필수(비-superadmin 크로스매장 차단).
- receiptNo 필수 → 앱에서 'COBRO-<yyyymmddHHMMSS>' 생성. paymentMethodId=해당 매장 efectivo id(요약 응답 or 별도 조회로 해결 — B2 에서 매장 efectivo id 포함 반환).
- 기존 무관 부채(ShopReadonlyDb, eslint no-unsafe)는 건드리지 않음.
