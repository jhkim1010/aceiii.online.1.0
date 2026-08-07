# 검토 결과 처리 — commit `b6b5b03` (Phase 75 W6-4)

검토: codex-cli 0.146.0, 2026-08-07 · **3회 반복** (지적 → 수정 → 재검토)
대상: `API_REPLICA_COUNT` 도입 + 커넥션 예산 단일 출처(`common/config/connection-budget.ts`)
판단: Claude Code — 규약 `.team/REVIEW-PROTOCOL.md`

| 회차 | 지적 | 판정 | 처리 |
|---|---|---|---|
| 1 | [P2] `perNode` 에 워커 수가 빠졌다 | **타당** | 수정 |
| 1 | [P2] ecosystem 이 기본값을 항상 주입해 `(미선언)` 이 영원히 안 뜬다 | **타당** | 수정 |
| 2 | [P2] replica 값 미검증 — `0`·음수·비숫자가 확정값으로 노출된다 | **타당** | 수정 |
| 3 | — | **이상 없음** | push |

**3건 모두 같은 실패 형태다: 계기판이 조용히 틀린 값을 확정값처럼 보여준다.**
W6-8(워커 수 이중 관리)과 정확히 같은 종류이고, 이번 phase 에서 반복해 나오는 주제다.

---

## 1. `perNode` 에 워커 수 누락 — 타당

인터페이스는 `perNode` 를 "노드 1대가 쓰는 클라이언트 수"로 선언해 놓고 `mainMax + shopMax`(워커 1개분)를
넣고 있었다. 4워커 배포에서 노드당 실제 100 인데 `/diagnostics/pool` 에는 **25** 로 노출된다.

`totalClients` 는 `replicas × workers × perNode` 였으므로 **합계는 우연히 맞았다** — 그래서 로그만 보면
정상으로 보이고 진단 API 를 읽는 사람만 틀린 값을 받는다. 이름이 값과 다른 필드는 조용히 속인다.

수정: `perNode = workers × (mainMax + shopMax)`, `totalClients = replicas × perNode`. 합계는 불변.

## 2. `(미선언)` 경고가 영원히 안 뜬다 — 타당, 가장 중요

`ecosystem.config.js` 가 `API_REPLICA_COUNT: Number(env ?? 1)` 로 **항상 주입**하고 있었다.
그러면 앱은 언제나 "1로 선언됨"을 보므로 `replicasDeclared: true` 다.

이게 왜 문제인가: Phase 76 병렬 리허설에서 스위치가 이 값을 빠뜨리면 **2노드인데 예산은 1노드치**로
찍히는데, `(미선언)` 표시가 없으니 **확정값으로 오인**한다. 그 상태의 예산 로그는 G5 판정 근거가 될 수 없다.
"추정값이면 게이트가 성립하지 않는다"고 W6-9 에서 못 박아 놓고 정작 그 표시가 안 뜨게 만들어 둔 셈이다.

수정: 선언이 있을 때만 env 를 전달한다(`...(DECLARED ? { API_REPLICA_COUNT } : {})`).
미선언이면 앱이 1 로 가정하되 로그·API 가 `(미선언)` / `replicasDeclared:false` 를 드러낸다.

## 3. 값 검증 부재 — 타당

`Number('')`=0 · `Number('abc')`=NaN 인데 "값이 있으니 선언됨"으로 처리하고 있었다.
예산이 **0 이나 NaN 인 채로 확정값처럼** 노출된다 — 0 은 "커넥션을 안 쓴다"로, NaN 은 화면에서 빈칸으로
보이므로 **둘 다 안전한 것처럼 오독된다.**

수정: `readPositiveInt()` — 양의 정수만 선언으로 인정하고, 아니면 1 + `(미선언)`.
`WEB_CONCURRENCY` 에도 같은 결함이 있어 함께 적용했다(codex 는 replica 만 지적했으나 동일 경로다).

검증 표(unset · `""` · `"  "` · `"0"` · `"-1"` · `"abc"` · `"2.5"` → 전부 미선언 / `"2"` · `" 3 "` → 선언):
로컬 실행으로 확인.

---

## 부수 확인 — codex 의 tsc 실행 실패

codex 가 `./node_modules/.bin/tsc` 를 찾지 못해 타입 검사를 못 했다(exit 127).
**npm workspaces 라 바이너리가 루트로 호이스팅**되기 때문이다. codex 의 결함이 아니라 환경 특성이다.
타입 검사는 `npx tsc --noEmit -p tsconfig.json` 으로 **내가 별도 수행**했고 통과했다.
다음에 codex 에 검사를 맡기려면 루트 경로를 알려줘야 한다.
