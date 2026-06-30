# SPEC: Phase 43 — Commerce Connector Core
생성일: 2026-06-26

## 목표

WooCommerce 싱크의 비즈니스 로직을 플랫폼 무관 `integrations/core/` 로 추출하고, `CommerceConnector` 인터페이스 + WooCommerce 어댑터 + outbox 기반 push worker 를 구축한다. **기능 변경 0** — WC 의 기존 push/webhook 동작이 리팩터 후 100% 동일해야 한다.

## 배경 및 컨텍스트

상세 배경은 `43-CONTEXT.md` 참조. 핵심:
- 기존 WC 코드: `api-ventago/src/app/integrations/wp/` (wc-client.ts, wp-sync.service.ts, wp-webhook.service.ts, wp.guard.ts, wp-channel/product-sync 모델)
- ORM: Sequelize 단일 인스턴스 (`database.module.ts`, pool min=10/max=80)
- 백본: `online_orders` 테이블에 channel·external_order_id·metadata·Phase28 필드 이미 존재
- 현재 push 트리거: `sales-create.service.ts` 의 fire-and-forget `pushProducts()`

## 기술 스택

- 언어/프레임워크: Node.js / NestJS 11 + TypeScript
- ORM: Sequelize + sequelize-typescript (underscored:true → DB snake_case)
- DB: PostgreSQL (운영 PG10 / 로컬 PG18·PG15) — 단일 Sequelize pool
- ESLint: 프로젝트 ESLint (Warning=빌드 에러. newline-before-return, lines-around-comment, no-unused-vars 주의)
- 큐: outbox 테이블 + 경량 worker (@nestjs/schedule cron 또는 BullMQ — Wave 4 에서 결정)

## 태스크 목록

### Wave 43-01 — 데이터 모델 & 비파괴 마이그레이션
- [ ] TASK-1: `.planning/intel/db-schema-tables.md` 로 wp_channels·wp_product_sync·online_orders 컬럼 최종 재확인 (추측 금지)
- [ ] TASK-2: `commerce_channels` 테이블 생성 — wp_channels 일반화 + `platform` 컬럼. **흡수 = 복사 마이그레이션(D-43-1a 확정)**: `INSERT INTO commerce_channels SELECT ..., 'woocommerce' FROM wp_channels`. 옛 테이블은 DROP 하지 않고 보존. 파일: `migrations/phase43-commerce-channels.sql` (idempotent: `IF NOT EXISTS` + 복사 시 `ON CONFLICT DO NOTHING` 로 재실행 안전)
- [ ] TASK-3: `product_sync` 테이블 생성 — wp_product_sync 일반화(`wc_product_id` → `external_product_id` varchar). 동일하게 `INSERT...SELECT` 복사. 옛 테이블 보존. 파일: `migrations/phase43-product-sync.sql`
- [ ] TASK-4: `sync_outbox` 테이블 설계 — id·store_id·channel_id·platform·op_type('push_product'|'push_stock'|'push_price')·payload jsonb·status('pending'|'processing'|'done'|'failed')·attempts·next_retry_at·last_error·created_at. 파일: `migrations/phase43-sync-outbox.sql`
- [ ] TASK-5: Sequelize 모델 작성 — `core/models/commerce-channel.model.ts`, `product-sync.model.ts`, `sync-outbox.model.ts`

### Wave 43-02 — 비즈니스 로직 코어 추출
- [ ] TASK-6: `core/sku-matcher.service.ts` — wp-webhook.service 의 SKU→Product 매칭 + 변형 그룹핑 로직 이관 (벌크 fetch 로 N+1 제거)
- [ ] TASK-7: `core/stock-resolver.service.ts` — branch stock + cap 계산 로직 이관 (wp-sync.service 의 branchStock/cap)
- [ ] TASK-8: `core/price-resolver.service.ts` — 2-tier price_type 해석 로직 이관
- [ ] TASK-9: 각 resolver 단위 테스트(Jest) — happy/sad path, cap 경계값, variant 그룹핑

### Wave 43-03 — Connector 인터페이스 & WooCommerce 어댑터
- [ ] TASK-10: `core/commerce-connector.interface.ts` — pushProduct/pushStock/pushPrice/testConnection/verifyWebhook/parseOrder/ensureAuth 계약 정의 + 공통 DTO(ResolvedProduct, NormalizedOrder, PushResult)
- [ ] TASK-11: `adapters/woocommerce/woocommerce.adapter.ts` — 기존 wc-client.ts 를 인터페이스 구현으로 래핑 (HMAC 검증·페이로드 변환만, 비즈니스 로직 호출 X)
- [ ] TASK-12: `core/connector.registry.ts` — platform enum → connector 주입 (DI 기반)

### Wave 43-04 — Orchestrator & Outbox Worker (pool 안전 핵심)
- [ ] TASK-13: `core/sync-orchestrator.service.ts` — pushProducts() 공통 진입점. resolver→connector 조합. 외부 API 호출은 트랜잭션 밖
- [ ] TASK-14: `core/outbox.service.ts` — enqueue(트랜잭션 내 INSERT만) + worker(배치 dequeue·push·재시도·백오프). 기존 Sequelize 인스턴스 재사용(신규 pool 0)
- [ ] TASK-15: `sales-create.service.ts` 수정 — fire-and-forget `pushProducts()` → `outbox.enqueue()` 로 교체 (판매 커밋 트랜잭션 내)
- [ ] TASK-16: rate-limit 백오프 골격 — 어댑터가 retry-after/429 신호를 worker 에 전달하는 인터페이스 (실제 플랫폼 구현은 44/46)

### Wave 43-05 — 회귀 검증 & 품질 게이트
- [ ] TASK-17: WC 회귀 테스트 — 기존 push(simple/variable)·order webhook·cancel 이 리팩터 후 동일 동작 (Jest + dev WC 채널 수동 검증)
- [ ] TASK-18: ESLint 검증 — `npx eslint api-ventago/src/app/integrations --fix`, 오류 0개
- [ ] TASK-19: pool 안전 점검 — outbox worker 실행 중 pool 모니터 로그 확인(waiting=0, 신규 pool 생성 0). before/after 사용량 비교
- [ ] TASK-20: 빌드 검증 — `npm run build` (api-ventago, NestJS SWC) 통과

## 완료 기준

- ESLint 오류 0개
- `npm run build` (api-ventago) 통과
- WC push(simple+variable) / order webhook / cancel 동작이 리팩터 전과 100% 동일 (회귀 테스트 PASS)
- outbox worker 가 기존 Sequelize pool 재사용 — 신규 pool 생성 0, waiting=0
- 마이그레이션 idempotent + add-only (운영 WC 채널 무중단)
- `CommerceConnector` 인터페이스 + WooCommerceAdapter 완성 (44/46/47 빌드 가능 상태)

## 금지사항 / 주의사항

- **기능 추가 금지** — 순수 리팩터. 신규 플랫폼 코드(TN/Shopify/Empretienda) 포함 금지
- **마이그레이션은 add-only + idempotent** — DROP/파괴적 변경 금지. 운영 WC 채널 무중단 필수
- **raw SQL query 회피** — ProductBranch PascalCase/snake 불일치 위험. Sequelize 모델 경유
- 외부 API(WC REST) 호출을 DB 트랜잭션 안에서 하지 말 것 (pool 점유)
- 주석 한국어 / 함수·변수명 영어 / 모든 async 에 try-catch
- ESLint: return 위 빈 줄, 주석 위 빈 줄, no-unused-vars 주의
- `.delete()` 아닌 `apiConnector.remove()` (프론트 무관하나 컨벤션)
- 양방향 재고 pull 절대 추가 금지

## Wave 의존성

```
43-01 (모델/마이그레이션) → 43-02 (resolver) → 43-03 (인터페이스/어댑터) → 43-04 (orchestrator/outbox) → 43-05 (회귀/검증)
```

각 wave 는 `43-0X-PLAN.md` 로 분리 실행. wave 완료 시 `43-0X-SUMMARY.md` 작성.
