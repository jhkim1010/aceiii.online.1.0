---
phase: 42-retail-envios-despacho-cobranza
plan: 08
subsystem: ventas-online (frontend)
tags: [frontend, swr, cuentas-por-cobrar, historial, cobro, envios]
requires:
  - "useCuentasPorCobrar (42-05) → { rows, totalSaldo, mutate }, clientBalance per row"
  - "CobroModal (42-07) → split/partial cobro modal"
  - "envioLabels (42-05) → canal/payment status labels"
  - "GET /online-orders (Phase 27/42) → list route with from/to(createdAt)+single status filter"
  - "GET /online-orders/cuentas-por-cobrar (42-04) → saldo>0 + clientBalance"
  - "GET /payment-methods, GET /credit/clients/:id/summary"
provides:
  - "CuentasPorCobrarTab — 외상 통제(saldo>0 빨강 + cobro→0 행 소멸)"
  - "HistorialTab — 종료 주문 이력(날짜 범위, DELIVERED 완납 + CANCELLED)"
  - "useEnviosHistory — 소매 배송 이력 전용 SWR 훅 (Phase-40 useDeliveryHistory 미수정 형제 파일)"
  - "Ventas Online 3-탭 컨트롤 센터 완성(Despacho/Cuentas/Historial) — placeholder 제거"
affects:
  - "ventago-app/src/views/ventas-online/VentasOnlineView.tsx (use_envios=true 경로만)"
tech-stack:
  added: []
  patterns:
    - "useDeliveryHistory 날짜범위 SWR 패턴을 형제 파일로 복제(식당/소매 공유 경로 회귀 가드)"
    - "닫힌 주문 집합을 list 라우트 범위조회 + 클라이언트 합성(다중 status 미지원 보완)"
    - "next/dynamic ssr:false 코드 스플리팅으로 탭별 지연 마운트"
key-files:
  created:
    - "ventago-app/src/hooks/api/useEnviosHistory.ts"
    - "ventago-app/src/views/ventas-online/CuentasPorCobrarTab.tsx"
    - "ventago-app/src/views/ventas-online/HistorialTab.tsx"
  modified:
    - "ventago-app/src/views/ventas-online/VentasOnlineView.tsx"
decisions:
  - "useEnviosHistory 는 Phase-40 useDeliveryHistory 를 수정/확장하지 않고 형제 파일로 신설(식당/소매 회귀 가드)"
  - "closed=DELIVERED 완납 + CANCELLED 판정을 클라이언트에서 합성(list 라우트가 단일 status·createdAt 만 지원)"
  - "부분결제(saldo>0)로 배달된 건은 Historial 에서 제외 → Cuentas por cobrar 통제 대상(중복 노출 방지)"
metrics:
  duration: ~1 task-cycle
  completed: 2026-06-19
---

# Phase 42 Plan 08: Cuentas por cobrar + Historial + 위상 검증 Summary

Ventas Online 3-탭 컨트롤 센터의 마지막 두 탭(외상 통제 Cuentas por cobrar + 종료 주문 Historial)과 전용 `useEnviosHistory` 훅을 신설하고, 42-06 이 남긴 placeholder 를 실제 뷰로 배선했다. RD-7/RD-8 충족. 백엔드 jest(24 PASS) + 프론트 lint(clean) 자동 검증 통과 — 단, 42-06/42-07 브라우저 UAT 2건은 여전히 사용자 sign-off PENDING 이므로 위상 완료(shipped)는 그것에 게이트됨.

## Commits (ventago-app submodule, branch fix/pos-precio-base-fallback)

- `fb236e5` feat(42-08): useEnviosHistory 훅 + CuentasPorCobrarTab (외상 통제 saldo>0 + cobro)
- `9de41d2` feat(42-08): HistorialTab(종료 주문 이력) + 3-탭 배선 완료

## What was built

### Task 1 — useEnviosHistory + CuentasPorCobrarTab
- **`useEnviosHistory.ts` (신규 형제 파일)**: 기존 `GET /online-orders`(from/to=createdAt 범위 + status, `FilterOnlineOrdersDto`)를 소비. `{ fromDate, toDate }`(toExclusive) 키, 5분 dedup, 폴링 없음. closed = `cancelled` ∪ (`delivered` ∧ `paymentStatus=paid`) 를 클라이언트에서 필터. **Phase-40 `useDeliveryHistory.ts` 는 한 줄도 수정하지 않음**(식당/소매 공유 경로 회귀 가드, user memory).
- **`CuentasPorCobrarTab.tsx`**: `useCuentasPorCobrar()` 소비. saldo>0 행만 빨강 노출(완납은 백엔드+클라이언트 이중 방어로 절대 미표시). 컬럼: `#` / Cliente / Total / Recibido / **Saldo(빨강)** / Saldo cliente(per-row `clientBalance`=StoreClient.balance) / Acción. 헤더에 `totalSaldo` 합계(빨강). 행별 **Registrar cobro → CobroModal**(`saldoPendiente=row.saldo`). `onCobroDone → mutate()` 로 완납(0)된 행이 응답에서 빠져 자연 소멸. payment-methods 가상 슬러그(credito/favor/senia) 필터, 행 고객 `favorBalance`(useCreditClientSummary). pageSize≤50 클라이언트 페이지네이션.

### Task 2 — HistorialTab
- **`HistorialTab.tsx`**: Desde/Hasta 날짜 범위(inclusive UI → toExclusive 변환) → `useEnviosHistory`. 컬럼: `#` / Cliente / Canal / Total / Pago(envioLabels 배지) / Transporte(carrier·tracking) / Despachado / Entregado / Resultado(Entregado·Cancelado 배지). 폴링/소켓 없음(정적 이력). pageSize≤50(훅이 50으로 fetch).
- **`VentasOnlineView.tsx`**: `cobrar`/`historial` 탭의 `EnviosTabPlaceholder('Cargando…')` 제거 + 미사용 placeholder 함수 삭제, `next/dynamic ssr:false` 로 두 탭 실제 배선. `use_envios=true` 경로만 변경, 레거시(`use_envios=false`) 탭 코드 무변경.

### Task 3 — 위상 검증(자동) — completion NOT claimed
- **42-06/42-07 브라우저 UAT 상태**: 둘 다 SUMMARY 상 **PENDING USER VERIFICATION**(42-06 L87 board UAT, 42-07 L71 cobro/cancel/caja UAT). 승인 미완 → **위상 완료(shipped) 주장하지 않음**.
- **백엔드 jest**: `npx jest online-orders transportes credit box-operation` → **3 suites / 24 tests PASS**. (force-exit 경고는 teardown leak 경고일 뿐 실패 아님. Phase-29 `mp-webhook.service.spec.ts` TS2554 는 이 패턴들에 매칭되지 않아 스코프 밖 — 노이즈 없음.)
- **프론트 lint**: Phase-42 touched 파일 12종 `npx next lint` → **No ESLint warnings or errors**.

## RD-1..RD-12 Coverage Map

| RD | 충족 plan | 본 plan(42-08) 기여 |
|----|-----------|----------------------|
| RD-1 | 01/03/05 | — |
| RD-2 | 02/04/05/06 | — |
| RD-3 | 02 | — |
| RD-4 | 02(ship intent)/03(deliver accrual) | — |
| RD-5 | 02/07 | — |
| RD-6 | 02/07 | — |
| RD-7 | 02/04(backend)/05(hook)/**08(tab)** | ✅ CuentasPorCobrarTab(saldo>0 + per-client balance + cobro→0 행 소멸) |
| RD-8 | **08** | ✅ HistorialTab + useEnviosHistory(날짜 범위 종료 주문) |
| RD-9 | 04/06 | — |
| RD-10 | 03 | — |
| RD-11 | 07 | — |
| RD-12 | 03/06 | 회귀 spot-check(아래) |

전 RD 가 plan 에 매핑됨 — 미커버 RD 없음.

## RD-12 소매 무회귀 spot-check (문서화)

- **use_envios=false 매장 = 레거시 탭 유지**: `VentasOnlineView` 진입점 분기(`useEnvios ? EnviosControlCenter : LegacyVentasOnline`)는 본 plan 에서 미변경. 본 plan 의 모든 변경은 `EnviosControlCenter`(use_envios=true) 내부에만 국한 → 레거시 Pedidos/Envíos/Devoluciones 경로 코드 회귀-0. lint 통과로 빌드 게이트 확인.
- **완납 배달의 PAID 미러/리포트 반영**: deliverOrder(완납) → `commitSale + createMirror`(jest 로그 `mirrorSaleId=5001 shipSaldo=0 paymentStatus=paid`) 확인. 본 plan 은 표시 레이어만 추가하여 미러/회계 로직 미접촉 → 이중계상 없음.
- **shortfall 배달 = sale_credit 정확히 1건**: jest 로그 `[deliverOrder] sale_credit 누적 amount=400` 1회 — 부분결제 배달 시 sale_credit 1건만 누적(credit.spec 그린). Cuentas por cobrar 는 이 미수금을 표시만 함(추가 분개 없음).
- **Cuentas 완납 미표시(clean close)**: 백엔드 cuentas-por-cobrar(saldo>0) + 클라이언트 `saldo>0` 이중 필터 → 완납 주문 절대 미노출. cobro→0 시 `mutate()` 로 행 소멸 = clean close.

## Missing backend route note (확인됨, 차단 아님)

`GET /online-orders` 목록 라우트(`FilterOnlineOrdersDto`)는 **단일 status enum** + **createdAt 기준 from/to** 만 지원한다. 따라서:
- "종료 주문 = DELIVERED 완납 + CANCELLED" 다중 status 집합을 한 번에 받을 수 없고,
- `deliveredAt`/`cancelledAt` 기준 날짜 필터(이력 본연의 시점)도 미지원(현재 createdAt 기준).

**현 구현**: useEnviosHistory 가 createdAt 범위로 받아 클라이언트에서 closed 합성. 대부분의 소매 운영(주문 생성~종료 간격 짧음)에서 충분.
**권고(선택, 미차단)**: 정밀 이력을 위해 `GET /online-orders/historial?from=&to=&` 형태의 **deliveredAt/cancelledAt 기준 + closed 다중 status** 전용 라우트를 추가하면 장기 범위 조회 정확도 향상. 본 plan 범위 밖이라 추가하지 않고 기록만 함(silently assume 회피).

## Deviations from Plan

### Auto-fixed / 판단 사항

**1. [Rule 3 - blocking 보완] HistorialTab 의 paymentStatus 배지 색**
- envioLabels `paymentStatusColor(status, saldo)` 는 saldo 인자 옵션 — 이력 행엔 saldo 미동봉이라 status 만으로 호출(paid=초록/partial=골드/그 외 빨강). 의도된 사용 범위 내.

**2. [설계 결정] closed 집합 클라이언트 합성**
- 위 "Missing backend route note" 참조. 아키텍처 변경(신규 라우트) 대신 기존 라우트 소비 + 클라이언트 필터로 해결(Rule 4 회피). 백엔드 라우트 권고는 SUMMARY 에 기록.

그 외 plan 대로 실행됨.

## Known Stubs

없음 — 두 탭 모두 실제 데이터 소스(useCuentasPorCobrar / useEnviosHistory)에 배선됨. 42-06 이 남긴 'Cargando…' placeholder 는 본 plan 에서 제거됨.

## Phase completion gate (중요 — 미주장)

본 plan 의 코드/자동검증은 완료이나, **위상 42 의 완전 검증/배포는 다음 2건의 브라우저 UAT 사용자 sign-off 에 게이트**된다:
1. **42-06 board UAT** — 실시간 보드 갱신(/envios 소켓) + 레거시(use_envios=false) 무회귀.
2. **42-07 cobro/cancel/caja UAT** — saldo 차감 / favor 적용 / caja 정합.

이 둘은 라이브 브라우저+dev 스택이 필요해 본 환경에서 실행 불가. **위상 완료(shipped) 주장하지 않음** — 사용자 UAT 후 게이트 해제.

## Self-Check: PASSED

- 생성 파일 4종 존재 확인(hook + 2 tabs + SUMMARY)
- 커밋 fb236e5 / 9de41d2 (ventago-app) git log 확인
