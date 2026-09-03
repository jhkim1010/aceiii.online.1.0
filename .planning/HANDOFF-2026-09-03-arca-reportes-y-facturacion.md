# 핸드오프 2026-09-03 — 첫 SOAP 발급 · Facturación 화면 개편 · ARCA 보고서

앞 세션은 `HANDOFF-2026-09-02-certificados-y-soap.md`.

```
api-ventago  066409c → cd8df68   (Jenkins #858·#859·#860 SUCCESS)
ventago-app  62a71e3 → bc225dd   (Jenkins #704·#705·#706 SUCCESS)
루트          fa0ba59 → (이 문서)
```

**미커밋 없음**(위 세 리포). 루트의 `.planning/STATE.md`·`legacy-query-mcp/` 등은 이번 세션과
무관한 기존 WIP 이므로 건드리지 않았다.

---

## ★★★ 가장 큰 것 — store 6 첫 SOAP 발급 성공

앞 핸드오프의 ★★★ 항목이 해결됐다.

```
Factura B (tipo 6) · PV 4 · N° 123
CAE 86361223780625  (vto 2026-09-13)
$1.00 · venta #188 · Consumidor Final · Capital Federal
```

**AFIP 에 직접 물어 확인했다** — 우리 DB 만이 아니라 AFIP 쪽 마지막 번호가 `B=123` 으로
올라갔다(A 는 80 그대로). 예측했던 「다음은 A=81, B=123」과 정확히 일치.

새 SOAP 경로에서만 나오는 두 가지도 실증됐다:

| 항목 | 이번 전표(#20) | 게이트웨이 시절(#18·#19) |
|---|---|---|
| `cond_iva_receptor` | **5** (RG 5616) | `NULL` — 게이트웨이 미전송 |
| `province_id` (IIBB) | **Capital Federal** | `NULL` |

### 발급하면서 알게 된 것

- **발송 수단 최소 1개가 필수**다. Térmica 를 끄면 `Emitir` 가 비활성화된다.
- 기본 발급 비율이 **30%** 로 잡혀 있다(`store_configs.afip_default_pct`). 100% 로 올려서
  발급했다. 의도한 기본값인지 확인 필요.
- 프린터가 꺼져 있어 종이는 안 나왔지만 **CAE 발급은 정상**이었다
  (`🖨️ Comandera desconectada — usá Reimprimir cuando vuelva`).
- POS 카탈로그에서 `ZZ TEST UAT 7007`($1.000)이 **검색되지 않았다** — 메모리의
  「POS 검색엔 서버 폴백이 없다」와 같은 증상. 이번엔 우회했으나 별건으로 남는다.

### ⚠ 판매 187 이 발급 없이 남아 있다

$156.000 · 12벌 · `Pagado` · `afip_status='no'` (2026-09-03 12:03:35 UTC 생성).
제가 만든 게 아니고 제 조작 1분 전에 이미 완료돼 있었다. **발급할지 버릴지 확인 필요.**
이제 판매내역의 «Facturar» 로 발급 가능하다(아래).

---

## 이번 세션에 한 일

### 1. 인증서 폴더 분리 (`f97c55e`) — 핸드오프 「할 일 2번」

앞 핸드오프에 적힌 **「복사」는 하면 안 되는 것**이었다.
`coolsistema/.lastTokens` 는 캐시가 아니라 cool-invoice 게이트웨이와의 **상호 조정
장치**다 — 유효 TA 가 있는데 재로그인하면 WSAA 가 `alreadyAuthenticated` 를 내고, 우리
코드는 그때 **같은 파일**을 다시 읽어 그 TA 를 쓴다(`afip-soap.client.ts:287`). 갈라
놓으면 한쪽이 **최대 12시간 발급 불가**가 된다.

→ `coolsistema` 한 폴더만 **중첩 bind mount** 했다:

```yaml
- /var/lib/ventago-certs:/app/certificates
- /var/lib/jenkins/workspace/certificados/coolsistema:/app/certificates/coolsistema
```

★ **심볼릭 링크는 안 된다** — `afip-cert-watch.service.ts` 가 `entry.isDirectory()` 로
거르는데 `readdir(withFileTypes)` 의 심볼릭 링크 Dirent 는 여기서 **false** 라 그 인증서가
만료 감시에서 조용히 빠진다.

부수 효과: 「나중에」로 미뤄 뒀던 **레거시 마운트 제거까지 같은 배포에서 끝났다** —
컨테이너가 보는 인증서 폴더가 **123개 → 2개**, 남의 개인키 109개가 안 보인다.

검증(전부 실측): inode 동일(6032293) · TA 기록 확인 · 레거시 부모 `No such file` ·
WSAA 로그인 + `FECompUltimoAutorizado` → A=80/B=122.

곁다리로 **slug 경로 검증**을 넣었다(CODEX 지적). `coolUser` 가 무검증으로
`path.join` 에 들어갔고 CSR 생성이 그 경로에 **파일을 쓴다** — 남의 테넌트 개인키를
덮어쓸 수 있었다. 경로를 만드는 **3곳 전부**(`carpeta`·`soap-direct`·`padron`) +
DTO `@Matches`. 검증기 `src/app/afip/cert-slug.ts`, 시험 18건.

★ 진단 스크립트 `api-ventago/scripts/afip-probe-lectura.js` — **발급 없이** 인증서
경로를 확인한다(`docker cp` → `docker exec node`). `FECAESolicitar` 는 넣지 말 것.

### 2. 인증서 상태를 파일에서도 읽는다 (`1cbaf68`)

`estado()` 가 `afip_certificados` 테이블만 봤고 그 테이블은 **0행**이라, 운영 인증서로
발급 중인 store 6 에게 화면이 **「Falta」** 라고 했다.

→ DB 행이 없으면 디스크를 읽는다(`leerDeArchivo`). 업로드 경로와 **같은 검증**을
통과한 것만 보고한다: cert 파싱 · **키 짝(modulus)** · CUIT 일치 · 환경(운영/homo).

상태를 `vencido`·`invalido`(+`motivo`)로 쪼갰다 — 셋 다 「발급이 안 된다」지만 **할 일이
다르다**(없으면 만들고 / 만료면 갱신하고 / 잘못된 파일이면 사람이 서버를 봐야).
`origen: 'db'|'archivo'`, `carpetaCompartida`, 경고 임계값(`avisoDias`/`urgenteDias`)도
응답에 실었다 — 화면에 60/14 를 박으면 `AFIP_CERT_WARN_DAYS` 변경 시 갈라진다.

운영 확인: `{"estado":"activo","origen":"archivo","diasRestantes":47,"carpetaCompartida":true}`
화면도 「Vence en 47 días」로 뜬다.

#### ⚠ 운영 인증서가 2026-10-20 만료 (핸드오프 시점 47일)

| slug | 용도 | CA | 만료 |
|---|---|---|---|
| `coolsistema` | store 6 **운영** | `Computadores` | **2026-10-20** |
| `coolsyncrohomo1` | store 9 homo | `Computadores Test` | 2028-07-03 |

**갱신 절차는 지금 동작한다**: Generar CSR → AFIP 포털 → `.crt` 업로드.
AFIP 절차가 즉시가 아니니 여유를 둘 것.

#### ★ 감시가 자기 동작을 증명하지 못했다 (같은 커밋에서 고침)

`notify()` 가 **이상이 없을 때만** 로그를 남겼다. 경보를 보내는 날에는 Telegram·메일 둘
다 성공 시 아무 말도 안 해서 로그가 통째로 비었다.

→ 그래서 나는 8일치 로그 0건을 보고 **「크론 미실행」이라고 잘못 판단했다.** 실제로는
47일 < 60일(임계값)이라 8월 21일부터 매일 «경보 경로»(무로그)를 탔을 가능성이 크다.
`@Cron` 은 27개가 정상 등록돼 있다(소스의 29건 중 하나는 **주석**, 하나는 **문자열 안**).

경보 경로에도 로그를 넣었다. CODEX 검토에서 여기 **[HIGH] 하나**가 나왔다 —
`sendMail` 이 실패를 삼키고 `void` 를 반환해서 `mailOk = true` 가 **거짓 성공**이었다
(로깅 개선을 통째로 무력화). `Promise<boolean>` 으로 바꿨다. dedup(정상)을 실패로 오인하던
것도 `sent|deduplicated|unconfigured|failed` 로 갈랐다
(`sendTelegramMessageDetailed`; 기존 boolean 함수는 그것을 감싼다).

**★ 아직 확인 안 된 것**: 8월 21일 이후 Telegram/메일로 인증서 만료 알림을 실제로
받았는지. 이제 로그로 구별되니 **08:10 UTC 이후 `[afip-cert]` 를 grep 하면 확정**된다.

### 3. 회선 배너 자동 정리 (`851faca`)

`error-bus` 는 설계상 autoDismiss 가 없어, 회선이 **한 번** 끊기면 빨간 배너가 영구히
남았다. 실측: 오전 10:31 의 순간 장애가 만든 배너가 **9시간 뒤에도** POS 화면에 있었고
그 사이 앱은 5분마다 정상 폴링에 성공했다. 화면만 보고는 「9시간 전 한 번」과 「지금
서버가 죽었다」를 구별할 수 없었다.

→ 회선 실패(`!error.response`)로 띄운 배너에 `red` 를 달고 **다음 성공 응답에서 그것만**
지운다(`errorBus.clearRed()`). HTTP 오류(4xx/5xx) 배너는 그대로 둔다 — 그건 서버가 실제로
그렇게 답한 사건이다. 시험 5건.

### 4. Facturación 화면 개편 (`2e538b5`, `bc225dd`)

사용자 요청: 「pendientes 부분은 필요없어. 오직 NC, ND, reimprimir 혹 PDF (A4)」

조사에서 **요청과 실제가 달랐다**: `Reimprimir`·`PDF A4` 는 **Emitidas 목록에 없었다.**
발급 직후 모달 안에만 있어서, 그 모달이 「usá Reimprimir cuando vuelva」라고 안내하는데
**모달을 닫으면 갈 곳이 없었다.** 그래서 «제거 + 추가» 두 가지가 됐다.

- `FacturacionShell` — Pendientes 마운트 제거. **PV 드롭다운도 제거**(그 값을 쓰는 곳이
  Pendientes 뿐이라 남기면 아무것도 안 하는 컨트롤). 파일·백엔드는 **보존** — 되돌리기 2줄.
- `voucher-actions.ts` **신규** — `reimprimirTermica`/`abrirPdfA4` 를 한 곳에.
  `PartialInvoiceModal` 도 자기 구현을 버리고 이걸 쓴다(두 화면이 갈라지지 않게).
- `EmitidasPanel` — 행마다 🖨️/PDF. NC/ND 여부와 무관(NC 자체도 종이가 필요하다).

#### ★ 판매내역에 사후 발급 진입점 (CODEX [HIGH] 대응, 사용자 선택 2번)

목록만 없애면 **앞으로도** F10 모달을 Esc 로 닫거나 AFIP 발급이 실패한 판매가
`afipStatus='no'` 로 남는데 **다시 꺼낼 방법이 영영 없다.** 운영에 이미 **32건**이 있었다
(store 6: 2건, store 9: 21건, 그 외 4개 매장 9건).

→ `SalesListView` 행에 «Facturar»(`tabler:receipt-tax`), 같은 `PartialInvoiceModal` 재사용.
판정은 `src/views/sales/list/facturable.ts` 로 뺐다 — 컴포넌트 안에 있으면 시험할 수 없고,
틀리면 판매가 갇히거나(좁음) **이중 발급을 유도한다**(넓음). 시험 11건.

운영 확인: #00002(발급됨) → Facturar **없음** / #00001($156.000) → Facturar **있음**.

모달 문구도 고쳤다: 「la venta queda en Pendientes」 → 「queda **sin facturar**」.
없는 화면을 가리키는 안내는 거짓말이다.

#### CODEX 검토에서 고친 것 (4건)

- **[MED]** 재출력이 `agent_offline` **이외의 거부를 「Enviado」로 표시**했다. 백엔드
  `dispatch` 는 「Voucher를 찾을 수 없습니다」·「Sucursal no pertenece a la tienda」 등
  5가지 이상으로 `{ok:false}` 를 준다 → **성공은 `ok === true` 하나뿐**.
- **[MED]** 중복 클릭 방지가 실제로 안 됐다. 단일 id 라 A 실행 중 B 를 눌렀다가 A 가
  먼저 끝나면 초기화돼 **도는 중인 B 가 다시 눌린다** → `useRef<Set>` 로 (전표,동작) 쌍.
- **[MED]** PDF 새 탭이 **정상 클릭에도 팝업 차단**됐다(`await` 뒤 `window.open`) →
  빈 탭을 먼저 동기적으로 열고 `location.replace`.
- **[LOW]** 캐스팅이 타입 불일치를 숨겼다(`error` vs `info`) → 재출력 반환을
  `success|warning` 으로 좁혀 캐스팅 제거.

★★ 그리고 **내가 CODEX 제안을 확인 없이 넣어 결함을 만들었다**(`bc225dd` 로 수정).
`window.open(url, name, 'noopener')` 는 **명세상 항상 null 을 반환한다**(핸들을 안 준다).
그래서 `win.location.replace` 를 못 하고 매번 「팝업 차단」 경로로 빠졌다 — 운영에서
**about:blank 탭만 뜨고 서버 요청 0건**이었다. `noopener` 를 빼고 `win.opener = null` 로 끊었다.

### 5. ARCA 월간 보고서 (`0031e24`, `cd8df68`) — 진행 중

`coolsyncro` 에 **이미 구현이 있다** — 발명이 아니라 이식이다.

#### Libro de IVA Digital 생성기 (`0031e24`) — 완료

`coolsyncro/src/main/afip/libro-iva.js` 를 `src/app/afip/libro-iva.ts` 로 그대로 옮겼다.
고정폭 2종: `VENTAS_CBTE`(266자/행) · `VENTAS_ALICUOTAS`(62자/행).

시험 **56건 통과**. 기준선(golden)이 **실제 ARCA 제출 파일(2026-08)에서 뽑은 행**이라
**바이트 단위로 비교**한다. Ventago 의 `computeNetoIva()` 가 coolsyncro 와 같은 바이트를 낸다.

원본이 피하는 함정 — 새로 짜면 그대로 밟는다:
- 기존 수기 파일은 neto/IVA 를 따로 반올림해 **170행 중 28행이 `total ≠ neto+impuesto`**
  였고(스펙 Campo 9 위반) **103행이 CAE 신고액과 1센타보 어긋났다.** 시험이 금액 500개로
  이 불변식을 검사한다.
- NC 는 같은 파일에 **양수**로 (부호는 tipo 003/008/053 가 나타낸다).
- 두 파일은 **같은 순서**여야 한다. 갈리면 ARCA 가 알리쿠오타를 엉뚱한 전표에 붙인다.
- 출력은 **순수 ASCII**. `Ñ` 하나가 UTF-8 2바이트면 그 행의 뒤 필드가 전부 밀린다.

#### 두 보고서의 쿼리 (`cd8df68`) — 완료, 아직 컨트롤러 미연결

★ **coolsyncro 는 레거시 스키마**(`fventas`·`clientes`·`provincias`)를 읽는다 — Ventago 와
다른 DB 다. **SQL 은 이식이 안 되고 다시 썼다.**

두 리포트는 **일부러 대상이 다르다.** 합계가 안 맞는다는 보고가 오면 버그가 아니다:

| | 시작 테이블 | 대상 |
|---|---|---|
| **Excel(jurisdicción)** | `FROM sales` | 그 달 **등록된 모든 판매**, CAE 없는 것도 |
| **IVA Digital** | `FROM afip_vouchers` | **발급된 전표만** |

기존 `/afip/iibb` 는 전표에서 시작하므로 **IVA Digital 쪽**이다. 중복이 아니다.
시험이 두 쿼리의 **시작 테이블**을 고정한다.

관할 코드는 이미 있다 — `provinces.cm_code`(901~924 CHECK, 902=CABA)에
`afip_vouchers.province_id` 가 붙는다.

##### ★ 테넌트 격리 (사용자 지시)

운영 실측: 2026년 8월에 판매가 있는 매장이 **5곳**이고 `WHERE s.store_id` 를 빼면 store 6 의
**53건 → 64건**이 된다. 11건이 남의 매장 매출이고 그게 그대로 회계사 신고서로 간다.

- 두 쿼리 모두 시작 테이블의 `store_id` 로 잠갔다
- 매장 소유 테이블(`afip_vouchers`·`store_clients`·`clients`·`branches`)에 조인할 때마다
  **같은 store 조건을 함께** 걸었다. FK 만 믿지 않는다
- `global_clients`·`provinces` 는 **설계상 매장 공유**라 조건을 걸지 않는다(걸면 조인이 죽는다)

정직하게: 조인 조건들은 오늘 데이터에 교차 참조가 **0건**이라 실측으로 효과를 증명할 수
없다(FK 가 막고 있다). 미래를 막는 방어선이고, 실측이 못 하는 몫을 시험이 고정한다 —
**돌연변이 3건으로 확인**(WHERE 제거 / clients 조인 조건 제거 / Excel 시작 테이블 교체).

##### ★★ coolsyncro 의 알려진 한계를 여기서 없앴다

원본은 고객의 **현재** `resiva` 로 알리쿠오타를 되계산하고, 주석에 스스로 적어 뒀다 —
「발급 후 고객의 IVA 조건이 바뀌면 인증된 comprobante 와 어긋난다. resiva 를 박제하는
마이그레이션이 근본 해결책이다」.

Ventago 는 **이미 박제한다**(`afip_vouchers.iva_alicuota`, 실측 확인). 그래서 박제값만
쓰고, **없으면 21%로 넘겨짚지 않고 실패시킨다** — 틀린 알리쿠오타 파일은 ARCA 대조에서
잡히는데 그때는 이미 신고된 뒤다.

`mes-arca.ts` — 「어느 달」 하나에서 기간·파일명. 기본값 `mesAnterior()` 는 **아르헨티나
달력** 기준이다(UTC 로 잡으면 현지 말일 밤에 한 달 틀린다 — 시험이 그 경계를 잡는다).
움직임 없는 달은 **빈 파일을 만들지 않고 거부**하고 "SIN MOVIMIENTOS" 를 안내한다.

시험 **93건 통과**(libro-iva 56 + mes-arca 19 + 서비스 18).

---

## 바로 이어서 할 일

### ③ 엔드포인트 + 모듈 등록 (다음 세션 첫 작업)

1. `afip.module.ts` 에 `ReportesArcaService` 를 **providers 에 추가** (지금 미등록 — 그래서
   동작 변화 0 이다)
2. 컨트롤러 2개:
   - `GET /afip/reportes/excel?mes=YYYY-MM` → `excelJurisdiccion()` 의 Buffer 를 xlsx 로
   - `GET /afip/reportes/iva-digital?mes=YYYY-MM` → `libroIva()` 의 두 본문을
     **`.zip` 하나로** (`2026-08-ventas.txt` + `2026-08-ventas_alicuotas.txt`)
   - `@Auth(admin, superadmin, gerente)` — vendedor 는 제외(세무 자료다)
   - `requireStoreId(user)` 로 storeId 를 넣을 것. **쿼리 파라미터로 받지 말 것**
3. 파일명은 `nombreBaseMes(mes)` 를 쓴다 — 달 전체이므로 `YYYY-MM` 이다

### ④ 프론트 — 목업대로

**목업 URL**: https://claude.ai/code/artifact/016557b5-b53b-4939-a7eb-4011be12cf07
(사용자 승인 완료 — 「mock up 대로 진행해줘」)

- 「Generar Reportajes por ARCA」 버튼 + **월 선택** 모달(기본 = 지난 달, 1일~말일 자동)
  - ★ 달력 두 개가 아니라 **달 하나**다. 사용자 결정 — 구간을 자유롭게 두면
    「8월 3일~9월 2일」 같은 파일이 만들어지고 임포트한 뒤에야 안다
  - `Carpeta de destino` 는 없다(웹앱) — 브라우저 다운로드
- **PV 드롭다운 부활** — 이제 Emitidas 목록의 실제 필터다
- **Pendientes 는 숫자 카운터만** + 「ver en Ventas →」 링크(목록 패널 없음)
- 체크박스 2개: `Mandar a AFIP automático`(=`afip_auto_issue`, store 6 은 **꺼짐**) ·
  `Imprimir x comandera térmica`
  - ⚠ **미해결 질문**: 이 둘은 설정 화면에도 같은 값이 있다. 여기서 켤 수 있게 하면 두 곳이
    갈라질 수 있다 — 여기서만 켤지, 읽기 전용으로 보여줄지 사용자에게 확인 필요
- Emitidas 액션: NC · ND · 🖨️ · PDF (이미 배포됨)

### 그 밖에 남은 것

| 우선순위 | 항목 |
|---|---|
| ★ | **인증서 갱신** — 2026-10-20 만료. 화면이 남은 일수를 알려준다 |
| ★ | 판매 187($156.000) 발급 여부 결정 |
| ★ | 감시 크론이 실제로 알림을 보냈는지 확인 (08:10 UTC 이후 `[afip-cert]` grep) |
| 중 | **거짓 0** — 화면 전환 중 금액·건수를 0으로 먼저 그린다. 측정치: `/caja-fuerte` 1746ms · `/productos` 1239ms · `/caja` 987ms · `/control-de-caja` 558ms. 원인은 `?? 0` 이 「모른다」와 「0원」을 같은 픽셀로 만드는 것. CODEX 권고 = **(다) 관측 기반 확장** + 데이터 계층에서 `loading` 보존. 범위 측정부터 |
| 중 | **속도** — 운영 route-timing 483건 실측: 전체 **P95 1192ms**(규약 300ms). `/configuracion?tab=productos` 1741 · **`/nueva-venta/` 1385**(POS!) · `/productos/` 1169. `_app.tsx:273` 의 「P95 ≤ 300ms 면 지연 스켈레톤 불필요」 전제가 **틀렸다** |
| 중 | `GET /users/:id` IDOR — `users.controller.ts:94` 에 데코레이터가 **하나도 없다**. 로그인만 하면 남의 id 조회 가능 |
| 하 | `/var/lib/ventago-certs` 가 **어떤 백업에도 없다**(레거시도 마찬가지였다) |
| 하 | POS 카탈로그 검색에 서버 폴백 없음 (`ZZ TEST UAT 7007` 미검색) |
| 하 | `afip_default_pct` 가 30% 인 것이 의도인지 |
| 하 | codex 1(NC/ND 환경 보장) · 5(`uq_afip_vouchers_serie`) · 7(NC/ND IIBB 스냅샷) |
| 하 | 게이트웨이 `CbtesAsoc` 결함 — 별도 리포라 여기서 못 고친다 |

---

## 다음 사람이 알아야 할 함정

1. **`window.open(url, name, 'noopener')` 는 항상 null 을 반환한다.** 핸들이 필요하면
   `noopener` 를 쓸 수 없다. 대신 연 뒤 `win.opener = null`.
2. **프론트의 게이트는 `next build` 다.** `npx eslint <file>` 로 exit 0 을 받은 파일 3개가
   빌드의 `lines-around-comment` 에서 걸렸다.
3. **`eslint --fix` 를 디렉터리 단위로 돌리지 말 것.** 무관한 파일 6개를 고쳐 놨다(원복함).
   파일 단위로만.
4. **프론트 시험은 `src/__tests__/` 아래여야 돈다.** jest `testMatch` 가 `**/__tests__/**`
   뿐이라 다른 곳에 두면 **조용히 실행되지 않는다.**
5. **jest 「Tests: 0」 은 통과가 아니라 미실행이다** — 컴파일이 깨진 것이다.
   이번에도 타입 좁히기 실패로 한 번 나왔다.
6. **감시가 조용한 것이 「이상 없음」이 아니다.** `notify()` 가 경보 경로에서 무로그였고,
   나는 그걸 「크론 미실행」으로 오판했다. 감시 코드는 **경보를 보낼 때도** 로그를 남겨야
   구별이 된다.
7. **`@Cron` 개수를 grep 으로 세지 말 것.** 소스의 29건 중 하나는 **주석 처리**돼 있고
   하나는 **문자열 안**에 있다. 실제 등록은 27개다.
8. **nginx 로그가 vhost 별로 갈린다.** `newapi`·`app` 은 `access.log` 가 아니라
   **`minio_acces.log`** 다. 엉뚱한 파일을 보고 「5xx 1건」이라고 잘못 말했다.
9. **cmux 브라우저는 WebKit 이다** — `layout-shift`·`longtask` PerformanceObserver 가
   **없다**(전 화면 0 이 나온다). `PerformanceObserver.supportedEntryTypes` 로 확인할 것.
10. **`history.pushState` 로는 Next Pages Router 가 안 움직인다.** 화면 전환을 몰려면
    `window.next.router.push()` 를 쓴다. pushState 로 재면 내용이 안 바뀌어 「깜빡임 없음」이
    거짓으로 나온다.
11. **상대 임계값으로 «빈 화면» 을 재지 말 것.** 「productos → caja 만 320ms 깜빡임」이
    나왔는데 최저 길이는 어느 경로에서나 **같았다**(311). 기준값이 큰 화면만 20% 선을
    넘은 artifact 였다.
12. **coolsyncro 는 레거시 스키마를 읽는다.** SQL 은 이식 대상이 아니다. 순수 함수
    (`libro-iva.js`)만 그대로 옮겨진다.
