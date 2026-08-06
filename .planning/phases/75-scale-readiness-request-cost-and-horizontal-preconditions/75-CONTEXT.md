# Phase 75: 확장 준비 — 요청 비용 절감 + 수평 확장 전제조건 — Context

**Created:** 2026-08-06
**Source:** 사용자 질문("사용자 3000명 대비 어떤 기술을 준비해야 하는가") + `load-stress-review-2026-07-31.md` + `pg-pool-review-2026-07-31.md` 를 **2026-08-06 코드로 재대조**
**결론 요약:** 병목은 **하드웨어가 아니라 요청 1건의 비용과 노드 간 일관성 비용**이다. 이걸 먼저 낮추지 않으면 서버를 늘려도 **느려진다.**

---

## 왜 이 phase 인가

### 표면과 실제가 어긋나 있다

| 관점 | 값 | 출처 |
|---|---|---|
| CPU | 8코어 중 **4개만** 사용 (의도적 — PG·nginx 여유) | `ecosystem.config.js` |
| 메모리 | 31GB 중 **18GB 유휴**, 워커 RSS 232MB | `ecosystem.config.js` 주석 |
| 부하 진단 | **동시접속 500 기준 위험등급 HIGH** | `load-stress-review-2026-07-31.md` |

**하드웨어는 남는데 500에서 위험하다.** 3000명을 목표로 서버를 늘리는 것은 이 모순을 해결하지 못한다.

### 사용자 수는 설계 지표가 아니다

같은 3000명이라도 **300개 매장에 흩어진 3000명**과 **한 매장에 몰린 3000명**은 다른 시스템을 요구한다.
전자는 현 구조로도 가고, 후자는 지금도 터진다.

이 phase 가 다루는 실제 지표는 셋이다.

1. **피크 시간 초당 판매 커밋 수**
2. **동시 WebSocket 연결 수**
3. **단일 매장 hot-row 경합** — Phase 66 이 이미 "단일 매장 피크 20건/s"를 착수 조건으로 명시(`66-PLAN.md` P2)

---

## 이론적 근거 — 왜 "서버 추가"가 답이 아닌가

### Little's Law — pool 을 늘리는 게 아니라 체류 시간을 줄여야 한다

> L = λW (동시 처리 수 = 처리율 × 응답시간)

pool 슬롯 20개로 100ms 쿼리 → 초당 200건. **같은 슬롯 20개로 3초 쿼리 → 초당 6.6건.**
실측된 `sync_outbox` claim 3,015ms 는 그 슬롯의 처리량을 30분의 1로 만든다.

pool 을 늘리면 큐가 **앱에서 DB 안으로 이동할 뿐**이고, DB 안의 대기는 락을 쥔 채 기다리므로 더 비싸다.
`database.module.ts` 주석과 `CLAUDE.md` 가 이미 "pool max 증가 금지"를 못 박은 이유가 이것이다.

### Universal Scalability Law — 노드를 늘리면 느려지는 구간이 실재한다

> C(N) = N / (1 + α(N−1) + βN(N−1))
> α = 경합(직렬화) · β = 일관성(노드 간 상태 동기화)

- **α** = 단일 PostgreSQL 커밋. 멀티테넌트 단일 DB라 모든 매장 쓰기가 한 곳으로 모인다
- **β** = **워커 로컬 캐시** · 크론 리더 중복 · 커넥션 예산의 노드 비례 증가

β > 0 이면 **어느 지점부터 노드를 늘릴수록 처리량이 감소한다.** 이 시스템은 β 가 크다.

> **`D-63-2`(서버 2호기 보류)는 결과적으로 옳았다. 다만 이유가 "아직 필요 없어서"가 아니라
> "지금 붙이면 오히려 느려져서"다.** 이 차이가 중요하다 — 전자는 "사용자가 늘면 붙이면 된다"로 이어지고,
> 후자는 "β 를 먼저 줄여야 붙일 수 있다"로 이어진다. 이 phase 는 후자를 실행한다.

### 다행인 것

샤딩 키가 이미 존재한다. 거의 모든 테이블에 `store_id` 가 있다(멀티테넌트 설계).
최후의 수단이지만 그 수단이 **열려 있다**는 것은 큰 자산이다.

---

## 결함 목록

| # | 결함 | 심각도 | Wave |
|---|------|--------|------|
| 1 | **소켓 증폭** — 동일 URL·동일 네임스페이스로 `io()` 를 여러 번 호출해 **물리 연결이 개별 생성**된다. POS 탭 1개 = 소켓 3개 | 높음 | W2 |
| 2 | **클라이언트 집계용 대량 조회** — `/expenses/search?pageSize=9999`(합계를 내려고 전량 수신) · `/products/by-parent?pageSize=1000`(POS 검색이 클라이언트에서 발생). **「규약 위반」이 아니라 「서버 집계·서버 검색 미적용」이 문제다** — 아래 정정 참조 | 높음 | W3 |
| 3 | **참조 데이터 SWR 미적용** — `useEffect + apiConnector.get` 직접 조회가 POS mount 마다 발생 | 높음 | W3 |
| 4 | **cache stampede** — `MemoryCacheService` 에 single-flight 없음. TTL 경계에서 동일 쿼리가 워커별 중복 실행 | 높음 | W5 |
| 5 | **캐시가 워커 로컬** — Redis 는 invalidation 만 전파하고 **값을 공유하지 않는다**. 노드를 N배 늘리면 같은 데이터를 N번 조회 → **수평 확장이 DB 부하를 늘린다**(USL 의 β) | 높음 | W5 |
| 6 | **pool 잠식 쿼리** — outbox claim 3,015ms · campaign claim 2,171ms · `slow_query_log` INSERT 2,069ms. **관측 기능이 스스로 느린 쿼리다** | 높음 | W4 |
| 7 | **커넥션 예산 역전** — 4워커 × 20 = 80 vs pgbouncer 슬롯 50. 공개몰 pool 격리 오판 시 최대 140 | 높음 | W6 |
| 8 | **크론 리더가 컨테이너 수에 비례 중복** — 2호기에 `CRON_ENABLED=false` 를 **수동으로** 주지 않으면 전부 리더 | 높음 | W6 |
| 9 | **Redis 단일 지점 + `noeviction`** — `maxmemory 128mb`. 소켓 fanout 증가 시 메모리가 차면 eviction 이 아니라 **쓰기 에러** | 중 | W6 |
| 10 | **확장 판단 기준 부재** — `D-63-2` 재개 조건이 "컨테이너 2대 결정 시"라는 순환 논법. 측정 가능한 게이트가 없다 | 중 | W7 |
| 11 | **추세 관측 장치 부재** — 감시가 `uptime-watchdog`(살아 있는가)과 500 알람뿐이다. **둘 다 "지금 이 순간"만 본다.** 디스크·DB 크기·커넥션·소켓이 서서히 차오르는 것을 못 잡고, 수 개월짜리 개선 작업의 **진척도 판정할 수 없다** | 높음 | **W1** |
| 12 | **감시기 생존을 아무도 감시하지 않는다** — 2026-08-06 실측에서 launchd 에이전트 **4개 전부 미작동**이 확인됐다(아래 참조). 감시 스크립트가 죽어도 알 방법이 없다 | **치명** | **W1** |

---

## 2026-08-06 코드 재대조 — 리뷰 이후 달라진 것

`load-stress-review-2026-07-31.md` 를 그대로 믿지 않고 현재 코드로 다시 확인했다.

### 부분적으로 해결된 것

| 리뷰 지적 | 현재 상태 |
|---|---|
| `DailySalesStats.tsx` pageSize **9999** | **절반만 수정됨.** `/sales/all` 경로는 Phase 73-14 가 서버 집계(`GET /sales/daily-summary`)로 대체했고 `:45` 주석에 이력이 남아 있다. 그러나 **같은 파일 `:60` 의 `/expenses/search?pageSize=9999` 는 그대로 살아 있다.** 초안이 "이미 수정됨"으로 단정했던 것을 정정한다 |

### ★ 초안의 가장 큰 오류 — 「pageSize 최대 50 규약」은 이미 공식 완화됐다

초안은 `pageSize` > 50 을 전부 「규약 위반」으로 규정하고 "위반 0건"을 목표로 삼았다.
**그 목표는 틀렸고, 실행하면 Phase 73 을 회귀시킨다.**

`api-ventago/src/common/pagination/pagination.util.ts:8-21`(Phase 73-08/73-15)이
**전 클라이언트 앱 호출부를 전수 조사한 뒤 명시적으로 반대 결정**을 기록해 두었다.

> *"여기서 정하는 상한은 **남용 방지 백스톱**이지 UX 규약이 아니다. CLAUDE.md 의 「pageSize 최대 50」은
> 프론트가 화면에 뿌릴 때의 규약이고, 서버 상한을 50 으로 잡으면 **정상 화면이 조용히 잘린다.
> 조용한 오답은 느린 응답보다 나쁘다**"* — `DEFAULT_MAX_PAGE_SIZE = 200`, `BULK_MAX_PAGE_SIZE = 10000`

`ProductList.tsx:198-200` 주석에는 상한을 걸었다가 **POS 검색이 최신 10건에서만 매칭되던 회귀 이력**이 남아 있다.
그리고 `pageSize` > 50 사용처는 초안이 센 5곳이 아니라 **10곳 이상**이라, "0건" grep 게이트를 걸면
**W3 범위 밖 파일 8개 이상에서 실패**해 게이트 자체가 실행 불가능하다.

**따라서 목표를 "숫자를 낮춘다" → "대량 조회가 필요 없게 만든다"로 바꿨다.**
Phase 73-14 가 판매에 대해 이미 증명한 패턴(클라이언트 집계 → 서버 집계)을 나머지에 적용한다.

| 유형 | 위치 | 값 | 조치 |
|---|---|---|---|
| 클라이언트 집계 | `DailySalesStats.tsx:60` `/expenses/search` | 9999 | **서버 집계로 대체** (W3) |
| 카탈로그 전량 | `ProductList.tsx:202` · `DraftAndDebtorsList.tsx:234` | 1000 | **서버 검색으로 대체** (W3, 회귀 이력 주의) |
| 화면 표시용 | 레스토랑 3곳 · `ModalPriceInactiveList`(100×4) · `PriceTypesList` · `InvoiceAditional`(100×2) · `talleres_LotesListView` · `AccessLogsView` · `useNotices`/`ClientLedgerView`/`SlowQueriesTab` | ≤200 | **범위 밖** — Phase 73-15 승인 범위 |

### 그 밖에 잔존하는 것

| 항목 | 위치 | 값 |
|---|---|---|
| single-flight 부재 | `api-ventago/src/common/cache/memory-cache.service.ts` | `get`/`set`/`del`/`delByPrefix`/`clear` 만 존재, in-flight 병합 키워드 0건 |
| 참조 데이터 직접 조회 | `/payment-methods` **5곳** — `CuentasPorCobrarTab:56` · `EnvioTimeline:181` · `SeniaRegisterModal:45` · `CreditPaymentModal:53` · `RestaurantPaymentModal:166` | SWR 훅 미적용 |

### 리뷰보다 **나쁜** 것 — 소켓 사용처가 3곳이 아니라 8곳

리뷰는 훅 3개(`useThermalAgentStatus` · `useSuspendedSaleSocket` · `useMpApprovedSocket`)만 지적했으나,
실제 `socket.io-client` 소비처는 **8곳**이다.

```
src/views/homes/hook/useSuspendedSaleSocket.ts:41
src/views/homes/hook/useThermalAgentStatus.ts:78
src/views/mercadopago/hooks/useMpApprovedSocket.ts:33
src/components/team-chat/TeamChatPanel.tsx:56
src/views/ventas-online/DespachoBoard.tsx
src/views/restaurante/DeliveryBoard.tsx
src/hooks/useRemoteSupport.ts:173
src/pages/soporte/visor.tsx:117
```

앞의 4개는 **완전히 동일한 호출 형태**다.

```ts
io(WS_URL, { transports: ['websocket'], auth: { token } })
```

**여기가 핵심이다.** socket.io-client v4 는 같은 URL 이면 Manager 를 재사용하지만,
**같은 네임스페이스(`/`)를 다시 요청하면 `sameNamespace` 판정으로 새 Manager·새 물리 연결을 만든다.**
한 Manager 는 네임스페이스당 Socket 1개만 가질 수 있기 때문이다.

즉 **동일 URL·동일 네임스페이스로 4번 호출 = WebSocket 4개**다. 멀티플렉싱이 되고 있다는 착각이 위험하다.

| 규모 | 사용자 소켓 | agent 소켓 | 합계 |
|---|---|---|---|
| 리뷰 기준(500 동시) | ~1,500 | ~1,000 | ~2,500 |
| **3000명 시나리오** | **~6,000** | ~600 | **~7,000** |

### 리뷰보다 **나은** 것 — 크론 리더에 스위치가 있다

`pg-pool-review` 는 "`NODE_APP_INSTANCE` 없는 컨테이너는 모두 리더"라고만 적었으나,
`src/common/cron/cron-leader.ts` 에는 **`CRON_ENABLED=false` 컨테이너 단위 스위치가 이미 있다.**

```ts
if (process.env.CRON_ENABLED === 'false') return false;
const instance = process.env.NODE_APP_INSTANCE;
return instance === undefined || instance === '' || instance === '0';
```

다만 이것은 **수동 설정 의존**이다. 2호기 배포 시 이 env 를 빠뜨리면 outbox·campaign 이 2배 실행된다.
"기본값이 안전"이 아니라 "기억해야 안전"한 구조라, W6 에서 advisory lock 기반으로 승격한다.

---

## 범위 밖 (명시적)

- **API 2호기 · nginx LB 실제 도입** — 이 phase 는 **전제조건과 판단 게이트**만 만든다.
  `D-63-2` 해제는 W7 게이트를 통과한 뒤 **별도 phase** 에서 결정한다.
  이 순서를 어기면 USL 하강 구간에 진입해 "역시 서버가 부족하다"는 잘못된 결론에 도달한다.
- **PG read replica / standby** — 가용성·내구성 축은 **Phase 74** 소관.
  읽기 분산은 2호기 결정과 한 묶음이라 W7 이후.
- **`store_id` 샤딩 · 테이블 파티셔닝** — Tier 3. 단일 PG 처리량 상한이 실측으로 확인된 뒤.
- **hot-row 완화** — Phase 66 P2 의 착수 조건("단일 매장 피크 실측 20건/s 초과") 유지.
  그 전에 손대면 정합성 회귀 위험만 얻는다.
- **pool.max 증가** — 금지. pgbouncer 슬롯 50 이 실질 상한이며 Little's Law 상 해결책이 아니다.
- **Redis 영속화** — pub/sub 전용 설계 의도(`--appendonly no`)는 유지. `maxmemory` 상향과 감시만 다룬다.
- **Phase 65 W8-5 알람 2종** — Phase 65 잔여로 남긴다.

**개별 판단으로 제외된 것** (근거는 `75-SPEC.md` 각 요구사항 본문):

- **≤200 인 화면 표시용 목록 전부** — Phase 73-15 가 호출부 전수조사로 승인한 값 (R2)
- **`AllCajasOverview.tsx:66-72` 의 `/resume` fan-out** — `:3` 주석이 *"열린 카하는 보통 1~5개 →
  개별 resume 은 Promise.all 병렬(pool 부담 최소)"* 라고 **의도적 설계임을 명시**한다.
  결함으로 규정하려면 카하 수 상한 실측(W0-12)이 선행돼야 한다 (R2)
- **`DespachoBoard:245` · `DeliveryBoard:147` · `useRemoteSupport:173` · `soporte/visor.tsx:117` 소켓** —
  페이지 단위 mount 라 상시 연결이 아니다 (R1)
- **프론트 번들 최적화(MUI tree-shaking 등)** — `next.config.js:139-141` 이 미완을 기록하고 있으나 별도 작업으로
  분리돼 있다. **W0-9 에서 계측만** 하고 결과에 따라 별도 phase 로 올린다
