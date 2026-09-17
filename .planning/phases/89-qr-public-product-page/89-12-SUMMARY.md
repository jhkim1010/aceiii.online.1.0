---
phase: 89-qr-public-product-page
plan: 12
subsystem: ui
tags: [nextjs, react, react-hook-form, register, referral, guestGuard]

# Dependency graph
requires:
  - phase: 89-08
    provides: "CTA② 「당신 매장에도 이 시스템을」 링크가 `/register?ref={apodo}` 로 나가는 QR 공개 페이지"
provides:
  - "RegisterForm.tsx — `?ref=` 쿼리로 추천인 apodo 를 프리필하고 기존 blur 검증(checkReferralApodo)을 그대로 태우는 useEffect"
  - "CTA② 도착지 실사용 확인 — 시크릿 브라우저(Chromium, Playwright)로 A~D 케이스 전부 실측, E(guestGuard 리다이렉트)는 모의 세션으로 실측"
affects: [89-08]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Pages Router 에서 router.isReady 이후 1회만 도는 프리필 useEffect + 기존 이벤트 핸들러(checkReferralApodo)를 직접 호출해 프리필 값도 수동 입력과 동일한 검증 경로를 타게 함"

key-files:
  created: []
  modified:
    - ventago-app/src/views/register/components/RegisterForm.tsx

key-decisions:
  - "새 useEffect 는 checkReferralApodo 선언 **뒤**(referralReg 선언 직전)에 둠 — 141행의 setValue 선례 바로 아래에 두면 TDZ(checkReferralApodo 가 아직 선언되지 않음)에 걸리므로, plan 지시대로 '파일 안의 선언 순서를 읽고 위치를 정함'을 실행"
  - "보상 관련 문구는 추가하지 않음 — referral_credits 운영 0행이라 단정할 근거가 없다는 plan/CONTEXT 결정을 그대로 따름. 새로 추가한 코드 주석 안에서만 '50%'를 설명 목적으로 언급했고, 사용자 대면 텍스트(Alert)는 89-이전부터 있던 문구 그대로임(신규 사용자 대면 문구 0건)"
  - "Task 2 검증에서 cmux browser(WKWebView) 가 이 dev 서버의 모든 페이지에서 hydration 이 멈추는 환경 문제를 발견 — RegisterForm.tsx 변경과 무관함(수정 안 한 /login 에서도 재현)을 대조로 확인 후, Playwright(Chromium) 를 스크래치패드에 별도 설치해 실제 검증을 완료함. 이 문제는 deferred-items.md 에 기록(Scope boundary — 고치지 않음)"
  - "E(로그인 상태) 검증은 실 계정 비밀번호를 모르므로 accessToken/sessionToken/userData 를 localStorage 에 심고 /auth/me 를 모의 응답으로 가로채는 방식으로 재현 — sessionToken 없이 시도했을 때는 앱의 전역 401(SESSION_EXPIRED) 인터셉터가 먼저 반응해 /login 으로 갔고, sessionToken 을 추가하자 GuestGuard 의 `router.replace('/')` 가 정확히 관측됨(이후 AclGuard 가 홈에서 추가로 전환하는 것도 관측 — 이 저장소의 기존 '홈은 AclGuard 가 가로챈다' 패턴과 일치)"

requirements-completed: [REQ-08]

# Metrics
duration: 50min
completed: 2026-09-17
---

# Phase 89 Plan 12: 가입 화면 `?ref=` 프리필 — CTA② 도착지 실사용화 Summary

**`RegisterForm.tsx` 에 `?ref=` 쿼리 프리필 `useEffect` 하나만 추가 — 기존 실사용 중인 가입 흐름(운영 `pending_registrations` 9행)을 전혀 건드리지 않고, `/register?ref={apodo}` 로 오는 CTA② 트래픽에 추천인 칸을 자동으로 채우고 기존 blur 검증을 그대로 태운다**

## Performance

- **Duration:** 약 50분
- **Started:** 2026-09-17 (KST 심야, UTC 로그 타임스탬프 사용)
- **Completed:** 2026-09-17
- **Tasks:** 2/2 완료
- **Files modified:** 1

## Accomplishments
- `RegisterForm.tsx` 에 `useRouter` import + `router.query.ref` 를 읽어 `referredByApodo` 를 `setValue` 로 채우는 `useEffect` 추가 — 파일에서 바뀐 곳은 정확히 이 세 군데(import 1 + `useRouter()` 호출 1 + `useEffect` 1)뿐이고, `guestGuard`·OTP·CUIT·주소 단계는 무변경
- 프리필된 값도 `checkReferralApodo()` 를 직접 호출해 **기존 blur 검증을 그대로 통과** — 오타난 apodo 가 조용히 저장되지 않음
- `?ref=` 가 없거나 해석 실패 시 **빈 값**으로 남고 아무 매장으로도 폴백하지 않음(acceptance C 케이스로 확인)
- Task 2 도달성 실측: cmux browser(WKWebView) 가 이 dev 서버(3050) 전 페이지에서 hydration 이 멈추는 환경 문제를 발견했고(무관·pre-existing, deferred-items.md 기록), Playwright(Chromium) 를 대체 경로로 써서 A~E 다섯 관측을 실제로 확보

## Task Commits

Each task was committed atomically (서브모듈 커밋 → 슈퍼프로젝트 gitlink 포인터 커밋):

1. **Task 1: `?ref=` 프리필 — 값을 채우고 기존 검증을 그대로 태운다** - `019205c` (ventago-app, feat) + `345fc5d` (root, chore: submodule pointer)
2. **Task 2: 도달성 실측** - 검증 전용(소스 변경 없음), 아래 관측 A~E 참조

**Plan metadata:** (이 커밋 — SUMMARY + STATE.md + ROADMAP.md)

## Files Created/Modified
- `ventago-app/src/views/register/components/RegisterForm.tsx` - `useRouter` import 추가, `useForm` 선언 뒤 `const router = useRouter()`, `checkReferralApodo` 선언 뒤(TDZ 회피)에 `router.isReady` 를 기다려 `router.query.ref` 를 정규화(`@` 제거)하고 `setValue('referredByApodo', ref, { shouldDirty: false })` + `checkReferralApodo(ref)` 를 1회 호출하는 `useEffect` 추가

## 도달성 실측 — A~E 관측 (Playwright/Chromium, 실 브라우저)

★ 「됐다」가 아니라 무엇이 보였는지를 적는다.

- **A (존재하는 apodo, `/register?ref=cool`, 시크릿 컨텍스트):** 추천인 입력 칸이 `"cool"` 로 채워져 있었고, 화면에 `success` Alert — "Te recomendó jungho K. de coolsistema. Recibirá una bonificación del 50% de un mes de servicio cuando tu registro sea aprobado." 가 렌더됐다(89-이전부터 있던 기존 문구, 이 plan 이 추가한 것 아님).
- **B (없는 apodo, `/register?ref=no-existe-jamas`):** 칸은 `"no-existe-jamas"` 로 채워졌고, `warning` Alert — "No encontramos ninguna tienda con el apodo @no-existe-jamas. Verificá que esté bien escrito e intentá de nuevo. (Podés dejarlo vacío y continuar.)" 가 렌더됐다. 조용히 통과하지 않음을 확인.
- **C (`?ref=` 없음, `/register`):** 칸은 빈 문자열(`""`)이었고, 화면에 Alert 는 0개였다 — `?ref=` 프리필 도입 전과 동일한 상태.
- **D (`/register?ref=%40cool`, 즉 `@cool`):** 칸은 `"cool"`(`@` 제거됨)로 채워졌고, A 와 동일한 success Alert 가 렌더됐다 — `@` 정규화가 실제로 동작함을 확인.
- **E (로그인 상태 모의, `accessToken`+`sessionToken`+`userData` 를 localStorage 에 심고 `/auth/me` 를 200 으로 가로챈 상태에서 `/register?ref=cool` 접속):** 페이지가 `/register` 에 머물지 않고 **`http://localhost:3050/` 로 즉시 이동**했다 — `GuestGuard.tsx` 의 `router.replace('/')` 그대로. 이동 직후 잠시 `document.title` 이 "Loading http://localhost:3050/login/" 로 바뀐 것도 관측됐는데, 이는 이 저장소에 이미 기록된 「홈(`/`)은 AclGuard 가 가로챈다」 패턴과 일치하는 후속 전환으로 보인다(모의 세션이라 실제 권한 데이터가 없어 최종적으로 어디에 정착하는지까지는 이 plan 범위에서 확인하지 않음).
  ⤷ **89-08 에 넘길 정보:** 로그인 상태(자기 매장 직원이 QR 을 찍는 경우 등)에서 CTA② 를 누르면 가입 화면이 아니라 **홈으로 튕긴다.** 89-08 의 CTA 문구가 이 사실(로그인 상태에서는 이 버튼이 가입 화면으로 가지 않는다)을 반영해야 할 수 있다.

## 추가 검증
- `cd ventago-app && npx tsc --noEmit` — 0 (종료코드로 판정)
- `npx eslint src/views/register/components/RegisterForm.tsx` — 0
- `grep -c "useRouter" RegisterForm.tsx` → 2, `grep -c "router.query.ref"` → 1, `grep -c "setValue('referredByApodo'"` → 1, `grep -c "router.isReady"` → 3(가드 1 + useEffect 배열 1 + 콘솔없음이므로 실제로는 조건문+deps 2곳)
- `grep -ci "bonificación\|50%\|recompensa"` → 3건 중 신규 사용자 대면 문구는 0건(1건은 새로 추가한 **코드 주석**, 1건은 기존 Alert, 1건은 `borderRadius: '50%'` 무관 CSS)
- `guestGuard` — `ventago-app/src/pages/register/index.tsx` 에서 여전히 `true`
- `curl http://localhost:5002/api/onboarding/referral/check?apodo=cool` → 200 (`@Public()` 살아있음, 무변경)
- `curl -sL http://localhost:3050/register?ref=cool` → 최종 200

## Deviations from Plan

없음 — plan 이 지시한 세 군데 변경(import 1 + `useRouter` 호출 1 + `useEffect` 1)만 적용했고, 그 외 이 파일의 어떤 부분도 건드리지 않았다.

Task 2 수행 중 예정에 없던 환경 문제(cmux browser/WKWebView 가 이 dev 서버에서 hydration 이 안 끝남)를 만났으나, RegisterForm.tsx 변경과 무관함을 `/login`(무변경 페이지) 대조로 확인했으므로 Rule 1-3 대상이 아니라 **Scope Boundary** 에 따라 고치지 않고 `deferred-items.md` 에 기록만 했다. 검증 자체는 Playwright(Chromium, 프로젝트 파일 변경 없이 스크래치패드에만 설치)로 대체 수행해 완료했다.

## Threat Flags

없음 — 이 plan 은 새 네트워크 표면이나 신뢰 경계를 추가하지 않았다(기존 `@Public()` 엔드포인트를 그대로 재사용).

## Known Stubs

없음.

## Self-Check: PASSED

- FOUND: ventago-app/src/views/register/components/RegisterForm.tsx (수정 확인)
- FOUND: 커밋 019205c (ventago-app 서브모듈 저장소 — `git -C ventago-app log` 로 확인)
- FOUND: 커밋 345fc5d (root 슈퍼프로젝트)
