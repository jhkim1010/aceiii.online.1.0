# 멀티플랫폼 커머스 싱크 — GSD 마스터 플랜

> **목적**: Ventago(POS/ERP)를 Tienda Nube · Empretienda · Shopify · WooCommerce 와 연동하여 **stock · precio · pedido · producto** 를 자동 동기화한다.
> **전제**: WooCommerce 싱크는 이미 production-ready 수준으로 구현됨(`api-ventago/src/app/integrations/wp/`). 이 코드를 **공통 추상화(connector/adapter)** 로 리팩터한 뒤 3개 신규 플랫폼을 동일 인터페이스로 붙인다.
> **작성일**: 2026-06-26 · **방식**: 빌게이츠 다층 사고법 + GSD phase 분해
> **산출물 유형**: 마스터 플랜 문서 (코드 구현은 각 phase 의 `/gsd-spec-phase` 단계에서 진행)

---

## 0. TL;DR — 한 문장 결론

WooCommerce 가 이미 증명한 "채널 모델 + SKU 매핑 + webhook 주문수신 + REST push" 패턴은 **Tienda Nube 와 Shopify 에 1:1로 이식 가능**하다. 다만 **Empretienda 는 공개 API 가 없어** 동일한 실시간 2-way 싱크가 **불가능**하며, 파일(Excel) 기반 반자동 커넥터 또는 certified-partner 경로로 별도 취급해야 한다. 따라서 "4개 플랫폼 전부 동일하게 구현"은 **3.5개만 가능**이 정확한 답이다.

---

## 1. 빌게이츠 다층 사고법 — 표면 / 구조 / 본질

### 1-A. 표면 문제 (사용자가 말한 것)

> "내 시스템과 Tienda Nube·Empretienda·Shopify·WooCommerce 를 연동해서 stock·precio·pedido 를 자동 싱크하고 싶다. 이미 만든 WC 와 싱크하는 모든 기능을 4개 플랫폼에 구현 가능한지 계획을 만들어달라."

표면적으로는 "커넥터를 3개 더 만들면 되는 일"처럼 보인다. WC 가 이미 돌아가니, 복붙해서 API 주소만 바꾸면 될 것 같다.

### 1-B. 구조적 원인 (왜 단순 복붙이 아닌가)

세 가지 구조적 긴장이 숨어 있다.

**(1) WC 코드와 Phase 27/28 백본의 이중 구조.**
현재 Ventago 에는 온라인 주문을 다루는 길이 **두 갈래**다.
- `integrations/wp/` — WooCommerce 전용. 주문이 들어오면 **suspended-sale(보류 판매)** 로 떨어지고, 데스크탑 POS 운영자가 확인해야 진짜 `Sale` 이 된다.
- `online-orders/` (Phase 27/28) — channel-agnostic 백본. `online_orders` 테이블에 `pending → delivered` 라이프사이클이 있고, Phase 28 에서 **재고 hold + sales mirror** 패턴이 완성됨.

WC 는 첫째 길을, Phase 27/28 은 둘째 길을 쓴다. **두 개의 진실 원천(source of truth)** 이 공존한다. 신규 3개를 어느 길에 붙일지 정하지 않으면, 플랫폼마다 주문 처리 방식이 갈라져 회계·재고 정합성이 깨진다. 이것이 가장 깊은 구조적 부채다.

**(2) "공통 추상화" 의 실체.**
WC 싱크는 잘 동작하지만 **추상화돼 있지 않다**. `WcClient`, `WpSyncService`, `WpGuard`, `WpChannel` 모델이 모두 WooCommerce 어휘(consumer_key, wc_product_id, HMAC `x-wp-signature`)에 묶여 있다. Shopify 는 GraphQL + location 개념 + `X-Shopify-Hmac-SHA256`, Tienda Nube 는 OAuth + `inventory_levels` + `x-linkedstore-hmac-sha256` 다. **각 플랫폼의 인증·페이로드·rate limit 이 전부 다르다.** 공통으로 뽑을 수 있는 건 "비즈니스 로직"(SKU 매칭, 재고 cap, 2-tier 가격, 주문→보류판매)이고, 달라지는 건 "전송 어댑터"(auth, HTTP/GraphQL, webhook 서명, 페이로드 변환)다. 이 경계선을 정확히 긋는 것이 리팩터의 핵심.

**(3) 플랫폼 역량의 비대칭.**
조사 결과 4개 플랫폼은 동급이 아니다.

| 역량 | WooCommerce | Tienda Nube | Shopify | Empretienda |
|---|---|---|---|---|
| 공개 API | ✅ REST v3 | ✅ REST 2025-03 | ✅ GraphQL(필수) | ❌ 없음 |
| 인증 | consumer key/secret | OAuth2 per-store | custom app token / OAuth | 비공개 partner only |
| 재고 push | ✅ | ✅ (`inventory_levels`) | ✅ (`inventorySetQuantities`) | ⚠️ Excel import |
| 가격 push | ✅ | ✅ (`promotional_price`) | ✅ (`compareAtPrice`) | ⚠️ Excel import |
| 주문 webhook | ✅ HMAC | ✅ HMAC(3초 timeout) | ✅ HMAC(raw body) | ❌ partner only |
| 벌크 | 변형 batch | `PATCH /products/stock-price` | bulkOperationRunMutation | 3000행 Excel |
| 승인 절차 | 없음 | **ERP homologation 필수** | public 앱만 review | partner 계약 |

**Empretienda 만 근본적으로 다른 등급**이다. 나머지 셋은 "어댑터만 다르고 본질은 같다."

### 1-C. 근본 본질 (진짜 풀어야 하는 것)

이 프로젝트의 본질은 **"커넥터를 N개 만드는 것"이 아니라 "Ventago 를 진정한 single source of truth 로 만들고, 외부 채널을 그 거울(mirror)로 강등시키는 것"** 이다.

소매 현장의 진실은 이렇다. 재고는 물리적으로 매장에 있다. 가격은 ERP 가 정한다. 판매는 POS 와 온라인 양쪽에서 일어나지만 **회계 장부는 하나**여야 한다. 따라서 외부 플랫폼은 "재고/가격을 받아쓰고(push 대상), 주문을 토해내는(webhook 소스)" 수동적 거울일 뿐, 절대 진실의 원천이 아니다.

이 본질이 서면, 모든 설계 결정이 따라 나온다.
- **재고/가격은 항상 Ventago → 플랫폼 단방향 push.** (역방향 pull 은 충돌만 부른다. CLAUDE.md 의 "재고 음수여도 판매 막지 말 것" 원칙과 일치 — 플랫폼 재고를 진실로 믿으면 안 됨.)
- **주문은 항상 플랫폼 → Ventago 단방향 ingest**, 그리고 Phase 28 의 hold+mirror 패턴으로 회계에 흡수.
- **충돌 해결이 거의 필요 없다.** 방향이 고정되면 last-writer-wins 류의 복잡한 reconciliation 이 사라진다. 이것이 pool 낭비와 race condition 을 원천 차단하는 길이다.

즉, 이 작업은 통합 작업이 아니라 **"데이터 소유권을 Ventago 로 못 박는 아키텍처 정리 작업"** 이다. WC 가 우연히 이미 이 방향(stock/price push, order ingest)으로 만들어진 것은 다행이고, 신규 플랫폼은 이 본질을 **명시적 계약(interface)** 으로 승격시켜 따르게 하면 된다.

---

## 2. 목표 아키텍처 — Connector/Adapter 패턴

### 2-A. 디렉터리 구조 (목표)

```
api-ventago/src/app/integrations/
├── core/                          # ★ 신규: 플랫폼 무관 공통 코어
│   ├── commerce-connector.interface.ts   # 모든 플랫폼이 구현하는 계약
│   ├── connector.registry.ts             # platform enum → connector 주입
│   ├── sync-orchestrator.service.ts      # pushProducts() 공통 진입점
│   ├── order-ingest.service.ts           # 주문→suspended/online-order 공통 변환
│   ├── sku-matcher.service.ts            # SKU→Product 매칭 + 변형 그룹핑(WC 로직 이관)
│   ├── stock-resolver.service.ts         # branch stock + cap 계산(WC 로직 이관)
│   ├── price-resolver.service.ts         # 2-tier price_type 해석(WC 로직 이관)
│   ├── outbox.service.ts                 # ★ 신규: 영속 retry 큐(현재 fire-and-forget 대체)
│   └── models/
│       ├── commerce-channel.model.ts     # wp_channels 를 일반화한 channels
│       ├── product-sync.model.ts         # wp_product_sync 일반화
│       └── sync-outbox.model.ts          # 재시도 큐 테이블
├── adapters/                      # ★ 신규: 플랫폼별 전송 어댑터
│   ├── woocommerce/               # 기존 wc-client.ts 를 adapter 로 래핑
│   ├── tiendanube/                # OAuth + inventory_levels + PATCH bulk
│   ├── shopify/                   # GraphQL + locations + bulkOperation
│   └── empretienda/               # Excel import/export 반자동(별도 등급)
└── wp/                            # 기존 코드 — adapter 이관 후 점진 제거
```

### 2-B. 공통 계약 (interface 스케치)

```typescript
// commerce-connector.interface.ts
export interface CommerceConnector {
  readonly platform: CommercePlatform; // 'woocommerce' | 'tiendanube' | 'shopify' | 'empretienda'

  // ── Ventago → 플랫폼 (push) ──
  pushProduct(ch: ChannelCtx, p: ResolvedProduct): Promise<PushResult>;   // 상품 생성/갱신
  pushStock(ch: ChannelCtx, items: StockUpdate[]): Promise<PushResult>;    // 재고(가능하면 벌크)
  pushPrice(ch: ChannelCtx, items: PriceUpdate[]): Promise<PushResult>;    // 가격
  testConnection(ch: ChannelCtx): Promise<boolean>;

  // ── 플랫폼 → Ventago (ingest) ──
  verifyWebhook(headers: Record<string,string>, rawBody: Buffer, secret: string): boolean;
  parseOrder(rawPayload: unknown): NormalizedOrder;  // 플랫폼 페이로드 → 공통 주문 형태

  // ── 인증 수명주기 ──
  ensureAuth(ch: ChannelCtx): Promise<void>;  // OAuth 토큰 갱신 등(WC 는 no-op)
}
```

**핵심 원칙**: 비즈니스 로직(SKU 매칭, cap, 2-tier, hold+mirror)은 `core/` 가 **한 번만** 소유. 어댑터는 오직 (a) 인증 (b) HTTP/GraphQL 전송 (c) 페이로드 ↔ 공통 DTO 변환 (d) webhook 서명 검증만 책임진다.

### 2-C. 두 개의 진실 원천 통합 결정 (구조적 부채 §1-B-1 해소)

**결정 D-A**: 신규 플랫폼은 **WC 의 suspended-sale 경로**가 아니라 **Phase 27/28 의 `online_orders` 백본**으로 통일한다.
- 이유: Phase 28 이 이미 재고 hold + sales mirror + 24h 만료 cron + SERIALIZABLE 격리를 완성했다. 이것이 회계 정합성의 정답이다.
- WC 도 **점진적으로** 이 백본으로 마이그레이션(별도 phase, 비파괴적). 당장은 WC 의 기존 동작 유지.
- 효과: 신규 3개 플랫폼의 주문이 전부 `online_orders` 로 흐르면, 리포트·재고·회계가 **코드 변경 0** 으로 자동 흡수됨(Phase 28 의 mirror 패턴 덕분).

### 2-D. Pool 안전 설계 (사용자 최우선 관심사)

현재 WC `pushOne()`/`pushVariable()` 은 상품당 8~12 쿼리(N+1)에 fire-and-forget. 이건 부채다. 공통 코어에서 다음을 강제한다.

1. **벌크 fetch**: `Product.findAll({ where:{ id: productIds }, include:[Color,Size,Price,ProductBranch] })` — 루프 내 단건 쿼리 제거.
2. **HTTP/GraphQL 호출은 트랜잭션 밖에서**: 외부 API I/O 동안 DB 커넥션을 잡지 않는다.
3. **Outbox 패턴으로 fire-and-forget 대체**: 판매 커밋 시 `sync_outbox` 에 행만 INSERT(같은 트랜잭션). 별도 worker(BullMQ 또는 경량 cron)가 배치로 꺼내 push. → 커넥션이 외부 API 응답을 기다리며 새지 않음. 기존 pool min=10/max=80 유지, 신규 pool 생성 0.
4. **rate-limit 백오프**: 어댑터가 `x-rate-limit-*`(TN), GraphQL cost(Shopify) 헤더를 읽어 worker 가 throttle. 동시성은 worker 농도로 제어 → DB pool 과 분리.

---

## 3. GSD Phase 분해

> 번호 규칙: 현재 빈 슬롯은 **43, 44**, 그 외 46+. (45 = legacy-bulk-import 사용 중)
> 각 phase 는 `.planning/phases/{NN}-{slug}/` 에 `{NN}-CONTEXT.md` + `{NN}-SPEC.md` 로 시작하고, wave 단위로 `{NN}-0X-PLAN.md` 진행.

### Phase 43 — Commerce Core 추상화 (기반 리팩터) 🔴 선행 필수

**slug**: `43-commerce-connector-core`
**목표**: WC 의 비즈니스 로직을 `integrations/core/` 로 추출하고, `CommerceConnector` 인터페이스 + WooCommerce 어댑터를 정의. **기능 변경 0, 동작 동일**(순수 리팩터 + 테스트).
**왜 먼저**: 이게 없으면 신규 플랫폼마다 WC 코드를 복붙 → 4중 중복 → 유지보수 지옥.

Waves:
- 43-01: `commerce_channels` / `product_sync` / `sync_outbox` 모델·마이그레이션 설계(기존 `wp_channels` 를 view 또는 호환 컬럼으로 흡수, 비파괴적)
- 43-02: `sku-matcher` / `stock-resolver` / `price-resolver` 서비스로 WC 로직 이관 + 단위 테스트
- 43-03: `CommerceConnector` 인터페이스 + `WooCommerceAdapter`(기존 `wc-client.ts` 래핑)
- 43-04: `sync-orchestrator` + `outbox` worker(fire-and-forget 대체, pool 안전)
- 43-05: WC 회귀 테스트 — 기존 push/webhook 동작 100% 동일 검증(운영 영향 0)

**산출 기준**: WC 채널이 리팩터 후에도 동일하게 stock/price push + order webhook 동작. ESLint·빌드 통과. pool 사용량 측정(before/after).

---

### Phase 44 — Tienda Nube 커넥터 🟢 가장 높은 ROI

**slug**: `44-tiendanube-connector`
**왜 두 번째**: LATAM 1위 플랫폼 + 공개 REST API 완비 + WC 와 모델이 가장 유사(SKU per-variant, promotional_price, HMAC webhook). 본 프로젝트의 **레퍼런스 구현**이 된다.

Waves:
- 44-01: OAuth2 install/authorize 플로우 + per-store 토큰 저장(`commerce_channels` 확장) + `User-Agent` 헤더 규약
- 44-02: `TiendaNubeAdapter` — 상품/변형 push(`PUT /products/{id}/variants`), 재고/가격 벌크(`PATCH /products/stock-price`, `inventory_levels`)
- 44-03: webhook 수신(`order/created`·`order/paid`·`product/updated`) + `x-linkedstore-hmac-sha256` 검증 + **3초 timeout 대응**(즉시 200, async 처리) + minimal payload → fetch-after-notify
- 44-04: 주문 → `online_orders` ingest(D-A 경로) + Phase 28 hold+mirror 연결 + idempotency(at-least-once 대비 dedup)
- 44-05: 관리 UI(채널 CRUD·sync 토글·연결 테스트) + multi-location(`/locations`) 매핑 + UAT
- 44-06: ERP homologation 준비(시퀀스 다이어그램·데모 영상·검증 미팅) — **출시 게이트**

**리스크**: homologation 승인 리드타임(미팅 필요). 데모 스토어 10상품 제한 → 부하 테스트는 실 스토어 필요.

---

### Phase 46 — Shopify 커넥터 🟡 GraphQL 전환 비용

**slug**: `46-shopify-connector`
**왜 세 번째**: 글로벌 표준이지만 **GraphQL-only**(2025년부터 REST 신규 금지)라 어댑터 작성 패러다임이 WC/TN(REST)과 다름. 코어가 안정된 뒤 진행이 안전.

Waves:
- 46-01: custom app access token(`X-Shopify-Access-Token`) 또는 OAuth + **API 버전 핀**(`2026-04`) + protected customer data 승인 절차
- 46-02: `ShopifyAdapter` GraphQL — `productSet`(카탈로그), `productVariantsBulkUpdate`(가격·compareAtPrice), `inventorySetQuantities`(location별 재고, source-of-truth=Ventago)
- 46-03: ERP 지점 → Shopify Location 매핑 테이블
- 46-04: webhook(`orders/create`·`orders/paid`) + **raw-body HMAC**(NestJS body-parser 순서 주의 — `rawBody:true`) + SKU 매칭
- 46-05: 대형 카탈로그용 `bulkOperationRunMutation`(JSONL staged upload) + GraphQL cost 기반 rate-limit 백오프
- 46-06: 주문 → `online_orders` ingest + UAT + 분기별 API 버전 bump 유지보수 태스크 등록

**리스크**: GraphQL cost 버킷 관리, 분기 버전 deprecation 추적, protected customer data 승인.

---

### Phase 47 — Empretienda 반자동 커넥터 🔴 등급이 다름 (별도 취급)

**slug**: `47-empretienda-file-connector`
**왜 마지막 & 별도**: **공개 API 없음.** 실시간 2-way 싱크 불가. 동일 인터페이스를 강제하면 안 됨 — 정직하게 "best-effort 파일 커넥터"로 설계.

옵션 (우선순위):
- **(권장) 파일 기반 반자동**: OUT — `Mi cuenta > Integraciones y API` 의 price-list/orders Excel export URL 주기 폴링·파싱. IN — 3000행 상품 Excel 생성 후 panel 업로드(스토어 OFF 필요).
- (대안) certified-partner 신청 — OAuth+실시간 주문 접근 가능하나 NDA·인증·계약 필요, scope 제한(stock/price write 보장 X).

Waves:
- 47-01: 타당성 재확인 + Empretienda partner team 컨택(실시간 경로 가능성 타진) → **go/no-go 결정 게이트**
- 47-02: `EmpretiendaAdapter`(file mode) — `CommerceConnector` 의 부분 구현(pushStock/pushPrice → Excel 생성; parseOrder → Excel export 파싱)
- 47-03: 주문 export 폴링 cron + **per-line 단가 부재 한계 보정**(총액÷수량, 수동 검수 플래그)
- 47-04: 운영자 워크플로우 UI("Empretienda 동기화" — 다운로드/업로드 가이드) + 한계 명시

**리스크**: 가장 큼. 단가 정보 부재로 회계 정확도 저하. 스토어 OFF 업로드는 운영 마찰. **사용자가 이 한계를 수용할지 사전 합의 필요.**

---

### Phase 48 (선택) — WooCommerce 백본 통일 + 관측성

**slug**: `48-wc-backbone-unify-observability`
**목표**: WC 의 suspended-sale 경로를 `online_orders` 백본으로 마이그레이션(D-A 완성) + 4개 플랫폼 공통 싱크 대시보드(outbox 상태·실패율·rate-limit 히트·last_synced) + 알림.
**왜 마지막**: 신규 플랫폼이 안정된 뒤 WC 를 정리해야 운영 리스크 최소.

---

## 4. 의존성 그래프

```
Phase 43 (Core) ──┬──> Phase 44 (TiendaNube) ──> Phase 46 (Shopify)
   [선행 필수]      │                                      │
                   └──> Phase 47 (Empretienda, 병렬 가능)   │
                                                           v
                                        Phase 48 (WC 통일 + 관측성)
```

- **43 은 절대 선행.** 코어 없이 신규 커넥터 작성 금지(중복 부채).
- 44 → 46 순서 권장(REST 레퍼런스로 패턴 확립 후 GraphQL).
- 47 은 43 이후 언제든 병렬(코어 인터페이스의 부분 구현이므로).

---

## 5. 구현 가능성 — 최종 판정표

| 플랫폼 | stock | precio | pedido | producto | 종합 판정 |
|---|:---:|:---:|:---:|:---:|---|
| **WooCommerce** | ✅ | ✅ | ✅ | ✅ | **완료**(리팩터만 필요) |
| **Tienda Nube** | ✅ | ✅ | ✅ | ✅ | **완전 구현 가능** (homologation 게이트) |
| **Shopify** | ✅ | ✅ | ✅ | ✅ | **완전 구현 가능** (GraphQL 전환) |
| **Empretienda** | ⚠️ | ⚠️ | ⚠️ | ⚠️ | **부분만 가능** (파일 반자동 / partner 경로) |

> "이미 만든 WC 와 싱크하는 모든 기능을 4개에 구현 가능한가?" → **WC·TN·Shopify 는 YES, Empretienda 는 NO(반자동만).** 3.5/4.

---

## 6. 지금 당장 실행할 단계별 액션 플랜

1. **이 마스터 플랜 합의 (오늘)** — §2-C 의 결정 D-A(신규 플랫폼은 `online_orders` 백본)와 §5 의 Empretienda 한계를 사용자가 수락하는지 확정.
2. **Phase 43 스펙 착수** — `/gsd-spec-phase 43` 로 CONTEXT/SPEC 생성. 첫 결정사항: `wp_channels` → `commerce_channels` 비파괴 흡수 전략(view vs 컬럼 추가).
3. **DB 스키마 확인 선행** — 마이그레이션 작성 전 `.planning/intel/db-schema-tables.md` 로 `wp_channels`·`online_orders`·`Stocks`·`ProductBranch` 컬럼 재확인(추측 금지).
4. **Outbox PoC** — 43-04 의 `sync_outbox` + worker 를 로컬 PG18 에서 pool 측정과 함께 검증(min=10/max=80 유지, 신규 pool 0 확인).
5. **Tienda Nube Partner 등록 병행** — homologation 리드타임이 기니 Phase 44 코드와 무관하게 **지금 파트너 신청** 시작.
6. **Empretienda partner team 컨택(병렬)** — 실시간 경로 가능성을 일찍 타진해야 47 의 go/no-go 가 빨라짐.

---

## 7. 내가(사용자가) 빠지기 쉬운 함정 3가지

1. **"WC 가 되니 복붙하면 된다"는 착각.** WC 코드는 WooCommerce 어휘에 강결합돼 있고 추상화돼 있지 않다. Phase 43(코어 추출) 없이 신규 커넥터를 만들면 4벌의 중복 비즈니스 로직이 생겨 cap/가격/재고 규칙이 플랫폼마다 어긋난다. **반드시 43 선행.**

2. **양방향 재고 싱크 욕심.** "플랫폼에서 팔리면 재고를 pull 해오자"는 유혹은 race condition 과 무한 pool 점유를 부른다. 본질(§1-C)은 **재고/가격 = push only, 주문 = ingest only**. 방향을 고정해야 충돌 해결 로직이 사라지고 pool 이 안전해진다. CLAUDE.md 의 "재고 음수여도 판매 막지 말 것" 과도 일치 — 플랫폼 재고를 진실로 믿지 마라.

3. **Empretienda 를 나머지 셋과 같은 등급으로 약속하기.** 공개 API 가 없는데 "실시간 싱크"를 약속하면 회계 부정확(per-line 단가 부재)과 운영 마찰(스토어 OFF 업로드)로 신뢰를 잃는다. 처음부터 "best-effort 파일 커넥터"로 기대치를 낮춰 합의하라.

---

## 8. 점검 포인트 — 1주 / 1개월 / 3개월

**1주 후**
- [ ] 마스터 플랜 + D-A 결정 + Empretienda 한계 사용자 사인오프 완료
- [ ] Phase 43 CONTEXT/SPEC 작성, `commerce_channels` 흡수 전략 결정
- [ ] Tienda Nube · Empretienda partner 신청서 제출(리드타임 시작)
- [ ] Outbox PoC 로컬 pool 측정 결과 확보(신규 pool 0 확인)

**1개월 후**
- [ ] Phase 43 완료 — WC 회귀 테스트 100% 통과, pool 사용량 before/after 개선 수치 확보
- [ ] Phase 44(Tienda Nube) Wave 1~3 — OAuth + adapter push + webhook 수신까지 dev 동작
- [ ] TN homologation 미팅 일정 확정
- [ ] 첫 실 스토어 베타 후보 선정(WC 베타와 동일 매장 권장)

**3개월 후**
- [ ] Phase 44 운영 출시(homologation 통과, 베타 매장 stock/price/order 정상 싱크)
- [ ] Phase 46(Shopify) Wave 1~4 — GraphQL adapter + raw-body webhook 검증 완료
- [ ] Phase 47(Empretienda) go/no-go 결정 + 파일 커넥터 PoC
- [ ] 공통 싱크 대시보드(Phase 48) 설계 — outbox 실패율·rate-limit 히트·last_synced 관측

---

## 9. 부록 — 플랫폼별 핵심 기술 레퍼런스 (구현 시 참조)

**Tienda Nube** (api 2025-03, base `https://api.tiendanube.com/2025-03/{store_id}`)
- 인증: OAuth2 authorization_code, 토큰 무만료, `User-Agent` 헤더 필수
- 재고/가격 벌크: `PATCH /products/stock-price` (products[].variants[] 에 price + inventory_levels)
- webhook: `{store_id,event,id}` minimal → API 재조회 필요 / `x-linkedstore-hmac-sha256` / 3초 timeout / at-least-once
- rate limit: leaky bucket 40, 2 req/s(상위 플랜 ×10), `x-rate-limit-*` 헤더
- ⚠️ `stock` 필드 deprecated → `inventory_levels`+`location_id` 사용. 주문 line-item id 는 int64. 주문 생성은 variant_id 사용(SKU 아님)

**Shopify** (GraphQL Admin, 버전 핀 `2026-04`)
- 인증: custom app `X-Shopify-Access-Token`(review 회피) 또는 OAuth(public)
- 카탈로그: `productSet`(create/update 통합) / 가격: `productVariantsBulkUpdate`(price·compareAtPrice) / 재고: `inventorySetQuantities`(location별 절대값)
- webhook: `orders/create`·`orders/paid`, `X-Shopify-Hmac-SHA256`(raw body 필수, NestJS `rawBody:true`)
- rate limit: GraphQL cost 버킷(standard 100 pts/s), `extensions.cost` 확인
- 벌크: `stagedUploadsCreate` → `bulkOperationRunMutation`(JSONL ≤100MB, 동시 5개)
- ⚠️ REST 신규 금지(2025-04~), 분기 버전 deprecation 추적, protected customer data 승인 필요

**WooCommerce** (기존 구현, REST v3 `{site}/wp-json/wc/v3`)
- 인증: consumer key/secret Basic Auth, webhook HMAC `x-wp-signature`(base64 HMAC-SHA256)
- 기존 파일: `wc-client.ts`, `wp-sync.service.ts`(pushOne/pushVariable), `wp-webhook.service.ts`, `wp.guard.ts`
- 채널 모델: `wp_channels`(stock_source_branch_id·stock_cap·2 price_type), `wp_product_sync`(sku↔wc_product_id)

**Empretienda** (공개 API 없음)
- 카탈로그 import: `Productos > Importar`(스토어 OFF 필요, 3000행, IDProduct/IDStock 컬럼, 이미지 불가)
- export: `Mi cuenta > Integraciones y API` price-list/orders Excel URL
- ⚠️ 주문 export 에 per-line 단가 없음(총액만) → ERP 단가 분해 필요. certified partner(Ecomm-App/Doppler) 만 실시간 접근

---

*문서 끝. 다음 단계: `/gsd-spec-phase 43` 으로 Commerce Core 추상화 스펙 착수.*
