# Phase 36: 권한매핑보강+UAT감업 — Specification

**Created:** 2026-05-23
**Ambiguity score:** 0.16 (gate: ≤ 0.20)
**Requirements:** 5 locked

## Goal

Phase 35 manual UAT (2026-05-23) 에서 발견된 운영 적용 차단 사항 3건을 해결하여 Phase 35 status 를 `verifying` → `ready-for-prod-deploy` 로 전환한다: (1) `stock.movement` 권한의 `role_function_actions` 매핑 보강 SQL + admin UI 권한 매트릭스 검증 (2) 운영 PG10 적용 절차 RUNBOOK (`35-RUNBOOK-PROD.md`) 작성 (3) Phase 35 U14 movBalance 알람을 interactive psql + browser 다웰로고 방식으로 재검증.

## Background

Phase 35 (Activity Ledger) 의 manual UAT 세션 (commit `75a2ce3`, 2026-05-23) 결과:
- **U9/U9b/U10 FAIL** — Plan 02 마이그레이션 SQL 이 `role_functions` 만 INSERT 하고 `role_function_actions` 매핑은 누락. 결과: admin UI 권한 매트릭스 (`/configuracion/permisos` 탭 1) 에서 모든 5종 role (store_owner/store_admin/branch_manager/cashier/inventory_clerk) 의 `stock.movement` 셀이 "—" (권한 없음). PermissionGuard (`function-permission.guard.ts:64`) 가 `RoleFunctionAction.findOne` 으로 검사하므로 store_id=1 Admin Store role 외 모든 사용자가 403 반환. dev DB 확인: `role_function_actions WHERE function_id=149` = 4행 (1 role × CRUD, store_id=1 only).
- **U14 SKIPPED** — destructive psql heredoc 으로 BEGIN; DELETE; 실행 시 EOF 자동 ROLLBACK 으로 트랜잭션 즉시 닫혀 UI 에서 ⚠ 알람 노출 시점 캡처 실패.
- **운영 PG10 RUNBOOK 부재** — `35-SPEC.md` D-09 가 "별도 PR + 사용자 검토 후 운영 실행" 으로 deferred. 마이그레이션 순서, backfill dry-run/실행, hotfix 코드 배포, 롤백 절차가 미문서화.

본 phase 의 hotfix 5건 (api-ventago `de8d0ae` + ventago-app `0151df5`) 은 이미 dev 환경에 적용/검증/push 완료 — 본 phase scope 외 (Phase 35 hotfix 의 일부로 처리됨).

추가 발견 회귀 2건 (REG-1 정상 sale branch 필터 누락, REG-2 movido/fallado dailyNumber 비-0 부여) 은 `.planning/phases/35-activity-ledger/35-UAT.md` 부록 B 에 기록되어 있으며 **본 phase 의 boundary 외** — 별도 Phase 36.1 hotfix phase 로 후속 처리 결정 (2026-05-23).

## Requirements

1. **role_function_actions 보강 마이그레이션 SQL 작성 및 dev 검증**
   - Current: `role_function_actions WHERE function_id=149` = 4행 (1 role_function × CRUD, store_id=1 only). 모든 store 의 store_owner/store_admin/gerente role 이 stock.movement 권한 사용 불가.
   - Target: 마이그레이션 SQL (`api-ventago/migrations/phase36-stock-movement-actions-backfill.sql`) 이 모든 store × {admin, store_owner, store_admin, gerente, superadmin} × `stock.movement` × {create, read, update, delete} 조합으로 `role_function_actions` 행을 idempotent INSERT (ON CONFLICT DO NOTHING).
   - Acceptance:
     - SQL 실행 후 `SELECT COUNT(*) FROM role_function_actions rfa JOIN role_functions rf ON rf.id=rfa.role_function_id WHERE rf.function_id=149` ≥ 48 (12 기존 role_functions × 4 actions).
     - admin UI `/configuracion/permisos` 탭 1 매트릭스에서 "stock.movement" 행의 모든 5종 role (store_owner/store_admin/branch_manager/cashier/inventory_clerk — UI 그룹화 기준) 셀이 ✓ (허용) 표시 또는 store_id-scoped 일관성 유지.
     - SQL 재실행 시 행 수 동일 (idempotent ON CONFLICT 검증).

2. **운영 PG10 적용 RUNBOOK 문서 작성**
   - Current: `.planning/phases/35-activity-ledger/` 에 운영 적용 절차 문서 없음. SPEC D-09 가 "별도 PR" 로 deferred.
   - Target: `.planning/phases/35-activity-ledger/35-RUNBOOK-PROD.md` 작성. 다음 sections 필수 포함:
     - **0. 사전 점검**: 운영 DB 백업 (pg_dump), 운영 서비스 상태, 사용자 0명 시간대 확인.
     - **1. 마이그레이션 SQL 적용 순서**: `phase35-activity-ledger.sql` → `phase35-stock-movement-permission.sql` → (Phase 36) `phase36-stock-movement-actions-backfill.sql`.
     - **2. Backfill 실행**: dry-run 명령 + 결과 검증 SQL + 실제 commit 명령 + 롤백 절차 + backfill_failures 확인.
     - **3. Hotfix 코드 배포**: api-ventago (de8d0ae) + ventago-app (0151df5) Docker 재배포 + restart 순서.
     - **4. 회귀 검증**: `/ventas` movido/fallado 노출, Stock Cockpit MOV+/MOV−/FAL + OFFSET=0, cURL POST /stocks/movement 200.
     - **5. 롤백 절차**: 각 단계별 ROLLBACK SQL + Docker 이전 태그 복구.
   - Acceptance:
     - 파일 존재 + 위 5 sections 모두 작성 + 각 명령 라인이 운영 환경 SSH alias (`jhkim-server`) 와 PG10 syntax 호환 (예: `STRING_AGG` 만 사용, `GENERATED AS IDENTITY` 미사용).
     - 사용자 (junghokim10@gmail.com) 가 문서 1회 검토 + 승인 메시지 회신.

3. **U14 movBalance 알람 검증 재시도 — interactive psql + browser**
   - Current: Phase 35 UAT U14 SKIPPED (psql heredoc 자동 ROLLBACK 으로 UI 캡처 실패). movBalance 알람 동작 미검증.
   - Target: Phase 36 의 plan task 로 다음 절차 실행 + 결과 캡처:
     1. dev 환경 인터랙티브 psql 세션 (별도 터미널) 에서 `BEGIN; DELETE FROM sale_items WHERE sale_id=100;` 실행 후 세션 유지.
     2. 별도 브라우저 창에서 `/ventas` 새로고침 → Σ TOTAL 행의 MOV+/MOV− 셀에 ⚠ 아이콘 + tooltip 노출 캡처 (스크린샷).
     3. psql 세션에서 `ROLLBACK;` 으로 데이터 복원.
   - Acceptance:
     - 스크린샷 1장이 `.planning/phases/36-permission-mapping-uat-hardening/u14-evidence.png` 에 저장됨 + Σ TOTAL 행에 ⚠ 표시 visible.
     - tooltip 텍스트 "동일 store 내 이동인데 IN/OUT 합이 다릅니다" (또는 동등 SPEC D-05 명세) 노출 확인.
     - 복원 후 `SELECT COUNT(*) FROM sale_items WHERE sale_id=100` 가 원래 수치로 복귀.

4. **Phase 35 UAT 결과 갱신 + Phase 35 status 전환**
   - Current: `35-UAT.md` frontmatter status = `verified_with_gaps`. ROADMAP Phase 35 status 미명시 (verifying 유지).
   - Target: Phase 36 의 R1+R2+R3 모두 완료 후 `35-UAT.md` U9/U9b/U10 결과를 FAIL → PASS (post-Phase-36-fix) 로 갱신, U14 결과를 SKIPPED → PASS 로 갱신. `.planning/STATE.md` 의 Phase 35 status 를 `verifying` → `ready-for-prod` 또는 운영 적용 후 `complete` 로 전환.
   - Acceptance:
     - `grep -c "\[x\] PASS" .planning/phases/35-activity-ledger/35-UAT.md` 가 이전 값 + 4 (U9, U9b, U10, U14) 증가.
     - STATE.md Phase 35 status 명시적으로 `ready-for-prod` 또는 `complete` 로 변경됨.

5. **Phase 35 deferred 항목 U18 후속 결정 + plant-seed**
   - Current: U18 (Stock Cockpit MOV+ 셀 hover tooltip 최근 5건) 이 DEFERRED 상태로 남음. 후속 phase 결정 미정.
   - Target: Phase 36 plan task 에서 U18 의 후속 처리 결정 (예: Phase 37 후보로 plant-seed, 또는 Phase 35-C 의 일부로 backlog 등록).
   - Acceptance:
     - `.planning/phases/36-permission-mapping-uat-hardening/u18-followup-decision.md` (또는 동등 위치) 에 결정 문서 1건 작성: trigger condition + 예상 phase 번호 + dependency.
     - 또는 `/gsd-plant-seed` 호출 흔적이 commit log 에 존재.

## Boundaries

**In scope:**
- `phase36-stock-movement-actions-backfill.sql` 마이그레이션 작성 + dev 검증 + idempotent guard
- `35-RUNBOOK-PROD.md` 작성 (5 sections)
- U14 interactive psql + browser 재검증 + 스크린샷 증거
- 35-UAT.md 의 U9/U9b/U10/U14 결과 갱신
- STATE.md Phase 35 status 전환
- U18 후속 결정 (plant-seed 또는 backlog)

**Out of scope:**
- 운영 PG10 실제 적용 — RUNBOOK 작성까지만. 실제 SSH 실행은 사용자 승인 + 별도 세션.
- REG-1 (정상 sale branch 필터 누락) hotfix — Phase 36.1 후속 phase (2026-05-23 결정).
- REG-2 (movido/fallado dailyNumber 비-0) hotfix — Phase 36.1 후속 phase.
- U18 MOV+ tooltip 실제 구현 — Phase 37 또는 backlog plant-seed 만, 본 phase 에서 코드 작업 안 함.
- frontend admin UI 권한 매트릭스 UX 개선 — Phase 33 v2 의 영역, 본 phase 는 데이터 layer (SQL) 만 처리.

## Constraints

- **PG10 호환성**: 마이그레이션 SQL 은 운영 PG10 + 로컬 PG15/18 모두에서 동작해야 함. `GENERATED AS IDENTITY` 미사용, `STRING_AGG` / `regexp_match` 등 PG10 안전 functions 만 사용. `ON CONFLICT DO NOTHING` 사용 (PG 9.5+, 운영 호환).
- **운영 다운타임 zero**: 운영 사용자 0명 가정 (Phase 33 v2 와 동일 패턴). 마이그레이션은 LOCK 최소화 (CREATE INDEX CONCURRENTLY 미사용 — INSERT 만 수행).
- **Idempotent**: SQL 재실행 시 행 추가 없어야 함. `ON CONFLICT (role_function_id, action) DO NOTHING` 활용 (스키마의 UNIQUE 제약 활용).
- **Reference 의존**: Phase 33 의 `roles` 테이블 + `functions` 테이블 (`function_id=149`, slug='stock.movement') 가 모든 store 에 존재한다고 가정.
- **U14 재검증 환경**: dev (PG18 localhost) 만 사용. 운영 데이터로 destructive test 절대 금지.

## Acceptance Criteria

- [ ] `phase36-stock-movement-actions-backfill.sql` 파일이 `api-ventago/migrations/` 에 존재하며 ESLint/lint 통과
- [ ] dev DB 에서 SQL 실행 후 `role_function_actions WHERE function_id=149` ≥ 48 행 (이전 4 → 48+)
- [ ] SQL 재실행 시 행 수 변화 없음 (idempotent 확인)
- [ ] admin UI `/configuracion/permisos` 탭 1 매트릭스에서 stock.movement 행이 모든 5종 role 에 권한 표시 (✓ 또는 store-scoped 일관성)
- [ ] `35-RUNBOOK-PROD.md` 파일 존재 + 5 sections (사전 점검 / 마이그레이션 / Backfill / Hotfix 배포 / 회귀 검증 / 롤백) 모두 작성
- [ ] 사용자 (junghokim10@gmail.com) 가 RUNBOOK 1회 검토 + 승인 메시지 회신
- [ ] U14 스크린샷 (`u14-evidence.png`) 저장 + Σ TOTAL 행 ⚠ 아이콘 visible + tooltip 텍스트 확인
- [ ] `35-UAT.md` 의 U9/U9b/U10/U14 결과 4건이 PASS (post-Phase-36-fix) 로 갱신
- [ ] STATE.md Phase 35 status 가 `ready-for-prod` 또는 `complete` 로 전환
- [ ] U18 후속 결정 문서 또는 plant-seed commit 흔적 존재

## Ambiguity Report

| Dimension          | Score | Min  | Status | Notes                                       |
|--------------------|-------|------|--------|---------------------------------------------|
| Goal Clarity       | 0.90  | 0.75 | ✓      | 5 requirements 명시, deliverables 구체적   |
| Boundary Clarity   | 0.88  | 0.70 | ✓      | REG-1/REG-2 → Phase 36.1 분리 명시         |
| Constraint Clarity | 0.75  | 0.65 | ✓      | PG10 호환 + idempotent + 0명 가정 명시     |
| Acceptance Criteria| 0.80  | 0.70 | ✓      | 10 pass/fail criteria, 모두 falsifiable    |
| **Ambiguity**      | 0.16  | ≤0.20| ✓      | Gate passed (Round 2 종료 시점)             |

## Interview Log

| Round | Perspective    | Question summary                                       | Decision locked                                                                          |
|-------|----------------|--------------------------------------------------------|------------------------------------------------------------------------------------------|
| 1     | Researcher+Simplifier | Phase 36 의 "완료" 정의 + deferred 항목 처리 | SQL+RUNBOOK 작성까지 (운영 적용 외) / U14 만 포함, U18 후속 phase                          |
| 2     | Failure Analyst | SQL acceptance 기준 + U14 검증 방식                  | admin UI 매트릭스 + DB COUNT 양쪽 검증 / interactive psql + browser 다웰로고 + 스크린샷    |
| 2.5   | User decision   | spec 진행 중 발견된 REG-1/REG-2 의 처리 방식         | (C) Phase 36 본 boundary 유지, REG-1/REG-2 는 Phase 36.1 별도 hotfix phase                |

---

*Phase: 36-permission-mapping-uat-hardening*
*Spec created: 2026-05-23*
*Next step: /gsd-discuss-phase 36 — implementation decisions (SQL 구체 작성 방법, RUNBOOK 템플릿 선택, U14 검증 스크립트화 등)*
