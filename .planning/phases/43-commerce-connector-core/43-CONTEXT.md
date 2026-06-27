# Phase 43 — Commerce Connector Core (CONTEXT)

> **유형**: 기반 리팩터 (순수 추상화 추출, 기능 변경 0)
> **선행**: 없음 (전체 멀티플랫폼 싱크의 선행 필수 phase)
> **후속**: Phase 44(Tienda Nube) · 46(Shopify) · 47(Empretienda) 가 이 코어 위에 빌드
> **마스터 플랜**: `.planning/docs/multiplatform-sync-master-plan.md`
> **작성일**: 2026-06-26

---

## 1. 왜 이 phase 인가 (배경)

WooCommerce 싱크(`api-ventago/src/app/integrations/wp/`)는 production-ready 지만 **WooCommerce 어휘에 강결합**돼 있어 추상화돼 있지 않다. Tienda Nube / Shopify 를 붙이려면 비즈니스 로직(SKU 매칭·재고 cap·2-tier 가격·주문 ingest)을 플랫폼 무관 코어로 추출하고, 플랫폼별 차이(인증·전송·webhook 서명·페이로드)를 어댑터로 격리해야 한다.

이 phase 없이 신규 커넥터를 만들면 비즈니스 로직이 N벌 복제돼 cap/가격/재고 규칙이 플랫폼마다 어긋난다. **반드시 선행.**

## 2. 핵심 원칙 (본질)

- **데이터 소유권은 Ventago.** 외부 플랫폼은 거울(mirror).
- **재고/가격 = Ventago → 플랫폼 push only.** (역방향 pull 금지 — race condition + pool 점유 방지)
- **주문 = 플랫폼 → Ventago ingest only.**
- 방향 고정 → 복잡한 충돌 해결(reconciliation) 불필요.

## 3. 확인된 현재 구조 (사실 기반)

### 3-A. 기존 WC 모델 (이관 대상)
- `wp_channels` (`wp-channel.model.ts`): storeId·branchId(UNIQUE)·stockSourceBranchId·channelKey·secret·siteUrl·wcConsumerKey/Secret·stockCap(default 100)·regular/promoPriceTypeId·isActive·lastReceived/PushedAt
- `wp_product_sync` (`wp-product-sync.model.ts`): storeId·branchId·productId·sku·syncEnabled·priceMode('normal'|'normal_promo')·wcProductId·lastSyncedStock·lastSyncedAt. `(branchId, productId)` UNIQUE

### 3-B. ORM = Sequelize (raw pg pool 아님)
DB 접근은 전부 `sequelize-typescript` 모델 경유. `database.module.ts` 의 단일 Sequelize 인스턴스가 pool 관리(min=10, max=80, idle=10s, acquire=15s). **즉 GSD 의 `pool.connect()`/`client.release()` 규칙은 raw pg 가 아니라 "Sequelize 트랜잭션을 외부 I/O 동안 잡지 않기"로 번역된다.** pool 모니터링은 `DatabaseModule.onModuleInit` 에 내장(waiting>0 또는 80% 초과 시 warn).

### 3-C. online_orders 백본 (D-A 타겟 — 이미 준비됨)
`online_orders` 테이블에 신규 플랫폼용 필드가 **이미 존재**:
- `channel` varchar(20), `external_order_id` varchar(120), `metadata` jsonb
- Phase 28 통합 필드: `branch_id`, `mirror_sale_id`, `stock_held_at`, `stock_released_at`, `payment_method_id`
→ 신규 플랫폼 주문은 새 컬럼 거의 없이 이 백본으로 흘릴 수 있다.

### 3-D. 현재 push 트리거 (대체 대상)
`sales-create.service.ts` 가 판매 커밋 후 `wpSyncService.pushProducts(...).catch(...)` 를 **fire-and-forget** 호출. 실패 시 콘솔 warn 만, 재시도 없음. → outbox 패턴으로 대체.

### 3-E. 최신 로그 상태
`error-2026-06-26.log`: WC 싱크 에러 0건. 무관한 `ThemeComponent` React Hook 경고만 반복(별도 hotfix 후보, 본 phase 범위 외).

## 4. Locked Decisions

- **D-43-1**: `wp_channels`/`wp_product_sync` 를 **비파괴적으로** 일반화한다. 신규 `commerce_channels`/`product_sync` 테이블을 만들되, 기존 WC 데이터는 마이그레이션으로 흡수하거나 호환 view 제공. **기존 WC 운영 동작 절대 중단 없음.**
- **D-43-2**: 어댑터는 4가지만 책임진다 — ① 인증 ② HTTP/GraphQL 전송 ③ 페이로드↔공통 DTO 변환 ④ webhook 서명 검증. 비즈니스 로직은 코어가 독점.
- **D-43-3**: fire-and-forget → **outbox 패턴**. 판매 커밋 트랜잭션 내에서 `sync_outbox` INSERT 만 하고, 별도 worker 가 배치로 push. 외부 API I/O 동안 DB 커넥션 미점유.
- **D-43-4**: 이 phase 는 **기능 변경 0**. WC 의 push/webhook 동작이 리팩터 후 100% 동일해야 함(회귀 테스트로 증명). 신규 플랫폼 코드는 포함하지 않음(인터페이스 + WC 어댑터까지만).
- **D-43-5**: `platform` enum = `'woocommerce' | 'tiendanube' | 'shopify' | 'empretienda'`. 이 phase 에선 woocommerce 만 구현.

## 5. Out of Scope (이 phase 가 하지 않는 것)

- Tienda Nube / Shopify / Empretienda 어댑터 실제 구현 (→ 44/46/47)
- WC suspended-sale → online_orders 백본 마이그레이션 (→ 48)
- 공통 싱크 대시보드/관측성 UI (→ 48)
- ThemeComponent React Hook 경고 수정 (무관)
- 양방향 재고 pull (영구 금지)

## 6. 위험 및 주의

- **비파괴 마이그레이션이 최우선.** 운영 WC 채널(ACE 등)이 돌고 있을 수 있으므로, 컬럼/테이블 변경은 add-only + idempotent. `.planning/intel/db-schema-tables.md` 재확인 후 작성.
- ProductBranch 운영=PascalCase quoted vs 로컬=snake 불일치(메모리 참조) — raw query 회피, Sequelize 모델 경유.
- outbox worker 가 새 pool 을 만들지 않도록 기존 Sequelize 인스턴스 재사용.
