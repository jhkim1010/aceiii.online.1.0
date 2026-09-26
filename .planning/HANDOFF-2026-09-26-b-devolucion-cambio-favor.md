# 핸드오프 2026-09-26 (b) — 반품 · 교환(cambio) · 「favor = crédito 의 음수」

> 다음 세션은 **§1 배포 상태**부터 확인할 것. 13:03 자동 배포는 **세션 안 예약**이라
> 세션이 끝났으면 실행되지 않았다.

## 0. 사용자 확정 규칙 (이 세션에서 정해짐)

| 규칙 | 내용 |
|---|---|
| favor | **crédito 의 음수**다. 결제수단이 아니다. 화면은 잔액 **한 숫자**(음수 = a favor) |
| 자동 상계 | favor 가 있는 손님의 **crédito 판매는 묻지 않고 상계**(Phase 26 SPEC 의 「자동 적용 금지」 폐기) |
| 반품 금액 | **현재 가격**, 서버가 계산(화면 단가 불신) |
| 손님 있음 | 돈을 안 돌려준다 → cuenta 차감(빚 FIFO → 남으면 favor_in) |
| 손님 없음 | **현금 환불**(열린 카하 retiro) |
| 교환 | 한 카트에 구매(+)·반품(−). 차액 > 0 이면 차액만 결제, **< 0 이면 「현금 / a favor」 를 묻는다** |
| AFIP | 교환은 **차액이 양수일 때만** 자동 발급 |
| 영수증 없는 반품 | 캐셔가 결정 — 원본 판매 연결 요구 안 함 |
| 운영 적용 | **모든 테스트는 스테이징에서**, 운영은 13시 이후 |

메모리: `favor-is-negative-credito.md`

## 1. 배포 상태

| 저장소 | 운영에 나감 | **미 push (13:03 예약)** |
|---|---|---|
| api-ventago | `f4e0d6f9` 반품 API · 자동상계 · 취소 시 favor 복원 / `7d5ae91b` 가격 해석 순서 | `71ea26d8` 교환(음수 판매 줄) |
| ventago-app | `ede746ea` 반품 다이얼로그 / `84d20a56` 반품 모드 음수 표시 | `ec96e393` 교환 카트 · `1f2e2171` dev 원격 origin |
| 루트 | `e3567fc` 까지 | 포인터 미갱신 |

- 예약 작업 `113cd28c` (CronCreate, 26일 13:03, one-shot): API push → 빌드 확인 → **성공 시에만** 프론트 push → 루트 포인터.
  ⤷ 세션이 닫혔으면 **손으로** 같은 순서로 할 것. **API 가 먼저**다 — 새 프론트가 `items[].isReturn` 을 보낸다.
- 운영에 이미 나간 반품 API(`/sales/devolucion`)는 새 프론트가 **더 이상 부르지 않는다**(교환 흐름으로 대체). 엔드포인트는 남아 있다.

## 2. 구현 요지 (교환 — 미 push 분)

**API** `api-ventago/src/app/sales/`
- `precio-actual.ts` — 반품 단가(부모 행 → 부모 기준가 → 자식). 반품 API 와 교환이 **같은 계산**.
- `sales-create.service.ts`
  - `processSaleItems`: `isReturn` 줄 → 수량 **음수 저장**, 단가 서버 계산·화면값 대조(ERR-DEV-006), 제네릭 거절(007)
  - `applyStockLedger`: **부호 있는** 재고(반품 +). 종전 `Math.abs` 는 반품을 빼 버렸다
  - `assertPagosDeCambio` / `processPaymentMethods`: 합계<0 → 결제 1줄 = 합계, efectivo−(retiro, 카하 없으면 거절 001) 또는 favor−(손님 필수 010, 후크에서 `applyReturnCredit`)
  - `prepareNullify` + modify: **교환 판매 취소·수정 차단**(ERR-DEV-012) — 취소 경로가 전부 `Math.abs`
- `afip/auto-issue.ts`: 합계 ≤ 0 이면 자동 발급 안 함

**프론트** `ventago-app/src/views/homes/`
- `utils/linea-devolucion.ts` — **부호는 여기서만**(표·PagoInline·PaymentSummary·InvoiceAditional·영수증)
- 「Devolver Ropas」 = **줄 모드**(특수모드 아님, 카트 안 비움). 줄에 `esDevolucion: true`
- 차액 ≤ 0 → 결제 패널 대신 빨간 박스 + 「Registrar devolución」 → `DevolucionDialog`(현금 / a favor)
- 반품 줄 카트: 보류·판매 수정 차단, 프로모션 제외(평가엔 qty 0 으로 넘김 — lineIndex 보존)

**검증**: itest `sale-return.itest.ts` 21/21 · 돌연변이 반품 9 + 교환 7 전부 사망 · api jest 85 suites/1280 · app jest 93 suites · 스테이징 HTTP/화면 시나리오 전부.

## 3. 스테이징 — 지금 이 Mac 에서 돌고 있는 것

| 프로세스 | 역할 |
|---|---|
| `ssh -N -L 15432:127.0.0.1:6432 jhkim-server` | 로컬 → 스테이징 pgbouncer |
| `npm run start:dev` (api-ventago, `CRON_ENABLED=false`) | 로컬 API :5002 → `ventago_staging` |
| `next dev -p 3050` | 프론트 (dev) |
| `node <scratchpad>/gate-proxy.js` | :8088 중계(화면+`/api`+소켓), 쿠키 게이트 |
| `cloudflared tunnel --url :8088` | 공개 URL (`*.trycloudflare.com`, 재기동마다 바뀜) |

- 사용자에게 준 링크: `https://interval-gratuit-wayne-nashville.trycloudflare.com/?k=<비밀>` (비밀은 scratchpad `gate.key`)
- 계정: `stg.devolucion@dummy.test` / `Dummy1234` (store 6 admin, **스테이징 DB 에만** 있음)
- Basic Auth 는 앱의 `Authorization: Bearer` 와 충돌해 **쿠키 게이트**로 대체했다.

**스테이징 DB 에 가한 변경**(운영 아님): 빠진 컬럼 13 · 테이블 3(`price_change_*`, `afip_issuer_branches`) ·
제약 3(`chk_sales_activity_type` 에 devuelto 등) 을 운영 정의로 맞춤. 검증 거래·계정이 남아 있다.
⤷ 스테이징 대조는 **컬럼만으로 부족** — CHECK·트리거·함수까지(메모리 `staging-restore-lags-production-schema`).

## 4. 남은 일 / 결정 대기

1. **`stage.coolsistema.com` 상시 스테이징** — 사용자 결정 대기: DNS 처리 주체, 접근 제한 방식.
   (스테이징 DB = 실데이터 복사본. 서버 nginx·certbot·컨테이너·빌드 필요)
2. **교환 판매 취소/수정** — 지금 차단. 부호 있는 역분개(재고·현금·favor)를 만들어야 풀린다.
3. **현금 환불 권한** — 반품 API 는 `stock-movement` 권한(inventory_clerk 포함)으로 현금이 나간다. 판매 취소 환불은 `modificar-venta`. 맞출지 사용자 결정.
4. **온라인 주문 외상**(`online-orders.service` sale_credit 2곳)은 favor 자동 상계를 안 탄다.
5. **운영 반품 1건**(sale 264, store 6, MULLER 180,000 favor) — 활동 행 방식이라 매출 미차감. 사용자: 「그대로 둔다」.
6. 판매 생성의 외상 심사는 **커밋 후 후크**에서만 돈다(종전 구조) — 심사 거절이면 판매만 남고 원장은 self-heal 이 매시간 재시도.
7. `CreateSaleItemDto` 에 `isReturn/priceTypeId` 추가 — Flutter 앱 등 다른 클라이언트는 안 보내므로 영향 없음.

## 5. 이번 세션의 교훈 (메모리 반영됨/후보)

- 스테이징 검증 요청 **전에** main push 해서 운영이 먼저 나갔다 → 이후 규칙: 스테이징 먼저, 운영은 지정 시각.
- 스테이징에서만 드러난 결함: 자식 상품의 **낡은 기준가 행**(40,000 vs 20,000)으로 두 배 적립될 뻔 — 로컬 itest 데이터엔 없던 형태.
- `$RANDOM` 은 `$(...)` 하위 셸마다 같은 값 → 멱등키 충돌로 422. 시험 스크립트 버그였지 서버가 아니었다.
- cmux 검증 창을 닫지 않고 터널을 끄면 사용자 화면에 「Error de conexión」 이 쏟아진다 — 검증 후 창부터 닫을 것.
