# SPEC: AI Watcher — Milestone 1 (MVP 감시 + 알림)

생성일: 2026-04-21
작성자: Marcos.J.Kim + Claude
관련 문서: `docs/ai-watcher/roadmap.md`
이전 단계: 없음 (최초 Milestone)
다음 단계: M2 (LLM 판단 추가)

---

## 목표

Ventago 운영 서버의 위험·장애 신호를 수집해 **Telegram 으로 알림만** 보내는 최소 기능 제품(MVP)을 구축한다.
M1 은 "알림 정확도 튜닝" 에 집중하며, 승인/실행 기능(M3)과 LLM 분석(M2)은 포함하지 않는다.

---

## 배경 및 컨텍스트

### 운영 환경
- **서버:** KVM 8 VPS — 8 코어 / 32 GB RAM / 400 GB 디스크 (srv803182 / 62.72.7.245)
- **PostgreSQL 10:** 호스트 OS 에 직접 설치 (Docker 아님), DB명 `ventago`, owner `coolsistema`
- **Ventago 스택:** Docker 컨테이너 3종 (api_ventago:5002, ventago-app:5001, dbpostgres-내부용)
- **Sequelize pool (api-ventago 실측):** 인스턴스당 max=80, 2 인스턴스 시 총 160 사용, PG max_connections=300 가정

### 실측 장애 패턴 (logs/error-2026-04-20 ~ 21 분석)
M1 감지 규칙 설계의 근거가 된 실제 로그 패턴:
- `column Envio.priority does not exist` — Sequelize 모델과 운영 DB 스키마 불일치
- `column p.cost_price does not exist` — 마이그레이션 미적용 상태로 배포
- `relation "product_branches" does not exist` — 누락된 테이블
- `column "pin_hash" does not exist` — talleres 기능 배포 사고
- `column "use_variants" does not exist` — `/me` 엔드포인트 전체 500 에러, 모든 로그인 사용자 영향
- `subquery uses ungrouped column` / `missing FROM-clause entry` — 런타임 SQL 오류

→ M1 은 이런 패턴을 **배포 직후 5분 내** 에 탐지하는 것이 핵심 가치.

### 기존 자원 활용
- Winston DailyRotateFile: `api-ventago/logs/error-YYYY-MM-DD.log` (tail 대상)
- BranchAgent 테이블: `isOnline`, `lastSeenAt` (에이전트 오프라인 감지)
- PostgreSQL `pg_stat_activity`, `pg_stat_statements` (pool / slow query)
- Docker 소켓 `/var/run/docker.sock` (컨테이너 health)

---

## 기술 스택

- **언어/프레임워크:** Node.js 20 LTS + TypeScript 5 + NestJS 11 (Ventago 와 동일 스택, 학습비용 0)
- **DB (vw-agent 자체용):** SQLite 3 (better-sqlite3) — 이벤트/알림 이력 저장
- **PG 접근:** `pg ^8.13.1` — 운영 PG 에 read-only pool (max=3) 로만 접근
- **Telegram:** `node-telegram-bot-api ^0.66` (long polling, webhook 불필요)
- **Docker 제어:** `dockerode ^4` (컨테이너 health 조회)
- **로그 수집:** `chokidar` (파일 watcher) + tail-by-line
- **스케줄링:** `@nestjs/schedule` — 주기 감지 루프
- **로깅:** `winston` + `winston-daily-rotate-file` (vw-agent 자체 로그)
- **ESLint 설정:** api-ventago 와 동일 규칙 복사 (`newline-before-return`, `lines-around-comment`, `no-unused-vars` 엄격)

### 주요 라이브러리 버전 고정
```json
{
  "@nestjs/core": "^11.0.0",
  "@nestjs/schedule": "^4.0.0",
  "pg": "^8.13.1",
  "better-sqlite3": "^11.0.0",
  "node-telegram-bot-api": "^0.66.0",
  "dockerode": "^4.0.0",
  "chokidar": "^3.6.0",
  "winston": "^3.19.0",
  "winston-daily-rotate-file": "^5.0.0"
}
```

---

## 디렉토리 구조

```
ACE_online_1.0/
└── vw-agent/                          # 신규 워크스페이스 추가 (npm workspaces)
    ├── Dockerfile
    ├── docker-compose.yml
    ├── .env.example
    ├── package.json
    ├── tsconfig.json
    ├── .eslintrc.js                   # api-ventago 복사
    ├── nest-cli.json
    ├── migrations/
    │   └── 001_create_watcher_role.sql  # PG read-only 계정 생성
    ├── src/
    │   ├── main.ts
    │   ├── app.module.ts
    │   ├── common/
    │   │   ├── logger/
    │   │   │   └── logger.config.ts
    │   │   ├── db/
    │   │   │   ├── pg-readonly.provider.ts   # max=3 pool, statement_timeout=3s
    │   │   │   └── sqlite.provider.ts
    │   │   └── config/
    │   │       └── config.schema.ts          # .env 검증 (zod)
    │   ├── observer/                  # 감시 규칙 8종
    │   │   ├── observer.module.ts
    │   │   ├── rules/
    │   │   │   ├── rule-01-pg-pool.ts
    │   │   │   ├── rule-02-slow-query.ts
    │   │   │   ├── rule-03-pg-lock.ts
    │   │   │   ├── rule-04-docker-health.ts
    │   │   │   ├── rule-05-log-pattern.ts
    │   │   │   ├── rule-06-log-rate.ts
    │   │   │   ├── rule-07-agent-offline.ts
    │   │   │   └── rule-08-heartbeat.ts
    │   │   └── log-tail.service.ts
    │   ├── reasoner/
    │   │   ├── reasoner.module.ts
    │   │   ├── rule-engine.service.ts         # 규칙 매칭
    │   │   └── dedup.service.ts               # 중복 알림 억제
    │   ├── notifier/
    │   │   ├── notifier.module.ts
    │   │   ├── telegram.service.ts            # Bot + sendMessage only
    │   │   └── templates.ts                   # 알림 메시지 포맷
    │   └── storage/
    │       └── event-log.service.ts           # SQLite 이벤트 저장
    ├── test/
    │   └── rules/
    │       └── rule-05-log-pattern.spec.ts    # 샘플 단위 테스트
    └── logs/                          # vw-agent 자체 Winston 로그
```

### 왜 별도 워크스페이스 (`vw-agent/`)?
- Ventago 모노레포 (npm workspaces) 규칙을 따르면서도 독립 배포 가능
- 기존 `api-ventago` 변경 없이 추가만 → 기존 시스템에 영향 0
- 루트 `package.json` 에 `"vw-agent"` 추가만 필요

---

## 감지 규칙 상세 (8종)

각 규칙은 `src/observer/rules/rule-NN-*.ts` 에 구현. 각 규칙은 아래 인터페이스 준수:

```typescript
interface WatcherRule {
  id: string;                    // 'pg-pool-high' 등
  severity: 'warn' | 'critical';
  cooldownSec: number;           // 동일 알림 억제 시간
  check(): Promise<RuleEvent | null>;
}
```

### RULE-01: PG pool 사용률 임계치
- **신호:** `pg_stat_activity` 에서 `application_name ILIKE '%ventago%'` 연결 수
- **임계치:** 활성 연결 수가 max(160)의 80% = 128 이상, 5분 지속
- **쿼리:** `SELECT count(*) FROM pg_stat_activity WHERE datname='ventago' AND application_name NOT ILIKE '%watcher%';`
- **Cooldown:** 15분
- **Severity:** warn → 활성 160+ 도달 시 critical

### RULE-02: Slow query 빈도
- **신호:** `pg_stat_statements` 의 `mean_exec_time > 1000ms` 항목 중 최근 1분 호출 > 5
- **사전 조건:** `pg_stat_statements` extension 설치 필요. 미설치 시 규칙 비활성 + 설치 권장 알림 1회.
- **Cooldown:** 10분

### RULE-03: PG lock 대기
- **신호:** `pg_locks` JOIN `pg_stat_activity`, `state='active'` 상태에서 `wait_event_type='Lock'` 10초 이상 지속
- **쿼리:**
  ```sql
  SELECT pid, now() - query_start AS wait_time, query
  FROM pg_stat_activity
  WHERE wait_event_type='Lock' AND now() - query_start > interval '10 seconds';
  ```
- **Cooldown:** 5분

### RULE-04: Docker 컨테이너 health
- **신호:** `dockerode.listContainers()` 에서 `api_ventago`, `ventago-app`, `dbpostgres` (있을 경우) 의 State.Health.Status
- **트리거:** Status != 'healthy' 또는 컨테이너 자체가 running 상태 아님
- **Cooldown:** 1분 (짧게 — 즉시 알리고 빠른 회복 감지)

### RULE-05: 로그 패턴 감지 — 스키마 불일치
- **신호:** `api-ventago/logs/error-YYYY-MM-DD.log` 최신 파일 tail
- **패턴 (정규식):**
  - `column "?[\w.]+"? does not exist`
  - `relation "?[\w.]+"? does not exist`
  - `missing FROM-clause entry`
  - `subquery uses ungrouped column`
- **트리거:** 패턴 1회라도 매칭 → 즉시 critical 알림
- **근거:** 실측 로그에서 `pin_hash`, `use_variants`, `product_branches`, `cost_price`, `Envio.priority` 등이 배포 직후 발생 → 분 단위 감지가 필수
- **Cooldown:** 10분 (동일 패턴)

### RULE-06: 에러 로그 발생률
- **신호:** 동일 로그 파일에서 분당 `[error]` 태그 카운트
- **트리거:** 분당 10건 초과
- **Cooldown:** 10분
- **Severity:** warn

### RULE-07: BranchAgent 오프라인
- **신호:** `SELECT label, last_seen_at FROM branch_agents WHERE is_online = false AND last_seen_at > now() - interval '1 day';`
- **트리거:** `last_seen_at` 이 10분 이상 오래됨
- **Cooldown:** 30분 (같은 에이전트)
- **Severity:** warn

### RULE-08: Dead-man heartbeat
- **목적:** watcher 자신이 죽어도 감지 가능하도록
- **구현:** 매 5분마다 Telegram 에 **보이지 않는 heartbeat** 전송 (특수 채널 또는 `silent: true` 메시지)
- **외부 감지:** 별도 채널(예: UptimeRobot 무료 티어) 이 watcher 의 `/health` 엔드포인트를 5분 간격 ping, 10분 연속 실패 시 Marcos 에게 SMS/이메일
- **M1 범위:** Telegram silent heartbeat 만 구현 (UptimeRobot 연동은 M2 로 이월)

---

## Telegram 메시지 포맷

```
🚨 [CRITICAL] PG 스키마 불일치 감지
━━━━━━━━━━━━━━━━━━━━━━
규칙: rule-05-log-pattern
패턴: column "use_variants" does not exist
최근 10분 발생: 47회

📍 영향 엔드포인트:
  GET /api/auth/me

📄 로그 샘플:
  2026-04-20 19:23:56 [error] [AuthService] [ME] ...
  (logs/error-2026-04-20.log:1523)

💡 추정 원인 (M2에서 LLM 분석 추가 예정):
  마이그레이션 미적용 배포 — use_variants
  컬럼이 모델에는 있으나 DB 에 없음

🕒 감지 시각: 2026-04-21 14:32:10 -03
```

- 아이콘: 🚨 CRITICAL / ⚠️ WARN / 💚 RECOVERY / 💗 HEARTBEAT (silent)
- 모두 Markdown V2 포맷, 최대 4096자 제한 준수

---

## PostgreSQL 안전 규칙 (반드시 준수)

### 1. 독립 Read-Only 계정 생성

`migrations/001_create_watcher_role.sql`:
```sql
-- vw-agent 전용 read-only 계정
CREATE ROLE ventago_watcher WITH LOGIN PASSWORD '<STRONG_PASSWORD>';

-- ventago DB 연결 + public 스키마 USAGE
GRANT CONNECT ON DATABASE ventago TO ventago_watcher;
GRANT USAGE ON SCHEMA public TO ventago_watcher;

-- 필요한 테이블만 SELECT (화이트리스트)
GRANT SELECT ON TABLE branch_agents TO ventago_watcher;

-- pg_stat_* 는 기본적으로 일반 사용자도 접근 가능 (본인 쿼리만)
-- 전체 보려면 pg_monitor 역할 필요:
GRANT pg_monitor TO ventago_watcher;

-- statement_timeout 강제 — watcher 쿼리가 운영에 영향 주지 않도록
ALTER ROLE ventago_watcher SET statement_timeout = '3s';
ALTER ROLE ventago_watcher SET idle_in_transaction_session_timeout = '5s';
ALTER ROLE ventago_watcher SET application_name = 'vw-agent-watcher';
```

### 2. Pool 설정 (vw-agent 쪽)
```typescript
// src/common/db/pg-readonly.provider.ts
import { Pool } from 'pg';

// vw-agent 전용 read-only pool — 운영 Ventago pool 과 완전 분리
export const pgReadOnlyPool = new Pool({
  host: process.env.PG_HOST,           // host.docker.internal (Docker 에서 호스트 PG 접근)
  port: parseInt(process.env.PG_PORT || '5432', 10),
  user: 'ventago_watcher',             // 전용 계정
  password: process.env.PG_WATCHER_PASSWORD,
  database: 'ventago',
  max: 3,                              // 최대 3 연결 (운영 pool max=80*2=160 과 완전 분리)
  min: 1,
  idleTimeoutMillis: 30_000,           // 30초 idle → release
  connectionTimeoutMillis: 5_000,      // 5초 내 연결 못 하면 에러
  application_name: 'vw-agent-watcher',
  statement_timeout: 3_000,            // 서버측 설정과 이중 안전망
});

// 프로세스 종료 시 반드시 pool 닫기
process.on('SIGTERM', async () => {
  await pgReadOnlyPool.end();
});
```

### 3. 쿼리 실행 규칙 — 반드시 `pool.query()` 사용 (자동 release)
```typescript
// ✅ 권장: pool.query() — 자동 release
const { rows } = await pgReadOnlyPool.query(
  'SELECT count(*) FROM pg_stat_activity WHERE datname = $1',
  ['ventago']
);

// ❌ 금지: pool.connect() 후 release 누락 위험
```

### 4. 트랜잭션 금지
M1 의 모든 쿼리는 SELECT 만 수행. BEGIN/COMMIT 사용 금지.

---

## 환경 변수 (`.env.example`)

```env
# 운영 서버 PostgreSQL (host.docker.internal 경유)
PG_HOST=host.docker.internal
PG_PORT=5432
PG_WATCHER_PASSWORD=<migrations/001 에서 생성한 비밀번호>

# vw-agent 자체 SQLite 경로
SQLITE_PATH=/app/data/watcher.sqlite

# Telegram Bot
TELEGRAM_BOT_TOKEN=<BotFather 에서 발급>
TELEGRAM_CHAT_ID=<알림 받을 chat_id 또는 group_id>
TELEGRAM_HEARTBEAT_CHAT_ID=<heartbeat 전용 chat_id, 동일 가능>

# Ventago 로그 경로 (Docker volume mount)
VENTAGO_LOGS_PATH=/ventago-logs

# Docker 소켓 (health check 용)
DOCKER_SOCKET=/var/run/docker.sock

# 루프 주기
OBSERVER_INTERVAL_MS=30000    # 30초마다 규칙 검사
HEARTBEAT_INTERVAL_MS=300000  # 5분마다 heartbeat

# 로깅
LOG_LEVEL=info
TZ=America/Argentina/Buenos_Aires
```

---

## docker-compose.yml (vw-agent 전용)

```yaml
version: '3.9'
services:
  vw-agent:
    build: .
    image: ventago-watcher:latest
    container_name: vw_agent
    restart: unless-stopped
    mem_limit: 512m
    cpus: 0.5
    env_file: .env
    extra_hosts:
      - "host.docker.internal:host-gateway"   # 호스트 PG 접근
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro  # Docker health 조회 (ro)
      - ../api-ventago/logs:/ventago-logs:ro          # Ventago 로그 read-only mount
      - ./data:/app/data                              # SQLite 저장
      - ./logs:/app/logs                              # vw-agent 자체 로그
    networks:
      - ventago
    healthcheck:
      test: ["CMD", "node", "-e", "require('http').get('http://127.0.0.1:9876/health', r => process.exit(r.statusCode === 200 ? 0 : 1))"]
      interval: 60s
      timeout: 5s
      retries: 3
    ports:
      - "127.0.0.1:9876:9876"   # 외부 노출 금지 (localhost bind)

networks:
  ventago:
    external: true
```

---

## 태스크 목록

### 준비 (Marcos 가 직접 수행)
- [ ] TASK-P1: Telegram Bot 생성 (@BotFather) 및 token / chat_id 확보
- [ ] TASK-P2: 운영 서버 SSH 로 PG `max_connections` / `pg_stat_statements` 설치 여부 확인
- [ ] TASK-P3: `ventago_watcher` 비밀번호 생성 (openssl rand -base64 32)

### 구현 (Claude 가 수행, Execute 단계)
- [ ] TASK-1: npm workspace 추가 — 루트 `package.json` 에 `vw-agent` 추가 + `vw-agent/package.json` 생성
- [ ] TASK-2: NestJS 프로젝트 스캐폴딩 (`main.ts`, `app.module.ts`, tsconfig, eslint 복사)
- [ ] TASK-3: `common/logger` 설정 — api-ventago 와 동일 패턴
- [ ] TASK-4: `common/config` — zod 로 env 검증
- [ ] TASK-5: `common/db/pg-readonly.provider.ts` — pool max=3 구현 + 싱글턴 + release 검증
- [ ] TASK-6: `common/db/sqlite.provider.ts` — better-sqlite3 + 마이그레이션
- [ ] TASK-7: `storage/event-log.service.ts` — 이벤트/알림 SQLite 기록
- [ ] TASK-8: `observer/log-tail.service.ts` — chokidar 로 Winston 로그 파일 tail
- [ ] TASK-9: `observer/rules/rule-01-pg-pool.ts`
- [ ] TASK-10: `observer/rules/rule-02-slow-query.ts` (pg_stat_statements 확인 포함)
- [ ] TASK-11: `observer/rules/rule-03-pg-lock.ts`
- [ ] TASK-12: `observer/rules/rule-04-docker-health.ts`
- [ ] TASK-13: `observer/rules/rule-05-log-pattern.ts` — 정규식 패턴 5종
- [ ] TASK-14: `observer/rules/rule-06-log-rate.ts`
- [ ] TASK-15: `observer/rules/rule-07-agent-offline.ts`
- [ ] TASK-16: `observer/rules/rule-08-heartbeat.ts`
- [ ] TASK-17: `reasoner/rule-engine.service.ts` — 모든 규칙 스케줄 실행
- [ ] TASK-18: `reasoner/dedup.service.ts` — cooldown 관리
- [ ] TASK-19: `notifier/telegram.service.ts` — sendMessage, error 재시도
- [ ] TASK-20: `notifier/templates.ts` — 알림 포맷 템플릿
- [ ] TASK-21: `/health` HTTP 엔드포인트 (NestJS 기본 Terminus 활용)
- [ ] TASK-22: `migrations/001_create_watcher_role.sql`
- [ ] TASK-23: `Dockerfile` (multi-stage: builder + runner, alpine)
- [ ] TASK-24: `docker-compose.yml`
- [ ] TASK-25: `.env.example`
- [ ] TASK-26: `README.md` (배포 순서 가이드)
- [ ] TASK-27: 단위 테스트 1종 — rule-05 정규식 패턴 검증
- [ ] TASK-28: ESLint 전체 검증 (오류 0)
- [ ] TASK-29: TypeScript 빌드 성공 확인 (`npm run build`)
- [ ] TASK-30: 로컬 실행 테스트 — 더미 로그로 rule-05 발화 확인

### 배포 (Marcos + Claude 공동)
- [ ] TASK-D1: 운영 서버에 `ventago_watcher` 계정 생성 (migrations/001 실행)
- [ ] TASK-D2: 운영 서버에 vw-agent 디렉토리 업로드 (`rsync` 또는 `./push-both.sh` 확장)
- [ ] TASK-D3: `.env` 설정 후 `docker compose up -d`
- [ ] TASK-D4: Telegram 에서 heartbeat 및 테스트 알림 수신 확인
- [ ] TASK-D5: 1주일 관측 — 오탐률 측정 후 M2 진행 여부 결정

---

## 완료 기준

- [ ] 8종 규칙 모두 단위 테스트 또는 수동 재현 테스트 통과
- [ ] ESLint 오류 0개
- [ ] TypeScript strict 모드 통과
- [ ] Docker 이미지 빌드 성공 (< 300MB)
- [ ] 운영 서버 배포 후 24시간 무중단 가동
- [ ] 배포 후 24시간 내 최소 1건의 실제 이벤트 감지 (로그 분석 기준, 현재 환경에서 일일 수건의 500 에러 발생 중이므로 쉬움)
- [ ] Marcos 의 Telegram 에 heartbeat 이 5분 간격으로 수신됨
- [ ] vw-agent 의 PG 연결이 3개 이하로 유지됨 (`pg_stat_activity` 확인)

---

## 금지사항 / 주의사항

### 절대 금지
- **Ventago 운영 DB 에 INSERT/UPDATE/DELETE/DDL 실행 금지.** vw-agent 는 read-only.
- **운영 Ventago pool 에 합류 금지.** 반드시 `ventago_watcher` 계정 + 독립 pool 사용.
- **Telegram token 을 git 에 커밋 금지.** `.env` 는 `.gitignore` 포함.
- **M1 에서는 LLM API 호출 없음.** 비용과 추가 리스크 방지.
- **M1 에서는 명령 실행 기능 없음.** Telegram 메시지에 버튼도 없음. 알림만.

### 주의
- Docker 소켓 mount 는 `:ro` (read-only) 필수 — 실수로 컨테이너 조작 방지.
- Ventago 로그 디렉토리 mount 도 `:ro`.
- vw-agent 가 죽어도 Ventago 영향 0 이어야 함 — 의존성 역방향 금지.
- Telegram rate limit (초당 30 메시지, 그룹당 분당 20) 준수 — dedup 으로 방어.
- `pg_stat_statements` 미설치 시 rule-02 는 조용히 비활성화 (크래시 금지).

### Ventago CLAUDE.md 규약 준수
- 주석 한국어, 함수/변수명 영어
- ESLint `newline-before-return`, `lines-around-comment` 준수
- 에러 핸들링 try/catch 필수
- PostgreSQL pool 안전 규칙 (GSD 스킬 내장) 준수

---

## 리스크 & 완화 (M1 한정)

| 리스크 | 완화 |
|---|---|
| log-tail 이 대용량 파일(일일 4MB) 재시작 시 전체 재처리 | 마지막 inode + 오프셋을 SQLite 에 저장, 재시작 시 이어서 읽기 |
| Telegram 장애로 알림 누락 | 재시도 3회 + 실패 시 SQLite `pending_notifications` 에 저장 후 복구 시 재송출 |
| chokidar 가 DailyRotateFile 의 파일 회전 못 쫓아감 | 자정에 `error-YYYY-MM-DD.log` 경로를 동적으로 갱신 |
| rule-05 정규식이 너무 느슨해 오탐 | 실측 로그 샘플로 테스트, 5 패턴만 시작, M1 후반 튜닝 |
| heartbeat 이 너무 시끄러움 | `disable_notification: true` 로 silent 전송 |

---

## 부록 A: 루트 `package.json` 변경 diff

```json
{
  "workspaces": [
    "api-ventago",
    "ventago-app",
    "print-agent",
    "zebra-agent",
    "vw-agent"
  ]
}
```

## 부록 B: 최초 구현 시 추천 순서 (dependency 그래프)

```
TASK-1,2,3,4 (기반) → TASK-5,6,7 (DB) → TASK-19,20 (알림)
  → TASK-8 (log-tail) → TASK-13,14 (로그 규칙 먼저 — 가장 가치 높음)
  → TASK-9,10,11 (PG 규칙) → TASK-12 (Docker) → TASK-15 (BranchAgent)
  → TASK-16 (heartbeat) → TASK-17,18 (엔진) → TASK-21 (health)
  → TASK-22 (migration) → TASK-23,24,25 (Docker) → TASK-26 (README)
  → TASK-27 (테스트) → TASK-28,29 (검증) → TASK-30 (로컬 실행)
```

첫 주에 TASK-1~14 까지 만 해도 "로그 스키마 에러 알림" 이라는 가장 큰 가치는 확보됨.

---

## 상태

- [x] 로드맵 수립
- [x] M1 SPEC 상세화
- [ ] **M1 사용자 승인 — 현재 단계**
- [ ] M1 Execute
- [ ] M1 Review
