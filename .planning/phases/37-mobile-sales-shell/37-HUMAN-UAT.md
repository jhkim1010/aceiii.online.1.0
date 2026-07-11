---
status: partial
phase: 37-mobile-sales-shell
source: [37-04-PLAN.md, 37-04-SUMMARY.md, 37-08-PLAN.md, 37-08-SUMMARY.md]
started: 2026-07-08
updated: 2026-07-11
tester: miguel@cool (user 19, store 1 "Cool Store", branch 12 "HELGUERA"), PIN 1234
env: local dev — backend PID on :5002 (Phase 37 code live), PG18 ventago
---

## Current Test

- Wave 4: 딥 화면 시각 확인(U1 매트릭스 / U3·U4 2기기 / 오프라인 CTA) — 실기기·에뮬레이터 대기.
- Wave 8 (37-08): Fichaje F1-F8 dev UAT — 3표면(백엔드/POS 웹/Flutter) 통합. 전 항목 pending(실기기 + DB 마이그레이션 + ATTENDANCE_QR_SECRET 선행).

## Tests

### 1. LOGIN 스모크 — 토큰·스코프 발급 (UI-D3)
method: curl POST /mobile/auth/login (miguel@cool/1234)
expected: 201 + accessToken + mobileSessionToken + scope{mode:vendedor, branchIds:[12], storeIds:null}
result: PASS — accessToken(roles:["vendedor"]) + mobileSessionToken(UUID) + scopeBranchIds:[12]. 데스크톱 세션과 독립(D-06).

### 2. U2 스코프 강제 (criterion 4, D-02)
method: GET /mobile/catalog with tokens
expected: 자기 지점(branchId=12) 200 · 외부 지점(branchId=1) 403 SCOPE_VIOLATION · 무토큰 401
result: PASS — 200 / 403 SCOPE_VIOLATION / 401 정확.

### 3. U5 보류판매 생성 (criterion 6, D-13)
method: POST /mobile/sales {product73, variant 19-14 x1, total 18000}
expected: 보류판매 생성, 재고 type:'suspend' -1 예약, 확정 Sale 미생성, Caja/box 무영향
result: PASS — ventas_suspendidas 0→1(id40), stocks type=suspend +1(stock=-1), confirmed sales today 1→1 불변, box_operations 2→2 불변.

### 4. U5b 취소→예약 해제
method: DELETE /suspended-sales/40 (vendedor 토큰)
expected: 200, 예약 해제(+1), 보류행 삭제
result: PASS — ventas_suspendidas 1→0, release +1 행 추가(순 예약 0 복원). dev DB 원복.

### 5. U6 STORE_SUSPENDED (criterion 9 강화 — mid-session)
method: stores.status=suspended 설정 후 로그인/기존토큰 요청, 이후 원복
expected: 로그인 즉시 401 STORE_SUSPENDED(DB fresh) + mid-session 60s 캐시 만료 후 401
result: PASS — TestA 로그인 401 STORE_SUSPENDED, TestB mid-session 401 STORE_SUSPENDED, 원복 후 재로그인 정상.

### 6. P95 지연 (MOBILE-D-01b, CLAUDE.md ≤300ms)
method: scripts/monitor-mobile-pool.sh --latency --n=30 (catalog + stock/73)
expected: /mobile/* P95 ≤ 300ms
result: PASS — catalog p95=19ms, stock p95=21ms (캐시 60s/10s, D-04).

### 7. D-13 불변식 (Caja-neutral)
method: 모바일 전 과정 중 확정 sales/box 델타 추적
expected: 확정 Sale 미생성, box 무영향
result: PASS — sales today 1→1, box 2→2 유지.

### 8. 앱 로그인 셸 + 테마 (criterion 10, UI-D3) — 브라우저 시각
method: flutter run -d web-server :8091, Chrome 렌더 + 실 로그인
expected: Ventago 다크네이비+골드, USUARIO/PIN/SUCURSAL, D-06 카피, dio→백엔드 인증
result: PASS — 로그인 화면 렌더 정확 + miguel 로그인 시 mobile_sessions 신규 행 생성(실 클라이언트→서버 인증 확인).

### 9. U1 매트릭스 시각 렌더 (D-15/UI-D2) — 실기기 필요
expected: color×size 매트릭스, 셀 직접 입력, 자기 지점 굵게 + otras:N 읽기전용, 자기 지점 상한
result: pending — 웹은 flutter_secure_storage(HTTP) 제약으로 로그인 후 리다이렉트 불가. 실기기/에뮬레이터 필요.

### 10. U3/U4 2기기 세션 (criterion 1/12) — 실기기 필요
expected: 데스크톱+모바일 동시 유지 / 2번째 기기 로그인 시 1번째 앱 401 MOBILE_SESSION_EXPIRED 토스트+/login
result: pending — API 레벨 세션 회전은 37-01 Jest에서 검증됨(재로그인 토큰 회전). 앱 토스트/리다이렉트 UX는 실기기 확인.

### 11. 오프라인 CTA 가드 (criterion 11) — 실기기 필요
expected: 오프라인 시 "Mandar a Caja" 비활성 + "Requiere conexión", 카탈로그/재고는 캐시 열람
result: pending — 실기기 연결 토글 필요.

### 12. QR 스캔 (D-14) — Phase 38 대기
expected: percha 라벨 스캔 → 해당 상품 매트릭스
result: pending/blocked — Phase 38(라벨 생성) 미구축. 딥링크 /m/stock?s=1&p=73 수동 입력으로 대체 검증 가능(실기기).

## Fichaje UAT (37-08 Task 3 — blocking checkpoint, PENDING human verification)

> **선행 조건** (아직 미충족 → 실행 전 반드시 세팅):
> 1. `api-ventago/.env` 에 `ATTENDANCE_QR_SECRET` 설정(예: `openssl rand -hex 32`). 미설정 시 QR 생성/검증 throw(fail-closed).
> 2. `api-ventago/migrations/37-06-seller-attendance.sql` 를 로컬 5432 + 운영 5434 양쪽 적용(2 테이블). 미적용 시 punch 500.
> 3. 백엔드 dev(`npm run dev:api`) + POS 웹(`npm run dev:app`) + Flutter 앱(실기기/에뮬레이터, baseUrl :5002) 기동.
> 4. coolsistema vendedor(PIN 설정) 1명 + 가능하면 2지점.
>
> **자동 검증은 이미 green** (37-06 Jest 28 + 37-07 eslint clean + 37-08 flutter test 13 + scoped analyze clean). 아래는 dev 환경 human 통합 UAT.

### F1. Ctrl+V QR 표시 + 모바일 QR 생성 차단 (criterion 1)
method: POS 웹에서 Ctrl+V → 현재 지점 풀스크린 QR. 핸드폰 브라우저로 GET /attendance/qr 요청.
expected: 데스크톱 풀스크린 QR 표시(store+branch+date, 자정 자동 갱신). 핸드폰 → **403 PLATFORM_NOT_ALLOWED**.
result: pending

### F2. vendedor 출퇴근 자동토글 (criterion 2)
method: vendedor 앱에서 F1 QR 스캔(1회), >60초 후 재스캔.
expected: 1회 → "Entrada registrada HH:mm". 재스캔 → "Salida registrada HH:mm · Hoy Xh Ym".
result: pending

### F2b. 출근 게이트 — 스캔 전 작업 차단 (criterion 2b)
method: 출근 전 앱 홈 확인 → 스캔(entrada) → 다시 확인 → 퇴근(salida) → 다시 확인. 직접 GET /mobile/catalog(열린세션 없이).
expected: 출근 전 홈이 Catálogo/스캐너/판매 잠금 + "Fichá tu entrada para empezar" + fichaje 버튼만. entrada 후 작업 해제. salida 후 재잠금. GET /mobile/catalog → **403 NOT_CLOCKED_IN**.
result: pending

### F2c. caja 마감 강제종료 (criterion 2c)
method: 세션 열린 상태에서 관리자가 지점 caja 마감(cierre).
expected: 열린 세션 강제 salida(source='caja_cierre'), 이후 vendedor 완전 불능(홈 재잠금).
result: pending

### F3. 크로스지점 + 타매장 QR (criterion 3)
method: vendedor 가 같은 매장 다른 지점 QR 스캔 / 다른 매장 QR 스캔.
expected: 같은 매장 다른 지점 → 출퇴근 정상(크로스지점). 다른 매장 QR → "QR de otra tienda"(QR_OTHER_STORE).
result: pending

### F4. 어제/위조 QR 거부 (criterion 4)
method: 어제 날짜 QR / 토큰 변조 QR 스캔.
expected: "Pedí el QR de hoy"(QR_EXPIRED) 또는 거부.
result: pending

### F5/F6. reportes/asistencia 리포트 + 관리자 보정 (criteria 5, 6)
method: 웹 reportes/asistencia 에서 vendedor 월 근무시간 + 열린세션 배지 확인. 세션 PATCH 편집.
expected: 판매원별 월 근무시간(Hh Mm) + 미마감 경고 표시. 편집 → 합계 갱신 + adjusted_by 기록.
result: pending

### F7. revendedor 매장권 QR (criterion 7)
method: 미승인 revendedor 가 매장 QR 스캔. Phase 24 승인(reseller_tienda_link) 시드 후 재스캔.
expected: 미승인 → "Tienda no aprobada por admin"(RESELLER_NOT_APPROVED). 승인 시드 후 → "Tienda {name} habilitada" + 카탈로그 개방.
note: Phase 24 부재 시 reseller_tienda_link 행 수동 시드로 승인 경로 검증.
result: pending

### F8. 소매/식당 무회귀 (criterion 8)
method: 출근 세션 없는 일반 데스크톱 판매 + caja 마감 전 과정 수행.
expected: 소매/식당 판매·caja 마감이 이전과 100% 동일(신규 격리 모듈, 기존 테이블 ALTER 0).
result: pending

## Summary

total: 12 (Wave 4) + 8 (Wave 8 Fichaje F1-F8) = 20
passed: 8
issues: 0
pending: 12 (Wave4 4 + Fichaje 8)
skipped: 0
blocked: 0

## Gaps

- Wave 4: pending 4건 — 실기기·에뮬레이터(웹 canvas + 웹 스토리지 제약) 및 Phase 38(QR) 의존. 백엔드 계약 실데이터 100% 검증됨.
- Wave 8 Fichaje: F1-F8 전 항목 pending — 실기기 + `ATTENDANCE_QR_SECRET` + 37-06 마이그레이션(2 테이블) 선행 필요. 자동 검증(Jest/flutter test/analyze)은 3표면 모두 green. dev 통합 UAT 는 사용자 실행 대기.
- 실기기 딥화면 + Fichaje F1-F8 확인 후 `/gsd-verify-work 37`로 종결 권장.
