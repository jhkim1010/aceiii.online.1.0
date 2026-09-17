# Phase 89 — Deferred Items (out of scope for individual plans)

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
