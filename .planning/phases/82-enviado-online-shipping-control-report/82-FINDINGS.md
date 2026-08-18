# Phase 82 — 실측 + 외부 조사 (2026-08-17)

## 사용자 요구

- Reportes 의 **Reservado 를 숨기고**, 그 자리에 **Enviado(Online Venta) Control** 보고서를 둔다
- Despacho 보드가 이미 잘 돼 있으니 **다른 시스템의 아이디어**를 조사해서 무엇을 담을지 정한다
- Mockup: `.gsd/` 대신 아티팩트로 공유 — https://claude.ai/code/artifact/eec55483-c567-4fb3-889d-75a26059a103

## F1. 데이터 — 구간 타임스탬프가 4개 있다 (이게 강점)

`online_orders`:
```
confirmed_at → prepared_at → dispatched_at → shipped_at → delivered_at   (+ cancelled_at)
```
부가: `transporte_id` · `shipping_carrier` · `tracking_code` · `despacho_code` · `shipping_cost` ·
`channel` · `fulfillment_branch_id` · `total`.

★ **`shipped_at` 과 `dispatched_at` 이 둘 다 존재한다.** 운영 9건은 둘 다 채워져 구분이 안 되지만,
정의를 하나로 고정하지 않으면 나중에 두 숫자가 갈라진다(이 저장소의 반복 사고 유형).
→ **`shipped_at` 을 "Enviado" 의 정본**으로 고정하고 그 사실을 화면 각주에 적는다.

## F2. 운영 데이터 규모 (2026-08-17)

| | 값 |
|---|---|
| `online_orders` 총 | 12 |
| status | delivered 8 · confirmed 2 · preparing 1 · cancelled 1 |
| `shipped_at` 있음 | 9 (그중 cancelled 1) |
| `delivered_at` 있음 | 8 |
| `tracking_code` 있음 | 8 |
| `transporte_id` 있음 | 10 / 운송사 3곳 |

→ **En tránsito 는 현재 0건**(9 발송 = 8 배달 + 1 취소). 화면은 비어 보이는 게 정상이다.
   히트맵·요일 분석은 표본이 없어 이번 범위에서 뺀다.

## F3. 외부 조사 — 다른 시스템이 실제로 보여주는 것

| 시스템 | 화면 | 가져온 것 |
|---|---|---|
| Shopify | `Order pending fulfillment` (병목 조기 발견) | 상태가 아니라 **경과 시간**으로 정렬 |
| ShipStation · Smart Que | `Awaiting Shipment` + **aging summary** | "떠났는데 안 닿은 것" 을 **별도 탭**으로 |
| MercadoLibre 판매자 패널 | **`Despachos demorados`** — 지연 추이 · 요일/시간대 | `Demorados` 탭(기본). 요일 히트맵은 표본 부족으로 보류 |
| Shipium · DCL · Shipink | OTD 95% 기준 · **운송사별** OTD · 주문당 배송비 · 처리시간 | `Por transporte` 탭 + KPI 기준치를 화면에 표기 |

공통 조언: **KPI 3개로 시작**(정시배송률 · 주문당 배송비 · 반품률).
→ **반품률은 뺀다** — `online_orders` 에 반품 상태가 없어 항상 0 인 칸이 된다.
   대신 **En tránsito(건수 + 묶인 금액)** 를 넣는다. 지금 어느 화면에도 없는 숫자다.

## F4. ★ 결정됨 — "정시"의 기준 (2026-08-17 사용자)

약속 배송일(`promised_delivery_date`)은 **만들지 않는다.** 스키마 변경과 입력 경로가 따라온다.
→ **내부 기준**을 쓴다: `delivered_at − shipped_at ≤ N일` 이면 정시. 기본 **N = 5**.

지켜야 할 것:
- 기준값은 **한 곳에서만** 정의한다(상수 1개). 화면·API·export 가 같은 값을 본다.
- 화면에 **기준을 그대로 표기**한다(`criterio ≤ 5 días`). 표기 없는 88% 는 좋은지 나쁜지 알 수 없다.
- 이건 운송사의 실제 약속이 아니라 **우리 내부 기준**이라는 사실을 각주로 남긴다.
- 매장별 설정(store_configs)으로 올리는 것은 **후속** — 지금은 상수, 필요해지면 그때.

## F5. Reservado 숨기기

`reports-v2/registry.ts` 에는 `hidden` 플래그가 **없다**. 엔트리를 배열에서 빼는 방식뿐이다.
→ 엔트리를 주석 처리하지 말고 **`hidden?: boolean` 필드를 추가**해 목록 렌더에서 거른다.
   코드·권한 슬러그(`reporte-reservado`)·보고서 본문은 **그대로 남긴다** — 되돌리기 쉽고,
   권한이 조용히 다른 보고서로 넘어가지 않는다.

★ 새 보고서는 **새 슬러그(`reporte-enviado`)** 를 쓴다. `reporte-reservado` 를 재사용하면
  Reservado 권한을 가진 사람이 자동으로 Enviado 를 보게 된다.
