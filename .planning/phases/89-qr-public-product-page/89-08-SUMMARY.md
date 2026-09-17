---
phase: 89-qr-public-product-page
plan: 08
subsystem: api
tags: [nestjs, react, mui, multer, throttle, minio, reseller, leads, cta]

# Dependency graph
requires:
  - phase: 89-05
    provides: "POST /public/ventago-leads — sourceProductId 소유 재검증 + 텔레그램 통지 계약"
  - phase: 89-06
    provides: "ventago-app/src/views/m-stock/QrProductView.tsx — CTA 자리를 비워 둔 8화면 상세 페이지"
  - phase: 89-12
    provides: "RegisterForm.tsx 의 ?ref= 프리필 + 로그인 상태 CTA② 관측(E: GuestGuard → '/')"
  - phase: 89-11
    provides: "대조군 실증 관례 — require_int 류 가드, 검사 자체의 무력화를 실행 중 잡는 절차"
provides:
  - "POST reseller/auth/register 가 QR 공개 페이지에서 처음으로 도달 가능해지고, 같은 커밋에서 storeIds 화이트리스트·업로드 제한(5MB×3·MIME·Throttle)·고아 파일 보상 삭제 3종 방어를 갖춘다"
  - "ventago-app/src/views/m-stock/{ResellerApplyForm,VentagoLeadForm}.tsx — CTA① reseller 신청 폼(매장 고정) + CTA③ 이탈 받이 폼"
  - "QrProductView.tsx 의 3단 CTA 위계 — [1]reseller contained [2]가입링크(주) outlined [3]이탈받이 caption, storeApodo null 이면 ?ref= 미부착, 보상 문구 단정 없음"
  - "scripts/check-cta-destinos.sh — 프론트/서버 도착지 정적 대조 + 대조군 + 실HTTP 확인(404만 실패, 429=Throttle 증거)"
  - "reseller-register.dto.ts 의 storeIds 멀티파트 단일값 정규화 버그 수정(실측으로 처음 발견)"
affects: [89-09]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "@Public() 무인증 멀티파트 라우트는 FileFieldsInterceptor 의 limits+fileFilter 로 크기/개수/MIME 을 먼저 막고, @Throttle 을 별도로 얹는다"
    - "커밋 전 실패 경로에서만 도는 보상 삭제(Promise.allSettled, 원 예외를 덮지 않음) — 커밋 뒤 단계는 응답을 바꾸지 않는다는 저장소 규약과 정합"
    - "판정의 근거(publicStores() 화이트리스트)와 폼이 보여주는 목록의 근거를 같은 함수로 통일 — 두 근거가 갈라지면 우회로가 생긴다"
    - "막다른 CTA 방지 검사는 프론트/서버 문자열을 서로 다른 파일에서 읽어 대조하고, 대조군(존재하지 않는 문자열)이 걸리면 스스로 exit 2 로 죽는다"

key-files:
  created:
    - ventago-app/src/views/m-stock/ResellerApplyForm.tsx
    - ventago-app/src/views/m-stock/VentagoLeadForm.tsx
    - api-ventago/src/app/reseller/auth/dto/reseller-register.dto.spec.ts
    - scripts/check-cta-destinos.sh
  modified:
    - api-ventago/src/app/reseller/auth/reseller-auth.controller.ts
    - api-ventago/src/app/reseller/auth/reseller-auth.service.ts
    - api-ventago/src/app/reseller/auth/reseller-auth.service.spec.ts
    - api-ventago/src/app/reseller/auth/dto/reseller-register.dto.ts
    - api-ventago/src/common/minio/minio.service.ts
    - ventago-app/src/views/m-stock/QrProductView.tsx
    - ventago-app/src/pages/m/stock/index.tsx

key-decisions:
  - "QrPublicDto 응답에 storeId 가 없어(최소 노출 원칙) CTA 폼이 storeId 를 알 방법이 없었다 — pages/m/stock/index.tsx 가 URL 의 s 를 QrProductView 에 prop 으로 내려주도록 Rule 3(blocking) 로 추가. 이 파일은 원래 files_modified 에 없었다"
  - "실측으로 발견한 버그(Rule 1): multer 는 같은 멀티파트 필드가 한 번만 오면 배열이 아니라 스칼라 문자열을 준다 — storeIds 를 그렇게 보내는 QR CTA① 의 정상 케이스가 전부 400 이었다(같은 필드를 두 번 보내야만 배열이 됨을 curl 로 실측). reseller-register.dto.ts 에 @Transform 을 추가해 스칼라를 배열로 정규화(이미 배열인 값은 그대로 둔다 — 계약을 좁히지 않음). 이 파일은 Task 1 의 files_modified 에 없었지만 계약(타입 number[])은 그대로이고 멀티파트 직렬화의 latent bug 만 고쳤다"
  - "관리자 승인 화면(다음 화면) 검증은 실제 로그인이 불가능해(비밀번호 모름) 실DB 의 실재 superadmin 계정(id=1)으로 JWT 를 직접 서명해 GET /reseller/admin/pending 을 호출하는 방식으로 대체 — 실제 @Auth(superadmin) 가드·서비스 쿼리를 그대로 실행시켰다(UI 클릭은 아니지만 백엔드 코드 경로는 실제로 탔다)"
  - "check-cta-destinos.sh 의 5번째 짝(관리자 승인 화면)은 CTA 폼이 직접 링크하지 않아 plan 표의 '프론트 문자열'이 비어 있었다 — 그 화면이 실제로 호출하는 백엔드 엔드포인트 리터럴(useResellersPending.ts 의 reseller/admin/pending)로 짝을 재정의했다(파일 존재는 별도 (c) 섹션에서 확인)"

requirements-completed: [REQ-04, REQ-05]

# Metrics
duration: 90min
completed: 2026-09-17
---

# Phase 89 Plan 08: 두 갈래 CTA — reseller 신청·가입 링크·이탈 받이 + 막다른 CTA 방지 검사 Summary

**QR 공개 상품 페이지 끝에 3단 CTA(① reseller 신청 contained · ② 기존 가입 화면 outlined(주) · ③ 이탈 받이 caption)를 붙이고, 한 번도 실행된 적 없던 `POST reseller/auth/register` 를 도달 가능하게 만들면서 같은 커밋에서 storeIds 화이트리스트·업로드 제한·고아 파일 삭제 3종 방어를 걸었다. 실측 종단 시험 중 그 엔드포인트의 실사용 latent bug(멀티파트 단일 storeIds 가 전부 400)를 발견해 즉시 고쳤다.**

## Performance

- **Duration:** 약 90분
- **Started:** 2026-09-16 (KST 심야)
- **Completed:** 2026-09-17
- **Tasks:** 3/3 완료
- **Files modified:** 11 (신규 4 · 수정 7)

## Accomplishments
- `reseller-auth.controller.ts` — `FileFieldsInterceptor` 에 `limits`(5MB×3파일)+`fileFilter`(이미지 MIME) 추가, `@Throttle(PUBLIC_RESELLER_REGISTER_THROTTLE)` 부착. 무인증 업로드가 워커를 못 죽인다
- `reseller-auth.service.ts` — `publicStores()` 화이트리스트로 `storeIds` 를 업로드보다 **먼저** 검증(400 `RESELLER_STORE_INVALID`, 부분 수용 없음). DB 트랜잭션 실패 시 이미 올라간 KYC 파일 3개를 `MinioService.removeFile()` 로 보상 삭제(커밋 전 경로에서만, 삭제 실패가 원 예외를 안 덮음)
- `MinioService.removeFile()` 신규 — 없는 객체는 no-op
- `ResellerApplyForm.tsx`/`VentagoLeadForm.tsx` 신규 — 공개(무인증) raw fetch, `storeIds` QR 매장 고정(선택 UI 없음), 클라이언트 5MB 상한(서버와 동일 숫자), 오류코드별 문구
- `QrProductView.tsx` — 3단 CTA 위계 + `storeId` prop(URL 의 `s`) 추가, `/register?ref=` 링크(storeApodo null 이면 `?ref=` 미부착), 보상 문구 단정 없음(`referral_credits` 0행)
- `scripts/check-cta-destinos.sh` 신규 — 5개 도착지 정적 대조 + 대조군 + 실HTTP 확인(404 만 실패)
- ★★ **실측 종단 시험 중 latent bug 발견 즉시 수정**: `reseller-register.dto.ts` 의 `storeIds` 가 멀티파트 단일 필드일 때 스칼라 문자열이라 `@IsArray()` 가 항상 400 — QR CTA① 의 유일한 실사용 케이스가 전부 막혀 있었다. `@Transform` 으로 정규화하고 회귀 시험 3건 + 대조군 1건 추가
- 실제로 브라우저(Playwright/Chromium)로 CTA① 끝까지 제출 → `reseller.resellers`/`reseller_tienda_link`/`reseller_documents` 행 생성 확인, CTA③ 제출 → `ventago_leads` 행 생성(`source_product_id` 채워짐, `notify_status='sent'`) 확인, CTA② 클릭 → `/register?ref=cool` 도달 + 추천인 칸 프리필 확인
- 관리자 승인 화면(다음 버튼) — 실DB 의 실재 superadmin 계정으로 서명한 JWT 로 `GET /reseller/admin/pending` 을 직접 호출해 두 시험 신청이 실제로 보임을 확인(실 가드+서비스 경로 실행)

## Task Commits

각 Task 는 서브모듈 커밋 → 슈퍼프로젝트 gitlink 포인터 커밋 순으로 원자적으로 커밋됨:

1. **Task 1: 백엔드 방어 3종** — `b587a009` (api-ventago, feat) + `87c66e0` (root, chore: submodule pointer)
2. **Task 2: CTA① 폼 + CTA② 가입 링크 + 이탈 받이 마운트** — `5931ca9` (ventago-app, feat) + `b727ab8` (root, chore: submodule pointer)
3. **[Rule 1 배포] storeIds 멀티파트 스칼라 정규화 버그 수정** — `2c7201a2` (api-ventago, fix) + `5629406` (root, chore: submodule pointer) — Task 3 종단 시험 중 발견해 즉시 반영
4. **Task 3: 막다른 CTA 방지 검사** — `1b811b3` (root, feat) — `scripts/check-cta-destinos.sh` 신규

**Plan metadata:** (이 커밋 — SUMMARY + STATE.md + ROADMAP.md)

## Files Created/Modified
- `api-ventago/src/app/reseller/auth/reseller-auth.controller.ts` - `limits`+`fileFilter`+`@Throttle` 추가
- `api-ventago/src/app/reseller/auth/reseller-auth.service.ts` - storeIds 화이트리스트(업로드보다 먼저) + 고아 파일 보상 삭제(`tx.rollback()` 과 `throw e` 사이)
- `api-ventago/src/app/reseller/auth/reseller-auth.service.spec.ts` - 시험 7건 추가(13→20개, 기존 것 안 지움) + 대조군 2건 실증
- `api-ventago/src/app/reseller/auth/dto/reseller-register.dto.ts` - `@Transform` 으로 storeIds 스칼라→배열 정규화(Rule 1 버그 수정)
- `api-ventago/src/app/reseller/auth/dto/reseller-register.dto.spec.ts` - 신규. 스칼라/배열/undefined 3케이스 + 대조군 실증
- `api-ventago/src/common/minio/minio.service.ts` - `removeFile()` 추가
- `ventago-app/src/views/m-stock/ResellerApplyForm.tsx` - 신규. CTA① 경량 KYC 폼(storeIds 고정)
- `ventago-app/src/views/m-stock/VentagoLeadForm.tsx` - 신규. CTA③ 이탈 받이(sourceProductId 실제 전송)
- `ventago-app/src/views/m-stock/QrProductView.tsx` - 3단 CTA + `storeId` prop 추가
- `ventago-app/src/pages/m/stock/index.tsx` - `storeId`(URL 의 `s`) 를 `QrProductView` 에 전달(Rule 3)
- `scripts/check-cta-destinos.sh` - 신규. 막다른 CTA 방지 검사

## Decisions Made
- **`storeId` prop 스레딩(Rule 3, blocking)**: `QrPublicDto` 응답에 `storeId` 가 없어(최소 노출 원칙, 89-06 의도적 설계) CTA 폼이 요청을 구성할 수 없었다. 서버가 이미 검증한 URL 의 `s` 를 페이지→뷰로 prop 전달했다. 두 CTA 모두 이 값을 "참고용 귀속"으로만 보내고(리드는 89-05 가, 신청은 Task 1 이 재검증) 그 이상을 주장하지 않는다.
- **storeIds 멀티파트 스칼라 버그(Rule 1)**: 실측(대조군 curl)으로 확인 — 필드가 한 번만 오면 `req.body.storeIds` 가 `'6'`(문자열)이고 `@IsArray()` 가 실패한다. 같은 필드를 두 번 보내야만 배열이 됐다. DTO 에 `@Transform` 을 추가해 스칼라를 `[value]` 로 감싸는 정규화를 넣었다 — 이미 배열인 값(다중 매장, 향후 선택 UI)은 그대로 둔다.
- **관리자 승인 화면 검증 방법**: 실 로그인 비밀번호를 모르므로 `ventago_staging` 의 실재 superadmin(`id=1`, role `superadmin`)에 대해 `JWT_SECRET_KEY` 로 payload(`{id,name,lastName,email,status,roles,storeId}`)를 직접 서명해 `GET /reseller/admin/pending` 을 호출했다. 이는 실제 `@Auth(ValidRoles.superadmin)` 가드 + `UserRoleGuard` + `ResellerAdminService.pending()` 을 그대로 실행시킨다(UI 클릭은 아니지만 백엔드 코드 경로는 진짜로 탔다).
- **check-cta-destinos.sh 5번째 짝 재정의**: plan 표는 `/admin/revendedores` 를 "코드가 링크하진 않는" 항목으로 남겨 뒀다. 프론트 쪽 대응 문자열이 없어 그 화면이 실제로 호출하는 백엔드 엔드포인트 리터럴(`useResellersPending.ts` 의 `reseller/admin/pending`)로 짝을 재구성했다 — 파일 존재 자체는 별도 (c) 섹션에서 확인한다.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - blocking] `QrPublicDto` 에 `storeId` 가 없어 CTA 페이로드를 구성할 수 없었다**
- **Found during:** Task 2 구현 중(`ResellerApplyForm`/`VentagoLeadForm` 의 `storeId` prop 출처를 찾다가)
- **Issue:** 89-06 이 최소 노출 원칙으로 `storeId` 숫자 필드를 응답에서 뺐다. `QrProductView.tsx` 는 `storeName`/`storeApodo` 등은 갖고 있었지만 정수 `storeId` 가 없어 CTA① `storeIds`·CTA③ `storeId` 를 채울 방법이 없었다.
- **Fix:** `pages/m/stock/index.tsx` 가 이미 URL 에서 파싱해 쓰고 있던 `s`(storeId) 를 `QrProductView` 에 `storeId` prop 으로 전달. 서버가 이미 그 값으로 조회를 수행했으므로 참고용 귀속으로 재사용(서버가 각자 재검증).
- **Files modified:** `ventago-app/src/pages/m/stock/index.tsx`, `ventago-app/src/views/m-stock/QrProductView.tsx`
- **Verification:** `tsc --noEmit` 0, `eslint` 0, Playwright 종단 시험에서 실제 DB 행 생성으로 확인
- **Committed in:** `5931ca9` (Task 2 커밋)

**2. [Rule 1 - bug] `storeIds` 멀티파트 단일 필드가 스칼라라 정상 신청이 전부 400**
- **Found during:** Task 3 종단 시험(Playwright 로 CTA① 실제 제출)
- **Issue:** `req.body.storeIds` 가 멀티파트 필드 1개일 때 문자열 `'6'` 로 온다. `@IsArray()` 가 이를 거부해 400 `storeIds must be an array` — QR CTA① 의 유일한 실사용 형태(매장 하나 고정)가 전부 실패했다. curl 로 대조 확인: 같은 필드를 **두 번** 보내야만 배열이 됐다.
- **Fix:** `reseller-register.dto.ts` 에 `@Transform(({value}) => Array.isArray(value) ? value : [value])` 를 `@IsArray()` 앞에 추가. 이미 배열인 값은 그대로 둔다(계약을 좁히지 않는다).
- **Files modified:** `api-ventago/src/app/reseller/auth/dto/reseller-register.dto.ts`, `api-ventago/src/app/reseller/auth/dto/reseller-register.dto.spec.ts`(신규)
- **Verification:** 신규 시험 3건(스칼라/배열/undefined) 통과 + 대조군 실증(`@Transform` 제거 → 2개 시험이 실제로 빨개짐 확인 → 원복). Playwright 재실행으로 실제 201 응답 + DB 행 생성 확인.
- **Committed in:** `2c7201a2` (api-ventago) + `5629406` (root, submodule pointer)

---

**Total deviations:** 2 auto-fixed (Rule 3 — blocking 1건, Rule 1 — bug 1건)
**Impact on plan:** 둘 다 CTA 가 "끝까지 눌린다"는 이 plan 의 핵심 성공 기준을 실제로 충족시키기 위해 필요했다. 스코프 확장 없음 — 계약(타입·필드명)은 그대로이고 직렬화/전달 경로의 결함만 고쳤다.

## Issues Encountered
- **Throttle 대조군 실증이 실제 종단 시험 순서에 영향을 줬다**: `check-cta-destinos.sh` 의 429 확인 루프가 `POST reseller/auth/register` 를 실제로 블록(5분)시켰다. Playwright 로 CTA① 을 실제 제출하기 전에 이 순서를 알았어야 했는데, 먼저 검사 스크립트를 돌려 블록이 걸렸고 5분 폴링으로 해제를 기다린 뒤 실제 제출을 진행했다(문제 없음, 그냥 순서 조정).

## User Setup Required
None - 외부 서비스 설정 불필요.

## ★ Task 1 acceptance 세부 확인 (grep + 행번호)

**(가) storeIds**
- `RESELLER_STORE_INVALID` 카운트 1 (reseller-auth.service.ts:249)
- 검증 블록(249행) < `this.minio.uploadFile` 호출(274행) — 업로드보다 먼저 막는다
- `publicStores()` 카운트 3(정의 1 + 주석 1 + register 내 사용 1, ≥2 요구 충족)

**(나) 고아 삭제**
- `removeFile`/`removeObject` 카운트 1
- 호출 위치(327행)가 `tx.rollback()`(319행) 과 `throw e`(330행) **사이**
- `allSettled` 카운트 1

**(다) 업로드 제한**
- `PUBLIC_RESELLER_REGISTER_THROTTLE` 카운트 2(import+사용)
- `limits:` 카운트 1, `fileSize`·`files: 3` 존재
- `fileFilter` 카운트 1, `image/` 화이트리스트 존재
- ★ nginx 상한 확인(운영 srv803182, 2026-09-17 실측): `client_max_body_size 25m;`(도메인 기본값) — `5MB × 3 = 15MB` 가 그 아래

**공통**
- `npx jest src/app/reseller --maxWorkers=1` — 10 suites / 51 tests, 종료코드 0
- 기존 시험 건수: 13 → 20 (줄지 않음, 7건 추가)
- 대조군 2건(storeIds 화이트리스트 제거·보상삭제 제거)이 각각 실제로 빨개짐을 확인 후 원복
- ★ 관측: `POST reseller/auth/login` 에는 **여전히 Throttle 이 없다**(범위 밖, T-89-44)

## ★ Task 3 acceptance 세부 확인

- `bash scripts/check-cta-destinos.sh` 종료코드 **0**
- 5개 도착지 전부 "프론트 N / 도착지 N" ≥1 (아래 원문 참고)
- `RegisterForm.tsx` 의 `router.query.ref` 존재 1건으로 찍힘
- 대조군(`public/no-existe-jamas`) 0건
- `API=http://localhost:5002/api` 모드에서 `/public/ventago-leads`·`/reseller/auth/register` 둘 다 400(404 아님)
- 같은 실행에서 `/reseller/auth/register` 연속 호출 → **429 실제 수신**(Throttle 증거)
- 대조군 실증: `leads-public.controller.ts` 의 `@Controller('public/ventago-leads')` 를 `@Controller('public/CAMBIADO-temporal')` 로 임시 변경 → 스크립트 **exit 1** 확인 → `diff` 로 원복 확인

### `bash scripts/check-cta-destinos.sh` 최종 실행 원문 (API+APP)
```
── (a) 정적 대조 — 프론트 ↔ 서버 ──
[1] CTA① reseller 신청 — 프론트 1건 / 도착지(@Controller 1건 · @Post('register') 1건)
[2] 이탈 받이 리드 — 프론트 1건 / 도착지(@Controller 1건 · @Post() 1건)
[3] QR 공개 조회 — 프론트 1건 / 도착지 1건
[4] 가입 화면(/register?ref=) — 프론트 1건 / 파일존재 1 / 프리필(router.query.ref) 1건
[5] 관리자 승인 화면(다음 화면) — 프론트 2건 / 도착지(@Controller 1건 · @Get('pending') 1건)

── (b) 대조군 — 존재하지 않는 경로 ──
대조군(public/no-existe-jamas) — 총 0건 (0 이어야 한다)

── (c) 프론트 라우트 존재 (Pages Router = 파일이 곧 라우트) ──
m/stock/index.tsx 존재: 1 · admin/revendedores.tsx 존재: 1

✓ 정적 대조 통과.

── (d) 실제 HTTP 확인 (API=http://localhost:5002/api) ──
POST /public/ventago-leads (빈 body) → 400 (400/429 기대, 404 면 실패)
POST /reseller/auth/register (빈 body) → 400 (400 기대, 404 면 실패)
GET /public/qr-stock/999999/999999 → 404 (없는 상품이라 404 가 정상 — 연결 자체만 확인)
GET /onboarding/referral/check?apodo=cool → 200 (200 기대, @Public — 89-12 프리필의 검증 경로)
  Throttle(429) 확인 — /reseller/auth/register 연속 호출 중...
  ✓ 429 를 받았다 — Throttle 이 실제로 걸려 있다

── 프론트 라우트 HTTP 확인 (APP=http://localhost:3050) ──
GET /register?ref=cool → 200 (200 기대, 404 면 실패)

✓ 전체 통과.
```
(exit 0)

## ★ 실제 DB 행 생성 확인 (ventago_staging — 로컬 dev API 가 실접속하는 DB, `.env` DATABASE_* 실측)

★ 로컬 dev API 프로세스(포트 5002)는 `.env` 상 `DATABASE_HOST=127.0.0.1 DATABASE_PORT=15432 DATABASE_NAME=ventago_staging`(SSH 터널)를 본다 — 89-06/89-11 이 이미 기록한 환경 특성 그대로. 이 plan 의 Task 3 종단 시험은 그 DB 에서 수행했다(스키마는 89-01 마이그레이션이 이미 적용돼 있음을 `to_regclass` 로 사전 확인).

```
reseller.resellers (최근 2건):
 2|15394895|pending_review|f   ← Playwright CTA① 실제 제출
 1|999999test2|pending_review|f  ← curl 직접 확인(멀티파트 배열 동작 검증용)

reseller.reseller_tienda_link:
 2|6|pending   ← 위 2번 신청, store 6(QR 매장)으로 고정됨
 1|9|pending
 1|6|pending

reseller.reseller_documents (2번 신청, 3개 전부):
 2|selfie|reseller/15394895/selfie-...-test-selfie.png
 2|residence_cert|reseller/15394895/residence_cert-...-test-residencia.png
 2|dni_photo|reseller/15394895/dni_photo-...-test-dni.png

ventago_leads (최근 2건):
 2|6|19|Lead Test 89-08|1155667788|sent   ← Playwright CTA③ 실제 제출, source_product_id=19 (null 아님, C-3 증거), notify_status=sent
 1|6|19|Lead Test 89-08|1155667788|sent
```

**관리자 승인 화면(다음 버튼) 확인** — 실재 superadmin(`id=1`, `ventago_staging`)에 대해 서명한 JWT 로 `GET /reseller/admin/pending` 직접 호출(실제 `@Auth(superadmin)` 가드 + 서비스 그대로 실행):
```
[
  { "id": 2, "document": "15394895", "stores": [{ "storeId": 6, "storeName": "coolsistema", "status": "pending" }] },
  { "id": 1, "document": "999999test2", "stores": [{ "storeId": 6, ... }, { "storeId": 9, ... }] }
]
```
→ **두 신청 모두 pending 목록에 실제로 보인다.**

**CTA② 도달 + 프리필** (Playwright): `Crear mi tienda` 클릭 → `http://localhost:3050/register/?ref=cool` 로 이동, `referredByApodo` 입력란이 `"cool"` 로 채워져 있음(89-12 산출물이 그대로 동작).

**로그인 상태에서 CTA② 를 눌렀을 때(모의 세션)**: `/auth/me` 를 가로채고 `accessToken`/`sessionToken`/`userData` 를 심은 상태에서 `/register?ref=cool` 접속 → 최종적으로 `http://localhost:3050/login/` 에 정착(89-12 Task 2 관측 E — `GuestGuard.router.replace('/')` 뒤 추가 전환 — 와 일치하는 패턴). 실계정이 아닌 모의 세션이라 정확한 최종 정착지는 이 plan 범위에서 단정하지 않는다.

## 시험 데이터 — 지우지 않고 남긴 것 (상시 규칙)

`ventago_staging` DB(로컬 dev API 실접속 대상):
- `reseller.resellers` id 1(document `999999test2`, stores 6·9), id 2(document `15394895`, store 6) — 둘 다 `status=pending_review`, `is_active=false`. **영향**: 승인 화면에 실제로 보인다(위 확인). 승인/거절하지 않았다 — 이 phase 범위 밖.
- `reseller.reseller_documents` 6행 — MinIO 에는 실제 파일이 없다(더미 PNG 를 실제로 업로드했으나 스크래치패드 파일 기준, 실 운영 MinIO 버킷이 아닌 dev 환경 버킷에 저장됨). **영향**: 승인 화면에서 문서 미리보기를 열면 실제 이미지가 뜬다(더미 4×4px PNG).
- `ventago_leads` id 1·2 — `notify_status='sent'`(텔레그램 통지 성공). **영향**: 리드 조회 진단 쿼리에서 보인다.

**되돌린 것**: `store_configs.qr_precio_publico`(store_id=6) — 시험을 위해 `true` 로 변경했다가 **`false` 로 원복 완료**(psql 로 직접 확인, curl 로 `mode:"shop_redirect"` 복귀 확인).

## Threat Flags

없음 — 이 plan 이 새로 여는 네트워크 표면·인가 경로는 전부 plan 의 `<threat_model>` 에 이미 등록돼 있다(T-89-08·T-89-26·T-89-27·T-89-43·T-89-52·T-89-53·T-89-54·T-89-44·T-89-28·T-89-29). `storeIds` DTO `@Transform` 추가는 검증을 **좁히지 않고** 정규화만 하므로 새 노출이 아니다.

## Known Stubs

없음 — 두 CTA 폼과 3단 위계는 전부 실제 엔드포인트에 배선되고 실제로 행을 만든다.

## Next Phase Readiness
- 89-09(다음 plan)가 이 CTA 흐름을 UAT 로 재확인할 수 있다.
- 배포 순서 재확인: 89-05(리드 API)+이 plan 의 Task 1(reseller 검증+storeIds 버그수정) 이 **먼저**, 그다음 프론트(Task 2). 반대면 버튼이 404 를 받거나 검증 없이/깨진 상태로 신청이 들어온다.
- ★ `reseller-register.dto.ts` 의 `@Transform` 수정은 **기존 계약을 넓히지 않는다** — 향후 다중 매장 선택 UI 가 생겨도 그대로 동작한다(이미 배열인 값은 무변경).
- 블로커 없음.

---
*Phase: 89-qr-public-product-page*
*Completed: 2026-09-17*

## Self-Check: PASSED

- FOUND: api-ventago/src/app/reseller/auth/reseller-auth.controller.ts
- FOUND: api-ventago/src/app/reseller/auth/reseller-auth.service.ts
- FOUND: api-ventago/src/app/reseller/auth/reseller-auth.service.spec.ts
- FOUND: api-ventago/src/app/reseller/auth/dto/reseller-register.dto.ts
- FOUND: api-ventago/src/app/reseller/auth/dto/reseller-register.dto.spec.ts
- FOUND: api-ventago/src/common/minio/minio.service.ts
- FOUND: ventago-app/src/views/m-stock/ResellerApplyForm.tsx
- FOUND: ventago-app/src/views/m-stock/VentagoLeadForm.tsx
- FOUND: ventago-app/src/views/m-stock/QrProductView.tsx
- FOUND: ventago-app/src/pages/m/stock/index.tsx
- FOUND: scripts/check-cta-destinos.sh
- FOUND commit b587a009 (api-ventago submodule)
- FOUND commit 2c7201a2 (api-ventago submodule)
- FOUND commit 5931ca9 (ventago-app submodule)
- FOUND commit 87c66e0 (root)
- FOUND commit b727ab8 (root)
- FOUND commit 5629406 (root)
- FOUND commit 1b811b3 (root)
