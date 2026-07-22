# SPEC: 매장별 홈페이지 테마 커스터마이징 (Phase 1 — 프리셋)
생성일: 2026-07-22
관련 스킬: gsd · 참고 목업: artifact `store-homepage-customizer`

## 목표
각 매장(store)이 자기 공개몰(tienda-app) 홈페이지의 **색상·배경톤·글꼴 페어링·레이아웃·모서리**를 hallmark 검증 프리셋 안에서 자유롭게 고르고, 실시간 미리보기 후 "발행"하면 `/[storeId]` 공개 페이지에 반영되도록 한다. Phase 1은 **프리셋 기반**(자유 색 1개 + 배경톤 + 폰트페어링 + 레이아웃 + radius)까지만 다룬다. hallmark `study`(URL/이미지에서 DNA 추출)는 Phase 3로 분리.

## 배경 및 컨텍스트
- **storefront**: `tienda-app` (Next.js 13.3.2, pages router, port 3060, `next lint`). PostgreSQL 직접 연결 없음 — `api-ventago`의 `/public/shop/:storeId/*` 호출.
- **핵심 발견 — 이미 CSS 변수 기반**: `styles/globals.css`의 `:root`에 `--gold --navy --ink --line --bg --soft --muted --green` 정의. `Header`, `ProductCard`, chip, 버튼이 전부 `var(--gold)` 등을 참조. → **이 변수들을 매장별로 override 하면 컴포넌트 수정 없이 즉시 리스킨** 된다. 이게 이 작업의 난이도를 크게 낮춘다.
- **하드코딩 잔여**: `[storeId]/index.tsx`의 hero/promo/aistrip 그라디언트(`#26264a`, `#fff7ea` 등), `ProductCard`/`Header`의 `background:#fff` — 토큰화 필요.
- **백엔드 shop-public 모듈**: `api-ventago/src/app/shop-public/` — `shop-catalog.controller.ts`, `shop-order.*`, `shop-storefront.controller.ts`(SSR 몰도 별도 존재), **`shop-readonly-db.service.ts`(읽기 전용 pool, `max=SHOP_DB_POOL_MAX||15`)**.
- **마이그레이션**: `api-ventago/src/database/migrations/` 에 `*.sql` 수기 파일 방식(예: `2026-07-17-reseller-onboarding.sql`).
- **⚠ 로그 확인(2026-07-20 combined)**: `sync_outbox` SELECT 슬로우쿼리 12~45초, `[Pool] ⚠️ 커넥션 대기 발생! waiting=2`, `OnlineOrdersExpiryCron ... Operation timeout`. → **신규 테마 조회가 메인 write pool을 건드리면 안 됨.** 공개 조회는 readonly pool + HTTP 캐시로 처리, 쓰기(편집)는 드문 인증 경로로 분리한다.

## 기술 스택
- 프론트: Next.js 13 (pages router), TypeScript, CSS 변수. ESLint = `eslint-config-next` (`npm run lint` / `next lint`).
- 백엔드: NestJS + TypeORM (`api-ventago`). DB pool은 `database.module.ts`(main, max=80, pgbouncer pool_size=50 캡) + `shop-readonly-db.service.ts`(readonly, max=15).
- DB: PostgreSQL. 마이그레이션 = `src/database/migrations/*.sql` 수기.

## 데이터 모델
```sql
-- store_themes: 매장 1 : 테마 1 (JSONB 단일 컬럼으로 토큰 유연 확장)
CREATE TABLE IF NOT EXISTS store_themes (
  store_id        INTEGER PRIMARY KEY REFERENCES stores(id) ON DELETE CASCADE,
  base_theme      VARCHAR(40)  NOT NULL DEFAULT 'Studio',   -- hallmark 프리셋명
  macrostructure  VARCHAR(40)  NOT NULL DEFAULT 'marquee',  -- marquee|bento|doc
  published_tokens JSONB       NOT NULL DEFAULT '{}'::jsonb, -- 실제 공개 반영본
  draft_tokens     JSONB,                                    -- 편집 중 초안(미발행)
  published_at    TIMESTAMPTZ,
  updated_at      TIMESTAMPTZ  NOT NULL DEFAULT now()
);
```
- 토큰 JSON 예: `{ "accentHue":210, "sat":70, "paperBand":"light", "fontPair":"sans", "weight":600, "radius":12 }`. **서버가 이 토큰을 CSS 변수 맵(--gold/--navy/--ink/--line/--bg/--soft/--font-display/--font-body/--radius)으로 변환**해 내려준다(프론트는 변환 로직 없이 그대로 주입).
- ⚠ `stores` 실제 PK/테이블명은 EXECUTE 착수 시 `DATABASE_SCHEMA.md`로 재확인(다중 branch 이슈 과거 존재).

## 태스크 목록

### A. 백엔드 (api-ventago)
- [ ] TASK-1: 마이그레이션 `src/database/migrations/2026-07-DD-store-themes.sql` — 위 `store_themes` DDL + 기본 시드(없으면 기본 테마). 로컬 5432 & 운영 5434 모두 적용 절차 명시.
- [ ] TASK-2: `store-theme.dto.ts` — 토큰 검증 DTO(class-validator). 허용 범위/enum 화이트리스트(paperBand, fontPair, macrostructure)로 임의값 차단.
- [ ] TASK-3: `store-theme.service.ts` — `getPublicTheme(storeId)`(readonly pool 사용, 없으면 기본 테마 반환) + `getDraft` / `saveDraft` / `publish`(메인 repo, 소유자 인증). 토큰→CSS변수 맵 변환 헬퍼 포함. 모든 async try/catch, pool.connect 수동 사용 금지(repository/readonly service 재사용).
- [ ] TASK-4: 공개 라우트 `GET /public/shop/:storeId/theme` (shop-catalog.controller 또는 신규 shop-theme.controller) — **`Cache-Control: public, max-age=300, stale-while-revalidate=600`** 헤더. readonly 경로.
- [ ] TASK-5: 소유자 라우트 `GET/PUT /shop/:storeId/theme/draft` + `POST /shop/:storeId/theme/publish` — 기존 인증 가드 재사용(매장 소유자만). 쓰기 드묾.

### B. 스토어프론트 (tienda-app)
- [ ] TASK-6: `services/shop-api.ts` — `getStoreTheme(storeId)` 추가(`/public/shop/:storeId/theme`). `types/shop.ts` — `StoreTheme`(cssVars: Record<string,string>, macrostructure) 타입.
- [ ] TASK-7: `styles/globals.css` — `--font-display/--font-body/--radius` 기본 토큰 추가, `body`에 `font-family:var(--font-body)`, 버튼/카드 radius를 `var(--radius)` 참조로. 기존 변수는 유지(하위호환).
- [ ] TASK-8: 하드코딩 색 토큰화 — `[storeId]/index.tsx`(hero/promo/aistrip 그라디언트→토큰), `ProductCard.tsx`/`Header.tsx`의 `#fff`→`var(--paper)`.
- [ ] TASK-9: 테마 주입(SSR, 무플리커) — `[storeId]/index.tsx` `getServerSideProps`에서 theme 병렬 fetch(`Promise.all`에 합류) → 최상위 래퍼 `<div style={cssVars}>`로 CSS 변수 주입 + `data-macro` 속성으로 레이아웃 분기. 실패 시 기본 테마 폴백(페이지 절대 깨지지 않게).
- [ ] TASK-10: 편집 UI 페이지 — 목업 이식. **위치 결정 필요(아래).** 좌측 컨트롤(테마/색/폰트/레이아웃/radius) + 우측은 실제 `Header`+`ProductCard` 재사용 실시간 미리보기 + 저장(초안)/발행. 상태는 메모리, 저장 시에만 API.

### C. 검증
- [ ] TASK-11: `cd tienda-app && npm run lint` 오류 0.
- [ ] TASK-12: `cd api-ventago && npx eslint src/app/shop-public --fix` 오류 0 + `npm run build`(tsc) 통과.
- [ ] TASK-13: Pool 안전 점검 — 신규 조회가 readonly pool만 사용, 수동 `pool.connect` 없음, 공개 엔드포인트 캐시헤더 존재 확인. 로컬 기동 후 `[DatabasePool]` 로그에 신규 대기 없음 확인.

## 완료 기준
- 서로 다른 두 매장(`/1`, `/2`)이 눈에 띄게 다른 색/폰트/레이아웃으로 렌더된다.
- 편집 → 발행 후 새로고침 시 반영, 발행 전 초안은 공개에 노출되지 않는다.
- 공개 `/theme` 응답에 캐시 헤더 존재, 메인 write pool 미사용.
- ESLint 0 (양 repo), tsc build 통과, SSR 무플리커(테마 색이 깜빡이지 않음).

## 결정 (2026-07-22 확정)
- **편집 UI 위치 = (a) tienda-app 내부 인증 라우트 `/[storeId]/panel/diseno`**. 같은 앱이라 실제 `Header`·`ProductCard`로 즉시 미리보기, 단일 repo, 리스크 최소. Phase 2에서 관리자 콘솔(front)로 이전 옵션 유지.

## 금지사항 / 주의사항
- 컴포넌트 구조·장바구니·체크아웃·probador(TryOn) 로직 변경 금지. 이번 작업은 **토큰/스킨 레이어만**.
- `pool.connect()` 수동 사용 금지, main pool에 신규 상시 조회 추가 금지(반드시 readonly + 캐시).
- 자유 색상 무제한/요소 드래그 빌더 금지(Phase 1 범위 밖, hallmark 슬롭 게이트 취지 위반).
- 마이그레이션은 로컬(5432)→검증 후 운영(5434) 순서, 운영 반영은 사용자 승인 게이트.
- 주석 한국어 / 함수·변수명 영어 / 모든 async try-catch.
