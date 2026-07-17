# SPEC: Phase 52 — Store Manager Mobile App (포인터)

생성일: 2026-06-29

> 정식 스펙: `.planning/phases/52-manager-mobile-app/52-CONTEXT.md` + `52-SPEC.md`

## 요약

- **무엇**: 매장 *관리자(오너·지점장)* 용 핸드폰·태블릿 Flutter 앱 — 관제/관리.
- **Phase 37 과 구분**: 37 은 *판매자*(vendedor/revendedor) 판매 앱. 52 는 *관리자* 관제·승인 앱.
- **기능**: 대시보드(매출·캐시·지점비교) / 재고·저재고 / 캐시 관제 / 환불·할인·비용 *승인* / 온라인주문 보드 / FCM 알림.
- **기술**: 기존 Flutter 인프라(Dio+Riverpod+secure storage+FCM+JWT) + `mobile_sessions` 재사용, 서버 role/scope 강제, pool 보호.
- **상태**: 전부 ⬜ (기획만). 착수 전 Wave 52-00(별도앱 vs 모드 결정 + 태블릿 디자인).
- **★ 데이터 소스 재사용 (2026-07-16 결정)**: 대시보드·관제 데이터는 **Phase 57의 `GET /dashboard/admin/control-center` 단일 집계 API를 그대로 재사용**한다 (앱용 개별 API·신규 pool 생성 금지). 따라서 실행 순서는 **57 → 52** — 57 Wave C 완료 후 이 앱은 Flutter 화면만 얹는다. 관련: `.gsd/spec-phase57-menu-admin-control-center.md` 위젯 카탈로그 W1~W8.
