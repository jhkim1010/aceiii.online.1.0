# Phase 86 SPEC 검토 보고서 — `86-legacy-import-full-migration`

- 검토 대상: `.planning/phases/86-legacy-import-full-migration/86-SPEC.md` (271줄, status DRAFT)
- 검토 기준: `AGENTS.md`(보고 형식·심각도), `.team/REVIEW-PROTOCOL.md`(우선순위), `CLAUDE.md`(프로젝트 규약)
- 검토 방식: SPEC 의 각 주장을 저장소 실물 코드·마이그레이션과 1:1 대조. 확인 못 한 것은 「미확인」으로 표시.
- 결론: **CRITICAL 4건 / HIGH 8건** 미해소. REVIEW-PROTOCOL 게이트 기준으로 이 상태의 SPEC 은 승인 대상이 아니다.

---

## CRITICAL

### [CRITICAL] 86-SPEC.md:§D2 — `sales.source = 'legacy'` 는 CHECK 제약 위반이다. ventas 임포트가 첫 행에서 통째로 실패한다

**문제**
SPEC D2 는 `sales.source = 'legacy'` 로 쓴다고 못박았는데, `sales.source` 에는 값 화이트리스트 CHECK 가 걸려 있고 `'legacy'` 는 거기 없다. INSERT 마다 `23514 check_violation` 이 난다. §5 마이그레이션 목록(M1~M4) 어디에도 이 제약을 넓히는 항목이 없다.

**근거**
```
api-ventago/migrations/phase28-full-online-integration.sql:217-218
      ADD CONSTRAINT sales_source_check
      CHECK (source IN ('pos','online','factura'));

api-ventago/migrations/40-04-sales-source-delivery.sql:29-31
  -- 'delivery' 포함 CHECK 재생성 (제약명은 phase28 선례와 동일하게 sales_source_check)
    ADD CONSTRAINT sales_source_check
```
```
api-ventago/src/app/sales/sales.model.ts:39-45
export enum SaleSource {
  POS = 'pos', ONLINE = 'online', FACTURA = 'factura', DELIVERY = 'delivery',
}
```
모델 주석(L33)이 직접 말한다 — "DB CHECK 제약과 동기화".

**수정**
M5 마이그레이션을 추가해 `sales_source_check` 를 `('pos','online','factura','delivery','legacy')` 로 재생성하고(선례 40-04 와 동일 패턴), `SaleSource` enum 에 `LEGACY = 'legacy'` 를 추가한다. 두 곳을 같은 커밋에 넣는다 — 한쪽만 바꾸면 배포 순서에 따라 500 이 난다.

---

### [CRITICAL] 86-SPEC.md:§D2 — `status = 'anulada'` 는 이 시스템의 값이 아니다. 취소된 legacy 판매가 **매출로 집계된다**

**문제**
SPEC 은 `vcodes.borrado = true → status = 'anulada'` 라고 썼다. 이 저장소가 실제로 쓰는 취소 상태는 `'Anulado'`(원본) / `'Anulación'`(역분개) 두 개다. `sales.status` 에는 CHECK 가 없어 `'anulada'` 는 **조용히 들어간다.** 그리고 매출 쿼리·화면의 취소 제외 필터가 전부 문자열 정확 일치라서 이 행들을 **취소로 인식하지 않는다** → 구 시스템에서 취소한 판매가 새 시스템 매출에 얹힌다. 조용히 틀리는 종류라 §6 대조표(행수·합계 일치)도 통과한다.

**근거**
```
api-ventago/src/app/sales/sales.model.ts:24-31
  NULLIFIED = 'Anulado',      // 원본 (무효화된 판매)
  NULLIFICATION = 'Anulación', // 역분개 (무효화 처리건)
```
```
api-ventago/src/app/sales/sales.service.ts:1325
    const NOT_VOID = `AND s.status NOT IN ('Anulado','Anulación')`;

api-ventago/src/app/sales/daily-summary.util.ts:97,102
  return status === 'Anulación' ? 'Anulado' : status;
  return normalizeStatus(rawStatus) === 'Anulado';

ventago-app/src/views/sales/list/SalesListView.tsx:562
    if (row?.status === 'Anulado' || row?.status === 'Anulación') return false;

ventago-app/src/views/sales/list/components/DataConfig.tsx:308
        const isVoid = status === 'Anulado' || status === 'Anulación'
```
백필 마이그레이션도 같은 집합을 쓴다: `2026-08-19-sales-branch-id.sql:67`.

**수정**
`SaleStatus.NULLIFIED`(`'Anulado'`)를 쓴다. SPEC 본문의 문자열을 고치고, §6 대조 항목에 "`status NOT IN ('Anulado','Anulación')` 로 거른 매출 합" 을 명시해 필터가 실제로 먹는지 검증한다.

---

### [CRITICAL] 86-SPEC.md:§D4 — pgbouncer 가 **transaction pooling** 이라 "잡 단위 advisory lock" 은 성립하지 않는다

**문제**
D4 는 "매장당 동시 잡 1개로 제한(advisory lock)" 이라고 했다. 그런데 이 잡은 같은 D4 에서 "엔티티 단위로 트랜잭션을 끊고 1,000행 배치 커밋" 하기로 되어 있다 — 즉 락이 **여러 트랜잭션에 걸쳐** 유지돼야 한다. 두 선택지 모두 막힌다:

- `pg_advisory_xact_lock` — 배치 커밋마다 해제된다. 커밋 사이에 다른 잡이 끼어든다 = 중복 방지 실패.
- `pg_advisory_lock`(세션 락) — 앱은 pgbouncer **transaction 모드**를 경유한다. 트랜잭션이 끝나면 서버 커넥션이 풀로 반납되어 **다른 클라이언트에게 넘어간다.** 락은 남의 세션에 붙어 떠돌고, `pg_advisory_unlock` 은 다른 서버 커넥션에서 실행돼 해제에 실패할 수 있다. 최악의 경우 그 서버 커넥션이 죽을 때까지 락이 남아 **그 매장의 모든 재임포트가 영구 차단**된다.

이 저장소는 이미 그 사실을 알고 있다 — advisory lock 사용처 **전부**가 `pg_advisory_xact_lock` 이다(세션 락 0곳).

**근거**
```
api-ventago/src/database/database.module.ts:52-57
        // ── PostgreSQL 커넥션 풀 설정 (pgbouncer transaction pooling 경유) ──
        // 앱은 pgbouncer(5432, transaction mode)를 경유해 PG18(5434)에 접속한다.

infra/stage/02-postgres.sh:224
pool_mode = transaction

docs/pg18-migration-runbook.md:32
| pgbouncer 풀 | `pool_mode=transaction`, ... |
```
전 사용처(세션 락 없음):
`sales/daily-number.service.ts:84`, `clients/clients.service.ts:661-663`,
`cashRegister/cashRegister.service.ts:731,1698`, `products/productStock.service.ts:128`,
`subcon/subcon-settlements/subcon-settlement.service.ts:239-244`, `online-orders/online-orders.service.ts:945`
— 전부 `pg_advisory_xact_lock`. `clients.service.ts:661` 주석이 이유를 적어뒀다: "커밋/롤백 시 자동 해제되고 커넥션을 추가 점유하지 않는다."

**수정**
advisory lock 을 버리고 **테이블 기반 잡 락**을 쓴다. 이 저장소에 이미 검증된 패턴이 둘 있다:
- `sync_outbox` 의 `locked_by` + `lease_expires_at` (`2026-07-27-phase64-outbox-lease.sql:9-10`)
- `cron_leases` (`2026-08-07-phase75-cron-leases.sql:14` — "`sync_outbox.lease_expires_at` 이 이미 쓰는 검증된 패턴을 답습한다")

`legacy_imports` 에 `(store_id) WHERE status IN ('QUEUED','RUNNING')` 부분 UNIQUE 인덱스 + 리스 만료 컬럼을 두면, 커넥션 상태와 무관하게 매장당 1잡이 강제되고 워커가 죽어도 리스 만료로 자동 회수된다. SPEC §5 의 M2 를 이 방향으로 다시 쓴다.

---

### [CRITICAL] 86-SPEC.md:§D4 — 업로드 상한 200MB + 전량 문자열 적재 = 운영 서버 OOM. Dockerfile 이 이미 같은 사고를 기록해 두었다

**문제**
D4 는 상한을 25MB → 200MB 로 올린다. 그런데 현행 변환 경로는 **압축 해제 결과 전체를 하나의 JS 문자열로** 만든다. 실측된 kandente4 백업은 56MB 이고 `codigos_tmp` 만 압축 해제 시 244MB 다(SPEC §2.3 F1 자인). diskStorage 로 바꿔도 해소되지 않는다 — 디스크는 업로드 원본만 덜어낼 뿐, 변환 결과 문자열은 여전히 힙에 통째로 올라간다.

이 서버에서 힙 스파이크는 단순한 실패가 아니다. Dockerfile 이 그 이유를 직접 적어놓았다.

**근거**
```
api-ventago/src/app/legacy-import/dump-converter.service.ts:43
// 변환(해제/restore) 결과 상한 — 메모리 보호 (200MB)
const MAX_DECOMPRESSED_BYTES = 200 * 1024 * 1024;
   → toPlainSql() 은 ConvertResult.sqlText: string 을 반환한다(L38-41)

api-ventago/src/app/legacy-import/legacy-import.controller.ts:205-208
    const { sqlText, format } = await this.dumpConverter.toPlainSql(
      file.buffer, file.originalname,
    );
```
```
api-ventago/Dockerfile:43-49
# Jenkins 는 **운영 서버(srv803182) 위에서** 돈다. 그 서버는 swap 이 0 이고 실제 free 는
# 1.6GB 뿐이며(나머지는 캐시), 같은 박스에서 운영 PostgreSQL 이 프로세스당 3GB 씩 쓰고 있다.
# ...
# 더 나쁜 것은 실패 자체가 아니라 위험이다: swap 이 없으므로 메모리 스파이크가 나면
# OOM killer 가 **운영 Postgres 를 고를 수 있다.** CI 가 장애를 만드는 구조는 안 된다.
```
API 는 PM2 클러스터(4워커, `Dockerfile:53,64`)다. 워커 하나가 200MB+ 문자열을 잡으면 free 1.6GB 서버에서 OOM killer 의 표적이 되고, 그 표적이 **운영 Postgres 일 수 있다**는 것이 위 주석의 요지다.

**수정**
D4 를 "diskStorage + 200MB" 로 끝내지 말고, **§7 TASK-2b(스트리밍 PGDMP 리더)를 선택이 아니라 200MB 상한의 전제조건으로** 승격한다. 즉 다음 셋을 한 묶음으로 결정한다:
1. 파일은 디스크에만 둔다(`diskStorage`, `file.path`).
2. 파서는 **블록 단위 스트리밍**으로 읽고 필요한 테이블만 디코드한다. 전체 SQL 문자열을 만드는 API(`toPlainSql(): string`)는 임포트 경로에서 제거한다.
3. 워커 프로세스의 RSS 상한을 실측해 SPEC 에 숫자로 적는다.
스트리밍 이식 없이 상한만 올리는 순서는 금지한다.

---

## HIGH

### [HIGH] 86-SPEC.md:§D1 「★ 트리거 함정」 — **주장이 사실과 다르다.** 새 `type` 값을 넣어도 `v_stock_balance_drift` 는 깨지지 않는다. 그래서 §6 검증이 이 실수를 못 잡는다

**문제**
SPEC 은 "`'OPENING_LEGACY'` 같은 새 값을 넣으면 어떤 `total_*` 버킷에도 안 잡히고 `on_hand` 에만 반영돼 **`v_stock_balance_drift` 가 즉시 깨진다**" 고 단정했다. 뷰 정의를 읽으면 **깨지지 않는다.** drift 뷰는 `available` 과 `movimientos` **두 개만** 본다. 두 값은 `type` 과 무관하게 항상 `NEW.stock` / `+1` 이다.

결론이 뒤집히는 게 아니라 **더 나쁘다**: 잘못된 `type` 을 써도 알람이 안 울린다. `total_*` 버킷만 조용히 어긋나 리포트가 틀린다. 그리고 §6 검증 5번의 "`v_stock_balance_drift` 0행" 은 이 오류에 대해 **아무 보증도 하지 않는다.**

**근거** — 기준선 행(`type=NULL, stock=N>0`)이 trigger 를 통과할 때
```
api-ventago/migrations/2026-08-08-stock-balances-traspaso.sql:54  total_ingreso  += N   (type IS NULL AND stock > 0)
                                              :64  on_hand        += N   (type IS NULL OR type <> 'suspend')
                                              :65  available      += N   (NEW.stock, 무조건)
                                              :83  movimientos    += 1
```
`type='OPENING_LEGACY'` 였다면 L54 만 0 이 되고 **L64·L65·L83 은 그대로다.**
```
api-ventago/migrations/2026-08-02-stock-interface-views.sql:20-33
CREATE VIEW v_stock_balance_drift AS
SELECT ... b.available - COALESCE(SUM(s.stock),0)::int AS drift ...
HAVING b.available <> COALESCE(SUM(s.stock), 0)
    OR b.movimientos <> COUNT(s.id);
```
→ `available` 도 `movimientos` 도 어긋나지 않으므로 **0행 유지**. 참고로 `stocks.type` 은 `varchar(20)`, CHECK 없음(`.planning/intel/db-schema-tables.md:2405` 이하) — DB 가 막아주지도 않는다. 유일한 방어는 Phase 65 W1 의 일회성 게이트뿐이다(`2026-07-28-phase65-w1-stock-type-normalize.sql:42-47`).

**결론 판정**
- SPEC 의 **처방**(`type = NULL` + `stock > 0` 을 쓰라)은 **맞다.** `total_ingreso` 로 집계되고 `fecha_primer_ingreso` 도 설정된다(L54, L66-67). drift 도 0 을 유지한다.
- SPEC 의 **이유**(새 값을 쓰면 drift 가 깨져서 잡힌다)는 **틀렸다.**

**수정**
1. §D1 의 「★ 트리거 함정」 문단을 "drift 가 깨진다" → "**drift 는 안 깨진다. `total_*` 버킷만 조용히 틀어진다 — 그래서 코드 리뷰 말고는 잡을 수단이 없다**" 로 고친다. 근거가 틀린 규칙은 다음 phase 에서 누군가 "왜 안 되지?" 하고 재시도한다.
2. §6 검증에 drift 0행만 두지 말고 **버킷 항등식**을 추가한다:
   `SUM(total_ingreso) = 임포트한 기준선 행 합`, `total_venta = 0`, `total_ajuste = 0`, `total_traspaso = 0`.
3. `stocks.type` 에 union CHECK 를 거는 별도 마이그레이션을 검토 대상으로 올린다(범위 밖이면 명시적으로 유예 기록).

---

### [HIGH] 86-SPEC.md:§8 — `trg_stocks_leaf_only` 가 §8 금지사항에 없다. 기준선 행이 madre PB 로 가면 **트랜잭션 전체가 죽는다**

**문제**
§8 은 `trg_stocks_immutable`, `product_id` 없음, `products.stock` 금지, 새 `type` 금지를 적었지만 **재고를 leaf 에만 붙일 수 있다**는 불변식은 빠져 있다. ACE 재고는 `codigoproducto` 단위인데 임포트는 `todocodigos → parents`, `codigos → variants` 로 **부모/자식 두 계층을 만든다**(`legacy-import.service.ts:78-88` TABLE_ROUTE). 매핑이 부모 쪽으로 떨어지는 코드가 하나라도 있으면 그 INSERT 에서 예외가 나고, 이 저장소는 그때 무슨 일이 벌어지는지 이미 겪었다 — 트랜잭션이 죽고 뒤따르는 문장이 전부 "current transaction is aborted" 가 되어 **진짜 원인이 덮인다.**

**근거**
```
api-ventago/migrations/2026-08-07-stock-leaf-only.sql:64-95
CREATE OR REPLACE FUNCTION stocks_leaf_only_guard() ...
  IF COALESCE(current_setting('ventago.allow_madre_stock', true), 'off') = 'on' THEN RETURN NEW; END IF;
  ... SELECT COUNT(*) INTO v_children FROM products c WHERE c.parent_id = v_product_id AND c.store_id = v_store_id AND c.status <> 'deactivated';
  IF v_children > 0 THEN  (예외)
```
```
api-ventago/src/app/sales/sales-create.service.ts:1971-1976
  // 운영 500 (14:29, 15:14 / 두 지점): ... applyStockLedger 가 그 **부모** ProductBranch 에
  // 원장을 쓰려다 `trg_stocks_leaf_only` 에 막혔다. 그 순간 트랜잭션이 죽고 뒤따르는 문장이 전부
  // "current transaction is aborted" 가 되어 **원인이 덮였다**
```
동시에 SPEC §2.2 가 인용한 ACE `stockrep` 원문에는 `length(codigoproducto) > 3` 필터가 있다 — ACE 안에서도 코드 길이로 계층이 갈린다는 신호다. 어느 쪽이 leaf 로 떨어지는지 SPEC 에 판정 규칙이 없다.

**수정**
1. §8 에 "`stocks` 는 **활성 자식이 있는 상품에 못 쓴다**(`trg_stocks_leaf_only`). 기준선 행은 leaf ProductBranch 에만" 을 추가한다.
2. 매퍼가 madre 로 해석된 코드를 만나면 **예외를 던지지 말고 skip + 결과표 보고**로 처리한다(부분 실패가 전체를 죽이지 않게).
3. `ventago.allow_madre_stock` 우회는 **쓰지 않는다** — 마이그레이션 스크립트 전용이라고 원문이 못박았다(`2026-08-07-stock-leaf-only.sql:61-63`).

---

### [HIGH] 86-SPEC.md:§D2 — legacy 판매를 나중에 **취소하면 있지도 않던 재고가 늘어난다**

**문제**
D1/D2 는 "임포트된 ventas 는 `stocks` 행을 만들지 않는다" 로 이중계상을 막았다. 여기까지는 옳다. 하지만 **판매 취소 경로는 원본이 재고를 깎았다고 가정하고 무조건 복원 행을 넣는다.** 매장주가 임포트된 과거 판매 한 건을 화면에서 취소하면, 차감된 적 없는 수량이 그대로 `+qty` 로 원장에 들어가 **재고가 부풀어 오른다.** 원장은 append-only 라 되돌리려면 또 보정 행을 넣어야 한다.

`vcodes.borrado = true` 인 것만 취소 상태로 넣는다는 D2 는 이 문제를 못 막는다 — 위험한 것은 **정상 상태로 임포트된 나머지 판매**다.

**근거**
```
api-ventago/src/app/sales/sales-create.service.ts:1414-1436
        // 재고 복원 (양수 이동 = 재입고)
        ...
            await Stocks.create(
              { productBranchId: pb.id, stock: qty, note: `anulacion sale_id=${locked.id}` },
              { transaction: t },
            );
```
이 행은 `type` 이 NULL 이므로 트리거에서 **`total_ingreso` 로 잡힌다**(`2026-08-08-stock-balances-traspaso.sql:54`) — 판매 취소가 입고로 기록되는 셈이라 리포트도 함께 오염된다.

**수정** — 셋 중 하나를 SPEC 에서 **명시적으로 선택**한다.
- (a) legacy 판매는 취소 불가로 막는다 — `SalesNullify` 진입점에서 `source='legacy'` 를 400 으로 거부.
- (b) `source='legacy'` 인 원본은 복원 행을 만들지 않는다 — `sales-create.service.ts:1414` 분기에 조건 추가.
- (c) 임포트 자체를 재고 중립으로 유지할 수 없다고 판단하고, 기준선을 "판매 이력 반영 후" 가 아니라 "판매 이력 반영 전" 시점으로 재정의한다.
(a) 가 가장 작고 되돌리기 쉽다. 어느 쪽이든 §6 검증에 "legacy 판매 1건 취소 → `v_stock_balance_drift` 0행 유지 + `available` 불변" 케이스를 넣는다.

---

### [HIGH] 86-SPEC.md:§D4 — DB 전역 타임아웃(statement 30s / idle-in-transaction 60s)을 SPEC 이 고려하지 않았다. 장시간 잡은 **중간에 세션이 끊긴다**

**문제**
D4 의 잡 러너는 "엔티티 단위 트랜잭션 + 1,000행 배치 커밋" 이다. 그런데 `ventago` DB 에는 데이터베이스 레벨 안전밸브가 걸려 있고, SPEC 은 이걸 한 줄도 언급하지 않는다.

- `statement_timeout = 30s` — 41,407행 `sale_items` 를 큰 배치로 넣으면 단일 문장이 30초를 넘길 수 있다(행마다 테넌트 트리거가 돈다). 넘기면 그 배치가 통째로 롤백된다.
- `idle_in_transaction_session_timeout = 60s` — **이쪽이 더 위험하다.** 트랜잭션을 연 채 다음 배치를 파싱·변환하느라 60초를 쉬면 **세션이 강제 종료된다.** 대용량 파일에서 CPU 바운드 파싱이 끼면 현실적인 시나리오다.
- `lock_timeout = 10s` — 라이브 매장에서 임포트하면 POS 판매와 락 경합 시 10초에 잘린다.

**근거**
```
api-ventago/migrations/db-safety-timeouts.sql:24-30
ALTER DATABASE ventago SET statement_timeout = '30s';
ALTER DATABASE ventago SET lock_timeout = '10s';
ALTER DATABASE ventago SET idle_in_transaction_session_timeout = '60s';
```
같은 파일 L12-13 이 예외 처리 방법도 적어뒀다: "배치/마이그레이션이 30s 를 넘길 수 있으면 해당 세션에서 `SET statement_timeout = 0;` 로 임시 해제".

**수정**
1. 잡 워커 트랜잭션 시작 시 `SET LOCAL statement_timeout` / `lock_timeout` 을 **명시적으로** 올린다(예: 60s/30s). `SET LOCAL` 이면 그 트랜잭션에서만 유효해 다른 경로에 안 샌다 — 이 저장소가 판매 경로에서 쓰는 패턴 그대로다(`sales-create.service.ts:638`). **`= 0`(무제한)은 쓰지 않는다** — pool 슬롯 영구 점유가 이 밸브를 만든 이유다.
2. **파싱·변환은 트랜잭션 밖에서 끝낸다.** 트랜잭션은 "이미 메모리에 준비된 배치를 INSERT 하고 즉시 커밋" 만 감싼다. idle-in-transaction 60초는 이 구조로만 안전해진다. 「트랜잭션 안 외부 I/O 금지」(§8)와 같은 취지이므로 §8 에 "트랜잭션 안 파싱 금지" 를 한 줄 추가한다.
3. 배치 크기 1,000 은 근거 없는 숫자다 — `sale_items` 처럼 트리거가 붙은 테이블에서 실측해 SPEC 에 소요시간을 적는다.

---

### [HIGH] 86-SPEC.md:§D3 — 임시 비밀번호의 **보관 위치가 설계에 없다.** "DB 평문 저장 금지" 와 "비동기 잡 + 폴링" 이 정면충돌한다

**문제**
D3 은 "임시 비밀번호는 임포트 결과 화면에서 1회만 표시 + CSV 다운로드. **DB 평문 저장 금지**, 로그 출력 금지" 라고 했다. 그런데 D4 는 실행을 **비동기 잡 + 폴링**으로 바꿨다. 비밀번호를 만드는 시점(워커)과 사용자가 결과를 보는 시점(폴링 응답)이 분리되므로, 평문은 **그 사이 어딘가에 반드시 존재해야 한다.** SPEC 은 그 자리를 지정하지 않았다.

가능한 자리마다 다른 위험이 있고 어느 것도 SPEC 에 평가돼 있지 않다:
- `legacy_imports.progress jsonb`(M2) 에 넣는다 → **"DB 평문 저장 금지" 위반.** 게다가 이력 테이블이라 영구히 남는다.
- 워커 프로세스 메모리에 둔다 → PM2 4워커다. 폴링 요청이 **다른 워커로 라우팅되면 결과를 못 찾는다.**
- 잡 완료 응답에 한 번만 실어 보낸다 → 폴링 타이밍을 놓치면(브라우저 새로고침·네트워크 끊김) 12개 계정이 **영구 잠금**된다. 복구 절차도 없다.

여기에 더해, D4 가 새로 여는 `GET /legacy-import/jobs/:id` 는 **소유권 검증 규칙이 SPEC 에 없다.** 현행 컨트롤러는 role 만 보고 storeId 는 요청자 것을 강제하는 구조인데(`assertAdmin` + `user.storeId`), 잡 ID 는 사용자가 주는 값이다. 검증을 빠뜨리면 다른 매장 admin 이 **남의 매장 임시 비밀번호 목록을 읽는다** — REVIEW-PROTOCOL 우선순위 3번(Phase 69 CR-02 유형) 그 자체다.

**근거**
```
api-ventago/src/app/legacy-import/legacy-import.controller.ts:80,151,154-158
  @UseGuards(AuthGuard('jwt'))        ← SessionGuard 없음(현행 상태)
    this.assertAdmin(user);
    ... this.legacyImportService.listHistory(user.storeId, ...)   ← storeId 는 토큰에서만 온다
```
현행 `history` 는 사용자 입력 ID 를 안 받아서 안전하다. `jobs/:id` 는 **처음으로 사용자 입력 ID 를 받는 엔드포인트**가 된다.
```
api-ventago/Dockerfile:53,64  (PM2 클러스터 — 워커 간 메모리 공유 없음)
```

**수정**
1. `GET /legacy-import/jobs/:id` 는 **`WHERE id = :id AND store_id = user.storeId`** 로 조회한다. 못 찾으면 403 이 아니라 404(존재 여부도 안 알린다). SPEC §D4 에 이 문장을 명시한다.
2. 임시 비밀번호는 **잡 결과에 담지 않는다.** 대안 중 하나를 SPEC 에서 고른다:
   - (권장) 임포트는 계정을 `must_change_password = true` + **비밀번호 없음/로그인 불가** 상태로만 만들고, 별도의 "초대 링크/1회용 토큰" 을 매장 admin 이 계정별로 발급한다. 평문이 아예 생기지 않는다.
   - 차선: 평문을 **bcrypt 저장과 동시에 짧은 TTL(예: 15분)의 별도 테이블**에 넣고, 1회 조회 후 삭제 + TTL 만료 삭제. 이 경우 "DB 평문 저장 금지" 를 "**단기 TTL 1회조회 테이블은 예외**" 로 SPEC 에 명시적으로 완화해야 한다 — 금지 문구를 남긴 채 구현하면 다음 검토에서 다시 걸린다.
3. CSV 다운로드 응답에 `Cache-Control: no-store` 를 건다.

---

### [HIGH] 86-SPEC.md:§4 — Gastos 의 의존성이 틀렸다. `expenses` 는 NOT NULL 이 4개다

**문제**
§4 의 체크박스 트리에서 `Gastos` 는 **의존 항목이 없다.** 실제 `expenses` 테이블은 `user_id`·`branch_id`·`description`·`date` 가 전부 NOT NULL 이다. Usuarios 를 선택하지 않고 Gastos 만 고르면 `user_id` 를 채울 수 없어 임포트가 실패한다. 지점도 마찬가지다.

분류 테이블도 어긋난다: SPEC §2.4 는 `expense_categories` 라고 썼는데 실제 이름은 **`expenses_categories`** 이고, `store_entity_id` 가 NOT NULL 이다(SPEC 에 언급 없음).

**근거**
```
.planning/intel/db-schema-tables.md:912-928  (expenses)
| `description` | character varying(255) | NOT NULL |
| `date`        | timestamp with time zone | NOT NULL |
| `user_id`     | integer | NOT NULL |
| `branch_id`   | integer | NOT NULL |
| `store_id`    | integer | NOT NULL |

.planning/intel/db-schema-tables.md:936-945  (expenses_categories)
| `store_entity_id` | integer | NOT NULL |
```

**수정**
§4 트리를 `[ ] Gastos (gastos + gasto_info) → Usuarios, 기준정보` 로 고치고, "사용자를 안 가져오면 임포트 실행자 계정으로 귀속" 같은 폴백을 쓸지 여부를 SPEC 에서 결정한다(폴백을 쓸 거면 그 사실이 결과표에 보여야 한다). §2.4 의 테이블명도 `expenses_categories` 로 정정한다.

---

### [HIGH] 86-SPEC.md:§D5 — 재개 전략이 "맵이 있으니 된다" 수준이다. **부분 저장 상태의 판정 규칙이 없다**

**문제**
D5 는 `legacy_entity_maps` 가 "잡 실패 시 **재개 지점**이 된다" 고만 적었다. 이 맵은 `(store_id, entity, legacy_id, ventago_id)` — 즉 **"이 엔티티는 만들었다" 만 기록한다.** 배치 커밋 중간에 죽었을 때 실제로 생기는 상태는 이 맵으로 판정되지 않는다.

구체적으로:
- `sales` 는 커밋됐는데 그 판매의 `sale_items` 배치가 죽었다 → 맵에는 sale 이 "완료" 로 있다. 재개하면 **품목 없는 판매**가 영구히 남는다. §6 의 `sale_items = vdetalle 유효행수` 대조는 실패하는데, 어느 판매가 반쪽인지는 알 수 없다.
- `sale_items` 는 맵에 개별 기록할 자연키가 마땅치 않다(ACE `vdetalle` 의 PK 를 넣으면 41,407행 × 맵 1행 = 맵 테이블이 본체보다 커진다).
- 기준선 `stocks` 행은 **append-only 라 되돌릴 수 없다.** 재개 시 중복 INSERT 하면 재고가 두 배가 되고, 정정하려면 반대 부호 보정 행이 또 필요하다.

「쓰기 경로 규약」의 "**하나의 업무 동작이 만드는 모든 행은 하나의 트랜잭션에서 커밋한다**"(CLAUDE.md)가 여기서 D4 의 배치 커밋과 충돌하는데, SPEC 은 그 충돌을 다루지 않는다.

**수정**
1. **트랜잭션 경계를 "부모+자식" 단위로 정의한다.** `sales` 배치는 그 배치에 속한 `sale_items`·`sale_payment_methods` 를 **같은 트랜잭션에서** 커밋한다. 배치는 "1,000행" 이 아니라 "**판매 N건과 그에 딸린 전부**" 로 센다.
2. `legacy_entity_maps` 에 자식이 아니라 **부모 엔티티만** 기록하고, 부모 커밋 = 자식 완결을 의미하도록 위 (1)로 보장한다.
3. 기준선 `stocks` 는 **단일 트랜잭션 all-or-nothing** 으로 넣고, 재개 시에는 `legacy_entity_maps(entity='stock_opening')` 존재 여부로 **통째로 건너뛴다.** 부분 재개를 허용하지 않는다.
4. §6 검증에 "임포트를 임의 시점에 강제 중단 → 재개 → 최종 행수가 무중단 실행과 동일" 케이스를 추가한다. 지금 §6-5 의 멱등성 항목("같은 파일 재임포트 시 신규 생성 0건")은 **성공 후 재실행**만 검증하고 **중단 후 재개**는 검증하지 않는다.

---

### [HIGH] 86-SPEC.md:§D2 — `daily_number` 재부여가 기존 판매와 충돌한다. 그리고 판매 1건마다 락을 잡으면 9,731회다

**문제 (a) 충돌**
D2 는 "`daily_number` 는 `uq_sales_branch_daylocal_dn` 때문에 **지점×일자 단위**로 재부여" 라고만 적었다. 재부여 **시작점**이 정의돼 있지 않다. 이미 VentaGO 에서 영업 중인 매장(또는 재임포트 상황)이라면 같은 `(store_id, branch_id, sale_day_local)` 버킷에 기존 행이 있고, 1번부터 다시 매기면 **UNIQUE 위반**으로 배치가 죽는다.

`branch_id` 가 NULL 로 떨어지는 판매도 위험하다 — 이 인덱스는 `NULLS NOT DISTINCT` 라서 NULL 지점도 **하나의 버킷으로 묶여** 유일성이 강제된다. 운영에 이미 NULL 지점 판매가 3건 있다.

**문제 (b) N+1**
기존 채번기를 판매마다 호출하면 판매 1건당 `advisory lock 1회 + findOne 1회` = **9,731건 × 2쿼리**. 게다가 채번기는 `pg_advisory_xact_lock` 이므로 배치 트랜잭션 전체가 그 지점·그 날짜에 대해 직렬화된다 — 라이브 매장이면 **그 지점의 POS 판매가 임포트 배치를 기다린다.**

**근거**
```
api-ventago/migrations/2026-08-20-sales-daily-number-per-branch.sql:21-24
CREATE UNIQUE INDEX IF NOT EXISTS uq_sales_branch_daylocal_dn
  ON sales (store_id, branch_id, sale_day_local, daily_number)
  NULLS NOT DISTINCT
  WHERE activity_type = 'sale' AND daily_number > 0;

같은 파일 L15-16
-- ★ NULLS NOT DISTINCT: branch_id 가 NULL 인 행(지점 미상, 운영 3건)도 하나의 버킷으로 묶어 ...
```
```
api-ventago/src/app/sales/daily-number.service.ts:83-106
        SELECT pg_advisory_xact_lock($1::int, hashtext($2::text))   ← 판매 1건당 1회
        ... Sale.findOne({ where: { storeId, branchId, activityType, saleDayLocal }, order: [['dailyNumber','DESC']] })
```
추가로 `BEFORE INSERT` 트리거가 `branch_id` 가 NULL 이면 `users.branch_id` 로 채운다 — SPEC 이 "직접 채운다" 고 한 값과 다른 값이 들어갈 수 있는 경로다:
```
api-ventago/migrations/2026-08-19-sales-branch-guards.sql:18-21
  IF NEW.branch_id IS NULL AND NEW.user_id IS NOT NULL THEN
    SELECT u.branch_id INTO NEW.branch_id FROM users u WHERE u.id = NEW.user_id;
```

**수정**
1. `DailyNumberService.reserve` 를 **행마다 호출하지 않는다.** 지점×일자별로 기존 최댓값을 **한 번** 조회하고(`GROUP BY branch_id, sale_day_local`), 배치 안에서 `ROW_NUMBER() OVER (PARTITION BY branch_id, sale_day_local ORDER BY sale_date, legacy_id)` 로 **오프셋을 더해** 부여한다. 쿼리 수가 9,731×2 → 버킷 수×1 로 떨어진다.
2. 지점 매핑 실패 시 `branch_id` 를 NULL 로 두지 말고 **해당 판매를 skip + 보고**한다 (NULLS NOT DISTINCT 버킷 오염 방지).
3. §D2 에 "재부여는 **기존 최댓값 다음부터**" 를 명시하고, §6 대조에 "임포트 후 `uq_sales_branch_daylocal_dn` 위반 0 / 기존 판매의 `daily_number` 불변" 을 넣는다.

---

## MEDIUM

### [MEDIUM] 86-SPEC.md:§6 — "`SUM(sales.total_amount)` = `SUM(vcodes.tpago)` (허용 오차 0)" 은 타입상 성립 불가일 수 있다
`sales.total_amount`·`subtotal`·`discount_amount` 와 `sale_payment_methods.amount` 는 전부 **integer** 다(`db-schema-tables.md:2174` 이하, `:2137` 이하). `sale_items.price`·`subtotal` 만 numeric 이다. ACE `tpago` 에 소수점이 있으면 판매 헤더에서 절사가 일어나 오차 0 은 불가능하다. 또한 헤더(integer)와 품목 합(numeric)이 갈라진다.
**수정:** ACE `tpago`/`vdetalle` 금액의 소수 자릿수를 실측해 §2.1 표에 적고, 반올림 규칙(헤더 기준 vs 품목 합 기준)을 §D2 에 명시. 오차 허용치를 실측값으로 정한다.

### [MEDIUM] 86-SPEC.md:§2.4 — 테이블명 오기 2건
`sale_payments` → 실제 **`sale_payment_methods`** (`db-schema-tables.md:2137`).
`expense_categories` → 실제 **`expenses_categories`** (`db-schema-tables.md:936`).
CLAUDE.md 가 "SQL/마이그레이션/raw query 작성 전 반드시 intel 파일 참조 — 추측 X" 라고 못박은 항목이다. 매퍼 작성 시 그대로 옮겨 적으면 런타임에야 드러난다.

### [MEDIUM] 86-SPEC.md:§4 — Venta x crédito 의 의존성이 부족하다 (`store_clients`·`payment_methods`·running balance)
`credit_ledger` 는 `store_client_id NOT NULL` + **`bucket_after numeric NOT NULL`**(누적 잔액), `credit_payments` 는 `payment_method_id NOT NULL` + `receipt_no NOT NULL` 이다(`db-schema-tables.md:752-788`). SPEC §4 는 Venta x crédito 의 의존을 `Ventas` 하나로만 적었다.
- `bucket_after` 는 **고객별 시간순 누적**이라 배치 순서가 결과를 바꾼다 — 병렬·역순 삽입 금지 규칙이 필요하다.
- ACE `cobranzacab` 의 결제수단을 VentaGO `payment_methods` 로 매핑하는 표가 없다.
- `store_clients.balance` / `senia_balance` 동기화 규칙도 없다.
**수정:** 의존을 `→ Ventas, Clientes, 결제수단` 으로 고치고, `bucket_after` 산출 규칙(고객별 `ORDER BY fecha, legacy_id` 누적)을 §D 에 추가한다.

### [MEDIUM] 86-SPEC.md:§D4 — 배치 `bulkCreate` 는 `Clients` 의 `AfterCreate` 훅을 건너뛴다 → `StoreClient` 가 안 생긴다
현행 clientes 임포트는 행 단위 `Clients.create` 로 돌고, 훅이 `GlobalClient`/`StoreClient` 를 파생시킨다.
```
api-ventago/src/app/legacy-import/legacy-import.service.ts:1074
        // Clients.create → AfterCreate 훅이 GlobalClient/StoreClient 자동 sync
api-ventago/src/app/legacy-import/legacy-import.module.ts:8   (같은 내용)
```
D4 의 1,000행 배치 커밋을 `bulkCreate` 로 구현하면 Sequelize 는 기본적으로 개별 훅을 실행하지 않는다 → `store_clients` 가 비고, 그 위에 얹히는 credito 임포트(`store_client_id NOT NULL`)가 전부 실패한다. 16,144행이라 성능상 `bulkCreate` 유혹이 큰 지점이다.
**수정:** SPEC 에 "clientes 배치는 `individualHooks: true` 또는 파생행 명시 생성" 을 못박는다. §6 대조에 `count(store_clients) = count(clients)` 를 추가한다.

### [MEDIUM] 86-SPEC.md:§5 M3 — `must_change_password` 는 컬럼만 추가하면 **아무 일도 일어나지 않는다.** 고쳐야 할 곳 5군데
D3 은 "최초 로그인 변경 강제" 라고 했지만 M3 은 컬럼 추가뿐이다. 현행 `signIn` 은 비밀번호가 맞으면 **그대로 accessToken 을 발급**하고 끝난다. 플래그를 안 보므로 임시 비밀번호로 시스템 전체를 무기한 쓸 수 있다.
지목:
1. `api-ventago/src/app/auth/auth.service.ts:600-613` — `signIn` 반환 객체에 `mustChangePassword` 추가(현재 `accessToken, id, name, ..., roles, storeId, ...sessionResult`).
2. `api-ventago/src/app/auth/auth.service.ts:812` — `me()` 응답에도 추가. 새로고침으로 로그인 화면을 우회하는 경로를 막는다.
3. `api-ventago/src/app/auth/auth.service.ts:1246-1270` — `changePassword` 성공 시 **플래그를 false 로 내린다.** 지금은 `user.update({ password: hashedPassword })` 만 한다(L1269). 안 내리면 영구 강제 루프.
4. **강제 지점** — 프론트 리다이렉트만으로는 API 가 그대로 열린다. `SessionGuard`(`api-ventago/src/app/session/guards/session.guard.ts`) 또는 신규 가드에서 `mustChangePassword === true` 면 `auth/change-password` 외 요청을 403 으로 막는다. SPEC 에 "어디서 막는지" 를 적는다.
5. `Users` 모델에 속성 추가 — 컬럼만 만들고 모델에 안 넣으면 앱이 읽지 못한다. Dockerfile 의 `verify-models.js` 게이트(`api-ventago/Dockerfile:23`)도 통과 대상이다.

### [MEDIUM] 86-SPEC.md:§5 M2 — `legacy_imports.status` 에 CHECK 제약이 없다. "QUEUED/RUNNING 허용" DDL 은 불필요
```
api-ventago/migrations/2026-06-25-legacy-imports.sql:44
  status  VARCHAR(32) NOT NULL DEFAULT 'COMPLETED',  -- COMPLETED | FAILED | PARTIAL
```
제약이 아니라 주석이다. M2 에서 실제로 필요한 것은 `selected_entities jsonb` / `progress jsonb` **컬럼 추가와 잡 락용 인덱스**뿐이다. SPEC 문구가 있으면 구현자가 없는 제약을 찾다가 시간을 쓴다.

### [MEDIUM] 86-SPEC.md:§5 M1 — `legacy_entity_maps` 에 FK·CASCADE·모델 등록이 명시돼 있지 않다
선례인 `legacy_imports` 는 `store_id INTEGER NOT NULL REFERENCES stores(id) ON DELETE CASCADE` 다(`2026-06-25-legacy-imports.sql:26`). M1 은 "`legacy_entity_maps` 신규 + UNIQUE + owner 이전 DO 블록" 만 적었다. FK/CASCADE 가 없으면 매장 삭제 시 **고아 매핑이 남아** 같은 store_id 가 재사용될 때 엉뚱한 `ventago_id` 로 FK 를 변환한다.
또한 이 테이블을 Sequelize 모델로 등록하지 않으면 테넌트 격리 훅이 안 걸린다 — 훅은 `sequelize.models` 순회로 설치된다(`api-ventago/src/common/tenant/tenant-hooks.ts:706-727`).
**수정:** M1 에 `REFERENCES stores(id) ON DELETE CASCADE`, `(store_id, entity)` 조회 인덱스, 모델 등록을 명시.

### [MEDIUM] 86-SPEC.md:§D1 — 기준선 임포트가 **리포트를 통째로 왜곡한다.** SPEC 의 "의도된 동작" 범위가 재고 잔액에만 걸려 있다
D2 는 `total_venta = 0` 이 의도된 동작이라고 했다. 그 파급이 잔액에서 끝나지 않는다:
```
api-ventago/migrations/2026-08-08-stock-balances-traspaso.sql:168-175 (v_stock_sucursal_variante)
    round(b.total_venta * 100.0 / NULLIF(b.total_ingreso + b.total_ajuste + b.total_traspaso, 0), 1) AS porcentaje_vendido,
    CASE WHEN b.available <= 0 THEN 'AGOTADO' WHEN b.total_venta = 0 THEN 'SIN_MOVIMIENTO' ...
```
→ 임포트한 **모든 품목이 `SIN_MOVIMIENTO`, `porcentaje_vendido = 0`, `dias_sin_venta = NULL`**. 매장주가 처음 보는 재고 화면이 통째로 "안 팔린 물건" 으로 표시된다.
```
api-ventago/migrations/2026-08-02-stock-interface-views.sql:72-83 (v_stock_dia)
```
→ 기준선 행의 `operation_date` 를 임포트 실행일로 두면(SPEC §D1 이 그렇게 정했다) **그날 하루에 전 품목 입고가 몰린 것으로** 잡힌다. Cockpit·`ingreso_hoy` 가 그날만 폭증한다.
또 `fecha_primer_ingreso`/`fecha_ultimo_ingreso` 가 실제 입고일이 아니라 임포트일이 된다(`traspaso.sql:66-67`).
**수정:** 이 세 가지를 §D1 에 "알려진 부작용" 으로 명시하고 수용 여부를 결정한다. 최소한 `operation_date` 를 임포트일이 아니라 **ACE 마지막 영업일** 같은 과거 날짜로 둘지 검토한다(그러면 `v_stock_dia` 오늘 폭증은 피한다).

### [MEDIUM] 86-SPEC.md:§2.2 — 365일 롤링 창을 그대로 이식하면 **임포트 당일에만 숫자가 맞다**
SPEC 은 "이 필터를 그대로 재현하지 않으면 매장주가 구 시스템 화면에서 보던 숫자와 달라진다" 고 했다. 맞다. 그런데 ACE 의 창은 **매일 미끄러진다**(`now - fecha < 365`). VentaGO 는 기준선을 한 번 박고 그 뒤로 영구 잔액으로 굴린다. 따라서 두 시스템은 **임포트 다음 날부터 자동으로 갈라진다** — VentaGO 는 유지, ACE 는 366일 지난 입고가 빠지면서 감소.
이건 결함이 아니라 정상이지만, SPEC 이 "같은 숫자" 를 목표로 적어두면 매장주 문의 시 근거가 없다.
**수정:** §2.2 에 "일치는 **임포트 시점 스냅샷 한정**. 이후 두 시스템은 정의가 달라 갈라진다" 를 명시하고, 결과 화면 문구에도 반영한다.

### [MEDIUM] 86-SPEC.md:§D4 — 격리 수준이 정해져 있지 않다. 현행 코드의 SERIALIZABLE 전제("동시 writer 없음")는 라이브 매장에서 깨진다
```
api-ventago/src/app/legacy-import/legacy-import.service.ts:658-660
    // 단일 SERIALIZABLE 트랜잭션 — 일회성 관리자 import, 동시 writer 없음 (D-2)
    await this.sequelize.transaction(
      { isolationLevel: Transaction.ISOLATION_LEVELS.SERIALIZABLE },
```
Phase 86 은 범위를 `sales`·`stocks`·`expenses` 로 넓힌다 — 전부 POS 가 동시에 쓰는 테이블이다. SERIALIZABLE 을 유지하면 `40001 serialization_failure` 가 나고, 배치 재시도 로직이 없으면 잡이 죽는다. 반대로 낮추면 그 이유를 적어야 한다.
**수정:** §D4 에 격리 수준과 `40001`/`40P01` 재시도 정책(횟수·백오프)을 명시. "동시 writer 없음" 전제는 **더 이상 참이 아니다**라고 기록한다.

### [MEDIUM] 대량 INSERT 가 통과하는 per-row 트리거 비용 — 규모를 SPEC 에 적어야 한다
실측 아닌 **정적 계수**다(측정 필요):
- `sales` 1행당 트리거 2개 — `trg_sales_fill_branch`(users 1 SELECT), `trg_tenant_sales_branch_id`(branches 1 SELECT) → `2026-08-19-sales-branch-guards.sql:27-40`. 9,731건 × 2 ≈ **19.5k 서브쿼리**.
- `sale_items` 1행당 테넌트 트리거 1개 → `2026-07-30-tenant-crossstore-triggers.sql:184`. 41,407건 ≈ **41k**.
- `stocks` 1행당 트리거 4개 — `trg_stocks_fill_tenant`, `trg_stocks_fill_operation_date`(PB→product→store 조인), `trg_stocks_leaf_only`(자식 수 COUNT), `trg_stock_balances_apply`(PB→product 조인 + upsert). 기준선 행 수 × 4.
합계 대략 **6만~7만 회의 트리거 내부 쿼리**. 30초 statement_timeout 과 함께 보면 배치 크기 1,000 이 안전한지는 **실측 없이 단정할 수 없다**.
**수정:** §6 검증에 "엔티티별 배치 소요시간·최대 단일 문장 시간" 측정을 추가하고 배치 크기를 그 결과로 정한다. `sync_outbox` 는 이 경로에 트리거가 없어 무관함을 확인했다(`sync_outbox` 는 애플리케이션이 명시 INSERT 하는 구조 — `phase43-sync-outbox.sql`).

### [MEDIUM] 86-SPEC.md:§7 TASK-2b — pg_restore 의존 제거는 **전부 아니면 전무**다. 부분 이식하면 tar 경로가 죽는다
현행 `DumpConverterService` 는 custom 과 **tar 둘 다** pg_restore 로 처리한다(`dump-converter.service.ts:9-11, 70-73`). TASK-2b 는 "PGDMP custom 리더" 만 이식한다고 적었다. 이 상태로 Dockerfile 의 `apk add postgresql-client`(`api-ventago/Dockerfile:60`)를 지우면 **tar(-Ft) 백업 업로드가 500 이 된다.**
**수정:** TASK-2b 를 승인한다면 (a) tar 도 함께 이식하거나 (b) tar 를 명시적으로 미지원 처리하고 사용자에게 안내 메시지를 준다 — 둘 중 하나를 SPEC 에 적는다. `postgresql-client` 제거는 그 다음이다.

---

## LOW

### [LOW] 86-SPEC.md:§2.1 — `corregidos` 의 행 수가 실측 표에 없다
§2.2 재고 공식의 세 번째 항이 `corregidos.cantoffset` 이고, SPEC 스스로 "빠뜨리면 실사 조정분이 통째로 사라진다" 고 경고했다. 그런데 §2.1 실측 표에 `corregidos` 가 없다. F2(`ingresos.cant3` 이 거의 전부 0)와 같은 함정이 여기에도 있는지 알 수 없다.
**수정:** `corregidos` 행 수와 `SUM(cantoffset)` 을 실측해 §2.1 에 추가한다.

### [LOW] 86-SPEC.md:§6.1 — 검증 도구가 `/tmp/w/ace.py` 에만 있다
"PGDMP custom 포맷 리더를 직접 구현해 백업을 완전히 디코드했다 (`/tmp/w/ace.py`)" — 샌드박스 임시 경로다. 세션이 끝나면 사라지고, 저장소에서 확인할 수 없다(**미확인**: 저장소 내 동일 파일 없음). §2.1·§2.2·§2.3 의 모든 실측 수치가 이 도구에 근거하는데 **재현이 불가능하다.**
**수정:** 스크립트를 `.planning/phases/86-.../tools/` 또는 `scripts/` 에 커밋한다. TASK-2b 를 승인하지 않더라도 검증 근거로 남겨야 한다.

### [LOW] `legacy-import.controller.ts` 는 `SessionGuard` 미적용 (현행 상태 — 이번 변경으로 나빠지지는 않는다)
`@UseGuards(AuthGuard('jwt'))` 만 걸려 있다(L80, L108, L139). CLAUDE.md 의 세션 보안 절은 "필요한 컨트롤러에 `@UseGuards(SessionGuard)` 적용" 이라고 되어 있다. 매장 전체 데이터를 쓰는 엔드포인트이고 §D3 로 **임시 비밀번호까지 다루게 되므로**, jobs 엔드포인트를 추가하는 김에 재검토할 가치가 있다. 이번 SPEC 이 만든 문제는 아니다.

### [LOW] `stocks.source = 'legacy_opening'` 은 안전하다 — 확인 완료
`stocks.source` 는 `varchar(32)`(`2026-08-07-stocks-source.sql:30`), CHECK 없음. `'legacy_opening'`(14자) 문제 없다. `total_traspaso` 는 `source = 'migration_transfer'` 만 세므로(`2026-08-08-stock-balances-traspaso.sql:60`) 간섭 없다. `total_ajuste` 도 `type='adjust'` 조건이라 무관하다(L57-59). **이상 없음.**

---

## 확인 결과 — SPEC 주장별 판정 요약

| SPEC 주장 | 판정 | 근거 |
|---|---|---|
| `type=NULL` + `stock>0` → `total_ingreso` 로 집계 + `fecha_primer_ingreso` 설정 | **참** | `2026-08-08-stock-balances-traspaso.sql:54,66-67` |
| 기준선 행을 넣어도 `v_stock_balance_drift` 0행 유지 | **참** | `2026-08-02-stock-interface-views.sql:20-33` (available·movimientos 양쪽 일치) |
| 새 `type` 값을 쓰면 drift 가 **즉시 깨진다** | **거짓** | drift 뷰는 `total_*` 를 보지 않는다 → HIGH 항목 참조 |
| `stocks` 는 UPDATE/DELETE 금지, 보정은 반대 부호 행 | **참** | `2026-07-28-phase65-w2-stocks-immutable-trigger.sql:37-41` |
| `stocks` 에 `product_id` 컬럼 없음 | **참** | `db-schema-tables.md:2405` 이하 — `product_branch_id` 만 존재 |
| `uq_sales_branch_daylocal_dn` 때문에 순번이 지점×일자 단위 | **참**(단 NULLS NOT DISTINCT 조건 누락) | `2026-08-20-sales-daily-number-per-branch.sql:21-24` |
| `sales.branch_id` 를 직접 채운다(user 유추 금지) | **참**, 단 BEFORE INSERT 트리거가 NULL 일 때 user 로 채운다는 사실 미언급 | `2026-08-19-sales-branch-guards.sql:18-21` |
| `sales.source = 'legacy'` | **거짓 — CHECK 위반** | CRITICAL 항목 |
| `sales.status = 'anulada'` | **거짓 — 실제 값은 `'Anulado'`** | CRITICAL 항목 |
| advisory lock 으로 매장당 동시 잡 1개 | **성립 불가(pgbouncer transaction mode)** | CRITICAL 항목 |
| 워커 커넥션 1개 → pool(min2/max20 ×4워커, pgbouncer 50)과 무충돌 | **커넥션 수는 무해**. 문제는 개수가 아니라 **점유 시간**(statement/idle 타임아웃) | `database.module.ts:62-68` + `db-safety-timeouts.sql:24-30` |
| diskStorage 전환 + 200MB | **현행 코드와 비호환**: `file.buffer` 전제(`legacy-import.controller.ts:188,205`) + 전량 문자열 적재 | CRITICAL 항목 |
| `legacy_entity_maps` 가 기존 `legacy_imports`/`code_imports` 와 충돌 | **충돌 없음**(이름·컬럼 중복 없음). 다만 FK/CASCADE·모델 등록 미명시 | `db-schema-tables.md:671,1057` |
| M2 가 status CHECK 를 넓혀야 한다 | **불필요 — CHECK 자체가 없다** | `2026-06-25-legacy-imports.sql:44` |
| `users.must_change_password` 추가로 강제 로그인 변경 | **컬럼만으로는 무효** — 5개 지점 수정 필요 | MEDIUM 항목 |

---

## 승인 권고

REVIEW-PROTOCOL 게이트 기준: **CRITICAL 4 / HIGH 8 이 미해소이므로 이 SPEC 은 그대로 승인하지 않는다.**

승인 전 SPEC 문서에서 반드시 고쳐야 할 것(구현 착수 전, 문서 수정만으로 가능):
1. `sales.source` 화이트리스트 확장을 M5 로 추가 + `SaleSource` enum 동시 변경 명시 (C1)
2. `status` 문자열을 `'Anulado'` 로 정정 (C2)
3. advisory lock → 리스 테이블 기반 잡 락으로 D4 재작성 (C3)
4. 200MB 상한을 스트리밍 파서(TASK-2b)의 **후행 조건**으로 재배치 (C4)
5. §D1 「트리거 함정」의 근거 문장 정정 + §6 에 버킷 항등식 추가 (H1)
6. §8 에 `trg_stocks_leaf_only` 추가 (H2)
7. legacy 판매 취소 정책 결정 (H3)
8. 트랜잭션 타임아웃·파싱 위치 규칙 (H4)
9. 임시 비밀번호 보관 위치 결정 + `jobs/:id` storeId 소유권 검증 명시 (H5)
10. §4 의존성 트리 정정: Gastos → Usuarios, Venta x crédito → +Clientes/결제수단 (H6, M-credito)
11. 중단-재개 시 부모+자식 트랜잭션 경계 규칙 (H7)
12. `daily_number` 재부여 시작점 + 벌크 채번 방식 (H8)

§9 「승인 필요 항목」에 대한 검토자 의견:
- **1번(D1 `type = NULL` 결정)**: 결정 자체는 **옳다**. 다만 근거 문장이 틀렸으므로 위 5번을 고친 뒤 승인할 것.
- **2번(TASK-2b)**: **선택이 아니라 필수**로 승격 권고 (C4). 단 tar 경로 처리를 함께 결정할 것 (M-TASK2b).
- **5번(M1~M4 운영 즉시 적용 여부)**: **로컬 검증 완료 후로 미룰 것.** 위 정정으로 M1·M2 의 내용이 바뀌고 M5(source CHECK)가 새로 필요하다. 지금 운영에 넣으면 되돌릴 수 없는 형태로 스키마가 갈라진다.
- **3·4번**: 검토 범위 밖 — **미확인**(정책 결정 사항이며 코드 대조로 판정할 성질이 아니다).
