# SPEC: 수표(Cheque) Cartera 시스템
생성일: 2026-07-07

## 목표
판매 결제로 수표를 받아 cartera(보유고)에 등록하고, gasto 지불 시 배서(endoso)로 사용하며, /cheques 메뉴에서 전체 생명주기를 추적한다.

## 확정된 설계 결정 (사용자 승인)
- 상태 전체 생명주기: `EN_CARTERA → USADO / DEPOSITADO / RECHAZADO`
- 차액 별도 기록: `expense_cheques.applied_amount` + `difference_amount`
- 메뉴: `/cheques` 독립 페이지 (admin 앱, adminOrder에서 /caja 다음)

## 배경 및 컨텍스트
- payment_methods 시드에 `slug='cheque'` 이미 존재 (type: mayorista) — POS에서 선택 가능하나 상세정보/추적 없음
- POS 결제 모달: `PaymentSummaryModal.tsx` (PaymentMethodsModal) — 분할결제, payment 객체에 slug 포함됨
- **주의**: `ProductList.tsx` saleObject의 paymentMethods 매핑이 `{paymentMethodId, optionId, amount}`만 전송 → cheque 정보 추가 필요
- 백엔드 결제 처리: `sales-create.service.ts::processPaymentMethods` (트랜잭션 내, slug='efectivo'만 분기 존재)
- Gasto: `ExpenseModal.tsx` — 지불수단 없음, affectsBox→caja 차감. 백엔드 `expenses.service.ts::createExpense`
- 네비게이션: DB 모듈 기반 + 코드 주입 패턴 (`navigation/vertical/index.ts`, Ventas Online 참조)
- 페이지 ACL: `Page.acl = { action: 'read', subject: 'caja' }` (caja 권한 재사용)

## 기술 스택
- NestJS 11 + Sequelize (underscored:true, autoLoadModels) / Next.js 13 + MUI 5
- DB: 로컬 PG18 (mcp postgres-ventago), 운영 PG10 (SSH, 사용자 승인 필요)
- ESLint: newline-before-return, lines-around-comment, no-unused-vars 주의

## DB 스키마
```sql
cheques: id, store_id FK, branch_id FK, number, bank, holder_name, holder_cuit,
  amount NUMERIC(12,2), type('comun'|'diferido'), due_date DATE,
  status('EN_CARTERA'|'USADO'|'DEPOSITADO'|'RECHAZADO'), sale_id FK,
  received_at, deposited_at, rejected_at, notes, created_by FK, timestamps
expense_cheques: id, expense_id FK, cheque_id FK UNIQUE, applied_amount, difference_amount, timestamps
expenses: + payment_source VARCHAR(10) DEFAULT 'caja'
```
PG10 호환(SERIAL, GENERATED 금지), 끝에 ALTER OWNER TO coolsistema (로컬은 role 존재 체크 DO 블록).

## 태스크 목록
- [x] TASK-1: 마이그레이션 `api-ventago/migrations/cheques-cartera.sql` (로컬 PG 적용은 Mac에서 psql 실행 필요)
- [x] TASK-2: Cheque/ExpenseCheque 모델 + ChequesService/Controller/Module + app.module 등록
- [x] TASK-3: CreateSalePaymentMethodDto에 cheque 필드, processPaymentMethods에서 slug='cheque' 시 Cheque 생성 (트랜잭션 내)
- [x] TASK-4: expenses: payment_source, createExpense에서 cheque 검증/USADO 전이/차액 기록 (트랜잭션)
- [x] TASK-5: PaymentSummaryModal cheque 필드 + ProductList saleObject 매핑에 cheque 전달
- [x] TASK-6: ExpenseModal medio de pago + cheque picker + 차액 표시
- [x] TASK-7: /cheques 페이지 (KPI/필터/테이블/액션) + 네비게이션 주입
- [x] TASK-8: ESLint 검증 완료 (backend 0, frontend 0 errors — 기존 exhaustive-deps warning만). 전체 tsc 는 Mac에서 실행 필요 (샌드박스 CPU 제약)

## 후속 작업 (미해결)
- sale nullify 시 해당 sale 의 EN_CARTERA 수표 처리 정책 미정 (현재: cartera 에 남음 — 수동 rechazar 필요)
- 수표로 지불한 gasto 를 삭제/수정할 때 수표 USADO 롤백 없음 (CrudController 기본 흐름)
- 운영 DB 마이그레이션 미적용 (사용자 승인 후 SSH 실행)

## 완료 기준
- ESLint 오류 0개, 수표 없는 기존 판매/gasto 흐름 무회귀
- 수표 사용은 1회만 (UNIQUE cheque_id), 사용 시 caja 무영향
- pool: 트랜잭션 단일 사용, 커넥션 누수 없음

## 금지사항 / 주의사항
- 운영 DB 적용은 사용자 승인 후 (마이그레이션 파일만 커밋)
- 기존 efectivo/credito/MP 결제 분기 무변경
- pageSize 최대 50, apiConnector.remove() 사용
- 재고/판매 차단 로직 추가 금지
