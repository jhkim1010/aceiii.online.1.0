# 핸드오프 2026-09-25-b — 역할별 CRUD 축 · POS 검색 배포 확인 · 미착수 결함 2건

앞 핸드오프 `HANDOFF-2026-09-25-pos-buscador-y-whatsapp.md` 의 뒤다.
다음 세션은 §1(배포) → §4(미해결) 순으로 읽는다.

---

## 1. ★★ 배포 상태

| 저장소 | 커밋 | 내용 | 상태 |
|---|---|---|---|
| api | `e6a80417` | `por-funcion` · `?userId=` · 매뉴얼 | ✅ **#959** |
| app | `8ca9c828` · `3203c28b` | 검색 ABC 순 · 목록 가격 = 청구 가격 | ✅ **#808** |
| 루트 | `21eeba9` | 포인터 → app `3203c28b` | ✅ push 완료 |
| app | **`b8c5c731`** · **`c4cfeb66`** | **역할 CRUD 축** + 409 계약 시험 (이번 세션) | ⬜ **push 대기** |

### #808 배포 확인 — **함수명이 아니라 서빙되는 청크 본문으로 쟀다**

빌드 로그의 `Checking out Revision 3203c28b0289…` + `Finished: SUCCESS`,
컨테이너 `ventagoapp` `Up 15 minutes`(재생성됨). 청크 안:

```js
renderOption:(e,n)=>{let t=resolveAmountFor(n,pickDefaultPriceType(n));…"2px 8px"…
…localeCompare(d,"es",{numeric:!0,sensitivity:"base"})…
```

★ 이 빌드는 `resolveAmountFor` 를 mangle 하지 **않았다.** 그래도 이름에 기대지 않고
  `2px 8px`(화면에 나가는 문자열) 앞뒤를 잘라 렌더 코드 자체를 꺼냈다 — 다음에도 그렇게 할 것.
★ 청크에 남아 있는 `prices[0].amount` 2건은 **다른 경로**다(수량 계산의 폴백 · 상품 폼).
  「0건이어야 한다」로 검사를 짜면 이 둘 때문에 영원히 실패한다.

### NOIX 데이터 대조 (운영 5434)

```
714 | 2515014-V | [SHORT POLLERA] MICROFIBRA  |  5000 | 가격행 5
730 | 258705    | [VESTIDO] TUL LARGO VOLADOS | 13000 | 가격행 1
```
714 의 가격행은 id 순으로 **PRECIO 5 $4.500 → 4 → 3 → 2 → PRECIO 1 $5.000**.
종전 `prices[0]` 이 정확히 $4.500 을 보여주고 있었다는 근거다.
⤷ **화면 확인은 사용자만 할 수 있다** (§5).

---

## 2. 한 것 — 역할별 CRUD 축 (사용자 선택)

### 2-a. ★★★ 측정이 요청의 형태를 바꿨다

사용자 요청: 「나중에 CRUD 를 따로 관리… 예를 들어 gerente 는 D 권한을 주지 않는 정도로」.
**짓기 전에 쟀고, 숫자가 할 일을 바꿨다.**

| 잰 것 | 값 |
|---|---|
| `@FunctionGuard` (slug, action) 쌍 | **102** / 기능 **98** |
| 그중 **두 액션**을 요구하는 기능 | **4** (`modificar-venta`·`gestionar-senia`·`registrar-pago`·`administrar-cdigos-qc…`) |
| `delete` 를 요구하는 기능 | **20** |
| store 6 Gerente 가 실제로 가진 D | **3** (`editar-stock-de-producto`·`gestionar-senia`·`modificar-venta`) |

★★★ 즉 **축은 이미 있었고 이미 강제되고 있었다** —
  `function-permission.service.ts:178` 이 `where { roleFunctionId, action }` 로 액션을 본다.
  없던 것은 **그것을 볼 방법**이었다. 98개 중 **94개가 액션 하나**라 스위치가 곧 그 액션인데,
  화면에는 맨 스위치뿐이었다. 그리고 **이름이 거짓말한다** —
  `editar-stock-de-producto` 는 `delete` 를 요구한다.

### 2-b. 넣은 것 (app `b8c5c731`)

- **각 줄에 글자.** 스위치가 주는 액션(C/R/U/D)을 **꺼져 있을 때도** 보여 준다 —
  켤 때 무엇을 주는지가 바로 거기서 필요한 정보다. **누를 수는 없다**(옆 스위치가 이미 지배).
- **글자로 거르기 + barrido.** 「Quitar «Eliminar» de N funciones」. 20개가 트리 전체에
  흩어져 있어 손으로는 20번 검색이다.
  ★ **두 형태를 구분한다**: 두 액션짜리는 글자만 빼고 켜 둔 채, **한 액션짜리는 기능을 끈다.**
    같게 다루면 액션 0개로 켜진 기능이 남는다 — 부여됐다고 표시되는데 가드는 403.
- `contratoDisponible()` 를 Permisos 그리드와 **공유**. `!falloGuardias` 가 못 보던 경우를
  덮는다: 옛 백엔드가 `{}` 를 200 으로 주면 182개가 전부 「sólo menú」로 그려졌다.

### 2-c. 검사 쪽에서 한 것

- `permisos-arbol.spec.ts` 가 이제 **주석을 지운 소스**를 본다. 양방향 대조군 2건.
  ★ 그 대조군이 **그 자리에서 잡았다** — 내 첫 버전은 *이 spec 자신의* 주석을 인용해 실패했다.
- **살아남은 돌연변이 1건 → 죽은 코드 발견.** `if (!acc.has(id)) continue;` 는
  결과를 바꾸지 않는다(`conAccion` 이 이미 빠지고, `conFuncion(...,false)` 는 없는 키를
  지워도 무해). **지웠다** — 두면 「apagada sigue apagada」 보장이 거기 사는 것처럼 보인다.

---

## 3. ★★ 재다가 나온 것 — **손대지 않았다** (사용자가 범위를 1번만 선택)

### 3-a. ★★★ `UserPermissionsDrawer` 가 아직 `ALL_ACTIONS` 를 쓴다

`ventago-app/src/views/users/components/UserPermissionsDrawer.tsx:38,201`

```ts
const ALL_ACTIONS = ['create', 'read', 'update', 'delete'];
…
actions: ALL_ACTIONS.map(action => ({ action, allowed }))
```

Phase 93 6단계가 **역할 쪽에서 닫은 그 결함이 사용자 쪽에 그대로 살아 있다.**
그리고 `isAllowed` 는 오버라이드가 있으면 **역할을 무시하고 그걸 따른다**(`:194`).
⤷ gerente 한 명에게 기능 하나를 개별로 켜 주면 **그 기능의 D 까지 넘어간다** —
  역할에서 D 를 뺀 의미가 그 자리에서 사라진다.

**운영 실측**: `user_functions` **4행 / 사용자 1명**, `user_function_actions` 16행이
**전부 `allowed=false`**. 지금까지 그 화면을 「빼는 데」만 썼기 때문에 **피해는 0**.
★ **처음으로 「주는 데」 쓰는 순간** 벌어진다. 오늘이 가장 싸다.

### 3-b. 가드가 요구하지 않는 액션 행 **20,329개**

| action | 가드 없음 | 가드 있음 |
|---|---|---|
| create | **6,582** | 950 |
| delete | **7,104** | 412 |
| update | **6,643** | 889 |
| read | 13,288 | 2,400 |

79개 역할 · 18개 매장. (`read` 의 13,288 은 **설계대로**다 — 「sólo menú」 기능은
행이 존재해야 해서 `read` 를 넣는 관례.)

★ 오늘은 아무것도 열지 않는다. **기존 기능에 `@FunctionGuard(…, 'delete')` 하나가 붙는 날
  그 역할들이 동시에 얻는다.** 「코드를 고쳐도 그 코드가 쓴 행은 남는다」의 그 모양이다.
★★ 정리 마이그레이션을 한다면 **기능 변화가 0이어야 한다** — 그걸 보장하려면
  가드 계약과 대조하는 검사가 **먼저** 있어야 한다. 위험이 제일 크다.

★ 「Solo Lectura 가 66개 중 62개에 delete 를 갖고 있다」는 **사실이지만 위협이 아니다** —
  그 62개 중 가드가 delete 를 요구하는 것은 **0개**다. 처음에 이 숫자만 보고 놀랐는데,
  가드 계약과 대조해서야 실제 효과가 나왔다. **행 수는 권한이 아니다.**

---

## 4. ★ 미해결 / 열린 결정

1. **app `b8c5c731` · `c4cfeb66` push 승인** (§1) — Jenkins `front-coolsistema`.
   ★ **api 는 안 건드렸다** — 짝 배포 문제 없음. app 만 나가면 된다.

2. **사람 확인 2건, 계속 미확인** — POS 터미널(Windows):
   · **`Alt+1`** 이 크롬 탭을 바꾸는가? (macOS 에선 못 잰다)
   · **`Ctrl+V`** 붙여넣기가 돌아왔는가? (fichaje QR 은 이제 `Alt+V`)

3. **§3-a `UserPermissionsDrawer` 결함** · **§3-b 낡은 행 20,329개** — 둘 다 미착수.
   사용자가 이번 범위에서 **뺐다**(범위 질문에서 1번만 선택). 없애지 말 것.

4. **WhatsApp 영수증 — 위치 결정 받았다**: 「**구입자가 원할 때만** 물어보게 하자.
   **구입자 정보를 입력할 때** 하는 것으로 충분」
   ⤷ 즉 **결제 패널이 아니라 고객 정보 입력 자리**(`InfoClient.tsx`)다.
   ★★ **그러면 도달 문제가 남는다**: 지금 전화번호·동의 칸은 `isExpanded` 안이고,
     그건 `문서번호 6자리 이상` **또는** `고객 선택` 일 때만 펼쳐진다. 빠른 판매에서는
     둘 다 안 일어나 사실상 도달 불가였다(4,294명 중 전화 816명, 동의 **0행**).
     ⤷ 사용자의 결정과 모순되지 않는다 — **「구입자 정보를 입력할 때」가 바로 그 자리**다.
       할 일은 그 자리를 **옮기는 것이 아니라**, 거기서 `comprobantes_opt_in` 을
       **광고 동의와 분리해서** 묻는 것. (지금 체크박스는 「Acepta **promociones**」 —
       영수증은 광고가 아니라 거래의 일부다. 기존 값을 물려받게 하지 **말 것**.)
   ★ 남은 결정 2건: 전표 있는 판매만(21/238) vs 티켓 PDF 신설 · 동의 문구

5. **Repaso(Ctrl+R) 가 판매 때마다 시계 화면으로** — 미해결. **이번에 배제가 더 늘었다**:
   · `refreshUser` 는 판매 경로에서 **호출부 0개** (`AuthContext.tsx:278`)
   · `StoreConfigContext` 의 `loaded` 강하는 `user?.storeId` 변경 때만 (`:295`)
   · 판매 완료 후 `router.push`/`reload`/`location.*` **0건** (`ProductList.tsx`)
   · `react-hotkeys-hook@5.2.4` 에서 `enableOnFormTags: true` 는 **정상 동작**
     (dist 의 `F(e,true)` → 태그명만 있으면 통과. 배열이 아니어도 된다)
   · `setReviewMode(false)` 로 가는 길은 **여전히 넷**이고 판매는 그중에 없다
   ⤷ **읽기로는 끝났다.** 갈림길은 「누가 껐다」 vs 「통째로 다시 떴다」 하나다.
     NOIX 화면에서 판매 **전에** 콘솔에 `window.__vida = Date.now()` 를 넣고,
     시계로 바뀐 뒤 `window.__vida` 가 `undefined` 면 **페이지가 다시 뜬 것**이다.

6. **매장 대행 전환의 캐시 보장을 재는 검사가 없다** — `ActingStoreBar.choose()` 의
   `window.location.reload()` 하나가 전 화면의 캐시 격리를 혼자 떠받친다.

7. `ver-<모듈>` 시드 · `audit.read` CRUD · 앞 핸드오프들의 §5-4~§5-7 — 그대로.

---

## 4-bis. ★★ CODEX 가 오늘 두 번 다 죽었다 — 손으로 훑었다

1. 자동 훅은 `reason=secret_pattern_in_diff` 로 **건너뛰었다**
   (`.auto-codex.SKIPPED.20260925-090505.txt`). 걸린 줄은 **누적 diff** 의 7041·13618 —
   `heads_last_reviewed` 가 `ventago-app=3219faf` 에 멈춰 있어 **내 커밋이 아니다.**
2. 손으로 두 번 띄웠고 **둘 다 파일만 덤프하고 판정 없이 끝났다.**
   로그 끝에 `hook: SessionStart Failed` · `hook: PostToolUse Failed`.
   → 메모리의 실패 모양 ④(「훅이 깨져 있으면 무엇을 해도 죽는다」) 그대로다.

⤷ **그래서 직접 적대적으로 훑었고, 그게 실제로 하나를 찾아냈다**:
  barrido 는 「기능 회수」와 「액션 회수」를 **한 번에** 만드는 유일한 경로라
  두 카운터가 겹치는 자리다. 서버(`role-function.service.ts:353`)를 읽어
  `targetIds` 가 `data` 에서만 나온다는 것을 확인했고 — 즉 꺼진 기능의 액션은
  `removeIds` 에 안 들어간다 — 그 계약을 시험 6건으로 못 박았다(`c4cfeb66`).
  돌연변이(「`diferencia` 가 꺼진 기능의 액션도 센다」)는 **사망**.
  그 시험이 없으면 그 돌연변이는 **기능을 끄는 모든 저장을 409** 로 만든다.

★ 다음 세션에도 CODEX 가 죽으면 **로그 끝의 `hook: … Failed` 를 먼저 볼 것.**
  프롬프트 크기 문제가 아니다 — 파일 1개짜리 짧은 프롬프트도 같은 자리에서 죽었다.

---

## 5. 사람이 확인해 줘야 하는 것

1. **NOIX 검색 화면** — `2515014-V` 가 **$5.000** 인지 · 빈칸이던 상품에 가격이
   보이는지(`258705` → `$13.000`) · 목록이 이름 ABC 순인지.
2. **Windows POS 의 `Alt+1` / `Ctrl+V`** (§4-2).
3. **Repaso 측정** (§4-5) — 콘솔 한 줄.

---

## 6. 검증 수치

| | |
|---|---|
| app | tsc 0 · eslint 0 · jest **88 suites / 1,058건** |
| 이번 세션 시험 | `permisos-eje-crud.spec.ts` **21건** + 배선 표식 **6건** |
| 이번 세션 시험(추가) | 409 계약 **6건** — barrido 가 만드는 두 종류 회수의 계약 |
| 돌연변이 | **11개 적용, 11개 사망**. 12번째는 **죽은 코드를 찾아냈다**(그래서 지웠다) |
| 대조군이 잡은 것 | 주석 제거 대조군이 **자기 spec 의 주석**을 인용한 내 실수를 즉시 잡음 |
