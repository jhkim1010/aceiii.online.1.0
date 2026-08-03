# Phase 70 — 재개 메모 (2026-08-03 작성)

세션 재시작 전 상태 인계. 이 문서 + `70-CONTEXT.md` + `70-BASELINE.md` 만 읽으면 이어서 진행할 수 있다.

---

## 지금까지 한 것

| Plan | 상태 | 근거 |
|---|---|---|
| 70-01 재고 읽기 전환 | **미착수** | — |
| 70-02 브랜치 정리 | **미착수** (팀 실행 3회 실패) | 아래 「팀 실행 실패」 |
| 70-03 상품 코드 수정·삭제 UI | **미착수** | — |
| 70-04 리포트 PDF | **미착수** | — |
| 70-05 폼 리셋 | **완료** — 커밋 `400e9cb` (ventago-app, **push 안 됨**) | `70-05-SUMMARY.md` |
| 70-06 트리거 폐기 | **미착수** (승인 게이트) | — |
| 70-07 UAT | **미착수** | — |

착수 시점 기준값은 `70-BASELINE.md` — 불변식 3종 로컬·운영 모두 0, 테스트 15 스위트/33건 pre-existing 실패.

## 다음에 할 일 (순서)

1. **70-03** 상품 코드 수정·삭제 UI → 2. **70-04** 리포트 PDF → 3. **70-01** 재고 읽기 전환(가장 신중히)
4. Wave 1 완료분 **한꺼번에 push** (api / front 각 Jenkins 빌드 성공 + 컨테이너 재생성 확인까지)
5. **70-06** 마이그레이션 — 로컬 5432 적용·검증까지 하고 **운영 5434 적용 전 사용자 승인**
6. **70-07** UAT (운영 + 브라우저 + Trello 카드 정리)

## 팀(cmux-team) 실행 실패 — 재시도 전 반드시 읽을 것

Conductor 를 3번 투입했고 **3번 다 같은 자리에서 죽었다. 산출물 0.**

- 증상: `Autocompact is thrashing: the context refilled to the limit within 3 turns of the previous compact, 3 times in a row`
- 요청 크기가 **첫 호출부터 520~550KB** (≈130k 토큰). 탐색으로 불어난 게 아니라 **시작부터** 차 있었다
- 원인: 전역 `~/.claude/settings.json` 의 `enabledPlugins` 34개 — MCP 도구 스키마가 모든 세션에 주입된다.
  역할 파일 38KB + `CLAUDE.md` 26KB 로는 설명되지 않던 나머지가 이것이다
- 조치: **플러그인 15개 제거** (figma/postman/planetscale/supabase/wix/sumup/mintlify/sourcegraph/serena/
  context7/chrome-devtools-mcp/data/agent-sdk-dev/ralph-loop/pyright-lsp).
  백업 `~/.claude/settings.json.bak-20260803-072738`
- ⚠️ **적용은 새 프로세스부터.** `/clear` 로는 안 되고 세션을 재시작해야 한다.
  재시작 후 Conductor 를 다시 띄우면 팀 실행이 실제로 가능한지 재평가할 것

태스크 6개는 `.team/tasks/` 에 남아 있다(001 assigned·죽음 / 002 aborted / 003~006 draft).
팀으로 재시도하지 않을 거라면 정리하거나 그대로 둔다 — 코드에는 영향 없다.

## 주의 사항

- **미push 커밋 1개**: ventago-app `400e9cb` (70-05). 루트 레포는 서브모듈 포인터를 아직 안 올렸다
- `.team/` · `.worktrees/` 는 추적 제외 처리됨 (루트 `.gitignore` / api-ventago `.git/info/exclude`).
  트리가 더러우면 cmux 동기화 검사가 태스크 ready 전환을 막는다
- 죽은 worktree 4개가 `.worktrees/` 에 남아 있다 — 필요 없으면 `git worktree prune` 후 디렉터리 삭제
- 70-06 은 `--exclusive`, 운영 적용·push 는 Master(사람 승인 후) 몫으로 태스크 본문에 명시돼 있다
