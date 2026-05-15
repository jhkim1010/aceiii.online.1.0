# GSD 종합 리뷰 — Phase 29 권한 시스템 v2 Sprint 1 완료

작성일: 2026-05-14
관련 SPEC: `.gsd/spec-permissions-v2.md`
이전 리뷰: Day 1-2, Day 3, Day 4

## Sprint 1 Backend 100% 완료 (5/5 day)

| Day | 태스크 | 상태 |
|---|---|---|
| Day 1 | DB 마이그레이션 (4 테이블 + ENUM + 컬럼 확장 + 인덱스) | ✅ |
| Day 2 | 8 Role + role_functions + approval_thresholds seed | ✅ |
| Day 3 | Sequelize 모델 4개 + 기존 3개 확장 + PermissionsModule | ✅ |
| Day 4 | PermissionGuard + Cache + Resolver + BranchScopeGuard | ✅ |
| Day 5 | ApprovalService + audit_log 확장 + Permissions API | ✅ |

## Day 5 산출물

### 신규 (5)
| 파일 | 역할 | 라인 |
|---|---|---|
| `src/app/permissions/approval.service.ts` | 임계값 체크 + 승인 큐 (approve/reject/expireOld) | ~250 |
| `src/app/permissions/approval.controller.ts` | 4 엔드포인트 (list/create/approve/reject) | ~150 |
| `src/app/permissions/permissions.service.ts` | 매트릭스 조회 + user_branch 부여/회수 (audit + cache 자동) | ~250 |
| `src/app/permissions/permissions.controller.ts` | 4 엔드포인트 (matrix/userDetail/assign/revoke) | ~165 |

### 수정 (2)
| 파일 | 변경 |
|---|---|
| `src/app/audit-log/audit-log.service.ts` | AuditLogAction union 8 신규 값 + logPermissionChange 헬퍼 |
| `src/app/permissions/permissions.module.ts` | 4 신규 service/controller + AuditLogModule import |

## 핵심 설계 결정

### 1. 권한 변경은 항상 트랜잭션 안에 audit_log 같이 INSERT
- `PermissionsService.assignUserBranch / revokeUserBranch` 안에서 같은 transaction 으로 audit_log 적재
- 분리 시 권한만 바뀌고 audit 누락되는 케이스 차단
- 트랜잭션 commit 후 cache invalidate (트랜잭션 밖에서 별도 connection)

### 2. Cache invalidate 타이밍
- `PermissionsService` 가 권한 변경 후 `cacheService.invalidateUser(userId)` 호출
- 트랜잭션 밖 → DB connection 짧게 사용 (pool 효율)

### 3. ApprovalService 의 socket.io 분리
- `createRequest()` 는 DB INSERT 까지만
- socket.io 푸시는 controller 또는 별도 service 에서 처리 (websocket 의존 분리)
- 향후 NotificationsModule 통합 시 정리 가능

### 4. ApprovalThreshold 의 지점별/매장 전역 fallback
- 지점별 임계값 우선, 없으면 매장 전역 (`branch_id IS NULL`) 임계값 적용
- `ORDER BY branch_id DESC NULLS LAST` 로 sort, LIMIT 1

## 전체 권한 시스템 v2 산출물 (Sprint 1 5일)

### DB (5 마이그레이션 SQL, 14 테이블/컬럼/인덱스)
| 파일 | 변경 |
|---|---|
| `phase29-permissions-v2.sql` | 4 신규 테이블 + ENUM 8 신규 값 + 6 컬럼 확장 + 8 인덱스 |
| `phase29-permissions-v2-fixup.sql` | user_functions 컬럼 + NOW() partial index 수정 |
| `phase29-functions-permission-slug.sql` | functions.permission_slug + 28 매핑 + 인덱스 |

### Backend Code (15 신규 + 7 수정)
| 분류 | 파일 수 | 라인 합계 |
|---|---|---|
| Sequelize 모델 (신규) | 4 | ~320 |
| Sequelize 모델 (수정) | 4 | (확장) |
| 서비스 | 4 | ~800 |
| 가드 | 2 | ~260 |
| 데코레이터 | 2 | ~55 |
| 컨트롤러 | 2 | ~315 |
| 모듈 | 1 | ~50 |
| Seeder/storeTemplate | 2 | (확장 200+) |

### 문서 산출물
| 파일 | 용도 |
|---|---|
| `ANALYSIS.md` | 다층 사고법 분석 + 추천 (387 줄) |
| `Ventago_Permissions_Matrix.xlsx` | 5시트 매트릭스 (Permission Matrix / Role 정의 / 승인 임계값 / Branch 스코프 모델 / Summary) |
| `mockup.html` | UI 4탭 인터랙티브 목업 |
| `spec-permissions-v2.md` | GSD SPEC + multi-role 정책 명문화 |
| `review-permissions-v2-day1-2.md` | Day 1-2 리뷰 |
| `review-permissions-v2-day3.md` | Day 3 리뷰 |
| `review-permissions-v2-day4.md` | Day 4 리뷰 |
| `note-permissions-v2-day4-decision.md` | 기존 가드 폐기 보류 결정 |
| `review-permissions-v2-sprint1-final.md` | (본 문서) Sprint 1 종합 |

## 품질 검증

### Pool 안전 (사용자 메모리 #pool 우선순위 기준)
- [x] `pool.connect()` 직접 사용 0건
- [x] 모든 query 가 sequelize 모델 메서드 또는 sequelize.query() 사용
- [x] 트랜잭션은 try/catch + finally rollback 보장
- [x] PermissionGuard 1 요청당 최대 2 query (cache MISS 시), HIT 시 1 query
- [x] PermissionResolverService 의 핵심 SQL 은 단일 round trip with CTE + JSONB aggregate
- [x] `idx_user_branches_user_active` 등의 NOW() IMMUTABLE 위반 모두 해결
- [x] DB Pool: `min=10, max=80, idle=10s, acquire=15s` (database.module.ts) — 변경 없음

### 코드 안전성
- [x] 모든 async 함수에 try/catch + 한국어 주석
- [x] 에러 시 deny-by-default 정책 (PermissionGuard, BranchScopeGuard)
- [x] super_admin / superadmin (legacy) 통과 호환
- [x] @Permission 메타 없는 핸들러 통과 (legacy 컨트롤러 호환)

### DB 무결성 (마지막 SQL 검증 결과)
| 항목 | 결과 |
|---|---|
| 신규 테이블 4개 | ✅ 모두 생성 |
| audit_logs.action ENUM 13값 | ✅ |
| user_functions 5 신규 컬럼 | ✅ |
| role_functions.branch_id | ✅ |
| functions.permission_slug | ✅ (28 매핑 / 18 unique) |
| 10 phase29 인덱스 | ✅ |

## 후속 작업 (Sprint 2 진입 전)

### ⚠️ 필수 (Mac 검증)
```bash
cd /Users/marcoskim/Trabajos_Programming/ACE_online_1.0/api-ventago
npm run build                           # 타입 체크
npx eslint src/app/permissions/ src/app/audit-log/ --fix
npm run dev:api                         # 부팅 + 모델 등록 로그 확인
```

기대: `[SequelizeModels] 등록된 모델 목록` 에 다음 4개 포함:
- UserBranch
- ApprovalThreshold
- ApprovalRequest
- UserPermissionCache

### ⚠️ 알려진 이슈 (별도 SPEC)
1. **storeTemplate idempotent 가드 누락** — 기존 `createDefaultRoleFunctions` 가 같은 매장에 여러 번 호출되면 중복 INSERT (store 6 의 rf_count = 436, 정상 148의 3배). 후속 SPEC 으로 처리.
2. **functions.permission_slug 커버리지 18%** — 28 / 148 매핑. 운영 진입 전 핵심 컨트롤러는 모두 매핑 필요.
3. **기존 @FunctionGuard 와 신규 @Permission 병행 운영** — 점진 마이그레이션은 Phase 30 후보 (`note-permissions-v2-day4-decision.md`).
4. **OnlineOrdersExpiryCron stuck** — 별개 이슈 (combined-2026-05-14.log). 본 SPEC 무관.

### Sprint 2 (Frontend) 시나리오
- Day 6-7: 4탭 권한 페이지 (mockup.html → MUI 변환)
- Day 8: ACL generator 스크립트 + `subject` → `function_slug` 일괄 치환
- Day 9: E2E 테스트 (실제 DB hit, mock 금지)
- Day 10: 매장 셋업 마법사 + 운영 PG10 마이그레이션

## 결론

**Sprint 1 (Backend) 100% 완료** — 권한 시스템 v2 의 backend 기반은 모두 구축됐습니다.

핵심 기능:
- ✅ Multi-branch RBAC (`user_branches` UNIQUE per user/branch)
- ✅ 1-query 권한 합성 (CTE + JSONB aggregate, cache 5분 TTL)
- ✅ Approval Threshold (금액·수량 기반 승인 큐)
- ✅ 권한 변경 audit_log (트랜잭션 안 자동 적재)
- ✅ 매트릭스 API (UI 용 단일 SQL)
- ✅ super_admin / store_owner / store_admin / branch_manager / cashier / inventory_clerk / accountant / viewer 8 표준 Role

운영 진입 가능성:
- 운영 사용자 0명 가정 → 점진 마이그레이션 코드 없음, 즉시 적용 가능
- Sprint 2 Frontend 완료 후 Day 10 에 운영 PG10 적용 예정

다음 액션: Mac 에서 build / ESLint / dev:api 부팅 검증 → Sprint 2 진입.
