# 핸드오프 — 2026-08-20 (밤) · Phase 85 W1 완결 + W2 대부분

`HANDOFF-2026-08-20-b-phase85-w1-done.md` 에서 이어짐.

## 배포 상태 — 전부 운영 반영됨

```
api-ventago  cf5bee1  feat(realtime): 방 이탈 프로토콜 (W2 서버측)     Jenkins #761 SUCCESS
             c19fc41  test(cache): kanban 키 배선 spec                 #760 SUCCESS
ventago-app  23577f9  feat(realtime): 반납 시 방을 떠난다 (W2)         front #674 SUCCESS
             0faf3dc  feat(realtime): 네임스페이스당 소켓 1개 (W2)     front #673 SUCCESS
root         274a8b8  chore: W2 방 이탈 프로토콜 배포 반영
```
운영 확인: 4워커 online · health ok · redis 구독자 4 · 5xx 0.

## Phase 85 진행률: 8 웨이브 중 **2개**

| 웨이브 | 상태 |
|---|---|
| W1 캐시 봉인 | ✅ 완결·배포 |
| W2 소켓 provider + 서버제한 | 🟢 대부분 — **잔여 2건** |
| W3 pageSize 클램프 | ⬜ |
| W4 무중단 마이그레이션·파티셔닝 | ⬜ (★ 행 수 실측 전 착수 금지) |
| W5 무중단 배포 / W6 매장별 논리 복구 / W7 야간 rollup / W8 300매장 회귀 | ⬜ |

## ★ 다음 세션이 바로 할 것 — W2 잔여 2건

### 1) 소켓 수 제한 (마지막에 켠다)
계획서의 **"기본 2" 를 그대로 켜면 POS 가 전부 끊긴다.** 통합 전 POS 한 탭이 최대 5소켓이었다.
통합이 배포됐으니 이제 실측 가능하다.

**실측 기준선 (2026-08-20 확인)**: POS 탭 1개 = API 컨테이너 established 연결 **+2**
(WebSocket 1 + HTTP keepalive 1). 측정법:
```bash
ssh jhkim-server 'sudo docker exec api_ventago sh -c \
  "cat /proc/net/tcp /proc/net/tcp6 | awk \\"\\\$4==\\\\\\"01\\\\\\"\\" | wc -l"'
# 탭 열기 전/후/닫은 후 3회. 2026-08-20 실측: 44 → 46 → 44
```
제한은 `(userId, terminalId)` 당 소켓 수. 한 사람이 탭을 여러 개 여는 것이 정상이므로
**2 는 너무 낮다** — 실사용 분포를 먼저 보고 정할 것.

### 2) `PrinterConfigTab.tsx:90` 30초 폴링 → realtime 대체
리팩터의 남은 절반. `useThermalAgentStatus` 가 이미 `agent_status_changed` 를 구독하므로
같은 훅을 쓰면 된다.

## W2 에서 배운 것 (다음 웨이브에도 적용된다)

★ **계획서 수치는 착수 전에 반드시 코드로 대조한다.** 이 Phase 에서 근거 문서가 낡은 것이
**3번째**였다: 대상이 4개가 아니라 9개, "제한 기본 2" 는 POS 를 끊는 값, "서버에 leave 가
아예 없다" 는 부정확(`registerBranch` 는 원래 있었다 — 이건 **내 조사**가 틀린 것이다).

★ **기전을 라이브러리 소스로 확인하면 해법이 바뀐다.** socket.io 는 *다른* 네임스페이스는
물리 연결을 공유하지만 **같은 네임스페이스를 두 번째로 열면 일부러 새 연결을 만든다**
(`lookup()` 의 `sameNamespace` 분기). 그래서 고칠 것은 "소켓을 줄이자" 가 아니라
**"같은 네임스페이스는 한 번만 연다"** 였다.

★ **공유 자원으로 바꾸면 기존 관용구가 흉기가 된다.** `socket.off('event')` 와
`removeAllListeners()` 는 남의 핸들러를 지우고, `disconnect()` 는 남의 화면을 죽인다.
소켓뿐 아니라 캐시(W1)에서도 같은 형태였다 — **공유로 바꾸는 변경은 기존 정리 코드를
전수 조사할 것.**

★ **codex 검토가 매번 실제 결함을 잡았다** (W1 2건 · W2 클라 3건 · W2 서버 1건 = 6건).
전부 "동작은 하는데 조용히 틀리는" 부류였다. 특히 W2 서버의 [HIGH]:
`register` 는 DB 검사를 `await` 한 뒤 join 하는데 `leave` 는 동기라
`register → 대기 → leave(무효) → join` 순서면 원치 않는 방에 **영구히** 남는다.

★ **빌드 확인은 파이프 없이 종료코드로.** `npm run build | grep` 은 grep 의 종료코드를
돌려줘 실패를 덮는다 — 깨진 커밋이 그대로 push 됐다(front #672 FAILURE).

## 환경 메모

- **로컬 `ventago` DB 는 비어 있다**(0 테이블). 메모리의 "복원했다" 기록은 낡았다.
  로컬 API 를 띄우려면 SSH 터널이 빠르다:
  `ssh -N -L 15432:127.0.0.1:5434 jhkim-server` → `.env` 의 DATABASE_PORT=15432,
  DATABASE_NAME=ventago_staging. `.env` 는 이미 그렇게 만들어 뒀다(gitignore 됨).
- ★ **`.env` 에서 운영과 반드시 달라야 하는 것**: DB(터널/스테이징) · `CRON_ENABLED=false`.
  크론을 켜면 캠페인·outbox·Telegram 이 **실제 고객에게** 나간다.
- ★ **로컬에서 `next start`(프로덕션 번들) 금지.** `api.service.ts:20` 이 NODE_ENV!=='development'
  이면 API 를 **운영**(`newapi.coolsistema.com`)으로 보낸다 — 브라우저가 운영에 로그인해
  중복로그인 차단으로 실제 사용자를 튕겨낸다. 반드시 `next dev`.
- dev 모드 프론트가 auth 로딩 셸에서 멈추는 현상을 겪었다(원인 미규명, 코드 변경과 무관 —
  같은 코드로 첫 시도엔 로그인까지 됐다). 운영에서 직접 검증해 우회했다.

## 공용 워킹트리 주의 (오늘 사고)

이 저장소에 **Phase 86 세션이 같은 워킹트리를 쓴다**(현재 중지, 브랜치
`feature/phase86-legacy-import-full`). 내가 `git add -A .planning` 을 써서 그 세션의
미완성 작업(`86-SPEC.md` 등)을 내 커밋에 쓸어담았다. 수습 완료:
main 은 깨끗하고(worktree 로 내 파일만 재커밋), 브랜치는 `git reset --mixed origin/main`
으로 되돌려 그 세션 파일은 untracked 로 무사하다(체크섬 대조 확인).

→ **이 저장소에서는 `git add -A` 를 쓰지 않는다. 경로를 명시한다.**
→ 병렬 세션이 필요하면 **worktree 를 분리**할 것.

## 이월 (고치지 않고 기록만)

- `/me` 가 워밍 상태에서도 **11쿼리 미캐시** — W1 이 3%밖에 못 줄인 진짜 이유. 어느 웨이브에도
  속하지 않은 별건이다.
- `mobile-stock` 캐시 키에 지점이 없다 — 같은 매장 다른 지점 판매원이 10초간 남의 지점 수치를 본다.
- 스테이징 DB 에 **테이블 14개가 없다**(`stock_balances` · `box_settlements` · `billing_*` 등).
  그쪽 엔드포인트는 스테이징에서 500 이다. 근본은 복원본 재생성.
- Redis 가 죽으면 무효화가 전파되지 않아 워커별로 TTL(최대 5분)까지 낡은 권한을 준다(기존 성질).
