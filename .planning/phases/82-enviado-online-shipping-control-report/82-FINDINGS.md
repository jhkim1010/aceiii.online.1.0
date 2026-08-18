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

---

# CODEX 교정 (2026-08-17) — 전문: `.gsd/review-codex-phase82-enviado.md`

## C1. ★ `dispatched_at → shipped_at` 은 구간이 아니다 (내 mockup 의 오류)
`shipOrder()` 가 **같은 줄에서** 둘 다 찍는다:
```ts
order.shippedAt = new Date();
order.dispatchedAt = new Date();   // online-orders.service.ts:1023-1024
```
→ 그 구간은 **항상 0**이다. 4칸 바에 넣으면 "존재하지 않는 운영 단계"를 만들어낸다.
**채택**: 3구간으로 줄인다 —
`confirmed→prepared`(준비) · `prepared→shipped`(출고) · `shipped→delivered`(운송).
4칸이 꼭 필요하면 앞에 `created→confirmed`(접수→확인)를 붙이되 이름을 정확히 쓴다.
`shipped_at` 을 Enviado 정본으로 쓰는 결정 자체는 유지.

## C2. 기간 필터의 **코호트**가 정의돼 있지 않았다 ★ Blocker
발송 기준으로 자르면 미배달분이 정시율 분모에서 빠지고, 배달 기준으로 자르면
발송 건수와 정시율이 **서로 다른 집합**이 된다.
**채택**: 기본 코호트 = `shipped_at >= :fromUtc AND shipped_at < :toUtc`(반개방).
KPI 마다 `eligibleCount` / `excludedCount` 를 응답하고, **미배달분이 분모에서 빠졌다는 사실을
화면에 표기**한다. "기간 중 배달 성과" 가 필요하면 같은 KPI 에 섞지 말고 별도 지표로.

## C3. 취소된 발송이 `En tránsito` 에 남는다 ★ Blocker
취소 경로는 판매·재고를 역분개하고 `stock_released_at` 을 찍는다 → **길에 묶인 재고가 아니다.**
**채택**: `shipped_at IS NOT NULL AND delivered_at IS NULL AND cancelled_at IS NULL`.
`Demorados`·운송사별 미배달도 **같은 조건 공유**. 발송 후 취소는 별도
`Cancelados después del envío` 로 노출(어느 칸에도 안 보이면 그것도 문제다).
진단값: `cancelled_at IS NOT NULL AND stock_released_at IS NULL`.

## C4. 타임존 변환을 구체화 ★ Blocker
"TODAY_SQL 규약을 따른다" 로는 부족하다. 기존 규약은 *오늘* 계산용이고, 여기는 사용자가 보낸
**현지 날짜 범위**를 UTC `timestamptz` 와 비교해야 한다. `shipped_at::date` 를 쓰면 17% 오차가 재발한다.
**채택**: 현지 `from 00:00` / `to+1 00:00` 을 UTC 로 변환해 **컬럼에 함수를 씌우지 않고** 비교.
경과일은 `(now AT TIME ZONE tz)::date − (shipped_at AT TIME ZONE tz)::date`.
DST·자정 경계 테스트 추가. 모든 쿼리에 `store_id` 필수.

## C5 (Should). 정시율을 둘로 나눈다
`delivered − shipped` 는 **운송사 성과**다. 이걸 "정시배송률" 이라 부르면 고객 체감(주문부터)을
가리킨다고 오해된다.
**채택**: 주 KPI `OTD transporte`(≤5일) + 보조 `Tiempo total`(confirmed→delivered)은 **비율이 아니라
평균·P90 일수**로. 운송사 비교는 `shipped` 기준만.

## C6 (Should). 구간마다 분모가 다르다
결측 제외는 맞지만 **4구간 평균의 합 ≠ 전체 평균**이다.
**채택**: 구간마다 `avgDays`·`sampleCount`·`missingCount` 반환, 화면에 `n=8` 표기.
합계를 전체 평균처럼 보여주지 않는다. 별도로 `completeJourneyAvg`(전 구간 타임스탬프가 다 있는 주문).
역전된 타임스탬프의 음수 구간은 조용히 빼지 말고 `invalidSequenceCount` 로 보고.

## C7 (Should). "묶인 금액" 은 재고가액이 아니다
`SUM(total)` 은 청구액이다. 발송 시 `mirror_sale_id` 로 판매도 생기므로 **Ventas 보고서와 합산하면
이중 계상**이다.
**채택**: 이름을 `Valor de pedidos en tránsito`(GMV)로. "판매 보고서와 합산 금지" 를 정의에 명시.
상품가액만 원하면 `subtotal − discount`, 배송비 포함 여부를 화면에 표기.

## C8 (Should). 배송비 KPI 의 분모·0 처리
**채택**: 분모는 **발송 코호트(취소 제외)**. 비율은 `SUM(shipping_cost)/NULLIF(SUM(total),0)`.
컬럼이 고객 청구액이면 이름은 `Costo` 가 아니라 `Cargo de envío cobrado`.

## C9 (Should). 표본이 작으면 회색 처리
`n=3` 의 100% 와 `n=14` 의 71% 를 나란히 강조하면 과잉 해석을 부른다.
**채택**: 행마다 `delivered n / shipped n` 표기, **분모 10 미만이면 회색 + `muestra pequeña` 배지**,
순위·최악 강조에서 제외. 95% 는 외부 목표가 아니라 **내부 참고 목표**임을 명시.

## C10 (Should). `hidden` 은 모든 탐색 경로에
사이드바 일반 목록만 거르면 **최근 항목·즐겨찾기**에 남는다.
**채택**: `isVisibleReport(entry) => !entry.hidden` 공용 함수를 목록·검색·최근·즐겨찾기에 전부 적용.
localStorage 에 남은 `reservado` 즐겨찾기도 렌더 단계에서 제거. 회귀 테스트 3경로.

## C11 (Should). 직접 URL 정책을 명시
`REPORTS_BY_SLUG` 에는 숨긴 엔트리가 남아 직접 URL 은 계속 열린다. 셸은 `hidden` 이 아니라 권한만 본다.
**채택**: 이번 요구는 **"탐색 UI 에서만 숨김, 기존 권한자의 직접 접근 허용"** 으로 문서화.
완전 비활성화가 목적이면 셸에서도 `hidden` 을 검사해야 한다(이번 범위 아님).

## C12 (Should). 인덱스는 성장 기준을 기록만
12건에서 성급히 만들지 않는다. 필요해지면
`CREATE INDEX CONCURRENTLY ... (store_id, shipped_at DESC) WHERE shipped_at IS NOT NULL`
(트랜잭션 밖). 운송사 집계가 병목이면 `(store_id, transporte_id, shipped_at)`.

## C13 (Nice). P90 · 데이터 품질 KPI
평균 옆에 **P90**(표본 충분할 때만). 이상 건수 진단: `delivered < shipped` ·
`shipped < prepared` · `shipped 있는데 confirmed 없음` · 취소인데 `stock_released_at` 없음 ·
`transporte_id` 없이 `shipping_carrier` 만 있음 · 발송인데 tracking 없음(즉시배송 제외).

---

# 측정 타당성 교정 (2026-08-17) — 사용자 지적에서 나온 것

## D1. ★ `delivered_at` 은 "도착 시각" 이 아니다

사용자 질문: *"모든 transporte 회사의 API 와 연결이 안 될 텐데 어떻게 배달 완료를 확인하지?"*

코드 확인 결과 **운송사 연동은 없다.** 운송사 이름이 나오는 곳은 despacho 코드 접두어
생성기(`'Correo Argentino' → 'CA'`) 하나뿐이다.
```
deliverOrder()  →  order.deliveredAt = new Date()      by=${userName}
```
= **직원이 Despacho 보드에서 "Entregado" 를 누른 시각**. (예외: 자체 배송은 `shipOrder` 안에서
발송과 동시에 찍는다.)

그래서 계획대로 OTD 를 계산하면 실제로 재는 것은:

| 재려던 것 | 실제로 재는 것 |
|---|---|
| 운송사가 며칠 걸렸나 | **직원이 며칠 만에 클릭했나** |
| 길에 묶인 금액 | 배달됐는데 **아무도 안 누른 주문**까지 포함 |

두 번째가 더 위험하다 — 클릭 안 된 주문은 영원히 `En tránsito` 에 남아 금액을 부풀린다.
조사한 시스템들이 OTD 를 헤드라인으로 쓸 수 있는 건 **운송사 스캔이 자동으로 들어오기 때문**이다.

## D2. 신뢰할 수 있는 신호는 `shipped_at` 하나뿐 → KPI 재구성

- **주 KPI = `Sin confirmar`** (발송 후 확인 안 된 건수·금액·경과일). 시스템이 쓰는 값만 쓴다
- OTD 는 유지하되 이름을 **`Entregas confirmadas a tiempo`** 로, **"확인 시각 기준"** 각주 필수
- 새 품질 KPI: **확인율**(발송 대비 `delivered_at` 있는 비율). 낮으면 나머지 숫자를 믿지 말라는 신호

→ 보고서가 "운송사 성과 측정"이 아니라 **"확인 습관을 고치는 도구"** 로 정직해진다.
   습관이 잡혀야 나중에 진짜 OTD 가 의미를 갖는다.

## D3. ★ 직원 확인은 **도착일을 입력받는다**

직원이 5일 늦게 클릭하면 그 늦음이 그대로 배송 지연으로 기록된다 — 지금 계획의 최대 왜곡 원인.
→ 확인 시 **"¿Cuándo llegó?"**(기본값 오늘)를 받고, **클릭 시각과 도착일을 따로** 저장한다.
   그러면 "우리가 얼마나 늦게 확인하는가" 도 측정된다.

## D4. 자동 확인은 하지 않는다

*"N일 지나면 자동 배달 처리"* 는 **책임자 없는 기록**을 만든다. 신규 주문은 `deliverOrder` 가
물류 마일스톤만 찍어 위험이 작지만, **레거시 폴백 경로(`mirrorSaleId == null`)는 여전히
매출·외상을 만든다.** 자동화가 그 경로를 건드리면 아무도 안 누른 회계 기록이 생긴다.

## D5. 고객 확인은 Phase 83 으로 분리

사용자 제안: 고객이 추적 링크에서 확인 → 잊으면 직원이 대행.
★ 단, **"직원 확인 → 고객이 그것에 OK"** 의 마지막 단계는 **뺀다.** 고객이 첫 번째를 안 눌렀다면
두 번째도 안 누른다 → 주문이 계속 열린 채 남아 처음 문제로 돌아온다.
→ 직원 확인은 **즉시 종결**시키고, 고객에게는 **통지만** 보낸다("아니면 알려주세요").
   침묵 = 동의. 고객이 "안 받았다" 를 누르면 `En disputa` 로 올라온다.
스키마(`delivered_confirmed_by/at`)·공개 페이지·토큰이 필요하므로 **Phase 83**.
