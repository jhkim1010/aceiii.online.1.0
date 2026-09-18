# Phase 57 보강 — 발행자 구조 + **cool-invoice 게이트웨이 이탈**

**작성:** 2026-09-18
**보강 대상:** `57-SPEC.md` (R1~R7, 2026-07-19 locked) → **R8~R12 추가**
**R1~R7 은 취소하지 않는다** — 출력(감열 ESC/POS·A4 PDF·NC/ND)은 이 보강과 직교한다.

---

## 0. 사용자 요건 (2026-09-18)

| # | 요건 | 원문 |
|---|---|---|
| **U1** | 매장마다 다른 CUIT | "각 매장은 (특별한 경우를 제외하면) 다른 cuit을 사용할것" |
| **U2** | 한 매장이 여러 CUIT 으로 발급 | "한 매장은 여러개의 cuit으로 영수증을 발급할 수 있어" |
| **U3** | 환경 선택 + 시험 7일 상한 | "Homologacion 과 producción 모드를 선택하게 하지만 일주일 이상은 테스트 모드를 돌리지 않게" |
| **U4** | 셋업 화면 | "여러 매장이 같은 cuit… 한 매장의 여러 지점들이 각각 다른 punto de venta… admin, configuración 페이지에서 셋업할 수 있어야" |
| **U5** | **게이트웨이 이탈** | "Soap, producción 모드에서 cool invoice 게이트웨이를 전혀 사용하지 않는 것이 목표 / 게이트웨이가 하던 일을 내가 다 하는 것" |
| **U6** ★ | **발급 시 CUIT 선택** | "1개 매장의 1 지점에서 여러 cuit중에서 하나를 선택해서 발급할 수 있어야 해" |

★ **U5 가 이 보강의 축이다.** U1~U4 는 그 위에서 정리되는 구조이고,
  U5 는 «지금 우리가 남의 시스템에 얹혀 있는 자리» 를 하나씩 떼어내는 일이다.

★ U1 과 U2 는 모순이 아니다. **CUIT 의 소유는 매장 단위(U1)** 다.

★★ **U6 이 U2 의 뜻을 확정한다 (2026-09-18 정정).** 처음에 나는 U2 를 「지점마다 CUIT
   하나씩」으로 읽고 R8 을 그렇게 설계했다. **틀렸다.** 사용자가 원하는 것은
   **한 지점에서 여러 CUIT 중 하나를 고르는 것**이다. 즉 발급 단위는 지점이 아니라
   **발급 건(件)** 이고, 지점은 **기본값을 정할 뿐**이다.
   → 그래서 `UNIQUE (store_id, branch_id)` 는 요건과 정면으로 충돌한다 (§4 ⑨).

---

## 1. 실측 ① — 데이터 (운영 5434, 2026-09-18)

```
afip_issuers (2행)
 id store branch branch명      cuit          PV  cool_user        iva inv_type inv_sucursal
  1   6      6   coolsistema  20950928434    4  coolsistema      RI  A        NULL
  2   9     14   JEFE         20950928434    1  coolsyncrohomo1  RI  A        NULL

store_configs   store 6: afip_provider=soap, afip_production=true   → producción
                store 9: afip_provider=soap, afip_production=false  → homologación

지점 수          store 6 = 3 (발행자 1개 → 지점 2개는 발행자 없음)
                store 9 = 2 (발행자 1개)

afip_certificados   0행  ← 레지스트리가 비어 있다. 인증서 실체는 파일시스템뿐
afip_vouchers       store 6 = 19건(유효, 번호 69~124) · store 9 = 2건(homo, 세무상 무효)
```

★ **정정(2026-09-18 A6 실측): 결번은 37개가 아니라 5개다.** 처음에 69~124 를 한 덩어리로
  세어 「37개」라고 했는데 **틀렸다** — AFIP 번호열은 `(PV, tipo_comprobante)` 단위다.
  실측:

```
store 6 · PV 4 · tipo 1 (Factura A)   11건  69~80    결번 1
store 6 · PV 4 · tipo 6 (Factura B)    8건  113~124  결번 4
store 9 · PV 1 · tipo 6                2건  16~17    결번 0
```

  81~112 는 「결번」이 아니라 **다른 tipo 의 번호**다. G3(PV 공유)의 실제 크기는
  **5개**이고, 그마저도 `min~max` 구간만 센 것이라 **69 이전은 안 잡힌다** —
  정확한 값은 `FECompUltimoAutorizado` 로 AFIP 에 물어야 안다(W-F6 ③).

**제약/인덱스**

| 이름 | 정의 | 문제 |
|---|---|---|
| `uq_afip_issuer_cuit_pv` | UNIQUE (cuit, punto_venta) | **전역** — 매장 경계를 안 본다 |
| `uq_afip_issuer_store_branch` | UNIQUE (store_id, branch_id) | `branch_id IS NULL` **중복 허용**(PG 기본) |
| `uq_afip_certificado_store_cuit` | UNIQUE (store_id, cuit) | (store,cuit)당 1개 — 환경 둘을 못 담는다 |

★★ **store 6 과 store 9 는 이미 같은 CUIT 을 쓴다.** PV 가 달라 통과했다.
   U1 의 「특별한 경우」가 이미 현실인데 **의도인지 잔재인지 기록이 없다.**

---

## 2. 실측 ② — 화면 (U4 가 겨냥하는 자리)

발행자를 만지는 화면이 **둘**이고, 서로 다른 것을 만지며 **각자 절반씩 없다.**

### (A) admin ▸ Tiendas ▸ 상세 ▸ 지점 — `ModalBranch.tsx`

```
필드: CUIT · Punto de venta (AFIP) · Sucursal de invoice · Cond. IVA · Tipo A/M(RI만)
      Razón social · Nombre de fantasía · Domicilio · Ingresos brutos · Inicio actividad
저장: PUT /afip/issuers/by-branch/:branchId          (@Auth admin, superadmin)
```
→ **지점별 PV·CUIT 은 여기서 이미 설정 가능하다.** U4 의 절반은 존재한다.
  다만 **환경(homo/prod) 필드가 없다.**

### (B) 매장 ▸ Facturación ▸ 발행자 — `views/facturacion/IssuerConfig.tsx`

```
폼: Punto de venta · CUIT · Cond. IVA · Cool user (gateway) · Razón social ·
    Nombre de fantasía · Domicilio · Ingresos brutos · Inicio actividad · Teléfono
저장: POST /afip/issuers | PUT /afip/issuers/:id      (@Auth admin, superadmin)
```
→ ★ **지점(sucursal) 필드가 없다.** 여기서 만든 발행자는 `branch_id = NULL` 로 들어가고,
  NULL 중복이 허용되므로 **NULL 발행자가 여러 개 쌓일 수 있다.** 어느 것이 기본인지
  정하는 규칙이 **어디에도 없다.**
→ ★ 「Cool user (gateway)」라는 필드가 화면에 그대로 노출돼 있다 — U5 의 관점에서
  **지워야 할 개념**이 사용자 입력란으로 남아 있는 것이다.

### (C) Configuración ▸ Preferencias ▸ Facturación — `FacturacionPrefsView.tsx`

```
FE 토글 · 기본 % · FeDocumentsCard(서류) · CertificadoCard(인증서)
```
→ **환경 선택이 없다.** `afip_production` 은 DB 에만 있다. U3 의 「선택하게 한다」는
  **현재 존재하지 않는 기능**이다.

### 권한 실측

| 엔드포인트 | 역할 |
|---|---|
| `GET /afip/issuers` | admin · superadmin · gerente · **vendedor** |
| `GET /afip/issuers/by-branch/:id` | admin · superadmin · gerente |
| `PUT /afip/issuers/by-branch/:id` · `POST /issuers` · `PUT /issuers/:id` · `DELETE /issuers/:id` | admin · superadmin |

★ `GET /afip/issuers` 는 **전체 레코드**를 vendedor 에게 준다. 거기에 `cool_user` —
  **인증서 폴더 이름** — 이 실려 나간다.

---

## 3. 실측 ③ — cool-invoice 결합 전수 (U5 의 작업 목록)

`provider='soap'` + `producción` 에서 **지금도 남아 있는** 결합이다.

| # | 결합 | 위치 | 성격 | soap+prod 에서 |
|---|---|---|---|---|
| **G1** | 인증서 폴더가 cool-invoice 테넌트 폴더에 **중첩 마운트** | `AFIP_CERTS_SHARED_SLUGS` 기본값 `'coolsistema'` · docker-compose | 파일시스템 공유 | **살아 있음** ★ store 6 의 slug 가 정확히 `coolsistema` |
| **G2** | WSAA TA 캐시 `.lastTokens` 공유 | `soap-direct.provider.ts:74` · `afip-soap.client.ts:5` | 최대 **12시간 발급 불가** 위험 | **살아 있음** |
| **G3** | **PV 4 번호열 공유** | store 6 PV 4 | 결번 = 남이 쓴 번호 → **Libro IVA 누락** | **살아 있음** |
| **G4** | `cool_user` 가 인증서 slug 의 출처 | `afip-issuer.model.ts:43` 외 6곳 | 개념 자체가 게이트웨이 것 | **살아 있음** |
| **G5** | `manager.coolsistema.com` PV 해석 | `afip-issuer.service.ts:105` · **57-05(R6) 미구현** | 게이트웨이에 PV 를 물어봄 | 미구현 → **폐기** |
| **G6** | `invoice.coolsistema.com` 릴레이 | `rest-gateway.provider.ts:15` | `ws` 발급 경로 | soap 에선 **안 탐** |
| **G7** | 외부 발급 원장 | `comprobante-externo.service.ts` | **G3 의 대증요법** | G3 해소 시 과거분 전용 |

**따라서 U5 의 실제 작업은 G1 · G2 · G3 · G4 넷이다.**
G5 는 «만들지 않는 것» 으로 끝나고, G6 는 `ws` 를 쓰는 동안만 남으며, G7 은 G3 이
사라지면 신규 발생이 멈춘다(과거 결번은 계속 원장에 남긴다).

★★ **G5 결론: `57-05`(R6, manager PV 해결)를 폐기한다.**
   "PV 는 invoice 가 정한다" 는 방침이 U5 로 **뒤집혔다.** PV 는 이제 우리가 정한다.
   아직 코드가 없으므로 폐기 비용은 **계획서 한 장**이다.

---

## 4. 깨지는 전제 — 8건 (코드/DB 실측)

### ① 인증서를 「매장의 첫 발행자」로 고른다 — U2 와 정면 충돌
`afip-cert.service.ts:108`
```ts
const issuer = await this.issuerModel.findOne({
  where: { storeId }, order: [['puntoVenta', 'ASC']],
});
return { cuit: String(issuer.cuit), slug: issuer.coolUser || String(issuer.cuit) };
```
매장에 CUIT 이 둘이면 **PV 가 작은 쪽 인증서**로 둘 다 서명을 시도한다.

### ② 발행자를 **판매자의 소속 지점**으로 고른다 — 세무 오귀속
`afip-voucher.service.ts:102-105` → `const branchId = sale.user?.branchId ?? null;`
판매 조회(`:270`)는 `sales.branch_id` 를 **select 조차 하지 않는다.**

★ CUIT 이 하나인 지금은 결과가 같아 **증상이 없다.** U2 를 켜는 순간 판매자가 다른
  지점에서 팔면 **틀린 CUIT 으로 발급**된다. CAE 를 이미 받았으므로 NC 로 취소 후 재발급뿐이다.

### ③ 환경이 **매장 단위** 플래그다 — U3 과 충돌
`afip-voucher.service.ts:141` → `production: config?.afipProduction ?? false`
CUIT 둘 중 하나는 prod, 하나는 시험 중 — **표현할 방법이 없다.**

### ④ WSAA 토큰 캐시가 환경 간 **공유**된다 (= G2)
```ts
const key = `${slug}:${req.production ? 'prod' : 'homo'}`;   // 인스턴스는 환경별 ✓
cacheTokensPath: path.join(certsDir, slug, '.lastTokens'),   // 토큰 파일은 하나 ✗
```
homo TA 를 prod 가 읽으면 WSFE 가 거절한다. TA 수명 12시간.

### ⑤ 환경을 실제로 가르는 것은 플래그가 아니라 **slug** 다 (= G4)
store 6 = `coolsistema`(운영 인증서) · store 9 = `coolsyncrohomo1`(시험 CA
`CN=Computadores **Test**`). 폴더가 `AFIP_CERTS_DIR/<slug>/` 하나뿐이라 **한 slug = 한 환경**.
그런데 slug 는 `cool_user` 에 얹혀 있고 환경 컬럼이 없다 — **우연히 맞아 돌고 있다.**

### ⑥ `ws` 에서는 시험 모드가 **거짓말**이다
`entorno-afip.ts` — 게이트웨이는 `production` 을 무시하고 항상 운영 발급.
**시험 모드는 `soap` 에서만 성립한다.**

### ⑦ 기본 발행자가 **정의되어 있지 않다**
`POST /afip/issuers` 는 `branchId` 없이 만들 수 있고 NULL 중복이 허용된다.

### ⑧ 발행자 삭제에 **전표 가드가 없다**
`DELETE /afip/issuers/:id` 는 그 발행자의 `afip_vouchers` 를 보지 않는다. 지우면
번호열 연속성(`serie-*`)이 근거를 잃는다.

### ⑨ ★★ **사용자가 고른 CUIT 이 버려진다** — U6 과 정면 충돌

`afip-voucher.service.ts:102-107`

```ts
// PV 도출: 판매지점(sale.user.branchId)의 발행자를 우선. 없으면 요청 PV로 폴백(호환).
const branchId = sale.user?.branchId ?? null;
const branchIssuer = branchId
  ? await this.issuerService.loadIssuerByBranch(storeId, branchId)
  : null;
const puntoVenta = branchIssuer?.puntoVenta ?? params.puntoVenta;
```

발급 API 는 **이미 `puntoVenta` 를 인자로 받는다**(`PartialInvoiceModal.tsx:263`).
그런데 **지점 발행자가 있으면 그것이 이긴다.** 화면에서 무엇을 고르든 무시된다.

★ 즉 U6 의 절반(«고를 수 있는 API»)은 이미 있고, **그 선택을 존중하지 않는 한 줄**이
  기능을 막고 있다. 고칠 자리가 좁다는 뜻이기도 하다.

### ⑩ 지점당 발행자가 **하나로 강제**돼 있다

`uq_afip_issuer_store_branch UNIQUE (store_id, branch_id)` — 한 지점에 발행자 2개를
넣을 수 없다. U6 은 **이 인덱스를 지우거나 바꿔야** 성립한다.

★ 단순히 `branch_id` 중복을 허용하는 것으로는 부족하다 — 같은 CUIT·PV 를 여러 지점에서
  쓰려면 행이 여러 개 필요한데 `uq_afip_issuer_cuit_pv (cuit, punto_venta)` 가 막는다.
  → **조인 테이블이 필요하다**(D-19).

### ⑪ 기본 발행자를 **배열의 첫 원소**로 고른다

`SalesListView.tsx:558` → `const defaultPv = afipIssuers?.[0]?.puntoVenta`

정렬 순서가 바뀌면 **기본 CUIT 이 바뀐다.** CUIT 이 하나일 때만 안전한 코드다.

### ⑬ ★★ 발행자가 **없는 지점에서 실제로 팔고 있다** — D-14 와 충돌 (A6 실측)

```
발행자 없는 지점:  store 6 → HELGUERA(16) · Depósito Central(25)
                  store 9 → SALA(15)
매장 기본 발행자(branch_id IS NULL):  **0개** — 아예 없다
```

★ **HELGUERA 는 실제 판매처다** — store 6 판매 15건이 거기서 일어났다(D-10 근거와 같은 건).
  지금은 `branchIssuer` 가 null 이라 `params.puntoVenta` 폴백이 작동해 **coolsistema 의
  PV 4 로 발급**되고 있다.

★★ **그대로 W-B 를 배포하면 HELGUERA 판매가 발급 불가가 된다.**
  D-14(기본 발행자 없으면 거절) + 매장 기본 발행자 0개 = 거절.
  → **백필이 이것을 메워야 한다**: 매장에 발행자가 **정확히 하나**일 때만,
    그 매장의 모든 지점에 그 발행자를 «허용 + 기본값» 으로 넣는다(현행 동작 보존).
    둘 이상이면 모호하므로 **넣지 않고 보고**한다 — 사람이 정할 일이다.

### ⑫ 전표에 **어느 발행자로 발급했는지** 남지 않는다

`afip_vouchers` 에 `issuer_id` 가 **없다**(실측 0). `punto_venta` 만 남는다.
PV 를 나중에 재배정하면 과거 전표의 귀속이 바뀐 것처럼 보인다.
★ **고른 근거와 저장한 근거가 같아야 한다** — 고를 때는 발행자를 고르고 저장은 PV 만
  하면, 되짚을 때 추론이 개입한다.

---

## 5. 추가 요건 R8 ~ R12

### R8 — 한 지점에서 **여러 CUIT 중 골라** 발급한다 (U2 + U6) ★ 2026-09-18 재작성

> 종전 R8(「지점마다 CUIT 하나」)은 **폐기**한다. U6 이 요건을 확정했다 —
> 발급 단위는 지점이 아니라 **발급 건**이고, 지점은 **기본값만** 정한다.

**모델**

```
afip_issuers            매장의 CUIT·PV 목록 (지점에 매이지 않는다)
afip_issuer_branches    어느 지점에서 쓸 수 있는가 + 그 지점의 기본값인가   ← 신설
  (issuer_id, branch_id, es_predeterminado)
```

- **Target:**
  1. **발급 시 선택이 권위다.** 요청이 발행자를 지정하면 **그대로 쓴다.**
     `branchIssuer?.puntoVenta ?? params.puntoVenta` 의 우선순위를 **뒤집는다.**
  2. 지정이 없을 때만 기본값 — **그 지점의 `es_predeterminado`**.
     지점 기본값이 없으면 **매장 기본값**, 그것도 없으면 **거절**(D-14).
  3. 기본값 산출의 지점은 **`sales.branch_id`**(D-10) — 판매자 소속이 아니라 **판매가 일어난 곳**.
  4. 선택한 발행자가 **그 지점에서 허용된 것인지 서버가 검증**한다
     (`afip_issuer_branches` 에 없으면 거절 — 화면이 보내는 값을 믿지 않는다).
  5. `afip_vouchers.issuer_id` 에 **무엇으로 발급했는지 기록**한다(전제 ⑫).
  6. 인증서 해석을 **발행자 단위**로: `emisorDe(storeId)` → `emisorDe(issuer)`.
  7. 전표 있는 발행자는 삭제 대신 **비활성**.
- **Acceptance:** 한 지점에 CUIT 둘을 붙이고 POS 에서 판매 → 발급 모달에서
  **둘 중 하나를 고르면 그 CUIT·그 인증서·그 PV 로 CAE** 가 나오고,
  `afip_vouchers.issuer_id` 가 고른 것과 같다. 아무것도 고르지 않으면 그 지점 기본값으로 나간다.
- **대조군 (셋 다 필요):**
  · 고른 값이 **무시되면 실패** — 지점 기본값과 **다른** 발행자를 골라 검증할 것
    (같은 것을 고르면 무시돼도 통과한다).
  · 그 지점에서 허용되지 않은 발행자를 보내면 **거절**되어야 한다.
  · 지점 기본값·매장 기본값 둘 다 없고 선택도 없으면 **거절**되어야 한다.

★★ **미리보기(F10)에서 고른 값이 실제 발급까지 가야 한다.** 확인 화면이 보여 준 CUIT 과
   다른 것으로 발급되면 그 화면은 구속력이 없는 장식이다. 미리보기 응답에 발행자를 싣고,
   발급 요청이 **그 값을 되돌려 보내** 서버가 대조한다.

★ 선택 UI 는 **발행자가 2개 이상일 때만** 뜬다. 1개면 지금과 똑같이 보여야 한다
   (대다수 매장이 그 상태다 — 새 기능이 기존 흐름을 느리게 만들지 않는다).

#### R8-a — 누가 어디서 고르는가 (D-20 = 지점 기본 · caja 에서 선택)

- **기본값의 근거는 지점**(D-10 = `sales.branch_id`), **선택하는 자리는 caja** 다.
- ★ **caja↔CUIT 연결 테이블은 만들지 않는다.** `afip_issuer_branches`(지점 허용목록 +
  지점 기본값) 하나면 충분하다 — D-20 이 (c)로 정해지며 스키마가 한 겹 줄었다.
- **권한 실측:** 발급 엔드포인트(`POST /afip/issue`)는 **이미 `vendedor` 를 허용**한다
  (`afip.controller.ts:364-366`). caja 운영자가 부를 수 있으므로 **권한 변경이 필요 없다.**
- ★ 다만 **고르려면 목록을 읽어야 한다.** 지금 vendedor 가 읽을 수 있는 것은
  `GET /afip/issuers`(전체 레코드)뿐이고 `by-branch` 는 gerente 이상이다.
  → **좁은 조회를 신설한다**: `GET /afip/issue/opciones?saleId=` —
  그 판매의 지점에서 고를 수 있는 발행자만, **표시에 필요한 필드만**
  (`id` · `cuit` · `puntoVenta` · `razonSocial` · `esPredeterminado`).
  `cool_user`/`cert_slug`/`entorno` 같은 운영 값은 **싣지 않는다.**
- ★★ **서버가 다시 검증한다.** caja 에서 보낸 발행자 id 가 그 판매 지점의 허용목록에
  있고 `activo` 인지 서버가 확인한다. 화면이 보낸 값을 믿지 않는다 — 프론트에서
  감추는 것은 경계가 아니다.

### R9 — CUIT 의 매장 귀속을 명시한다 (U1)
- **Target:** 타 매장이 쓰는 CUIT 등록은 **기본 거절**. `cuit_compartido = true` 로
  **명시할 때만** 허용하고 누가 쓰는지 화면에 보인다. 기존 2행은 백필로 현행 보존.
- **Acceptance:** 미표시로 등록 → 400 + 「이 CUIT 은 <매장>이 사용 중」. 표시하면 통과.
  **기존 store 6·9 회귀 0.**
- **쓰기 경로 3곳 전부**에 건다 (`afip-issuer-guard.spec.ts` 가 이미 그 형태를 센다).

### R10 — 환경은 **발행자별**, 시험 모드 7일 상한 (U3)
- **Target:** ① `afip_issuers.entorno`(`homo`|`prod`)가 **권위**, 매장 플래그는 전환기 폴백.
  ② **`soap` 일 때만 homo 선택 가능**, `ws` 는 `prod` 고정 + 사유 문구.
  ③ `homo` 전환 시각을 `homo_desde` 에. `prod` 로 가면 NULL.
  ④ **7일 초과 시 자동으로 `prod` 로 전환**한다(D-09 확정). ⑤ D-3·D-1 예고.
  ⑥ TA 캐시 환경별 분리(G2). ⑦ 환경별 인증서를 발행자의 `cert_slug` 로 지정.
- **대조군:** `prod` 발행자는 `homo_desde` 와 무관하게 영향 없음.

#### R10-a — 자동 prod 전환의 절차 (D-09 = 자동 전환)

**전제: 운영 인증서가 없으면 전환은 성립하지 않는다.** homo 인증서(issuer CN 에
`Computadores Test`)로 운영 발급은 **물리적으로 불가능**하다. 그러므로 자동 전환은
「플래그를 바꾸는 일」이 아니라 **「인증서를 바꿔 끼우는 일」** 이다.

★ 다행히 판정 재료가 **이미 있다** — `afip-cert.service.ts:leerDeArchivo` 가
  인증서마다 다음을 계산한다:

```
esProduccion      issuer CN 이 운영 CA 인가 (AFIP_CA_PROD ∧ ¬AFIP_CA_HOMO)
parejaOk          cert 와 key 의 modulus 가 맞는가 (WSAA 서명 가능 여부)
cuitEnCert        인증서의 CUIT 이 이 발행자의 것인가
estado            'activo' | 'vencido'  (notAfter 기준)
entornoCoincide   인증서 환경 == 설정 환경
```

**전환 절차 (7일째, 발급 시점 판정)**

```
1. 이 발행자의 CUIT 에 대한 운영 인증서를 찾는다
2. 검사: esProduccion ∧ parejaOk ∧ cuitEnCert 일치 ∧ estado='activo'
3. 통과 → cert_slug 를 그 인증서로 옮기고 entorno='prod', homo_desde=NULL
         · audit_logs 에 «자동 전환» 을 사유와 함께 남긴다
         · 사용자에게 통지한다 (이제 진짜 전표가 나간다)
4. 불통과 → **발급 차단** (D-09b 확정). 사유를 나눠서 말한다:
        · 운영 인증서 없음        → 「운영 인증서를 올려 주세요」 + 발급 안내 링크
        · 있으나 CUIT 불일치      → 어느 CUIT 의 인증서인지 알린다
        · 있으나 만료(vencido)    → 만료일과 갱신 안내
        · 있으나 key 짝 불일치    → 「서명을 만들 수 없습니다」
     ★ 「차단」 하나로 뭉뚱그리지 않는다 — 막힌 사람이 **무엇을 해야 하는지** 알아야
       그날 안에 풀 수 있다. 이 네 갈래는 leerDeArchivo 가 이미 구분해 준다.
```

★★ **자동 전환은 되돌릴 수 없는 방향의 동작이다.** 전환된 순간부터 **실제 세금계산서**가
   나간다. 그래서 전환 자체를 조용히 하지 않는다 — D-3·D-1 예고를 반드시 붙이고,
   전환 시점에도 통지한다. **목표는 7일째가 놀라운 날이 아니라 예정된 날이 되는 것**이다.

★ 전환의 **판정도 발급 시점에 한다**(D5 와 같은 이유). cron 으로 미리 바꿔 두면
  「언제 바뀐 줄 모르는」 상태가 생기고, 비리더 워커에서는 그 cron 이 아예 없다.

- **Acceptance:** 운영 인증서를 올려 둔 homo 발행자의 `homo_desde` 를 8일 전으로 두고
  발급하면, **그 발급이 prod 로 나가고** 발행자의 `entorno` 가 `prod` 로 남는다.
- **대조군:** 운영 인증서가 **없는** 발행자는 같은 조건에서 **전환되지 않고 차단**된다
  (D-09b). 여기서 전환되면 인증서 검사가 안 걸린 것이고, 그냥 발급되면 7일 게이트가
  안 걸린 것이다 — **두 가지를 따로 단언한다.**

### R11 — 셋업 화면 (U4)
두 화면의 **역할을 가른다.**

| 화면 | 누가 | 무엇을 |
|---|---|---|
| **admin ▸ Tiendas ▸ 지점** (`ModalBranch`) | superadmin | 매장 경계를 넘는 것 — CUIT 공유 표시, 타 매장 사용 현황 |
| **Configuración ▸ Facturación ▸ Emisores** (신설) | 매장 admin | 자기 매장 안 — 지점별 발행자(CUIT·PV·환경·인증서) |

- **신설 화면:** 표(지점·CUIT·PV·Cond.IVA·A/M·**환경 배지**·인증서 상태·**남은 시험일수**),
  행 추가/편집(**지점 선택 필수 또는 「기본」**·CUIT·PV·환경 라디오(soap만)·인증서),
  **기본 발행자 지정**, 시험 만료 임박 배너.
- **admin 보강:** 그 CUIT 을 쓰는 **다른 매장 목록** + 공유 허용 체크.
- ★ **프론트에서 감추는 것은 경계가 아니다** — 환경 제한·CUIT 공유 거절은
  **서버가 같은 규칙으로 거절**해야 한다.

### R12 — cool-invoice 게이트웨이 이탈 (U5) ★ 이 보강의 축

- **Current:** `soap`+`producción` 에서도 G1·G2·G3·G4 가 살아 있다.
- **Target:** **`soap`+`producción` 발행자는 cool-invoice 와 공유하는 자원이 0이다.**

  | 결합 | 목표 상태 |
  |---|---|
  | **G1** 인증서 폴더 | Ventago 전용 디렉터리로 이전. `AFIP_CERTS_SHARED_SLUGS` 에 걸리는 slug 로는 **soap+prod 발급 금지** |
  | **G2** TA 캐시 | 발행자·환경별 전용 파일. 공유 폴더에 쓰지 않는다 |
  | **G3** PV | **Ventago 전용 punto de venta** 로 이전. 남과 번호열을 나누지 않는다 |
  | **G4** `cool_user` | `cert_slug` 로 대체. 화면에서 「Cool user (gateway)」 라벨 제거 |
  | **G5** manager PV | **만들지 않는다** — `57-05` 폐기 |

- **Acceptance (핵심):** soap+prod 발행자 하나를 골라
  ① 그 인증서 경로가 `AFIP_CERTS_SHARED_SLUGS` 밖에 있고,
  ② TA 파일이 그 발행자 전용이며,
  ③ 그 PV 의 AFIP 최종번호와 우리 `afip_vouchers` 최대번호가 **연속**(결번 0)이고,
  ④ 코드 경로에 `coolsistema.com` 호출이 **0건**임을 자동 검사가 확인한다.
- **대조군:** 공유 slug 를 쓰는 발행자로 soap+prod 발급을 시도하면 **거절**되어야 한다.
  통과하면 ①이 검사되지 않은 것이다.

★★ **G3(PV 이전)이 이 요건에서 가장 무겁고 가장 값어치 있다.** 결번 37개가
   사라지는 것이 아니라 **더 이상 새로 생기지 않는다.** 과거 결번은 `comprobante-externo`
   원장으로 계속 메운다(G7).

---

## 6. 결정이 필요한 것

| # | 질문 | 선택지 | 내 권고 | 왜 |
|---|---|---|---|---|
| **D-09** | 7일 경과 시 | (a) 발급 차단 (b) 경고만 (c) 자동 prod | ✅ **(c) 자동 prod 전환 — 확정 2026-09-18** | §5 R10-a 에 전제와 절차 |
| **D-09b** | 7일째에 **운영 인증서가 없으면** | (a) 발급 차단 (b) homo 유지 (c) 경고만 | ✅ **(a) 발급 차단 — 확정 2026-09-18** | 전환의 전제가 없다. (b)는 요건("일주일 넘게 시험 금지")을 안 지키고, (c)는 아무것도 막지 않는다 |
| **D-10** | **기본값** 산출 지점 (선택이 없을 때) | (a) `sales.branch_id` (b) `user.branchId` 유지 | ✅ **(a) 판매가 일어난 지점 — 확정 2026-09-18** | 영수증의 CUIT·주소·PV 는 «누가 팔았나» 가 아니라 «어디서 팔았나» 다. **실측: store 6 판매 148건 중 15건(10%)이 판매지점≠판매원소속** (예: 판매 206 — HELGUERA 에서 팔았으나 jungho 는 coolsistema 소속) |
| **D-19** ★ | 지점↔발행자 연결 | (a) 조인 테이블 `afip_issuer_branches` (b) `branch_id` 중복 허용 | **(a) 조인 테이블** | (b)는 `uq_afip_issuer_cuit_pv` 에 막힌다 — 같은 CUIT·PV 를 여러 지점에서 쓰려면 행을 복제해야 하는데 불가능 |
| **D-20** | 발급 시 CUIT 을 **누가/어디서** 고르나 | (a) caja 에 CUIT 을 묶는다 (b) caja 에 묶되 변경 가능 (c) **지점이 기본, caja 에서 사람이 고른다** | ✅ **(c) — 확정 2026-09-18** | caja↔CUIT 연결 테이블이 **불필요**해진다. 기본값은 D-10(판매 지점), 선택은 caja 운영자 |
| **D-16** | `GET /issuers` vendedor 노출 | 좁힌다 / 둔다 | ✅ **좁힌다(닫지는 않는다)** | D-20(c) 로 **caja 운영자가 목록을 읽어야** 한다 → 닫으면 기능이 죽는다. 필드만 줄인다 |
| **D-11** | 교차 매장 CUIT | 표시하면 허용 / 금지 | **표시하면 허용** | store 6·9 가 이미 그 상태 |
| **D-12** | 환경별 인증서 지정 | 폴더 규칙 / `cert_slug` 컬럼 | **`cert_slug` 컬럼** | 폴더 규칙은 공유 자원이라 우리가 못 정한다 |
| **D-13** | 7일 기준 시각 | UTC / 매장 타임존 | **매장 타임존** | 이 저장소의 「오늘」은 UTC 가 아니다 |
| **D-14** | 기본 발행자 없는 판매 | 거절 / 아무거나 | **거절** | 「모른다」를 「괜찮다」로 읽지 않는다 |
| **D-15** | 7일 시계 시작 | 생성 시 / homo **선택** 시 | **homo 선택 시** | 만들고 안 쓴 기간까지 세면 부당 |
| **D-17** ★ | **PV 이전 방식**(G3) | (a) 새 PV 를 ARCA 에 신청해 전환 (b) PV 4 를 cool 이 비우게 협의 | ✅ **(a) — 확정 2026-09-18. ARCA 등록은 사용자가 직접 수행** | (b)는 남의 일정에 걸린다. 등록이 끝나면 시스템 쪽 전환은 W-F6 |
| **D-18** ★ | **인증서 폴더 이전**(G1) | (a) 전용 디렉터리 복사 후 전환 (b) 지금 자리 유지 | ✅ **(a) 전용 디렉터리로 복사 후 전환 — 사용자 확정 2026-09-18** | 「캐시」로 보이는 공유 파일이 사실은 잠금이다. 절차는 W-F3 |

★ **D-09 · D-10 · D-17 · D-18 은 작업 내용을 바꾼다.** 나머지는 구현 세부다.
★ D-17 은 **세무 절차**가 따른다 — 새 PV 는 ARCA 에 등록해야 하고, 전환 시점 이후
  전표는 새 PV 로 나간다. 회계사와의 합의가 필요할 수 있다.

---

## 7. 작업 계획

**순서의 근거: 막는 것을 먼저, 그 다음에 여는 것, 이탈은 마지막.**
반대로 하면 잘못된 발행자 데이터가 먼저 들어오고, 이탈 중에 구조가 흔들린다.

### W-A — 잠금장치와 관측 (동작 변경 0)

| # | 작업 |
|---|---|
| A1 | 마이그레이션 ①: `entorno`·`homo_desde`·`cert_slug`·`cuit_compartido`·`activo` **nullable 추가** + CHECK(NOT VALID→VALIDATE) |
| A2 | `uq_afip_issuer_store_default` — `(store_id) WHERE branch_id IS NULL`, **CONCURRENTLY** |
| A3 | 백필 — 현행 보존 (§8) |
| A4 | 읽기 폴백 배선 `issuer.entorno ?? 매장플래그` (화면 없음) |
| A5 | 관측 로그: 발급 시 «발행자 id·CUIT·PV·환경·cert_slug·공유폴더 여부» |
| **A6** | **현황 스크립트** — NULL-branch 중복 · 교차 매장 CUIT · 발행자 없는 지점 · **`sales.branch_id` 결측 판매 수** · **PV 별 결번 수** |

★ **합격 조건: 배포해도 동작이 안 바뀐다.** A6 이 0 이 아니면 W-B 전에 정리한다.

### W-B — 발행자 선택 교정 (D-10 · D-14)

| # | 작업 |
|---|---|
| B1 | 판매 조회에 `sales.branch_id` 추가 |
| **B2** | ★ **우선순위를 뒤집는다** — `resolveIssuerForSale(sale, seleccion)`:<br>① 요청이 지정한 발행자(**권위**) → ② `sales.branch_id` 의 `es_predeterminado` → ③ 매장 기본 → ④ **throw** |
| B2b | 선택 검증 — 지정된 발행자가 그 지점에서 허용(`afip_issuer_branches`)되고 `activo` 인지. 아니면 거절 |
| B3 | **발급 경로를 전수로 센 뒤** 전부 교체: `afip-voucher`·`nota-credito`·`nota-debito`·`auto-issue` |
| B4 | 회귀 대조: 기존 21건을 새 함수로 재해석 → **전부 같은 발행자** 확인 |
| B5 | `emisorDe(storeId)` → `emisorDe(issuer)` |
| B6 | `afip_vouchers.issuer_id` 쓰기 — 고른 그 id 를 저장(재추론 금지) |
| B7 | 프론트 `defaultPv = afipIssuers[0]` 제거 → 지점 기본값 조회로 교체 |

★ B3 이 핵심이다. 이 저장소는 「한 곳만 고쳐 나머지가 조용히 빠지는」 사고를 반복했다.
  **손대기 전에 경로를 세고, 센 개수를 시험이 지키게 한다.**

### W-C — 가드

| # | 작업 |
|---|---|
| C1 | 교차 매장 CUIT 가드 — 쓰기 **3경로 전부**, guard spec 에 편입 |
| C2 | 발행자 삭제 가드 — 전표 있으면 409, `activo=false` 로 유도 |
| C3 | `GET /afip/issuers` 응답 축소 (D-16) |

### W-D — 환경과 7일 상한 (D-09 · D-13 · D-15)

| # | 작업 |
|---|---|
| D1 | `entorno` 전환 서비스 — homo 진입 시 `homo_desde=now()`, prod 진입 시 NULL |
| D2 | **`ws` 발행자의 homo 거부** — 서버 400 + 화면 비활성 + 사유 |
| D3 | 발급 게이트 — `entorno='homo' AND homo_desde < 매장오늘-7일` → **자동 전환 시도**(R10-a) |
| D3b | 전환 불가 시 **차단** + 4갈래 사유(D-09b). 각 사유에 «무엇을 하면 되는지» 를 붙인다 |
| D4 | 예고 D-3·D-1 (배너 + 기존 알림 경로) |
| D5 | 판정은 **발급 시점 계산**, 상태를 저장하지 않는다 ★ |

★ **cron 을 쓰지 않는 쪽을 권한다.** 비리더 워커는 cron 이 전부 삭제되고,
  「1회 조회」 화면은 cron 이 쓰면 낡는다. 발급 시점 계산이면 워커 수와 무관하고
  저장할 상태가 없다. **예고 알림만** 별도 주기로 돌린다.

### W-E — 화면 (R11 / U4)

| # | 작업 |
|---|---|
| E1 | **Configuración ▸ Facturación ▸ Emisores** 신설 |
| E2 | 지점 선택 필드 + 「기본 발행자」 지정 |
| E3 | 환경 라디오(soap 만) + 남은 시험일수 배지 |
| E4 | 인증서 상태 — `cert_slug`·만료일·homo/prod CA 구분·**공유 폴더 경고** |
| E5 | admin `ModalBranch` 보강 — 그 CUIT 을 쓰는 다른 매장 + 공유 허용 체크 |
| E6 | **막다른 길 검사** — 신설 메뉴가 실제 라우트에 닿는지 자동 확인 |
| **E7** ★ | **발급 모달의 CUIT 선택기** (U6) — 발행자 2개 이상일 때만 노출. 1개면 현행과 동일 |
| E8 | 미리보기(F10) 응답에 발행자를 싣고, 발급 요청이 **그 값을 되돌려 보내** 서버가 대조 |
| E9 | 지점별 「이 지점에서 쓸 수 있는 CUIT」 설정 — 조인 테이블 편집 + 기본값 지정 |

★ E6 을 따로 두는 이유: 이 저장소는 **없는 메뉴·없는 페이지로 보내는 CTA** 를 만든 적이 있다.
★ 상단 앱바는 데스크톱에서 숨겨져 있다 — 신설 진입점을 거기 두면 **없는 것과 같다.**

### W-F — 게이트웨이 이탈 (R12 / U5) ★ D-17 · D-18

| # | 작업 | 결합 |
|---|---|---|
| F1 | **`57-05` 폐기** — 계획서 + ROADMAP 정리. `resolvePvAndCoolUser` 는 만들지 않는다 | G5 |
| F2 | `cool_user` → `cert_slug` 전환 — 읽기를 `cert_slug` 로 옮기고 화면 라벨 제거. 컬럼은 **폴백으로 남긴다** | G4 |
| F3 | 인증서 **전용 디렉터리** 신설 + 복사 + 전환 (D-18 확정). 절차는 아래 ★★ | G1 |
| F4 | TA 캐시 전용 파일 — `<전용경로>/<cert_slug>/.lastTokens.<entorno>` | G2 |
| F5 | **공유 slug 로 soap+prod 발급 금지** 가드 (`AFIP_CERTS_SHARED_SLUGS` 대조) | G1 |
| F6 | **전용 PV 이전** (D-17 확정) — 역할이 나뉜다, 아래 ★★★ | G3 |
| F7 | **이탈 검사** — 발급 경로에서 `coolsistema.com` 호출 0건을 자동으로 센다 | 전부 |

★★★ **F6 — 역할이 나뉜다 (D-17 확정).**

| 단계 | 누가 |
|---|---|
| ① 새 punto de venta 를 **ARCA 에 등록** | **사용자** (2026-09-18 확정) |
| ② 등록된 PV 번호·CUIT·유효 시작일을 알려 준다 | 사용자 → Claude |
| ③ 그 PV 의 **AFIP 최종번호 조회**(`FECompUltimoAutorizado`) | 시스템 |
| ④ 발행자의 `punto_venta` 변경 + `pv_migrado_en` 기록 | 시스템 |
| ⑤ 연속성 검증이 **전환 이전 구간은 옛 PV 기준**으로 보게 한다 | 시스템 |
| ⑥ 시험 발급 1건으로 새 번호열 확인 | 시스템 |

★ **④ 를 ③ 보다 먼저 하면 번호열이 끊긴 것으로 보인다.** 새 PV 는 보통 1번부터
  시작하는데, 우리 원장의 마지막 번호(124)와 이어지지 않기 때문이다. ⑤ 가 «전환 시각»
  을 경계로 삼아야 두 구간이 각자 연속으로 읽힌다.

★ 착수 시점에 **사용자에게 물어야 할 것**: 새 PV 번호 · 어느 CUIT 의 것인지 ·
  언제부터 그것으로 발급할지. 셋이 없으면 ③ 부터가 안 된다.

★ 전환 이후에도 **옛 PV(4)의 과거 전표는 그대로 조회·재출력되어야 한다.** 옛 PV 를
  지우지 않는다 — 발행자 행을 비활성으로 남기거나, `pv_migrado_en` 으로 구간을 가른다.
★ F3·F4 는 **남의 시스템이 읽는 파일**을 건드린다 — «누가 읽는가» 를 실측한 뒤,
  **새 경로를 추가**하고 옛 경로는 남긴다(읽기 폴백). 지우는 것은 마지막 단계다.

★★ **F3 절차 (D-18 = 복사 후 전환) — 복사는 이동이 아니다.**
```
1. AFIP_CERTS_DIR_VENTAGO (신규, Ventago 전용) 를 만든다
2. 대상 slug 의 cert·key 를 복사한다 — 원본은 그대로 둔다
   · 권한 0600 확인 (개인키다)
   · 복사본의 modulus 대조 — parejaOk 가 새 경로에서도 참인지
3. 발행자의 cert_slug 를 새 경로 기준으로 바꾼다 (한 발행자씩)
4. 그 발행자로 **homologación 시험 발급** 1건 — 새 경로에서 WSAA 서명이 되는지
5. 통과하면 운영 발급으로 넘긴다. 실패하면 3번을 되돌린다 (원본이 남아 있다)
6. 모든 발행자 전환 + 안정화 확인 후에야 옛 경로 읽기를 끊는다
```
★ **원본을 지우는 것은 이 phase 의 작업이 아니다.** cool-invoice 가 같은 폴더를 읽고
  있고(G1), 우리가 지우면 그쪽이 깨진다. 우리는 **읽기를 그만둘 뿐**이다.
★ 2번의 modulus 대조를 생략하지 않는다 — 복사가 조용히 잘리면 WSAA 서명이
  **발급 시점에** 실패한다. 그때는 이미 판매가 끝나 있다.
★ F7 은 **대조군이 필요하다** — 일부러 `ws` 발행자로 발급하면 이 검사가 **실패해야** 한다.
  둘 다 통과하면 아무것도 검사하지 않은 것이다.

---

## 8. 마이그레이션 (expand → migrate → contract)

CLAUDE.md 무중단 규약. **한 배포에 추가 + NOT NULL 을 같이 하지 않는다.**

```sql
-- ═══ ① expand — 배포 1차(W-A). 전부 nullable ═══
SET lock_timeout = '5s';

ALTER TABLE afip_issuers
  ADD COLUMN entorno         varchar(4),      -- 'homo' | 'prod'
  ADD COLUMN homo_desde      timestamptz,     -- homo 전환 시각 (prod 면 NULL)
  ADD COLUMN cert_slug       varchar(64),     -- 인증서 폴더. cool_user 를 대체
  ADD COLUMN cuit_compartido boolean,         -- 타 매장과 CUIT 공유 명시
  ADD COLUMN activo          boolean,         -- 삭제 대신 비활성
  ADD COLUMN pv_migrado_en   timestamptz;     -- G3: 전용 PV 로 옮긴 시각

ALTER TABLE afip_issuers
  ADD CONSTRAINT ck_afip_issuer_entorno CHECK (entorno IN ('homo','prod')) NOT VALID;
-- 별도 트랜잭션:
ALTER TABLE afip_issuers VALIDATE CONSTRAINT ck_afip_issuer_entorno;

-- ═══ ② 지점↔발행자 조인 테이블 (D-19) — U6 의 핵심 ═══
CREATE TABLE IF NOT EXISTS afip_issuer_branches (
  id                serial PRIMARY KEY,
  issuer_id         integer NOT NULL REFERENCES afip_issuers(id) ON DELETE CASCADE,
  branch_id         integer NOT NULL REFERENCES branches(id),
  es_predeterminado boolean NOT NULL DEFAULT false,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);
-- w4-exempt: 이 테이블은 이 배포에서 처음 만들어져 읽는 코드가 아직 없다
CREATE UNIQUE INDEX IF NOT EXISTS uq_issuer_branch
  ON afip_issuer_branches (issuer_id, branch_id);
-- 지점당 기본값은 **하나**
CREATE UNIQUE INDEX IF NOT EXISTS uq_issuer_branch_default
  ON afip_issuer_branches (branch_id) WHERE es_predeterminado;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'coolsistema') THEN
    ALTER TABLE afip_issuer_branches OWNER TO coolsistema;
    ALTER SEQUENCE afip_issuer_branches_id_seq OWNER TO coolsistema;
  END IF;
END $$;

-- 기존 branch_id 를 조인 테이블로 옮긴다 (원본 컬럼은 남긴다 — 폴백)
INSERT INTO afip_issuer_branches (issuer_id, branch_id, es_predeterminado)
SELECT i.id, i.branch_id, true FROM afip_issuers i
 WHERE i.branch_id IS NOT NULL
ON CONFLICT (issuer_id, branch_id) DO NOTHING;

-- ═══ ③ 전표에 발행자를 기록한다 (전제 ⑫) ═══
ALTER TABLE afip_vouchers ADD COLUMN issuer_id integer REFERENCES afip_issuers(id);
-- 과거 21건 백필: (store_id, punto_venta) 로 유일하게 찾힌다
UPDATE afip_vouchers v SET issuer_id = i.id
  FROM afip_issuers i
 WHERE i.store_id = v.store_id AND i.punto_venta = v.punto_venta
   AND v.issuer_id IS NULL;

-- ═══ ④ 매장 기본 발행자 — 부분 UNIQUE (CONCURRENTLY, 트랜잭션 밖) ═══
CREATE UNIQUE INDEX CONCURRENTLY uq_afip_issuer_store_default
  ON afip_issuers (store_id) WHERE branch_id IS NULL;
-- 실패해 INVALID 가 남으면 DROP 후 재시도.

-- ═══ ⑤ 옛 제약 해제 — **조인 테이블 읽기가 배포된 다음** 배포에서만 ═══
-- U6 은 한 지점에 발행자 2개를 요구하므로 이 인덱스는 결국 사라져야 한다.
-- 그러나 지금 지우면 옛 코드(loadIssuerByBranch 의 findOne)가 **여러 행 중 하나를
-- 임의로** 집는다 → 조용히 틀린 CUIT. 순서를 지킨다.
-- DROP INDEX CONCURRENTLY uq_afip_issuer_store_branch;

-- ═══ ③ migrate — 현행 보존 백필 ═══
UPDATE afip_issuers i SET
  entorno = CASE
    WHEN lower(coalesce(c.afip_provider,'ws')) = 'soap'
      THEN CASE WHEN c.afip_production THEN 'prod' ELSE 'homo' END
    ELSE 'prod'                              -- ws 는 게이트웨이가 항상 운영 발급
  END,
  homo_desde = NULL,                         -- 소급 만료를 걸지 않는다
  cert_slug  = coalesce(nullif(i.cool_user,''), i.cuit),
  cuit_compartido = true,                    -- store 6·9 가 이미 공유 중
  activo = true
FROM store_configs c
WHERE c.store_id = i.store_id AND i.entorno IS NULL;

-- ═══ ④ contract — 읽기에서 폴백을 뺀 *다음* 배포에서만 ═══
-- ALTER TABLE afip_issuers ALTER COLUMN entorno SET NOT NULL;
-- ALTER TABLE afip_issuers ALTER COLUMN activo  SET NOT NULL;
-- (cool_user 는 F2 검증이 끝난 뒤 별도 배포에서 DROP — 옛 백업 복원 영향 확인 필요)
```

★ `homo_desde` 를 **NULL 로 둔다** — 기존 homo 발행자(store 9)에 소급 7일을 적용하면
  배포 즉시 발급이 막힌다. 시계는 **다음에 homo 를 선택할 때부터**(D-15).
★ `cool_user` 를 **DROP 하지 않는다**(이 단계에선). 컬럼을 지우면 옛 백업 복원이 깨진다.
★ 신규 테이블이 아니므로 owner DO 블록 불필요. **로컬 5432 + 운영 5434 동시 적용.**

---

## 9. API 계약 변경

| 엔드포인트 | 변경 | 호환 |
|---|---|---|
| `GET /afip/issuers` | `entorno`·`homoDesde`·`certSlug`·`cuitCompartido`·`activo` 추가. vendedor 축소본 | **추가만** — 옛 프론트 무해 |
| `POST /afip/issuers` · `PUT /afip/issuers/:id` · `PUT /afip/issuers/by-branch/:id` | 교차 CUIT 가드 | 새 400 ⚠ |
| `DELETE /afip/issuers/:id` | 전표 있으면 409 | 새 409 ⚠ |
| (신설) `GET /afip/issuers/:id/entorno` | 남은 시험일수 · 차단 여부 | 신규 |
| (신설) `PUT /afip/issuers/:id/entorno` | 환경 전환(시계 시작/정지) | 신규 |
| (신설) `GET /afip/issuers/:id/independencia` | G1~G4 결합 상태(R12 Acceptance 표시용) | 신규 |

★ ⚠ 의 실패 조건은 「타 매장 CUIT 등록」·「전표 있는 발행자 삭제」라 **정상 사용에는 안 걸린다.**
  그래도 **API 를 먼저 배포**하는 순서가 안전하다.

---

## 10. 배포 순서 (짝을 이루는 변경)

```
1차   W-A                     api 만.  동작 변경 0
      → A6 현황 스크립트 이상 0 확인 후 진행

2차   W-B + W-C               api 만.  ★ 동작이 바뀐다
      → B4 회귀 대조 21건 전부 동일해야 진행

3차   W-D + W-E               api + app **동시** (화면이 새 엔드포인트 전제)
      → ★ api 를 먼저 낸다. app 이 먼저면 없는 엔드포인트로 404

4차   W-F                     운영 절차 포함 — 코드 배포만으로 안 끝난다
      → F6(PV 이전)은 ARCA 등록·회계사 합의가 선행
```

★ 4차는 **배포가 아니라 이행(migration) 작업**이다. 인증서 복사·PV 전환은
  되돌리기 어려우므로 **각 단계마다 되돌아갈 지점**을 먼저 정하고 시작한다.

---

## 11. 검증 — 통과가 아니라 «지켜짐» 을 잰다

| 무엇 | 시험 | 대조군 (**실패해야 정상**) |
|---|---|---|
| **선택이 권위** (U6) | 지점 기본값과 **다른** 발행자를 골라 발급 | 고른 값이 무시되면 **실패**. ★ 기본값과 같은 것을 고르면 무시돼도 통과한다 — 반드시 다른 것으로 |
| 선택 검증 | 그 지점에 없는 발행자를 보낸다 | **거절**되어야 한다 |
| 전표 귀속 | `afip_vouchers.issuer_id` | 고른 id 와 **다르면 실패**. PV 로 재추론하면 안 된다 |
| 미리보기 구속력 | F10 이 보여 준 CUIT vs 실제 발급 | 다르면 **실패** |
| 발행자 선택 | `resolveIssuerForSale` 단위 | 지점·기본 둘 다 없음 → **거절** |
| 판매 지점 권위 | 판매자 소속≠판매 지점 | `user.branchId` 로 고르면 **실패** |
| 다중 CUIT 인증서 | CUIT 둘에서 각각 서명 | 두 번째가 **첫 인증서로 서명하면 실패** |
| 교차 CUIT 가드 | 쓰기 3경로 각각 | 한 경로라도 가드를 안 부르면 **실패** |
| 7일 상한 | `homo_desde` 8일 전 | **`prod` 발행자는 영향 없음** |
| ws 는 homo 불가 | 서버 400 | **프론트만 막고 API 열려 있으면 실패** |
| 기본 발행자 유일성 | NULL-branch 2행 INSERT | **DB 가 거절** (앱 체크만으론 경합에 진다) |
| **G1 공유 폴더** | 공유 slug + soap+prod 발급 | **거절되어야 한다** |
| **G2 TA 분리** | homo→prod 연속 발급 | 옛 공유 파일을 읽으면 **실패** |
| **G3 결번** | 전환 후 구간의 AFIP 최종번호 대조 | **결번 0**. 하나라도 있으면 실패 |
| **G7 이탈 검사** | 발급 경로 `coolsistema.com` 호출 수 | `ws` 발급 시엔 **검사가 실패**해야 한다 |
| 회귀 | 기존 21건 재해석 | 하나라도 다르면 **중단하고 원인부터** |
| 돌연변이 | 위 가드에 stryker | 조건을 뒤집었는데 **살아남으면** 그 시험은 그 가드를 안 지킨다 |

★ 이 저장소는 「대조군이 같이 통과해 아무것도 검증 안 한」 사례를 여러 번 겪었다.
  **오른쪽 칸이 없는 줄은 시험으로 치지 않는다.**
★ 구현에서 정답을 import 하는 시험을 만들지 않는다 — 값을 빼도 통과한다.

---

## 12. 이 보강에서 **하지 않는 것**

- **R1~R7(출력) 을 건드리지 않는다** — 감열·A4·NC/ND 는 발행자 구조와 직교한다.
- **`ws` 기본값을 바꾸지 않는다** — 2026-09-18 사용자 확정. 안정화 후 별건.
  (U5 는 «soap+prod 에서 결합 0» 이지 «ws 제거» 가 아니다.)
- **`ws` 릴레이(G6) 를 제거하지 않는다** — 기본값이 ws 인 동안 그 경로는 살아 있어야 한다.
- **과거 결번(37개)을 소급 정리하지 않는다** — `comprobante-externo` 원장으로 메운다.
  F6 이 막는 것은 **새로 생기는 결번**이다.
- **`afip_certificados` 레지스트리(0행) 를 권위로 올리지 않는다** — 인증서 실체는
  파일시스템이고 `cert_slug` 가 그것을 가리킨다. 승격은 별도 결정.
- **store 9 의 homo 전표 2건을 지우지 않는다** — 세무상 무효라 지표에서 거르면 되고,
  삭제는 감사 흔적을 없앤다.
- **`cool_user` 컬럼을 이번에 DROP 하지 않는다** — 옛 백업 복원이 깨진다.

---

## 13. 남아 있는 위험 (착수해도 안 사라지는 것)

1. **`cert_slug` 가 자유 입력이면 남의 폴더를 가리킬 수 있다** — 인증서 디렉터리는
   다른 시스템과 공유된다. `assertSlugValido` 화이트리스트를 **새 컬럼에도** 반드시 건다.
2. **`.lastTokens` 를 잘못 가르면 cool-invoice 가 최대 12시간 발급 불가**가 된다.
   F4 는 «누가 읽는가» 실측 없이 착수하지 않는다.
3. **운영 인증서 없이는 prod 전환이 불가능하다.** D-09 가 **자동 전환**으로 정해졌으므로
   이 위험은 「7일째에 전환할 인증서가 없는 매장」으로 좁혀진다 → **D-09b** 가 그 동작을
   정하고, 어느 쪽이든 **인증서 발급 안내를 같은 화면에** 둔다. 예고(D-3·D-1)의 목적이
   바로 그날까지 인증서를 준비시키는 것이다.
4. **`sales.branch_id` 결측 판매**가 있으면 B2 가 기본 발행자로 떨어진다. A6 에서 먼저 센다.
5. **PV 이전(F6)의 ARCA 등록은 사용자가 맡는다**(D-17 확정). 시스템 쪽 전환은
   등록이 끝나고 **PV 번호·CUIT·유효 시작일**을 받은 뒤에 시작한다. 그 전에는
   W-F6 을 착수하지 않는다 — 나머지 F1~F5 는 이 결정과 무관하게 진행할 수 있다.
6. **인증서 디렉터리 실측치가 낡았을 수 있다** — 그 디렉터리에는 다른 시스템의
   인증서가 100개 넘게 있다. 「Ventago 것」을 셀 때 `afip_issuers` 를 권위로 삼는다.
