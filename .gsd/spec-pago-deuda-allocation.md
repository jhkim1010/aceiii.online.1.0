# SPEC: Pago 등록 시 supplier 외상(deuda) FIFO 차감
생성일: 2026-07-03

## 목표
`POST /materia-prima/payments` 로 pago 등록 시, 해당 공급자의 미결제 입고(ENTRADA) 이동에
결제액을 FIFO 로 배분하여 `paid_amount`/`payment_status` 를 갱신 → deuda 가 실제로 차감되게 한다.

## 배경 및 컨텍스트
- **버그**: payment 생성이 generic `CrudService.create` 를 그대로 사용 → `mes_material_supplier_payments` 에 insert 만 하고 끝.
- deuda 계산(`getSupplierDebtSummary`)은 **오직** `mes_material_movements` 의
  `total_amount - paid_amount` (type=ENTRADA, status PENDIENTE/PARCIAL) 만 본다.
- 따라서 pago 를 아무리 등록해도 deuda 불변 (로그 2026-07-03 15:53 POST 201 후 debt-summary 동일 134b 응답으로 확인).
- 관련 파일:
  - `api-ventago/src/app/production/material-supplier-payments/material-supplier-payment.service.ts`
  - `api-ventago/src/app/production/material-movements/material-movement.model.ts` (paidAmount, paymentStatus)
  - 프론트 `ventago-app/src/views/materia-prima/PagosView.tsx` — 변경 불필요 (등록 후 refetchDebt 이미 수행)

## 기술 스택
- NestJS 11 + Sequelize (sequelize-typescript)
- DB: 로컬 PG18 (`ventago`) — pool 은 database.module.ts 전역 설정 (min=10, max=80), raw pool 사용 안 함
- ESLint: 프로젝트 규칙 (newline-before-return, lines-around-comment 주의)

## 설계
`MaterialSupplierPaymentService.create(data)` 오버라이드, 단일 `sequelize.transaction`:
1. payment row 생성
2. `data.movementId` 가 있으면 해당 movement 먼저 배분
3. 나머지 금액을 supplier 의 미결제 ENTRADA movements (movement_date ASC, id ASC) 에 FIFO 배분
   - `lock: t.LOCK.UPDATE` 로 row lock (동시 결제 대비)
   - alloc = min(잔여결제액, total_amount - paid_amount)
   - newPaid >= total → PAGADO, 아니면 PARCIAL
4. 초과 결제(잔여 > 0)면 배분 없이 이력만 남김 (deuda 0 이 최저)

## 태스크 목록
- [x] TASK-1: `material-supplier-payment.service.ts` — create 오버라이드 (FIFO 배분 + 트랜잭션) — DECIMAL 은 Number() 캐스팅
- [ ] TASK-2: ESLint 검증 (`npx eslint` — Mac 로컬에서 실행, 샌드박스 불가)
- [ ] TASK-3: 테스트 데이터 정리 — payment id=4 ($1.000.000, 미배분) 삭제 (사용자 psql)
- [ ] TASK-4: 수동 검증 — pago 등록 후 deuda 차감 확인 + movements 화면 상태 확인

## 완료 기준
- pago 등록 → deuda 즉시 차감, movement 상태 PARCIAL/PAGADO 전환
- ESLint 오류 0개
- pool 낭비 없음 (sequelize.transaction 이 connection 자동 반환)

## 금지사항 / 주의사항
- getSupplierDebtSummary 쿼리 로직 변경 금지 (movements 가 진실의 원천 유지)
- 프론트 수정 불필요 — 범위 밖
- 운영 반영 시: FK 교체 마이그레이션(2026-04-25) 4번 섹션 운영 미적용 여부 먼저 확인 필요
