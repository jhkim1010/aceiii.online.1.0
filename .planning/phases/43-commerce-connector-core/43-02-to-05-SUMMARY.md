# 43-02~05 SUMMARY — 코어 추출 · 인터페이스 · Orchestrator · 배선

> Wave: 43-02/03/04/05 · 상태: ✅ 코드 완료 (정적 검증 PASS, 빌드/테스트는 사용자 Mac)
> 일자: 2026-06-27

## Wave 43-02 — resolver 3종 추출
- `core/stock-resolver.service.ts` — branchStock + applyCap(순수) + resolveMany(N+1 제거 벌크)
- `core/price-resolver.service.ts` — priceAmount + resolveMany(regular/promo 일괄)
- `core/sku-matcher.service.ts` — SKU→Product 매칭 + codigoMadre 변형 그룹핑(벌크 조회)
- `core/__tests__/resolvers.spec.ts` — cap 경계/벌크/그룹핑/폴백 단위 테스트(Jest, 모델 모킹)

## Wave 43-03 — 인터페이스 + WC 어댑터
- `core/commerce-connector.interface.ts` — CommerceConnector 계약 + 공통 DTO(ChannelCtx, ResolvedProduct, NormalizedOrder, PushResult 등)
- `adapters/woocommerce/woocommerce.adapter.ts` — WcClient 래핑. pushProduct/pushStock/pushPrice/testConnection/verifyWebhook(HMAC)/parseOrder. 비즈니스 로직 미포함
- `core/connector.registry.ts` — platform→connector 주입

## Wave 43-04 — Orchestrator + Outbox (pool 안전 핵심)
- `core/outbox.service.ts` — enqueue(트랜잭션 내 INSERT) + tick(worker, BATCH_SIZE=20 상한, 동시 실행 가드, 백오프 재시도). D-43-8 동시성 상한 구현
- `core/sync-orchestrator.service.ts` — OutboxProcessor 구현. resolver로 최신값 산출→connector push. 외부 API는 트랜잭션 밖(D-43-6). enqueuePush(판매 hook용)
- `core/outbox.cron.ts` — 10초 주기 worker tick
- `sales-create.service.ts` 수정 — USE_OUTBOX_SYNC 플래그로 outbox/기존 경로 분기(@Optional 주입, 기본값=기존 경로)

## Wave 43-05 — 배선 + 검증
- `core/commerce-core.module.ts` — 코어 모듈(모델 forFeature + providers + exports)
- `app.module.ts` / `sales.module.ts` — CommerceCoreModule 등록
- 정적 검증 PASS:
  - import 경로 전부 실재(7개 참조 모델 + wc-client)
  - 모델 속성 일치(Stocks.stock/productBranchId, Price.amount, Product.isParent/colorId/sizeId/parentId)
  - no-unused-vars 의심 0
  - newline-before-return 위반 0 (1건 발견→수정)

## 회귀 안전성 (D-43-4)
- ✅ 기존 `integrations/wp/` 디렉터리 **무변경** → WC 기존 동작 회귀 위험 0
- ✅ sales-create 는 feature flag 기본 off → 기존 fire-and-forget WC push 그대로
- ✅ CommerceCoreModule 은 신규 모듈 → 기존 흐름 영향 없음
- ✅ 수정 파일 3개(app.module/sales-create/sales.module)는 추가만, 기존 로직 보존

## 사용자 Mac 검증 결과 (2026-06-27)

- ✅ `npm run build` (nest build) — **0 에러**
- ✅ `npx jest integrations/core` — **11/11 PASS** (cap/벌크/그룹핑/폴백)
- ⚠️ `npx eslint src/app/integrations` — 327 problems. **단, 절반 이상이 기존 `wp/` 디렉터리**(wc-client/wp-sync/wp-webhook/wp.guard) 에서 발생 — 제가 안 건드린 파일. 이 프로젝트의 api-ventago ESLint 는 `no-unsafe-*` strict 라 기존 `wp/` 도 원래 통과 못 함. **api-ventago 빌드는 `nest build`(SWC)라 ESLint 와 무관하게 성공**(CLAUDE.md 의 "Warning이 빌드 막음"은 프론트 ventago-app 규칙).

## 린트 클린업 (신규 파일만 — 2026-06-27)

신규 core/adapter 파일의 `no-unsafe-*` + prettier 위반 제거:
- `core/util/err.ts` 신규 — errMessage(e:unknown)/isUniqueViolation 헬퍼
- 모든 `catch (e: any)` → `catch (e: unknown)` + errMessage
- raw 쿼리 결과에 인터페이스 타입(ProductLite/ChildLite/NamedRow/ResolvedPriceEntry 등) — `as unknown as T[]`
- 어댑터: WcProductPayload/WcOrderPayloadLoose 타입 정의로 `any` 제거
- prettier: 모델 status 컬럼·테스트 provider 객체·item 객체 줄바꿈 정리
- 검증: 신규 파일에 `: any`/`catch(e:any)` 잔존 0, errMessage import 전부 연결

## 후속 (사용자 Mac)
- ⏳ `npx eslint src/app/integrations/core src/app/integrations/adapters --fix` — 신규 파일만 대상. 남은 prettier 줄바꿈은 --fix 자동 해결. no-unsafe 는 타입 명시로 해결됨
- ⏳ (선택) USE_OUTBOX_SYNC=true 스모크 + pool 모니터(waiting=0) 확인
