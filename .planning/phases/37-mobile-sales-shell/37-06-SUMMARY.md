---
phase: 37-mobile-sales-shell
plan: 06
subsystem: api
tags: [attendance, fichaje, qr, hmac, nestjs, sequelize, guards, multitenant, timezone]

# Dependency graph
requires:
  - phase: 37-01
    provides: mobile_sessions + MobileSessionGuard + PIN 로그인 인프라
  - phase: 37-02
    provides: MobileScopeGuard(req.scope) + /mobile/catalog·stock·sales 컨트롤러
provides:
  - "seller_attendance + reseller_store_qr_auth 2 격리 테이블 (기존 테이블 ALTER 전무)"
  - "AttendanceService: 데스크톱 게이트 일일 HMAC QR + role 라우팅 punch(vendedor 출퇴근 토글 / revendedor 매장권) + report + adjust + revoke"
  - "RequireAttendanceGuard: /mobile/catalog·stock·sales 에 vendedor 출근 게이트(NOT_CLOCKED_IN)"
  - "RequireStoreAuthGuard: revendedor 매장권 skeleton(Phase 24 활성 대기, 라이브 라우트 미부착)"
  - "caja-cierre 강제종료 훅: closeCashRegister 가 지점 열린 세션 강제 salida(단일 tx)"
  - "GET /mobile/me 에 clockedIn + openSince (앱 홈 게이트 즉시 판정)"
affects: [phase-24-reseller-marketplace, mobile-sales-app, ventago-app-reportes-asistencia]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "일일 공용 HMAC QR 토큰(nonce 테이블 없음, 종일 유효 + date freshness + store 소유권 강제)"
    - "단일 QR role 라우팅(vendedor↔revendedor 를 req.scope.mode 로 분기)"
    - "MobileModule ↔ AttendanceModule forwardRef 순환(guard/service 교차 소비)"
    - "caja 마감 훅 = 신규 테이블 raw model update로 AttendanceModule import 없이 순환 회피 + NO-OP 무회귀"

key-files:
  created:
    - "api-ventago/migrations/37-06-seller-attendance.sql"
    - "api-ventago/src/app/attendance/attendance.service.ts"
    - "api-ventago/src/app/attendance/attendance.controller.ts"
    - "api-ventago/src/app/attendance/attendance.module.ts"
    - "api-ventago/src/app/attendance/attendance-qr.util.ts"
    - "api-ventago/src/app/attendance/attendance-time.util.ts"
    - "api-ventago/src/app/attendance/models/seller-attendance.model.ts"
    - "api-ventago/src/app/attendance/models/reseller-store-qr-auth.model.ts"
    - "api-ventago/src/app/attendance/guards/require-attendance.guard.ts"
    - "api-ventago/src/app/attendance/guards/require-store-auth.guard.ts"
    - "api-ventago/src/app/attendance/dto/punch.dto.ts"
    - "api-ventago/src/app/attendance/dto/adjust-attendance.dto.ts"
    - "api-ventago/src/app/attendance/attendance.service.spec.ts"
    - "api-ventago/src/app/attendance/guards/require-attendance.guard.spec.ts"
  modified:
    - "api-ventago/src/app.module.ts"
    - "api-ventago/src/app/mobile/mobile.module.ts"
    - "api-ventago/src/app/mobile/catalog/mobile-catalog.controller.ts"
    - "api-ventago/src/app/mobile/sales/mobile-sales.controller.ts"
    - "api-ventago/src/app/mobile/auth/mobile-auth.service.ts"
    - "api-ventago/src/app/mobile/auth/mobile-auth.service.spec.ts"
    - "api-ventago/src/app/cashRegister/cashRegister.service.ts"
    - "api-ventago/src/app/cashRegister/cashRegister.module.ts"

key-decisions:
  - "seller_attendance.check_out_at 은 timestamptz — caja 마감 시 closing_time(HH:mm:ss)이 아니라 매장TZ date+time+offset 로 완전한 순간을 구성해 저장"
  - "reseller_tienda_link(Phase 24) 조회는 raw SQL + try/catch — 테이블 부재 시 500 아닌 RESELLER_NOT_APPROVED 403 으로 안전 강등"
  - "RequireStoreAuthGuard 는 37-06 에서 어떤 라이브 라우트에도 미부착(export 만) — revendedor 카탈로그와 함께 Phase 24 활성"
  - "MobileModule ↔ AttendanceModule 은 forwardRef 양방향 순환(punch=MobileScopeGuard, catalog/sales/getMe=RequireAttendanceGuard/AttendanceService)"
  - "caja-cierre 훅은 SellerAttendance raw update(정적 모델) — AttendanceModule import 회피로 순환 없음"

patterns-established:
  - "일일 HMAC QR: base64url(HMAC_SHA256(ATTENDANCE_QR_SECRET, storeId:branchId:date)) + timing-safe verify + fail-closed(secret 미설정 throw)"
  - "출근 게이트: MobileScopeGuard 뒤 RequireAttendanceGuard(vendedor 만, revendedor bypass)"

requirements-completed: [ATTEND-01, ATTEND-02, ATTEND-03, ATTEND-04, ATTEND-05, ATTEND-07, ATTEND-08]

# Metrics
duration: 22min
completed: 2026-07-11
---

# Phase 37 Plan 06: QR 출퇴근 통제 (Fichaje / Asistencia) Summary

**데스크톱 전용 일일 HMAC QR 을 모바일이 스캔하면 role 로 갈리는 출퇴근 통제 백엔드 — vendedor 출퇴근 세션 토글(60s 멱등·크로스지점) + revendedor 매장 판매권(Phase24 승인 게이트), /mobile/* 출근 게이트, caja 마감 강제종료, 관리자 리포트/보정/취소. 2개 격리 테이블, 소매/식당 무회귀.**

## Performance

- **Duration:** 22 min
- **Started:** 2026-07-11T13:35:12Z
- **Completed:** 2026-07-11T13:58:10Z
- **Tasks:** 4
- **Files modified:** 22 (14 created + 8 modified)

## Accomplishments
- 2개 신규 격리 테이블(`seller_attendance` 부분 UNIQUE 열린세션 + `reseller_store_qr_auth`) — 기존 테이블 ALTER 전무 → 소매/식당 무회귀(criterion 8)
- 일일 공용 HMAC QR: 데스크톱(Windows/macOS) UA + active_sessions 게이트로 생성, date freshness + store 소유권 강제, 위조/어제 QR 거부
- 단일 QR role 라우팅 punch: vendedor 출퇴근 자동토글(entrada/salida, 60s 더블탭 멱등, 크로스지점 허용, 타매장 QR 403) / revendedor 매장권 영구 등록(Phase24 승인 필수)
- `RequireAttendanceGuard` 를 `/mobile/catalog`·`/mobile/stock/:id`·`/mobile/sales` 에 부착 → vendedor 출근 전·퇴근 후·caja 마감 후 전면 차단(NOT_CLOCKED_IN)
- caja 마감 훅: 지점 열린 세션 강제 salida(단일 tx, 완전 timestamptz, source=caja_cierre), 열린세션 0 → NO-OP
- 관리자 월 리포트(MemoryCache 30s, 마감세션 근무초 합산 + 열린세션 수) + 수동보정(audit adjusted_by, IDOR) + 매장권 취소(IDOR)
- `GET /mobile/me` 에 clockedIn/openSince 추가 → 앱이 홈 게이트 즉시 판정

## Task Commits

각 태스크 원자 커밋:

1. **Task 1: 마이그레이션(2 격리 테이블)+2 모델+HMAC/store-TZ util** - `efb127d` (feat)
2. **Task 2: AttendanceService + DTO + spec (TDD)** - `3e5f249` (feat, 25 jest)
3. **Task 3: Controller + 2 가드 + /mobile/* 출근게이트 + 모듈 등록 (TDD)** - `ade706f` (feat, 3 jest)
4. **Task 4: caja-cierre 강제종료 훅 + /mobile/me clockedIn** - `7aa9770` (feat)

_(TDD 태스크는 시간 제약상 spec+impl 을 단일 커밋으로 통합 — RED→GREEN 순서로 작성하되 원자 커밋)_

## Files Created/Modified
- `migrations/37-06-seller-attendance.sql` — 2 테이블 + 부분/유니크 인덱스 + owner DO 블록
- `attendance/attendance.service.ts` — QR 생성/punch/report/adjust/revoke/getSellerAttendanceStatus
- `attendance/attendance.controller.ts` — GET /qr · POST /punch · GET /report · PATCH /:id · DELETE /reseller-auth/:id
- `attendance/attendance-qr.util.ts` — HMAC buildToken/verifyToken (fail-closed)
- `attendance/attendance-time.util.ts` — 매장 TZ storeNowParts/nextMidnightISO (Intl)
- `attendance/models/*.model.ts` — SellerAttendance + ResellerStoreQrAuth
- `attendance/guards/require-attendance.guard.ts` — vendedor 출근 게이트
- `attendance/guards/require-store-auth.guard.ts` — revendedor 매장권 skeleton(미부착)
- `cashRegister/cashRegister.service.ts` — closeCashRegister 강제종료 훅 + composeStoreTimestamp/tzOffsetMs
- `mobile/auth/mobile-auth.service.ts` — getMe clockedIn/openSince
- `mobile/{catalog,sales} controller` — RequireAttendanceGuard 부착
- `app.module.ts` / `mobile.module.ts` / `cashRegister.module.ts` — 모듈 등록/forFeature/forwardRef

## Decisions Made
- QR 보안: 일일 공용 HMAC(nonce 테이블 없음) — 모니터 상시 노출 요구사항 + date freshness 로 위조 방어
- caja-cierre 훅은 raw `SellerAttendance.update`(정적 모델) — AttendanceModule import 회피로 순환 없음, 열린세션 0 시 NO-OP
- reseller_tienda_link 부재 시 안전 강등(403) — Phase 24 미배포 상태에서도 500 없이 동작

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] MobileAuthService 생성자 arity 변경 → 기존 spec 보강**
- **Found during:** Task 4 (getMe clockedIn)
- **Issue:** getMe 가 AttendanceService 를 필요로 해 생성자 인자 5→6 개로 증가 → 기존 `mobile-auth.service.spec.ts` 의 `new MobileAuthService(...5 args)` 가 TS2554 로 컴파일 실패
- **Fix:** spec 에 6번째 인자로 mock AttendanceService(getSellerAttendanceStatus) 추가 + 변수 선언
- **Files modified:** src/app/mobile/auth/mobile-auth.service.spec.ts
- **Verification:** mobile-auth.service.spec 12/12 green, tsc 무신규 에러
- **Committed in:** 7aa9770 (Task 4 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** 생성자 확장에 따른 기존 테스트 유지용 필수 보강. scope creep 없음.

## Issues Encountered
- 없음. 백엔드 `cashRegister.service.ts` 는 파일 자체에 pre-existing `no-unsafe-*` eslint 34건(heavy `any`) 이 baseline 으로 존재 — 내 변경은 net-zero(추가 0). 백엔드 eslint 는 빌드 게이트 아님(NestJS/SWC). tsc 는 mp-webhook spec 2건 pre-existing(Phase 42 deferred baseline) 외 신규 0.

## Known Stubs
- `RequireStoreAuthGuard` — 의도된 skeleton. 37-06 에서 어떤 라이브 라우트에도 미부착(export 만). revendedor 카탈로그/견적/주문 엔드포인트(Phase 24 wave)와 함께 활성. 스펙 L169 명시.
- caja 2차 자동마감 지점 `cashRegister.service.ts` 의 `autoCloseAndReopen`(closingTime='23:59:59') 은 이번 훅 미적용 — 후속 후보(플랜 Task 4 지시대로 미배선).

## User Setup Required
**신규 환경변수 필수.** `ATTENDANCE_QR_SECRET` 미설정 시 QR 생성/검증이 throw(fail-closed).
- `ATTENDANCE_QR_SECRET` = 32+ 바이트 랜덤 hex/base64. `api-ventago/.env`(로컬) + 운영 배포 env 양쪽에 추가. JWT secret 과 분리(유출 시 로그인 토큰 위조 방지).
- 예: `openssl rand -hex 32` 결과를 `ATTENDANCE_QR_SECRET=...` 로 설정.

## DB 마이그레이션 (사용자 실행 필요)
`api-ventago/migrations/37-06-seller-attendance.sql` — 샌드박스는 로컬 DB 미도달로 미적용. 양쪽 수동 적용:
- **로컬 5432 (Mac):** `psql -p 5432 -d ventago -f api-ventago/migrations/37-06-seller-attendance.sql`
- **운영 5434 (SSH, 확인 후):** `sudo -u postgres psql -p 5434 -d ventago -v ON_ERROR_STOP=1 --single-transaction -f 37-06-seller-attendance.sql`
- 적용 후 양쪽 스키마 대조 + `./.planning/intel/db-schema.regen.sh` 재생성. owner DO 블록으로 coolsistema owner(테이블+시퀀스) 자동 이전(로컬은 role 부재 시 skip).

## Next Phase Readiness
- vendedor 출퇴근이 실동작 부분 — 마이그레이션 + ATTENDANCE_QR_SECRET 설정 후 dev 부팅(DI forwardRef 그래프)·브라우저/실기기 UAT 필요(샌드박스 DB 미도달로 런타임 부팅 미검증).
- 프론트(ventago-app Ctrl+V QR 오버레이 + /reportes/asistencia)와 mobile-sales-app fichaje feature 는 후속 wave.
- revendedor 매장권(RequireStoreAuthGuard 부착)은 Phase 24 활성.

## Self-Check: PASSED
- 14 created files 전부 디스크 확인(FOUND)
- 4 task 커밋 전부 git log 확인(efb127d, 3e5f249, ade706f, 7aa9770)
- attendance dir eslint exit 0 · attendance+guard spec 28/28 green · migration 0 ALTER on existing

---
*Phase: 37-mobile-sales-shell*
*Completed: 2026-07-11*
