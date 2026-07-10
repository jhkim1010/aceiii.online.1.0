# SPEC: Phase 53 — VentaGO 파트너 네트워크 (도매상↔소매상 실시간 판매 공유)

생성일: 2026-07-10

## 목표

소매상 매장에서 도매상 공급 상품이 팔릴 때, **양측 동의 하에** 상품별 판매 수량·재고 잔량을 실시간으로 도매상에 공유해 생산·재주문을 조기에 시작하게 돕는다. **매출 총액·고객 정보는 절대 공유하지 않는다.** cross-store 격리를 partner_link 이중 게이트로 강제하며, 판매 성능·pool 에 영향 0(커밋 후 best-effort + outbox 재사용).

## 배경 및 컨텍스트

상세 배경은 `53-CONTEXT.md`, 검증은 `53-RESEARCH.md` 참조. 핵심:
- 판매 캡처 = `sales-create.service.ts` 커밋 후 best-effort 블록(트랜잭션 밖).
- 전달 = Phase 43 `integrations/core/` outbox 큐 재사용(신규 pool 0).
- 실시간 = Socket.io 신규 `/partner` namespace(기존 `/envios`·`/restaurant` 동형).
- 격리 = store_id FK + partner_links.status='active' 이중 게이트.
- 유사하나 다름: cross-branch(같은 store 내)와 근본적으로 다른 cross-store 신뢰 경계.

## 기술 스택

- 언어/프레임워크: Node.js / NestJS 11 + TypeScript
- ORM: Sequelize + sequelize-typescript (underscored:true → DB snake_case)
- DB: PostgreSQL 18 (로컬 5432 / 운영 5434) — 단일 Sequelize pool(min=10/max=80)
- 실시간: Socket.io (신규 namespace `/partner`)
- 큐: Phase 43 outbox 패턴 재사용(트랜잭션 안 INSERT + @nestjs/schedule cron worker)
- 캐시: MemoryCacheService(대시보드 30~60초 TTL)
- 프론트: Next.js 13 Pages Router + MUI 5 + Redux Toolkit + SWR(5분 dedup) + apexcharts-clevision
- 알림: Telegram(scripts/monitor-online-credit.sh 봇 패턴 재사용)
- ESLint: 프로젝트 규칙(Warning=빌드 에러. newline-before-return, lines-around-comment, no-unused-vars)

## 요구사항 (Requirements)

- **RPN-1 (연결 인프라):** 매장이 다른 매장에 파트너 초대를 보내고, 상대가 수락하면 양측 동의 연결이 성립한다. 각 측이 독립적으로 공유 카테고리를 설정한다(비대칭 허용). 언제든 해제 가능하며 해제 시 공유 이력이 삭제된다.
- **RPN-2 (판매 캡처+공유):** 소매 판매 커밋 후, 공유 카테고리에 속한 상품의 판매 수량·재고 잔량이 도매 파트너에게 전달된다. 판매 트랜잭션·pool 에 영향 0.
- **RPN-3 (프라이버시 하드가드):** 공유 payload 에 금액·고객·판매원·터미널·결제수단이 물리적으로 부재한다. 모든 연결/해제/공유 이벤트가 감사 로그에 남는다.
- **RPN-4 (실시간 도매 대시보드):** 도매가 파트너별 판매 현황·인기 상품 TOP 10·일별 트렌드·재고 소진 예측을 실시간으로 본다. 조회는 요청 store 가 도매측인 active link 로만 격리된다.
- **RPN-5 (알림+생산 추천):** 임계값(재고 N일치 이하) 도달 시 Telegram 알림. 판매속도×재고잔량 기반 생산 우선순위 추천.
- **RPN-6 (소매 혜택):** 우수 파트너 티어, 도매→소매 프로모션 전달, 자동 재주문 제안(MVP=제안 표시).

## 태스크 목록 (Wave = Phase 0~4)

### Wave 53-01 — Phase 0: 파트너 연결 인프라 (Foundation)
- [ ] TASK-1: `.planning/intel/db-schema-tables.md` 로 sale_items·products·product_branches·stores 컬럼 최종 확인(매칭 키 SKU/codigo_madre/category_id 확정 — 추측 금지)
- [ ] TASK-2: 마이그레이션 `phase53-partner-links.sql` — `partner_links { id, store_a_id, store_b_id(UNIQUE 쌍, a<b 정규화), initiator_store_id, status CHECK('pending','active','rejected','revoked'), shared_categories jsonb, created_at, approved_at, revoked_at }`. add-only idempotent(IF NOT EXISTS) + owner→coolsistema DO 블록
- [ ] TASK-3: 마이그레이션 `phase53-partner-data-shares.sql` — `partner_data_shares { id, partner_link_id FK, product_sku, quantity_sold, stock_remaining, shared_at }`. **금액·고객 컬럼 부재**. FK ON DELETE CASCADE(링크 해제 시 이력 삭제) + FK 인덱스
- [ ] TASK-4: 마이그레이션 `phase53-store-config-partner.sql` — store_configs `use_partner_network BOOLEAN NOT NULL DEFAULT false`(Socios 탭 게이트)
- [ ] TASK-5: Sequelize 모델 — `partner/models/partner-link.model.ts`, `partner-data-share.model.ts` (snake_case 매핑, store 관계)
- [ ] TASK-6: `partner/partner.service.ts` — invite/accept/reject/revoke + findScoped(IDOR 가드: store_id=@GetUser). a<b 정규화, UNIQUE 중복 초대 방지, 상대 매장 식별자→store_id 해석(이메일/store code, 무차별 노출 금지)
- [ ] TASK-7: `partner/partner.controller.ts` — `POST /partners/invite`, `PATCH /partners/:id/accept`, `PATCH /partners/:id/reject`, `DELETE /partners/:id`, `GET /partners`(내 연결/받은 초대). @Auth + SessionGuard 검토
- [ ] TASK-8: 감사 로그 배선 — 연결/해제/공유 이벤트를 기존 activity_ledger/audit_logs 재사용 or partner 전용 audit 에 기록(RESEARCH 결과 따라 확정)
- [ ] TASK-9: `partner.service.spec.ts` — 정규화/중복방지/IDOR/해제시 cascade 단위 테스트

### Wave 53-02 — Phase 1: 판매 이벤트 캡처 + 집계
- [ ] TASK-10: `partner/partner-share.service.ts` — `capturePartnerSale(storeId, affectedProductIds, saleItems)`: 소매 store 의 active partner_links 조회 → 공유 카테고리 교집합 SKU 필터 → **화이트리스트 DTO**(sku/quantity/stock_remaining) 생성. 금액·고객 유입 원천 차단
- [ ] TASK-11: `sales-create.service.ts` **커밋 후 best-effort 블록**에 `capturePartnerSale` 훅 추가(트랜잭션 밖, try-catch 무시 로깅, outbox enqueue 옆). 판매 성공 영향 0
- [ ] TASK-12: outbox 전달 — Phase 43 `sync_outbox` op_type='partner_share' 확장 vs `partner_share_outbox` 신규(RESEARCH 결정). cron worker 가 dequeue → `partner_data_shares` INSERT + `/partner` emit. **기존 Sequelize pool 재사용(신규 pool 0)**
- [ ] TASK-13: 집계 서비스 `partner-aggregation.service.ts` — 일별/주별 파트너별·SKU별 판매 요약(rollup 테이블 or 온디맨드 GROUP BY + MemoryCache 30~60초). raw shares 정리 정책 포함
- [ ] TASK-14: stock_remaining 계산 — 소매 매장 해당 SKU 현재 재고(product_branches 합산, RESEARCH 확정 범위). 벌크 fetch(N+1 금지)
- [ ] TASK-15: `partner-share.service.spec.ts` — 카테고리 필터/화이트리스트/금액배제/pool 안전 테스트

### Wave 53-03 — Phase 2: 도매 대시보드 (실시간 + 조회 API)
- [ ] TASK-16: `partner/partner.gateway.ts` — `@WebSocketGateway({ namespace: '/partner', cors: wsCorsOptions })`. room=도매 store_id. 연결 시 JWT+store_id 검증, active link 당사자만 join. 카드 단위 emit(online-orders-board.gateway 복제)
- [ ] TASK-17: `GET /partners/dashboard` — 요청 store 가 **도매측 active link** 인 shares 만 집계(IDOR: store_id=@GetUser). KPI + 파트너별 현황 + TOP 10(GROUP BY sku ORDER BY sum(quantity_sold)) + 일별 트렌드. MemoryCache
- [ ] TASK-18: 재고 소진 예측 — 최근 일평균 판매속도 ÷ stock_remaining → "N일 후 품절" 선형 추정(ML 아님). `GET /partners/dashboard/forecast`
- [ ] TASK-19: 프론트 Socios 탭 — `configuracion` 편입. 연결 목록/받은 초대(수락·거절)/초대 보내기(매장 식별자+카테고리). 상태 배지 + 프라이버시 배너. `use_partner_network` 게이트
- [ ] TASK-20: 프론트 도매 대시보드 — 신규 페이지(next/dynamic ssr:false). KPI + 카드(socket 구독 실시간) + TOP 10 막대(apexcharts) + 트렌드 라인 + 소진예측 리스트. SWR 훅 `usePartnerDashboard`/`usePartnerLinks`
- [ ] TASK-21: ESLint 검증 — eslint-guardian subagent(front+back)

### Wave 53-04 — Phase 3: 알림 + 생산 추천
- [ ] TASK-22: 재주문 임계값 설정 — 도매가 SKU/카테고리별 "재고 N일치 이하 알림" 설정 저장(partner_link 또는 신규 partner_alert_config)
- [ ] TASK-23: Telegram 알림 — scripts/monitor-online-credit.sh 봇 패턴 재사용. 임계값 도달 + 판매속도 급증 시 도매에게 push
- [ ] TASK-24: 생산 우선순위 추천 — 판매속도×재고잔량 스코어(낮을수록 우선) 파생 계산. `GET /partners/dashboard/production-priority`
- [ ] TASK-25: (조건부) 이메일 일일 요약 — 기존 메일 인프라 있으면 구현, 없으면 Deferred 기록

### Wave 53-05 — Phase 4: 소매 혜택 + 고도화
- [ ] TASK-26: 우수 파트너 티어 — 판매량 buckets 파생 배지(소매 대상)
- [ ] TASK-27: 도매→소매 프로모션 전달 — 공지 push(`/partner` emit + 소매 UI 배너)
- [ ] TASK-28: 자동 재주문 제안 — 소진 임박 SKU 를 소매에게 "재주문 제안" 표시(MVP: 제안까지. 실제 주문 엔티티 생성은 Deferred/후속 SPEC)
- [ ] TASK-29: 통합 검증 — cross-store 격리 E2E(비당사자 store 가 타 파트너 데이터 조회/수신 불가), 프라이버시 payload 스냅샷(금액·고객 부재 assert), pool 모니터(waiting=0)

## 보안 / 프라이버시 (필수 게이트)

- **동의 없이 무공유:** partner_links.status='active' + 양측 accept 전 어떤 share 도 생성 금지.
- **payload 화이트리스트:** DTO 에 sku/quantity_sold/stock_remaining/shared_at 만. 금액·고객·판매원·터미널·결제수단 컬럼 물리적 부재. TASK-29 스냅샷 테스트로 회귀 방지.
- **감사 추적:** 연결/해제/공유 로그 보존(누가·언제·무엇을).
- **해제 시 이력 삭제:** DELETE /partners/:id → partner_data_shares CASCADE 삭제(감사 로그는 별도 보존).
- **cross-store 이중 격리:** 모든 조회·socket join 에서 store_id(@GetUser) + active link 당사자 검증. request body/query 신뢰 금지(IDOR).

## 완료 기준

- ESLint 오류 0개(front+back), `npm run build`(api-ventago) 통과
- 초대→수락→판매→도매 실시간 수신 E2E PASS(양측 동의 후에만 흐름)
- 프라이버시 payload 스냅샷 테스트 PASS(금액·고객 부재 assert)
- cross-store 격리 테스트 PASS(비당사자 접근 차단)
- outbox worker 가 기존 Sequelize pool 재사용 — 신규 pool 0, waiting=0
- 마이그레이션 add-only idempotent + owner→coolsistema(운영 5434 무중단), 로컬 5432 동시 적용
- 해제 시 shares CASCADE 삭제 확인, 감사 로그 보존 확인

## 금지사항 / 주의사항

- **매출 총액·고객 정보 공유 절대 금지** — payload 화이트리스트 하드가드. 실수 유입 방지 DTO+테스트
- **동의 없는 공유 금지** — active link 전 share 생성 금지
- **신규 pool 생성 금지** — 파트너 outbox/실시간 모두 기존 Sequelize pool 재사용
- **판매 트랜잭션 안에서 파트너 공유 금지** — 커밋 후 best-effort(pool 점유 최소화)
- **cross-branch 격리 신뢰 금지** — 같은 store 내 로직 재사용 시 cross-store 신뢰 경계 별도 검증([[project_cross_branch_fulfillment]] 대조)
- **마이그레이션 add-only + idempotent + owner 이전** — DROP 금지, 운영 5434+로컬 5432 동시(한쪽만 금지)
- 주석 한국어 / 함수·변수명 영어 / 모든 async try-catch
- ESLint: return 위 빈 줄, 주석 위 빈 줄, no-unused-vars. 프론트 `apiConnector.remove()`(.delete 아님), pageSize≤50, next/dynamic ssr:false, SWR 5분 dedup

## Wave 의존성

```
53-01 (Phase0 연결 인프라)
   → 53-02 (Phase1 캡처+집계)
      → 53-03 (Phase2 대시보드/실시간)
         → 53-04 (Phase3 알림/추천)
            → 53-05 (Phase4 혜택/고도화)
```

각 wave 는 `53-0X-PLAN.md` 로 분리 실행. wave 완료 시 `53-0X-SUMMARY.md` 작성. Phase 0(53-01)이 나머지 전부의 데이터 기반이므로 최우선.
