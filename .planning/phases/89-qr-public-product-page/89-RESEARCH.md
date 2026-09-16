# Phase 89: 상품 QR → 공개 상품 페이지 + 두 갈래 CTA — Research

**Researched:** 2026-09-16
**Domain:** Next.js Pages Router 공개 페이지 + NestJS `@Public()` API + 기존 알림 유틸 재사용
**Confidence:** HIGH (전부 이 저장소의 코드/설정/운영 DB 를 직접 확인 — 추측 없음)

## Summary

이 phase 의 4개 핵심 질문에 전부 코드·설정·운영 조회로 답이 났다. **Q1(도착지)은 이미 저장소
안에 실사용 중인 동일 패턴(`entrega/[token].tsx`)이 있어 그대로 복제하면 된다** — 새 인프라
(nginx 변경) 없이 Next.js 공개 페이지 파일 하나만 추가하면 된다. **Q2(이미지)는 이미
공개다** — `MinioController.getImage`가 `@Public()`이고 실측 curl 200 을 받았다. 단, store 9
는 부모상품 이미지가 0/15로 "사진 없음" 화면이 필수다. **Q3(reseller 신청)는 백엔드 API 는
완성돼 있고 승인 화면(`/admin/revendedores`)도 실재하지만, 신청자가 쓰는 폼이 어디에도 없다**
— 그래서 운영 0행이다. **Q4(리드 수집)는 완전히 새로 만들어야 하지만, 알림 통로
(`notifyTelegram`)는 이미 있어 "받는 곳"을 새로 짓지 않고 재사용할 수 있다.**

**Primary recommendation:** `/m/stock` 은 ventago-app 에 `src/pages/m/stock/index.tsx` 로
공개 페이지를 추가한다(옵션 ⓐ). nginx/인프라 변경 불필요. reseller CTA 는 기존
`POST reseller/auth/register`(다중 파일 업로드 KYC)를 그대로 쓰되 `storeIds`를 QR 의 매장
하나로 고정한 경량 폼을 새로 만든다. 리드 CTA 는 새 테이블 + `notifyTelegram()` 재사용으로
최소 코드로 "사람이 실제로 보는" 경로를 만든다.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| `/m/stock` 공개 페이지 렌더 | Frontend Server (Next.js Pages Router, ventago-app) | — | Q1 — 기존 `entrega/[token].tsx` 선례와 동일 호스트(app.coolsistema.com), `getLayout`+`authGuard=false` 로 사이드바 없이 SSR-free CSR 렌더 |
| 공개 상품 조회 API | API / Backend (NestJS `@Public()`) | — | `qr_print_log`+`products`+`prices` 조인은 DB 접근이 필요해 API 계층 소유. `storeId`는 서버가 강제(테넌트 가드 무력화 보완) |
| 상품 이미지 서빙 | API / Backend (MinioController, 이미 `@Public()`) | CDN 아님(직접 서빙) | Q2 — 이미 존재. 신규 작업 없음 |
| reseller 신청 폼(신규) | Frontend Server (Next.js 공개 페이지) | API(`reseller/auth/register` 기존) | Q3 — 폼만 신규, 백엔드 계약은 기존 DTO 그대로 재사용 |
| reseller 승인 콘솔 | Frontend Server(관리자 앱, 이미 존재) + API(이미 존재) | — | 신규 작업 없음(`/admin/revendedores`) |
| Ventago 리드 수집(신규) | API / Backend(신규 테이블+엔드포인트) | 알림: 기존 `notifyTelegram` 유틸 | Q4 — 저장 없이 텔레그램만 보내면 유실 위험(전송 실패 시 흔적 없음) → 최소 테이블 필요 |
| 설정 스위치(④, 가격 공개 여부) | API / Backend(`store_configs` 확장) | Frontend(Configuración 화면) | 기존 `store_configs` boolean 명명 규약을 그대로 따름 |

## Q1. `/m/stock` 을 어디서 서빙할 것인가

### 확인한 것

1. **308 의 정체**: `curl -sI https://app.coolsistema.com/m/stock?s=6&p=1` → `308` +
   `location: /m/stock/?s=6&p=1`. 이건 nginx 가 아니라 **Next.js 자체의
   `trailingSlash: true`** 정규화다 — 근거: `ventago-app/next.config.js:123`
   `trailingSlash: true`(주석 99-102: `/api/csp-report`도 같은 이유로 308 을 낸다고 이미
   문서화돼 있음). `curl -sL`로 리다이렉트를 따라가면 최종 **404**(페이지 파일이 없어서
   Next 자체 404).
2. **동일 패턴이 이미 운영 중**: `ventago-app/src/pages/entrega/[token].tsx:247`
   `EntregaPage.authGuard = false` (+ `guestGuard = false`). 실측:
   `curl -sI https://app.coolsistema.com/entrega/test123` → 동일하게 308 →
   `/entrega/test123/`, `curl -sL` → **200**(유효하지 않은 token 이어도 페이지 자체는
   렌더된다 — 에러 얼럿을 보여주는 UI로 처리). 즉 **로그인 없이 열리는 페이지의 실전
   선례가 이미 있고 정상 동작 중이다.**
3. **AclGuard/AuthGuard 차단 지점**: `ventago-app/src/pages/_app.tsx:247`
   `const authGuard = Component.authGuard ?? true` — **기본값이 true**라서 아무 설정도
   안 하면 `AuthGuard`(`src/@core/components/auth/AuthGuard.tsx`)가 `auth.user === null`
   일 때 `/login`으로 즉시 `router.replace`한다. `AclGuard`
   (`src/@core/components/auth/AclGuard.tsx`)는 Phase 65 이후 **권한 판정을 하지 않는다** —
   `router.route === '/'`일 때 로그인 사용자를 역할별 홈으로 보내는 것만 한다(★ CONTEXT가
   경고한 "홈(`/`) 라우트를 AclGuard 가 가로챈 전례"는 `/` 경로 전용 로직이라
   `/m/stock`에는 적용되지 않는다 — 확인 완료, 이 페이지는 안전하다).
   → 결론: `Component.authGuard = false`만 명시하면 AuthGuard/AclGuard 둘 다 우회된다.
   `entrega/[token].tsx`가 실제로 이 경로로 동작 중임을 위 curl 결과가 증명한다.
4. **레이아웃**: `entrega/[token].tsx:245` `EntregaPage.getLayout = (page) =>
   <BlankLayout>{page}</BlankLayout>` — 사이드바/네비게이션 없는 순수 페이지.
   같은 `BlankLayout`을 재사용하면 된다.
5. **API 호출 방식(중요 함정, 기존 주석)**: `entrega/[token].tsx:7-9` —
   `apiConnector`를 쓰지 않는다. 그 인스턴스는 401 을 만나면 `/login`으로 보낸다
   (`api.service.ts`의 전역 인터셉터). 공개 페이지가 그 인터셉터를 타면 **고객이
   로그인 페이지로 튕긴다.** 그래서 `fetch()`를 직접 쓴다. `/m/stock` 페이지도
   동일하게 **raw `fetch`**를 써야 한다(재상속 필수 규약).
6. **nginx**: `ssh jhkim-server`로 `/etc/nginx/sites-enabled/app.coolsistema.com.conf`
   확인 — `location /` 하나만 있고 전부 `proxy_pass http://127.0.0.1:5001`(ventago-app
   컨테이너)로 넘어간다. 경로별 분기가 전혀 없다. 옵션 ⓑ(nginx가 `/m/stock`만 api로
   프록시)를 하려면 **새 `location` 블록을 추가**하고 순서(정확 매치 `location =`가
   prefix보다 먼저 평가됨)까지 신경 써야 하며, 이건 운영 nginx 설정 변경 + reload가
   필요한 **인프라 작업**(승인·재시작 필요, CLAUDE.md 규칙상 사용자 확인 필수)이다.
7. **api 가 이미 공개 HTML을 직접 서빙하는 선례도 있다**: `GET /api/public/shop/:storeId/store`
   (`api-ventago/src/app/shop-public/shop-storefront.controller.ts`)가
   `@Header('Content-Type','text/html')`로 문자열 HTML을 반환. 하지만 이건
   **newapi.coolsistema.com** 호스트고, QR 의 `PUBLIC_WEB_URL` 기본값은
   `https://app.coolsistema.com`(`api-ventago/src/app/print/print.service.ts:197,300`
   하드코딩 fallback)이다. app 호스트에서 api 호스트로 실제 리다이렉트를 태우려면
   또 다른 홉이 늘거나 nginx 프록시가 필요해 ⓑ와 같은 비용이 붙는다.

### 판단

- **URL 을 바꾸지 않는다**는 전제(라벨 보존)와 **가장 적은 인프라 변경**이라는 두 기준
  모두에서 ⓐ가 압도적으로 유리하다. ⓑ는 동작은 하지만 운영 nginx 설정 변경(승인 필요,
  실수 시 app.coolsistema.com 전체 장애 위험)이 필요하고, ⓒ(그 외 — 예: 별도 서브도메인)
  는 QR 이 이미 인쇄된 라벨과 호스트가 달라져 URL 변경과 동급의 위험이 있다.
- ⓐ의 유일한 비용은 "308 한 홉"인데, 이건 이미 `/entrega`, `/api/csp-report` 등 앱
  전역에 존재하는 **알려진, 감수된 비용**이다(주석으로 이미 문서화돼 있음). 새로운
  리스크가 아니다.
- AclGuard 의 `/` 전용 리다이렉트 로직은 `/m/stock`과 무관함을 코드로 확인했으므로
  ★ CONTEXT 의 경고("홈 라우트 가로챈 전례")는 이 경로에는 적용되지 않는다 — 다만 앞으로
  이 페이지에 사이드바 레이아웃(`UserLayout`)을 실수로 쓰면 다른 전역 리다이렉트 로직에
  걸릴 수 있으니 **반드시 `BlankLayout`을 명시**할 것.

### 권장

`ventago-app/src/pages/m/stock/index.tsx` 신설:
- `authGuard = false`, `guestGuard = false`
- `getLayout = page => <BlankLayout>{page}</BlankLayout>`
- 데이터 fetch 는 `apiConnector` 대신 raw `fetch()`(entrega 패턴 그대로) — 신규 공개 API는
  아래 Q1 부속 엔드포인트(`GET /public/qr-stock/...` 또는 유사)로 설계, 401 인터셉터를
  절대 타지 않게 한다.
- 인프라(nginx) 변경 없음 — 이 phase 의 작업은 전부 코드 배포로 끝난다.

## Q2. 상품 사진을 공개로 보여줄 수 있는가

### 확인한 것

1. **코드**: `api-ventago/src/common/minio/minio.controller.ts:91-105`
   `@Public() @Get(':filename') getImage(...)` — 인증 없이 열린다. 단
   `isPubliclyServable()`(:34-46)가 `.csv/.xlsx/.pdf/...` 같은 비이미지 확장자와
   슬래시 포함 경로(`talleres/qc/...` 등 내부 파일)를 차단한다. 상품 이미지는
   `{sku}_{ts}` 형태(슬래시 없음)라 이 필터를 통과한다(주석 :30-31에 명시).
2. **실측 curl**: 운영 DB에서 store 6 상품 이미지 파일명 3개를 뽑아
   `curl -o /dev/null -s -w '%{http_code}' "https://newapi.coolsistema.com/api/minio/<filename>"`
   → **200** (두 파일 모두, 공백 포함 파일명도 URL 인코딩 후 200).
3. **이미지 없는 상품 비율(운영 DB, `is_parent=true` 기준)**:
   - store 9 (`stock`, slug 있음): 부모상품 15개 중 `image_url` 있음 **0개(0%)**,
     `image_urls` 배열도 0개.
   - store 6 (`cool`, slug 있음): 부모상품 20개 중 `image_url` 있음 **7개(35%)**.
   - 쿼리: `SELECT store_id, count(*), count(image_url), count(*) FILTER
     (WHERE image_urls IS NOT NULL AND jsonb_array_length(image_urls)>0) FROM products
     WHERE store_id IN (6,9) AND is_parent=true GROUP BY store_id;`
4. **필드**: `products.image_url`(단일, varchar255) + `products.image_urls`(jsonb 배열,
   대표 이미지가 배열 첫 요소인 경우가 많음 — `shop-catalog.service.ts`의
   `ShopProductDto`도 둘 다 노출). 이미지 URL 조립 규약은 CLAUDE.md 그대로
   `{API_HOST}/minio/{fileName}`.

### 판단

- 공개 여부는 **이미 해결돼 있다.** 새 인증 우회 코드 불필요.
- store 9 는 **부모상품 사진이 0%** — "사진 없음" 화면(플레이스홀더)이 옵션이 아니라
  **필수**다. `image_url`과 `image_urls[0]` 둘 다 null 인 경우를 명시적으로 처리해야
  한다.
- store 6 도 65% 는 사진이 없어, 두 매장 모두 "사진 없음"은 흔한 케이스로 설계해야
  한다(예외 케이스로 취급하면 안 됨).

### 권장

공개 상품 API 응답에 `imageUrl: string | null`(1장만, `image_url` 우선 →
`image_urls[0]` 폴백)을 명시적으로 내려주고, 프론트는 null 일 때 브랜드 톤(다크
네이비+골드)의 자리표시자를 렌더한다. `shop-catalog.service.ts`의 `ShopProductDto`
필드 선택 패턴(명시적 컬럼 나열, `SELECT *` 금지)을 그대로 복제할 것 — CLAUDE.md의
"무엇이 새로 나가나" 원칙과 일치.

## Q3. reseller 신청 경로가 실제로 도는가

### 확인한 것

1. **`POST reseller/auth/register` 구현**
   (`api-ventago/src/app/reseller/auth/reseller-auth.controller.ts:33-51` +
   `reseller-auth.service.ts:216-291`):
   - `@Public()`, `multipart/form-data`. 요구값: `name, phone, document, password(≥6자),
     storeIds: number[]` + **파일 3개 필수**(`dniPhoto, residenceCert, selfie` — 하나라도
     없으면 400 `RESELLER_DOCS_REQUIRED`). 이건 KYC 급 심사 폼이다 — QR 을 찍은
     사람이 그 자리에서 셀피와 거주증명서를 올릴 것이라 기대하기 어렵다.
   - `email = ${document}@app`(가짜 이메일 자동생성). `document` 중복이면 409
     `RESELLER_DUPLICATE`(`findOne` 후 `create` — DB에도 `resellers_document_key`
     UNIQUE 인덱스 실재, `ssh` 조회로 확인: `resellers_document_key`,
     `resellers_email_key`). TOCTOU 레이스는 DB 유니크가 최종 방어하지만, 경합 시
     unhandled 500(친절한 409 아님) — 낮은 우선순위 결함.
   - 파일은 MinIO 업로드 후(트랜잭션 밖) DB 트랜잭션에서
     `resellers`(status: `'pending_review'`, `isActive: false`) +
     `reseller_documents` + `reseller_tienda_link`(`status: 'pending'`, storeIds
     각각)를 커밋.
2. **매장 연결**: `dto.storeIds: number[]`(다중 선택) → `reseller_tienda_link`에
   매장마다 한 행씩(status `'pending'`) bulkCreate. 즉 **매장별 신청 개념이 이미
   구조에 있다** — QR 페이지에서는 이 배열을 `[해당 storeId]` 하나로 고정하면 된다.
3. **승인 화면은 이미 존재한다(CONTEXT 의 "화면 없음" 주장과 다른 지점 확인 필요)**:
   `ventago-app/src/pages/admin/revendedores.tsx` → `WithAccess allowedApps={["admin"]}`
   로 게이트된 `RevendedoresView`가 `useResellersPending()` 훅으로
   `GET /reseller/admin/pending`을 부르고, `RevendedorReviewDrawer.tsx:75,97`가
   `PATCH /reseller/admin/:id/approve`, `/reject`를 호출한다. 백엔드
   `reseller-admin.controller.ts`도 `@Auth(ValidRoles.superadmin)`로 이 두 엔드포인트를
   제공한다. **이 화면은 실재하고 배선돼 있다.**
4. **없는 것은 "신청자용 입력 폼"이다.** 저장소 전체(`ventago-app`, `admin-app`,
   `despacho-app`, `edge-agent`, `mobile-sales-app`, `print-agent`, `tienda-admin-app`,
   `zebra-agent`)에서 `reseller/auth/register` 또는 `reseller/auth/login`을 호출하는
   프론트 코드가 **0건**(grep 결과 `api-ventago` 자체 코드/스펙 외에는 없음, 유일한
   외부 참조는 `.worktrees/phase88-api`의 백엔드 서비스 파일 자체). 즉 **API는 완성돼
   있지만 그걸 부르는 화면이 어디에도 없다.** 이게 운영 0행의 진짜 원인이다.
5. **운영 데이터**: `reseller.resellers` 0, `reseller.reseller_tienda_link` 0,
   `reseller.reseller_documents` 0 (모두 재확인). `ResellerModule`은
   `app.module.ts:337`에 등록돼 활성 상태 — 죽은 모듈이 아니라 **호출된 적 없는
   모듈**이다.
6. **이름 충돌 주의(함정)**: `api-ventago/src/app/reseller/`(새 `reseller` 스키마,
   위에서 다룬 것)와 별개로 `api-ventago/src/app/revendedor/`라는 **완전히 다른
   레거시 모듈**이 존재한다(`revendedor-auth.service.ts`,
   `revendedor-auth.controller.ts`). `reseller.model.ts:10` 주석이 직접 명시:
   "Phase 24 reseller 스키마. legacy `public.revendedores` 와 별개." 이름이
   스페인어/영어로만 다를 뿐 실제로는 두 개의 독립된 재판매자 시스템이다 — 이번
   phase 의 CTA①은 **`reseller` 스키마(새 것)**를 써야 하며, `revendedor`(레거시)와
   혼동하면 안 된다.

### 판단

- "화면이 없어 0행"이라는 CONTEXT 의 결론은 **부분적으로만 맞다.** 정확히는:
  **승인 화면(관리자용)은 있다. 신청 화면(고객용)이 없다.** 이 구분이 W4 작업량
  산정에 중요하다 — 관리자 콘솔은 재사용, 신청 폼만 신규.
- 기존 `register()` DTO(3개 파일 필수 업로드)를 QR 페이지에 그대로 노출하면
  이탈률이 높을 것이다(찍고 나서 셀피까지 그 자리에서 요구하는 것은 마찰이 크다).
  다만 이 phase 의 성공 판정은 "CTA 를 끝까지 눌러 실제 화면에 도달"이지 "전환율
  최적화"가 아니므로, **기존 DTO 그대로 재사용해도 요구사항은 만족한다** — UX 비교는
  범위 밖.

### 권장

- 새 공개 페이지(`/m/stock` 또는 그 하위)에서 CTA① 클릭 시 기존
  `POST reseller/auth/register` 폼(파일 3개 포함)을 **그 매장 storeId 로 고정**해
  보여주는 경량 프론트만 신규 작성. 백엔드는 무변경.
- 신청 후 안내 문구는 "심사 중 — 승인/거부는 관리자가 `/admin/revendedores`에서
  처리"로 명확히 하고, 신청자 쪽엔 진행 상태를 알 방법이 없다는 점(로그인 포털 부재)도
  같이 인지시킬 것(CONTEXT 도 "reseller 포털 없음"으로 이미 명시).
- `reseller` vs `revendedor` 이름 혼동 방지를 위해 코드 주석에 명시적으로
  스키마를 표기할 것(기존 `reseller.model.ts:10` 관례를 따름).

## Q4. 리드(Ventago 잠재고객) 수집을 어디에 붙일 것인가

### 확인한 것

1. **비슷한 것**: `api-ventago/src/app/onboarding/`가 "신규 매장 가입" 전체 흐름을
   갖고 있다 — `pending-registration.model.ts`(가입 폼 임시 저장,
   `tableName: 'pending_registrations'`), `onboarding-alta.service.ts`,
   `onboarding-approval.service.ts`, `onboarding-verification.service.ts`.
   이건 우리가 찾는 "리드"보다 훨씬 무거운 완결형 가입(CUIT·주소·관리자 계정 생성)
   이라 QR 페이지에서 그대로 쓰긴 과하지만, **알림 패턴**은 그대로 재사용 가치가
   있다.
2. **알림 유틸이 이미 있다**:
   - `api-ventago/src/common/telegram/telegram.ts` — `notifyTelegram(text, {dedupKey,
     chatId})`(fire-and-forget), `sendTelegramMessageDetailed()`가 4가지 결과
     (`sent/deduplicated/unconfigured/failed`)를 구분해 반환. `TELEGRAM_BOT_TOKEN`/
     `TELEGRAM_CHAT_ID` env 미설정이면 조용히 스킵하되 로그는 남긴다(★ 이 저장소
     메모리 "감시 장치는 부재에서 침묵한다" — 이 유틸은 그 교훈을 이미 반영해 결과
     타입을 구분해 두었다).
   - 실사용 예: `onboarding-alta.service.ts:218` — 신규 가입 승인 대기 알림을
     운영자 텔레그램 채널로 보낸다. HTML 파싱 모드로 매장명/CUIT/담당자 정보를
     포맷.
   - `api-ventago/src/common/mail/mail.ts` — `sendMail()`(Resend HTTP API, 캠페인/OTP용),
     `sendMailWithAttachmentSmtp()`(nodemailer, 영수증 PDF 첨부용). 이메일 발송도
     이미 준비돼 있다.
3. **받는 쪽(사람이 실제로 보는 화면)**: 텔레그램 채널로 보내면 운영자가
   **이미 보고 있는 채널**(신규 가입·에러 알림과 같은 채널)에 그대로 도착한다 —
   새 UI(관리자 리드 목록 화면)를 만들지 않아도 "사람이 실제로 본다"는 성공 조건을
   만족할 수 있다.
4. **저장 없이 텔레그램만 보내는 것의 위험**: `notifyTelegram`은 실패 시
   `'failed'`를 반환하지만 저장소가 없으면 **재시도·이력 조회가 불가능**하다.
   `PUBLIC_DELIVERY_THROTTLE`(`throttle.constants.ts:72-78`, 분당 20회) 같은
   rate limit 정책도 이미 상수화돼 있어 그대로 재사용 가능.

### 판단

- "아무것도 없다"는 CONTEXT 의 결론은 맞다 — 리드 저장 테이블도, 리드 전용 알림도
  없다. 하지만 **알림 배선(텔레그램/메일)과 그 상수(throttle)는 이미 있어서, 신규
  코드는 "테이블 하나 + 엔드포인트 하나 + notifyTelegram 호출 한 줄"로 최소화된다.**
  새 관리자 UI를 만들 필요는 없다(성공 조건이 "사람이 본다"이지 "전용 대시보드"가
  아니므로).
- 저장을 아예 생략하고 텔레그램만 보내면 "받는 사람이 그 순간 못 보면 영구 유실"이라는
  리스크가 있다(CONTEXT 의 "받는 곳이 없으면 수집은 사라진다"는 지적과 같은 함정을
  텔레그램 단독으로도 재현할 수 있다). 최소 테이블 저장 후 알림이 안전하다.

### 권장

- 최소 스키마 1개 신설(예: `ventago_leads`: id, storeId(어느 매장 QR 인지),
  contactName, contactPhone/email, sourceProductId, createdAt) — 무중단 규약(신규
  테이블이라 W4 예외 대상, 락 걱정 없음)에 따라 additive로 추가.
  `POST /public/ventago-leads`(`@Public()`, `Throttle` — `throttle.constants.ts`에
  `PUBLIC_DELIVERY_THROTTLE`과 같은 형태로 `PUBLIC_LEAD_THROTTLE` 신설 권장)로
  저장 후 `notifyTelegram()` 한 번 호출(운영자 기본 채널, dedupKey는 리드 id 기준
  — 중복 방지).
  메일 발송은 1차 범위에서 생략 가능(텔레그램만으로 "사람이 본다" 조건 충족,
  `mail.ts`는 향후 확장 시 재사용).

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Next.js (Pages Router) | 13.x (레포 고정) | `/m/stock` 공개 페이지 | 이미 `entrega/[token].tsx`가 동일 요구사항을 이 프레임워크로 풀고 있다 [VERIFIED: 코드] |
| NestJS 11 + `@Public()` 데코레이터 | 레포 고정 | 공개 상품 조회 API, 리드 저장 API | 기존 `MinioController`, `PublicDeliveryController`, `ShopCatalogController` 전부 이 패턴 [VERIFIED: 코드] |
| `@nestjs/throttler` | ^6.5.0 | 공개 엔드포인트 rate limit | `PUBLIC_DELIVERY_THROTTLE` 선례 그대로 재사용 [VERIFIED: package.json] |
| Sequelize + sequelize-typescript | 레포 고정 | `qr_print_log`/`products`/`prices` 조인, 신규 `ventago_leads` 모델 | 프로젝트 전역 ORM, `underscored: true` [CITED: CLAUDE.md] |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `notifyTelegram` (자체 유틸) | 사내 코드 | 리드 발생 알림 | `api-ventago/src/common/telegram/telegram.ts` — 신규 작성 불필요, import 만 |
| MUI 5 | 레포 고정 | 공개 페이지 UI(entrega 패턴과 동일 톤) | `Box/Paper/Typography/Button`, BlankLayout |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| ⓐ Next.js 공개 페이지 | ⓑ nginx 프록시로 `/m/stock`만 api 로 | ⓑ는 운영 nginx 설정 변경+reload 필요(승인·장애위험), ⓐ는 코드 배포만으로 끝남 — ⓐ 채택 |
| 신규 `ventago_leads` 테이블 | 텔레그램 알림만(저장 없음) | 저장 없으면 실패 시 유실·재시도 불가 — 테이블 채택 |
| 신규 reseller 신청 API | 기존 `reseller/auth/register` 그대로 | 새 API 를 또 만들 이유가 없다 — 기존 DTO 그대로 재사용, storeIds 고정만 프론트에서 처리 |

**버전 확인:** 이 phase 는 신규 npm 패키지 설치가 필요 없다(전부 레포에 이미 설치된
패키지 재사용). `npm view` 확인 생략.

## Architecture Patterns

### System Architecture Diagram

```
[고객 스마트폰 카메라]
        │ QR 스캔 (기존, 변경 없음)
        ▼
https://app.coolsistema.com/m/stock?s={storeId}&p={parentProductId}
        │ 308 (Next.js trailingSlash — 기존에도 있는 비용, 신규 아님)
        ▼
Next.js Pages Router ─ src/pages/m/stock/index.tsx (신규, authGuard=false)
        │ raw fetch() — apiConnector 아님 (401→/login 인터셉터 회피)
        ▼
NestJS API ─ GET /public/qr-stock/:storeId/:productId (신규, @Public())
        │
        ├─ qr_print_log 최신 1건 JOIN products(store_id 강제) → price_type_id 확정
        │     └─ 없으면: base 가격 폴백 + "가격 일치 보장 없음" 플래그
        ├─ store_configs.qr_precio_publico 확인(신규 플래그, 기본 false)
        │     └─ false 면 가격 필드 생략(상품명·사진만)
        ├─ stores.slug 확인 → 있으면(공개몰 ON) 관련 카테고리 링크 노출 가능
        │     └─ 없으면(공개몰 OFF) 이 상품 1개만
        └─ MinioController(:filename) — 이미 @Public() — 사진 서빙
        ▼
페이지 렌더: 매장·지점·사진(or 자리표시자)·가격(or 숨김)
        │
        ├─ CTA① "이 매장의 reseller 신청" → 신규 경량 폼
        │       → POST /reseller/auth/register (기존, storeIds=[storeId] 고정)
        │       → reseller.resellers(pending_review) + reseller_tienda_link(pending)
        │       → 승인: 기존 /admin/revendedores (WithAccess allowedApps=["admin"])
        │
        └─ CTA② "당신 매장에도?" → 신규 경량 폼
                → POST /public/ventago-leads (신규, @Public())
                → ventago_leads 테이블 INSERT (신규)
                → notifyTelegram() (기존 유틸 재사용, 운영자 채널)
```

### Recommended Project Structure
```
ventago-app/src/pages/m/stock/
└── index.tsx                     # 공개 페이지 (authGuard=false, BlankLayout)

ventago-app/src/views/m-stock/    # (선택) 뷰 분리 시
├── QrProductView.tsx
├── ResellerApplyForm.tsx         # CTA① 경량 폼(storeIds 고정)
└── VentagoLeadForm.tsx           # CTA② 리드 폼

api-ventago/src/app/print/        # 기존 모듈에 공개 조회 엔드포인트 추가
└── qr-public.controller.ts       # 신규 — GET /public/qr-stock/:storeId/:productId

api-ventago/src/app/leads/        # 신규 모듈
├── lead.model.ts
├── leads.module.ts
└── leads-public.controller.ts    # POST /public/ventago-leads
```

### Pattern 1: 공개 페이지 = authGuard/guestGuard 명시 + BlankLayout + raw fetch
**What:** Next.js 페이지 컴포넌트에 `authGuard = false`, `guestGuard = false`를 static
프로퍼티로 붙이고, 데이터 요청은 `apiConnector`(401→로그인 인터셉터 보유) 대신 순수
`fetch()`를 쓴다.
**When to use:** 로그인 없이 열려야 하는 모든 고객 대면 페이지(이번 phase, 향후 유사
기능 전부).
**Example:**
```typescript
// Source: ventago-app/src/pages/entrega/[token].tsx (실사용 중, 신규 아님)
const API_HOST =
  process.env.NODE_ENV === 'development' ? 'http://localhost:5002/api' : 'https://newapi.coolsistema.com/api'

const post = async (path: string, body: Record<string, unknown>) => {
  const res = await fetch(`${API_HOST}/public/entrega/${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body)
  })
  // ...
}

Page.getLayout = (page: ReactNode) => <BlankLayout>{page}</BlankLayout>
Page.authGuard = false
Page.guestGuard = false
```

### Pattern 2: 공개 API 는 `@Public()` + storeId 강제 + rate limit
**What:** 테넌트 가드가 무력화되므로 컨트롤러/서비스 레벨에서 `storeId`를 쿼리 조건에
직접 박는다. 목록 열거가 아닌 단건 조회에도 `@Throttle`을 건다.
**Example:**
```typescript
// Source: api-ventago/src/app/online-orders/public-delivery.controller.ts (실사용 패턴)
@Controller('public/entrega')
export class PublicDeliveryController {
  @Public()
  @Throttle(PUBLIC_DELIVERY_THROTTLE)
  @Post('consultar')
  async consultar(@Body() body: { token?: string }) {
    return this.service.getPublicDelivery(body?.token ?? '');
  }
}
```

### Anti-Patterns to Avoid
- **`apiConnector` 를 공개 페이지에서 쓰기**: 401 시 `/login`으로 튕겨 고객이 영영
  페이지를 못 연다(entrega 페이지 주석이 이미 경고). 반드시 raw `fetch`.
- **`qr_print_log`를 `product_id`만으로 조회**: `store_id` 컬럼이 없어 테넌트를
  넘을 수 있다. 항상 `products` JOIN 으로 `store_id` 강제.
- **`SELECT *`로 공개 응답 구성**: `ShopCatalogService.getProductBySlug`가 보여주는
  것처럼 필드를 명시적으로 나열할 것 — 원가·공급처·내부 SKU 접두사(`str_prefix`) 등을
  실수로 흘리지 않는다.
- **reseller 신청 폼을 `reseller`가 아닌 `revendedor`(레거시) 엔드포인트로 잘못
  연결**: 이름이 비슷해 혼동하기 쉽다. 반드시 `reseller.model.ts`가 명시한 "Phase 24
  reseller 스키마"를 쓸 것.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| 신규 채널로 신규 알림 발송기 만들기 | 새 텔레그램/메일 클라이언트 | `notifyTelegram()`, `sendMail()`(기존 유틸) | dedup·타임아웃·실패 로깅이 이미 구현돼 있고 전 사이트에서 검증됨 |
| 이미지 공개 서빙 로직 | 새 공개 이미지 프록시/CDN 설정 | 기존 `MinioController.getImage` (이미 `@Public()`) | 이미 존재, 확장자 화이트리스트까지 구현됨 |
| reseller 신청 계정/문서 저장 로직 | 새 회원가입 플로우 | 기존 `reseller/auth/register` DTO/서비스 | 이미 트랜잭션·중복 체크·MinIO 업로드까지 완비 |
| rate limit 정책 | 새 in-memory 리미터 | `@nestjs/throttler` + `throttle.constants.ts`의 `toInt(...)` 패턴 | env 로 재정의 가능한 기존 규약과 어긋나면 운영 튜닝 시 혼란 |

**Key insight:** 이 phase 는 "새 기능"이 거의 없다 — 기존 조각(공개 페이지 패턴, 공개
이미지, reseller 백엔드, 텔레그램 유틸)을 **연결만** 하면 된다. 새로 만들 것은
QR 조회 API 1개, reseller 신청 프론트 폼 1개, 리드 테이블+API+폼 1개뿐이다.

## Common Pitfalls

### Pitfall 1: `authGuard` 기본값을 빠뜨림
**What goes wrong:** `Component.authGuard`를 명시하지 않으면 기본값 `true`가 적용돼
비로그인 사용자가 QR 을 찍자마자 `/login`으로 튕긴다.
**Why it happens:** `_app.tsx:247`의 `?? true` 기본값을 모르고 넘어가기 쉽다.
**How to avoid:** 페이지 파일 최하단에 `Page.authGuard = false; Page.guestGuard = false`를
반드시 명시(entrega 페이지가 정확히 이렇게 함).
**Warning signs:** 로컬에서 로그인된 브라우저로 테스트하면 증상이 안 보인다 — 반드시
시크릿 창(비로그인)으로 검증할 것.

### Pitfall 2: `qr_print_log`에 인쇄 기록이 없는 라벨
**What goes wrong:** `printed_at` 최신 1건이 없으면 `price_type_id`를 모른다. base
가격으로 조용히 폴백하면 화면과 실제 라벨 가격이 다를 수 있는데 사용자는 알 수 없다.
**Why it happens:** `qr_print_log` 도입 이전에 인쇄된 라벨, 또는 유실된 로그.
**How to avoid:** 폴백 사용 시 응답에 `priceSource: 'exact' | 'fallback'` 같은 플래그를
반드시 포함하고, 프론트는 fallback 일 때 "참고 가격" 같은 문구를 표시(CONTEXT ①의
명시적 요구).
**Warning signs:** 인쇄 5건(모두 store 6)만 실제 로그가 있다 — 그 외 상품/매장은 전부
fallback 경로를 타게 된다는 뜻. 폴백이 예외가 아니라 **주 경로**가 될 수 있음을
설계에 반영.

### Pitfall 3: `store_configs.qr_precio_publico`(신규 플래그) 배포 타이밍
**What goes wrong:** 컬럼 추가와 코드 배포 순서가 어긋나면 기존 14개 매장 전부가
500 을 받거나(컬럼 없음), 반대로 기본값을 잘못 잡으면(true) 배포 즉시 전 매장
가격이 공개된다.
**Why it happens:** CLAUDE.md의 "모델에 컬럼을 더하면 마이그레이션 전엔 push 금지"
메모리와 정확히 같은 함정.
**How to avoid:** `defaultValue: false`(CONTEXT ④ 결정 그대로) + 로컬 5432/운영 5434
동시 마이그레이션 적용 확인 후에만 프론트/백엔드 코드 배포. 기존
`allow_sale_without_stock`(true 기본) 패턴과 달리 이번엔 **false 기본**임을 재차 확인.

### Pitfall 4: reseller 신청 폼에서 `storeIds`를 사용자가 고르게 둠
**What goes wrong:** 기존 DTO는 다중 매장 선택을 전제로 설계돼 있다. QR 에서 진입한
신청은 "이 매장"이어야 하는데 프론트에서 선택 UI를 그대로 노출하면 엉뚱한 매장에
연결될 수 있다.
**Why it happens:** `ResellerRegisterDto.storeIds: number[]`를 그대로 재사용하다 보면
기존 가입 폼(`GET reseller/public/stores` 로 전체 매장 목록을 보여주는 방식)을 그대로
베끼기 쉽다.
**How to avoid:** QR 페이지에서는 `storeIds: [qrStoreId]`로 프론트에서 고정 전송,
매장 선택 UI 자체를 노출하지 않는다.

## Code Examples

### 공개 페이지 인증 우회 선언
```typescript
// Source: ventago-app/src/pages/entrega/[token].tsx:245-247 (실사용 중)
EntregaPage.getLayout = (page: ReactNode) => <BlankLayout>{page}</BlankLayout>
EntregaPage.authGuard = false
EntregaPage.guestGuard = false
```

### 공개 이미지 서빙(변경 불필요, 그대로 재사용)
```typescript
// Source: api-ventago/src/common/minio/minio.controller.ts:91-105
@Public()
@Get(':filename')
async getImage(@Param('filename') filename: string, @Res() res: any) {
  if (!isPubliclyServable(filename)) {
    throw new ForbiddenException('Objeto no disponible públicamente');
  }
  try {
    const stream = await this.service.getObjectStream(filename);
    res.setHeader('Content-Type', 'image/png');
    stream.pipe(res);
  } catch (err) {
    res.status(404).send('Not found');
  }
}
```

### 텔레그램 알림(리드 발생 시 재사용)
```typescript
// Source: api-ventago/src/app/onboarding/onboarding-alta.service.ts:217-225 (패턴 참고)
notifyTelegram(
  `🧲 <b>Ventago 리드 — QR 에서 유입</b>\n` +
    `• 매장(QR 출처): <b>${storeName}</b>\n` +
    `• 연락처: ${contactName} · ${contactPhone}\n`,
  { dedupKey: `ventago-lead-${leadId}` },
)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|---------------|--------|
| QR 이 재고(`stock`) 화면을 가리킴(경로명의 기원) | 재고는 절대 공개 안 함, 가격·사진·매장 정보만 | 2026-09-16 사용자 결정 ② | 경로명(`/m/stock`)과 실제 기능이 불일치하지만 URL 은 안 바꾼다 — 코드 주석으로 "왜 m/stock 인데 재고가 아닌지" 남길 것 |

**Deprecated/outdated:** 없음 — 이 phase 는 신규 기능이지 기존 기능 대체가 아니다.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | 신규 `store_configs.qr_precio_publico` 컬럼명이 향후 실제 채택될 이름 | Common Pitfalls #3, Architecture Diagram | 이름만 다를 뿐 설계엔 영향 없음 — PLAN 단계에서 최종 확정 필요 |
| A2 | CTA②(리드)에 이메일 알림은 1차 범위에서 생략 가능 | Q4 권장 | 사용자가 텔레그램 채널을 안 본다면 리드가 묻힐 수 있음 — PLAN/CONTEXT 재확인 권장 |
| A3 | `qr_print_log` 최신 1건 확정 시 `printed_at DESC LIMIT 1`이면 충분(동시 인쇄 tie 미고려) | Pitfall 2 | 극히 드문 동시 인쇄(같은 branch+product+priceType, 같은 ms)에서만 문제, 실무 영향 거의 없음 |

## Open Questions

1. **`store_configs.qr_precio_publico` false 일 때 페이지 자체를 404 로 할지, 가격만
   숨길지 (상품명·사진은 보여줄지)**
   - What we know: CONTEXT ROADMAP W0 에 "이것은 W0 에서 확정한다"고 명시돼 있어
     아직 미결.
   - What's unclear: 매장이 이 기능 자체를 원치 않아 완전히 끄고 싶은 경우와, 가격만
     숨기고 "문의하세요" CTA 는 보여주고 싶은 경우 중 어느 쪽이 기본 기대치인지.
   - Recommendation: PLAN 단계에서 CONTEXT 작성자(사용자)에게 재확인 필요 — 연구
     범위에서 확정할 수 없는 제품 결정.

2. **CTA①(reseller 신청) 완료 후 신청자에게 진행 상태를 알려줄 수단이 전혀 없음**
   - What we know: reseller 로그인 포털이 앱 목록 어디에도 없다(CONTEXT, 이번 연구
     둘 다 확인).
   - What's unclear: 승인/거부 시 신청자에게 알림(SMS/이메일/전화)을 보낼지, 아니면
     "매장에서 연락드립니다" 수준으로 끝낼지.
   - Recommendation: 이번 phase 범위(성공판정 3번 "CTA 끝까지 눌러 실제 화면 도달")는
     신청 접수 화면 도달까지만 요구하므로, 승인 후속 알림은 **범위 밖**으로 명시하고
     별도 phase 로 미루는 것을 권장.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `TELEGRAM_BOT_TOKEN`/`TELEGRAM_CHAT_ID` (운영 env) | CTA② 리드 알림 | 확인 못 함(env 값 자체는 비밀값이라 조회 안 함) — 단 `onboarding-alta.service.ts`가 이미 같은 env 로 실사용 중이므로 **설정돼 있을 가능성 높음** [ASSUMED] | — | 미설정이어도 `notifyTelegram`이 조용히 skip + 로그(장애 아님), 저장 테이블은 정상 동작 |
| MinIO(운영) | 상품 이미지 서빙 | ✓ (curl 200 확인) | — | — |
| PostgreSQL 18(로컬 5432/운영 5434) | `qr_print_log` 조회, 신규 `ventago_leads` 테이블 | ✓ | 18 | — |

**Missing dependencies with no fallback:** 없음.
**Missing dependencies with fallback:** 텔레그램 미설정 시 리드는 DB 에는 남지만
알림만 안 감(테이블 저장을 권장한 이유이기도 함).

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Jest 29.7 (api-ventago), 프론트는 전용 테스트 스크립트 없음(레포 관례상 lint+tsc+수동검증) |
| Config file | `api-ventago/package.json`의 `jest` 필드(별도 `jest.config.js` 없음, 표준 `test` 스크립트) |
| Quick run command | `cd api-ventago && npx jest src/app/print --maxWorkers=1` (변경 모듈 디렉터리만 — 전역 메모리 폭발 주의, 사용자 메모리 규칙 준수) |
| Full suite command | `cd api-ventago && npx jest --maxWorkers=1`(전수 — 커밋 게이트 범위 밖, CI/사람이 실행) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| REQ-01 | `/m/stock`이 비로그인 상태에서 200 렌더 | manual + e2e | 실물 라벨 스캔 또는 `curl -sL` | ❌ Wave 0(공개 페이지 파일 자체가 없어 스모크 테스트 신규 작성 필요) |
| REQ-02 | 공개 API 가 `store_id` 를 넘는 조회를 차단(테넌트 격리) | unit | `pytest` 아님 — `jest src/app/print/qr-public.controller.spec.ts` (신규) | ❌ Wave 0 |
| REQ-03 | `qr_precio_publico=false` 매장은 가격 필드 미노출 | unit | 위와 동일 파일에 케이스 추가 | ❌ Wave 0 |
| REQ-04 | `reseller/auth/register` 는 storeIds 고정 시에도 기존 계약 그대로 동작 | unit(기존) | `jest src/app/reseller/auth/reseller-auth.service.spec.ts`(있다면 재사용, 없으면 신규) | 확인 못 함 — `find` 로 spec 파일 존재 여부 미검증, PLAN 단계에서 확인 필요 |
| REQ-05 | 리드 저장 성공 시 `notifyTelegram` 호출(mock 검증) | unit | `jest src/app/leads/leads-public.controller.spec.ts`(신규) | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** 변경 디렉터리만(`--maxWorkers=1` 필수 — 사용자 메모리 규칙:
  "전체 jest 는 --maxWorkers=1", "jest 는 기본 옵션이면 기계가 언다")
- **Per wave merge:** api-ventago 전수(로컬, `--maxWorkers=1`)
- **Phase gate:** 실물 라벨 스캔(성공 판정 1번)은 자동화 불가 — 사람이 폰으로 직접
  확인.

### Wave 0 Gaps
- [ ] `api-ventago/src/app/print/qr-public.controller.spec.ts` — REQ-01·02·03 커버
- [ ] `api-ventago/src/app/leads/leads-public.controller.spec.ts` — REQ-05 커버
- [ ] `reseller-auth.service.spec.ts` 존재 여부 확인(PLAN 단계 — 이번 연구에서 미확인)

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-------------------|
| V2 Authentication | no | 이 phase 전체가 의도적으로 무인증(공개 페이지) |
| V3 Session Management | no | 세션 없음 |
| V4 Access Control | yes | `@Public()`가 테넌트 가드를 무력화 — 컨트롤러/서비스에서 `storeId` 직접 강제(코드로 확인된 기존 패턴) |
| V5 Input Validation | yes | `class-validator` DTO(기존 `ResellerRegisterDto` 패턴), 쿼리 파라미터 화이트리스트(`ShopCatalogController`의 `CATALOG_SORTS` 패턴 참고) |
| V6 Cryptography | no | 신규 암호화 요구 없음(reseller 비밀번호는 기존 bcrypt 그대로) |

### Known Threat Patterns for 이 phase

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|----------------------|
| 다른 매장의 `qr_print_log`/상품을 `product_id`만으로 조회해 테넌트 넘기 | Information Disclosure | `products` JOIN 으로 `store_id` 강제 조건(이번 phase의 핵심 방어선) |
| 공개 리드/reseller 폼 대량 자동 제출(봇) | Denial of Service | `@Throttle`(기존 `PUBLIC_DELIVERY_THROTTLE` 패턴 재사용) |
| 이미지 파일명 경로 조작으로 비공개 파일(정산 CSV 등) 접근 | Information Disclosure | 이미 `isPubliclyServable()`이 슬래시/확장자 화이트리스트로 차단(기존 코드, 변경 불필요) |
| 리드/reseller 폼에서 공개 매장 정보 외 내부 필드(원가·공급처) 노출 | Information Disclosure | 응답 DTO 필드 명시적 나열(`ShopProductDto` 패턴), `SELECT *` 금지 |

## Sources

### Primary (HIGH confidence — 이 저장소 코드/설정/운영 조회로 직접 확인)
- `ventago-app/src/pages/entrega/[token].tsx` — 공개 페이지 실전 패턴
- `ventago-app/src/pages/_app.tsx`, `AclGuard.tsx`, `AuthGuard.tsx` — 가드 동작 확인
- `ventago-app/next.config.js:123` — `trailingSlash: true`
- `api-ventago/src/common/minio/minio.controller.ts` — 공개 이미지 서빙
- `api-ventago/src/app/reseller/auth/*` — reseller 신청 백엔드
- `api-ventago/src/app/reseller/admin/reseller-admin.controller.ts` +
  `ventago-app/src/pages/admin/revendedores.tsx` — 승인 화면 실재 확인
- `api-ventago/src/common/telegram/telegram.ts`,
  `api-ventago/src/app/onboarding/onboarding-alta.service.ts` — 알림 유틸/패턴
- `api-ventago/src/app/shop-public/shop-catalog.service.ts` — 공개 DTO 필드 선택 패턴
- `api-ventago/src/app/print/print.service.ts` — QR URL 조립, `qr_print_log` 활용
- 운영 nginx: `ssh jhkim-server`로 `/etc/nginx/sites-enabled/app.coolsistema.com.conf` 조회(읽기 전용)
- 운영 DB(읽기 전용): `qr_print_log`, `products.image_url` 비율, `reseller.*` 3개
  테이블 행 수, `resellers_document_key`/`resellers_email_key` 유니크 인덱스
- curl 실측: `https://app.coolsistema.com/m/stock`, `/entrega/test123`,
  `https://newapi.coolsistema.com/api/minio/<file>`

### Secondary (MEDIUM confidence)
- 없음 — 이번 연구는 전부 1차 소스(코드/DB/운영 조회)로 확인 가능했다.

### Tertiary (LOW confidence)
- `TELEGRAM_BOT_TOKEN` 운영 값 실재 여부 — 비밀값이라 직접 조회하지 않음, 기존
  `onboarding-alta.service.ts` 실사용 근거로 [ASSUMED] 처리(Assumptions Log A-없음,
  Environment Availability 표에 명시).

## Metadata

**Confidence breakdown:**
- Q1(도착지): HIGH — 실사용 중인 동일 패턴(`entrega`)과 curl 실측으로 확정
- Q2(이미지): HIGH — 코드 + curl 200 + DB 비율 실측
- Q3(reseller): HIGH — 백엔드/프론트 양쪽 코드 전부 대조, 운영 DB 행 수 확인
- Q4(리드): HIGH(기존 유틸 존재 여부) / MEDIUM(신규 스키마 설계는 이번 연구의 권장안이지 확정 결정 아님 — PLAN 단계에서 확정)

**Research date:** 2026-09-16
**Valid until:** 2026-10-16 (30일 — 이 phase 관련 코드가 안정적이나, 운영 배포/마이그레이션
빈도가 높은 레포이므로 한 달 이상 지나면 재확인 권장)
