---
phase: 89-qr-public-product-page
plan: 06
subsystem: ui
tags: [nextjs, react, mui, public-page, qr]

# Dependency graph
requires:
  - phase: 89-04
    provides: "GET /public/qr-stock/:storeId/:productId?b=&pt= — QrPublicDto 응답 계약(3갈래 detail/shop_redirect/closed, precioEtiqueta/priceSource/labelMatch)"
provides:
  - "ventago-app/src/pages/m/stock/index.tsx — 죽어 있던 QR 라벨 도착지(https://app.coolsistema.com/m/stock?s=&p=)의 실제 구현. authGuard=false·BlankLayout·raw fetch"
  - "ventago-app/src/views/m-stock/QrProductView.tsx — 8가지 화면 상태(loading/invalid/notfound/error + detail/사진없음/shop_redirect/closed) 전부 빈 화면 없이 렌더"
  - "ventago-app/src/views/m-stock/qr-public.types.ts — 서버 qr-public.dto.ts 를 그대로 옮긴 프론트 타입 계약"
affects: [89-07, 89-08, 89-11]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "공개 페이지는 apiConnector 대신 raw fetch + BlankLayout + authGuard=false (entrega/[token].tsx 와 동일 골격)"
    - "이미지 URL 조립에 encodeURIComponent 적용 — 비ASCII 파일명 보호(89-02 완전 해결과 무관하게 프론트가 취할 수 있는 방어)"
    - "가격 보조 문구 3축(precioEtiqueta·priceSource·labelMatch)을 서로 독립된 조건으로 렌더 — 하나로 뭉치지 않음"

key-files:
  created:
    - ventago-app/src/views/m-stock/qr-public.types.ts
    - ventago-app/src/pages/m/stock/index.tsx
    - ventago-app/src/views/m-stock/QrProductView.tsx
  modified: []

key-decisions:
  - "Task 1 의 plan 지시 주석 원문에 'apiConnector'·'store-theme.service' 리터럴이 그대로 있었으나, 같은 Task 의 acceptance_criteria 는 그 문자열이 0건이어야 한다고 요구해 89-01/89-04 와 같은 형태의 plan 자체 모순이었다 — 의미는 유지하고 표현만 동의어로 교체해 해소"
  - "priceLabel 을 보여주는 '칩'은 plan 이 MUI Chip 컴포넌트를 암시했지만, 같은 Task 의 '허용 컴포넌트는 Box/Paper/Typography/Button/CircularProgress/Alert 뿐' 제약과 충돌해 Chip import 없이 Box+Typography 로 시각적으로 동일한 pill 을 구성"
  - "QrProductView.tsx 를 Task 1 시점에 최소 골격(loading 상태만)으로 먼저 만듦 — next/dynamic(ssr:false) 의 import 대상이 디스크에 없으면 tsc 가 project-wide 로 실패하므로, Task 1 acceptance(tsc 0)를 충족하려면 대상 파일이 먼저 존재해야 했다(Rule 3, blocking)"

requirements-completed: [REQ-01, REQ-03, REQ-06]

# Metrics
duration: 95min
completed: 2026-09-17
---

# Phase 89 Plan 06: QR 도착지 공개 페이지 — 상세/사진없음/목록전환/닫힘 Summary

**`/m/stock?s=&p=&b=&pt=` 공개 페이지 신설 — authGuard 우회 + raw fetch 로 89-04 API 를 불러 8가지 화면 상태(로딩/오류 4종 + 상세/사진없음/목록전환/닫힘)를 빈 화면 없이 렌더, 가격 병기 3축을 독립 조건으로 표시**

## Performance

- **Duration:** 약 95분 (Task 1-2 구현 35분 + Task 3 로컬 실측 및 환경 정리 60분)
- **Started:** 2026-09-16 (KST 심야, 날짜 경계로 커밋 타임스탬프는 2026-09-17 UTC로도 나타남)
- **Completed:** 2026-09-17
- **Tasks:** 3/3 완료
- **Files modified:** 3 (전부 신규)

## Accomplishments
- 운영에서 `https://app.coolsistema.com/m/stock?s=6&p=1` 이 308→404 로 죽어 있던 QR 라벨 도착지를 실제로 여는 페이지 완성 — URL 은 그대로 유지(이미 인쇄된 라벨 보호)
- `authGuard=false`·`guestGuard=false`·`BlankLayout` 명시로 비로그인 시크릿 창에서 `/login` 으로 튕기지 않음을 실제 headless 브라우저로 확인
- 서버 3갈래(`detail`/`shop_redirect`/`closed`) + 클라이언트 4상태(`loading`/`invalid`/`notfound`/`error`) 조합 총 8개 화면을 전부 구현 — 빈 화면으로 끝나는 경로 없음
- 사진 없음(store 9 부모상품 100% 무사진 실측 기준)과 이미지 로드 실패(`onError`)를 모두 "Sin foto" 골드 테두리 자리표시자로 동일하게 처리 — 예외가 아니라 주 경로로 설계
- 가격 보조 문구 3축(precioEtiqueta·priceSource·labelMatch)을 서로 독립된 JSX 조건으로 렌더 — 셋 다 `data-testid` 부여, 일치할 때는 `precioEtiqueta === null` 분기로 **아무것도 렌더하지 않음**(결정 ① 개정, "없음"도 판정 대상)
- `shop_redirect` 는 `target=_blank`+`rel=noopener noreferrer` 링크로 실제 운영 공개몰 도메인(`stock.coolsistema.com`→200, `up.coolsistema.com`→307)에 도달함을 curl 로 직접 확인 — 막다른 CTA 아님
- `closed` 는 매장명·로고 없이 회색 톤 문구만 렌더(서버가 애초에 null 을 주므로 프론트가 가릴 데이터 자체가 없음)

## Task Commits

Each task was committed atomically (서브모듈 커밋 → 슈퍼프로젝트 gitlink 포인터 커밋 순):

1. **Task 1: 응답 타입 + 공개 라우트 껍데기** - `929d91c` (ventago-app, feat) + `ff56597` (root, chore: submodule pointer)
2. **Task 2: 4개 본 화면 — 상세 / 사진없음 / 목록전환 / 닫힘** - `62a4a51` (ventago-app, feat) + `0589c60` (root, chore: submodule pointer)
3. **Task 3: 로컬 실측** - 검증 전용, 소스 변경 없음(아래 참조)

**Plan metadata:** (이 커밋 — SUMMARY + STATE.md + ROADMAP.md)

## Files Created/Modified
- `ventago-app/src/views/m-stock/qr-public.types.ts` - 신규. 서버 `qr-public.dto.ts` 를 그대로 옮긴 `QrPublicMode`/`QrLabelMatch`/`QrPublicProductDto`/`QrPublicDto`/`MStockStatus` 타입
- `ventago-app/src/pages/m/stock/index.tsx` - 신규. `router.isReady` 대기 → `s`/`p`/`b`/`pt` 파싱 → raw fetch → 5가지 로딩 상태를 `QrProductView` 에 props 로 전달. `authGuard=false`·`guestGuard=false`·`BlankLayout`
- `ventago-app/src/views/m-stock/QrProductView.tsx` - 신규. 8개 화면 상태 전부(로딩/잘못된링크/찾을수없음/오류(재시도) + 상세/사진없음/목록전환/닫힘), 가격 보조 문구 3축 독립 렌더, `Sin foto` 자리표시자, `encodeURIComponent` 이미지 URL 조립

## Decisions Made
- **plan 자체 모순 해소(Task 1)**: 지시된 주석 원문의 `apiConnector`/`store-theme.service` 리터럴을 acceptance(0건 요구)와 충돌 없이 의미 보존하며 동의어로 교체
- **Chip 대신 Box+Typography pill**: Task 2 가 "칩으로 표시"를 언급했지만 "허용 컴포넌트는 6개뿐" 제약과 충돌 — Chip import 없이 시각적으로 동일한 pill 을 직접 구성해 두 요구를 모두 충족
- **QrProductView.tsx 선행 골격**: `next/dynamic(() => import(...), { ssr: false })` 의 대상 모듈이 디스크에 없으면 `tsc --noEmit` 이 프로젝트 전역에서 실패하므로, Task 1 커밋에 최소 골격(loading 상태만 렌더)을 포함시켜 Task 1 자체의 acceptance(tsc 0)를 충족시켰다(Rule 3, blocking) — Task 2 가 그 파일을 완성

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - plan 내부 모순] Task 1 주석 리터럴이 acceptance_criteria(0건 요구)와 충돌**
- **Found during:** Task 1 acceptance 검증(grep 체크 실행 중)
- **Issue:** `<action>` 이 지시한 주석 원문에 `apiConnector`·`src/services/store-theme.service.ts` 문자열이 그대로 있었는데, 같은 Task 의 `<acceptance_criteria>`는 `grep -c "apiConnector\|store-theme.service"` 가 0이어야 한다고 요구했다(89-01/89-04 와 동일한 형태의 plan 자체 모순)
- **Fix:** 의미는 그대로 두고 리터럴 문자열만 동의어("인증이 걸린 공용 HTTP 클라이언트", "매장 테마 조회 모듈")로 교체
- **Files modified:** `ventago-app/src/pages/m/stock/index.tsx`
- **Verification:** `grep -c "apiConnector\|store-theme.service"` → 0, 나머지 acceptance 전부 통과, `tsc --noEmit` 0, `eslint` 0
- **Committed in:** `929d91c` (Task 1 커밋)

**2. [Rule 3 - blocking] `next/dynamic` 대상 모듈 부재로 tsc 프로젝트 전역 실패**
- **Found during:** Task 1 acceptance 검증(`npx tsc --noEmit`)
- **Issue:** `pages/m/stock/index.tsx` 가 `dynamic(() => import('src/views/m-stock/QrProductView'), { ssr: false })` 를 참조하지만, plan 의 파일 구분상 그 파일은 Task 2 가 만들 예정이었다. TypeScript 는 dynamic import 라도 컴파일 타임에 모듈 해석을 시도하므로 파일이 없으면 `TS2307` 로 프로젝트 전체 tsc 가 실패한다
- **Fix:** Task 1 커밋에 `QrProductView.tsx` 의 최소 골격(props 타입 정의 + `loading` 상태 렌더만)을 포함시켜 Task 1 자체의 acceptance(tsc 0)를 충족시키고, Task 2 에서 같은 파일을 완성했다
- **Files modified:** `ventago-app/src/views/m-stock/QrProductView.tsx` (Task 1: 최소 골격 생성, Task 2: 전체 완성)
- **Verification:** Task 1: `tsc --noEmit` 0. Task 2: 전체 acceptance grep 항목 전부 통과
- **Committed in:** `929d91c` (Task 1, 골격) / `62a4a51` (Task 2, 완성)

**3. [Rule 1 - 관측 사실] `api-ventago/.env` 가 로컬 DB 오버라이드 도중 원인 불명으로 재작성됨**
- **Found during:** Task 3 로컬 실측(임시 `nest start --watch` 프로세스에 `DATABASE_HOST=127.0.0.1 DATABASE_PORT=5432 ...` 를 shell env var 로 오버라이드해서 기동)
- **Issue:** 오버라이드로 기동한 직후 `api-ventago/.env` 파일 자체가 로컬 값(`DATABASE_NAME=ventago` 등)으로 바뀌어 있었고, 원본(스테이징 값)이 `.env.bak-20260917-staging` 으로 자동 백업돼 있었다. 이 저장소 코드베이스(`src`·`scripts`) 전체를 `grep` 했으나 `.env` 를 쓰는 로직을 찾지 못해 원인 불명
- **Fix:** 백업 파일 내용을 `.env` 로 복원하고 프로세스를 재기동(재기동해야 부팅 시점에 다시 읽은 설정이 실제로 적용됨을 확인) → 원래 스테이징 경로로 정상 복귀 확인(`GET /public/qr-stock/6/19` 가 다시 `500 column ... does not exist` 를 냄 — 이것이 89-01 이전부터의 스테이징 DB 원래 상태다). 백업 파일은 삭제(`.env` 는 gitignore 대상이라 git 영향 없음)
- **Files modified:** `api-ventago/.env` (gitignore 대상, git 추적 안 됨 — 커밋 없음)
- **Verification:** 복원 후 `git status` 클린(api-ventago 서브모듈), 재기동한 프로세스가 스테이징 경로 원래 증상을 재현함을 확인
- **기록:** `.planning/phases/89-qr-public-product-page/deferred-items.md` 에 스테이징 DB 스키마 지연 항목으로 상세 기록(아래 참조)

---

**Total deviations:** 3 auto-fixed (Rule 1 — plan 내부 모순 1건 + 환경 관측사실 기록 1건, Rule 3 — blocking 1건)
**Impact on plan:** 코드·응답 계약·화면 로직은 plan 지시 그대로. 사람이 읽는 주석 표현과 파일 생성 순서만 조정. 로컬 dev 환경(.env)은 원상 복구 완료, 코드베이스 변경 없음.

## Issues Encountered

**로컬 dev API 서버의 기본 DB 경로(`ventago_staging`, SSH 터널)가 89-01/89-03 마이그레이션이 적용 안 된 상태** — 이 plan 의 범위 밖(Scope boundary). `.planning/phases/89-qr-public-product-page/deferred-items.md` 에 `[89-06]` 항목으로 상세 기록. Task 3 의 실측은 명시적 env override 로 Mac 로컬 Postgres(5432, `ventago` — 89-01 이 실제 적용된 DB)를 가리키는 임시 프로세스에서 수행했고, 검증 후 원래 프로세스를 원래 커맨드 그대로 재기동해 스테이징 경로로 복귀시켰다.

## User Setup Required
None - 외부 서비스 설정 불필요.

## ★ Task 3 — 로컬 실측 상세 (관측 기록)

**환경:** api(임시 프로세스, Mac 로컬 Postgres 5432 `ventago` DB 로 override) + app(포트 3050, 기존 실행 중) + Chrome headless(CDP, 무쿠키 임시 프로필 — 시크릿 창과 동등)로 실제 DOM 을 확인.

### 8가지 화면 각각 실제로 확인함

| # | 시나리오 | URL | 관측 |
|---|---|---|---|
| 1 | `invalid` | `/m/stock` (쿼리 없음) | "Enlace incorrecto" — 빈 화면 아님 |
| 2 | `notfound` | `/m/stock?s=6&p=999999` | "Producto no disponible" |
| 3 | `error`(재시도) | 로컬 API 에 스테이징 500 유발 | "No pudimos cargar la información" + Reintentar 버튼(실제 렌더 확인) |
| 4 | `closed` | `/m/stock?s=8&p=21` (store 8, slug 없음+qr off) | "Esta tienda no comparte..." 회색 톤, 매장명/로고/버튼 전부 없음 |
| 5 | `shop_redirect` | `/m/stock?s=9&p=299` (store 9, slug='stock'+qr off) | "Stock" + "Ver catálogo" 버튼(`href=https://stock.coolsistema.com`, `target=_blank`, `rel=noopener noreferrer`) — **curl 로 실제 200 확인, 막다른 CTA 아님** |
| 6 | `detail` 사진 있음 (7a: 일치) | `/m/stock?s=6&p=264` | "cool" + 사진(`<img src=".../minio/macowens-....webp">`) + `$22.000` + `qr-precio-etiqueta` **없음**(precioEtiqueta=null 일치 판정) + `qr-label-latest` 있음 |
| 7 | `detail` 사진 없음 (fallback) | `/m/stock?s=6&p=338` | "Sin foto" 자리표시자 + `qr-precio-referencia` 있음("Precio de referencia...") + `qr-label-latest` **없음**(labelMatch=none) |
| 8 | `detail` 가격 병기 3갈래 | 아래 참조 | — |

### 인증 우회 (T-89-22)
비로그인 헤드리스 브라우저(쿠키 없는 임시 프로필)로 8개 시나리오 전부 실제 콘텐츠가 렌더됨을 확인 — **`/login` 으로 리다이렉트되지 않았다.** `curl -sL "http://localhost:3050/m/stock?s=6&p=1"` 최종 상태코드 **200**.

### 가격 병기 3갈래 (사용자 결정 ① 개정 검증) — `qr_print_log` 시험 행 1건 추가로 만듦
- **7a. 일치 → 없음**: product 264(store 6), 기존 print log(가격 22000 = base 22000) → `hasTestidEtiqueta:false` **확인**(있는 것이 아니라 **없는 것을 확인**)
- **7b. 불일치 → 있음**: product 89 에 시험용 `qr_print_log` 행 추가(branch=6, price_type=12, printed_price=99999, 현재가=38720) → `b`/`pt` 없이 요청 → `precioEtiqueta:99999` 렌더, `labelMatch=latest-print`(구 라벨 취급)
- **7c. b/pt 실으면 확정 → "최신 인쇄분" 문구 사라짐**: 같은 product 89 를 `?b=6&pt=12` 로 요청 → `labelMatch=exact-label`, `qr-label-latest` **사라짐**(precioEtiqueta 는 여전히 표시 — 두 축이 독립임을 실증)

### 테넌트 격리
- `GET /public/qr-stock/6/89?b=6&pt=12` → `branchName: "coolsistema"`(store 6 소속 지점만 이름 노출)
- `GET /public/qr-stock/6/21`(product 21 은 store 8 소속) → `detail` 모드(store 6 이 qr_on)에서 **404** — 자격 미달·교차 테넌트가 같은 404 로 처리됨(89-04 설계 그대로 재확인)

### 로컬 DB 시험용 변경 — 원복 여부
- `store_configs.qr_precio_publico`(store_id=6): 시험을 위해 `true` 로 변경 → **`false` 로 원복 완료**(psql 로 직접 확인)
- `qr_print_log` 시험 행(id=8, branch=6, product=89, price_type=12, printed_price=99999, printed_name='pañuelo k-pop TEST-89-06'): **상시 규칙("테스트로 만든 것은 지우지 않는다")에 따라 삭제하지 않고 유지**. ★ 영향: product 89 의 branch=6/price_type=12 조합에서 다음 QR 인쇄 전까지 "최신 인쇄" 판정은 이 시험 행(99999)을 기준으로 델타(NUEVO/CAMBIO)가 계산된다 — 실제 라벨 인쇄 이력이 아니므로 그 조합에 대한 다음 실측/화면에서 혼동하지 않도록 여기 기록해 둔다.

### 로컬 API 서버 환경
- Task 3 수행을 위해 기존 dev API 프로세스(스테이징 DB 연결, 89-01/89-03 마이그레이션 미적용으로 이 엔드포인트가 500)를 종료하고, `DATABASE_HOST=127.0.0.1 DATABASE_PORT=5432 DATABASE_NAME=ventago ...` 오버라이드로 임시 재기동(Mac 로컬 Postgres, 89-01 적용 완료 DB)해 실측을 수행했다.
- 실측 종료 후 임시 프로세스를 종료하고, 오버라이드 없이 원래 커맨드(`npm run start:dev --workspace=api-ventago`)로 재기동 — **정확히 원래 상태로 복귀**(같은 500 재현으로 확인).
- 이 과정에서 관측된 `.env` 자동 재작성 현상은 위 "Deviations" 3번과 `deferred-items.md` 에 기록.

## Next Phase Readiness
- 89-07(신 라벨 `b`/`pt` 인쇄 흐름 완성)이 이 페이지를 그대로 도착지로 쓸 수 있다 — `labelMatch=exact-label` 비중이 늘어나면 "최신 인쇄분 기준" 문구가 자연히 줄어든다.
- 89-08(reseller 신청·`/register?ref=` CTA)이 이 화면의 "CTA 자리"(현재 의도적으로 비워둠, 주석으로 표시)를 채울 수 있다. `storeApodo` 는 이미 타입·데이터에 있지만 이 plan 에서는 사용하지 않았다(계획대로).
- 89-11(자동화 시험)이 `data-testid="qr-precio-etiqueta"`/`"qr-precio-referencia"`/`"qr-label-latest"` 를 그대로 셀렉터로 쓸 수 있다.
- 블로커 없음. 남은 것은 `deferred-items.md` 의 스테이징 DB 스키마 지연 항목(이 plan 범위 밖)뿐.

---
*Phase: 89-qr-public-product-page*
*Completed: 2026-09-17*

## Self-Check: PASSED

- FOUND: ventago-app/src/views/m-stock/qr-public.types.ts
- FOUND: ventago-app/src/pages/m/stock/index.tsx
- FOUND: ventago-app/src/views/m-stock/QrProductView.tsx
- FOUND: .planning/phases/89-qr-public-product-page/89-06-SUMMARY.md
- FOUND: .planning/phases/89-qr-public-product-page/deferred-items.md
- FOUND commit 929d91c (ventago-app submodule)
- FOUND commit 62a4a51 (ventago-app submodule)
- FOUND commit ff56597 (root)
- FOUND commit 0589c60 (root)
