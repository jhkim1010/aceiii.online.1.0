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

- **D-43-1**: `wp_channels`/`wp_product_sync` 를 일반화한 신규 `commerce_channels`/`product_sync` 테이블을 만든다. **기존 WC 운영 동작 절대 중단 없음.**
- **D-43-1a (확정 2026-06-26)**: WC 데이터 흡수 방식 = **복사 마이그레이션(Copy Migration)**. 호환 view 가 아님. 이유: 본 phase 의 본질은 데이터 소유권을 단일 테이블로 못 박는 것 — view 는 WC=옛 테이블/신규=새 테이블로 구조를 영구 분할시켜 본질에 위배. 안전장치로 배포를 단계화: ① 새 테이블 생성 → ② `INSERT...SELECT` 복사 → ③ 코드 전환 → ④ 검증 후에도 옛 `wp_channels`/`wp_product_sync` 는 **한 사이클(최소 1주) 보존**(즉시 DROP 금지) → rollback 가능. DROP 은 별도 후속 phase/태스크에서 사용자 확인 후.
- **D-43-2**: 어댑터는 4가지만 책임진다 — ① 인증 ② HTTP/GraphQL 전송 ③ 페이로드↔공통 DTO 변환 ④ webhook 서명 검증. 비즈니스 로직은 코어가 독점.
- **D-43-3**: fire-and-forget → **outbox 패턴**. 판매 커밋 트랜잭션 내에서 `sync_outbox` INSERT 만 하고, 별도 worker 가 배치로 push. 외부 API I/O 동안 DB 커넥션 미점유.
- **D-43-4**: 이 phase 는 **기능 변경 0**. WC 의 push/webhook 동작이 리팩터 후 100% 동일해야 함(회귀 테스트로 증명). 신규 플랫폼 코드는 포함하지 않음(인터페이스 + WC 어댑터까지만).
- **D-43-5**: `platform` enum = `'woocommerce' | 'tiendanube' | 'shopify' | 'empretienda'`. 이 phase 에선 woocommerce 만 구현.

### 동시성·정합성 결정 (멀티플랫폼 동시 주문 대비 — 2026-06-27 추가)

여러 플랫폼이 동시에 같은 상품 주문을 보낼 때의 충돌·pool 낭비 분석 결과:

- **D-43-6 (ingest 는 외부 API 무호출 + 짧은 트랜잭션)**: 주문 수신 핸들러는 webhook 페이로드만으로 처리. fetch-after-notify(TN minimal payload)가 필요하면 **트랜잭션 밖에서** 먼저 fetch 후, DB 작업은 짧게. → 동시 webhook 이 와도 커넥션을 외부 API 응답 대기로 점유하지 않음 → pool 안전.
- **D-43-7 (재고 차감 = SERIALIZABLE + 40001 재시도)**: 재고 hold 는 Phase 28 의 SERIALIZABLE 격리 패턴 재사용. 여러 플랫폼이 동시에 같은 재고를 차감해도 DB 가 직렬화 → oversell 방지. 직렬화 실패(40001)는 제한 횟수 재시도.
- **D-43-8 (outbox worker 동시성 상한)**: worker 가 한 번에 처리하는 push 건수에 상한(batch size + 동시성 제한). 플랫폼이 늘어도 push I/O 가 DB pool 을 위협하지 않도록 — push 동시성은 worker 농도로 제어(webhook 과 완전 분리).
- **D-43-9 (Phase 48 백본 통일은 동시성 정합성의 필수 종착점)**: 현재 WC 만 suspended-sale 경로(Phase 28 SERIALIZABLE 미보호), 신규 플랫폼은 online_orders 경로(보호됨). "WC + 신규플랫폼 동시 주문"의 경로 불일치는 Phase 48 백본 통일로만 완전 해소. 따라서 48 은 "정리"가 아니라 멀티플랫폼 oversell 방지의 **필수 단계**로 격상.

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
