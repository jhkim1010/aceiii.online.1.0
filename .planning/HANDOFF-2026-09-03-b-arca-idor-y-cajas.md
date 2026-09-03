# 핸드오프 2026-09-03 (b) — ARCA 엔드포인트 · IDOR · 카하 금액 오류

앞 세션은 `HANDOFF-2026-09-03-arca-reportes-y-facturacion.md`.

```
api-ventago  1cbaf68 → 18ae385   (Jenkins #861~#864 SUCCESS)
ventago-app  bc225dd → 2796051   (Jenkins #707~#711)
```

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

## 이 세션에서 CODEX 가 잡은 «내가 만든» 결함 셋 (기록)

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

---

## 남은 것

| 우선순위 | 항목 |
|---|---|
| ★ | **인증서 만료 2026-10-20** (핸드오프 시점 47일). 갱신 절차는 화면에서 동작한다 |
| ★ | 감시 크론 알림 확인 — 컨테이너 재생성으로 이전 로그가 없다. **내일 08:10 UTC 이후** `[afip-cert]` grep |
| ★ | JuanaCaja 의 닫히지 않은 근무 6개 (42일) — 닫을지 사용자 결정 필요 |
| ★ | **ARCA 보고서 화면 육안 검증이 아직 없다** — 로그인이 필요해 못 했다. Excel 53행 / IVA Digital 4건이 나와야 맞다 |
| 중 | 판매 190($144.000) 미발급 (187 은 발급 불필요로 접수) |
| 중 | `/configuracion?tab=productos` 1741ms — 엔드포인트 11개, `price-types/all` **중복**. 대부분 SWR 훅이 이미 있는데 안 쓴다 |
| 하 | 거짓 0 나머지 — 금액 이름이 붙은 `?? 0` 이 110곳. 측정된 화면부터 했다 |
| 하 | `afip_default_pct` 30% 가 의도인지 |

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
