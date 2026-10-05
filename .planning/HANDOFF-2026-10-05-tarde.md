# HANDOFF 2026-10-05 (tarde)

## 1. 오늘 운영에 반영한 것 (전부 push·빌드·번들 확인 완료)

| 작업 | 저장소 커밋 | 빌드 |
|---|---|---|
| WP 동기화: WC 상품에 변형이 없고 Ventago 변형이 1개면 재고·가격을 상품 본체로 전송 (Cielo 재고가 한 번도 안 나가던 원인). 변형 1개·속성 없음 폴백도 변형 재고 사용 | api `0d80da8e` | #1083 |
| Cielo 5행 `last_synced_at = NULL` (운영 DML, 승인) → 다음 주기에 5개 전송, WC 재고 일치 확인 | DB | — |
| Reportes › Stocks 「Web」 열 (✓ 동기화 · ⟳ 대기 · ✕ 짝 없음) + `wp_product_sync.last_sync_sin_par int[]` 컬럼 | api `0d336be8` · app `38512846` · 마이그레이션 `2026-10-05-a-wp-sync-sin-par.sql`(로컬+운영 적용) | #1084 · #969 |
| Vendedor 앱 Modo lector (`GET /mobile/scan/:code`, 연속 스캔→카트 +1) + 카트 lineKey(다른 상품 같은 색·사이즈 줄 섞임 수정) + `/mobile/stock` 변형 storeId 필터(테넌트 격리) | api `d89add3d` · mobile-sales-app `9ca614b` · root `74be009` · 태그 `mobile-sales-app-v1.0.7` | #1085 · Actions 성공 |
| v1.0.7 설치 파일 → Dropbox `ACE_3_uversion/app herramientas download/` (고정 이름 3개 + 버전 사본) | — | — |
| Costo por variación: Código Vista 변형 행 원가 입력, 상품 패널 「Costo base · variantes sin costo propio」+ 가격 범위 요약, 부모 원가 비울 때 통화·% 유지 | app `5ac8b6a3` | #970 |
| 변형 원가 칸을 테두리 상자로 + 포커스 강조 | app `aadd393e` | #971 |
| 상품 저장 재진입 잠금(Enter/Ctrl+Enter 가 두 번째 `POST /products` 를 쏘던 것) + 원가 칸 Enter 는 저장 안 함 | app `284041b3` | #972 |
| 사이드바 단축키 Alt+A/V/P/S (그 그룹만 펼침·첫 항목 포커스·↑↓·Enter), 메뉴 옆 「Alt+V」 표시, 포커스 테두리. 출근 QR 은 **Alt+V → Alt+Q** | app `0ec125b5` · `46de3872` · `05349d67` | #973 · #974 · #975 |
| Phase 99 계획 12개 플랜 (실행 전) | root `499c178` | — |

## 2. 미확인 / 남은 것

- **상품 저장 잠금**: 운영에서 실제 이중 저장으로 시험하지 않았다(상품이 생기므로). 코드·빌드만 확인.
- **Código Vista 변형 원가 칸**: 브라우저에서 직접 입력해 보지 않았다.
- **Costo por variación 가격 차이**: 시험 상품 12855(263201)는 ARS 11~12 + 0% 라 반올림 $100 으로 판매가가 모두 같다. USD 나 큰 원가로 넣어 가격이 갈라지는 것을 아직 운영에서 못 봤다.
- **Modo lector**: 실제 폰·카메라로 시험 안 함. Cielo 판매원에게 v1.0.7 설치 후 확인 필요.
- **출근 QR 키 변경(Alt+Q)**: 쓰는 매장에 알려야 한다.
- **PEDIDO 9·10·11·12 (Cielo)**: 계획서만 보냄. 결정 대기(각 PLAN.md 「결정해 주실 점」). PEDIDO 11 의 즉시 동기화 버튼·품절 표시는 오늘 원인 수정으로 일부 성격이 바뀜 — 다시 볼 것.
  - PEDIDO 9 PLAN 의 버전은 v1.0.31 로 정정됨(처음 보낸 파일은 v1.0.10 오기).
- **PEDIDO 8**: 매장 답변 초안만 있음, 미발송. P47 매장 안내문은 사용자가 「안 보내도 된다」.
- **WP 동기화 범위 밖(CODEX)**: `create_missing=true` 채널(store 6)에서 기존 simple 상품이 variable 로 바뀔 수 있음 — 기존 동작, 미수정.
- **Phase 99**: 계획 완료. 넣을지 미정인 항목 5개(#6 B9 · #15 · #16 · #17 · B8). 다음은 `/gsd:execute-phase 99`.

## 3. 다음 세션 주의

- 커밋 게이트가 `grep -la` 를 `commit -a` 로 오인한다 → `git commit` 은 단독 명령으로.
- 앱 jest 의 실패 2개(widget_test, reseller_store_selector_test)는 기존 실패.
- jest 돌연변이 시험 때 MemoryCacheService 를 쓰는 spec 은 실패 시 jest 가 안 끝난다 → `--forceExit`.
- 브라우저 자동화: 스크린샷 좌표(1568) ≠ CSS 픽셀(1920). 로드 직후 이벤트는 하이드레이션 전이라 무시될 수 있다.
