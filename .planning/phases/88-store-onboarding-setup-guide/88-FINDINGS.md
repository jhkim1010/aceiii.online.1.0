---
phase: 88-store-onboarding-setup-guide
type: findings
created: 2026-09-09
source: 적대적 검토 1회(코드·스키마 실측) + 직접 재확인
---

# Phase 88 — FINDINGS · v1 계획이 착수 전에 무너진 지점

**판정: v1 계획대로 착수하면 안 됐다.** CRITICAL 3 · HIGH 6 · MEDIUM 11.
아래는 **고친 결과**를 적는다. 원인·근거는 각 항목에 파일:줄로 남긴다.

---

## CRITICAL

### C-1 · `set_prices` 술어가 **원리적으로 참이 될 수 없었다** — Square 59% 고착의 재현

v1 은 `price_type_ranges` 를 「가격 설정」의 증거로 삼았다. 실측:

- `createStoreDefaults()` (`storeTemplate.service.ts:135-180`) 의 시드 목록에 **`price_types` 도 `price_type_ranges` 도 없다.**
- `price_type_ranges` 는 기본 가격이 아니라 **대량가격 구간 규칙**이다(`prices/price-type-ranges.service.ts:1-10`).
- `PriceType` 생성 경로는 **둘뿐** — `POST /price-types`(`types/priceType.controller.ts:68`)와 레거시 임포트(`legacy-import.service.ts:501`).

⤷ 정상적으로 가격을 넣어도 그 테이블에는 한 행도 안 생긴다. **체크리스트 2번이 영구 미완.**

**고침:** 시드가 없으므로 **행 존재만으로 충분하다** — `EXISTS(price_types WHERE store_id=$1)`.

### C-2 · 「시드 이탈 = 5분/1분 시각 비교」가 **목표(15분 TTFV)와 충돌**하고 마이그레이션에 취약

- 가입 4분 뒤 결제수단을 추가하면 `created_at > store.created_at + 5분` 이 false → **행을 만들었는데 미완**, 그리고 **회복되지 않는다.**
- `internet-pedido-rename-label.sql` 은 `UPDATE payment_methods SET ..., updated_at=NOW()` 를 **store_id 필터 없이** 실행한 전례다. 이런 마이그레이션이 한 번만 더 나오면 **전 매장의 판정이 일제히 뒤집힌다.**

**고침: 시각 비교를 전부 버린다.** 술어는 **시드 상수와의 대조**로 바꾼다(§아래 표).
시드 결제수단은 실측 **3개** — `efectivo` · `tarjeta-debito` · `mercadopago`
(`storeTemplate.service.ts:507,514,521`). 그 밖의 slug 가 있거나 시드 중 하나가 꺼져 있으면 「손댔다」.

### C-3 · `api-ventago/src/app/onboarding/` 은 **이미 다른 모듈**이다 — 덮어쓰기·라우트 충돌·순환 의존

- 기존 `onboarding.controller.ts` = **공개(무인증) 가입 OTP API** (`@Public()`, `POST /onboarding/start`, `GET /onboarding/status/:token`).
- `onboarding.module.ts:14,28` 이 이미 `AuthModule` 을 import → `AuthService` 가 역방향으로 주입하면 **순환 → 부팅 실패**.

**고침: 이름을 분리한다.** 모듈 `app/setup-guide/`, 서비스 `SetupGuideService`,
라우트 `@Controller('setup-guide')`, 테이블 `store_setup_steps` / `store_setup_events`,
`/me` 필드 `setupGuide`. **"onboarding" 이라는 단어를 이 phase 에서 쓰지 않는다.**

---

## HIGH — 전부 계획에 반영

| | 결함 | 고침 |
|---|---|---|
| H-1 | 마이그레이션이 배포보다 늦으면 `Store` 모델이 없는 컬럼을 SELECT → **`/auth/me` 500 → 전 사용자 로그인 불가** | **게이트로 못 박음**: 운영 5434 적용 확인 **전에는 push 금지**(PLAN §1 TASK-1 첫 줄) |
| H-2 | `branch_agents` 에 `store_id` 가 없고(`db-schema-fks.md:43`) raw query 는 테넌트 훅을 안 탄다 → 계획이 **자기 규칙을 위반** | `JOIN branches b ON b.id=a.branch_id AND b.store_id=$1` + `branchId` 는 `branches WHERE id=? AND store_id=?` 로 **먼저 검증** |
| H-3 | 「Promise.all 에 넣는다」와 「hidden 이면 호출 안 한다」가 **동시 성립 불가**(hidden 은 그 Promise.all 의 결과물) | 술어 쿼리를 `FROM stores s WHERE s.id=$1` 로 시작해 **`CASE WHEN s.setup_hidden_at IS NOT NULL THEN NULL ELSE EXISTS(...) END`** 로 단락. 숨긴 매장은 PK 조회 1건 |
| H-4 | `/me` 안에서 `completed` INSERT — 실패하면 `auth.service.ts:1242-1251` 이 **모든 예외를 401 로 변환** → 기록 실패가 곧 로그인 실패. 4워커 동시 INSERT 중복도 남 | ① 읽기 경로에서 **쓰지 않는다**(아래 H-6 의 전용 엔드포인트에서만) ② `try/catch` → 실패 시 `setupGuide: null` ③ **부분 UNIQUE** + `ON CONFLICT DO NOTHING` |
| H-5 | 「Ayuda 에서 되돌아온다」가 **구현 불가** — unhide API 없음, hidden 이면 상태가 안 실림, 그리고 **「Ayuda」 메뉴 자체가 없다** | `PATCH /setup-guide/visibility {hidden}` 양방향 + hidden 이어도 `progress` 는 내려보냄 + **Ayuda 진입점을 W2 태스크로 신설** |
| H-6 | `/me` 는 부팅 1회뿐 → 상품을 등록해도 **가이드가 안 바뀐다.** 그런데 v1 은 새 엔드포인트도 폴링도 금지했다 | **D-7 개정.** `/me` 에는 요약만, 홈에서 가이드를 볼 때 `GET /setup-guide` 로 갱신(SWR dedupe 10초). 사이드바 클릭마다가 아니므로 pool 규약과 무관 |

★ H-6 은 규칙 자체가 틀렸던 경우다 — **비용이 없는 곳에서 비용을 아끼려다 제품을 못 쓰게 만들었다.**

---

## MEDIUM — 반영

- **M-1** `sales` 는 판매 전용이 아니다(`activity_type`: sale/movido/fallado). 지점 간 이동 1건이 「첫 판매」가 됐다.
  → `activity_type = 'sale'`(코드의 `SaleActivityType.SALE` 을 파라미터로) `AND nullified_by_sale_id IS NULL`.
  그리고 `sales.branch_id` 는 **nullable** 이라 지점 술어가 판매를 놓친다 → **`first_sale` 을 매장 단위로 내린다.**
- **M-2** `MemoryCacheService.get/set` 은 Phase 85 W8 에서 **private 봉인**, 키는 브랜드 타입 → `storeKey('setup', storeId, branchId ?? 0)` 사용. 무효화도 같은 생성기로.
- **M-3** `COALESCE(branch_id,0)` 표현식 UNIQUE + Sequelize `upsert` = `42P10`.
  → **`branch_id integer NOT NULL DEFAULT 0`**(매장 단위는 0) + 평범한 UNIQUE. FK 는 걸지 않는다(0 은 지점이 아니다 — 이 DB 는 애초에 FK 가 거의 없다).
- **M-4** `w4-exempt` 는 **파일 전체**를 면제시킨다(`migration-conventions.spec.ts:88-91`). 새 테이블 문장은 `targetsNewTable()` 이 **자동 면제**하므로 주석이 불필요하고 해롭다 → 삭제. 파일명은 `/^\d{4}-\d{2}-\d{2}/` 를 만족하는 **실제 날짜**여야 검사 대상이 된다.
- **M-5** act-as-store 중 `/auth/me` 는 대행을 무시한다(`HANDOFF-2026-09-06`) → **superadmin 이 대행으로 가이드를 볼 수 없다.** 이 phase 범위 밖(별건)이지만 **SPEC 에 명시**하고 W1 성공기준에서 뺀다.
- **M-6** 「목적지는 전부 `/configuracion?tab=`」는 **사실이 아니다** — `precios`·`sucursales`·`impresora`·`productos` 는 `HUB_TABS` 에 없다. 그리고 허가 없는 탭 키는 **조용히 첫 탭으로 폴백**(`configuracion/index.tsx:100-102`) → 권한 없는 사용자에게 그 항목을 보이지 않는다.
- **M-7** `keySeparator: false`(`configs/i18n.ts:19`) → 사전을 **중첩 객체로 넣으면 키가 그대로 화면에 뜬다.** 평평한 키(`"setupGuide.load_products.title": "..."`)로 넣는다. `useSuspense:false` + http-backend 라 사전 로드 전 첫 렌더에 키가 스칠 수 있다 → **가이드 문구는 초기 로드에 포함**시킨다.
- **M-8** 폐지 잔여물: ① `views/talleres/components/OnboardingTour.tsx` 는 **동명이인**(사용 중) — 이름으로 지우면 탈례레스가 깨진다. ② `data-tour` 마커 4파일 정리. ③ `PUT /auth/onboarding-complete` 는 `OnboardingWrapper` 가 유일한 호출자 — **엔드포인트·컬럼은 남기고 사용만 중단**(삭제는 별건), 프런트 참조만 제거.
- **M-9** `createStoreDefaults` 호출부는 **세 곳**이다 — `auth.service.ts:720`, `store.controller.ts:203`, **`auth/services/user-registration.service.ts:102`(죽은 경로, 배선되면 살아난다)**. 그리고 `provisionStoreAndOwner` 에는 **감싸는 트랜잭션이 없다** → v1 의 「생성 트랜잭션 안에서 기록」은 성립하지 않는다.
  → **TASK-5 삭제.** 시작 3항목은 카탈로그가 「항상 참」이라 이벤트가 애초에 필요 없다.
- **M-10** `createDefaultGenericProduct`(`storeTemplate.service.ts:1013-1047`)는 `_storeId` 를 **쓰지 않고** 전역에 제네릭이 있으면 아무것도 안 만든다 → **CONTEXT §1-2 의 「시드에 producto genérico 포함」은 틀렸다.** 실제 제네릭은 첫 빠른판매 때 `products.service.ts:550` 이 지연 생성한다. `load_products` 술어(`is_generic=false`)의 **결론은 맞지만 근거가 달랐다.**
- **M-11** 로그인 직후 모달은 **4개**다 — `SelectBranchModal` 이 빠져 있었다(`UserLayout.tsx:301-314`).

---

## 「괜찮다」로 확인된 것

`branches` 테이블명 정확 · `payment_methods`/`price_type_ranges` 의 타임스탬프는 NOT NULL(문제는 NULL 이 아니라 설계였다) ·
`products.is_generic` 실재 · raw query 가 테넌트 훅을 안 탄다는 전제 정확(그래서 H-2 가 실제 통로) ·
`MemoryCacheService.getOrLoad` 의 single-flight 로 stampede 방어됨 · `/me` 는 부팅 1회라 pool 부담 자체는 작다(진짜 위험은 직렬 왕복) ·
`pages/index.tsx` 랜딩 성립(`store_owner` 는 `getRedirectUrl` 목록에 없어 `/` 로 폴백) — 단 나중에 초대되는 직원은 `/nueva-venta` 로 가므로 **메뉴 배지가 선택이 아니라 필수**.

## 확인 실패 (추측하지 않음)

이 세션의 `device_bash` 는 격리 VM 이라 **psql 도 없고 `jhkim-server` 도 안 닿는다.**
→ `stores` 행 수(= `UPDATE stores` 영향 범위) · `sales.activity_type` 분포 · `sales.branch_id IS NULL` 건수는 **재지 못했다.**
운영 마이그레이션 승인 요청 때 사용자가 실행해 확인한다.
