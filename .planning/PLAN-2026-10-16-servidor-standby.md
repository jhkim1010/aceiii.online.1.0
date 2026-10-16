# 대기(standby) 서버 — 운영 장애 시 서비스 유지 (2026-10-16)

## 계기
- 2026-10-16 08:13–08:31 (매장 시간) 운영 서버 srv803182 정지 **18분**, 전 매장 「MODO SIN CONEXIÓN」.
- 원인: **Hostinger 하이퍼바이저가 끈 것** — 저널 `qemu-ga: guest-shutdown called` →
  `System is powering down (hypervisor initiated shutdown)` (11:13:40 UTC). 재부팅 후 커널 6.8.0-136 → 147.
  우리 배포·작업과 무관. 업체 쪽 작업은 예고 없이 또 올 수 있다.
- 그 시간 동안 대안이 없었다: srv2 에는 복제가 없고(설계만 있음), 백업은 하루 1회(22:30)라
  전환하면 밤사이 데이터를 잃는다.

## 사용자 결정 (2026-10-16)
- 대기 서버 = **새 VPS** (srv2 아님 — dranytime·WordPress·Ollama 와 메모리를 다투고 같은 장애 범주)
- 수준 = **수동 전환부터** (명령 하나 ≈ 10–15분). 안정되면 자동 감지를 덧붙인다.
- active-active(동시 운영)는 하지 않는다 — 카하 서랍 규칙·판매 번호·AFIP 번호가 두 곳에서 갈라진다.

## 운영 서버 실측 (대기 서버 사양의 근거)
| 항목 | 값 |
|---|---|
| CPU / RAM | AMD EPYC 8 vCPU / 32 GB (사용 6 GB) |
| 디스크 | 387 GB 중 161 GB 사용 (`/var/lib/postgresql` 96 GB) |
| Ventago DB (PG18 :5434) | **1.1 GB** |
| 레거시 PG10 (:5433) | DB 128개 · **36 GB** — 126개 테넌트가 실제로 씀 |
| MinIO | 20 MB |
| 컨테이너 | 19개 (Ventago 외 cool-invoice·syncace·coolify·mongodb·tienda 등) |
| OS | Ubuntu 24.04.2 |

## 단계
| # | 할 일 | 승인 | 비고 |
|---|---|---|---|
| 0 | VPS 구입 (사용자) — 아래 사양 · root SSH 키 | — | 운영과 **다른 업체**, 미주 지역 |
| 1 | 기본 보안: SSH 키 전용·방화벽(22/80/443 만)·swap·자동 업데이트 **재부팅 끔** | — | `scripts/server2-setup.sh` 재사용 |
| 2 | PG18 설치 + **스트리밍 복제 standby** (운영 :5434 → 대기) | **운영 변경 승인** | 운영: replicator role · pg_hba 1줄 · 슬롯(`max_slot_wal_keep_size` 상한). 복제는 TLS/WireGuard 위로만 |
| 3 | 같은 이미지 배포: api_ventago · ventagoapp · nginx(TLS) · redis · pgbouncer · minio — **정지 상태로 대기** | — | Jenkins 가 빌드한 이미지를 대기 서버로 전달하는 단계 추가 |
| 4 | 파일 동기화: MinIO · AFIP 인증서(Ventago 것만) · `.env` | — | 비밀은 대기 서버에서 600 |
| 5 | 전환 스크립트 `failover.sh`: 운영 응답 없음 확인 → standby 승격 → 컨테이너 기동 → 헬스체크 | 실행 시 사용자 | ★ 운영이 **확실히 죽었을 때만** (둘이 동시에 쓰면 split-brain) |
| 6 | DNS: `newapi`·`app` A 레코드 TTL 을 300초로 낮춤 · 전환 시 대기 IP 로 | 사용자(GoDaddy) | 자동화는 GoDaddy API 키가 있으면 |
| 7 | 복귀 절차 `failback.sh`: 대기가 새 원본 → 옛 운영을 standby 로 재구성 → 한가한 시간에 되돌림 | 실행 시 사용자 | |
| 8 | **리허설** (밤): 실제로 전환 → POS 판매·AFIP 발급 1건 → 복귀. 걸린 시간 기록 | 사용자 | 리허설 전에는 「준비됨」이 아니다 |
| 9 | 감시: 복제 지연·슬롯 WAL 크기·대기 서버 생존을 텔레그램 경보에 추가 | — | 「부재」 경보 포함 |

## 범위 — 2026-10-16 사용자 결정: **Ventago 만 먼저** (레거시는 Ventago 안정 후 별도)

(검토했던 선택지)
- **Ventago (PG18 + api + app)** 는 확정.
- 같은 서버의 **레거시 PG10(126 테넌트) · cool-invoice · syncace** 도 대기 서버로 보호할지? (오늘 그것들도 같이 멈췄다)
  - 포함 시: 디스크·RAM 이 커지고(PG10 36 GB, PG10 은 PG18 로 복제 불가 → PG10 standby 따로), 일이 2배.
  - 미포함 시: 장애 때 Ventago 만 살아난다.

## 권장 VPS 사양
- 4–8 vCPU · **16 GB RAM**(Ventago 만) / 32 GB(레거시 포함) · NVMe 160 GB 이상 · Ubuntu 24.04
- 지역: 아르헨티나 지연이 작은 곳 (São Paulo 또는 미국 동부)
- 업체: Hostinger 가 **아닌** 곳 (같은 업체 장애에 같이 죽지 않게)

## 위험 / 주의
- 복제 슬롯은 대기가 끊기면 운영 디스크에 WAL 을 무한히 쌓는다 → `max_slot_wal_keep_size = 20GB` 상한 필수.
- pgbouncer 가 인터넷에 열린 것(레거시)은 대기 서버에서 **같은 구조로 복제하지 않는다**.
- AFIP: 전환 중 발급은 같은 인증서·같은 번호 원장(DB)을 쓰므로 번호가 갈라지지 않는다 — 단 운영이 살아 있는데 대기가 승격되면 갈라진다(→ 단계 5 의 확인).
- Jenkins 는 운영 서버 위에서 돈다 — 운영이 죽으면 배포도 못 한다(전환 중에는 배포 없음으로 운용).

## Estado 운용3 (paso 2)

2026-10-16 15:05 UTC — 운용3(Vultr Miami, `ssh ventago-standby`)에 PG18 스트리밍 복제본 가동. 운영 쪽은 변경 없음(읽기 조회만).

**설치·구성**
- PostgreSQL **18.6** (PGDG apt, 운영은 18.4 — 같은 메이저, 대기 쪽 마이너가 높은 것은 허용 방향). `createcluster.conf` 에 `create_main_cluster = false` → `main` 클러스터 없음.
- 클러스터 `18/ventago18`, 포트 **5434**, `listen_addresses = localhost`. ufw 는 22/80/443 그대로(PG 포트 미노출).
- 설정: `/etc/postgresql/18/ventago18/conf.d/10-standby.conf` (hot_standby=on, max_connections=200 등 운영값 이상 — hot standby 필수조건, pg_stat_statements preload).
  ★ `pg_basebackup` 이 운영의 `postgresql.auto.conf`(ALTER SYSTEM 값)를 그대로 가져온다 — auto.conf 가 conf.d 보다 우선이므로
  대기 쪽 auto.conf 에서 `shared_buffers 2GB→1GB`, `effective_cache_size 12GB→5GB` 로 직접 고쳤다(8GB RAM). 이 파일은 WAL 로 복제되지 않는다.
  ★ 승격(promote) 시 운영과 같은 성능을 원하면 RAM 에 맞게 다시 볼 것.
- 데이터: `/var/lib/postgresql/18/ventago18` (`pg_basebackup -X stream -S ventago_standby -R`, 2.6GB). `standby.signal` 있음,
  `primary_conninfo` = host=127.0.0.1 port=15434 user=replicator passfile=/var/lib/postgresql/.pgpass, `primary_slot_name = 'ventago_standby'`.
- 비밀번호: `/var/lib/postgresql/.pgpass` (0600 postgres) 에만 있음.

**서비스 (둘 다 enabled — 재부팅 시 자동 기동)**
- `pg-tunnel.service` — 사용자 `tunnel`, `autossh -M 0 -N ... -L 127.0.0.1:15434:127.0.0.1:5434 jhkim@62.72.7.245`, Restart=always, RestartSec=5.
- `postgresql@18-ventago18.service`.
- 터널이 끊겨도 복제는 터널 복구 뒤 슬롯 위치부터 자동 재개된다. 운영 쪽 슬롯은 최대 `max_slot_wal_keep_size=20GB` 까지 WAL 을 붙잡는다.

**지연 확인**
```bash
# 대기(운용3)
ssh ventago-standby "sudo -u postgres psql -p 5434 -Atc 'SELECT pg_is_in_recovery(), now()-pg_last_xact_replay_timestamp()'"
ssh ventago-standby "sudo -u postgres psql -p 5434 -Atc 'SELECT status, sender_host, sender_port FROM pg_stat_wal_receiver'"
ssh ventago-standby "systemctl is-active pg-tunnel postgresql@18-ventago18"
# 운영(읽기 전용)
ssh jhkim-server "sudo -u postgres psql -p 5434 -Atc 'SELECT client_addr,state,sync_state,pg_wal_lsn_diff(pg_current_wal_lsn(),replay_lsn),replay_lag FROM pg_stat_replication'"
ssh jhkim-server "sudo -u postgres psql -p 5434 -Atc \"SELECT active, pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(),restart_lsn)) FROM pg_replication_slots WHERE slot_name='ventago_standby'\""
```
⤷ `now()-pg_last_xact_replay_timestamp()` 는 운영에 쓰기가 없으면 커진다(유휴 = 지연 아님). 진짜 지표는 운영 쪽 바이트 차이.
⤷ 슬롯 `active=f` 가 오래 지속되면 운영 디스크에 WAL 이 쌓인다(최대 20GB) — 감시 대상.

실측(가동 직후): 대기 `pg_is_in_recovery=t`, 재생 지연 2.0s · 운영 `streaming/async`, 바이트 차 0, replay_lag 0.05s, 슬롯 active=t ·
`sales` count 359,669 / max(id) 359,691 양쪽 동일.

**되돌리기 (문서만 — 실행하지 않음)**
1. 운용3: `sudo systemctl disable --now postgresql@18-ventago18 pg-tunnel`
2. 운영(승인 필요 · 슬롯이 inactive 인 상태에서): `SELECT pg_drop_replication_slot('ventago_standby');` — **반드시** 할 것. 남겨 두면 운영이 WAL 을 20GB 까지 붙잡는다.
3. (선택) 운영: `DROP ROLE replicator;` · pg_hba 의 `host replication all 127.0.0.1/32` 줄 제거 후 reload · 운영 `~jhkim/.ssh/authorized_keys` 의 tunnel 키 줄 제거.
4. (선택) 운용3: `sudo pg_dropcluster --stop 18 ventago18`, `sudo rm /etc/systemd/system/pg-tunnel.service /var/lib/postgresql/.pgpass && sudo systemctl daemon-reload`.

## Estado 운용3 (paso 3 + paso 9) — 2026-10-16 17:40–18:00 (BA)

**paso 3 — 컨테이너 (만들어만 둠, 띄우지 않음)**
- `/opt/ventago/docker-compose.yml` (저장소 사본 `scripts/standby/docker-compose.yml`). 프로젝트 이름 `ventago`.
  ★ `/opt/ventago` 는 750 root — `cd` 불가. 명령은 `sudo docker compose -f /opt/ventago/docker-compose.yml --project-directory /tmp ...`
- 컨테이너 4개 `Created`/`Exited`, 전부 `restart: "no"`: api_ventago(**host 네트워크** — DB 가 localhost 5434) · ventagoapp(127.0.0.1:5001) ·
  ventago_redis(127.0.0.1:6379) · minio(127.0.0.1:9005/9001).
- 이미지: 운영에서 `docker save | zstd` 로 옮김(Mac 경유, 468MB, 2분) — `ventago_5003-apiventago:latest`(운영 id 4f27b3e9…) · `ventagoapp-front:latest`(96c81ef6…)
  · `minio/minio:latest`(운영 것, 2025-06-23). ★ **Docker Hub 의 minio/minio 는 더 이상 받을 수 없다**(pull access denied) — 운영에서 옮겨야 한다.
  ★ 운영 배포마다 이미지가 바뀐다 — 지금은 **수동으로** 다시 옮겨야 한다(Jenkins 연동은 미구현). 전환 직전 이미지가 낡았으면 그 차이만큼 옛 코드가 뜬다.
- env: `/opt/ventago/{api,app,minio}.env` (600 root) = 운영 컨테이너의 `docker inspect` 환경 그대로, 바꾼 것은
  `DATABASE_HOST/SHOP_DB_HOST=127.0.0.1` · `*_PORT=5434` · `REDIS_HOST=127.0.0.1` 뿐. api 는 pm2 설정 때문에 **항상 5002** 에서 듣는다(PORT 무시).
- ★ **pg_hba**: 운영 계정 비밀번호가 **md5 해시**라 대기 기본값(scram-sha-256)으로는 api 가 로그인 못 한다 → `host all all 127.0.0.1/32 md5`(::1 도) 로 변경
  (백업 `pg_hba.conf.bak-20261016`). coolsistema·shop_readonly 로그인 확인.
- 스모크(임시 컨테이너 `api_smoke`, CRON_ENABLED=false · 텔레그램/메일/FASHN 키 비움): Nest 부팅 성공, `/api/health` = db up · schema ok · redisAdapter on.
  app `/login` 응답(308). 외부에서 5002·5001 닫힘 확인. ★ 시험 때 **텔레그램 토큰을 꼭 비운다** — Pedidos 봇 폴링이 운영과 업데이트를 나눠 먹는다.
- 미포함: ollama(AI 채팅은 전환 중 안 됨) · pgbouncer(api 가 PG 직결, 4워커×20=80 < max_connections 200).

**paso 9 — 감시**
- `scripts/ventago-health-watch.sh` 에 `CHEQUEAR_REPLICA` 블록: 승격 여부 · WAL 수신기 streaming · 운영에서 받은 지 N초(180).
  운용3 에 systemd 타이머 60초로 설치, `/etc/ventago-health-watch.env`(600: 텔레그램 · ETIQUETA=STANDBY-운용3 · CONTENEDORES= · CHEQUEAR_ADAPTER= · FALLOS_PARA_ALERTA=3).
  운영 공개 URL 도 같이 본다 → **세 번째 외부 감시**(다른 업체). 첫 실행에 생존 신호 발송.
- 검증: 정상 = 무경보 · PG 포트 틀림 = 경보 · 상한 음수 = 경보 · **터널 실제 중단 → 10초 안에 「sin-receptor」**, 재기동 후 streaming 복귀.
- ★ 아직 없는 것: **운영 쪽** 슬롯 WAL 크기 감시(운용3 가 통째로 죽으면 이 감시도 죽는다 — 그때는 생존 신호가 끊기는 것으로만 안다).
  운영 health-watch 에 슬롯 검사를 더하는 것은 운영 파일 변경이라 승인 후.

## Estado 운용3 (paso 4) — 2026-10-16 18:00–18:15 (BA)

- **nginx 1.24** + `/etc/nginx/conf.d/ventago.conf`(사본 `scripts/standby/nginx-ventago.conf`) — 운영 3개 사이트(newapi·app·apiminio)와 같은 동작,
  다른 점은 `upstream ventago_api { 127.0.0.1:5002 }` 하나. 평소엔 컨테이너가 꺼져 502 가 정상.
- **TLS**: 운영 `/etc/letsencrypt/live/coolsistema/{fullchain,privkey}.pem`(SAN 13개, 만료 2026-12-13) → `/etc/ssl/ventago/`(700/600).
- **AFIP 인증서**: `/var/lib/ventago-certs`(5 폴더: 23942305044·coolsistema·coolsyncrohomo1·noix·ventago_st6) → `/opt/ventago/certs`,
  `/var/lib/jenkins/workspace/certificados/coolsistema` → `/opt/ventago/certs-coolsistema`(`.lastTokens` 포함).
- **MinIO**: 데이터 사본(227 객체, 17.4 MiB, 21:00 UTC) · 컨테이너 `minio` 만 **항상 켬**(`unless-stopped`, 127.0.0.1 전용).
- **이미지 태그 고정**: 운영은 blue/green 이라 `ventago_5002-…`/`ventago_5003-…` 가 번갈아 바뀐다 → 대기는 `ventago-api:standby`·`ventago-app:standby`.
- **끝단 시험**(Mac `curl --resolve <host>:443:149.28.107.232`, 외부효과 끈 api_smoke): newapi `/api/health` 200 · app `/login` 308 ·
  apiminio `/minio/health/live` 200 · 세 도메인 TLS 검증 통과(ssl_verify=0).
- **동기화** `scripts/standby-sync.sh` — Mac launchd `com.ventago.standby-sync`(1시간, 로그 `~/Library/Logs/ventago-standby-sync.log`):
  운영이 **지금 쓰는** 이미지 id 가 바뀌면 save→load→태그→`create --force-recreate`(★ start 안 함) · AFIP 인증서 폴더 해시 · TLS 지문.
  성공 시 `/opt/ventago/state/last-sync` → 운용3 감시가 3시간 넘으면 경보(부재도 경보). ★ 해시 정렬은 `LC_ALL=C` — 로캘 차이로 같은 내용이 「다름」이었다.
  검증: 상태 파일 삭제 → 이미지 차이 감지 · 인증서 파일 변조 → 그 폴더만 감지 후 운영 것으로 복구.

**남은 구멍 — 운영 변경이라 승인 대기**
1. **MinIO 지속 동기화**: rclone 이 운영 공개 주소로는 서명이 안 맞는다(운영 nginx 가 `Host $host:$server_port` 로 `:443` 을 붙이는데 rclone 은 기본 포트를 떼고 서명).
   → 운영 `~jhkim/.ssh/authorized_keys` 의 tunnel 키에 `permitopen="127.0.0.1:9005"` 추가 + 터널에 `-L 127.0.0.1:19005:127.0.0.1:9005` → rclone 15분.
   그 전까지 대기의 MinIO 는 **21:00 UTC 사본**(그 뒤 올린 사진·로고는 없음).
2. **운영 쪽 슬롯 감시**: 운영 health-watch 에 `ventago_standby` 슬롯 active·보유 WAL 크기 검사.
3. **전환 시 hosts**: api 의 `MINIO_HOST=apiminio.coolsistema.com` 이 대기 안에서도 운영 IP 로 풀린다 → failover.sh 가 `/etc/hosts` 에
   `127.0.0.1 apiminio.coolsistema.com` 을 넣어야 한다(5단계에서).

## Estado (2026-10-16 19:00 BA) — cambios en prod aprobados («진행»)
- **A** prod `~jhkim/.ssh/authorized_keys` línea 9 (clave `ventago-standby-tunnel`): + `permitopen="127.0.0.1:9005"` (backup `authorized_keys.bak-20261016-minio`).
  운용3: `minio-tunnel.service`(19005 → prod 9005, 복제 터널과 분리) · rclone endpoint `http://127.0.0.1:19005` ·
  `standby-minio-sync.timer` 15분 `rclone copy`(삭제 안 따라감) → `/opt/ventago/state/last-minio-sync`. 첫 대조 227/227 일치.
  운용3 감시: MinIO 사본 1시간 넘으면/없으면 경보.
- **B** prod `ventago-health-watch` 에 `CHEQUEAR_SLOT=ventago_standby`(drop-in `/etc/systemd/system/ventago-health-watch.service.d/10-slot.conf`),
  스크립트 백업 `/usr/local/bin/ventago-health-watch.sh.bak-20261016`(설치본 = 저장소 d002590 과 동일했음).
  검증: 정상 무경보 · 없는 슬롯 · WAL 상한 · **운용3 터널 실제 중단 → 「비활성」**. 보유 WAL 상한 경보 2048MB.

## Estado (paso 5) — `ventago-failover` (2026-10-16 19:05 BA)
- `scripts/standby/failover.sh` → 운용3 `/usr/local/sbin/ventago-failover` (0750 root). `--simular` · (sin flag) · `--forzar-prod-vivo`.
- ① 운영 사망 확인 3회×20초(prod IP 로 `--resolve` health + 22번 포트) — API 200 이면 **거부**, 서버(22) 살아 있으면 `--forzar-prod-vivo` 없이는 거부.
  ② 복제 상태·마지막 적용 트랜잭션 시각·`sales max(id)` 표시 → 확인 문구 `PROMOVER ventago` → ③ 터널·MinIO 타이머 정지 ④ `pg_promote(true,60)`
  + `/opt/ventago/state/PROMOVIDO` ⑤ `/etc/hosts` 에 newapi/app/apiminio → 127.0.0.1(api 가 host 네트워크라 MINIO_HOST 가 여기로) ⑥ 컨테이너 start(restart unless-stopped)
  ⑦ health(로컬 + nginx --resolve) ⑧ 감시 env 를 원본 모드로(ETIQUETA=ORIGINAL-운용3, 컨테이너·어댑터 검사 켬, 복제 검사 끔) ⑨ 텔레그램 + DNS 안내.
- `--simular` 실측(운영 정상): 3회 모두 200/22 열림 → 「거부했을 것」 두 줄, 복제 streaming · 지연 15초 · sales max 359777, 변경 0.
- `standby-sync.sh` 는 `PROMOVIDO` 가 있으면 아무것도 안 한다(승격된 api 를 created 로 되돌리지 않게).
  ★ 처음엔 `test -f` 를 sudo 없이 해서 **보호가 안 돌았다**(/opt/ventago 750) — 표식 파일을 실제로 만들어 보고 잡았다.
- 아직: 6 DNS TTL 300(사용자, GoDaddy) · 7 failback · 8 리허설(운영 api 를 멈추고 `--forzar-prod-vivo`, 밤).
- (19:24) **이미지 갱신 경로 실측** — api #1191(0964a70d) 배포 직후 동기화: 첫 시도 `docker compose create` 에 `--no-deps` 가 없어 **재생성 실패**
  (태그만 바뀌고 컨테이너는 옛 이미지) → 옵션 제거 + 「같은 이름·같은 생성 시각이면 다시 안 옮김」 추가. 재실행 39초, api `Created`(ventago_5002) · redis 그대로 정지.
  ★ 「sin cambios」만 시험했으면 첫 배포 때까지 아무도 몰랐다.
