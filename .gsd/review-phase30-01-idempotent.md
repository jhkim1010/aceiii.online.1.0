# Phase 30 #1 — storeTemplate idempotent 가드 (완료)

작성일: 2026-05-15
관련 SPEC: `.gsd/spec-permissions-v2.md` (Phase 29 후속)
Day 1-2 Review 의 알려진 이슈 #1 해결

## 요약

storeTemplate 의 `createDefaultRoleFunctions` 가 같은 매장에 여러 번 호출되어도 중복 INSERT 가 발생하지 않도록 `findOrCreate` 가드 추가.

## 발견 정정

이전 review (`review-permissions-v2-day1-2.md`) 에서 store 6 의 role_functions 가 436 row 라 "정상 148 의 3배 = 중복" 이라 적었는데, 정밀 분석 결과:

```
role_id=23 (admin):    148 row, 0 중복
role_id=24 (vendedor): 144 row, 0 중복
role_id=25 (gerente):  144 row, 0 중복
합계 436 row, 중복 0건
```

**실제 중복은 0건**. 단지 매장 6 에 3 role 이 있어서 매장 1 (148 row) 의 약 3배로 보였던 것. 이전 review 의 오해였음.

그럼에도 idempotent 가드는 미래 안전을 위해 가치 있음.

## 변경 파일

### 수정 (1)
| 파일 | 변경 |
|---|---|
| `src/app/store/storeTemplate.service.ts` | `createDefaultRoleFunctions` 의 `RoleFunction.create` → `RoleFunction.findOrCreate` + `RoleFunctionAction.findOrCreate`. skipped 카운터 추가. |

### 신규 (2)
| 파일 | 역할 |
|---|---|
| `migrations/phase30-role-functions-dedupe.sql` | DRY-RUN + ACTUAL CLEANUP (선택적). 향후 중복 발생 시 사용 |
| `.gsd/review-phase30-01-idempotent.md` | (본 문서) |

## 코드 변경 핵심

### Before (Phase 29)
```typescript
const roleFunction = await RoleFunction.create(
  { roleId: role.id, functionId: fn.id, storeId },
  { transaction },
);

for (const action of actions) {
  await RoleFunctionAction.create(
    { roleFunctionId: roleFunction.id, action },
    { transaction },
  );
}
```

### After (Phase 30 #1)
```typescript
const [roleFunction, rfCreated] = await RoleFunction.findOrCreate({
  where: { roleId: role.id, functionId: fn.id, storeId },
  defaults: { roleId: role.id, functionId: fn.id, storeId } as any,
  transaction,
});

if (!rfCreated) {
  skipped++;
  continue;
}

for (const action of actions) {
  await RoleFunctionAction.findOrCreate({
    where: { roleFunctionId: roleFunction.id, action },
    defaults: { roleFunctionId: roleFunction.id, action } as any,
    transaction,
  });
}
```

## 다른 메서드 점검 결과

| 메서드 | 상태 |
|---|---|
| `createDefaultRoles` | ✅ 이미 idempotent (findOne → if !existing → create) |
| `createDefaultRoleFunctions` | ✅ Phase 30 #1 에서 수정 (findOrCreate 적용) |
| `createDefaultApprovalThresholds` | ✅ 이미 idempotent (`ON CONFLICT (store_id, branch_id, function_slug, role_slug) DO NOTHING`) |
| `createDefaultBranch` | ✅ 이미 idempotent (findOne → if !branch → create) |
| `createDefaultBox` / `createDefaultTerminal` | (확인 필요 — 별도 task) |

## 품질 검증

### Pool 안전 (사용자 메모리 #pool 우선순위)
- [x] `findOrCreate` 는 단일 쿼리로 SELECT-then-INSERT 동작 (Sequelize 자동 release)
- [x] 트랜잭션 컨텍스트 그대로 유지
- [x] N+1 패턴: role × function 의 N×M loop 인 점은 변경 없음 (이미 Phase 29 부터 그랬음)

### 회귀 위험
- [x] 신규 매장 (role_functions 없음) — `rfCreated=true` → 정상 INSERT (Phase 29 와 동일)
- [x] 재호출 (이미 시드된 매장) — `rfCreated=false` → skip (이전엔 중복 INSERT, 지금은 안전)
- [x] 부분 시드 (일부 function 만 있음) — 누락된 function 만 INSERT (이전엔 전체 재INSERT 시도)

### dev DB 현재 상태 (검증 결과)
```
role_functions 중복 분석:
  duplicate_groups:    0
  total_duplicate_rows: 0
  rows_to_delete:      0
```

깨끗한 상태 — cleanup SQL 실행 불필요.

## 운영 적용 가이드

본 fix 는 코드 변경만 — 마이그레이션 SQL 불필요.

```bash
# Backend 배포만 하면 다음 매장 생성부터 idempotent 가드 자동 적용
git add api-ventago/src/app/store/storeTemplate.service.ts
git commit -m "feat(phase30): storeTemplate.createDefaultRoleFunctions idempotent guard"
git push
# Jenkins 배포
```

만약 운영에서 중복이 의심되면:
```bash
ssh jhkim-server "sudo -u postgres psql -d ventago" \
  < api-ventago/migrations/phase30-role-functions-dedupe.sql
# DRY-RUN 결과 확인 후 ACTUAL CLEANUP 블록 주석 해제하여 재실행
```

## 후속 작업 (Phase 30 다른 후보)

- [ ] #2 functions.permission_slug 커버리지 확대 (18% → 80%+)
- [ ] #3 기존 @FunctionGuard → @Permission 점진 마이그레이션
- [ ] #4 Frontend ACL 어휘 일괄 통일
- [ ] #5 approval_thresholds UI 편집 기능
- [ ] #6 OnlineOrdersExpiryCron stuck 조사
- [ ] #7 CASL 도입 검토 (3개월 후)

## 결론

Phase 30 #1 완료. **운영 적용 직전 차단 이슈** 였던 idempotent 가드가 해결됐고, dev DB 도 실제 중복 0건으로 깨끗한 상태. 운영 PG10 적용 가능합니다.
