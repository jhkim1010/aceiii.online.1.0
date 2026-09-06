# 핸드오프 2026-09-06 — 매장 대행 복구 · 미마감 카하 10개 정리

앞 세션은 `HANDOFF-2026-09-05-gastos-caja-aperturas-y-facturacion.md`.

```
api-ventago  6772be6 → 26e2416   (#872 SUCCESS · SHA 로 대조 · 운영 컨테이너에서 dist 확인)
부모 저장소   변경 없음 (Flutter 관리자앱 APK 는 여전히 미빌드)
```

앞 핸드오프의 ★★★ 두 건이 **둘 다 끝났다.**

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

실행 스크립트: `scratchpad/regularizar-cajas.sh`
(`--dry-run` · `--diag`(이제 `/auth/verify` 를 쓴다) · 이미정리됨 집계 · throttle 3초)

---

## 남은 것

| 우선 | 항목 |
|---|---|
| ★★★ | **ACE box 19 의 −2,731,000 원인 규명** → 그 다음 18·19 정리 |
| ★★ | **superadmin 대시보드 = 전 매장 파노라마**. 카하 **개시 여부**와 **미마감 경과일**이 둘 다 경고여야 한다 — 148일짜리가 조용히 있었다 |
| ★ | 관리자앱 **APK 빌드**(`build-apk.sh`) — 안 하면 폰에서 Fac. electrónica 탭이 안 보인다 |
| ★ | 인증서 만료 **2026-10-20 (44일)**. 감시 정상 |
| 중 | 대행 중 `reports?storeId=` 우선순위 · `stores` 훅 면제 (위 ① 마지막 절) |
| 중 | 채번 뮤텍스 → PG advisory lock (워커 4개 · 10016 거부 방지) |
| 중 | `ops-daily-check` 가 `todas`·Dropbox 업로드를 안 본다 |
| 중 | `dropbox_sync.sh`·`pg_backup_todas.sh`·`regularizar-cajas.sh` 가 **git 에 없다** |
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
