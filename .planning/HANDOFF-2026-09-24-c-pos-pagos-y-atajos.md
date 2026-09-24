# 핸드오프 2026-09-24-c — POS 결제상자 장애 4건 · 단축키 Alt+N

앞 핸드오프(`HANDOFF-2026-09-24-b`)는 **Phase 93 4단계**까지를 다룬다. 이 문서는 그 **뒤에**
일어난 운영 장애 대응이다. 다음 세션은 §1(미push) → §5(미해결) 순으로 읽으면 된다.

---

## 1. ★ push 안 된 커밋 — 하나

| 저장소 | 커밋 | 내용 |
|---|---|---|
| app | `c247d5e5` | 결제 줄 단축키를 **Alt+1 ~ Alt+4** 로 통일 (§4) |

검증 끝: tsc · eslint(오류 0) · jest 66 suite **761건** · `npm run build` exit 0.
프론트 단독이라 배포 순서 무관.

---

## 2. 이 세션에 배포된 것 — 전부 SUCCESS

| Jenkins | 커밋 | 내용 |
|---|---|---|
| api **#949** | `5eb9fc90` | 결제수단 **「Activar」 가 400** 이던 것 |
| api **#950** | `2f0c4d4f` | update 로 **남의 매장에** 결제수단을 밀어 넣을 수 있던 것 |
| front **#788** | `a26ff258` | **Efectivo 를 0 으로 못 만들던** 것 |
| front **#789** | `41d2bb5d` | **Tab** 으로 이동할 때 내려보내기가 건너뛰던 것 |
| front **#791** | `4fb1929`(=`9e40b56c`) | 금액을 **올리면 아랫줄이 줄어드는** 것(신규 기능) |
| front **#792** | `5f84bfb8` | **숫자패드** Re Pág/Av Pág 이 안 잡히던 것 |

★ front **#790 은 실패**했다 — 빌드가 아니라 **체크아웃**에서 죽었다
(`git@github.com: Permission denied (publickey)`). 같은 시각 내 push 도 GitHub 이
500 을 돌려줬다. **일시 장애**였고, 빈 커밋으로 웹훅을 다시 울려 #791 로 복구했다.
⤷ 이 잡은 **GitHub push 웹훅으로만** 돈다(`GitHubPushTrigger`, authToken 없음).
  Jenkins 는 `127.0.0.1:8080` 이라 API 로 못 부른다. 다시 죽으면 **ref 를 움직이는 것**이
  유일한 재시도 방법이다(빈 커밋).

---

## 3. 고친 장애 4건 — 원인이 전부 「보이지 않는 자리」에 있었다

### ① 「Activar」 가 400 (api #949)

`UpdatePaymentMethodDto.title` 이 **필수**였다. 토글은 `{ is_active }` 만 보낸다
(`PaymentMethodsList.tsx:64`) → `400 title must be a string`.
**update DTO 가 전 필드를 요구하면 어떤 토글도 성립하지 않는다.**

★★ 이게 매장 6(coolsistema)을 막고 있었다. 그 매장은 자기 결제수단
`tarjeta-debito`·`mercadopago`·`tarjeta-de-credito` 가 전부 비활성인데 **켤 수가 없었다.**
`GET /payment-methods` 는 `is_active=true` 만 주므로 POS 카탈로그에 매장 수단이
`efectivo` 하나뿐이었다. **전 매장 실측: 매장 6 만 4개 중 1개 활성.**

★ `@IsOptional()` 이 아니라 `@ValidateIf(=== undefined)` 를 썼다 —
`@IsOptional()` 은 **`null` 을 통과시키고**, `title`·`slug` 는 DB 에서 nullable 이라
`null` 이 오면 터지지 않고 **값을 지운다**(→ [[is-optional-lets-null-through]]).

### ② update 로 남의 매장에 밀어 넣기 (api #950, CODEX P1)

`assertRowAccess` 는 **편집하려는 행이 내 것인가**만 본다. 그런데 `storeId` 가 DTO 에
있어 **본문 값이 그대로 써졌다** — 자기 결제수단을 남의 매장으로 옮길 수 있었다.
DTO 에서 뺐다(`whitelist: true` 라 파이프가 버린다).
★ 시험은 「오류가 난다」가 아니라 **「서비스까지 안 간다」**를 잰다 — 버려지는 필드는
  검증 오류를 안 만든다.

### ③ Efectivo 를 0 으로 못 만든다 (front #788)

```
0 입력 → ponerMontoEnLista 가 줄을 삭제(의도된 동작)
      → 결제 0건 → AutoEfectivo 가 「새 판매」로 보고 전액을 다시 쓴다
```
0 이 존재할 틈이 없어 **내려보내기 자체가 불가능**했다. 막는 가드(`manuallyEdited`)는
**`InvoiceAditional` 의 지역 상태**였고, 2026-09-23 에 생긴 `PagoInline` 이 같은 목록을
편집하는데 그 가드를 켤 방법이 없었다.
⤷ 신호를 `SaleProductsContext` 로 올려 `pagoEditadoAMano` 로 만들었다.
⤷ 판정을 `debeSembrarEfectivo()` **순수 함수로 뺐다**(시험 10건) —
  이 결함이 안 보였던 이유가 「볼 수 없는 자리에 있었다」는 것이다.

### ④ Tab 으로 움직이면 내려보내기가 건너뛴다 (front #789)

★★★ **사용자는 항상 Tab 으로 움직인다.** 그래서 늘 겪고 있었다.

```
Tab → saltarAlSiguienteMonto 가 같은 keydown 안에서 다음 칸에 focus()
    → blur(윗줄): 내려보내기를 «예약»만 한다 (아직 갱신 전)
    → focus(아랫줄): 「들어올 때 금액」을 갱신 전 렌더에서 읽는다 → 0
    → 0 입력 → blur: 「이전(0) == 지금(0)」 → 안 바뀌었다고 보고 건너뛴다
```
1단계(efectivo)가 되던 이유는 **클릭**으로 들어가서 값이 제대로 잡히기 때문이다.
⤷ `pagosRef` (동기 거울)를 두고 `onFocus`/`onBlur` 가 그것을 읽는다.
  `useEffect` 는 페인트 뒤라 **같은 이벤트의 `focus` 에는 이미 늦다.**
⤷ 이 상자의 쓰기를 **한 통로**(`escribirPagos`)로 모았다 — CODEX 가 그중 **둘이 이미
  「수동 편집」 표시를 잊고 있던 것**을 짚었다(마지막 수표 삭제 · 슬롯 메서드 교체).

---

## 4. 새로 만든 것

### 금액을 올리면 아랫줄이 줄어든다 (front #791)

종전 규칙은 부족분만 내려보내고 초과분은 일부러 뒀다. 이제 같은 방향으로 내려가며 뺀다.
**규칙(사용자 결정 2026-09-24)**: 아래로 **이어서** 뺀다 · **현금 불가침** ·
**수표 불가침**(금액이 종이에 적혀 있다) · 아래가 모자라면 「Sobra」로 남기고 **위로
올라가지 않는다**. `reequilibrarAbajo()` 하나로 두 방향을 합쳤다.

### 단축키 Alt+1 ~ Alt+4 (미push, `c247d5e5`)

「Alt + N = N번째 줄」. 라벨도 바꿨다. **4번째 줄에는 애초에 단축키가 없었다.**

★★ **Re Pág / Av Pág 은 지웠다.** 오늘 실측으로 **필요한 자리에서 안 먹는 것**이 드러났다:
 · 숫자패드는 `code` 가 `Numpad9`/`Numpad3` → 라이브러리가 `"9"`/`"3"` 으로 정규화 →
   `'pageup'` 과 영영 안 맞는다. **토스트조차 안 떴다**(판정부까지 안 갔다).
 · Mac 에는 PageUp 키가 **없다**(`Fn+↑` 가 `ArrowUp` 으로 온다 — 실측).
⤷ `useKey: true` 로 `code` 가 아니라 `key` 를 본다. `Alt+N` 은 세 OS 가 같은 `key` 를 준다.
★ **F9 는 남기고 목록에도 실었다.** 처음엔 「옛 키를 조용히 남기자」고 했는데
  `pos-shortcuts-sync` 시험이 막았다 — 「코드에 있는 키는 전부 목록에 있어야 한다」.
  **그 규칙이 옳다: 동작하는데 안내 안 하는 키는 함정이다.**

---

## 5. ★ 미해결

1. **Repaso(Ctrl+R) 가 판매 때마다 시계 화면으로 바뀐다** (매장 19 NOIX 등
   `use_size=false`·`use_color=false` 매장). 시계는 **그 매장들의 Zone 2 기본값**이다
   (`VcontrolHome.tsx:375-383`) — 즉 Repaso 가 닫히면 시계가 남는다.
   ★ 코드에 **평범한 판매로 `reviewMode` 를 끄는 경로가 없다**(`setReviewMode` 전수:
     Ctrl+R 토글 · Ctrl+D · 패널 닫기 버튼 · 변형매장 스위치). 그래서 화면이 통째로
     **재마운트**되는 쪽을 의심한다. 게이트 후보: `pages/nueva-venta/index.tsx` 의
     `loaded` · `withAccess` 의 `if (!user || !hasRole …) return null`.
   ⤷ 다음에 재현되면 **화면이 잠깐 깜빡이거나 회색 틀(스켈레톤)이 보이는지** 확인.
     그 한 가지로 「누가 상태를 끈다」와 「통째로 다시 뜬다」가 갈린다.

2. 앞 핸드오프 §7 의 미결 3건(프로비저닝 트랜잭션 · 서버 수표 중복 거절 ·
   같은 이름 descuento) 그대로.

---

## 6. 도구·방법 메모

- **소스만 보면 전부 «맞게» 보이는 결함이 셋이었다.** ③④ 와 숫자패드 건은
  훅도 옵션도 키 이름도 정상이었다. 갈린 것은 **브라우저에서 실제로 찍어 본 것**이다:
  ```js
  window.__k=[]; window.addEventListener('keydown',e=>window.__k.push(e.key+' | '+e.code),true)
  ```
  `KEY PageUp | Numpad9` 한 줄이 원인을 확정했다.
- **cmux/Chrome 으로 운영을 몰 수 없다.** 그 Chrome 은 로그인 상태가 아니고,
  **내가 로그인하면 사용자의 POS 세션이 끊긴다**(중복 로그인 차단). 그리고
  그 Chrome 은 `localhost:3050` 에도 **닿지 못한다**(`ERR_CONNECTION_REFUSED`,
  셸의 curl 은 200) — 같은 기계의 네트워크가 아니다.
- **로컬 운영 빌드**: `npx next start -p 3050`. ★ `NODE_ENV=production` 이라
  **운영 API 를 본다** — 거기서 F2 를 누르면 **진짜 판매**다.
- `codex exec` 는 **`-o` 를 주면 조용히 죽는다**(이 세션 2회). stdout 리다이렉트로 받고,
  프롬프트에 「git 명령 금지, 아래 3~4개 파일만 `cat`」을 명시한다.
  → [[codex-exec-dies-silently-on-big-prompt]]
