# Design Spec — Factura Electrónica (AFIP) 이식 into Ventago

> 작성일: 2026-07-09 · 상태: 검토 대기
> 출처: CoolSyncro `src/main/afip/` 모듈 정독 + 사용자 브레인스토밍 결정
> 대상: `api-ventago` (NestJS) + `ventago-app` (Next.js) — 멀티테넌트 POS/ERP

## 0. 목표 (WHAT)

CoolSyncro(Electron 싱크 에이전트)에 이미 구현된 **AFIP 전자 영수증(Factura Electrónica) 발급 기능**을 Ventago 백엔드/프론트로 이식한다. AFIP 통신은 **ws 게이트웨이 방식(`invoice.coolsistema.com` REST)** 을 유지하되, 나중에 SOAP 직접 방식으로 교체 가능한 provider 인터페이스 경계를 둔다. 현지 관행을 반영해 **부분 발급(발급 % 선택)** 을 1급 기능으로 포함한다.

성공 기준(요약):
- FE 활성 매장에서 판매건에 대해 유효한 CAE를 발급받고, QR+CAE 포함 영수증(감열/A4/디지털)을 출력한다.
- 발행자 IVA 상태(RI/Monotributo)에 따라 comprobante 종류(A/B/C/M + NC/ND)가 자동 선택된다.
- 발급 시 %를 선택하면 품목 수량은 유지되고 금액만 스케일되어 AFIP에 축소 금액이 보고된다.
- 실제 판매액(`sales`)과 발급액(`afip_vouchers`)이 분리 저장되어 "실판매 vs 발급" 추적이 가능하다.

## 0.1 배경 — AFIP 발급 메커니즘 (설계 전제)

AFIP WSFEv1 `FECAESolicitar`는 **금액 총계와 식별 정보만** 전송한다 — **개별 품목(detalle)은 AFIP로 가지 않는다.** 따라서:
- $10,000 판매를 70%로 발급하면 AFIP에는 **$7,000짜리 정상 comprobante**만 존재한다. AFIP는 실판매 $10,000을 모른다.
- 출력 영수증의 품목 라인은 우리가 렌더링하는 표현일 뿐(수량 유지 + 단가 스케일). CAE/QR은 총액 $7,000을 담는다.
- IVA 채무·CITI 월보고 모두 발급액($7,000) 기준.
- 미발급분의 세무·법적 처리는 매장 운영자 책임 영역. 소프트웨어는 "발급할 금액을 선택해 유효한 comprobante를 만드는" 기능만 제공한다.

## 0.2 확정된 결정 (사용자 승인)

| # | 결정 | 값 |
|---|---|---|
| D1 | 전송 방식 | **ws 게이트웨이(1차)** + provider 스왑 경계로 soap 나중 전환 |
| D2 | 발급 트리거 | **둘 다** — 수동 목록 발급 + POS 자동 발급(매장별 `afip_auto_issue`) |
| D3 | 발행자·PV 설정 저장 | 신규 `afip_issuers` 테이블 (parametros 대체) |
| D4 | CAE 저장 | `sales` 요약 컬럼 + 신규 `afip_vouchers` 로그 테이블 |
| D5 | comprobante 종류 | 발행자×수신자 IVA 자동 선택. RI→A/B/M, **Monotributo→C 전용**, +NC/ND |
| D6 | 영수증 출력 | **감열지(기본)** + A4 PDF + 디지털(WhatsApp/이메일), 발급 시 선택 |
| D7 | 게이트웨이 자격 | 인증서는 게이트웨이 보관. Ventago는 매장별 `{cuit, cool_user, PV}` 저장. **coolUser는 admin UI 관리** |
| D8 | 적용 매장 | `store_configs.use_factura_electronica` 플래그 on 매장만 |
| D9 | 부분 발급 | 발급 % 선택 → 수량 유지·금액 스케일 → 검토 후 전송 |
| D10 | 실패 알림 | **Ventago 토스트**(인라인 Alert + prominent 토스트). Telegram 미사용 |

## 1. 아키텍처

### 1.1 백엔드 — 신규 모듈 `api-ventago/src/app/afip/`

```
afip/
├── afip.module.ts
├── afip.controller.ts            # REST 엔드포인트 (§4)
├── afip-issuer.service.ts        # 매장/PV별 발행자 설정 로드 + effective config 병합
├── afip-voucher.service.ts       # 발급 오케스트레이션 (CoolSyncro cae-issuer 대응)
├── nota-credito.service.ts
├── nota-debito.service.ts
├── partial-invoice.ts            # 부분 발급 스케일 계산 (순수 함수, §6)
├── code-maps.ts                  # tipo/IVA/문서 매핑 — 이식 + C 계열 추가 (§5)
├── qr-builder.ts                 # AFIP QR 규격 (RG 4892) — 거의 그대로 이식
├── providers/
│   ├── cae-provider.factory.ts   # selectCaeProvider seam (ws | soap)
│   ├── provider.interface.ts     # issueCae/getStatus/getLastVoucher/getVoucherByNumber
│   ├── rest-gateway.provider.ts  # ws — invoice.coolsistema.com (1차 구현)
│   └── soap-direct.provider.ts   # soap — 후속 (인터페이스만 확보, throw NotImplemented)
├── pdf/
│   ├── a4-generator.ts           # pdfkit + qrcode (A4 comprobante)
│   └── thermal-generator.ts      # pdfkit 80mm (감열지) — 또는 print-agent ESC/POS 경로
└── models/
    ├── afip-issuer.model.ts
    └── afip-voucher.model.ts
```

**이식 원칙:** 순수 로직(`code-maps`, `qr-builder`, voucher 계약, PDF 렌더)은 CoolSyncro에서 거의 그대로 가져온다(axios/pdfkit/qrcode 기반, 프레임워크 무관). Electron IPC/`config.json`/raw-`pg` 부분만 NestJS(컨트롤러/`ConfigService`/Sequelize)로 교체한다.

**Provider 계약** (스왑 경계):
```ts
interface CaeProvider {
  issueCae(req: VoucherRequest): Promise<{ cae; caeDate; number; total; error?; ambiguous? }>;
  getStatus(): Promise<object | null>;
  getLastVoucher(pto: number, tipo): Promise<{ number } | null>;
  getVoucherByNumber(pto, tipo, n): Promise<object | null>;
}
```
`cae-provider.factory.ts`가 `store_configs.afip_provider`('ws'|'soap')로 구현체를 선택한다. **'soap'로 정확히 지정된 경우에만** 직접 모드, 미지정/오타는 ws로 안전 폴백(CoolSyncro 규칙 유지).

### 1.2 프론트엔드

- 신규 페이지 `ventago-app/src/pages/facturacion/` (2패널 목록 + 발급 모달, §7)
- admin `configuracion` 하위 **발행자(afip_issuers) CRUD** 서브뷰 (coolUser 포함)
- POS 판매 완료 화면 `Facturar` 버튼(자동 매장은 자동, 수동 매장은 모달)
- SWR 훅: `useAfipIssuers`, `useAfipPendientes`, `useAfipEmitidas(date)`

### 1.3 멀티테넌트·pool 규약

- 모든 쿼리에 `store_id` 격리.
- **게이트웨이 호출은 DB 커넥션 밖에서** 실행(조회→반환→호출→새 커넥션 저장). pool 낭비 금지 (min=10/max=80 유지).
- 발행자 파라미터는 발급 시점 조회(캐싱 없음 — 충분).

## 2. 데이터 모델 (Sequelize, `underscored: true` → snake_case, additive)

### 2.1 신규 `afip_issuers` — 매장/PV별 발행자

| 컬럼 | 타입 | 비고 |
|---|---|---|
| id | serial PK | |
| store_id | int FK→stores | |
| punto_venta | int | PV 번호 (예: 5) |
| cuit | varchar(13) | 발행자 CUIT |
| cool_user | varchar(100) | 게이트웨이 인증서 폴더 키 (admin 관리) |
| iva_condition | varchar(10) | 'RI' \| 'MONO' \| 'EXENTO' — comprobante 자동선택 근거 |
| razon_social | varchar(200) | 영수증 출력용 |
| razon_social_l2 | varchar(200) | nullable |
| domicilio | varchar(250) | 영수증 출력용 |
| ingresos_brutos | varchar(50) | 영수증 출력용 |
| inicio_actividad | varchar(20) | DD/MM/YYYY 문자열, 영수증 전용 |
| telefono | varchar(50) | 영수증 출력용 |

UNIQUE(store_id, punto_venta). CAE 발행에 실제 필요한 값은 **cuit + punto_venta**(+ cool_user)뿐. 나머지는 영수증/PDF 출력용.

### 2.2 신규 `afip_vouchers` — CAE 발급 로그

| 컬럼 | 타입 | 비고 |
|---|---|---|
| id | serial PK | |
| store_id | int FK | |
| sale_id | int FK→sales | 원본 판매 |
| cae | varchar(20) | |
| cae_vto | date | 벤시미엔토 CAE |
| punto_venta | int | |
| afip_number | int | comprobante 번호 |
| tipo_comprobante | int | INVOICE_TYPE 코드 (A=1,B=6,C=11,M=51,NC/ND…) |
| doc_tipo | int | 80/86/96/99 |
| doc_nro | varchar(20) | 수신자 문서 |
| imp_total | numeric(15,2) | **발급액** (= 실판매 × invoice_pct) |
| neto_gravado | numeric(15,2) | CITI 대비 IVA 분해 |
| iva_liquidado | numeric(15,2) | |
| iva_alicuota | int | |
| invoice_pct | numeric(5,2) | **발급 비율** (100=전액) |
| nota_credito | boolean | default false |
| nota_debito | boolean | default false |
| cae_anterior | varchar(20) | NC/ND 원본 CAE 참조 |
| created_at | timestamp | |

### 2.3 `sales` 컬럼 추가 (요약 — 빠른 조회)

`cae varchar(20)`, `cae_vto date`, `punto_venta int`, `afip_number int`, `tipo_comprobante int`, `afip_status varchar(15)` — 값: `no`(대기/Pendientes 대상) · `en_progreso` · `facturado` · `verificar`(ambiguous) · `cancelado`.

> `sales.total`(실판매액)은 **불변**. 발급액은 `afip_vouchers.imp_total`에만 기록.

### 2.4 `store_configs` 플래그 추가

`use_factura_electronica boolean default false`, `afip_provider varchar(5) default 'ws'`, `afip_production boolean default false`, `afip_auto_issue boolean default false`, `afip_default_pct numeric(5,2) default 100`.

### 2.5 마이그레이션

`api-ventago/migrations/`에 additive SQL 파일. 운영 PG10 호환(`ADD COLUMN IF NOT EXISTS` 대신 information_schema 체크 또는 PG10 지원 문법 확인). 기존 데이터 보존. Sequelize sync 아닌 명시적 마이그레이션.

## 3. 발급 흐름 (D2)

### 3.1 수동 (기본)

1. Facturación 페이지 좌측 Pendientes = `sales WHERE afip_status='no' AND store_id=?`.
2. `[Facturar]` 클릭 → **부분 발급 모달**(§6) 오픈: % 선택 → 스케일 미리보기 → 출력 방식 선택.
3. `[Confirmar y enviar]` → `POST /afip/vouchers { saleId, pv, invoicePct, output }`.
4. 백엔드 오케스트레이션(§3.3).

### 3.2 자동 (매장별)

- `afip_auto_issue=true` 매장은 판매 완료 훅(`sales-create.service`)에서 발급 큐 트리거.
- **프롬프트 없이** `store_configs.afip_default_pct` 적용, 출력=매장 기본(감열).
- ⚠️ 자동 발급은 "검토 후 전송" 원칙(D9)과 상충 → 자동 매장은 검토 생략을 명시적으로 수용하는 것. **검토가 필수인 매장은 자동을 끄고 수동 사용.** (스펙 검토 시 최종 확인 항목)

### 3.3 오케스트레이션 (공통, `afip-voucher.service`)

```
1. sale + items + store_client(수신자) 로드
2. issuer = afip-issuer.service.load(storeId, pv)   # cuit, cool_user, iva_condition …
3. tipo = decideComprobante(issuer.iva_condition, receptor)   # §5
4. scaled = applyPartial(items, total, invoicePct)            # §6
5. voucherRequest 빌드 { point:pv, type:tipo, docType, docNro, amount:neto, iva, asoc? }
6. sale.afip_status = 'en_progreso'  (원자적 클레임)
7. provider.issueCae(voucherRequest)   # ← DB 커넥션 밖에서
8a. 성공 → afip_vouchers INSERT + sale(cae,…,afip_status='facturado') UPDATE
    → qr-builder → PDF/thermal → output(§ E)
8b. ambiguous(타임아웃/5xx) → sale.afip_status='verificar' (재발급 금지, day-close 복구 후속)
8c. fatal(4xx) → sale.afip_status='no' 복구 + 토스트 에러(사유 전면 노출)
```
인쇄 실패는 CAE를 무효화하지 않음 — 재인쇄는 Emitidas 측으로 분리.

### 3.4 취소 / NC / ND

- **Cancelar**: `sale.afip_status='cancelado'` (Pendientes에서 제외).
- **Nota de Crédito**: Emitidas의 발급건 → `emitirNotaCredito(voucherId, items?)`. 원본 CAE `asoc` 참조, `creditNoteTypeOf(tipo)`(NCA/NCB/NCC/NCM). 부분 NC 지원(`items`). 이미 NC 있으면 거부(`cae_anterior` 중복 체크).
- **Nota de Débito**: 잘못 발급한 NC 되돌리기 등. NC 참조 `asoc`.

## 4. REST 엔드포인트 (`afip.controller.ts`)

CoolSyncro 13 IPC 채널 대응. 전부 `@Auth` + `store_id` 소유권 검증.

| Method Path | 기능 |
|---|---|
| GET `/afip/issuers` | 매장 발행자/PV 목록 |
| POST/PUT/DELETE `/afip/issuers` | 발행자 CRUD (admin, coolUser 포함) |
| GET `/afip/pendientes` | 발급 대기 판매 (afip_status='no') |
| GET `/afip/emitidas?date=` | 발급 완료 (날짜별) |
| GET `/afip/vouchers/:saleId/preview?pct=` | 부분 발급 스케일 미리보기 |
| POST `/afip/vouchers` | 발급 { saleId, pv, invoicePct, output } |
| POST `/afip/vouchers/:id/cancel` | 취소 |
| POST `/afip/vouchers/:id/nota-credito` | NC { items? } |
| POST `/afip/vouchers/:id/nota-debito` | ND |
| POST `/afip/vouchers/:id/reprint` | 재인쇄(감열) |
| GET `/afip/vouchers/:id/pdf` | A4 PDF |
| POST `/afip/vouchers/:id/send` | 디지털 전송(WhatsApp/이메일) |
| GET `/afip/status` | 게이트웨이/AFIP 상태 |

후속: `POST /afip/citi-ventas`(월보고), `POST /afip/day-close`(마감/복구).

## 5. Comprobante 자동 선택 (D5) — `code-maps.ts`

CoolSyncro `code-maps.js` 이식 + **발행자 IVA 조건 분기 + C 계열 추가**.

| 발행자 iva_condition | 수신자 조건 | comprobante |
|---|---|---|
| RI | RI/CUIT (11자리 검증) | **A** (위험 플래그 시 M) |
| RI | 소비자·Monotributo·Exento | **B** |
| RI | 수출(exterior) | E (후속) |
| **MONO** | **모든 수신자** | **C** |
| MONO | 수출 | E (후속) |

- 신규 코드: `INVOICE_TYPE.C=11, NCC=13, NDC=12`.
- `decideComprobante(issuerIva, receptor)`: MONO → 항상 C. RI → 기존 `decideInvoiceType(resiva, …)` 로직.
- `documentType`: A/M → CUIT 필수. DNI 8자리→96, CUIT 11자리→80, 빈값→99(FINAL_CONSUMER).
- `CondicionIVAReceptorId`(RG 5616) 매핑 유지.

## 6. 부분 발급 (D9) — `partial-invoice.ts`

**순수 함수** `applyPartial(items, realTotal, pct) → { lines, impTotal, neto, iva }`:
- `factor = pct/100`.
- 각 라인 `cantidad` **불변**, `precioUnitario × factor` → 라인 소계 = 원본 × factor.
- `impTotal = round(realTotal × factor, 2)`. **반올림 잔차는 마지막 라인에서 보정**(Σ라인 = impTotal 보장).
- neto/iva = tipo 규칙으로 impTotal에서 역산(`computeNetoIva`, 정수-센트 연산으로 Java BigDecimal DOWN 미러).

**미리보기 계약**: `GET /afip/vouchers/:saleId/preview?pct=70` → 모달이 스케일된 라인·총계·tipo 뱃지를 렌더. 사용자 확정 시 동일 pct로 `POST`.

**자동 발급**은 `afip_default_pct` 사용(프롬프트 없음).

**저장**: `afip_vouchers.imp_total`(축소액) + `invoice_pct`. `sales.total`은 실판매액 불변.

## 7. UI (D6, D9)

### 7.1 Facturación 페이지 — 2패널

```
┌─ Facturación electrónica ───── [PV: 00005 ▼] [⚙ Configuración] ─┐
│  ┌── Pendientes ──────────┐   ┌── Emitidas ‹ 2026-07-09 › ─────┐│
│  │ [B] Consumidor Final   │   │ Hora Tipo PV Nº Cliente Monto ..││
│  │ $10.000  T1·#4821      │   │ 14:02 B 5 00012 C.Final $7.000 ││
│  │ [Facturar] [Cancelar]  │   │   CAE 7514… Vto 07/19 [Nota Cr]││
│  └────────────────────────┘   └────────────────────────────────┘│
└──────────────────────────────────────────────────────────────────┘
```
- 좌 Pendientes(카드): tipo 뱃지(A파랑/B보라/C초록/M주황/E청록), 고객·**실판매액**·터미널. `[Facturar]`/`[Cancelar]`.
- 우 Emitidas(테이블): Hora·Tipo·PV·Nº·Cliente·Doc·**발급액**·CAE·Vto·액션(NC/ND, 재인쇄, PDF, 전송).
- 상단 PV 드롭다운(멀티 PV), ⚙ Configuración(발행자 CRUD).

### 7.2 부분 발급 모달 (§6)

```
Facturar venta #4821
Venta real: 3 ítems · $10.000
% a facturar: [100][70][50][__%]
▸ Vista previa: Tipo B · 3 ítems(수량 유지) · 단가 스케일 · TOTAL $7.000 (neto/IVA)
Salida: (●)Térmica ( )PDF A4 ( )WhatsApp
[Cancelar] [Confirmar y enviar →]
```

### 7.3 발행자 Configuración (admin)

`afip_issuers` CRUD 폼: PV, CUIT, **iva_condition(RI/MONO/EXENTO)**, cool_user, razón social, domicilio, ingresos brutos, inicio actividad, teléfono. IDOR 가드(store_id 소유권).

### 7.4 프론트 규약

- MUI 5 + 다크네이비/골드(sketch-findings-ace-online). 코드 스플리팅 `next/dynamic`. SWR 5분 dedup. `apiConnector.remove()`. ESLint(newline-before-return 등) 준수.
- 실패 = 인라인 Alert + prominent 토스트(사유 전면 노출, feedback_error_visibility).

## 8. 출력/전달 (D6) — `pdf/` + print-agent

- **감열지(기본)**: `thermal-generator`(80mm, pdfkit+qrcode) 또는 기존 print-agent ESC/POS 파이프라인(`emitPrintInvoice`) 재사용. → **결정 필요**(스펙 검토): pdfkit-80mm-PDF를 print-agent로 보낼지 vs print-agent가 직접 ESC/POS 렌더할지. AFIP QR은 이미지로 렌더 필요하므로 pdfkit-PDF 경로가 안전.
- **A4 PDF**: `a4-generator` → 브라우저 뷰/다운로드/재인쇄.
- **디지털**: PDF 링크를 WhatsApp/이메일(Ventago CRM Phase 34 활용).

## 9. 범위 / 단계

**1차 슬라이스 (이 스펙):**
- ws 게이트웨이 provider + factory seam
- afip_issuers / afip_vouchers / sales·store_configs 마이그레이션
- 발급 오케스트레이션(수동+자동), comprobante 자동선택(A/B/C/M + NC/ND)
- 부분 발급(%) + 미리보기 + 검토 모달
- 2패널 UI + 발행자 Configuración
- 감열/A4 출력, 디지털 전송

**후속 (범위 밖):**
- CITI Ventas 월보고(RG 3685 고정폭 파일) — CoolSyncro `citi-ventas.js` 이식
- soap 직접 provider(WSAA cert + WSFEv1) — provider 인터페이스에 채워 넣기
- Factura E(수출, WSFEX)
- day-close 자동 복구(`verificar`/`en_progreso` 대사)
- 디지털 전송 템플릿 고도화

## 10. 확인 필요 (스펙 검토 시)

1. 자동 발급(§3.2)과 "검토 후 전송"(D9) 상충 — 자동 매장은 검토 생략 수용으로 확정?
2. 감열 출력 경로 — pdfkit-80mm-PDF → print-agent vs print-agent 직접 ESC/POS(§8)?
3. 운영 PG10 마이그레이션 문법 호환(§2.5) 최종 검증.
4. 게이트웨이가 부분 발급 금액을 그대로 수용하는지(voucherRequest.amount 축소값 전달) — CoolSyncro rest-gateway는 amount를 그대로 전송하므로 호환 예상, E2E 확인 필요.

## 11. 재사용 맵 (CoolSyncro → Ventago)

| CoolSyncro | Ventago | 변환 |
|---|---|---|
| `cae-provider.js` | `providers/cae-provider.factory.ts` | 거의 그대로 |
| `rest-gateway-provider.js` | `providers/rest-gateway.provider.ts` | axios 유지, config→store_configs |
| `code-maps.js` | `code-maps.ts` | +C 계열, 발행자 IVA 분기 |
| `qr-builder.js` | `qr-builder.ts` | 그대로 |
| `cae-issuer.js` | `afip-voucher.service.ts` | IPC→서비스, raw pg→Sequelize |
| `nota-credito.js`/`nota-debito.js` | 동명 service | 동일 |
| `issuer-parametros.js` | `afip-issuer.service.ts` | parametros→afip_issuers |
| `factura-repository.js` | Sequelize 모델/서비스 | fistmpcab/fventas→sales/afip_vouchers |
| `pdf/generator.js`·`thermal-generator.js` | `pdf/*.ts` | pdfkit 유지 |
| `afip-ipc.js` | `afip.controller.ts` | IPC→REST DTO |
| `soap-direct-provider`/`wsaa-auth`/`wsfe-client` | `providers/soap-direct.provider.ts` | 후속 |
