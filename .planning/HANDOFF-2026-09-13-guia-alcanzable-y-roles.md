# 핸드오프 — 2026-09-12~13 · 셋업 가이드: 도달 가능성과 역할

앞 핸드오프: `HANDOFF-2026-09-11-caja-fuerte-구간과-레거시-임포트.md`

이 세션은 **① 옛 온보딩 투어를 삭제**해 안내를 셋업 가이드 하나로 통일했고,
**② 가이드를 매장을 운영하는 사람에게만** 보이게 했으며,
**③ 그 가이드가 애초에 화면에 나온 적이 없다는 것**을 브라우저 실측으로 찾아 고쳤다.

---

## 0. 배포 상태 — **전부 운영 반영 확인**

| 빌드 | 커밋 | 결과 |
|---|---|---|
| api #896 | `7ab3617` | **SUCCESS** — 역할 게이트 · 투어 백엔드 제거 · CODEX 매장 필터 |
| front #732 | `e4fa8ed` | **SUCCESS** — 사이드바 메뉴 · 되살리기 · 투어 삭제 |
| front #733 | `a27b7ca` | **SUCCESS** — `/auth/me` 재발급 토큰 저장 |
| 루트 | `f6853b9` | 포인터 |

컨테이너 재생성 확인(`ventagoapp`·`api_ventago`) · 재기동 후 SQL 오류 **0건** ·
`app.coolsistema.com` 200 · API 401(정상) · i18n 3개 언어가 운영에서 실제로 내려옴.

★ **미push 없음.** 워킹트리에 남은 것은 이전 세션의 미추적 문서뿐이다.

---

## 1. ★★★ 가장 중요한 발견 — 가이드는 **아무도 본 적이 없었다**

```
/  →  src/@core/components/auth/AclGuard.tsx:38   router.replace(getHomeRoute(roles))
                                                   → '/dashboards/'
   →  src/pages/dashboards/index.tsx               router.replace('/nueva-venta')
```

`AclGuard` 가 `router.route === '/'` 를 **명시적으로 가로채고**, 다음 페이지가
superadmin(→`/dashboards/admin`)을 뺀 **모든 역할**을 POS 로 보낸다. 그 사이
`pages/index.tsx` 는 `<Spinner/>` 만 그린다. 즉 Phase 88 W2(체크리스트)와
W4(빈 상태·EmptyState)는 **배포된 채로 죽은 코드**였다.

★★★ 앞 핸드오프 §10 의 「가이드가 9곳에 보이고 5곳은 자동 숨김」은
  **DB 플래그를 센 것**이지 화면을 본 것이 아니었다. **마운트됨 ≠ 도달 가능.**

**고친 방식** — 리다이렉트는 **건드리지 않았다.** POS 진입 흐름을 바꾸는 쪽이 더
위험하다. 대신 가이드에 **자기 주소 `/guia-configuracion` + 사이드바 메뉴**를 줬다.
`/perfil` 때와 같은 형태다: 없던 것은 기능이 아니라 **찾을 수 있는 자리**였다.

★★ 메뉴 노출 판정에 **역할 목록을 프론트에 적지 않았다.** 서버가 `setupGuide`
  요약을 실어 보냈는지만 본다 — 그 값 자체가 서버의 판정이다. 덕분에 미뤄뒀던
  **CASL subject 시드가 필요 없어졌다.**
★ `useNavigation` 의 `useMemo` 의존성에 `resumenGuia` 를 넣었다. 안 넣으면 숨긴
  뒤에도 낡은 메뉴가 남아 빈 화면으로 보낸다.

---

## 2. 역할 게이트 — 가이드는 **매장을 운영하는 사람**의 것

사용자 결정(2026-09-12): **gerentes · dueño · admin + 지점장**.

**무엇이 문제였나.** 쓰기(`dismiss`·`snooze`·영구닫기)는 이미 관리자 전용인데
**조회는 전원에게 열려 있었다.** 그래서 판매 직원 홈에 「4/8 — 아직 100% 활용
못 하고 있습니다」가 뜨는데 **아무 버튼도 안 눌렸다.** 자기가 할 수 없는 일을
재촉하는 안내는 안내가 아니다.

→ 컨트롤러 **클래스 레벨** `SetupGuideRoleGuard`(조회·쓰기 같은 집합) +
  `/auth/me` 와 로그인 응답 **양쪽**에서 `setupGuide` 를 `null` 로.

★★★ **`ADMIN_ROLES` 에 `branch_manager` 를 직접 넣지 않았다.** 그 집합은
  **레거시 데이터 임포트** 권한과 공유한다 — 넣었다면 지점장이 남의 매장 덤프를
  밀어 넣는 권한까지 얻는다. 요청된 적 없는 확대다. `SETUP_GUIDE_ROLES` 를
  **파생**시키고(`...ADMIN_ROLES` + 한 줄), 검사가 차이가 **정확히 하나**인지 지킨다.

★★ 게이트는 `resolve()` **호출부**에 둔다 — 안에 넣으면 캐시 키가 `store+branch`
  라 **먼저 부른 사람의 역할 결과가 굳는다.**

★ 프론트는 **한 줄도 안 고쳤다**(메뉴 제외). 화면이 이미 요약 하나만 보고 `null`
  이면 아무것도 안 그린다. 비관리자는 SWR 키가 `null` 이라 403 을 볼 일도 없다.

운영 29명 — **볼 수 있는 21명**(관리자 20 + 지점장 1) / **못 보는 8명**
(vendedor 5 · cashier 2 · inventory_clerk 1).

---

## 3. 옛 온보딩 투어 — **삭제**

사용자 지시: 「1번은 없애버려줘. 의미가 없어」 · 「2번 하나로 통일하자고」.

지웠다: `OnboardingTour.tsx`(347줄) · `OnboardingWrapper.tsx` ·
`PUT /auth/onboarding-complete` 본체 · `completeOnboarding()` · `/me` 응답 필드 3곳 ·
`users.model.ts` 의 컬럼 선언 · 프론트 `UserDataType.onboardingCompleted`.

**왜**: ① NN/g 실측상 코치마크 투어는 과제 수행을 개선하지 못한다.
② 2초 지연 때문에 `SelectBoxTerminalModal`·`NoticesBanner` 와 **겹쳤다** —
모달 충돌의 실제 원인이었다. ③ 안내가 두 벌이면 하나도 없는 것보다 나쁘다.

★★★ **DB 컬럼 `users.onboarding_completed` 는 남겼다.** 지금 DROP 하면 배포가
  끝나는 몇 분 동안 아직 도는 구 버전 코드가 SELECT 해서 `users` 조회가 전부
  500 이 된다. 게다가 `store/store-restore-columns.txt` 매니페스트가 이 컬럼을 연다.
★★ **`app/onboarding/` 은 다른 모듈이다** — 공개 가입 OTP(`@Public()`,
  `POST /onboarding/start`). 이름만 같다. 안 건드렸다.
★★ **탈레레스에 동명이인 `OnboardingTour` 가 살아 있다**
  (`src/views/talleres/components/`). 이름으로 일괄 삭제하면 그것까지 지운다.
★ 외부 소비자 전수 확인 — 로컬 8개 저장소 grep 0건(Flutter 포함).

---

## 4. 스테이징 실측 — 환경과 결과

### 환경 (★ 스테이징에 **프론트가 없다**)
`api_staging` 은 2026-08-21 W6 감사용 일회성 컨테이너(정지 상태)이고 스테이징
프론트는 **존재하지 않는다.** 그래서 **로컬 앱(오늘 코드) + SSH 터널 →
`ventago_staging`** 로 검증했다. `api-ventago/.env` 가 이미
`127.0.0.1:15432 → ventago_staging` 을 가리키므로 터널만 열면 된다:

```bash
ssh -N -L 15432:localhost:5434 jhkim-server
cd api-ventago && npm run start:dev     # 5002
cd ventago-app && npm run dev           # 3050
```

★★ **`.planning` 의 스테이징 기록이 낡아 있었다.** §9 는 2,258MB 레거시 이관본
  이라 했는데 **밤에 재생성이 실제로 돌았다** — 지금은 **240테이블(운영과 동일)** ·
  `store_setup_steps`/`_events` 존재 · `sales.total_amount` **double precision**
  (운영과 일치) · 매장 314 · 유저 3,029. **이제 금액 시험도 유효하다.**

**더미 매장**: **320 「Tienda Demo Guia」** / `guia.demo@ventago.test` / `Demo1234`
(신규 가입 흐름 `POST /auth/register` — 기본 지점·카하·터미널이 자동 생성돼
3/8 로 시작하는 진짜 모습이 나온다). **지우지 않고 남겨 뒀다.**

### 확인한 것 (전부 통과)
3/8 · `arranque` 문구 · 「No aplica」 3→4 + 「Deshacer」 4→3 · 「Más tarde」는 목록에서
내려가되 **진행률 유지**(CODEX P2 수정 동작) · 새로고침 후 상태 보존 ·
**CTA 5개 전부 실재 도달**(`/productos` `/precios` `/configuracion?tab=ventas`
`/sucursales` `/nueva-venta`) · `?tab=ventas` 가 **실제로 그 탭을 열고** 기본
결제수단 3개가 있음 · W4 `<EmptyState/>` · **역할 게이트**(cashier→`null` ·
branch_manager→보임 · store_owner→보임) · **옛 투어 안 뜸**.

### 결함 2 — 「Ocultar guía」 직후 **빈 화면** (같이 고침)
숨기면 가이드는 사라지는데 되살리기 링크가 **새로고침 전엔 안 떴다.**
`cerradoPorUsuario` 는 `/auth/me` 요약에서 오는데 숨긴 뒤 그것을 다시 안 받았다.
→ `onOculta` 를 **필수 prop** 으로. 선택이면 빠뜨려도 조용히 그 상태로 돌아간다.

---

## 5. CODEX 자문 — 3라운드, **P2 3건 중 하나는 내 결함**

| 라운드 | 지적 | 판정 | 조치 |
|---|---|---|---|
| 1 | `/me` 의 `verGuia` 만 **매장 필터가 없다** | **내 결함** | `rolesDeLaTienda()` |
| 1 | superadmin 이 집합에 있는데 `/me` 는 늘 `null` | 기존 상태 | 문서화만 |
| 1 | 폐기 계약 즉시 제거 → 배포 창 404 배너 | 맞다 | 한 주기 **no-op** |
| 2 | `/auth/me` **재발급 토큰을 버린다** | 맞다(W2 에서 옴) | `refreshUser()` |
| 2 | 검사가 **작은따옴표만** 읽는다 | 맞다 | 세 종류 + 한계 명시 |
| 2 | `/guia-configuracion` 에 프론트 ACL 없음 | **안 받아들임** | 아래 |

★★★ **매장 필터 누락이 왜 위험했나.** `user_roles` 에는 역할의 매장이 사용자의
  매장과 같아야 한다는 **DB 제약이 없다.** `issueAccessToken` 과 `/me` 의
  `roles_local` 은 이미 거르는데 **내가 넣은 판정만 안 걸렀다** — 같은 응답 안에서
  근거가 둘로 갈렸다. 다른 매장에 `admin` 행이 남은 사용자가 지금 매장의 가이드를
  열람·변경할 수 있었다. 운영 실측 어긋난 행 **0건**이지만, 0건인 것과 막혀 있는
  것은 다르다.

★★ **`/auth/me` 는 새 accessToken 을 재발급한다.** 인터셉터는 localStorage 를
  **읽기만** 하므로, 화면이 직접 부르면 그 토큰을 **버린다.** 만료 임박 사용자가
  「Ocultar guía」를 누르면 6시간짜리 새 토큰을 받고도 원래 만료 시각에 끊긴다.
  ⤷ **새 화면에서 `/auth/me` 를 다시 받을 일이 있으면 `refreshUser()` 를 쓴다.**

★ **안 받아들인 것**: `vendedor` 가 `/guia-configuracion` 주소를 직접 쳐도
  `setupGuide` 가 `null` 이라 **서버 호출조차 안 하고** 환영 문구 한 줄만 나온다.
  CODEX 도 「보안 문제 아님」이라 했고, 역할 집합을 프론트에 복제하는 것은 이번
  변경이 **일부러 피한** 바로 그 일이다.

---

## 6. 새 검사 — 그리고 **무엇을 못 잡는지**

`ventago-app/src/__tests__/menu-paths-exist.spec.ts` —
레지스트리의 모든 `path` 에 페이지 파일이 있는가. 대조군 2개 포함.

★★ **못 잡는 것을 주석에 전부 적었다**: 리다이렉트(**이번에 당한 바로 그것**) ·
  DB(`module.url`)에서 오는 메뉴 · 변수·템플릿 path · 렌더 예외 · ACL ·
  동적/catch-all 라우트. 테스트 이름도 「모든 메뉴 경로」 → 「레지스트리의 모든
  `path`」로 좁혔다 — **이름이 실제 보장보다 넓으면 그 자체가 거짓 안심이다.**

돌연변이로 확인: 페이지 삭제 ⇒ 2건 실패 · 큰따옴표 회피 ⇒ 2건 실패 ·
`puedeVerGuia → true` ⇒ 5건 실패 · `branch_manager` 를 `ADMIN_ROLES` 로 이동 ⇒ 2건 실패 ·
매장 필터 제거 ⇒ 2건 실패.

---

## 7. 다음 세션이 할 일

1. **폐기 no-op `PUT /auth/onboarding-complete` 제거** — 다음 배포 이후 언제든.
   **같이 지울 것**: DB 컬럼 `users.onboarding_completed` ·
   `api-ventago/src/app/store/store-restore-columns.txt` 의 그 줄.
2. **`shapeAuthUser()` 의 `req.user.roles` 에 매장 필터가 없다**
   (`users.service.ts:162`). 가드 둘(`SetupGuideRoleGuard` · **`AdminRoleGuard`
   = 레거시 임포트**)이 그것을 읽는다. 기존 상태이고 **모든 인증 요청**이 타는
   자리(실측 44,231회)라 별건으로 다룰 것.
3. **Phase 88 W3 위저드** — 유일하게 남은 웨이브.
   · **D-22**: 업태를 **저장하지 않고 응답에서도 뺀다.** 위저드 답은 1회용 시드로만.
   · **D-23**: 모드 전환 시 완료·dismiss 승계 → **`store_setup_steps` UNIQUE 키에
     mode 를 넣는 마이그레이션이 필요하다.** 잊지 말 것.
4. (선택) `AclGuard` 가 `/` 를 가로채는 **뿌리**. 홈을 진짜 홈으로 쓸 생각이면
   그때 다뤄야 한다. 지금은 가이드에 자기 주소를 줘서 우회했다.
5. 이월(앞 핸드오프 §7): 업로드 상한 재검토 · 재고 `importar` · 외상·온라인 매퍼 ·
   레거시 임포트 프론트 화면 · CI step 타임아웃 · Phase 87 착수.

★ **영구 제외**(2026-09-11 사용자 결정): 운영 DB 인터넷 노출 · 스테이징 재생성.
  「남은 작업」으로 세지 않는다. (단 스테이징은 **이미 재생성됐다** — §4 참조.)

### 지금 살아 있는 것 (정리하려면 말할 것)
- 스테이징 더미 매장 **320** 과 사용자 `guia.demo@ventago.test`
- 로컬 dev 서버 api(5002)·앱(3050)과 SSH 터널(15432)

---

## 8. 이번에 배운 것

1. **「DB 플래그가 켜져 있다」와 「화면에 보인다」는 다른 사실이다.** 앞 세션이
   전자를 후자로 적었고, 그래서 기능이 **한 달 가까이 죽은 채** 완료로 남아 있었다.
   새 화면은 **브라우저로 직접 도달해 볼 것.**
2. **대조군이 통과하는 것을 또 겪었다.** 역할 게이트 1차 시험은 `set --` 가 라벨을
   SQL 에 넣어 **UPDATE 가 전부 실패했는데 출력은 결과처럼 보였다.** 그리고
   프론트 번들 grep 이 0건이었을 때 «없다»로 읽을 뻔했는데, 대조군을 넣으니
   **grep 자체가 안 돌고 있었다.**
3. **종료코드를 grep 에서 읽었다.** `npx tsc --noEmit | grep -v "npm warn"` 의 `$?`
   는 grep 것이다. 파일로 받고 `$?` 를 읽을 것.
4. **커밋을 쪼개다 중간 상태를 깨뜨릴 뻔했다.** `auth.service.ts` 에 두 변경이
   얽혀 있어 파일 단위로 나누면 「가이드는 뜨는데 API 가 403」이 된다. 한 커밋으로.
5. **서브모듈보다 루트를 먼저 push 했다.** `cd` 실패로 순서가 뒤집혀 잠깐 **없는
   커밋을 가리키는 포인터**가 원격에 있었다. `git -C <sub> push` 로 확실히 할 것.
6. **내가 만든 검사도 돌연변이로 재야 한다.** 「모든 메뉴 경로」 검사가 따옴표
   한 종류만 읽고 있었고, CODEX 가 짚기 전까지 통과만 보고 안심하고 있었다.
