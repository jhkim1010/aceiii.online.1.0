# Phase 44 — Tienda Nube Connector (CONTEXT)

> **유형**: 신규 플랫폼 어댑터 (Phase 43 코어 위 첫 구현, 레퍼런스)
> **선행**: Phase 43 (Commerce Connector Core) ✅ 완료
> **후속**: Phase 46 (Shopify) 가 이 어댑터를 레퍼런스로 참고
> **마스터 플랜**: `.planning/docs/multiplatform-sync-master-plan.md`
> **작성일**: 2026-06-27

---

## 1. 왜 이 phase 인가

Phase 43 으로 플랫폼 무관 코어(`CommerceConnector` 인터페이스 + outbox + resolver)가 섰다. Tienda Nube 는 LATAM 1위 + 완전한 공개 REST API + WC 와 모델이 가장 유사(SKU per-variant, promotional_price, HMAC webhook)해서 **첫 신규 어댑터의 레퍼런스**가 된다. 이 phase 가 코어의 인터페이스가 실제로 충분한지 검증한다.

## 2. 확인된 코어 계약 (Phase 43)

어댑터는 `CommerceConnector` 를 구현 (`integrations/core/commerce-connector.interface.ts`):
- push: `pushProduct(ctx, ResolvedProduct)` / `pushStock` / `pushPrice` / `testConnection`
- ingest: `verifyWebhook(headers, rawBody, parsedBody, secret)` / `parseOrder(raw) → NormalizedOrder`
- auth: `ensureAuth(ctx)` (WC=no-op, TN=OAuth 토큰 보장)

`ChannelCtx.externalMeta` (jsonb) 가 플랫폼별 인증 확장 슬롯 — TN 의 access_token, store_id 를 여기 저장.
`ConnectorRegistry` 에 `register(tiendaNubeAdapter)` 추가하면 platform='tiendanube' 라우팅됨.
outbox 의 platform 컬럼은 이미 'tiendanube' 수용.

## 3. Tienda Nube API 역량 (조사 완료, 2026)

- **API**: REST 2025-03, base `https://api.tiendanube.com/2025-03/{store_id}`. JSON snake_case. `User-Agent` 헤더 필수.
- **인증**: OAuth2 authorization_code (per-store). 토큰 무만료(재발급/uninstall 시만 무효). `Authorization: bearer <token>`.
- **상품/변형**: price·stock·sku 는 variant 에. `PUT /products/{id}/variants`(전체 교체), `PATCH /products/{id}/variants`(부분). 상품당 최대 1000 변형.
- **재고**: per-variant. `stock` deprecated → `inventory_levels:[{location_id, stock}]`. `POST /products/{id}/variants/stock`(action replace/variation).
- **가격**: variant 의 `price`/`promotional_price`(네이티브 promo).
- **★ 벌크**: `PATCH /products/stock-price` — 여러 상품×변형의 price+inventory_levels 한 요청. ERP 싱크 핵심.
- **주문**: `GET /orders`, `GET /orders/{id}`. line item 에 `sku`/`variant_id`/`quantity`/`price`. 생성은 variant_id 사용(SKU 아님).
- **webhook**: order/created·paid·updated·cancelled, product/updated. 페이로드 minimal `{store_id,event,id}` → **fetch-after-notify 필수**. 서명 `x-linkedstore-hmac-sha256` = HMAC-SHA256(raw_body, client_secret). **3초 timeout** → 즉시 200, async 처리. at-least-once → 멱등 필수.
- **rate limit**: leaky bucket 40, 2 req/s(상위 ×10). `x-rate-limit-*` 헤더. 429 시 백오프.
- **homologation**: ERP 앱은 동기 승인(미팅+시퀀스다이어그램+데모영상). 데모스토어 10상품 제한.

## 4. WC 와 다른 점 (어댑터가 흡수할 차이)

| 항목 | WooCommerce | Tienda Nube |
|---|---|---|
| 인증 | consumer key/secret (정적) | OAuth2 토큰 (per-store, externalMeta 저장) |
| 재고 모델 | 단일 stock_quantity | inventory_levels[{location_id}] |
| 벌크 | 변형 batch | PATCH /products/stock-price (상품 횡단) |
| webhook 서명 | x-wp-signature (재직렬화) | x-linkedstore-hmac-sha256 (raw body) |
| webhook 페이로드 | 주문 통째 | minimal → API 재조회 |
| timeout | 관대 | 3초 (즉시 ACK) |
| 주문 생성 키 | SKU | variant_id |

## 5. Locked Decisions

- **D-44-1**: 주문은 Phase 27/28 `online_orders` 백본으로 ingest (D-A). WC 의 suspended-sale 경로 안 씀. hold+mirror 패턴 재사용 → 회계/재고 자동 흡수.
- **D-44-2**: webhook 은 **즉시 200 ACK + async 처리**(3초 timeout 대응). minimal payload → `GET /orders/{id}` 재조회(fetch-after-notify). 재조회는 트랜잭션 밖(D-43-6).
- **D-44-3**: OAuth 토큰은 `commerce_channels.external_meta` jsonb 에 저장(access_token, tn_store_id, scope). `ensureAuth` 가 유효성 보장.
- **D-44-4**: 재고/가격 push 는 `PATCH /products/stock-price` 벌크 우선. single 변형은 fallback. inventory_levels + location_id 사용(stock deprecated 회피).
- **D-44-5**: 멱등 — webhook 의 order id 를 `online_orders.external_order_id` 로 dedup(at-least-once 대비). outbox dedupeKey 와 동일 패턴.
- **D-44-6**: rate limit — 어댑터가 `x-rate-limit-*` 읽어 429 시 outbox 재시도(백오프). worker BATCH 상한과 결합.
- **D-44-7**: homologation 은 코드와 분리된 출시 게이트(별도 wave). 코드는 데모스토어로 먼저 검증.

## 6. Out of Scope

- Shopify/Empretienda 어댑터 (→ 46/47)
- WC suspended-sale → online_orders 마이그레이션 (→ 48)
- TN 결제/배송 라벨 연동 (별도)
- 양방향 재고 pull (영구 금지)

## 7. 위험 및 주의

- **homologation 리드타임** — 미팅 필요. 코드 무관하게 **지금 파트너 신청** 병행 권장.
- **OAuth 토큰 수명주기** — uninstall webhook(app/uninstalled) 처리, 토큰 무효 시 채널 비활성.
- **3초 timeout** — webhook 핸들러에서 절대 동기 처리 금지. 즉시 ACK 후 outbox/async.
- **inventory_levels location** — TN 다지점(플랜별 1~N location). Ventago branch ↔ TN location 매핑 필요(externalMeta).
- **rate limit 2 req/s** — 대량 카탈로그는 벌크 PATCH + 백오프. resolver 는 이미 벌크(N+1 제거)라 유리.
- 코어 패턴 준수: `declare id`, `catch(e:unknown)`+errMessage, raw 결과 `as unknown as T[]` (Phase 43 린트 교훈).
