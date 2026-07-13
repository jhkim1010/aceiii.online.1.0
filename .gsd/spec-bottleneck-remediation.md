# SPEC: 운영서버 5대 병목 + 디스크 경고 해결
생성일: 2026-07-13
작성: 주간 브리핑 후속 (GSD Plan)

## 목표
2026-07-13 브리핑에서 도출한 5대 병목과 디스크 78% 경고를, **실제 코드·pgbouncer·인덱스 근거로 재검증**하여 위험도를 정정하고, 운영 안전·pool 무낭비 원칙 하에 단계별 해결책을 확정한다.

## 배경 및 컨텍스트 (실측 근거, 2026-07-13)
- **접속 경로 확정**: api(도커 172.18.0.6) → **pgbouncer 172.17.0.1:5432 (pool_mode=transaction, default_pool_size=20, reserve 10, max_client_conn=1000)** → PG18 127.0.0.1:5434. PG 5434에 붙은 established는 pgbouncer 서버연결 **2개뿐**.
- **Sequelize pool**(`src/database/database.module.ts`): min=2, max=80, acquire=15s. 최신 로그(07-11) 내내 `size=2 using=0 waiting=0` — 사실상 무부하.
- **인스턴스 수**(`ecosystem.config.js`): 현재 **instances=1** (2026-06-30 socket.io sticky 문제로 2→1 임시 강등, ws-only 어댑터 수정 후 복귀 예정).
- **인덱스 실측**: `sale_items`는 pkey(id)+promo_group 부분인덱스뿐 → **sale_id(FK)·product_id(FK) 인덱스 없음**. `sales`는 이미 다수 인덱스 보유(terminal_id, store_client, activity_date, source_store_date 등)이나 **user_id 인덱스 없음**(지점 도달 경로). `cash_registers`는 이미 (store_id,box_id) 인덱스 보유.
- **미사용 인덱스**: 재시작(uptime 17분)으로 통계 리셋됨 → 현재 idx_scan=0 수치 신뢰 불가. 전체 미사용 인덱스 총량 ≈ **4.8MB**(공간 이득 미미).
- **pg_stat_statements**: 2026-07-13 설치 완료(v1.12), 수집 시작.
- **디스크**: `/dev/sda1` 78%(298G/387G, 여유 89G). `/var/lib/postgresql`=57G. 단, **5433(PG10)은 ace00…apparel09 등 다수 DB를 서비스** → 단순 삭제 금지 대상.

## 기술 스택
- 언어/프레임워크: NestJS 11 + Sequelize (api-ventago)
- DB: PostgreSQL 18 (운영 5434) / pgbouncer transaction pooling (5432)
- ESLint: `eslint.config.mjs` (Warning=빌드차단 규칙)
- 마이그레이션 규칙: 로컬(Mac PG18:5432) + 운영(PG18:5434) **동시 적용**, 신규객체 owner=coolsistema

---

## 위험도 정정 요약 (브리핑 대비)

| # | 항목 | 브리핑 위험도 | **정정 위험도** | 정정 사유 |
|---|------|:---:|:---:|------|
| ① | Connection pool 포화 | 🔴 CRITICAL | 🟡 **MEDIUM(잠복)** | pgbouncer transaction 모드가 백엔드를 이미 캡핑 → "160>100 크래시"는 현 구조에서 불성립. 실질 병목은 pgbouncer default_pool_size=20 큐잉 |
| ② | sales/sale_items 풀스캔 | 🟠 HIGH | 🟠 **HIGH(유효)** | sale_items의 sale_id·product_id FK 인덱스 부재 = 진짜 원인. 최우선 실행 |
| ③ | pg_stat_statements 계측 | 🟡 MEDIUM | 🟢 **완료+후속** | 설치 완료. 남은 건 조회 role GRANT + 주간 스냅샷 |
| ④ | cash_registers seq_scan | 🟡 MEDIUM | 🟢 **LOW** | 이미 (store_id,box_id) 인덱스 존재. 135행이라 seq_scan 비용 자체가 미미 |
| ⑤ | 미사용 인덱스 376개 | 🟢 LOW | ⚪ **보류** | 통계 리셋됨+총 4.8MB → 공간이득 미미·오제거 위험. pgss 2~4주 축적 후 재판단 |
| 💾 | 디스크 78% | 강한경고 | 🟠 **HIGH(유효)** | 임계 근접 사실. 단 5433 라이브 DB 존재로 "규명 후 안전회수"로 접근 |

---

## 태스크 목록 (실행 순서 = 위험도·안전도)

### TASK-1 [②·HIGH] sale_items FK 인덱스 추가 — 최우선
- 파일: `api-ventago/migrations/2026-07-13-sale-items-fk-indexes.sql`
- 내용:
  - `CREATE INDEX CONCURRENTLY idx_sale_items_sale_id ON sale_items (sale_id);`
  - `CREATE INDEX CONCURRENTLY idx_sale_items_product_id ON sale_items (product_id);`
  - `CONCURRENTLY` 사용(락 없이 온라인 생성 — pool·서비스 무영향). ※CONCURRENTLY는 트랜잭션 블록 밖에서 실행(--single-transaction 금지).
  - 끝에 owner DO 블록: `ALTER TABLE sale_items ...`는 불필요(기존 테이블), 인덱스 owner는 테이블 따라감.
- 사전검증: `EXPLAIN (ANALYZE,BUFFERS)`로 대표 쿼리(판매상세 조회, 리포트 집계)가 Index Scan으로 전환되는지 확인.
- 적용: 로컬(Mac 5432) + 운영(5434) 동시. 운영은 `psql -p 5434 -d ventago -f <file>`(CONCURRENTLY라 단일트랜잭션 옵션 제외).

### TASK-2 [②·HIGH] sales.user_id 인덱스 검토 + EXPLAIN 근거화
- 파일: 같은 마이그레이션 파일에 조건부 추가
- 내용: pg_stat_statements로 sales seq_scan 유발 실제 쿼리 확인 → user_id 단독/복합 필터가 잦으면 `CREATE INDEX CONCURRENTLY idx_sales_user_id ON sales (user_id);`. **EXPLAIN 근거 없으면 추가하지 않음**(과잉 인덱스=쓰기부담).

### TASK-3 [💾·HIGH] 디스크 원인 규명 + 안전 회수
- 파일: 조치 스크립트 아님(진단 우선). 결과는 본 SPEC에 기록.
- 내용(read-only 진단 먼저):
  - `du -xh --max-depth=1 /var/lib/postgresql/{10,18}`로 클러스터별 용량 분리
  - PG10(5433) 각 DB 크기 + ventago가 5433에 잔존(롤백본)하는지 확인 → **컷오버 안정화(2026-07-10) 확인 후에만** PG10 ventago DB 단독 회수 검토
  - WAL/로그 누적 확인(`pg_wal`, `/var/log/postgresql`), api-ventago `logs/`(12MB짜리 07-09 등) 로테이션 정책 점검
  - Docker 이미지/볼륨(`docker system df`) 정리 여지
- **안전장치**: 실제 삭제·DROP은 개별 사용자 승인. 80% 도달 전 여유(89G) 확보 목표.

### TASK-4 [①·MEDIUM] pgbouncer 풀 예산 정렬 + Sequelize max 정합
- 파일: 서버 `/etc/pgbouncer/pgbouncer.ini` (사용자 승인 후) + `src/database/database.module.ts`
- 내용:
  - **풀 예산 계산**: max_connections=100. 동시 활성 pooled DB들의 `pool_size` 합 + reserve < 100 유지. ventago 라인에 명시적 `pool_size=` 부여(예 40) 검토, 나머지 테넌트는 소값 유지.
  - **Sequelize max 하향**: 80 → 40(인스턴스당). pgbouncer 뒤에서 80은 과다구독(서버 20슬롯). instances=2 복귀해도 40×2=80 클라이언트<max_client_conn 1000, 백엔드는 pgbouncer가 캡핑.
  - **transaction 모드 호환성 검증**: named prepared statement/세션 SET 의존 없는지 확인(node-postgres 기본 unnamed → 일반적으로 안전). `SET TIME ZONE`은 트랜잭션 단위 재적용이라 문제없음 확인.
  - **주의**: 이 변경은 재배포(Sequelize) 또는 pgbouncer reload 필요 → 저부하 창.

### TASK-5 [③·완료후속] pg_stat_statements 활용 세팅
- 파일: `api-ventago/migrations/2026-07-13-pgss-grant.sql` (선택)
- 내용:
  - superadmin 진단 페이지가 읽을 수 있게 조회 role에 `GRANT pg_read_all_stats` 또는 뷰 SELECT 권한(권한 최소화).
  - 주간 Top-N 스냅샷 쿼리 확정(total_exec_time/mean_exec_time/calls 상위). 다음 브리핑부터 실측 사용.
  - 2~4주 축적 후 TASK-6 재개.

### TASK-6 [⑤·보류] 미사용 인덱스 정리 — 2~4주 후
- 조건: pg_stat_statements + pg_stat_user_indexes 데이터 충분히 축적된 뒤.
- 내용: idx_scan=0 & non-unique & non-PK 인덱스만, 크기 큰 것부터 개별 검토 후 `DROP INDEX CONCURRENTLY`. 현재는 공간이득 미미(4.8MB)라 **이번 사이클에서 실행 안 함**.

### TASK-7 검증
- ESLint: `npx eslint . ` 오류 0 (database.module.ts 수정 시)
- 마이그레이션 로컬+운영 양쪽 스키마 대조
- 적용 후 최신 로그 재확인(에러/Pool waiting 0)
- pg_stat_statements로 대상 쿼리 mean_exec_time 개선 확인

## 완료 기준
- sale_items 조인/조회가 Index Scan으로 전환(EXPLAIN 근거)
- 디스크 여유 확보 계획 확정(및 80% 알림 세팅)
- Sequelize max·pgbouncer 풀 예산이 max_connections=100 이내로 정합
- ESLint 0, 로컬·운영 스키마 일치, 로그 clean

## 금지사항 / 주의사항
- **CONCURRENTLY 인덱스는 트랜잭션 블록·--single-transaction 금지** (실패 시 INVALID 인덱스 잔존 → 재생성 전 DROP).
- **5433(PG10) 클러스터·타 테넌트 DB 삭제 금지** — ace00…apparel09 라이브 가능성. PG10 ventago 단독 회수도 컷오버 안정 확인 후 승인.
- 운영 DDL·pgbouncer.ini 수정·서비스 재시작은 **개별 사용자 승인** 후 저부하 창.
- 마이그레이션 한쪽만 적용 금지(로컬+운영 동시), 신규객체 owner=coolsistema.
- pool 낭비 금지: 진단은 단일 psql·read-only·즉시 종료.
