---
status: partial
phase: 37-mobile-sales-shell
source: [37-04-PLAN.md, 37-04-SUMMARY.md]
started: 2026-07-08
updated: 2026-07-08
tester: miguel@cool (user 19, store 1 "Cool Store", branch 12 "HELGUERA"), PIN 1234
env: local dev — backend PID on :5002 (Phase 37 code live), PG18 ventago
---

## Current Test

딥 화면 시각 확인(U1 매트릭스 / U3·U4 2기기 / 오프라인 CTA) — 실기기·에뮬레이터 대기.

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

## Summary

total: 12
passed: 8
issues: 0
pending: 4
skipped: 0
blocked: 0

## Gaps

없음. 실패 0건. pending 4건은 실기기·에뮬레이터(웹 canvas + 웹 스토리지 제약) 및 Phase 38(QR) 의존이며, 백엔드 계약은 실데이터로 100% 검증됨. 실기기 딥화면 확인 후 `/gsd-verify-work 37`로 종결 권장.
