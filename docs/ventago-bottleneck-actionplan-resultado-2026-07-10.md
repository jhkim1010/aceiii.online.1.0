# 병목 액션플랜 실행 결과 (2026-07-10)

원본 분석: `docs/ventago-analisis-bottleneck-2026-07-10.md`
브랜치: `feat/factura-electronica` (3 repo). 각 Step 개별 커밋 + push 완료.

---

## Step 1 — DB 안전밸브 타임아웃 ✅

- 파일: `api-ventago/migrations/db-safety-timeouts.sql`
- 로컬(5432) 적용 완료. 검증:
  - `statement_timeout=30s`, `lock_timeout=10s`, `idle_in_transaction_session_timeout=60s` (ALTER DATABASE 반영 확인).
- 근거: 2026-07-09 마지막 로그 `[Outbox] outbox tick 오류: Operation timeout` + sync_outbox 최대 157초 락 대기.
- **운영(5434) 수동 적용 대기** — ALTER DATABASE 는 트랜잭션 밖 실행(`--single-transaction` 미사용).

## Step 2 — 부팅 순서 가드 ✅

- 파일: `outbox.cron.ts`, `sync.service.ts`, `migrations/app-boot-flags.sql`
- **OutboxCron**: `OnApplicationBootstrap`(전 모듈 onModuleInit 완료) + 15s 안정화 유예까지 tick 스킵 → sequelize.sync 의 ALTER/ADD FK ACCESS EXCLUSIVE 락과 경합 회피.
- **backfillDailyNumbers**: `app_boot_flags` 영속 플래그로 완료 후 매 부팅 sales 전체 COUNT(운영 1.2s) 생략. 플래그 테이블 미적용 환경은 COUNT 폴백(무회귀).
- 로컬 `app_boot_flags` 테이블 생성 확인.
- 디버그 로그: 부팅 진행중/유예중/플래그 스킵 상태 추적.

## Step 3 — FK 인덱스 + ANALYZE ✅

- 파일: `perf-indexes-fk.sql`(로컬 일반), `perf-indexes-fk.concurrent.sql`(운영 CONCURRENTLY)
- 로컬 적용 + `vacuumdb --analyze-only` 완료. 검증:
  - 신규: `idx_sale_items_sale_id`, `idx_sale_items_product_id`, `idx_prices_product_id`(복합), `idx_sales_client_id`(partial).
  - 중복 `products_sku_store_id` 제거(= true). `uq_products_sku_store` UNIQUE 제약 유지.
- 참고: 로컬 EXPLAIN 은 소량 데이터라 Seq Scan 선택(플래너 정상). 인덱스는 운영 규모에서 발효 — 문서 예측대로.
- **운영은 CONCURRENTLY 파일 사용** (세션 한정 안전밸브 해제 SET 포함, 트랜잭션 블록 금지).

## Step 4 — Pool 재조정 ✅

- 파일: `database.module.ts`
- `pool.min: 10 → 2` (유휴 상시 점유 축소, 실사용 using=1).
- `max: 80` 유지. 주석의 잘못된 "PG max_connections=300" → 실측 **100** + 2인스턴스 복귀 시 총 160>100 초과 위험 명시.

## Step 5 — 사이드바 리렌더 3종 ✅

- 파일: `SidebarFooter.tsx`, `VerticalNavGroup.tsx`, `VerticalLayout.tsx`, `UserLayout.tsx`
1. **SidebarFooter**: 시계 → `SidebarClock`(memo) 분리로 매초 리렌더를 시계로 한정. 모달 3개를 `open && <Modal/>` 조건부 마운트로 전환.
2. **VerticalNavGroup**: route-change effect 에 멤버십 변경 가드 — 실제 변경 시만 setState(이전: 그룹 수만큼 무조건 새 배열 → nav 트리 리렌더 연쇄).
3. **VerticalLayout**: `toggleNavVisibility` useCallback+함수형 updater → `memo(Navigation)` 부활. `UserLayout` 의 `settings.layout` 렌더 중 직접 변이 제거 → effect+saveSettings.
- tsc 타입에러 0, ESLint 0 error(1 warning = 기존 exhaustive-deps, 경고레벨 비차단).

---

## 검증 (Step 6)

| 항목 | 상태 |
|---|---|
| 로컬 DB 안전밸브 3종 | ✅ 적용 확인 |
| app_boot_flags 테이블 | ✅ 생성 확인 |
| 인덱스 4종 + 중복 제거 | ✅ 확인 |
| 프론트 tsc / ESLint | ✅ 0 error |
| 부팅 로그 SlowQuery 🔴 소멸 | ⏳ 다음 백엔드 재기동 후 확인(이 환경 재기동 불가) |
| 사이드바 Profiler 유휴 리렌더 0 / 라우트당 nav ≤2 | ⏳ 브라우저 UAT 대기(인증+백엔드 필요) |

## 운영 적용 잔여 (수동, 5434)

1. `db-safety-timeouts.sql` (트랜잭션 밖 실행)
2. `app-boot-flags.sql`
3. `perf-indexes-fk.concurrent.sql` (CONCURRENTLY, 세션 안전밸브 해제 포함)
4. 적용 후 `vacuumdb --analyze-only -p 5434 -d ventago`
5. api-ventago / ventago-app 배포(Jenkins) → 부팅 로그에서 sync_outbox 🔴 + tick 스킵 반복 소멸 확인.

## 로컬 적용 명령 (사용자 Mac, 참고)

이미 이 세션에서 로컬 5432 적용 완료. 다른 로컬 환경 재현 시:
```bash
psql -p 5432 -d ventago -f api-ventago/migrations/db-safety-timeouts.sql
psql -p 5432 -d ventago -f api-ventago/migrations/app-boot-flags.sql
psql -p 5432 -d ventago -f api-ventago/migrations/perf-indexes-fk.sql
vacuumdb --analyze-only -p 5432 -d ventago
```
