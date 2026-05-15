# Day 4 결정 노트 — 기존 function-permission.guard 폐기 보류

작성일: 2026-05-14

## 결정

**기존 `@FunctionGuard` (스페인어 slug 기반) 은 폐기하지 않고 신규 `@Permission` (영어 dot notation) 과 병행 사용.**

## 배경

SPEC 원안: "Day 4 에서 `function-permission.guard.ts` 폐기 + `@FunctionGuard` → `@Permission` 일괄 치환"

검토 결과:
- 기존 `@FunctionGuard` 사용처: 약 30+ 컨트롤러 메서드 (clients, client-import, code-import, reports 등)
- 모두 스페인어 slug 사용 (`'manage-clients'`, `'reporte-stocks'`, `'manage-codigo-import'` 등)
- 매트릭스 (`Ventago_Permissions_Matrix.xlsx`) 의 영어 dot notation 과 직접 매핑 안 됨
- 일괄 치환 = 30+ 곳 코드 수정 + 매핑 결정 + 모든 케이스 회귀 테스트 → Day 4 범위 초과

## 새 전략

1. **두 가드 병행 운영**
   - 기존 `@FunctionGuard('manage-clients', 'update')` — 그대로 유지
   - 신규 컨트롤러 + 신규 기능은 `@Permission('clients.update', 'update')` 사용
   - NestJS Reflector 가 메타 키별로 다른 가드 호출 — 충돌 없음

2. **점진 마이그레이션 (별도 SPEC)**
   - functions.permission_slug 컬럼이 채워진 function 부터 신규 가드로 전환
   - 컨트롤러별로 1주 dry-run (신규 가드를 log-only 모드로 호출, deny 차이 분석)
   - 차이 0건 확인 후 기존 데코레이터 제거
   - 추정 기간: 2-3주, 별도 SPEC 으로 진행

3. **Day 4 범위 조정**
   - TASK-4.5 (기존 가드 폐기) 는 deferred → 향후 SPEC
   - 대신 **신규 가드 + 데코레이터 + 캐시 + Resolver** 가 정상 작동하는지 검증에 집중

## 후속 작업

- [ ] 신규 SPEC: "기존 @FunctionGuard → @Permission 점진 마이그레이션 (Phase 30 후보)"
- [ ] 마이그레이션 시작 전 functions.permission_slug 매핑 완성도 확인 (현재 일부만)
- [ ] log-only 모드 가드 (PermissionShadowGuard) 신설 — 두 결과 비교용
