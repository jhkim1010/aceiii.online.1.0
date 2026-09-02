# 핸드오프 2026-09-01 — IIBB 관할 · CAE 중복 차단 · 가입 즉시 개통

**전부 배포·검증 완료. 미커밋 없음.** 다음 세션은 「바로 이어서 할 일」부터.

```
api-ventago  c0d781f → 246d5d1   (Jenkins #844·845·846·847·848 전부 SUCCESS)
ventago-app  b7b4c49 → 5869788   (Jenkins #695·696·697·698 전부 SUCCESS)
루트          8e17002 → 03505cd
```

---

## 바로 이어서 할 일 (우선순위 순)

### 1. ★ coolsistema(store 6) 발급을 SOAP 직접으로 — **검증부터**

사용자 요청. **아직 아무것도 안 바꿨다.**

```
store 6 coolsistema   provider=ws    production=TRUE   ← 실제 운영
store 9 ACE           provider=soap  production=FALSE  ← homologación 전용
```

★★★ **SOAP 경로는 운영에서 한 번도 실행된 적이 없다.** store 9 의 soap 은
전부 시험 환경이고 인증서도 `coolsyncrohomo1`(homo 전용)이다.
store 6 을 바꾸면 **운영 AFIP 에 SOAP 로 처음 발급**하는 것이 된다.

#### 검증 결과 (2026-09-01) — **세 항목 모두 통과. 전환 자체를 막는 것은 없다.**

1. **인증서 — OK.** `CN=CNCOOLSISTEMA2024, CUIT 20950928434` (= `afip_issuers.cuit`),
   issuer `CN=Computadores, O=AFIP, C=AR` = **운영 CA**, 유효 2024-10-20 ~ **2026-10-20**,
   cert/key modulus 일치. 대조군으로 homo 인증서(`coolsyncrohomo1`)를 같이 읽어
   issuer 가 `CN=Computadores **Test**` 로 갈리는 것을 확인했다 — 이 구분은 실제로 작동한다.
   ★ 실호출로 확증: **WSAA 운영 로그인 성공** + FEDummy(App/Db/Auth 전부 OK).
2. **채번 — 위험 자체가 없었다.** 게이트웨이 `afip-v2.ts:30 getNextBill()` 도
   `getLastBillNumber() + 1` 이다. **자체 카운터가 없다.** 출처가 AFIP 으로 같아 어긋날 수 없다.
   실측 대조 (PV 4):

   | CbteTipo | AFIP 마지막 | 우리 DB max |
   |---|---|---|
   | 1 (Fac A) | 80 | **80** OK |
   | 6 (Fac B) | 122 | **122** OK |
   | 3 (NC A) | 29 | 0건 |
   | 8 (NC B) | 42 | 0건 |

   nro 80·122 를 `FECompConsultar` 로 열어 CAE·금액·docTipo·docNro·caeVto 까지 전부 일치 확인.
   ★ NC 는 AFIP 에 29·42 까지 있는데 Ventago 에는 0건 — **다른 시스템이 같은 PV 로 NC 를 냈다.**
     채번은 AFIP 이 쥐므로 무해하지만, 「store 6 에 NC 0건」의 이유가 이것이다.
3. **TA 캐시 — 설계상 이미 조정돼 있다.** 게이트웨이도
   `certificates/<slug>/.lastTokens` · `tokensExpireInHours: 12` 로 **경로·스키마·만료가 동일**하고
   로그인 전에 캐시를 먼저 읽는다(`AfipSoap.ts:57`). 공유가 곧 상호 조정이다.
   - `token/TA-20950928434-wsfe.xml`(2025-02)은 **어느 쪽도 안 쓰는** 제3 시스템 잔재다.
   - 우리는 root 로 쓰는데 파일은 `ubuntu:ubuntu 0660` — 실측 결과 **덮어쓰기가 소유자를 보존**해
     게이트웨이 쓰기 권한이 유지됐다. (파일이 삭제됐다 root 로 재생성되면 그때는 잃는다.)

#### ★ 검증 중 새로 나온 문제 2건 (전환 전 처리)

**A. NC/ND 는 `afip_provider` 를 아예 안 본다 — 2026-09-01 수정 완료(미커밋→커밋됨).**
`nota-credito.service.ts` · `nota-debito.service.ts` 가
`selectCaeProvider({ provider: 'ws' })` 를 **하드코딩**했다. 설정을 읽는 곳은
`AfipVoucherService.resolveProvider()` 뿐이었다.

딸려 있던 두 번째 결함: **`production` 도 안 읽었다.** `input.production ?? false` 인데
컨트롤러가 아예 안 넘긴다 → 항상 `false`. 게이트웨이가 `production` 을 **무시**해서
(게이트웨이 소스에 `production` 0건, `homo:false` 하드코딩) 드러나지 않았을 뿐이다.
**provider 만 고치고 soap 으로 넘어갔으면 NC/ND 가 homologación 으로 나갔다.**

수정: 두 서비스에 `StoreConfig` 를 **생성자 맨 뒤**에 주입(기존 spec 이
`new NotaCreditoService(a, b)` 로 직접 생성 → 앞에 끼우면 인자가 밀린다) 하고,
`resolveTarget()` 이 **config 를 한 번 읽어 provider 와 production 을 함께** 돌려준다.
따로 구하면 조합이 갈라진다.

★ 검증: 기존 spec 은 `_provider` 를 override 하므로 **새 로직을 한 줄도 안 지난다.**
  그래서 override 없는 describe 를 따로 붙였고, **돌연변이 2종**(provider→'ws',
  production→호출자 인자)이 각각 죽는 것을 확인했다.

**B. 게이트웨이는 `CondicionIVAReceptorId` 를 안 보낸다 — 급하지 않다(기준일 확인 완료).**
게이트웨이 전체 소스에서 `CondicionIVAReceptor` **0건**. 우리 SOAP 은 보낸다.
(우리는 REST 게이트웨이 호출 body 에 이미 `condicionIVAReceptorId` 를 실어 보낸다 —
`rest-gateway.provider.ts:90`. **게이트웨이가 무시할 뿐**이라 게이트웨이 쪽 수정만으로도 해결된다.)

★★★ **기준일은 2026-09-01 이 아니라 2026-12-01 이다.** 코드에 적혀 있던 9월은
Phase 59(2026-07-20)에 **근거 없이** 쓴 값이었다. ARCA 공식 개발자 매뉴얼
(`arca.gob.ar/fe/ayuda/documentos/wsfev1-RG-4291.pdf`, RG 4291 Proyecto FE) 개정 이력 원문:

> **4.8 | 01/12/2026** — "Será obligatorio el campo Condición Frente al IVA del receptor,
> atento a la entrada en vigencia reglamentada por la Resolución General N°5616.
> Por tal motivo los códigos de error **10245** para CAE y **825** para CAEA quedaran en desuso."

- 그 전까지 미전송은 **관측(observación) 10245** — "resultará obligatorio"(미래형). **발급은 된다.**
- 거부 코드 **10246** 은 "es obligatorio"(현재형)로 오류표에 있으나, 시행일 이후 동작한다.
- 매뉴얼 전체에서 RG 5616 과 묶인 날짜는 **01/12/2026 뿐**이다. 바로 직전 개정
  **4.7(01/09/2026)** 은 Seguros de Caución 건이고 이 필드와 무관하다.
- 2차 자료(블로그·요약글)는 9월과 12월이 엇갈린다. **매뉴얼 원문을 근거로 삼을 것.**

→ 코드 주석 2곳(`soap-direct.provider.ts` · `wsfe-types.ts`)을 12-01 로 정정했다(미커밋).
→ **남은 시간 3개월.** SOAP 전환의 근거는 «오늘 거부됨» 이 아니라 «게이트웨이가 이 필드를
   영영 안 보낸다» 이다. 급하지 않으므로 **A 를 먼저 고치고** 전환하는 순서가 맞다.

★ 남긴 것: `certificates/coolsistema/.lastTokens.bak-20260901-162505`
  (전환 전 스냅샷. 만료된 TA 라 무해하고 어느 시스템도 `.bak-*` 를 읽지 않는다.)

#### ★★ codex 자문 결과 — A 를 고치다 나온 7건 (2026-09-01)

**고침**

**C. SOAP 경로가 `CbtesAsoc` 를 조용히 버렸다.** `[3, 8, 13]`(NCA/NCB/NCC)로 걸러
   **ND 전체(2·7·12·52·20)와 NCM(53)·NCE(21)** 가 빠졌다 — 10개 중 3개만 나갔다.
   (codex 는 ND 5개를 짚었고, 전수로 세어 NCM·NCE 2개를 더 찾았다.)
   `asoc` 를 세우는 곳이 NC/ND 두 곳뿐이므로 **타입 목록을 없애고** «있으면 보낸다» 로 바꿨다.
   근거: ARCA 오류 10040 의 허용 CbteTipo 목록에 ND 02·07·12·52 가 있다.
   타입별 전수 테스트 + 대조군(asoc 없으면 미전송) 추가. 돌연변이가 정확히 7건을 죽인다.
   ★ **게이트웨이에도 같은 결함이 있다** (`isCreditNote = [3,8,13]`). 우리 REST provider 는
     `associatedVoucher` 를 항상 보내는데 **게이트웨이가 거기서 버린다** — 즉 오늘 운영에서도
     ND 의 원본 참조는 나가지 않는다. 게이트웨이는 별도 리포라 여기서 못 고친다.

**안 고침 — 각각 별개 작업이다 (스키마 변경이 필요한 것이 여럿)**

| # | 항목 | 왜 별개인가 |
|---|---|---|
| 1 | **원본과 NC/ND 의 AFIP 환경이 같다는 보장이 없다** | 전표에 «어느 환경에서 발급됐는지» 컬럼이 없다. config 를 한 번 읽는 것으론 과거를 알 수 없다. 해결하려면 컬럼 추가(expand→migrate→contract) 또는 발급 전 AFIP 조회. ★ 계획된 store 6 전환(ws→soap)은 **양쪽 다 production** 이라 이 건에 안 걸린다 |
| ~~2~~ | ~~**reconciliación 이 틀린 환경을 조회할 수 있다**~~ **→ 2026-09-02 해결** | 조회 환경을 현재 `afipProduction` 으로 정한다. `ws + production=false` 매장은 실제로는 운영 발급인데 homo 를 조회 → 미기록 CAE 를 «없음» 으로 보고 `liberar` 제안 → **중복 발급**. 기존 결함 |
| ~~3~~ | ~~**NC/ND 에는 `verificar` 같은 재발급 차단 상태가 없다**~~ **→ 2026-09-01 해결** | 팩투라는 `sales.afipStatus='verificar'` 로 못박는데 NC/ND 는 `ambiguous:true` 만 반환한다. 다시 누르면 재발급된다. CAE 성공 후 `create()` 실패도 마찬가지. 게다가 **모든 23505 를 «이미 존재»로 처리**해 번호 유니크 충돌(=두 번째 CAE)을 숨긴다 |
| 5 | **번호 유니크가 환경·CUIT 를 구분 안 한다** | `uq_afip_vouchers_serie (store_id, punto_venta, tipo_comprobante, afip_number)`. 환경을 바꾸면 양쪽에 같은 번호가 정상적으로 존재한다 |
| ~~6~~ | ~~**NC/ND 의 `condIvaReceptor` 가 원본과 다를 수 있다**~~ **→ 2026-09-01 해결** | `condIvaReceptorFor({ cbteTipo, resiva: undefined })` → B/C 는 항상 Consumidor Final. 원본 수신자가 Exento·Monotributo 였어도 그렇다. 전표에 스냅샷이 없다. **게이트웨이가 이 필드를 안 보내서 숨어 있었고, SOAP 전환이 드러낸다** |
| 7 | **NC/ND 가 IIBB `provinceId` 를 저장 안 한다** | 팩투라는 필수 저장인데 NC/ND 의 `create()` 에 없다 → 조회가 «현재» 주소로 폴백해 원본과 다른 관할에 귀속될 수 있다. 이번 IIBB 작업의 구멍 |

★ 6번과 3번이 **store 6 전환의 실제 사정거리 안**에 있다. 전환 전에 판단할 것.
★ `AfipVoucherService.issue()` 는 public 이고 직접 호출하면 config 를 안 읽고 'ws' 로 폴백한다.
  현재 호출자는 없지만 우회 진입점이 될 수 있다.

전환은 한 줄이고 복귀도 한 줄:
```sql
UPDATE store_configs SET afip_provider='soap' WHERE store_id=6;   -- 복귀: 'ws'
```

★ **화면에는 이 항목이 없다** (프론트·DTO 모두 `afipProvider` 참조 0건).
  DB 에만 있고 `AfipVoucherService.resolveProvider()` 한 곳에서만 읽는다.
  화면 추가는 **동작을 확인한 뒤에** 할 것 — 검증 안 된 선택지를 올리면 누가 누른다.

### 2. ★ `dbtunnel` 전용 계정 — 내가 만든 위험을 닫는다

DBeaver 접속용으로 `~/.ssh/id_dbeaver`(**passphrase 없음**)를 만들어
서버 `jhkim` 계정에 등록했다. 그런데 `jhkim ALL=(ALL) NOPASSWD: ALL` 이라
**그 키 하나가 곧 root** 다(codex CRITICAL).

현재 제한: `permitopen="127.0.0.1:5434",no-agent-forwarding,no-X11-forwarding`
→ 5433(PG10) 등 다른 포트로는 못 간다. 하지만 셸은 열린다.

해결: sudo 없는 전용 계정을 만들고 키를 옮긴다. DBeaver 는 User Name 한 칸만 바꾼다.

★★ **SSH 키 제한과 DBeaver 의 충돌 조합**(4번 실패하고 알아냄):

| 옵션 | 결과 |
|---|---|
| `restrict` | ✗ PTY 를 막는데 DBeaver 가 요청 → `Connection reset` |
| `command="…"` (어떤 형태든) | ✗ 세션 동작을 건드려 실패 |
| **`permitopen=…`** | **✓ 동작** — 포워딩 목적지만 제한 |

### 3. ~~사용자 확인 대기 (3개)~~ — **2026-09-01 전부 확인됨**

- ~~DBeaver `Test Connection` 통과 여부~~ → OK
- ~~`/configuracion/` 중복 이름 저장 시 «Ya existe…» 안내~~ → OK
- ~~Facturación 에서 IIBB xlsx 다운로드~~ → OK

### 4. 미해결 위험 (codex 점검)

| 심각도 | 항목 |
|---|---|
| CRITICAL | **PG10 `0.0.0.0/0 md5`** · 126 테넌트 · EOL 2022-11 |
| HIGH | 앱 포트 7개 직접 공개 · pgbouncer 5432 평문 |
| — | ufw inactive, iptables INPUT ACCEPT |

★★★ **방화벽으로 막으면 매장이 즉시 죽는다.** codex 권고 순서:
`① 72시간 접속원 수집(읽기 전용, 안전) → ② 권한 조사 → ③ 보호 경로 병행 구축
→ ④ 매장 소수씩 이전 → ⑤ 마지막에 0.0.0.0/0 제거`
**①을 건너뛰고 ③~⑤를 하면 안 된다.**

절차는 스킬로 저장했다: `.claude/skills/revision-servidor-produccion/`

### 5. 작은 것들

- 지점 16 `HELGUERA` 주(州) 미설정 — 그 지점 CF 판매 발급 시 미확정이 생긴다
- 크레딧 노트 음수 처리 — store 6 에 NC 0건이라 **실제 데이터로 검증 못 함**
- Dropbox `todas/` 보존 정책 미정 (자동 삭제 안 걸어 둠)

---

## 이번 세션에 한 일

### 백업 + 자동 복구 시험
126개 테넌트 DB 백업이 9개월 전이 마지막이었다. 이제 매일 돈다.
`운영 01:30 덤프 → 서버2 03:00 당겨와 표본 4개 실제 복원 → 운영 04:20 부재 감시`
★ 복원 «성공» 을 믿지 않고 **덤프의 테이블 수와 대조**한다.
상세: `scripts/backup/README.md`

### IIBB (Convenio Multilateral) 관할
★★★ **관할은 구입자 주소다.** 판매자·지점 주소가 아니다(사용자 정정).
지점으로 폴백하면 화면에 그럴듯한 값이 미리 차서 **판매원이 구입자를 안 물어본다.**
그래서 폴백 «경로 자체» 를 없앴다. 보고서에만 옛 전표용 폴백이 남아 있다.

- 발급 시 관할 필수. 못 정하면 **AFIP 을 부르기 전에** 거부
- `GET /afip/iibb` · `/afip/iibb/xlsx` (회계사 Hoja1 형식 + Resumen 시트)
- 기간은 **아르헨티나 달력**으로 자른다 (UTC 면 말일 21~24시가 다음 달로 넘어감)
- 크레딧 노트는 **음수**로 싣는다
- 마이그레이션 3건 적용(로컬 5432 + 운영 5434 대조 완료)

### CAE 중복 차단 + verificar 해소
CAE 수신 후 저장이 실패하면 판매가 `en_progreso` 로 남고 10분 뒤 재클레임이
열려 **두 번째 CAE** 가 나갔다. 이제 `verificar` 로 못박는다.
`verificar` 를 푸는 경로가 **어디에도 없었다** → 진단·해소 화면을 새로 만들었다.
★ 조회는 발급 provider 와 분리(`ConsultorAfip`) — 게이트웨이 매장도 SOAP 로 조회.
★ 붙이기는 수신자·금액을 대조한다. 번호 존재만으로 붙이면 남의 전표를 귀속시킨다.

### 가입 즉시 개통 + 3일 시한
인증 끝나면 매장을 바로 만들고, 3일 내 미승인 시 자동 정지(2일차 텔레그램 예고).
★ 만료 로직이 개통된 신청을 `expired` 로 바꾸면 정지 크론이 영영 못 잡는다 → 제외.

### 상품 삭제 + 중복 이름 409
- 자식 있는 마드레는 **실제 삭제 불가**(parent_id 가 SET NULL → 고아). 소프트 삭제로.
- CodigoVista `Borrados` 체크박스 + `Restaurar`
- 중복 이름 500 → **409**. 전역 필터에서 처리 —
  `(name, store_id)` 유니크가 **12개 테이블**이라 개별로 고치면 빠뜨린다.

---

## 다음 사람이 알아야 할 함정

1. **jest 「N passed」는 무엇이 통과했는지 말하지 않는다.** 컴파일 깨진 suite 는
   조용히 빠진다. `Test Suites:` 를 함께 볼 것. 돌연변이의 `Tests: 0` 은 미실행이다.
2. **돌연변이가 컴파일을 깨뜨리면 그 자체가 좋은 신호** — 타입 시스템이 이미 막고 있다.
3. **느린 쿼리 상위는 거의 항상 레거시 임포트·일회성 정리다.** 거르지 않으면
   «시스템이 느리다» 로 오독한다. 진짜 지표는 «호출 많은 쿼리가 빠른가»
   (실측: 오늘 API 689건 중 300ms 초과 1건, 핫패스 0.0~0.2ms).
4. **화면 깜빡임이 성능이 아닐 수 있다.** 이번엔 500 반복이었다.
5. **`nc -z` 로는 `permitopen` 을 검증할 수 없다** — 로컬 리스너만 본다.
6. **`Details >>` 한 줄이 추측 네 번보다 빠르다.**

---

## 2026-09-01 (오후) — 추가로 끝낸 것

```
api-ventago  246d5d1 → ca1b1ed   (Jenkins #849·850·851·852 전부 SUCCESS)
ventago-app  5869788 → 80f6a6b   (Jenkins #699·700 전부 SUCCESS)
```

### A. NC/ND 가 `afip_provider`·`production` 을 읽는다  ✅ 배포
`resolveTarget()` 이 config 를 **한 번 읽어 둘을 함께** 돌려준다. 따로 구하면
`soap` + `production=false` 조합이 생겨 NC 만 homologación 으로 나간다.

### C. SOAP 이 `CbtesAsoc` 를 버리던 것  ✅ 배포
`[3,8,13]` 으로 걸러 **10개 중 7개**(ND 전체 + NCM·NCE)가 빠졌다. 타입 목록을 없앴다.
★ **게이트웨이에도 같은 결함이 있다** (`isCreditNote = [3,8,13]`) — 오늘 운영에서도
  ND 의 원본 참조가 안 나간다. 별도 리포라 여기서 못 고친다. **남은 일.**

### RG 5616 기준일 정정  ✅ 배포
`2026-09-01` → **`2026-12-01`**. Phase 59 에서 근거 없이 적은 값이었다.
ARCA 매뉴얼 wsfev1 RG-4291 **v4.8(01/12/2026)** 원문 확인. 2차 자료는 9월/12월로 엇갈린다.

### NC 를 이미 낸 전표에 NC 버튼이 계속 보이던 것  ✅ 배포 (사용자 요청)
화면이 행의 `notaCredito`(=«이 행이 NC 이다»)를 «이 팩투라에 NC 가 있다» 로 읽었다.
`listEmitidas` 가 `hasNotaCredito`/`hasNotaDebito` 를 실어 보낸다.
★ 하루치 목록 안에서 찾으면 안 된다 — NC 는 다른 날 발급될 수 있다.

### 6. 수신자 IVA 조건 스냅샷  ✅ 배포 + 마이그레이션
`afip_vouchers.cond_iva_receptor` (nullable). NC/ND 가 원본에서 물려받고, 자기 행에도
이어 붙인다. NULL(운영 19건)은 종전 계산식 폴백.

### 3. NC/ND 예약 — 두 번째 CAE 차단  ✅ 배포 + 마이그레이션
`afip_nota_reservas` 신규. AFIP 을 부르기 **전에** 자리를 잡아 두 번째 요청이
AFIP 에 **도달하지 못하게** 한다. 성공 시 전표 INSERT 와 같은 트랜잭션에서 삭제,
ambiguous 는 `verificar` 로 남긴다. `23505` 를 제약 이름으로 갈라
«받아 적지 못한 CAE» 를 더 이상 숨기지 않는다.
해소는 **사람이** (`GET /afip/notas/pendientes` + `NotasPendientesPanel`).
크론 자동 해소 없음 — 「조회 실패 = 미발급」 오판이 곧 이중발급이다.

★★ **왜 별도 테이블인가**: `afip_vouchers` 안에 예약 행을 두면 CAE 없는 행이
   모든 조회에 노출되는데 거르는 곳이 없다. 특히 **IIBB 보고서에 `cae IS NOT NULL`
   필터가 없어** 회계사 xlsx 에 빈 행이 실리고 금액이 관할 합계에 더해진다.
   별도 테이블이라 `afip_vouchers` 읽는 코드는 한 줄도 안 바뀌었다.

### 남은 codex 지적 (1·2·5·7)
| # | 항목 |
|---|---|
| 1 | 원본과 NC/ND 의 AFIP 환경이 같다는 보장이 없다 (전표에 환경 컬럼이 없다) |
| 2 | reconciliación 이 현재 `afipProduction` 으로 조회 환경을 정한다 → `ws`+`production=false` 매장은 틀린 환경을 본다 |
| 5 | `uq_afip_vouchers_serie` 가 환경·CUIT 를 구분 안 한다 |
| 7 | NC/ND 가 IIBB `provinceId` 스냅샷을 저장 안 한다 (이번 IIBB 작업의 구멍) |

### ~~store 6 전환은 아직 안 했다~~ → **2026-09-01 전환 완료**
검증이 전부 통과하고 전환을 막던 6·3 이 닫혀서 그날 바로 전환했다:
```sql
UPDATE store_configs SET afip_provider='soap' WHERE store_id=6;   -- 복귀: 'ws'
```
★ **첫 SOAP 발급은 아직 안 나갔다** — 확인 절차는 09-02 핸드오프의 「바로 이어서 할 일 1」.

---

## 이어지는 세션

2026-09-02 작업(인증서 자가 발급 · store 6 SOAP 전환 확인 대기 · 설정 UX · codex #2)은
**`HANDOFF-2026-09-02-certificados-y-soap.md`** 로 옮겼다. 여기 두 벌로 두면 어느 쪽이
최신인지 알 수 없다 — 그 파일이 최신이다.
