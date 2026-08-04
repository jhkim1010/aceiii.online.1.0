# 70-02 SUMMARY — 브랜치 정리 + cmux-team 잔재 청소 (S1)

실행: 2026-08-04. 계획: `70-PLAN-SINGLE-PROCESS.md` S1 (원안 `70-02-PLAN.md` 을 팀 잔재 포함해 확대).
코드 변경 **0**. 3 저장소 모두 `main` 단일 브랜치로 수렴.

---

## S1-a. cmux-team 중지

- draft 태스크 3건을 journal 남기고 close (`--deliverable-kind none`)
  - `004` 70-05 → 이미 완료·배포됨(app `400e9cb`). 태스크 폐기
  - `006` 70-06 → 새 계획 **S3** 으로 이관 (승인 게이트 유지)
  - `009` 70-03-fk → 새 계획 **S4** 로 이관
- `cmux-team send SHUTDOWN` → daemon PID `3091` 소멸 확인
- `.team/` 디렉터리는 **보존** — 태스크 16건의 실패 기록이 재발 방지 근거

## S1-b. worktree 정리

전 worktree 에서 **미머지 커밋 0** 을 먼저 확인했다 (실패 기록과 일치 — 건질 산출물 없음).
dirty 파일은 `package-lock.json` / `.gsd-snapshot.json` / 서브모듈 포인터뿐이었다.

| worktree | dirty | 미머지 커밋 |
|---|---|---|
| task-001-1785751889 | package-lock | 0 |
| task-003-1785738563 | — | 0 |
| task-003-1785755414 | gsd-snapshot, package-lock | 0 |
| task-005-1785738533 | — | 0 |
| task-012-1785777398 | 서브모듈 2, package-lock | 0 |
| task-013-1785777424 | 서브모듈 1, package-lock | 0 |
| task-015-1785806410 | 서브모듈 1, package-lock | 0 |

7개 전부 `git worktree remove --force` → `prune`. 서브모듈(api/app) 쪽에도 stale 등록이 남아 있어
`git -C <submodule> worktree prune` 을 별도 실행해야 브랜치 삭제가 풀렸다.

**`/tmp/wt_root` (locked, detached `c9ce3e7`) 는 소유 불명이라 계획대로 손대지 않았다.**

## S1-c. 태스크 브랜치 삭제 (15개, 전부 `-d` 통과 = 머지 완료)

- root 8: `task-001-1785751889/task` `task-003-1785738563/task` `task-003-1785755414/task`
  `task-005-1785738533/task` `task-007-1785755216/task` `task-012-1785777398/task`
  `task-013-1785777424/task` `task-015-1785806410/task`
- api-ventago 5: `task-003-70-04` `task-010-1785773023/api` `task-012-70-04`
  `task-013-1785777424/api` `task-015-1785806410/api`
- ventago-app 2: `task-003-70-04` `task-012-70-04`
- 추가: api/app `fix/trello-6a6e43fb` (main ff-merge 완료분) 삭제

## S1-d. 70-02 원안 10개 — 삭제 직전 재검증 결과

`git fetch --all --prune` 후 `git log --oneline origin/main..<branch>` 로 전수 재확인.

| 저장소 | 브랜치 | 미머지 | 처분 |
|---|---|---|---|
| root | `split/mobile-sales-app` | **13** (공통 조상 없음) | 태그 백업 후 `-D` |
| root | `origin/feature/phase58-offline-sync` | 0 | 원격 삭제 |
| api | `backup/phase57-df122c7` | **1** | ⚠️ 아래 예외 처리 |
| api | `security/global-jwt-guard` (로컬+origin) | 0 | 양쪽 삭제 |
| api | `origin/feat/revendedor-zona` | 0 | 원격 삭제 |
| api | `origin/feat/sku-serial` | 0 | 태그 백업 후 원격 삭제 |
| api | `origin/feature/phase58-offline-sync` | 0 | 원격 삭제 |
| app | `_probe_branch` | 0 | 로컬 삭제 |
| app | `origin/feat/sku-serial` | 0 | 태그 백업 후 원격 삭제 |
| app | `origin/feature/phase58-offline-sync` | 0 | 원격 삭제 |

### 예외 1 — `split/mobile-sales-app` (예정된 예외)
`origin/main` 과 공통 조상 없음(독립 히스토리). T2 절차대로 서브모듈 히스토리 온전성 확인
(`mobile-sales-app` 57커밋, 최초 커밋 `a2f3775` 까지 존재) → 태그 push 성공 확인 후 `-D`.

### 예외 2 — `backup/phase57-df122c7` (계획에 없던 발견)
원안은 "main 과 diff 없음" 이라 했으나 **실제로는 미머지 커밋 1건**이 있었다:
`df122c7 feat(dashboard): Phase 57 Wave C — Admin Centro de Control 단일 집계 API` (4파일 +724).

T1 규칙대로 멈추고 확인한 결과 — `src/app/dashboard-admin/` 3파일이 **`origin/main` 에 내용 동일로 존재**
(`git diff origin/main:… branch:…` 결과 0). sha 만 다른 동등 반영(cherry-pick/rebase 흔적)이었다.
태그 백업 후 **사용자 승인을 받아** `-D` 로 삭제 (계획서의 "-D 금지" 제약에 대한 명시적 예외).

## 백업 태그 (전부 원격 push 확인)

| 저장소 | 태그 | 대상 sha |
|---|---|---|
| root | `archive/split-mobile-sales-app` | `62f1c7b` |
| api-ventago | `archive/backup-phase57-df122c7` | `df122c7` |
| api-ventago | `archive/feat-sku-serial` | `ed5dd04` |
| ventago-app | `archive/feat-sku-serial` | `c467a1b` |

> `feat/sku-serial` 태그는 원안에 없던 추가 안전장치다 — SKU serial 재설계가 미완 상태로 남아 있다는
> 기록이 있어 되살릴 여지를 남겼다.

## T4 — `fix/trello-*` 잔존

4개 저장소(root / api-ventago / ventago-app / mobile-sales-app) 전부 **없음**.

## 최종 상태

```
root         : main, origin/main
api-ventago  : main, origin/main
ventago-app  : main, origin/main
worktree     : 주 작업트리 1개 + /tmp/wt_root(locked, 미접촉)
```

미커밋 잔여(추적 파일, 의도적 제외): `.claude/hooks/.gsd-snapshot.json`, `.team/config.json` — 머신 로컬 런타임 값.

## 다음

**S2 — 70-01b 잔여 `products.stock` 읽기 경로 5곳 이관.** 70-06 의 하드 게이트다.
