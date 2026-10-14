# Phase 108 — Cuenta corriente y vales (minorista / mayorista) en Preferencias › Ventas

작성 2026-10-14 · 상태: **계획 + 목업 — 결정 대기, 구현 전**
목업: `mockup.html` / `mockup.png` (같은 폴더)

## 사용자 요청 (원문)
> 사실은 외상 판매를 하느냐 아닌가로 봐야 해. 그리고 소매상이냐 도매상이냐도 구별해서 해야 하는거지.
> admin, configuration, preferencias 셋팅, venta 부분에서 이것을 셋팅할 수 있으면 좋을 것 같아.
> 거기 inventario 부분에
> permitir venta x crédito (sin pagar, llevar ropas, control de favor, seña, deuda pago) … 체크하면 이를 허용하기
> inhabilitado 상태면 완전히 그 부분을 숨기고.
> permitir control de vale (vale salida, vale entrada) - minorista 인 경우에 동일하게 처리하는거지..
> minorista 의 경우 돈을 돌려줘야 할 경우 티켓(명함)에 도장을 찍고 금액을 적어서 다음번 compra 때 이 매장에서만
> 현금처럼 사용하는거지.. vale salida 는 이것을 발행했다는 것이고. vale entrada 는 이것이 들어와서 현금 대신 받았다는 것

## 왜 Phase 107 과 다른가
Phase 107 은 **결제수단 하나하나**를 숨긴다(Métodos globales). 그런데 외상은 결제수단 하나가 아니라 **업무 방식**이다 —
crédito · favor · seña · 빚 회수 · Cuentas corrientes 메뉴 · 부채 보고서가 한 묶음이다. 107 로는 crédito 를 숨겨도
favor 자동 상계가 남는 등 묶음이 갈라졌다(107 의 알려진 한계). 108 은 **묶음 스위치 하나**를 둔다.

- 판정 순서: **매장 스위치(108) → 결제수단 숨김(107)**. 스위치가 꺼지면 묶음 전체가 꺼진다.
  스위치가 켜져 있을 때만 107 의 개별 숨김이 의미가 있다.
- 진실은 **한 곳**: `store_configs.use_cuenta_corriente`. 스위치를 끌 때 107 의 숨김 행을 같이 써 넣지 않는다
  (두 곳이 같은 사실을 들면 갈라진다 — 메모리 edit-target-needs-single-source).

## 실측 (운영, 2026-10-14)
- 최근 90일 credit_ledger 사용 매장: **coolsistema(6) · NOIX(19, sale_credit 14) · Shaple(26, sale_credit 72 · payment_in 93)**.
  → `use_cuenta_corriente` 기본값은 **true** 여야 한다. false 로 시작하면 NOIX·Shaple 의 외상이 배포 순간 사라진다.
- `payment_methods.type` 에 이미 `minorista | mayorista | minorista,mayorista` 가 있다(54 / 6 / 46행).
  **지금은 아무 판정에도 안 쓰인다.** 108 은 이것을 건드리지 않는다(D2).
- 「vale」 개념은 코드·DB 에 없다(신규).

## 화면 (목업 1)
`/configuracion/preferencias` › Ventas 탭. 「Inventario」 바로 아래에 새 섹션 **«Cobro y crédito al cliente»**.
(요청은 「inventario 부분에」 — 같은 탭 같은 흐름이되, 재고와 무관한 설정이라 제목만 분리했다. D1)

| 항목 | 표현 (es-AR) | 기본값 |
|---|---|---|
| Tipo de venta de la tienda | Minorista / Mayorista / Minorista y mayorista | 미설정 → «Minorista y mayorista» |
| Cuenta corriente | **Habilitar cuenta corriente de clientes (venta a crédito)** — Venta a crédito (fiado) · Saldo a favor · Seña / reserva · Cobro de deudas | **ON** (기존 동작 유지) |
| Vales | **Habilitar vales de compra (vale emitido / vale recibido)** | **OFF** |

용어: 아르헨티나 업무 용어로 외상 장부는 **«cuenta corriente»**, 외상 판매는 **«venta a crédito / fiado»**.
vale salida/entrada 는 화면에 **«Vale emitido (salida)» / «Vale recibido (entrada)»** 로 둘 다 쓴다(현장 용어 유지).

## A. Cuenta corriente 스위치

### OFF 일 때 숨는 것 (전수 — 구현 전 다시 grep 으로 셀 것)
| 자리 | 파일 (현재) |
|---|---|
| POS 결제 Crédito 줄 · PgUp | `views/homes/components/ProductList/components/PagoInline.tsx`, `InvoiceAditional.tsx`, `PaymentSummaryModal` |
| 반품 «Dejar a favor» | `DevolucionDialog.tsx` |
| «Reservar Seña» · 고객 원장 | `views/cuentas-corrientes/ClientLedgerView.tsx` |
| 메뉴 «Cuentas corrientes» | `navigation/menuRegistry.ts` (`/cuentas-corrientes`) |
| 판매 화면 고객 잔액 표시 | `views/homes/components/InfoClient.tsx` |
| Ventas online 수금 | `views/ventas-online/components/CobroModal.tsx` |
| 보고서 부채 섹션 | reports-v2 (deuda / cobranzas) |
| Flutter 앱 | `/api/reports/*` 를 부르는 두 앱 — 메모리 reports-api-has-flutter-consumers |

프론트 판정은 기존 `funcionesDePago()` (`homes/utils/funciones-de-pago.ts`) 에 스위치를 한 인자로 더해 **한 함수**에서 낸다
— 화면마다 따로 `if` 를 두지 않는다.

### 서버가 거절해야 하는 것 (프론트 플래그는 보안 경계가 아니다)
- 판매 생성: crédito 결제 줄 / favor 자동 상계(`sales-create.service.ts` 의 favor_apply) / seña 생성 → 400 «La tienda no usa cuenta corriente».
- 반품: favor_in 경로(`sale-return`) → 거절.
- ★ 이 거절이 **107 의 한계(favor 숨겨도 자동 상계)** 를 스위치 OFF 경우에 한해 해소한다.

### 이미 열려 있는 잔액 (목업 2)
끌 때 확인창에 **빚 있는 고객 수·금액, a favor 잔액, 미수령 seña** 를 보여 준다.
권장안: **신규만 막고 회수는 남긴다** — 잔액이 0 이 될 때까지 Cuentas corrientes 는 «sólo cobro» 모드로 보인다.
(빚을 숨기면 받을 돈을 잊는다. 끄는 순간 회수 화면이 사라지면 그게 돈 사고다.) → **D3**

## B. Vales

### 개념
- 손님 등록 **불필요** (무기명). 매장 단위, 이 매장 안에서만 현금처럼 쓴다.
- **Vale emitido (salida)**: 반품·교환 차액을 돈 대신 vale 로 준다. **카하에서 돈이 안 나간다.** 매장의 부채가 생긴다.
- **Vale recibido (entrada)**: 결제수단 «Vale». 번호로 조회 → 잔액만큼 결제. **카하에 돈이 안 들어온다**(서랍 대조에서 제외).
- 종이: 명함에 도장 + 금액 손글씨 그대로 쓴다. 시스템은 **번호를 발급**하고 그 번호를 명함에 적는다. 열감지 인쇄는 선택(목업 4).

### 데이터 (신규 테이블 — expand only)
```
vales            id, store_id, branch_id, numero (매장별 순번, UNIQUE(store_id, numero)),
                 monto, saldo, estado ('vigente'|'usado'|'anulado'|'vencido'),
                 origen ('devolucion'|'manual'), origen_sale_id, vence_at, user_id, nota, created_at
vale_movimientos id, vale_id, store_id, tipo ('emision'|'canje'|'anulacion'), monto,
                 sale_id, branch_id, cash_register_id, user_id, created_at
```
- 잔액은 `vale_movimientos` 합이 권위, `vales.saldo` 는 같은 트랜잭션에서 맞춘다(재고 원장과 같은 형태).
- 같은 vale 의 이중 사용 방지: 캔제 시 `SELECT … FOR UPDATE` + `saldo >= monto` 확인 (POS 두 대가 같은 번호를 동시에 받는 경우).
- 결제수단 `vale` 은 Phase 107 의 **잠금 목록(이름 고정)** 에 넣는다.
- store_configs: `use_cuenta_corriente boolean NOT NULL DEFAULT true`, `use_vales boolean NOT NULL DEFAULT false`,
  `tipo_venta varchar(24) NULL` — 모두 additive. `update-flag` 화이트리스트에 추가.

### 화면
- 반품 다이얼로그에 **«Dar vale»** (목업 4) — 손님이 없어도 된다(지금 손님 없으면 현금뿐인 자리).
- 결제 화면에 **«Vale Nº»** 입력 (목업 5). 사용된·anulado·vencido 번호는 어디서 언제 썼는지와 함께 거절.
- **Ventas › Vales** 목록 (목업 6): 미사용 vale 합계 = 매장 부채, 기한 임박, 수동 발급·anular(권한).
- 보고서: vale 로 돌려준 반품도 Phase 105 «Devoluciones» 줄에 들어간다. vale 결제는 **매출이 아니라 결제수단**이다
  (돈 대신 받은 것 — 매출은 판매 시점에 이미 잡혔다). 카하 정산식 9곳(메모리 caja-balance-formula-duplicated-9-places)에서
  vale 는 현금이 아님을 확인.

## 결정이 필요한 것
| # | 질문 | 권장 |
|---|---|---|
| D1 | 위치 — Inventario 섹션 **안**에 넣을지, 바로 아래 **별도 섹션**(«Cobro y crédito al cliente»)으로 둘지 | 별도 섹션 (같은 탭) |
| D2 | «Tipo de venta» 가 무엇을 하는가 — (a) 추천만 (b) 스위치 기본값 결정 (c) 결제수단 `type` 으로 POS 목록까지 거른다 | (a) 추천만. (c) 는 그 매장 결제수단 106행의 type 이 지금 맞는지부터 봐야 한다 |
| D3 | 외상 OFF 시 기존 빚 — (a) 회수는 남김 (b) 잔액 있으면 끌 수 없음 (c) 전부 숨김 | (a) |
| D4 | vale 사용 범위 — 매장 전 지점 / 발급 지점만 | 전 지점 («이 매장에서만») |
| D5 | vale 가 구매액보다 클 때 — (a) 남은 잔액을 같은 vale 에 유지 (b) 새 vale 재발급 (c) 차액 현금 반환 금지 | (a) — 명함에 잔액을 고쳐 적는다 |
| D6 | 유효기간 — 없음 / 기본 N일(매장 설정) | 기본 90일, 매장에서 변경 |
| D7 | vale 끄기 시 미사용 vale — (a) 받기는 계속 (b) 바로 막음 | (a) 손님 손에 있는 돈이다 |
| D8 | 「Dar vale」 를 cuenta corriente 가 켜진 매장(손님 있음)에서도 보일지 | 둘 다 켜져 있으면 둘 다 보인다 |

## 작업 순서 (결정 후)
1. **108-01 마이그레이션** — store_configs 3컬럼 + vales/vale_movimientos (로컬 5432 + 운영 5434 동시, 운영은 승인 후). intel 재생성.
2. **108-02 API 스위치** — update-flag 화이트리스트, `/store-config` 응답, 판매·반품·seña 서버 거절, favor 자동 상계 차단. itest.
3. **108-03 프론트 스위치** — 설정 섹션, `funcionesDePago` 확장, 숨김 자리 전수, 메뉴, 끌 때 확인창(잔액 조회 API).
4. **108-04 Vales API** — 발급(반품 경로·수동)·조회·캔제(FOR UPDATE)·anular·목록, 결제수단 `vale` 시드(전 매장, 숨김 기본?), 카하 정산식 확인.
5. **108-05 Vales 프론트** — 반품 «Dar vale», 결제 «Vale Nº», 목록 화면, 열감지 인쇄(선택, 중복 인쇄 경로 전수 확인 후).
6. **108-06 보고서·Flutter 확인** — Devoluciones 줄, 결제수단 집계, `/api/reports/*` 소비자.
7. CODEX 자문 → 배포(api → app 순서: 새 컬럼이 기본값 true 라 옛 프론트도 안전) → cmux 로 coolsistema(6) 에서 확인.

## 위험
- 기본값 false 실수 → NOIX·Shaple 외상 증발. 마이그레이션 시험에 「기존 매장 = true」 단언.
- 숨김 자리를 하나라도 빠뜨리면 꺼진 기능이 버튼으로 남는다(막다른 CTA) → 서버 거절이 마지막 방어선.
- vale 이중 사용(동시 POS) → 행 잠금 + 시험.
- 카하 정산식에 vale 이 현금처럼 섞이면 서랍 차이가 난다.
