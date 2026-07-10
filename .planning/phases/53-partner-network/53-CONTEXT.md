# Phase 53: VentaGO 파트너 네트워크 — 도매상↔소매상 실시간 판매 공유 - Context

**Gathered:** 2026-07-10
**Status:** Ready for spec
**Source:** 기획 요청 (도매상-소매상 실시간 판매 데이터 공유 시스템)

<domain>
## Phase Boundary

소매상(tienda minorista) 매장에서 도매상(mayorista)이 공급한 상품이 팔릴 때, **양측 동의(opt-in)** 하에 해당 판매 이벤트를 도매상 매장에 실시간 공유해 도매상이 생산·재주문 준비를 하루라도 빨리 시작하게 돕는 **서로 다른 store 간(cross-store) 데이터 공유 레이어**.

핵심 불변식 3가지:
1. **동의 없이 어떤 데이터도 흐르지 않는다** — 연결은 양측 accept 후에만 활성(`partner_links.status = 'active'`), 공유 범위는 합의한 카테고리(`shared_categories`)로 제한.
2. **매출 총액·고객 정보는 절대 공유하지 않는다** — 공유 대상은 "상품별 판매 수량 + 재고 잔량"뿐. 금액(단가/매출), 고객명, 결제수단, 마진은 payload 에서 원천 배제.
3. **연결 해제 시 이력 소멸** — `DELETE /partners/:id` 시 `partner_data_shares` 이력도 함께 삭제(양측 언제든 해제 가능). 감사 추적 로그는 별도 보존(누가 언제 연결/해제/공유했는지).

**아키텍처 결정 배경:** Ventago 는 이미 (a) `online_orders` / `restaurant-delivery` 가 사용하는 Socket.io 게이트웨이 패턴, (b) Phase 43 `integrations/core/` 의 outbox 큐(트랜잭션 안 INSERT + cron worker, pool 안전), (c) `sales-create.service.ts` 의 **커밋 후 best-effort 외부 I/O 블록**(프린터·outbox·ledger push 지점), (d) 멀티테넌트 `store_id` FK 격리를 보유한다. 파트너 네트워크는 **신규 도메인이지만 이 4개 기반 위에 얹는다** — 판매 이벤트 캡처는 sales-create 커밋 후 훅, 전달은 outbox 재사용, 실시간 push 는 신규 `/partner` namespace, 격리는 store_id + partner_link 이중 게이트.

본 CONTEXT 는 "무엇을(WHAT)" 이 아니라 회색지대의 "어떻게(HOW)" 를 고정한다.

</domain>

<decisions>
## Implementation Decisions

### 파트너 연결 모델 (Phase 0 Foundation)
- **D-01 (partner_links 대칭 구조):** `partner_links = { id, store_a_id, store_b_id, initiator_store_id, status, shared_categories(jsonb/int[]), created_at, approved_at, revoked_at }`. `store_a_id < store_b_id` 정규화(중복 연결 방지 UNIQUE(store_a_id, store_b_id)). `initiator_store_id` 로 누가 초대했는지 구분. status enum: `pending | active | rejected | revoked`. **역할(도매/소매)은 링크에 저장하지 않음** — 한 매장이 어떤 파트너에겐 공급자, 다른 파트너에겐 소매일 수 있으므로 방향은 "판매가 일어난 store = 소매, 상대 = 도매" 로 이벤트 시점에 파생.
- **D-02 (shared_categories 의미):** 소매상이 판 상품 중 이 카테고리에 속하는 것만 공유. 카테고리 매칭은 **SKU 기준**(도매·소매가 같은 SKU 공유 전제) 또는 소매 매장 자기 카테고리 id 목록. 정확한 매칭 키(SKU vs category_id vs codigo_madre)는 SPEC/PLAN 에서 확정 — db-schema-tables.md 의 `sale_items`/`products` 컬럼 대조 후 결정(추측 금지).
- **D-03 (초대 흐름):** `POST /partners/invite { targetStoreIdentifier, sharedCategories }` → status=pending. 상대 매장이 `PATCH /partners/:id/accept { sharedCategories }`(양측이 각자 공유 범위 독립 설정 — 비대칭 공유 허용) → status=active. `PATCH /partners/:id/reject` → rejected. `DELETE /partners/:id` → revoked + shares 삭제. 매장 식별자는 이메일/store code 등 — 무차별 store_id 노출 금지(IDOR).

### 판매 이벤트 캡처 + 집계 (Phase 1)
- **D-04 (캡처 지점):** `sales-create.service.ts` 의 **커밋 후 best-effort 외부 I/O 블록**(현 line ~362/473, outbox enqueue·ledger push 와 같은 자리)에 파트너 공유 훅 추가. 트랜잭션 밖 — 판매 성공에 영향 0. affectedProductIds + storeId 이미 계산되어 있어 재사용.
- **D-05 (전달 = outbox 재사용):** 파트너 공유는 **Phase 43 outbox 패턴 재사용**(신규 pool 금지). `sync_outbox` 를 확장하거나 `partner_share_outbox` 신규 — op_type='partner_share', payload=최소 필드. cron worker 가 배치 dequeue → 수신 store 의 `partner_data_shares` INSERT + `/partner` namespace emit. 외부 HTTP 아님(같은 DB 내 store 간이므로 직접 INSERT). SPEC 에서 sync_outbox 확장 vs 신규 테이블 확정.
- **D-06 (payload 최소주의 — 프라이버시 하드가드):** 공유 레코드 = `{ partner_link_id, product_sku, quantity_sold, stock_remaining, shared_at }`. **금액·고객·터미널·판매원·결제수단 컬럼 물리적 부재** — 실수로도 새지 않도록 payload DTO 를 화이트리스트로 정의. stock_remaining = 소매 매장 해당 SKU 현재 재고(ProductBranch 합산 또는 매장 총합, SPEC 확정).
- **D-07 (집계 서비스):** 일별/주별 파트너별·SKU별 판매 요약. **실시간 raw share(append) + 주기적 rollup(집계 테이블 or 온디맨드 GROUP BY)** 병행. 도매 대시보드 부하 대비 — raw shares 무한 성장 방지 위해 rollup 후 오래된 raw 정리 정책은 SPEC. 인메모리 캐시(MemoryCacheService, 30~60초 TTL) 로 대시보드 조회 pool 절약.

### 실시간 채널 (Phase 1-2)
- **D-08 (신규 /partner namespace):** Socket.io `@WebSocketGateway({ namespace: '/partner' })` 신규 — 기존 `/envios`·`/restaurant`·`/print-agent`·`/support` 와 동형. room = 도매 store_id. 소매 판매 이벤트 발생 시 해당 파트너(도매) room 에만 카드 단위 payload emit(전체 재조회 회피, pool 절약). Phase 40/42 board gateway 패턴 복제.
- **D-09 (인증/격리):** 게이트웨이 연결 시 JWT + store_id 검증. 한 store 는 자기가 도매측인 active partner_link 의 이벤트만 수신 — room join 전 partner_link 조회로 권한 게이트. cross-store 이므로 store_id 격리를 이중(link status=active + 수신 store 가 링크 당사자)으로 강제.

### 도매 대시보드 (Phase 2)
- **D-10 (조회 API 격리):** `GET /partners/dashboard` 는 요청 store 가 **도매측으로 참여한 active link** 의 shares 만 집계. IDOR 방지 — store_id 는 @GetUser 에서, request body/query 신뢰 금지. 인기 상품 TOP 10 = 전체 파트너 합산 GROUP BY sku ORDER BY sum(quantity_sold). 재고 소진 예측 = 최근 판매속도(일평균) ÷ stock_remaining → "N일 후 품절" 단순 선형 추정(ML 아님, SPEC).
- **D-11 (프론트 격상 vs 신규):** Configuración → **Socios 탭 신규**(초대/수락/연결관리/공유범위) + 도매 대시보드 신규 페이지(`/partners/dashboard` 또는 dashboards 하위). next/dynamic ssr:false 코드스플리팅 필수, SWR 훅(5분 dedup) 로 참조데이터. 실시간 부분만 socket 구독.

### 알림 + 생산 추천 (Phase 3)
- **D-12 (Telegram 재사용):** `scripts/monitor-online-credit.sh` 가 이미 텔레그램 알림 온디맨드 스크립트 보유([[reference_monitor_online_credit]]) — 봇 토큰/전송 패턴 재사용. 파트너 알림 = 임계값(재고 N일치 이하 + 판매속도 급증) 도달 시 도매에게 push. 알림 임계값은 도매가 대시보드에서 설정(D-2 재주문 임계값 연계).
- **D-13 (생산 우선순위 추천):** 판매속도 × 재고잔량(낮을수록 우선) 단순 스코어. 순수 파생 계산 — 신규 ML/외부 API 금지. 이메일 일일 요약은 기존 메일 발송 인프라 확인 후(없으면 Deferred).

### 소매상 혜택 + 고도화 (Phase 4)
- **D-14 (티어/프로모션/재주문):** 우수 파트너 티어(판매량 buckets), 도매→소매 프로모션 전달(공지 push), 자동 재주문 제안(소매 1클릭 → online_order 또는 신규 purchase_order 생성). 재주문이 실제 주문 엔티티를 만드는지/제안만인지는 Phase 4 SPEC 에서 확정 — MVP 는 "제안 표시"까지.

### Claude's Discretion
- **매칭 키(SKU/codigo_madre/category_id):** Ventago 상품 구조상 도매·소매가 동일 SKU 를 공유하는지, codigo_madre 로 묶는지 db-schema + products 모듈 확인 후 PLAN 확정. cross-store SKU 충돌 가능성 검증.
- **sync_outbox 확장 vs partner_share_outbox 신규:** op_type 추가로 흡수 가능하면 재사용, payload 스키마가 크게 다르면 신규. Phase 43 outbox worker 재사용 원칙 유지.
- **rollup 저장 방식:** 집계 테이블(partner_daily_rollup) vs 온디맨드 GROUP BY + 캐시. shares 볼륨 예측 후 결정.
- **감사 로그 저장소:** 기존 `activity_ledger`/`audit_logs` 재사용 vs partner 전용 audit 테이블. 연결/해제/공유 이벤트 기록 필수(D-06 프라이버시 감사 추적).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### DB schema reference (SQL/migration 작성 전 필수 — 추측 금지)
- `.planning/intel/db-schema-tables.md` — 133개 테이블 전체 컬럼. `sale_items`(product_id/quantity/promo 컬럼), `products`(SKU/codigo_madre/category), `product_branches`(재고), `stores`(식별자) 확인 필수
- `.planning/intel/db-schema-fks.md` — 모든 외래 키 관계. store_id 격리 확인

### Backend 재사용 대상 (확장 only)
- `api-ventago/src/app/sales/sales-create.service.ts` — **커밋 후 best-effort 외부 I/O 블록**(line ~362 주석, ~473 outbox enqueue). 파트너 공유 훅 추가 지점(D-04). affectedProductIds/storeId 재사용
- `api-ventago/src/app/integrations/core/outbox.service.ts` + `outbox.cron.ts` + `models/sync-outbox.model.ts` — Phase 43 outbox 큐(트랜잭션 안 INSERT + cron worker, 기존 Sequelize pool 재사용, pool 안전). 파트너 전달에 재사용(D-05)
- `api-ventago/src/app/online-orders/online-orders-board.gateway.ts` — `@WebSocketGateway({ namespace: '/envios' })` board gateway 원형. `/partner` namespace 신규 시 복제(D-08). room 단위 emit 패턴
- `api-ventago/src/app/restaurant-delivery/restaurant-delivery.gateway.ts` — `/restaurant` namespace 동형 참조
- `api-ventago/src/common/socket/websocket.gateway.ts` + `wsCorsOptions` — 공통 소켓 설정
- `api-ventago/src/app/shared/store-clients/` 및 `credit/` — 재사용 아님(파트너는 매출/고객 미공유). **참조 금지 리스트** — payload 에 금액·고객 유입 방지 경계
- `api-ventago/src/app/store/config/storeConfig.model.ts` — store_configs. `use_partner_network`(Boolean, 기본 false) 신규 게이트 후보(Socios 탭 노출)
- MemoryCacheService — 대시보드 조회 캐시(30~60초 TTL, D-07)
- `api-ventago/migrations/` — `partner_links` + `partner_data_shares`(+ rollup/outbox) 신규 테이블. PG18 호환(SERIAL/snake_case/CHECK=enum, add-only idempotent, owner→coolsistema DO 블록). CLAUDE.md 「DB 마이그레이션 적용 규칙」 준수(로컬 5432 + 운영 5434 동시)

### Frontend 재사용/신규 대상
- `ventago-app/src/pages/configuracion/` — Socios 탭 신규 편입 위치
- `ventago-app/src/pages/dashboards/` — 도매 대시보드 신규 페이지 후보(next/dynamic ssr:false)
- `ventago-app/src/hooks/api/` — SWR 훅 패턴(5분 dedup). `usePartnerLinks`/`usePartnerDashboard` 신규
- `ventago-app/src/services/api.service.ts` — apiConnector(get/post/put/**remove()** — .delete 아님)
- 실시간 차트 — 기존 apexcharts(apexcharts-clevision alias) 재사용

### 유사 기능 대비 (cross-branch vs cross-store)
- `[[project_cross_branch_fulfillment]]` — `online_orders.fulfillment_branch_id` 교차 출고는 **같은 store 내** 지점 간. 파트너 네트워크는 **서로 다른 store 간** — 격리 게이트가 근본적으로 다름(같은 store 신뢰 불가). 대조 학습용
- `[[reference_monitor_online_credit]]` — `scripts/monitor-online-credit.sh` 텔레그램 알림 패턴(Phase 3 D-12 재사용)

### 프로젝트 규약
- `CLAUDE.md` — Sequelize underscored(snake_case), pool min=10/max=80(파트너 outbox 신규 pool 금지), 300ms 타겟+코드스플리팅, SWR 5분 dedup, MemoryCache TTL, ESLint(newline-before-return/lines-around-comment/no-unused-vars), apiConnector.remove(), pageSize≤50, DB 마이그레이션 로컬+운영 동시
- `CLAUDE.md 「멀티테넌트 구조」` — store_id FK 격리. 파트너는 이 격리를 **의도적으로 뚫는** 유일 경로 → partner_link status=active 이중 게이트 필수

</canonical_refs>

<specifics>
## Specific Ideas

- **Socios 탭(Configuración):** 「연결된 파트너」목록(매장명·역할 배지·공유 카테고리·연결일·해제 버튼) + 「받은 초대」(수락/거절) + 「초대 보내기」(매장 식별자 입력 + 공유 카테고리 선택). 상태 배지: pending(노랑)/active(초록)/rejected·revoked(회색).
- **도매 대시보드:** 상단 KPI(오늘 공유 판매 수량 합·활성 파트너 수·품절임박 SKU 수) + 파트너별 판매 현황 카드(실시간 갱신) + 인기 상품 TOP 10 막대차트 + 일별 트렌드 라인차트 + 재고 소진 예측 리스트("청바지 M — 3일 후 품절, 재주문 권장").
- **재주문 알림 임계값:** SKU별 또는 카테고리별 "재고 N일치 이하 시 알림" 설정. 도매가 대시보드에서 조정.
- **Telegram 알림 예시:** "파트너 3개 매장에서 청바지 M 오늘 120벌 판매, 재고 3일치 이하 — 생산 우선순위 상위".
- **프라이버시 배너:** Socios 탭·대시보드에 "공유 데이터: 상품별 판매수량·재고만. 매출액·고객정보 미공유" 명시(신뢰 UX).

</specifics>

<deferred>
## Deferred Ideas

- **금액/매출 공유** — 원칙적으로 범위 밖(프라이버시 하드가드). 향후 별도 동의 티어로만 검토.
- **택배/물류 자동 발주** — Phase 4 재주문 제안은 "제안 표시"까지. 실제 발주 자동화는 후속.
- **ML 기반 수요예측** — Phase 2 재고 소진 예측은 선형 추정. ML 은 후속.
- **다자간(N:N) 공급망 그래프** — MVP 는 1:1 파트너 링크. 다단계 공급망 시각화 후속.
- **이메일 일일 요약** — 기존 메일 인프라 없으면 Deferred(Telegram 우선).
- **cross-store SKU 표준화** — 도매·소매 SKU 불일치 시 매핑 테이블은 후속(MVP 는 동일 SKU 전제 또는 수동 매핑).

</deferred>

---

*Phase: 53-partner-network*
*Context gathered: 2026-07-10 (from 기획 요청)*
