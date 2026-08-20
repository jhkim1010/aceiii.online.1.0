# 핸드오프 — 2026-08-20 (밤, 이어서) · Phase 85 **W2 완결**

`HANDOFF-2026-08-20-c-phase85-w2.md` 에서 이어짐. 그 문서의 "다음 세션이 바로 할 것 —
W2 잔여 2건" 을 **둘 다 끝냈다.**

## 배포

```
api-ventago  f682397  feat(socket): 소켓 보유 수를 클러스터 전체로 센다      Jenkins api #762 SUCCESS
             fe9b63e  fix(socket): identity 가 전원 u:undefined 로 뭉치던 것  api #763 SUCCESS
             f659bef  fix(socket): 공방 포털 토큰(id·email 없음)도 센다       api #764
ventago-app  e7f4f7b  perf(printer): 에이전트 상태 30초 폴링 → realtime      front #675 SUCCESS
```

★ **뒤의 두 커밋은 배포 후 운영 Redis 를 직접 보고 나온 것이다.** 코드도 테스트도
빌드도 다 통과한 상태에서, 실제 키가 무엇으로 찍히는지 보고서야 두 번 틀린 것을 알았다.
자세한 것은 아래 「배운 것」.

## Phase 85 진행률: 8 웨이브 중 **2개 완결**

| 웨이브 | 상태 |
|---|---|
| W1 캐시 봉인 | ✅ 완결·배포 |
| W2 소켓 provider + 서버제한 | ✅ **완결·배포** (한도는 관측 후 켠다 — 아래) |
| W3 pageSize 클램프 | ⬜ ← **다음** |
| W4 무중단 마이그레이션·파티셔닝 | ⬜ (★ 행 수 실측 전 착수 금지) |
| W5 무중단 배포 / W6 매장별 논리 복구 / W7 야간 rollup / W8 300매장 회귀 | ⬜ |

## ★ 다음 세션이 **먼저** 할 것 (5분) — 소켓 한도 켜기

집계는 배포됐고 **한도는 꺼져 있다**(`SOCKET_MAX_PER_IDENTITY=0`). 며칠 돌린 뒤 분포를
보고 켠다.

```bash
# superadmin 토큰으로
curl -s https://newapi.coolsistema.com/api/diagnostics/sockets -H "Authorization: Bearer <token>" | jq
```

읽는 법:
- `histogram` = **"소켓 N개를 들고 있는 identity 가 몇 명인가"**. 한도는 이 꼬리 **위**에 둔다.
- `maxPerIdentityAcrossNamespaces` = 한 사람이 전 네임스페이스 통틀어 들고 있는 최댓값.
- `source: 'worker-local'` 이 나오면 Redis 가 안 붙은 것 — 그 값은 **실제의 1/4** 이다(4워커).
- `byNamespace` 에 `realtime` 이 사용자 수보다 훨씬 크면 **또 누가 `io()` 를 직접 불렀다는 뜻**이다.

켜기: `api-ventago/.env` 에 `SOCKET_MAX_PER_IDENTITY=<값>` → 컨테이너 재시작. **재배포 불필요.**
`SOCKET_WARN_PER_IDENTITY`(기본 6)는 한도가 꺼져 있어도 초과 시 경고 로그를 남긴다.

★ **계획서의 "기본 2" 를 그대로 켜지 말 것.** 그 값은 W2 통합 **전**(POS 한 탭 = 5소켓)
기준이다. 지금은 한 탭 = 네임스페이스당 1개지만, **한 사람이 탭을 여러 개 여는 것은 정상**이다.

## W2 에서 배운 것 (다음 웨이브에도 적용된다)

★ **`npm run lint` 를 api-ventago 에서 돌리지 말 것.** 이 스크립트는 `eslint --fix` 라
저장소 전체를 **자동 수정한다** — 오늘 무관한 파일 162개가 한 번에 바뀌었다. api 는
이미 9,445개 lint 오류를 안고 있어서 이 명령은 게이트도 아니다(**Docker 빌드는 `nest build`
만 돌린다**). 검사는 `npx eslint --no-fix <바꾼 파일>` 로 한다.
프론트는 반대다 — `next build` 가 lint 를 진짜 게이트로 쓴다.

★ **zsh 는 `for f in $VAR` 에서 단어 분리를 하지 않는다.** 위 사고를 수습하려고
"내가 바꾼 파일만 빼고 되돌리기" 를 했는데 제외 목록이 통째로 한 단어가 되어
**내 작업까지 되돌아갔다.** 파일 목록은 배열(`arr=(...)`)이나 stdin 으로 넘긴다.
(macOS `xargs` 에 `-a` 없음, `timeout` 없음도 같이 걸렸다.)

★ **워커 로컬 카운터는 카운터가 아니다.** pm2 4워커에서 한 탭의 소켓들은 OS 가 워커에
나눠 배정하므로 로컬 집계는 실제의 1/4 을 본다. rate-limit 에서 이미 같은 함정을 겪었고
(`redis-throttler.storage.ts` 주석), 소켓에서도 같았다. 공유 카운터는 Redis 로 간다.

★ **정리 없는 카운터는 시한폭탄이다.** 워커가 SIGKILL 로 죽으면 disconnect 훅이 안 돈다.
죽은 항목을 걸러내지 않으면 카운트가 영구히 올라가 **한도를 켜는 순간 전원이 차단된다.**
그래서 6분 만료 + 실제 HDEL 로 자가 치유하고, 그 정리 로직을 지우면 죽는 spec 을 뒀다.

★ ★ **관측 장치는 "코드가 맞다" 로 검증되지 않는다 — 운영에서 나온 값을 봐야 한다.**
집계를 배포한 뒤 Redis 를 열어 보니 키가 **`wsc:realtime:u:undefined` 하나뿐**이었다.
`JwtPayload.id` 는 인터페이스에만 있고 **서명 payload 에는 없다**
(`auth.service.ts:646` — name/lastName/email/status/trialEndsAt/roles/storeId 뿐).
전원이 한 identity 로 뭉쳐 있었고, **그 상태로 한도를 켰다면 N번째 이후 전원 차단**이었다.
고쳐서 재배포한 뒤 또 보니 이번엔 `u!<socketId>` — id 도 email 도 없는
**공방 포털 토큰**(`vendor-auth.service.ts:81`: `type·vendorId·storeId·vendorPhone`)이
`/realtime` 에 붙어 있었다. 이 저장소의 JWT 는 **한 가지 모양이 아니다**:

| 발급처 | payload | identity |
|---|---|---|
| 웹/모바일 사용자 | email·storeId·roles (**id 없음**) | `u#<해시>` |
| 재판매자 | `type:'revendedor'`·id·email | `revendedor:<id>` |
| 공방 포털 | `type:'vendor'`·vendorId (**id·email 없음**) | `vendor:<id>` |

★ **부수 발견 — 별건이지만 알아 둘 것:** 사용자 토큰에 `id` 가 없다는 것은
`websocket.service.ts:55` 주석이 이미 적어 둔 기존 결함이다. 그래서 `user:{id}` room
가입이 안 되고 **`emitToUser` 가 브라우저에 도달하지 못한다**(DM 류 채널이 죽어 있다).
고치려면 토큰 payload 에 `id` 를 넣어야 하는데 인증 변경이라 Phase 85 밖으로 남겼다.

★ **codex 가 또 실제 결함 2건을 잡았다** (누적 8건). 이번 [P1] 은 특히 조용한 부류다:
node-redis 는 `reconnectStrategy` 가 숫자를 돌려주면 **초기 접속도 무한 재시도**해서
`await connect()` 가 영영 resolve 되지 않는다 → Redis 가 죽은 채 배포하면 **앱이 아예 안 뜬다.**
판단 기록: `.team/reviews/phase85-w2-socket-census-resolution.md`

## 이월 (고치지 않고 기록만)

- ★ **같은 `await connect()` 부팅 차단이 두 곳 더 있다** — `RedisThrottlerStorage.onModuleInit`
  과 `main.ts` 의 `RedisIoAdapter.connect()`. Redis 가 내려간 채 배포하면 같은 방식으로 막힌다.
  이번 커밋 범위 밖이라 손대지 않았다.
- ★ **`registerBranch` 는 단일 슬롯이다** (`websocket.service.ts:145`). 새 지점을 등록하면
  이전 방을 떠난다. 소켓을 공유하는 지금, 서로 다른 branchId 를 요구하는 소비자가 **동시에**
  뜨면 나중 것이 앞 것을 방에서 밀어낸다. 지금은 소비자가 둘이고 서로 다른 페이지라 무해 —
  **셋째가 생기면 터진다.**
- ★ **사용자 JWT 에 `id` 가 없어 `emitToUser`(user:{id} room) 가 죽어 있다** — 위 참조.
  토큰 payload 변경이라 별건. 고치면 소켓 집계 identity 도 자동으로 `u:{id}` 가 된다.
- `/me` 가 워밍 상태에서도 11쿼리 미캐시 (어느 웨이브에도 속하지 않은 별건)
- `mobile-stock` 캐시 키에 지점이 없다 — 같은 매장 다른 지점 판매원이 10초간 남의 수치를 본다
- 스테이징 DB 에 테이블 14개 누락 (`stock_balances`·`box_settlements`·`billing_*` 등)
- Redis 가 죽으면 권한 무효화가 전파되지 않아 워커별로 TTL(최대 5분)까지 낡은 권한

## 공용 워킹트리 (여전히 유효)

Phase 86 세션이 같은 워킹트리를 쓴다(브랜치 `feature/phase86-legacy-import-full`,
untracked 로 `tools/phase86/`·`api-ventago/migrations/2026-08-20-phase86-*.sql` 등).
**`git add -A` 금지 — 경로를 명시한다.** 오늘도 스테이징은 전부 경로 명시로 했다.
