# Phase 86 SPEC 검토 — 지적별 판단

- 대상: `.planning/phases/86-legacy-import-full-migration/86-SPEC.md` (v1, 2026-08-20)
- 검토 보고서: `.team/reviews/phase86-spec-review.md`
- 판단자: Claude Code · 2026-08-20

> **검토 주체 고지.** 이 검토는 **codex 가 아니다.** 이 세션(클라우드 샌드박스)에서는
> `npm i @openai/codex` 로 CLI(v0.148.0) 설치까지는 됐으나 `api.openai.com` 이 프록시 403 으로
> 차단되고 인증 정보도 없어 `scripts/codex-review.sh` 를 돌릴 수 없었다.
> 대신 `AGENTS.md` 검토 기준으로 저장소 코드를 직접 대조하는 독립 검토를 수행했고,
> CRITICAL·HIGH 지적은 **판단자가 파일을 다시 열어 전수 재확인**했다.
> Mac 로컬에서 실제 codex 검토를 받을 것: `scripts/codex-review.sh --task 86`

---

## CRITICAL — 전부 수용

| ID | 지적 | 판단 | 재확인 근거 |
|---|---|---|---|
| C1 | `sales.source = 'legacy'` 는 CHECK 위반 | **수용** | `40-04-sales-source-delivery.sql:29-31` 에서 `CHECK (source IN ('pos','online','factura','delivery'))` 직접 확인. `sales.model.ts:39-45` 의 `SaleSource` 에도 없음 |
| C2 | `status = 'anulada'` 는 존재하지 않는 값 | **수용 — 가장 위험한 지적** | `sales.model.ts:24-31` → `NULLIFIED = 'Anulado'`, `NULLIFICATION = 'Anulación'`. status 에는 CHECK 가 없어 오타가 조용히 저장되고, 취소 제외 필터가 문자열 정확 일치라 **취소 판매가 매출로 잡힌다.** v1 의 §6 대조표로는 못 잡는다 |
| C3 | pgbouncer transaction pooling 에서 잡 단위 advisory lock 불성립 | **수용** | `pool_mode = transaction`. 배치 커밋을 반복하므로 `pg_advisory_xact_lock` 은 매 커밋에 풀리고, 세션 락은 커넥션이 다른 클라이언트로 넘어가 떠돈다. 저장소의 기존 사용처가 전부 `_xact_` 인 것이 방증 |
| C4 | 200MB 상한 + 전량 문자열 적재 = 운영 OOM | **수용** | `legacy-import.controller.ts:188,205` 가 `file.buffer` 전제. diskStorage 전환만으로는 힙 문제가 안 풀리고, **`file.buffer` 전제 때문에 전환 자체가 현행 코드와 비호환**. `Dockerfile:43-49` 에 swap 0 / free 1.6GB 기록 있음 |

**C1·C2 조치:** `SaleSource` 에 `LEGACY = 'legacy'` 추가 + `sales_source_check` 확장 마이그레이션(M5) 신설.
취소 판매는 `SaleStatus.NULLIFIED`(`'Anulado'`) 를 **enum 상수로만** 참조하고 문자열 리터럴 금지.

**C3 조치:** advisory lock 폐기 → `legacy_import_leases(store_id PK, job_id, lease_expires_at)` 리스 테이블.
저장소에 이미 같은 패턴이 있다(`sync_outbox.lease_expires_at`).

**C4 조치:** **TASK-2b 를 선택에서 필수로 승격.** 스트리밍 파서가 없으면 상한은 25MB 로 동결한다.
"200MB 상한"과 "TASK-2b" 는 한 몸이며 따로 배포하지 않는다.

---

## HIGH — 7건 수용, 1건 조건부

| ID | 지적 | 판단 |
|---|---|---|
| H1 | §D1 「트리거 함정」의 **근거가 사실과 다르다** | **수용(근거 정정), 처방은 유지** — `v_stock_balance_drift` 는 `available` vs `SUM(stock)`, `movimientos` vs `COUNT(id)` 만 본다(`2026-08-02-stock-interface-views.sql:20-33`). 트리거 L85 가 미지의 type 도 `available` 에 넣으므로 **drift 는 안 깨진다. `total_*` 만 조용히 틀어진다.** 즉 위험은 "즉시 터진다"가 아니라 **"안 터지고 리포트만 틀린다"** — 더 나쁘다. `type = NULL` 처방은 그대로 옳다(`traspaso.sql:54,66-67`) |
| H2 | `trg_stocks_leaf_only` 누락 | **수용** — 기준선 행이 madre PB 로 가면 트랜잭션 전체 abort(`2026-08-07-stock-leaf-only.sql:64-95`). §8 금지사항에 추가 |
| H3 | legacy 판매를 나중에 취소하면 없던 재고가 는다 | **수용** — 취소 경로가 무조건 `+qty` 복원(`sales-create.service.ts:1414-1436`). legacy 판매는 재고 차감이 없었으므로 복원도 없어야 한다. **`sales.source='legacy'` 인 판매의 취소는 재고 복원을 건너뛰도록 취소 경로에 가드 추가** |
| H4 | `statement_timeout=30s` / `idle_in_transaction_session_timeout=60s` 미고려 | **수용** — 파싱·변환은 **트랜잭션 밖**에서 끝내고, 트랜잭션은 INSERT 배치만 감싼다. 배치 크기를 60초 안에 끝나는 값으로 정한다(초기 500행, 실측으로 조정) |
| H5 | 임시 비밀번호 보관 위치 부재 + jobs 엔드포인트 IDOR | **수용 — 보안상 가장 중요** | 아래 별도 항목 |
| H6 | `expenses` NOT NULL 4개 (`user_id`·`branch_id`·`description`·`date`) | **수용** — Gastos 의존성에 Usuarios·지점 매핑 추가. `gastos.tema` 가 NULL 이면 `gasto_info.desc_gasto` → 없으면 `'(sin descripción)'` |
| H7 | 중단-재개 시 부분 저장 판정 규칙 없음 | **수용** — 아래 별도 항목 |
| H8 | `daily_number` 재부여 충돌 + N+1 | **조건부 수용** — `uq_sales_branch_daylocal_dn` 이 `NULLS NOT DISTINCT` 인 점 수용. 다만 채번을 행마다 하지 않고 **지점×일자 버킷별로 `MAX(daily_number)` 를 한 번 읽어 메모리에서 연번 부여** 후 배치 INSERT 한다(9,731회 → 버킷 수만큼) |

### H5 조치 — 임시 비밀번호

- **DB 에 평문을 남기지 않는다.** 잡 결과의 임시 비밀번호는 `legacy_import_secrets` 에
  **애플리케이션 키로 암호화**해 저장하고 `expires_at = now() + 24h`, **1회 조회 시 즉시 삭제**.
- `GET /legacy-import/jobs/:id` 는 **반드시 `job.storeId === user.storeId` 를 검증**한다.
  사용자 입력 ID 를 받는 첫 엔드포인트이므로 IDOR 이 곧 남의 매장 자격증명 유출이다.
- 임시 비밀번호는 **로그·에러 메시지·소켓 페이로드에 절대 싣지 않는다.**
- CSV 는 서버가 파일로 만들지 않고 **조회 응답에서 클라이언트가 생성**한다.

### H7 조치 — 재개 규칙

`legacy_entity_maps` 에 `status` 를 둔다: `PENDING` → INSERT 직전 기록, `DONE` → 같은 트랜잭션에서 커밋.
- 재개 시 `PENDING` 행은 **미완성으로 간주해 해당 엔티티를 되돌리고 다시 만든다**
- `sales` 는 헤더와 품목을 **한 트랜잭션**에 넣는다(품목 없는 판매 방지)
- `stocks` 는 append-only 라 되돌릴 수 없다 → **기준선은 잡의 맨 마지막 단계**에 한 번만, 매장×임포트당 1회로 제한

---

## MEDIUM — 채택 요약

- **M2 테이블명 오기 2건 수용**: `sale_payments` → **`sale_payment_methods`**, `expense_categories` → **`expenses_categories`**
- **M5 수용**: `must_change_password` 는 컬럼만 추가하면 무효 → `auth.service.ts:600-613 / 812 / 1246-1270` + 가드 + Users 모델 5개 지점을 TASK 에 명시
- **M6 수용**: `legacy_imports.status` 에 CHECK 가 **없다**(`2026-06-25-legacy-imports.sql:44`) → **M2 마이그레이션에서 status 확장 DDL 삭제**
- **M4 수용**: `bulkCreate` 는 `Clients` 의 `AfterCreate` 훅을 건너뛰어 `StoreClient` 가 안 생긴다 → 훅 우회 시 수동 생성
- **M8 수용**: 기준선 임포트가 재고 **리포트**를 왜곡한다 → "의도된 동작" 범위를 잔액뿐 아니라 입고/판매 리포트까지로 확대 명시하고 UI 에 고지
- **M9 조건부 수용**: 365일 롤링 창은 **임포트 시점 스냅샷**으로만 의미가 있다. 새 시스템은 영구 잔액이므로 이후 자연히 갈라진다 — 이건 **버그가 아니라 이관의 정의**다. 다만 UI 에 "기준일 현재 재고" 로 명시하고 기준일을 `stocks.operation_date` 에 남긴다
- **M12 수용**: TASK-2b 는 전부 아니면 전무 — plain/gzip/custom/tar 4경로를 한 번에 이식한다
- **M1 수용**: `sales.total_amount` 는 integer, ACE `tpago` 는 double precision → 대조는 **반올림 후 정수 비교**, 반올림 손실 건수를 별도 보고

## LOW

- L1 수용: `corregidos` 실측 행 수 §2.1 에 추가
- L2 수용: PGDMP 리더를 `/tmp` 가 아니라 **`tools/ace-dump/`** 로 저장소에 커밋
- L3 기록만: `legacy-import.controller.ts` 의 `SessionGuard` 미적용은 현행 상태이며 이번 변경이 악화시키지 않는다. 별건으로 분리
- L4: `stocks.source = 'legacy_opening'` 안전 확인 — 조치 없음

---

## 승인 권고 반영

| §9 항목 | 검토 권고 | 최종 |
|---|---|---|
| 1. D1 `type = NULL` | 결정은 옳고 근거만 정정 | **채택** — 근거를 H1 대로 다시 씀 |
| 2. TASK-2b | 필수로 승격 | **채택** — 200MB 상한의 전제조건 |
| 3. 2차 이월 항목 | 정책 사항(미확인) | **사용자 결정으로 범위 변경** — `fventas`/`fdetalles`/`ingresos`/`creditoventas` 모두 포함. `codigos_tmp` 제외 확정 |
| 4. `logs(alerta=true)` | 정책 사항(미확인) | `legacy_alerts` 보관 전용 (v2 확정) |
| 5. 운영 즉시 적용 | **보류** | **채택** — M1·M2 내용이 바뀌고 M5 가 새로 생겼다. 로컬 검증 완료 후 일괄 적용 |
