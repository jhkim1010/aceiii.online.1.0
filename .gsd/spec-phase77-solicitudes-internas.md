# SPEC: Phase 77 — Solicitudes Internas (사내 구매요청 · 장비 수리의뢰 · 자산/소모품)

생성일: 2026-08-08
개정: **v2 — codex 교차검토 반영 (2026-08-10)**
상태: **PLAN v2 — 사용자 승인 대기**
검토 리포트: `.gsd/review-codex-phase77.md`
설계 문서: `docs/solicitudes-internas-spec.md`
UI 목업: `mockups/solicitudes-internas-mockup.html`

---

## v2 개정 요약 — codex 검토 반영

검토에서 제기된 항목을 **전부 코드로 재검증**했습니다. 결과: **제기된 주장은 사실상 전부 사실**이었고,
v1 계획의 전제 2건이 틀렸습니다.

### 검증한 주장과 결과

| 주장 | 검증 방법 | 결과 |
|---|---|---|
| `DERIVED_SCOPE` 레지스트리가 있고 기본 `enforce` | `src/common/tenant/tenant-scope.registry.ts:130,273` | **사실.** `store_id` 없는 모델은 여기 등록해야 격리됨 |
| 테넌트 훅은 컨텍스트 미해석 시 no-op | `tenant-hooks.ts:59-70` (`allowedStores()` → `null`) | **사실.** raw SQL·시스템 컨텍스트는 자동 보호 안 됨 |
| `ApprovalService.approve()` 는 audit_log·socket 을 쓰지 않는다 | `approval.service.ts:504-556` — `this.logger.log` 뿐 | **사실. v1 의 전제가 틀렸다** (헤더 주석이 거짓) |
| 대신 자가승인 차단·승인등급(SoD)·만료판정을 갖고 있다 | `approval.service.ts:524`(maker-checker), `:546`(`assertApproverRank`) | **사실.** 이것이 진짜 잃는 것 |
| `sync_outbox` 는 commerce 전용 | `sync-outbox.model.ts:31`(`channelId` NOT NULL), `:40`(`platform`), `:44`(`opType`) | **사실.** 재사용 불가 |
| `MinioService` 에 삭제 메서드가 없다 | `minio.service.ts` — `getObjects`/`uploadFile`/`download`/`getObjectStream` 뿐 | **사실.** 보상 삭제 직접 구현 필요 |
| 상품 재고는 DB 트리거가 강제 | `migrations/2026-07-28-phase65-w2-stocks-immutable-trigger.sql`, `2026-08-02-stock-balances.sql` | **사실** |
| Phase 70-06 은 *공통 부모행* 트리거만 폐기했고 key별 balance 트리거는 유지 | `migrations/2026-08-04-retire-product-stock-cache.sql` | **사실. v1 이 이 교훈을 오독했다** |
| 백엔드 권한은 CASL 이 아니라 `PermissionGuard` | `src/app/permissions/guards/permission.guard.ts`, `@Audit` 31개 파일 | **사실** |
| `isSuperAdminUser()` 가 여러 role shape 을 처리 | `tenant-user.util.ts:26` | **사실.** `user.roles.includes()` 는 취약 |
| `sale_idempotency` 는 `sale_id` 에 결합 | `sale-idempotency.model.ts` | **사실.** 별도 테이블 필요 |
| `boxes.is_deleted` / `terminals.is_deleted` 존재 | `db-schema-tables.md` | **사실.** v1 시드 SQL 은 필터 누락 |

### v1 에서 **틀렸던 것** (정정)

1. **"`ApprovalService` 를 우회하면 audit_log 와 socket 을 잃는다"** → 애초에 그 서비스가 둘 다 하지 않는다.
   실제로 잃는 것은 **자가승인 차단 · 승인등급(SoD) · fail-closed 정책**이며, 이건 v1 이 언급조차 안 했다.
2. **"Phase 70-06 이 트리거를 폐기했으니 소모품도 애플리케이션 갱신이 낫다"** → 폐기된 건 마드레 부모행을
   잠그던 `trg_stocks_sync_product_cache` 뿐이고, key별 `trg_stock_balances_apply` 는 지금도 살아 있다.
   소모품 잔량은 후자와 같은 구조이므로 **트리거가 맞다**.

### 수용하지 **않은** 지적 1건

| 지적 | 판단 |
|---|---|
| "운영 DB 적용·`git push` 를 구현 계획에서 분리하라" | **부분 수용.** `CLAUDE.md` 「상시 규칙(2026-07-29)」이 *"push 와 마이그레이션은 Claude 가 직접"* 을 명시하므로 담당자를 넘기지는 않는다. 다만 같은 문서가 *"운영 DDL 실행 전 SQL + 영향 row 승인"* 도 요구하므로, **Wave 11 배포 게이트로 분리하고 건별 사용자 승인을 필수화**한다. → 사용자 확인 필요 (D7) |

---

## 목표

매장 직원이 고장난 장비의 수리를 의뢰하고 필요한 물품을 요청하는 창구를 **단일 페이지 `/solicitudes`** 로 만든다.
의뢰 내용은 Telegram 으로 알리고 DB 에 남겨, 매장 admin 은 "무엇을 맡겼고 지금 어떤 상태이며 비용이 얼마인지"를,
superadmin 은 "전 매장의 요청 현황과 빨리 소진되는 부품"을 같은 화면에서 확인한다.

---

## 배경 및 컨텍스트

### 0. 로그 확인 (GSD 1단계 필수)

| 로그 | 마지막 기록 | 내용 |
|---|---|---|
| `ventago-app/logs/error-2026-08-07.log` | 2026-08-07 18:16 | webpack `DEP_WEBPACK_MODULE_UPDATE_HASH` deprecation ×4 |
| `ventago-app/logs/combined-2026-08-07.log` | 2026-08-07 18:17 | `ag-grid.css` autoprefixer `end value has mixed support` |

**기능 오류 없음.** 둘 다 서드파티 경고. 착수를 막는 선행 이슈 없음.
단, ag-grid 경고를 감안해 **이 화면은 AG Grid 를 쓰지 않는다** (MUI + 순수 테이블).

### 1. 재사용 자산 (신규 개발 금지)

| 자산 | 위치 | 재사용 범위 |
|---|---|---|
| Telegram 헬퍼 | `common/telegram/telegram.ts` | `sendTelegramMessage()` — **워커에서만 호출** (D5) |
| 승인 임계값 | `permissions/models/approval-threshold.model.ts` | `function_slug='solicitud'` 로 재사용 |
| 승인 보안 로직 | `permissions/approval.service.ts:524,546` | **패턴을 이식** (자가승인 차단 · `assertApproverRank`) |
| 권한 가드 | `permissions/guards/permission.guard.ts` | `permissionSlug + action` 시드 추가 |
| 감사 로그 | `@Audit` 데코레이터 (31개 파일 선례) | 승인·거절·재고조정·자산등록에 적용 |
| 테넌트 격리 | `common/tenant/tenant-scope.registry.ts` `DERIVED_SCOPE` | **신규 파생 모델 등록 필수** |
| superadmin 판정 | `common/tenant/tenant-user.util.ts:26` `isSuperAdminUser()` | 그대로 사용 |
| 멱등성 패턴 | `sales/sale-idempotency.service.ts` | **패턴만** 차용, 테이블은 신설 |
| 원장 트리거 패턴 | `migrations/2026-07-28-...immutable-trigger.sql`, `2026-08-02-stock-balances.sql` | 소모품에 동일 구조 적용 |
| 메뉴 레지스트리 | `navigation/menuRegistry.ts` (Phase 57) | 항목 추가만 |
| MinIO | `common/minio/minio.service.ts` | **삭제 메서드 없음 → 추가 필요** |

### 2. 스키마 사실 (설계 문서 대비 정정)

| # | 확인 | 영향 |
|---|---|---|
| C-1 | `terminals` 에 `branch_id` 없음 → `terminals.box_id → boxes.branch_id` | 시드 SQL join 필요 |
| C-2 | `boxes.is_deleted` / `terminals.is_deleted` 존재 | 시드에서 필터 필수 |
| C-3 | `store_configs` 34컬럼에 `telegram_chat_id` 없음 | 신규 컬럼 |
| C-4 | `approval_thresholds` 이미 존재 | `store_configs.request_approval_threshold` **철회** |
| C-5 | 테이블명 전부 복수형 (`branches`/`stores`/`users`/`terminals`/`boxes`) | FK 참조 정확 |
| C-6 | `sync_outbox.channel_id` NOT NULL + commerce 결합 | **재사용 불가 → 전용 outbox** |
| C-7 | 백엔드 권한 = `PermissionGuard` (CASL 아님) | 설계 문서 정정 대상 |

### 3. PostgreSQL pool 현황

`database.module.ts`: `pool { min:2, max:20, idle:10000, acquire:15000, evict:1000 }`
pgbouncer(5432, transaction mode) → PG18(5434). PM2 4워커 = 앱 상한 80, pgbouncer `pool_size=50`.

Sequelize 사용이므로 `connect()`/`release()` 직접 관리 없음. 실제 위험은 3가지:
① 트랜잭션 내 외부 I/O ② `transaction` 인자 누락 ③ 쿼리 비용(왕복 수가 아니라 **점유 시간**)

> **v1 정정**: "API 4개 = pool 4개 소모"는 과장이다. 병렬 4요청은 순간 동시 checkout 을 최대 4 늘릴 뿐,
> 항상 4개를 장시간 점유하는 게 아니다. **호출 개수 규칙이 아니라 측정으로 상한을 정한다.**

---

## 착수 전 확정 필요 — 결정 7건 ★

### D1. 자산 대장 초기 데이터 — **v2 변경**

v1 은 `terminals` 를 `PC-*` 물리 자산으로 자동 생성하려 했다. **`terminals` 는 논리 POS 단위이지 물리 PC 가 아니다**
(`box_id` + soft delete 를 가진 논리 엔티티). 물리 PC 와 1:1 이라는 근거가 없다.

| 안 | 내용 |
|---|---|
| ~~D1-a~~ | ~~terminals → `PC-*` 자동 생성~~ **철회** |
| D1-b | 전부 수동 등록 — 아무도 등록하지 않아 기능이 죽을 위험 |
| **D1-c (권장)** | **`branch_agents` 만 자동 시드**(실제 물리 장치: 열감지·Zebra 프린터, `label`·`api_key` 보유). `terminals` 는 `category='pos_terminal'` 로만 시드하고 `PC-*` 라 부르지 않는다. 물리 PC 는 수동 등록 후 선택적으로 `terminal_id` 연결 |

멱등성 키는 사용자가 고칠 수 있는 `code` 가 아니라 **source FK 에 partial UNIQUE** (`terminal_id`, `branch_agent_id`).
시드는 `is_deleted = false` 필터 필수 (C-2).

### D2. 승인 처리 — **v2 근거 교체, 결론 유지**

`approval_thresholds` 만 재사용하고 승인/거절은 `internal_requests.status` 자체 전이 (**D2-a 유지**).
단 v1 이 "잃는다"고 적은 audit_log·socket 은 **애초에 없었다**. 실제로 이식해야 할 것:

- **자가승인 차단** (maker-checker) — 요청자 ≠ 승인자
- **승인등급 판정** (`assertApproverRank` 패턴) — JWT roles 가 아니라 **DB 현재 역할**로 재조회
- **fail-closed** — 정책 미상 시 거부
- **원자적 조건부 UPDATE** — `WHERE status = 'solicitado'` + row lock
- **`@Audit`** — 승인·거절·비용변경·재고조정·자산등록

### D3. 소모품 잔량 — **v2 변경: DB 트리거로**

v1 은 애플리케이션 이중 쓰기 + drift 뷰였다. **drift 뷰는 탐지이지 예방이 아니다.**
Phase 70-06 이 폐기한 건 마드레 부모행을 잠그던 트리거뿐이고, key별 balance 트리거는 유지 중이다.

→ **`trg_internal_supply_movements_immutable`(UPDATE/DELETE 차단) + `trg_internal_supply_balance_apply`(AFTER INSERT upsert)**.
애플리케이션은 **movement 만 INSERT** 한다. 잔량 테이블은 직접 쓰지 않는다.

### D4. `track_stock` 기본값

**D4-a (권장)**: 신규 소모품 기본 `false`. 매장이 필요한 품목만 켠다.
부정확한 수량이 표시되는 것보다 "관리 안 함"이 정직하다.

### D5. Telegram 전달 보장 — **v2 신규**

`sync_outbox` 는 `channel_id` NOT NULL + commerce platform/opType 에 결합돼 재사용 불가 (C-6).

| 안 | 내용 |
|---|---|
| ~~fire-and-forget~~ | **철회** — 커밋 직후 프로세스 종료 시 알림 유실 |
| **D5-a (권장)** | **전용 `notification_outbox` 테이블** — 요청/이벤트와 **같은 트랜잭션**에 INSERT, 별도 워커가 lease + retry + dedupe + 성공 표기 |
| D5-b | 기존 `sync_outbox` 범용화 | commerce 스키마를 오염시킴 — 비권장 |

4종 알림(생성·상태변경·완료·저재고) **전부 같은 경로**로 보낸다. 중요도별 이중 경로는 운영 의미를 흐린다.

### D6. 승인 임계값 초기값

**D6-a (권장)**: `max_amount = 50000` (ARS). `0` 은 소모품 재주문까지 승인 큐에 넣어 실사용에서 무시당한다.

### D7. 운영 배포 담당 — **v2 신규 / 사용자 판단 필요**

codex 는 "운영 DB 적용과 push 를 계획에서 분리하라"고 권고했다.
그러나 `CLAUDE.md` 「상시 규칙 (2026-07-29)」은 **"push 와 마이그레이션은 Claude 가 직접"** 을 명시한다.

| 안 | 내용 |
|---|---|
| **D7-a (권장)** | 규칙 유지 — Claude 가 직접 실행하되 **Wave 11 배포 게이트로 분리**하고, 운영 DDL 마다 *SQL + 영향 row* 를 보여주고 **건별 승인**을 받는다 (이것도 `CLAUDE.md` 요구사항) |
| D7-b | codex 권고대로 배포를 계획 밖으로 분리 | `CLAUDE.md` 상시 규칙과 충돌 |

---

## 태스크 목록

### Wave 0 — 결정 확정
- [ ] **TASK-0**: D1(자산 시드) · D2 · D3 · D4 · D5(outbox) · D6 · D7(배포 담당) 사용자 승인

### Wave 1 — 테넌트 격리 설계 (**Blocker 선행**)
- [ ] **TASK-1**: 신규 8모델의 테넌트 전략 표 작성 — 파일: `.gsd/note-phase77-tenant-scope.md`
      - 직접 `store_id` 보유 모델 vs `DERIVED_SCOPE` 등록 모델 구분
      - `internal_request_events` / `internal_request_items` / `internal_request_attachments` /
        `internal_supply_stocks` / `internal_supply_movements` = 부모 경로 등록 대상
- [ ] **TASK-2**: `DERIVED_SCOPE` 등록 — 파일: `api-ventago/src/common/tenant/tenant-scope.registry.ts`
- [ ] **TASK-3**: 교차매장 FK 불변식 정의 — `(store_id, id)` 복합 UNIQUE + constraint trigger 로
      `request ↔ branch ↔ asset`, `supply ↔ branch` 동일 매장 강제
- [ ] **TASK-4**: raw SQL 스코프 표 — 어느 쿼리가 어떤 scope 을 **서버 계산값으로 bind** 하는지 명시.
      매장 사용자의 `storeId` 는 **query param 이 아니라 인증 사용자에서만** 얻는다

### Wave 2 — DB
- [ ] **TASK-5**: 본 마이그레이션 — 파일: `api-ventago/migrations/2026-08-XX-phase77-internal-requests.sql`
      - 테이블 8 + `store_configs.telegram_chat_id` + TASK-3 제약
      - `request_approval_threshold` 컬럼 **추가하지 않음** (C-4)
- [ ] **TASK-6**: 소모품 원장 트리거 (D3) — 같은 파일
      - `trg_internal_supply_movements_immutable` (UPDATE/DELETE 차단)
      - `trg_internal_supply_balance_apply` (AFTER INSERT → `internal_supply_stocks` upsert)
      - 자동 입고 중복 방지: `UNIQUE (request_id, request_item_id, kind)` partial
- [ ] **TASK-7**: 요청 코드 카운터 — `internal_request_counters (store_id PK, last_value)`.
      `UPDATE ... RETURNING` 로 1행만 잠근다. **`MAX()+1` 금지**
- [ ] **TASK-8**: 멱등성 테이블 — `internal_request_idempotency_keys (store_id, idempotency_key) UNIQUE`
      + `request_hash` + `internal_request_id`. **`sale_idempotency` 재사용 금지** (모델이 `sale_id` 에 결합)
- [ ] **TASK-9**: 알림 outbox (D5) — `notification_outbox` (channel='telegram', payload, status,
      attempts, max_attempts, next_attempt_at, leased_until, dedup_key, last_error)
- [ ] **TASK-10**: 자산 자동 시드 (D1-c, 멱등) — `branch_agents` + `terminals(pos_terminal)`.
      `is_deleted=false` 필터, source FK partial UNIQUE
- [ ] **TASK-11**: 소모품 카탈로그 시드 + `approval_thresholds` 시드(`function_slug='solicitud'`, 50000)
- [ ] **TASK-12**: 권한 시드 — `solicitudes.read/create/update/approve`,
      `internal_assets.read/create/update`, `internal_supplies.read/manage/move` (PermissionGuard 방식)
- [ ] **TASK-13**: 메뉴 시드 — apps 1 + modules 1 (서브메뉴 없음)

### Wave 3 — 백엔드 도메인
- [ ] **TASK-14**: 모델 11개 (기존 8 + counters + idempotency + outbox) — `.../models/*.model.ts`
- [ ] **TASK-15**: DTO — `.../dto/*.dto.ts`
- [ ] **TASK-16**: 생성 서비스 — `.../internal-requests.service.ts`
      - 코드 발급 + 멱등 claim + 요청 + items + 최초 event + **outbox 행**을 **단일 트랜잭션**
      - 소유권 검증(branch/asset/supply 가 같은 매장인지)을 **같은 트랜잭션에서**
      - `ApprovalThreshold` 로 자동승인 판정
- [ ] **TASK-17**: 상태 전이 서비스 (D2 보안 불변식) — `.../internal-request-transition.service.ts`
      - `SELECT ... FOR UPDATE` + `WHERE status = <expected>` 원자적 조건부 전이
      - 자가승인 차단 · DB 현재 역할로 승인등급 판정 · fail-closed
      - `finalizado` 시 자산 status 복원 + 소모품 **movement INSERT만** (잔량은 트리거가 반영)
      - items 락 순서 `(supply_id, branch_id)` 오름차순 고정
      - `@Audit` 적용
- [ ] **TASK-18**: 소모품 서비스 — `.../internal-supplies.service.ts` (movement-only 쓰기)
- [ ] **TASK-19**: 첨부 서비스 — UUID object key, MIME/크기 제한,
      **DB insert 실패 시 MinIO 보상 삭제**, 삭제 엔드포인트, orphan 정리 job
- [ ] **TASK-20**: `MinioService.deleteFile()` 추가 — 파일: `api-ventago/src/common/minio/minio.service.ts`

### Wave 4 — 알림 워커
- [ ] **TASK-21**: outbox 워커 — `.../notification-outbox.worker.ts`
      - lease(`leased_until`) + 지수 backoff retry + `dedup_key` + 실패 관제 로그
      - `sendTelegramMessage()` 는 **여기서만** 호출
- [ ] **TASK-22**: 메시지 빌더 4종 — `.../internal-requests.notifier.ts` (payload 생성만, 전송 안 함)
- [ ] **TASK-23**: 저재고 일일 cron — `@Cron('0 9 * * *')`, 전 지점 **단일 쿼리** → 지점당 1행 outbox
      - **매장 `telegram_chat_id` 미설정 시 발송하지 않고 경고 로그** (전역 채널 fallback 금지)

### Wave 5 — 백엔드 API
- [ ] **TASK-24**: 컨트롤러 — `.../internal-requests.controller.ts`
      - `@UseGuards(PermissionGuard)` + `Idempotency-Key` 헤더 처리
      - superadmin 만 DTO `storeId` 허용, 판정은 `isSuperAdminUser()`
- [ ] **TASK-25**: `GET /internal-requests/page` — 목록 **선(先) 페이지네이션** 후
      `LATERAL jsonb_agg` 로 events/items 집계. **단일 대형 join 금지** (행 증폭 · count 왜곡)
- [ ] **TASK-26**: superadmin 소진 랭킹 쿼리 (CTE 2개) + 명시적 scope bind
- [ ] **TASK-27**: 모듈 등록 — `.../internal-requests.module.ts` + `app.module.ts`

### Wave 6 — 문서 정정
- [ ] **TASK-28**: `docs/solicitudes-internas-spec.md` 정정
      - C-1(terminals→boxes) / C-4(임계값) / C-6(outbox) / C-7(PermissionGuard, CASL 아님)
      - `user.roles.includes('superadmin')` → `isSuperAdminUser()`
      - "API 4개 = pool 4개" 과장 표현 삭제
      - 잔량 갱신을 트리거 방식으로 교체

### Wave 7 — 프론트 (MVP 루프)
- [ ] **TASK-29**: SWR 훅 — `ventago-app/src/hooks/api/useSolicitudesPage.ts`
- [ ] **TASK-30**: 페이지 진입점 — `src/pages/solicitudes/index.tsx` (`next/dynamic`, `ssr:false`)
- [ ] **TASK-31**: 페이지 셸 — `src/views/solicitudes/SolicitudesPage.tsx`
- [ ] **TASK-32**: 목록 테이블 — `src/views/solicitudes/SolicitudesTable.tsx`
- [ ] **TASK-33**: 인라인 상세 아코디언 — `src/views/solicitudes/SolicitudDetailRow.tsx`
- [ ] **TASK-34**: 공용 컴포넌트 — `src/views/solicitudes/components/*.tsx`
- [ ] **TASK-35**: 생성 모달 — `src/views/solicitudes/SolicitudFormDialog.tsx` (`Idempotency-Key` 생성 포함)

### Wave 8 — 프론트 (레일 + superadmin)
- [ ] **TASK-36**: 내 장비 레일 — `src/views/solicitudes/rail/EquiposRail.tsx`
- [ ] **TASK-37**: 소모품 레일 + 장바구니 — `src/views/solicitudes/rail/InsumosRail.tsx`
- [ ] **TASK-38**: 소진 랭킹 레일 — `src/views/solicitudes/rail/ConsumoRail.tsx`
- [ ] **TASK-39**: 매장 현황 레일 — `src/views/solicitudes/rail/TiendasRail.tsx`
- [ ] **TASK-40**: i18n 키 등록 — 상태·오류·권한 메시지. 컴포넌트에 스페인어 하드코딩 금지
- [ ] **TASK-41**: 메뉴 등록 — `src/navigation/menuRegistry.ts` (`directPath`). **`vertical/index.ts` 수정 금지**

### Wave 9 — 테스트
- [ ] **TASK-42**: 상태 머신 — 정상 전이 6종 + **불법 전이 거부** — `internal-request-transition.spec.ts`
- [ ] **TASK-43**: 보안 — 자가승인 거부 / 승인등급 미달 거부 / **타 매장 IDOR** / raw SQL scope — `internal-requests-access.spec.ts`
- [ ] **TASK-44**: 동시성 — 동시 `finalizado` 2회 → movement 1건 / 동일 `Idempotency-Key` replay → 요청 1건
- [ ] **TASK-45**: 원장 — `internal_supply_movements` UPDATE/DELETE 차단 확인 + balance 트리거 정확성
- [ ] **TASK-46**: outbox — 전송 실패 후 retry / dedupe / lease 만료 회수
- [ ] **TASK-47**: 첨부 — DB 실패 시 MinIO 보상 삭제
- [ ] **TASK-48**: 프론트 — 역할별 렌더링 (매장 admin 에게 승인 버튼 미노출)

### Wave 10 — 품질 검증
- [ ] **TASK-49**: ESLint — `api-ventago && npm run lint`, `ventago-app && npm run lint` → **오류 0**
- [ ] **TASK-50**: 프론트 프로덕션 빌드 통과
- [ ] **TASK-51**: pool 체크리스트 (아래)
- [ ] **TASK-52**: **부하 측정** — 단일 page API vs 분리 API 의 P95 · pool checkout · 응답 바이트 비교.
      측정 결과로 최종 구조 확정 (추측 금지)

### Wave 11 — 배포 게이트 (**D7 승인 후 진행**)
- [ ] **TASK-53**: 로컬(5432) 마이그레이션 적용 + `\d` 확인
- [ ] **TASK-54**: **운영 DDL SQL + 영향 row 수를 사용자에게 제시하고 건별 승인**
- [ ] **TASK-55**: 운영(5434) 적용 + 양쪽 스키마 대조 + owner/시퀀스 `coolsistema` 확인
- [ ] **TASK-56**: `./.planning/intel/db-schema.regen.sh` 재생성 + commit
- [ ] **TASK-57**: commit + `git push origin main` → Jenkins 빌드 성공 + 운영 컨테이너 재생성 확인

---

## PostgreSQL pool 안전 체크리스트 (TASK-51)

Sequelize 사용 → `pool.connect()`/`release()` 직접 관리 없음. 실제 위험만 점검한다.

- [ ] **트랜잭션 안에 외부 I/O 없음** — Telegram·MinIO·HTTP 가 트랜잭션 콜백 밖에 있는가?
      (D5 채택 시 Telegram 은 outbox INSERT 로 대체되므로 자동 충족)
- [ ] **`transaction` 인자 누락 없음** — 생성/전이 경로의 모든 `.create()`/`.update()` 에 `{ transaction }`
- [ ] **헬퍼는 `transaction` 을 필수 인자로 선언** — 선택 인자면 누락이 컴파일에서 안 잡힌다
- [ ] **N+1 없음** — 목록 행마다 events/items/asset 개별 조회하지 않는가?
- [ ] **행 증폭 없음** — events × items 카티션 곱이 발생하지 않는가? (`LATERAL jsonb_agg` 사용)
- [ ] **cron 은 단일 쿼리** — 지점 수만큼 왕복하지 않는가?
- [ ] **락 순서 고정** — items 처리가 `(supply_id, branch_id)` 오름차순인가?
- [ ] **조건부 전이** — `FOR UPDATE` + `WHERE status = <expected>` 로 경합을 막는가?
- [ ] **`pageSize` ≤ 50** (기본 25)
- [ ] **측정 완료** — TASK-52 결과가 있는가? *(호출 개수 규칙이 아니라 P95·checkout 실측으로 판단)*

---

## 완료 기준

- ESLint 오류 **0개** (양쪽 프로젝트)
- 프론트 프로덕션 빌드 통과
- Wave 9 테스트 전부 통과 — 특히 **타 매장 IDOR 차단**, **자가승인 거부**, **동시 finalizado 중복 방지**
- 소모품 원장 UPDATE/DELETE 가 **DB 에서 차단**되고 잔량이 트리거로 일치
- Telegram 4종이 **outbox 경유**로 전달되며 워커 재시도가 동작
- 마이그레이션이 로컬(5432) + 운영(5434) 양쪽 적용 + 스키마 일치 + owner `coolsistema`
- 사이드바 `Solicitudes` 최상위 메뉴 1개, 서브메뉴 없음
- **P95 응답시간과 pool checkout 이 측정되어 기록됨** (~~"API 호출 1회"~~ 는 기준에서 제외)
- Jenkins 빌드 성공 + 운영 컨테이너 재생성 확인

---

## 금지사항 / 주의사항

### 건드리지 말 것
- `ventago-app/src/navigation/vertical/index.ts` — `menuRegistry.ts` 만 수정
- `api-ventago/src/database/database.module.ts` — pool 설정 변경 금지
- `approval_requests` / `approval_thresholds` **스키마 변경 금지** — 읽기·시드만
- `sync_outbox` — commerce 전용. `solicitud.*` 를 얹지 않는다 (C-6)
- `sale_idempotency` 테이블 — `sale_id` 결합. 재사용 금지
- `products.stock`, `stocks` 테이블 — 소모품과 절대 섞지 않는다

### 주의
- **애플리케이션은 `internal_supply_stocks` 를 직접 쓰지 않는다.** movement 만 INSERT (D3)
- **`user.roles.includes('superadmin')` 금지** → `isSuperAdminUser()` 사용
- **매장 사용자의 `storeId` 를 query param 에서 받지 않는다** — 인증 사용자에서만
- 백엔드 권한은 **CASL 이 아니라 `PermissionGuard`** (`permissionSlug + action`)
- 요청 **hard delete 엔드포인트를 만들지 않는다** — `cancelado` 를 종결 상태로. 잘못 취소 시 새 요청 생성
- AG Grid 사용 금지 (MUI + 순수 테이블)
- `apiConnector.remove()` 사용 (`.delete()` 아님)
- ESLint: `return` 위 빈 줄, `//` 주석 위 빈 줄, 미사용 import 금지
- 신규 테이블은 운영에서 owner + 시퀀스를 `coolsistema` 로 이전
- 주석 한국어, 함수/변수명 영어, 모든 async 에 에러 핸들링

### v1 에서 제거한 과잉 규칙 (codex 지적 수용)
- ~~`Promise.all` 3개 이하 절대 규칙~~ → 측정으로 상한 결정
- ~~"페이지 API 호출 1회" 완료 기준~~ → P95 · payload · checkout 실측으로 대체
- ~~`React.memo` 를 파일 단위 태스크로 강제~~ → 렌더 프로파일 후 필요한 곳에만

---

## 롤백 계획

| 단계 | 롤백 |
|---|---|
| 마이그레이션 | 신규 테이블 11 + 트리거 + 제약 `DROP`. 기존 테이블 무변경 |
| `DERIVED_SCOPE` | 등록 항목 제거 (다른 모델 영향 없음) |
| `store_configs.telegram_chat_id` | NULL 허용이라 남겨도 무해 |
| 메뉴 | `modules`/`apps` 행 삭제 |
| 코드 | `app.module.ts` imports 에서 모듈 제거 |
| outbox 워커 | 스케줄러 비활성화 → 미발송 행이 테이블에 남을 뿐 |

기존 테이블을 변경하지 않으므로 롤백은 신규 객체 제거로 완결된다.

---

## 진행 로그

| 날짜 | 단계 | 비고 |
|---|---|---|
| 2026-08-08 | PLAN v1 | 로그 확인(오류 없음), 스키마 대조 5건, 결정 4건 |
| 2026-08-10 | **PLAN v2** | codex 교차검토 반영. 주장 12건 코드 재검증(전부 사실). v1 전제 2건 정정, Blocker 8건 수용, 과잉 규칙 3건 제거, 태스크 36 → 57 |
