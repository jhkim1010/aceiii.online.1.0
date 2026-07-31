# 생산 흐름(Producción) 검증 매뉴얼

> **대상**: Ventago / ACE III — `app.coolsistema.com`
> **최초 작성**: 2026-07-31 · 최초 실행에서 흐름이 끝까지 도는 것을 확인함
> **목적**: 자재 → BOM → 로트 → Cut Ticket → 자재 소비까지 한 번에 검증한다.
> 새 매장을 열거나, 자재·BOM 관련 코드를 수정한 뒤 이 순서대로 다시 실행한다.

---

## 0. 핵심 개념 — 재고 카운터가 둘이다

이 시스템에는 **서로 다른 재고 저장소가 두 개** 있고, 서로 동기화되지 않는다.
헷갈리면 진단을 통째로 틀리게 하므로 먼저 익힌다.

| | 대상 | 테이블 | 줄어드는 시점 |
|---|---|---|---|
| **자재 재고** | 원단·부자재 | `mes_materials.current_stock` | **Cut Ticket 발행** |
| **상품 재고** | 완제품·변형 | `products.stock` (+ `stocks` 원장) | 판매·이동·생산완료 |

- 자재 소비의 **실사용 경로는 Cut Ticket** 이다(`talleres` 모듈).
- MES `작업지시(work-order)` 경로도 코드에 있으나 다른 저장소를 쓴다 —
  `products.sku = material.code` 인 **미러 상품**을 찾아 `stocks` 원장을 움직인다.
  미러 상품이 없으면 **경고 로그만 남기고 조용히 건너뛴다.** 운영에는 미러가 0건이므로
  이 경로는 사실상 비활성이다. 검증은 Cut Ticket 경로로 한다.

> **자재 소비가 0건이라고 곧 버그는 아니다.** 대부분 BOM 이 비어 있어서다.
> 2026-07-31 이전 운영 데이터가 정확히 그 상태였다(BOM 2건, 항목 0개, 소비 0건).

---

## 1. 사전 준비

### 1-1. 계정

**운영 계정(admin@cool)을 검증에 쓰지 말 것.** `active_sessions` 는 유저당 1개라
같은 계정으로 로그인하면 **실사용자가 즉시 튕긴다.**

검증용 계정을 따로 만든다. BOM·로트·Cut Ticket 은 `@Auth(admin, superadmin, gerente)` 이므로
**`gerente` 역할**이 필요하다.

| 항목 | 값(예시) |
|---|---|
| 사용자 | `depogte@dummy.test` |
| 비밀번호 | `dep1010` |
| 역할 | `gerente` |
| 매장 / 지점 | coolsistema(6) / coolsistema(6) |

> ⚠️ `inventory_clerk`(창고 담당) 역할로는 **로그인 직후 `/unauthorized/` 로 튕긴다.**
> `ValidRoles` 에 매핑이 없는 역할(`inventory_clerk`·`accountant`·`viewer`)은 앱을 못 쓴다.
> 이 검증에는 반드시 `gerente` 를 쓴다.

### 1-2. 새 기기 대화상자

처음 로그인하면 `Nuevo dispositivo detectado` 가 뜬다 →
`Mover desde un terminal existente` → 사용 중이 아닌 터미널 선택 → `Mover a este terminal`.

### 1-3. 캐하(Caja) 대화상자 — **절대 확인 누르지 말 것**

작업 중 `Selecciona Caja y Terminal` 이 반복해서 뜬다. `Monto inicial de hoy` 를 넣고
`Confirmar` 하면 **캐하가 개시되고 차액이 금고(Caja Fuerte)로 이체된다.**
검증 중에는 항상 **`Cancelar`** 를 누른다.

---

## 2. 검증 절차

각 단계마다 화면 결과와 **DB 확인 쿼리**를 함께 적었다. 화면만 믿지 말고 DB 로 확인한다.

DB 접속(읽기 전용):

```bash
ssh jhkim-server "sudo -u postgres psql -p 5434 -d ventago -A -F' | ' -c \"<SQL>\""
```

### 단계 1 — 공급업체 등록

`Materia Prima` → `Proveedores` → **`Nuevo Proveedor`**

| 칸 | 예시 |
|---|---|
| 업체명 | `DUMMY Textil Andina` |
| CUIT | `30-11111111-1` |
| 전화 | `011-4444-0001` |
| 담당자 | `Sr. Prueba Uno` |
| 결제조건 | `30 días` |

`Crear` → 목록에 나타나면 성공.

![단계 1 — Proveedores 화면. `Nuevo Proveedor` 로 등록하면 목록에 나타난다.](img/01-proveedores.png)

```sql
SELECT id, name, cuit FROM mes_material_suppliers
 WHERE store_id=6 AND name LIKE 'DUMMY%' ORDER BY id;
```

### 단계 2 — 자재 등록

`Materia Prima` → `Inventario` → **`Nuevo material`**

자재는 **madre + 색상(codigoHijito)** 구조다. 색상 행이 **최소 1개** 없으면 저장되지 않는다
(`Agregá al menos un color` 토스트만 뜬다).

| 칸 | 예시 |
|---|---|
| Código madre * | `DUM-TEL-01` |
| Nombre * | `DUMMY Tela algodon` |
| Unidad | `m (metro)` |
| Color | `AZUL` |
| Stock | `100` |
| Stock mín. | `20` |

> ⚠️ **이 폼에는 단가(precio) 입력칸이 없다.** 저장 payload 에 필드 자체가 없어
> `standard_price` 가 `NULL` 로 남는다. → **BOM 원가가 $0 으로 계산된다.**
> 현재는 별도 경로로 단가를 넣어야 한다(아래 「알려진 제약」 참조).

![단계 2 — Materia Prima · Inventario. madre 아래 색상별 자식이 붙고 재고는 자식에 붙는다.](img/02-materiales.png)

```sql
SELECT id, code, name, unit, standard_price, supplier_id, current_stock
  FROM mes_materials WHERE store_id=6 AND code LIKE 'DUM%' ORDER BY id;
```

기대: madre 행 + 색상 자식 행이 각각 생성되고, 재고는 **색상 자식**에 붙는다.

### 단계 3 — 완제품(madre) 상품 등록

`Productos` → 폼에 `NOMBRE`, `PRECIO 1` 입력 → **`Guardar`**

BOM 은 **`código madre` 상품에만** 걸린다. 자식 상품은 BOM 목록에 나오지 않는다.

```sql
SELECT id, sku, name, serial, str_prefix FROM products
 WHERE store_id=6 AND name ILIKE 'DUMMY%' ORDER BY id;
```

> ⚠️ **여기서 막히는 경우가 많다.** `Se alcanzó el máximo de 99 en este grupo` 오류가 뜨면
> SKU 시리얼 카운터가 상한(99)을 넘은 것이다. 아래 「알려진 제약 ①」 참조.

### 단계 4 — BOM 작성

`Talleres` → **`Cost Sheet (BOM)`** 탭

1. `Producto (código madre)` 드롭다운에서 단계 3 의 상품 선택
2. **`Crear BOM v1.0`**
3. **`Agregar material`** → 자재 선택(재고가 있는 **색상 자식** 을 고른다)
4. `Cantidad / prenda` 입력 (예: `2`)

변경은 자동 저장된다(`Cambios se guardan automáticamente`).

**확인 포인트**: `Precio` 와 `Subtotal / prenda` 가 채워지는지.
`$0` 이면 그 자재의 `standard_price` 가 비어 있다는 뜻이다.

![단계 4 — Cost Sheet (BOM). 자재·수량·단가·소계가 한 줄로 보인다. 수량을 넣어야 소계가 계산된다.](img/03-bom.png)

```sql
SELECT bi.id, bi.material_id, bi.quantity, bi.unit
  FROM mes_bom_items bi JOIN mes_bom b ON b.id=bi.bom_id
 WHERE b.product_id=<상품ID>;
```

### 단계 5 — 로트 생성

`Talleres` → `Lotes` → **`Nuevo Lote`**

| 칸 | 예시 |
|---|---|
| Producto * | 단계 3 의 상품 |
| Cantidad Total * | `10` |

![단계 5 — Lotes 목록. 로트별 총수량·진행률·상태가 보인다.](img/04-lotes.png)

```sql
SELECT id, lote_number, product_id, total_quantity, cut_ticket_number
  FROM talleres_lotes WHERE product_id=<상품ID>;
```

### 단계 6 — Cut Ticket 발행 ★ 자재가 소비되는 지점

**발행 전 자재 재고를 먼저 기록한다.**

```sql
SELECT id, code, current_stock FROM mes_materials WHERE id=<자재ID>;
```

`Talleres` → `Cut Ticket` 탭 → 로트 선택 → **`✂️ Configurar y Generar Cut Ticket`**
→ 공정 순서 확인(corte → lavadero → costura → estampadero → planchero) → **`Configurar y Generar`**

![단계 6 — Cut Ticket 발행 후. 번호(CT-YYYY-NNN)와 BOM·공정 스냅샷이 확정된다. 이 시점에 자재가 차감된다.](img/05-cutticket.png)

---

## 3. 기대값 — 이 표와 다르면 회귀다

BOM 수량 `Q`(벌당), 로트 수량 `N` 일 때:

| 확인 항목 | 기대값 |
|---|---|
| `talleres_lotes.cut_ticket_number` | `CT-YYYY-NNN` 부여됨 |
| `mes_material_movements` 신규 행 | `type='SALIDA'`, `quantity = Q × N` |
| 그 행의 `reference` | 발행된 `CT-YYYY-NNN` (추적성) |
| `mes_materials.current_stock` | **발행 전 − (Q × N)** |

### 2026-07-31 최초 실행 실측

| 항목 | 값 |
|---|---|
| 상품 | `263701` (id 308) |
| BOM | `DUM-TEL-01-AZUL` **2 m/벌**, Subtotal $9.000 |
| 로트 | `LOT-2026-007`, **10벌** |
| Cut Ticket | **`CT-2026-012`** |
| 자재 이동 | `SALIDA 20.000`, `reference=CT-2026-012` |
| 자재 재고 | **100 → 80** (= 2 × 10 차감) |

**흐름 정상 동작 확인.**

### 실패 판정

- `SALIDA` 행이 안 생김 → BOM 에 자재 항목이 없다(가장 흔함). 단계 4 를 다시 본다
- `quantity ≠ Q × N` → 소비량 계산 결함
- `current_stock` 이 안 줄어듦 → `consumeMaterialsFromBom` 트랜잭션 실패. API 로그 확인
- 같은 Cut Ticket 으로 `SALIDA` 가 2건 → **이중 차감**

```bash
ssh jhkim-server "docker logs --since 10m api_ventago 2>&1 | grep -a consumeMaterialsFromBom | tail -10"
```

---

## 4. 알려진 제약 (2026-07-31 기준)

수정되면 이 절을 갱신한다.

### ① SKU 시리얼 카운터 오염 — 상품 생성 차단

`sku_serials.last_serial` 에 `category_id × 10` 이 들어간 그룹이 있다(2026-07-16 백필 추정).
코드 상한은 `MAX_SERIAL = 99` 라 카운터가 이미 초과 → **자동 SKU 상품 생성 불가.**

```sql
SELECT store_id, count(*) 그룹수, count(*) FILTER (WHERE last_serial > 99) 초과그룹, max(last_serial)
  FROM sku_serials GROUP BY store_id ORDER BY store_id;
```

실측: store 6 은 12개 중 **10개**, store 11 은 3개 중 1개가 초과.

**임시 우회**: `Configuración` → `Productos` 탭 → `Parámetros` 표 →
`Prefijo para SKU` 행의 `Editar` → 값을 올린다(`25` → `26`).
새 prefix 는 새 시리얼 그룹이라 1부터 시작해 즉시 풀린다.

> 근본 해결은 카운터를 실제 최대 시리얼로 재계산하는 것이다. 단 `products.serial` 컬럼도
> 같은 백필로 오염돼 있어(SKU 문자열과 불일치) 거기서 값을 뽑으면 안 된다.

### ② `prefix` 빈 값 전송 — 400

`GET /products/next-serial?prefix=&supplierId=0&...` → `prefix es requerido` 오류 배너.
설정에 값이 있는데도 프론트가 빈 값으로 보낸다. 서버가 자체적으로 prefix 를 읽으므로
**상품 생성 자체는 성공**하지만 사용자에게는 붉은 오류가 보인다. (`ventago-app` 건)

### ③ 자재 폼에 단가·공급업체 칸 없음

단계 2 참조. `standard_price` 가 `NULL` 로 남아 **Cost Sheet 원가·마진이 전부 $0** 이 된다.
자재 원가 계산을 쓰려면 이 폼에 단가·공급업체 입력이 추가돼야 한다.

### ④ 캐하 대화상자 반복 차단

터미널이 배정되지 않은 사용자는 화면 이동 중에도 `Selecciona Caja y Terminal` 이 계속 뜬다.
검증 중에는 `Cancelar` 로 넘긴다(§1-3).

### ⑤ 색상 미입력 시 저장 실패 원인 불명확

자재 폼에서 색상을 비우고 `Guardar` 하면 토스트만 뜨고 어느 칸이 문제인지 표시되지 않는다.

---

## 5. 정리 (검증 후)

검증 데이터는 `DUMMY` / `DUM-` 접두를 붙여 만든다. 정리 시:

```sql
-- 확인용 조회 (삭제 전 반드시 대상 확인)
SELECT id, code, name FROM mes_materials WHERE code LIKE 'DUM%';
SELECT id, name FROM mes_material_suppliers WHERE name LIKE 'DUMMY%';
SELECT id, sku, name FROM products WHERE name ILIKE 'DUMMY%';
SELECT id, lote_number FROM talleres_lotes WHERE product_id IN (...);
```

> **판매는 지울 수 없다.** 검증 중 판매가 생겼다면 화면에서 **anular**(역분개) 한다.
> 자재 이동(`mes_material_movements`)도 원장이므로 지우지 말고 반대 이동으로 상쇄한다.

`Prefijo para SKU` 를 바꿨다면 원래 값으로 되돌릴지 결정한다 —
되돌리려면 ①의 카운터 문제를 먼저 해결해야 상품 생성이 가능하다.

---

## 부록 — 한 번에 확인하는 쿼리

```sql
SELECT
  (SELECT count(*) FROM mes_materials  WHERE store_id=6)            AS 자재,
  (SELECT count(*) FROM mes_bom)                                     AS BOM,
  (SELECT count(*) FROM mes_bom_items WHERE material_id IS NOT NULL) AS BOM자재항목,
  (SELECT count(*) FROM talleres_lotes WHERE cut_ticket_number IS NOT NULL) AS CutTicket발행,
  (SELECT count(*) FROM mes_material_movements WHERE type='SALIDA')  AS 자재출고;
```

`BOM자재항목` 이 0 인데 `CutTicket발행` 이 있다면, 그 발행들은 **자재를 소비하지 않았다.**
