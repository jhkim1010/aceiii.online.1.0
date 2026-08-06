# Phase 75: 확장 준비 — 요청 비용 절감 + 수평 확장 전제조건 — Plan

**Created:** 2026-08-06
**Source:** `75-SPEC.md` (R1~R7)
**Waves:** 8 (W0~W7)
**성격:** **장기 phase — 수 개월.** 한 번에 끝내지 않는다. W1(일일 점검)이 그동안의 판정 근거가 된다.

---

## 실행 순서

```
W0 {계측 기준선}            1회성 실측 · 반나절
     ↓
W1 {일일 자동 점검}          ★ 상시 계측 · 이후 모든 판정의 근거 · Phase 74 와 공유
     ↓
W2 {소켓 멀티플렉싱}         효과 최대 · 단독 배포
W3 {요청 비용, 프론트}       W2 와 계열 다름 — 병렬 가능, 배포는 순차
W4 {pool 잠식 쿼리, 백엔드}  W2·W3 와 병렬 가능, 배포는 순차
     ↓
W5 {stampede + 캐시 공유}
     ↓
W6 {수평 확장 전제조건}      2호기의 실질 전제
     ↓
W7 {게이트 확정 + 재측정}    D-63-2 재검토 판단 근거 확정
```

**부분 완료 인정 지점:** W0 → W1 → W2. 소켓이 1/3 로 줄고 일일 점검이 돌면
그 이후는 데이터를 보며 판단할 수 있다.

**배포 원칙:** W2~W4 는 계열이 달라 개발은 병렬 가능하나 **배포는 반드시 하나씩** 한다.
동시 배포하면 회귀 원인을 분리할 수 없다.

---

## W0. 계측 기준선 — 1회성 실측 (반나절)

**측정 없이 시작하면 몇 달 뒤 "나아졌는가"에 답할 수 없다.**

| # | 태스크 | 명령 |
|---|---|---|
| 0-1 | pgbouncer 실제 대기·통계 | `psql -p 5432 -U pgbouncer -d pgbouncer -c 'SHOW POOLS;' -c 'SHOW STATS;'` |
| 0-2 | 느린 쿼리 상위 15 | `psql -p 5434 -d ventago -c "SELECT calls, mean_exec_time, total_exec_time, query FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 15;"` |
| 0-3 | 동시 소켓 실측 | `ss -tn state established '( sport = :5002 )' \| wc -l` |
| 0-4 | 실제 API 인스턴스 수 (예산 산식 근거) | `docker ps --filter name=api_ventago` + `pm2 list` |
| 0-5 | 디스크·DB 크기 기준점 | `df -h` · `psql -p 5434 -c "SELECT pg_size_pretty(pg_database_size('ventago'));"` |
| 0-6 | POS 최초 진입 요청 수·전송량 (W3 비교 기준) | 브라우저 DevTools Network — 캐시 비우고 1회 |
| 0-7 | POS 탭 1개당 WebSocket 수 (W2 비교 기준) | DevTools Network › WS |
| 0-8 | **route p95 실측** (SC 비교 기준) | 기존 route timing 계측(Phase 1)에서 수집. **없으면 W7 에서 비교가 불가능하다** |
| 0-9 | **프론트 번들 바이트** (사용자 수에 선형 비례하는 비용) | `@next/bundle-analyzer` 1회 실행 — 계측만, 조치는 범위 밖 |
| 0-10 | **`PGBOUNCER_POOL_SIZE` 실측 고정** — 현재 미설정 시 로그에 `'50(추정)'` 을 찍는다. **추정값이면 G5 게이트가 성립하지 않는다** | `SHOW POOLS` 결과로 env 고정 |
| 0-11 | **워커 수 단일 출처 확인** — `ecosystem.config.js:18 instances` 와 `:32 WEB_CONCURRENCY` 가 별도 하드코딩. **W6 의 4→6 실험이 이 이중 관리로 예산 로그를 틀리게 만든다**(G3 전제) | 코드 확인 |
| 0-12 | 열린 caja 수 분포 (R2 의 `/resume` fan-out 판단 근거) | `SELECT count(*) FROM ... WHERE status='open' GROUP BY store_id` |

- **게이트:** 0-1·0-2·0-3·**0-8** 을 모르면 다음으로 가지 않는다.
  **추측 최적화는 반드시 엉뚱한 곳을 고친다.** 특히 0-8(p95)은 W7 비교의 유일한 기준선이라 빠뜨리면
  "나아졌는가"에 영원히 답할 수 없다.
- 전부 조회성이라 승인 불필요. `pg_stat_statements` 확장이 없으면 설치 여부를 먼저 확인한다.

---

## W1. 일일 자동 점검 (R7) — ★ 최우선 · Phase 74 와 공유

**이 wave 가 나머지 전부의 판정 근거다.** 그리고 Phase 74 의 슬롯 디스크 감시·백업 실패 알람이
여기에 얹히므로, **두 phase 중 먼저 도달하는 쪽이 구현하고 다른 쪽은 항목만 추가**한다.

| # | 태스크 | 위치 |
|---|---|---|
| 1-1 | `ops-daily-check.sh` 수집기 — 하루 1회, 조회성 쿼리만. **pgbouncer 우회 5434 직결, 커넥션 1개** (앱 pool 무영향) | 서버 `/var/lib/postgresql/ops-metrics/` |
| 1-2 | JSONL append (`daily.jsonl`) — **DB 테이블 금지.** DB 가 아플 때도 기록이 남아야 하고, 그때가 가장 중요하다 | 서버 |
| 1-3 | 수집 항목 구현 — 디스크(파티션별) · DB 크기 · 상위 10 테이블 · dead tuple/autovacuum · WAL 아카이브·슬롯 lag · 백업 mtime/크기/`TABLE DATA` 수 · pgbouncer `cl_waiting`·POOLS·STATS · 동시 소켓 · 느린 쿼리 상위 · Docker 이미지/로그 용량 | 서버 |
| 1-4 | **전일 대비 증분 + 7일 평균 증분** 계산 — 절대값보다 먼저 잡힌다 | 서버 |
| 1-5 | **소진 예측** — 7일 평균 증분으로 "N일 후 디스크 참" 산출. **잔여 30일 미만이면 경고 승격.** 이 장치의 핵심 가치 | 서버 |
| 1-6 | 임계 판정 — 디스크 >70% 경고 / >85% 긴급 · 일 증분 >10GB 경고 · WAL 아카이브 > `max_slot_wal_keep_size`×0.7 경고 · 슬롯 lag 급증 긴급 · 백업 mtime >26h 긴급 · `cl_waiting`>0 지속 경고 · 테이블 주간 증가율 이상치 경고 | 서버 |
| 1-7 | 알림 — `tools/uptime-watchdog.sh` 의 `send_telegram()` + `.uptime.env` 재사용. **새 채널 만들지 않는다.** **임계 위반 시에만 즉시 발송** | 서버 |
| 1-8 | **주 1회 트렌드 요약** 1건 — 추세·소진 예측·주요 변화. 읽히는 빈도라 유용하다 | 서버 (일요일) |
| 1-9 | **부재 감지** — 일일 리포트 26시간 미갱신 시 **Mac launchd** 에서 알림. 서버 안 감시는 서버가 죽으면 같이 죽는다. **Phase 74 R4-3 과 같은 장치 공유** | Mac |
| 1-10 | JSONL 을 `dropbox_sync.sh` 업로드 대상에 추가 — 오프사이트 시계열 사본 | 서버 |
| 1-11 | 스크립트를 `scripts/ops-daily-check.sh` 로 저장소 **커밋** — 서버에만 두면 서버 소실 시 함께 사라진다 | 저장소 |
| **1-13** | **★ 상호 감시 (결함 12)** — Mac 워치독이 `launchctl list` 로 에이전트 5개 확인 + 서버에 heartbeat touch / 서버 점검이 heartbeat 26h 초과 시 긴급 알림. **2026-08-06 launchd 4개 사망 사고의 재발 방지** | 양쪽 |
| 1-12 | **소음 검증** — 정상 운영 7일간 즉시 알림 **0건**. 소음이 나면 임계를 조정한다 | 관찰 |

- **게이트:** JSONL 일 1행 누적 · 디스크 70%/일 증분 10GB 인위 유발 시 Telegram 도달 ·
  소진 예측일 산출 · 주간 요약 1건 도착 · 리포트 부재 시 Mac 알림 ·
  **에이전트 1개 unload 시 Mac 워치독 감지** · **heartbeat 삭제 시 서버 점검 감지** ·
  **정상 7일간 즉시 알림 0건** · 수집기가 `cl_waiting` 을 만들지 않음

- **진행 상황 (2026-08-06 1차):** launchd 5개 재등록 완료(exit 0) · `.uptime.env` 배치 완료 ·
  **Telegram 알림 경로 끝단까지 실증**(`STALE_HOURS=0` 강제 발송 → 수신 확인) ·
  `ssh -n` 누락으로 파이프 실행 시 스크립트가 조용히 중단되던 결함 1건 발견·수정.

- **진행 상황 (2026-08-06 2차 — 서버 배포 완료):** `docs/OPS_DAILY_CHECK_SETUP.md` 1~6단계 전부 실행.
  `/var/lib/postgresql/ops-metrics/` 배치 · 크론 `10 4 * * *` 등록 · `daily.jsonl` 1행 누적 ·
  Dropbox `ventago_pg_backups/ops-metrics/daily.jsonl` 업로드 확인.
  **게이트 통과 6건** — JSONL 누적(1) · 디스크 임계 알림(2) · 백업 부재 알림(3) · 주간 요약(5) ·
  에이전트 사망 감지(8) · heartbeat 상호 감시 양방향(9).
  **2·8 은 사용자 단말 수신까지 확인**(2026-08-06) — 발송 로그가 아니라 도달 확인이다.
  임계 판정 → 발송 → 도달 전 구간이 실증됐으므로, 앞으로 알림이 안 오면 **임계 로직만** 의심하면 된다.

  배포 중 발견·수정한 결함 **4건**:
  1. **SSH 키가 ssh-agent 에 없어 Mac 워치독이 매시간 "판정 보류"만 남기고 있었다** — 백업이 멈춰도
     알림이 안 가는 상태였다. `~/.ssh/config` 에 `AddKeysToAgent yes` + `UseKeychain yes` 추가로 재부팅 후에도 유지.
  2. **pgbouncer 수집 불능** — `-U pgbouncer` + unix socket 으로 붙으려 했으나 pgbouncer 는 TCP 전용이고
     `stats_users = coolsistema,postgres` 다. `-h 127.0.0.1 -U coolsistema` + `~postgres/.pgpass` 로 교정.
     **`cl_waiting` 이 G1 게이트의 유일한 근거라 이게 없으면 W7 판정이 성립하지 않는다.**
     컬럼 위치 파싱도 헤더 이름 기반으로 교체(1.19 에서 `cl_*_cancel_req` 가 끼어들어 `sv_active` 위치가 밀렸다).
  3. **heartbeat 파일이 *아예 없으면* 침묵했다** — 게이트 9(삭제 후 CRIT)를 구현이 통과 못 하는 상태.
     부재도 CRIT 로 승격. Mac 쪽 `daily.jsonl` 부재도 대칭으로 승격(배포 완료 전 bootstrap 예외였다).
  4. 디스크 임계를 env 로 덮어쓸 수 있게 함 — 게이트 2 를 **스크립트를 고치지 않고** 반복 검증하기 위해.
     고쳐서 검증하면 원복을 빠뜨린다.

  **남은 것:** 1-12(정상 7일 알림 0건 — 2026-08-13 판정) · 소진 예측(이력 2일 필요, 08-07 크론 후) ·
  `API 연결` 실측(배포 시각이 야간이라 established 0 이었다 — **영업시간 재확인 필요**).
  **W1 은 1-12 통과 전까지 완료로 표시하지 않는다.**
- **주의:** 임계를 너무 민감하게 잡으면 알람이 소음이 되고, 소음이 된 알람은 **진짜 사고도 함께 묻는다.**
  1-12 를 통과할 때까지 완료로 표시하지 않는다.

---

## W2. 소켓 멀티플렉싱 (R1) — 효과 최대 · 단독 배포

| # | 태스크 | 대상 |
|---|---|---|
| 2-1 | `RealtimeProvider` 신설 — 인증 소켓 **1개**를 Context 로 제공. 재연결·토큰 갱신 일원화 | `src/context/RealtimeContext.tsx` (신규) |
| 2-2 | `useSuspendedSaleSocket.ts:41` → Provider 구독. **훅 반환 인터페이스 불변** | 프론트 |
| 2-3 | `useThermalAgentStatus.ts:78` → Provider 구독 | 프론트 |
| 2-4 | `useMpApprovedSocket.ts:33` → Provider 구독 | 프론트 |
| 2-5 | `TeamChatPanel.tsx:56` → Provider 구독 | 프론트 |
| 2-6 | 기능 분리를 **room join 이벤트**로 — 서버의 기존 `branch:{id}` room 패턴(Phase 40) 답습 | 프론트 + 백엔드 |
| 2-7 | 생명주기 — 마지막 구독자 unmount 후에도 **연결 유지**(재연결 폭주 방지), **로그아웃 시에만** 해제 | 프론트 |
| 2-8 | `print.gateway.ts:106` `server.fetchSockets()` + **`:106-127` 전체 순회** → agent 별 room. 저장소 내 `fetchSockets` 사용처는 이 1곳뿐 (SPEC R1-6) | 백엔드 |
| 2-9 | `PrinterConfigTab.tsx:73-93`(`:90` `setInterval(fetchAgents, 30_000)`) 폴링 제거 — realtime 채널이 이미 있다 (SPEC R1-7) | 프론트 |

- **범위 제외:** `DespachoBoard:245` · `DeliveryBoard:147` · `useRemoteSupport:173` · `pages/soporte/visor.tsx:117` —
  페이지 단위 mount 라 상시 연결이 아니고, 원격지원은 성격이 다르다. 별도 판단.
  (`socket.io-client` 소비처는 총 **8곳** — 초안의 7곳은 `visor.tsx` 누락이었다.)
- **게이트:** POS 탭 1개당 WS **1개**(DevTools) · 실시간 기능 4종 전부 동작(보류판매·agent 상태·MP 승인·팀챗) ·
  서버 동시 연결 **1/3 이하**(0-3 대비) · 로그아웃 시 해제 · `fetchSockets()` 사용처 0건 ·
  `PrinterConfigTab` 폴링 제거 후에도 agent 상태 실시간 갱신 · **기능 회귀 0**
- **위험:** POS 핵심 경로의 실시간 기능 4종이 동시에 회귀할 수 있다. **훅 외부 인터페이스를 바꾸지 않는 것**이
  1차 방어선이다. 기능별로 개별 검증하고 단독 배포한다.

---

## W3. 대량 조회를 서버 집계로 대체 (R2) — 프론트 + 백엔드

> **★ 착수 전 필수 (3-0).** 초안의 "`pageSize` 50 규약 복원, grep 게이트 0건"은 **실행 불가능하고 유해했다.**
> `pagination.util.ts:8-21`(Phase 73-08/73-15)이 전 클라이언트 호출부 전수조사 후
> `DEFAULT_MAX_PAGE_SIZE=200` / `BULK_MAX_PAGE_SIZE=10000` 을 **명시적으로 결정**해 두었고,
> `ProductList.tsx:198-200` 에는 상한을 걸었다가 **POS 검색이 최신 10건에서만 매칭되던 회귀 이력**이 있다.
> 게다가 ≤200 사용처가 저장소에 10곳 이상이라 grep 게이트를 지금 걸면 **W3 범위 밖 파일 8개 이상에서 실패**한다.
> **목표를 "숫자를 낮춘다" → "대량 조회가 필요 없게 만든다"로 바꾼다.**

| # | 태스크 | 위치 |
|---|---|---|
| **3-0** | **`CLAUDE.md` ↔ `pagination.util.ts` 규약 충돌 해소** — 「pageSize 최대 50」을 실제 결정과 일치시킨다. **이 작업이 선행되지 않으면 나머지가 Phase 73 회귀가 된다** | `CLAUDE.md` |
| 3-1 | **`DailySalesStats.tsx:60` `/expenses/search?pageSize=9999` → 서버 집계 엔드포인트.** Phase 73-14 의 `GET /sales/daily-summary` 와 같은 패턴·명명. **이 phase 에서 가장 확실한 이득** | 프론트 + 백엔드 |
| 3-2 | **`ProductList.tsx:202` `/products/by-parent?pageSize=1000` → 서버 검색.** ⚠ 위험 — `:198-200` 회귀 이력(검색이 최신 10건에서만 매칭) **재현 테스트 필수**. 서버 검색이 카탈로그 전량을 대상으로 하지 않으면 같은 사고가 반복된다. **3-1 과 분리 배포** | 프론트 + 백엔드 |
| 3-3 | `DraftAndDebtorsList.tsx:234` 동일 패턴 — 3-2 검증 후 적용 | 프론트 |
| 3-4 | 참조 데이터 → SWR 훅. **`/payment-methods` 5곳부터** (`CuentasPorCobrarTab:56` · `EnvioTimeline:181` · `SeniaRegisterModal:45` · `CreditPaymentModal:53` · `RestaurantPaymentModal:166`) | 프론트 |
| 3-5 | 백엔드 N+1 — `clients.service.ts:318-331` 루프 내 `findAll()`(`:322`) 제거 | 백엔드 |

- **범위 제외 (명시):** ≤200 인 화면 표시용 목록 **전부** — 레스토랑 3곳(200) · `ModalPriceInactiveList`(100×4) ·
  `PriceTypesList`(100) · `InvoiceAditional`(100×2) · `talleres_LotesListView`(100·100·200) ·
  `AccessLogsView`(200) · `useNotices`/`ClientLedgerView`/`SlowQueriesTab`. Phase 73-15 승인 범위다.
  **`AllCajasOverview.tsx:66-72` `/resume` fan-out 도 제외** — `:3` 주석이 *"열린 카하는 보통 1~5개 →
  Promise.all 병렬(pool 부담 최소)"* 라고 의도를 명시. 0-12 실측으로 반박되지 않는 한 손대지 않는다.
- **게이트:** `/expenses/search` 대량 조회 0건 · POS 상품 **검색 정확성 회귀 없음**(전량 대상 매칭) ·
  `/payment-methods` 직접 조회 0건 · POS 진입 요청 수·전송량이 0-6 대비 감소 · **기능 회귀 0**
- ESLint: `newline-before-return` · `lines-around-comment` · `no-unused-vars` 가 빌드를 막는다. 수정 후 `npx eslint --fix`.

---

## W4. pool 잠식 쿼리 교정 (R4) — 백엔드

> **★ 초안 정정 2건 (2026-08-06 검증).**
> **(1) `sales-create.service.ts:1176-1220` 은 이미 bulk 화 완료다** — `:1201-1207` 이
> `WHERE product_id = ANY($3::int[]) ORDER BY product_id FOR UPDATE` 이고 `:1192` 주석이
> "루프 대신 1쿼리 + 잠금 순서 고정(N+1 금지)"를 명시한다(Phase 64 W8/R10 + Phase 70 W1).
> 초안은 **완료된 작업을 재지시**했고, 그에 딸린 "락 순서 = 교착" 최고위험 경고도 대상이 없었다.
> **(2) `slow_query_log` 는 이미 비동기 배치다** — `slow-query-buffer.ts` 가 `MAX_BUFFER=2000` 버퍼 +
> 다중행 단일 INSERT + 10초 cron. "전환"할 것이 없다.
>
> **★ 전제 반증 (2026-08-06 W0 실측 — `75-W0-BASELINE.md`, SPEC R4 참조).**
> outbox 3,015ms / campaign 2,171ms 는 **5일치 `pg_stat_statements` 에서 재현되지 않는다**
> (45,009회 실행에 max 1.1ms). `slow_query_log` 는 전체 기간 2행, 오늘 100ms 초과 0건.
> 출처는 07-29 단일 일자 앱 로그이고 **그 로그는 이미 사라졌다**(컨테이너 로그 volume 부재).
> **W4 의 성격이 "느린 쿼리를 고친다" → "재발을 관측하고 근거를 남긴다" 로 바뀐다.**
> 아래 표의 판정을 따른다 — **동결 항목을 근거 없이 착수하지 않는다.**

| # | 태스크 | 판정 · 비고 |
|---|---|---|
| **4-4** | **★ 최우선으로 승격.** slow-query 버퍼를 **워커별 flush**, prune 만 리더에서. `main.ts:161` 이 비리더 프로세스의 `SchedulerRegistry` cron/interval 을 **전부 삭제**하므로 워커 1~3 버퍼는 **영구 유실**된다. `AdminConsoleCron` 의 per-worker `setInterval` 패턴 답습 | **근거 강화** — 기록된 2행이 **전부 `instance=0`**. 관측 공백이 실측으로 확인됐다. `diagnostics.cron.ts:14-23` |
| 4-1 | `EXPLAIN (ANALYZE, BUFFERS)` — outbox · campaign · online_orders | **유지 · 목적 변경** — "원인 규명"이 아니라 **정상 계획을 기록해 재발 시 비교 기준**으로 삼는다. partial index 3종은 이미 존재 |
| 4-5 | 판매 쓰기 경로 **잔존부** bulk 화 — `sales-create.service.ts:1261-1278` 의 품목별 `ProductBranch.findOne`/`create` + `Stocks.create` 루프 → bulk 조회/생성 + `bulkCreate`. `processSaleItems` 의 품목별 `productModel.findOne` 루프도 함께 | **유지** — 느린 쿼리와 무관하게 트랜잭션 점유 시간 문제다. **`:1201-1207` 락 쿼리는 건드리지 않는다** |
| 4-6 | `import.service.ts:95-108,144-154` · `cheques.service.ts:127-142` 순차 DML → bulk | **유지** — 점유 시간이 건수에 선형 비례 |
| ~~4-2~~ | ~~원인이 인덱스로 확정된 경우에만 `CREATE INDEX CONCURRENTLY`~~ | **동결** — 근거 소멸. 재발 실측 전 착수 금지 |
| ~~4-3~~ | ~~`slow_query_log` INSERT(2,069ms) batch 상한 + `statement_timeout`~~ | **동결** — 5일간 2행만 기록한 테이블이다 |
| ~~4-3b~~ | ~~`slow_query_log` 인덱스 3개 재평가~~ | **동결** — 쓰기 부하 자체가 관측되지 않는다. **단 4-4 로 4워커 기록이 살아나면 재평가 대상으로 복귀** |

- **게이트 (재조준 후):** **4워커 전부**의 slow query 기록(4-4 — 현재 `instance=0` 만 기록된다) ·
  outbox·campaign claim p95 **< 100ms 유지**(달성이 아니라 **회귀 방지** 기준이다 — W0 실측 max 1.1ms) ·
  판매 트랜잭션 점유 시간 감소(측정) · import·cheques 대량 처리 시 커넥션 점유 시간 감소 ·
  **Phase 64 동시성 스위트 8종 통과 유지** · **`:1201-1207` 무변경 확인(diff)** · **기능 회귀 0**
- **동결 해제 조건:** 4-2/4-3/4-3b 는 **재발이 실측될 때만** 착수한다. 판정 근거는 W1 일일 점검 JSONL
  (느린 쿼리 상위 · `cl_waiting`)과 4-4 로 살아난 4워커 `slow_query_log` 다.
- **위험:** 4-5 는 재고 쓰기 경로다. 기존 락 쿼리를 건드리지 않는 것이 1차 방어선이고,
  Phase 64 스위트를 통과하지 못하면 즉시 되돌린다.

---

## W5. stampede 제거 + 캐시 공유 (R3 + R5-1)

| # | 태스크 | 비고 |
|---|---|---|
| 5-1 | `MemoryCacheService.getOrLoad(key, ttlMs, loader)` — 같은 key in-flight Promise **병합** | `memory-cache.service.ts` |
| 5-2 | loader 실패 시 Promise 즉시 제거 — **실패가 TTL 동안 고착되지 않게** | 동일 |
| 5-3 | 호출부 **점진 전환** — 한 번에 다 바꾸지 않는다(호출부가 넓다) | 백엔드 |
| **5-4a** | **TTL 분류 기준을 `CLAUDE.md` 에 먼저 정의** (참조 데이터 / 대시보드 / 기타 집계). 규약 없이 숫자만 맞추면 다음에 또 갈라진다 | `CLAUDE.md` |
| 5-4b | 분류에 따라 **5건** 판정·정정 — `subcon/dashboard-v2:25`(60초) · `subcon/dashboard:426`(5분, **같은 파일 `:299` 에 30초 공존**) · `subcon-settlement:544`(2분) · `lote.service:1572`(2분) · `defect-code:55`(60초) | 초안은 2건만 알고 있었다 |
| 5-5 | AFIP cache key 에 `storeId` 명시 — 현재 `afip-header:${cuit}:${sucursal}` 로 "모든 key 에 store_id" 규약 미충족 | `afip-issuer.service.ts:68-84` |
| 5-6 | **캐시 값 공유** — 참조 데이터(60초)를 Redis L2 로. 로컬 L1 + Redis L2 2단. **β 직접 감소** | `getOrLoad` 위에 |

- **게이트:** 동일 key 동시 100 요청 시 loader **1회**(유닛 테스트) · 실패 후 다음 요청에서 재시도 ·
  TTL 분류 기준이 `CLAUDE.md` 에 명시됨 · 5건 전부 판정·정정 · 모든 cache key 에 `storeId` 포함 · **기능 회귀 0**

---

## W6. 수평 확장 전제조건 (R5) — 2호기의 실질 전제

| # | 태스크 | 비고 |
|---|---|---|
| 6-1 | 크론 리더를 **transaction-scoped advisory lock** 으로 승격. **session-level 금지**(pgbouncer transaction pooling 에서 깨진다) | `cron-leader.ts` |
| 6-2 | `CRON_ENABLED` 스위치는 **명시적 비활성화 수단으로 유지** — 제거하지 않는다 | 동일 |
| 6-3 | 공개몰 격리를 **명시 플래그** `SHOP_DB_ISOLATED=true` 로. host 문자열 비교 제거. 그 외에는 fallback `max=5`. **메인 pool max 불변** | `shop-readonly-db.service.ts:19-40` |
| 6-4 | `API_REPLICA_COUNT` 필수 env + 부팅 로그에 `replicas × workers × (main+shop)` 표기 | `database.module.ts:159-192` |
| 6-5 | Redis `maxmemory` 상향(소켓 수 기준 산정) + 사용률 알람(W1 에 항목 추가) | `docker-compose.yml` |
| 6-6 | `noeviction` 유지 여부 실측 판단 — pub/sub 유실 vs 쓰기 에러 트레이드오프 | 판단 후 기록 |
| 6-7 | 운영 `sequelize.sync` 완전 비활성화 검증 — error 로그에 view 의존 컬럼 alter 실패가 반복된다. 노드가 늘면 이 실패도 노드 수만큼 반복 (SPEC R5-6) | `synchronize:false` 는 이미 설정, `SyncService` 호출 조건 확인 |
| **6-8** | **★ 워커 수 이중 관리 해소 (G3 전제)** — `ecosystem.config.js:18 instances:4` 와 `:32 WEB_CONCURRENCY:4` 별도 하드코딩. **4→6 실험이 이 때문에 예산 로그를 틀리게 만든다.** 단일 출처로 통합 (SPEC R5-7) | `ecosystem.config.js` |
| **6-9** | **`PGBOUNCER_POOL_SIZE` 실측값 env 고정** — 미설정 시 `'50(추정)'` 표기. **추정값이면 G5 가 성립하지 않는다.** 0-10 결과 사용 (SPEC R5-8) | env |

- **★ 게이트 (β 감소 실증):** **워커 4 → 6 증설 시 동일 참조 데이터 쿼리 수가 증가하지 않을 것.**
  이게 안 되면 2호기도 안 된다 — 이 실험이 W7 의 G3 다.
- 추가 게이트: `CRON_ENABLED` 미설정 2번째 프로세스에서 크론 중복 **0건** ·
  부팅 로그 예산이 **실측값 기반**으로 실제 총량과 일치(추정값 표기 0건) · 워커 수 단일 출처 ·
  부팅 시 sync 시도 0건 · **기능 회귀 0**
- **승인 필요:** 6-5 Redis 설정 변경(컨테이너 재시작 동반) · 6-1 배포(크론이 전혀 안 도는 실패 모드 존재 —
  스테이징 다중 프로세스 검증 선행)

---

## W7. 게이트 확정 + 재측정 (R6)

| # | 태스크 |
|---|---|
| 7-1 | G1~G6 를 `Centro de Control` `infraestructura` 위젯에 노출. **신규 인프라 금지** — W1 JSONL 을 데이터원으로 |
| 7-2 | 부하 테스트 재실행 — 0-1~0-12 기준선과 대비. **`cl_waiting` 피크와 route p95 를 반드시 포함**(SC 판정 항목이며 0-1·0-8 이 유일한 비교 기준) |
| 7-3 | `66-PLAN.md:109` P2 착수 조건을 **G1~G6 로 교체** (순환 논법 제거) |
| 7-4 | `ROADMAP.md` 에 게이트 상호 참조 기재 (Phase 66 ↔ 75 ↔ D-63-2) |
| 7-5 | `D-63-2` 재검토 여부 **판단만** 한다. 해제는 별도 phase |

### G1~G6 — 2호기 착수 게이트

| 게이트 | 기준 |
|---|---|
| G1 | pgbouncer `cl_waiting` 피크 **지속 0** |
| G2 | outbox·campaign claim **p95 < 100ms** |
| G3 | **워커 4 → 6 증설 시 처리량이 실제로 증가** (β 실증) |
| G4 | 크론 리더가 **advisory lock 으로 보장** |
| G5 | `서버수 × 워커수 × pool.max ≤ pgbouncer 슬롯` |
| G6 | 피크 판매 커밋/s · 동시 소켓 · 단일 매장 hot-row **상시 관측** |

- **게이트:** 6개 전부 위젯에서 확인 가능 · `66-PLAN.md` 갱신 · 상호 참조 기재

---

## 승인 게이트 요약

| 시점 | 내용 | 이유 |
|---|---|---|
| W0 종료 후 | 0-1·0-2·0-3 실측값 | 기준선 없이 진행하면 전부 추측 |
| W1-12 | 정상 7일 알림 0건 확인 | 소음이 된 알람은 진짜 사고를 묻는다 |
| W2 배포 전 | 실시간 4종 개별 검증 결과 | POS 핵심 경로 동시 회귀 위험 |
| W4-2 실행 전 | `EXPLAIN` 결과 + 인덱스 SQL | 잘못된 인덱스는 쓰기를 느리게 한다 |
| W4-5 배포 전 | Phase 64 동시성 스위트 결과 + **`:1201-1207` diff 무변경 확인** | 재고 쓰기 경로 · 기존 락 쿼리 보호 |
| W6-1 배포 전 | 스테이징 다중 프로세스 검증 | 크론이 전혀 안 도는 실패 모드 |
| W6-5 실행 전 | Redis 설정 변경 (재시작 동반) | 서비스 영향 |
| W7-5 | `D-63-2` 재검토 판단 | 되돌리기 어려운 아키텍처 결정 |

---

## 점검 포인트 (장기 실행용)

### 1주 후 — 계측이 존재하는가

- W0 의 세 값(`cl_waiting` 피크 · 느린 쿼리 상위 15 · 동시 소켓 피크)을 아는가
- W1 일일 점검이 돌기 시작했는가
- **판정:** 하나라도 모르면 다음 단계로 가지 않는다

### 1개월 후 — 요청 비용이 줄었는가

- 소켓이 이전 대비 **1/3** 인가
- `/expenses/search` 대량 조회가 서버 집계로 대체됐는가 (**「pageSize 위반 0건」은 폐기된 목표** — W3 서두 참조)
- ~~outbox claim 이 3,015ms → **100ms 미만**인가~~ → **W0 에서 이미 1.1ms.** 질문을 바꾼다:
  **4워커 전부가 slow query 를 기록하는가**(4-4) · **7일간 outbox·campaign 이 100ms 를 넘긴 적이 있는가**(재발 감시)
- **route p95 기준선이 존재하는가** — 0-8 이 미확보라 이게 선행이다(로그 영속화). *없으면 이 항목 전체를 판정할 수 없다*
- p95 가 **W0-8 기준선 대비 개선**됐는가 (*300ms 목표 달성은 이 phase 단독으로 보장하지 않는다 — Phase 71 프론트 렌더 개선과 함께 판단*)
- 일일 점검 알림이 **소음 없이** 동작하는가
- **판정:** 재발이 관측되면 그때 4-2/4-3/4-3b 동결을 해제하고 `EXPLAIN` 부터 다시 한다.
  **재발이 없으면 W4 는 4-4·4-5·4-6 만으로 종료한다** — 없는 병을 고치지 않는다

### 3개월 후 — 확장 가능한 상태가 됐는가

- 크론 전용 리더가 **advisory lock 으로 보장**되는가
- 캐시가 Redis 공유값으로 전환됐는가
- **워커 4 → 6 에서 처리량이 실제로 늘어나는가** ← G3. 이게 안 늘면 2호기도 안 늘어난다
- 커넥션 예산이 `서버수 × 워커수 × pool.max ≤ 슬롯` 안에 드는가
- **판정:** 넷 다 YES 일 때만 `D-63-2` 를 다시 연다. 하나라도 NO 면 2호기는 돈과 시간을 쓰면서 시스템을 느리게 만든다

---

## 빠지기 쉬운 함정 3가지

1. **`pool.max` 를 늘려 해결하려는 유혹.** pgbouncer 슬롯 50 이 실질 상한이라 큐가 앱에서 DB 안으로
   이동할 뿐이고, DB 안의 대기는 락을 쥔 채 기다리므로 훨씬 비싸다. Little's Law 는 L 을 키우라는 게 아니라
   W 를 줄이라는 말이다. 코드 주석에 "증가 금지"가 여러 번 적혀 있지만 **압박이 오면 이 규칙이 가장 먼저 깨진다.**
2. **W6 을 건너뛰고 2호기부터 붙이는 것.** 지금 붙이면 크론 2배 + 캐시 미스 2배 + 커넥션 160 대 50 이
   동시에 일어난다. 처리량이 늘지 않고 **줄어들 가능성이 높다.** 그리고 이때 "역시 서버가 부족하다"는
   잘못된 결론에 도달해 3호기를 붙이는 악순환이 시작된다. USL 하강 구간을 용량 부족으로 오독하는 것이
   확장 실패의 전형적 경로다.
3. **"3000명"을 목표 지표로 삼는 것.** 사용자 수는 시스템이 느끼는 부하가 아니다. 실제 지표는
   피크 판매 커밋/s · 동시 소켓 수 · 단일 매장 hot-row 경합 셋이다. 3000명이 300개 매장에 흩어져 있으면
   현 구조로도 가고, 500명이 한 매장에 몰리면 지금도 터진다.

---

## 이 phase 가 하지 않는 것

**정본은 `75-SPEC.md` 「범위 밖 (명시적)」이다.** 요약하면:

**구조적 범위 밖 (7)** — API 2호기·nginx LB **실제 도입**(전제조건과 게이트만) · PG read replica/standby(Phase 74 및
2호기 결정과 한 묶음) · `store_id` 샤딩·파티셔닝(Tier 3) · hot-row 완화(Phase 66 조건 유지) · `pool.max` 증가 ·
Redis 영속화(pub/sub 전용 의도 유지) · Phase 65 W8-5 알람 2종.

**개별 판단으로 제외 (4)** — ≤200 화면 표시용 목록(Phase 73-15 승인 범위, W3) ·
`AllCajasOverview` `/resume` fan-out(의도적 설계, W0-12 실측 후 재판단, W3) ·
`DespachoBoard`/`DeliveryBoard`/`useRemoteSupport`/`soporte/visor` 소켓(상시 연결 아님, W2) ·
프론트 번들 최적화(W0-9 계측만, 결과에 따라 별도 phase).
