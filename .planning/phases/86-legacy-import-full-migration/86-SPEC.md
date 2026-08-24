> # ⚠ 이 문서는 대체됐다 — **`86-SPEC-v3.md` 를 볼 것**
>
> v2 는 **kandente4 한 매장**의 백업만 보고 썼고, 다른 매장(serpenti)을 실제로
> 복원해 재 보니 전제 두 개가 무너졌다:
>
> 1. "`codigos_tmp` 가 백업 대부분" → serpenti 에서는 **5.4%** 뿐 (94.6% 잔존).
>    그 위에 서 있던 **TASK-2b 정당화가 함께 무너진다.**
> 2. 재고를 `stockrep`(365일 롤링)로 → 사용자 결정으로 **`screendetails2_id`,
>    전 기간**으로 바뀌었다.
>
> 그리고 선택 단위(원시 테이블 → 업무 단위 원자 묶음)와 음수 재고 정책도 확정됐다.
> **아래 본문은 참고용이며, 충돌하면 v3 가 이긴다.**

---
phase: 86-legacy-import-full-migration
type: spec
version: 2
created: 2026-08-20
revised: 2026-08-20 (검토 반영 — .team/reviews/phase86-spec-resolution.md)
branch: feature/phase86-legacy-import-full
status: CONFIRMED — 구현 착수 가능
approved_decisions:
  - 검증 환경: 샌드박스 PG18 (npm 바이너리) + ventago 스키마 복제 + 더미 매장
  - 재고 정책: 스냅샷 기준선 (ventas·ingresos 는 stocks 원장에 쓰지 않는다)
  - ingresos: `legacy_ingresos` 이력 보관 + 기준선 유지
  - fventas/fdetalles: `afip_vouchers` + `sales.cae` 로 매핑
  - 계정 이관: 임시 비밀번호 발급 + 최초 로그인 변경 강제
  - 실행 방식: 비동기 잡 + 진행률 (advisory lock 아님 — 리스 테이블)
  - TASK-2b (PGDMP 스트리밍 리더): **필수**
---

# Phase 86 — Importar Legacy 전면 확장 (구 ACE III → VentaGO 전체 이관)

## 0. v1 → v2 변경 요약

검토(`.team/reviews/phase86-spec-review.md`)에서 CRITICAL 4 / HIGH 8 이 나왔고 전부 반영했다.
판단 근거는 `.team/reviews/phase86-spec-resolution.md`. **v1 을 그대로 구현했으면 사고가 났을 지점 3개:**

1. `sales.source = 'legacy'` 는 CHECK 위반 → 첫 INSERT 에서 23514. **M5 마이그레이션 신설.**
2. `status = 'anulada'` 는 존재하지 않는 값. CHECK 가 없어 **조용히 저장되고 취소 판매가 매출로 집계된다.**
   → `SaleStatus.NULLIFIED`(`'Anulado'`) enum 상수만 사용.
3. pgbouncer 가 transaction pooling → 잡 단위 advisory lock 불성립. **리스 테이블로 대체.**

범위도 사용자 지시로 확대됐다: `fventas`·`fdetalles`·`ingresos`·`creditoventas` **포함**, `codigos_tmp` **제외 확정**.

---

## 1. 목표

구 시스템(ACE III, PostgreSQL 9.4) 사용자가 **백업 파일 하나로 새 시스템에 바로 진입**할 수 있게 한다.
매장 admin 의 **Configuración › Importar Legacy** 에서 원하는 항목만 체크해 가져온다.

---

## 2. 사전 조사 결과 (kandente4 백업 실측)

`aceiii_2.0_backups/kandente4_20260812_160643.backup`
— PGDMP custom v1.16, 56MB, 원본 DB = PostgreSQL **9.4.0**, pg_dump 17.10, TOC 420항목 / 65테이블.

> 같은 폴더의 나머지 11개 매장(shaple, antito43, krencia, charo, denimweb, themarket, nam2,
> antito4, serpenti, aleida, evase)은 Dropbox 온라인 전용(0바이트) 상태다.
> **스키마 편차 검증에는 최소 2~3개 매장 파일을 추가로 내려받아야 한다** (ACE 는 PC 마다 컬럼이 다르다).

### 2.1 실측 행 수

| ACE 테이블 | 행 수 | 처리 |
|---|---:|---|
| `codigos_tmp` | 3,105,051 | **제외 확정** — 재고가 아니라 일별 가격 스냅샷 로그 (§2.3 F1) |
| `fdetalles` | 189,208 | **포함** — 팩투라 상세 |
| `logs` | 185,139 (alerta=`t` **937**) | alerta=true 만 |
| `vdetalle` | 41,407 | ventas |
| `clientes` | 16,144 | clientes |
| `vcodes` | 9,731 | ventas |
| `cobranzacab` | 5,277 | venta x crédito (수금) |
| `codigos` | 3,214 | productos |
| `todocodigos` | 2,986 | productos |
| `ingresos` | 2,740 | **포함** — `legacy_ingresos` 이력 |
| `afip_factura` | 2,368 | **포함** — `afip_vouchers` |
| `fventas` | 1,011 | **포함** — 팩투라 헤더 |
| `gastos` | 712 | gastos |
| `parametros` | 507 | 제외 |
| `vtags` | 431 | ventas 결제수단 |
| `provincias` | 28 | 기준정보 |
| `color` | 20 | 기준정보 |
| `vendedor_estado` | 17 | 제외 |
| `permisos` | 15 | usuarios |
| `usuarios` | 12 | usuarios |
| `transportes` | 11 | 기준정보 |
| `vendedores` | 9 | vendedores |
| `tipos`/`temporadas`/`origenes` | 6 each | 기준정보 |
| `gasto_info` | 5 | gastos |
| `cuentas` | 4 | 결제수단 매핑 |
| `empresas` | 4 | 기준정보 |
| `creditoventas` | 3 | **포함** — venta x crédito |
| `corregidos` | **0** | 재고 보정 (이 매장은 비어 있음) |
| `crddetalle`·`cheques`·`cobtags`·`cobdetalles`(12) | 0~12 | venta x crédito |

### 2.2 ★ ACE 의 재고 정의 (뷰 `stockrep` 원문에서 확정)

ACE 에는 재고 컬럼이 **없다.** 뷰로 계산된다:

```
stock(codigoproducto, sucursal)
  =  SUM(ingresos.cant3)         -- ingresorep    : borrado IS NOT TRUE AND (now - fecha)  < 365
   -  SUM(vdetalle.cant1)        -- itemrep       : borrado IS NOT TRUE AND (now - fecha1) < 365
                                 --   AND length(codigoproducto) > 3
                                 --   AND vcode1 IN (SELECT vcode FROM vcodes
                                 --        WHERE casoesp NOT LIKE '%V%' AND casoesp NOT LIKE '%F%'
                                 --          AND borrado IS NOT TRUE)
   +  SUM(corregidos.cantoffset) -- corregidorep  : borrado IS NOT TRUE AND (now - fecha)  < 365
```

**함의 2가지**

1. ACE 재고는 영구 잔액이 아니라 **365일 롤링 창**이다. 이 필터를 그대로 재현하지 않으면
   매장주가 구 시스템 화면에서 보던 숫자와 달라진다.
2. `corregidos.cantoffset`(수동 실사 보정)을 빠뜨리면 조정분이 통째로 사라진다.

> **롤링 창의 수명.** 이 값은 **임포트 기준일의 스냅샷으로만** 의미가 있다. 새 시스템은 영구 잔액이므로
> 이후 두 시스템은 자연히 갈라진다 — 버그가 아니라 이관의 정의다. UI 에 "기준일 현재 재고" 로 명시하고
> 기준일을 `stocks.operation_date` 에 남긴다.

### 2.3 ★ 조사에서 드러난 함정

| # | 발견 | 대응 |
|---|---|---|
| F1 | `codigos_tmp` 는 **일별 가격 스냅샷 로그**. 2,552개 코드가 각각 1,691회 반복(2023-12-05~2026-08-12), 압축 해제 시 244MB — 백업 용량의 대부분 | 스트리밍 리더가 **이 TOC 블록을 아예 디코드하지 않는다** |
| F2 | kandente4 의 `ingresos.cant3` 은 2,740행 중 **2,739행이 0**. 이 매장은 재고 관리를 쓰지 않는다. §2.2 를 그대로 적용하면 **전 품목이 큰 음수** | preview 에서 `SUM(cant3)=0` 감지 → 경고 + **Stock 항목 기본 비선택**. 강행 시 음수는 0 클램프 후 건수 보고 |
| F3 | `usuarios.amho` 는 **MD5** (`698d51a1…` = `md5('111')`, `c6f057b8…` 는 5명 공유). bcrypt 아님. 12명 중 5명은 `usuario_nombre` 가 빈 문자열 | 임시 비밀번호 발급. 이름 없는 계정은 `legacy_user_{id}` 로 username 생성 후 결과표에 명시 |

> ### ★★ F1 정정 (2026-08-24 실측) — **일반화하면 안 된다**
>
> F1 은 `codigos_tmp` 가 "백업 용량의 대부분" 이라고 적었고, TASK-2b 의 정당화
> ("그 블록을 안 읽으면 200MB 까지 열린다")가 여기에 기대고 있다.
> **다른 매장 백업으로 재 보니 성립하지 않는다:**
>
> | | serpenti (46.4MB) |
> |---|---|
> | 전체 SQL | 260.2MB |
> | `codigos_tmp` **제외 후** | **246.1MB — 94.6% 잔존** |
>
> 즉 이 매장에서 `codigos_tmp` 는 **5.4%** 다. F1 의 수치는 **kandente4 한 매장**의
> 것이고, SPEC 자신이 §9-1 에서 경고한 매장별 편차가 바로 이 형태로 나타났다.
>
> **함의:** TASK-2b 를 "`codigos_tmp` TOC 블록을 건너뛴다" 로 구현하면
> **목표(대용량 수용)를 달성하지 못한다.** 큰 파일을 받으려면 세 구간 모두에서
> 전체를 메모리에 올리지 않아야 한다 — 업로드(diskStorage) · 변환(스트림 읽기) ·
> 파싱(구문 단위 배치).
>
> ### 팽창률과 상한 (실측 23개 파일)
>
> * 팽창률 **x5.35 ~ x5.93**
> * 경계가 둘이고 성질이 다르다: `MAX_DECOMPRESSED_BYTES`(400MB)=**깨끗한 거부**,
>   Node 문자열 **512MB**=**크래시**
> * 현재 상한 **65MB** (65 × 5.93 ≈ 386MB). §D7 의 "25MB 동결" 은 해제됐다 —
>   동결 근거였던 "swap 0, free 1.6GB" 가 현재 값이 아니었다(실측 available 15GB).
> * ★ **164MB 백업이 877.8MB 로 풀린다** — 이 구조로는 **어떤 설정으로도** 못 연다.

### 2.4 ACE → VentaGO 대응 (테이블명 검증 완료)

| 개념 | ACE | VentaGO |
|---|---|---|
| 판매 헤더 | `vcodes` (PK `vcode_id`, 비즈니스키 `vcode`) | `sales` |
| 판매 상세 | `vdetalle` (`ref_id_vcode`) | `sale_items` |
| 결제 태그 | `vtags` (`ref_id_cuenta` → `cuentas`) | **`sale_payment_methods`** + `payment_methods` |
| 팩투라 헤더 | `fventas` (`ref_id_vcode`) | `sales.cae` / `cae_vto` |
| 팩투라 상세 | `fdetalles` (`ref_id_vcode`) | `legacy_facturas_detalle` (§3-D6) |
| AFIP CAE | `afip_factura` (`vcode`) | **`afip_vouchers`** |
| 외상 판매 | `creditoventas` + `crddetalle` | `credit_ledger` + `store_clients.balance` |
| 외상 수금 | `cobranzacab` + `cobdetalles` + `cheques` | **`credit_payments`** + `credit_ledger` |
| 비용 | `gastos` (`codigo` → `gasto_info.codigo`) | `expenses` |
| 비용 분류 | `gasto_info` | **`expenses_categories`** |
| 입고 이력 | `ingresos` | **`legacy_ingresos`** (신규, 이력 전용) |
| 재고 | 뷰 `stockrep` (§2.2) | `stocks` 기준선 1행 → `stock_balances` |
| 사용자 | `usuarios` + `permisos` + `permiso_usuarios` | `users` + role/permission |
| 판매원 | `vendedores` | `sellers` |
| 고객 | `clientes` | `clients` + **`store_clients`** |
| 알림 | `logs WHERE alerta = true` | `legacy_alerts` (신규) |
| 지점 | `sucursal` (정수, kandente4 = 전부 `4`) | `branches` |

---

## 3. 설계 결정

### D1. 재고 — 스냅샷 기준선

- `stocks` 는 **append-only 테이블**(뷰 아님)이고 `trg_stocks_immutable` 이 UPDATE/DELETE 를 DB 에서 막는다.
  `stock_balances` 도 **테이블**이며 `trg_stock_balances_apply` 가 같은 트랜잭션에서 증분 갱신한다.
  뷰인 것은 그 위의 감시 계층(`v_stock_balance_drift`, `v_stock_tenant_leak`)이다.
- **§2.2 공식으로 산출한 기준일 재고를 품목×지점당 `stocks` 1행으로만 넣는다.
  임포트된 ventas·ingresos 는 `stocks` 에 쓰지 않는다.**

**★ 트리거 함정 (근거 정정).**
`v_stock_balance_drift` 는 `available` vs `SUM(stock)`, `movimientos` vs `COUNT(id)` 만 본다
(`2026-08-02-stock-interface-views.sql:20-33`). 트리거 L85 가 **미지의 `type` 도 `available` 에 넣으므로
drift 는 깨지지 않는다** — `total_ingreso`/`total_venta` 등 `total_*` 만 조용히 틀어진다.
즉 위험은 "즉시 터진다"가 아니라 **"안 터지고 재고 리포트만 틀린다"** 이고, §6 의 drift 검증으로는 못 잡는다.
그러므로 새 `type` 값을 만들지 않고 기존 ingreso 의미를 그대로 쓴다:

```
stocks.type              = NULL      -- ingreso (total_ingreso 집계 + fecha_primer_ingreso 설정)
stocks.stock             = 기준일 재고 (> 0 인 것만; 음수는 0 클램프 후 보고)
stocks.source            = 'legacy_opening'
stocks.note              = 'Importar Legacy — saldo inicial (ACE stockrep)'
stocks.operation_date    = 임포트 기준일
stocks.product_branch_id = 매핑된 product_branch   ★ product_id 컬럼은 존재하지 않는다
```

**★ `trg_stocks_leaf_only`.** 기준선 행이 madre(부모) product_branch 로 가면
**트랜잭션 전체가 abort** 된다(`2026-08-07-stock-leaf-only.sql:64-95`). 기준선은 **리프 PB 에만** 넣는다.

**★ 리포트 왜곡 고지.** 판매가 재고를 건드리지 않으므로 `stock_balances.total_venta` 는 legacy 분이 0 이다.
이는 잔액뿐 아니라 **입고/판매 재고 리포트에도 그대로 나타난다.** 의도된 동작이며 UI 에 고지한다.

### D2. ventas — 이력 전용

```
sales.source        = 'legacy'                 ★ M5 로 sales_source_check 확장 필요 (없으면 23514)
sales.activity_type = 'sale'
sales.status        = SaleStatus.NULLIFIED     ★ 'Anulado' — 문자열 리터럴 금지, enum 상수만
sales.branch_id     = sucursal 매핑 결과       ★ user_id → users.branch_id 유추 금지
```

- `vcodes.borrado = true` → `SaleStatus.NULLIFIED`. `status` 에는 CHECK 가 없어 **오타가 조용히 저장되고**
  취소 제외 필터가 전부 문자열 정확 일치라(`sales.service.ts:1325`, `daily-summary.util.ts:97,102`,
  `SalesListView.tsx:562`, `DataConfig.tsx:308`) **취소 판매가 매출로 집계된다.**
- `daily_number`: `uq_sales_branch_daylocal_dn` 은 `NULLS NOT DISTINCT` 라 NULL 지점도 한 버킷이다.
  **지점×일자 버킷별로 `MAX(daily_number)` 를 한 번 읽어 메모리에서 연번 부여** 후 배치 INSERT
  (행마다 채번하면 9,731회 락).
- **★ 취소 가드.** 취소 경로는 무조건 `+qty` 복원 행을 넣는다(`sales-create.service.ts:1414-1436`).
  legacy 판매는 재고 차감이 없었으므로 복원도 없어야 한다 →
  **`source='legacy'` 인 판매의 취소는 재고 복원을 건너뛴다.** (안 하면 없던 재고가 는다.)

### D3. 계정 — 임시 비밀번호

- `users.password` = bcrypt(랜덤 12자), `must_change_password = true` (신규 컬럼)
- **★ 컬럼만 추가하면 아무 일도 일어나지 않는다.** 강제 로직을 넣을 5개 지점:
  `auth.service.ts:600-613`, `:812`, `:1246-1270`, 인증 가드, `Users` 모델
- `usuarios.borrado = true` → `status = 'inactive'`
- **임시 비밀번호 보관**: `legacy_import_secrets` 에 **애플리케이션 키로 암호화** 저장,
  `expires_at = now() + 24h`, **1회 조회 시 즉시 삭제**. DB 평문·로그·소켓 페이로드 금지.
  CSV 는 서버가 파일로 만들지 않고 조회 응답에서 클라이언트가 생성한다.

### D4. 비동기 잡 + 진행률

- `POST /legacy-import/jobs` → `{ jobId }` 즉시 반환. `GET /legacy-import/jobs/:id` 폴링
- **★ IDOR 방지**: `GET /jobs/:id` 는 반드시 `job.storeId === user.storeId` 를 검증한다.
  사용자 입력 ID 를 받는 첫 엔드포인트이고, 뚫리면 남의 매장 **임시 비밀번호가 샌다.**
- **★ 동시 실행 제어는 advisory lock 이 아니다.** pgbouncer 가 `pool_mode = transaction` 이라
  `pg_advisory_xact_lock` 은 매 배치 커밋에 풀리고 세션 락은 커넥션을 따라 떠돈다(최악: 그 매장 영구 차단).
  → **`legacy_import_leases(store_id PK, job_id, lease_expires_at)` 리스 테이블.**
  저장소에 같은 패턴 선례가 있다(`sync_outbox.lease_expires_at`).
- **★ DB 전역 타임아웃**: `statement_timeout=30s`, `idle_in_transaction_session_timeout=60s`,
  `lock_timeout=10s` (`db-safety-timeouts.sql:24-30`).
  → **파싱·변환은 트랜잭션 밖에서 끝내고, 트랜잭션은 INSERT 배치만 감싼다.**
  배치 크기는 60초 안에 끝나는 값(초기 **500행**, 실측으로 조정).
- pool: 임포트 워커는 **동시 1 커넥션**. 트랜잭션 안 외부 I/O 금지(Phase 64). 진행률 발신은 커밋 후.
- **★ `bulkCreate` 는 Sequelize 훅을 건너뛴다** → `Clients` 의 `AfterCreate` 가 만들던
  `StoreClient` 가 안 생긴다. 훅 우회 시 수동 생성.
- 업로드 상한 25MB → **200MB. 단 TASK-2b 와 한 몸이다** (§D7).

### D5. 재실행 멱등성 + 재개

`legacy_entity_maps(store_id, entity, legacy_id, ventago_id, status)` + `UNIQUE(store_id, entity, legacy_id)`

- FK 변환(ACE id → VentaGO id)의 단일 출처, 재실행 시 중복 생성 차단
- `status`: `PENDING`(INSERT 직전 기록) → `DONE`(같은 트랜잭션에서 커밋)
- **재개 시 `PENDING` 행은 미완성으로 간주해 되돌리고 다시 만든다**
- `sales` 헤더와 품목은 **한 트랜잭션** (품목 없는 판매 방지)
- `stocks` 는 append-only 라 되돌릴 수 없다 → **기준선은 잡의 맨 마지막 단계에 매장×임포트당 1회만**

### D6. 신규 범위 (사용자 지시)

| 대상 | 착지점 | 비고 |
|---|---|---|
| `ingresos` | **`legacy_ingresos`** (신규) — 날짜·수량·단가·담당·`num_corte` 원본 보관 | **`stocks` 에 쓰지 않는다.** 재고 진실은 D1 기준선. 조회·보고서용 |
| `fventas` + `fdetalles` | 매칭된 sale 에 `sales.cae`/`cae_vto` 채움 + `legacy_facturas_detalle` 에 상세 보관 | `ref_id_vcode` 로 vcodes 연결 → **ventas 임포트 선행 필수** |
| `afip_factura` | **`afip_vouchers`** (`sale_id`, `cae`, `cae_vto`, `punto_venta`, `afip_number`, `nota_credito`, `nota_debito`, `cae_anterior`) | `imp_total`·`tipo_comprobante`·`doc_tipo` 는 NOT NULL → `fventas` 에서 보강, 불가 시 스킵+보고 |
| `creditoventas` + `crddetalle` | `credit_ledger`(movement_type=sale_credit) + `store_clients.balance` | kandente4 는 3행뿐이고 `clientes.deuda` 가 전부 0 — **다른 매장 백업으로 별도 검증 필요** |
| `cobranzacab` + `cobdetalles` + `cheques` | **`credit_payments`** + `credit_ledger` 입금 | `bucket_after` 는 running balance 라 **시간순 처리 필수** |

### D7. TASK-2b — PGDMP 스트리밍 리더 (필수)

**200MB 상한의 전제조건이다.** 현행 `dump-converter.service.ts` 는 `sqlText: string` 을 반환하고
컨트롤러가 `file.buffer` 를 넘긴다(`legacy-import.controller.ts:188,205`). diskStorage 로 바꿔도
힙 문제는 그대로이며, **`file.buffer` 전제 때문에 전환 자체가 현행 코드와 비호환**이다.
`Dockerfile:43-49` 에 기록된 대로 운영 서버는 **swap 0, free 1.6GB** 이고 같은 박스에 운영 Postgres 가 있다
— 메모리 스파이크 시 OOM killer 가 **운영 Postgres 를 고를 수 있다.**

이번 조사에서 PGDMP custom 포맷(헤더 → TOC → 블록별 zlib)을 직접 디코드해 65개 테이블 전수 읽기를
검증했다. TS 로 이식하면:
- **`Dockerfile` 의 `postgresql-client` 의존 제거** (pg_restore 버전 불일치 장애 요인 제거)
- 필요한 테이블 블록만 디코드 → `codigos_tmp` 244MB 를 아예 안 읽음 (F1)
- 스트리밍 파싱으로 메모리 상한 확보

**★ 전부 아니면 전무.** plain / gzip / custom / tar 4경로를 한 번에 이식한다. 부분 이식하면 tar 경로가 죽는다.
스트리밍 리더가 완성되기 전에는 **상한을 25MB 로 동결**한다.

---

## 4. 엔티티 선택 UI 와 의존성

```
[✓] 기준정보 (tipos·color·temporadas·origenes·empresas·provincias·transportes·cuentas)  — 항상
[✓] Productos       (todocodigos + codigos + precios)              → 기준정보
[ ] Vendedores      (vendedores)
[✓] Clientes        (clientes → clients + store_clients)           → Vendedores
[ ] Usuarios        (usuarios + permisos + permiso_usuarios)
[ ] Ventas          (vcodes + vdetalle + vtags)                    → Productos, Clientes, Vendedores, Usuarios
[ ] Facturas        (fventas + fdetalles + afip_factura)           → Ventas
[ ] Venta x crédito (creditoventas + crddetalle + cobranzacab + cobdetalles + cheques) → Ventas, Clientes
[ ] Gastos          (gastos + gasto_info)                          → Usuarios, 지점   ★ H6
[ ] Ingresos        (ingresos → legacy_ingresos)                   → Productos
[ ] Stock           (ingresos − vdetalle + corregidos, 기준선)      → Productos        ⚠ F2 경고
[ ] Alertas         (logs WHERE alerta = true)
```

**★ Gastos 의존성 (H6).** `expenses` 는 NOT NULL 이 4개다 — `user_id`, `branch_id`, `description`, `date`.
→ Usuarios 매핑과 지점 매핑이 선행돼야 하고, `gastos.tema` 가 NULL 이면
`gasto_info.desc_gasto` → 없으면 `'(sin descripción)'` 로 채운다.

프리셋 버튼:
- **"Básico"** = 기준정보 + Productos + Clientes + Stock
- **"Completo"** = 전부

---

## 5. 마이그레이션 (로컬 5432 + 운영 5434 동시 적용 — 단 로컬 검증 완료 후)

| # | 파일 | 내용 |
|---|---|---|
| M1 | `phase86-legacy-entity-maps.sql` | `legacy_entity_maps` 신규 (+`status`, FK, CASCADE, UNIQUE, 모델 등록) |
| M2 | `phase86-legacy-imports-job.sql` | `legacy_imports` 에 `selected_entities jsonb`, `progress jsonb` 추가. **status CHECK 확장 DDL 없음 — 제약 자체가 없다**(`2026-06-25-legacy-imports.sql:44`) |
| M3 | `phase86-users-must-change-password.sql` | `users.must_change_password boolean NOT NULL DEFAULT false` |
| M4 | `phase86-legacy-alerts.sql` | `legacy_alerts` 신규 |
| **M5** | `phase86-sales-source-legacy.sql` | **`sales_source_check` 에 `'legacy'` 추가 (C1 — 없으면 ventas 임포트 전멸)**. 선례: `40-04-sales-source-delivery.sql` |
| **M6** | `phase86-legacy-ingresos.sql` | `legacy_ingresos` + `legacy_facturas_detalle` 신규 (D6) |
| **M7** | `phase86-legacy-import-leases.sql` | `legacy_import_leases` + `legacy_import_secrets` (C3, H5) |

> 신규 테이블·시퀀스는 **owner 를 `coolsistema` 로 이전**하는 DO 블록 필수.
> 누락 시 운영에서 permission denied 500. `ALTER TABLE OWNER` 는 시퀀스를 안 옮긴다 — `ALTER SEQUENCE` 별도.
> 인덱스는 규모를 보고 판단 — 작은 테이블에 `CONCURRENTLY` 를 쓰면 원자성이 깨지고 INVALID 인덱스가 남는다.

---

## 6. 검증 계획 (샌드박스 PG18)

1. npm `@embedded-postgres/linux-arm64@18.4` 로 샌드박스에 PG18 기동
2. `.planning/intel/db-schema-*.md` + `api-ventago/migrations/` 로 ventago 스키마 복제
3. 더미 매장 `kandente4-test` + Branch/Box/Terminal 생성
4. 프리셋 2종을 각각 임포트

**대조 항목**

| # | 기준 |
|---|---|
| V1 | `sales` 행수 = 유효 `vcodes` 행수, `sale_items` = 유효 `vdetalle` 행수 |
| V2 | `SUM(sales.total_amount)` vs `SUM(vcodes.tpago)` — `total_amount` 는 integer, `tpago` 는 double → **반올림 후 정수 비교**, 반올림 손실 건수 별도 보고 |
| V3 | **취소 판매 검증**: `vcodes.borrado=true` 건이 전부 `status='Anulado'` 이고 매출 집계에서 빠지는가 (C2 회귀 가드) |
| V4 | `stock_balances.available` = ACE `stockrep.stock` (품목별 전수 비교) |
| V5 | `v_stock_balance_drift` 0행, `v_stock_tenant_leak` 0행 |
| V6 | **`stock_balances.total_ingreso` 가 기준선 합계와 일치** (H1 — drift 로는 못 잡는 항목) |
| V7 | `expenses` 합계 = `SUM(gastos.costo WHERE borrado=false)`, NOT NULL 4개 전부 충족 |
| V8 | `afip_vouchers` 행수 = 매칭 성공한 `afip_factura` 행수, 스킵 건수 보고 |
| V9 | `legacy_alerts` = 937행 |
| V10 | 같은 파일 재임포트 시 신규 생성 0건 (멱등성) |
| V11 | **중단-재개**: 잡을 중간에 죽인 뒤 재개 → `PENDING` 행이 정리되고 최종 결과가 무중단과 동일 |
| V12 | legacy 판매 1건을 취소 → **재고가 늘지 않는다** (H3 회귀 가드) |
| V13 | 임포트 중 `pg_stat_activity` 워커 커넥션 1개 초과 없음, 트랜잭션 지속 60초 미만 |
| V14 | `GET /legacy-import/jobs/:id` 를 **다른 매장 사용자로 호출 시 403** (H5 IDOR 가드) |
| V15 | ESLint 오류 0 (변경 파일), api/app 빌드 통과 |
| V16 | **§6.2 Stock & Reports 회귀 루틴 전 항목 통과** |

### 6.2 ★ 임포트 후 Stock & Reports 회귀 루틴 (Phase 86 종료 조건)

임포트가 "행을 넣는 데 성공"하는 것과 **매장주가 보는 화면이 맞는 것**은 다르다.
기준선 방식(§D1)은 재고 원장의 모양을 바꾸므로 **재고·보고서 계층이 조용히 틀어질 수 있고,
드리프트 뷰로는 안 잡힌다**(H1). 그래서 임포트 직후 아래를 **자동 스모크로 전수 실행**한다.

**실행 방식:** 더미 매장 admin 토큰으로 각 엔드포인트를 호출하는 스크립트(`tools/phase86-report-smoke.ts`).
각 항목마다 **① HTTP 200 ② 응답이 비어 있지 않음 ③ 합계가 원장·ACE 원본과 일치 ④ export 가
유효한 xlsx** 4가지를 본다. 하나라도 실패하면 Phase 86 은 미완이다.

| # | 화면 / 엔드포인트 | 임포트 의존 | 통과 기준 |
|---|---|---|---|
| R1 | `GET /reports/stocks-report` + `-export` | Stock, Productos | 품목별 재고가 **ACE `stockrep.stock` 과 전수 일치**. 0행 아님. xlsx 열림 |
| R2 | `GET /reports/products-report` + `-export` | Productos | 상품 수 = 매핑된 `codigos` 수 |
| R3 | `GET /reports/sales-report` + `-export` | Ventas | 행수·합계가 V1·V2 와 일치. **취소분 제외 확인**(C2 회귀) |
| R4 | `GET /reports/sale-items-summary`, `product-sales-summary` | Ventas, Productos | 품목 합계 = `SUM(vdetalle.cant1)` (유효행) |
| R5 | `GET /reports/vendedor-report` + `-export`, `vendedor-cockpit`(+`/trend`,`/mix`,`/ventas`) | Ventas, Vendedores | 판매원별 합계 = 전체 매출. 미매핑 판매원이 있으면 건수 보고 |
| R6 | `GET /reports/gasto-report` + `-export`, `gastos/by-category` | Gastos | 합계 = `SUM(gastos.costo WHERE borrado=false)`. 분류 미지정 건수 보고 |
| R7 | `GET /reports/ingreso-report` + `-export` | Ingresos | **★ 기준선 방식에서 이 화면이 무엇을 보여야 하는지 확정 필요.** `legacy_ingresos` 를 읽을지, `stocks` 기준선만 볼지. 현재 구현은 `stocks` 기준 → **legacy 입고가 안 보인다**. 결정 후 통과 기준 확정 |
| R8 | `GET /reports/facturacion-report` + `-export`, `facturacion-cockpit` | Facturas | CAE 건수 = `afip_vouchers` 행수 |
| R9 | `GET /reports/clientes-credito-report` + `-export`, `GET /credit/...` | Venta x crédito, Clientes | 잔액 = `store_clients.balance`, `credit_ledger.bucket_after` running balance 정합 |
| R10 | `GET /reports/alertas-report` + `-export` | Alertas | 937행 |
| R11 | `GET /reports/cheque-estado-report` + `-export` | Venta x crédito | kandente4 는 0행 — **빈 상태에서 500 이 아니라 정상 빈 응답**인지 |
| R12 | `GET /reports/fallados-report`, `movidos-report`, `reservado-report`, `corregido-report` (+ 각 `-export`) | — | legacy 데이터가 없는 영역 — **빈 상태에서 깨지지 않는지**(가장 흔한 회귀) |
| R13 | `GET /reports/breve-venta-report` + `-export` | Ventas | 일자별 합계 = R3 총합 |
| R14 | `GET /reports/category-color-pivot`, `season-turnover`, `provincia-dashboard` | Productos, Ventas | 200 + 비어 있지 않음 |
| R15 | `GET /dashboards/products/*`, `/dashboards/sales/*`, `/dashboard/admin/*` | 전체 | 200 + 카드 수치가 R1·R3 과 모순 없음 |
| R16 | 프론트 `reportes/*` 17개 화면 + `dashboards/*` 5개 | 전체 | 콘솔 에러 0, 빈 상태 스켈레톤 정상, 표 렌더 |
| R17 | `reportsPdf.service` 경유 PDF 출력 | Ventas | PDF 생성 성공 (열림) |

**★ R7 은 설계 공백이다.** 기준선 방식을 택한 순간 `ingreso-report` 가 legacy 입고를 못 본다.
구현 착수 전 착지점을 정한다(§9-6).

**★ 재고 리포트 고지.** `stock_balances.total_venta` 가 legacy 분 0 이므로 R1 의 "판매" 열은
legacy 기간에 대해 0 이다. 이건 §D1 의 의도된 결과이며 **화면에 고지**해야 오해가 없다.

---

## 7. 태스크

| ID | 내용 | 대상 |
|---|---|---|
| ~~TASK-1~~ | ~~마이그레이션 M1~M7 작성 + 적용~~ **DONE (2026-08-20)** — 샌드박스 PG18 에서 7개 적용 + 동작 12건 + 멱등 확인. **Mac(5432)·운영(5434) 적용은 미실시** | `migrations/2026-08-20-phase86-*.sql` |
| **TASK-2b** | **PGDMP 스트리밍 리더 TS 이식 (plain/gzip/custom/tar 4경로 일괄)** — 다른 모든 작업의 전제 | `dump-converter.service.ts`, `tools/ace-dump/` |
| TASK-2 | 파서: 대상 테이블 화이트리스트 + `codigos_tmp` 스킵 | `sql-parser.service.ts` |
| TASK-3 | 매퍼: ventas / facturas / crédito / gastos / ingresos / stocks / usuarios / vendedores / alertas | `ace-mapping.ts` |
| TASK-4 | 잡 러너 + 진행률 + **리스 테이블** + 배치 커밋(500행) + PENDING/DONE 재개 | `legacy-import.service.ts` |
| TASK-5 | 컨트롤러: 엔티티 선택 DTO, jobs 엔드포인트(**storeId 검증**), diskStorage | `legacy-import.controller.ts` |
| TASK-6 | `must_change_password` 강제 로직 5개 지점 | `auth/`, `users` 모델 |
| TASK-7 | legacy 판매 취소 시 재고 복원 스킵 가드 | `sales-create.service.ts` |
| TASK-8 | 프론트: 체크박스/프리셋/진행률/결과표/임시비번 CSV/재고 리포트 고지 | `ImportLegacyView.tsx` |
| TASK-9 | 샌드박스 PG18 검증 하니스 + V1~V15 대조 스크립트 | `.planning/`, `tools/` |
| **TASK-9b** | **Stock & Reports 회귀 스모크 (§6.2 R1~R17)** — Phase 86 종료 조건 | `tools/phase86-report-smoke.ts` |
| TASK-10 | ESLint + 빌드 + codex 검토(`scripts/codex-review.sh --task 86`) + 최종 리뷰 | 전체 |

---

## 8. 금지사항 / 주의

- `stocks` 행 **UPDATE/DELETE 금지** (`trg_stocks_immutable`). 보정은 반대 부호 행으로
- `stocks` 는 **리프 product_branch 에만** (`trg_stocks_leaf_only` — madre 로 가면 트랜잭션 전체 abort)
- `stocks` 조회·기록은 항상 `product_branch_id` 기준 — **`product_id` 컬럼은 없다**
- `products.stock` 참조 금지 (Phase 70-06 강등)
- **새 `stocks.type` 값 도입 금지** (§D1 — drift 는 안 깨지고 `total_*` 만 조용히 틀어진다)
- **`sales.status`/`source` 는 enum 상수만** — 문자열 리터럴 금지 (CHECK 가 없어 오타가 조용히 저장된다)
- **advisory lock 금지** (pgbouncer transaction pooling)
- 트랜잭션 안 외부 I/O 금지. 파싱·변환은 트랜잭션 밖
- 트랜잭션 지속 60초 미만 (`idle_in_transaction_session_timeout`)
- storeId 격리·admin 가드 불변. `GET /jobs/:id` 소유권 검증 필수
- 임시 비밀번호: DB 평문 저장 금지, 로그·소켓 페이로드 출력 금지
- 스트리밍 리더 완성 전 업로드 상한 25MB 유지

---

## 9. 남은 확인 (구현과 병행)

1. **다른 매장 백업 2~3개** 를 로컬로 내려받아 스키마 편차 검증 (ACE 는 PC 마다 컬럼이 다르다)
2. `creditoventas` 는 kandente4 에 3행뿐 — **외상을 실제로 쓰는 매장 백업으로 별도 검증**
3. 마이그레이션 운영(5434) 적용은 **로컬 검증 완료 후**
4. Mac 로컬에서 실제 codex 검토: `scripts/codex-review.sh --task 86`
   (이 세션은 샌드박스라 OpenAI API 가 프록시 403 으로 차단됨 — `.team/reviews/phase86-spec-resolution.md` 상단 고지)
5. push 는 Mac 또는 로컬 세션에서 (샌드박스는 GitHub 접근 차단)
6. ~~R7 착지점 결정~~ → **확정(2026-08-20): B안 — 별도 "Importación legacy" 화면으로 분리.**
   기존 `ingreso-report` 는 손대지 않고 `legacy_ingresos` 전용 화면을 만든다.
   이관 데이터와 운영 데이터를 한 화면에 섞으면 이후 모든 리포트에서 "이건 legacy 인가" 를
   따져야 하고 그 비용이 계속 누적된다. 대신 `ingreso-report` 화면 상단에
   **legacy 입고 존재를 알리는 배너 + 링크**를 둔다 (안 두면 "예전 입고 어디 갔냐" 문의가 온다).
   되돌리기 쉬운 결정 — A안(UNION)으로 바꾸려면 프론트와 뷰 하나만 손대면 된다.

---

## 10. Phase 86 완료 정의

다음이 **전부** 참일 때만 완료로 표시한다.

1. V1~V16 전 항목 통과 (§6)
2. **§6.2 R1~R17 전 항목 통과** — 임포트 후 stock·reports 화면과 export 가 모두 정상
3. 마이그레이션 M1~M7 이 **로컬(5432) + 운영(5434) 양쪽에 적용**되고 스키마 대조 완료
4. ESLint 오류 0, api/app 빌드 통과
5. `scripts/codex-review.sh --task 86` 실행 + `.team/reviews/86-resolution.md` 작성
6. push 후 Jenkins 빌드 성공 + 운영 컨테이너 재생성 확인
