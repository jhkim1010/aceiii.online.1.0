---
id: 005
title: P65-W7-3 DB 계정 비밀번호 회전 (승인 게이트 · 단독 배포창)
priority: high
created_at: 2026-08-05T06:00:00.000Z
---

## Task
근거: `.planning/phases/65-stock-ledger-truth-and-boundary-hardening/65-W7-ROTATION-SUBJECTS.md` §5

wave 2 — **002/003/004 와 병렬 금지.** 단독 배포 창에서 실행한다.

## 선행 조건 (전부 충족 전 착수 금지)

1. **서버 조회 7항목 완료** — 65-W7-ROTATION-SUBJECTS.md §2 의 "서버 확인 필요" 표.
   현재 **미완**: 이 세션에서 운영 SSH 가 막혀 있었다(publickey 거부).
   - pgbouncer `userlist.txt` ★ · 백업 크론 03:17 · Jenkins · `.pgpass` · `venpsql` · `pg_stat_activity` 실측 · vw-agent `PG_PORT`
2. **사용자 명시 승인** — 파괴적 작업. SQL 과 영향 범위를 보여주고 동의받는다
3. **롤백 지점 확보** — 현재 `userlist.txt` 백업, 현재 비밀번호 보관

## 순서 (65-W7-ROTATION-SUBJECTS.md §5 그대로)

1. 사전 실측 — `pg_stat_activity` 로 `coolsistema` 실제 접속 주체 전수. **목록에 없는 주체는 회전 후 조용히 죽는다**
2. 롤백 지점
3. `ALTER ROLE coolsistema PASSWORD '<신규>'` (PG18 **5434**)
4. pgbouncer `userlist.txt` 갱신 → reload ★ **여기를 빠뜨리면 앱 전체 정지**
5. 앱 `.env` `DATABASE_PASSWORD` → 컨테이너 재기동 → `/health`
6. 백업 크론 · Jenkins · `.pgpass` · `venpsql`
7. 검증 — 판매 1건 왕복 · **다음 날 03:17 백업 성공 확인** · `pg_stat_activity` 실패 접속 0
8. 구 비밀번호 폐기 + 004 잔여 정리 확인

## 주의

- 계정이 3개다: `coolsistema`(앱) / `postgres`(로컬 superuser) / `ventago_watcher`(vw-agent).
  65-PLAN 은 `coolsistema` 하나만 상정했다. 어디까지 회전할지 먼저 결정한다.
- 5 에서 실패하면 앱이 **부팅을 거부**한다(W7-2 `requireSecret` 효과). 조용한 반쪽 상태는 생기지 않는다 — 이건 안전장치다.
- **비밀번호 값을 대화·커밋·보고서에 남기지 마라.**

## 곁가지 (회전 전에 확인할 가치 있음)

`vw-agent/.env.example:21-25` 가 `PG_PORT=5433`(구 PG10, 컷오버 후 롤백 안전망) 을 기본값으로 둔다.
운영 `.env` 가 예시대로면 감시 에이전트가 **실사용 안 하는 클러스터를 감시**하고 있다 — 장애가 나도 조용하다.
확인: `docker exec vw-agent env | grep PG_PORT`
