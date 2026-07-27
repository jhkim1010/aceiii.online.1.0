# SPEC: Phase 63 — Scale-Out & Resilience (3,000 터미널 대비)

생성일: 2026-07-26
상태: PLAN (사용자 승인 대기)
우선순위: ★사활 (시스템 생존 기능)

## 목표

300매장 × 10터미널 = 3,000 POS 터미널(총 연결 4,000~5,000, 피크 600~900 req/s)에서
P95 ≤ 300ms·pool waiting 0·단일 장애점 없이 운영 가능한 상태로 만든다.
"한 가지가 모든 것을 하다 기절하는" 구조를 측정 → 성능 → 확장 → 격리 → 리허설
5단계 Wave 로 점진 보완하며, 매 Wave 후에도 시스템은 정상 서비스를 유지한다.

## 배경 및 컨텍스트 (2026-07-26 실측)

| 항목 | 현재값 | 비고 |
|---|---|---|
| 서버 | srv803182 단일 (8코어/31GB) | API+PG+pgbouncer+MinIO+Jenkins+Mongo 전부 동거 = SPOF |
| API | pm2 cluster instances=4, ws-only, Redis adapter(ventago_redis), 리더가드 | 2026-07-25 전환 완료 |
| 앱 pool | 워커당 max=20 (4×20=80 클라이언트) | database.module.ts |
| pgbouncer | transaction mode, ventago pool_size=50, reserve 10, max_client_conn 1000 | 실질 병목 지점 |
| PG18 | max_connections=200, shared_buffers=2GB(과소), work_mem=16MB | 5434, 호스트 설치 |
| 캐시 | MemoryCacheService (워커별 중복, 공유 안 됨) | Redis 인프라는 이미 존재 |
| 관측 | slow query 로그(100ms+) + pool 모니터 로그만. 대시보드/알람 없음 | Prometheus 제안만 존재 |
| 부하테스트 | **한 번도 없음** | 500명 목표 미검증 |
| 오프라인 생존 | Phase 58 edge agent (지점 PC 설치는 일부만) | 서버 다운 시 판매 지속 수단 |

핵심 원리 (Little's Law): 필요 DB 동시성 = 처리율 × 쿼리 점유시간.
900 req/s × 30ms = 27 커넥션 (pool_size 50 여유) / × 100ms = 90 커넥션 (붕괴).
→ **pool 숫자가 아니라 쿼리 지연시간이 성패를 결정한다.**

## 기술 스택

- 백엔드: NestJS 11 + Sequelize (api-ventago)
- DB: PostgreSQL 18 (5434) + pgbouncer transaction mode (5432)
- 인프라: pm2 cluster / Docker / nginx / Redis (ventago_redis)
- 부하: k6 (신규 도입, `loadtest/` 디렉터리)
- 관측: Prometheus + Grafana + Loki (self-hosted, 기존 제안 채택)
- ESLint: api-ventago/.eslintrc (Warning=에러, newline-before-return 등)

---

## Wave A — 측정: 지금 어디까지 버티는지 처음으로 잰다 (선행 필수)

> 측정 없이는 아래 모든 Wave 가 추측이다. A 완료 전 B~D 착수 금지.

- [x] A-1: k6 POS 시나리오 스크립트 — 파일: `loadtest/pos-scenario.js` ✅ 2026-07-26
      실측 API 경로 반영: login(fingerprint)→me/products/payment-methods/clients 부팅→
      POST /sales 반복(1~4아이템, efectivo)+10% hold+5% daily-stats.
      PRESET 4종(smoke/baseline/stress/full). active_sessions UNIQUE 제약 → VU별 유저.
- [x] A-1b: 시드 + 안전가드 — `loadtest/seed-staging.sql` (lt_vu_N 유저 + IP/디바이스
      사전등록, ventago_staging DB명 가드), `loadtest/watchdog.sh` (주간 테스트 시
      load/메모리/운영 cl_waiting 임계 초과하면 k6 자동 중단) ✅ 2026-07-26
- [x] A-1c: 스테이징 환경 구축 ✅ 2026-07-26 (에이전트가 서버에서 직접 실행)
      · `ventago_staging` = 운영 pg_dump 복원본 (PG18:5434, owner coolsistema)
      · **전용 pgbouncer**(6432, `/var/lib/postgresql/pgbouncer-staging.ini`) — 운영
        pgbouncer(5432)는 ventago 외 ~125개 DB 를 함께 서비스하며 단일 스레드라
        부하를 태우면 전 시스템 영향 → 프로세스 분리 필수였음
      · `api_staging`(5012) — 운영 이미지 재사용. ★`API_PORT` 로 포트 지정(pm2
        ecosystem env.PORT=5002 가 컨테이너 PORT 를 덮어씀), ★`CRON_ENABLED=false`
        (캠페인/outbox cron 이 실고객에게 나가는 것 차단 — 18개 해제 확인),
        ★REDIS_HOST 제거(운영 print-agent 소켓 채널과 격리)
      · 파일: `loadtest/{docker-compose.staging.yml,pgbouncer-staging.ini}`
        서버 경로 `/home/jhkim/phase63-staging/`
- [x] A-1d: 다매장 동시 판매 버스트 시나리오 ✅ 2026-07-26
      `loadtest/burst-multistore.js` (constant-arrival-rate — 초당 판매 건수 고정),
      `loadtest/seed-burst-multistore.sql` (매장별 유저/디바이스, 소프트삭제·비활성
      매장 자동 제외), `loadtest/verify-burst.sql` (저장 건수·dn 중복·항목/결제 누락·
      금액 정합성·초당 분포 6종 검증)
- [x] A-2: 부하 baseline 1차 ✅ 2026-07-26 — `loadtest/README.md` 결과표 참조
      smoke 10VU P95 92ms / burst 3매장 10건per s P95 35ms / 1매장 20건per s P95 37ms,
      HTTP 에러 0%. **성능은 목표 대비 여유** — 병목은 정합성(F-1) 이었다.
- [~] A-2b: 고부하 baseline — **저강도분만 완료 (2026-07-27 주간)**, 붕괴점 탐색은 심야 대기
      · daylight 프리셋(100→200 VU) 실행: P50 38.8ms / P95 74.9ms / 판매 P95 57.7ms,
        체크 2,477건 100%, login_fail 0%, 서버 4xx·5xx 0 (초기 5.35% 실패는 F-8 스크립트 결함)
      · 서버 load average 0.5~0.7 — 운영 영향 없음. watchdog 미발동
      · 남은 것: 500/1000/2000 VU 램프업(PRESET=stress) — 00~06 ART 전용
- [x] A-2b ✅ 2026-07-27 **붕괴점 측정 완료** (운영 유휴 확인 후 주간 실행, 사용자 승인)
      · 500→1000→1500→2000 VU 22분. 붕괴점 = **약 950 판매/분(16건per s)**, 이후 처리량 1/4 로 꺾임
      · 원인 = **상품 재고 행 락 경합**(Lock/transactionid 35 + tuple 25) → pgbouncer 슬롯 포화 →
        SequelizeConnectionAcquireTimeoutError → 판매 500 연쇄. CPU 아님(붕괴 시 load 0.89/8코어)
      · 로그인은 2000 VU 부팅까지 login_fail 0% — F-4 캐시·인덱스 개선 유효
      · 부하 제거 후 60초 내 완전 회복, 운영 무영향(prod 커넥션 1/4, watchdog 미발동)
      · ★단일 매장 상한임(시드가 1개 매장 3,000 유저). 300매장 분산 용량은 Wave E 에서 별도 측정
      · 상세: `loadtest/README.md` F-10 / F-11
- [ ] A-2b(원문) 고부하 baseline (심야) — 500/1000/2000 VU 램프업으로 첫 붕괴점 탐색
      100 → 500 → 1,000 → 2,000 VU 램프업. 각 단계 P50/P95/에러율/pool waiting/
      pgbouncer cl_waiting 기록. 첫 붕괴 지점(req/s)과 병목 원인 식별.
- [ ] A-3: pg_stat_statements Top-20 추출 — 파일: `loadtest/slow-top20.md`
      부하 중 total_exec_time 상위 20개 + 누락 FK 인덱스 목록 (sale_items/prices 기존
      확인분 포함). Wave B 의 입력이 된다.
- [ ] A-4: 관측 스택 구축 — 파일: `docker-compose.observability.yml` (신규, 서버)
      Prometheus + Grafana + Loki + postgres_exporter + pgbouncer_exporter.
      대시보드 4종: API P95 / pool·pgbouncer 슬롯 / PG (커넥션·락·cache hit) / Node RSS·CPU.
- [ ] A-5: 알람 2종 — Grafana alert: ① pool waiting > 0 (5분), ② P95 > 300ms (10분)
      → Telegram (기존 store.telegramChatId 봇 재사용).

## Wave B — DB 성능 + 동시성 정합성

> ★ Wave A 실측(2026-07-26) 결과 우선순위 변경: 응답 지연은 이미 목표 대비 여유
> (P95 35ms @ 20 sales/s). 진짜 위험은 성능이 아니라 **동시성 정합성**이었다.
> B-0 을 최우선으로 올린다.

- [x] B-0 ★치명 ✅ 2026-07-26 코드+마이그레이션, **2026-07-27 운영 배포·적용 완료**
      (운영 5434 `uq_sales_store_day_daily_number` + advisory lock dist 확인 / 로컬 5432 동일)
      · 코드: `reserveDailyNumber()` 신설 — 판매 INSERT 와 같은 트랜잭션 내
        `pg_advisory_xact_lock(storeId, YYYYMMDD)`. 무효화 경로도 트랜잭션화.
      · 마이그레이션: `migrations/2026-07-26-phase63-daily-number-unique.sql`
        (중복 재배정 → UNIQUE 부분 인덱스). **로컬 5432 + 운영 5434 동시 적용 필요**
      · 검증: 1매장 20건/s 중복 13→**0**, 3매장 30건/s 2,701건 **0**, P95 변화 없음
      · ★배포 순서: 코드 배포 → 중복 정리 → 인덱스 생성 (역순이면 판매 거부 발생)
- [ ] B-0(원문 참고) `daily_number` 채번 경합 — 파일: `api-ventago/src/app/sales/sales-create.service.ts`
      실측: 1매장 20건/s 에서 1,197건 중 13건 중복(1.1%), 한 번호 6회 발급.
      원인: 264-278행 read-then-write(락 없음) + 트랜잭션(367행) 밖 + UNIQUE 제약 없음.
      무효화 경로(599-613행)도 동일 결함.
      수정: ① 트랜잭션 내 `pg_advisory_xact_lock(hashtext('sale_dn:'||storeId||':'||날짜))`
            ② `(store_id, sale_date::date, daily_number) WHERE activity_type='sale'`
               UNIQUE 부분 인덱스 (기존 중복 정리 선행 + 충돌 재시도)
      검증: `loadtest/burst-multistore.js` + `verify-burst.sql` 재실행 → 중복 0
- [ ] B-0c ★[F-10] 판매 처리량 상한 = 상품 재고 행 락 경합 (A-2b 붕괴 원인, 단일 매장 16건per s)
      · 재고 차감을 트랜잭션 후반으로 + 상품 id 정렬로 락 획득 순서 고정
      · lock_timeout / statement_timeout 을 짧게 → 빠른 실패·재시도로 pool 보호
      · pool 획득 실패는 500 이 아니라 503 + Retry-After
      · (구조) 재고를 행 UPDATE 대신 이동 원장(append-only) + 집계로 전환 검토
      · 검증: burst-multistore 를 STORES=1 로 돌려 단일 매장 상한이 얼마나 올라가는지 측정
- [ ] B-0d [F-14 후속] 채번 UNIQUE 인덱스를 타임존 독립 구조로 교체
      현재는 인덱스가 'America/Argentina/Buenos_Aires' 하드코딩 + 앱은 stores.timezone 사용.
      2026-07-27 데이터 교정(전 매장 Buenos_Aires)으로 즉시 위험은 제거했으나, 타임존이
      다른 매장이 생기면 재발한다.
      · `sales.sale_day_local` (date, 앱이 매장 tz 로 계산해 INSERT 시 저장) 추가
      · UNIQUE (store_id, sale_day_local, daily_number) WHERE activity_type='sale' 로 교체
      · 기존 인덱스 제거는 신규 컬럼 backfill 완료 후
- [ ] B-0b [중]: 로그인 throttle IP 기준 완화 — 파일: `api-ventago/src/common/throttle/`
      IP당 15회/분 → NAT 뒤 10터미널 매장 개점 시 일부 터미널 60초 차단.
      키를 (IP + deviceFingerprint) 또는 등록 지점 IP 예외로 검토.

### Wave B 기존 태스크 (DB 성능)

- [ ] B-1: Top-20 slow query 인덱스 마이그레이션 — 파일: `api-ventago/migrations/2026-07-XX-phase63-indexes.sql`
      A-3 결과 기반. `CREATE INDEX CONCURRENTLY` (운영 무중단), 로컬 5432 + 운영 5434
      동시 적용, owner coolsistema DO 블록 포함. ★운영 DDL = 사용자 승인 게이트.
- [ ] B-2: N+1/과다 조회 상위 5개 리팩터링 — 파일: A-3 에서 식별된 service 파일들
      include 폭발·루프 내 쿼리 → 배치 쿼리 전환 (revenue-summary 배치 5쿼리 전례 패턴).
- [ ] B-3: PG18 튜닝 — shared_buffers 2GB→8GB, effective_cache_size 20GB,
      random_page_cost 1.1 (SSD). ★PG 재시작 필요 = 사용자 승인 + 심야 적용.
- [ ] B-4: MemoryCacheService → Redis 공유 캐시 승격 — 파일: `api-ventago/src/app/cache/`
      참조데이터(60s)·대시보드(30s) 캐시를 ventago_redis 로. 워커 4개 중복 조회 제거.
      인터페이스 유지(내부 구현만 교체) → 호출부 무변경. Redis 다운 시 in-memory fallback
      (에러 핸들링 필수 — 캐시 장애가 API 장애가 되면 안 됨).
- [ ] B-5: 재부하 테스트 — A-2 동일 시나리오 재실행, 개선폭 정량 기록.

## Wave C — 앱 확장: 기절해도 되는 인스턴스 여러 개

- [ ] C-1: cron/부팅 1회성 작업 리더 가드 전수 감사 — 파일: `@nestjs/schedule` 사용 모듈 전체
      NODE_APP_INSTANCE=0 가드가 **다중 컨테이너**에서도 안전한지 (인스턴스별 instance 0
      존재 → Redis 분산락 `SET NX PX` 로 교체). sync_outbox tick·Telegram 알림 중복 방지.
- [ ] C-2: 두 번째 API 컨테이너 — 파일: `api-ventago/docker-compose.yml`
      api_ventago_2 (포트 5003, 워커 2~4). pool 산식: (4+4)워커 × 20 = 160 클라이언트
      < max_client_conn 1000, 서버슬롯은 pool_size 50 캡 유지 → PG 200 한도 내 안전.
- [ ] C-3: nginx upstream LB — 파일: 서버 nginx conf
      least_conn + `/socket.io/` Upgrade 헤더 유지. ws-only 라 sticky 불필요(기확인),
      Redis adapter 가 인스턴스 간 emit 중계(기설치) → 검증만 필요.
- [ ] C-4: 크로스 인스턴스 print 검증 — 인스턴스1 판매 → 인스턴스2 접속 agent 출력 100% 도달.
- [ ] C-5: graceful shutdown 점검 — SIGTERM 시 in-flight 요청 완료 + pool 안전 종료
      (onModuleDestroy 기존 로직 검증) → 무중단 배포 기반.

## Wave D — 격리: "한 가지가 모든 것을" 해체

- [ ] D-1: 무거운 백그라운드 분리 — 파일: `api-ventago/src/workers/` (신규 pm2 app)
      캠페인 발송·sync_outbox·보고서 집계를 별도 pm2 프로세스(HTTP 미수신)로.
      POS 경로와 CPU/pool 분리 (worker 전용 pool max 5).
- [ ] D-2: 보고서/대시보드 read 경로 분리 준비 — 파일: `api-ventago/src/database/`
      Sequelize read replica 설정 골격 (replica 미도입 시 primary 폴백, 코드만 선행).
- [ ] D-3: 서버 2호기 계획서 — 파일: `docs/phase63-second-server-plan.md`
      API 컨테이너를 2호기로, PG+pgbouncer 는 1호기 전용화. WAL 아카이브 + 스탠바이
      (또는 관리형 PG) 옵션 비교, 비용 포함. ★구매 결정 = 사용자.
- [ ] D-4: edge agent 배포 확대 체크리스트 — 파일: `docs/phase63-edge-rollout.md`
      서버가 죽어도 매장이 판매를 계속하는 최후 방어선. 미설치 지점 목록 + 설치 우선순위.
- [ ] D-5: nginx rate-limit + 서킷브레이커 — 로그인/보고서 등 폭주 취약 엔드포인트
      limit_req. 한 매장의 폭주가 전체를 기절시키지 않게.

## Wave E — 리허설: 3,000 터미널 + 장애 주입

- [ ] E-1: 풀 시뮬레이션 — k6 3,000 VU (에이전트 ws 연결 700 포함). 합격선:
      P95 ≤ 300ms, 에러율 < 0.1%, pool waiting 0, pgbouncer cl_waiting < 5.
- [ ] E-2: 장애 주입 — ① 워커 1개 kill ② 인스턴스 1개 중단 ③ Redis 중단 ④ PG 재시작.
      각각에서 판매 경로 생존/복구 시간 기록. edge 오프라인 전환 확인(④).
- [ ] E-3: 결과 리포트 + 300매장 온보딩 Go/No-Go — 파일: `docs/phase63-capacity-report.md`
- [ ] E-4: ESLint 전체 검증 (`npx eslint . `) 0개 + PostgreSQL pool 체크리스트 재확인.

---

## 완료 기준

- 3,000 VU 시뮬레이션에서 P95 ≤ 300ms, 에러율 < 0.1%, pool waiting = 0
- 장애 주입 4종에서 판매 경로 생존 (④는 edge 오프라인 전환으로 생존)
- Grafana 대시보드 + Telegram 알람 2종 상시 가동
- 모든 운영 쿼리 P95 < 100ms (pg_stat_statements 기준)
- ESLint 오류 0, 신규 코드 전부 에러 핸들링 + 캐시/Redis 장애 시 fallback

## 확정된 결정 (2026-07-26)

- **D-63-1 ✅**: 부하 테스트는 **운영 서버 안에서** 실행. 고객 온보딩 초기라 다운 리스크 수용.
  단, 운영 DB 직접 타격 금지 — 백업 복원 `ventago_staging` + `api_staging`(5012) 대상.
  심야(00~06 ART) 집중 + 주간은 PRESET=smoke + watchdog.sh 가드 하에서만.
  구현: `loadtest/` (pos-scenario.js / seed-staging.sql / watchdog.sh / README.md)
- **D-63-2 ✅**: 서버 2호기는 **보류**. 운영 서버 내 테스트가 힘들어지는 시점에 재논의.
  → Wave D-3 (2호기 계획서)는 문서만 선행, 구매 결정은 게이트로 유지.
- **D-63-3**: Redis 캐시 승격 범위 — 참조데이터+대시보드만(권장안으로 진행, 이견 시 조정)

## 금지사항 / 주의사항

- 운영 DDL·PG 재시작·서비스 재시작 = 반드시 사용자 승인 게이트 (CLAUDE.md 규칙)
- 마이그레이션은 로컬 5432 + 운영 5434 **동시 적용** (한쪽만 금지)
- pool max 상향 금지 — waiting 발생 시 원인 쿼리부터 (본 SPEC 의 존재 이유)
- `@socket.io/cluster-adapter` 단독 사용 금지 (PM2 primary 제약 — 기존 spec 교훈)
- 부하 테스트로 운영 데이터 오염 금지 (전용 테스트 store/브랜치)
- device VM 에서 jest/부하도구 실행 금지 (OOM) — 서버 또는 러너 잡 사용
- 각 Wave 종료 시 최신 로그 확인 후 다음 Wave 진행 (신규 에러 0 확인)

## Wave 순서 및 게이트

A (측정) → B (DB) → C (확장) → D (격리) → E (리허설)
각 Wave 는 독립 배포 가능하며 완료 후에도 서비스 정상 유지가 게이트 조건.
A-2 baseline 결과에 따라 B~D 태스크 우선순위 재조정 가능 (측정이 계획을 이긴다).
