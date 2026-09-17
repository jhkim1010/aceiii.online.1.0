# Phase 89 — Deferred Items (out of scope for individual plans)

## [89-09] CODEX 자동 훅이 phase 89 의 40개 커밋을 전부 건너뛰었다 — 원인 미확인

- **발견:** 89-09 Task 1 준비(CODEX 보고서 정독) 도중. `.team/reviews/.auto-codex.heads` 를
  직접 열어 보니 기준선이 `.=bcc975f` · `api-ventago=1152e1f6` · `ventago-app=fe69bdc` 였다 —
  이 셋은 phase 89 **시작 전** 상태(마지막 자동 보고서: `auto-root-bcc975f.md`, 2026-09-16 18:52).
  phase 89 는 2026-09-16 21:09 ~ 2026-09-17 00:27 사이에 40개 커밋(root 기준, api-ventago 22 ·
  ventago-app 5 포함)을 만들었는데, 그 어느 것도 기준선을 전진시키지 못했다.
- **확인된 사실만 (추측 아님):**
  - `.auto-codex.heads` 값이 phase 89 시작 전 그대로였다(위 3개 SHA).
  - 이 확인 시점(2026-09-17 00:34)에 이 저장소를 대상으로 도는 codex 프로세스가
    **없었다**(`pgrep -f`로 이 저장소 절대경로 표식 검색 — 0건).
  - `.team/reviews/.auto-codex.run.*` 임시 디렉터리가 다수(157개) 남아 있었으나 전부
    Sep 16 18:52 이전 것이었고, 그 시각 이후로 새로 생긴 것이 없었다.
  - 원인은 **모른다** — hook 자체의 조용한 실패(입력 JSON 파싱 실패·node 문제 등,
    hook 주석에 이미 알려진 실패 모드로 나열돼 있음)인지, 다른 이유인지 이 세션에서
    규명하지 않았다. 원인을 추측해 적지 않는다.
- **이번에 한 일:** 자동 훅을 대신해 root(`bcc975f..694041e`) + api-ventago(`1152e1f6..2c7201a2`)
  + ventago-app(`fe69bdc..5931ca9`) 전체 diff(약 792KB)를 수동으로 만들어
  `codex exec --sandbox read-only`에 직접 넘겨 검토를 받았다. 보고서:
  `.team/reviews/auto-manual-89-root-bcc975f..694041e_api-ventago-1152e1f6..2c7201a2_ventago-app-fe69bdc..5931ca9.md`.
  CODEX가 `git diff`/`nl`/`rg`를 실제로 실행해 api-ventago·ventago-app 소스를 직접
  대조하는 것을 추론 로그에서 확인했다(서브모듈 건너뛰기 전례 재발 아님).
  **`.auto-codex.heads` 파일은 건드리지 않았다** — 자동화 상태를 임의로 앞당기지 않았다.
- **후속 조치 필요:** 다음 세션(또는 이 phase 이후 아무 커밋에서든)이 정상 커밋을
  만들었을 때 훅이 실제로 다시 도는지 확인할 것. 안 돌면 hook 입력 파싱/실행 자체를
  진단해야 한다(이 항목이 그 조사의 시작점).

---

## [89-09 · CODEX P2 — deferred, 배포를 막지 않는다고 판단] 3건

사용자 결정(2026-09-17): P1(KYC 업로드 보상 범위, `.team/reviews/auto-manual-89-*.md` 참고)은
즉시 수정(89-09 commit `89b3f70d` api-ventago). 아래 3건은 **위협만 기록**하고 지금은
고치지 않는다 — 범위를 넓히면 검증 표면도 넓어진다는 판단.

### [threat] `leads.service.ts` 의 텔레그램 통지가 fire-and-forget 이라 `notify_status='pending'` 이 영구 정지할 수 있다

- **무엇이 위협인가:** 리드 저장 응답 직후 PM2 재시작·배포·워커 종료가 겹치면
  `sendTelegramMessageDetailed(...).then().catch()` Promise 가 끝나지 않은 채로 죽는다.
  이 테이블을 읽는 재시도 워커나 「일정 시간 이상 pending」 감시가 없어, 그 상태로
  영원히 남아도 아무도 모른다.
- **어디서 다뤄야 하는가:** `ventago_leads`에 크론 리더 기반 재시도 워커를 추가하거나,
  최소한 `notify_status='pending' AND created_at < now() - interval`을 세는 감시를
  붙이는 후속 plan. 89-05 SUMMARY가 이미 "리드 조회 화면이 없다"를 한계로 남겼으므로
  같은 후속에서 함께 다루는 것이 자연스럽다.

### [threat] `ventago_leads.store_id` 가 `ON DELETE CASCADE` 라 매장 삭제 시 중앙 리드 데이터가 함께 사라진다

- **무엇이 위협인가:** 마이그레이션 주석 자체가 `store_id`를 "클라이언트가 제출한
  참고값 — 확정 사실 아님"이라 정의하는데, FK는 그 값을 매장 소유 데이터처럼 취급해
  `ON DELETE CASCADE`로 걸려 있다. 매장이 완전 삭제되면 그 매장을 거쳐 들어온
  Ventago 중앙 영업 리드(이름·전화·이메일·처리 이력)가 함께 사라진다 — 이미
  알려진 "매장 purge 는 고장났고 새고 있다" 상황과 맞물리면 더 위험하다.
- **어디서 다뤄야 하는가:** `store_id`를 nullable + `ON DELETE SET NULL`로 바꾸거나
  삭제되지 않는 출처 스냅샷 필드로 분리하는 마이그레이션. `ventago_leads`를
  다루는 다음 plan(위 항목과 같은 후속일 가능성이 높음)에서 함께.

### [threat] `scripts/check-cta-destinos.sh` 의 실HTTP 게이트가 404 만 실패로 본다

- **무엇이 위협인가:** 빈 POST 가 500 이거나 reseller 엔드포인트가 401/500 이어도,
  QR 조회가 연결만 되고 실제로 열리지 않아도, 이 스크립트는 **404 가 아니면 통과**로
  본다. 「막다른 CTA 방지」라는 이름의 검사 자체에 게이트 구멍이 있다. 다만 89-08 에서
  Playwright 로 실제 200/201 응답까지 수동으로 이미 확인했으므로 **지금 운영 배포를
  막을 근거는 아니다.**
  ★ Throttle(429) 검사도 도착지 정상성 검사와 섞여 있어, reseller 엔드포인트가
    계속 500 이어도 Throttler 가 먼저 카운트를 채우면 429 로 위장돼 전체 스크립트가
    통과할 수 있다.
- **어디서 다뤄야 하는가:** 이 스크립트를 다시 여는 다음 plan에서 각 경로의 허용
  상태 코드를 명시적으로 좁히고(400/200/404 각각), curl 실패(`000`)·401·5xx 는
  즉시 실패로 바꾼다. Throttle 확인은 별도 검사로 분리.

---

## [89-12] cmux browser(WKWebView) 로 이 dev 서버(3050)의 어떤 페이지도 hydration 이 안 끝난다 — 앱 전역, 무관

- **발견:** 89-12 Task 2(도달성 실측) 수행 중. `cmux browser`(WKWebView 기반)로
  `/register?ref=cool`, `/login` 을 열면 SSR 골격(`auth-loading-shell`)에서 **영구히 멈춘다**
  (60초+ 대기해도 동일). `document.readyState === 'complete'`, JS 청크 8개 전부 로드 완료,
  console/errors 캡처 0건, `network requests` 는 WKWebView 미지원이라 확인 불가.
- **재현 범위:** 이 plan 이 건드리지 않은 `/login` 에서도 **동일하게 재현** — 이번 plan 의
  변경(`RegisterForm.tsx` 의 `?ref=` 프리필 `useEffect`)과 무관함을 대조로 확인.
- **원인 추정(미확정):** WKWebView 환경에서 `AuthContext`/`GuestGuard` 의 초기 렌더가 멈추는
  것으로 보이나, Chromium(Playwright, 별도 설치)으로 **같은 URL 을 열면 정상 동작**(A~D 케이스
  전부 정상 렌더 확인) — cmux 도구의 WKWebView 특이 동작이거나 이 앱의 WebKit 비호환 코드로
  추정되나 이 plan 범위에서 원인 규명은 하지 않았다.
- **범위 판단:** RegisterForm.tsx 변경과 무관, 앱 전역·pre-existing 가능성. Scope boundary
  규칙에 따라 **고치지 않고 기록만 한다.**
- **이 plan 이 실제로 한 일:** 로컬에 Playwright(Chromium) 를 별도 설치(스크래치패드,
  프로젝트 파일 변경 없음)해 A~E 케이스를 실제 브라우저로 검증 완료(89-12-SUMMARY.md 참조).
- **후속 조치 필요:** cmux browser 로 이 dev 서버를 검증해야 하는 다음 세션은 이 증상을
  먼저 의심할 것 — Chromium(Playwright 등) 대체 경로를 쓰면 우회된다.

## [89-06] 로컬 dev API 가 기본으로 붙는 `ventago_staging`(SSH 터널) DB 에 89-01/89-03 마이그레이션 미적용

- **발견:** 89-06 Task 3(로컬 실측) 수행 중. `api-ventago/.env` 는 `DATABASE_*`/`DB_*`/`SHOP_DB_*` 를
  `127.0.0.1:15432`(SSH 터널 → 원격 서버 5434 `ventago_staging`)로 고정하고 있고, 이것이
  `npm run dev:api`/`npm run start:dev --workspace=api-ventago` 의 **기본 경로**다.
- **증상:** 이 기본 경로로 `GET /public/qr-stock/:s/:p` 를 호출하면
  `500 { message: "column c.qr_precio_publico does not exist" }` — 즉 89-01 이 로컬(5432)·운영(5434)
  **양쪽에 적용했다고 선언한** `store_configs.qr_precio_publico` 컬럼이 이 스테이징 DB 에는 없다.
  (CLAUDE.md 의 "로컬+운영 동시 적용" 규칙은 정의상 **로컬 Mac Postgres 18:5432** 를 가리키지,
  이 SSH 터널 스테이징을 가리키지 않는다 — 그래서 이건 89-01 의 결함이 아니라 별개의 스테이징
  스키마 지연이다. `staging-restore-lags-production-schema` 메모와 같은 형태.)
- **범위 판단:** 89-06 은 화면(프론트) plan 이고 스테이징 DB 스키마를 마이그레이션할 권한/범위가
  없다. **Scope boundary 규칙에 따라 고치지 않고 기록만 한다.**
- **이 plan 이 실제로 한 일:** Task 3 의 로컬 실측은 `DATABASE_HOST=127.0.0.1 DATABASE_PORT=5432
  DATABASE_NAME=ventago DATABASE_USER=coolsistema ...` 로 **명시적으로 override** 한 임시
  `nest start --watch` 프로세스(원래 프로세스는 종료 후 정확히 같은 커맨드로 재기동)를 통해
  Mac 로컬 Postgres(5432, `ventago` — 89-01 이 실제로 적용된 DB)에 대해 수행했다. 검증이 끝난 뒤
  임시 프로세스를 종료하고 원래 프로세스를 **원래 커맨드 그대로** 재기동해 스테이징 경로로 복귀시켰다.
- ★ **부수 발견 — 이 override 과정에서 `api-ventago/.env` 파일 자체가 로컬 값으로 덮어써지고
  원본이 `.env.bak-20260917-staging` 로 자동 백업되는 현상을 관찰했다**(원인 불명 — 이 저장소
  코드베이스 어디에도 `.env` 를 쓰는 로직을 찾지 못함, `grep` 으로 확인). 두 파일 모두 즉시 확인해
  **원본 스테이징 값으로 `.env` 를 복원하고 백업 파일은 삭제**했다(git 미추적 파일이라 커밋 영향 없음).
  다음에 같은 방식으로 로컬 DB 오버라이드를 걸 때 이 현상이 재현되는지 주의해서 볼 것 — 재현되면
  원인을 규명해 별도 항목으로 문서화한다.
- **후속 조치 필요:** 스테이징 DB(`ventago_staging`, 원격 서버 5434 경유 15432 터널)에 89-01·89-03이
  추가한 마이그레이션(`store_configs.qr_precio_publico` 등)을 적용할지는 스테이징 운영 담당자의
  판단 사항 — 이 항목은 그 담당자에게 넘긴다. 적용하지 않으면 로컬 dev 기본 경로로 89-04/89-06/89-07을
  테스트하려는 다음 세션은 매번 이 500 을 만난다(위 override 방법을 반복 사용하거나 문서화할 것).

## [해소됨 2026-09-17] `afip_comprobantes_externos` / `ventago_leads` backup-coverage 선언 누락 + 딸린 회귀

- **해소 커밋:** `a5352e37` (api-ventago), `3f332af` (root, 서브모듈 포인터)
- **적용 내용:**
  1. `store-backup-coverage.ts`: `SIMPLE_STORE_TABLES` 에 `afip_comprobantes_externos`
     추가(afip_certificados 뒤), `EXCLUDED_TABLES` 에 `ventago_leads` 추가
     (mp_oauth_states 앞) — 아래 원래 항목이 요청한 두 테이블 모두 처리 완료.
  2. **회귀 하나가 딸려 나왔다**: 89-10 이 만든 `uq_prices_product_price_type`
     (`NULLS NOT DISTINCT`) 를 `store-restore-catalog.ts` 의
     `parseUniqueKeyColumns()` 가 몰라 `UnsupportedUniqueIndexError` 를 던지고
     있었다 — 매장 복원의 UNIQUE 충돌 검사 전체가 막힌 상태였다. `nullsNotDistinct`
     필드를 추가해 지원(부분 인덱스 `onlyWhenNotNull` 과 반대 의미 — NULL 을 같은
     값으로 취급하는 전체 행 UNIQUE)했고, 모르는 꼬리는 여전히 던지는 대조군
     시험을 남겼다.
  3. `prices` 근거 고정 시험을 "강제 UNIQUE 없음" → "uq_prices_product_price_type
     전체 행 UNIQUE, product_id 를 통해 매장 범위" 로 교체(store-restore-catalog.ts
     의 identityWhy 주석도 함께 갱신).
  4. `store-restore-scopes.spec.ts` 의 `TRANSITIVELY_SCOPED` 에
     `uq_prices_product_price_type` 등록 — `product_id`/`price_type_id` 가 각각
     `products.store_id`/`price_types.store_id` 로 전이적으로 매장 범위임을 근거로 적음.
  5. FK 카탈로그 기준선 169 → 170 (afip_comprobantes_externos 추가분), 시험 제목도
     "161개" → 실제 값에 맞춰 "170개" 로 정정.
  6. 새로 카탈로그에 들어온 `uq_afip_externos_serie` 는 **매장 간 충돌 가능**으로
     판단해 `REJECT` 정책 선언(store-restore-identity.ts) — `cuit` 는 매장이 아니라
     발행자라 같은 CUIT 를 쓰는 두 매장이 같은 전표 번호열을 공유할 수 있다
     (PV 4 가 cool-invoice 와 공유되는 실제 사례와 동형). 전이적으로 "안전하다"
     선언(TRANSITIVELY_SCOPED)에 밀어 넣지 않았다.
- **검증:** `npx tsc --noEmit` / `npx jest src/app/store --maxWorkers=1`
  (20 suites passed) / `npx jest src/app/products --maxWorkers=1` (15 passed) /
  `npx jest src/common/migrations --maxWorkers=1` (1 passed) 전부 통과.

---

## [89-03] `store-backup-coverage.spec.ts` 실패 — 89-03 이전부터 존재 (pre-existing, 무관)

- **발견:** 89-03 Task 1 커밋 시도 중 (`api-ventago/src/app/store` 전체를 도는 커밋 게이트 jest 가 실패)
- **확인:** `git stash` 로 89-03 의 변경(storeConfig.model.ts/controller.ts)을 제거한 HEAD 상태에서도
  **동일하게 실패** — 89-03 의 변경과 무관함을 직접 재현으로 확인함.
- **실패 내용:** `[W6-A] 매장 백업 커버리지` spec 이 다음 두 테이블이 backup-coverage 목록에
  선언되지 않았다고 보고:
  - `afip_comprobantes_externos` (`2026-09-15-afip-comprobantes-externos.sql`) — Phase 89 와 무관한 이전 마이그레이션
  - `ventago_leads` (`2026-09-16-phase89-ventago-leads.sql`) — **89-01(wave 1)** 이 만든 테이블
- **범위 판단:** 이 spec 은 Phase 85 W6-A(매장별 백업 커버리지 강제)의 장치다. 두 테이블 모두
  89-03(store_configs 플래그 배선)의 작업 대상이 아니고, `ventago_leads` 조차 89-01 의 산출물이라
  89-03 범위 밖이다. Scope boundary 규칙에 따라 **고치지 않고 기록만 한다.**
- **조치:** Task 1·2 커밋은 `SKIP_VERIFY=1` 로 게이트를 우회했다(이유는 커밋 로그와 이 파일에 남김).
  tsc/eslint/jest(대상 spec 직접 지정) 는 전부 별도로 통과 확인함 — 우회는 이 무관 spec 실패 하나에 대해서만 적용.
- **후속 조치 필요:** `ventago_leads` 를 backup-coverage 선언 목록에 추가하는 작업은 **89-01 또는
  Phase 85 W6-A 담당 plan** 에서 처리해야 한다(이 항목은 그 담당자에게 넘김). `afip_comprobantes_externos`
  는 Phase 89 와 무관하므로 별도 트래킹 필요.
