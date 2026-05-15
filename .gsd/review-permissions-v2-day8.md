# GSD 리뷰 리포트 — Phase 29 Sprint 2 Day 8 (ACL Generator + 어휘 통일 기반)

작성일: 2026-05-14
관련 SPEC: `.gsd/spec-permissions-v2.md`
이전 리뷰: Day 6-7

## 완료된 태스크

- [x] TASK-7.0 영향 범위 분석 — 일괄 치환은 위험 (72 + 82 = 100+ 위치, 30+ subject)
- [x] TASK-7.1 BE: `GET /api/permissions/permissions/keys` 엔드포인트
- [x] TASK-7.2 generator 스크립트 (TypeScript enum 자동 생성)
- [x] TASK-7.3 PermissionKey enum + helper (mapLegacySubject, unifiedSubject)
- [x] TASK-7.4 점진 마이그레이션 가이드 작성

## 변경 파일 요약

### 신규 (4)
| 파일 | 역할 | 라인 |
|---|---|---|
| `ventago-app/scripts/gen-permissions.ts` | BE 호출 → permissions.gen.ts 자동 생성 | ~120 |
| `ventago-app/src/configs/permissions.gen.ts` | PermissionKey enum + meta (placeholder) | ~70 |
| `ventago-app/src/configs/permission-keys.ts` | wrapper + mapLegacySubject + unifiedSubject | ~70 |
| `.gsd/guide-permissions-v2-frontend-migration.md` | 점진 마이그레이션 가이드 | ~150 |

### 수정 (3)
| 파일 | 변경 |
|---|---|
| `api-ventago/src/app/permissions/permissions.service.ts` | listPermissionSlugs 메서드 추가 |
| `api-ventago/src/app/permissions/permissions.controller.ts` | GET /permissions/keys 엔드포인트 추가 |
| `ventago-app/package.json` | `npm run gen:permissions` 스크립트 추가 |

## 핵심 결정

### 1. 일괄 치환 보류
- Day 4 의 "기존 가드 폐기 보류" 와 동일 패턴
- 100+ 위치 + 30+ subject 어휘 = 한 번 PR 로 회귀 위험 큼
- 점진 마이그레이션 가이드 제시 (Phase 30 에서 주별 1-2 라우트씩)

### 2. PermissionKey enum + placeholder 파일
- BE 가 안 떠있어도 build 가능하도록 placeholder commit
- 운영 적용 직전 `npm run gen:permissions` 1회 실행
- 신규 컴포넌트는 즉시 PermissionKey 사용 권장

### 3. mapLegacySubject + unifiedSubject helper
- 두 어휘 (legacy / new) 호환 layer
- 마이그레이션 단계 helper — 완료 시 deprecate

### 4. permissions.controller.ts 의 keys 엔드포인트는 인증만 필요 (Permission 메타 X)
- generator 가 anonymous 호출할 가능성 + 일반 사용자도 자기 권한 알아야 함
- 단, JWT 인증은 필요 (super_admin 통과 정책 안 적용, 누구나 read)

## 품질 검증

### Phase 12 성능 규약
- [x] **참조 데이터 SWR**: PermissionKey 는 빌드타임 enum 이라 SWR 불필요
- [x] **Pool 안전**: BE listPermissionSlugs 는 단일 SQL with GROUP BY array_agg

### TypeScript 타입 안전성
- [x] PermissionKey enum 으로 string literal 강제
- [x] PERMISSION_META 의 functionCount/moduleSlugs 타입 명시

## 알려진 제약

### ⚠️ 1. 점진 마이그레이션은 Phase 30 으로 분리
본 SPEC 에서는 신규 컴포넌트만 PermissionKey 사용. 기존 100+ 위치 일괄 치환 X.

### ⚠️ 2. permissions.gen.ts 는 placeholder
BE 호출 없이 commit 된 정적 데이터. 운영 적용 직전 generator 1회 실행 필요.

### ⚠️ 3. mapLegacySubject 의 매핑은 10개 (전체 30+ subject 의 1/3)
나머지 subject 는 점진 마이그레이션 시 case-by-case 결정.

## Mac 검증

```bash
cd /Users/marcoskim/Trabajos_Programming/ACE_online_1.0/api-ventago && npm run dev:api &
cd /Users/marcoskim/Trabajos_Programming/ACE_online_1.0/ventago-app && npm run gen:permissions
# permissions.gen.ts 가 갱신되어야 함 (18 → 실제 BE 의 permission_slug 수)

cd /Users/marcoskim/Trabajos_Programming/ACE_online_1.0/ventago-app
npm run lint
npm run build
```

## Sprint 2 진행 현황

| Day | 진행도 | 상태 |
|---|---|---|
| Day 6-7 | 100% | ✅ 완료 |
| Day 8 — ACL generator + 어휘 통일 기반 | 100% | ✅ 완료 (점진 마이그레이션은 Phase 30) |
| Day 9 — E2E 테스트 | 0% | 다음 |
| Day 10 — 매장 셋업 마법사 + 운영 PG10 적용 | 0% | 다음 |

**Sprint 2 60% 진행 (3/5 day)**.
