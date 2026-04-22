# vw-agent — Ventago Watcher Agent (M1 MVP)

운영 서버(srv803182) 의 상태를 실시간 감시하고 이상 징후를 Telegram 으로 즉시 알리는 에이전트입니다.
Ventago POS/ERP 본체와 **완전히 독립적으로** 동작하며, 읽기 전용 계정으로만 PG 에 접근해 운영 트래픽에 영향을 주지 않습니다.

---

## 무엇을 감시하는가

M1 에서 구현된 8개 규칙:

| 규칙     | 감지 내용                                                    | Severity   |
| -------- | ------------------------------------------------------------ | ---------- |
| RULE-01  | PG active connection 수 임계 초과 (WARN 250 / CRIT 320)       | warn/crit  |
| RULE-02  | 장시간 실행 쿼리 (≥10s) / idle in transaction (≥30s)          | warn/crit  |
| RULE-03  | PG pool saturation (총 연결 / max_connections ≥ 80% / 95%)    | warn/crit  |
| RULE-04  | Docker 컨테이너 state != running / health=unhealthy / restart 루프 | warn/crit  |
| RULE-05  | 스키마 드리프트 — `column "x" does not exist` 등 로그 패턴    | critical   |
| RULE-06  | 5xx 폭주 — 60초 내 60건 또는 단일 엔드포인트 30건             | critical   |
| RULE-07  | BranchAgent (프린터 에이전트) offline ≥ 5분 + 복귀 알림       | info/warn  |
| RULE-08  | vw-agent 자체 heartbeat (30분 주기, silent 송신)             | info       |

---

## 아키텍처

```
 ┌───────────┐        ┌────────────────┐        ┌───────────────┐
 │ Observers │  ───▶  │  EventBus      │  ───▶  │  Reasoners    │
 │           │        │  (Node EE)     │        │  (8 rules)    │
 │ PgPoller  │        └────────────────┘        └───────┬───────┘
 │ DockerPlr │                                          │
 │ AgentPlr  │                                          ▼
 │ LogTail   │                                 ┌────────────────┐
 └───────────┘                                 │ RuleEngine     │
                                               │  - dedup       │
                                               │  - SQLite      │
                                               │  - Telegram    │
                                               └────────────────┘
```

- **Observers**: PostgreSQL/Docker/BranchAgent polling + api_ventago 로그 tail
  - 로그 tail 은 `docker exec api_ventago tail -F /app/logs/combined-YYYY-MM-DD.log` 방식 (host bind-mount 없음)
- **Reasoners**: 규칙별 평가 로직 (RULE-01 ~ RULE-08)
- **RuleEngine**: 발화 공통 파이프라인 — dedup → SQLite insert → Telegram 비동기 송신
- **Storage**: SQLite (WAL 모드) — events, dedup_keys, heartbeats
- **Notifier**: Telegram Bot API (MarkdownV2)

---

## 안전 원칙 (절대 변경 금지)

1. **PG 연결 최소화**: `max=3` pool (운영 `max_connections=400` 의 0.75%)
2. **read-only 전용 계정**: `ventago_watcher` — SELECT 만 가능, `statement_timeout=3s`
3. **Docker 소켓 접근**: `docker.sock` RW 마운트 (exec 필수), 코드에서 `container.exec(['tail',...])` 외 변경 API 호출 없음
4. **api_ventago 무중단**: 호스트 bind-mount 없이 `docker exec tail -F` 로 로그 스트림만 구독 — api_ventago 는 전혀 건드리지 않음
5. **dedup 기본 15분**: 동일 이슈 반복 알림 방지
6. **리소스 제한**: CPU 0.5 / Memory 256M

---

## 설치 & 실행 (운영 서버)

### 1. 사전 준비

#### 1-1. ventago_watcher 계정 생성

운영 서버(srv803182) 에서:

```bash
# 비밀번호 생성 (openssl)
PG_PW=$(openssl rand -base64 32)
echo "PG_WATCHER_PASSWORD=$PG_PW"  # .env 에 저장할 값

# 호스트 PG 에 계정 생성 (PG10)
sudo -u postgres psql -d ventago \
  -v watcher_pw="'$PG_PW'" \
  -f vw-agent/migrations/001_create_ventago_watcher.sql

# 검증 — 접속 가능 여부
PGPASSWORD=$PG_PW psql -h 127.0.0.1 -U ventago_watcher -d ventago \
  -c "SELECT count(*) FROM pg_stat_activity;"
```

#### 1-2. pg_stat_statements 확장 (선택, M2 부터 필수)

```sql
-- 호스트 PG 에서
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
-- postgresql.conf: shared_preload_libraries = 'pg_stat_statements'  (재시작 필요)
```

#### 1-3. Telegram Bot 준비

1. `@BotFather` 에 `/newbot` → token 수신
2. 봇과 DM 시작 → `https://api.telegram.org/bot<TOKEN>/getUpdates` 호출 → `chat.id` 확인
3. `.env` 의 `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID` 에 저장

### 2. .env 파일 작성

```bash
cd vw-agent
cp .env.example .env
vim .env  # 실제 값 채우기
```

필수 항목:
- `PG_WATCHER_PASSWORD` — 1-1 에서 생성한 값
- `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`
- `DOCKER_GID` — `getent group docker | cut -d: -f3` 결과 (운영 서버: `988`)
- `API_VENTAGO_CONTAINER` — 기본 `api_ventago` (변경 필요 없으면 그대로)

### 3. Docker 로 실행

```bash
docker compose up -d --build
docker compose logs -f vw-agent
```

기동 완료 시 Telegram 에 `🟢 vw-agent 기동 완료` 메시지가 수신됩니다.

### 4. /health 엔드포인트

```bash
curl -s http://localhost:5999/health | jq
```

응답 예:

```json
{
  "status": "ok",
  "uptime_sec": 1847,
  "version": "0.1.0",
  "started_at": "2026-04-22T01:30:00.000Z",
  "pg_pool":  { "total": 2, "idle": 2, "waiting": 0, "max": 3 },
  "sqlite":   { "recent_events": 14, "last_event_at": "...", "last_heartbeat_at": "..." },
  "telegram": { "configured": true },
  "rules":    {
    "RULE-01": { "last_fired_at": "...", "count_24h": 2 },
    "RULE-08": { "last_fired_at": "...", "count_24h": 8 }
  }
}
```

`status=degraded` 조건: `pg_pool.waiting > 0` 또는 `pg_pool.total == 0`.

---

## 로컬 개발

### 사전 준비

```bash
# 로컬 Mac PG (Homebrew PG18) 에 계정 생성
PG_PW=$(openssl rand -base64 32)
psql -U postgres -d ventago \
  -v watcher_pw="'$PG_PW'" \
  -f migrations/001_create_ventago_watcher.sql

# 의존성 설치
npm install

# .env 작성 (로컬용 값)
cp .env.example .env
# PG_HOST=127.0.0.1
# PG_PORT=5432                      # 로컬 Mac PG18
# API_VENTAGO_CONTAINER=            # 로컬에선 비워두면 LogTail 비활성화
```

### 실행

```bash
npm run start:dev       # watch 모드
npm run lint            # ESLint
npm test                # Jest 단위 테스트
npm run build           # nest build → dist/
```

### 스크립트 체인 (CI 용)

```bash
npm ci && npm run lint && npm test && npm run build
```

---

## 프로젝트 구조

```
vw-agent/
├── src/
│   ├── common/              # EventBus, Logger
│   ├── config/              # zod 기반 env 스키마
│   ├── db/                  # PG read-only pool + SQLite
│   ├── notifiers/           # Telegram Bot
│   ├── observers/           # PgPoller, DockerPoller, AgentPoller, LogTail
│   ├── reasoners/           # RuleEngine + 8 rules
│   ├── health/              # /health 컨트롤러
│   └── main.ts              # NestJS 부트스트랩
├── migrations/              # ventago_watcher 계정 생성 SQL
├── Dockerfile               # multi-stage (builder → runtime)
├── docker-compose.yml       # 운영 배포용
├── .env.example             # 환경변수 템플릿
└── package.json
```

---

## 로그 & 데이터 위치

| 대상                | 컨테이너 경로         | 호스트 볼륨                 |
| ------------------- | ---------------------- | --------------------------- |
| SQLite (events/dedup) | `/app/data/vw-agent.db` | `vw-agent-data` (named vol) |
| Winston 로그        | `/app/logs/*.log`       | `vw-agent-logs` (named vol) |
| api_ventago 로그    | `docker exec tail -F`   | 없음 (stream)               |

재기동 시 `dedup_keys` 와 `events` 는 보존되므로 동일 이슈 반복 알림이 방지됩니다.

### SQLite 수동 조회

```bash
docker compose exec vw-agent sh -c "sqlite3 /app/data/vw-agent.db 'SELECT rule_id, severity, title, created_at FROM events ORDER BY id DESC LIMIT 20'"
```

---

## 트러블슈팅

### "Docker 소켓 미존재 — DockerPoller 비활성화"
- `/var/run/docker.sock` bind-mount 확인. 로컬 Mac 이면 정상 (RULE-04 만 비활성화됨).

### "permission denied while trying to connect to the Docker daemon socket"
- `DOCKER_GID` 가 호스트 docker 그룹 GID 와 일치하는지 확인:
  ```bash
  getent group docker | cut -d: -f3
  ```

### "PG_WATCHER_PASSWORD 는 최소 8자"
- `.env` 에 PG_WATCHER_PASSWORD 가 비어있거나 짧음. `openssl rand -base64 32` 로 생성.

### Telegram 403 Forbidden
- 봇이 사용자와 DM 을 시작한 적 없음. 봇에 `/start` 를 먼저 보내세요.

### pg_pool.waiting > 0 지속
- query pattern 이 예상보다 오래 걸림. `pg_stat_activity` 에서 `vw-agent-watcher` application_name 쿼리 확인.

---

## 로드맵

이 M1 은 MVP 입니다. 전체 로드맵은 `docs/ai-watcher/roadmap-ai-watcher.md` 를 참고하세요.

| Milestone | 범위 |
| --- | --- |
| M1 (현재) | 8개 규칙 + Telegram 알림 + SQLite dedup |
| M2 | LLM advisor — 알림에 "원인 분석 + 조치 제안" 추가 |
| M3 | Telegram 승인 버튼 (`/restart api_ventago` 등) |
| M4 | Postgres tuning advisor (pg_stat_statements 기반) |
| M5 | Web dashboard (이벤트 타임라인, 규칙 ON/OFF) |
| M6 | 다점포/다서버 수평 확장 |

---

## License

UNLICENSED — 내부 전용
