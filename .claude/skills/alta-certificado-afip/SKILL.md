---
name: alta-certificado-afip
description: 매장의 AFIP(ARCA) 전자영수증 연결을 처음부터 끝까지 대신 한다 — ARCA 에서 새 punto de venta(RECE para aplicativo y web services) 생성, Ventago 에서 발행자 등록·CSR 생성, ARCA 인증서 발급, wsfe·ws_sr_constancia_inscripcion 연결, .crt 업로드·활성화·Padrón 확인. cmux 브라우저 탭 두 개(Ventago superadmin + ARCA)를 쓰고 사용자는 로그인만 한다. "certificado digital 연결해줘", "아핍 인증서 등록", "fac. electronica 연결", "padron a5 연결", "punto de venta 만들어줘" 요청 시 사용.
---

# AFIP 인증서·PV 연결 (cmux 브라우저)

2026-10-22 beula1(store 70, CUIT 20928928498)에서 처음부터 끝까지 실제로 한 절차다.
결과: PV 7 · 인증서 alias `ventago70` · wsfe + constancia 수락 · 활성화 · Padrón 「Funcionando」.

## 원칙 (어기지 말 것)

- **사용자는 로그인만 한다.** clave fiscal 은 채팅으로 받지 않는다(기록에 남는다). 비밀번호를 대신 치지 않는다.
- **ARCA 로그인 CUIT == Ventago 매장 CUIT** 를 첫 단계에서 대조한다. 다르면 멈춘다 — 인증서가 남의 CUIT 에 생긴다.
- **기존 인증서 alias·PV 는 건드리지 않는다.** 다른 시스템(회계사 프로그램·cool-invoice)이 쓰는 것일 수 있다.
  Ventago 전용 alias(`ventago<storeId>`)와 **새 PV** 를 만든다. 공유하면 TA·번호가 충돌한다([[afip-ta-is-per-certificate-not-per-cuit]]).
- **이 스킬이 발동되면 「Factura electrónica habilitada」를 무조건 켠다**(2026-10-22 사용자 지시) — 절차 8.
- **무조건 Producción 이다. Homologación 은 쓰지도, 제안하지도, 언급하지도 않는다**(2026-10-22 사용자 지시).
  Modo AFIP 가 「ARCA directo · Producción」이 아니면 그것으로 바꾼다. 화면도 Producción 만 고를 수 있다.
- **전표를 발급하지 않는다**(AFIP 자동 발급 절대 금지). 검증은 활성화(FEParamGetPtosVenta) + Padrón 「Verificar ahora」까지.
- cool-invoice 내용은 참조하지 않는다.

## 준비

```bash
cmux browser open "https://auth.afip.gob.ar/contribuyente_/login.xhtml" --focus true   # → surface:A (ARCA)
cmux new-surface --type browser --pane <pane> --url "https://app.coolsistema.com/login/" --focus false  # → surface:V
```
사용자: V 에 superadmin, A 에 그 매장 CUIT + clave fiscal 로 로그인.

- 대상 매장의 CUIT·기존 상태를 DB 로 본다:
  `SELECT id,name,cuit FROM stores WHERE id=N;` · `afip_certificados` · `afip_issuers` (store_id=N)
- ARCA 로그인 확인: 포털 상단 `navigation "NAME [20-XXXXXXXX-X]"`.
- Ventago 작업 화면: `https://app.coolsistema.com/admin/tiendas/detalle/<storeId>/`
  (superadmin 은 `?storeId=` 로 그 매장 인증서를 다룬다 — `tiendaDestino`)

## 절차

ARCA 서비스는 `https://portalcf.cloud.afip.gob.ar/portal/app/mis-servicios` 에서 연다
(카드 = `a[role=button]`, 클릭하면 **새 탭 surface** 가 생긴다 → `cmux tree` 로 번호 확인).

1. **PV 생성** — 「ADMINISTRACIÓN DE PUNTOS DE VENTA Y DOMICILIOS」→ `A/B/M de puntos de venta` → 기존 목록 확인 → `Agregar..`
   - 필드: `frmAlta_pveNro`(다음 빈 번호) · `frmAlta_pveNombreFantasia` · `frmAlta_sisCodigo=RAW`(RECE para aplicativo y web services)
     · `frmAlta_codTipoDomicilio`(FISCAL) · `frmAlta_idActividad` → Aceptar → 「¿Ha ingresado…?」 **Si**
   - 확인: 목록 행 `7 BEULA RECE para aplicativo y web services …`
2. **Inicio de actividades** — 포털 헤더 「Registro Único Tributario」→ `Inicio de actividad: MM/AAAA`, IVA 여부.
   일 단위가 없으면 `01/MM/AAAA` 로 넣는다(보고에 명시).
3. **Ventago 발행자** — 매장 상세 「Nuevo emisor」: Inicio de actividades · Ingresos brutos(보통 CUIT) · Punto de venta(새 PV) → Guardar.
   MUI 입력은 native setter + `input` 이벤트로 넣는다.
4. **CSR** — 「1. Generar CSR」. 원문은 API 로 받아 주체 확인:
   `GET /afip/cert/csr?storeId=N` → `openssl req -noout -subject` 에 `serialNumber=CUIT <cuit>` 인지.
5. **인증서 발급** — 「ADMINISTRACIÓN DE CERTIFICADOS DIGITALES」→ `cmdIngresar`(Agregar alias)
   - `txtAliasCertificado=ventago<storeId>` · `#archivo` 에 CSR 을 `DataTransfer` 로 넣고 `cmdIngresar`
   - 목록 → 그 alias 「Ver」(`__doPostBack`) → 다운로드 image input 의 폼을 **페이지 안에서 fetch POST**
     (`name.x`/`name.y` 추가) → 응답이 PEM. 파일 다운로드 창을 쓰지 않는다.
   - 확인: `openssl x509 -pubkey` 와 CSR pubkey md5 일치.
6. **서비스 연결** — 「ADMINISTRADOR DE RELACIONES DE CLAVE FISCAL」, 서비스마다 반복:
   `cmdNuevaRelacion` → `cmdBuscarServicio` → `setService('relationAdd','ws://wsfe')` → `cmdBuscarUsuario`
   → `cboComputadoresAdministrados` 에서 새 alias 선택(change) → `cmdSeleccionarServicio` → `cmdGenerarRelacion`
   - 결과 URL 에 `aceptada=True`.
   - 두 번째: `ws://ws_sr_constancia_inscripcion` (**옛 이름 Padrón A5 / `ws_sr_padron_a5` 는 목록에 없다** — Ventago 도 constancia 를 쓴다)
7. **업로드·활성화** — V 에서 「3. Subir certificado (.crt)」 숨은 `input[type=file][accept*=.crt]` 에 DataTransfer
   → 「Activar certificado」. AFIP 가 웹서비스 PV 목록을 돌려주면 wsfe 인증이 된 것이다.
8. **Factura electrónica habilitada (무조건)** — 매장 상세 「Modo AFIP (emisión)」의 스위치를 켠다
   (`PUT /store-config/<storeId>/fe-aprobacion {aprobada:true}`). 「Sin aprobar」 상태로 끝내지 않는다 —
   그러면 매장 화면에 facturación 이 아예 안 보인다.
   같은 카드의 ACTUAL 이 「ARCA directo · Producción」인지 확인하고, 아니면 「Cambiar a: ARCA directo · Producción」.
9. **Padrón** — 「Verificar ahora」 → `Funcionando`.
10. **DB 확인** — `afip_certificados.estado='activo'`, serial·not_after, `afip_issuers.punto_venta`,
    `store_configs.afip_production=true`·`afip_provider='soap'`·FE 승인 컬럼, `afip_vouchers` 0건.

## 함정 (실측)

- **가려진 cmux 탭은 렌더링이 멈춘다.** 새로고침 후 body 가 비면 `cmux focus-panel --panel surface:V` 로 앞으로 가져온다([[cmux-hidden-pane-pauses-raf]]).
- ARCA 서비스 클릭은 새 탭을 연다 — 같은 surface 에서 기다리지 말고 `cmux tree` 로 새 번호를 찾는다.
- PEM 을 python 으로 읽으면 CRLF→LF 로 바뀌어 크기가 달라진다. 내용은 같다.
- 매장 상세의 「Modo AFIP」가 **「Sin aprobar」** 면 매장 화면에는 facturación 이 안 보인다 — 인증서와 별개라 따로 켜야 한다(절차 8, 묻지 않고 켠다).
- 같은 CUIT 의 기존 웹서비스 PV(예: 0004)가 있으면 Ventago 가 「sin vincular」로 알려 준다. 정상이다.
- 커밋 명령에 `grep -a` 를 섞으면 훅이 `commit -a` 로 오인한다.

## 보고

PV 번호·alias·serial·만료일, 두 relation 의 `aceptada`, 활성화 결과, Padrón 상태, 발급 0건을 적는다.
일 단위로 추정한 값(Inicio de actividades 등)은 따로 밝힌다.
