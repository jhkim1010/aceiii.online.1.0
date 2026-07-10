# SPEC: Phase 54 — 운영 관측 시스템 (병목 조기예측, 경량 self-hosted)

생성일: 2026-07-10 · 상태: **PLAN(준비만 완료, 실행 대기)** · 방식: 경량 self-hosted(Prometheus+Grafana+Loki)

> **Phase 번호: 54** (다음 가용 번호 — 44~52 사용, 53 보안강화 실행 중, 53.1 분리. 54+ 미사용).
> **Phase 48(WC 백본 통일)과의 관계**: Phase 48의 "관측성"은 커머스 싱크 대시보드(outbox 실패율·rate-limit·last_synced)에 국한된 **부분집합**. 본 Phase 54는 인프라·DB·pool·호스트 전반의 상위 관측 플랫폼이며, Phase 48 대시보드는 추후 본 스택에 흡수 가능.
> 설계 근거 문서: 대화 전달된 「ACE/ventago 운영 관측 시스템 제안서」.
> 이 SPEC 은 **준비(PLAN)** 단계 산출물입니다. 각 태스크는 사용자 승인 후 EXECUTE 로 진행합니다.
> 관련 메모리: `project_observability_proposal.md`, `project_pg18_version_unification.md`.

## 목표

고객 10명 → 1000명 확장 시 발생할 병목(특히 PostgreSQL pool 고갈·느린 쿼리)을 **터지기 전에 자동 감지·경보**하는 관측 계층을 운영 VPS 에 구축한다. 이미 있는 winston·SlowQuery·Pool 모니터 자산을 살려 시계열 지표·로그 집계·조기 경보·용량 실측으로 승격한다.

## 배경 및 컨텍스트

- **스택**: NestJS 11 + Sequelize(pg 8.13) + PM2(현재 `instances=1`) + pgbouncer(:5432) → PostgreSQL 18(:5434, `max_connections=100`).
- **자산(구현됨)**: `src/common/logger/logger.config.ts`(winston daily-rotate + 시크릿 마스킹), `src/database/database.module.ts`(SlowQuery 로거 >100ms/>500ms 🔴, DatabasePool 60초 모니터).
- **라이브 병목(최근 로그 `logs/combined-2026-07-09.log`)**: `sync_outbox` SELECT 가 83s→87s→**157s**, Outbox tick 계속 스킵. 지금은 저부하라 pool 여유(`size=2 using=1`)로 숨겨짐.
- **관련 코드**: `api-ventago/src/app/integrations/core/outbox.service.ts`(tick), `outbox.cron.ts`(`EVERY_10_SECONDS`), `models/sync-outbox.model.ts`.
- **핵심 통찰(Little's Law)**: pool 고갈 원인 = 커넥션 개수가 아니라 커넥션을 오래 붙잡는 느린 쿼리. 쿼리만 빠르면 1000명도 커넥션 몇 개로 감당. → 1순위 감시=느린 쿼리·커넥션 점유시간.

## 기술 스택

- 언어/프레임워크: Node.js(NestJS/TypeScript), 관측 스택은 Docker Compose(Prometheus/Grafana/Loki/exporters), 부하테스트 k6.
- DB: PostgreSQL 18, Sequelize pool `min=10 / max=80 / acquire=15s`. 마이그레이션은 **로컬(5432) + 운영(5434) 동시 적용** 규칙 준수(CLAUDE.md).
- ESLint 설정 파일: `api-ventago/eslint.config.mjs` (Warning=빌드 실패. newline-before-return / lines-around-comment / no-unused-vars 주의).

---

## ★ 발견된 잠복 위험 (실행 시 우선 반영)

- **(A) 2인스턴스 복귀 시 커넥션 초과**: pool `max=80`/인스턴스 × 2 = 160 > `max_connections=100`. `ecosystem.config.js` 에 `instances` 1→2 복귀 계획 주석 존재. 코드 주석의 `max_connections=300` 은 낡음(실측 100).
- **(B) `pg_stat_statements` 미설치**(`pgss_installed=0`): 느린쿼리 순위 표준 도구. `shared_preload_libraries` 추가 + `CREATE EXTENSION` + **재시작** 필요.
- **(C) `sync_outbox` 157초 쿼리**: 모델에 `@Index` 없음(주석은 "due 인덱스 활용"이라 주장) → 인덱스 부재 + 누적행(done/failed 미정리) seq scan 가설.

---

## 태스크 목록

### Phase 0 — 무비용 즉시 개선 + 라이브 병목 진단 (최우선)

- [ ] **TASK-0 (게이트): `sync_outbox` 157초 진단**. 운영 PG18(read-only)에서 아래를 수집·판정한다. ① `SELECT status, count(*) FROM sync_outbox GROUP BY status;`(누적행 규모). ② 인덱스 존재 확인 `\d sync_outbox` / `pg_indexes`. ③ 실제 쿼리 `EXPLAIN (ANALYZE, BUFFERS) SELECT ... WHERE status='pending' AND next_retry_at<=now() ORDER BY next_retry_at ASC LIMIT 20;`(seq scan/sort 여부). ④ dead tuple/bloat `pg_stat_user_tables`(n_dead_tup, last_autovacuum). — 파일: 진단 리포트(코드 변경 없음). **이 결과가 TASK-1 방향을 결정하는 게이트.**
- [ ] **TASK-1: `sync_outbox` 조기 인덱스 + 정리**. 진단 결과에 따라 **부분 인덱스** `CREATE INDEX CONCURRENTLY idx_sync_outbox_due ON sync_outbox (next_retry_at) WHERE status='pending';`(done/failed 제외로 인덱스 슬림) + 필요 시 done 행 아카이브/프루닝 + `VACUUM (ANALYZE)`. — 파일: `api-ventago/migrations/NNNN-sync-outbox-due-index.sql`. **로컬(5432)+운영(5434) 동시 적용**, 기존 테이블이라 owner 이전 불필요(이미 coolsistema). `CONCURRENTLY` 는 트랜잭션 밖 실행(단일 트랜잭션 옵션 제외).
- [ ] **TASK-2: 안전밸브 `statement_timeout` 도입**. 앱 롤(coolsistema)에 `statement_timeout`(초기 60s 권장, 이후 30s 검토) + `idle_in_transaction_session_timeout`(60s) 적용. 단, **적용 전 정상적으로 장시간 걸리는 배치/리포트 쿼리 조사**(있으면 해당 세션만 예외 `SET LOCAL`). — 파일: `api-ventago/migrations/NNNN-app-role-timeouts.sql`(로컬+운영). 주의: pool `acquire=15s` 와 상충 아님(무관 계층).
- [ ] **TASK-3: pool max × 인스턴스 재점검(위험 A)**. `ecosystem.config.js` 2인스턴스 복귀 전제로, Sequelize `max` 를 인스턴스 수로 나눠 총합 ≤ 0.85×`max_connections`(=85) 이내가 되도록 재배분(예: 2인스턴스면 각 40) 또는 `max_connections` 상향 계획 명시. — 파일: `src/database/database.module.ts` 주석 정정(300→100) + 값 조정안. **이번엔 값 확정만, 실제 복귀는 socket.io 수정 이후.**
- [ ] **TASK-4: winston 운영 포맷 JSON 화**. 운영(`NODE_ENV=production`)만 JSON transport(로컬 dev 는 기존 컬러 텍스트 유지). 시크릿 마스킹 유지. Loki 라벨링(level/context) 대비. — 파일: `src/common/logger/logger.config.ts`.
- [ ] **TASK-5: `prom-client` 계측 도입**. `prom-client` 의존성 추가, `/metrics` 엔드포인트(NestJS). 기존 DatabasePool 수치(size/using/available/waiting)를 **로그 대신 gauge** 로 노출 + HTTP RED 히스토그램(라우트별 지연/에러/요청수) + **Outbox 게이지**(pending 큐 깊이 + 최고령 미처리 행 나이 = 157초 사건 상시 감시). pool 규칙: 계측이 앱 pool 을 추가 점유하지 않도록 in-process 카운터만 사용. — 파일: `src/common/metrics/*.ts`(신규 모듈), `main.ts` 등록.
- [ ] **TASK-6: 로그 보존/디스크 방어 점검**. daily-rotate `maxFiles`/압축(gzip) 설정 확인(하루 ~12MB 누적). — 파일: `src/common/logger/logger.config.ts`.
- [ ] **TASK-7: ESLint 검증** (`npx eslint . --fix` in `api-ventago`) — 오류 0.
- [ ] **TASK-8: pool 안전 점검** — 변경 코드에 `pool.connect()`/`release()` 누락 없음, 신규 계측이 커넥션 미점유 확인.

### Phase 1 — 지표 코어 (Prometheus + exporters + Grafana)

- [ ] **TASK-1-1: 전용 `monitoring` 롤** — `pg_monitor` 부여, `CONNECTION LIMIT 3`, **pgbouncer 우회 PG18 직결**(앱 pool 무낭비). 로컬+운영 SQL.
- [ ] **TASK-1-2: `pg_stat_statements` 활성화(위험 B)** — `shared_preload_libraries` 추가 + `CREATE EXTENSION` + **재시작(점검창)**. 운영 재시작이라 **사용자 승인·일정 필수**.
- [ ] **TASK-1-3: docker-compose 관측 스택** — Prometheus + node_exporter + postgres_exporter + pgbouncer_exporter + Grafana. 별도 compose 파일, 앱과 분리.
- [ ] **TASK-1-4: Grafana 대시보드** — 골든시그널 + pool(using/max·waiting·acquire p95) + pgbouncer(cl_waiting·maxwait) + PG(느린쿼리 top·락·캐시적중·활성커넥션/100) + Outbox lag.

### Phase 2 — 로그 상관 + 조기 경보

- [ ] **TASK-2-1: Loki + promtail** — winston JSON 로그 수집, 지표와 동일 시간축.
- [ ] **TASK-2-2: 경보 규칙** — 제안서 4장 임계값(pool 70%/90%, waiting>0 1분, cl_waiting>0, 최장쿼리>5s/30s, Outbox 나이>5분/30분, 5xx>1%/5%, 디스크<20%/10%)을 Grafana Alerting → 텔레그램 봇.

### Phase 3 — 용량 실측(k6)

- [ ] **TASK-3-1: k6 시나리오** 100/500/1000 VU 단계 상승, 실제 핵심 API. 스테이징 또는 저부하 시간대.
- [ ] **TASK-3-2: 포화 곡선 + SLO** — 무너지는 지점 실측 → pool/max_connections/인스턴스 목표 확정, SLO(p95<300ms, 에러<0.5%) 정의.

### Phase 4 — (선택) 분산 추적

- [ ] **TASK-4-1: OpenTelemetry** 요청→쿼리 추적(느린 요청의 원인 쿼리 자동 연결).

---

## 완료 기준 (Phase 0 기준)

- TASK-0 진단 리포트로 sync_outbox 병목 근본 원인 확정.
- 인덱스/타임아웃 마이그레이션이 **로컬(5432)+운영(5434) 양쪽** 적용, 스키마 대조 일치.
- `/metrics` 에 pool·RED·Outbox 지표 노출 확인.
- ESLint 오류 0, pool release 누락 0.
- 재현: 조치 후 로그에서 sync_outbox SlowQuery(🔴)와 tick 스킵 소멸 확인.

## 금지사항 / 주의사항

- **실행 금지(이번은 준비만)**: 본 SPEC 승인 전 어떤 DDL·코드 변경도 하지 않는다.
- 운영 DDL(인덱스/타임아웃/롤/확장)·**PostgreSQL 재시작**은 CLAUDE.md 규칙대로 **SQL 내용+영향 row+일정**을 보여주고 **사용자 승인 후** 실행.
- 마이그레이션 한쪽만 적용 금지(로컬↔운영 스키마 분기 = 500 사고 전례).
- exporter 는 앱 pool·pgbouncer 앱 풀을 쓰지 않는다(전용 monitoring 롤 직결).
- `statement_timeout` 은 정상 장시간 쿼리 조사 후 적용(무분별 적용 시 배치 중단 위험).
- 로컬 Mac(5432) 적용 SQL 은 샌드박스가 못 닿으므로 **명령을 사용자에게 전달**해 Mac 에서 실행.
