# SPEC: producto nuevo ZPL 출력 "branchId requerido" 디버깅
생성일: 2026-07-08

## 목표
producto nuevo(Historial del día) 화면에서 "Imprimir x ZPL" 클릭 시 발생하는 `branchId requerido` 오류의 원인을 로그로 즉시 식별 가능하게 하고, branchId 전달 누락을 수정한다.

## 배경 및 컨텍스트
- 프론트 `ventago-app/src/views/products/list/components/ProductsList.tsx` 의 `handlePrintZpl` 이 `/print/barcode` 로 `branchId: undefined` 를 고정 전송.
- 백엔드 `api-ventago/src/app/print/print.controller.ts` `printBarcode` 는 `body.branchId || req.user.branchId || req.user.sucursalId || 0` 순으로 해석 → 로그인 유저의 `users.branch_id` 가 NULL 인 계정(매장 오너/관리자 등)에서는 0 → `branchId requerido` 반환.
- `/print/temp` 에는 이미 수신 디버그 로그가 있으나 `/print/barcode` 에는 없어 원인 추적 불가였음.

## 기술 스택
- 언어/프레임워크: Next.js 13 + React 18 (프론트), NestJS 11 (백엔드)
- DB: 변경 없음 (pool 영향 없음 — 신규 쿼리/커넥션 없음)
- ESLint: ventago-app (Warning 도 빌드 차단 — newline-before-return, lines-around-comment 준수)

## 태스크 목록
- [x] TASK-1: 프론트 `handlePrintZpl` — `[ZPL-DEBUG]` 요청/응답/예외 로그 3종 추가 — 파일: ProductsList.tsx
- [x] TASK-2: 프론트 — `BranchContext.selectedBranchId ?? user.branchId` 를 `body.branchId` 로 전송 (수정) — 파일: ProductsList.tsx
- [x] TASK-3: 백엔드 `printBarcode` — 수신/거부/emit 로그 3종 추가 (`/print/temp` 패턴 동일) — 파일: print.controller.ts
- [ ] TASK-4: ESLint 검증 (Mac 로컬에서 실행 필요 시)

## 완료 기준
- 재현 시 브라우저 콘솔 `[ZPL-DEBUG]` 와 api 로그 `[POST /print/barcode]` 로 branchId 소스가 어디서 비는지 즉시 확인 가능
- 지점 선택된 상태에서는 오류 없이 Zebra 로 전송

## 금지사항 / 주의사항
- `/print/barcode` 응답 스키마(ok/error/branchId) 변경 금지 — zebra-agent 하위 호환
- pool 관련 변경 없음 (신규 DB 쿼리 없음)

## 남은 확인 포인트
- 오류가 계속되면 콘솔 로그에서 `selectedBranchId` / `userBranchId` 둘 다 null 인지 확인 → 유저 계정에 지점 배정 또는 지점 선택 UI 노출 필요
- zebra 에이전트 오프라인 케이스는 별도 (`emitPrintBarcode` 는 fire-and-forget broadcast)
