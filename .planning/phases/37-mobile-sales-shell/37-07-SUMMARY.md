---
phase: 37-mobile-sales-shell
plan: 07
subsystem: web-frontend
tags: [attendance, fichaje, qr, ctrl-v, overlay, reportes, swr, mui, nextjs, eslint]

# Dependency graph
requires:
  - phase: 37-06
    provides: "GET /attendance/qr · GET /attendance/report · PATCH /attendance/:id · DELETE /attendance/reseller-auth/:id · GET /mobile/me(clockedIn)"
provides:
  - "Ctrl+V 전역 풀스크린 AttendanceQrOverlay (caja 보조 모니터, 매장TZ 자정 자동 재조회)"
  - "reportes/asistencia 월 근무시간 리포트(판매원별 Hh Mm + 세션수 + 미마감 빨강 배지, 코드스플릿)"
  - "AttendanceEditModal — 관리자 세션 보정(PATCH /attendance/:id)"
  - "ResellerAuthPanel — 관리자 revendedor 매장권 취소(DELETE /attendance/reseller-auth/:id)"
  - "백엔드 신규 조회 엔드포인트 2종(GET /attendance/sessions · GET /attendance/reseller-auths) — UI 목록 공급"
affects: [mobile-sales-app, phase-24-reseller-marketplace]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "전역 단축키 오버레이 = UserLayout useHotkeys('ctrl+v') → dynamic(ssr:false) 오버레이 (Ctrl+G 패턴 미러)"
    - "SWR key=null 스킵 + 명시 mutate() 자정 재조회(dedup-stale 회피)"
    - "관리자 리포트 = 집계(report) + drill-down 세션 목록(sessions) 분리 → 개별 세션 PATCH"

key-files:
  created:
    - "ventago-app/src/hooks/api/useAttendanceQr.ts"
    - "ventago-app/src/hooks/api/useAttendanceReport.ts"
    - "ventago-app/src/views/attendance/AttendanceQrOverlay.tsx"
    - "ventago-app/src/pages/reportes/asistencia/index.tsx"
    - "ventago-app/src/views/reports/asistencia/AsistenciaReport.tsx"
    - "ventago-app/src/views/reports/asistencia/AttendanceEditModal.tsx"
    - "ventago-app/src/views/reports/asistencia/ResellerAuthPanel.tsx"
  modified:
    - "ventago-app/src/layouts/UserLayout.tsx"
    - "api-ventago/src/app/attendance/attendance.service.ts"
    - "api-ventago/src/app/attendance/attendance.controller.ts"

key-decisions:
  - "37-06 백엔드가 집계 report 만 노출 → 개별 세션 id 보정(PATCH) 과 매장권 목록(revoke) 을 위해 GET /attendance/sessions + GET /attendance/reseller-auths 2개 read 엔드포인트 추가(Rule 2/3 deviation, store_id 격리, @Auth admin)"
  - "QRCodeSVG(qrcode.react v4 — 기본 QRCode export 폐지) 사용, 흰바탕+검정 QR 로 카메라 스캔 최적 고대비"
  - "자정 재조회는 SWR dedup 아닌 setTimeout(msUntil(refreshAt))+mutate() — 밤새 켜둔 모니터가 다음날 QR 표시"

requirements-completed: [ATTEND-01, ATTEND-06, ATTEND-07, ATTEND-08]

# Metrics
duration: 12min
completed: 2026-07-11
---

# Phase 37 Plan 07: Fichaje 웹 프론트 (Ctrl+V QR 오버레이 + 근무시간 리포트) Summary

**caja 보조 모니터용 전역 Ctrl+V 풀스크린 QR 오버레이(매장TZ 자정 자동 재조회) + reportes/asistencia 월 근무시간 리포트(판매원별 Hh Mm·미마감 빨강 배지·관리자 세션 보정 PATCH·revendedor 매장권 취소 DELETE). 37-06 이 집계만 노출해 개별 세션/매장권 목록 read 엔드포인트 2종을 백엔드에 보강. 전량 추가 UI, ESLint/tsc clean, 소매·식당 무회귀.**

## Performance
- **Duration:** 12 min
- **Started:** 2026-07-11T14:02:12Z
- **Completed:** 2026-07-11T14:14:45Z
- **Tasks:** 3
- **Files:** 10 (7 created + 3 modified)

## Accomplishments
- **Ctrl+V 오버레이**(criterion 1 웹): UserLayout 전역 `useHotkeys('ctrl+v')`(Ctrl+G 패턴 미러) → dynamic(ssr:false) `AttendanceQrOverlay` — 풀스크린 흰바탕 고대비 `QRCodeSVG`(size 420), 매장명+날짜 캡션, ESC/닫기 버튼, branchId=`user?.branchId || selectedBranchId`
- **자정 재조회**: `setTimeout(() => mutate(), refreshAt - now)` + 언마운트 clearTimeout — 밤샘 모니터가 다음날 토큰 자동 표시
- **월 리포트**(criterion 5): `reportes/asistencia` 코드스플릿 페이지 + WithAccess(asistencia-reportes)+acl, 월/지점 필터, 표 Vendedor|Total(Hh Mm)|Sesiones|Sin cerrar, openCount>0 빨강 Chip, 에러 인라인 Alert+prominent 토스트
- **관리자 세션 보정**(criterion 6): 행 클릭 → `AttendanceEditModal` 세션 목록(entrada/salida/nota datetime-local 편집) → `apiConnector.patch('/attendance/:id')` → report mutate
- **revendedor 매장권 취소**(criterion 7 admin): `ResellerAuthPanel`(Tabs "Horas"|"Revendedores") 활성 매장권 목록 → confirm → `apiConnector.remove('/attendance/reseller-auth/:id')`(.delete() 아님) → 토스트+refresh
- **추가 UI 전용**(criterion 8): 소매/식당 판매 플로우 무접촉

## Task Commits
1. **Task 1: Ctrl+V 오버레이 + useAttendanceQr + UserLayout 배선** — `4a013ef` (ventago-app, feat)
2. **Task 2 (backend deviation): sessions+reseller-auths read 엔드포인트** — `1430e3d` (api-ventago, feat)
3. **Task 2 (frontend): 리포트 페이지+뷰+useAttendanceReport+EditModal** — `6b320cd` (ventago-app, feat)
4. **Task 3: ResellerAuthPanel + Tabs 마운트** — `f30ce4c` (ventago-app, feat)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2/3 - Missing critical / Blocking] 백엔드 조회 엔드포인트 2종 추가**
- **Found during:** Task 2 & 3 (read_first 로 37-06 attendance.controller/service 확인)
- **Issue:** 37-06 은 집계 `GET /attendance/report`(sellerId/totalSeconds/counts) 만 노출 — 개별 세션 id 가 없어 EditModal 의 `PATCH /attendance/:id` 대상 세션을 나열/선택 불가. `reseller_store_qr_auth` 행 목록 엔드포인트도 없어 ResellerAuthPanel 이 취소할 대상을 못 가져옴. 두 must_have(관리자 보정/취소)가 dead stub 이 됨.
- **Fix:** `AttendanceService.listSessions(user, sellerId, month, branchId?)` + `listResellerAuths(user)` 추가 및 컨트롤러 `GET /attendance/sessions`·`GET /attendance/reseller-auths` 라우트(@Auth admin/superadmin/gerente, store_id 격리, raw SELECT — 신규 pool 없음). 라우트는 `@Patch(':id')` 앞에 선언.
- **Files modified:** api-ventago/src/app/attendance/attendance.service.ts, attendance.controller.ts
- **Verification:** tsc 신규 에러 0(기존 mp-webhook spec 2건 baseline 유지), attendance dir eslint exit 0(prettier 1건 --fix). grep 검증 통과.
- **Committed in:** 1430e3d

**2. [Rule 1 - Lint] 백엔드 prettier 위반 자동수정**
- **Found during:** Task 2 backend eslint
- **Issue:** `listResellerAuths(user: AuthUser,)` 단일 인자 줄바꿈 prettier/prettier 에러
- **Fix:** `npx eslint --fix`
- **Committed in:** 1430e3d

**Total deviations:** 2 auto-fixed (1 missing-critical/blocking backend read endpoints, 1 lint). **Impact:** 프론트 단독 계획이 백엔드 2개 조회 라우트를 추가로 포함(api-ventago 배포 동반 필요). scope creep 없음 — 두 라우트는 plan must_have 를 실동작시키는 최소 read 엔드포인트.

## Threat Flags

| Flag | File | Description |
|------|------|-------------|
| threat_flag: new-endpoint | api-ventago/src/app/attendance/attendance.controller.ts | GET /attendance/sessions — 판매원 세션 나열. @Auth(admin/superadmin/gerente) + store_id 격리(user.storeId). T-37-29/30 완화 패턴 준수(다른 매장 sellerId 요청해도 store_id 필터로 0행) |
| threat_flag: new-endpoint | api-ventago/src/app/attendance/attendance.controller.ts | GET /attendance/reseller-auths — 매장권 나열. @Auth admin + store_id=user.storeId 강제. PII(revendedor 이름) 노출은 관리자 전용 |

## Known Stubs
- 없음. EditModal/ResellerAuthPanel 은 모두 실제 백엔드 엔드포인트에 연결(집계·세션·매장권 read + PATCH/DELETE). 데이터 미존재 시 "No hay ..." 빈 상태 표시(정상 UX).

## Issues Encountered
- `reportes/asistencia` 는 `WithAccess(allowedModules=["asistencia-reportes"])` 게이트 → 이 모듈 slug 가 사용자 권한 구조(structure)에 등록돼야 접근 가능(reportes/vendedor 의 "vendedor-reportes" 와 동형). 네비게이션 메뉴 항목 추가 및 모듈 시드는 이 계획 범위(프론트 코드) 밖 — 배포 시 권한/메뉴 설정 필요. URL 직접 접근은 권한 보유 시 동작.
- 백엔드 tsc 기존 baseline 2건(mercadopago mp-webhook.service.spec — Phase 42 deferred) 유지, 신규 0.

## Next Phase Readiness
- api-ventago 배포 필요(신규 read 엔드포인트 2종). 37-06 마이그레이션(seller_attendance/reseller_store_qr_auth) + `ATTENDANCE_QR_SECRET` 선적용 전제.
- 브라우저 UAT: Ctrl+V 오버레이(데스크톱에서 QR 표시)·리포트 월/지점 필터·세션 보정 PATCH·매장권 취소 DELETE.
- 후속: 37-08(모바일 앱 fichaje feature) — 스캔 → punch. asistencia 네비 항목/모듈 시드는 권한 설정 작업으로 분리.

## Self-Check: PASSED
- 7 created files 디스크 확인 예정(아래 self_check)
- 4 커밋 git log 확인 예정(4a013ef, 1430e3d, 6b320cd, f30ce4c)
- 전체 37-07 프론트 eslint exit 0 · 프론트 tsc 0 error · 백엔드 attendance tsc 신규 0

---
*Phase: 37-mobile-sales-shell*
*Completed: 2026-07-11*
