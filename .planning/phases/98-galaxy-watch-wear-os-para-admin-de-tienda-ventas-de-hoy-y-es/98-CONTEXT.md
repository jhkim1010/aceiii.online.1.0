# Phase 98 — CONTEXT (결정 확정 2026-10-04)

설계 근거·현재 상태·API 형태·웨이브는 `98-PROPUESTA.md`, 화면은 `98-mockup.png`. 이 파일은 **확정된 결정**만.

## Decisions (LOCKED)

- **D-01 플랫폼**: Galaxy Watch = Wear OS 전용. Apple Watch 범위 밖.
- **D-02 방식**: 워치 전용 앱(B). Kotlin + Jetpack Compose for Wear OS, 모노레포 신규 `wear-admin-app/`.
  applicationId = 휴대폰 앱과 동일 `com.coolsistema.tienda_admin_app`.
- **D-03 정보**: 오늘 매출(매장 타임존·지점별·티켓 수·어제 같은 시각 대비) + 카하 현황(서랍 단위·열림/닫힘·잔액·담당자·지난 날 미마감). **읽기 전용.**
- **D-04 배포**: **Google Play** (내부 테스트 트랙으로 시작). Play 개발자 계정·서명키 준비는 사용자 작업 — W5 체크포인트.
- **D-05 대상**: **매장 admin 만**(gerente·기타 역할 제외). 매 요청 시 현재 역할로 재판정 — admin 이 아니게 되면 즉시 401.
- **D-06 연결**: **코드 페어링** — 워치가 코드 표시 → admin 이 **휴대폰 앱(tienda-admin-app) 「Relojes」** 에서 입력. 웹 화면은 이번 범위 밖.
  워치 토큰은 `GET /watch/resumen` 전용(다른 라우트 401), 90일 sliding · 30일 유휴 · 회수 가능, 헤더로만 전달.
- **D-07 금액 표시**: **축약(M)** — 워치 앱·Tile·컴플리케이션 모두. 예: `$1,28 M`, 백만 미만은 `$842 K`, 천 미만은 그대로.
  (es-AR 소수점 콤마.)

## Claude's discretion

- 새 테이블 이름/컬럼, 코드 길이·만료(제안: 8자 · 5분), rate limit 수치, 캐시 TTL(제안 30초).
- Tile 갱신 주기(시스템 최소 15분 근처), 오프라인 표시 문구.

## Deferred

- 푸시 알림(FCM) · Apple Watch · 웹 페어링 화면 · 기존 `/dashboards/sales/summary` 의 UTC 「오늘」 버그(별건).
