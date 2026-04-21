# SPEC: PostgreSQL Connection 과다 사용 진단 (pgBouncer 환경)

> ## ⚠️ 상태: DEFERRED (보류) — 2026-04-21
>
> **재평가 결과:** 운영 PG 실시간 측정 시 활성 connection 34개 (80 고객 환경).
> 1 고객당 0.425 connection 비율 → 300 고객 추정해도 약 128 connection.
> max_connections=300 으로 충분, 1000 으로의 증설 불필요.
>
> **결정:** 당장 별도 진단 작업은 진행하지 않음. M1 (vw-agent MVP) 의 RULE-01
> (PG pool 사용률 모니터링) 이 자동으로 피크 시간 connection 변동을 추적하므로,
> 만약 향후 피크에서 200+ 가 재현되면 그때 이 SPEC 을 재가동한다.
>
> **재가동 트리거:**
> - vw-agent RULE-01 이 활성 connection > 200 알림을 발화
> - 또는 Marcos 가 수동으로 piek 시간 측정 후 200+ 확인
>
> 본문은 향후 참고용으로 그대로 보존.

---

생성일: 2026-04-21
작성자: Marcos.J.Kim + Claude
우선순위: ~~필수 선결 과제~~ → **참고용 (보류)**
관련 문서: `docs/ai-watcher/roadmap.md`, `docs/ai-watcher/spec-M1.md`

---

## 목표

Ventago 운영 서버에서 현재 80명 고객인데도 PostgreSQL `pg_stat_activity` 에 **200+ connection 슬롯이 점유**되는 원인을 찾아서 수정한다.
목표 수치: 80 고객 → **활성 connection 30 이하**, 300 고객 확장 시에도 80 이하로 억제.

---

## 배경 및 컨텍스트

### 환경 (확인된 것)
- **서버:** KVM 8 (8코어 / 32GB RAM / 400GB)
- **PostgreSQL 10:** 호스트 OS 설치, max_connections=300 가정
- **pgBouncer:** 5432 포트에서 프록시 중 (CLAUDE.md 명시)
- **api-ventago:** Sequelize 인스턴스당 pool max=80, 개발자 기억 기준 "2인스턴스" → 이론상 최대 160
- **다른 시스템:** coolinvoice 등 Docker 스택이 같은 호스트에 존재 (별도 PG 가능성)

### 문제 현상
- 고객 80명 환경에서 `pg_stat_activity` 슬롯 200+ 점유
- 목표 고객 300명 확장 시 지금 추세로는 시스템 한계 도달
- Marcos 는 "1000 connection 필요한가?" 질문 → 그보다 근본 원인 진단이 먼저

### 핵심 가설 (우선순위순)
1. **pgBouncer `pool_mode=session`** → pgBouncer가 실제로는 연결 재사용 안 하고 있음
2. **api-ventago 가 pgBouncer 우회** → 직접 PG:5433 같은 포트로 붙어서 pgBouncer 효과 무효
3. **api-ventago 인스턴스가 2개가 아니라 더 많음** (PM2 cluster mode `instances: max` 등)
4. **Sequelize pool 설정의 idle 시간이 너무 길어 유휴 연결 누적**
5. **다른 시스템(coolinvoice) 연결이 같은 300 슬롯을 공유**
6. **raw `pg.Client` 를 사용하는 코드가 있어 release 누락**

---

## 기술 스택

- 조회만 수행 — 운영 PG / pgBouncer / Docker / 시스템 (read-only)
- 코드 정적 분석 — grep / ripgrep

---

## 태스크 목록

### 준비 (Marcos 가 직접 SSH 로 실행, 결과를 Claude 에게 공유)

- [ ] **TASK-D1: pgBouncer 설정 확인**
  ```bash
  ssh jhkim-server "sudo cat /etc/pgbouncer/pgbouncer.ini | grep -vE '^\s*;|^\s*$'"
  ```
  확인 포인트:
  - `pool_mode` (session / transaction / statement)
  - `default_pool_size` (DB당 PG 연결 수)
  - `max_client_conn` (클라이언트 최대)
  - `listen_port`, `listen_addr`
  - `[databases]` 섹션에서 `ventago =` 라인

- [ ] **TASK-D2: pgBouncer 실시간 상태 (admin console)**
  ```bash
  # pgbouncer admin console 접속 (보통 postgres 사용자로)
  ssh jhkim-server "sudo -u postgres psql -h 127.0.0.1 -p 5432 -d pgbouncer -c 'SHOW POOLS;' -c 'SHOW CLIENTS;' -c 'SHOW SERVERS;' -c 'SHOW CONFIG;' 2>&1 | head -100"
  ```
  (`pgbouncer` 가상 DB 에 접속. 인증 실패 시 `userlist.txt` 에 admin 계정 있는지 확인)

- [ ] **TASK-D3: PG 실제 연결 상태 분석**
  ```bash
  ssh jhkim-server "sudo -u postgres psql -d ventago <<'EOF'
  -- 전체 연결 현황
  SELECT count(*) AS total FROM pg_stat_activity;

  -- 데이터베이스별 분포
  SELECT datname, count(*) FROM pg_stat_activity GROUP BY datname ORDER BY count(*) DESC;

  -- application_name 별 분포 (누가 가장 많이 쓰나)
  SELECT COALESCE(NULLIF(application_name,''),'<empty>') AS app, state, count(*)
  FROM pg_stat_activity
  GROUP BY app, state
  ORDER BY count(*) DESC
  LIMIT 30;

  -- 클라이언트 주소별 분포 (pgBouncer 경유면 127.0.0.1 만 있어야 정상)
  SELECT client_addr, count(*) FROM pg_stat_activity GROUP BY client_addr ORDER BY count(*) DESC;

  -- 유휴(idle) 연결 age 분포 — 오래된 idle 많으면 idle_timeout 문제
  SELECT state, count(*),
         min(now() - state_change) AS min_age,
         max(now() - state_change) AS max_age,
         avg(now() - state_change) AS avg_age
  FROM pg_stat_activity
  WHERE datname = 'ventago'
  GROUP BY state;

  -- ventago DB 활성 쿼리 현황
  SELECT state, wait_event_type, count(*)
  FROM pg_stat_activity
  WHERE datname = 'ventago'
  GROUP BY state, wait_event_type
  ORDER BY count(*) DESC;
  EOF"
  ```

- [ ] **TASK-D4: api-ventago 실제 접속 정보 확인**
  ```bash
  # docker compose 에 들어간 PG_HOST / PG_PORT 확인
  ssh jhkim-server "docker exec api_ventago env | grep -E 'PG_|DB_|POSTGRES_'"

  # 실제 컨테이너에서 어디로 붙고 있는지 (netstat 대체)
  ssh jhkim-server "docker exec api_ventago sh -c 'ss -ntp 2>/dev/null || netstat -ntp 2>/dev/null' | grep -E ':5432|:5433|:6432' | head -10"
  ```

- [ ] **TASK-D5: api-ventago 인스턴스 수 확인**
  ```bash
  # 실제 컨테이너 개수
  ssh jhkim-server "docker ps --filter name=api_ventago --format 'table {{.Names}}\t{{.Status}}'"

  # 컨테이너 내부 Node 프로세스 수 (PM2 cluster 여부)
  ssh jhkim-server "docker exec api_ventago sh -c 'ps aux | grep -E \"node|pm2\" | grep -v grep'"
  ```

- [ ] **TASK-D6: 다른 시스템이 같은 PG 쓰는지**
  ```bash
  ssh jhkim-server "sudo ss -ntp | grep ':5432' | awk '{print \$6}' | sort -u"
  # 또는
  ssh jhkim-server "sudo lsof -i :5432 -n 2>/dev/null | head -30"
  ```

### 분석 (Claude 가 수행, 코드 정적 분석)

- [ ] **TASK-C1: raw `pg.Client` 직접 사용 검색**
  대상: `api-ventago/src/` 전체. `pg` 라이브러리를 Sequelize 밖에서 직접 쓰는 지점 찾기

- [ ] **TASK-C2: Sequelize 인스턴스 다중 생성 검색**
  `new Sequelize(`, `new SequelizeModule(`, `SequelizeModule.forRoot` 가 여러 번 있는지

- [ ] **TASK-C3: cron/schedule 작업의 pool 사용**
  `@Cron`, `@Interval` 데코레이터 근처에서 DB 쿼리 패턴, release 누락 여부

- [ ] **TASK-C4: Dockerfile / docker-compose 의 PG_HOST 확인**
  `api-ventago/Dockerfile`, `api-ventago/docker-compose.yml`, `.env.production` 등에서 PG 접속 설정

- [ ] **TASK-C5: package.json 스크립트의 PM2 instances 설정**
  `pm2.config.js`, `ecosystem.config.js`, `package.json` scripts 에서 `instances:` 값

### 진단 종합 및 수정 Plan 제안

- [ ] **TASK-R1: 5 가설 중 무엇이 원인인지 확정**
- [ ] **TASK-R2: 수정안 작성** (설정 변경 / 코드 수정 / 인프라 변경 단계별)
- [ ] **TASK-R3: Marcos 승인 후 Execute 단계 착수**

---

## 예상 수정 시나리오 (진단 결과별)

### 시나리오 A: pgBouncer가 `pool_mode=session`
**수정:** `pool_mode = transaction` 으로 변경
**효과:** 200 슬롯 → 30~50 슬롯으로 감소 가능
**주의:** transaction mode 는 SET/LISTEN/prepared statement 제약 → Sequelize 는 호환 가능하나 실제 코드 검증 필요
**적용:**
```ini
# /etc/pgbouncer/pgbouncer.ini
pool_mode = transaction
default_pool_size = 30
reserve_pool_size = 10
max_client_conn = 500
server_idle_timeout = 60
```
재시작: `sudo systemctl reload pgbouncer`

### 시나리오 B: api-ventago 가 pgBouncer 우회
**수정:** `PG_HOST` / `PG_PORT` 를 pgBouncer 포트로 변경
**효과:** 즉시 효과, 기존 연결 수 pgBouncer 가 재사용

### 시나리오 C: PM2 cluster mode 로 8 인스턴스
**수정:** `instances: 2` (CPU 코어의 25%) 로 고정, `exec_mode: cluster`
**효과:** 8 × 80 = 640 시도 → 2 × 80 = 160 시도

### 시나리오 D: Sequelize idle timeout 문제
**수정:**
```typescript
pool: {
  min: 5,       // 10 → 5 로 축소 (cold start 부담 작음)
  max: 30,      // 80 → 30 (pgBouncer 가 multiplex 하므로 여유)
  idle: 5000,   // 10000 → 5000 (유휴 빠르게 반납)
  acquire: 15000,
  evict: 1000,
}
```

### 시나리오 E: raw pg.Client 누수
**수정:** 해당 코드 Sequelize 로 전환 또는 `finally { client.release() }` 패턴 강제

---

## 완료 기준

- [ ] TASK-D1~D6 결과 수집 완료
- [ ] TASK-C1~C5 정적 분석 완료
- [ ] 원인 가설 확정 (하나 또는 복합)
- [ ] Marcos 가 수정 방향 승인
- [ ] 수정 적용 후 `pg_stat_activity` 활성 연결 < 50 확인 (80 고객 기준)
- [ ] 30분 관측 후 재증가 없음 확인

---

## 금지사항 / 주의사항

- **운영 PG / pgBouncer 재시작은 반드시 Marcos 승인 후.** 재시작 시 순간적 장애 가능성.
- **pgBouncer `pool_mode` 변경 전, Sequelize 사용 패턴 검증.** Prepared statement 이름 충돌 가능.
- **Ventago 이외 시스템(coolinvoice) 영향 확인.** pgBouncer 가 공유된다면 변경이 다른 시스템도 건드림.
- **진단 쿼리는 모두 read-only.** `SHOW`, `SELECT` 만.
- **pgbouncer admin 계정 비밀번호 git 에 노출 금지.**

---

## 상태

- [x] SPEC 작성
- [ ] **TASK-D1~D6 결과 수집 (Marcos 가 SSH 실행) — 현재 단계**
- [ ] TASK-C1~C5 정적 분석
- [ ] 원인 확정
- [ ] 수정 Plan 승인
- [ ] Execute
- [ ] 검증
- [ ] Phase 0 SPEC 재개
