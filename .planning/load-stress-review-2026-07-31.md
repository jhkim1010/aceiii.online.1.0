# 동시접속 500 부하 점검 결과

검토일: 2026-07-31  
범위: 현재 워킹트리 정적 분석 및 최신 로컬 로그(앱 코드 변경 없음)  
목표: 무중단, p95 ≤ 300ms, PostgreSQL/pgbouncer 서버 pool 50 유지

## 요약

- 위험 등급: **HIGH**
- 핵심 위험 3가지:
  1. **[HIGH] POS 상품 조회가 `pageSize=1000`으로 규약(최대 50)을 20배 초과**합니다. 500명이 동시에 POS에 진입하면 응답 직렬화, 네트워크, React 렌더링 및 DB 부하가 함께 증가합니다 (`ventago-app/src/views/homes/components/ProductList/ProductList.tsx:194-210`).
  2. **[HIGH] `MemoryCacheService`에 single-flight가 없어 cache stampede가 발생**합니다. TTL 경계에 500개 miss가 동시에 들어오면 동일 집계/참조 쿼리가 워커별로 중복 실행됩니다 (`api-ventago/src/common/cache/memory-cache.service.ts:85-99`).
  3. **[HIGH] 앱 커넥션 예산이 pgbouncer 50 슬롯보다 큽니다.** 메인 4워커 × 20 = 80 client pool에, 같은 DB로 폴백할 수 있는 공개몰 pool이 워커별 최대 5개 추가됩니다 (`api-ventago/src/database/database.module.ts:56-64`, `api-ventago/src/app/shop-public/shop-readonly-db.service.ts:9-40,70-87`). pool max를 늘리지 말고 쿼리/요청 동시성을 줄여야 합니다.

최신 로그 확인 결과:

- `api-ventago/logs/error-2026-07-29.log`: `sequelize.sync` 스키마 불일치가 반복되며, 04:00 `client_segments.store_id` NULL 위반이 기록됐습니다. 배치 재시도/로그 폭증과 멀티테넌트 데이터 경계 오류 후보입니다.
- `api-ventago/logs/combined-2026-07-29.log`: `sync_outbox` 3,015ms, `campaign_recipients` 2,171ms, `online_orders` 876ms 등 300ms 초과 쿼리가 실측됐습니다. `START TRANSACTION` 521ms 및 `COMMIT` 757ms도 있어 당시 pool/DB 큐잉 또는 I/O 포화 징후가 있습니다.
- `ventago-app/logs/error-2026-07-30.log`: webpack deprecation 경고만 있으며 route p95 실측값은 없습니다.

## Pool / DB

- pool max 적정성: **⚠️ HIGH** — 메인 pool은 워커당 `min=2/max=20/acquire=15s`이고 4워커 합계 80입니다 (`api-ventago/src/database/database.module.ts:56-64`). pgbouncer 서버 슬롯 50보다 client-side 대기열이 크며, 15초 acquire는 p95 300ms 목표와 맞지 않습니다. max 증가는 금지하고 N+1/pageSize/stampede를 우선 제거해야 합니다.
- 공개몰 pool: **⚠️ HIGH** — 별도 DB endpoint가 아니면 같은 DB에 워커당 최대 5개를 추가합니다 (`api-ventago/src/app/shop-public/shop-readonly-db.service.ts:19-40,61-87`). 4워커라면 메인 80 + 공개몰 20 client까지 같은 pgbouncer를 경쟁할 수 있습니다. 운영 환경에서 `SHOP_DB_HOST/PORT`가 실제 별도 DB인지 반드시 진단값으로 확인해야 합니다.
- connection 누수: **✓** — 확인한 Sequelize callback transaction은 자동 commit/rollback을 사용합니다. `ShopReadonlyDbService.query()`도 `pool.query()`를 사용해 명시적 client release 누수는 없습니다 (`api-ventago/src/app/shop-public/shop-readonly-db.service.ts:112-120`).
- N+1 의심: **[HIGH]** `api-ventago/src/app/clients/clients.service.ts:311-331` — `stillUnmapped` client마다 `storeClientModel.findAll()`을 순차 실행합니다. 손님 목록 read path에서 오염 데이터 수에 비례해 1+N 쿼리가 발생합니다.
- N+1 의심: **[MEDIUM]** `ventago-app/src/views/box/components/AllCajasOverview.tsx:31-49` — 열린 caja 목록 1회 후 caja마다 `/resume` REST 요청을 병렬 실행합니다. DB 관점의 fan-out N+1이며 50건이면 사용자 1명당 최대 51 요청입니다.
- N+1/긴 transaction: **[MEDIUM]** `api-ventago/src/app/import/import.service.ts:95-108,144-154` — import transaction 내부에서 parent/variant마다 중복 조회와 create를 순차 실행합니다. 대량 import가 pool connection 하나를 오래 점유합니다.
- 순차 DML: **[MEDIUM]** `api-ventago/src/app/cheques/cheques.service.ts:127-142` — cheque마다 create + update를 순차 수행합니다. 건수가 커지면 transaction 점유 시간이 선형 증가합니다.
- lock 사용: **✓/관찰 필요** — outbox와 campaign claim은 `FOR UPDATE SKIP LOCKED`로 워커 경합을 회피합니다 (`api-ventago/src/app/integrations/core/outbox.service.ts:216-251`, `api-ventago/src/app/campaigns/services/campaign-sender.service.ts:184-210`). 다만 최신 로그에서 이 쿼리들이 각각 최대 3,015ms/2,171ms이므로 인덱스와 autovacuum 상태를 스테이징에서 `EXPLAIN (ANALYZE, BUFFERS)`로 확인해야 합니다.

## SWR 캐시

- 미적용 참조 데이터: **[HIGH]** `ventago-app/src/views/homes/components/ProductList/ProductList.tsx:323-333` — branch 목록을 `useEffect + apiConnector.get('/branch')`로 직접 조회합니다. 기존 `useBranchByStore` 계열 SWR 훅을 공유하지 않아 POS mount마다 요청합니다.
- 미적용 참조 데이터: **[HIGH]** `ventago-app/src/views/homes/components/ProductList/components/InvoiceAditional.tsx:70-74` — discounts/recharges/payment-methods를 mount마다 직접 조회하며 pageSize 100도 사용합니다.
- 미적용 참조 데이터: **[MEDIUM]** `ventago-app/src/views/ventas-online/components/EnvioTimeline.tsx:181`, `ventago-app/src/views/ventas-online/CuentasPorCobrarTab.tsx:56`, `ventago-app/src/views/homes/components/ProductList/components/PaymentSummaryModal.tsx:162` — `/payment-methods` 참조 데이터를 각 컴포넌트에서 직접 조회합니다.
- pageSize 위반: **[HIGH]** `ventago-app/src/views/homes/components/ProductList/ProductList.tsx:198-203` — 1000.
- pageSize 위반: **[HIGH]** `ventago-app/src/views/homes/components/DraftAndDebtors/DraftAndDebtorsList.tsx:234` — 1000.
- pageSize 위반: **[HIGH]** `ventago-app/src/views/sales/list/components/DailySalesStats.tsx:51` — 9999.
- pageSize 위반: **[MEDIUM]** 레스토랑 상품 modal 3곳에서 200: `RestaurantPaymentModal.tsx:187`, `OrderModal.tsx:163`, `NuevoPedidoModal.tsx:131`.
- pageSize 위반: **[MEDIUM]** `ventago-app/src/views/talleres/lotes/talleres_LotesListView.tsx:112-114` — vendors/etapas 100, materials 200이며 이미 존재하는 talleres SWR 훅을 우회합니다.

## 백엔드 캐시 / 멀티테넌트

- 참조 TTL: **✓** categories/sizes/colors/suppliers/origins/seasons는 60초이며 cache key에 `storeId`가 포함됩니다. 예: `api-ventago/src/app/category/category.service.ts:62-70`.
- 판매 대시보드 TTL: **✓** 30초, store-scoped입니다 (`api-ventago/src/app/dashboards/sales/salesDashboards.service.ts:16,36-37,187`).
- 대시보드 TTL 위반: **[MEDIUM]** talleres dashboard-v2는 60초입니다 (`api-ventago/src/app/subcon/dashboard-v2/dashboard-v2.service.ts:20-25,36-74`). 규약은 대시보드 30초 고정입니다.
- 대시보드 TTL 위반: **[MEDIUM]** vendor scorecard는 5분입니다 (`api-ventago/src/app/subcon/dashboard/dashboard.service.ts:304-315,425-426`). 대시보드 30초 규약과 불일치합니다.
- cache stampede: **[HIGH]** 공통 서비스가 단순 `get`/`set`만 제공하고 in-flight Promise를 합치지 않습니다 (`api-ventago/src/common/cache/memory-cache.service.ts:85-99`). 위 모든 캐시 사용처는 워커별 첫 miss 시 중복 fetch가 가능합니다. Redis는 invalidation만 전파하며 값을 공유하지 않습니다 (`memory-cache.service.ts:35-81`).
- store_id cache isolation: **대부분 ✓**, 그러나 **[MEDIUM]** AFIP cache key는 `afip-header:${cuit}:${sucursal}`로 `storeId`를 명시적으로 포함하지 않습니다 (`api-ventago/src/app/afip/afip-issuer.service.ts:68-84`). CUIT가 사실상 tenant 식별자여도 “모든 cache key에 store_id” 규약을 만족하지 않으며, 중복/변경 CUIT 시 교차매장 오염 가능성을 배제하기 어렵습니다.
- 로그 기반 격리 실패: **[HIGH]** segment refresh가 NULL `store_id`를 생성하려다 실패했습니다. 정확한 생성 SQL/모델 경로를 별도 교정해야 하며, 성공하도록 NULL 허용해서는 안 됩니다.

## Socket.io / Poller

- 예상 동시 연결: print/zebra agent 1,000개 가정 + 사용자 realtime 연결. POS 한 탭은 현재 기능별로 별도 `/realtime` socket을 만들 수 있습니다: agent status (`useThermalAgentStatus.ts:57-99`), suspended sales (`useSuspendedSaleSocket.ts:34-52`), MercadoPago (`useMpApprovedSocket.ts:26-44`). 500 POS 탭이 세 훅을 함께 mount하면 사용자 socket만 최대 약 1,500개, agent 포함 약 **2,500개**가 됩니다.
- cleanup: **✓** 세 훅 모두 unmount 시 `disconnect()`합니다.
- 연결 증폭: **[HIGH]** 동일 namespace에 기능별 `io()`를 생성해 connection multiplexing을 공유하지 않습니다. 단일 authenticated realtime socket/provider가 여러 room을 join하도록 통합하는 것이 필요합니다.
- print-agent 연결 처리: **[MEDIUM]** 새 agent 연결마다 DB 검증, online UPDATE, `server.fetchSockets()` 전체 순회를 수행합니다 (`api-ventago/src/app/print/print.gateway.ts:72-107`). 재연결 폭주 1,000건이면 adapter 전체 socket 조회가 연결마다 반복될 수 있습니다. agent별 room을 사용하면 전체 순회를 피할 수 있습니다.
- disconnect 정리: **✓** socketId 조건으로 offline 처리합니다 (`api-ventago/src/app/print/print.gateway.ts:174-182`). branch room도 사용합니다 (`:91-101`).
- polling: **[MEDIUM]** printer 설정 화면이 30초마다 직접 REST fetch합니다 (`ventago-app/src/views/branches/components/printer/PrinterConfigTab.tsx:73-93`) رغم realtime status 채널이 존재합니다.
- polling: **[LOW]** diagnostics 5초, salon 15초, admin sessions 15초 폴링이 있습니다 (`useDiagnostics.ts:64-80`, `useSalonSummary.ts:23-27`, `useAdminSessions.ts:31-35`). admin-only는 낮은 위험이나 salon은 매장 단말 수에 비례합니다.
- heartbeat/ping: Socket.io 기본값에 의존하며 코드에서 명시적 `pingInterval/pingTimeout`을 확인하지 못했습니다. 1,000+ agent 운영 가정을 스테이징에서 disconnect/reconnect storm과 함께 검증해야 합니다.

## ActiveSession

- Race condition 위험: **⚠️ HIGH**
- UPSERT 자체는 안전합니다 (`api-ventago/src/app/session/session.service.ts:60-91`). 그러나 `createSession()` 시작에서 다른 fingerprint 세션을 먼저 DELETE합니다 (`:128-133`). 동시 로그인 A/B에서 A의 UPSERT 직후 B의 선행 DELETE가 A 행을 지운 뒤 B가 진행 중 실패하면 활성 세션이 사라질 수 있습니다. DELETE를 제거하고 단일 UPSERT의 last-writer-wins로 완결해야 합니다.
- SessionGuard는 매 요청마다 `active_sessions.findOne`을 실행합니다 (`api-ventago/src/app/session/guards/session.guard.ts:18-29`). 500 동접의 모든 보호 API에 추가 DB round trip이 붙으므로 `(user_id, session_token)` 인덱스/UNIQUE 활용과 실제 p95를 반드시 검증해야 합니다.

## p95 위반 후보 라우트

현재 로그에는 HTTP route와 duration의 상관관계가 없어 **route별 p95를 확정할 수 없습니다**. 아래는 코드 fan-out과 실측 slow query를 근거로 한 우선 후보입니다.

1. `/nueva-venta` — 상품 1,000건 fetch, branch/payment-method 직접 fetch, 기능별 다중 socket 연결 (`ProductList.tsx:194-210,323-333`).
2. `/ventas` — `DailySalesStats`가 `pageSize=9999`로 판매 데이터를 가져옵니다 (`DailySalesStats.tsx:51`).
3. caja overview API 묶음 — `/cash-register` 뒤 열린 row마다 `/cash-register/:id/resume` fan-out (`AllCajasOverview.tsx:31-49`).
4. `/talleres/dashboard-v2` — TTL 경계에서 5개 집계를 요청마다 병렬 재실행하며 single-flight가 없습니다 (`dashboard-v2.service.ts:36-74`).
5. background contention 후보 — `sync_outbox`, `campaign_recipients`, stale `online_orders`; 최신 로그에서 각각 p95 목표를 크게 넘는 3,015ms, 2,171ms, 876ms 실행이 확인됐습니다. 사용자 route와 같은 50개 pgbouncer 슬롯을 경쟁합니다.

코드 스플리팅은 핵심 페이지(`/nueva-venta`, `/ventas`, `/productos` 등)에 `next/dynamic(..., { ssr:false })`가 적용돼 있습니다. 이번 검토에서 이 세 핵심 route의 누락은 확인되지 않았습니다.

## 우선순위 조치 Top 3

1. **[HIGH] 요청 증폭 제거** — POS/ventas의 1000/9999 fetch를 서버 검색 + 최대 pageSize 50으로 전환하고, caja resume를 백엔드 단일 batch aggregate endpoint로 합칩니다.
2. **[HIGH] cache single-flight 도입** — `MemoryCacheService.getOrLoad(key, ttl, loader)` 형태로 워커 내부 동시 miss를 하나로 합치고, 모든 key에 명시적 `storeId`를 포함합니다. TTL은 참조 60초/대시보드 30초를 유지합니다.
3. **[HIGH] 연결/세션 race 정리** — `/realtime` socket을 탭당 하나로 공유하고, ActiveSession의 선행 DELETE를 제거해 단일 `INSERT ... ON CONFLICT DO UPDATE`로 만듭니다. pool max는 증가시키지 않습니다.

## 권장 부하 테스트 시나리오

운영 DB에서는 실행하지 않고 production과 같은 4-worker + pgbouncer(pool_size=50) **스테이징**에서 수행합니다.

- k6 browse/POS: 500 VU, 5분. `/products/by-parent?pageSize=50`, `/branch`, `/payment-methods`, `/cash-register/open` 혼합. 목표: 전체 p95 ≤ 300ms, pool acquire timeout 0, pgbouncer `cl_waiting=0` 또는 순간적이고 회복 가능.
- k6 sale peak: 300 login/sec를 60초 ramp + 500 VU 유지. 동일 user 동시 로그인 비율 10%를 포함해 ActiveSession 최종 row 1개, 5xx/unique violation 0을 검증합니다.
- artillery WebSocket: `/realtime` 사용자 socket 500개 + `/print-agent` 1,000개, 5분 유지 후 30% 동시 reconnect. DB validate/update p95, Redis adapter 지연, event-loop lag, disconnect 정리 정확성을 측정합니다.
- k6 cache-expiry burst: 동일 store의 categories/sizes/colors 및 dashboard endpoint에 TTL 직후 500 동시 요청. endpoint별 loader/SQL 실행 횟수가 워커 수 이하인지 검증합니다. 현 구조에서는 요청 수에 근접할 가능성이 큽니다.
- background contention: outbox/campaign pending 데이터를 스테이징에 준비하고 POS 500 VU와 cron claim을 동시에 실행합니다. `sync_outbox`/`campaign_recipients`의 `EXPLAIN (ANALYZE, BUFFERS)`, lock wait, pool waiting, HTTP p95를 함께 수집합니다.

## 판정 한계

- 정적 분석과 로컬 로그 감사이며 실제 500 VU 시험은 수행하지 않았습니다.
- 운영 pgbouncer 설정과 PM2/container 실제 replica 수는 코드 주석을 근거로 했습니다. read-only 운영 진단에서 `SHOW POOLS`, `SHOW STATS`, 실행 인스턴스 수를 대조해야 최종 pool 판정이 가능합니다.
