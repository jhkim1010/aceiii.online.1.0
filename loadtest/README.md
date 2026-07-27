# Phase 63 — 부하 테스트 (운영 서버 내 스테이징 방식)

D-63-1 확정 (2026-07-26): 운영 서버(srv803182) 안에서 실행한다.
심야 집중 + 주간은 watchdog 가드 하에 저강도(smoke)만. 운영 DB(`ventago`)는 절대 직접 타격하지 않고,
백업 복원본 `ventago_staging` + 별도 API 컨테이너(`api_staging`, 포트 5012)를 대상으로 한다.

## 0. 구성도

```
k6 (서버 내) ──► api_staging:5012 (pm2 4워커, 운영과 동일 이미지)
                    │ pgbouncer 경유 없이 직결 or 별도 pgbouncer 항목
                    ▼
               ventago_staging (PG18:5434, 운영 백업 복원본)
```

- 운영과 같은 PG 인스턴스(5434)를 공유하므로 **PG 자원 경합은 존재** — 이것이 이 방식의
  한계이자, 사용자가 수용한 트레이드오프 (심야 집중으로 완화).
- pgbouncer.ini 에 `ventago_staging = host=127.0.0.1 port=5434 dbname=ventago_staging pool_size=50`
  항목 추가 → 운영과 같은 pooling 조건 재현.

## 1. 스테이징 DB 준비 (1회, 심야 권장)

```bash
# 최신 백업 복원 (백업은 매일 03:17 cron)
sudo -u postgres createdb -p 5434 ventago_staging
sudo -u postgres pg_restore -p 5434 -d ventago_staging -j 4 <최신백업파일>
# 또는 plain sql 백업이면: psql -p 5434 -d ventago_staging -f <백업.sql>

# owner 정리 (운영과 동일 규칙)
sudo -u postgres psql -p 5434 -d ventago_staging -c \
  "REASSIGN OWNED BY postgres TO coolsistema;" || true
```

## 2. 시드 (테스트 유저 3,000 + IP/디바이스 사전등록)

```bash
# 템플릿 유저 비번을 loadtest123 으로 (스테이징에서만!)
# bcrypt 해시 생성: node -e "console.log(require('bcrypt').hashSync('loadtest123',10))"
sudo -u postgres psql -p 5434 -d ventago_staging -c \
  "UPDATE users SET password='<위 해시>' WHERE id=<템플릿유저ID>;"

sudo -u postgres psql -p 5434 -d ventago_staging \
  -v template_user_id=<템플릿유저ID> -v n_users=3000 -v test_ip='127.0.0.1' \
  -v ON_ERROR_STOP=1 -f seed-staging.sql
```

시드 스크립트에는 `current_database() = 'ventago_staging'` 가드가 있어 운영 DB 에서
실수로 실행하면 즉시 중단된다.

## 3. api_staging 컨테이너

```bash
# 운영과 동일 이미지, env 만 스테이징 DB 로 (포트 5012)
docker run -d --name api_staging --network host \
  -e NODE_ENV=production -e PORT=5012 \
  -e DB_HOST=127.0.0.1 -e DB_PORT=5432 -e DB_NAME=ventago_staging \
  -e DB_USER=coolsistema -e DB_PASS=<pw> \
  <api_ventago 이미지>
# 로그인 throttle 이 빡빡하면 스테이징 한정 env 로 완화 검토
```

## 4. 실행

```bash
# k6 설치 (1회)
sudo gpg -k && sudo apt-get install -y k6 || \
  (curl -sL https://dl.k6.io/key.gpg | sudo apt-key add - && \
   echo "deb https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list && \
   sudo apt-get update && sudo apt-get install -y k6)

# 주간(저강도, 가드 필수):
./watchdog.sh &
k6 run -e BASE_URL=http://127.0.0.1:5012/api -e PRESET=smoke pos-scenario.js
kill %1

# 심야(본 측정):
./watchdog.sh &
k6 run -e BASE_URL=http://127.0.0.1:5012/api -e PRESET=baseline pos-scenario.js \
  --summary-export=results/baseline-$(date +%Y%m%d).json
kill %1

# 한계 탐색(심야 전용): PRESET=stress   /  Wave E 리허설: PRESET=full
```

## 5. 테스트 중 관찰 (별도 터미널)

```bash
# pgbouncer 슬롯/대기
watch -n2 "sudo -u postgres psql -h 127.0.0.1 -p 5432 -U pgbouncer -d pgbouncer -c 'SHOW POOLS;'"
# PG 활동
watch -n2 "sudo -u postgres psql -p 5434 -Atc \"SELECT datname,state,count(*) FROM pg_stat_activity GROUP BY 1,2;\""
# api_staging pool 로그
docker logs -f api_staging 2>&1 | grep -E 'Pool|SlowQuery'
```

## 6. 결과 기록 (A-2)

| 날짜 | 시나리오 | VU/RATE | req/s | P50 | P95 | 에러율 | 비고 |
|---|---|---|---|---|---|---|---|
| 2026-07-26 | smoke (pos) | 10 VU | 0.43 | 48.9ms | 92.4ms | 0% | 전 체크 100% 통과 |
| 2026-07-26 | burst 3매장 | 10/s, 30터미널 | 11.2 | 28.7ms | 35.5ms | 0% | 1,200건 전량 저장. ★dn 중복 1건 |
| 2026-07-26 | burst 1매장 | 20/s, 10터미널 | 20.8 | 29.3ms | 37.0ms | 0% | 1,197건 저장. ★dn 중복 13건(1.1%) |
| 2026-07-26 | **F-1 수정 후** 1매장 | 20/s, 10터미널 | 20.7 | 29.5ms | 37.0ms | 0% | 1,190건. **중복 0** (지연 변화 없음) |
| 2026-07-26 | **F-1 수정 후** 3매장 | 30/s, 30터미널 | 31.7 | 26.9ms | 33.5ms | 0% | 2,701건. **중복 0**, 항목/결제/금액 정합 전부 통과 |
| 2026-07-26 | **23매장** (더미20 포함) | 50/s, 230터미널 | 50.0 | 28.3ms | 1958ms※ | 0% | 5,961건. **중복 0**, 정합 전부 통과. ※P95 는 부팅 폭풍(F-4) 때문 — 정상구간 avg 27ms |
| 2026-07-27 | T-1 고객 동시등록 23매장 | 20/s, 46터미널 | 20.8 | — | — | **9.2%** | 1,247건 중 115건 500 (F-5/F-6) |
| 2026-07-27 | T-1 **수정 후** | 20/s, 46터미널 | 20.8 | — | — | **0%** | 1,201건 생성 + 364 수정 + 117 삭제, 전 검증 통과 |
| 2026-07-27 | **전체 수정본 회귀** 23매장 | 50/s, 230터미널 | 49.3 | 30.7ms | — | **0%** | 5,919건. 정상구간 avg 30ms, 부팅구간 617ms(F-4, CPU) |
| 2026-07-27 | 로그인 용량 (F-4) | 15/s · 60/s | — | — | 78ms · 81ms | 0% | **60/s 까지 여유** |
| 2026-07-27 | 로그인 용량 (F-4) | 80/s · 100/s | — | — | 4.9s · 7.9s | 0% | 80/s 부터 붕괴 |
| 2026-07-27 | **daylight** 램프업 (주간) | 100→200 VU | 5.5 | 38.8ms | **74.9ms** | 5.35%※ | 체크 2,477건 100% 통과, login_fail 0%, sale P95 57.7ms. ※전량 F-8(스크립트 payload 400) — 서버 결함 아님 |

응답 지연·처리량은 목표(P95 300ms) 대비 매우 여유. 병목은 성능이 아니라 **동시성 정합성**이었다.

### 운영 반영 현황 (2026-07-27)

| 항목 | 로컬 5432 | 운영 5434 / 컨테이너 |
|---|---|---|
| F-1 `uq_sales_store_day_daily_number` + advisory lock | ✅ | ✅ |
| F-6 레거시 `global_clients_document` UNIQUE 제거 | ✅ | ✅ |
| `idx_user_roles_user` (F-4 로그인 핫패스) | ✅ | ✅ |
| F-5/F-6/F-7/F-4/F-2 코드 (커밋 1de4d44 + b87f044) | — | ✅ 배포 확인 (기동 로그 에러 0) |

---

## ★ 발견사항 (Findings)

### F-1 [치명] `daily_number` 채번 경합 — 동일 번호 중복 발급

- **증상**: 같은 매장에서 동시 판매 시 `daily_number`(고객이 보는 티켓 번호)가 중복 발급.
  - 3매장 10건/s → 1,200건 중 1건 중복 (0.08%)
  - 1매장 20건/s → 1,197건 중 13건 중복 (1.1%), 한 번호가 **6번** 발급된 사례 존재
- **원인**: `api-ventago/src/app/sales/sales-create.service.ts:264-278`
  ```ts
  const lastSaleToday = await this.saleModel.findOne({ order: [['dailyNumber','DESC']] });
  const dailyNumber = (lastSaleToday?.dailyNumber || 0) + 1;   // ← 락 없음
  ```
  read-then-write 경합. 게다가 이 계산은 **트랜잭션(367행) 밖**에서 수행되고,
  `(store_id, 날짜, daily_number)` UNIQUE 제약도 없어 DB 가 막아주지도 못한다.
  같은 코드가 무효화(anulación) 경로(599-613행)에도 존재.
- **영향(3,000 터미널 기준)**: 지금은 매장당 초당 판매가 낮아 드물지만, 러시아워에
  한 매장이 초당 수 건을 처리하면 상시 발생. 티켓/영수증 번호 중복 → 회계·AFIP 대사 불가.
- **해결 후보**:
  1. 트랜잭션 내 `pg_advisory_xact_lock(hashtext('sale_dn:'||store_id||':'||날짜))` — 매장별
     직렬화, 커밋 시 자동 해제, 커넥션 추가 점유 없음(pool 안전)
  2. `(store_id, sale_date::date, daily_number) WHERE activity_type='sale'` UNIQUE 부분 인덱스
     — DB 차원 보증. 충돌 시 재시도 로직 필요, 기존 중복 정리 선행 필요
  3. 1+2 병행 (권장): 락으로 예방 + 인덱스로 보증
- **재현**: `k6 run -e STORES=6 -e PER_STORE=10 -e RATE=20 -e DUR=1m burst-multistore.js`
  → `psql -f verify-burst.sql` 의 2번 쿼리
- **✅ 수정 완료 (2026-07-26)**: 채택안 = ①+② 병행
  - ① 코드: `reserveDailyNumber(storeId, tz, t)` 신설 — 판매 INSERT 와 **같은 트랜잭션** 안에서
    `pg_advisory_xact_lock(storeId, YYYYMMDD)` 로 매장·날짜 단위 직렬화. 커밋 시 자동 해제,
    추가 커넥션 점유 없음(전달받은 트랜잭션 재사용 → pool 무영향). 무효화 경로도 동일 적용.
  - ② 마이그레이션: `api-ventago/migrations/2026-07-26-phase63-daily-number-unique.sql`
    (기존 중복 재배정 → `uq_sales_store_day_daily_number` UNIQUE 부분 인덱스)
  - **검증 결과**: 1매장 20건/s 중복 13건 → **0건**, 3매장 30건/s 2,701건 → **0건**.
    P95 37ms→37ms / 33ms 로 **지연 페널티 없음**. 초당 51건 순간 처리 구간도 정상.
  - ★ 배포 순서: 코드 먼저 → 기존 중복 정리 → 인덱스 생성. (인덱스가 먼저면 경합 시 판매 거부)

### F-6 [치명] 서로 다른 사업자(owner_group)가 같은 고객을 등록할 수 없음

- **증상**: 23매장(owner_group 2개)이 동시에 고객을 등록하자 1,247건 중 **115건(9.2%)이 500**.
  단순 경합이 아니라 **영구 차단**이다 — 한 owner_group 이 어떤 DNI 를 먼저 등록하면
  다른 owner_group 은 그 고객을 **영원히 등록할 수 없다**.
- **원인**: `global_clients` 에 유일성 제약이 3개 공존.
  | 인덱스 | 범위 |
  |---|---|
  | `global_clients_document` | **document 단독** — 전 시스템에서 유일 (레거시) |
  | `uq_global_clients_owner_doc_partial` | (owner_group_id, document) — 설계 의도 |
  | `uq_global_clients_owner_docnorm` | (owner_group_id, 정규화 document) — 설계 의도 |
  멀티테넌트 설계는 owner_group 범위인데, 레거시 단독 UNIQUE 가 이를 무력화한다.
  아르헨티나 DNI 는 전 국민 공통 번호이므로 300매장·다수 사업자 환경에서 **상시 충돌**.
- **검증**: `DROP INDEX global_clients_document` 후 동일 테스트 → **500 0건**,
  global 중복 0, store_clients 중복 0, 매장별 수정/삭제 격리 정상.
  owner_group 별로 같은 document 가 1행씩(40 docs → 71 rows / 2 groups) 공존.
- **✅ 마이그레이션**: `migrations/2026-07-27-phase63-global-clients-owner-scope.sql`
  (owner 범위 UNIQUE 2종 존재 확인 후에만 레거시 단독 UNIQUE 제거 — 제약 완화라 데이터 무손실)

### F-5 [높음] Sequelize 훅 실패가 호출자 트랜잭션을 오염 — 500 유발

- **증상**: `Clients.afterCreate` 훅의 `syncFromLegacy` 가 실패하면 호출자가
  `"current transaction is aborted, commands ignored until end of transaction block"` 500 을 받음.
- **원인**: 훅은 실패를 try/catch 로 잡고 "legacy row 는 보존됨" 이라 기록하지만,
  **PostgreSQL 은 트랜잭션 내 statement 하나가 실패하면 트랜잭션 전체를 abort** 한다.
  JS 예외를 잡아도 DB 트랜잭션은 이미 죽어 있어 이후 모든 쿼리가 거부된다.
- **✅ 수정**: `clients.model.ts` 의 afterCreate / afterBulkCreate 훅을 **SAVEPOINT**
  (Sequelize 중첩 트랜잭션)로 감쌌다. 실패 시 savepoint 까지만 롤백되고 호출자는 계속 진행.
  같은 패턴의 훅이 다른 모델에도 있는지 점검 필요(후속 과제).
- 부수 수정: `clients.service.ts` 의 `createWithStoreLink` 에 `pg_advisory_xact_lock`
  (ownerGroupId, document) 추가 — 같은 그룹 내 동시 등록 직렬화.

### F-7 [높음] rate-limit 이 워커별로 집계 — 실제 한도가 설정값의 4배

- **증상**: 같은 지문으로 브루트포스 80회 시도 → 60회 통과 후에야 429.
  설정은 15회/분인데 pm2 워커 4개가 각자 카운터를 들고 있어 15×4=60 이 실제 한도였다.
  인스턴스를 2대로 늘리면 8배가 된다 — 설정값이 의미를 잃는다.
- **원인**: `@nestjs/throttler` 기본 저장소가 **프로세스 메모리**.
- **✅ 수정**: `common/throttle/redis-throttler.storage.ts` 신설 —
  기존 Redis(`ventago_redis`)를 공유 카운터로 사용. Redis 장애 시 로컬 폴백이라
  **인증이 막히지 않는다**(가용성 우선). DB pool 미사용.
- **검증**: 수정 후 정확히 **15회에서 429**. 정상 터미널 30대 동시 로그인은 전부 200.

### F-4 [재정의] 로그인은 CPU 바운드 — 캐시가 아니라 "분산과 증설"이 답

**최초 진단은 부정확했다.** slow query 로그만 보고 "권한 쿼리 병목"으로 판단했으나,
실측해 보니 DB는 전혀 병목이 아니었다(pg_stat_statements 상 모든 쿼리 1ms 미만).

- **실제 원인**: 로그인 1건 = bcrypt 해시 검증 + 권한 조립 + **약 55KB JSON 직렬화**
  (그중 47KB가 앱/모듈/기능 구조). 전부 CPU. 부팅 폭주 시 CPU 92% 도달.
- **로그인 처리 용량 실측** (워커 4개 / 8코어, k6 도 같은 서버에서 CPU 경합):
  | 초당 로그인 | login p95 | 판정 |
  |---|---|---|
  | 15/s | 78ms | ✅ 여유 |
  | 60/s | 81ms | ✅ 여유 |
  | 80/s | 4,871ms | ❌ 붕괴 시작 |
  | 100/s | 7,904ms | ❌ 붕괴 |
  → **지속 가능 한도 ≈ 60~70 로그인/초**.
- **3,000 터미널 환산**: 초당 60건이면 전 터미널 로그인에 **약 50초**. 개점 시간대처럼
  자연스럽게 분산되면 문제없다. 위험한 건 *동시에 한 순간*에 몰리는 경우다
  (실측: 230터미널을 t=0 에 한꺼번에 → 최대 3.9초, 다만 **오류는 0건**).
- **✅ 적용한 완화**:
  1. `functions.service.ts` — 앱/모듈/기능 카탈로그 캐시(10분). 정적 데이터인데
     로그인·/me 마다 3단 중첩 조인으로 재조회하던 것을 제거.
  2. `auth.service.ts` — /me 구조 필터링 결과를 (매장 + 허용함수 해시) 키로 캐시(5분).
     키가 권한에서 파생되므로 권한 변경 시 자동으로 새 키가 되어 무효화가 불필요하다.
  ※ 두 캐시는 **정상 운영 부하를 줄이지만 콜드 동시 폭주는 못 막는다**
    (전원이 같은 순간 캐시 미스). 이건 캐시로 풀 문제가 아니다.
- **남은 권장 조치** (별도 과제):
  1. 클라이언트 재접속에 지터(0~30초 랜덤) — 일제 재시도 방지. 효과 대비 비용 최소.
  2. 워커/인스턴스 증설 — CPU 바운드라 선형으로 확장된다.
  3. `structure` 를 /me 에서 분리해 ETag 캐시 가능한 별도 엔드포인트로 (payload 86% 감소).
- **참고**: JWT 유효기간이 6시간이라 서버 재시작으로 전 터미널이 재로그인하지는 않는다.
  실제 위험 시나리오는 "개점 시각 집중" 하나로 좁혀진다.

### F-4(초기 서술, 참고용) 동시 로그인 폭주 시 권한 해석이 병목 — "개점 러시" 취약

- **증상**: 23매장 230터미널이 동시에 부팅(로그인+초기로드)하자 첫 60초 동안 응답이 급격히 악화.
  | 구간 | 판매 avg |
  |---|---|
  | 부팅 폭풍(02:37, 2,857건) | **455ms** |
  | 정상 구간(02:38, 3,000건) | **27ms** |
  부팅 구간 엔드포인트별(231회): `login` p50 1,098ms / p95 3,291ms, `/auth/me` p50 458ms,
  `/products` p50 344ms, `/payment-methods` p50 210ms.
- **원인**: slow query 상위가 전부 **권한 해석 스택** —
  `role_function_actions`(21회), `users`(15), `role_functions`(6), `user_functions`(4),
  `apps`(4), `stores`(7). 로그인마다 권한 트리를 매번 조립한다(캐시 콜드).
- **영향(3,000 터미널)**: 매장 개점 시간대, 배포 후 전 터미널 재접속, 정전 복구 시
  동시 로그인이 몰린다. 230터미널에서 이미 3.5초라면 3,000터미널은 타임아웃 영역.
  **정상 운영 중 처리량(초당 50건, 27ms)은 전혀 문제없다** — 문제는 오직 동시 부팅.
- **해결 후보**:
  1. `user_permission_cache` 테이블 활용도 점검 → 권한 트리를 Redis 공유 캐시로 (Wave B-4)
  2. `role_function_actions(role_function_id)`, `role_functions(role_id, store_id)` 인덱스 확인
  3. 로그인 응답에서 권한 트리를 분리(지연 로드) — 로그인은 토큰만, 권한은 별도 엔드포인트
  4. 프론트 재접속 시 지수 백오프 + 지터 (일제히 재시도하지 않도록)
- **재현**: 23매장 RATE=50 버스트의 첫 60초. `docker logs api_staging | grep 'POST /api/auth/login'`

### F-2 [중→해결] 로그인 throttle 이 IP 기준 — NAT 뒤 다중 터미널 매장 위험

- **증상**: `LOGIN_THROTTLE` 이 IP당 60초 15회였다. 한 지점의 터미널 10대가 같은 공인 IP 를
  공유하므로, 아침 개점 시 일괄 로그인 + 재시도가 겹치면 일부 터미널이 60초간 로그인 불가.
- **1차 시도(폐기)**: 트래커 키를 `IP + deviceFingerprint` 로 변경 → ★**보안 결함**.
  지문은 클라이언트가 보내는 값이라 공격자가 매 요청 바꾸면 새 버킷이 무한 생성되어
  로그인 시도 제한이 사실상 사라진다. `@Throttle(LOGIN_THROTTLE)` 도 같은 트래커를
  쓰므로 IP 백스톱조차 없었다. (커밋 1de4d44 → b87f044 에서 즉시 되돌림)
- **최종 해결**: 집계 키는 **서버가 신뢰할 수 있는 값**으로만 구성하고 축을 둘로 나눈다.
  · IP 축: `THROTTLE_LOGIN_LIMIT` 15 → **150/분** (10터미널 개점 수용, 회선 상한은 유지)
  · 계정 축: `LOGIN_ACCOUNT_LIMIT` **15/분** — `ProxyThrottlerGuard` 가 POST `/auth/login`
    에서 `emailOrUsername` 기준 강제. IP 를 바꿔가며 한 계정을 노려도 막힌다.
  · 저장소(Redis) 장애 시 429 만 전파하고 통과 — 로그인 가용성 우선, IP 축이 백스톱.
- **교훈**: rate-limit 키에 클라이언트가 정하는 값을 넣으면 제한이 아니라 장식이 된다.
- 일반 요청 한도는 `THROTTLE_DEFAULT_LIMIT` 600회/분(IP당) 무변경 — 10터미널이면 터미널당 60회/분.
- 스테이징에서는 측정 방해를 피하려 env 로 완화(docker-compose.staging.yml).

### F-9 [높음] 전역 `forbidNonWhitelisted` — 클라이언트 버전 스큐가 전면 400 이 되는 구조

F-8(스크립트 400)을 파고들다 나온 **구조적 위험**. 증상은 스크립트였지만 원인 정책은 전역이었다.

- `main.ts` 의 전역 `ValidationPipe({ whitelist: true, forbidNonWhitelisted: true })` —
  DTO 에 없는 필드가 **하나만 와도 요청 전체가 400**. 모든 엔드포인트 공통.
- 노출 벡터: ventago-app 은 API 와 같이 배포되어 창이 짧지만, **설치형 클라이언트**
  (print-agent / zebra-agent / mobile-sales-app APK / ventago-admin-app)는 사용자가
  업데이트해야 한다. DTO 필드를 지우거나 이름만 바꾸면 구버전이 그 순간 전멸한다.
  3,000 터미널에서는 부분 장애가 아니라 전면 정지.
- 관측 사각지대였다: `store_error_log` 는 **500 만** 기록했고 컨테이너 로그는 재기동 시
  소실 → "클라이언트 계약 위반으로 거부됨" 이력이 어디에도 남지 않았다.
- 판단 근거: `whitelist: true` 만으로도 미지 필드는 제거되어 서버가 사용하지 않는다.
  거부는 보안 강화가 아니라 "무시 대신 거부"라는 **가용성 정책 선택**이다.
- 조치 (2026-07-27, 운영 배포·검증 완료):
  · `LoggingValidationPipe` — whitelist 유지, forbidNonWhitelisted 제거,
    제거된 필드를 warn 으로 기록(DTO명 + 필드 경로, 5분 dedup)
  · 400/422 를 `store_error_log` 에 영속 기록 (401/403/404/429 는 노이즈라 제외)
  · superadmin `errors24h` 카운트에 `status_code >= 500` 조건 추가(의미 보존)
  · 타입 불일치·필수 누락은 **종전대로 400 유지**
- 운영 실증: `POST /auth/login` 에 미지 필드 `campoInexistente` 포함 →
  이전 400 거부 → 현재 정상 처리(404 유저 없음) + `[ValidationPipe] DTO 에 없는 필드가 제거됨` 로그.
  비밀번호 6자 미만은 여전히 400.

### F-8 [스크립트] hold(보류판매) 페이로드가 DTO 화이트리스트 위반

- `POST /api/suspended-sales` 가 400 (`items.0.property total should not exist`).
- 2026-07-27 daylight 200VU 측정의 실패율 5.35% 는 **전량 이 항목** — 서버 결함이 아니라
  k6 스크립트가 `items[].total` 을 보냈기 때문. 판매(`POST /sales`)·로그인·조회는 전부 정상.
- 수정: `pos-scenario.js` 의 hold 페이로드에서 `total` 제거.

### F-3 [참고] `/clients` 페이지네이션은 0-based

`GET /clients?page=0&pageSize=20` 이 1페이지. `page=1` 은 2페이지(데이터 19건이면 빈 배열).
프론트가 MUI TablePagination 0-based 를 그대로 전달하기 때문. API 직접 호출 시 주의.

## 7. 정리 (테스트 기간 종료 후)

```bash
docker rm -f api_staging
sudo -u postgres dropdb -p 5434 ventago_staging   # ★ staging 만! 오타 주의
```

## 안전 수칙

- 운영 API(5002 / newapi.coolsistema.com) 에 k6 를 직접 겨누지 않는다.
- 주간에는 PRESET=smoke 만 + watchdog.sh 필수 동반.
- stress / full 은 심야(00:00~06:00 ART) 전용. 시작 전 운영 트래픽 확인.
- watchdog 임계치: load 6.0 / 여유메모리 2GB / 운영 cl_waiting 5.
- 테스트 전후 `docker logs api_ventago` 최신 로그에서 운영 이상 여부 확인.
