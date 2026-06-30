# SPEC: Phase 52 — Store Manager Mobile App (핸드폰·태블릿)
생성일: 2026-06-29
배경: `52-CONTEXT.md`. 구분: Phase 37(판매자 앱)과 다른 *관리자* 앱.

## 목표

매장 오너·지점장이 핸드폰/태블릿으로 매장을 관제·관리(매출/캐시/재고/승인/온라인주문/알림)하는
Flutter 앱을 만든다. 기존 Flutter 인프라(Dio+Riverpod+secure storage+FCM+JWT)와 `mobile_sessions`,
기존 대시보드/리포트 API 를 최대 재사용하고, 서버에서 role/scope 를 강제한다.

## 비목표 (Non-goals)

- POS 판매 기능(그건 데스크탑 POS + Phase 37 판매 앱)
- 신규 백엔드 도메인 (가능한 기존 API 재사용 + 얇은 `/admin-mobile/*` 만)

## 기술 스택 (예정)

- Flutter (null safety, Riverpod, dart 스타일가이드) — `talleres-vendor-app` 인프라 재사용
- Dio + secure storage + FCM, JWT + `mobile_sessions`
- 백엔드: NestJS 11, role/scope 가드, **pool 낭비 금지**(폴링 주기·캐시)

## 태스크 목록 (Waves)

### Wave 52-00 — 결정 & 디자인 ⬜
- [ ] 별도 앱 vs Phase 37 `manager` 모드 결정 (공유 인프라 패키지 범위)
- [ ] 태블릿(master-detail) + 핸드폰(카드) 반응형 디자인 토큰(다크 네이비+골드)
- [ ] 정보구조(IA): 대시보드 / 재고 / 캐시 / 승인 / 온라인주문 / 알림

### Wave 52-01 — 앱 스캐폴드 + 인증/세션 ⬜
- [ ] Flutter 워크스페이스(또는 모드) 스캐폴드, 라우팅, 테마
- [ ] JWT 로그인 + `mobile_sessions`(데스크탑 active_sessions 와 분리)
- [ ] role/scope 부트스트랩(store_owner=전지점, branch_manager=자지점)
- [ ] 백엔드 `/admin-mobile/*` 가드(서버 스코프 강제, IDOR 차단)

### Wave 52-02 — 대시보드(관제) ⬜
- [ ] 오늘/기간 매출, 캐시 잔액, 지점 비교, 결제수단 분해 — 기존 `dashboards/*`·`reports/*` 재사용
- [ ] 지점 전환(멀티지점), 새로고침 주기/캐시(pool 보호)

### Wave 52-03 — 재고 ⬜
- [ ] 상품/지점 재고 조회 + 검색, 저재고 경보 목록
- [ ] 빠른 재고 조정 + 가격 변경(권한 한정, 감사로그)

### Wave 52-04 — 캐시·승인 워크플로우 ⬜
- [ ] caja/control-de-caja 상태·불일치 경보·마감 확인
- [ ] 환불·할인·비용·가격변경 **승인/반려**(멱등 + 감사로그)

### Wave 52-05 — 온라인 주문/배송 모니터링 ⬜
- [ ] online_orders despacho 보드(Phase 27/42) 읽기 + 상태 알림

### Wave 52-06 — 알림(FCM) ⬜
- [ ] 저재고/대형 환불/캐시 불일치/신규 온라인주문/세션 이상 푸시
- [ ] 푸시 → 딥링크(해당 화면/승인) 

### Wave 52-07 — 태블릿 최적화 ⬜
- [ ] master-detail 레이아웃, 대시보드 그리드, 멀티지점 동시 보기

### Wave 52-08 — 보안 & 검증 ⬜
- [ ] scope IDOR 차단 테스트(지점장 타지점 접근 불가)
- [ ] 데스크탑 POS + 모바일 동시 세션 정상
- [ ] 폴링/캐시로 운영 pool 무영향 확인

## 완료 기준

- 오너/지점장이 모바일에서 매출·캐시·재고를 보고, 승인 워크플로우를 완주
- 서버 스코프 강제로 권한 경계 침범 0
- 알림(FCM) → 딥링크 동작
- 모바일 트래픽이 운영 POS pool 에 영향 없음

## 금지사항 / 주의사항

- 권한 경계는 **서버에서** 강제(클라 신뢰 금지).
- 승인/조정은 돈·재고 상태 변경 → 멱등 + 감사로그 필수.
- 모바일 폴링이 pool 잠식 금지(주기·캐시).
- Phase 37 과 코드 중복 최소(공유 인프라/디자인).
- 주석 한국어, 함수/변수명 영어(프로젝트 규약).
