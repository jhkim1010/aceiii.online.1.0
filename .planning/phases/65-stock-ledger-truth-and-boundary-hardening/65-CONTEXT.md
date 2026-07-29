# Phase 65: 재고 원장 단일 진실 · 테넌트/감사 경계 · 장애 감지 — Context

**Gathered:** 2026-07-29
**Status:** Ready for planning
**Source:** `docs/VentaGo_현황진단서_20260729.pdf` (Phase 64 이후 재평가, 코드 실측) + 본 문서의 file:line 재검증

<domain>
## Phase Boundary

Phase 64 는 **"판매 한 건이 두 건이 되는 것"**을 막았다. Phase 65 는 **"재고 숫자가 조용히 틀어지는 것"**과
**"틀어진 것을 아무도 모르는 것"**을 막는다. 신규 기능 0 — 전부 무회귀 교정.

**포함 (결함 9건):**

| # | 결함 | 심각도 | Wave |
|---|------|--------|------|
| 1 | `stocks.type` 에 모델 union 밖 값(`'ajuste'`/`'produccion'`)이 기록되어 리포트 집계가 오염됨 | 높음 | W1 |
| 2 | 원장 불변(append-only) 규칙이 `stocks.service.ts` 한 파일에만 적용 — 다른 파일 9곳이 원장을 UPDATE/DELETE | 높음 | W2 |
| 3 | 이동(movido)·폐기(fallado)·로트 입고·변형 생성이 `products.stock` 캐시를 갱신하지 않음 → 구조적 드리프트 | 치명 | W3 |
| 4 | 가용재고(현재고/예약/가용) 정의가 경로마다 달라 같은 "재고"를 계산하는 SQL 이 4벌 | 중 | W4 |
| 5 | 원장-캐시 대조·보정 장치 전무 (재고 관련 크론 0건). 문서의 대조 SQL 조차 예약분을 오탐 | 치명 | W5 |
| 6 | 감사로그 2개 라우트가 매장 경계 없이 조회됨 (한 곳은 fail-open 이 **전체 공개**) | 높음 | W6 |
| 7 | 사용자 수정/삭제에 storeId 대조 없음 + `dto.storeId` 로 타 매장 이동 가능 | 높음 | W6 |
| 8 | 마이그레이션 SQL 10개 파일에 DB 비밀번호가 평문으로 커밋됨 | 높음 | W7 |
| 9 | 장애 감지 수단 부재 — 헬스체크·외부 uptime·graceful shutdown 없음 | 높음 | W8 |

**제외 (명시적):**
- **RLS 도입** — `docs/db-risk-analysis-20260727.md:105` 에서 **도입 금지**로 결정됨. pgbouncer transaction pooling 에서
  세션변수 RLS 는 오히려 테넌트 누출 위험 + superadmin 크로스매장 기능 파손. 이 결정을 뒤집지 않는다.
- **복합 FK `(id, store_id)`** — `sale_items` 에 `storeId` 컬럼 자체가 없어(`sales-item.model.ts` 확인) 컬럼 추가부터 필요.
  범위 과대. 애플리케이션 계층 강제로 대체한다.
- **완제품 안전재고·재주문점·자동발주·수요예측** — 재고 잔액이 정확해진 뒤에 착수. Phase 66 이후.
  *잘못된 잔액으로 발주를 자동 생성하는 시스템이 되면 안 된다.*
- **서버 2호기·read replica·nginx LB** — `spec-phase63:214` D-63-2 에서 보류 결정. W8 은 **감지**까지만 하고 **이중화**는 다루지 않는다.
- **SSO·MFA·SoD 규칙엔진·셀프서비스 BI·개발자 포털** — 영업 요구 확정 시.
- **로트→판매 연결(`sale_items.loteId`)·부분 반품/교환** — 스키마 확장이라 별도 Phase.
- **Phase 64 가 이미 해결한 것 재작업 금지** — 판매 멱등키, 취소·보류·생산 원자화, outbox claim/lease,
  조건부 재고 차감, 판매 경로 매장 경계는 **현행 유지**하고 그 위에 얹는다.

</domain>

<current-code>
## 현재 코드 위치 (2026-07-28 커밋 `b02ac0d` 기준, 전부 재확인됨)

### 결함 1 — 이동유형 값이 모델 정의 밖
- `api-ventago/src/app/stocks/stocks.model.ts:15` — `export type StockMovementType = 'sale' | 'adjust' | 'suspend'`
- `api-ventago/src/app/stocks/stocks.service.ts:151` — `type: 'ajuste'` ← **Phase 64 W7 이 도입한 보정 행**. union 밖(스페인어)
- `api-ventago/src/app/production/work-orders/work-order.service.ts:209` — `type: 'produccion'` (자재 소비, 음수)
- `api-ventago/src/app/production/work-orders/work-order.service.ts:232` — `type: 'produccion'` (완제품 입고, 양수)
- `api-ventago/src/app/reports/reportsStocksCockpit.service.ts:476` / `:479` / `:723` / `:726` —
  `(s.type IS NULL OR s.type NOT IN ('adjust','suspend'))` 로만 필터
- → **보정 행과 생산 행이 정상 입고·판매(salidas)로 집계된다.** Phase 64 가 도입한 장치가 리포트를 오염시키는 상태.
- 참고: 판매 차감 원장(`sales-create.service.ts:515` 부근)은 `type` 을 넣지 않는다(NULL = 일반). 이는 모델 주석과 일치.

### 결함 2 — 원장 불변이 한 파일에만 적용
Phase 64 W7 의 grep 게이트(`.destroy() → 0`, `stock.update( → 0`)는 **`stocks.service.ts` 스코프**에서만 참이다.
잔존(전부 `stocks` 테이블 대상):
- `api-ventago/src/app/products/productStock.service.ts:622` — `row.destroy()` (`correctTodayStocks`)
- `api-ventago/src/app/products/productStock.service.ts:629` — `row.destroy()` (잔여 행 정리)
- `api-ventago/src/app/products/productStock.service.ts:914` — `stockModel.destroy({...})` (`deleteStockTodayByParent`) — 라우트 `products.controller.ts:414`
- `api-ventago/src/app/products/productStock.service.ts:1493` — `stockModel.destroy({...})` (`editMadreVariants` 색상 삭제)
- `api-ventago/src/app/products/productStock.service.ts:401` / `:483` / `:727` — 원장 행 수량 절대값 덮어쓰기
- `api-ventago/src/app/products/products.service.ts:431` — `stockRecord.update({ stock })`
- `api-ventago/src/app/subcon/subcon-material-issues/subcon-material-issue.service.ts:59` — `stock.update({ stock: newStock })`
- DB 계층 강제(트리거/권한 분리) 없음 — 규약이 코드 리뷰로만 지켜진다.

### 결함 3 — 캐시 갱신 누락 (드리프트 발생원)
- `api-ventago/src/app/stocks/stocks.service.ts:368` / `:402` — **movido / fallado**.
  `Sale` + `SaleItem` + `Stocks` 만 INSERT 하고 `products.stock` 을 갱신하지 않는다.
  → **지점 간 이동·폐기 1건마다 캐시-원장이 영구히 벌어진다. 재고 조정 화면에서 가장 자주 쓰이는 경로다.**
- `api-ventago/src/app/products/productStock.service.ts:89` — 외주 로트 입고(`ingresarStockPorMatrix`, `lote.service.ts:152` 호출). 원장만.
- `api-ventago/src/app/products/productStock.service.ts:265`–`:333` — `createVariantsBatch`.
  자식 상품 `create` 에 `stock` 필드가 없어 자식 캐시가 0에서 출발.
- `api-ventago/src/app/products/productStock.service.ts:358`–`:372` — `updateMotherStock` 가
  부모 캐시를 **원장 합이 아니라 자식 캐시 합**으로 계산 → 오차가 부모로 전파.

### 결함 4 — 가용재고 정의 불일치
- 예약은 원장 `type='suspend'` 음수 행으로만 표현(`stocks.model.ts:26-27`), `products.stock` 에는 미반영
  (`online-order-stock.service.ts:342-343` 주석에 명시).
- → **두 저장소의 의미가 다르다**: `products.stock` = 물리 현재고, 원장 SUM = 현재고 − 예약.
- 같은 "재고"를 계산하는 SQL 이 최소 4벌이고 `is_active`/`type` 필터가 서로 다르다:
  - `reportsStocksCockpit.service.ts:575` — 원장 SUM (suspend 포함 = 사실상 available), `:487-490` 예약 별도 컬럼
  - `reportsAlertas.service.ts:74-89` — 원장 SUM (suspend 미분리)
  - `productStock.service.ts:1185-1192` (`GET /products/:id/live-stock`, 라우트 `products.controller.ts:516`) — 원장 SUM, **`is_active` 필터 없음**
  - `offline-sync/table-registry.ts:191-195` — 원장 SUM (`is_active=true`)
- ATP(Available To Promise) 개념·함수 없음.

### 결함 5 — 대조·보정 장치 없음
- 재고 관련 `@Cron` **0건**(등록 크론 19개 전수 확인 — 전부 무관).
- `reconcile`/`recalc`/`drift` 재고 대조 로직 0건. `diagnostics` 모듈에 재고 코드 0건.
- 유일한 수단은 문서의 수동 SQL — `docs/db-risk-analysis-20260727.md:88-92`.
  같은 문서가 "`products.stock` 드리프트 실재"를 운영 실측으로 기록하고 "야간 보정 잡 + 1회 백필"을 계획했으나 미구현(§5 Wave 3).
- **그 대조 SQL 자체가 부정확하다** — `type` 필터가 없어 `type='suspend'` 예약 행을 드리프트로 오탐한다.
- **이식원 존재**: `api-ventago/src/app/mercadopago/cron/mp-wallet-reconcile.cron.ts:27-65` —
  지갑 잔액 캐시 vs 계산값 drift 탐지 후 자동 보정. **동형 패턴이라 이식 비용이 낮다.**

### 결함 6 — 감사로그 매장 경계
- `api-ventago/src/app/audit-log/audit-log.controller.ts:37-42` — `GET /audit-log/entity/:entityType/:entityId`.
  **`@GetUser()` 자체가 없다.** entityType+entityId 만으로 조회 → 타 매장 감사로그 열람 가능.
- `api-ventago/src/app/audit-log/audit-log.controller.ts:50-53` — `GET /audit-log/store`:
  ```typescript
  if (!user.roles || user.roles.length === 0 || user.roles[0] == null) {
    return this.auditLogService.getAllLogs(+page, +pageSize, {});   // ← 전 매장 반환
  }
  ```
  `audit-log.service.ts:129` 가 `filters.storeId` falsy 면 where 조건을 붙이지 않는다.
  → **권한 판정 실패가 차단이 아니라 전체 공개로 귀결된다.**
- 대조군: 같은 파일 `:30-34`(`getAllLogs`)는 `storeId: user.storeId || storeId` 로 올바르게 스코프한다.

### 결함 7 — 사용자 관리 매장 경계
- `api-ventago/src/app/users/users.service.ts:299` — `adminUpdateUser`: `findByPk(id)` 만. **storeId 대조 없음.**
- `api-ventago/src/app/users/users.service.ts:322` — `if (dto.storeId !== undefined) updateData.storeId = dto.storeId;`
  → **사용자를 임의의 다른 매장으로 이동 가능.**
- `api-ventago/src/app/users/users.controller.ts:102` (`PUT /users/:id`) / `:146` (`DELETE /users/:id`) —
  `@FunctionGuard` 는 있으나 대상의 소속 매장을 검사하지 않는다. 자기 계정 차단 가드만 존재.
- 관련: `api-ventago/src/app/permissions/approval.service.ts:168`–`:203` — `approve()` 에
  **자가 승인 차단(`approverId !== request.requestedBy`)이 없다** → maker-checker 미성립.

### 결함 8 — 커밋된 자격증명
`PGPASSWORD` 가 주석에 평문으로 들어 있고 **git 추적 상태**인 마이그레이션 파일 10개:
`add-is-active-to-stocks.sql`, `add-use-variants-to-stores.sql`, `backfill-default-color-size-for-all-stores.sql`,
`extract-and-build-payload.sh`, `20260421-create-talleres-qc-tables.sql`, `20260422-cost-sheet-step1-schema.sql`,
`20260422-cost-sheet-step2-verify.sql`, `20260422-vendor-etapa-historization-step1-schema.sql`,
`20260424-phase25-step1-owner-group.sql`, `20260424-phase25-step2-global-owner.sql`
- 추가: `api-ventago/src/config/env.config.ts:15`–`:16` — DB password / jwtSecretKey 하드코딩 폴백.
- 추가: `api-ventago/src/common/crypto/email-secret.ts:24` — `JWT_SECRET_KEY` 미설정 시 **고정 문자열로 실제 암복호 동작**.

### 결함 9 — 장애 감지 부재
- 헬스체크 라우트 **0건** (`/health`·`/ping` 없음, `@nestjs/terminus` 미설치, `src/app.controller.ts` 부재).
- `api-ventago/docker-compose.yml` — API 서비스에 `healthcheck` 없음 (Redis 만 있음).
  `restart: always` 는 2026-07-25 재부팅 후 **2시간 무중단 다운**을 겪고서야 추가된 것(파일 주석).
- 외부 uptime 감시 없음 (`docs/ai-watcher/spec-M1.md:200-201` 에서 M2 로 이월).
- `app.enableShutdownHooks()` 호출 **0건**(`src/main.ts` 전체) → SIGTERM 시
  `database.module.ts:266` 의 `onModuleDestroy`(pool 정리)가 트리거되지 않고 in-flight 드레이닝도 없다.
- 현재 유일한 알람은 `all-exceptions.filter.ts:173-205` 의 Telegram **500 알림** —
  **프로세스가 죽거나 DB 가 내려가면 알림이 오히려 멈춘다.**

### 부수 — 계획 문서 ↔ 코드 불일치 (W9 에서 정리)
- `.planning/ROADMAP.md` Phase 64 — "Plans: 0/10 executed" 표기. 실제 W1~W9 완료·운영 배포됨.
- `.planning/STATE.md` — 최종 갱신 2026-07-24, "Current focus: Phase 61" 로 정지.
- `.planning/intel/db-schema-*.md` — 2026-06-25 자. Phase 64 W10 의 재생성 미완.
- `DATABASE_SCHEMA.md:468-477` — Stocks 정의가 3컬럼(`id/stock/productBranchId`)뿐,
  `type`·`note`·`operationDate`·`isActive`·`backfillProcessedSaleId` 누락. 테이블 총목록도 최신이 아님.
- `CLAUDE.md` — pool 을 "min=10, max=80" 이라 기술하나 실제는 `database.module.ts:58-59` **min=2, max=20**
  (4워커 × 20 = 80, pgbouncer pool_size=50 과 균형 — `ecosystem.config.js:11-14` 참조).
- Phase 64 브라우저 UAT 12건 전부 미실행(`64-VALIDATION.md` §6 UAT 칸 공란).

</current-code>

<constraints>
## 지켜야 할 규약 (CLAUDE.md:305-311, Phase 64 확립)

- **단일 트랜잭션 원칙** — 하나의 업무 동작이 만드는 모든 행은 한 트랜잭션에서 커밋. 헬퍼는 `transaction` 을 필수 인자로.
- **`stocks` 는 append-only 원장** — UPDATE/DELETE 금지. 잘못된 이동은 **반대 부호 보정 행**으로 상쇄하고
  `products.stock` 캐시를 같은 트랜잭션에서 맞춘다. 조회·기록은 항상 `product_branch_id` 기준
  (**`product_id` 컬럼은 존재하지 않는다**).
- **트랜잭션 안 외부 I/O 금지** — HTTP·프린터·소켓은 커밋 후. 필수 후속 작업은 같은 트랜잭션에서 `sync_outbox` 에 INSERT.
- **커밋 후 = 성공** — 커밋 이후 단계의 실패는 응답 코드를 바꾸지 않는다.
- **경합 방어는 설정을 존중** — 재고 초과 차단은 `store_configs.allowSaleWithoutStock=false` 매장에만.
  허용 매장의 음수 재고는 **의도된 동작**이므로 차단을 걸면 회귀다.
- **락 순서 고정** — 여러 상품 행을 잠그는 경로는 전부 `productId` 오름차순.

## 운영 제약

- 마이그레이션은 **로컬 5432 + 운영 5434 양쪽 수동 적용**. 신규 테이블은 owner/시퀀스를 `coolsistema` 로 이전하는 DO 블록 필수.
- **적용 순서: 마이그레이션 → 코드 배포.** 역순이면 판매가 거부될 수 있다(Phase 64 에서 실제 발생 — `64-VALIDATION.md` §1).
- `synchronize: false`(`database.module.ts:39`) 확인됨. 단 과거 sync 산물인 중복 제약 43건이 로컬에 잔존(별도 과제).
- 배포 롤백 경로가 없다(이미지 태그 미고정) — 되돌리기 어려운 변경은 사전 승인 필요.
- 부하 테스트는 운영 서버 안에서 수행된다. 재측정 시 심야 + watchdog 필수.

## 되돌리기 어려운 작업 (별도 승인 필요)

1. **W5 재고 백필** — 기존 데이터 보정. 실행 전 읽기 전용 측정 → 영향 행 수 보고 → 승인 → 실행.
2. **W7 자격증명 회전** — 운영 DB 계정 비밀번호 변경. 모든 접속 주체 사전 파악 필요.
3. **W1 이동유형 백필** — 기존 `'ajuste'`/`'produccion'` 행의 `type` 값 변경.

</constraints>

<measurement-first>
## 착수 전 반드시 측정할 것 (읽기 전용)

Phase 64 W7 이 "차단 도입 전 위반 건수 측정"을 선행해 성공했다. 같은 순서를 지킨다.

1. **재고 드리프트 실제 규모** — 예약분(`type='suspend'`)을 제외한 정확한 대조로
   로컬 5432 + 운영 5434 양쪽의 불일치 상품 수·수량 합·금액 규모.
   *이 수치 없이 W5 백필을 설계하면 안 된다.*
2. **이동유형 분포** — `SELECT type, count(*) FROM stocks GROUP BY type` 양쪽.
   `'ajuste'`/`'produccion'` 행 수 = W1 백필 대상 규모.
3. **원장 고아 행** — `product_branch_id IS NULL` 인 `stocks` 행 수
   (`products.service.ts:238` 의 유령 컬럼 `create` 가 만들었을 가능성).
4. **감사로그 크로스테넌트 노출 규모** — `audit_logs` 총 행 수와 `store_id IS NULL` 비율.
5. **`users` 매장 이동 이력** — 과거에 실제로 발생했는지(감사로그에서 `Usuarios` + storeId 변경 조회).

</measurement-first>
