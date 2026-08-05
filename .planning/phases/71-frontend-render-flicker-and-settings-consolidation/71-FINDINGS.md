# Phase 71 — 코드 대조 결과 (2026-08-05)

외부 AI 의 제안을 계획서로 옮기기 전에 **전부 실제 코드로 확인**했다.
Phase 65 에서 계획서가 코드와 어긋난 채 남아 사고로 이어진 전례가 있어, 전제부터 검증한다.

결론: **지적 5건 전부 사실.** 추가로 계획서에 없던 결함 1건을 더 찾았다.

---

## 확인된 것

### F1. 라우트 전환에 로딩 표현이 2개 동시에 걸린다 — 사실

`ventago-app/src/pages/_app.tsx`

| 위치 | 내용 |
|---|---|
| `:113~126` | `routeChangeStart` → `NProgress.start()`, complete/error → `NProgress.done()` |
| `:250~270` | 같은 이벤트로 `isRouteChanging` 토글 |
| `:288` | `isRouteChanging ? <PageTransitionSkeleton/> : <Component/>` |

**지연이 없다.** 전환이 20ms 든 2초든 콘텐츠가 즉시 사라진다. 빠른 페이지일수록 깜빡임으로 보인다.

### F2. 전역 스켈레톤 모양이 실제 화면과 무관하다 — 사실

`src/components/layout/PageTransitionSkeleton.tsx`

```
필터 3개: 120×40, 120×40, 80×40
테이블   : width 100%, height 400
```

모든 페이지에 같은 모양을 그린다. 이 구조와 다른 화면(POS 판매, 대시보드, 설정)에서는
스켈레톤 → 실제 화면 전환이 **더 큰 시각적 변화**를 만든다. 로딩 표시가 오히려 깜빡임을 키우는 구조다.

### F3. 설정이 기본값으로 먼저 그려진 뒤 복원된다 — 사실

`src/@core/context/settingsContext.tsx:119`

```tsx
const [settings, setSettings] = useState<Settings>({ ...initialSettings })
useEffect(() => { const restored = restoreSettings(); if (restored) setSettings({ ...restored }) }, [pageSettings])
```

첫 페인트는 항상 기본값(라이트 모드 등) → 다음 프레임에 저장값. 다크 모드 플래시의 직접 원인.

### F4. ★ 계획서에 없던 결함 — 설정 복원이 통째로 버려질 수 있다

같은 effect 안에서:

```tsx
setSettings({ ...restoredSettings })            // (1)
if (pageSettings) setSettings({ ...settings, ...pageSettings })   // (2)
```

(2) 의 `settings` 는 **클로저에 잡힌 복원 이전 값**이다. `pageSettings` 가 있는 페이지에서는
(1) 의 복원 결과가 (2) 에 덮여 사라진다. 상태 갱신이 비동기라 (1) 의 결과가 (2) 시점에 보이지 않는다.

외부 제안은 "여러 effect 가 오래된 settings 를 쓸 수 있다"는 일반론으로 언급했지만,
**한 effect 안에서 이미 발생하고 있다.** 부분 업데이트 API(F6)로 가면 구조적으로 사라진다.

### F5. 반응형 레이아웃 교정이 두 곳에 중복돼 있다 — 사실

| 파일 | 조건 | 동작 |
|---|---|---|
| `src/@core/layouts/Layout.tsx:18` | `hidden` 변화 | `navCollapsed`·`layout`·`lastLayout` 을 saveSettings 로 교정 |
| `src/layouts/UserLayout.tsx:139` | `hidden && layout==='horizontal'` | `layout: 'vertical'` 로 saveSettings |

두 writer 가 같은 키(`layout`)를 각자 판단해 쓴다. 게다가 둘 다 `{ ...settings, ... }` 전체 객체를
넘기므로 서로의 변경을 덮을 수 있다. `Layout.tsx` 는 deps 가 `[hidden]` 뿐이라 `settings` 가 낡는다.

### F6. `saveSettings` 가 전체 객체 교체형이다 — 사실

호출부가 전부 `saveSettings({ ...settings, key: value })` 형태다.
`settings` 스냅샷이 낡으면 그 사이의 다른 변경이 되돌아간다. F4·F5 가 같은 뿌리다.

### F7. AuthGuard 는 인증 확인 전 `fallback` 을 그린다 — 사실

`src/@core/components/auth/AuthGuard.tsx:42` — `return fallback`.
**이 차단 자체는 옳다.** 제거하면 보호 페이지가 순간 노출된다. 바꿀 것은 fallback 의 *모양*뿐이다.

---

## 판단 — 계획서와 다르게 가는 지점

**"전역 스켈레톤을 먼저 제거하고 계측"이 맞다.** 외부 제안의 권장 순서와 같은 결론이며,
근거는 CLAUDE.md 의 P95 ≤ 300ms 규약이다. 300ms 를 지키고 있다면 180ms 지연 스켈레톤은
**대부분의 페이지에서 영원히 나타나지 않는다** — 즉 코드만 늘고 효과는 없다.
계측 없이 지연 스켈레톤부터 넣는 것은 순서가 뒤집힌 것이다.

**쿠키 기반 설정(F3 장기안)은 이번 phase 범위에서 뺀다.** SSR/hydration 계약을 건드리는 변경이라
깜빡임 제거라는 목표에 비해 위험이 크다. 초기 상태 함수(단기안)로 먼저 해결하고,
hydration 경고가 실제로 나오는지 확인한 뒤 별도로 판단한다.

**F4 는 우선순위를 올린다.** 이건 깜빡임이 아니라 **설정이 사라지는 기능 결함**이다.
사용자가 저장한 설정이 특정 페이지에서 무시된다.
