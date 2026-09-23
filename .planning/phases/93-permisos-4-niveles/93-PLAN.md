# Phase 93 착수 계획 — 권한 4단계 + 역할 정리

작성 2026-09-23. **codex 자문 반영본.** 원안(`93-CONTEXT.md` 의 착수 순서)을 **바꾼다.**
근거는 전부 이 세션에서 직접 측정했다(로컬 5432 · 운영 5434 · 소스 전수 · codex 교차검증).

사용자 결정 2026-09-23:
- `store_owner` → **`admin`** 으로 병합
- 착수는 **위험 순서 우선**
- 사용자 0명 역할(Contador·Solo Lectura·Encargado de Stock·Responsable de Envíos)은 **건드리지 않는다**

---

## 0. 착수 전에 드러난 결함 — 이것부터 고치지 않으면 Phase 93 이 성립하지 않는다

### [P1-a] 로그인이 권한을 되채운다 ★ 내가 찾았다 (codex 는 못 봄)

`api-ventago/src/app/auth/auth.service.ts:241-317` `_runBackfillAsync()`

```ts
const BACKFILL_FULL_ROLES = new Set(['super_admin','superadmin','store_owner','store_admin','admin']);
...
// 기존 RoleFunction 에 누락된 CRUD 액션 보충 (관리자 계열만).
// 여기가 "권한을 좁혀도 다음 로그인에 원복되던" 지점이다.   ← 코드 주석 원문
```

관리자가 「삭제」를 꺼도 **그 역할 사용자가 다음에 로그인하면 되살아난다.**
⤷ ④단계는 admin 계열에서 **구조적으로 불가능**하다.
⤷ 게다가 `store_owner` 10명을 `admin` 으로 옮기면 **그 10명이 새로 백필 대상이 된다.**
   역할 정리와 이 백필은 **같이** 다뤄야 한다.

조치: 「기존 행에 누락 액션 보충」루프만 제거(새 함수 등록은 유지).
`permission-backfill.spec.ts` 가 `store_owner` 가 화이트리스트에 **있다**고 단언하므로 같이 고친다.

### [P1-b] `roleId` 의 매장 소유권을 아무도 검사하지 않는다 ★ codex 가 찾았다 (내가 확인)

`role-function.controller.ts:48` → `role-function.service.ts:110-175`
`storeId` 는 로그인 사용자에게서 오지만 **`roleId` 가 그 매장 것인지 확인하지 않는다.**
소스 전체에 `roles.store_id = storeId` 검사가 **0건**(직접 grep 확인).
⤷ 남의 매장 `roleId` 로 내 `storeId` 행을 만들 수 있다.

조치: 저장 전 `roles.id = roleId AND roles.store_id = user.storeId` 확인.
superadmin 은 `storeId` 가 없을 수 있으므로 대상 `storeId` 를 **명시 인자**로 받는 계약 필요.

### [P1-c] bulk 저장은 「최종 상태 교체」다 — 부분 로드가 곧 대량 삭제

`role-function.service.ts:135-148` — payload 에 없는 `functionId` 는 **삭제**한다.
프론트가 구조를 덜 받은 채 저장하면 그만큼 지워진다.
(지금 프론트에 `!loaded || loadError` 가드가 있어 막히지만, 서버가 스스로는 안 막는다.)

조치: 변경분 patch 계약 추가, 또는 서버가 「전체 교체」임을 명시적 플래그로 요구.

### [P1-d] 마이그레이션은 캐시 무효화를 우회한다

정상 UI 저장은 캐시를 지우지만(`role-function.service.ts:244`), SQL 마이그레이션은 그 코드를
지나지 않는다. 권한 회수 후 **최대 60초**(`PERM_CACHE_TTL_MS`) 동안 옛 판정이 남는다.

조치: 데이터 마이그레이션 배포 절차에 **전 워커 캐시 무효화(또는 재시작)** 를 단계로 넣는다.

### [P1-e] `isAllowed()` 의 fail-open 은 5번을 막는 선행 결함이다

`function-permission.service.ts:94` — 카탈로그에 없는 slug 는 **통과**한다.
「시드와 코드를 같은 배포에」만으로는 롤링 배포 중 구·신 조합을 못 막는다.
⤷ codex 판정: **현 상태에서 slug 일괄 변경은 승인하면 안 된다.**

---

## 1. 측정된 사실 (추측 없음)

### 액션 축은 운영에서 100% 무의미하다

운영 store 6 — 역할별 `role_function` 중 4액션 보유:

| 역할 | role_functions | 4액션 | 1액션 |
|---|---|---|---|
| admin | 179 | **179** | 0 |
| cashier | 175 | **175** | 0 |
| store_owner | 176 | 175 | 1 |
| viewer (Solo Lectura) | 63 | **62** | 1 |
| vendedor | 33 | **33** | 0 |

→ ④단계는 「기존 설정 존중」의 대상이 없다. **전원이 전권**에서 출발한다.
→ UI 를 여는 순간 **첫 저장이 곧 대규모 권한 회수**다.

### 액션 축은 이름의 동사와 거의 완전히 중복이다

가드 호출부 **219개** 전수(`@FunctionGuard(slug, action)` / `@RequireFunction`):

- 요구 액션: `read` 105 · `update` 50 · `create` 42 · `delete` 22 — **CRUD 4개뿐**
- 고유 `(slug, action)` 쌍 **102개**
- 두 액션으로 요구되는 slug 은 **4개뿐**: `administrar-cdigos-qc-y-scorecards`(create,update) ·
  `gestionar-senia`(create,delete) · `modificar-venta`(delete,update) · `registrar-pago`(create,update)
- 이름의 동사와 요구 액션이 어긋나는 것은 **단 1개**: `editar-stock-de-producto` → 요구는 **delete**

★ codex 판정: 이 관찰은 원안 4번(동사형 132개 접기)을 **정당화하지 않고 불필요하게 만든다.**
  219개 계약 변경 + 데이터 재매핑 + override 재매핑 + fail-open 위험을 치를 이유가 없다.
  대신 **④에서 「그 기능이 실제로 쓰는 액션만」 보여주면** 같은 목적을 훨씬 싸게 이룬다.

### 그 밖

| 사실 | 근거 |
|---|---|
| 메뉴 파생은 **액션을 안 본다** — `RoleFunction` 행만 본다 | `user-structure.service.ts` `buildStructure` |
| 서버는 이미 임의 액션 배열을 받는다 → ④는 **프론트 전용** | `PUT /role-functions/bulk-actions/:roleId` |
| `CrudActionRow.tsx` 는 이미 있고 **import 0건** | 전수 grep |
| 판정 캐시 TTL 60초, UI 경로 무효화는 실측 작동 | `PERM_CACHE_TTL_MS`, 2026-09-23 왕복 |
| `Mi perfil`·`Chat de equipo` 는 **의도적으로** ACL 미적용 | `menuRegistry.ts:343-360` 주석 |
| `Guía de configuración` 은 이미 서버가 역할로 건다 | `setup-guide.rules.ts` `SETUP_GUIDE_ROLES` |
| superadmin 은 구조를 통째로 받는다 — 별도 정책 필요 | `user-structure.service.ts:196` |

---

## 2. 역할 정리

### 코드는 이미 사용자 생각대로 믿고 있다

`user-role.guard.ts:8-14` — `store_owner→admin` · `store_admin→admin` · `branch_manager→gerente`.
`ValidRoles` enum 에는 **admin·superadmin·vendedor·gerente·envio_manager 5개뿐.**
⤷ 이 작업은 새 정책이 아니라 **데이터를 코드의 믿음에 맞추는 것**이다.

### 병합 방향 (기능 집합 실측으로 정함 — store 6, EXCEPT 양방향)

| 병합 | 왼쪽에만 | 오른쪽에만 | 사용자 | 판정 |
|---|---|---|---|---|
| `branch_manager` → `gerente` | 0 | **0** | 1 | 집합 동일 · **무손실** |
| `store_admin` → `admin` | admin +6 | **0** | **0** | admin ⊃ · **무손실** · 가장 안전 |
| `store_owner` → `admin` | admin +3 | **0** | **10** | admin ⊃ · **무손실**(3개 더 받음) |
| ~~`store_owner` → `gerente`~~ | 0 | **41** | — | ⚠ **41개 손실 — 채택 안 함** |

★ 사용자 확인 완료: `store_owner` → **`admin`**.

### 왜 그냥 지우면 안 되는가

- `store_owner` 가 **사용자 최다(10명)** 이고, 그 10명은 매장 **10·11·13~20** 에 있다.
- **그 매장들에는 `admin` 행도 `gerente` 행도 아예 없다.**
- 그 매장들은 살아 있다 — store 19(NOIX) 마지막 판매 **2026-09-22(어제)** ·
  17(Liverpool) 08-31 · 15(Sager) 08-15 · 16(kim) 08-11.
- 각 매장 사용자 대부분 **1명** → 그 1명이 그 매장의 **유일한 관리자**.

### 블라스트 반경 — FK 4개가 전부가 아니다 ★ codex 가 보탬

| 경로 | 종류 |
|---|---|
| `role_functions` · `user_roles` · `user_branches`(1행) · `shared_folder_role_access` | FK |
| **`approval_thresholds.role_slug` / `approver_role_slug`** | **문자열 — FK 아님** (`approval-threshold.model.ts:47`) |
| 진행 중 승인 요청의 **역할 slug 스냅샷** | `approval.service.ts:183` |
| `folder-access-resolver.service.ts:29` 의 자체 하드코딩 역할 집합 | 코드 |
| **JWT 안의 역할 slug** — 토큰 만료까지 구 slug 잔존 | 토큰 |

소스 전체: 지울 3개 slug 이 **130곳 · 파일 33개**(비-spec **26개**).

### 시드 경로를 먼저 막지 않으면 되살아난다 ★

`storeTemplate.service.ts` 에만 **42회**. 고쳐야 할 곳:

- `:218` 기본 역할 목록 (`{ name:'Dueño de Tienda', slug:'store_owner', storeId }` 등)
- `:637` / `:658` full-CRUD vs read-only 역할 정책 — **`store_owner` 만 full CRUD 다.**
  이 정책을 같이 옮기지 않으면 **새 `admin` 이 생겨도 관리자 권한을 못 받는다.**
- `:738~` 승인 임계값의 `role_slug` · `approver_role_slug`
- `auth.service.ts:822` 신규 가입자의 `store_owner` 조회·할당
- alias 2곳 (`user-role.guard.ts`, `branch-scope.util.ts`)

⤷ **「구 역할을 더 이상 생성하지 않는 코드」가 데이터 이전보다 먼저 배포돼야 한다.**

---

## 3. 착수 순서 (확정)

사용자는 「위험 순서 우선」을 택했고, codex 는 「메뉴를 액션보다 먼저」를 권했다.
**둘은 충돌하지 않는다** — 아래 순서가 둘 다 만족한다.

| # | 하는 것 | 데이터 | 배포 |
|---|---|---|---|
| **0** | **선행 결함 5건**: 로그인 백필 정지(P1-a) · roleId 테넌트 검사(P1-b) · 저장 계약(P1-c) · 마이그레이션 캐시 무효화 절차(P1-d) · fail-open 판단(P1-e) | 없음 | 1차 |
| **1** | **구 역할 생성 중단** — 시드/가입 경로를 신 slug 로. alias 는 **그대로 둔다**(expand) | 없음 | 2차 |
| **2** | **역할 이전**(migrate) — 매장별: `admin` 시드 → 권한 합집합 → `user_roles`·`user_branches`·`shared_folder_role_access`·`approval_thresholds` 재지정 → **매장마다 관리자 ≥1 확인** → 캐시 무효화 | INSERT→UPDATE | 마이그레이션 |
| **3** | **관찰** — 최소 JWT 최대 수명 이상. 403 · `/unauthorized` · 승인 실패 지표 | 없음 | — |
| **4** | **contract** — alias 제거 · 하드코딩 구 slug 제거 · **마지막에** 구 역할 행 DELETE | DELETE | 3차 |
| **5** | **①메뉴 → ②부메뉴 → ③기능 UI** — 사이드바 14개 모델링 + aux 기능 시드(expand→migrate→contract, 전원이 메뉴를 잃는 구간 없이) | INSERT only | 4차 |
| **6** | **④액션 UI** — `[...ALL_ACTIONS]` 제거 · `CrudActionRow` 재사용 · **기존 값 그대로 초기화** · 「그 기능이 실제로 쓰는 액션만」 표시 · `Solo ver`/`Gestionar` 프리셋 | 없음 | 5차 |
| **7** | 스페인어화 · 가짜 임계값 탭(₩ 하드코딩) 제거 | 없음 | 〃 |
| **보류** | ~~동사형 132개 → 자원+동작 접기~~ | — | **별도 ADR 필요** |

### ④ UI 의 필수 안전장치 (codex)

- 서버에서 받은 기존 action 집합을 **그대로** 초기값으로
- dirty 가 아니면 저장 비활성
- 저장 전 **「추가 N / 회수 N / 영향 사용자 N」 미리보기**, 회수가 있으면 별도 확인
- 전체 교체보다 **변경분 patch**
- 동시 편집 방지(버전 또는 `updatedAt` 검사)
- 감사 로그 + 즉시 캐시 무효화

★ **동사 이름으로 선제 재시드하지 않는다**(codex 반대, 동의):
  이름↔액션 불일치 사례가 있고, 동사 없는 47개는 추론 불가이며,
  관리자의 명시적 의사 없이 권한을 회수하게 된다.

### ★★ ④단계 컨트롤 규칙 — 확정 (사용자 2026-09-23)

> 「4칸을 항상 그리면 안 됩니다. 필요하면 on/off 스위치를 사용해야지」

**동사 어휘 25종을 전수로 뽑아 가드가 실제로 요구하는 액션과 대조**해 분류했다.
CRUD 동의어 **16종** 확인(`agregar`·`registrar`·`manage`→create ·
`modificar`·`cambiar`·`publicar`·`confirmar`→update · `borrar`→delete ·
`reporte`·`detalle`·`view`·`historial`→read), 업무 동작 **13개**는 안 쪼갠다.

| 컨트롤 | 대상 | 줄 | 컨트롤 수 |
|---|---|---|---|
| **CRUD 칩** (그 자원이 **실제로 가진 칸만**) | 동사 2개 이상인 자원 | 25 | 74 |
| **on/off 스위치** | 동사 1개뿐인 자원 92 + 업무 동작 13 | 105 | 105 |
| **합계** | | **130** (지금 179) | **179** |

★ **컨트롤 179 : 기능 179 — 1:1 정확히 대응, 허수 0개.**
  4칸을 항상 그렸다면 117자원 × 4 = **468칸** 중 **302칸(65%)이 허수**였다
  (켜도 아무 일 없음). 동사 1개뿐인 92개 중 **68개가 읽기 전용**(보고서·대시보드)이라
  C·U·D 를 그릴 대상이 아예 없다.

★ 179개 컨트롤 중 **95개만 API 를 바꾼다**. 나머지 84개는 **메뉴 노출에만** 영향한다
  (가드 호출부가 0개인 기능). 화면이 그 차이를 표시해야 «껐는데 왜 되지»가 안 생긴다.

★ **불변식 — 시험으로 못 박는다**: 「화면이 그리는 컨트롤 수 == 카탈로그의 기능 수」이고
  「모든 컨트롤은 정확히 하나의 `functions.slug` 에 대응한다」.
  이게 깨지면 허수 칸이 다시 생긴 것이다.

★ 접기는 **화면에서만** 한다 — `functions.slug` 는 그대로 둔다(데이터 변경 0).
  DB 의 slug 자체를 바꾸는 안은 fail-open 때문에 **보류**(위 P1-e).

#### 접기 전에 고쳐야 할 어긋남 2건

- `editar-stock-de-producto` → 가드 요구는 **delete**. 이름과 반대다.
- `agregar-*` 3개가 create 1 · update 1 로 **갈린다**.
⤷ 액션 메타데이터는 **가드 계약에서 생성**하고, 이름에서 추론하지 않는다.

### 화면 통합 방향 — 원안을 뒤집는다 ★

원안 요건 1번은 `Configuración › Permisos`(= `permission_slug` 축)를 저장 화면으로 삼자고 했다.
**거꾸로다.** 서버의 실제 집행 계약은 **219곳이 쓰는 `functions.slug`** 이고 쓰기 경로도 거기 있다.
`permission_slug` 는 사용처 11곳 · 쓰기 0건이다.

⤷ Roles 권한 편집기를 **정본 컴포넌트**로 만들고 두 진입점에서 재사용한다.
  `permission_slug` 는 표시·별칭으로만 두고 단계적으로 폐기.

### `editar-stock-de-producto`(요구=delete) 처리

UI 가 숨기지 않는다. **엔드포인트의 실제 부작용을 기준으로 가드 호출부를 고친다.**
「update 를 눌렀는데 되는 척」 보이는 매핑은 금지.
액션 메타데이터는 UI 추측이 아니라 **가드 계약에서 생성·검증**한다.

---

## 4. 검증 방법

- 시험 계정 4개: `perm.admin` · `perm.vendedor` · **`perm.sinrol`(역할 0개)** · `perm.otra`
  ★ **역할 0개가 잣대다** — vendedor 로만 재면 「허용된 것」과 「아무도 안 막는 것」이 안 갈린다.
- **admin 대조군을 매번 다시 잰다** — 지난 세션에 회귀를 두 번 잡았다.
- 라우트 목록은 **소스가 아니라 실제 요청으로** 센다(`CrudController` 상속 라우트는 파일에 안 보인다).
- **소스 문자열 검사로 시험을 쓰지 않는다** — `seeders-access.spec` 이 그래서 헛통과했다.
- 역할 이전 후 **매장마다 관리자 ≥1** 을 SQL 로 전수 확인한다(사람 눈 아님).
- cmux 브라우저는 **운영 빌드**여야 하이드레이션된다(`next build && next start -p 3050`).
