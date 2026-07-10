# SPEC: Phase 55 — 화면 깜빡임/불필요 리렌더 제거 (사이드바 + 라우트 전환)
생성일: 2026-07-10

## 목표
페이지 전환 시 컨텐츠 영역이 스켈레톤으로 "깜빡"하는 현상과, 사이드바가 유휴 상태에서도 매초·라우트 전환마다 수차례 다시 그려지는 낭비를 제거한다. 시각적 디자인은 그대로 유지한다.

## 배경 및 컨텍스트 (2026-07-10 로컬 분석으로 확정된 원인)

### 깜빡임(플리커) 확정 지점 — 정확한 위치와 메커니즘

**F-1. 라우트 전환 스켈레톤 즉시 교체 (가장 눈에 띄는 깜빡임)**
- 위치: `ventago-app/src/pages/_app.tsx` 251~292행 (`isRouteChanging` + `PageTransitionSkeleton`)
- 메커니즘: `routeChangeStart` 즉시 `isRouteChanging=true` → **현재 페이지가 그 자리에서 언마운트**되고 스켈레톤(버튼 3개+400px 박스)으로 교체 → 전환 완료 시 새 페이지 마운트. 빠른 전환(100~300ms)에서도 무조건 `컨텐츠 → 스켈레톤 → 컨텐츠` 2회 화면 교체가 발생 = 깜빡임. NProgress 바까지 동시에 돌아 로딩 표시가 이중.
- 개선: **지연 스켈레톤 패턴** — routeChangeStart 후 200ms 타이머를 걸고, 200ms 안에 완료되면 스켈레톤을 아예 그리지 않는다(이전 컨텐츠 유지). 200ms 초과 시에만 스켈레톤 표시. (cleanup에서 clearTimeout 필수)

**F-2. 사이드바 풋터 1초 시계 → 매초 풋터 전체 리렌더**
- 위치: `ventago-app/src/layouts/components/vertical/SidebarFooter.tsx` 41~49행 `setInterval(() => setNow(...), 1000)`
- 메커니즘: 시계 state가 SidebarFooter 최상위에 있어 매초 로고/지점배지/유저정보/Tooltip/모달 3개(SelectBoxTerminalModal·ModalCashRegister·BranchSwitchModal, 인라인 `onClose={() => ...}` 포함)가 전부 리렌더. 유휴 상태에서도 앱이 초당 1회 사이드바 하단을 다시 그린다.
- 개선: 시계를 전용 `<SidebarClock />` 컴포넌트로 분리(리렌더를 시계 텍스트에만 격리) + 모달 3개를 `{open && <Modal .../>}` 조건부 마운트로 전환.

**F-3. 사이드바 그룹의 라우트 전환 연쇄 setState (그룹 접힘/펼침 재애니메이션 깜빡임)**
- 위치: `ventago-app/src/@core/layouts/components/vertical/navigation/VerticalNavGroup.tsx` 130~145행 `useEffect([router.asPath])`
- 메커니즘: 라우트가 바뀌면 **그룹마다** 내용이 같아도 무조건 `setGroupActive([...groupActive])` + `setCurrentActiveGroup([...])` 호출 → 새 배열 참조로 부모(Navigation) state 변경 → **그룹 수(≈6)만큼 전체 nav 트리 리렌더 연쇄** + Collapse 상태 재계산으로 열림/닫힘 애니메이션이 다시 도는 깜빡임.
- 개선: effect 내에서 멤버십이 **실제로 변할 때만** setState (배열 비교 가드). `navCollapsed && !navHover` 분기도 현재 상태와 다를 때만 set.

**F-4. memo(Navigation) 무력화 — 사이드바가 레이아웃 리렌더에 무조건 동승**
- 위치: `ventago-app/src/@core/layouts/VerticalLayout.tsx` 90행 `const toggleNavVisibility = () => setNavVisible(!navVisible)`
- 메커니즘: 매 렌더 새 함수 → `memo(Navigation)`의 props 비교가 항상 실패. 라우트 전환 시 `_app`의 `isRouteChanging` true→false 토글 2회 + UserLayout state 변화(모달/터미널 조회 등)마다 사이드바 전체가 따라 그려짐.
- 개선: `useCallback(() => setNavVisible(v => !v), [])` 로 고정.

**F-5. 보조 안정화 (F-4와 세트)**
- `navigation/index.tsx` 94행: `navMenuContentProps = {...props, navHover, ...}` 매 렌더 새 객체 → afterContent(SidebarFooter) 재호출 유발 → 필요한 필드만 useMemo로 구성.
- `UserLayout.tsx` 122~124행: `settings.layout = 'vertical'` **직접 변이(안티패턴)** → effect + saveSettings 로 교체(추후 memo 최적화 시 stale UI 버그 예방).
- `UserLayout.tsx` 53행: `branchOptions` 매 렌더 새 배열 → useMemo.

### 제외(깜빡임 원인 아님을 확인)
- `settingsContext`의 pageSettings effect: `setConfig` 사용 페이지가 현재 0개 — 실동작 없음.
- AuthContext: `/auth/me`는 마운트 1회만 — user 참조 안정, 네비 useMemo 정상 동작 중.

## 기술 스택
- 언어/프레임워크: Next.js (Pages Router) + React 18 + MUI, TypeScript
- DB: 해당 없음 (프론트엔드 전용 phase — pool 영향 없음)
- ESLint 설정 파일: `ventago-app/.eslintrc.json`

## 태스크 목록
- [ ] TASK-1: 지연 스켈레톤 (200ms 임계) — 파일: `src/pages/_app.tsx` (F-1)
- [ ] TASK-2: `SidebarClock` 분리 + 모달 3개 조건부 마운트 — 파일: `src/layouts/components/vertical/SidebarFooter.tsx`, 신규 `src/layouts/components/vertical/SidebarClock.tsx` (F-2)
- [ ] TASK-3: NavGroup effect 변경 가드 — 파일: `src/@core/layouts/components/vertical/navigation/VerticalNavGroup.tsx` (F-3)
- [ ] TASK-4: `toggleNavVisibility` useCallback 고정 — 파일: `src/@core/layouts/VerticalLayout.tsx` (F-4)
- [ ] TASK-5: navMenuContentProps 안정화 + settings.layout 변이 제거 + branchOptions useMemo — 파일: `src/@core/layouts/components/vertical/navigation/index.tsx`, `src/layouts/UserLayout.tsx` (F-5)
- [ ] TASK-6: ESLint 검증 실행 (`npx eslint src/... --fix`, 오류 0개)
- [ ] TASK-7: React DevTools Profiler 검증 — (a) 유휴 60초간 리렌더 = SidebarClock만, (b) 라우트 전환 1회당 nav 트리 리렌더 ≤ 2회, (c) 200ms 미만 전환에서 스켈레톤 미표시(깜빡임 소멸) 확인

## 완료 기준
- ESLint 오류 0개
- 빠른 라우트 전환(<200ms)에서 스켈레톤이 보이지 않고 컨텐츠 교체가 1회만 발생
- 유휴 상태에서 사이드바 리렌더가 시계 텍스트로만 격리됨 (Profiler로 확인)
- 라우트 전환 시 그룹 Collapse 재애니메이션 깜빡임 소멸
- 사이드바 시각 디자인·아코디언 동작 변화 없음

## 금지사항 / 주의사항
- 시각 디자인(색/폭/애니메이션 시간) 변경 금지 — 순수 리렌더 최적화만
- 그룹 아코디언 열림/닫힘 규칙(순수 아코디언) 변경 금지
- `@core` 템플릿 광범위 리팩터링 금지 — 명시된 파일·행만 최소 수정
- memo/useCallback 남발 금지 — 원인 제거(F-1~F-3)가 우선, memo는 F-4 한 곳
- TASK-1에서 타이머 cleanup(clearTimeout) 누락 금지 — 빠른 연속 전환 시 스켈레톤이 늦게 떠버리는 역효과 방지
- 한 태스크 = 한 커밋 단위로 진행, 각 태스크 후 해당 파일 eslint 확인
