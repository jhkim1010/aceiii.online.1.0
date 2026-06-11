---
phase: 36
plan: 01
type: execute
status: complete
completed: 2026-06-11
requirements:
  - R1
commit: 8c7ba1d (api-ventago)
---

# Phase 36 Plan 01 — role_function_actions 보강 SQL Summary

## Goal

`stock.movement` 권한이 `role_functions` 만 INSERT 되고 `role_function_actions` 매핑이
누락되어 권한 매트릭스에 "권한 없음" 표시 + PermissionGuard 403 반환하던 Phase 35 결함 수정.
모든 `role_functions(function_id=149)` 행에 4 action(create/read/update/delete) 매핑 보강.

## Changes

### `api-ventago/migrations/phase36-stock-movement-actions-backfill.sql` (신규)

- function_id=149 (stock.movement) precheck DO-block (없으면 EXCEPTION → 안전 중단)
- `role_functions × VALUES(create/read/update/delete)` CROSS JOIN INSERT
- `ON CONFLICT (role_function_id, action) DO NOTHING` → 멱등
- 최종 행 수 검증 DO-block (total vs expected NOTICE/WARNING)
- PG10/PG15/PG18 호환 (ON CONFLICT / CROSS JOIN / VALUES row constructor 모두 PG10+)

## Verification (dev PG18)

- pre-state: 12 role_function_actions (function 149)
- 1차 실행: `INSERT 0 0` — `NOTICE: total=12 expected=12` (이미 완비)
- post-state: admin / gerente / vendedor (store 1) 모두 `{create,delete,read,update}` ✓
- 2차 실행 (멱등성): recount=12, 변화 없음 ✓

## Deviation from plan

- Plan 은 prod 기준 "12 role_functions → 48 actions" 가정. dev 에는 stock.movement
  role_functions 가 3개(admin/gerente/vendedor, store 1)뿐이라 pre/post 모두 12.
  SQL 로직은 환경 무관하게 정확(모든 role_function 에 4 action 보장) — 수치만 환경별 상이.
- Task 4 (admin UI 매트릭스 스크린샷): manual UI 단계라 SQL 레벨 데이터 검증으로 대체.
  데이터가 올바르므로 매트릭스 렌더는 정상 예상. 운영 적용 후 UI 확인 권장.

## 운영 적용

미적용 (deferred). 35-RUNBOOK-PROD (Plan 02) 순서대로 사용자 확인 후 적용.
prod function_id=149 가 stock.movement 가 아니면 precheck 가 EXCEPTION 으로 안전 중단.

## Files

- `api-ventago/migrations/phase36-stock-movement-actions-backfill.sql` (신규)
