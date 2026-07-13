# Phase 56: VentaGO 파트너 네트워크 - Research

**Researched:** 2026-07-10
**Domain:** cross-store 판매 이벤트 실시간 공유 + outbox 전달 + Socket.io + 프라이버시 하드가드
**Confidence:** HIGH (기반 4개 — sales-create 훅·outbox·gateway·store_id 격리 — 모두 코드로 검증)

<user_constraints>
## User Constraints (from 56-CONTEXT.md)

### Locked Decisions (D-01 ~ D-14)
- **D-01:** partner_links 대칭 구조(a<b 정규화, initiator 구분, status enum, 역할은 이벤트 시점 파생). **측별 공유범위 = `shared_categories_a`/`shared_categories_b` 2컬럼**(비대칭 공유 D-03 구현. 단일 컬럼 금지).
- **D-02:** 매칭 키 = **SKU 또는 codigo_madre**(category_id 제외 — cross-store 매칭 불가). 도매·소매 SKU 불일치는 기존 `sku-matcher.service.ts` 재사용. 최종 컬럼만 db 대조로 확정.
- **D-03:** 초대→수락(양측 독립 공유범위, 측별 2컬럼)→해제(shares 삭제). 매장 식별자 IDOR 방지.
- **D-04:** 캡처 = sales-create 커밋 후 best-effort 블록(트랜잭션 밖).
- **D-05:** 전달 = Phase 43 outbox worker/재시도 재사용(신규 pool 금지, 같은 DB 내 직접 INSERT). **저장은 `partner_share_outbox` 신규 테이블 확정**(sync_outbox.channel_id/platform NOT NULL).
- **D-06:** payload 화이트리스트 = sku/quantity_sold/stock_remaining/shared_at. 금액·고객 물리적 부재.
- **D-07:** 집계 = 실시간 append + rollup 병행 + MemoryCache.
- **D-08:** 신규 `/partner` Socket.io namespace, room=도매 store_id, 카드 단위 emit.
- **D-09:** 게이트웨이 JWT+store_id 검증, active link 당사자만 수신.
- **D-10:** 대시보드 조회 = 도매측 active link 만 격리(IDOR: @GetUser).
- **D-11:** Socios 탭 신규 + 도매 대시보드 신규 페이지(next/dynamic ssr:false).
- **D-12:** Telegram = monitor-online-credit.sh 봇 패턴 재사용.
- **D-13:** 생산 우선순위 = 판매속도×재고잔량 파생(ML 금지).
- **D-14:** 티어/프로모션/재주문 = MVP 제안 표시까지.

### Claude's Discretion (2026-07-11 리뷰로 2건 해소)
- ✅ 매칭 키: category_id 제외 확정, SKU/codigo_madre 중 최종 컬럼만 PLAN 확정. sku-matcher.service.ts 재사용.
- ✅ outbox: `partner_share_outbox` 신규 테이블 확정(worker 만 재사용).
- rollup 저장 방식(테이블 vs 온디맨드+캐시) — 미해소.
- 감사 로그 저장소(activity_ledger/audit_logs 재사용 vs 전용) — 미해소(Phase 0 안에서 확정 필요).

### Deferred (OUT OF SCOPE)
- 금액/매출 공유, 물류 자동 발주, ML 수요예측, N:N 공급망 그래프, 이메일 요약(인프라 없으면), cross-store SKU 표준화.
</user_constraints>

<phase_requirements>
## Phase Requirements (RPN-1 ~ RPN-6)
연결 인프라(양측 동의·비대칭 공유·해제 이력삭제) / 판매 캡처+공유(판매 영향 0) / 프라이버시 하드가드(금액·고객 부재·감사) / 실시간 도매 대시보드(격리) / 알림+생산추천 / 소매 혜택. 상세는 56-SPEC.md.
</phase_requirements>

<codebase_findings>
## Codebase Findings (검증됨)

### 1. 판매 캡처 지점 — 검증 완료
`api-ventago/src/app/sales/sales-create.service.ts`:
- line ~362 주석: "외부 I/O(프린터·outbox·ledger)는 커밋 후 best-effort 로 트랜잭션 밖에서 실행 (pool 점유 시간 최소화)."
- line ~473~493: Phase 43 `USE_OUTBOX_SYNC` 분기 — `syncOrchestrator.enqueuePush(storeId, resolvedBranchId, affectedProductIds)` 또는 `pushProducts(...)`. try-catch 무시 로깅.
- **결론:** `capturePartnerSale` 를 이 블록에 나란히 추가하면 판매 트랜잭션·pool 영향 0. `storeId`·`resolvedBranchId`·`affectedProductIds` 이미 계산됨 → 재사용.

### 2. Outbox 큐 — 검증 완료
`api-ventago/src/app/integrations/core/`:
- `outbox.service.ts` — enqueue(트랜잭션 안 INSERT) + worker(배치 dequeue·재시도·백오프).
- `outbox.cron.ts` — @nestjs/schedule cron.
- `models/sync-outbox.model.ts` — id·store_id·channel_id·platform·op_type·payload jsonb·status·attempts·next_retry_at·last_error.
- **기존 Sequelize 인스턴스 재사용(신규 pool 0).**
- **검증(2026-07-11):** `sync-outbox.model.ts` 의 `channel_id`(INTEGER)·`platform`(STRING(20)) 가 **NOT NULL**. partner_share 는 이 둘이 무의미 → 흡수 시 운영 커넥터 동기화 스키마를 nullable 로 변경해야 해 회귀 위험.
- **결론(확정):** `partner_share_outbox` **신규 테이블**. cron worker/재시도/백오프 로직만 재사용, 저장은 분리.

### 3. Socket.io 게이트웨이 — 검증 완료
기존 namespace: `/envios`(online-orders-board.gateway.ts), `/restaurant`(restaurant-delivery.gateway.ts), `/print-agent`, `/support`. 공통 `wsCorsOptions`(common/socket/websocket.gateway.ts).
- online-orders-board.gateway: `@WebSocketGateway({ namespace: '/envios', cors: wsCorsOptions })`, room 단위 카드 emit.
- **결론:** `/partner` namespace 신규 = 1:1 복제 + room=도매 store_id + join 전 active link 권한 게이트.

### 4. store_id 격리 vs cross-store — 대조 검증
- 기존 모든 도메인: store_id FK 로 매장 격리(멀티테넌트). 조회는 @GetUser.storeId 로 강제.
- `online_orders.fulfillment_branch_id`(cross-branch): **같은 store 내** 지점 간 — 같은 매장이라 신뢰 가능.
- **파트너 = 서로 다른 store 간** → store_id 만으로 부족. **partner_links.status='active' + 수신 store 가 링크 당사자** 이중 게이트 필수. 이것이 이 Phase 의 근본 신규성.

### 5. Telegram 알림 — 재사용 가능
`scripts/monitor-online-credit.sh`([[reference_monitor_online_credit]]) 봇 토큰/전송 패턴 보유. Phase 3 파트너 알림에 재사용.

### 6. 매칭 키 — 대부분 해소(2026-07-11), 컬럼만 PLAN 확정
- **category_id 제외 확정:** 카테고리는 store 별 로컬 id → cross-store(다른 owner) 에서 매칭 불가.
- **동일성 판정 = SKU/codigo_madre**, 최종 컬럼만 `sale_items`(product_id/quantity)·`products`(sku/codigo_madre)·`product_branches`(재고) db 대조로 PLAN 확정.
- **기존 `integrations/core/sku-matcher.service.ts` 발견·재사용:** 외부↔내부 SKU 매칭 + 미매칭 수동 연결(직원 notes) 폴백 보유(TiendaNube/Shopify 커넥터용). cross-store SKU 불일치를 이 서비스로 흡수 → 신규 매칭 로직 불필요.
</codebase_findings>

<similar_systems>
## 유사 시스템 분석

- **EDI / 852 Product Activity Data (전통 소매 공급망):** 소매 POS 판매·재고를 공급자에 정기 전송해 보충 발주. 파트너 네트워크는 이 개념의 실시간·경량·동의 기반 버전. 배치(852) 대비 Socket.io 실시간 + 카테고리 단위 opt-in 이 차별점.
- **VMI (Vendor Managed Inventory):** 공급자가 소매 재고를 보고 보충. Phase 4 자동 재주문 제안이 경량 VMI 방향(단 MVP=제안까지, 자동 발주 아님).
- **Shopify Collective / 마켓플레이스 실시간 sync:** 판매 이벤트 webhook fan-out. 우리는 같은 DB 내 store 간이라 외부 HTTP 대신 outbox+직접 INSERT(더 단순·안전).
- **차별점:** (a) 프라이버시 하드가드(금액·고객 원천 배제) — 대부분 공급망 시스템은 매출까지 공유, 우리는 의도적 최소주의. (b) 양측 비대칭 opt-in. (c) 기존 Ventago outbox/gateway 기반 위 얹어 신규 인프라 최소.
</similar_systems>

<tech_stack_selection>
## 기술 스택 선택 (근거)

- **전달 = outbox 큐 (BullMQ/Redis 신규 아님):** Phase 43 이 이미 트랜잭션-안전 outbox + cron worker 를 Sequelize 단일 pool 위에 구축. Redis/BullMQ 도입 = 신규 인프라·pool. cross-store 가 같은 DB 내이므로 외부 큐 불필요. **worker 패턴 재사용이 pool 규약·운영 단순성 모두 우위.** 단 저장은 `partner_share_outbox` 신규 테이블(sync_outbox 컬럼 NOT NULL 제약 회피).
- **실시간 = Socket.io 신규 namespace (SSE 아님):** 프로젝트가 이미 Socket.io 표준(4개 namespace). room 기반 타겟 emit·재연결·인증 미들웨어 검증됨. SSE 신규 도입 이점 없음.
- **집계 = PostgreSQL GROUP BY + MemoryCache (분석 DB 아님):** 볼륨 MVP 수준. 별도 OLAP/ClickHouse 과설계. rollup 테이블은 shares 성장 시 도입(단계적).
- **예측 = 선형 추정 (ML 아님):** 일평균 판매속도÷재고. 투명·설명가능·pool 무부하. ML 은 데이터 축적 후 후속.
- **알림 = Telegram (신규 push 인프라 아님):** monitor-online-credit.sh 봇 재사용. 이메일은 기존 인프라 확인 후 조건부.
- **프론트 = MUI5+SWR+apexcharts (프로젝트 표준):** 신규 라이브러리 0. next/dynamic ssr:false 코드스플리팅, SWR 5분 dedup, 실시간만 socket 구독.
</tech_stack_selection>

<risks>
## 리스크 & 완화

- **프라이버시 유출(치명):** payload 에 금액/고객 실수 유입. → DTO 화이트리스트 + 스냅샷 테스트(TASK-15/29)로 회귀 차단.
- **cross-store IDOR:** 비당사자 store 가 타 파트너 데이터 조회/수신. → store_id(@GetUser)+active link 이중 게이트, socket join 권한 검사, E2E 격리 테스트(TASK-29).
- **pool 고갈:** 파트너 공유가 판매 트랜잭션·pool 점유. → 커밋 후 best-effort + outbox(기존 pool), 신규 pool 0, waiting=0 모니터.
- **shares 무한 성장:** raw append 볼륨. → rollup + 오래된 raw 정리 정책(TASK-13).
- **매칭 키 불일치:** cross-store SKU 상이. → 기존 `sku-matcher.service.ts`(수동 연결 폴백) 재사용으로 완화. category_id 매칭은 제외(store 별 로컬 id). 표준화는 Deferred.
- **운영 마이그레이션 갭:** 로컬만 적용 시 운영 500. → CLAUDE.md 규칙대로 5432+5434 동시, owner→coolsistema DO 블록([[project_prod_migration_gap_phase40]] 전례).
</risks>

---

*Phase: 56-partner-network*
*Researched: 2026-07-10*
