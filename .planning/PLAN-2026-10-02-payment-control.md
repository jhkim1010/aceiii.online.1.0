# Payment Control (Configuración de Suscripción) — 1화면 재구성 + Factura electrónica 비용 — 계획

## 요청
1. 화면이 흩어져 있다 → **스크롤 없이 한 화면**에서 다 보이게.
2. **Fac. electrónica 비용도 계산**되게.

## 현재 (코드 근거)
- `ventago-app/src/views/admin/subscription/SubscriptionConfigView.tsx` (688줄): 카드 8개가 세로로
  — Estado del Sistema · Precios(3칸이 한 줄씩) · Período de prueba · Módulos e Integraciones ·
  Mercado Pago · Stripe · Simulador · Resumen de ingresos. 입력칸이 전부 전체 폭.
- **FE 요금 필드는 이미 있다**: `subscription_config.integration_factura_electronica_price = 20.000 ARS`.
  ★ 그런데 **시뮬레이터에서만** 쓰인다(`subscription-config.service.ts:100`). 실제 청구 계산
  `billing/billing-calculator.ts`(유일한 계산기, 청구서·요약·매장 상세가 공유)는
  **플랜 + 유료 앱 − 할인**만 본다 → **FE 를 쓰는 매장(Noix·Cielo·coolsistema·ACE)에 FE 요금이 한 번도 청구되지 않았다.**

## 제안
### A. 1화면 레이아웃 (3열, 1366×768 에서 스크롤 없음)
| 열 | 내용 |
|---|---|
| 1 | **Estado** (스위치·Pasarela·Moneda 한 줄) · **Prueba/Gracia**(2칸 한 줄) · **Pasarela 키**는 접힘(선택한 pasarela 만, 기본 닫힘) |
| 2 | **Precios** 표 한 개: Plan base / Sucursal / Terminal / **Factura electrónica** / 앱·연동 — 「항목 · 월 금액」 2열, 행 높이 30px |
| 3 | **Simulador**(같은 표에 수량 칸만) · **Resumen de ingresos**(매장별 1줄: 플랜 · 앱 · **FE** · 할인 · 합계) |
- 저장 버튼은 상단 고정(「Sin guardar」 칩 옆).

### B. Factura electrónica 비용 — **실제 청구에 포함**
- 계산은 `billing-calculator.ts` **한 곳에** 줄 1개 추가: `factura-electronica` (type 'integration').
  화면·요약·청구서가 같은 계산을 쓰므로 갈라지지 않는다.
- `BILLING_FORMULA_VERSION` 1 → **2** (이미 발행된 청구서는 v1 금액 그대로).
- ★ **정해 주실 것** — 청구 단위:
  - **(권고) 매장당 월 정액** — FE 사용 매장(`store_configs.use_factura_electronica = true`)에 20.000/월.
  - (대안 1) **발행자(CUIT)당 월 정액** — CUIT 여럿 쓰는 매장은 그만큼.
  - (대안 2) **전표 건수 비례** — 월 N건까지 포함, 초과분 건당 X. (계산은 되지만 청구 시점에 그 달 건수가 확정돼야 함)
- ★ **정해 주실 것** — 언제부터: 다음 청구 회차부터(권고) / 소급 없음.
- 매장별 예외(무료 제공)는 기존 **할인** 기능으로 처리 — 새 장치 안 만든다.

## 범위 밖
- 결제 게이트웨이·청구 실행 로직 변경 없음(계산 줄 1개 + 버전).

## 영향 · 규모
| 대상 | 내용 |
|---|---|
| api | `billing-calculator.ts`(+spec) · 사실 수집부(매장의 FE 사용 여부) · 버전 2 |
| app | `SubscriptionConfigView.tsx` 재배치 · 매장 상세 청구 카드에 FE 줄 표시 |
| DB | 없음(필드 이미 존재) |
| 위험 | **돈** — 다음 청구부터 FE 매장 금액이 오른다. 대상 매장·금액 목록을 배포 전 보여 드림 |
| 규모 | M |

---
## 2026-10-02 사용자 결정 (요금 정책)
- **기본 플랜 포함**: 1 sucursal · **2 terminales** · **app de vendedor 2명**
  (현재 계산기는 `PER_BRANCH` = 지점당 터미널 1대 포함 → **정책 변경**: 기본 2대 포함. `BILLING_FORMULA_VERSION` 2)
- **추가 요금**: Factura electrónica · app de vendedor(3명째부터) · app de revendedor
- 기존 추가: sucursal adicional · terminal adicional · 유료 앱(Talleres 등)

### 세는 기준 — 확인 필요 (DB 실측 2026-10-02)
| 항목 | 제안 기준 | 근거·문제 |
|---|---|---|
| Fac. electrónica | 매장 `use_factura_electronica = true` → 월 정액 | 필드 있음(20.000) |
| app de vendedor | **그 달에 판매원 앱에 로그인한 서로 다른 사용자 수** − 2 | `mobile_sessions`(user_id·last_seen_at)는 있으나 store_id 없음·판매원 앱/관리자 앱 구분 확인 필요(`app/mobile/auth`). 운영에 모바일 PIN 사용자 1명(store 6)뿐 |
| app de revendedor | 매장에 **승인된 재판매자 연결**(`reseller.reseller_tienda_link`, status) 이 1개 이상이면 월 정액 — 또는 재판매자 1명당 | 스키마 `reseller` (public 아님) |
- 가격 칸 신규: `appVendedorExtraPrice`, `appRevendedorPrice` (subscription_config 에 컬럼 추가 = 마이그레이션 필요)
