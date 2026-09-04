# 핸드오프 2026-09-03 (b) — ARCA 엔드포인트 · IDOR · 카하 금액 오류

앞 세션은 `HANDOFF-2026-09-03-arca-reportes-y-facturacion.md`.

```
api-ventago  1cbaf68 → e4d75bf   (#861~#864 SUCCESS · 그 뒤 2건 빌드 미확인)
ventago-app  bc225dd → e180b6b   (#707~#711 SUCCESS · 그 뒤 2건 빌드 미확인)
```

⚠ **마지막 두 커밋(api `095e3a0`·`e4d75bf` / app `95c4784`·`e180b6b`)의 Jenkins 결과를
아직 못 봤다.** SSH 키가 에이전트에서 빠지고(passphrase 필요) `prod-ssh` MCP 도
시간초과라 운영 서버로 가는 두 경로가 동시에 막혔다. 다음 세션 **첫 일**로 확인할 것:

```bash
ssh-add --apple-use-keychain ~/.ssh/id_ed25519   # 사용자가 직접(passphrase)
ssh jhkim-server "for j in api-new-coolsistema front-coolsistema; do \
  n=\$(ls -1v /var/lib/jenkins/jobs/\$j/builds | grep -E '^[0-9]+\$' | tail -1); \
  echo -n \"\$j #\$n \"; grep -oE '<result>[A-Z]+</result>' \
  /var/lib/jenkins/jobs/\$j/builds/\$n/build.xml; done"
```

push 전 로컬 검증은 끝났다 — api 674건 · front 319건 · 양쪽 build · verify-models.

★ **앞 핸드오프의 「cd8df68 까지 배포됨」은 사실이 아니었다** — 원격은 `1cbaf68`
이었고 `0031e24`·`cd8df68` 은 push 된 적이 없었다. 모듈 미등록이라 동작 영향은 없었다.

---

## ★★★ 오늘 가장 큰 것 — 카하 목록의 금액이 틀려 있었다

사용자가 「이 숫자들은 오늘 판매 상태인가」라고 물어 확인하러 갔다가 찾았다.

```
JuanaCaja   화면 $845.900   실제 $805.900   (+$40.000)
«Total en cajas visibles» 도 같은 만큼 틀렸다
```

**원인 — 조인 팬아웃.**

```sql
COALESCE(SUM(cr.initial_amount), 0) + <movNeto>
FROM cash_registers cr
LEFT JOIN box_operations bo ON bo.cash_register_id = cr.id
GROUP BY cr.box_id          -- ← 근무가 아니라 카하로 묶는다
```

근무 하나에 움직임이 N개면 그 근무의 행이 **N번 복제**되고
`SUM(cr.initial_amount)` 가 초기금을 N번 더한다.

기전까지 맞췄다: JuanaCaja 의 열린 근무 6개 중 **하나만** 움직임이 5건이고
그 근무 초기금이 $10.000 → `10.000 × 5 = 50.000` = **+$40.000**. 화면 차이와 일치.

`cashRegister.service.ts` 의 같은 식은 **`GROUP BY cr.id`** 라 멀쩡했다 —
★ **식이 같아도 묶는 단위가 다르면 결과가 다르다.**

→ `LEFT JOIN LATERAL` 로 근무별 소계를 먼저 접는다. 운영 10개 카하 전부 차이 0.

### 함께 알게 된 것 (미해결)

`Saldo actual` = **열린 근무**의 초기금 + 그 근무의 입출금. 근무를 안 닫으면 누적된다.

| 카하 | 열린 근무 | 가장 오래된 것 |
|---|---|---|
| Caja 1 | 2 | 2026-09-03 (오늘) |
| Caja de HELGUERA | 1 | 2026-09-03 (오늘) |
| **JuanaCaja** | **6** | **2026-07-23 (42일 전)** |

★ **JuanaCaja 의 근무 6개를 닫을지 사용자에게 물었고 답을 못 받았다.**
데이터 상태라 임의로 닫지 않았다.

---

## ★★ IDOR — 문이 셋이었다

`users.controller` 12개 라우트 중 **둘에 가드가 하나도 없었다.** 전역
`JwtGlobalGuard` 는 **로그인만** 강제하므로, 가드 없는 라우트는 «비공개» 가 아니라
**«로그인한 아무나»** 다.

```
GET /users/:id             — id 를 1 부터 세면 전 매장 사용자
GET /users/store/:storeId  — URL 의 매장 id 로 전 직원을 검색·페이징 (더 나쁨)
```

두 번째는 **URL 을 만들 필요도 없었다** — `/admin/tiendas` 가
`allowedApps={["admin"]}` 로만 막혀 있고 그 앱은 운영 **12개 매장 전부**에 켜져 있다.

**CODEX 가 세 번째 문을 찾았다**: `GET /users`(가드는 있다)의 `findAllForUser` 가
`!isSuperadmin && authUser?.storeId` 라, **매장 없는 비-superadmin** 이 조건 없는
목록을 받았다. 운영에 그런 계정은 현재 0건이지만 **fail-open 이라 언제든 열린다.**

- 타 매장은 **404**(403 아님) — 403 은 「그 id 는 존재한다」를 알려준다
- 비밀번호·mobilePin 은 **안 샜다** — 모델 defaultScope 가 막는다.
  Sequelize 6 이 두 `exclude` 를 **합치는지 덮어쓰는지**가 갈림길이라 재현해 확인(합친다)

---

## `xlsx` 가 운영 컨테이너에 없었다 (2곳)

```
docker exec api_ventago ls node_modules/xlsx → No such file or directory
```

`api-ventago/package.json` 에 없고 모노레포 루트로 호이스팅된 것이라 **로컬에서만**
풀렸다. Dockerfile 은 자기 package.json 으로만 `npm install` 한다.
`require` 가 메서드 안이라 **부팅은 통과하고 그 엔드포인트만 500.**

- `excelJurisdiccion` (ARCA) → exceljs
- `GET /code-import/template` (빈 양식) → exceljs
  ★ 앞서 「엑셀 **업로드** 500」이라 말했는데 **틀렸다** — 업로드는 JSON 을 받는다

---

## 「거짓 0」 — 핸드오프의 원인 진단이 반쯤 틀렸다

앞 핸드오프는 원인을 `?? 0` 이라 했는데, 측정된 느린 화면 3개 중 `/productos`·
`/caja`·`/control-de-caja` 의 views 에는 `?? 0` 이 **0건**이다.
진짜 원인은 **loading 추적이 없다**는 것 — `useCajaFuerte.getBalance` 에는 아예 없어서
`getCajaFuerte` 가 끝나면 loading=false 인데 balance 는 null 이라 $0 이 그려졌다.

`src/utils/monto-conocido.ts` — 모르면 «—», **진짜 0원은 $0**.
같은 화면의 `CajasOverviewCard` 가 이미 그 규칙을 쓰고 있었다(선례를 따랐다).

---

## 속도 — 재집계

★ 첫 집계가 **압축된 옛 로그를 빼먹어** 낮게 나왔다(P95 432ms). 전체 1067건:

| | P50 | P95 | n |
|---|---|---|---|
| 전체 | 171 | **1003** | 1067 |
| `/configuracion/?tab=productos` | 354 | **1741** | 28 |
| `/nueva-venta/` (POS) | 323 | 1266 | **167** |
| `/productos/` | **420** | 1135 | 138 |

300ms 초과 **33.1%**.

`/store-config/:storeId` 를 컨텍스트가 이미 들고 있는데 **4곳**이 또 받고 있었다.
셋을 전환(ProductsView · POS ProductList · BasicDataCard).
남은 1곳은 `ConfigurationView` — **설정을 편집하는** 화면이라 저장 후 갱신 흐름이 얽힌다.

---

## 이 세션에서 CODEX 가 잡은 «내가 만든» 결함 (기록)

1. **POS 회귀** — 컨텍스트로 바꾸자 `StoreConfigProvider` 가 매장 전환 시 `loaded` 를
   안 내린다는 사실이 실제 동작 차이가 됐다(새 사용자가 앞 매장 설정으로 POS 를 연다).
   POS 가 자기 요청을 하던 동안에는 자가 교정됐다.
2. **파일 삭제** — 저장 실패 시 빈 파일을 치우려 `handle.remove()` 를 넣었는데,
   저장 대화상자에서는 **기존 파일도 고를 수 있다.** 「방금 만든 빈 파일」과
   「원래 있던 빈 파일」을 구별할 API 가 없어 **삭제를 포기**했다.
   문구에서도 「지워라」를 뺐다 — 같은 이유로.
3. **틀린 SKU** — 컨텍스트는 실패해도 `loaded` 를 참으로 두고 **기본값**을 들고 있다.
   종전에는 `storeConfig === null` 이 SKU 생성 게이트였는데 내가 그것을 없앨 뻔했다.
   → 컨텍스트가 `fallo` 를 따로 내보낸다. **`loaded` 는 「끝났다」지 「성공했다」가 아니다.**
4. **모든 금액이 0** — 카하의 「오늘/누적」을 만들면서 `AT TIME ZONE stores.timezone`
   을 검증 없이 썼다. 그 컬럼은 임의 문자열이라 오타 하나면 쿼리 전체가 죽고,
   catch 가 삼켜 **화면의 모든 카하 잔액이 0** 이 된다 — 같은 날 아침에 고친
   「거짓 0」 을 저녁에 내 손으로 되살릴 뻔했다.
5. **자정 경계 오판** — 「여러 날인가」를 브라우저 시간대로 비교했다.

★ 다섯 다 같은 형태다 — **없애도 되는 안전장치라고 착각했거나, 모르는 쪽에 판단을
맡겼다.** 이 세션에서 CODEX 가 잡은 것이 도합 **20건 남짓**이고, 그중 절반 이상이
내가 «개선» 하면서 만든 것이었다.

---

---

## Pendientes 의 뜻을 좁혔다 (사용자 지시 · 승인)

「pendientes 는 ARCA 로 전송하라고 했는데 문제가 발생해서 영수증 발급이 안 된
경우에만 거기에 넣도록」.

**구별 자체가 없었다.** `sales.afip_status` 의 `no` 가 두 가지를 같이 담았다:
F10 을 Esc 로 닫아 **안 보낸** 판매와, 보내려 했는데 **실패한** 판매
(`afip-voucher.service` 의 «fatal → no 복구»). 그래서 손을 써야 하는 건이
운영 34건 안에 묻혔다.

| | |
|---|---|
| 발급 실패 | `afip_status='error'` + **사유**(`sales.afip_error`) |
| `listPendientes` | `'error'` 만 |
| `cancelPendiente` | `'no'`·`'error'` **둘 다** — `no` 를 빼면 판매내역의 취소가 조용히 0건이 된다 |
| `verificar` | **일부러 제외** — AFIP 에 전표가 있을 수 있어 취소로 덮으면 묻힌다 |
| 프론트 `esFacturable` | `'error'` 도 대상 — 안 열면 실패한 판매가 영영 갇힌다 |
| 툴바 | `Fallaron en ARCA` + **사유를 툴팁에** (목록 패널이 없으므로) |

마이그레이션 `2026-09-03-sales-afip-error.sql` — **양쪽 적용 확인**.

★ **기존 34건은 안 건드렸다.** 어느 것이 «실패» 였는지 알 방법이 없다 — 그 정보를
저장한 적이 없다. 없는 사실을 만들지 않는다. 카운터가 잠시 0 이 된다. 그것이 정확하다.

★★ CODEX 가 **내 범위 서술**을 바로잡았다. `ambiguous=false` 실패에는 AFIP 의 거절뿐
아니라 **인증서 만료·WSAA 로그인 실패처럼 전송 전에 죽은 것**도 들어온다. 동작을
좁히지 않고 **문구를 고쳤다** — 지시가 「전송하라고 했는데 발급이 안 된 경우」였고
인증서 때문에 못 나간 판매도 사람이 손을 써야 한다.
**구별되는 것은 «시도했는가» 이지 «누가 거절했는가» 가 아니다.**
그리고 `error` 를 **벗어나는 모든 전이**에서 사유를 지운다(facturado·verificar 3곳·
cancelado). 성공 경로만 지우면 `cancelado` 행에 옛 사유가 붙어 남는다.

---

## 카하 — 「오늘」과 「누적」을 나눈다 (사용자 요청)

「caja 가 여러 날 cierra 되지 않은 경우 (오늘 활동: 0, 누적: 805900) 라는 식으로」.

```
$805.900
hoy $0 · acum. desde 2026-07-23      ← 여러 날에 걸친 서랍에만 붙는다
```

★ 오늘 연 서랍은 **안 쪼갠다** — 두 수가 같아 「오늘 300.001 · 누적 300.001」 은 잡음이다.

응답에 셋을 더했다: `movHoy` · `abiertaDesde` · `arrastraDiasPrevios`.

### CODEX 2건 — 하나는 그날 고친 버그를 되살릴 뻔했다

- **[P1]** `stores.timezone` 은 임의 문자열을 받는 컬럼이다. 오타 하나면
  `AT TIME ZONE` 이 예외를 던져 **잔액 쿼리 전체가 실패**하고, catch 가 삼켜서
  **모든 카하 잔액이 0** 이 된다 — 같은 날 고친 「거짓 0」 그 자체다.
  → `pg_timezone_names` 에 실재할 때만 쓴다(현재 잘못된 값 0건이지만 손으로 바뀔 수 있다).
- **[P2]** 「여러 날인가」를 브라우저가 자기 시간대로 판정하면 매장과 다를 때 자정
  경계에서 틀린다 → **서버가 판정해 boolean 으로** 준다.

운영 검증: JuanaCaja `arrastra=t`(누적 805.900 / 오늘 0 / 2026-07-23), 오늘 연 둘은 `f`.

## 남은 것

| 우선순위 | 항목 |
|---|---|
| ★ | **인증서 만료 2026-10-20** (핸드오프 시점 47일). 갱신 절차는 화면에서 동작한다 |
| ★ | 감시 크론 알림 확인 — 컨테이너 재생성으로 이전 로그가 없다. **내일 08:10 UTC 이후** `[afip-cert]` grep |
| ★★ | **JuanaCaja 마감 — `countedCash` 답을 기다리는 중.** 사용자가 「닫아주고」 라고 했지만 **내가 SQL 로 닫으면 안 된다**(아래 참조) |
| ★ | **ARCA 보고서 화면 육안 검증이 아직 없다** — 로그인이 필요해 못 했다. Excel 53행 / IVA Digital 4건이 나와야 맞다 |
| 중 | 판매 190($144.000) 미발급 (187 은 **발급 불필요로 접수**) |
| 중 | `/configuracion?tab=productos` 1741ms — 엔드포인트 11개, `price-types/all` **중복**. 대부분 SWR 훅이 이미 있는데 안 쓴다 |
| 하 | 거짓 0 나머지 — 금액 이름이 붙은 `?? 0` 이 110곳. 측정된 화면부터 했다 |
| 하 | `afip_default_pct` 30% 가 의도인지 |
| 하 | `/configuracion?tab=productos` 의 마지막 `store-config` 중복 — **설정을 편집하는** 화면이라 저장 후 갱신 흐름이 얽힌다. 그 탭은 엔드포인트 11개를 부르고 `price-types/all` 이 중복이며, 대부분 SWR 훅이 이미 있는데 안 쓴다 |

## ★★ JuanaCaja 마감 — 왜 내가 안 했나

사용자가 「닫아주고」 라고 했다. 그런데 **SQL 로 `closing_time` 을 채우면 안 된다** —
정식 마감은 세션만 닫는 게 아니라 **돈을 금고로 이체**한다(`retiro` + 금고 `ingreso`
+ `box_settlements` 기록). 단순 UPDATE 로 닫으면 $805.900 이 **장부 없이 사라진다**.

그리고 크론이 42일간 안 한 것은 **버그가 아니다**:

```
CATCHUP_DAYS = 3
★ 이 창이 있는 이유: 배포 당시 운영에 미마감 24건이 2026-04-10 까지 쌓여 있었다.
  그 백로그는 실사가 필요한 건이라 자동으로 돈을 움직이면 안 된다(사용자 결정).
```

**전에 사용자가 직접 내린 결정**이고, JuanaCaja 가 정확히 그 백로그다.

정식 경로: `/caja` → 정산 대기 → **«Regularizar»**
(`POST /cash-register/settlement-queue/:boxId/regularize`, admin 전용, 감사 로그 남음)

| 필드 | 값 |
|---|---|
| `through` | `2026-08-10` |
| **`countedCash`** | **서랍을 열어 실제로 센 현금** — 서버가 정할 수 없는 유일한 값 |
| `notes` | 사유(필수, 3자 이상) |

장부값은 **$805.900**(초기금 $42.000 + 움직임 $763.900). 두 선택지:

- `countedCash: 0` → **이체 없이 구간만 닫는다**(7~8월 돈이 이미 다른 경로로 정리된 경우)
- `countedCash: 805900` → $805.900 을 금고로 이체

차액은 `box_settlements` 에 남고 `review_required` 로 표시된다.
**실제 현금 상태는 코드가 알 수 없다 — 사람이 정해야 한다.**

## 다음 사람이 알아야 할 함정

1. **로그 집계는 `.gz` 를 포함해야 한다.** 압축된 옛 로그를 빼먹어 P95 를 절반 이하로
   잘못 냈다. `/app/logs/perf-*.log` 만 보면 며칠치가 통째로 빠진다.
2. **`loaded` 는 「성공」이 아니다.** 실패해도 참이고 값은 기본값이다. 그 기본값으로
   무언가를 «만들면»(SKU·코드) 조용히 틀린 것이 나온다.
3. **템플릿 리터럴 안의 SQL 주석에 백틱을 쓰지 말 것.** 문자열이 끊겨 TS 오류가
   엉뚱한 줄에서 난다.
4. **jest mock 은 receiver 를 안 본다.** `window.showSaveFilePicker` 를 떼어 부르면
   실제 브라우저는 `Illegal invocation` 을 던지는데 mock 은 통과한다 —
   mock 이 `this` 를 검사하게 만들어야 잡힌다.
5. **개발 기계 시간대가 시험을 무의미하게 만들 수 있다.** 「아르헨티나 달력」 로직을
   지워도 17건이 전부 통과했다(이 기계가 America/Buenos_Aires). `jest.global-setup.js`
   가 UTC 를 강제한다. 시험 파일 안에서 `process.env.TZ` 를 바꾸는 것은 **너무 늦다.**
6. **`type="month"` 는 브라우저마다 다르게 그려진다.** 이 환경에서는 달력 없이 그냥
   글자 입력칸이었다.
7. **SQL 로 카하를 닫지 말 것.** 마감은 돈을 금고로 이체한다. `closing_time` 만
   채우면 잔액이 장부 없이 사라진다.
8. **`AT TIME ZONE <컬럼>` 은 그 컬럼이 임의 문자열이면 위험하다.** 오타 하나로
   쿼리 전체가 죽고, catch 가 삼키면 **화면의 모든 금액이 0** 이 된다.
   `pg_timezone_names` 로 거를 것.
9. **「오늘」 판정을 브라우저에 맡기지 말 것.** 매장 타임존과 다르면 자정 경계에서
   틀린다. 서버가 판정해 boolean 으로 내려보낸다.
   — 이 세션에서 **같은 형태가 세 번** 나왔다(거짓 0 · 낡은 응답 · 오늘 판정):
   **모르는 쪽이 판단하면 안 된다.**
