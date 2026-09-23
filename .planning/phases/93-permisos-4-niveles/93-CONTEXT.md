# Phase 93 — 권한을 4단계로: 메뉴 → 부메뉴 → 자원 → 동작

사용자 정의(2026-09-23):
> 「1단계 제어는 사이드 메뉴의 어느것을 사용하게 하느냐 마느냐. 어떤 메뉴가 허용되면
> 그 부메뉴 중 어느것이 허용되느냐. 그 부메뉴에 소속된 기능 중 어느것을 건들 수 있느냐.
> 최종 기능에 대해서는 보기만 할 것이냐, 생성·편집·삭제가 가능하게 할 것이냐.」

추가 지시:
> 「각 role 들에 대해서 각 메뉴에 접근을 허용하는가를 **먼저** on/off 하게 해야 해.」
> 「**Mi perfil 을 제외하고는** 모든 메뉴의 제어가 가능해져야 해.」

Mock-up: https://claude.ai/artifact/BTnotmcsJBvFLwm6VvCNNP (아트보드 4장)

---

## 전제 — DB 는 이미 4단계를 지탱한다. UI 가 덮어쓰고 있다

2026-09-23 실측(로컬 `ventago`, 매장 6):

| | 수치 |
|---|---|
| apps (메뉴) | 6 |
| modules (부메뉴) | 50 |
| functions | 179 |
| role_function_actions | 44,137 |
| 모듈 없는 기능 | **0** — 계층이 온전하다 |

`role_function_actions` 는 `(role_function_id, action)` 으로 **액션별 행**을 이미 지원하고,
`user_function_actions` 는 `allowed` 불리언으로 사용자 단위 grant/deny 까지 된다.
판정도 그것을 읽는다(`function-permission.service.ts:118-134`).

**그런데 저장하는 화면이 언제나 네 개를 통째로 쓴다:**

```
ventago-app/src/views/users/roles/RolePermissionsDrawer.tsx:156   actions: [...ALL_ACTIONS]
ventago-app/src/views/users/components/UserPermissionsDrawer.tsx:205  ALL_ACTIONS.map(...)
```

결과(store 6 실측):

| 역할 | 기능 수 | 「읽기만」 | 「전부」 |
|---|---|---|---|
| **Solo Lectura** | 63 | **1** | **62** |
| Contador | 71 | 1 | 70 |
| Vendedor | 33 | 0 | 33 |
| Cajero | 175 | 0 | 175 |

→ **「읽기 전용」이라는 이름의 역할이 삭제 권한을 갖고 있다.** 아무도 준 적이 없다.

★ 액션별 칩 컴포넌트 `views/users/roles/components/CrudActionRow.tsx` 는
  **이미 있는데 아무도 import 하지 않는다**(전수 grep 0건).

## 두 번째 전제 — 3단계에 동사가 박혀 있다

179개 중 **132개(74%)** 가 동사로 시작한다: `ver…` 53 · `editar…` 32 · `crear…` 25 ·
`eliminar…` 22. 같은 자원에 동사 2~3개가 붙은 묶음이 다수다
(`crear-cliente`/`editar-cliente`/`eliminar-cliente`, caja·color·gasto·material·proveedor…).

그 위에 또 CRUD 4개가 붙으니 **16조합 중 의미 있는 것은 4개**다.
「고객 생성 권한을 삭제할 수 있다」는 말이 성립하지 않는다.

나머지 **47개는 동사가 없다**(`gestionar-senia` 등). 그것들은 업무 동작이므로
체크박스 하나로 남긴다 — CRUD 로 쪼개지 않는다.

## 세 번째 전제 — 화면이 둘이고 열쇠가 둘이다

| | Configuración › Permisos | Usuarios › Roles |
|---|---|---|
| 축 | `functions.permission_slug` | `functions.slug` |
| 서버가 쓰는 것 | 엔드포인트 **11곳** | 엔드포인트 **221곳** |
| 쓰기 | **없다**(모바일 터미널 배정만) | `PUT /role-functions/bulk-actions/:roleId` |
| 언어 | 렌더 문자열 88줄 중 **87줄이 한국어** | 100% 스페인어 |

→ 매트릭스는 `permission_slug` 가 채워진 기능만 보여준다. 드로어에서 켠 대부분이
**매트릭스에 아예 안 나온다.** 보이는 그림과 실제로 막는 것이 다르다.

★ 승인 임계값 탭(`ThresholdEditor.tsx:68-75`)은 API 호출 0건, **하드코딩 8행**,
  아르헨티나 제품인데 **원화(₩)** 표기다.

---

## 1단계의 대상은 「앱 6개」가 아니라 **사이드바에 보이는 것 전부**다

사용자가 보는 최상위 항목은 14개이고 출처가 네 갈래다:

| 항목 | 출처 | 지금 역할로 제어되나 |
|---|---|---|
| Admin · Venta · Producto · Stock & Reportajes · Talleres · Materia Prima | `apps` | 기능 권한에서 **파생** |
| **Tesorería** | 가상 그룹(`virtualGroups`) — admin 앱의 `/caja`·`/control-de-caja` + `/cheques` 주입 | 파생 |
| **ClienteVista** | 모듈 `cliente-vista` (venta, `is_auxiliary`) | 기능 권한 |
| **CodigoVista** | 모듈 `precios` (producto, `is_auxiliary`) — 이름은 CodigoVista 인데 url 은 `/precios` | 기능 권한 |
| Guía de configuración · Descargas · **Mi perfil** · Chat de equipo · Manuales | 코드(`auxiliaryExtras`) | **없음 — 전원 노출** |

★ `/precios` 와 `/codigo-vista` 는 **한 모듈에 묶인 두 화면**이라 따로 켤 수 없다.
★ **Mi perfil 만** 전원 공개로 남긴다(사용자 지시). 비밀번호 변경 입구라 막으면
  직원이 자기 암호를 못 바꾼다 — 코드 주석도 그 이유를 적어 두었다.
  나머지 4개는 제어 대상으로 끌어온다.

## ②단계에 대한 주의 — 모듈 on/off 테이블은 없다

모듈 표시는 「허용 기능 ≥1」의 **파생 결과**다(`user-structure.service.ts:139-143`).
그래서 보고서 권한을 전부 빼면 「Stock & Reportajes」 메뉴가 **저절로 사라진다**
(2026-09-23 실측: structure 에서 `reportes` 앱이 빠지고 사이드바에서 사라졌으며
`/reportes-v2` 직접 진입도 `/unauthorized` 였다).

⤷ 이것은 지금 구조의 **장점**이다. 별도 테이블을 만들면 「권한은 있는데 메뉴는 꺼진」
  모순 상태가 생긴다. 1단계 토글은 **하위 전체 일괄 토글**로 구현한다.
  단, `auxiliaryExtras` 5개 중 4개는 파생될 기능이 없으므로 **새로 기능을 시드**해야 한다.

---

## Requirements

1. **한 화면으로 합친다** — Configuración › Permisos 가 저장하는 화면이 된다.
   Usuarios › Roles 드로어는 같은 화면을 역할로 필터해 연다.
2. **`functions.slug` 위에 짓는다** — 221곳이 쓰는 그 열쇠. `permission_slug` 경로는 건드리지 않는다.
3. **네 칸을 묻는다** — `[...ALL_ACTIONS]` 제거. 기존 `CrudActionRow.tsx` 재사용.
4. **1단계 = 사이드바 14개 그대로.** Mi perfil 만 「todos」로 고정 표시.
5. **전부 스페인어.** 가짜 임계값 탭은 API 가 생길 때까지 내린다.
6. **동사형 132개를 자원+동작으로 접는다** — 데이터 마이그레이션, 되돌릴 수 있게.
7. 사용자별 예외는 기한(`validUntil`)과 사유(`reason`)를 남긴다 — 스키마에 이미 있다.

## Depends on

- api `0dc49803` (클래스 레벨 `@Auth` 가 실제로 작동하게 된 것) — **배포 완료**
- api `fcdaaace` (CrudController 상속 라우트 37개 차단) — 커밋됨, push 대기
- 시험 계정 4개: `perm.admin` / `perm.vendedor` / **`perm.sinrol`(역할 0개)** / `perm.otra`
  ★ 역할 0개 계정이 이 phase 의 잣대다. vendedor 로만 재면
    「허용된 것」과 「아무도 안 막는 것」이 구분되지 않는다.

## 착수 순서 (위험 낮은 것부터)

| # | 하는 것 | 데이터 변경 | 되돌리기 |
|---|---|---|---|
| 1 | `[...ALL_ACTIONS]` 제거 + 네 칸 UI | 없음 | 커밋 되돌리기 |
| 2 | 스페인어화 · 가짜 임계값 탭 제거 | 없음 | 〃 |
| 3 | 1단계를 사이드바 14개로 · aux 4개에 기능 시드 | INSERT only | DELETE |
| 4 | 동사형 132개 → 자원+동작 | **UPDATE/INSERT** | 역마이그레이션 필요 |

★ 4번 전에 1~3번이 운영에서 한 주 돌아야 한다. 4번은 가드 계약키(`functions.slug`)를
  바꾸는 일이라, 시드와 코드가 **같은 배포**에 실려야 한다
  (`isAllowed()` 는 카탈로그에 없는 slug 를 **통과시킨다** — `function-permission.service.ts:94`).

## 이 phase 가 건드리지 않는 것

- `permissions` · `role_permissions` · `user_permissions` — 레거시, 운영 0행
- `functions.resource_key` — 읽는 코드 0건
- 경로 B 가드(`@Permission`, 11곳) — 그대로 둔다
