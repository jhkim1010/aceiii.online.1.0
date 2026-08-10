# Phase 75 W0 — 계측 기준선 실측

**측정일:** 2026-08-06 23:20~23:35 UTC (아르헨티나 20:20~20:35 — **야간·저부하 시간대**)
**측정자:** 조회성 쿼리만. 앱 pool 무영향(5434 직결 / pgbouncer stats 조회).

> **이 문서의 목적은 "W7 에서 나아졌는가"에 답할 수 있게 만드는 것이다.**
> 그러므로 값보다 **측정 조건**을 함께 남긴다. 야간 값과 영업시간 값을 섞으면 비교가 무의미해진다.

---

## 요약 — W0 게이트 판정

플랜의 게이트는 `0-1 · 0-2 · 0-3 · 0-8` 이다.

| 게이트 | 상태 | 값 |
|---|---|---|
| 0-1 pgbouncer 대기 | **✅ 확보** | `cl_waiting = 0` · 누적 `total_wait_time` 4.73s / 130,452 xact (평균 36µs) |
| 0-2 느린 쿼리 | **✅ 확보 (전제 반증)** | 상위는 전부 1회성 벤치/DDL. **애플리케이션 쿼리 최대 1.4ms** |
| 0-3 동시 소켓 | **⚠️ 야간값만** | 0 (실제 유휴). **영업시간 재측정 필요** |
| 0-8 route p95 | **❌ 확보 불가** | **기준선이 없고, 현 구조로는 축적되지도 않는다** (아래 참조) |

**판정: W1 관찰 기간과 병행해 0-8 을 먼저 해결한다.** 플랜이 명시한 대로
"0-8 이 없으면 W7 에서 비교가 불가능하다" — 지금 손대지 않으면 7일 뒤에도 기준선이 없다.

---

## ★ 가장 중요한 발견 — W4 의 전제가 현재 재현되지 않는다

플랜 W4 는 `sync_outbox` claim **3,015ms** · `campaign_recipients` **2,171ms** ·
`online_orders` **876ms** 를 전제로 세워져 있다. 출처는 `load-stress-review-2026-07-31.md:18`
→ 원본은 **`api-ventago/logs/combined-2026-07-29.log` 단일 일자 앱 로그**다.

5일치(`stats_reset` 2026-08-01 17:45 UTC) `pg_stat_statements` 실측:

| 쿼리 | calls | mean | **max** |
|---|---|---|---|
| `UPDATE sync_outbox o SET status=…` (claim) | 45,009 | 0.01ms | **1.1ms** |
| `UPDATE campaign_recipients SET status=…` | 15,005 | 0.02ms | **1.2ms** |
| `UPDATE sync_outbox SET locked_by=…` | 13,130 | 0.01ms | **1.4ms** |

**3,015ms → 1.1ms.** 2,700배 차이다. 그리고 이건 표본이 적어서가 아니다 — 45,009회다.

교차 확인 3건 모두 같은 방향:
- `slow_query_log` 테이블: **전체 기간 통틀어 2행**, 최대 225ms (2026-07-30 · 2026-08-05).
  → W4-3 의 "`slow_query_log` INSERT 2,069ms — 관측 기능이 스스로 느린 쿼리다" 는
  **현재 거의 아무것도 기록하지 않는 컴포넌트**에 대한 이야기다.
- 오늘(08-06) 앱 로그: 100ms 초과 쿼리 **0건**. (임계 100ms 로거는 정상 작동 중 —
  `database.module.ts:76-77` `benchmark:true`, dev 게이팅 없음.)
- pgbouncer 누적 대기 4.73초 / 130k 트랜잭션.

### 이것이 의미하는 것

07-29 의 3초는 **상시 속성이 아니라 그날의 사건**이었을 가능성이 높다(I/O 포화·락 폭주·
일시적 pool 고갈). 앱측 타이밍은 **커넥션 획득 대기를 포함**하므로, 큐잉이 있으면
쿼리 자체가 빨라도 3초로 찍힌다 — pgbouncer 쪽 누적 대기가 사실상 0 인 지금과 모순되지 않는다.

**그러므로 W4 를 "인덱스·배치 크기를 고치는 wave"로 실행하면 없는 병을 고치게 된다.**
플랜이 스스로 경고한 함정("추측 최적화는 반드시 엉뚱한 곳을 고친다")에 W4 자신이 걸려 있다.

**재조준 필요:** W4-1 의 `EXPLAIN` 대상은 유지하되, 목적을 "느린 쿼리 원인 규명"에서
**"07-29 같은 사건이 다시 나는지 상시 관측"**으로 바꾼다 — 그게 W1 일일 점검과
0-8 기준선의 역할이다. 4-3(batch 상한)·4-3b(인덱스 3개 재평가)는 **근거가 사라졌으므로
착수 전 재검증**한다. 반면 4-4(워커별 flush)는 **근거가 강화됐다** — `slow_query_log` 2행이
전부 `instance=0` 이라 "워커 1~3 의 버퍼는 영구 유실"이 실측으로 확인된다.

---

## ★ 0-8 이 불가능한 이유 — 로그가 컨테이너와 함께 사라진다

route timing / Web Vitals 계측은 **살아 있다**:
`_app.tsx:233 useRouteTimingLogger()` · `:349 reportWebVitals()` → `/api/web-vitals`
→ `perf-logger.ts` → `logs/perf-YYYY-MM-DD.log` → `scripts/aggregate-perf.js` 로 P95 집계.

문제는 저장 위치다. `ventago-app/docker-compose.yml` 에 **volume 이 없다**(ports·networks 뿐).
`api-ventago` 도 마운트는 `manuales`·`certificates` 둘뿐이다.

→ **배포할 때마다 `/app/logs` 가 통째로 사라진다.** 오늘만 front 배포 2회(#544·#545),
측정 시각의 `ventagoapp` uptime 은 1분이었다. `perf-*.log` 는 존재조차 하지 않았다.

같은 이유로 **W4 전제의 원본인 `combined-2026-07-29.log` 도 이미 없다** — 그래서 그날이
어떤 사건이었는지 사후 규명이 불가능하다. 근거가 휘발되는 구조 자체가 결함이다.

**조치 (2026-08-06 승인 후 실행 — 둘 다 했다):**

1. **호스트 volume 마운트** — `ventago-app` `f638bc8` · `api-ventago` `37f8868`.
   `/var/lib/ventago-logs/{app,api}` → `/app/logs`. 배포·재생성과 무관하게 원본이 남는다.
   `docker-compose.yml` 에 커밋했으므로 **다음 배포가 덮어쓰지 않는다** (서버에서 손으로 고치면 덮인다).
2. **집계값을 `daily.jsonl` 로** — `ops-daily-check.py collect_route_perf()`.
   전일 `perf-YYYY-MM-DD.log` 에서 route p50/p95 + 느린 라우트 상위 5를 뽑아 매일 04:10 에 누적.
   Dropbox 오프사이트 사본까지 자동으로 따라간다.

두 개를 함께 해야 한다 — volume 만 두면 서버가 죽을 때 같이 사라지고,
집계만 두면 배포와 배포 사이의 원본이 사라진다.

**임계 알림은 일부러 넣지 않았다.** 기준선이 없는 상태에서 임계를 정하면 그 숫자가 곧 소음이 된다.
W1-12(정상 7일 알림 0건) 판정을 오염시키지 않도록, **7일간은 수집만 하고 그 분포를 보고 임계를 정한다.**

---

## 실측값 (야간 기준선)

### 0-1 pgbouncer

```
ventago | coolsistema     | cl_active 5 | cl_waiting 0 | sv_idle 2
ventago | shop_readonly   | cl_active 0 | cl_waiting 0 | sv_used 2
ventago | ventago_watcher | cl_active 1 | cl_waiting 0 | sv_idle 1
SHOW STATS: total_xact 130,452 · total_query 160,702 · total_wait_time 4,732,108µs
```

**G1(`cl_waiting` 피크 지속 0)은 현 부하에서 이미 충족.** 다만 "피크"는 영업시간 값이라야 한다 —
W1 일일 점검이 매일 04:10 에 이 값을 JSONL 에 남기므로 7일 뒤 추세로 판정한다.

### 0-4 / 0-11 인스턴스·워커 — G5 예산의 실제 숫자

- 컨테이너 **1** (`api_ventago`) × PM2 cluster 워커 **4** (pid 18·25·32·43, 각 RSS ~230MB)
- 워커 수는 **두 곳에 하드코딩** — `ecosystem.config.js:18 instances:4` 와 `:32 WEB_CONCURRENCY:4`.
  주석이 *"instances 값을 바꾸면 이 값도 함께 갱신할 것"* 이라고 **수동 동기화를 지시**한다.
  → W6-8(단일 출처 통합)의 전제가 실측으로 확인됨. G3(4→6 실험)을 이 상태로 하면 예산 로그가 틀린다.

### 0-10 pgbouncer pool_size — 추정 아님, 실측 고정

`/etc/pgbouncer/pgbouncer.ini:118` → `ventago = host=127.0.0.1 port=5434 dbname=ventago pool_size=50`
전역: `pool_mode=transaction` · `max_client_conn=1000` · `default_pool_size=20` · `reserve_pool_size=10`

**주의 — G5 문구 재검토 필요.** pgbouncer 의 `pool_size` 는 **(db,user) 쌍마다** 적용된다.
`ventago` DB 에는 `coolsistema` / `shop_readonly` / `ventago_watcher` 3개 유저 풀이 붙어 있으므로
"슬롯 50"은 앱(coolsistema) 기준이다. 한편 앱측 상한은 **`1 × 4워커 × (메인 20 + 공개몰 5) = 100`**.
**100 > 50 은 위반이 아니라 설계다** — pgbouncer 가 다중화 지점이고 `max_client_conn=1000` 안에 든다.

> **정정 (2026-08-07):** 이 문단은 처음에 `4 × 20 = 80` 으로 적었다가 배포 후 부팅 로그를 보고 고쳤다.
> `커넥션 예산: 워커 4 × (메인 20 + 공개몰 5) = 100 클라이언트` — **공개몰 pool 5 가 워커마다 별도로 붙는다.**
> 코드가 이미 합산해서 찍고 있었는데 내가 메인 pool 만 세었다. 예산 산식을 손으로 다시 계산하지 말고
> **부팅 로그를 근거로 쓴다.**
>
> 같은 로그에 `공개몰 격리=no` 도 찍힌다 — W6-3(`SHOP_DB_ISOLATED` 명시 플래그)의 현재 상태다.
G5 를 글자 그대로 적용하면 정상 구성을 결함으로 오판한다. **W7 에서 문구를 정정할 것.**

### 0-5 디스크·DB

`/dev/sda1 387G · 사용 131G · 34%` — DB `ventago` **45MB**.
상위 테이블: `role_function_actions` 8.9MB · `role_functions` 3.1MB ·
`role_function_actions_bak_20260728` 2.3MB(백업 잔재) · `global_clients` 1.1MB · `daily_quotes` 1.0MB
dead tuple 171. **DB 는 디스크 압박의 원인이 아니다** — 131GB 는 다른 곳(Docker 이미지·로그)에서 온다.

### 0-12 열린 caja 분포 — `AllCajasOverview` fan-out 제외 근거 확인

| store_id | cajas | branches |
|---|---|---|
| 6 | 3 | 2 |
| 3 · 9 · 15 | 2 | 2 |
| 그 외 | 1 | 1 |

**최대 3개.** 코드 주석의 *"보통 1~5개 → Promise.all 병렬"* 이 실측과 일치하므로
W3 의 "`/resume` fan-out 범위 제외" 판단을 **유지**한다(플랜 W3 각주의 재판단 조건 해소).

### 0-3 동시 소켓 — 야간 0

`ss -tn state established '( sport = :5002 )'` = **0**. 호스트에 `LISTEN 0.0.0.0:5002` 가 있으므로
집계 경로는 정상이고, 값 0 은 실제 유휴다(전체 established 48건, 443 포트도 0).
**영업시간 재측정 필수** — W2 의 "1/3 이하" 게이트가 이 값과 대비된다.

### 0-9 프론트 번들 — 계측만 (조치는 이 phase 범위 밖)

`ANALYZE=true next build` 1회 (2026-08-06, 로컬). 페이지 **127개**.

| 지표 | 값 |
|---|---|
| **First Load JS shared by all** | **471 kB (gzip)** |
| ↳ `chunks/pages/_app` | **385 kB (gzip) / 1,301 kB (parsed)** — 공유분의 **82%** |
| ↳ framework · main · webpack · css | 45.3 · 33 · 5.65 · 1.69 kB |
| 페이지별 추가분 | **0.26 ~ 5.54 kB** (POS `/nueva-venta` 5.54 kB) |
| 페이지 총합 최대 | `/login` 479 kB · `/configuracion` 477 kB |

**해석: 코드 스플리팅은 이미 잘 되어 있다.** 페이지별 추가분이 최대 5.5 kB 라는 건
`next/dynamic` 규약이 지켜지고 있다는 뜻이다. **비용은 전부 `_app` 공유 청크 한 곳에 있고,
127개 모든 라우트가 이 385 kB 를 매번 지불한다.** 즉 페이지 단위 최적화는 의미가 없다.

`_app` 청크 구성 (parsed, 상위):

| 모듈 | parsed |
|---|---|
| `@mui/material` (+`@mui/system` 22.7) | **227.5 kB** |
| **`posthog-js`** | **112.5 kB** |
| `luxon` | **79.0 kB** |
| `src/iconify-bundle/icons-bundle-react.js` | **44.8 kB** (앱 소스 중 최대) |
| `socket.io-client` | 44.0 kB |
| `axios` 32.1 · `react-hook-form` 31.9 · `yup` 31.3 | |
| **`react-toastify` 30.8 + `react-hot-toast` 11.6** | **토스트 라이브러리가 2개 들어 있다** |
| `@reduxjs/toolkit` 23.1 · `buffer` 23.0 · `@popperjs/core` 22.8 · `@iconify/react` 21.4 · `perfect-scrollbar` 20.5 | |

앱 소스는 `_app.tsx + 127 modules (concatenated)` 로 총 **316 kB / 138 파일**.

**눈에 띄는 것 3가지 (판단은 별도 phase — 여기서는 기록만):**
1. `posthog-js` **112.5 kB** 가 `_app.tsx:16-18` 에서 **최상위 정적 import** 다. 분석 도구가
   첫 진입 비용의 1/4 를 차지한다. `next/dynamic` 지연 로드 후보.
2. **토스트 라이브러리 2종 공존** — `react-toastify`(30.8) + `react-hot-toast`(11.6). 하나면 된다.
3. `luxon` **79 kB** 가 공유 청크에. 사용 범위 확인 필요.

**주의:** 이 셋은 사용자 수에 **선형 비례**하는 비용이라 W2~W5 의 서버측 절감과 성격이 다르다.
플랜 0-9 가 "계측만, 조치는 범위 밖"이라고 못 박았으므로 **여기서 손대지 않는다.**
결과에 따라 별도 phase 로 올린다.

---

## 미완 항목

| # | 항목 | 왜 아직 안 됐나 | 필요한 것 |
|---|---|---|---|
| 0-3 | 동시 소켓 피크 | 야간 측정 | 영업시간 재실행 (W1 일일 점검이 매일 자동 수집) |
| 0-6 | POS 진입 요청 수·전송량 | 브라우저 DevTools + 로그인 필요 | 사용자 협조 1회 |
| 0-7 | POS 탭당 WS 수 | 동일 | 사용자 협조 1회 (W2 의 비교 기준) |
| 0-8 | **route p95** | **✅ 확보 (2026-08-10)** — 아래 | — |
| 0-9 | 프론트 번들 | **✅ 완료** (위) | — |

### 0-8 route p95 — 첫 기준선 (2026-08-10 확보)

| 날짜 | n | p50 | **p95** |
|---|---|---|---|
| 2026-08-07 | 60 | 74ms | **342ms** |
| 2026-08-08 | 27 | 139ms | **664ms** |
| 2026-08-09 | 1 | 40ms | 40ms (표본 1 — 무의미) |

**p95 가 300ms 규약을 넘는다.** 다만 표본이 하루 27~60건으로 작다 — `useRouteTimingLogger` 는
**SPA 내 라우트 전환**에서만 발화하므로 최초 진입·새로고침은 잡히지 않는다. 절대값보다
**같은 계측 방식끼리의 추세 비교**에 쓰는 것이 맞다.

> **★ 사흘을 놓칠 뻔한 이유 — 읽는 쪽이 못 봤다.**
> winston 이 `zippedArchive: true` 로 회전해 **어제 파일은 보통 `.log.gz`** 인데
> 수집기가 `.log` 만 보고 있었다. 그래서 08-07~09 세 행이 전부 `n=0` 이었고,
> 로그만 보면 **"계측이 안 된다"로 오진하기 딱 좋았다** — 실제로 나도 한 번 그렇게 판단했다.
> 원자료는 멀쩡히 남아 있어 `.gz` 를 읽도록 고친 뒤 2행을 복구했다(`backfilled: true` 표시).
> **"수집 0건"은 "발생 0건"이 아니다.**

> **0-8 은 "완료"가 아니라 "이제야 시작"이다.** 오늘 이전 데이터는 존재하지 않으므로
> W7 비교 기준은 **2026-08-07 이후 축적분**이 된다. 이보다 앞선 시점과의 비교는 불가능하다 —
> 그 사실을 알고 있는 것 자체가 W7 판정의 전제다.
| 0-9 | 프론트 번들 바이트 | 미실행 | 로컬 `@next/bundle-analyzer` 1회 (계측만) |
