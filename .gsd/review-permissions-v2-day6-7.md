# GSD 리뷰 리포트 — Phase 29 Sprint 2 Day 6-7 (Frontend 권한 페이지)

작성일: 2026-05-14
관련 SPEC: `.gsd/spec-permissions-v2.md`
이전 리뷰: Sprint 1 Final Review

## Day 6-7 완료된 태스크

- [x] TASK-6.1 권한 페이지 진입점 (next/dynamic, ssr false)
- [x] TASK-6.2 SWR 훅 4개 (matrix / userBranches / approvalQueue / auditLog)
- [x] TASK-6.3 MatrixGrid 컴포넌트 (sticky table, role × permission, CRUD chip)
- [x] TASK-6.4 UserDetail / AuditLogTimeline / ThresholdEditor 컴포넌트

## 변경 파일 요약

### 신규 (9)
| 파일 | 역할 | 라인 |
|---|---|---|
| `src/pages/configuracion/permisos/index.tsx` | Next.js 페이지 + WithAccess 가드 | ~30 |
| `src/views/configuracion/permisos/PermissionsView.tsx` | 4탭 진입 (next/dynamic) | ~95 |
| `src/views/configuracion/permisos/MatrixGrid.tsx` | Role × Permission 매트릭스 + 검색 + 지점 필터 | ~210 |
| `src/views/configuracion/permisos/UserDetail.tsx` | 사용자 상세 (multi-branch RBAC) | ~150 |
| `src/views/configuracion/permisos/AuditLogTimeline.tsx` | 권한 변경 타임라인 + 필터 | ~150 |
| `src/views/configuracion/permisos/ThresholdEditor.tsx` | 임계값 표 (조회 only) | ~125 |
| `src/hooks/api/usePermissionsMatrix.ts` | SWR — matrix 5분 dedup | ~30 |
| `src/hooks/api/useUserBranches.ts` | SWR — user detail 1분 dedup | ~30 |
| `src/hooks/api/useApprovalQueue.ts` | SWR — approval 10초 dedup + 30초 refresh | ~40 |
| `src/hooks/api/useAuditLog.ts` | SWR — audit log 30초 dedup | ~50 |

### 수정 (0)
없음 — 모두 신규 추가만.

## 핵심 설계 결정

### 1. 코드 스플리팅 (Phase 12 규약 준수)
- 페이지: `next/dynamic(() => import(...), { ssr: false })`
- 4탭의 view 도 각각 `next/dynamic` — 사용자가 탭 클릭하기 전까지 chunk 안 로드됨
- Loading skeleton 컴포넌트 inline (TabSkeleton)

### 2. SWR 캐시 전략
- `usePermissionsMatrix` — 5분 dedup (변경 빈도 낮음)
- `useUserBranches` — 1분 dedup (사용자 상세는 자주 갱신)
- `useApprovalQueue` — 10초 dedup + 30초 refreshInterval (실시간성)
- `useAuditLog` — 30초 dedup (필터별 캐시)

### 3. ACL (WithAccess)
- `PermissionsPage.acl = { action: 'manage', subject: 'configuracion-permisos' }`
- super_admin / store_owner / store_admin 만 접근 가능 (CASL 규약)

### 4. mockup.html → MUI 변환
- 다크 네이비/골드 테마는 MUI 의 기본 theme 으로 (커스터마이징은 후속)
- Chip / Card / Stack 으로 mockup 의 카드 레이아웃 재현
- 매트릭스 셀의 CRUD 코드 (CRUD/CRU—/CR—/—R—) 는 actionsToCode 헬퍼로 일관

### 5. UserDetail / ThresholdEditor 의 편집 기능 disabled
- 이번 phase 는 read-only — 편집 (POST/PUT) 은 후속 SPEC
- 데이터 모델/API 는 Sprint 1 Backend 에서 완성됐으므로 향후 활성화만 하면 됨

## 품질 검증

### Phase 12 성능 규약 준수
- [x] **next/dynamic**: 페이지 + 4탭 view 모두 dynamic import
- [x] **SWR 훅**: 5/1/10/30초 dedup 적절히 설정
- [x] **참조 데이터 SWR**: 권한 매트릭스 등 모두 SWR 훅
- [x] **순차 API 호출 금지**: 매트릭스는 단일 API (BE 의 1-query CTE)
- [x] **React.memo**: 모든 컴포넌트 (MatrixGrid, UserDetail 등) 적용

### MUI / 디자인 규약
- [x] sx prop 일관 사용 (inline style 회피)
- [x] Sentence case ("권한 매트릭스" / "사용자 상세")
- [x] Icon: @iconify/react (mdi:* 일관)
- [x] CircularProgress / Skeleton 으로 loading state

### TypeScript 타입 안전성
- [x] SWR 훅의 응답 타입 명시 (MatrixResponse, UserDetail 등 export)
- [x] 컴포넌트 props/state 타입 명시

## 알려진 제약 (후속 SPEC 으로 처리)

### ⚠️ 1. UserDetail 의 사용자 검색 — 단순 ID 입력
- 현재: textfield 에 user_id 입력
- 향후: 자동완성 검색 (이메일 / 이름)

### ⚠️ 2. 매트릭스 편집 disabled
- 현재: Chip 으로 read-only 표시
- 향후: 셀 클릭 → CRUD 4 체크박스 popover → 저장

### ⚠️ 3. ThresholdEditor 정적 데이터
- 현재: 시드 값과 매칭되는 정적 표
- 향후: BE GET /api/permissions/thresholds 엔드포인트 + 인라인 편집

### ⚠️ 4. WithAccess subject 가 'configuracion-permisos'
- 기존 ACL 어휘 사용 — Phase 30 의 generator 스크립트가 신규 어휘로 통일 예정

## Mac 검증 권장

```bash
cd /Users/marcoskim/Trabajos_Programming/ACE_online_1.0/ventago-app
npm run lint
npm run build
npm run dev          # http://localhost:3050/configuracion/permisos 접속
```

기대:
- /configuracion/permisos 라우팅 정상
- 4탭 각각 chunk 로 분리 로드
- BE (npm run dev:api) 가 같이 떠있어야 매트릭스 데이터 표시

## Sprint 2 진행 현황

| Day | 진행도 | 상태 |
|---|---|---|
| Day 6 — 페이지 + SWR 훅 | 100% | ✅ 완료 |
| Day 7 — 4 컴포넌트 | 100% | ✅ 완료 |
| Day 8 — ACL generator + 어휘 통일 | 0% | 다음 |
| Day 9 — E2E 테스트 | 0% | 다음 |
| Day 10 — 매장 셋업 마법사 + 운영 적용 | 0% | 다음 |

**Sprint 2 40% 진행 (2/5 day)** — Frontend 핵심 화면은 완성.
