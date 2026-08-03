# 재고 조회 체계 제안 — 결과는 계승, 구조는 새로

작성 2026-08-02 · 근거: 업로드된 `15. create x screendetails2 (2026.Feb.27).sql` (ACE III 데스크톱), 현행 Ventago 스키마 실측, Trello LNBmJ2ZI 사고

---

## 0. 이 문서의 입장

주신 SQL 에서 **가져올 것은 결과물의 정의**입니다.

```
stockreal   = 입고 + 보정 − 판매 − 예약
porcentaje  = 판매 × 100 / (입고 + 보정)
fecha 3종  = 최초 입고 / 최종 입고 / 최종 판매
today 2종  = 오늘 입고 / 오늘 판매
4개 관점    = (지점별 | 통합) × (변형 | 코디고 마드레)
```

**버릴 것은 계산 방식**입니다. 아래에서 왜 그대로 옮기면 안 되는지, 무엇으로 대체하는지 설명합니다.

---

## 1. legacy 구조를 그대로 옮기면 안 되는 이유 3가지

### ① 조회할 때마다 원장 전체를 다시 더한다 — O(원장)

`screendetails2` 계열은 뷰 6개를 만들어 6-way LEFT JOIN 합니다. 뷰는 저장물이 아니라 **매크로**이므로, 화면을 열 때마다 `ingresos`·`vdetalle`·`cobdetalles`·`corregidos` 전체를 다시 스캔·집계합니다. 단일 매장 데스크톱에서는 견뎠지만 지금 목표 규모에서는 못 견딥니다.

실측·추정:

| 시점 | `stocks` 행수 | 상품목록 1회 렌더 비용 |
|---|---|---|
| 지금 (2026-08-02) | 1,020행 (6.4행/일) | 무시 가능 |
| Phase 63 목표 (3,000 터미널) | **~30만 행/일 → 연 1억 행** | 뷰 재집계로는 불가능 |

터미널 1대가 하루 50건 판매 × 평균 2품목 = 100행/일 기준입니다. **읽기 비용이 누적 거래량에 비례하는 설계는 시간이 지나면 반드시 죽습니다.**

### ② 입고 없는 지점의 판매가 통째로 사라진다 (legacy 실제 버그)

`screendetails2_id_2` 는 `sucursal` 을 **입고 뷰(`ing1`)에서만** 가져옵니다.

```sql
from codigos cdg
left outer join ingresodetails_id_2 ing1 on cdg.id_codigo = ing1.id_codigo
left outer join itemdetails_id_2   item1 on ing1.id_codigo = item1.id_codigo
                                        AND ing1.sucursal0 = item1.sucursal   -- ← ing1 기준
```

지점 1에만 입고했는데 재고 이동 후 지점 2에서 팔았다면 **지점 2 행 자체가 생기지 않습니다.** 다지점 운영에서 조용히 틀립니다.

### ③ 단독 매장 전제

`codigos` 전체가 곧 한 매장입니다. Ventago 는 매장 차원이 **두 갈래**로 들어옵니다 — `products.store_id`(상품)와 `branches.store_id`(지점). `ProductBranch` 가 둘을 잇는 매핑이라, 어긋난 행이 하나라도 생기면 남의 매장 화면에 상품이 뜹니다.

실측(2026-08-02): `ProductBranch` 230행 중 어긋난 행 **0건**, `parent_id` 교차 202행 중 **0건**. Phase 67 정리 이후 깨끗하지만, 실제로 오염됐던 자리이므로 **구조에 방어를 박습니다**.

---

## 2. ★ 지금 코드에 있는 더 큰 병목 — 부모 행 잠금

제안에 앞서, 조사 중 발견한 것을 먼저 말씀드립니다. 현행 `trg_stocks_sync_product_cache` 는 이렇게 돼 있습니다.

```sql
UPDATE products
   SET stock = COALESCE(stock, 0) + NEW.stock
 WHERE id = v_product_id
    OR (v_parent_id IS NOT NULL AND id = v_parent_id);   -- ★ 부모 행도 잠근다
```

**어떤 변형이 팔리든 같은 코디고 마드레의 부모 행 하나를 잠급니다.** 마드레 하나에 변형 20개가 달려 있고 여러 지점·터미널에서 동시에 팔리면, 그 판매들이 전부 **부모 행 한 줄에서 직렬화**됩니다. 터미널이 늘어날수록 정확히 이 지점에서 막힙니다. 뷰를 아무리 잘 만들어도 쓰기가 여기서 걸리면 소용없습니다.

제안하는 구조는 이 잠금을 **없앱니다** (§3-B).

---

## 3. 제안 구조 — 3층

```
 [A] stocks            원장. append-only + 불변(트리거로 강제). 진실의 유일한 출처
       │  INSERT 트리거 (증분)
       ▼
 [B] stock_balances    잔액 스냅샷. ProductBranch 1행 = 1행. 읽기 O(1)
       │
       ▼
 [C] 인터페이스 뷰 4종  지점별/통합 × 변형/마드레 — 앱은 여기만 본다
       +
     v_stock_dia       당일 지표 (원장 1일치 인덱스 스캔 — 작음)
     stock_mensual     월별 롤업 (기간 리포트용, 마감된 달은 동결)
```

### [A] 원장에 `store_id` / `branch_id` 비정규화 컬럼 추가 ★

`stocks` 는 지금 `product_branch_id` 밖에 없습니다. 그래서 **매장 범위를 알려면 매번 `ProductBranch → products → branches` 3중 조인**이 필요합니다.

이게 성능 문제만은 아닙니다. Phase 67 멀티테넌트 격리 훅은 `store_id` 컬럼이 있는 모델에만 붙는데, `stocks` 에는 없어서 **훅이 조용히 건너뜁니다.** 즉 지금 `stocks` 는 격리 4중 방어의 사각지대입니다.

```sql
ALTER TABLE stocks ADD COLUMN store_id  int;
ALTER TABLE stocks ADD COLUMN branch_id int;
-- 백필 후 NOT NULL + INSERT 트리거로 자동 채움 (앱 코드 변경 불필요)
CREATE INDEX idx_stocks_store_date ON stocks (store_id, operation_date);
CREATE INDEX idx_stocks_pb_type    ON stocks (product_branch_id, type);
```

**조인 3개 제거 + 격리 사각지대 제거**를 한 번에 얻습니다. 이 하나만으로도 지금 느린 재고 쿼리들이 눈에 띄게 빨라집니다.

### [B] `stock_balances` — 증분 잔액 스냅샷

```sql
CREATE TABLE stock_balances (
  product_branch_id int PRIMARY KEY REFERENCES "ProductBranch"(id) ON DELETE CASCADE,
  store_id  int NOT NULL,
  branch_id int NOT NULL,
  product_id int NOT NULL,
  parent_id  int,

  total_ingreso  int NOT NULL DEFAULT 0,
  total_anulado  int NOT NULL DEFAULT 0,
  total_ajuste   int NOT NULL DEFAULT 0,
  total_venta    int NOT NULL DEFAULT 0,
  total_transfer int NOT NULL DEFAULT 0,
  reservado      int NOT NULL DEFAULT 0,
  on_hand        int NOT NULL DEFAULT 0,
  available      int NOT NULL DEFAULT 0,

  fecha_primer_ingreso date,
  fecha_ultimo_ingreso date,
  fecha_ultima_venta   date,
  movimientos    int NOT NULL DEFAULT 0,
  updated_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_sb_store_branch ON stock_balances (store_id, branch_id);
CREATE INDEX idx_sb_parent       ON stock_balances (store_id, parent_id);
```

트리거는 `INSERT ... ON CONFLICT DO UPDATE` 하나로 생성과 증분을 동시에 처리합니다.

```sql
CREATE FUNCTION stock_balances_apply() RETURNS trigger AS $$
BEGIN
  INSERT INTO stock_balances AS b (
    product_branch_id, store_id, branch_id, product_id, parent_id,
    total_ingreso, total_anulado, total_ajuste, total_venta, total_transfer,
    reservado, on_hand, available,
    fecha_primer_ingreso, fecha_ultimo_ingreso, fecha_ultima_venta, movimientos)
  SELECT
    pb.id, p.store_id, pb.branch_id, pb.product_id, p.parent_id,
    CASE WHEN NEW.type IS NULL AND NEW.stock > 0 THEN NEW.stock ELSE 0 END,
    CASE WHEN NEW.type='adjust' AND NEW.note LIKE 'anulacion ingreso%' THEN -NEW.stock ELSE 0 END,
    CASE WHEN NEW.type='adjust' AND COALESCE(NEW.note,'') NOT LIKE 'anulacion ingreso%' THEN NEW.stock ELSE 0 END,
    CASE WHEN NEW.type='sale'     THEN -NEW.stock ELSE 0 END,
    CASE WHEN NEW.type='transfer' THEN  NEW.stock ELSE 0 END,
    CASE WHEN NEW.type='suspend'  THEN -NEW.stock ELSE 0 END,
    CASE WHEN NEW.type IS NULL OR NEW.type <> 'suspend' THEN NEW.stock ELSE 0 END,
    NEW.stock,
    CASE WHEN NEW.type IS NULL AND NEW.stock > 0 THEN NEW.operation_date END,
    CASE WHEN NEW.type IS NULL AND NEW.stock > 0 THEN NEW.operation_date END,
    CASE WHEN NEW.type = 'sale' THEN NEW.operation_date END,
    1
  FROM "ProductBranch" pb
  JOIN products p ON p.id = pb.product_id
  JOIN branches b2 ON b2.id = pb.branch_id AND b2.store_id = p.store_id   -- ★ 매장 일치 방어
  WHERE pb.id = NEW.product_branch_id
  ON CONFLICT (product_branch_id) DO UPDATE SET
    total_ingreso  = b.total_ingreso  + EXCLUDED.total_ingreso,
    total_anulado  = b.total_anulado  + EXCLUDED.total_anulado,
    total_ajuste   = b.total_ajuste   + EXCLUDED.total_ajuste,
    total_venta    = b.total_venta    + EXCLUDED.total_venta,
    total_transfer = b.total_transfer + EXCLUDED.total_transfer,
    reservado      = b.reservado      + EXCLUDED.reservado,
    on_hand        = b.on_hand        + EXCLUDED.on_hand,
    available      = b.available      + EXCLUDED.available,
    fecha_primer_ingreso = LEAST(b.fecha_primer_ingreso, EXCLUDED.fecha_primer_ingreso),
    fecha_ultimo_ingreso = GREATEST(b.fecha_ultimo_ingreso, EXCLUDED.fecha_ultimo_ingreso),
    fecha_ultima_venta   = GREATEST(b.fecha_ultima_venta, EXCLUDED.fecha_ultima_venta),
    movimientos    = b.movimientos + 1,
    updated_at     = now();
  RETURN NEW;
END $$ LANGUAGE plpgsql;
```

### 왜 이 증분이 안전한가 — 캐시와 다른 점

`products.stock` 캐시가 못 미더웠던 건 캐싱이 나빠서가 아닙니다. **불변식이 없었기 때문**입니다. 여기엔 있습니다.

1. `stocks` 는 `trg_stocks_immutable` 로 UPDATE·DELETE 가 **물리적으로 막혀** 있습니다.
2. 따라서 원장 변화는 **INSERT 뿐**이고, 모든 지표는 **덧셈으로만 이동**합니다 (`MIN`/`MAX` 는 단조).
3. 덧셈만 있는 집계는 증분 유지가 **수학적으로 정확**합니다 — 재계산 결과와 항상 같습니다.
4. 그래서 `스냅샷 − 원장재계산 = 0` 이 **불변식**이 됩니다. 0이 아니면 그 자체가 버그 경보입니다 (§6).

즉 이 스냅샷은 "빠르지만 틀릴 수 있는 캐시" 가 아니라 **"검증 가능한 파생 상태"** 입니다.

### 부수 효과: 부모 행 잠금 제거

`stock_balances` 는 `ProductBranch` 단위라 부모 행을 건드리지 않습니다. 마드레 합계는 읽을 때 자식 몇 개를 더하면 됩니다(§4-c/d, 인덱스 `idx_sb_parent`).
→ §2 의 직렬화 지점이 사라집니다. `trg_stocks_sync_product_cache` 는 W5 에서 폐기하고 `products.stock` 은 진단용으로 강등합니다.

### [C] 당일 지표는 스냅샷에 넣지 않는다

`ingreso_hoy` / `venta_hoy` 를 스냅샷에 두면 자정마다 전 행을 리셋해야 합니다 — 락 폭탄입니다.
대신 **하루치만 원장에서 읽습니다.** `idx_stocks_pb_opdate` 로 오늘 파티션만 스캔하므로 항상 작습니다.

```sql
CREATE VIEW v_stock_dia AS
SELECT store_id, branch_id, product_branch_id, operation_date,
  COALESCE( SUM(stock) FILTER (WHERE type IS NULL AND stock > 0), 0)::int AS ingreso,
  COALESCE(-SUM(stock) FILTER (WHERE type = 'adjust' AND note LIKE 'anulacion ingreso%'), 0)::int AS anulado,
  COALESCE(-SUM(stock) FILTER (WHERE type = 'sale'), 0)::int AS venta,
  ( COALESCE(SUM(stock) FILTER (WHERE type IS NULL AND stock > 0), 0)
  + COALESCE(SUM(stock) FILTER (WHERE type = 'adjust' AND note LIKE 'anulacion ingreso%'), 0))::int AS ingreso_neto
FROM stocks
GROUP BY store_id, branch_id, product_branch_id, operation_date;
```

오늘 배포한 `v_product_branch_daily_ingreso` 를 이걸로 대체합니다 (상위 호환).

### [D] 기간 리포트는 월별 롤업으로

"올해 총 판매", "분기별 회전율" 같은 질의는 스냅샷(전 기간 누계)으로도, 당일 뷰로도 답할 수 없습니다.

```sql
CREATE TABLE stock_mensual (
  product_branch_id int NOT NULL,
  store_id int NOT NULL,
  periodo  date NOT NULL,          -- 월 첫날
  ingreso int, anulado int, ajuste int, venta int, transfer int, reservado_delta int,
  cerrado boolean NOT NULL DEFAULT false,   -- 마감된 달은 다시 계산하지 않는다
  PRIMARY KEY (product_branch_id, periodo)
);
```

지난 달들은 **동결**되어 다시 스캔되지 않고, 당월만 야간 배치로 갱신합니다. 기간 질의 = 마감월 인덱스 조회 + 당월 소량 스캔.

---

## 4. 인터페이스 뷰 4종 — 앱이 보는 유일한 면

세 층의 복잡함은 여기서 감춥니다. 앱 코드는 테이블을 직접 만지지 않습니다.

```sql
-- ── (a) 지점별 × 변형 ─ 가장 세밀. 재고 실사·이동 판단 ──────────────────────
CREATE VIEW v_stock_sucursal_variante AS
SELECT
  b.store_id, b.branch_id, br.name AS sucursal, br.is_warehouse AS es_deposito,
  b.product_id, p.sku AS codigo, p.name AS descripcion,
  b.parent_id AS madre_id, pm.sku AS codigo_madre,
  c.name AS color, t.name AS talle,
  b.total_ingreso, b.total_ajuste, b.total_venta, b.reservado,
  b.on_hand, b.available,
  COALESCE(d.ingreso_neto, 0) AS ingreso_hoy,
  COALESCE(d.venta, 0)        AS venta_hoy,
  b.fecha_primer_ingreso, b.fecha_ultimo_ingreso, b.fecha_ultima_venta,
  (CURRENT_DATE - b.fecha_ultima_venta)::int AS dias_sin_venta,
  ROUND(b.total_venta * 100.0
        / NULLIF(b.total_ingreso + b.total_ajuste, 0), 1) AS porcentaje_vendido,
  CASE
    WHEN b.available <= 0                                      THEN 'AGOTADO'
    WHEN b.total_venta = 0                                     THEN 'SIN_MOVIMIENTO'
    WHEN (CURRENT_DATE - b.fecha_ultima_venta) > 60            THEN 'LENTO'
    ELSE 'NORMAL'
  END AS estado
FROM stock_balances b
JOIN products p  ON p.id = b.product_id
JOIN branches br ON br.id = b.branch_id AND br.store_id = b.store_id     -- ★ 매장 가드
LEFT JOIN products pm ON pm.id = b.parent_id AND pm.store_id = b.store_id -- ★ 매장 가드
LEFT JOIN colors c ON c.id = p.color_id
LEFT JOIN sizes  t ON t.id = p.size_id
LEFT JOIN v_stock_dia d
       ON d.product_branch_id = b.product_branch_id
      AND d.operation_date = CURRENT_DATE;

-- ── (b) 통합 × 변형 ─ 전사 재고. 온라인몰 노출 수량 ─────────────────────────
CREATE VIEW v_stock_total_variante AS
SELECT b.store_id, b.product_id, p.sku AS codigo, p.name AS descripcion, b.parent_id AS madre_id,
  SUM(b.total_ingreso)::int AS total_ingreso, SUM(b.total_ajuste)::int AS total_ajuste,
  SUM(b.total_venta)::int   AS total_venta,   SUM(b.reservado)::int    AS reservado,
  SUM(b.on_hand)::int AS on_hand, SUM(b.available)::int AS available,
  COUNT(*) FILTER (WHERE b.available > 0)::int AS sucursales_con_stock,
  MIN(b.fecha_primer_ingreso) AS fecha_primer_ingreso,
  MAX(b.fecha_ultima_venta)   AS fecha_ultima_venta,
  ROUND(SUM(b.total_venta) * 100.0
        / NULLIF(SUM(b.total_ingreso) + SUM(b.total_ajuste), 0), 1) AS porcentaje_vendido
FROM stock_balances b
JOIN products p ON p.id = b.product_id AND p.store_id = b.store_id
GROUP BY b.store_id, b.product_id, p.sku, p.name, b.parent_id;

-- ── (c) 지점별 × 코디고 마드레 ─ 지점 발주 판단 ─────────────────────────────
CREATE VIEW v_stock_sucursal_madre AS
SELECT b.store_id, b.branch_id, COALESCE(b.parent_id, b.product_id) AS madre_id,
  SUM(b.total_ingreso)::int AS total_ingreso, SUM(b.total_ajuste)::int AS total_ajuste,
  SUM(b.total_venta)::int   AS total_venta,   SUM(b.reservado)::int    AS reservado,
  SUM(b.on_hand)::int AS on_hand, SUM(b.available)::int AS available,
  COUNT(DISTINCT b.product_id)::int AS variantes,
  MAX(b.fecha_ultima_venta) AS fecha_ultima_venta,
  ROUND(SUM(b.total_venta) * 100.0
        / NULLIF(SUM(b.total_ingreso) + SUM(b.total_ajuste), 0), 1) AS porcentaje_vendido
FROM stock_balances b
GROUP BY b.store_id, b.branch_id, COALESCE(b.parent_id, b.product_id);

-- ── (d) 통합 × 코디고 마드레 ─ 대시보드·리포트 ──────────────────────────────
CREATE VIEW v_stock_total_madre AS
SELECT m.store_id, m.madre_id, p.sku AS codigo_madre, p.name AS descripcion,
  SUM(m.total_ingreso)::int AS total_ingreso, SUM(m.total_ajuste)::int AS total_ajuste,
  SUM(m.total_venta)::int   AS total_venta,   SUM(m.reservado)::int    AS reservado,
  SUM(m.on_hand)::int AS on_hand, SUM(m.available)::int AS available,
  MAX(m.variantes)::int AS variantes,
  COUNT(*) FILTER (WHERE m.available > 0)::int AS sucursales_con_stock,
  MAX(m.fecha_ultima_venta) AS fecha_ultima_venta,
  ROUND(SUM(m.total_venta) * 100.0
        / NULLIF(SUM(m.total_ingreso) + SUM(m.total_ajuste), 0), 1) AS porcentaje_vendido
FROM v_stock_sucursal_madre m
JOIN products p ON p.id = m.madre_id AND p.store_id = m.store_id       -- ★ 매장 가드
GROUP BY m.store_id, m.madre_id, p.sku, p.name;
```

`ALTER VIEW ... OWNER TO coolsistema` 는 전부 필수입니다 (누락 시 운영 500).

---

## 4-B. 실측 벤치마크 — 얼마나 빨라지는가

추정이 아니라 **운영과 같은 서버**에서 잰 값입니다 (8코어 / 31GB / PG18.4 / shared_buffers 2GB). `ventago_staging` 에 `bench` 스키마를 만들어 측정하고 삭제했습니다.

**합성 데이터**: 50 매장 × 400 ProductBranch = 20,000 PB, 원장 10,000,000행 (PB당 500 이동, 판매 60% / 입고 15% / 예약 15% / 보정 10%, 730일 분포).
**측정 질의**: 매장 1곳(400 PB, 원장 200,000행)의 재고 목록. 3회 실행 후 안정값.

| 방식 | 1M행 | 3M행 | 10M행 |
|---|---|---|---|
| **A** legacy 그대로 (뷰에 매장 스코프 없음) | 45 ms | 82 ms | **253 ms** |
| **A′** legacy 구조 + 매장 필터 push-down | — | — | **65 ms** |
| **B** 단일 FILTER 패스 (§3 L1 방식) | 4.1 ms | 7.9 ms | **63 ms** |
| **C** 스냅샷 — 매장 전체 400행 | — | — | **0.24 ms** |
| **C2** 스냅샷 — 화면 페이지 50행 | — | — | **0.61 ms** |
| **D** 스냅샷 — 마드레 롤업 (매장 전체) | — | — | **0.31 ms** |

**@10M 배수: A 대비 C2 = 415배, C = 1,054배. A′ 대비도 106배.**

부가 측정:
- 스냅샷 전량 재구축(W2 백필, 10M행) = **1.68초** — 무중단 도입 가능
- 스냅샷 크기 **2.8 MB** vs 원장 **812 MB** (0.35%)

### 정직하게 짚을 점 두 가지

**① 다중 패스 자체는 생각보다 싸다.** A(253ms) → A′(65ms) 로 4배가 줄어드는데, 이건 패스를 줄여서가 아니라 **매장 필터를 안으로 밀어넣어서**입니다. A′와 B가 65ms vs 63ms 로 거의 같습니다 — PostgreSQL 이 두 번째 패스부터는 캐시된 페이지를 읽기 때문입니다.
→ **legacy 의 진짜 문제는 6-way JOIN 이 아니라 "매장 개념이 없어서 항상 전량을 훑는 것"** 이었습니다. 여기서도 §1-③ 이 성능 문제로 되돌아옵니다.

**② 지금 규모에서는 스냅샷이 오히려 느립니다.** 스냅샷 조회에는 인덱스 탐색 + 차원 조인이라는 고정비 약 0.6ms 가 있습니다. 원장이 작으면 그냥 훑는 게 빠릅니다.

```
뷰 방식   T ≈ 0.33 µs × (매장 원장 행수)     ← 데이터에 비례해 무한히 증가
스냅샷    T ≈ 0.6 ms  (고정)                 ← 원장 크기와 무관
손익분기  ≈ 매장당 원장 1,800행
```

현재 ACE 최대 매장(store 6)은 **885행** — 아직 분기점의 절반입니다. 지금 당장은 이득이 없습니다.
**이 제안의 값어치는 지금이 아니라 분기점 이후에 있습니다.**

### 예측표 — 매장당 원장 행수로 읽으세요

| 매장 원장 행수 | 도달 시점(추정) | 뷰 방식 | 스냅샷 | 배수 |
|---|---|---|---|---|
| 885 (현재 store 6) | 지금 | 0.3 ms | 0.6 ms | 0.5× (뷰 우세) |
| 1,800 | ~5개월 후 (6.4행/일 유지 시) | 0.6 ms | 0.6 ms | 1× (분기점) |
| 20,000 | 매장 활성화·터미널 증설 | 7 ms | 0.6 ms | 12× |
| 200,000 | (실측 지점) | 65 ms | 0.6 ms | **108×** |
| 2,000,000 | 3,000 터미널 × 3년 | ~650 ms | 0.6 ms | **1,080×** |
| 20,000,000 | 대형 체인 장기 | ~6.5 초 | 0.6 ms | **10,800×** |

**예측이 가능한 이유**: 두 방식 모두 실행계획이 단순합니다. 뷰 = Seq/Index Scan + HashAggregate = **O(스코프 내 행수)**, 스냅샷 = Index Scan + Limit = **O(log M + 페이지크기)**. 1M→3M→10M 측정이 선형을 확인해 주므로 위 표는 외삽이 아니라 같은 직선 위의 점들입니다.

### pool 관점 — 이게 진짜 이유입니다

응답시간보다 **커넥션 점유시간**이 중요합니다. 워커당 max=20, PM2 4워커 = 상한 80.

| 매장 원장 행수 | 뷰 방식 점유 | 워커당 처리량 상한 | 스냅샷 점유 | 상한 |
|---|---|---|---|---|
| 200,000 | 65 ms | **~300 q/s** | 0.6 ms | ~33,000 q/s |
| 2,000,000 | 650 ms | **~30 q/s** | 0.6 ms | ~33,000 q/s |

원장 200만 행 시점에 재고 목록 조회가 **워커당 초당 30건**이면, 터미널 3,000대 환경에서 pool 이 먼저 말라붙습니다. 커넥션을 늘려 해결할 문제가 아닙니다 — pgbouncer `pool_size=50`, PG `max_connections=200` 이 상한이라 **쿼리 효율로만 풀 수 있습니다.**

---

## 5. legacy 대비 무엇이 좋아지는가

| 항목 | legacy `screendetails2` | 제안 |
|---|---|---|
| 읽기 복잡도 | **O(원장 전체)** — 조회마다 재집계 | **O(1)** — 스냅샷 1행 조회 |
| 조인 수 | 보조뷰 6개 6-way LEFT JOIN | 스냅샷 + 상품/지점 조인 2~3개 |
| 매장 범위 조인 | 없음 (단독 매장) | `stocks.store_id` 로 조인 3개 제거 |
| 입고 없는 지점 판매 | **누락됨** | `ProductBranch` 기준이라 정상 |
| "오늘" | 뷰에 하드코딩, 다른 날짜 불가 | 날짜가 컬럼 — 임의 날짜 조회 |
| 분모 0 소진율 | 500% 같은 이상치 | `NULL` |
| 창고(deposito) | 뷰마다 규칙 제각각 | `es_deposito` 컬럼 — 호출자가 결정 |
| 쓰기 경합 | — | **부모 행 잠금 제거** (§2) |
| 정합성 | 검증 수단 없음 | `드리프트 = 0` 불변식 (§6) |
| 기간 리포트 | 불가 | 월별 롤업으로 지원 |
| 멀티테넌트 | 없음 | 전 뷰 `store_id` + 조인 매장 가드 |

---

## 6. 정합성 감시 — "0이어야 한다"

증분이 정확하다는 §3-B 의 논증은 **검증 가능**해야 의미가 있습니다.

```sql
CREATE VIEW v_stock_balance_drift AS
SELECT b.product_branch_id, b.store_id,
       b.available AS snapshot, COALESCE(SUM(s.stock), 0)::int AS ledger,
       b.available - COALESCE(SUM(s.stock), 0)::int AS drift
FROM stock_balances b
LEFT JOIN stocks s ON s.product_branch_id = b.product_branch_id
GROUP BY b.product_branch_id, b.store_id, b.available
HAVING b.available <> COALESCE(SUM(s.stock), 0);
```

야간 배치가 이 뷰를 조회해 **1행이라도 나오면 Telegram 알림**을 보냅니다. 원장이 불변이므로 정상 상태에서는 항상 0행입니다 — 즉 0이 아닌 순간이 곧 버그 발생 시점이고, `updated_at` 으로 언제인지도 좁혀집니다.

추가로 `v_stock_tenant_leak` — §4 의 매장 가드에서 걸러진 행을 **드러내는** 뷰를 둡니다. 방어와 관측을 분리해야 조용한 데이터 손실이 안 생깁니다.

---

## 7. 이번 사고와의 관계 — 뷰만으로는 부족하다

Trello LNBmJ2ZI 는 재고가 -336이 된 사건이었습니다. 그런데 **캐시는 원장을 정확히 반영하고 있었습니다** — 드리프트 목록에 없었습니다. 원장 자체에 중복 상쇄 행 4개가 들어간 것이었습니다.

즉 **뷰도 스냅샷도 이 사고를 막지 못합니다.** 읽기 구조는 "같은 질문에 같은 답"을 보장할 뿐, "잘못된 행이 안 들어옴"은 보장하지 않습니다. 쓰기 경로의 멱등성 가드(오늘 배포 완료)는 이 제안과 별개로 계속 필요합니다.

이 제안이 실제로 막는 것은 **그 사고의 방아쇠**였습니다 — 목록이 갱신되지 않아 사용자가 5번 클릭한 것. 읽기 정의가 하나로 통일되면 첫 클릭에 행이 사라집니다.

---

## 8. 단계 제안

| 단계 | 내용 | 위험 | 되돌리기 |
|---|---|---|---|
| **W1** | `stocks.store_id/branch_id` 추가 + 백필 + 인덱스 | 낮음 (컬럼 추가) | 컬럼 DROP |
| **W2** | `stock_balances` 테이블 + 트리거 + 원장 전량 백필 | 낮음 (읽는 코드 없음) | 테이블 DROP |
| **W3** | `v_stock_balance_drift` 야간 감시 — **1주일 관찰** | 없음 | — |
| **W4** | 인터페이스 뷰 4종 + `v_stock_dia` 생성 | 없음 | 뷰 DROP |
| **W5** | 재고 목록·대시보드 읽기를 뷰로 교체 | 중 (화면 회귀) | 코드 revert |
| **W6** | 판매 검증·live-stock 을 뷰로 교체 | 높음 (POS) | 별도 phase |
| **W7** | `trg_stocks_sync_product_cache` 폐기, `products.stock` 진단용 강등 | 높음 | 트리거 재생성 |
| **W8** | `stock_mensual` 월별 롤업 (기간 리포트 요구 시) | 낮음 | — |

**W1~W4 는 기존 코드가 전혀 읽지 않는 신규 구조물**이라 운영 중에 넣어도 안전합니다. W3 에서 1주일간 드리프트 0을 확인한 뒤에야 W5 로 넘어갑니다 — 증분이 정확하다는 주장을 실측으로 확인하고 가는 게 이 계획의 핵심입니다.

로컬(5432)·운영(5434) 동시 적용, 신규 테이블은 owner + 시퀀스를 `coolsistema` 로 이전하는 DO 블록 포함이 전제입니다.
