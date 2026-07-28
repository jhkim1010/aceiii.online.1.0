# SPEC: tienda-admin-app 개선 6건 (Caja 수동입력·터미널 유령세션·이메일 편집·판매 상세·다중 Caja·Tesorería 통합)
생성일: 2026-07-28

## 목표
매장 admin 앱(tienda-admin-app)의 Caja/Usuarios/Actividad 기능 보강 + 웹 Tesorería 구조 개선.
버그 2건은 운영 DB 실측으로 근본 원인 확정 후 수정.

## 진단 결과 (2026-07-28 운영 DB 실측)

### (2) 터미널 삭제/추가 미반영 — 원인: 삭제된 터미널의 유령 open 세션
- store 9(ACE/Stock) 터미널: 활성 = 20 "Terminal SALA", 43 "Jefe Mac"(오늘 생성). 나머지(19,21,27,28,29,41)는 is_deleted=t.
- cash_registers 미마감(closing_time NULL) 세션:
  - **#187** terminal 21 "jefe"(삭제됨) 2026-07-24 개봉 — 앱에 유령 "Abierta"로 계속 표시 ← 미반영의 정체
  - **#184** terminal 20, 2026-07-24 개봉 미마감
  - **#194** terminal 20, 2026-07-27 개봉 미마감 (같은 터미널에 2개 open)
  - #199 terminal 43 오늘 개봉 (정상)
- 앱 로직: `getTodayCajas()` = 오늘 것 + (날짜 무관) open 전부 → 유령 세션이 영구 표시됨.

### (3) admin@stock 이메일 편집 실패 — 유력 원인: 비활성 계정의 이메일 점유
- user 17 admin@stock (email bsas.ubf@gmail.com, role Admin id29 — editar-usuario update 권한 있음 → 403 아님).
- 비활성 계정: 21 marcos@stock=ruthkim0212@gmail.com, 22 mark@stock=marcoskim@gmail.com (둘 다 2026-07-28 01:07 비활성화됨 — 이메일 회수 시도 정황).
- `isUserUnique()`가 status 무관 전역 검사 → 비활성 계정이 가진 이메일로 변경 시
  400 "Ya existe un usuario con ese email".
- 부수 발견: audit 로그 description 이 "ID undefined: undefined undefined" (getDescription 이 req.body 를 못 받음).

### 로그 확인 (로컬 dev)
- api-ventago/logs/error-2026-07-28.log: `[Outbox] column "lease_expires_at" does not exist` 10초 간격 무한 반복
  → Phase 63 sync_outbox 마이그레이션 로컬 미적용. 로컬 5432 적용 SQL 사용자 전달 필요.

### (6) 두 메뉴의 실체
- **Estado de Caja** = `/caja` → BoxResume: 현재 지점의 "지금 열린 카하" 실시간 운영 뷰 (수동 이동 입력 포함)
- **Cajas Registradoras** = `/control-de-caja` → CashRegisterList: 전체 카하 세션 이력/감사 뷰 (필터+상세)
- 성격이 "현재 vs 이력"으로 다름. 단, 메뉴 2개로 나눌 만큼 크지 않음 → reportes/talleres 의
  `directPath` 패턴으로 **Tesorería 클릭 → 부메뉴 없이 탭 통합 뷰** 가능 (menuRegistry 기존 기능 활용).

## 기술 스택
- Flutter (tienda-admin-app, Riverpod) / NestJS (api-ventago) / Next.js (ventago-app)
- DB: PostgreSQL 18 (로컬 5432 / 운영 5434) — 이번 작업 스키마 변경 **없음** (DML 정리만)
- ESLint: api·front 는 프로젝트 규칙(newline-before-return 등), Flutter 는 dart analyze

## 태스크 목록

### Wave A — 버그 수정 (백엔드)
- [ ] TASK-A1: 터미널 삭제 시 열린 cash_register 자동 마감(또는 open 세션 존재 시 삭제 차단+안내)
      — 파일: api-ventago/src/app/terminal/terminal.controller.ts(.service)
      ※ 단일 트랜잭션, 마감 box_operation 기록 없이 closing_time 만 세팅하는 기존 close 로직 재사용
- [ ] TASK-A2: isUserUnique — active 계정만 검사 + 사용자 활성화(activate) 경로에서 이메일 충돌 재검사
      — 파일: api-ventago/src/app/users/users.service.ts
- [ ] TASK-A3: (부수) Usuarios audit getDescription undefined 수정 — users.controller.ts
- [ ] TASK-A4: 운영 DB 유령 세션 정리 DML (사용자 승인 후): #187 마감 (+#184/#194 처리 여부 확인)

### Wave B — tienda-admin-app 기능
- [ ] TASK-B1: Caja 상세에 Retiro/Ingreso/Gasto 수동 입력 시트 (열린 카하만)
      — POST /box-operation/manual {cashRegisterId,userId,terminalId,amount,type,description}
      — 저장 후 resume+movements invalidate. 파일: caja_detail_screen.dart, caja_repository.dart
- [ ] TASK-B2: Caja 목록에서 삭제된 터미널/이전 날짜 유령 세션 구분 표시(경고 배지 + 마감 유도)
      — 백엔드 /cash-register 응답에 terminal.isDeleted 포함 확인. 파일: caja_repository.dart, caja_screen.dart
- [ ] TASK-B3: Actividad 판매 탭 → 판매 상세 화면 (GET /sales/:id — items·pagos·cliente·vendedor)
      — 신규 sale_detail_screen.dart + repository 메서드
- [ ] TASK-B4: dart analyze 통과 + APK 빌드·Dropbox 복사(상시 규칙)

### Wave C — 웹 Tesorería (ventago-app)
- [ ] TASK-C1: Estado de Caja(BoxResume)에 매장 전체 카하 요약 카드(다른 지점/카하 open 상태 한눈에)
      — /cash-register + resume 재사용, SWR, Promise.all, pageSize≤50
- [ ] TASK-C2: Tesorería directPath 통합 뷰 — 탭: Estado | Registros | Cheques
      (menuRegistry virtualGroup 에 directPath 개념 추가 또는 /tesoreria 허브 페이지 + 기존 페이지 URL 유지)
- [ ] TASK-C3: ESLint 검증 (newline-before-return, lines-around-comment, no-unused-vars)

### 마무리
- [ ] TASK-D1: 로컬 5432 sync_outbox lease_expires_at 마이그레이션 SQL 사용자 전달 (Outbox 에러 소거)
- [ ] TASK-D2: 리뷰 리포트 + push(변동 있으면 빌드까지 — 상시 규칙)

## 완료 기준
- dart analyze 0 issues / ESLint 오류 0
- 운영에서: 삭제 터미널 유령 caja 미표시, admin@stock 이메일 변경 성공
- pool 안전: 새 쿼리 전부 기존 서비스 경유(pool.query 패턴), 트랜잭션 내 외부 I/O 없음

## 금지사항 / 주의사항
- stocks·판매 쓰기 경로 무변경. cash_registers 스키마 변경 없음.
- 운영 DML(#187 마감 등)은 SQL+영향 row 수 제시 후 사용자 승인 필수.
- Mac 워킹트리 미커밋 WIP(afip-issuer.service.ts) 건드리지 않기.
