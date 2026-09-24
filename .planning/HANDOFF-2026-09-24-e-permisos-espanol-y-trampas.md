# 핸드오프 2026-09-24-e — 권한 화면 스페인어화(Phase 93 **7단계**) · 두 개의 함정

앞 핸드오프 `HANDOFF-2026-09-24-d` 의 **뒤**다. 다음 세션은 §1(배포 상태) → §5(미해결) 순으로 읽으면 된다.

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

1. **(B) 매장 관리자 전용 앱** — `allowedApps={['admin']}` **단독으로 열리는 페이지 24개**
   (앞 핸드오프는 32 이라 했으나 2026-09-24 실측은 **24**). cashier·accountant·viewer 는
   admin 기능이 있어 **URL 로 도달 가능**하다(API 는 별도로 막지만 화면은 뜬다).
   이 화면들은 **모듈도 기능도 없다** — 권한 체계에 존재하지 않는다.
   ⤷ 착수 시 주의: 잘못 조이면 **관리자가 자기 설정 화면에서 잠긴다.** 따로 재고 따로 배포.

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
