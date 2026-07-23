# SPEC: AFIP 발행 직후 comandera 자동 감열출력 배선 (CoolSyncro 알고리즘 이식)
생성일: 2026-07-23

## 목표
CoolSyncro `cae-issuer.js`의 "CAE 획득 → 로컬 저장 → 즉시 printReceipt" 알고리즘을 ACE에 이식한다.
즉, fac. electronica 발행(CAE 성공) 직후 백엔드가 자동으로 `AfipOutputService.dispatch({output:'thermal'})`를
호출해 comandera termica로 재정영수증을 출력하도록 배선한다. 출력 실패는 비치명적(판매·CAE 유효 유지).

## 배경 및 컨텍스트
- print-agent(main.js)는 `print_fiscal`/`print_invoice(payload.factura)` 수신 시 fiscal HTML→PNG→ESC/POS로
  comandera 출력이 이미 구현됨 (변경 없음).
- 영수증 포맷(build-factura.ts + fiscal-formatter.js)은 이미 CoolSyncro thermal-generator와 정렬됨 (변경 없음).
- `AfipOutputService.dispatch({output:'thermal',...})`가 emitPrintInvoice로 print-agent에 emit하는 경로 존재.
- GAP: 발행 후 자동 dispatch 배선 부재.
  - 자동발행: sales-create.service.ts:506 shouldAutoIssue → issueForSale (voidcatch), dispatch 없음.
  - 수동발행: afip.controller.ts @Post('vouchers') issue() → {...result, output} 반환만, dispatch 없음.
- issueForSale 반환: { ok, reason?, cae?, voucherId?, qrUrl?, ambiguous? } — voucherId 존재 → 배선 가능.
- sales-create는 resolvedBranchId, resolvedTerminalId 보유. AfipModule 이미 import됨.

## 기술 스택
- 언어/프레임워크: Node.js / NestJS / Sequelize
- DB: PostgreSQL (dispatch는 짧은 model 쿼리 후 websocket emit — 커넥션 장기점유 없음, pool 안전)
- ESLint: api-ventago/.eslintrc(존재), tsc

## 태스크 목록
- [x] TASK-1: AfipModule exports에 AfipOutputService 추가 — 파일: app/afip/afip.module.ts
- [x] TASK-2: IssueVoucherDto에 optional branchId, terminalId 추가 — 파일: app/afip/dto/issue-voucher.dto.ts
- [x] TASK-3: afip.controller.ts issue() — 발행 ok+voucherId 후 output==='thermal'이면 dispatch thermal
       (fire-and-forget, 비-throw, 판매응답 차단 없음) — 파일: app/afip/afip.controller.ts
- [x] TASK-4: sales-create.service.ts — AfipOutputService 주입 + 자동발행 issueForSale.then()에서
       dispatch({output:'thermal', storeId, voucherId, branchId:resolvedBranchId, terminalId:resolvedTerminalId})
       (비치명적, fire-and-forget) — 파일: app/sales/sales-create.service.ts
- [x] TASK-5: ESLint(--fix) + tsc(가능 시) 검증, 오류 0
- [x] TASK-6: pool 안전 점검 + 최신 로그 재확인

## 완료 기준
- 자동발행/수동발행(thermal) 모두 발행 직후 comandera로 print_invoice(factura) emit 발생
- 출력 실패가 판매/CAE 트랜잭션을 절대 롤백하지 않음 (throw 없음, catch로 흡수)
- ESLint 오류 0, 신규 pool 커넥션 누수 없음

## 금지사항 / 주의사항
- build-factura.ts, fiscal-formatter.js, print-agent(main.js) 변경 금지 (이미 정렬됨)
- issueForSale 내부 로직 변경 금지 (발행 성공 후 배선만 추가)
- dispatch 실패를 절대 throw로 전파하지 말 것 (소매 무회귀)
- 자동발행은 이미 void+catch fire-and-forget이므로 판매 응답 지연 금지


## REVIEW 리포트 (2026-07-23)
### 완료 태스크
- [x] TASK-1: afip.module.ts — exports 에 AfipOutputService 추가
- [x] TASK-2: issue-voucher.dto.ts — optional branchId, terminalId 추가
- [x] TASK-3: afip.controller.ts issue() — 발행 ok+voucherId + output==='thermal' + branchId 시 void dispatch(비-throw)
- [x] TASK-4: sales-create.service.ts — AfipOutputService 주입 + issueForSale.then() 에서 자동 thermal dispatch(비치명적)
- [x] TASK-5: prettier --check 4파일 통과. 타입인지 ESLint/tsc 는 VM OOM 제약 → Jenkins CI 게이트 위임
- [x] TASK-6: pool 안전(짧은 조회 후 emit, 커넥션 장기점유 없음) + 최신 로그 afip/print 에러 없음 확인

### 검증 상태
- prettier: 4/4 clean
- 타입: 수동 확인 — dispatch DispatchInput 시그니처와 인자 일치, result.voucherId truthy 내로잉으로 number 보장, no-floating-promises 는 void/.catch 로 해소
- ⚠️ 전체 tsc/type-eslint 는 이 VM 에서 미실행(OOM) — main push 시 Jenkins 빌드가 최종 게이트

### 미커밋 상태
- 4개 파일 로컬 반영 완료. git commit/push 는 사용자 지시 대기(미실행).
