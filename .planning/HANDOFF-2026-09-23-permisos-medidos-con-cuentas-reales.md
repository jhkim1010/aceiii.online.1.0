# 핸드오프 2026-09-23 — 권한을 더미 계정으로 직접 재고 고쳤다

다음 세션은 **§6(다음 할 일)** 부터 보면 된다. §1~§5 는 배포까지 끝났다.

핸드오프 `HANDOFF-2026-09-22-pos-단축키와-점검.md` §5 의 「§3 관리·설정 재점검」과,
그 문서가 «admin 계정으로는 F1 을 잴 수 없다 — 판매원 시험 계정이 필요하다» 고
적어 둔 그 계정을 **실제로 만들어 로그인해서** 잰 결과다.

---

## 0. 이 세션의 방법 — 이것이 결과를 갈랐다

더미 계정 **4개**를 만들고 브라우저 **2창**(admin / 판매원)을 동시에 띄워 쟀다.

| 계정 | id | 역할 | 쓰임 |
|---|---|---|---|
| `perm.admin@dummy.test` | 188 | admin (store 6) | 권한을 주고 뺏는 쪽 · **회귀 대조군** |
| `perm.vendedor@dummy.test` | 185 | vendedor (store 6) | 제한이 걸리는 쪽 |
| `perm.sinrol@dummy.test` | 186 | **역할 0개** | ★★ 가드 유무의 잣대 |
| `perm.otra@dummy.test` | 187 | vendedor (store 9) | 테넌트 격리 |

비밀번호는 저장소에 적지 않는다 — 값은 메모리 `permission-test-accounts-exist` 에 있다.
브라우저 프로필 `permadmin` / `permvendedor` 로 두 세션을 동시에 유지했다.

★★ **역할 0개 계정이 핵심이다.** vendedor 로만 재면 「이 역할이 허용된 것」과
  「아무도 막지 않는 것」이 구분되지 않는다. 그 구분이 무가드 쓰기 경로 **16개**를 드러냈다.

★ **응답 코드만 믿지 말 것.** `PATCH /role/21` 은 200 을 줬지만 DB 는 안 바뀌었고
  (DTO whitelist), `POST /role` 은 201 과 함께 **행이 실제로 생겼다.** DB 로 확인한다.

★ 환경: 로컬 API 를 로컬 `ventago`(5432)로 띄웠다 — `.env` 기본값은 staging(15432)을
  가리키므로 `DATABASE_NAME=ventago DATABASE_PORT=5432` 를 덮어써야 한다.
  cmux 브라우저는 **운영 빌드**여야 하이드레이션된다(`next build && next start -p 3050`).

---

## 1. 배포 완료 (운영 반영됨)

| 커밋 | 내용 |
|---|---|
| api `32744e5c` | 무권한 쓰기 경로 **10곳** 차단 (role·stocks·prices·discounts·movements·cash-register·notifications·users·audit-log) |
| api `0dc49803` | **클래스 레벨 `@Auth` 가 실제로 작동하게** + 판매원을 Tesorería 에서 제외 |
| api `fcdaaace` | `CrudController` **상속 라우트 37개 전수 차단** (역할0 통과 7→0) |
| api `68c92cc3` | AI 도우미가 **사용자 언어로** 답한다 (한국어·스페인어) |
| app `ea9fc19` | `WithAccess` 의 `allowedRoles` 배선 복구 · 화면 3개 차단 · 403 을 경고 톤으로 |
| app `f5d6c5e` | 화면 역할 판정에도 서버와 **같은 alias** 적용 |
| app `950a44b` | Sucursales 가 빈 데이터로 죽던 것 · Mi suscripción 문구 |
| root `6be652d` · `582017c` · `a3c4429` · `30cfbab` · `524494a` | 점검 문서 · 포인터 · **Phase 93** |

근거 문서: `.planning/AUDIT-2026-09-22-permisos-medido.md`

---

## 2. 실제로 뚫려 있던 것 (전부 역할 0개 계정으로 재현)

**DB 로 확인한 실제 쓰기 성공:**
- `POST /role` → 역할 생성(id 3849), `DELETE /role/:id` → 삭제(0행 확인).
  매장의 `vendedor` 역할을 지우면 **직원 전원이 권한을 잃는다.**
- `POST /price-types` → `price_types` 2행 INSERT
- `POST /prices` → `prices` 227725 INSERT (판매가)
- `POST /configuration` → `configurations` 481 INSERT
- `POST /notifications` → `sendNotificationToAll` 이 `{"success":true}`

**가드를 지나가기만 한 것**(유효성·404 까지 도달): stocks 쓰기 3 · prices 쓰기 2 ·
discounts 쓰기 3 · movements 쓰기 2 · cash-register PUT/POST/DELETE · box-operation 쓰기 3 ·
recharges 쓰기 2 · module-alias 쓰기 2

**역할 인자가 없어 열려 있던 조회:** `GET /users`(직원 이름·이메일·역할) ·
`GET /audit-log` 5개(동료 활동 기록)

---

## 3. 이번에 확인된 「같은 형태」 — 다음에도 먼저 의심할 것

1. **클래스 레벨 `@Auth(역할)` 은 아무것도 막지 않았다** — `UserRoleGuard` 가
   `getHandler()` 만 읽었다. **26곳**이 그 상태였고 `seeders`(superadmin 전용)도 포함됐다.
   → `getAllAndOverride([getHandler(), getClass()])` 로 고침.
2. **`CrudController` 상속 라우트는 파일을 읽어도 안 보인다** — 데코레이터가 부모에 있다.
   `box-operation.controller.ts` 를 끝까지 읽어도 `PUT /box-operation/:id` 의 존재가 안 나온다.
   **라우트 목록은 소스가 아니라 실제 요청으로 세야 한다.** 37개 컨트롤러가 상속한다.
3. **소스 문자열 검사는 동작을 재지 않는다** — `seeders-access.spec` 이
   「클래스 위에 `@Auth(superadmin)` **문자열**이 있는가」만 보며 «2차 방어선» 이라 부르고
   계속 통과했다. 그 데코레이터는 아무것도 안 막고 있었다. → **동작 시험으로 교체**.
4. **`WithAccess` 의 `allowedRoles` 는 타입에만 있고 구조분해에서 빠져 있었다** —
   넘겨도 안 막히면서 타입 검사는 통과한다.
5. **배선을 살리면 alias 도 같이 살려야 한다** — `allowedRoles` 를 복구하니
   프론트에 백엔드의 role alias(`cashier→vendedor` 등)가 없어
   「API 는 통과하는데 화면은 막힌다」가 될 뻔했다.
6. **`@Get(':id')` 는 반드시 맨 뒤** — Nest 는 선언 순서로 매칭한다. 위에 뒀더니
   `/expenses/daily-summary` 를 삼켜 **판매 화면이 판매원에게 403** 이 됐다.
   가드가 `ParseIntPipe` 보다 먼저 돌아 400 이 아니라 **403** 이라 원인을 찾기 어렵다.
7. **빈 데이터 하나가 화면 전체를 죽인다** — `pt.name.toUpperCase()` 가
   `name: NULL` 행에서 터져 `/sucursales` 가 통째로 안 열렸다.
8. **경로를 나눠도 문구를 안 나누면 혼동은 남는다** — `/mi-suscripcion` 이
   «facturas emitidas» 라고 해서 `/facturacion › Emitidas`(매장이 AFIP 로 끊은 전표)로 읽혔다.
   파일 주석은 「경로를 나눠 혼동을 막는다」고 적혀 있었다 — 나눈 것은 경로뿐이었다.

★ **대조군이 회귀를 두 번 잡았다**: `/configuracion` 리다이렉트를 `loading` 확인 없이
  넣어 **admin 도 튕겼고**, 위 6번이 판매 화면을 죽였다. admin 창으로 매번 다시 잰 덕이다.

---

## 4. 권한 토글은 실제로 작동한다 (실측)

| 단계 | `POST /products` |
|---|---|
| 부여 전 | **403** |
| admin 이 `crear-producto` 부여 → 1초 뒤 | **400**(유효성) = 통과 |
| 회수 → 1초 뒤 | **403** |

판정 캐시(60초)의 무효화가 **실제로 돈다**. `crear-venta` 로도 같은 왕복을 했다.

**메뉴 파생도 정상이다**: 판매원의 보고서 권한 14개를 전부 빼자
`/auth/me` structure 에서 `reportes` 앱이 사라지고 사이드바에서 **메뉴가 없어졌으며**
`/reportes-v2` 직접 진입도 `/unauthorized` 였다. 권한을 되돌리니 메뉴도 돌아왔다.

---

## 5. 최종 실측 (수정 후)

| | admin | vendedor | 역할 0개 |
|---|---|---|---|
| `/facturacion` `/cheques` `/configuracion` `/productos` `/usuarios` `/admin/auditoria` | 전부 열림 | 전부 `/unauthorized` | — |
| Tesorería 6화면 (`/tesoreria` `/caja` `/control-de-caja` `/gastos` `/cheques` `/caja-fuerte`) | 전부 열림 | 전부 `/unauthorized` | — |
| `/nueva-venta` `/ventas` `/reportes-v2` `/cliente-vista` `/ventas-online` | 열림 | **열림**(회귀 없음) | — |
| CrudController 상속 라우트 37개 | 정상 | 정상 | **통과 0건** |

운영: Jenkins api #935·#936, front #771·#772 전부 SUCCESS · 컨테이너 재생성 확인 · **5xx 0건**.

---

## 6. 다음 할 일

1. **Phase 93 — 권한을 4단계로.** 사용자가 이 세션에서 지시해 등록했다.
   `.planning/phases/93-permisos-4-niveles/93-CONTEXT.md` · Mock-up
   https://claude.ai/artifact/BTnotmcsJBvFLwm6VvCNNP (아트보드 4장)
   착수 순서가 위험 낮은 것부터 4단으로 나뉘어 있다. **1~3번은 데이터를 안 바꾼다.**
2. **AI 지식 검색이 언어를 넘지 못한다** — 답변 언어는 고쳤지만, 검색은 단어 매칭이라
   한국어 질문이 스페인어 문서(운영 110건 중 **98건**)와 안 겹친다. 그 98건에 대해서는
   「매뉴얼에서 찾을 수 없습니다」가 — 이제 한국어로 — 나온다.
   질의 번역이나 언어별 색인이 필요하다.
3. **`CrudController` 자체를 닫는 것**은 아직 안 했다. 이번엔 **뚫린 7개 컨트롤러만**
   덮었다(16개 라우트). 부모(`src/common/crud/crud.controller.ts`)에 기본 가드를 두는 편이
   근본적이지만, 37개 상속처의 회귀 범위를 먼저 재야 한다.
4. **`@Auth()`(역할 인자 없음)가 아직 많다** — 「로그인만」을 뜻한다.
   이번에 `GET /users` 하나를 고쳤다. 나머지는 세어 보지 않았다.
5. §1·§4 의 미해결분(전 핸드오프) — AFIP Emitidas 의 UTC 날짜창, 발급 모달 Enter,
   판매 수정 중 Suspender 복제는 **그대로 남아 있다.**

---

## 7. 이 세션이 만든 것 / 지운 것

**남겼다 (시험 장치):** 더미 계정 4개 · 브라우저 프로필 2개.
**지웠다 (화면을 깨뜨리던 빈 행):** `price_types` 2186·2187·2188 ·
`prices` 227725 · `configurations` 481 · `branches` 1436(+caja·terminal 각 1).
세 테이블 모두 `name is null` 이 지금 **0건**이다.

★ 그 빈 행들은 **가드가 없던 시절의 시험이 만든 것**이다. 지금은 그 경로가 전부 막혔으므로
  같은 방식으로는 다시 생기지 않는다. 그래도 화면 쪽에 방어를 넣었다(`SIN NOMBRE`).

**새 시험:** `crud-inherited-routes.spec`(50건) · `idioma-respuesta.spec`(10건) ·
`api-error-presentation.spec`(5건) · `role-alias-parity.spec`(5건) ·
`seeders-access.spec`(동작 시험으로 교체).
전부 **대조군**과 **돌연변이 검증**을 거쳤다.
