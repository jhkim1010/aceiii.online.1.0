---
phase: 70-stock-cache-retirement-and-backlog-cleanup
plan: 06 (단일 프로세스 계획 S3)
status: complete — 운영 적용됨, 24시간 관찰 대기
date: 2026-08-04
requirements: [R1]
---

# 70-06 — `trg_stocks_sync_product_cache` 폐기 + `products.stock` 강등

Phase 70 의 핵심. **쓰기 경합 제거**가 목적이고, Phase 63(터미널 3,000대)의 선결 조건이다.

배포: api-ventago `c0bfe06` → 루트 `a412a9e`. Jenkins **#601 SUCCESS**, `api_ventago` 15:08:49 재생성(healthy).
DDL: 로컬 5432 + 운영 5434 **양쪽 적용 완료**.

---

## 문제 — 부모 행 한 줄에서 직렬화

```sql
UPDATE products SET stock = COALESCE(stock,0) + NEW.stock
 WHERE id = v_product_id OR (v_parent_id IS NOT NULL AND id = v_parent_id);
```

뒤쪽 `OR` 절이 마드레 부모 행을 잠근다. 변형이 20개면 그 20개의 모든 판매가 한 행에서 줄을 선다.

## T1 — 경합 실측 (전/후)

로컬 5432, 같은 마드레(92)의 **서로 다른 변형·서로 다른 지점**에 동시 원장 INSERT:
변형 93 / `ProductBranch` 76 / 지점 10 **vs** 변형 112 / `ProductBranch` 123 / 지점 11.

| | 두 번째 세션 결과 |
|---|---|
| **before** (트리거 있음) | **7초 대기 후 lock_timeout** — 에러가 `stocks_sync_product_cache() line 17` 의 UPDATE 를 지목 |
| **after** (트리거 없음) | **0초, 즉시 INSERT** |

지점이 달라도 막혔다는 점이 핵심이다 — 지점 격리로는 피할 수 없는 경합이었다.

> 원안 T1 은 `ventago_staging` + k6/pgbench 부하를 요구했다. 실행하지 않았고 대신 위 결정적
> 락 프로브로 대체했다. **p95 응답시간 전/후 수치는 측정하지 못했다** — 부하 하네스 기반 수치가
> 필요하면 별도 과제로 남긴다. 여기서 증명한 것은 "부모 행 잠금이 실제로 존재했고 사라졌다" 까지다.

## T2 — 마이그레이션 `2026-08-04-retire-product-stock-cache.sql`

```sql
BEGIN;
DROP TRIGGER IF EXISTS trg_stocks_sync_product_cache ON stocks;
COMMENT ON COLUMN products.stock IS '[DEPRECADO 2026-08-04 / Phase 70-06] ...';
COMMIT;
```

- **컬럼 DROP 안 함** / **함수 `stocks_sync_product_cache()` DROP 안 함** — 둘 다 롤백 수단
- 파일 하단에 **롤백 스크립트 + 원장 기준 백필 쿼리** 동봉
- 영향 행수 **0** (DDL 2문장, 데이터 미변경)

| 환경 | 결과 |
|---|---|
| 로컬 5432 | 적용됨. 남은 트리거 3개 |
| 운영 5434 | 적용됨. 남은 트리거 3개 (`trg_stock_balances_apply` / `trg_stocks_fill_tenant` / `trg_stocks_immutable`) |

> 운영 적용 시 `--single-transaction` 과 파일 내 `BEGIN` 이 겹쳐
> `WARNING: there is already a transaction in progress` 가 떴다. 무해하며 DDL 은 정상 커밋됐다
> (트리거 부재·COMMENT 적용 확인). 다음 마이그레이션부터는 둘 중 하나만 쓰는 편이 낫다.

## T3 — 진단 지표 전환 (이걸 안 하면 매일 밤 오탐 알람)

`products.stock` 이 동결되므로, 그 컬럼을 계속 원장과 대조하면 **정상 판매마다 "드리프트"가 쌓인다.**

`diagnostics/stock-drift.service.ts` 주 지표를 교체:

| | 종전 | 이후 |
|---|---|---|
| 대조 대상 | `products.stock` ↔ 원장 (`v_product_stock_drift`) | `stock_balances` ↔ 원장 (`v_stock_balance_drift`) |
| 단위 | 상품 | **ProductBranch(지점별)** — 스냅샷이 그 단위 |
| DTO | `cached` / `totalProducts` | `snapshot` / `totalBalances` + `branchId`·`productBranchId` 추가 |

이 불변식은 `trg_stock_balances_apply` 가 원장 INSERT 와 **같은 트랜잭션에서** 유지한다 —
여기서 0 이 아니면 실제 버그다. 프론트 소비처는 없어서(DiagnosticsView 미사용) DTO 변경 파급 없음.

## T4 — 모델 주석

`products.model.ts` 의 `stock` 에 `@deprecated` + 대체 경로 명시
(지점별 → `stock_balances`, 전 지점 합 → `getAvailableByProduct()`).

## T5 — 검증

| 항목 | 로컬 5432 | 운영 5434 |
|---|---|---|
| `trg_stocks_sync_product_cache` | 제거됨 | 제거됨 |
| `trg_stock_balances_apply` | 유지 | 유지 |
| `v_stock_balance_drift` | 0 | 0 |
| `v_stock_tenant_leak` | 0 | 0 |
| `products.stock` COMMENT | 적용 | 적용 |

**스냅샷 즉시 반영 (로컬, 트랜잭션+ROLLBACK)**
`ProductBranch 76` 에 `venta -3` INSERT → `stock_balances.available` **50 → 47 즉시**,
같은 트랜잭션에서 `products.stock` 은 **50 그대로(동결 확인)**.

**빌드/테스트**: `tsc -p tsconfig.build.json` 0 / `nest build` 0 /
jest `diagnostics`+`products` = 2 suites·20 tests 실패인데 **stash 후 clean tree 에서 동일 수치**
→ 전부 pre-existing, **신규 실패 0**.

**운영 로그**: 재기동 후 에러 없음, healthy. 다만 운영은 마지막 원장 이동이 2026-08-02 라
**실사용 판매로는 아직 관찰되지 않았다** — 아래 참조.

---

## 남은 것

- **운영 24시간 관찰** — 재고 표시 이상 신고 여부. 첫 실판매가 들어올 때
  `stock_balances.updated_at` 이 갱신되는지 확인할 것 (현재 운영 최근 원장 = 2026-08-02)
- p95 응답시간 전/후 수치 (부하 하네스 필요, 미측정)
- 야간 크론(03:30) 첫 실행 후 텔레그램 알람이 조용한지 확인 — 지표 전환이 맞았다면 drift 0
