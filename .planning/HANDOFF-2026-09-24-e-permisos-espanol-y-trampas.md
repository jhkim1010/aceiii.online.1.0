# 핸드오프 2026-09-24-e — Phase 93 **완료** · (B) 관리자 화면 권한화 · 세 개의 함정

앞 핸드오프 `HANDOFF-2026-09-24-d` 의 **뒤**다. 다음 세션은 §1(배포 상태) → §5(미해결) 순으로 읽으면 된다.

---

## 0. ★★ Phase 93 은 **끝났다** (2026-09-24, 실측으로 확인)

`93-CONTEXT.md` 의 착수 순서표 4항목 기준. 핸드오프의 「단계」 번호와는 다른 축이다.

| # | 하는 것 | 상태 |
|---|---|---|
| 1 | `ALL_ACTIONS` 제거 + 액션 컨트롤 | ✅ api #953 · front #796 |
| 2 | 스페인어화 · 가짜 임계값 탭 제거 | ✅ front #797 · #798 |
| 3 | 사이드바 14개 · aux 4개 시드 | ✅ api #952 · front #795 |
| 4 | 동사형 → 자원+동작 | ✅ PLAN 이 **「화면에서만, 데이터 변경 0」**으로 수정 → 6단계가 구현 |

#4 의 세부 조건을 **코드로 하나씩 확인**했다(선언이 아니라 확인):
- 「가드 없는 기능은 그렇게 적어 둔다」 → `RolePermissionsDrawer.tsx:490` 의 `menú` 칩 + 툴팁 ✅
- 「어긋남 2건」 → `editar-stock-de-producto` 는 `@Delete('stock-today/:parentId')` 에 붙어 있고
  **그 엔드포인트가 실제로 stock 을 destroy 한다.** 이름만 오해를 부를 뿐 가드는 부작용과 맞다 ✅
- 「컨트롤 1:1」 → 드로어가 서버 기능 목록을 그대로 순회한다(구조적 보장) ✅
- ✗ **「시험으로 못 박는다」던 불변식이 빠져 있었다** → `permisos-controles-sin-huecos.spec.ts`
  로 추가(front #800). 돌연변이 4개(네 칸 복귀·1액션도 칸으로·menú를 스위치로·모르는 액션을
  칸으로) **전부 잡힌다.**

---

## 0-b. (B) 관리자 화면 권한화 — **배포 완료** (Phase 93 밖, 사용자 제안)

| Jenkins | 커밋 | 내용 |
|---|---|---|
| front **#799** | `b8727783` | ⓐ `superadminOnly` |
| api **#954** / front **#800** | `15bcaf21` / `7138b498` | ⓒ 시드 + 17개 화면 + 불변식 시험 |

**결과: `allowedApps={['admin']}` 단독 게이트가 21개 → 0개.**

### 근본 원인 — 「권한을 잘못 줬다」가 아니었다

`admin` **앱이 잡화점**이다: `caja`(5) · `control-de-cajas`(7) 같은 **운영 모듈**을
`dashboard-admin`·`logs-auditoria` 와 같이 담고 있다. 앱 노출은 「그 앱의 **아무** 모듈에
허용 기능 1개 이상」에서 파생되므로, 계산원은 카하 기능 하나로 admin 앱을 얻는다.
실측: admin·gerente·**viewer·cashier·accountant 18/18** 보유.
⤷ **게이트가 틀린 질문을 하고 있었다.**

### ★★★ 세 개의 함정 (전부 조용히 깨지는 자리다)

1. **`WithAccess` 로는 「운영자 전용」을 쓸 수 없었다.** `PRIVILEGED_ROLES` 에 매장 `admin`
   이 있고 그 목록에 걸리면 **모든 게이트를 우회**한다 → `allowedRoles={['superadmin']}`
   라고 적어도 매장 관리자는 전부 통과. **타입도 빌드도 통과해서 안 보인다.**
   → `superadminOnly` 추가. 판정은 `roles.ts` 의 `esOperadorSaaS()`.
2. **모듈 게이트로는 화면당 제어가 안 된다.** `allowedModules` 는 「그 모듈에 허용 기능이
   1개라도 있으면」 통과 → 한 모듈에 12개를 담으면 **하나만 켜도 열두 개가 열린다.**
   → `allowedFunctions` 추가. 근거 데이터(`structure[].modules[].functions[].slug`)는
   **이미 프론트에 와 있었다**(`slimStructureForMe`).
3. **`admin` 의 privileged 우회는 사이드바에 안 통한다.** 사이드바는 `user.structure` 에서
   **파생**된다. 그래서 「부여」가 곧 사이드바를 결정하고, **SQL 이 코드보다 먼저**여야 한다 —
   순서가 뒤집히면 **모두의 사이드바에서 Configuración 이 사라진다.**

### 시드 — `2026-09-24-phase93-b-seed-configuracion.sql` (양쪽 적용 완료)

운영(5434) 모듈 1 · 기능 13 · 부여 512 · 액션 512 / 로컬(5432) 404 · 404.
부여(사용자 결정): **admin·gerente 전부 13개 · accountant 는 `configurar-facturacion` 만.**

★ **5단계와 반대로 `admin` 앱 아래**에 뒀다. 유추가 아니라 숫자로 정했다 — 받는 세 역할이
  이미 admin 앱을 18/18 갖고 있어 **앱을 새로 얻는 역할이 0**이다.
★ 재실행 멱등을 운영에서 **두 번 돌려 실측**했다(두 번째 전부 `INSERT 0 0`).
  5단계에서는 이 가드가 「변경 없음」을 찍기만 하고 **안 봤다.**

### mockup

세 안 비교: https://claude.ai/artifact/A7uh54MfNAGMKUR7husr9t (비공개 — 공유하려면 Share 필요)

---

---

## 0-c. ★★★ 백필 버그가 남긴 행 — **치워졌다** (2026-09-24)

사용자가 새 매트릭스 화면을 보고 짚었다: 「계산원이 점장보다 권한이 많은 것은 오류」.
그 화면이 처음으로 **보이게 만들어서** 드러난 것이다(종전에는 `✓` 하나로 덮여 있었다).

### 데이터로 재구성한 사건

| 시각 | 일어난 일 |
|---|---|
| 2026-07-31 01:49 | 관리자가 사용자 33(계산원)을 생성 |
| 2026-07-31 01:50 | 그 계정이 **처음 로그인** → `cashier` 에 109기능/**436액션** |
| 2026-07-31 02:45 | 같은 식으로 `inventory_clerk` 에 96기능/**384액션** |

**둘 다 감사 로그 0건.** 사람이 아니라 `/me` 의 백필이 썼다 — 그 코드는 로그인한
역할에 **시스템의 모든 함수**를 등록하고 CRUD 를 채웠다.

★★★ **코드는 이미 고쳐져 있었다.** `auth.service.ts:229-243` 이 이 버그를
  **바로 그날의 실측**과 함께 적어 뒀다(「inventory_clerk 79 → 로그인 후 175」).
  치워지지 않은 것은 **그 코드가 이미 써 놓은 행들**이다.
  ⤷ **코드 수정은 데이터를 치료하지 않는다.** 이 형태를 다음에도 의심할 것 —
    「버그를 고쳤다」와 「버그가 만든 것을 치웠다」는 다른 일이다.

### 복구 — 목표값은 짐작이 아니다

| 역할 | 전 | 제거 | 후 | 같은 `gerente`(554)인 ACE |
|---|---|---|---|---|
| `cashier` | 703 | 436 | **267** | **267** |
| `inventory_clerk` | 704 | 384 | **320** | **320** |

두 번 다 **자릿수까지 일치**한다. 마이그레이션 2개, **양쪽 DB 적용 완료**.
2026-07-31 하루를 전 매장·전 역할로 훑어 **배치는 둘뿐**, 둘 다 coolsistema.

계산원이 갖고 있던 것: `Eliminar usuario` · `Cambiar contraseña de usuarios` ·
**`Eliminar logs`** — 사용자를 지우고 그 기록도 지울 수 있었다.

★ 최종 확인: 역할 역전을 **5쌍 × 전 매장**으로 다시 훑어 **0건**.
★ 회수라 워커별 권한 캐시가 최대 60초 남는다 — 스스로 만료, 재시작 불필요.

### 같이 고친 것 — 「Legacy」 배지가 현행 역할에 붙어 있었다

사용자: 「지금 지점장이라는 role 은 없는데..」 — `Gerente de Sucursal` 은 **현행**인데
카드가 «Legacy / Rol del sistema anterior» 로 표시하고 있었다. `LEGACY_ROLE_SLUGS` 가
**Phase 30 시절 목록**(`admin`·`vendedor`·`gerente`) 그대로였다.
⤷ 화면이 **오늘 가장 중요한 역할 둘을 폐기된 것으로** 표시했고, 사용자는 그대로 읽었다.
⤷ 이제 `['vendedor']` 뿐이고, 검사가 백엔드 `SEED_DEFAULT_ROLES` 파일과 **직접 대조**한다.

### 아직 결정 대기

**`audit.read` 가 `CRUD`** 라 그 아래 「Eliminar logs」가 admin·gerente·accountant 에게
남아 있다. 감사 로그는 「누가 무엇을 바꿨나」의 유일한 기록이다.

---

---

## 0-d. ★ 열어 둔 셋 — 전부 **측정은 끝났다**, 착수만 남았다

### ① Permisos 화면 재구성 — ★ **다음 세션은 여기서 시작한다**

★★ **설계는 확정됐다**(사용자 2026-09-24): mockup 의 **①안 «세 칸»**(Miller columns).
  메뉴 → 서브메뉴 → 권한, 왼쪽에서 오른쪽으로 좁혀 간다.

**필요한 것 3가지:**
  1. **api** — 역할×기능을 한 번에 주는 엔드포인트. 지금 없다(`/role-functions/:roleId`
     는 역할 하나씩이라 7~9번 불러야 한다). `permissions.controller.ts` 에 추가.
  2. **app** — `MatrixGrid.tsx` 를 3칸 드릴다운으로 재작성.
     데이터: `/functions/structure`(트리) + `/functions/acciones-de-guardia`(가드 계약)
     + 새 엔드포인트. 셀은 `codigo-de-acciones.ts` 의 `codigoDeAcciones()` 재사용.
  3. **검사** — 기존 `permisos-matriz-dice-donde-editar.spec.ts` 가 「안내가 표보다 먼저」
     를 잰다. 구조가 바뀌면 같이 손봐야 한다.

★ 각 권한 줄에 **가드가 요구하는 액션**과 **`sólo menú`** 를 표시할 것 — 이름이 오늘
  나를 두 번 속였다(`editar-stock-de-producto`=delete, `eliminar-logs`=가드 없음).

### (배경) 왜 지금 표를 버리는가

사용자(2026-09-24): 「지금 테이블 구조는 전혀 사용자에게 와 닿지 않아. 모듈별로 어떤
서브 메뉴, 어느 서브, 어느 권한을 조절할지 **단계별 리스트**로 정리해줘.」

★★ **지금 표는 틀린 축으로 그려져 있다.** `Matriz de permisos` 는
`/permissions/matrix` 를 쓰는데 그건 **`permission_slug` 19개** 기준이다. 실제 권한은
**`functions` 182개**이고, `93-PLAN.md` 가 이미 「`permission_slug` 는 표시·별칭으로만
두고 단계적으로 폐기」라고 정했다. 즉 납작한 표를 고치는 게 아니라 **축을 바꾸는** 일이다.

mockup 2안: https://claude.ai/artifact/PXdeyqvSboArhaoy8f7zdG
  · ① 세 칸(Miller columns) — 메뉴 → 서브메뉴 → 권한, 왼→오
  · ② 아코디언 — 한 줄로 펼쳤다 접기

★ **api 엔드포인트가 필요하다.** 역할×기능을 한 번에 주는 API 가 없다 —
  `/role-functions/:roleId` 는 역할 하나씩이고, 7~9번 불러야 한다.
  (구조는 `/functions/structure`, 가드 계약은 `/functions/acciones-de-guardia`.)

### ② `ver-<모듈>` 시드 — 읽기 전용 권한이 **존재하지 않는다**

사용자: 「CodigoVista 의 권한 리스트에 단순하게 Ver 라는 권한이 없네.」

모듈 노출은 **「허용 기능 ≥1」에서 파생**되므로, 화면을 **보게만** 하려면 쓰기 기능을
하나 켜야 한다. 가드 계약으로 실측: **51개 모듈**에 `read` 만 요구하는 기능이 0개다.
그중 **5개는 가드 없는 기능조차 0개**라 「보기」가 **원천적으로 불가능**하다:

| 모듈 | 기능 | 지금 보는 역할 |
|---|---|---|
| `configuracion-productos` | 21 | 78 |
| `gastos` | 3 | 88 |
| `productos` | 3 | 78 |
| `configuracion-ventas` | 3 | 58 |
| `stocks-reportes` | 1 | 81 |

계획: 모듈마다 `ver-<모듈>`(가드 없음 = 메뉴 전용)을 INSERT 하고 **지금 그 모듈을 보는
역할에만** 부여 → 아무도 새로 얻지 않는다.
실측 규모: 기능 **51** · 부여 **5,027** · 액션 **5,027** = 약 **10,100행** (126역할 · 18매장).

★★ 행이 많은 이유는 **역할이 매장마다 따로 있기 때문**이다. 정의는 51줄뿐이다.
★ 착수한다면 **위 5개부터**가 첫 조각이다 — 거기만 「보기가 불가능」이고, 수백 행이면 된다.
★ 그 다음 조각: 페이지 게이트를 `allowedModules` → `allowedFunctions={['ver-<모듈>']}` 로.
  **안 하면** `ver-` 를 꺼도 쓰기 기능이 켜져 있으면 모듈이 계속 보여 **토글이 고장난
  것처럼 보인다.** 둘은 짝이다.

### ③ ~~CodigoVista · ClienteVista 를 Herramientas 로~~ → ✅ **완료** (`ccada75d`)

양쪽 DB 적용. **코드 배포 불필요** — `modules.app_id` 만 바꿨다.
옮기기 전 실측: `herramientas` 는 18개 매장 전부 enabled · 앱을 잃는 역할 **0개** ·
`role_functions` 무변경(보던 사람은 그대로 본다) · 사이드바 무변경(`is_auxiliary` 라
`getAppChildren()` 이 걸러 새 그룹이 안 생긴다).

원래 기록:

**두 화면이 같은 것을 다른 기준으로 묶고 있다:**

| 모듈 | 앱 | `is_auxiliary` | 사이드바 | 권한 화면 |
|---|---|---|---|---|
| `precios` (CodigoVista) | **producto** | `t` | HERRAMIENTAS | **Producto** |
| `cliente-vista` (ClienteVista) | **venta** | `t` | HERRAMIENTAS | **Venta** |
| `clientes-import` · `-history` | venta | `t` | HERRAMIENTAS | Venta |

사이드바는 `getAuxiliaryItems()` 가 **`is_auxiliary` 로 전 앱에서 끌어모으고**,
권한 화면은 **`app` 으로** 묶는다.

★★ **`app_id` 를 옮기기 전에 재야 한다.** 앱 노출이 파생이라, `precios` 를 빼면
  **`producto` 앱을 잃는 역할이 생길 수 있다**(그 역할의 유일한 producto 모듈이었다면).
  `allowedApps={['producto']}` 로 걸린 화면도 같이 확인할 것.
  ⤷ 대안: 앱을 안 옮기고 **권한 화면이 사이드바와 같은 기준(`is_auxiliary`)으로 묶게**
    하는 것 — 데이터 변경 0. ①과 같이 하면 자연스럽다.

### 그리고 결정 대기 1건

`audit.read` 가 `CRUD` 라 「Eliminar logs」가 admin·gerente·accountant 에 남아 있다.
★ **단, 확인 결과 감사 로그를 지우는 엔드포인트는 없다** — `audit-log.controller.ts` 는
  `@Get` 뿐이고 `eliminar-logs` 를 요구하는 가드도 0개다. 이름만 무서운 메뉴 전용 기능이다.
  (나는 이름을 보고 「지울 수 있다」고 사용자에게 잘못 말했다. 빼도 아무것도 안 막는다.)

---

## 1. 배포 상태 — **push 대기 없음**

| Jenkins | 커밋 | 내용 | 결과 |
|---|---|---|---|
| front **#797** | `da3b4bbd` | Phase 93 7단계 본체 | SUCCESS (220초) |
| front **#798** | `62a74fd9` | 페이지 머리말 주석 정정 | SUCCESS |

★ 앞 핸드오프 §1 이 「push 대기 4개」라고 했는데 **이미 배포돼 있었다** —
  api #953(`0c6ad344`) · front #796(`0d1f3934`), 둘 다 SUCCESS. 문서가 낡았던 것이다.
  ⤷ **핸드오프의 「미push」 목록도 믿지 말고 `git log origin/main..HEAD` 로 확인할 것.**

라이브 검증(추측 아님): `app.coolsistema.com` 이 내주는 청크에
`Matriz de permisos` 1건 · `Registro de cambios` 1건 · `승인 임계값` **0건**.

---

## 2. 한 것 — Phase 93 7단계

`/configuracion/permisos` 는 아르헨티나 직원이 쓰는데 **전부 한국어**였다. 번역만 하려다
실측하니 화면이 **여섯 가지로 사실과 달랐다.** 번역은 그중 하나였을 뿐이다.

| | 실측 근거 | 조치 |
|---|---|---|
| ① 「승인 임계값」 탭 | 정적 표에 **원화**(`₩50,000`). DB `approval_thresholds` 와 무관. 게다가 `checkThreshold` **호출부 0개** · 운영 `approval_requests` **0행** (시드만 13개 매장 130행) | 탭 + `⚠ 임계값` 칩 제거. **백엔드는 그대로** — 켤 때 쓴다 |
| ② 「Resource — CRUD」 섹션 | `functions.permission_slug` **29건이 전부 점을 포함** → 분류가 전원 business_action. **한 번도 렌더된 적 없음**. 범례 4줄은 나올 수 없는 기호를 설명 중 | 2섹션 분리 제거 → 한 표 |
| ③ 셀이 `✓` | store 6 실측: 19개 권한 × 모든 역할이 **전부 `create,read,update,delete`**. 6단계가 정리하려는 그 정보를 덮고 있었다 | 셀에 **액션 글자**(`CRUD`) |
| ④ `UserDetail` 컨트롤 3개 | 역할 셀렉트 · 회수 ✕ · 「지점 추가」 **전부 `disabled`** | 제거 + 편집이 실제로 되는 곳(«Usuarios», 경로 실재 확인) 안내 |
| ⑤ 내부 테이블명 노출 | `user_branches 매핑이 없습니다` · `audit_logs 테이블` · 날짜 `ko-KR` | 사용자 말로 · `es-AR` |
| ⑥ 감사 로그 필터 | `approval_threshold`·`threshold_change` — 그 기능을 걷어냈으므로 **행이 생길 수 없다** | 제거 |

### 새 파일
- `views/configuracion/permisos/nombres-de-permiso.ts` — 19개 slug 의 스페인어 이름
- `views/configuracion/permisos/codigo-de-acciones.ts` — 셀 판정(순수 함수)
- `__tests__/permisos-pantalla-en-espanol.spec.ts` (5) · `permisos-celda-nunca-achica.spec.ts` (9)

검증: app tsc 0 · eslint 0 · jest **73 suites / 894건**.
돌연변이 3개(모르는 액션 버리기 · null 가드 제거 · CRUD 자리 뒤집기) **전부 죽었다.**

---

## 3. ★★ 이 세션에서 배운 것 (같은 형태가 또 온다)

### ① 「AUTO-GENERATED · DO NOT EDIT」 가 **거짓이면 생성기가 함정이 된다**

`src/configs/permissions.gen.ts` 는 그 머리말을 달고 있었지만 **생성기가 만든 적이 없다.**
누군가 `type`·`label`·`hasThreshold`·`getResourceKeys`·`getBusinessActionKeys` 다섯을
손으로 넣었는데 `scripts/gen-permissions.ts` 는 **그 다섯을 만들지 않는다.**
⤷ `npm run gen:permissions` 를 한 번 돌리면 그것들이 사라지고 **빌드가 깨진다.**
⤷ 「손대지 말 것」이 지켜지지 않은 순간, 그 파일은 **아무도 재생성할 수 없는 파일**이 된다.
⤷ 조치: 생성기가 **실제로 내놓는 모양**으로 되돌리고, 사람이 쓰는 이름은
  덮어쓰이지 않는 별도 파일로 옮겼다. (그 모듈의 소비자는 앱 전체에서 `MatrixGrid` **하나**였다.)

### ② 권한 화면에서 **과소표시**는 화면을 봐도 안 보인다

`role_function_actions.action` 은 **nullable 이다**(운영 스키마 실측). `array_agg` 가
`[null]` 을 주면 종전 구현은 **빈 칩**을 그렸다 — 「권한 없음(`—`)」과 구분되지 않는다.
⤷ 보는 사람은 「없구나」로 읽고 넘어가는데 **그 역할은 그 일을 할 수 있다.**
  넓게 보이는 쪽은 최소한 눈에 띄어 누군가 따지지만, 좁게 보이는 쪽은 **아무도 안 따진다.**
⤷ 그래서 모르는 액션도 버리지 않고 덧붙이고(`R+export`), 아무 글자도 못 만들면 `?` 로
  **「있다」고** 말한다. 이 규칙은 `permisos-celda-nunca-achica.spec.ts` 가 돌연변이로 지킨다.

### ③ 판정을 `.tsx` 안에 두면 **시험할 수가 없다**

이 저장소 jest 는 `jsx: preserve` 라 spec 이 `.tsx` 를 import 하면 그 자리에서 죽는다
(`SyntaxError: Unexpected token '<'`). 그래서 `codigoDeAcciones` 를 `.ts` 로 빼냈다.
⤷ **화면 안에 있는 판정은 시험되지 않는다** — 기존 spec 이 전부 「소스 문자열 검사」인
  이유가 이것이다. 새로 판정을 만들면 처음부터 `.ts` 에 둘 것.

### ④ 소스 문자열 검사는 **양방향 대조군**이 있어야 한다

「한국어가 안 그려진다」 검사는 주석 제거 정규식이 너무 많이 지우면 **조용히 통과**한다.
그래서 대조군을 둘 뒀다 — (a) 코드 안의 한국어는 **잡히고**, (b) 주석 안의 한국어는
**안 잡힌다**(이 저장소 주석은 한국어로 쓰므로). 실제로 이 검사가 남아 있던 한국어
`console.error` 1건을 잡았고, JSX 라벨을 한국어로 되돌린 돌연변이도 죽였다.

---

## 4. 도구 메모

- **`codex exec` 가 3회 모두 죽었다** — `hook: SessionStart Failed` / `hook: PostToolUse Failed`
  직후 종료. 프롬프트 크기 문제가 아니었다(파일 1개짜리도 죽었다). **환경 쪽 문제**이므로
  다음 세션은 codex 를 믿기 전에 **작은 프롬프트로 한 번 살아 있는지 확인**할 것.
  이번에는 자문 없이 직접 적대적으로 훑었고, 그 과정에서 §3-② 가 나왔다.
- **`next build` 를 돌리지 않았다** — 포트 3050 에 dev 서버가 떠 있었고 `.next` 를 공유한다.
  돌리기 전에 `lsof -nP -iTCP:3050 -sTCP:LISTEN` 을 볼 것.
- **커밋 게이트가 `git add X && git commit` 을 또 막았다.** add 를 따로 실행.
- 청크 안의 문자열을 셀 때 **`grep -a`** — 이 저장소 번들은 바이너리로 판정된다.

---

## 5. ★ 미해결 — **이번 세션에 실측으로 다시 셌다**

앞 핸드오프의 이월 목록을 그대로 옮기지 않고 코드·DB 로 확인했다. **세 건이 달랐다.**

1. ~~**(B) 매장 관리자 전용 앱**~~ → ✅ **해소 (§0-b).** 단독 게이트 21 → **0**.
   ★ 이월하면서 두 번 틀리게 셌다: 32 → 24 → 실제 **21**. 앞의 둘은 **파일 단위 grep**
     이라 과대 계상이었다(한 파일에 `<WithAccess>` 가 여러 개고, 3개는 이미 `allowedModules`
     가 붙어 있었다). **`<WithAccess>` 단위로 세야 한다.**
   ★ 그리고 「URL 로 도달 가능」은 **화면만** 열리는 것이고 API 는 403 을 준다.
     데이터 유출이 아니라 **막다른 화면**이었다 — 처음 보고에서 과하게 말했다.

2. **Repaso(Ctrl+R) 가 판매 때마다 시계 화면으로 바뀐다** — 코드 조사는 끝났고 배제 완료
   (앞 핸드오프 §6-2 의 목록 그대로 유효, 이 세션에 관련 커밋 없음).
   ⤷ **다음은 읽는 게 아니라 재는 것.** 그 매장 화면에서:
     ① `sessionStorage.v=(+sessionStorage.v||0)+1; window.__vida=Date.now()` → 증상 뒤
       `window.__vida` 가 `undefined` 면 **새로고침된 것**.
     ② 아니면 Network 에서 `/auth/me` + 청크 재요청 → 재마운트 여부.
     ③ 둘 다 아니면 `window.__k=[]; addEventListener('keydown',e=>window.__k.push(e.key),true)`.
   ⤷ ★ 먼저 **지금 빌드에서도 재현되는지** 확인할 것.

3. **수표 중복을 서버가 막지 않는다** — 2026-09-24 실측: 운영 `cheques` **2행**,
   인덱스는 `cheques_pkey` · `idx_cheques_store_status` · `idx_cheques_due_date` ·
   `idx_cheques_sale` 뿐 — **(bank, number) UNIQUE 없음.** 지금이 가장 싸다.
   ⤷ ★★ **함정 그대로**: `nullifySale` 은 수표를 **안 건드린다.** 그냥 UNIQUE 를 걸면
     **판매를 무효화한 뒤 같은 수표를 다시 못 받는다.** 「무효화 시 수표를 어떻게 할지」가 먼저다.

4. **같은 이름 descuento/recargo 를 말없이 거부** — 앞 핸드오프는 2줄이라 했으나
   **실측 3줄**: `InvoiceAditional.tsx:547`(descuento) · `:564` · `:572`(recargo 둘).
   조용히 `return` 하는데 패널은 열린 채 남고 `focusSku()` 가 불린다 → **사용자는 적용된 줄 안다.**
   ⤷ 결정 필요: **거절하며 알리기** vs **허용**. (셋을 한 번에 — 하나만 고치면 갈라진다.)

5. **프로비저닝 경로 결함 2건** — 실측 유효: `provisionStoreAndOwner`(`auth.service.ts:775`)
   본문 105줄에 **`transaction` 이 0회** → 단일 트랜잭션이 아니다.
   `POST /store/new` 는 관리자 0명 매장을 `success: true` 로 준다.

6. **(신규) `SetupWizardView.tsx` 가 아직 한국어 + 죽은 기능을 안내한다** —
   `승인 임계값 검토` · `승인 임계값 기본값`. 이번에 「임계값은 화면에서 걷어낸다」고
   정했으므로 **그 결정과 어긋나는 자리**다. 매장 설정 마법사라 범위가 달라 손대지 않았다.

7. **(신규) 감사 로그의 action 드롭다운은 고르면 언제나 0건** — 운영의 유일한 권한 이력은
   `entity_type='role'` 의 `create` **70건** · `remove` **48건**인데 이 둘이
   `PermissionChangeData` 의 action 유니온에 **없다**(다른 경로가 쓴다).
   ⤷ 목록을 넓히는 것은 **「무엇이 정본인가」를 정한 뒤**의 일이라 손대지 않고 주석에 적어 뒀다.

---

## 6. 사람이 확인해 줘야 하는 것

1. **`/configuracion/permisos`** (배포됨 — `Ctrl+Shift+R` 필요할 수 있다):
   탭이 **3개**인지 · 제목이 `Permisos` 인지 · 셀이 `CRUD` 글자인지 ·
   각 행에 스페인어 이름 + 아래 작은 글씨로 slug 인지.
   ★ 지금은 **거의 전부 `CRUD`** 로 보일 것이다. 그게 정상이고, **그게 6단계가 정리할 대상**이다.
2. **Usuarios › 역할 › 권한** (앞 핸드오프 §7-2, 여전히 미확인) — 역할 하나를 열어
   ①앱 헤더 ②모듈 ③기능 ④`modificar-venta` 의 칩 2개, 그리고 **첫 저장이 「−N acciones」**
   를 크게 보여 주는지.
