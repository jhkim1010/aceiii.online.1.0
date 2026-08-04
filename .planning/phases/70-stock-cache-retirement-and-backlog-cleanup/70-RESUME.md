# Phase 70 — 재개 메모 (2026-08-04 갱신)

> **실행 계획은 `70-PLAN-SINGLE-PROCESS.md` 로 이동했다.** cmux-team 실행은 중단하고
> 단일 프로세스 순차 실행으로 전환. 이 문서는 상태 요약과 이력만 유지한다.
>
> 재개 시 읽을 것: `70-PLAN-SINGLE-PROCESS.md` + `70-CONTEXT.md` + `70-BASELINE.md`

---

## 상태 (2026-08-04 03:21 검증)

| Plan | 상태 |
|---|---|
| 70-01 재고 읽기 전환 | **완료·배포됨** (api `ba22ff7`) |
| 70-01b 잔여 읽기 경로 5곳 | **미착수** — 70-06 하드 게이트 (계획 S2) |
| 70-02 브랜치 정리 | **미착수** (계획 S1, 팀 잔재 포함해 범위 확대) |
| 70-03 코드 수정·삭제 UI | **완료·배포됨** (app `e5bb72a`) |
| 70-03 후속 백엔드 하드닝 | **미착수** (계획 S4) |
| 70-04 리포트 PDF | **완료·배포됨** (api `eb31895`·`3e7c8f7` / app `7105226`·`fd951a4`) |
| 70-05 폼 리셋 | **완료·배포됨** (app `400e9cb`) |
| 70-06 트리거 폐기 | **미착수** — 승인 게이트 (계획 S3) |
| 70-07 UAT | **미착수** (계획 S5) |

곁다리 반영: Trello bklfCOX3(같은 날 2번째 지점 입고) — api `e5e7d76` / app `c3dd121` 배포 완료.

**미push 커밋 0.** 루트 `10b8505`, api `e5e7d76`, app `c3dd121` 전부 origin/main.
Jenkins api #599 / front #529 SUCCESS, 컨테이너 재생성 확인(03:19:22 / 03:20:41).

착수 시점 기준값은 `70-BASELINE.md` — 불변식 3종 로컬·운영 모두 0, 테스트 15 스위트/33건 pre-existing 실패.

---

## 이력: 팀(cmux-team) 실행 결과 — 재시도 전 반드시 읽을 것

**태스크 16건 중 성공 3 / 초안 3 / 중단 10.** 중단은 전부 인프라 사유였다.

- `resume_no_session_id` 5건 (001·003·007·012·013·015) — 재개 시 세션 ID 유실
- `disconnect_timeout` 3건 (010·011·016) — Conductor 연결 끊김
- autocompact 폭주 1건 (002)

같은 태스크(70-01b)가 **010→013→015→016 으로 4번 배정돼 4번 다 산출물 0**. 코드가 아니라
Conductor 수명 문제라 재시도해도 같은 자리에서 죽는다.

초기 대응(2026-08-03): 요청 크기가 첫 호출부터 520~550KB(≈130k 토큰)였고, 원인을 전역
`~/.claude/settings.json` 의 `enabledPlugins` 34개로 지목해 **15개 제거**
(figma/postman/planetscale/supabase/wix/sumup/mintlify/sourcegraph/serena/context7/
chrome-devtools-mcp/data/agent-sdk-dev/ralph-loop/pyright-lsp).
백업 `~/.claude/settings.json.bak-20260803-072738`. 이 조치 **이후에도** 010·016 이 죽었다.

→ 결론: 남은 작업량이 오케스트레이션 오버헤드보다 작다. 단일 프로세스로 전환.

`.team/` 은 **삭제하지 않는다** — 위 실패 기록이 재발 방지 근거다. draft 3건(004 70-05 / 006 70-06 /
009 70-03-fk)의 내용은 새 계획의 S3·S4 로 이관됐다(004 는 이미 완료된 70-05 라 폐기).

## 남은 정리 대상 (계획 S1)

- cmux-team daemon PID `3091` 실행 중
- 죽은 worktree 7개 (`.worktrees/task-*`) + 소유 불명 `/tmp/wt_root` (locked, 손대지 말 것)
- 태스크 브랜치 15개 (root 8 / api 5 / app 2) + 3 저장소 `fix/trello-6a6e43fb` (머지 완료)
- 70-02 원안 브랜치 10개
