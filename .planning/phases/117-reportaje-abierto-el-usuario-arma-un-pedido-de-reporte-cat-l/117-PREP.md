# Phase 117 — Reportaje abierto

등록 2026-10-17. 사용자: 「reportaje abierto 라는 식으로 메뉴를 하나 준비하고, 거기 사용자가 정해진 주문서를 허용된 한도 내에서 만들 수 있게」 → 목업 확인 후 「Phase 로 등록해 둬. 그리고 진행하자.」

- 목업: `.planning/mockups/2026-10-17-reportaje-abierto/mockup.html` (+ png)
- CODEX 자문 원문: `.planning/mockups/2026-10-17-reportaje-abierto/CODEX.md`

## 구조 (CODEX 동의)
의미 카탈로그(지표·차원·필터 allowlist) → 사용자 주문서 JSON → 서버 검증(store_id 는 세션에서 강제, 권한·한도) → 파라미터 바인딩된 SQL 컴파일 → 표/차트/CSV. 자유 SQL 없음. 나중에 AI 는 같은 JSON 만 생성.

## CODEX 권고 (MVP 기본값 — discuss 에서 확정)
- 지표: 순매출 · 수량 · 티켓 수 · 평균 티켓(SUM/SUM) · 반품(별도). 마진은 관리자 전용(2차 가능).
- 차원: 지점 · 로컬 일/주/월 · 카테고리 · 상품/마드레(TOP N 필수). 2차: 판매자·결제수단·비용. 고객 제외(PII).
- 한도: 차원 ≤2(고카디널리티 ≤1) · 일 단위 ≤90일, 주/월 ≤12개월 · 화면 ≤1,000행 · CSV ≤10,000 · TOP ≤100 · timeout 5s(CSV 20s) · 매장당 동시 1 · 전체 semaphore 4~6.
- 금지: 재고×시간 · 상품×일(31일·TOP 없이) · 상품×고객/결제수단 · 결제수단 평균 티켓.
- 「판매」 정의를 기존 보고서와 **하나의 버전화된 정의**로(activity_type·취소·반품/NC·로컬 날짜) — Phase 105(보고서 일관성)와 겹친다.
- 재고는 별도 보고서 유형(stock_balances snapshot).
- 저장 주문: store_id·권한 결과 저장 금지, 열 때마다 재검증 + 카탈로그 버전 경고.
- 운용3 복제본: MVP 에선 안 씀(primary + 강한 한도 + slow 로그).
