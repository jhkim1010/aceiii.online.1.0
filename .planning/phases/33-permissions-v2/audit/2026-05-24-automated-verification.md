---
date: 2026-05-24
phase: 33 (Permissions v2)
status: verifying → 🔴 **블로킹 결함 2건 + 잠재 결함 3건 발견**
performed_by: automated (api + DB + Playwright-ready)
test_env: localhost dev (api:5002 / app:3050 / PG18 ventago)
admin_account: admin@cool.test (store_id=1)
artifacts: /tmp/phase33-test.sh, /tmp/phase33-me{1,2,3}.json
---

# Phase 33 자동 권한 점검 — 2026-05-24

## 요약

Scenario A(role seed) + B(toggle 반영) + F(cache TTL) 자동 점검 수행. **즉시 반영(B)은 작동**하지만 **이중 자동복구 로직(auto-repair)이 사용자의 토글 의도와 DB 상태를 분리**시키고, **5분 TTL 캐시(F)가 미작동**.

## 환경

| 항목 | 값 |
|---|---|
| Admin | admin@cool.test (id=2, store_id=1, role=Admin Store id=5) |
| Stores | id=1 (Cool Store), id=6 (test1) |
| Branches in store 1 | id=1 (Cool Store), id=12 (HELGUERA) |
| Test user | test_perm_userb@local.test (id=17, role=Vendedor Store id=6) — 정리 완료 |

## Scenario A — Role 시드 무결성 (PARTIAL PASS)

| Check | Result |
|---|---|
| ✅ Store 1 에 10 표준 role 시드 (slug: admin / vendedor / gerente / store_owner / accountant / inventory_clerk / store_admin / viewer / cashier / branch_manager) | OK |
| ✅ Admin Store(5) → 149 functions × 4 CRUD = 596 actions | OK |
| ✅ Solo Lectura(36): 1 action/func (read-only 의도 일치) | OK |
| ✅ Cajero(37): 2 actions/func, Contador(30): 3 actions/func | OK |
| 🔴 **Vendedor Store(6) / Gerente Store(7) role_functions = 0건** | 시드 누락 — 유저 배정 시 사이드바 빈 화면 |
| 🔴 **Legacy 4 roles (vendedor/admin/superadmin/gerente, store_id IS NULL)** | Phase 33 spec "기존 deprecate" 미실행 — role_functions 0건 |
| ⚠️ **permission_slug = 32/149 (78% null)** | Phase 33 신규 `module.action` slug 가 일부 함수에만 적용. PermissionGuard 가 permission_slug 기반이면 78% 함수 unguarded |
| ⚠️ Solo Lectura/Cajero/Contador/Encargado/Gerente de Sucursal: 148 funcs (1 누락) | 누락 함수 미식별 |

## Scenario B+F — Toggle 반영 + Cache (FAIL with caveats)

### 시퀀스

1. test_perm_userb 생성 (Vendedor Store role) → /me 1차: `permissions = {}` (Vendedor Store 0개 role_function)
2. admin → `PUT /role-functions/bulk-actions/6` 로 4 functions × CRUD 토글
3. test user /me 2차 → 4 functions 모두 CRUD true ✅
4. admin → fn=7(crear-usuario) 만 `["read","update","delete"]` 로 재토글 ('create' 제거)
5. test user /me 3차 → `crear-usuario: {create:false, read:true, update:true, delete:true}` ✅

### Tight reproduction (최소 케이스)

```
[A] bulk-actions: fn=7 actions=['read']                    (오직 1 row 명시)
[B] DB 직후: role_functions count=1, fn=7 actions='read'   ✅ 의도대로
[C] /me 응답: crear-usuario={create:F, read:T, update:F, delete:F}  ✅ 정확히 반영
[D] DB /me 직후: role_functions count=11 ← 자동으로 10개 추가됨
                 actions for fn=7: 'read' (그대로 유지)
                 user_permission_cache rows = 0   🔴 캐시 미작동
```

### 결함

| ID | 결함 | 영향 |
|---|---|---|
| 🔴 **D1** | `/me` 호출이 `user-structure.service.ts::ensureRoleFunctions` 를 트리거하여 사용자의 role 에 **모든 function 의 RoleFunction row 를 자동 생성** (actions 없이) | 권한 매트릭스 UI 에 사용자가 의도하지 않은 RoleFunction 이 표시됨. "Vendedor 에 1 func 부여" 했는데 DB 에 149 row 누적. **운영 적용 시 매트릭스 화면 신뢰 불가** |
| 🔴 **D2** | `user_permission_cache` 0 rows — Phase 33 spec "5분 TTL 캐시" 미작동 | Phase 33 spec 목표 "function-permission.guard.ts(104ms slow query) 캐시 기반 교체" 미달성. `/me` 매 호출마다 권한 재계산 (PG pool 부담) |
| ✅ B1 | bulk-actions API 의 `actions` 토글은 **정확히** 반영됨 ([Bulk API] {fn:7, ['read']} → /me 응답에서 create/update/delete = false) | OK |
| ✅ F1 | 권한 변경 후 재로그인 없이 즉시 /me 응답에 반영 (캐시 미작동의 부수효과로 자동 즉시 반영) | OK (단 D2 이유) |

### 원인 코드 위치

- D1 트리거: [api-ventago/src/app/auth/services/user-structure.service.ts:113-160](../../../../api-ventago/src/app/auth/services/user-structure.service.ts#L113) — `ensureRoleFunctions` 가 `roleFunctions.length === 0` 일 때 모든 functions 를 `RoleFunction.create(...)` 로 채워넣음
- D1 유사 코드: [api-ventago/src/app/auth/services/user-registration.service.ts:139-160](../../../../api-ventago/src/app/auth/services/user-registration.service.ts#L139) — admin role 에도 동일 auto-fill 패턴
- D2 호출 누락: [api-ventago/src/app/role/role-function/role-function.service.ts:71-105](../../../../api-ventago/src/app/role/role-function/role-function.service.ts#L71) — `bulkUpdateRoleFunctionActions` 에 `cacheService.invalidateUser` 호출 없음
  - cf. [api-ventago/src/app/permissions/permissions.service.ts:256](../../../../api-ventago/src/app/permissions/permissions.service.ts#L256) — assignUserBranch 에는 invalidateUser 호출 있음

## Scenario C — Branch scope (NOT RUN)

dev 데이터에서 user_branches 테이블이 **거의 비어있음** (admin@cool.test 의 user_branches=0건). Phase 33 의 다지점 매핑(1 user × N branch × 1 role) 이 실 데이터에 적용 안 됨. 의미 있는 점검 위해서는:

1. user_branches 에 admin@cool.test 의 entry 백필
2. 운영 PG10 적용 후 실 데이터로 점검

→ 현재 dev 환경 기준 점검 의미 적음.

## 권장 후속 작업 (우선순위 순)

| # | 작업 | 영향 |
|---|---|---|
| 🔴 P0 | `user-structure.service.ensureRoleFunctions` 자동 채워넣기 비활성화 (또는 default actions=[] 로) | 매트릭스 UI 신뢰성 회복 |
| 🔴 P0 | `bulkUpdateRoleFunctionActions` 끝에 `cacheService.invalidateUser` 호출 추가 | Phase 33 cache TTL 활성화 (단, D1 fix 후) |
| 🔴 P0 | 운영 PG10 적용 RUNBOOK (이미 Phase 36 plan 에 포함) 의 사전 점검에 D1/D2 fix 포함 | 운영 적용 시 회귀 방지 |
| 🟡 P1 | Vendedor Store / Gerente Store role_functions 시드 (Phase 33 마이그레이션 보강) | role 배정 시 빈 사이드바 방지 |
| 🟡 P1 | Legacy 4 roles (store_id IS NULL) deprecate or seed | Phase 33 마무리 |
| 🟢 P2 | 78% 함수의 `permission_slug` 백필 | PermissionGuard 일관성 |
| 🟢 P2 | user_branches 백필 (admin 포함) → Scenario C 본격 점검 가능 | 다지점 RBAC 검증 |

## 정리

테스트 유저 + Vendedor Store 의 role_functions/actions/user_roles/user_branches 모두 삭제. dev DB 영향 없음.

## 재현 절차

```bash
# 사전: ./dev.sh 가동 (5002 api + 3050 app)
/tmp/phase33-test.sh   # 자동 시나리오 B+F
# 산출물:
#   /tmp/phase33-me1.json (baseline)
#   /tmp/phase33-me2.json (after bulk-actions)
#   /tmp/phase33-me3.json (after toggle off)
```

## 결론

> **Phase 33 의 verifying status 가 정상화되지 않은 이유가 명확함.** retroactive 등록 시점에 운영 PG10 미적용 + 30 파일 uncommitted 라는 메타 정보만 있었으나, 실제 dev 동작 자체에 위 2건의 P0 결함이 존재. 운영 적용 전 hotfix 필수.
