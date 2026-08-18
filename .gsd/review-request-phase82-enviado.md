# 자문 요청 — Phase 82: Enviado(온라인 배송) 관제 보고서 + Reservado 숨김

당신은 이 저장소(Ventago POS/ERP — NestJS + Sequelize + PostgreSQL 18 + Next.js 13 + MUI 5)의
시니어 리뷰어입니다. **비판적으로** 검토해 주세요. 구현 전 계획 단계입니다.

## 사용자 요구

- Reportes 메뉴의 **Reservado 를 숨기고**, **Enviado(Online Venta) Control** 보고서를 새로 만든다
- Despacho 칸반 보드(`/ventas-online`)가 이미 운영을 잘 담당하므로, 보고서는 **다른 질문**에 답해야 한다
- Mockup: KPI 4칸 → 구간 분해 바 → 탭 4개(`Demorados`/`Enviados`/`Por transporte`/`Sin tracking`)

## 데이터 (운영 실측 2026-08-17)

`online_orders` 컬럼:
```
confirmed_at · prepared_at · dispatched_at · shipped_at · delivered_at · cancelled_at
status(varchar) · transporte_id · shipping_carrier · tracking_code · despacho_code
shipping_cost · total · subtotal · channel · fulfillment_branch_id · branch_id
mirror_sale_id · stock_held_at · stock_released_at
```

| | 값 |
|---|---|
| 총 주문 | **12** |
| status | delivered 8 · confirmed 2 · preparing 1 · cancelled 1 |
| `shipped_at` 있음 | 9 (그중 **cancelled 1**) |
| `delivered_at` 있음 | 8 |
| `tracking_code` 있음 | 8 |
| `transporte_id` 있음 | 10 / 운송사 **3곳** |
| `dispatched_at` 있음 | 9 / `prepared_at` 있음 | 9 |

★ `shipped_at` 과 `dispatched_at` 이 **둘 다** 존재하고 9건 모두 채워져 있어 지금은 구분이 안 된다.

## 외부 조사에서 가져온 정보 구조

Shopify(`Order pending fulfillment`) · ShipStation(aging summary) ·
MercadoLibre 판매자 패널(`Despachos demorados` — 지연 추이·요일/시간대) ·
Shipium/DCL/Shipink(OTD 95% 기준, **운송사별** OTD, 주문당 배송비, 처리시간).

조사 권장 KPI 3개는 정시배송률·주문당 배송비·**반품률**인데, **반품률은 뺐다** —
`online_orders` 에 반품 상태가 없어 항상 0 인 칸이 된다. 대신 **En tránsito(건수 + 묶인 금액)**.

## 계획

**정의(사용자 결정 반영)**
- `shipped_at` 을 "Enviado" 의 **정본**으로 고정 (dispatched_at 과 섞지 않는다)
- **정시 = `delivered_at − shipped_at ≤ 5일`**. 사용자가 `promised_delivery_date` 컬럼을
  만들지 않기로 결정했다 → **내부 기준**. 상수 하나(`ON_TIME_MAX_DAYS`)에서만 정의하고
  응답에 값을 실어 화면이 `criterio ≤ 5 días` 로 표기한다
- 취소 주문은 정시 계산에서 제외

**W1(서버)**: KPI(정시율 · En tránsito 건수+`SUM(total)` · 주문당 배송비+티켓 대비 % · 평균 소요일) ·
구간 분해(4구간 평균 일수, **양쪽 타임스탬프가 있는 주문만**) ·
목록 4종 · 권한 `reporte-enviado`(새 슬러그) + 시드/마이그레이션

**W2(화면)**: Mockup 대로. registry 에 `hidden?: boolean` 을 추가해 `reservado: hidden true`.
엔트리·코드·권한 슬러그(`reporte-reservado`)는 **남긴다**.

## 질문

1. **`shipped_at` vs `dispatched_at`** — 정본 선택이 맞는가? 두 컬럼이 각각 어디서 쓰이는지
   코드에서 확인하고, 의미가 다르다면 어느 쪽이 "고객에게 나갔다" 인지 판단해 달라.
2. **정시의 시작점** — 나는 `shipped_at` 기준으로 쟀다. 그런데 고객 체감은 **주문(confirmed_at)
   부터**다. 우리 쪽 준비 지연(0.9일)이 정시율에 안 잡히는 게 맞는가? 두 지표를 다 둬야 하는가?
3. **구간 분해의 결측 처리** — 양쪽 타임스탬프가 있는 주문만 세면 구간마다 **분모가 달라진다.**
   그러면 4구간 합이 전체 평균과 안 맞는데, 화면에 어떻게 표현해야 거짓말이 아닌가?
4. **취소 주문** — 발송 후 취소된 1건을 정시 분모에서 뺐다. `En tránsito`(발송·미배달)에는
   포함되는가? 재고는 어떻게 되나(`stock_released_at`)? 이 건이 어느 칸에서도 안 보이면 그것도 문제다.
5. **"묶인 금액"** — `SUM(total)` 로 잡았다. `mirror_sale_id` 가 있는 주문은 판매로도 잡히는데
   **이중 계상**인가? `subtotal`/`shipping_cost` 중 무엇이 맞는가?
6. **표본이 작다** — 운송사별 n=3~14 다. 정시율 71% vs 96% 를 나란히 보여주면 **과잉 해석**을
   부르지 않는가? 최소 표본 표기나 회색 처리 같은 장치가 필요한가?
7. **Reservado 숨김** — registry 에 `hidden` 을 추가하는 방식이 맞는가?
   직접 URL(`/reportes?slug=reservado` 또는 legacyHref)로는 여전히 열리는가? 그래도 되는가?
   권한 슬러그를 남기는 선택의 위험은?
8. **날짜 경계** — 이 저장소는 `created_at::date` 를 UTC 로 세다가 17% 가 어긋난 전례가 있다.
   기간 필터와 "hoy" 계산에서 무엇을 조심해야 하는가?
9. **성능** — 주문 12건이라 지금은 자명하지만, 인덱스가 필요해지는 지점은 어디인가?
10. 그 밖에 놓친 위험 — 특히 **조용히 틀린 숫자가 나오는** 경로.

## 읽어야 할 파일

- `.planning/phases/82-enviado-online-shipping-control-report/82-FINDINGS.md` (실측·조사)
- `.planning/phases/82-enviado-online-shipping-control-report/82-01-PLAN.md` / `82-02-PLAN.md`
- `api-ventago/src/app/online-orders/` (상태 전이·shipped/dispatched 사용처)
- `api-ventago/src/app/reports/reportsStocksCockpit.service.ts` (TODAY_SQL·타임존 규약 참고)
- `ventago-app/src/views/reports-v2/registry.ts` · `ReportsSidebar.tsx`
- `ventago-app/src/views/ventas-online/` (Despacho 보드 — 역할 중복 확인)
- `CLAUDE.md`

## 출력 형식

**총평** → **반드시 고쳐야 할 것(Blocker)** → **고치는 게 좋은 것(Should)** → **선택(Nice)**.
각 항목에 `[근거: 파일:줄]` 과 **구체적 대안**을 붙일 것.
