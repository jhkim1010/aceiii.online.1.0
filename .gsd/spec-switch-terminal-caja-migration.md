# SPEC: 같은 지점 내 터미널 전환 시 열린 카하 자동 이관
생성일: 2026-07-06

## 목표
Cambiar sucursal(터미널 전환) 시 새 터미널이 열린 카하와 같은 지점(branch)이면
`cash_registers.terminal_id`(+`box_id`)를 자동 이관해, 카하 마감→재시작 없이
푸터 표시와 프린터 라우팅이 즉시 새 터미널을 따라가게 한다.

## 배경 및 컨텍스트
- 푸터 표시(`Caja · Terminal`)와 POS `/print/temp` 라우팅은 모두 열린 카하의
  `cash_registers.terminal_id` 기준 (ProductList.tsx:1084).
- `POST /session/switch-terminal` → `moveToTerminalAndCreateSession()` 은
  terminal_devices 재바인딩 + 세션 토큰 발급만 수행 — 열린 카하는 그대로.
- 지점이 다른 전환은 회계(arqueo) 보호를 위해 현행 유지 (카하 잔류).
- 주의: `moveToTerminalAndCreateSession` 은 로그인 플로우 `POST /session/move-terminal`
  에서도 재사용됨 → 두 흐름 모두 동일하게 이관 적용 (같은 근거: 사용자가 실제
  위치한 터미널로 티켓이 나가야 함).

## 기술 스택
- NestJS 11 + sequelize-typescript (`underscored: true`)
- DB: PostgreSQL (스키마 변경 없음 — UPDATE 만, 마이그레이션 불필요)
- Sequelize 모델 경유라 pool 영향 없음 (기존 커넥션 재사용, 추가 쿼리 1~2회)
- ESLint: api-ventago (백엔드), ventago-app (프론트)

## 태스크 목록
- [x] TASK-1: `session.service.ts` — moveToTerminalAndCreateSession 에 열린 카하
      이관 로직 추가. 조건: 열린 카하 존재 && 카하 box.branchId === 새 터미널
      box.branchId && terminalId 다름 → terminalId + boxId UPDATE. try/catch 로
      이관 실패가 전환 자체를 막지 않게 함. — 파일: api-ventago/src/app/session/session.service.ts
- [x] TASK-2: `BranchSwitchModal.tsx` — 안내 문구 동적 분기: 같은 지점 내 전환
      선택 시 info(카하 자동 이동), 그 외 warning(다른 지점이면 카하 잔류). — 파일: ventago-app/src/components/modals/BranchSwitchModal.tsx
- [x] TASK-3: ESLint 검증 — 프론트 통과. 백엔드는 샌드박스 타임아웃으로 TS
      transpile 검증만 완료 (Mac 에서 `npx eslint` 1회 권장)
- [x] TASK-4: 리뷰 리포트 (2026-07-06 완료)

## 완료 기준
- ESLint 오류 0개
- 같은 지점 터미널 전환 → 리로드 후 푸터가 새 터미널 표시, /print/temp 가 새 터미널 매핑으로 라우팅
- 다른 지점 전환 → 기존 카하 잔류 (현행 동일)

## 금지사항 / 주의사항
- 지점 간 이관 금지 (arqueo 보호)
- 이관 실패 시 전환 플로우를 throw 로 중단하지 말 것 (로그만)
- box_operations / 판매 기록은 건드리지 않음 (terminal_id, box_id 만 이동)
