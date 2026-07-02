# SPEC: 지점(터미널) 전환 기능

생성일: 2026-07-01

## 목표

노트북 한 대(디바이스)로 로그인한 admin·gerente가 로그아웃 없이 사이드바에서 다른 지점의 터미널로 전환하여, 그 지점 기준으로 POS 판매를 할 수 있게 한다.

## 배경 및 컨텍스트

### 현재 구조 (왜 지금은 지점이 고정되는가)

- 디바이스는 `terminal_devices`에 **deviceToken(localStorage) + fingerprint → terminalId + branchId**로 1:1 바인딩.
- 로그인 시 `session.service.ts:79~124`의 knownDevice 경로가 **IP·위치를 무시**하고 저장된 터미널/지점으로 세션 생성.
- 판매는 열린 카하의 `box.branchId`로 기록됨 (`ProductList.tsx`의 `branchId: cashRegister.box.branchId`). 카하는 디바이스의 터미널 위에서만 열림.
- 결과: 노트북 → 터미널 1개 → 지점 1개 고정. B 매장에 물리적으로 가도 A로 기록.

### 이미 존재하는 재사용 자산 (신규 구현 최소화)

- 백엔드 `POST /session/move-terminal` → `moveToTerminalAndCreateSession()` : 디바이스를 기존 터미널로 재바인딩하고 새 sessionToken/deviceToken 발급. **현재 `@Auth()`(모든 인증 사용자) — 권한 제한 필요.**
- 백엔드 `GET /session/registration-context` → `{ isAdmin, branches }`.
- 백엔드 `GET /terminal` (findByStore), `GET /terminal/by-branch/:branchId` : 터미널 목록(박스/지점 포함) 조회.
- 프론트 `SidebarFooter.tsx:174~188` : 현재 지점명 표시 + 지점 선택기 (전환 버튼 배치 위치).
- 프론트 `AuthContext.tsx` : deviceFingerprint 수집(`getDeviceFingerprint`), sessionToken/deviceToken localStorage 저장 로직.
- 프론트 기존 모달 후보: `components/modals/SelectBoxTerminalModal.tsx`, `SelectBranchModal.tsx` (재사용/참고).

### 확정된 제품 결정 (사용자 승인)

1. **전환 권한**: admin·gerente만. vendedor는 배정 지점에 고정.
2. **버튼 위치**: 사이드바 지점 선택기 옆 (`SidebarFooter`).
3. **열린 카하 처리**: 열린 카하가 있어도 **경고만 표시하고 전환 허용**.

## 기술 스택

- 백엔드: NestJS 11 + Sequelize. DB: PostgreSQL (pool min=10/max=80, `database.module.ts`).
- 프론트: Next.js 13 (Pages Router) + MUI 5 + Context(Auth/Branch).
- ESLint: 프로젝트 ESLint (Warning도 빌드 차단). `newline-before-return`, `lines-around-comment` 등 주의.

## 태스크 목록

### 백엔드

- [ ] **TASK-1**: `move-terminal` 권한 제한 — 파일: `api-ventago/src/app/session/session.controller.ts`
  - 기존 `isUserAdmin`을 admin·superadmin·gerente 허용으로 확장(`isUserManagerOrAdmin`) 또는 별도 헬퍼 추가.
  - `moveToTerminal` 핸들러 진입 시 권한 미달이면 `ForbiddenException` (스페인어 메시지). 로그 `[SWITCH_FAIL] reason=FORBIDDEN`.
  - pool: 추가 쿼리는 단일 findOne(기존 `isUserAdmin` 패턴 재사용). 신규 pool 생성 금지.

- [ ] **TASK-2**: 전환용 터미널 목록 엔드포인트 확인/보강 — 파일: `session.controller.ts` (필요 시)
  - 우선 기존 `GET /terminal` 응답에 box+branch가 포함되는지 확인. 포함되면 신규 엔드포인트 불필요.
  - 미포함 시 `GET /session/switch-context` 추가: 지점별 그룹핑된 활성 터미널 목록 반환(store 격리, 단일 쿼리 + include).

### 프론트엔드

- [ ] **TASK-3**: 전환 모달 컴포넌트 — 파일: `ventago-app/src/components/modals/BranchSwitchModal.tsx` (신규 또는 기존 모달 확장)
  - 지점 → 터미널 선택 UI. admin·gerente에게만 노출.
  - 선택 후 `POST /session/move-terminal { terminalId, deviceFingerprint }` 호출.
  - 응답의 sessionToken/deviceToken을 localStorage에 갱신 + `/me` 재조회로 user.branchId/terminal 갱신.
  - 전환 전 열린 카하 확인(`GET /cash-register/open`) → 있으면 경고 토스트/다이얼로그 후 계속 진행 허용.
  - 전환 완료 후 `cashRegisterUpdated`/`saleCreated` 이벤트 또는 라우터 refresh로 POS 상태 리로드. `selectedBranchId`도 새 지점으로 동기화.
  - 에러 핸들링: try/catch + 실패 토스트, 롤백(토큰 미갱신).

- [ ] **TASK-4**: 사이드바 전환 버튼 — 파일: `ventago-app/src/layouts/components/vertical/SidebarFooter.tsx`
  - 현재 지점명 옆에 "지점 전환" 버튼/아이콘 추가. `isAdmin || isGerente`일 때만 렌더.
  - 클릭 시 BranchSwitchModal 오픈. i18n 키 추가(`sidebar_switch_branch`).

- [ ] **TASK-5**: 권한 판별 유틸 — user role slug(admin/superadmin/gerente) 확인 로직을 프론트에서 재사용(기존 useAuth/CASL 패턴 확인 후 최소 추가).

### 검증

- [ ] **TASK-6**: ESLint 검증 — `npx eslint <변경파일> --fix` 오류 0개.
- [ ] **TASK-7**: PostgreSQL pool 점검 — 신규 쿼리 pool 누수 없음(pool.connect 수동 사용 없음, 기존 Sequelize 모델 경유).
- [ ] **TASK-8**: 수동 시나리오 검증 — 로컬 store 6(지점 3개)로 admin 로그인 → 전환 → 새 지점 카하 열기 → 판매 branch_id 확인.

## 완료 기준

- admin·gerente가 사이드바에서 다른 지점 터미널로 전환 → 재로그인 없이 그 지점으로 판매 가능.
- vendedor에게는 전환 버튼이 보이지 않음(백엔드에서도 차단).
- 전환 후 POS의 código/재고/카하가 새 지점 기준으로 표시.
- 열린 카하가 있으면 경고는 뜨되 전환은 진행됨.
- ESLint 오류 0개, pool 누수 없음.

## 금지사항 / 주의사항

- `session.service.ts`의 knownDevice 자동 바인딩 로직 자체는 변경하지 않음(기존 로그인 흐름 보존). 전환은 별도 명시적 액션으로만.
- vendedor 권한 우회 금지 — 백엔드 권한 체크가 1차 방어선(프론트 숨김은 2차).
- deviceToken/sessionToken 갱신 실패 시 이전 세션 유지(부분 전환 상태 방지).
- store 격리: 터미널/지점 조회는 반드시 `storeId` 필터.
- pool: 신규 `new Pool()` 금지, 기존 Sequelize 모델/커넥션만 사용.
- ESLint: `return` 위 빈 줄, 주석 위 빈 줄, 미사용 import 금지.
```
