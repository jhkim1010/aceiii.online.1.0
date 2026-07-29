# Phase 65: 재고 원장 단일 진실 · 테넌트/감사 경계 · 장애 감지 — Execution Plan

**Created:** 2026-07-28
**Verified against:** HEAD `dcc7610` (2026-07-28) — 진단서(`b02ac0d` 기준)의 file:line 주장을 본 PLAN 작성 시점에 전수 재검증
**Source:** `65-CONTEXT.md` · `65-SPEC.md` (R1~R9)
**원칙:** 신규 기능 0, 전부 무회귀 교정. CLAUDE.md 쓰기 경로 규약(단일 트랜잭션·append-only·트랜잭션 안 외부 I/O 금지·락 순서 고정) 준수.

---

## 0. 진단서 검증 결과 (이 PLAN 의 전제)

2026-07-28 HEAD `dcc7610` 에서 진단서의 핵심 주장을 코드로 재확인한 결과:

| 주장 | 판정 | 비고 |
|---|---|---|
| `stocks` UPDATE/DELETE 9곳 잔존 (`productStock.service.ts:622/629/914/1493` destroy, `:401/483/727` update, `products.service.ts:431`, `subcon-material-issue.service.ts:59`) | **사실** | 라인 전부 일치 |
| union 밖 이동유형 `'ajuste'`(`stocks.service.ts:151`)·`'produccion'`(`work-order.service.ts:209/232`) | **사실** | 코크핏 필터 `NOT IN ('adjust','suspend')` 4곳(`:499/502/739/742`)도 확인 |
| movido/fallado 가 `products.stock` 캐시 미갱신 | **사실** | `stocks.service.ts` 이동 경로는 Stocks INSERT 만 수행 |
| 재고 대조 크론 0건 / `mp-wallet-reconcile.cron.ts` 이식 가능 | **사실** | reconcile 매치 0건, MP 크론 존재 |
| `audit-log.controller.ts` — entity 라우트 `@GetUser` 없음, store 라우트 역할 없으면 전체 공개 | **사실** | 코드 원문 확인 |
| `users.service.ts` `adminUpdateUser` — `findByPk` 만, `dto.storeId` 무조건 반영 | **사실** | `:299`(findByPk), `:322`(storeId) 확인 |
| 마이그레이션 10개 파일에 `PGPASSWORD` 평문 커밋 | **사실** | `grep -rl` 10건 |
| CORS `origin: true` + credentials (`main.ts:55`) | **사실** | `app.enableCors` 재호출까지 확인 |
| `enableShutdownHooks` 0건 / `/health` 라우트 0건 | **사실** | grep 0건 |
| function guard fail-open ("function 이 DB 에 없으면 통과") | **사실** | 주석 원문 그대로 |
| CLAUDE.md pool 표기(min=10/max=80)와 실제(min=2/max=20) 불일치 | **사실** | `database.module.ts` 주석에 2026-07-25 변경 이력 |

**진단서보다 실제가 더 나쁜 것 (신규 발견 2건, W2 에 반영):**

1. `stocks` 모델에 `productId` 컬럼이 **존재하지 않는다** (`productBranchId` 만 존재).
   따라서 `products.service.ts:431` 과 `subcon-material-issue.service.ts:59` 의
   `stockModel.findOne({ where: { productId } })` 는 원장을 덮어쓰는 게 아니라 **런타임 SQL 에러**를 낸다
   — Phase 64 가 생산 완료 경로에서 발견한 것과 동일 계열의 결함. 즉 상품 수정 시 stock 반영과 외주 자재 출고 재고 차감은
   **현재 조용히 무동작/에러**일 가능성이 높다. W2 에서 단순 "update→보정 행 교체"가 아니라 **조회 키 교정부터** 해야 한다.
2. movido/fallado 는 `type='adjust'` 로 기록되므로 코크핏 입출고 집계에서 **이동 물량이 통째로 빠진다**.
   W1 백필 때 이동/폐기를 별도 유형으로 분리할지 정책 결정 필요 (아래 W1 Open Point).

---

## Wave 실행 순서

```
W1 → W2 → W3 → W4 → W5   (재고 계열, 선형 의존)
W6 · W7 · W8              (병렬 가능 — 단 W7 은 단독 배포 창)
W9                        (마지막)
```

각 Wave = 독립 배포 단위. Wave 내 태스크는 순서대로. **매 Wave 종료 시: `npx eslint` 0 오류 + `tsc --noEmit` 통과 + Phase 64 동시성 스위트 회귀 확인.**

---

## W1. 이동유형 표준화 (R1)

| # | 태스크 | 파일 |
|---|---|---|
| 1-1 | `StockMovementType` 을 `'sale' \| 'adjust' \| 'suspend' \| 'production'` 으로 확장 + 값 상수(`STOCK_MOVEMENT_TYPES`) 중앙화 | `stocks/stocks.model.ts` |
| 1-2 | 기록부 교체: `'ajuste'→'adjust'`(`stocks.service.ts:151`), `'produccion'→'production'`(`work-order.service.ts:209/232`) — 문자열 리터럴 대신 상수 사용 | `stocks/stocks.service.ts`, `production/work-orders/work-order.service.ts` |
| 1-3 | 코크핏 필터 교정: 입출고 집계에서 `'production'` 도 제외하고 생산 물량을 별도 컬럼(`producidos`)으로 노출 (기존 `reservados` 방식) | `reports/reportsStocksCockpit.service.ts` (4곳) |
| 1-4 | 백필 마이그레이션 — `UPDATE stocks SET type='adjust' WHERE type='ajuste'` + `'produccion'→'production'`. 사전 측정 SELECT 포함, 멱등 | `migrations/2026-07-XX-phase65-w1-stock-type-normalize.sql` |
| 1-5 | grep 게이트 스크립트: union 밖 type 리터럴 0건 검증 | `.planning/phases/65-.../gates/` |

- **게이트:** 코드 grep 0건 · `SELECT type, count(*) FROM stocks GROUP BY type` 이 union 값만 반환 · 코크핏 백필 전후 수치 비교표 기록
- **주의:** 백필은 되돌리기 어려움 → **사전 측정 결과를 사용자에게 보고하고 승인 후 실행** (로컬 5432 + 운영 5434 동시, `--single-transaction`)
- **Open Point:** 이동(movido)·폐기(fallado)를 `'adjust'` 에 계속 둘지 `'transfer'`/`'writeoff'` 로 분리할지 — 분리 시 리포트 의미가 좋아지나 백필 범위 증가. 착수 전 사용자 결정.

## W2. 원장 불변 전면 적용 (R2)

| # | 태스크 | 파일 |
|---|---|---|
| 2-1 | `stocks.service.ts` 의 `adjust()` 보정-행 패턴을 재사용 가능한 헬퍼로 추출 — `transaction` **필수 인자**, `productBranchId` 기준, FOR UPDATE 락, `products.stock` 동시 조정 | `stocks/stocks.service.ts` |
| 2-2 | `productStock.service.ts` destroy 4곳(`:622/629/914/1493`)을 보정 행 방식으로 교체 (당일 입고 0 처리·잔여 정리·`deleteStockTodayByParent`·madre 색상 삭제) | `products/productStock.service.ts` |
| 2-3 | 절대값 덮어쓰기 3곳(`:401/483/727`)을 "목표값 − 현재 원장합" 델타 보정 행으로 교체 | 〃 |
| 2-4 | **조회 키 교정 + 교체**: `products.service.ts:431`, `subcon-material-issue.service.ts:59` — 존재하지 않는 `productId` 조회를 `productBranchId` 경유로 교정하고 보정 행 방식 적용. 기존에 무동작이었는지 로그로 확인 후 동작 복원 | `products/products.service.ts`, `subcon/subcon-material-issues/…` |
| 2-5 | DB 안전망 트리거 — `stocks` UPDATE/DELETE 차단 (`BEFORE UPDATE OR DELETE … RAISE EXCEPTION`). 신규 객체 owner `coolsistema` DO 블록 포함 | `migrations/2026-07-XX-phase65-w2-stocks-immutable-trigger.sql` |
| 2-6 | grep 게이트 확장: 전 저장소에서 `stockModel.destroy\|stockRecord.update\|stock.update` 0건 | gates |

- **게이트:** grep 0건 · 트리거 위반 시도 실패 확인 · 기존 라우트(`products.controller.ts:414` 등) 응답 형태 불변 · 유닛 스모크
- **주의:** 트리거는 로컬+운영 동시 적용. 배포 순서 = **코드 먼저, 트리거 나중** (역순이면 기존 코드가 500).

## W3. 캐시 갱신 누락 봉합 (R3)

| # | 태스크 | 파일 |
|---|---|---|
| 3-1 | movido/fallado 경로 — 같은 트랜잭션에서 `products.stock` 증감 (origin −, target +). 락 순서 productId 오름차순 | `stocks/stocks.service.ts` |
| 3-2 | 외주 로트 입고 `ingresarStockPorMatrix`(`productStock.service.ts:89`) — 동일 트랜잭션 캐시 증가 | `products/productStock.service.ts` |
| 3-3 | `createVariantsBatch`(`:265-333`) — 자식 상품 `stock` 초기값 명시 | 〃 |
| 3-4 | `updateMotherStock`(`:358-372`) — 자식 캐시 합 → **원장 합 기준**으로 전환 | 〃 |
| 3-5 | 실패 주입 유닛 테스트 — 트랜잭션 중간 실패 시 원장·캐시 동시 롤백 확인 | spec 파일 (※ VM jest 금지 — 러너/Mac 에서 실행) |

- **게이트:** 이동 1건 후 `products.stock` = 원장 합(예약 제외) · 로트 입고가 POS 검증에 즉시 반영 · 신규 변형 캐시 정확

## W4. 가용재고 정의 단일화 (R4)

| # | 태스크 | 파일 |
|---|---|---|
| 4-1 | on-hand / reserved / available 3값 정의 문서화 + 단일 계산 함수(`StockValuationService` 또는 SQL 뷰) | `stocks/` 신규 |
| 4-2 | 4개 경로 수렴: `reportsStocksCockpit.service.ts:575` · `reportsAlertas.service.ts:74-89` · `productStock.service.ts:1185-1192`(is_active 누락 교정) · `offline-sync/table-registry.ts:191-195` | 각 파일 |
| 4-3 | 값이 달라지는 화면 목록화 → 사용자 사전 고지 | 문서 |

- **게이트:** 같은 상품·지점에 대해 4개 경로 동일 값 · 차이 발생분은 필터 교정으로 설명 가능

## W5. 정합성 대조·보정 자동화 (R5)

| # | 태스크 | 파일 |
|---|---|---|
| 5-1 | **읽기 전용 드리프트 측정** (운영, 예약분 제외 정확 쿼리) — 건수·금액 규모 보고. *운영 조회는 SSH read-only 로 기본 허용* | 측정 SQL |
| 5-2 | 야간 대조 크론 — `mp-wallet-reconcile.cron.ts:27-65` 패턴 이식. 탐지→로그→임계 초과 시 Telegram. **자동 보정 기본 OFF** (설정 플래그). 크론 리더 가드(`NODE_APP_INSTANCE===0`) 준수, 쿼리는 배치 1회로 pool 점유 최소화 | `stocks/cron/stock-reconcile.cron.ts` 신규 |
| 5-3 | 1회 백필 — 측정 결과 승인 후, **보정 행 INSERT 방식**으로 캐시 정정 (원장 파괴 금지) | 백필 스크립트 |
| 5-4 | `GET /api/diagnostics/stock-drift` (superadmin) — 기존 diagnostics 3종과 동일 형태 | diagnostics 컨트롤러 |
| 5-5 | Centro de Control `infraestructura` 위젯에 드리프트 건수 추가 | `dashboard-admin.service.ts` |

- **게이트:** 백필 후 0건 → 야간 크론 지속 0 · 의도적 드리프트 주입 테스트에서 탐지+알람 · 진단 API 동작
- **주의:** 백필은 되돌리기 어려움 → **별도 승인 + 롤백 계획(백필 전 스냅샷 테이블)** 필수

## W6. 감사·사용자 매장 경계 (R6) — 재고 계열과 병렬 가능

| # | 태스크 | 파일 |
|---|---|---|
| 6-1 | `GET /auditlog/entity/...` — `@GetUser` 추가, 대상 엔티티의 store 스코프 검증 (superadmin 은 `?storeId=` 명시) | `audit-log/audit-log.controller.ts:37-42` + service |
| 6-2 | `GET /audit-log/store` — fail-open 제거: 역할 판정 실패 = **403** (전체 공개 아님) | `:50-53` |
| 6-3 | `adminUpdateUser`/`remove` — 대상 유저 `storeId` 를 요청자 스코프와 대조, 불일치 403. `dto.storeId` 반영은 superadmin 전용(일반 admin 400) | `users/users.service.ts:299-330` |
| 6-4 | `approve()` 자가 승인 차단 — `approverId !== requestedBy` + `approver_role_slug` 대조 | `approval.service.ts:168-203` |
| 6-5 | 회귀 테스트 — 타 매장 접근 403 고정 spec (Phase 64 W7 수준) | spec 파일 |

- **게이트:** 크로스테넌트 조회/수정/삭제 403 · 역할 없는 사용자가 전체 로그 못 받음 · 자기 매장 정상 흐름 회귀 0
- **주의:** superadmin 앱(ventago-admin-app)과 tienda-admin-app 이 이 라우트들을 쓰는지 사전 확인 — 앱 회귀 주의 (admin 앱 인증은 JWT-only, SessionGuard 추가 금지 규약 유지)

## W7. 자격증명 위생 (R7) — 단독 배포 창에서 실행

| # | 태스크 |
|---|---|
| 7-1 | 마이그레이션 10개 파일에서 `PGPASSWORD` 평문 제거 (환경변수 참조로 재작성) — 대상: `extract-and-build-payload.sh`, `backfill-default-color-size-for-all-stores.sql`, `20260422-cost-sheet-step1/2`, `20260421-talleres-qc`, `20260424-phase25-step1/2`, `add-use-variants-to-stores.sql`, `20260422-vendor-etapa-step1`, `add-is-active-to-stocks.sql` |
| 7-2 | `env.config.ts:15-16` 하드코딩 폴백 제거 + `email-secret.ts:24` 고정 문자열 폴백 제거 → 미설정 시 부팅 실패 |
| 7-3 | 접속 주체 목록화(앱·pgbouncer·백업 크론 03:17·Jenkins·운영자 `.pgpass`·`venpsql`) → **DB 계정 비밀번호 회전** — 순서: 신규 비번 설정 → 각 주체 갱신 → 검증 → 구 비번 폐기 |
| 7-4 | 시크릿 스캔 게이트 (grep `PGPASSWORD\|password.*=.*['"]` 마이그레이션 스코프) |

- **게이트:** 저장소 평문 자격증명 0건 · 시크릿 미설정 시 부팅 실패 · 회전 후 전 주체 정상 동작 (특히 03:17 백업 크론 다음날 확인)
- **주의:** **회전은 파괴적 작업 — 사용자 명시 승인 + 롤백 계획 필수.** 다른 Wave 배포와 겹치지 않는 창에서 단독 실행. git 이력의 구 값은 회전으로 무력화(이력 재작성 범위 밖).

## W8. 장애 감지 최소셋 (R8) — 병렬 가능

| # | 태스크 | 파일 |
|---|---|---|
| 8-1 | `GET /health` — DB `SELECT 1` + Redis ping, 결과 5초 캐시로 pool 잠식 방지, 무인증 | `app.controller.ts` 또는 `health/` 신규 |
| 8-2 | docker-compose API healthcheck (`curl -f /health`) + `restart: always` 연계 확인 | `api-ventago/docker-compose.yml` |
| 8-3 | 외부 uptime 감시 — 서버 **외부**에서 `/health` 주기 확인, 실패 시 Telegram. 위치는 Open Question 5 (제안: 무료 uptime 서비스 → Telegram webhook) | 외부 설정 + 문서 |
| 8-4 | `app.enableShutdownHooks()` + SIGTERM 드레이닝 — `database.module.ts:266` pool 정리 훅이 실제 트리거되게. PM2 `kill_timeout` 정합 확인 | `main.ts`, `ecosystem.config.js` |
| 8-5 | 알람 2종 — pool waiting>0 지속, outbox lease 초과 (Centro de Control `infraestructura` 위젯 확장, 신규 인프라 없음) | `dashboard-admin.service.ts` + 알람 |

- **게이트:** 프로세스/DB 중단 실험 → 60초 내 알림 · SIGTERM 시 in-flight 정상 종료 + pool 정리 로그 · `/health` 가 pool waiting 을 만들지 않음
- **주의:** 컨테이너 재시작 실험은 **운영이 아닌 스테이징(api_staging:5012)에서 먼저**. 운영 재시작은 사용자 승인.

## W9. Phase 64 마감 + 문서 동기화 (R9) — 마지막

| # | 태스크 |
|---|---|
| 9-1 | Phase 64 브라우저 UAT 12건 실행·기록 (멱등 재시도·취소·보류·생산·generic 판매·식당 주문) → `65-VALIDATION.md` |
| 9-2 | `.planning/intel/` 재생성 (`db-schema.regen.sh`, 로컬 PG18 — 사용자 Mac 실행) |
| 9-3 | ROADMAP(0/10 표기 정정)·STATE(Phase 63/64/65 반영) 동기화 |
| 9-4 | `DATABASE_SCHEMA.md` Stocks 정의 갱신 (type·note·operationDate·isActive) |
| 9-5 | CLAUDE.md pool 표기 교정 — 실제 값 min=2/max=20 × 4워커 (2026-07-25 조정 반영) |
| 9-6 | 멱등키 `purgeExpired` 를 기존 cron 태스크에 연결 (신규 스케줄러 금지) |

- **게이트:** 문서 = 코드 상태 일치 · UAT 결과 기록됨

---

## 승인 게이트 요약 (사용자 확인 필수 지점)

| 시점 | 내용 | 이유 |
|---|---|---|
| W1-4 실행 전 | type 백필 사전 측정 결과 + SQL | 운영 DML, 되돌리기 어려움 |
| W1 착수 전 | movido/fallado 유형 분리 여부 결정 | 백필 범위 확정 |
| W5-3 실행 전 | 드리프트 측정 결과 + 백필 SQL + 스냅샷 계획 | 운영 DML, 되돌리기 어려움 |
| W5 크론 정책 | 자동 보정 ON/OFF (제안: 2주 탐지만) | 잘못된 자동 보정 위험 |
| W7-3 실행 전 | 회전 창·주체 목록·순서 | 운영 중단 위험 |
| W8 운영 재시작 실험 | 실험 시각 | 서비스 영향 |

## 무회귀 게이트 (Phase 전체, 매 Wave 배포 전)

- `npx eslint` 0 오류 (front lint 규칙: newline-before-return · lines-around-comment · no-unused-vars 주의)
- `tsc --noEmit` 통과 (기존 잔여 1건 외 신규 0)
- Phase 64 동시성 스위트 8종 통과 유지 (러너/Mac 실행 — VM jest 금지)
- 마이그레이션은 로컬(5432)·운영(5434) **동시 적용** + 신규 객체 owner `coolsistema`
- 트랜잭션 안 외부 I/O 금지 · 헬퍼 `transaction` 필수 인자 · 락 순서 productId 오름차순
- 배포 후 마지막 로그 파일(`logs/error-*.log`, pm2) 확인 — 신규 에러 0
