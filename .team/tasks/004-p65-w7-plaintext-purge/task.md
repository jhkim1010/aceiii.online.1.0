---
id: 004
title: P65-W7 루트 저장소 평문 자격증명 제거 + 스캔 게이트(W7-4)
priority: high
created_at: 2026-08-05T06:00:00.000Z
---

## Task
근거: `.planning/phases/65-stock-ledger-truth-and-boundary-hardening/65-W7-ROTATION-SUBJECTS.md` §2·§3

repo: **루트 저장소**(api-ventago 아님). wave 1. 002/003 과 파일 겹침 없음 — 병렬 가능.

`be8c387` 이 W7-1/W7-2 를 끝냈지만 **api-ventago 만** 건드렸다. 루트 저장소에는 그대로 남아 있다.

### 실행되는 것 — 우선 (환경변수 참조로 교체)
- `.codex/config.toml:6` — MCP postgres 접속 문자열 통째. **포트 15432 의 정체를 먼저 확인**(로컬 5432/운영 5434 와 다름. SSH 터널 추정)
- `pre-deploy.sh:53,103`
- `scripts/measure-cockpit-pool.sh:55`

### 문서 — 값만 마스킹
`.gsd/spec-codigo-import-review.md:65` · `docs/superpowers/plans/2026-05-11-product-promotions.md`(2곳) ·
`docs/superpowers/plans/2026-06-11-mobile-access-terminal-binding.md`(3곳) ·
`docs/superpowers/specs/2026-05-29-shared-folders-google-drive-design.md:636` ·
`.planning/phases/` 6파일(14-01 / 25-17 / 26-01 / 26-02 / 29-02 / 29-VALIDATION / 33.1-03)

### 계정 B `postgres` 도 같이
`api-ventago/migrations/2026-06-25-legacy-imports.sql:8` · `docs/superpowers/plans/2026-07-09-factura-electronica-plan-1-backend-core.md:108` ·
`vw-agent/migrations/001_create_ventago_watcher.sql:18`

### W7-4 스캔 게이트
커밋 훅 또는 CI 에서 평문 자격증명 유입을 막는다. 패턴은 `scripts/codex-review.sh` 의 리댁션 정규식을 재사용하면 된다
(접속 문자열 / `password[:=]'...'` / `PGPASSWORD=` / `*_SECRET|KEY|TOKEN=`).

## 반드시 인지할 것

**파일을 지워도 git 이력의 값은 계속 유효하다.** 이 태스크는 *신규 유입 차단*이고,
기존 노출의 실제 무효화는 **005 회전**이다. 004 완료를 "자격증명 문제 해결"로 보고하지 마라.
