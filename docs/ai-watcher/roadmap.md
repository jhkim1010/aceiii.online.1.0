# AI Watcher — 전체 로드맵

생성일: 2026-04-21
작성자: Marcos.J.Kim + Claude
프로젝트 코드명: **ventago-watcher** (또는 약칭 `vw-agent`)

---

## 비전

Ventago 운영 서버(srv803182) 에서 발생하는 위험·장애를 **감지 → 예측 → 알림 → 승인 기반 수정** 까지 수행하는 AI 운영 비서.
Telegram Bot 을 주 인터페이스로 사용하며, 모든 destructive 작업은 Marcos 의 명시적 승인 후에만 실행한다.

## 설계 원칙 (절대 변경 금지)

1. **PostgreSQL pool 낭비 금지** — watcher 전용 read-only 계정 + 독립 pool (max=3), Ventago 운영 pool(max=80) 과 절대 공유하지 않음.
2. **Destructive 작업은 승인 필수** — AI 가 자동 실행하는 작업은 "화이트리스트 SAFE 등급" 만, 그것도 Telegram 승인 클릭 후.
3. **최근 로그부터 확인** — 모든 감지 루프의 첫 동작은 `logs/error-YYYY-MM-DD.log` 최신 파일 tail.
4. **자기 자신을 감시** — watcher 프로세스도 죽을 수 있으므로 systemd/Docker healthcheck + dead-man switch (Telegram 에 "alive" heartbeat).
5. **오탐 우선 튜닝** — M1 은 "알림만" 받으면서 오탐을 줄이는 기간. 승인/실행 기능은 M3 로 미룸.

---

## 아키텍처 개요

```
┌──────────────────── 운영 서버 (srv803182) ────────────────────┐
│                                                                 │
│  [기존 Ventago 스택]                                           │
│    - api_ventago (Docker, Node.js, :5002)                      │
│    - ventago-app (Docker, Next.js, :5001)                      │
│    - PostgreSQL 10 (host, ventago DB)                          │
│    - pgbouncer (:5432)                                         │
│                                                                 │
│  [신규 vw-agent — Docker 컨테이너 단일]                        │
│    ┌──────────────────────────────────────────┐                │
│    │  Observer (수집)                          │                │
│    │   - LogTail (Winston error/combined)     │                │
│    │   - PGPoller (pg_stat_activity 등)       │                │
│    │   - DockerPoller (컨테이너 health)       │                │
│    │   - AgentPoller (BranchAgent isOnline)   │                │
│    │   - HTTPProbe (API /health, Front /)    │                │
│    └──────────────────────────────────────────┘                │
│    ┌──────────────────────────────────────────┐                │
│    │  Reasoner (판단)                          │                │
│    │   - RuleEngine (M1~M2)                   │                │
│    │   - LLMAdvisor (M2+, Claude API)         │                │
│    │   - Dedup/Cooldown (스팸 방지)           │                │
│    └──────────────────────────────────────────┘                │
│    ┌──────────────────────────────────────────┐                │
│    │  Notifier/Actor                           │                │
│    │   - TelegramBot (알림 + 승인 버튼)       │                │
│    │   - ActionRunner (승인 후 화이트리스트   │                │
│    │                    명령만 실행)           │                │
│    │   - AuditLog (모든 실행 이력 SQLite)     │                │
│    └──────────────────────────────────────────┘                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**중요:** vw-agent 는 자체 SQLite 를 사용한다. Ventago 운영 DB 에 쓰기 금지.
PostgreSQL 은 오직 `ventago_watcher` read-only 계정으로 `pg_stat_*` / `pg_locks` / 카운트 쿼리만 수행.

---

## Milestone 구분

각 Milestone 은 독립 배포 가능하도록 분리. 이전 Milestone 없이 다음 Milestone 을 시작하지 않는다.

> **명명 규칙**: Ventago 본체의 Phase 번호(Phase 1~13, 최근 Zebra Agent) 와 혼동을 피하기 위해
> AI 비서(vw-agent) 내부 진행 단계는 **Milestone (M1~M6)** 으로 구분한다.

### M1 — 감시 + 알림 (MVP)
**기간:** 3~5 일
**목표:** "문제가 터지기 전/터진 직후 Telegram 으로 알림이 온다" 까지.
**기능 범위:**
- vw-agent Docker 컨테이너 기본 골격 (Node.js + TypeScript)
- 운영 서버에 `ventago_watcher` PG read-only 계정 생성
- 감시 규칙 8종 (Observe 레이어):
  1. PG pool 사용률 > 80% (5분 지속)
  2. PG slow query > 1000ms (분당 5건 초과)
  3. PG lock 대기 > 10초
  4. Docker 컨테이너 down / unhealthy (api_ventago, ventago-app, dbpostgres)
  5. Winston error 로그 "column X does not exist" / "relation X does not exist" 패턴
  6. Winston error 로그 분당 10건 초과
  7. BranchAgent isOnline=false 지속 > 10분
  8. Dead-man heartbeat (watcher 자신이 5분간 알림 채널에 신호 없음 → 외부에서 감지 가능)
- Telegram Bot: 알림 메시지만 전송 (버튼 없음)
- 규칙 기반만, LLM 없음
- SQLite 에 이벤트 로그 기록

**산출물:**
- `ventago-watcher/` 신규 저장소 (또는 `ACE_online_1.0/vw-agent/` 워크스페이스)
- Dockerfile + docker-compose.yml
- 운영 서버 배포 스크립트
- `.env.example` (Telegram token, PG 접속정보, 채널 ID)
- 마이그레이션 SQL: `ventago_watcher` 계정 생성

**완료 기준:**
- [ ] 8종 감지 규칙 모두 테스트 통과 (인위적 장애 재현)
- [ ] 운영 서버에 배포 완료, 1주일 무중단 가동
- [ ] 오탐률 < 10% (알림 10건 중 진짜 문제 9건 이상)

### M2 — LLM 판단 추가
**기간:** M1 안정화 후 +3~5 일
**목표:** 규칙에 걸린 이벤트에 "왜 이런 일이 일어났는지 + 어떻게 고칠지" LLM 분석 첨부.
**기능 범위:**
- Anthropic Claude API 연동 (claude-sonnet-4-6)
- 이벤트 분류별 프롬프트 템플릿 (DB 에러 / 인프라 / 마이그레이션 / 세션 등)
- 컨텍스트 자동 수집: 최근 로그 50줄, 관련 PG 쿼리, 최근 배포 정보 (git log)
- Telegram 메시지 포맷 변경 — 규칙 히트 + LLM 요약 2단 구성
- 비용 상한선 (일일 $5 이상 호출 시 fallback)

**산출물:**
- `reasoner/llm-advisor.ts` 모듈
- 프롬프트 템플릿 4종
- LLM 응답 캐시 (동일 패턴 1시간 dedup)

**완료 기준:**
- [ ] 대표 에러 10종에 대해 LLM 조치 제안이 실제 조치와 70% 이상 일치
- [ ] 일일 비용 $3 이하 유지

### M3 — 승인 기반 자동 수정
**기간:** M2 안정화 후 +5~7 일
**목표:** Telegram 버튼 클릭으로 AI 제안 조치를 실행.
**기능 범위:**
- 화이트리스트 기반 ActionRunner
  - SAFE 등급 (인라인 버튼 승인): `docker restart <name>`, `docker compose restart`, 로그 아카이브, PM2 restart, 메모리 캐시 플러시
  - CAUTION 등급 (6자리 코드 재확인): `pg_terminate_backend(PID)`, pgbouncer reload, VACUUM
  - FORBIDDEN (AI 가 제안조차 안 함): DROP / TRUNCATE / DELETE without WHERE / rm / shutdown / 스키마 변경
- Telegram 인라인 버튼 (승인 / 거부 / 자세히)
- 실행 이력 SQLite 감사 로그 (누가·언제·무엇을·결과)
- 실행 후 결과 (stdout/stderr) Telegram 회신
- 2단계 승인: CAUTION 등급은 "버튼 누름 + 6자리 코드 회신" 필요

**산출물:**
- `actor/action-runner.ts` + 화이트리스트 config
- `actor/telegram-inline.ts` (콜백 핸들러)
- SQLite 스키마: `audit_actions(id, ts, rule, action, approved_by, status, stdout, stderr)`

**완료 기준:**
- [ ] SAFE 등급 5종 시나리오 실행 성공
- [ ] CAUTION 등급 코드 재확인 흐름 성공
- [ ] FORBIDDEN 등급은 AI 가 절대 제안 안 하는지 red-team 테스트

### M4 — 예측 기반 알림 (Preventive)
**기간:** M3 안정화 후 +7~10 일
**목표:** "아직 에러는 안 났지만 위험한 추세" 감지.
**기능 범위:**
- 시계열 메트릭 저장 (SQLite → 필요시 TimescaleDB 검토)
- 추세 감지:
  - pool 사용률 1시간 기울기 > +X%
  - slow query 수 주간 대비 증가
  - Jenkins 빌드 시간 점진 증가
  - BranchAgent 오프라인 빈도 증가
- 매출 이상 패턴 (Sales 테이블 시계열 분석, M1 에서는 제외)
- 주간 리포트 Telegram 자동 전송 (월요일 오전 9시)

**완료 기준:**
- [ ] 추세 감지 규칙 4종 이상
- [ ] 주간 리포트 Markdown → Telegram 자동화

### M5 — 세션/보안 이상 감지
**기간:** +3~5 일
**목표:** Ventago 의 active_sessions / branch_ip_registries / terminal_devices 를 활용한 보안 이상 감지.
**기능 범위:**
- 새 IP 에서 로그인 시도 지속 시 알림
- 한 사용자의 급격한 세션 변경 패턴
- Fingerprint 변경 이상
- 비정상 시간대 로그인

### M6 — 웹 대시보드 (옵션)
**기간:** +7~10 일
**목표:** Telegram 만으로는 한눈에 보기 어려운 상태를 웹 대시보드로 제공.
**기능 범위:**
- 단일 페이지 HTML 대시보드 (별도 포트)
- 실시간 차트 (pool, slow query, error rate)
- 최근 알림 이력, 실행 이력 조회
- `vw-agent` 자체 상태 페이지

---

## 배포 & 운영

### 운영 서버 사양 (확인 완료, 2026-04-21)
- **호스팅:** KVM 8 (만료 2027-04-15, 자동갱신)
- **CPU:** 8 코어
- **RAM:** 32 GB
- **디스크:** 400 GB
- **PostgreSQL 10:** 호스트 OS 설치, `max_connections=300` 가정 (확인 필요)
- **여유 자원:** vw-agent 가 사용할 0.5 코어 / 512 MB 는 전체의 1~6% 수준 → 운영 영향 무시 가능

### 배포 구성
- **배포 위치:** srv803182 운영 서버 (Docker 컨테이너 단일)
- **네트워크:** Docker network `ventago` 에 참여해 `dbpostgres` (내부 DNS) 로 접근. 단, 운영 PG 가 호스트에 있으므로 `extra_hosts: "host.docker.internal:host-gateway"` 로 접근.
- **포트:** 내부용 HTTP 헬스체크 하나만 (`127.0.0.1:9876` 바인딩, 외부 노출 X). Telegram 은 long polling 으로 방화벽 변경 불필요.
- **리소스 제한:** Docker `mem_limit: 512m`, `cpus: 0.5`.
- **디스크 사용 예상:** SQLite 일일 ~10MB, 1년 보관 ~4GB → 400GB 의 1% 미만.
- **로그:** Winston daily rotate, `vw-agent/logs/` (api-ventago 와 동일 패턴).
- **백업:** SQLite 일일 로테이션 + 7일 보관.

### 디스크 알림 임계값 (32GB RAM / 400GB 디스크 기준)
- 디스크 사용률 > 80% (320GB) → WARN
- 디스크 사용률 > 90% (360GB) → CRITICAL
- RAM 사용률 > 85% → WARN
- Load average (1분) > CPU 코어 수(8) × 1.5 = 12 → WARN

---

## 리스크 & 완화

| 리스크 | 영향 | 완화 |
|---|---|---|
| watcher 가 PG pool 을 고갈시킴 | 운영 장애 유발 | 독립 계정 + max=3 pool, statement_timeout=3s |
| Telegram token 유출 | 외부에서 알림 변조 | `.env` git 제외, 승인 시 서명 검증 |
| LLM 이 잘못된 조치 제안 | 장애 악화 | 화이트리스트 외 실행 불가, 모든 실행 Marcos 승인 |
| watcher 자체 장애 | 알림 끊김 | dead-man heartbeat + systemd restart=always |
| 오탐 폭증 | Telegram 피로 → 진짜 알림 무시 | M1 1주 튜닝 기간, cooldown/dedup 내장 |

---

## 참고 문서

- Ventago CLAUDE.md (프로젝트 기본 규약)
- `api-ventago/src/database/database.module.ts` (실제 pool 설정 — max=80)
- `api-ventago/src/common/logger/logger.config.ts` (Winston 설정)
- `docs/ai-watcher/spec-M1.md` (다음 단계 상세 SPEC)

---

## 상태

- [x] 로드맵 수립
- [x] M1 SPEC 상세화 (`docs/ai-watcher/spec-M1.md`)
- [x] Connection 누수 진단 (deferred — 34 connection 정상 영역으로 판정, `docs/ai-watcher/spec-pool-leak-diagnosis-DEFERRED.md` 보류)
- [ ] **M1 사용자 최종 승인 — 현재 단계**
- [ ] M1 Execute
- [ ] M1 Review
- [ ] M2 시작 (M1 안정화 후)
