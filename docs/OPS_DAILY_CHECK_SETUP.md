# 일일 운영 점검 설치 가이드 (Phase 75 W1)

디스크·DB·백업·커넥션·소켓을 매일 수집해 **추세**를 보고, 임계를 넘을 때만 Telegram 으로 알린다.
기존 감시(`uptime-watchdog.sh` = 살아 있는가, 500 알람 = 지금 에러가 났는가)는 **"지금 이 순간"만** 본다.
디스크는 어느 날 갑자기 차지 않는다 — 며칠에 걸쳐 차오르다 마지막 하루에 서비스를 멈춘다.

## 구성

| 파일 | 위치 | 역할 |
|---|---|---|
| `scripts/ops-daily-check.py` | 서버 (postgres 유저) | 수집 · JSONL 누적 · 임계 판정 · Telegram |
| `tools/backup-freshness-watchdog.sh` | **Mac** (launchd) | 백업·리포트 부재 감지 — 서버가 죽으면 서버 안 감시도 죽으므로 |
| `tools/com.ventago.backup-freshness.plist` | Mac | 1시간 주기 등록 |

**상호 감시** — Mac 워치독은 "서버 백업이 도는가"를 보고, 서버 점검은 "Mac 워치독이 살아 있는가"(heartbeat)를 본다.
한쪽이 죽으면 다른 쪽이 알린다. 2026-08-06 에 launchd 4개가 조용히 죽어 있던 사고의 직접적 대응이다.

### 앱 로그 volume (2026-08-06 추가 — Phase 75 W0-8)

| 호스트 경로 | 컨테이너 | 무엇이 남는가 |
|---|---|---|
| `/var/lib/ventago-logs/app` | `ventagoapp:/app/logs` | `perf-*.log` (route timing · Web Vitals) — **p95 기준선의 원본** |
| `/var/lib/ventago-logs/api` | `api_ventago:/app/logs` | `combined-*.log` · `error-*.log` — 느린 쿼리 등 진단 근거 |

**이전에는 volume 이 없어 배포마다 통째로 사라졌다.** 그래서 p95 기준선이 축적되지 않았고,
Phase 75 W4 전제의 원본 로그(`combined-2026-07-29.log`)도 이미 소실돼 사후 규명이 불가능했다.

정의는 **각 저장소의 `docker-compose.yml` 에 커밋**돼 있다. 서버에서 손으로 고치면 다음 배포가 덮어쓴다.
디렉터리는 없으면 docker 가 root:root 755 로 만든다 — 일일 점검(postgres 유저)이 읽을 수 있어야 하므로
권한을 더 좁히지 않는다.

> **읽을 때 주의 — 하루의 경계는 UTC 다.** 서버 타임존이 UTC 라 `perf-YYYY-MM-DD.log` 는
> UTC 자정에 회전하고, 그 시각은 **아르헨티나 21:00** 이다. 즉 "전일 p95" 는
> 현지 기준 21:00~21:00 구간이며, 하루 영업이 두 파일에 걸쳐 나뉜다.
> 일별 값을 영업일과 1:1 로 읽으면 어긋난다 — 추세로 보는 것이 안전하다.

## 설계 원칙

- **JSONL 파일, DB 테이블 아님** — DB 가 아플 때도 기록이 남아야 하고, 그때가 가장 중요한 순간이다
- **pgbouncer(5432) 우회, PG 5434 직결, 커넥션 1개** — 앱 pool 예산에 영향 없음 (`pg_dump` 와 같은 방식)
- **성공 침묵** — 임계 위반 시에만 즉시 알림. 매일 오는 "정상" 알림은 곧 무시되고, 무시되는 알람은 진짜 사고도 함께 묻는다
- **절대값 + 변화율 + 소진 예측** — 70% 알람은 "지금 문제"를, 소진 예측은 **"언제까지 조치해야 하는가"**를 알려준다
- **알림 경로 재사용** — `tools/uptime-watchdog.sh` 의 `.uptime.env` 를 그대로 쓴다. 새 채널을 만들지 않는다

## 임계값

| 조건 | 등급 |
|---|---|
| 디스크 사용률 > 70% | 경고 |
| 디스크 사용률 > 85% | 긴급 |
| 하루 증분 > 10GB | 경고 |
| 소진 예측 < 30일 | 경고 (< 7일이면 긴급) |
| 백업 mtime > 26h | 긴급 |
| 복제 슬롯 비활성 (Phase 74) | 긴급 — WAL 축적 → 디스크 폭발 경로 |
| 슬롯 lag > `max_slot_wal_keep_size` × 70% | 경고 — PITR 연속성 상실 임박 |
| pgbouncer `cl_waiting` > 0 | 경고 |
| autovacuum 지연 의심 테이블 존재 | 경고 |
| 테이블 주간 2배 이상 증가 | 경고 |
| **Mac 워치독 heartbeat > 26h** | **긴급** — 외부 감시 사망 |
| **launchd 에이전트 미등록** | **긴급** — 감시기가 꺼져 있음 (Mac 측 판정) |

---

## ★ 설치 전 확인 — launchd 경로 (2026-08-06 조치 완료)

> **완료됨.** 아래는 이력이자 재발 시 대응 절차다. 저장소를 다시 옮기면 같은 일이 반복된다.
>
> 2026-08-06 실측에서 `launchctl list | grep ventago` 가 **비어 있었다** — 경로만 깨진 게 아니라
> 등록 자체가 해제된 상태였고, **서버가 죽어도 아무도 모르는 상태**였다.
> 경로 교정 + 5개 재등록 완료(exit code 전부 0), Telegram 수신까지 실증했다.

저장소가 `/Users/marcoskim/Trabajos_Programming/ACE_online_1.0` → `/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0`
로 이동했는데, **기존 plist 4개가 아직 옛 경로를 가리킨다.**

```
tools/com.ventago.uptime-watchdog.plist:11
tools/com.ventago.trello-sync.plist:11
tools/com.ventago.agent-runner.plist:11
tools/com.ventago.git-fetch-notify.plist:11
tools/git-fetch-notify.sh:7
```

옛 경로가 없으면 **외부 uptime 감시가 조용히 죽어 있다.**
(`.planning/trello-inbox/` 리포트 여러 건이 "동기화 복구 필요"를 반복 기록하는 것도 같은 원인일 수 있다.)

```bash
ls -d /Users/marcoskim/Trabajos_Programming/ACE_online_1.0 2>/dev/null \
  || echo "옛 경로 없음 → launchd 4개 전부 죽어 있음"
launchctl list | grep ventago
tail -5 /tmp/ventago-uptime-watchdog.log
```

옛 경로가 없으면 먼저 고친다.

```bash
cd /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
sed -i '' 's|/Users/marcoskim/Trabajos_Programming/ACE_online_1.0|/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0|g' \
  tools/com.ventago.*.plist tools/git-fetch-notify.sh

for p in uptime-watchdog trello-sync agent-runner git-fetch-notify; do
  launchctl unload ~/Library/LaunchAgents/com.ventago.$p.plist 2>/dev/null
  cp tools/com.ventago.$p.plist ~/Library/LaunchAgents/
  launchctl load ~/Library/LaunchAgents/com.ventago.$p.plist
done
launchctl list | grep ventago
```

---

## 1단계 — 서버에 수집기 배치

```bash
cd /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0

scp scripts/ops-daily-check.py jhkim@62.72.7.245:/tmp/

ssh jhkim-server "
  sudo mkdir -p /var/lib/postgresql/ops-metrics
  sudo mv /tmp/ops-daily-check.py /var/lib/postgresql/ops-metrics/
  sudo chown -R postgres:postgres /var/lib/postgresql/ops-metrics
  sudo chmod +x /var/lib/postgresql/ops-metrics/ops-daily-check.py
"
```

## 2단계 — Telegram 자격증명 배치

`uptime-watchdog.sh` 가 쓰는 것과 **같은 값**이다. 서버 `.env` 에서 복사한다.

```bash
ssh jhkim-server "
  sudo -u postgres tee /var/lib/postgresql/ops-metrics/.uptime.env >/dev/null <<'EOF'
TELEGRAM_BOT_TOKEN=여기에_토큰
TELEGRAM_CHAT_ID=여기에_챗ID
EOF
  sudo chmod 600 /var/lib/postgresql/ops-metrics/.uptime.env
"
```

## 3단계 — dry-run (알림 미발송, 기록 미기록)

**반드시 먼저 돌린다.** 수집이 되는지, 임계 판정이 말이 되는지 눈으로 본다.

```bash
ssh jhkim-server "sudo -u postgres python3 /var/lib/postgresql/ops-metrics/ops-daily-check.py --dry-run"
```

확인 항목:

- 디스크 사용률·DB 크기·백업 나이·상위 테이블이 채워지는가
- **`🔌 pgbouncer 대기` 줄이 아예 안 보이면 접속 실패다** (아래 2-1 참조).
  **`cl_waiting` 은 G1 게이트의 유일한 근거라 이게 없으면 W7 판정이 성립하지 않는다.**
- `🔗 API 연결 0` 은 야간에는 정상이다 — 실제 유휴다. **영업시간에 한 번 더 확인**해야 의미가 있다
- 판정 결과가 비어 있으면 정상 (성공 침묵)

### 2-1단계 — pgbouncer stats 접속 (2026-08-06 실측 반영)

pgbouncer 는 **unix socket 없이 TCP 로만** 뜨고(`listen_addr = *`, `auth_type = md5`),
admin 계정 `pgbouncer` 가 아니라 `pgbouncer.ini` 의 **`stats_users = coolsistema,postgres`** 만
`SHOW POOLS` 를 볼 수 있다. `postgres` 의 평문 비밀번호는 없으므로 `coolsistema` 로 붙는다.

```bash
ssh jhkim-server '
PW=$(sudo docker inspect api_ventago --format "{{range .Config.Env}}{{println .}}{{end}}" \
     | grep "^DATABASE_PASSWORD=" | cut -d= -f2-)
sudo -u postgres bash -c "umask 077; printf \"127.0.0.1:5432:pgbouncer:coolsistema:%s\n\" \"$PW\" > ~/.pgpass"
sudo -u postgres psql -h 127.0.0.1 -p 5432 -U coolsistema -d pgbouncer -c "SHOW POOLS;" | head -3
'
```

접속 정보가 바뀌면 `OPS_PGB_HOST` / `OPS_PGB_PORT` / `OPS_PGB_USER` 로 덮어쓸 수 있다.

## 4단계 — 크론 등록

기존 백업 03:17 · 업로드 03:40 뒤인 **04:10** 에 돈다(백업 결과까지 반영해서 보기 위해).

```bash
ssh jhkim-server "sudo -u postgres bash -c '(crontab -l; echo \"10 4 * * * python3 /var/lib/postgresql/ops-metrics/ops-daily-check.py >/dev/null 2>&1\") | crontab -'"
ssh jhkim-server "sudo -u postgres crontab -l"
```

주간 요약은 **일요일에 자동**으로 함께 나간다(별도 크론 불필요).

## 5단계 — JSONL 을 Dropbox 업로드에 추가

시계열이 서버에만 있으면 서버와 함께 사라진다.

```bash
ssh jhkim-server "sudo -u postgres sed -i \
  's|--include \"globals_\\*.sql.gz\" \\\\|--include \"globals_*.sql.gz\" \\\\\\n    --include \"daily.jsonl\" \\\\|' \
  /var/lib/postgresql/pg_backups/dropbox_sync.sh"
```

수동 편집이 안전하다 — `dropbox_sync.sh` 의 `rclone copy` 에
`--include "daily.jsonl"` 를 추가하고 `BACKUP_DIR` 대신 두 디렉터리를 각각 올리도록 한다.

## 6단계 — Mac 부재 감지 등록

```bash
cd /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
chmod +x tools/backup-freshness-watchdog.sh

# .uptime.env 가 tools/ 에 있는지 확인 (uptime-watchdog 과 공유)
ls -l tools/.uptime.env

./tools/backup-freshness-watchdog.sh          # 수동 1회 — OK 가 나와야 한다

cp tools/com.ventago.backup-freshness.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.ventago.backup-freshness.plist
launchctl list | grep backup-freshness
```

---

## 검증 (W1 게이트)

| # | 확인 | 방법 |
|---|---|---|
| 1 | JSONL 일 1행 누적 | `ssh jhkim-server "sudo -u postgres wc -l /var/lib/postgresql/ops-metrics/daily.jsonl"` |
| 2 | 디스크 임계 알림 | 임시로 `DISK_PCT_WARN` 을 현재값 아래로 낮춰 1회 실행 → Telegram 도착 확인 → 원복 |
| 3 | 백업 부재 알림 | Mac 에서 `STALE_HOURS=0 ./tools/backup-freshness-watchdog.sh` |
| 4 | 소진 예측 산출 | 이력 2일 이상 쌓인 뒤 `--dry-run` 출력에 "N일 후 소진" 표시 |
| 5 | 주간 요약 | `--weekly --dry-run` |
| 6 | **소음 없음** | **정상 운영 7일간 즉시 알림 0건.** 소음이 나면 임계를 조정한다 |
| 7 | pool 무영향 | 실행 전후 `SHOW POOLS` 의 `cl_waiting` 변화 없음 |
| 8 | **에이전트 사망 감지** | `launchctl unload ~/Library/LaunchAgents/com.ventago.trello-sync.plist` 후 `./tools/backup-freshness-watchdog.sh` → 알림 → 다시 load |
| 9 | **heartbeat 상호 감시** | 서버에서 `mac-watchdog.heartbeat` 삭제 후 `--dry-run` → CRIT 판정 |

**6번을 통과할 때까지 W1 을 완료로 표시하지 않는다.**
임계를 너무 민감하게 잡으면 알람이 소음이 되고, 소음이 된 알람은 진짜 사고도 함께 묻는다.

## 문제 시

```bash
ssh jhkim-server "sudo -u postgres tail -30 /var/lib/postgresql/ops-metrics/ops-daily-check.log"
tail -30 /tmp/ventago-backup-freshness.log
```
