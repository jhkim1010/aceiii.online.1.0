# 스테이지 서버 프로비저닝

운영(srv803182)의 **ventago 스택 미러** 스테이지. 운영과 동일한 포트 구조·컨테이너 구성을
쓰므로 운영 진단 절차와 스크립트가 그대로 통한다.

**대상 서버**: IONOS VPS `74.208.60.137` — 4 vCore / 8GB RAM / 240GB NVMe (US)

```
인터넷 → nginx(443, Let's Encrypt)
           ├─ stage.coolsistema.com     → 127.0.0.1:5001  ventagoapp_stage   (Next.js)
           └─ stageapi.coolsistema.com  → 127.0.0.1:5002  api_ventago_stage  (NestJS/PM2 2워커)
                                                │
                                                ├─ ventago_redis_stage (socket.io 어댑터)
                                                ├─ minio_stage:9000     (API 가 프록시)
                                                └─ host.docker.internal:5432
                                                     pgbouncer (transaction mode)
                                                        └─ 127.0.0.1:5434
                                                             PostgreSQL 18 / ventago18
```

### 범위: ventago 만

배포 대상은 `api-ventago` + `ventago-app` **둘 뿐**이다. 모노레포의 나머지는 올리지 않는다:

| 제외 | 이유 |
|---|---|
| `tienda-app` / 공개몰 | 별도 도메인·트래픽 특성. `shop_readonly` pool 은 최소값(2)만 유지 |
| `despacho-app`, `mobile-sales-app`, `talleres-vendor-app` | 독립 배포 대상 |
| `ventago-admin-app` (superadmin) | 운영 데이터 복제본에 superadmin UI 를 띄우지 않는다 |
| `print-agent` / `zebra-agent` / `vw-agent` / `edge-agent` | Electron 데스크톱 앱. 필요하면 로컬에서 스테이지 API 를 가리키게 하면 된다 |
| MinIO 전용 도메인 | 불필요 — 프론트가 `{API_HOST}/minio/{fileName}` 로 API 를 경유한다 |

→ DNS A 레코드는 `stage` / `stageapi` **2개만** 필요하다.

---

## 실행 순서

```bash
cd infra/stage
cp 00-config.env.example 00-config.env
vi 00-config.env          # CHANGE_ME 전부 채우기 (IP·도메인은 이미 채워져 있음)
chmod 600 00-config.env

./00-inspect.sh           # 읽기 전용 점검 — 아무것도 바꾸지 않는다
./00-check-firewall.sh    # IONOS Cloud Firewall 실제 통과 테스트 (80/443)
./01-base.sh              # OS 하드닝, swap 4G, ufw, fail2ban
./02-postgres.sh          # PG18 + pgbouncer
./03-docker-minio.sh      # Docker, coolsistema_network, MinIO
./04-restore.sh           # ★ 운영 DB 복제 + 안전화 (확인 프롬프트 있음)
./05-deploy.sh            # 앱 빌드 & 기동
./06-nginx-ssl.sh         # nginx + Let's Encrypt (DNS 선행 필요)
./07-verify.sh            # 검증 — 실패 시 종료코드 1
```

각 스크립트는 **멱등**하다. 실패하면 원인을 고치고 그 스크립트만 다시 돌리면 된다.

---

## 사전 준비

| 항목 | 내용 |
|---|---|
| **IONOS Cloud Firewall** | 콘솔의 `My firewall policy` 에서 TCP **22 / 80 / 443** 인바운드 허용. ufw 만 열면 certbot 이 실패한다 |
| DNS | `stage.coolsistema.com`, `stageapi.coolsistema.com` A 레코드 → `74.208.60.137`. **06 실행 전 필수** |
| SSH 키 | 로컬 → 스테이지 root 키 로그인. 01 이 비밀번호 로그인을 끄므로 **반드시 먼저 확인** (`00-inspect.sh` 5번 항목) |
| 운영 접근 | `~/.ssh/config` 의 `jhkim-server` alias (04 가 pg_dump 에 사용) |
| 배포 키 | 스테이지에서 private repo clone 이 가능해야 함 (05) — deploy key 또는 SSH agent forwarding |
| 디스크 | 240GB. 운영 DB 크기의 3배 여유가 있는지 `00-inspect.sh` 2번 항목에서 확인 |

---

## ★ 안전 설계 — 왜 이렇게까지 하는가

운영 데이터를 **그대로** 복제하기로 했다. 그 결정의 실제 의미는
"실제 고객 연락처와 실제 결제 자격증명이 스테이지 서버에 존재한다"는 것이다.
아무 조치 없이 앱을 띄우면 스테이지가 다음을 **실제로** 한다:

| 경로 | 사고 |
|---|---|
| 캠페인 워커 | 실제 고객에게 WhatsApp/이메일 발송 |
| `mp_accounts` 운영 토큰 | 실제 Mercadopago 계정으로 결제·환불 |
| `branch_agents.api_key` | 운영 매장 comandera/Zebra 에서 테스트 전표 출력 |
| `sync_outbox` | 운영 WooCommerce 로 재고 덮어쓰기 |
| socket.io Redis 공유 | 스테이지 print 이벤트가 운영 print-agent 로 |
| MP 웹훅 URL | 스테이지 결제 콜백이 운영 API 로 |

전부 되돌릴 수 없다. 그래서 **DB 레벨과 앱 레벨에 이중으로** 차단을 건다.

**DB 레벨** (`sql/stage-sanitize.sql`, 04 가 자동 실행)
- MP 토큰 → `STAGE_DISABLED`, `environment='sandbox'`
- WhatsApp / 이메일 / Telegram 자격증명 → NULL
- WooCommerce·WP 채널 → 비활성 + `site_url='https://stage.invalid'`
- `sync_outbox` 미처리 건 → `cancelled`
- 모든 에이전트 `api_key` → 재발급 (운영 프린터와 상호 접속 불가)
- 세션 테이블 전부 TRUNCATE
- 매장 별칭에 `[STAGE]` 접두어 → 화면에서 즉시 구분

**앱 레벨** (`05-deploy.sh` 가 생성하는 `.env`)
- `CRON_ENABLED=false` — 캠페인·outbox 워커 정지
- `REDIS_HOST=ventago_redis_stage` — socket.io 채널 격리
- `MP_NOTIFICATION_BASE_URL` → 스테이지 도메인
- Telegram/Email/WhatsApp 토큰 공란

**네트워크 레벨**
- 앱·DB 포트는 전부 `127.0.0.1` 바인딩, ufw 는 22/80/443 만 허용
- 프론트에 basic auth (`user: stage`) + `X-Robots-Tag: noindex`

`07-verify.sh` 의 6번 항목이 이 차단들을 **전부 0 인지** 확인한다. 하나라도 0 이 아니면
스테이지를 쓰지 말고 안전화를 다시 돌린다.

### 남아 있는 위험 (알고 쓸 것)
- 실제 고객 개인정보(이름·전화·이메일)와 `users.password` 해시가 스테이지에 존재한다.
  스테이지 서버의 보안 수준이 곧 그 데이터의 보안 수준이다.
- 개인정보를 두고 싶지 않다면 안전화 스크립트에 마스킹 UPDATE 를 추가하면 된다
  (`clients`, `global_clients`, `store_clients` 의 연락처 컬럼).

---

## 커넥션 예산 (pool 낭비 방지)

산식은 앱의 단일 출처(`src/common/config/connection-budget.ts`)와 **동일하게** 맞췄다.
여기서만 다르게 계산하면 배포 전 검사와 부팅 로그가 다른 숫자를 말하게 된다.

```
앱 클라이언트 = replicas × workers × (mainMax + shopMax)   ← 앱 → pgbouncer
pgbouncer 백엔드 = pool_size 의 (db, user) 쌍별 합          ← pgbouncer → PG
```

**★ 층위를 혼동하지 말 것.** 두 값은 다른 자로 재는 숫자다. 클라이언트가 백엔드보다
큰 것은 정상이며, 그게 transaction pooling 의 존재 이유다. 서버측 포화의 진짜 판정
근거는 숫자 비교가 아니라 `SHOW POOLS` 의 `cl_waiting` 이다(Phase 75 W0-10).

| 항목 | 스테이지 (8GB) | 운영 (31GB) |
|---|---|---|
| API 워커 | 2 | 4 |
| sequelize `pool.max` (워커당) | 20 ※ | 20 |
| 공개몰 pool (워커당, 실효) | 2 | 5 |
| **앱 클라이언트 상한** | **44** | 100 |
| pgbouncer `ventago` `pool_size` | 16 | 50 |
| pgbouncer `shop_readonly` `pool_size` | 2 | — |
| pgbouncer `max_client_conn` | 200 | 1000 |
| PG `max_connections` | 60 | 200 |
| 클라이언트 : 백엔드 | 2.4 : 1 | 2.0 : 1 |

> ※ **`pool.max` 는 env 로 못 바꾼다.** `api-ventago/src/database/database.module.ts` 에
> `max: 20` 으로 하드코딩돼 있다. `00-config.env` 의 `SEQUELIZE_POOL_MAX` 는 예산 계산이
> 현실과 맞도록 그 코드값을 **적어두는 표기값**이지, 앱을 바꾸는 값이 아니다.
> 실제로 낮추려면 코드 변경이 필요하고 그건 운영에도 영향을 주는 별도 결정이다.

`lib/common.sh` 의 `verify_connection_budget()` 이 02·05 실행 전에 검사하고 어긋나면 막는다:

- 클라이언트가 `max_client_conn`(200) 초과 → **중단**
- 백엔드 합이 `max_connections` 의 70%(42) 초과 → **중단**
- 클라이언트 : 백엔드 > 6:1 → 경고 (sequelize `acquire` 15초 안에 못 받는 요청 발생)
- 클라이언트 < 백엔드 → 경고 (**서버 슬롯 낭비** — PG 백엔드 프로세스당 메모리를 쓴다)

`07-verify.sh` 는 `pg_stat_activity` 의 **idle in transaction** 을 함께 출력한다.
이 값이 쌓이면 커넥션이 반납되지 않고 있다는 뜻이므로 즉시 조사한다.

### 8GB 메모리 배분

DB 전용 서버가 아니다. 교과서값(`shared_buffers = RAM/4`)을 쓰면 Next.js 빌드에서 OOM 이
난다 — 운영에서 겪은 build #620(swap 0, SIGABRT)과 같은 형태다.

| 항목 | 값 | 근거 |
|---|---|---|
| DB 예산 | RAM 의 45% ≈ 3.5GB | 나머지는 API 2워커 + Next.js + Redis + MinIO + OS |
| `shared_buffers` | ≈ 1.6GB | DB 예산의 45% |
| `work_mem` | 10MB | `(DB예산 − shared_buffers) ÷ 60conn ÷ 3node`, 상한 16MB |
| `maintenance_work_mem` | ≈ 296MB | 상한 512MB |
| 최악 사용량 추정 | ≈ 3.7GB (RAM 의 46%) | 80% 초과 시 `02-postgres.sh` 가 배포를 막는다 |
| swap | 4GB | Next.js 프로덕션 빌드 한 번이 2GB 넘게 쓴다 |

`vm.overcommit_memory` 는 PG 문서 권장값(2, 엄격)이 **아니라** 기본값 0 을 쓴다.
V8 이 힙을 크게 예약하므로 엄격 모드에서는 빌드가 ENOMEM 으로 죽는다. postmaster 보호는
`OOMScoreAdjust=-900` systemd drop-in 으로 대신한다 — 효과는 같고 앱은 안 깨진다.

`07-verify.sh` 는 `pg_stat_activity` 의 **idle in transaction** 을 함께 출력한다.
이 값이 쌓이면 커넥션이 반납되지 않고 있다는 뜻이므로 즉시 조사한다.

---

## 운영 작업

```bash
# 코드 갱신 후 재배포
./05-deploy.sh

# 운영 데이터 재복제 (스테이지 DB 는 DROP 된다)
./04-restore.sh

# 상태 점검
./07-verify.sh

# 로그
ssh root@<STAGE_HOST> 'docker logs -f api_ventago_stage'
ssh root@<STAGE_HOST> 'tail -f /var/log/postgresql/postgresql-18-ventago18.log'
```

### 마이그레이션 검증 흐름
새 마이그레이션은 **로컬(5432) → 스테이지(5434) → 운영(5434)** 순으로 적용한다.
스테이지가 운영 데이터 복제본이므로, 여기서 통과하면 운영에서 터질 확률이 크게 준다.

```bash
ssh root@<STAGE_HOST> "sudo -u postgres psql -p 5434 -d ventago \
  -v ON_ERROR_STOP=1 --single-transaction" < api-ventago/migrations/<file>.sql
```

---

## 트러블슈팅

| 증상 | 원인 / 조치 |
|---|---|
| certbot 챌린지 실패 | DNS A 레코드 미전파. `dig +short <도메인>` 으로 확인 후 재실행 |
| API 500 `permission denied` | 시퀀스 owner 누락. `04-restore.sh` 의 소유권 이전 블록 재실행 |
| `relation does not exist` | 스테이지에 마이그레이션 미적용. 04 재실행 또는 개별 SQL 적용 |
| socket.io 400 `Session ID unknown` | nginx WebSocket 업그레이드 헤더 누락. `snippets/ventago-proxy.conf` 확인 |
| pgbouncer `no such user` | `/etc/pgbouncer/userlist.txt` 재생성 (02 의 해당 블록) |
| acquire 타임아웃 15초 | 커넥션 예산 불균형. `SHOW POOLS;` 의 `cl_waiting` 확인 |
| 빌드 중 OOM | 운영과 달리 swap 2G 가 있으나 부족하면 `API_WORKERS` 를 1 로 낮추고 재시도 |
