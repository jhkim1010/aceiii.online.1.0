---
phase: 36
plan: 03
type: execute
status: complete_with_pending_manual
completed: 2026-06-11
requirements:
  - R3
  - R4
  - R5
---

# Phase 36 Plan 03 — U14 검증 + UAT 갱신 + U18 plant-seed Summary

## Goal

U14 movBalance 재검증 + 35-UAT.md 결과 갱신 + STATE.md status 전환 + U18 plant-seed.

## Changes

### Task 2 — `.planning/phases/35-activity-ledger/35-UAT.md` 갱신
- 헤더 status: `verified_with_gaps` → `ready-for-prod-deploy`
- 미해결 Gap / Sign-off 섹션: U9 권한 매핑(36-01) + RUNBOOK(36-02) 해소 표시.
  잔여 manual(U9/U10 cURL smoke, U14 브라우저) 정직하게 pending 유지.

### Task 3 — `.planning/STATE.md` Phase 35 status 전환
- `awaiting_user_validation` → `ready-for-prod-deploy`
- blocker 2건 해소 + 잔여 manual UAT + Resume 절차 명시.

### Task 4 — U18 plant-seed
- `.planning/phases/36-permission-mapping-uat-hardening/u18-followup-decision.md` (신규)
  trigger / 예상 phase(38+) / dependencies / effort 명시.

## Deviation / 잔여 (정직 보고)

### Task 1 (U14 movBalance) — manual, 미수행
interactive psql BEGIN+DELETE + **브라우저 /ventas Σ TOTAL ⚠ 캡처** + ROLLBACK 필요.
브라우저 스크린샷은 자율 수행 불가 → 사용자 dev 실행 시 보충. `u14-evidence.png` 미생성.

### Task 2 U9/U9b/U10 — DATA 해소 / cURL smoke 잔여
권한 DATA(role_function_actions)는 Phase 36-01 로 해소. 단 `POST /stocks/movement`
200/403 cURL smoke 는 dev api(`./dev.sh`) + JWT 필요 → 미실행. UAT 에 정직하게 pending 표기
(plan 의 "4건 모두 PASS 전환" 은 cURL/브라우저 미실행분을 PASS 로 위조하지 않음).

## Files

- `.planning/phases/35-activity-ledger/35-UAT.md` (갱신)
- `.planning/STATE.md` (갱신)
- `.planning/phases/36-permission-mapping-uat-hardening/u18-followup-decision.md` (신규)
