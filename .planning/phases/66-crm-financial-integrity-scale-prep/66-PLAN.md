# Phase 66: CRM/금융 정합성 · 부팅 위생 · 확장 준비 — Plan

**Created:** 2026-07-29
**Source:** 외부 AI 분석(2026-07-29 로그 기준) + Claude 자체 관측 — 양쪽 주장을 코드·운영 실측으로 전수 검증 후 종합
**전제:** Phase 65 완료(원장 단일 진실·경계·감지·회전). 본 phase 는 "판매 이후의 돈·CRM 데이터"와 "다음 성장 단계 준비"를 다룬다.

---

## 0. 주장 검증 결과 (이 PLAN 의 전제)

| # | 외부 AI 주장 | 판정 | 근거 |
|---|---|---|---|
| 1 | 고객 세그먼트 매장 간 혼합 | **사실 (P0)** | `segment-refresh.cron.ts` — `GROUP BY s.client_id`(store 없음), `ON CONFLICT (client_id)`, store_id 를 `clients.store_id` 에서 취득. 여러 매장을 쓰는 공유 고객의 금액 합산·등급이 교차 오염. ※운영 error 로그엔 아직 0건(로컬에서 관측된 NULL 실패) — 구조 결함은 동일 |
| 2 | 운영 부팅 `sequelize.sync` 반복 실패 | **사실** | 운영 = `permission denied for schema public`, 로컬 = `cannot alter type ... view or rule`. 메시지는 다르나 결론 동일: 마이그레이션 체계 확립 후의 잔재 — 제거 대상 |
| 3 | 판매 성공 후 신용원장 누락 가능 | **사실** | `sales-create.service.ts:607~` — 커밋 후 try/catch(비치명). Phase 64 "커밋 후 = 성공" 규약상 방향은 맞으나, CLAUDE.md 규약의 나머지 반쪽("반드시 일어나야 하는 후속 작업은 같은 트랜잭션에서 outbox INSERT")이 미적용 |
| 4 | outbox enqueue 예외가 판매 트랜잭션을 abort | **사실** | `outbox.service.ts:58~` — unique violation 을 catch 하지만 PG 는 이미 트랜잭션 aborted 상태 → 이후 판매 문장 전부 실패. catch 가 보호가 아니라 착시 |
| 5 | 멱등 완료 기록이 늦음 | **사실** | `complete()` 가 커밋+원장+프린터+재조회 이후. 중간 프로세스 종료 시 `processing` 고착 → POS 재시도가 in_flight 오류 |
| 6 | lease 회수 1.445초 | **로컬 한정** | 운영엔 `sync_outbox_lease_idx` 존재. 1.445s 는 로컬 Mac 관측. tick 마다 회수→간격 제한은 저비용 개선으로 수용 |
| 7 | Redis 미설정·단일 어댑터 | **운영 반증** | 운영 부팅 로그 "socket.io Redis 어댑터 등록" 확인, ventago_redis 컨테이너 가동. 로컬 dev 한정. 단 "다중워커+Redis 미설정 시 경고" 가드는 수용 |
| 8 | 로그 증폭 | 부분 | SCHEMA_SYNC 제거(W2)로 최대 발생원 소거. pool 로그 등은 P2 |

**Claude 자체 관측 (Phase 65 마감 시점):**

| 항목 | 판정 |
|---|---|
| 판매·취소 경로가 부모(madre) 캐시 미갱신 — 드리프트 크론도 비parent 만 검사 | **사실 (grep 확인)** — W2 에 포함 |
| 로그인 CPU 붕괴점 80건/s (bcrypt+권한 55KB 조립) | 실측 기록 — W5 |
| 단일 매장 판매 41건/s hot-row 상한 | 실측 — 요구 5건/s 대비 8배 여유 → **착수 금지, 감시만** |
| cron 리더 `NODE_APP_INSTANCE===0` — 컨테이너 2대 시 중복 | 확장 전제 조건 — P2 |

---

## Wave 구성

```
W1(세그먼트 테넌트 격리) → W4(금융 outbox)   ← CRM/금융 정합성 축 (P0)
W2(부팅 위생+부모 캐시)  · W3(outbox/멱등 견고화)  ← 병렬 가능 (P0)
W5(로그인 다이어트)                                ← P1, W1~W4 후
W6(확장 가드 소품)                                 ← P1, 병렬
P2(보류): Redis 분산락 리더 · 2호기+standby · hot-row 완화 — 착수 조건 명시
```

### W1. 고객 세그먼트 (store_id, client_id) 재설계 — P0 ★최우선

| # | 태스크 |
|---|---|
| 1-1 | `client_segments` UNIQUE 를 `(store_id, client_id)` 로 변경하는 마이그레이션 (기존 데이터 백업 테이블 후 TRUNCATE — 파생 집계라 재구축 가능) |
| 1-2 | 집계 쿼리 재작성 — `GROUP BY s.store_id, s.client_id`, store_id 는 `sales.store_id` 기준. 구매 이력 없는 고객은 `store_clients` 기준 매장별 행 생성 |
| 1-3 | `ON CONFLICT (store_id, client_id)` 로 교체. NULL store_id 행은 집계 제외(WHERE s.store_id IS NOT NULL) — 로컬 실패 재발 방지 |
| 1-4 | 소비처 전수 확인 — campañas 세그먼트 빌더·필터가 (store, client) 키로 조회하는지 대조 후 교정 |
| 1-5 | 재구축 실행(로컬+운영) + 교차 오염 사전/사후 측정 SELECT 기록 |

- **게이트:** 같은 client 가 두 매장에서 구매 시 매장별 별도 행 · 타 매장 금액 미합산(테스트 데이터로 확인) · 크론 1회 무오류 완주
- **주의:** campañas 발송 대상 수가 변할 수 있음(정확해지는 방향) — 변경 전후 매장별 대상 수 비교표를 남겨 사용자 확인

### W2. 부팅 위생 + 부모 캐시 — P0 (소규모 묶음)

| # | 태스크 |
|---|---|
| 2-1 | `sync.service.ts` 의 `sequelize.sync()` 제거 → "필수 마이그레이션 존재 검사"로 대체(핵심 테이블·컬럼 몇 개 SELECT 확인, 실패 시 error 로그 + `/health` 에 degraded 표기 — 부팅은 유지) |
| 2-2 | 드리프트 크론에 **부모(madre) 캐시 재계산** 단계 추가 — 파생값이므로 자동 재계산 OK(자식은 계속 탐지-전용). `updateMotherStock` 정의(자식+자기 PB, suspend 제외) 재사용, 야간 1회 |
| 2-3 | 드리프트 크론 요약에 parent 재계산 건수 포함 + `/diagnostics/stock-drift` 응답에 노출 |

- **게이트:** 배포 후 SCHEMA_SYNC_FAILED 로그 소멸 · 크론 다음 실행에서 parent 재계산 정상 · 판매 다음날 부모 표시값 = 원장 합

### W3. outbox enqueue·멱등 견고화 — P0

| # | 태스크 |
|---|---|
| 3-1 | `enqueue()` 를 raw `INSERT ... ON CONFLICT DO NOTHING` 으로 교체(판매 트랜잭션 abort 제거). 중복 외 오류는 **재throw** — 판매 tx 가 정상 롤백되게(조용한 유실 금지) |
| 3-2 | 멱등 레코드에 `saleId` 를 **판매 트랜잭션 안에서** 기록(committed 표시). `complete()` 는 사후 응답 본문 저장으로 역할 축소. 재시도 시 `saleId` 로 판매 재조회 응답 |
| 3-3 | 고아 `processing` 복구 스위퍼 — 기존 크론에 편승: N분 경과 `processing` 을 실제 sales 존재 여부와 대조해 completed/실패 정리 |
| 3-4 | lease 회수를 매 tick → 30초 최소 간격으로 제한(마지막 회수 시각 메모) |

- **게이트:** 판매 tx 중 enqueue 중복 발생 시 판매 정상 커밋(유닛) · 커밋 직후 kill 시나리오에서 재시도가 sale_id 복구 응답 수신 · processing 고아 자동 정리

### W4. 신용원장 financial outbox — P0

| # | 태스크 |
|---|---|
| 4-1 | 판매 트랜잭션 안에서 `sync_outbox` 에 ledger 작업 INSERT (opType='credit_ledger', dedupeKey=`sale#{id}:ledger`) — CLAUDE.md 규약 그대로. 신규 테이블 대신 기존 outbox 재사용(신규 인프라 0) |
| 4-2 | outbox processor 에 credit_ledger 핸들러 — `attachCreditLedgerForSale` 호출, `(saleId, eventType)` 멱등 |
| 4-3 | 기존 커밋-후 직접 호출은 유지하되 성공 시 outbox 작업을 done 처리(즉시성 유지 + outbox 는 안전망) |
| 4-4 | 일일 대사: 외상 판매 합 ↔ 고객 원장 합 비교를 드리프트 크론에 추가(탐지·알람) |

- **게이트:** ledger 훅 강제 실패 주입 시 outbox 재시도로 원장 최종 기록 · 대사 크론이 불일치 탐지·Telegram

### W5. 로그인 다이어트 — P1

| # | 태스크 |
|---|---|
| 5-1 | `/me` 응답 실측 분해(47KB 권한 구조) → 웹·superadmin 앱·tienda-admin 3 소비자의 실사용 필드 전수 대조 |
| 5-2 | 권한을 slug 배열 중심으로 축소(목표 <10KB), 상세는 별도 엔드포인트 lazy |
| 5-3 | 권한 조립 결과 캐시(역할-버전 키, 재시드/역할변경 시 무효화) |
| 5-4 | 터미널·에이전트 재접속 지터(무작위 0~30초) — 정전 복구 동시 로그인 분산 |
| 5-5 | 스테이징 로그인 부하 재측정 — 목표 100건/s (현 60~70) |

### W6. 확장 가드 소품 — P1 (병렬)

| # | 태스크 |
|---|---|
| 6-1 | 부팅 검사: `PM2 instances > 1 && Redis 미가용` → error 로그 + health degraded (로컬 dev 다중워커 사고 방지) |
| 6-2 | 반복 경고 로그 부팅당 1회 억제(스키마 검사·Redis 경고) |
| 6-3 | 부하 25건/s 재측정 — Phase 65 무회귀 게이트 마감 (스테이징, 심야) |

### P2 — 착수 조건 명시 (지금 하지 않음)

- **hot-row 완화(41건/s)**: 단일 매장 피크 실측이 20건/s 를 넘을 때. 그 전에 손대면 정합성 회귀 위험만 얻는다
- **Redis 분산락 cron 리더 + API 2호기 + PG standby**: 컨테이너 2대 결정 시 한 묶음으로. 현재는 D-63-2 보류 결정 유지
- **pool 재계산**: 서버/워커 증설 시 `서버수×워커수×pool.max` 재산정 (현 1×4×20=80 vs pgbouncer 50 — 의도된 큐잉)

---

## 실행 순서와 승인 게이트

1. W2 → W3 (코드만, 즉시) → 배포·검증
2. W1 (마이그레이션 포함 — **UNIQUE 변경·재구축 SQL 사전 보고 후 승인**) → 재구축 실행
3. W4 → 배포 후 실패 주입 검증
4. W5·W6 병렬 (W5-2 는 3개 앱 필드 대조표 사용자 확인 후)
5. 완료 게이트: 세그먼트 교차 오염 0(측정 SQL) · SCHEMA_SYNC 로그 0 · 판매 tx abort 재현 불가 · ledger 불일치 대사 0 · 로그인 100건/s · 부하 25건/s 저장 실패 0
