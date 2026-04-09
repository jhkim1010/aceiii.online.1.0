# Phase 14: Permisos Control — 역할별 권한 관리 UI - Context

**Gathered:** 2026-04-09
**Status:** Ready for planning

<domain>
## Phase Boundary

역할별/유저별 권한 관리 시스템 전체 구축. 백엔드 API Guard + 프론트엔드 CASL granular enforcement + 관리 UI를 포함한 full-stack 권한 제어. 기존 Apps→Modules→Functions 구조에 CRUD Action을 추가하여 정교한 권한 관리 실현.

</domain>

<decisions>
## Implementation Decisions

### 적용 범위
- **D-01:** Full stack 적용 — 관리 UI + 프론트엔드 CASL granular enforcement + 백엔드 API 엔드포인트별 Guard
- **D-02:** 현재 CASL의 `can('manage', 'all')` → 실제 Function+Action 기반 granular 체크로 변경

### 접근 권한 계층
- **D-03:** 권한 관리 UI 접근 3단계:
  - **superadmin**: 전체 시스템 권한 관리 (모든 매장, 모든 역할)
  - **admin**: 자기 매장(store) 내 역할/유저 권한만 관리
  - **gerente**: 자기 지점(branch) 소속 유저 권한 조회/수정만 가능

### 차단 UX
- **D-04:** 권한 없는 기능 접근 시:
  - 사이드바에서 해당 메뉴 숨김 (네비게이션에서 제거)
  - URL 직접 접근 시 401 Not Authorized 페이지 표시

### 권한 Granularity
- **D-05:** Function 단위 + CRUD Action 분리
  - 기존 구조: Apps → Modules → Functions (ON/OFF)
  - 변경: Apps → Modules → Functions → Actions (create/read/update/delete)
  - 각 Function에 대해 CRUD 액션별 개별 허용/차단 가능
  - 예: '상품 관리' Function에서 read만 허용, create/update/delete는 차단

### Claude's Discretion
- 기존 UI(RoleCards, RolePermissionsDrawer, UserPermissionsDrawer) 개선/통합 방식 — 코드베이스 분석 후 최적 접근법 결정
- DB 스키마 변경 방식 (RoleFunction/UserFunction에 action 컬럼 추가 vs 별도 테이블)
- 백엔드 Guard 구현 패턴 (데코레이터 기반, 미들웨어 등)
- CASL ability 빌딩 로직 리팩토링 방식

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### 권한 모델 (백엔드)
- `api-ventago/src/app/functions/functions.model.ts` — Functions 모델 (Apps→Modules→Functions 계층의 leaf)
- `api-ventago/src/app/functions/functions.service.ts` — getStructure() 메서드 (Apps→Modules→Functions 트리 조회)
- `api-ventago/src/app/role/role.model.ts` — Role 모델 (id, name, slug, storeId)
- `api-ventago/src/app/role/role-function/role-function.model.ts` — 역할별 Function 할당
- `api-ventago/src/app/users/user-function/user-function.model.ts` — 유저별 Function 오버라이드 (allowed: boolean)
- `api-ventago/src/app/users/user-role/user-role.model.ts` — 유저-역할 매핑

### 인증/세션 (백엔드)
- `api-ventago/src/app/auth/auth.service.ts` — /me 엔드포인트, structure 응답 구성, RoleFunction/UserFunction 로딩
- `api-ventago/src/app/session/guards/session.guard.ts` — 세션 Guard 패턴 참조

### CASL 권한 (프론트엔드)
- `ventago-app/src/configs/acl.ts` — 현재 CASL ability 빌딩 (manage all 패턴 → 개선 필요)
- `ventago-app/src/layouts/components/acl/Can.tsx` — AbilityContext 정의
- `ventago-app/src/@core/components/auth/AclGuard.tsx` — 페이지 레벨 권한 체크
- `ventago-app/src/layouts/components/acl/CanViewNavLink.tsx` — 네비게이션 링크 권한 체크
- `ventago-app/src/layouts/components/acl/CanViewNavGroup.tsx` — 네비게이션 그룹 권한 체크

### 기존 권한 관리 UI
- `ventago-app/src/views/admin/permissions/PermissionsListView.tsx` — superadmin 권한 목록 (FullTable)
- `ventago-app/src/views/users/components/UserPermissionsDrawer.tsx` — 유저별 권한 편집 (TreeView)
- `ventago-app/src/views/users/roles/RoleCards.tsx` — 역할 카드 UI
- `ventago-app/src/views/users/roles/hooks/useRoleFunctions.ts` — 역할별 Function 조회 훅
- `ventago-app/src/views/users/roles/hooks/useFunctions.ts` — Functions 구조 조회 훅

### 네비게이션
- `ventago-app/src/navigation/vertical/index.ts` — 사이드바 메뉴 구성 (user.structure 기반)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **FullTable 컴포넌트**: `src/components/table/FullTable` — 페이지네이션, 검색 지원 테이블 (PermissionsListView에서 사용중)
- **TreeView (MUI Lab)**: UserPermissionsDrawer에서 이미 권한 트리 표시에 사용
- **CardFilter 컴포넌트**: 필터 카드 UI
- **useRoleFunctions / useFunctions 훅**: 역할별/전체 Function 구조 조회
- **CrudService**: `src/common/crud/crud.service.ts` — 범용 CRUD 서비스 패턴

### Established Patterns
- **백엔드 Guard**: SessionGuard 패턴 참조 가능 (JWT 후 추가 검증)
- **Sequelize underscored**: DB 컬럼은 snake_case, 모델은 camelCase
- **멀티테넌트**: 거의 모든 테이블에 storeId FK
- **네비게이션**: user.structure (auth /me 응답)로 사이드바 동적 구성

### Integration Points
- **auth.service.ts /me**: structure에 권한 정보 포함하여 반환 → CASL ability 빌딩에 사용
- **acl.ts buildAbilityFor()**: 현재 roles 기반 → Function+Action 기반으로 변경 필요
- **AclGuard.tsx**: 페이지별 aclAbilities 체크 → granular subject/action으로 확장
- **네비게이션 index.ts**: user.structure 기반 → 권한 없는 메뉴 숨김 로직 추가

</code_context>

<specifics>
## Specific Ideas

- Function별 CRUD Action 분리: create/read/update/delete 4개 액션
- 3단계 관리 계층: superadmin → admin → gerente
- 기존 RoleFunction/UserFunction 테이블에 action 정보 추가 필요

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 14-permisos-control-ui*
*Context gathered: 2026-04-09*
