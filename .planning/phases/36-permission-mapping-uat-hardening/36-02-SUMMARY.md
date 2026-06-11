---
phase: 36
plan: 02
type: execute
status: complete_pending_user_review
completed: 2026-06-11
requirements:
  - R2
---

# Phase 36 Plan 02 — 운영 PG10 RUNBOOK Summary

## Goal

Phase 35 운영 PG10 적용 절차 RUNBOOK 작성 (`35-RUNBOOK-PROD.md`) — 백업/마이그레이션 순서/
backfill/배포/회귀검증/롤백.

## Changes

### `.planning/phases/35-activity-ledger/35-RUNBOOK-PROD.md` (신규)

5 sections + sign-off 체크리스트:
- Section 0: 사전 점검 (백업, 헬스, 세션 0명, 사용자 승인)
- Section 1: 마이그레이션 순서 (phase35 base → stock.movement permission → phase36 actions backfill → 검증)
- Section 2: Backfill (dry-run → 승인 → commit → 검증 → REG-2 dailyNumber 보정)
- Section 3: Hotfix 코드 배포 (de8d0ae + f3ade81 + 0151df5 + d215bbb, Docker 재배포)
- Section 4: 회귀 검증 (ventaVista / Stock Cockpit / 권한 매트릭스 / cURL)
- Section 5: 롤백 (Docker 이전 태그 / 데이터 ROLLBACK / pg_dump 복원)

## 참조 commit 검증 (2026-06-11)

RUNBOOK 이 참조하는 4 commit 모두 git 존재 확인:
- api-ventago: de8d0ae (Phase 35 hotfix), f3ade81 (Phase 36.1 REG-1/REG-2)
- ventago-app: 0151df5 (tab title + admin fallback), d215bbb (Movidos/Fallados 체크박스)

> Phase 36.1 코드(f3ade81)는 ad-hoc commit 으로 존재 (GSD SUMMARY 미등록) — 운영 빌드 포함 전제.

## Verification

- 파일 존재 + 5 sections + jhkim-server SSH + PG10 syntax ✓
- 각 단계 estimated time + 실패 시 액션 명시 ✓

## 잔여 (plan Task 2)

**사용자 RUNBOOK 검토/승인 대기** — junghokim10@gmail.com 1회 review 후 "OK 진행" 또는 수정 요청.

## Files

- `.planning/phases/35-activity-ledger/35-RUNBOOK-PROD.md` (신규)
