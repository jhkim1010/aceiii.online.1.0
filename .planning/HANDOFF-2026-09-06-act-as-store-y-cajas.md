# 핸드오프 2026-09-06/07 — 매장 대행 복구 · 카하 정리 · 개시금 진입점

앞 세션은 `HANDOFF-2026-09-05-gastos-caja-aperturas-y-facturacion.md`.

```
api-ventago  6772be6 → 26e2416 (#872)  → 7ee3848 (#873)   전부 SUCCESS
ventago-app  e180b6b → 91327be (#714)  SUCCESS
부모 저장소   8a1d920 → f5b2257 → (이 문서)
```
세 배포 모두 **운영 컨테이너 안에서 dist 를 grep 해 반영을 확인**했다
(빌드 SUCCESS 는 배포 확인이 아니다).

앞 핸드오프의 ★★★ 두 건이 **둘 다 끝났고**, 그 과정에서 나온 두 건을 더 했다.

목업(개시금 진입점 결정용): `.planning/mockups/caja-monto-inicial/` —
아트보드 5장(현재 / 안A / 안B / 모달 2상태). 캔버스는
https://claude.ai/code/artifact/646d0fe3-137e-49de-9880-bd1d873624ea

---

## ① X-Store-Id — nginx 가 아니었다. 가드가 두 번 돌았다

**앞 핸드오프의 가설은 틀렸다.** 운영 로그에 `[ACT-AS]` 감사 줄이 8/8 남아 있었다 —
헤더는 앱까지 **도달했다.** nginx 는 무죄다.

진짜 원인:

```
전역 JwtGlobalGuard   →  request.user = {...user, storeId: 6}     ← 채운다
라우트 @Auth()        →  UseGuards(AuthGuard('jwt'), UserRoleGuard)
                          passport 가 **한 번 더** 돌며 request.user 를 덮어쓴다  ← 지운다
핸들러 @GetUser()     →  storeId = null  →  400 "Usuario no tiene tienda asignada"
```

Nest 가드 순서가 **전역 → 컨트롤러 → 라우트**라서다. `TenantContext` 는 storeId=6 을
유지했으므로 ORM 격리는 맞게 돌았다 — 깨진 것은 `request.user.storeId` **하나**다.
`/afip/soap-status` 가 200 이었던 것도 이것으로 설명된다(같은 `@Auth()` 지만
`user.storeId` 를 안 읽는다).

**범위는 라우트 하나가 아니었다**: `@Auth(` 576곳(131파일) + 직접
`UseGuards(AuthGuard('jwt'))` 45곳. 즉 Phase 67-C 도입 이후 **매장 대행은 한 번도
동작한 적이 없었다.** act-as 관련 테스트가 저장소에 0건이라 아무도 몰랐다.

★★ **앞 핸드오프의 `--diag` 는 돌렸어도 틀린 답을 줬다.** `/auth/me` 는 `request.user`
   를 안 보고 Authorization 헤더에서 사용자를 다시 유도한다
   (`auth.controller.ts` → `authService.me(req.headers.authorization)`).
   대행이 정상이어도 storeId 가 절대 안 바뀐다 → 「헤더가 안 먹는다」로 오독됐을 것이다.
   **맞는 잣대는 `GET /auth/verify`** — `@GetUser()` 로 request.user 를 그대로 돌려준다.

### 수정 (`26e2416`)

대행 적용 지점을 **가드에서 전략으로** 옮겼다. `JwtStrategy` 에
`passReqToCallback: true` 를 켜고 `validate(req, payload)` 안에서 헤더를 해석해
**복제본**을 돌려준다 → passport 가 몇 번을 돌든 결과가 같다.

`resolveActAsStore` 는 둘로 나눴다:
- `resolveActAsStoreFor(request, user)` — 순수 해석기(로그 없음). 전략이 쓴다.
  (전략 시점에는 `request.user` 가 아직 없어 주체를 인자로 받아야 한다.)
- `resolveActAsStore(request)` — 감사 로그 래퍼. 요청당 한 번 도는 가드만 쓴다.
  안 나누면 `[ACT-AS]` 가 요청마다 **두 줄**씩 찍힌다.

★ 캐시된 사용자 객체는 변형하지 않는다 — `auth:user:{id}` 로 30초 공유되므로
  in-place 로 찍으면 대행이 끝난 뒤의 다른 요청까지 오염된다.

### 검증

`src/app/auth/act-as-store.spec.ts` (supertest + **실제 `@Auth()` 라우트**), 9건.
- 고치기 전 코드에서 **실패**하는 것을 확인했다(핵심 2건 실패, 대조군은 양쪽 통과).
- ★ 「가드가 두 번 돈다」는 **전제 자체를 잰다** — `/con-auth` passport 2회,
  대조군 `/sin-auth` 1회. 이 계수가 없으면 `@Auth()` 를 떼도 통과한다(codex 지적).
- 일반 사용자 헤더 무시 · 없는 매장 400 · 캐시 비오염도 함께 고정.

운영 실측(`--diag`):
```
헤더 없이 : storeId= None   actingAsStoreId= None   roles= ['superadmin']
헤더 있이 : storeId= 6      actingAsStoreId= 6      roles= ['superadmin']
```

### CODEX 자문에서 확인한 것

- `passport-jwt@4.0.1` 은 `passReqToCallback` 시 `verify(req, payload, done)` 를 부르고
  Nest 래퍼가 그대로 넘긴다 → `validate(req, payload)` 서명이 맞다.
- `validate()` 안의 `BadRequestException` 은 401 로 뭉개지지 않고 **400** 으로 나간다
  (`auth.guard.js:58` 이 원래 err 를 그대로 throw).
- `request.user.roles` 는 항상 `string[]` 이라 `UserRoleGuard` 의 객체 분기는 죽은 코드다
  → 대행 중 superadmin 이 역할을 잃는 경로는 없다.
- `storeId=null` 을 「전 매장」으로 읽던 3곳(admin 대시보드 2 · reports 1)은
  대행 시 **의도대로 좁아진다.** 넓어지는 분기는 없다.

### ★ 대행은 격리가 아니다 (이번 커밋 범위 밖 · 대행 이전부터 있던 것)

- `reports` 는 raw SQL 이라 ORM 훅이 안 걸리는데 `requestedId ?? user.storeId` 순서다
  → `X-Store-Id: 6` + `?storeId=9` 면 **9 가 이긴다**.
- `stores` 는 테넌트 훅 **면제 테이블**이고 `roles` 에 superadmin 이 남아 있어
  대행 중에도 `/store/<다른매장>` 조회·수정이 열린다.

권한 상승은 아니다(superadmin 은 원래 다 볼 수 있다). 하지만 「대행 중에는 그 매장에
갇힌다」는 문서상의 약속은 **사실이 아니다.** 그렇게 믿고 무언가를 짓지 말 것.

---

## ② 미마감 카하 — 10개 정리 완료, ACE 2개는 일부러 남겼다

**★ 앞 핸드오프의 표는 범위가 틀렸다.** 「8서랍 16세션」의 16은 *열린* 세션 수였고,
`regularize` 는 **그 서랍의 미정산 섬 전체**를 닫는다. 그리고 열린 세션이 0이라
목록에서 빠져 있던 서랍이 **4개**(box 6·18·19·20, 117세션) 더 있었다.

실행 결과 (2026-09-06 01:35–01:36 UTC · `box_settlements` id 39~48):

| box | 매장 | 서랍 | 세션 | 구간 | esperado | variance |
|---|---|---|---|---|---|---|
| 15 | coolsistema | JuanaCaja | 51 | 04-23~08-10 | 677,400 | −677,400 |
| 6 | coolsistema | Caja 1 | 60 | 03-26~08-10 | 139,500 | −139,500 |
| 20 | coolsistema | HELGUERA | 5 | 08-03~08-10 | 0 | 0 |
| 3 | CART | Caja 1 | 17 | 02-23~04-28 | −1,100 | +1,100 |
| 13 | CART | Caja de TEST | 1 | 04-10 | 14,500 | −14,500 |
| 9 | genius | Caja 1 | 6 | 03-27~04-20 | 464 | −464 |
| 21·22·23·24 | mana·Asado·naty·naty | — | 2·4·3·1 | — | 0 | 0 |
| | | | **150** | | | |

★ **box 15 는 805,900 이 아니라 677,400 이다.** 서비스는 섬의 **첫 세션 개시금 하나**만
  쓴다(`uncovered[0].initialAmount` = 16,500). 51세션 개시금 합 230,000 이 아니다.

**돈은 움직이지 않았다 — 실측으로 확인:**
```
caja_fuerte_operations 신규        0
box_operations 신규                0
caja_fuerte_operation_id 있는 정산행 0
counted_cash <> 0 인 정산행         0
10개 서랍의 남은 열린 세션           0   (16 → 0)
남은 미커버 세션                    52   (= ACE 18/19 정확히)
sum(sessions_count) 39~48          150  (예측과 일치)
```
감사 로그 10건(`audit_logs` 4659~4668)에 contado/esperado/diferencia + 사유가
매장별로 정확히 남았다 — 대행이 끝까지 동작했다는 증거이기도 하다.

### ★★ ACE(store 9) 2개는 남겼다 — 사용자 결정 2026-09-06

| box | 서랍 | 세션 | esperado | 0 으로 닫으면 |
|---|---|---|---|---|
| 18 | Caja Jefe | 32 | −26,000 | variance +26,000 |
| **19** | **Caja de SALA** | 20 | **−2,731,000** | variance **+2,731,000** |

**box 19 는 출금·지출이 매출·입금보다 273만 많다.** 0 으로 닫으면 「현금이 273만
남아돌았다」는 기록이 남는다. ACE 는 실제 영업 중인 매장이라 **원인을 먼저 본다.**
가설: 카드 매출이 `venta` 로 안 들어갔거나, `retiro` 만 기록됐거나.

### ★ 「실패 10건」 은 성공이었다

스크립트를 두 번 돌렸고 **두 번째 출력만 보고됐다.**
- 01:35:44~01:36:18 UTC → 10× `201 Created` ← 진짜 실행
- 03:00:14~03:00:48 UTC → 10× `400 ERR-REG-004` ← 멱등 재실행의 **정상** 응답

「성공 0 · 실패 10」으로 읽혔지만 장부는 이미 완료 상태였다. 스크립트를 고쳐
ERR-REG-004 를 **「이미 정리됨」** 칸으로 따로 세게 했다.

실행 스크립트: **`.planning/regularizar-cajas.sh`** (이제 저장소에 있다 — 종전에는
scratchpad 에만 있어 세션이 끝나면 사라졌다. 「서버에만 있는 스크립트」와 같은 문제였다)
(`--dry-run` · `--diag`(이제 `/auth/verify` 를 쓴다) · 이미정리됨 집계 · throttle 3초)

---

## ③ ACE box 19 의 −2,731,000 — 이미 고쳐진 결함의 잔재였다

**−2,720,000 이 2026-06-04 하루에서 나왔다.** 나머지 날은 전부 순증감 0 이다.
그날 서랍: 입금 20,000 · 지출 680,000×2 · **출금 1,380,000**(= 20,000 + 1,360,000).

원인은 커밋 **`924736f`(2026-08-13)** 이 **이미 진단하고 이 카하를 이름으로 지목해
고친 것**이다:

> `expenses.service` 가 gasto 를 `-Math.abs` 로 **음수** 저장했는데 잔액을 읽는 9곳은
> 양수 크기를 가정한다 → 부호가 두 번 뒤집혀 **지출이 잔액을 올렸다.**
> 운영: **카하 125(store 9 / 지점 15 SALA)** — 자동마감이 잔액을 1,380,000 으로
> 계산해 전액을 금고로 이체했다(`caja_fuerte_operations #44`). 실입금은 20,000.

수정은 살아 있다 — `chk_box_operations_amount_non_negative` 존재 · 음수 행 **0건**.
그 커밋은 CODEX 자문을 거쳐 **과거 이체는 재계산하지 않기로** 결정했고, 그래서
유령이 장부에 남아 있었다. 금고(SALA, id 8)는 2,922,001 까지 쌓였다가
**부호 수정과 같은 날 소유자가 `admin_retiro` 두 번으로 0 으로 비웠다.**

★ **틀린 가설을 두 번 세웠다.** 「자동마감이 gasto 를 더했다」로 시작했는데,
  6월에 실제 배포돼 있던 커밋(빌드 369 `973a5b8` — 빌드 370 은 이체보다 2시간 뒤인
  14:03 시작)을 읽으니 코드는 정상이었다. 산수는 같아도 **원인 위치가 달랐다** —
  코드가 더한 게 아니라 데이터가 음수였다. 배포 시각을 먼저 확인했으면 빨랐다.

**box 18 의 −26,000 은 성격이 다르다 — 부패가 아니라 구조다.**
매일의 개시금 선언(30,000·20,000·12,000)이 원장에 **입금으로 안 잡히는데**
자동마감은 그 현금을 금고로 옮긴다. box 19 의 나머지 −11,000 도 같은 것이다.
현재 코드는 `declaredOpening` vs `openingFromSafe` 대조로 `review_required` 로 잡는다.

**중복 지출 1건 삭제**(사용자 결정 2026-09-06): `box_operations #69` "Compra de PC"
680,000. 19:10:34 입력 → 19:11:39 「Hardware」 카테고리 생성(감사 433) → 19:12:03
재입력. `expenses` 대응 행 없음(gasto↔카하 링크는 `d158007`, 8월 13일 도입),
트리거 0 · 인입 FK 0 → 자기완결적. `audit_logs` 에 `old_values` 전문과 함께 기록.
→ box 19 esperado **−2,731,000 → −2,051,000**.

## ④ 개시금(monto inicial)을 뒤늦게 넣을 방법이 데스크톱에 없었다

```
api-ventago  26e2416 → 7ee3848   (#873)
ventago-app  e180b6b → 91327be   (#714)
```

POS 는 카하가 없으면 `auto-open` 으로 **0 원짜리**를 먼저 연다. 그 뒤 실제 금액을
넣을 자리가 **없었다** — 네 문이 전부 닫혀 있었다:

| 진입점 | 왜 안 되나 |
|---|---|
| 상단 앱바 ✏️ (`BoxTerminalStatus`) | 앱바가 `display:{xs:'block',lg:'none'}` — 데스크톱에서 DOM 에는 있으나 **0×0** |
| 사이드바 수정 모달 | `setEditModalOpen(true)` **호출부가 파일에 없다** (죽은 코드) |
| 사이드바 「카하 시작」 | `!boxName` 조건 — 카하가 열려 있으면 안 보인다 |
| 개시 모달 | `openedToday` 면 `setModalOpen(false)` 후 return |

그리고 유일한 저장 경로였던 범용 `PUT /cash-register/:id` 에는 **규칙이 없었다** —
방향 제한·금고 기록·감사·마감 확인 전부 없음. 개시 경로가 막아 둔 우회로가
옆문으로 열려 있었다.

- 신규 `POST /cash-register/:id/monto-inicial` — **정확히 0 에서만**, 열린 카하만,
  매장·지점 스코프, 같은 트랜잭션에서 `withdrawOpeningFromCajaFuerte`.
- 범용 `PUT` 은 `initialAmount` 가 오면 **400**. 조용히 지우면 화면은 성공했다고 믿는다.
- 권한은 **이미 있던** `cambiar-monto-inicial-de-caja`(id 78, 모듈 `control-de-cajas`).
  `/control-de-caja` 목록이 이미 쓰던 그것이다. `functions.slug` 에 DB UNIQUE 가
  없어 moduleSlug 까지 넘긴다.
- 화면: 사이드바 푸터에 개시금 줄(0 이면 골드) + 모달 2상태(선언 / 차단→movimiento).
  권한 없으면 그리지 않는다.

CODEX 지적 반영 5건 — 그중 둘이 컸다:
- **SAVEPOINT**: `withdrawOpeningFromCajaFuerte` 는 예외를 삼키지만 **PG 오류는
  삼켜도 사라지지 않는다.** 트랜잭션이 aborted 가 되어 선언까지 롤백됐을 것이다.
  즉 "비치명적" 이라 적어 둔 경로가 실제로는 치명적이었다.
- **`current > 0` → `!== 0`**: 음수 개시금이 통과하고 있었다.

시험 13건 + 돌연변이 4종 사멸. ★ 그중 하나는 `if (false && ...)` 가 ts-jest 컴파일을
깨뜨려 **「Tests: 0」** 이 나왔다 — 통과가 아니라 **미실행**이다. 블록을 통째로 지워 다시 쟀다.

## 남은 것

| 우선 | 항목 |
|---|---|
| ★★★ | **ACE box 18·19 마감** — 원인 규명 끝. `regularizar-cajas.sh 18 19` (사용자 로그인 필요). 2026-09-07 첫 시도는 throttle 로 429, 스크립트 수정됨 |
| ★★ | **superadmin 대시보드 = 전 매장 파노라마**. 카하 **개시 여부**와 **미마감 경과일**이 둘 다 경고여야 한다 — 148일짜리가 조용히 있었다 |
| ★ | 관리자앱 **APK 빌드**(`build-apk.sh`) — 안 하면 폰에서 Fac. electrónica 탭이 안 보인다 |
| ★ | 인증서 만료 **2026-10-20 (44일)**. 감시 정상 |
| 중 | 대행 중 `reports?storeId=` 우선순위 · `stores` 훅 면제 (위 ① 마지막 절) |
| 중 | 프런트 `useHasFunction` 은 admin·store_owner 자동 통과, 서버는 superadmin 만 — 권한 없는 admin 은 버튼을 보고 403 (저장소 전역 패턴) |
| 중 | 상단 앱바가 `lg` 이상에서 통째로 숨겨진다 — 거기 든 기능(BoxTerminalStatus 등)은 데스크톱에서 없는 것과 같다 |
| 중 | 채번 뮤텍스 → PG advisory lock (워커 4개 · 10016 거부 방지) |
| 중 | `ops-daily-check` 가 `todas`·Dropbox 업로드를 안 본다 |
| 중 | `dropbox_sync.sh`·`pg_backup_todas.sh` 가 **git 에 없다**(서버에만). `regularizar-cajas.sh` 는 2026-09-07 에 저장소로 옮겼다 |
| 중 | legacy import 배선 — 매퍼 6개가 화면에서 안 불린다 |
| 하 | 외상/예약 매퍼 미구현 · `/configuracion?tab=productos` 1741ms |
| 하 | `by-slug/ecommerce` 404 폴러(매분) |
| 하 | `AfipResponseError`=「발급 안 됨」 전제는 ARCA 매뉴얼로 확인해야 한다 |

---

## 다음 사람이 알아야 할 함정

1. **감사 로그에 흔적이 있다 = 그 기능이 동작했다, 가 아니다.** `[ACT-AS]` 8줄이
   찍혀 있었지만 그 직후 다른 가드가 결과를 지웠다. 로그는 **그 지점까지** 왔다는 뜻뿐이다.
2. **진단 엔드포인트는 재는 대상과 같은 곳을 봐야 한다.** `/auth/me` 는 `request.user`
   를 안 본다. 잣대가 틀리면 「정상」과 「고장」이 같은 값을 낸다.
3. **멱등 경로의 재실행은 「실패 N건」으로 보인다.** 결과는 응답이 아니라 **DB** 로
   확인한다. `docker logs --since` 의 타임스탬프로 실행이 몇 번이었는지 갈린다.
4. **codex 에 `--model gpt-5-codex` 를 주면 안 된다** — 이 계정에서 미지원이고,
   출력을 파이프로 받고 있으면 오류가 안 보인 채 45분을 매달린다. 모델 지정 없이 부르고,
   프롬프트는 **stdin 이 아니라 argv** 로 준다. 긴 diff 를 붙이는 것보다
   「이 파일들을 읽고 git diff 를 봐라」가 더 안정적이고 정확했다.
   ★ `codex` 를 돌리면 **셸 cwd 가 저장소 루트로 리셋된다.**
5. **eslint 는 이 저장소에서 게이트가 아니다** — 손 안 댄 파일도 39건씩 난다.
   내 파일만 `npx prettier --write` 하고, `npm run lint`(=`eslint --fix`)는 돌리지 말 것.
6. **`boxes` 다** — 테이블 이름이 `box` 가 아니다.
7. **`SENSITIVE_THROTTLE` 은 60초에 10건이다**(초과 시 60초 차단). 일괄 스크립트가
   12건을 33초에 보내 마지막 두 건이 429 를 받았다. **이미 끝난 건도 요청은 나간다** —
   멱등이라고 공짜가 아니다. `regularizar-cajas.sh` 는 이제 서랍 번호를 **여러 개**
   받고(`… 18 19`), 10건을 넘으면 실행 전에 경고하며, 429 를 「권한 없음」과 구분해 찍는다.
8. **`functions.slug` 에 DB UNIQUE 제약이 없다.** 오늘 중복은 0건이지만 그건 제약이
   아니라 우연이다 — `@FunctionGuard` 에 moduleSlug 까지 넘기는 편이 안전하다.
