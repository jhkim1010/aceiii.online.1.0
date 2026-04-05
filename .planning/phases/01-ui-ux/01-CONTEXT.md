# Phase 1: UI 토글 메커니즘 - Context

**Gathered:** 2026-04-05
**Status:** Ready for planning

<domain>
## Phase Boundary

UI/UX 토글 메커니즘 구축. 사이드바 하단에 "UI/UX nuevo" 체크박스를 추가하여 admin/superadmin 유저가 새 UI와 기존 UI를 전환할 수 있게 한다. 새 UI 디자인 자체는 Phase 4에서 구현하며, 이 Phase는 토글 인프라만 담당.

</domain>

<decisions>
## Implementation Decisions

### 토글 저장소
- **D-01:** 토글 상태는 DB `users` 테이블에 `ui_mode` 컬럼으로 저장 (유저별 설정, 디바이스 무관)

### 토글 UI
- **D-02:** 사이드바 하단(`SidebarFooter.tsx`)에 체크박스 + "UI/UX nuevo" 라벨로 표시
- **D-03:** admin, superadmin 역할만 체크박스 표시. vendedor/gerente에게는 숨김

### 적용 범위
- **D-04:** 페이지별 점진적 적용 방식. 토글 ON이더라도 새 UI가 준비된 페이지만 새 UI 표시, 미준비 페이지는 기존 UI 유지
- **D-05:** UX-01, UX-02, UX-03 요구사항은 Phase 4로 이동. Phase 1은 토글 인프라만

### 조건부 렌더링 전략
- **D-06:** 조건부 렌더링 메커니즘은 Claude 재량. 컨텍스트/HOC/컴포넌트 분기 등 적절한 방식 선택

### Claude's Discretion
- 조건부 렌더링 아키텍처 패턴 (Context API, HOC, 동적 import 등)
- DB 마이그레이션 방식 (기존 마이그레이션 패턴 따름)
- API 엔드포인트 설계 (토글 상태 변경용)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### 사이드바 구조
- `ventago-app/src/layouts/components/vertical/SidebarFooter.tsx` — 토글 체크박스 추가 위치
- `ventago-app/src/layouts/UserLayout.tsx` — 메인 레이아웃 진입점
- `ventago-app/src/@core/layouts/VerticalLayout.tsx` — 레이아웃 프레임

### 인증 & 역할
- `ventago-app/src/hooks/useAuth.tsx` — user 객체 접근 (role, storeId 등)
- `ventago-app/src/configs/roles.ts` — 역할 정의 (admin, superadmin, vendedor, gerente)
- `api-ventago/src/app/auth/auth.service.ts` — `/me` 엔드포인트 (user 정보 반환)

### DB & 모델
- `api-ventago/src/app/users/users.model.ts` — Users 모델 (ui_mode 컬럼 추가 대상)
- `api-ventago/src/database/migrations/` — 마이그레이션 디렉토리

### 테마 설정
- `ventago-app/src/configs/themeConfig.ts` — MUI 테마 설정

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `SidebarFooter.tsx`: 사이드바 하단 컴포넌트 (매장 로고/이름 + 시계 표시 중). 체크박스 추가 위치
- `useAuth()` 훅: user 객체에서 role 확인 가능 (admin/superadmin 체크)
- `AuthContext.tsx`: 인증 상태 관리. ui_mode를 여기에 포함 가능
- `apiConnector`: API 호출 유틸리티

### Established Patterns
- MUI 5 컴포넌트 사용 (Checkbox, FormControlLabel 등)
- Sequelize `underscored: true` → DB 컬럼은 `ui_mode` (snake_case)
- React.memo로 사이드바 리렌더링 최적화 적용됨 — 토글 추가 시 이 최적화 유지 필요

### Integration Points
- `/me` API 응답에 `uiMode` 필드 추가 필요
- `users` 테이블에 `ui_mode` 컬럼 추가 (마이그레이션)
- 토글 상태 변경 API 엔드포인트 필요 (PUT `/users/ui-mode`)
- 프론트엔드에서 조건부 렌더링을 위한 컨텍스트/훅 필요

</code_context>

<specifics>
## Specific Ideas

- 사이드바 하단의 체크박스는 작고 심플하게 — 기존 로고/시계 영역을 방해하지 않도록
- 토글 변경 시 페이지 새로고침 없이 즉시 반영이 이상적

</specifics>

<deferred>
## Deferred Ideas

### Phase 4로 이동된 요구사항
- UX-01: 로그인 화면 세련화
- UX-02: 대시보드 개선 및 주요 지표 시각화
- UX-03: 전반적 UI 일관성 및 반응형 개선

*이 요구사항들은 Phase 4 (새 UI/UX 디자인)에서 토글 ON 상태의 UI로 구현*

</deferred>

---

*Phase: 01-ui-ux*
*Context gathered: 2026-04-05*
