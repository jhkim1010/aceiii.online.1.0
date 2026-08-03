# Phase 70 — 변경 전 기준값 (2026-08-03 측정)

70-07 UAT 가 "변화가 있었는가" 를 판정하려면 착수 시점 값이 필요하다. Wave 1 시작 직후,
어떤 Plan 도 코드를 바꾸기 전에 측정했다.

## 불변식 (양쪽 모두 0 이어야 하고, 지금도 0)

| 지표 | 로컬 5432 | 운영 5434 |
|---|---|---|
| `v_stock_balance_drift` | **0** | **0** |
| `v_stock_tenant_leak` | **0** | **0** |
| `v_product_stock_drift` (unexplained_delta ≠ 0) | **0** | **0** |

## 규모

| 테이블 | 로컬 | 운영 |
|---|---|---|
| `stock_balances` | 642 | 230 |
| `stocks` | 944 | 1,020 |

CONTEXT 의 손익분기(매장당 원장 1,800행)에 아직 못 미친다 — 이 Phase 의 값어치는
응답시간이 아니라 **쓰기 경합 제거**라는 전제가 측정으로도 유지된다.

## 테스트 안전망 (변경 전)

`npx jest` 전체: **15 스위트 / 33 테스트 실패** (996 중). 전부 pre-existing.

실패 스위트: `stocks.service` · `productStock.service` · `products.service` · `sales.controller` ·
`suspended-sales.controller` · `suspended-sales.service` · `afip-output.service` ·
`rest-gateway.provider` · `outbox.service` · `role-function.service` · `user-function.service` ·
`click-to-chat.whatsapp` 외.

70-01 이 만지는 파일 4개(`stocks.service` / `productStock.service` / `products.service` /
`sales.controller`)가 전부 이 목록에 있다 — **신규 실패와 기존 실패를 반드시 구분**해야 한다.

## 운영 상태 (착수 시점)

- api 빌드 `#594` (커밋 `6819f44` = Phase 69-11) → 이후 다른 세션의 Stock Vistas 커밋 4개가 얹힘
- api-ventago HEAD `c03ac03`, ventago-app HEAD `60d7c83`
- 격리 훅: `mode=enforce 보호모델=114 | derivedMode=enforce 대상=45`
