# Phase 75: 확장 준비 — 요청 비용 절감 + 수평 확장 전제조건 — Specification

**Created:** 2026-08-06
**Source:** `75-CONTEXT.md` (2026-08-06 코드 재대조) + `load-stress-review-2026-07-31.md` + `pg-pool-review-2026-07-31.md`
**Scope:** Wave 0 ~ Wave 7 (결함 11건)
**Requirements:** 7 locked (R1~R7)
**성격:** 장기 phase — 수 개월에 걸쳐 실행된다. 따라서 **상시 계측 장치(R7)를 가장 먼저 세운다.**

## Goal

**서버를 늘려도 빨라지는 시스템으로 만든다.**

지금은 그렇지 않다. 워커나 컨테이너를 늘리면 캐시 미스가 노드 수만큼 늘고(β), 크론이 중복 실행되며,
커넥션 예산이 pgbouncer 슬롯 50 을 더 크게 초과한다. **확장하려고 늘린 노드가 확장을 방해한다.**

이 phase 는 두 가지를 한다.

1. **요청 1건의 비용을 줄인다** — 소켓 증폭 제거, 대량 조회를 서버 집계·서버 검색으로 대체, stampede 제거, pool 잠식 쿼리 교정
2. **수평 확장의 전제조건을 갖춘다** — 캐시 공유값 전환, 크론 리더 자동 보장, 커넥션 예산 정합

신규 기능 0. 사용자에게 보이는 동작 변경 0. 전부 무회귀 교정이다.

## Background

사용자 3000명을 목표로 서버 증설을 검토했으나, 실측은 다른 그림을 보여준다.
**CPU 는 8코어 중 4개, 메모리는 31GB 중 18GB 가 유휴인데 동시접속 500 기준 진단이 이미 HIGH** 다.

하드웨어가 남는데 500 에서 위험하다면 필요한 것은 하드웨어가 아니다.

원인은 두 층위다. 첫째, **요청 1건이 필요 이상으로 비싸다** — 합계를 내려고 비용 전량을 받고(`pageSize=9999`),
POS 검색을 하려고 카탈로그 전량을 받고(`pageSize=1000`), POS 탭 하나가 WebSocket 3개를 열고,
TTL 경계마다 동일 쿼리가 워커별로 중복 실행된다. 사용자 수가 6배가 되면 이 비용도 6배가 된다.
*(주의: 이것은 「`pageSize` 규약 위반」이 아니다 — Phase 73 이 상한을 명시적으로 완화했다. 문제는 숫자가 아니라
**서버 집계·서버 검색이 없어서 전량을 받아야만 하는 구조**다. R2 참조.)

둘째, 그리고 더 근본적으로, **노드 간 일관성 비용(USL 의 β)이 크다.** `MemoryCacheService` 는 워커 로컬이고
Redis 는 invalidation 만 전파할 뿐 값을 공유하지 않는다. 노드를 N배 늘리면 같은 데이터를 N번 조회한다.
크론 리더는 `CRON_ENABLED=false` 를 수동으로 주지 않으면 컨테이너마다 중복된다.
커넥션은 `서버수 × 워커수 × 20` 으로 선형 증가하는데 pgbouncer 슬롯은 50 고정이다.

β > 0 인 시스템은 **어느 지점부터 노드를 늘릴수록 처리량이 감소한다.** 따라서 `D-63-2`(2호기 보류)는
"아직 필요 없어서"가 아니라 **"지금 붙이면 역효과라서"** 유효하다. 이 phase 는 그 역효과를 제거해
2호기를 **붙일 수 있는 상태**로 만들고, 붙일 시점을 **측정 가능한 게이트**로 고정한다.

## Requirements

**Current** = 현행(2026-08-06 코드 확인), **Target** = 목표, **Acceptance** = 완료 판정.

---

### R1. 소켓 증폭 제거 (결함 1) — Wave 2

- **Current:** `socket.io-client` 소비처가 **8곳**이며, 그중 4곳이 완전히 동일한 형태로 호출한다 —
  `io(WS_URL, { transports: ['websocket'], auth: { token } })`
  (`useSuspendedSaleSocket.ts:41` · `useThermalAgentStatus.ts:78` · `useMpApprovedSocket.ts:33` · `TeamChatPanel.tsx:56`).

  socket.io-client v4 는 같은 URL 이면 Manager 를 재사용하지만 **같은 네임스페이스를 다시 요청하면
  `sameNamespace` 판정으로 새 Manager·새 물리 연결을 만든다**(한 Manager 는 네임스페이스당 Socket 1개).
  즉 **멀티플렉싱이 되고 있다는 착각과 달리 호출 수만큼 WebSocket 이 생긴다.**
  POS 탭 1개 = 소켓 3개, 3000명 시나리오에서 **약 7,000 연결**.
- **Target:**
  1. **단일 `RealtimeProvider`** 도입 — 앱 전체에서 인증된 소켓 **1개**만 생성하고 Context 로 제공한다.
  2. 기존 훅 4곳은 `io()` 직접 호출을 버리고 Provider 의 소켓을 구독한다.
     **훅의 외부 인터페이스(반환값·콜백)는 바꾸지 않는다** — 호출부 회귀를 막기 위해서다.
  3. 기능별 분리는 **room join 이벤트**로 처리한다(연결이 아니라 구독을 나눈다).
     서버는 이미 `branch:{id}` room 패턴(Phase 40)을 쓰고 있으므로 그 방식을 따른다.
  4. `DespachoBoard:245` · `DeliveryBoard:147` · `useRemoteSupport:173` · `pages/soporte/visor.tsx:117` 은
     **이번 범위에서 제외** — 페이지 단위로 mount/unmount 되어 상시 연결이 아니고, 원격지원은 성격이 다르다. 별도 판단.
  5. cleanup 회귀 금지 — 현행 4개 훅은 unmount 시 `disconnect()` 하고 있다.
     Provider 전환 후 마지막 구독자가 사라져도 **연결은 유지**되어야 하며(재연결 폭주 방지),
     로그아웃 시에만 끊는다.
  6. **서버 측 fanout 비용 제거** — `print.gateway.ts:106` 의 `this.server.fetchSockets()` 와
     그 뒤 **`:106-127` 전체 순회**를 agent 별 room 으로 대체한다. 저장소 전체에서 `fetchSockets` 사용처는
     이 1곳뿐이다. agent 재연결 폭주 시 연결마다 전체 socket 을 훑는 구조라 연결 수 제곱에 비례한다.
  7. **중복 폴링 제거** — `PrinterConfigTab.tsx:73-93`(`:90` `setInterval(fetchAgents, 30_000)`)의
     30초 REST 폴링. realtime 상태 채널이 이미 있으므로 중복이다.
- **Acceptance:** POS 탭 1개당 WebSocket **1개**(브라우저 DevTools Network › WS 로 확인) ·
  기존 실시간 기능 4종 전부 동작(보류판매 알림 · agent 상태 · MP 승인 · 팀챗) ·
  서버 측 동시 연결 수가 전환 전 대비 **1/3 이하** · 로그아웃 시 연결 해제 확인 ·
  `fetchSockets()` 사용처 **0건** · `PrinterConfigTab` 폴링 제거 후에도 agent 상태가 실시간 갱신됨.
- **효과:** 투자 대비 효과가 가장 크다. 3000명 시나리오에서 7,000 → 약 2,600 연결.

---

### R2. 대량 조회를 서버 집계로 대체 (결함 2·3) — Wave 3

> **★ 초안 정정 (2026-08-06 검증).** 이 요구사항은 원래 "`pageSize` 최대 50 규약 복원, 위반 0건"이었다.
> **그 목표는 틀렸고, 실행하면 Phase 73 을 회귀시킨다.**
>
> `common/pagination/pagination.util.ts:8-21`(Phase 73-08/73-15)이 **전 클라이언트 앱 호출부를 전수 조사한 뒤
> 명시적으로 반대 결정**을 기록해 두었다 — *"CLAUDE.md 의 「pageSize 최대 50」은 프론트가 화면에 뿌릴 때의
> 규약이고, 서버 상한을 50 으로 잡으면 **정상 화면이 조용히 잘린다. 조용한 오답은 느린 응답보다 나쁘다**"*.
> `DEFAULT_MAX_PAGE_SIZE = 200`, `BULK_MAX_PAGE_SIZE = 10000` 이 그 결론이고,
> `ProductList.tsx:198-200` 주석에는 상한을 걸었다가 **POS 검색이 최신 10건에서만 매칭되던 회귀 이력**이 남아 있다.
>
> 또한 "`DailySalesStats.tsx` 의 9999 는 이미 수정됨"이라는 초안 서술도 **부분적으로 틀렸다.**
> `/sales/all` 경로는 Phase 73-14 가 서버 집계(`GET /sales/daily-summary`)로 대체했지만,
> **같은 파일 `:60` 의 `/expenses/search?pageSize=9999` 는 그대로 살아 있다.**
>
> **따라서 목표를 "숫자를 낮춘다"가 아니라 "대량 조회가 필요 없게 만든다"로 바꾼다.**
> Phase 73-14 가 판매에 대해 이미 증명한 패턴 — **클라이언트 집계 → 서버 집계** — 를 나머지에 적용한다.
> 상한만 낮추면 화면이 조용히 잘리고, 서버 집계로 바꾸면 페이로드와 화면 정확성을 동시에 얻는다.

- **Current:** 대량 조회가 세 종류로 남아 있다.

  | 유형 | 위치 | 값 | 성격 |
  |---|---|---|---|
  | **클라이언트 집계용 대량 조회** | `DailySalesStats.tsx:60` `/expenses/search` | 9999 | 합계를 내려고 전량을 받는다 — **서버 집계 대상** |
  | **카탈로그 전량 로드** | `ProductList.tsx:202` · `DraftAndDebtorsList.tsx:234` `/products/by-parent` | 1000 | POS 검색이 클라이언트에서 일어난다 — **서버 검색 대상** |
  | **화면 표시용 목록** | 레스토랑 3곳(200) · `ModalPriceInactiveList`(100×4) · `PriceTypesList`(100) · `InvoiceAditional`(100×2) · `talleres_LotesListView`(100·100·200) · `AccessLogsView`(200) · `useNotices`/`ClientLedgerView`/`SlowQueriesTab`(100·100·200) | ≤200 | **Phase 73 이 명시적으로 허용한 범위** — 손대지 않는다 |

  참조 데이터 직접 조회도 잔존한다 — `/payment-methods` 만 **5곳**
  (`CuentasPorCobrarTab.tsx:56` · `EnvioTimeline.tsx:181` · `SeniaRegisterModal.tsx:45` ·
  `CreditPaymentModal.tsx:53` · `RestaurantPaymentModal.tsx:166`). POS mount 마다 요청이 나간다.
- **Target:**
  1. **`/expenses/search?pageSize=9999` → 서버 집계 엔드포인트.**
     Phase 73-14 의 `GET /sales/daily-summary` 와 **같은 패턴·같은 명명**을 따른다.
     이것이 이 요구사항에서 가장 확실한 이득이다 — 비용 건수에 비례하던 페이로드가 상수가 된다.
  2. **`/products/by-parent?pageSize=1000` → 서버 검색.**
     POS 상품 검색을 서버로 옮기고 화면은 페이지 단위로 받는다.
     **`ProductList.tsx:198-200` 의 회귀 이력(검색이 최신 10건에서만 매칭)을 반드시 재현 테스트한다.**
     서버 검색이 카탈로그 전량을 대상으로 하지 않으면 같은 사고가 반복된다.
     이 항목은 위험이 크므로 **1번과 분리해 배포**한다.
  3. 참조 데이터 직접 조회 → `src/hooks/api/` SWR 훅(5분 dedup).
     훅이 없으면 신설하되 기존 명명 규칙(`useXxxByStore`)을 따른다. `/payment-methods` 5곳부터.
  4. 백엔드 N+1 — `clients.service.ts:318-331` 의 `stillUnmapped` 루프별 `findAll()`(`:322`) 제거.
  5. **`CLAUDE.md` 의 「pageSize 최대 50」 표기를 `pagination.util.ts` 의 실제 결정과 일치시킨다.**
     지금은 두 문서가 충돌하고 있고, 그 충돌이 이 초안의 오류를 만들었다.
- **범위 제외 (명시):** ≤200 인 화면 표시용 목록 전부. Phase 73-15 가 호출부 전수조사로 승인한 값이다.
  **`AllCajasOverview.tsx:66-72` 의 `/resume` fan-out 도 제외** — `:3` 주석이
  *"열린 카하는 보통 1~5개 → 개별 resume 은 Promise.all 병렬(pool 부담 최소)"* 라고 의도를 명시하고 있다.
  결함으로 규정하려면 **카하 수 상한 실측**이 선행돼야 한다(W0 에 측정 항목으로 추가, 조치는 이번 범위 밖).
- **Acceptance:** `/expenses/search` 대량 조회 **0건** · POS 상품 검색이 서버에서 수행되고
  **검색 정확성 회귀 없음**(전량 대상 매칭 확인) · `/payment-methods` 직접 조회 0건 ·
  POS 최초 진입 요청 수·전송량·**번들 바이트**가 W0 기준선 대비 감소(수치 기록) ·
  `CLAUDE.md` ↔ `pagination.util.ts` 표기 일치 · **기능 회귀 0**.

---

### R3. cache stampede 제거 (결함 4) — Wave 5

- **Current:** `MemoryCacheService` 는 `get`/`set`/`del`/`delByPrefix`/`clear` 만 제공하고
  in-flight Promise 를 병합하지 않는다(in-flight 관련 키워드 0건 확인).
  TTL 경계에 동시 요청이 몰리면 **동일 집계 쿼리가 워커별로 중복 실행**된다.
  참조 데이터 60초 · 대시보드 30초 TTL 이므로 경계는 규칙적으로 찾아온다.

  TTL 규약(참조 60초 / 대시보드 30초) 이탈도 **2건이 아니라 5건**이다.

  | 위치 | 현재 | 비고 |
  |---|---|---|
  | `subcon/dashboard-v2/dashboard-v2.service.ts:25` | 60초 | 대시보드 |
  | `subcon/dashboard/dashboard.service.ts:426` (vendor scorecard) | 5분 | **같은 파일 `:299` 에 30초가 공존** |
  | `subcon/subcon-settlements/subcon-settlement.service.ts:544` | 2분 | 대시보드 아님 — 판단 필요 |
  | `subcon/lotes/lote.service.ts:1572` | 2분 | 동일 |
  | `subcon/defect-codes/defect-code.service.ts:55` | 60초 | 참조 데이터면 규약 준수 |

- **Target:**
  1. `getOrLoad(key, ttlMs, loader)` API 추가 — 같은 key 의 in-flight Promise 를 **하나로 병합**.
  2. loader 실패 시 Promise 를 즉시 캐시에서 제거해 **실패가 TTL 동안 고착되지 않게** 한다.
  3. 기존 `get`/`set` 호출부를 점진 전환한다. **한 번에 다 바꾸지 않는다** — 호출부가 넓다.
  4. **TTL 규약의 경계를 먼저 정의한다.** 지금은 "대시보드 30초"만 있고 그 외 집계 캐시에 대한 규약이 없어
     위 5건의 판정이 갈린다. `CLAUDE.md` 에 분류 기준(참조 데이터 / 대시보드 / 기타 집계)을 명시한 뒤
     각 건을 판정한다. **규약 없이 숫자만 맞추면 다음에 또 갈라진다.**
  5. 대시보드로 분류된 것을 30초로 통일. `dashboard.service.ts` 한 파일 안의 30초·5분 공존을 해소.
  6. **AFIP cache key 에 `storeId` 명시** — `afip-issuer.service.ts:80` 은
     `afip-header:${c}:${suc}` 로 "모든 cache key 에 store_id" 규약을 충족하지 않는다.
     **실질 누출 위험은 낮다**(CUIT 가 세무주체 단위라 사실상 tenant 식별자) — 규약 일관성 목적이며
     **우선순위는 낮게** 잡는다.
- **Acceptance:** 동일 key 동시 100 요청 시 loader **1회만** 실행(유닛 테스트) ·
  loader 실패가 다음 요청에서 재시도됨 · TTL 분류 기준이 `CLAUDE.md` 에 명시됨 ·
  5건 전부 분류에 따라 판정·정정됨 · 모든 cache key 에 `storeId` 포함.

---

### R4. pool 잠식 쿼리 교정 (결함 6) — Wave 4

- **Current:** ~~로그 실측 — `sync_outbox` claim **3,015ms** · `campaign_recipients` claim **2,171ms** ·
  `slow_query_log` INSERT **2,069ms** · `COMMIT` 757ms.~~
  **→ W0 실측(2026-08-06)에서 재현되지 않았다. 아래 「★ 전제 반증」 참조.**

  Little's Law 상 3초 쿼리는 그 pool 슬롯의 처리량을 **1/30** 로 만든다 — 이 논리 자체는 유효하나,
  **그 3초가 현재 존재하지 않는다.**

> **★ 전제 반증 (2026-08-06 W0 실측 — `75-W0-BASELINE.md`).**
>
> 위 숫자의 출처는 `load-stress-review-2026-07-31.md:18` 이고, 그 원본은
> **`api-ventago/logs/combined-2026-07-29.log` 단일 일자 앱 로그**다.
>
> 5일치(`stats_reset` 2026-08-01) `pg_stat_statements` 실측:
>
> | 쿼리 | calls | mean | max |
> |---|---|---|---|
> | `UPDATE sync_outbox …` (claim) | 45,009 | 0.01ms | **1.1ms** |
> | `UPDATE campaign_recipients …` | 15,005 | 0.02ms | **1.2ms** |
> | `UPDATE sync_outbox SET locked_by …` | 13,130 | 0.01ms | **1.4ms** |
>
> **3,015ms → 1.1ms.** 45,009회 실행이라 표본 부족이 아니다. 교차 확인 3건 모두 같은 방향:
> `slow_query_log` 는 **전체 기간 통틀어 2행**(최대 225ms) · 오늘 앱 로그의 100ms 초과 쿼리 **0건**
> (임계 100ms 로거는 `database.module.ts:76-77` 에서 정상 작동 중) ·
> pgbouncer 누적 대기 **4.73초 / 130,452 트랜잭션**.
>
> **해석:** 앱측 타이밍은 **커넥션 획득 대기를 포함**한다. 07-29 의 3초는 상시 속성이 아니라
> 그날의 **사건**(I/O 포화·락 폭주·일시적 pool 고갈)이었을 가능성이 높고, pgbouncer 대기가
> 사실상 0 인 현재 상태와 모순되지 않는다. **원본 로그는 이미 사라져 사후 규명이 불가능하다**
> (컨테이너에 로그 volume 이 없어 배포마다 소실 — 0-8 이 불가능한 것과 같은 원인).
>
> **그러므로 R4 의 성격이 바뀐다.** "느린 쿼리를 고치는 요구사항"이 아니라
> **"07-29 같은 사건이 재발하는지 관측하고, 재발했을 때 근거가 남게 만드는 요구사항"** 이다.
> 남은 개별 항목의 재판정:
>
> | 항목 | 판정 |
> |---|---|
> | 4-1 `EXPLAIN` | **유지** — 단 목적을 "원인 규명" → "정상 계획 확인 + 재발 시 비교 기준" 으로 |
> | 4-2 인덱스 추가 | **동결** — 근거 소멸. 재발 실측 없이 착수 금지 |
> | 4-3 batch 상한 | **동결** — 2,069ms 의 근거가 사라졌고, 현재 이 테이블은 5일간 2행만 기록했다 |
> | 4-3b 인덱스 3개 재평가 | **동결** — 위와 같음. 쓰기 부하 자체가 관측되지 않는다 |
> | 4-4 워커별 flush | **근거 강화 · 우선순위 상승** — 기록된 2행이 **전부 `instance=0`**. 워커 1~3 버퍼 영구 유실이 실측 확인됐다. **관측 공백 자체가 결함**이므로 R4 에서 가장 먼저 한다 |
> | 4-5 판매 경로 잔존 bulk 화 | **유지** — 느린 쿼리와 무관하게 트랜잭션 점유 시간 문제다 |
> | 4-6 import·cheques bulk | **유지** — 동일 |
>
> **이 반증을 무시하고 4-2/4-3 을 실행하면, 플랜이 스스로 경고한 함정
> ("추측 최적화는 반드시 엉뚱한 곳을 고친다")에 R4 자신이 걸린다.**
> **★ 초안 정정 2건 (2026-08-06 검증).**
>
> **(1) 판매 재고 경로는 이미 bulk 화돼 있다.** 초안은 "품목별 순차 `SELECT FOR UPDATE` → 단일 `IN (...)`"
> 을 지시했으나, `sales-create.service.ts:1201-1207` 은 **이미 그 결과물**이다 —
> `SELECT ... WHERE product_id = ANY($3::int[]) ORDER BY product_id FOR UPDATE`,
> `:1192` 주석에 *"루프 대신 1쿼리 + `ORDER BY product_id` 로 문장 안에서 잠금 순서를 고정(N+1 금지)"*.
> Phase 64 W8/R10 + Phase 70 W1 이 이미 처리했다. **완료된 작업을 재지시하고 있었고,
> 그에 딸린 "락 순서 변경 = 교착" 최고위험 경고도 존재하지 않는 변경을 대상으로 했다.**
> 실제 잔존부는 **`:1261-1278`**(품목별 `ProductBranch.findOne`/`create` + `Stocks.create` 루프)와
> `processSaleItems` 의 품목별 `productModel.findOne` 루프다. 대상을 이쪽으로 옮긴다.
>
> **(2) `slow_query_log` 는 이미 비동기 배치다.** `slow-query-buffer.ts` 가 인메모리 버퍼(`MAX_BUFFER=2000`)를
> 두고 `drainSlowQueries()` 후 **다중행 단일 INSERT** 를 10초 cron 으로 보낸다. "전환"할 대상이 없다.
> 2,069ms 의 유력 원인은 **한 번에 최대 2,000행 × 7컬럼(=14,000 bind)** 을 밀어넣는 구조와,
> `slow-query-log.sql:28,30,32` 의 **인덱스 3개**(`created_at DESC` · `duration_ms DESC` · `table_name`)를
> 배치마다 갱신하는 쓰기 비용이다. 남은 일은 **batch 상한 + `statement_timeout` + 인덱스 재평가** 셋이다.

- **Target:**
  1. **`EXPLAIN (ANALYZE, BUFFERS)` 를 먼저 돌린다.** 인덱스를 추측으로 추가하지 않는다.
     **단, "partial index 존재 여부"는 이미 답이 나왔다** — `sync_outbox_due_idx`(`phase43-sync-outbox.sql`) ·
     `sync_outbox_lease_idx`(`2026-07-27-phase64-outbox-lease-index.sql`) · `campaign_recipients_due_idx`
     (`2026-07-22-campanas.sql`) 가 **모두 존재한다.**
     따라서 **1순위 가설은 인덱스 부재가 아니라 dead tuple · autovacuum 지연 · lock 대기**다.
     이 순서로 진단하지 않으면 W4 가 헛돈다.
  2. 원인이 인덱스로 확정된 경우에만 추가 — `CREATE INDEX CONCURRENTLY`, 로컬 5432·운영 5434 양쪽 적용.
  3. `slow_query_log` — **batch 상한** 도입(2,000 → 실측 기반 축소) + 짧은 `statement_timeout` +
     **인덱스 3개의 필요성 재평가**(append-only 고빈도 쓰기 테이블에 인덱스 3개는 배치마다 3중 갱신이다).
     조회 패턴을 확인해 불필요한 인덱스는 제거한다.
  4. slow-query 버퍼를 **워커별 flush**, prune 만 리더에서.
     `main.ts:161` 이 비리더 프로세스의 `SchedulerRegistry` cron/interval 을 **전부 삭제**하므로
     현재 워커 1~3 의 버퍼는 **영구 유실**된다. `AdminConsoleCron` 의 per-worker `setInterval` 패턴을 따른다.
  5. 판매 쓰기 경로 잔존부 bulk 화 — **`sales-create.service.ts:1261-1278`** 의 품목별
     `ProductBranch.findOne`/`create` + `Stocks.create` 루프 → bulk 조회/생성 + `bulkCreate`.
     `processSaleItems` 의 품목별 `productModel.findOne` 루프도 함께.
     **`:1201-1207` 의 기존 락 쿼리는 건드리지 않는다** — 이미 올바르다.
  6. `import.service.ts:95-108,144-154` · `cheques.service.ts:127-142` 순차 DML → bulk.
     트랜잭션 점유 시간이 건수에 선형 비례하는 경로다.
  7. SQL 의미를 바꾸지 않는다. pool 을 늘리지 않는다.
- **Acceptance:** outbox·campaign claim **p95 < 100ms** · `slow_query_log` INSERT 가 pool 슬롯을 초 단위로
  점유하지 않음 · **4워커 전부**의 slow query 기록됨 · 판매 경로 트랜잭션 점유 시간 감소(측정) ·
  import·cheques 대량 처리 시 커넥션 점유 시간 감소 ·
  **Phase 64 동시성 스위트 8종 통과 유지** · **`:1201-1207` 락 쿼리 무변경 확인**(diff 검토).

---

### R5. 수평 확장 전제조건 (결함 5·7·8·9) — Wave 5~6

> **Wave 표기 주의:** R5-1(캐시 값 공유)은 R3 의 `getOrLoad` 위에 얹히므로 **W5 에서** 수행한다.
> 나머지 R5-2~R5-5 는 **W6**. 이 요구사항만 두 wave 에 걸친다(CONTEXT 결함 5 = W5, 결함 7·8·9 = W6).

이 요구사항이 **2호기의 실질 전제**다. USL 의 β 를 낮추는 작업이다.

- **Current:**
  - 캐시가 **워커 로컬** — Redis 는 invalidation 만 전파하고 값을 공유하지 않는다. 노드 N배 = 조회 N배
  - 커넥션 예산 **80 vs 50**(공개몰 폴백 시 최대 140). 노드 수에 선형 비례
  - 공개몰 격리 판정이 **host 문자열 비교** — 같은 PG 를 Docker 브리지 주소로 가리키면 격리로 **오판**하고 `max=15` 적용
  - 크론 리더가 `CRON_ENABLED=false` **수동 설정 의존** — 2호기 배포 시 빠뜨리면 outbox·campaign 2배 실행
  - Redis `maxmemory 128mb` + **`noeviction`** — 소켓 fanout 증가로 메모리가 차면 eviction 이 아니라 **쓰기 에러**
- **Target:**
  1. **캐시 값 공유** — 참조 데이터(60초)를 Redis 공유값으로 전환. 대시보드(30초)는 store-scoped 라 후순위.
     R3 의 `getOrLoad` 위에 얹어 로컬 L1 + Redis L2 2단으로 구성한다.
  2. **크론 리더를 transaction-scoped advisory lock 으로 승격** — env 를 빠뜨려도 안전하도록.
     **session-level lock 금지**(pgbouncer transaction pooling 에서 깨진다 — `pg-pool-review` 지적).
     `CRON_ENABLED` 스위치는 **명시적 비활성화 수단으로 유지**한다.
  3. **공개몰 격리를 명시 플래그로** — host 비교 대신 `SHOP_DB_ISOLATED=true`(별도 PG/별도 pgbouncer pool 이
     검증된 경우만). 그 외에는 fallback `max=5` 유지. **메인 pool max 는 변경하지 않는다.**
  4. **커넥션 예산 산식 정정** — `API_REPLICA_COUNT` 를 필수 env 로 도입하고
     `replicas × workers × (main + shop)` 을 부팅 로그에 표기. 현재는 replica 수를 몰라 축소 표기된다.
  5. **Redis 안전판** — `maxmemory` 상향(소켓 수 기준 산정) + 사용률 알람.
     `noeviction` 유지 여부를 실측 후 판단(pub/sub 유실 vs 쓰기 에러 트레이드오프).
  6. **부팅 시 `sequelize.sync` 완전 비활성화 검증** — `synchronize:false` 는 이미 설정돼 있으나
     error 로그에 view 의존 컬럼 alter 실패가 **반복 기록**된다. `SyncService` 가 어떤 조건에서
     sync 를 호출하는지 확인하고 migration-only 정책을 강제한다.
     노드가 늘면 이 실패도 노드 수만큼 반복된다.
  7. **★ 워커 수 이중 관리 해소 (G3 의 전제)** — `ecosystem.config.js:18` 의 `instances: 4` 와
     `:32` 의 `WEB_CONCURRENCY: 4` 가 **별도로 하드코딩**돼 있고 주석이 "함께 갱신할 것"이라 적어 두었다.
     **W6 의 4→6 증설 실험이 이 이중 관리 때문에 예산 로그를 틀리게 만든다** — G3 실증의 전제가 흔들린다.
     `WEB_CONCURRENCY` 를 `instances` 에서 파생시키거나 단일 출처로 통합한다.
  8. **`PGBOUNCER_POOL_SIZE` 실측값 고정** — 현재 미설정 시 `'50(추정)'` 을 로그에 찍는다.
     **G5(`≤ pgbouncer 슬롯`) 판정 근거가 추정값이면 게이트가 성립하지 않는다.**
     W0 에서 `SHOW POOLS` 로 실측해 env 로 고정한다.
- **Acceptance:** 워커 4 → 6 증설 시 **동일 참조 데이터 쿼리 수가 증가하지 않음**(β 감소 실증) ·
  `CRON_ENABLED` 미설정 2번째 프로세스에서 크론 중복 실행 0건(advisory lock 검증) ·
  부팅 로그의 커넥션 예산이 **실측값 기반**으로 실제 총량과 일치(추정값 표기 0건) ·
  워커 수가 단일 출처에서 파생됨 · Redis 사용률 알람 동작 · 부팅 시 sync 시도 0건.

---

### R6. 확장 판단 게이트 (결함 10) — Wave 7

- **Current:** `D-63-2` 재개 조건이 `66-PLAN.md:109` 의 "컨테이너 2대 결정 시 한 묶음으로" 뿐이다.
  **"2대로 갈지 결정하면 2대 준비를 한다"는 순환 논법**이라 실제 판단 기준이 없다.
- **Target:** 아래를 **전부 만족할 때만** `D-63-2` 를 재검토한다. 하나라도 미달이면 2호기는
  돈과 시간을 쓰면서 시스템을 느리게 만든다.

  | 게이트 | 기준 | 근거 |
  |---|---|---|
  | G1 | pgbouncer `cl_waiting` 피크 **지속 0** | 커넥션이 이미 상한이면 노드 추가는 악화 |
  | G2 | outbox·campaign claim **p95 < 100ms** | Little's Law — W 가 크면 L 을 늘려도 무의미 |
  | G3 | **워커 4 → 6 증설 시 처리량이 실제로 증가** | β 실증. 이게 안 늘면 2호기도 안 늘어난다 |
  | G4 | 크론 리더가 **advisory lock 으로 보장** | env 누락 사고 방지 |
  | G5 | `서버수 × 워커수 × pool.max ≤ max_client_conn`(1000) **이고** `cl_waiting` 0 유지 | 예산 정합 — **문구 정정됨, 아래 참조** |
  | G6 | 피크 판매 커밋/s · 동시 소켓 수 · 단일 매장 hot-row **상시 관측** | 판단 근거의 존재 |

  > **★ G5 정정 (2026-08-06 W0-10 실측).** 이 문서 곳곳의 "pgbouncer 슬롯 50" 표현은
  > **두 층위를 섞고 있다.** `pool_size=50` 은 **pgbouncer→PG 서버** 커넥션의 **(db,user) 쌍별** 상한이고,
  > `서버수×워커수×(메인+공개몰 pool.max)`(현재 `1×4×(20+5)=100`, 부팅 로그 실측)는 **앱→pgbouncer 클라이언트** 커넥션으로
  > 상한이 `max_client_conn=1000` 이다. 따라서 **`100 > 50` 은 위반이 아니라 설계다** —
  > pgbouncer 가 다중화하는 지점이 정확히 거기다.
  >
  > 원문대로 판정하면 **정상 구성을 결함으로 오판**하고, 그 처방은 `pool.max` 나 워커를 줄이는 것 —
  > **멀쩡한 시스템을 느리게 만든다.** 서버측 포화는 숫자 비교가 아니라 **`cl_waiting`** 으로 본다.
  >
  > 다만 **「`pool.max` 증가 금지」결론 자체는 유지된다** — 이유가 "슬롯 50 초과"가 아니라
  > "앱에서 기다리던 큐가 DB 안으로 옮겨갈 뿐이고, DB 안의 대기는 락을 쥔 채 기다려 더 비싸다"로 바뀔 뿐이다.

  1. 위 6개를 상시 관측 가능하게 만든다 — `Centro de Control` 의 `infraestructura` 위젯 확장.
     **신규 인프라를 만들지 않는다.**
  2. `66-PLAN.md` P2 항목의 착수 조건을 이 게이트로 **교체**한다(순환 논법 제거).
  3. **`D-63-2` 자체는 이 phase 에서 해제하지 않는다.** 게이트만 만든다.
- **Acceptance:** 6개 게이트가 위젯에서 확인 가능 · `66-PLAN.md` 착수 조건 갱신 ·
  `ROADMAP.md` 에 게이트 상호 참조 기재.

---

### R7. 일일 자동 점검 — 용량·추세 감시 (결함 11) — **Wave 1 (최우선)**

- **Current:** 운영 상태를 **사람이 물어봐야만** 알 수 있다. 감시는 두 가지뿐이다 —
  `tools/uptime-watchdog.sh`(살아 있는가)와 `all-exceptions.filter.ts`(500 이 났는가).
  **둘 다 "지금 이 순간"만 본다. 추세를 보는 장치가 없다.**

  이것이 장기 phase 에서 치명적인 이유는 두 가지다.
  1. **진척을 알 수 없다.** 몇 달에 걸쳐 요청 비용을 줄이는데, 나아졌는지 판단할 시계열이 없다.
     G3(워커 4→6 시 처리량 증가) 같은 게이트는 **비교 대상이 있어야** 판정된다.
  2. **서서히 차오르는 것을 못 잡는다.** 디스크는 어느 날 갑자기 차지 않는다. 며칠에 걸쳐 차오르다
     **마지막 하루에 서비스를 정지시킨다.** 특히 Phase 74 의 복제 슬롯은 수신기가 죽으면
     WAL 을 무한 축적해 **PostgreSQL 자체를 멈춘다** — 절대값 알람은 이미 늦다.
- **Target:**
  1. **일일 수집기** — 매일 정해진 시각에 지표를 수집해 append-only 시계열로 남긴다.
     저장은 **JSONL 파일**(`/var/lib/postgresql/ops-metrics/daily.jsonl`).
     **DB 테이블을 쓰지 않는다** — DB 가 아플 때도 기록이 남아야 하고, 그때가 가장 중요한 순간이다.
     기존 백업 업로드(`dropbox_sync.sh`)에 얹어 오프사이트 사본도 확보한다.
  2. **수집 항목**

     | 분류 | 지표 |
     |---|---|
     | 디스크 | 파티션별 사용률·사용량 · **전일 대비 증분** · 7일 평균 증분 |
     | PostgreSQL | DB 크기 · 전일 대비 증분 · 상위 10개 테이블 크기·증가율 · dead tuple · autovacuum 지연 |
     | WAL (Phase 74) | 아카이브 디렉터리 크기 · **복제 슬롯 lag** · `max_slot_wal_keep_size` 대비 비율 |
     | 백업 (Phase 74) | 최신 덤프 mtime · 크기 추이 · `TABLE DATA` 항목 수 · Dropbox 업로드 성공 여부 |
     | 커넥션 | pgbouncer `cl_waiting` 피크 · `SHOW POOLS`/`SHOW STATS` · pool 사용률 피크 |
     | 실시간 | 동시 WebSocket 연결 수 피크 |
     | 부하 | 피크 판매 커밋/s · 느린 쿼리 상위 · Docker 이미지·컨테이너 로그 용량 |
     | **감시기 생존** | **Mac 워치독 heartbeat 나이** (상호 감시 — 결함 12) |

  3. **임계값 — 절대값과 변화율을 함께 본다.** 변화율이 더 일찍 알려준다.

     | 조건 | 등급 | 근거 |
     |---|---|---|
     | 디스크 사용률 **> 70%** | 경고 | 사용자 지정 |
     | 디스크 사용률 > 85% | **긴급** | 여유가 며칠 남지 않음 |
     | 하루 증분 **> 10GB** | 경고 | 사용자 지정 — 절대값보다 먼저 잡힌다 |
     | WAL 아카이브 > `max_slot_wal_keep_size` 의 70% | 경고 | 슬롯 무효화 임박 = PITR 연속성 상실 |
     | 복제 슬롯 lag 급증 | **긴급** | 수신기 사망 → 디스크 폭발 경로 |
     | 백업 mtime > 26h | **긴급** | Phase 74 R4 와 동일 |
     | pgbouncer `cl_waiting` > 0 지속 | 경고 | 커넥션 상한 도달 = G1 위반 |
     | **Mac 워치독 heartbeat > 26h** | **긴급** | 외부 감시가 죽었다 — 2026-08-06 사고의 재발 방지 |
     | **launchd 에이전트 미등록** (Mac 측 판정) | **긴급** | 감시기가 꺼져 있다 |
     | 특정 테이블 주간 증가율 이상치 | 경고 | 원인 테이블을 지목해 준다 |

  4. **소진 예측** — 7일 평균 증분으로 "이 속도면 **N일 후** 디스크가 찬다"를 계산해 리포트에 포함한다.
     **이것이 이 장치의 핵심 가치다.** 70% 알람은 "지금 문제"를 알려주지만, 소진 예측은
     **"언제까지 조치해야 하는가"**를 알려준다. 잔여 30일 미만이면 경고로 승격한다.
  5. **알림 정책 — 성공 침묵 + 주간 요약**
     - 임계 위반 시에만 **즉시** Telegram. 매일 오는 "정상" 알림은 곧 무시되고, 무시되는 알림은 실패도 함께 묻는다
     - **주 1회 트렌드 요약** 1건 — 추세·소진 예측·주요 변화. 이건 읽히는 빈도라 유용하다
     - **부재 감지** — 일일 리포트가 26시간 넘게 갱신되지 않으면 **Mac(launchd)에서** 알림.
       서버 안 감시는 서버가 죽으면 같이 죽는다. Phase 74 R4-3 과 **같은 장치를 공유**한다
  6. **알림 경로 재사용** — `tools/uptime-watchdog.sh` 의 `send_telegram()` + `.uptime.env` 패턴.
     **새 알림 채널·새 인프라를 만들지 않는다.**
  7. **수집기가 부하가 되지 않을 것** — 하루 1회, 조회성 쿼리만, `pg_stat_*`/`information_schema` 중심.
     `pg_dump` 와 같이 **pgbouncer 를 우회해 5434 직결**로 접속하고 커넥션 1개만 쓴다.
     앱 pool 예산에 영향을 주지 않는다.
- **Acceptance:** JSONL 에 일 1행 누적 · 디스크 70% / 일 증분 10GB 초과를 인위 유발 시 Telegram 도달 ·
  소진 예측일이 리포트에 포함 · 주간 요약 1건 도착 · 리포트 부재 26시간 시 Mac 워치독 알림 ·
  **launchd 에이전트 1개를 unload 하면 Mac 워치독이 감지** · **heartbeat 를 지우면 서버 점검이 감지** ·
  **정상 운영 중 즉시 알림 0건**(소음 없음) · 수집기 실행이 pgbouncer `cl_waiting` 을 만들지 않음.
  8. **★ 상호 감시 (결함 12)** — 감시기 자체를 감시한다.
     - **Mac → 서버:** `backup-freshness-watchdog.sh` 가 `launchctl list` 로 에이전트 5개 등록을 확인하고,
       서버에 `mac-watchdog.heartbeat` 를 touch 한다
     - **서버 → Mac:** 일일 점검이 heartbeat 나이를 보고 26시간 초과 시 긴급 알림
     - 한쪽이 죽으면 다른 쪽이 알린다. **2026-08-06 에 launchd 4개가 조용히 죽어 있던 사고**
       (저장소 경로 이동으로 plist 가 옛 경로를 가리킨 채 등록 해제)의 직접적 재발 방지 장치다.
       그때 서버가 죽어도 아무도 모르는 상태였고, **아무도 그것을 몰랐다.**

- **Phase 74 와의 관계:** 이 장치는 **두 phase 가 공유**한다. Phase 74 R4(백업 실패 알람)와
  R1-4(슬롯 디스크 안전판 감시)가 여기에 얹힌다. **먼저 만드는 쪽이 구현하고 다른 쪽은 항목만 추가**한다 —
  같은 것을 두 번 만들지 않는다.

---

## 실행 순서

```
W0 {계측 기준선}            ← 1회성 실측. 없으면 나머지가 전부 추측이다
     ↓
W1 {일일 자동 점검}          ← ★ 상시 계측 장치. 이후 모든 wave 의 판정 근거
     ↓
W2 {소켓 멀티플렉싱}         ← 효과 최대. 단독 배포 가능
W3 {요청 비용, 프론트}       ← W2 와 병렬 (파일 겹침 확인 필요)
W4 {pool 잠식 쿼리, 백엔드}  ← W2·W3 와 병렬 (계열 다름)
     ↓
W5 {stampede + 캐시 공유}
     ↓
W6 {수평 확장 전제조건}      ← 2호기의 실질 전제
     ↓
W7 {게이트 확정 + 재측정}
```

**이 phase 는 수 개월에 걸친다.** 그래서 순서가 특히 중요하다.

- **W1 을 먼저 하는 이유:** 장기 작업에서 계측 없이 진행하면 **몇 달 뒤 "나아졌는가"에 답할 수 없다.**
  W7 의 게이트 G1·G2·G3 는 전부 **시계열 비교**를 요구한다. 비교 대상은 지금부터 쌓아야 생긴다.
  또한 W1 은 Phase 74 의 슬롯 디스크 감시와 백업 실패 알람을 함께 담으므로, 두 phase 중
  **먼저 도달하는 쪽이 구현**한다.
- **W0 → W1 → W2 만으로도 부분 완료로 인정한다.** 소켓이 1/3 로 줄면 3000명 시나리오의 가장 큰 항목이
  해소되고, 일일 점검이 돌면 그 이후는 데이터를 보며 판단할 수 있다.
- W2~W4 는 계열이 달라(프론트 소켓 / 프론트 요청 / 백엔드 쿼리) 병렬 가능하나,
  **한 번에 하나씩 배포**한다. 동시 배포하면 회귀 원인 분리가 안 된다.

## Success Criteria (what must be TRUE)

- **일일 점검이 매일 돌고 시계열이 누적된다** · 디스크 70% / 일 증분 10GB 초과 시 Telegram 도달 ·
  소진 예측일 산출 · 주간 요약 1건 · 리포트 부재 26시간 시 Mac 워치독 알림 · **정상 시 즉시 알림 0건**
- POS 탭 1개당 WebSocket **1개** · 서버 동시 연결이 전환 전 대비 **1/3 이하**
- **`/expenses/search` 대량 조회 0건**(서버 집계로 대체) · **POS 상품 검색이 서버에서 수행되고 검색 정확성 회귀 없음** ·
  `/payment-methods` 직접 조회 0건
  *(≤200 인 화면 표시용 목록은 Phase 73-15 승인 범위 — 완료 기준이 아니다)*
- 동일 key 동시 요청 시 loader **1회** 실행 · 대시보드 TTL 30초 통일
- outbox·campaign claim **p95 < 100ms** · 4워커 전부의 slow query 기록됨
- **워커 4 → 6 증설 시 참조 데이터 쿼리 수가 증가하지 않음** (β 감소 실증)
- `CRON_ENABLED` 미설정 2번째 프로세스에서 크론 중복 0건
- 커넥션 예산 로그가 **실측값 기반**으로 실제 총량과 일치 (추정값 표기 0건)
- **W7 재측정에서 `cl_waiting` 피크가 W0 기준선 대비 감소** — *"지속 0"은 이 phase 의 완료 기준이 아니라
  2호기 착수 게이트 G1 이다.* 이 phase 는 `cl_waiting` 을 만드는 원인(요청 비용·pool 잠식 쿼리)을 줄일 뿐,
  0 을 보장하지 않는다
- **W7 재측정에서 p95 가 W0 기준선 대비 개선** — 300ms 목표 달성은 이 phase 단독으로 보장하지 않는다
  (Phase 71 프론트 렌더 개선과 함께 판단). **W0-8 에서 p95 를 반드시 수집해야 비교가 성립한다**
- **G1~G6 게이트가 상시 관측 가능** · `66-PLAN.md` 착수 조건이 게이트로 교체됨
- **기능 회귀 0 — W2·W3·W4·W5·W6 각 wave 게이트에 개별 포함** · Phase 64 동시성 스위트 8종 통과 유지

## 되돌리기 어려운 작업 / 위험

| 작업 | 위험 | 완화 |
|---|---|---|
| R1 소켓 단일화 | 실시간 기능 4종 동시 회귀. POS 핵심 경로 | 훅 외부 인터페이스 불변 유지 · 기능별 개별 검증 · 단독 배포 |
| R4-5 판매 쓰기 잔존부 bulk 화 (`:1261-1278`) | `ProductBranch` 유니크 충돌 · `bulkCreate` 부분 실패 · 삽입 순서 변화 | **기존 락 쿼리 `:1201-1207` 무변경**(diff 게이트)이 1차 방어선 · `ON CONFLICT` 처리 명시 · Phase 64 동시성 스위트 통과 게이트 |
| R5-2 advisory lock 리더 | 잘못 구현 시 크론이 **전혀** 안 돌거나 전부 돈다 | transaction-scoped 필수(session-level 금지) · 스테이징 다중 프로세스 검증 |
| R5-5 Redis `maxmemory` | 상향 시 호스트 메모리 압박 | 18GB 유휴라 여유 있음 · 소켓 수 기준 산정 |
| W4 인덱스 추가/제거 | 잘못된 인덱스는 쓰기를 느리게 한다. `slow_query_log` 인덱스 **제거**는 조회 기능을 죽일 수 있다 | `EXPLAIN` 선행 필수 · `CONCURRENTLY` · 제거 전 조회 패턴 확인 |

## 범위 밖 (명시적)

**이 목록이 정본이다.** `75-CONTEXT.md` 「범위 밖」과 `75-PLAN.md` 「이 phase 가 하지 않는 것」은
앞의 7항목(구조적 범위 밖)만 담고, 뒤의 4항목(개별 판단으로 제외된 것 — ≤200 목록 · AllCajas fan-out ·
비상시 소켓 · 번들 최적화)은 각 요구사항 본문에서 근거와 함께 다룬다. 세 문서를 대조할 때 이 구분을 전제한다.

- **API 2호기 · nginx LB 실제 도입** — 전제조건과 판단 게이트(G1~G6)만 만든다. `D-63-2` 해제는 W7 통과 후 별도 phase
- **PG read replica / standby** — 가용성·내구성 축은 **Phase 74** 소관. 읽기 분산은 2호기 결정과 한 묶음
- **`store_id` 샤딩 · 테이블 파티셔닝** — Tier 3. 단일 PG 처리량 상한 실측 후
- **hot-row 완화** — Phase 66 P2 조건("단일 매장 피크 20건/s") 유지
- **`pool.max` 증가** — pgbouncer 슬롯 50 이 실질 상한
- **Redis 영속화** — pub/sub 전용 설계 의도(`--appendonly no`) 유지. `maxmemory` 상향·감시만
- **Phase 65 W8-5 알람 2종** — Phase 65 잔여
- **≤200 인 화면 표시용 목록** — Phase 73-15 가 전수조사로 승인한 값(R2 참조)
- **`AllCajasOverview` `/resume` fan-out** — 의도적 설계. 카하 수 상한 실측 후 재판단(R2 참조)
- **`DespachoBoard` · `DeliveryBoard` · `useRemoteSupport` · `soporte/visor` 소켓** — 상시 연결 아님(R1 참조)
- **프론트 번들 최적화(MUI tree-shaking 등)** — `next.config.js:139-141` 이 미완을 기록하고 있으나
  별도 작업으로 분리돼 있다. **W0 에서 번들 바이트를 계측만** 하고 조치는 이번 범위 밖.
  사용자 수에 선형 비례하는 비용이므로 계측 결과에 따라 별도 phase 로 올린다

## 금지 사항

- **`pool.max` 증가 금지** — pgbouncer 슬롯 50 이 실질 상한. 큐가 DB 안으로 이동할 뿐이다
- **2호기 선착수 금지** — W5 완료 + W6 게이트 통과 전에는 붙이지 않는다
- **session-level advisory lock 금지** — transaction pooling 에서 깨진다
- **`sales-create.service.ts:1201-1207` 무변경** — 이미 올바른 bulk 락(`ORDER BY product_id ... FOR UPDATE`)이다.
  `productId` 오름차순 순서를 바꾸면 교착이 난다(`CLAUDE.md` 쓰기 경로 규약)
- **인덱스 추측 추가 금지** — `EXPLAIN (ANALYZE, BUFFERS)` 선행
- **신규 로딩·캐시 레이어 신설 금지** — 기존 것을 합치거나 걷어내는 방향(Phase 71 과 동일 원칙)
- **hot-row 완화 선착수 금지** — Phase 66 조건(단일 매장 20건/s) 미달 시 정합성 회귀 위험만 얻는다
