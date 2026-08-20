# Phase 85 — 실측 (2026-08-19, HEAD `84fa3fd`)

## 계기

사용자 질문: *"300개 매장이 될 때에도 문제가 없도록 하는 것이 중요하다."*

착수 배경 메모: `.planning/ADVISOR-2026-08-19-승산과-300매장.md`

## ★ 한 줄

**지켜진 규약과 무너진 규약의 차이는 개발자의 성실함이 아니라 강제 지점의 유무다.**

백엔드에서 살아남은 것은 전부 "위반이 불가능한" 형태였고(필수 인자·DB 트리거·기본 stop),
프론트에서 무너진 것은 전부 "문서에만 있는" 형태였다(pageSize 50 · SWR 사용 · 소켓 1개).
지적된 지 19일이 지난 지금 후자는 하나도 고쳐지지 않았고 **오히려 신규 위반이 늘었다.**

---

## A. 2026-07-31 리뷰 지적 항목 재점검 (코드 실측)

문서가 아니라 현재 코드를 읽어 판정했고, 판정 오류를 막기 위해 **반증 조사를 별도로 한 번 더** 돌렸다.
그 결과 **초기 판정 2건이 뒤집혔다**(B-4, B-7). 아래는 반증 후 최종값이다.

| # | 항목 | 판정 | 근거 |
|---|---|---|---|
| A-1 | 테넌트 격리 CR-01/02/03 | ✅ 해결 | Phase 69 전건 봉쇄 + 회귀 테스트. 잔여: 운영 env `TENANT_DERIVED_MODE` 실물값 확인 |
| A-2 | 자동 `sequelize.sync` | ✅ 해결(초과 달성) | Phase 66 W2 에서 sync **삭제**. `sync.service.ts:35-70` 이 sentinel 3개 존재만 읽기전용 검사 → 누락 시 `SCHEMA_CHECK_FAILED` + `/api/health.schema` |
| A-3 | 매장별 논리 복구 | ❌ 미해결 | 전체 덤프·`tools/backup-freshness-watchdog.sh`·전체 복원(`infra/stage/04-restore.sh`) 완비. **`store_id` 하나만 되돌리는 경로 없음** |
| B-4 | pool 예산 | ✅ 해결(**판정 뒤집힘**) | `SHOP_DB_ISOLATED` 명시 플래그(`shop-readonly-db.service.ts:31-56`), 예산 단일출처 `common/config/connection-budget.ts`(replica×worker 반영) |
| B-5 | 요청 증폭 | ❌ 미해결 **+ 신규 위반** | 아래 표 |
| B-6 | cache single-flight | ❌ 미해결 | `getOrLoad` 류 **0건**. `MemoryCacheService` 주입 파일 **38개** 전부 `get→miss→DB→set` |
| B-7 | 판매 재고 | ⚠️ 부분해결(**판정 뒤집힘**) | 잠금은 완결, 쓰기는 미완 — 아래 |
| B-8 | 소켓 탭당 1개 | ❌ 미해결 **+ 악화 중** | 아래 |
| B-9 | 크론 중복 | ✅ 해결(초과 달성) | lease 2겹 + `main.ts:207-236` 이 lease 판정 **전** SchedulerRegistry 전 job `.stop()`. `@Cron` 24건 전부 게이트 대상 |

### ★ B-4 는 왜 뒤집혔나 — 비교의 층위가 틀렸다

"워커 max 20×4=80 vs pgbouncer pool_size 50" 이라는 비교 자체가 **카테고리 오류**다.
`connection-budget.ts:14-17` 이 이미 이렇게 적어 두었다:

> 앱→pgbouncer 합계의 상한은 `max_client_conn`(1000)이지 `pool_size`(50)가 아니다.
> **두 값을 같은 자로 재면 정상 구성을 결함으로 오판한다.**

transaction pooling 에서 앱 클라이언트 수가 `pool_size` 를 넘는 것은 정상이고 큐잉으로 흡수된다.
실제 포화 지표 `cl_waiting` 은 **앱이 아니라** `scripts/ops-daily-check.py:291-328` 이 5분 주기로
수집하고 `>0` 이면 WARN 알림한다(`:659-661`). 앱이 pgbouncer admin 콘솔을 폴링하지 않는 것이 옳은 배치다.

**교훈: 리뷰 문서의 판정도 낡는다. 착수 전 코드 대조는 예외가 없다.**

### ★ B-7 은 왜 뒤집혔나 — 잠금과 쓰기를 하나로 봤다

| 구간 | 상태 | 근거 |
|---|---|---|
| 잠금 | ✅ 단일 문장 bulk | `sales-create.service.ts:1711-1751` `unnest($2,$3)` + `ORDER BY … FOR UPDATE OF sb` |
| 트랜잭션 내 외부 I/O | ✅ 없음 | 프린터·AFIP·소켓 전부 `afterCreateCommit()` (`:809-941`) |
| 취소·수정 경로 | ✅ 동일 규칙 재사용 | `sales-modify.service.ts:428` |
| **원장 쓰기** | ❌ **품목당 순차** | `:1884-1900` `ProductBranch.findOne → create → Stocks.create` 루프 = 최대 **3N 쿼리** |

`bulkCreate` 는 `sale_items` 에만 적용돼 있다(`:2091-2104`). 두 개를 같은 것으로 오인했다.
락을 **잡은 뒤** 이 루프를 돌기 때문에 **락 보유 시간이 품목 수에 비례**한다.

### B-5 실측 — 지적된 5곳 중 4곳 원값 유지, 신규 2곳 추가

| 위치 | 값 | 상태 |
|---|---|---|
| `ProductList.tsx:274` | **1000** | 그대로 (POS 핵심 경로) |
| `DraftAndDebtorsList.tsx:279` | **1000** | 그대로 |
| `DailySalesStats.tsx:60` (지출) | **9999** | 그대로 — 판매 집계만 서버 GROUP BY 로 전환됨 |
| restaurante 3곳 | 200 | 그대로 |
| `talleres_LotesListView.tsx:112-114` | 100·100·200 | 그대로 |
| `InvoiceAditional.tsx:70-71` | 100×2 | **신규 위반** |
| `AccessLogsView.tsx:41` | 200 | **신규 위반** |

`ventago-app/src` 전체에서 pageSize 51 이상 하드코딩 **19곳** (거친 집계).

★ **부분 수정이 더 위험하다.** `DailySalesStats` 는 판매 집계만 고쳐져 "해결된 것처럼" 보이지만
같은 파일 같은 함수 안에 9999 가 남아 있다.

### B-8 실측 — 미해결이 아니라 **복제 중**

| 훅/모듈 | 위치 | 상태 |
|---|---|---|
| `useThermalAgentStatus` | `:78` | 개별 `io()` |
| `useSuspendedSaleSocket` | `:41` | 개별 `io()` |
| `useMpApprovedSocket` | `:33` | 개별 `io()` |
| **`utils/catalog-refresh.ts`** | `:134` | **신규** — 주석에 *"기존과 같은 형태"* 라고 쓰고 안티패턴을 복제 |

공유 provider/context **0건**. POS 탭 하나에 3개(결제 모달 열면 4개).
`PrinterConfigTab.tsx:90` 30초 폴링도 잔존 — 같은 리팩터가 **절반만** 적용됐다.

★ 이것이 이 Phase 의 존재 이유다. **provider 를 만들어도 다음 사람이 `io()` 를 또 부른다.**
실제로 그렇게 됐다.

---

## B. 300매장에서 **새로 생기는** 문제 (패치로 안 잡힌다)

위 A 항목을 전부 고쳐도 남는 것들이다. 공통점: **지금은 공짜인데 나중엔 불가능하다.**

| # | 문제 | 지금 상태 | 300매장에서 |
|---|---|---|---|
| C-1 | 배포 다운타임 | nginx upstream 1개(`infra/stage/06-nginx-ssl.sh:92,112`) + `docker compose up`. 블루/그린·롤링 **없음** | 배포 1회 = **300건 동시 판매 중단** |
| C-2 | 마이그레이션 락 | 마이그레이션 306개, 테이블 209개. 무중단 마이그레이션 규약 **없음** | 큰 테이블 `ALTER … NOT NULL` = 전 고객 동시 정지 |
| C-3 | 원장 볼륨 | `stocks` append-only(`trg_stocks_immutable`). 파티셔닝 흔적 **0건** | 300 × 100건/일 × 3년 ≈ **3억 행**. 파티셔닝은 테이블이 작을 때만 무통증 |
| C-4 | 집계 동시성 | 대시보드 TTL 30초 캐시 = 요청 시 계산 | 300매장이 월초에 **같이** 월말 보고서를 돌린다 |
| C-5 | 카탈로그 크기 편차 | POS 가 상품 전량(1000)을 받아 클라이언트 필터 | 상품 5만 개 매장이 들어오면 1000 으로도 안 된다 — 페이지네이션이 아니라 **검색·delta sync** 문제 |
| C-6 | 부하 리그 부패 | 309매장 스테이징 존재하나 **손 절차**. `loadtest/README.md` 에 *"쓰지 않는 동안 조용히 낡는다"* 자기 기록 + 되살릴 때 2건 걸림 | 손 절차는 반드시 안 돈다 |
| C-7 | 관측이 게이트가 아니다 | route p95 342ms(08-07) → 664ms(08-08). 규약은 300ms | **측정만 되고 아무것도 막지 않는다.** 막지 않는 규약은 규약이 아니다 |

---

## C. 저장소에 이미 있는 **정답 패턴** (새로 발명할 필요 없음)

이 Phase 는 새 기법을 도입하지 않는다. **이미 이 저장소에서 작동이 증명된 형태를 프론트로 옮긴다.**

| 성공 사례 | 강제 지점 | 결과 |
|---|---|---|
| 표 밀도 30px | `FullTable` 기본값이 상수를 읽음 — *"아무것도 안 하면 맞는다"* (CLAUDE.md) | 유지됨 |
| CR-02 `scope` | **필수 위치 인자** — 빠뜨리면 컴파일 실패 (`productStock.service.ts`) | 유지됨 |
| `stocks` 불변 | **DB 트리거** `trg_stocks_immutable` | 유지됨 |
| 크론 리더 | **기본 `.stop()`**, 리더만 `.start()` (`main.ts:207-236`) | 유지됨 |
| 파생 스코프 | **기본값 `enforce`** (`tenant-scope.registry.ts:284`) | 유지됨 |
| 청구 계산 | **순수 함수 + `formulaVersion`** (`billing-calculator.ts`) | 유지됨 |
| — 대조 — | | |
| pageSize ≤ 50 | 문서만 | ❌ 19곳 위반 + 신규 발생 |
| SWR 참조데이터 | 문서만 | ❌ 미전환 |
| 소켓 1개 | 문서만 | ❌ 복제 중 |

**규칙: CLAUDE.md 의 모든 규약은 그것을 강제하는 코드 위치를 가져야 한다. 없으면 그 규약은 없는 것으로 친다.**

---

## D. 최신 로그 확인 (GSD 1단계 필수)

| 로그 | 내용 | 이 Phase 와의 관계 |
|---|---|---|
| `api-ventago/logs/error-2026-08-12.log` | `RecepcionService.createRecepcion` 검증 ROLLBACK 다수 — 대부분 **의도된 거부**(수량 불일치·타 매장 지점·초과 입고). 단 `17:50:06` 에 `current transaction is aborted` → **500** 1건 | Phase 84 영역. 이 Phase 범위 아님 — 단 "검증 실패 후 같은 트랜잭션 재사용" 패턴은 W1 착수 시 참고 |
| `ventago-app/logs/error-2026-08-19.log` | `Failed to compile.` (04:47) + webpack deprecation warning | **W1 착수 전 로컬 빌드가 통과하는지 먼저 확인할 것.** 깨진 상태에서 시작하면 원인이 섞인다 |
| pool 관련 | `error-2026-07-29` 이후 `ConnectionAcquireTimeout`·`too many clients` **0건** | B-4 판정과 일치 |

---

## E. 미측정 — 착수 시 반드시 채울 것

이 Phase 의 W4(파티셔닝)는 실제 행 수 없이 계획할 수 없다. **추측 금지.**

```bash
# 운영(읽기 전용) — 파티셔닝 대상 판정의 유일한 근거
ssh jhkim-server "sudo -u postgres psql -p 5434 -d ventago -c \
 \"SELECT relname, n_live_tup, pg_size_pretty(pg_total_relation_size(relid)) AS total \
     FROM pg_stat_user_tables ORDER BY n_live_tup DESC LIMIT 20;\""
```

- [ ] `stocks` / `sales` / `sale_items` / `stock_balances` / `sync_outbox` 현재 행 수·크기
- [ ] 운영 컨테이너 env 의 `TENANT_DERIVED_MODE` 실물값 (A-1 잔여)
- [ ] 운영 `PGBOUNCER_POOL_SIZE` / `API_REPLICA_COUNT` / `WEB_CONCURRENCY` 실물값
- [ ] 최근 7일 `cl_waiting` 피크 (`ops-metrics` samples)
