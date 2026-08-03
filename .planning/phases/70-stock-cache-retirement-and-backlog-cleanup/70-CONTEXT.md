# Phase 70 — 재고 캐시 폐기 · 잔여 백로그 정리

생성 2026-08-03 · 선행 Phase: Stock Vistas W1~W4 (배포 완료, api #597 / front #527)

---

## 왜 이 Phase 인가

Phase 직전 작업에서 `stocks` 원장 위에 **증분 스냅샷(`stock_balances`)과 인터페이스 뷰 4종**을 세우고 Stock Vistas 리포트까지 배포했다. 읽기 구조는 섰지만 **옛 캐시가 그대로 살아 있다** — 그리고 그 캐시가 지금 시스템의 가장 큰 확장 병목이다.

```sql
-- trg_stocks_sync_product_cache (현행)
UPDATE products
   SET stock = COALESCE(stock, 0) + NEW.stock
 WHERE id = v_product_id
    OR (v_parent_id IS NOT NULL AND id = v_parent_id);   -- ★ 부모 행도 잠근다
```

**어떤 변형이 팔리든 같은 코디고 마드레의 부모 행 하나를 잠근다.** 마드레 하나에 변형 20개가 달려 있고 여러 지점·터미널에서 동시에 팔리면 그 판매들이 전부 한 행에서 직렬화된다. Phase 63 목표(터미널 3,000대)에서 정확히 여기가 먼저 막힌다. 읽기를 아무리 빠르게 해도 쓰기가 여기서 걸리면 소용없다.

`stock_balances` 는 `ProductBranch` 단위라 부모 행을 건드리지 않는다. 이 Phase 는 읽기를 스냅샷으로 옮긴 뒤 옛 트리거를 걷어내 **그 직렬화 지점을 없앤다.**

여기에 더해, 지난 트리아지에서 남은 Trello 3건과 미머지 브랜치 10개를 같이 정리한다.

---

## 현재 상태 (사실)

### 이미 있는 것 — 만들지 말 것

| 대상 | 상태 |
|---|---|
| `stocks.store_id` / `branch_id` | 컬럼 + `trg_stocks_fill_tenant` (BEFORE INSERT 자동 채움). 로컬·운영 적용됨 |
| `stock_balances` | 테이블 + `trg_stock_balances_apply` (AFTER INSERT 증분). 운영 230행 / 로컬 642행 |
| 인터페이스 뷰 4종 | `v_stock_{sucursal,total}_{variante,madre}` |
| 보조 뷰 | `v_stock_dia`, `v_product_branch_daily_ingreso`, `v_stock_balance_drift`, `v_stock_tenant_leak` |
| Stock Vistas 리포트 | `GET /reports/stock-vistas`, `-export`. 권한 `reporte-stock-vistas` (10매장 × 8역할 부여됨) |

### 불변식 — 매 Wave 종료 시 확인

```sql
SELECT count(*) FROM v_stock_balance_drift;  -- 0 이어야 한다
SELECT count(*) FROM v_stock_tenant_leak;    -- 0 이어야 한다
```

`stocks` 는 `trg_stocks_immutable` 로 UPDATE/DELETE 가 막혀 있다 → 변화가 INSERT 뿐 → 덧셈만 있는 집계라 증분 = 재계산. 드리프트가 0이 아니면 그 자체가 버그다.

### 규모와 손익분기 (실측)

운영 동급 서버, 원장 1,000만 행 벤치마크: legacy 4패스 253ms / 매장필터 push-down 65ms / **스냅샷 페이지 0.61ms (415배)**.
단, **손익분기 = 매장당 원장 1,800행**. 현재 최대 매장(store 6) 885행이라 아직 뷰가 더 빠르다. 이 Phase 의 값어치는 응답시간이 아니라 **쓰기 경합 제거**에 있다.

---

## 이 Phase 의 범위

| Plan | 내용 | Wave | 저장소 |
|---|---|---|---|
| 70-01 | 재고 **읽기** 경로를 `stock_balances`/뷰로 전환 | 1 | api |
| 70-02 | 미머지 브랜치 10개 정리 | 1 | git |
| 70-03 | Trello `fXUDii66` Articulos — 상품 코드 수정/삭제 UI | 1 | api+front |
| 70-04 | Trello `30zWO5C8` Pasar a pdf — 리포트 PDF 내보내기 | 1 | api+front |
| 70-05 | Trello `diACgk5B` Cargar varios — 카테고리 변경 시 폼 리셋 | 1 | front |
| 70-06 | **W7** `trg_stocks_sync_product_cache` 폐기 + `products.stock` 강등 | 2 | migration+api |
| 70-07 | UAT + 배포 · 불변식 확인 | 3 | — |

Wave 1 의 5개 Plan 은 **수정 파일이 겹치지 않아 완전 병렬 실행 가능**하다 (cmux team 용).

### 선결정 사항 (2026-08-03 — 실행 중 멈추지 않도록 미리 확정)

- **70-05 폼 리셋 = 안 B**: 저장 성공 후 항상 리셋. 단 지점(branchId)은 보존하고, 저장 **실패** 시에는 리셋하지 않는다. `ProductsView.tsx:951-964` 의 기존 "값 유지" 주석을 갱신할 것
- **70-02 브랜치 = 10개 전부 삭제 승인**. 단 재검증에서 미머지 커밋이 나오면 그 브랜치만 건너뛰고 보고
- 남은 승인 게이트는 **70-06 운영 적용**(POS 판매 경로)과 **70-07 UAT** 뿐이다

### 범위 밖

- W8 `stock_mensual` 월별 롤업 — 기간 리포트 요구가 실제로 생기면 별도 Phase
- 드리프트 야간 Telegram 알림 배선 — 이번에 선택되지 않음
- Trello `sW1EH87H` APK Vendedor / `0p0yNa7x` Registro de tienda — 재현 정보 대기 중
- ~~`ProductList.tsx` 고객명 폴백~~ — **커밋 `60d7c83`(front #528)에서 이미 해결됨.** 1765행에 `fullname` 우선 + `clientFormData` 폴백까지 들어가 있다. 70-07 에서 회귀 확인만 한다.

---

## 공통 규약 (모든 Plan 적용)

### PostgreSQL / pool
- `sequelize.query()` 만 사용 — 수동 `connect()/release()` 없음
- 트랜잭션 안에서 HTTP·프린터·소켓 호출 금지 (커밋 후 수행)
- 쓰기 경로는 단일 트랜잭션, 헬퍼는 `transaction` 을 **필수 인자**로
- `stocks` 는 append-only — UPDATE/DELETE 금지, 반대부호 보정 행으로 상쇄
- 락 순서는 `productId` 오름차순 고정
- pageSize 상한 50

### 멀티테넌트
- 모든 조회에 `store_id` 강제. 클라이언트가 보낸 storeId 신뢰 금지 — 인증 주체에서 파생
- 조인에 매장 가드: `AND b.store_id = p.store_id`, `AND pm.store_id = p.store_id`

### 재고 정책 (건드리면 회귀)
- **재고 음수는 정상 동작일 수 있다** — `store_configs.allowSaleWithoutStock` 이 true 인 매장은 의도된 설계. 차단 코드를 새로 넣지 않는다
- `stocks` 키는 `product_branch_id` — **`product_id` 컬럼은 존재하지 않는다**

### 마이그레이션
- **로컬 5432 + 운영 5434 양쪽 적용.** 한쪽만 적용 금지
- 신규 테이블/뷰는 끝에 `ALTER TABLE/SEQUENCE/VIEW ... OWNER TO coolsistema` DO 블록 (누락 시 운영 permission denied 500)
- 클라우드 세션에서 로컬 5432 는 못 닿음 → Mac agent-runner 잡으로 실행

### ESLint / 빌드
- 프론트는 **warning 도 빌드를 막는다**: `return` 위 빈 줄, `//` 주석 위 빈 줄, 미사용 import 금지
- 백엔드는 `npx tsc --noEmit -p tsconfig.build.json`
- 검증은 Mac agent-runner 로 실행 (샌드박스에서 이 저장소 빌드 불가)

### 배포
- push 는 직접 수행 → Jenkins `api-new-coolsistema` / `front-coolsistema` 빌드 **성공 + 컨테이너 재생성 확인까지가 완료**
- 운영 DB DML/DDL, 서비스 재시작은 사용자 승인 후 실행

---

## 참조

- `.planning/stock-views-proposal-2026-08-02.md` — 설계 근거 + 벤치마크 원본
- `.gsd/spec-stock-vistas.md` — W1~W4 SPEC
- `.planning/intel/db-schema-tables.md` / `db-schema-fks.md` — 컬럼명 확인 (추측 금지)
- `.planning/trello-inbox/report-2026-08-02.md` — Trello 트리아지 근거
