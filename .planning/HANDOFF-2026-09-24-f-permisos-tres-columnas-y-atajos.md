# 핸드오프 2026-09-24-f — Permisos **세 칸** 구현 · 사용자 편집 직행 · 단축키 전수 점검

앞 핸드오프 `HANDOFF-2026-09-24-e` 의 뒤다. 다음 세션은 §1(배포 상태) → §4(미해결) 순으로 읽으면 된다.

---

## 1. ★★ 배포 상태 — **push 대기 2건, 순서가 중요하다**

| 저장소 | 커밋 | 내용 | 상태 |
|---|---|---|---|
| api | `eca618cb` | `?userId=` 필터 | ✅ 배포 **#958 SUCCESS** |
| app | `cc8bcfe5` | 사용자 편집 직행 링크 | ✅ 배포 **#804 SUCCESS** |
| app | `fce40001` | `Ctrl+Q` + 단축키 검사 | ✅ 배포 **#804 SUCCESS** |
| api | `953d2a73` | `GET /permissions/por-funcion` | ⬜ **push 대기** |
| app | `635fe01e` | Permisos 세 칸 | ⬜ **push 대기** |

★★★ **api 를 먼저 배포해야 한다.** app 이 먼저 나가면 `/permissions/por-funcion` 이
  404 라 Permisos 탭이 「No se pudieron cargar」로 몇 분간 **죽는다.** 반대 순서는 무해하다
  (새 엔드포인트를 아무도 안 부른다).

배포 확인은 빌드 성공만으로 끝내지 않았다 — 컨테이너 안에서 실측했다:
`api_ventago` 에 `userId inválido` **1건**, `ventagoapp` 청크에 `editar:` **1건**.

---

## 2. 한 것

### 2-a. Permisos 화면 — 표 → **세 칸**(①안, 사용자 확정)

`menú → submenú → permiso`. 왼쪽에서 오른쪽으로 좁힌다.

★★ **표를 고친 게 아니라 축을 바꿨다.** 옛 표는 `/permissions/matrix` 를 썼는데 그건
  `permission_slug` **19개** 기준이다. 실제 권한은 **199개 기능**이라 한 줄이 다섯 개를
  덮고 있었고, 어느 화면의 권한인지 아무 데도 안 적혀 있었다.

★★★ 각 권한 줄에 **가드가 실제로 요구하는 액션**(`pide delete`) 또는 `sólo menú` 를 붙였다.
  이름은 거짓말한다 — `editar-stock-de-producto` 는 `@Delete` 에 달려 재고를 파괴하고,
  `eliminar-logs` 는 **가드가 없어 아무것도 못 지운다.** 6단계의 `controlDe()` 를 재사용했다.

**새 API** `GET /permissions/por-funcion` — 역할×기능 한 번에. 종전엔 `/role-functions/:roleId`
를 역할 수만큼(7~9번) 불러야 했다.
- `LEFT JOIN` 이 핵심: `getMatrix` 의 `JOIN` 은 **액션 0개인 부여 행을 없애** 「권한 없음」과
  구분이 안 된다. 오늘은 0행이지만 스키마가 허용하고 6단계가 만드는 것이 바로 그 행이다.
- 역할 목록은 join 과 **따로** 준다 — 권한 0개인 역할이 join 에 없어 **열이 통째로 사라진다.**

**판정은 `.ts` 에 뒀다**(`arbol-tres-columnas.ts` · `celda-de-permiso.ts`). 이 저장소 jest 는
`jsx: preserve` 라 spec 이 `.tsx` 를 import 하면 죽는다 — **화면 안의 판정은 시험되지 않는다.**

★ **대조군이 결함을 하나 잡았다**: 검색에 **공백 하나**를 치면 트리가 통째로 사라졌다.
  글자로 검색하면 잘 되니 눈으로는 완성으로 보였다.

### 2-b. 사용자 편집 화면으로 직행 (사용자 요청)

`Permisos › Detalle por usuario` → `/usuarios?editar=<id>` → **그 사람의 모달**.

★★★ `GET /users/:id` 를 **쓰면 안 된다** — `raw: true` 에 `roles` 를 안 싣는다. 그 모양으로
  모달을 열면 역할 셀렉트가 빈 채로 뜨고 **저장하면 역할이 지워진다.** 목록과 같은
  엔드포인트에 `?userId=` 를 더했다.

### 2-c. 단축키 — Chrome 충돌 전수 점검

사용자 질문: 「Alt+1~4 가 탭을 바꾸지 않나? Ctrl 을 써야 할 것 같다」

★★ **반대다.** Chrome 탭 전환은 `Ctrl+1~8`(Win/Linux) · `⌘+1~8`(Mac). `Alt+N` 은
  **Firefox** 다. Alt→Ctrl 은 **없던 충돌을 만드는 쪽**이라 Alt 를 유지했다.
  ⤷ 아직 **Windows 실측 미완** — §4-1.

전수: `useHotkeys` 25건 중 브라우저 기본키를 안 막는 것은 **`ctrl+q` 1건**뿐. 고쳤다.
`pos-atajos-vs-navegador.spec.ts` 가 괄호를 세어 각 호출을 잘라 검사한다(느슨한 정규식이면
**옆 호출의 `preventDefault` 를 자기 것으로** 세어 빠진 것을 놓친다).

---

## 3. ★★ 이 세션에서 배운 것

### ① 적용 안 된 돌연변이는 **살아남은 돌연변이처럼 보인다**

`perl -0pi -e` 의 패턴이 들여쓰기 한 칸 때문에 안 맞았는데, 결과는 `EXIT=0` —
「검사가 못 잡는다」와 **구분되지 않는다.** 제대로 적용하니 5개 시험이 잡았다.
⤷ **돌연변이는 적용됐는지를 먼저 확인할 것**(`assert old in s` + `diff`).

### ② 외부 지적은 근거까지 대조해야 한다 — 이번엔 **4건 중 1건이 전제부터 틀렸다**

codex [HIGH] 「SWR 캐시가 매장 간에 공유돼 5분간 남의 매장이 보인다」 →
근거였던 「`setActingStore()` 가 SWR 를 무효화하지 않는다」는 **효과상 거짓**이다.
`ActingStoreBar.choose()` 가 `window.location.reload()` 를 하고, 이 앱 SWR 에는
영속 캐시 provider 가 없다. 그 창은 존재하지 않는다.
⤷ 대신 **그 보장을 재는 검사가 없다**는 것이 진짜 발견이다(§4-4).

### ③ 내가 세운 근거가 「화면에 없는 이야기」일 수 있다

`?userId=` 에서 비활성 제외를 풀며 「재활성화에 필요하다」고 적었다. 실측하니 그 링크의
출발점(`GET /users`)이 **이미 비활성을 제외**해서 애초에 도달 불가였다. 얻는 것 없이
id 열거만 열어 줄 뻔했다. ⤷ **근거를 적을 때 그 경로가 실제로 존재하는지 확인할 것.**

### ④ 「짝을 이루는 변경」은 순서까지 판단해서 알린다

api·app 두 커밋이 서로를 전제한다. 어느 쪽이 먼저여도 되는지 **먼저 판단**해서 §1 에 적었다.
(앞선 사용자-편집 링크는 `fila.id !== pedido` 대조 덕분에 순서가 무관해졌다 — 설계로
 순서 의존을 **없앤** 쪽이 더 낫다.)

---

## 4. ★ 미해결

1. **Alt+1~4 의 Windows 실측** — 사용자가 POS 터미널에서 `Alt+1` 을 눌러 탭이 바뀌는지
   확인해야 한다. macOS 에서는 잴 수 없다(⌘ 를 쓴다). 바뀌면 `Ctrl+Alt+1~4` 로 옮긴다.
   ★ `Ctrl+1~4` 로는 **절대 옮기지 말 것** — 검사가 막는다.

2. **`Ctrl+V` 가 앱 전체의 붙여넣기를 막는다** — `UserLayout.tsx:69`.
   **2026-09-22 에 P1-B 로 올라간 사용자 결정 대기 건**이고 코드상 지금도 그대로다(확인함).
   선택지: 키를 옮긴다(`Ctrl+Alt+V`) / 입력칸에서 뺀다(`enableOnFormTags` 제거).

3. **Repaso(Ctrl+R) 가 판매 때마다 시계 화면으로** — 여전히 미해결. 이번에 후보 셋을
   **배제**했다: `ctrl+r` 은 `preventDefault`+`enableOnFormTags` 가 제대로 걸려 있고,
   `StoreConfigContext.loaded` 는 `storeId` 가 바뀔 때만 내려가며(`fetchConfig` deps 는 `[]`),
   iframe 후보였던 `PDFPreviewModal` 은 **호출부 0개인 죽은 코드**다.
   ⤷ 다음은 읽는 게 아니라 **재는 것** — 앞 핸드오프 §5-2 의 측정 절차 그대로.

4. **(신규) 매장 대행 전환의 캐시 보장을 재는 검사가 없다** — 지금은
   `ActingStoreBar.choose()` 의 `window.location.reload()` 하나가 **전 화면의 캐시 격리를
   혼자 떠받친다.** 누가 그 줄을 지우면 SWR 훅 **전부**가 남의 매장 데이터를 보여 준다.
   한 줄짜리 소스 검사로 못 박을 가치가 있다.

5. **② `ver-<모듈>` 시드** — 앞 핸드오프 §0-d ② 그대로 유효. 읽기 전용 권한이 존재하지
   않는다(51개 모듈, 그중 5개는 「보기」가 원천 불가). 규모 실측 약 10,100행.

6. **`audit.read` 가 CRUD** — 「Eliminar logs」가 admin·gerente·accountant 에 남아 있다.
   ★ 단 감사 로그를 지우는 엔드포인트는 **없다**(`@Get` 뿐). 빼도 아무것도 안 막는다.

7. 앞 핸드오프의 §5-4(같은 이름 descuento/recargo 3줄) · §5-5(프로비저닝 트랜잭션 0회) ·
   §5-6(SetupWizardView 한국어) · §5-7(감사 로그 action 드롭다운) — 손대지 않았다.

---

## 5. 사람이 확인해 줘야 하는 것

1. **POS 터미널(Windows)에서 `Alt+1`** — 탭이 바뀌는가? (§4-1)
2. **`Ctrl+V` 를 어떻게 할지** (§4-2) — 키 이동 vs 입력칸에서 제외.
3. **api 먼저 push** (§1) — 그 뒤 app.
4. 배포 후 `/configuracion/permisos` 의 **Matriz** 탭: 세 칸으로 보이는지 ·
   각 권한 줄에 `pide <액션>` 또는 `sólo menú` 가 붙는지 · 셀이 `CRUD`/`●`/`—` 인지.

---

## 6. 검증 수치

| | |
|---|---|
| api | tsc 0 · eslint 추가줄 0(HEAD 대비 controller 46→44) · jest `src/app/users` 66 · `src/app/permissions` 8 |
| app | tsc 0 · eslint 0 · jest **84 suites / 979건** |
| 돌연변이 | **17개 전부 죽었다** (그중 1건은 적용 실패를 잡아내 재실행) |
| codex | 2회 자문 · 지적 8건 중 **6건 적용 · 1건 근거 반박 · 1건 보류** |
