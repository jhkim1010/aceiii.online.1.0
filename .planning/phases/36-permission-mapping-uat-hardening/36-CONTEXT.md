# Phase 36: 권한매핑보강+UAT감업 — Implementation Context

**Generated:** 2026-05-23 (from SPEC.md + spec-phase Round 1/2 + 추가 결정)
**Source:** `.planning/phases/36-permission-mapping-uat-hardening/36-SPEC.md`
**Downstream:** `gsd-planner` → 36-NN-PLAN.md

## Locked Implementation Decisions

### D-01: role_function_actions 보강 SQL 구조

**Decision:** PG10 호환 INSERT ... SELECT ... CROSS JOIN with `ON CONFLICT (role_function_id, action) DO NOTHING`.

```sql
-- 모든 store 의 모든 role_functions (function_id=149) × 4 actions
INSERT INTO role_function_actions (role_function_id, action, created_at, updated_at)
SELECT rf.id, act.action, NOW(), NOW()
FROM role_functions rf
CROSS JOIN (VALUES ('create'), ('read'), ('update'), ('delete')) AS act(action)
WHERE rf.function_id = 149
ON CONFLICT (role_function_id, action) DO NOTHING;
```

**Reasoning:**
- PG10 + 15 + 18 호환 (`ON CONFLICT` PG 9.5+, `VALUES` row constructor PG 8+, `CROSS JOIN` 표준)
- `role_function_actions` 의 `role_function_actions_rf_action_unique` UNIQUE 제약 활용
- Idempotent: 재실행 시 추가 INSERT 0건
- 12 기존 role_functions × 4 actions = 최대 48 행 INSERT (4 기존 행 제외 시 44 신규)

**파일 위치:** `api-ventago/migrations/phase36-stock-movement-actions-backfill.sql`

### D-02: RUNBOOK 문서 구조

**Decision:** 5-section markdown — sequential numbered execution. 각 단계마다 명령 라인 + 예상 결과 + 실패 시 대응.

**File:** `.planning/phases/35-activity-ledger/35-RUNBOOK-PROD.md`

**Sections:**
0. **사전 점검** — pg_dump 백업, 운영 서비스 상태, 사용자 0명 시간대
1. **마이그레이션 SQL** — 순서: phase35-activity-ledger.sql → phase35-stock-movement-permission.sql → phase36-stock-movement-actions-backfill.sql
2. **Backfill 실행** — dry-run → 검증 → COMMIT, backfill_failures 확인
3. **Hotfix 코드 배포** — Docker 재배포 순서 (api-ventago de8d0ae+f3ade81, ventago-app d215bbb), 재시작 명령
4. **회귀 검증** — /ventas movido/fallado 노출, Stock Cockpit MOV+/MOV−/FAL + OFFSET=0, cURL POST /stocks/movement 200
5. **롤백 절차** — 각 단계 ROLLBACK SQL + Docker 이전 태그

**Reasoning:** 운영 적용 시 SSH alias `jhkim-server` 환경에서 step-by-step 실행. 각 단계 독립 가능해야 부분 롤백 가능.

### D-03: U14 검증 절차

**Decision:** 사용자 자체 수행 — 스크립트화 안 함. `.planning/phases/36-permission-mapping-uat-hardening/u14-evidence.png` 1장 캡처가 acceptance.

**절차:**
1. 사용자 터미널 A: `psql -h localhost -p 5432 -U $USER -d ventago` 인터랙티브 세션 → `BEGIN; DELETE FROM sale_items WHERE sale_id=100;` 입력 후 세션 유지.
2. 사용자 브라우저: `/ventas` 새로고침 → Σ TOTAL 행 ⚠ 아이콘 + tooltip 캡처 (Cmd+Shift+4).
3. 터미널 A: `ROLLBACK;` 입력으로 복원 + 세션 종료.

**Reasoning:** Phase 35 UAT 시 시도했으나 heredoc 자동 ROLLBACK 으로 실패. 인터랙티브 세션 사용이 필수. 스크린샷이 가장 빠른 evidence.

### D-04: 35-UAT.md 결과 갱신 방식

**Decision:** Phase 36 의 마지막 plan 에서 `35-UAT.md` 의 U9/U9b/U10/U14 결과 4건을 `[x] PASS (post-Phase-36-fix)` 로 업데이트. 기존 FAIL 기록은 보존 (history 추적).

### D-05: U18 후속 처리

**Decision:** `/gsd-plant-seed` 호출로 미래 트리거 등록 — 실제 phase 추가는 안 함. trigger: "Phase 35 운영 적용 + 사용자 운영 1개월 후 hover tooltip 요청 발생 시".

### D-06: Phase 35 status 전환 절차

**Decision:** Phase 36 의 모든 acceptance 통과 후 STATE.md 의 Phase 35 status를 `verifying` → `ready-for-prod-deploy`. 운영 실제 적용 (RUNBOOK 실행) 후에야 `complete`.

## Constraints Confirmed

- **PG10 호환**: 모든 SQL 은 PG10/15/18 동시 호환. `GENERATED AS IDENTITY` 미사용, `STRING_AGG` / `regexp_match` / `ON CONFLICT` 만 사용.
- **운영 다운타임 zero**: 모든 마이그레이션 INSERT 만 (DDL CREATE/ALTER 는 Phase 35 시점 완료). LOCK 최소.
- **Idempotent**: SQL 재실행 시 데이터 변경 없음.
- **외부 의존**: Phase 33 의 `roles` + `functions` (id=149) 모든 store 에 존재 전제. 부재 시 ERROR (Phase 33 v2 적용 후 확인됨).

## Deferred Ideas (Phase 36 boundary 외)

- **REG-1 sale branch 필터 회귀** → **Phase 36.1 진행 중** (api-ventago f3ade81 commit, hotfix 적용 완료, 사용자 재검증 대기)
- **REG-2 movido/fallado dailyNumber 비-0** → **Phase 36.1 진행 중** (동일 commit, 방어적 fix + DB UPDATE 복원 5 rows)
- **U18 MOV+ tooltip 실제 구현** → plant-seed (D-05 참조)
- **role_function_actions 의 admin UI 자동 생성 UX** → Phase 33 v2 영역, 별도 plant-seed 후보

## Risks Identified

1. **role_function_actions UNIQUE constraint 충돌**: 이미 존재하는 4행 (Admin Store / store_id=1 / CRUD) 과 충돌 — `ON CONFLICT DO NOTHING` 으로 안전.
2. **role_functions 데이터 부족**: 일부 매장 (예: 신규 매장) 에 stock.movement role_functions 행이 없을 수 있음. 마이그레이션 SQL 이 신규 행 INSERT 안 함 (기존 매핑만 actions 보강). → Phase 33 v2 의 storeTemplate.createDefaultRoleFunctions idempotent 가드 가 보장.
3. **RUNBOOK 사용자 검토 지연**: 사용자가 RUNBOOK 1회 검토 + 승인이 acceptance. 시간 차에 따라 운영 적용 지연 가능.
4. **U14 스크린샷 캡처 실패 가능**: 사용자 OS/브라우저 환경에 따라 캡처 안 될 수 있음. Plan task 에 명확한 절차 + 대체 텍스트 evidence 옵션 필요.

---

*Phase: 36-permission-mapping-uat-hardening*
*Context generated: 2026-05-23 (streamlined discuss-phase)*
*Next step: gsd-planner reads SPEC.md + CONTEXT.md → 36-NN-PLAN.md*
