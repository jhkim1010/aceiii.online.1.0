# SPEC: superadmin 크로스플랫폼 앱 (Flutter) — 관측+운영+직원 통제

생성일: 2026-07-10 · 상태: **PLAN(준비만, 실행은 phase별 승인 후)** · 방식: Flutter 단일 코드베이스(Android · macOS · Windows) + 기존 NestJS API 재사용

> 대화에서 확정된 결정(2026-07-10):
> - **앱 범위**: 관측+운영 통합(모듈형 대시보드) — 방금 만든 /diagnostics + 매장/구독/사용자 관리 + 알림.
> - **권한 방식**: 역할 프리셋 + 사용자별 오버라이드.
> - **권한 입자**: 기능 모듈 단위(화면/버튼 숨김·비활성).
> - **직원용**: Windows 배포, 권한 제한. 접속현황(휴대폰/Windows 구분) + 하루 활동 타임라인 + 원격 강제 로그아웃 요구.
> 관련: `.gsd/spec-observability-monitoring.md`, 메모리 `project_observability_diagnostics_superadmin.md`.

## 목표

superadmin(사장)과 제한 권한 직원이 **Android/Mac/Windows 네이티브 앱** 하나로 Ventago 운영을 통제한다. 실시간 관측(느린쿼리·pool·outbox), 매장/구독/사용자 관리, **직원 접속현황(온라인·플랫폼 구분)**, **직원 하루 활동 타임라인**, 원격 강제 로그아웃을 제공한다. 권한은 백엔드가 authority, 앱은 숨김/비활성만.

## 배경 및 기존 자산 (재사용)

- **인증**: JWT(`@Auth(...ValidRoles)`) + `x-session-token`(SessionGuard). 프리셋 역할은 `src/app/auth/interfaces/valid-roles.ts`.
- **세션**: `active_sessions`(유저당 UNIQUE 1행 = 로그인 상태, 동시 2기기 불가). 컬럼: `userId·sessionToken·deviceFingerprint·publicIp·userAgent·terminalId·branchId·storeId·lastActivityAt`(+timestamps). `session.guard.ts:44` 가 매 요청마다 `lastActivityAt` 갱신 → 온라인 판별 신호. 강제 로그아웃 = 행 삭제(기존 중복로그인 차단 로직 재사용).
- **감사**: `audit_logs`(userId·action(ENUM)·description·changes JSONB·storeId·entityType·entityId·ipAddress·userAgent·createdAt). 기록은 `@Audit` 데코레이터 **옵트인**(`src/common/interceptors/audit.interceptor.ts`) — 현재 권한변경 위주만 부착됨.
- **관측**: `DiagnosticsModule`(2026-07-10 구축) — `GET /diagnostics/{slow-queries,pool,outbox}` `@Auth(superadmin)`, `slow_query_log` 영속. 앱이 그대로 재사용.
- **업무 레코드**: 직원의 실제 행위는 이미 `sales.user_id`·expenses·credit_payments·box 조작·가격변경에 남음 → 추가 로깅 없이 하루 타임라인 집계 가능.
- **프론트 참조**: 웹 `/admin`(superadmin=manage:all), 나중에 앱과 API 공유.

## 기술 스택

- 앱: **Flutter**(Dart, null-safety) + **Riverpod** 상태관리. dio(HTTP, 인터셉터로 JWT+x-session-token+x-client-platform 주입). 데스크톱(macOS/Windows) + 모바일(Android) 동일 코드, 반응형(데스크톱=사이드바 / 모바일=bottom-nav).
- 백엔드: 기존 NestJS 11 + Sequelize. 신규 마이그레이션은 **로컬(5432)+운영(5434) 동시 적용**(CLAUDE.md 규칙), 신규 테이블 owner→coolsistema DO 블록.
- 배포: Play Store(Android) / `.dmg`(macOS) / `.msi`(Windows) + 자동 업데이트.

---

## ★ 잠복 위험 / 주의 (실행 시 우선 반영)

- **(A) 권한은 백엔드가 authority**: 앱의 사이드바 숨김은 UX 일 뿐. 모든 엔드포인트에 `@Auth` + 모듈 권한 가드 필수. 클라이언트 신뢰 금지.
- **(B) 활동 로깅 볼륨**: 전역 activity 인터셉터 도입 시 매 mutating 요청 INSERT → pool 낭비 위험. **`slow_query_log` 패턴(인메모리 버퍼 → 배치 flush)** 재사용 강제. 무분별 동기 INSERT 금지.
- **(C) 네이티브 UA 모호**: Flutter 앱은 `user-agent` 로 Android/Windows 구별 불안정 → **명시적 `x-client-platform` 헤더** 필요(웹은 UA 파싱 폴백).
- **(D) 소매 회귀 금지**: 세션/인증 공유 경로 수정 시 기존 웹 로그인·POS 회귀 검증 필수.
- **(E) lastActivityAt = 요청활동 기준**: 앱 켜두고 방치 시 오래됨. 순수 소켓 접속 여부까지 원하면 presence 게이트웨이 별도(Phase 옵션).

---

## 태스크 목록 (Phase별, 각 phase 승인 후 실행)

### Phase 0 — 권한 모델 ★ 재설계: **기존 Permissions v2 재사용** (신규 테이블 불필요)

> 실행 중 발견(2026-07-10): Ventago 에 이미 **preset+override+모듈/함수 입자** 권한 시스템 완비.
> `Role`+`RoleFunction`(역할 프리셋), `UserFunction`(allowed 플래그 = 사용자별 오버라이드),
> `Functions`(app→module→function 계층), `StoreApps`(매장별 앱 활성), `getEffectiveFunctions()`(프리셋∪오버라이드 병합) → `/me` 의 `structure` 필터. 웹 `/admin/permisos` 편집기 존재.
> ⇒ `user_capabilities` 신설 **폐기**. 아래로 대체:

- [ ] **TASK-0-1(재): admin 앱 모듈/함수 등록** — 신규 화면(diagnostics·sesiones·tenants·mensajes·actividad)을 기존 `apps/modules/functions` 구조에 seed. 각 모듈에 function(read 등) 추가 → RoleFunction/UserFunction 로 프리셋·오버라이드 자동 동작.
- [ ] **TASK-0-2(재): 역할 프리셋** — 기존 Role(per store) 에 운영자 프리셋(Op.Soporte·Op.Facturación·Monitor) 구성 + RoleFunction 매핑. 직원 = 운영자 store 의 user + role + UserFunction override.
- [ ] **TASK-0-3(재): 가드 재사용** — 기존 function-permission 가드 사용(신규 `@RequireModule` 불필요). 임시로 superadmin-only 는 `@Auth(ValidRoles.superadmin)`.
- [ ] **TASK-0-4: `/me` structure 검증** — 앱이 기존 `structure`(apps.modules.functions) 로 사이드바 구성. capabilities 별도 필드 불필요.
- [ ] **TASK-0-5: 편집 UI** — 기존 `/admin/permisos` 재사용/확장(신규 API 불필요).

### Phase 1 — 직원 접속현황 (플랫폼 구분 + 강제 로그아웃) ✅ 슬라이스 1 구현됨 (2026-07-10)

- [x] **TASK-1-3: `GET /admin-console/sessions`** (superadmin) — active_sessions + users/branches/stores join. 상태 파생(🟢<5분/🟡<30분/⚪), 플랫폼은 **userAgent 파싱**(스키마 변경 0), 지점/IP/로그인시각/마지막활동. `AdminConsoleModule`.
- [x] **TASK-1-4: 강제 로그아웃 `DELETE /admin-console/sessions/:userId`** — active_sessions 행 삭제 → 401.
- [x] **TASK-1-5: 웹 `/admin/sesiones` 패널** — SWR 15초 폴링 + 강제로그아웃 확인 다이얼로그 + nav/i18n. lint/tsc clean.
- [ ] **TASK-1-1/1-2 (후속, Flutter 앱 시점): `active_sessions.device_type` 컬럼 + `x-client-platform` 헤더** — 네이티브 앱 정확 구분용. 지금은 userAgent 파싱으로 충분(웹/모바일 브라우저). 앱 로그인 붙일 때 마이그레이션(로컬+운영) + 헤더 수집 추가.

### Phase 1.5 — 테넌트(고객 매장) 운영 콘솔 + 매장 독촉 메시지

SaaS 운영자(사장) 시점: 각 결제 매장(store=테넌트)의 규모·빌링·오류를 실시간 관측 + 특정 매장 관리자에게 경고/독촉 발송. 대부분 기존 데이터 재사용.

- [ ] **TASK-1.5-1: 테넌트 개요 API** `GET /admin/tenants` (superadmin) — store별 집계: 지점수(branch), 터미널수(terminal via branch), 판매수/매출(sales user→branch→store, 기간필터), 마지막 활동(active_sessions/sales 최신). 즉시 구현(추가 스키마 0).
- [ ] **TASK-1.5-2: 빌링 상태 노출** — `store_billing`(monthlyAmount·status[trial/pending/confirmed/paid/overdue/suspended]·paidAt·기간) join. "지난달 관리비 X, 미납(overdue)/완납" 표시. `overdue`·`suspended` 하이라이트. 추가 스키마 0(기존 store_billing).
- [ ] **TASK-1.5-3: 테넌트 에러 모니터** — 전역 `all-exceptions.filter` 를 tap 해서 5xx(+선택 4xx) 를 `{storeId, path, statusCode, message, at}` 로 **인메모리 버퍼→배치 flush**(slow_query_log 패턴, pool 보호) → `store_error_log` 테이블. `GET /admin/tenants/:storeId/errors` + 개요에 매장별 최근 에러수/최신에러. storeId 는 req.user 에서. 마이그레이션 로컬+운영, owner→coolsistema.
- [ ] **TASK-1.5-4: 매장 메시지 — 영속 + 타겟(단일/복수/전체) 전송**. 신규 `store_notices` 테이블(storeId·level[info/warning/dunning]·title·body·campaignId·createdBy·readAt·createdAt). `campaignId`(UUID) 로 한 번의 발송을 묶음(전체/복수 fan-out 시 매장당 1행). `POST /admin/notices`(superadmin) — body `{ target: 'all' | { storeIds:[...] } | { storeId }, level, title, body }`. 서버가 대상 store 목록 해석 → **매장당 store_notices 1행 INSERT(bulk)** + 전달. 전달: `all`=`emitToAll`, 복수/단일=대상 store room `emitToStore(storeId,...)`(WebsocketService 확장). 미접속 대비 DB 영속(다음 접속 시 미확인 조회). 마이그레이션 로컬+운영, owner→coolsistema.
- [ ] **TASK-1.5-5: 매장 관리자 수신 UI** — store admin 웹/앱에서 미확인 notice 배너/모달 표시(레벨별 색: dunning=red). 읽음 처리 `PATCH /notices/:id/read`. 기존 소매/POS 회귀 없이 레이아웃 상단 배너로.
- [ ] **TASK-1.5-6: 작성/전송 UI(superadmin 앱·웹)** — **대상 선택기**: ⦿ 전체 매장 / ⦿ 복수 선택(체크박스+검색, "미납만"·"suspended만" 필터 프리셋) / ⦿ 단일. 레벨·제목·본문 입력. 빠른 템플릿("관리비 미납 독촉", "점검 예정 공지"). 발송 전 대상 수 확인(예: "12개 매장에 전송"). 발송 이력(campaign별 대상수·읽음률) 표시.
- [ ] **TASK-1.5-7: 캠페인 조회 API** — `GET /admin/notices`(발송 이력, campaign 그룹) + `GET /admin/notices/:campaignId`(대상별 읽음 상태). 대량 발송이라 조회는 페이지네이션.

### Phase 2 — 직원 하루 활동 타임라인

- [ ] **TASK-2-1: 활동 집계 API** `GET /admin/users/:id/activity?date=` (superadmin) — 3소스 union: ① 업무 레코드(sales·expenses·credit_payments·box·가격변경, user_id+date) ② `audit_logs`(편집/삭제/민감작업) ③ 세션 이벤트(로그인/로그아웃 시각). 시간순 타임라인 + 요약(N판매·매출·N지출).
- [ ] **TASK-2-2: `@Audit` 커버리지 확대** — 주요 mutating 엔드포인트(재고·고객·삭제 등)에 데코레이터 부착(서술형 description). **또는** TASK-2-3.
- [ ] **TASK-2-3 (옵션): 전역 activity 인터셉터** — 모든 POST/PUT/PATCH/DELETE 자동기록. **인메모리 버퍼 → 배치 flush(slow_query_log 패턴)** 필수, pool 무점유. 보존기간 prune.
- [ ] **TASK-2-4: 웹 `/admin` 타임라인 뷰** — 직원 선택 + 날짜 + 타임라인.

### Phase 3 — Flutter 앱

- [ ] **TASK-3-1: 프로젝트 스캐폴딩** — Flutter(Android/macOS/Windows 타겟), Riverpod, dio 인터셉터(JWT+x-session-token+x-client-platform), 반응형 셸(데스크톱 사이드바 / 모바일 bottom-nav).
- [ ] **TASK-3-2: 로그인+세션** — 기존 로그인 플로우(디바이스 fingerprint, Branch/Terminal 등록 모달 대응) 이식. deviceFingerprint 네이티브 수집.
- [ ] **TASK-3-3: 권한기반 사이드바** — `/me` capabilities 로 모듈 노출/🔒. 미허가 라우트 접근 차단.
- [ ] **TASK-3-4: 모듈 화면** — Dashboard(KPI 종합) · Diagnóstico(느린쿼리·pool·outbox 재사용) · **Tenants(테넌트 개요+빌링+에러 모니터+독촉 발송)** · 접속현황 · 활동 타임라인 · Tiendas · Suscripciones · Usuarios · Permisos(편집) · Alertas.
- [ ] **TASK-3-5: 알림** — pool waiting/최장쿼리/outbox lag 등 푸시(FCM Android + 데스크톱 로컬 알림).

### Phase 4 — 패키징/배포

- [ ] **TASK-4-1: 빌드/서명** — Android `.aab`(Play Store) / macOS `.dmg`(notarize) / Windows `.msi`. CI(GitHub Actions, 기존 에이전트 빌드 패턴 참조).
- [ ] **TASK-4-2: 자동 업데이트** — 데스크톱 업데이터 + 버전 게이트.

### 공통

- [ ] **ESLint(백엔드 변경) 오류 0** · pool release 누락 0(신규 쿼리 커넥션 미점유 확인).
- [ ] **마이그레이션 로컬(5432)+운영(5434) 동시 적용** + 스키마 대조.

---

## 완료 기준

- superadmin 이 앱(3플랫폼)에서 로그인 → 전체 모듈 접근. 직원은 프리셋+오버라이드대로 제한 모듈만 노출, 미허가 직접 접근 시 백엔드 403.
- 접속현황에서 각 직원 온라인 상태 + **📱/🖥 플랫폼 구분** + 지점/IP/마지막활동 표시. 원격 강제 로그아웃 동작.
- 직원 하루 활동 타임라인이 업무레코드+audit+세션 이벤트로 재구성됨.
- 테넌트 콘솔에서 매장별 지점·터미널·판매수 + 관리비(monthlyAmount·미납/완납) + 실시간 에러가 보임. superadmin 이 특정 매장에 독촉/경고 메시지를 작성·전송 → 매장 관리자 앱/웹에 배너 표시.
- 신규 마이그레이션 양쪽 적용·스키마 일치. 활동·에러 로깅이 pool 낭비 없음(배치 flush).

## 금지사항 / 주의

- **실행 금지(이번은 준비만)**: 각 phase 승인 전 DDL·코드 변경 금지.
- 마이그레이션 한쪽만 적용 금지(로컬↔운영 분기 = 500 사고 전례).
- 권한은 백엔드가 authority — 앱 숨김만 믿지 말 것.
- 활동/세션 로깅은 pool 절약(배치·인메모리) 강제.
- 세션/인증 공유 경로 변경 시 웹·POS 소매 회귀 별도 검증.
