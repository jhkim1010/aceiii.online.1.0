# 권한 실측 점검 2026-09-22 — 더미 계정으로 직접 재고, 고친 것과 남은 것

핸드오프 `HANDOFF-2026-09-22-pos-단축키와-점검.md` §5 의 「§3 관리·설정 재점검」에 해당한다.
그 문서가 «admin 계정으로는 F1 을 잴 수 없다 — 판매원 시험 계정이 필요하다» 고 적어 둔 그 계정을
실제로 만들어 **로그인해서** 쟀다.

## 시험 장치 (지우지 않는다)

로컬 `ventago`(PG18:5432) · 로컬 API(5002) · 로컬 운영빌드 프론트(3050) · cmux 브라우저 2창.

| 계정 | 역할 | 쓰임 |
|---|---|---|
| `perm.admin@dummy.test` (id 188) | admin (store 6) | 권한을 **주고 뺏는** 쪽 · 회귀 대조군 |
| `perm.vendedor@dummy.test` (185) | vendedor (store 6) | 제한이 걸리는 쪽 |
| `perm.sinrol@dummy.test` (186) | **역할 0개** | ★ 대조군. 「가드가 있다」를 가르는 잣대 |
| `perm.otra@dummy.test` (187) | vendedor (store 9) | 테넌트 격리 |

비밀번호는 저장소에 적지 않는다 — 네 계정 모두 같은 값이고, 값은 메모리
(`permission-test-accounts-exist`)에 있다. 브라우저 프로필 `permadmin` / `permvendedor` 로 두 세션을 동시에 띄웠다.

★ **역할 0개 계정이 이 점검의 핵심이다.** vendedor 로만 재면 「이 역할이 허용된 것」과
  「아무도 막지 않는 것」을 구분할 수 없다. 실제로 그 구분이 아래 P1 들을 드러냈다.

★★ 시험 중 만들어진 것: branch 1436 · price_types 2186·2187 · roles 3849(삭제 시험으로 제거됨).
   남겨 둔다. 지우면 「무권한 쓰기가 실제로 성공했다」는 증거가 사라진다.

---

## 1. 확정된 결함 — 고쳤다

전부 **역할 0개 계정으로 재현**했고, 고친 뒤 `403 / admin은 통과` 를 다시 쟀다.

| # | 결함 | 근거(실측) | 수정 |
|---|---|---|---|
| P1-1 | `POST·PATCH·DELETE /role` **가드 전무** | 역할0 계정이 role 을 **실제 생성**(id 3849) 하고 **삭제**했다(DB 0행 확인). 매장의 `vendedor` 역할을 지우면 직원 전원이 권한을 잃는다 | `role.controller.ts` 쓰기 3개에 `@Auth(admin, superadmin)` |
| P1-2 | `POST /price-types` 무가드 | 역할0 계정이 **행 2개를 INSERT**(2186·2187) | 쓰기 5개에 `@Auth(admin, superadmin, gerente)` — 같은 파일 `toggle-status` 와 같은 집합 |
| P1-3 | `POST /notifications` 무가드 | 역할0 계정이 `{"success":true}` — `sendNotificationToAll` | `@Auth(admin, superadmin)` |
| P1-4 | `POST·PUT·DELETE /stocks` 무가드(`@Audit` 만) | 역할0 계정이 유효성 검사까지 도달(=가드 통과) | 세 개에 `@Auth(admin, superadmin, gerente)` |
| P1-5 | `PUT·DELETE /prices/:id` 무가드 | 동상 | 두 개에 같은 집합 |
| P1-6 | `POST /discounts` 3종 무가드 | 동상. 할인율은 곧 매출 | 세 개에 같은 집합 |
| P1-7 | `POST·PATCH /movements` 무가드 | 동상 | 같은 집합 |
| P1-8 | `PUT /cash-register/:id` 무가드 | 동상 | 같은 집합 |
| P2-1 | `GET /users` 가 `@Auth()`(역할 인자 없음) | 판매원이 매장 전 직원의 이름·이메일·역할을 200 으로 받았다 | `@Auth(admin, superadmin, gerente)` |
| P2-2 | `GET /audit-log` 계열에 역할 제한 없음 | 판매원이 동료의 활동 기록 전체를 열람 | 5개 라우트에 `@Auth(admin, superadmin, gerente)` |

★ **가드는 전부 메서드 단위로 붙였다.** 클래스에 올리면 같은 컨트롤러의
  `POST /stocks/movement`(POS 판매 한복판) · `GET /discounts/all` · `GET /prices/matrix` ·
  `GET /cash-register/open` 이 함께 막혀 **판매가 즉시 깨진다**. 호출부를 전수로 확인한 뒤 정했다.

★★ 좁혀도 되는 근거: 위 쓰기 경로들은 웹·Flutter·에이전트 통틀어 **프론트 호출부가 0건**이거나
  이미 admin 앱 뒤 화면에서만 불린다. 웹의 가격 변경은 `POST /products/bulk-update-prices` 를 쓴다.

### 화면 접근 (판매원 = ventas 만)

| # | 결함 | 수정 |
|---|---|---|
| P1-9 | **`WithAccess` 가 `allowedRoles` 를 무시했다** — 타입에는 있는데 구조분해에서 빠져 있었다. 넘겨도 아무것도 막지 않으면서 **타입 검사는 통과**한다 | 배선 복구 |
| P1-10 | 판매원이 URL 직접 입력으로 `/facturacion` 진입 (메뉴에선 `roles: supervisorRoles` 로 숨겨져 있었다) | 페이지에 `allowedRoles={SUPERVISOR_ROLES}` — 메뉴와 **같은 집합** |
| P1-11 | `/cheques` 에 **가드가 하나도 없었다** (첫 줄 주석은 「+ ACL」이라고 적혀 있었다) | Tesorería 허브와 **같은 근거**(`/caja` 모듈)로 판정 |
| P1-12 | `/configuracion` 의 Productos 탭이 앱만 보고 모듈을 안 봐서, **`/productos` 는 막히는데 그 설정 탭은 열렸다**(카테고리·공급업체가 보였다) | `requiredModules: ['productos']` — `/productos` 페이지와 같은 게이트 |
| P1-13 | 허용 탭 0개일 때 `return null` → **빈 화면** | `/unauthorized` 로 보낸다 |

### 「시스템 고장처럼 보이는 것」 (사용자 지시)

| # | 결함 | 수정 |
|---|---|---|
| UX-1 | 403 이 500 과 **같은 붉은 배너**로 떴다. 판매원의 `/facturacion` 화면에 `Forbidden resource` 와 `GET /afip/notas/pendientes · HTTP 403` 이 그대로 찍혔다 | 403 → 경고 톤 + «No tenés permiso para esta acción», 기술 상세 제거. 판정은 `api-error-presentation.ts` 단일 출처 |
| UX-2 | `/unauthorized` 화면이 **404 그림**을 쓰고 있었다 — 「페이지가 없다」로 읽힌다 | 같은 폴더의 `401.png` 로 교체 + 문구를 아르헨티나 표기(`tenés`)로, 「관리자에게 요청하라」를 덧붙임 |

★ 403 을 **무음으로 만들지 않았다.** 누른 버튼이 아무 반응도 없으면 같은 조작을 반복한다.
★★ 500·회선 실패 배너는 **그대로 둔다.** 같이 순화하면 «저장 실패» 를 사용자가 못 보고 넘어간다.

---

## 2. 권한 토글은 실제로 작동한다 (실측)

admin 창에서 권한을 주고 빼면서 판매원 쪽을 매번 다시 쟀다.

| 단계 | `POST /products` |
|---|---|
| 부여 전 | **403** |
| admin 이 `crear-producto` 부여 → 1초 뒤 | **400**(유효성) = 통과 |
| 회수 → 1초 뒤 | **403** |

`crear-venta` 로도 같은 라운드트립을 했다(POST /sales 400 ↔ 403).
판정 캐시(60초)는 `role_functions` 갱신 시 무효화가 **실제로 돈다**.

---

## 3. 「이상 없음」으로 판정한 것 — 목록에서 뺀다

- **POS 단축키 F2/F10/Ctrl+S 가 `crear-venta` 를 무시한다** → 위협 아님. `crear-venta` 를 빼고
  `POST /sales` 를 쏘면 **서버가 403 을 준다.** 남는 것은 「눌러도 안 되는 키」라는 UX 문제뿐이다.
- `GET /role` · `GET /role/store/:id` → 테넌트 훅이 자기 매장으로 거른다(실측: store 6 만 10행).
- `GET /users/store/9` → 403 «No podés ver usuarios de otra tienda.» 정상.
- `POST /functions` · `POST /modules` → 403(매장 스코프 훅). 단 **오류 문구가 한국어**다(별건).
- `/facturacion` 의 `GET /afip/emitidas` 가 vendedor 를 허용하는 것은 `@Auth(..., vendedor)` 로
  **명시된 설계**다. 이번에 화면을 막았으므로 도달 경로가 사라졌다.

---

## 4. 남은 것 — 사용자 결정이 필요하다

### ★★ 클래스 레벨 `@Auth(역할)` 이 **28곳에서 아무것도 막지 않는다**

`UserRoleGuard` 가 `reflector.get('roles', context.getHandler())` 로 **핸들러만** 읽는다
(`user-role.guard.ts:23-26`). 그래서 `@Controller` 위에 붙인 `@Auth(역할)` 은 조용히 무시된다.

실측: `GET /talleres/settlements` → **역할 0개 계정도 200**(공방 정산 데이터).

해당 28곳에는 `seeders.controller.ts`(`@Auth(superadmin)`, 주석에 "2차 방어선"이라고 적혀 있다)와
`shared-folders-admin.controller.ts`(`@Auth(admin, superadmin)`)도 포함된다.

**고치는 방법은 한 줄이다** — `getAllAndOverride([getHandler(), getClass()])`.
**그런데 그 한 줄이 28개 컨트롤러의 접근을 한꺼번에 실제로 바꾼다.**

위험: 가드의 alias 표(`user-role.guard.ts:8-14`)에 **`inventory_clerk`·`accountant`·`viewer` 가 없다.**
운영에 `inventory_clerk` 사용자가 **1명** 있다(2026-09-22 실측). 28곳 중 그 역할을 목록에 적지 않은
컨트롤러(subcon·production 다수)에서 그 사람이 **갑자기 막힌다.**

★★★ **이 상태를 지키는 시험이 이미 있고, 통과하고 있다.**
  `seeders-access.spec.ts:64-74` 는 「클래스 위에 `@Auth(ValidRoles.superadmin)` 문자열이 있는가」를
  소스에서 찾아 확인하고 «2차 방어선» 이라고 이름 붙였다. 위치까지 단언한다.
  **그런데 그 데코레이터는 실제로 아무도 막지 않는다.** 소스 문자열 검사가
  동작을 재는 것으로 읽힌 전형이다 — 가드를 고칠 때 이 시험도 **동작을 재도록** 바꿔야 한다.

→ 선택지:
1. 가드를 고치고, 28곳의 역할 목록을 **실제 사용 역할 기준으로 먼저 보정**한다(안전하지만 일이 많다)
2. 가드를 고치고 alias 에 `inventory_clerk → vendedor` 등을 추가한다(빠르지만 권한이 넓어진다)
3. 28곳을 메서드 단위로 내린다(가장 명시적, 가장 오래 걸린다)

### 그 밖에 아직 안 고친 것

- `GET /talleres/defects` → 판매원 200(빈 배열). 위 28곳 문제의 일부다.
- 「권한 없는 **버튼**은 비활성 + 툴팁」 — 이번엔 **페이지 진입**까지만 했다.
  화면 안의 개별 버튼은 다음 단계다(대상을 먼저 세야 한다).
- `POST /functions`·`POST /modules` 의 거절 문구가 **한국어**다(스페인어 화면).

---

## 5. 회귀 확인 (대조군)

★ **admin 창으로 매번 다시 쟀다.** 한 번은 여기서 실제로 회귀를 잡았다 —
  `/configuracion` 리다이렉트를 `loading` 확인 없이 넣었더니 **admin 도 `/unauthorized` 로 튕겼다**.
  (Tesorería 허브가 같은 함정을 이미 주석으로 남겨 뒀는데도 그대로 밟았다.)

수정 후 최종 실측:

| 경로 | admin | vendedor |
|---|---|---|
| `/facturacion` `/cheques` `/configuracion` `/productos` `/usuarios` `/admin/auditoria` | 전부 열림 | 전부 `/unauthorized` |
| `/nueva-venta` `/ventas` `/reportes-v2` | 열림 | **열림**(회귀 없음) |

API: 10개 경로에서 `ven=403 · nada=403 · adm=200/201/400/404`.

시험: `src/__tests__/api-error-presentation.spec.ts` (app).
돌연변이 3종으로 확인했다 — 403 분기 제거 · 경고→오류 · **인터셉터가 판정을 버림** 전부 잡힌다.
