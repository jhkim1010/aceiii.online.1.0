# Manual de verificación del flujo de Producción / 생산 흐름(Producción) 검증 매뉴얼

> **Destino / 대상**: Ventago / ACE III — `app.coolsistema.com`
> **Creado / 최초 작성**: 2026-07-31 · **Actualizado / 갱신**: 2026-07-31
> **ES** — Objetivo: verificar de una sola pasada el circuito material → BOM → lote → Cut Ticket → consumo de material.
> Repetir este orden al abrir una tienda nueva o al tocar código de materiales/BOM.
> **KO** — 목적: 자재 → BOM → 로트 → Cut Ticket → 자재 소비까지 한 번에 검증한다.
> 새 매장을 열거나, 자재·BOM 관련 코드를 수정한 뒤 이 순서대로 다시 실행한다.
>
> Este documento es bilingüe: cada bloque aparece en español (**ES**) y en coreano (**KO**).
> 이 문서는 이중 언어다: 모든 블록이 스페인어(**ES**)와 한국어(**KO**)로 함께 나온다.

---

## 0. Concepto clave — hay dos contadores de stock / 핵심 개념 — 재고 카운터가 둘이다

**ES** — El sistema tiene **dos almacenes de stock distintos** que no se sincronizan entre sí.
Confundirlos lleva a diagnósticos completamente equivocados, así que conviene fijarlo primero.

**KO** — 이 시스템에는 **서로 다른 재고 저장소가 두 개** 있고, 서로 동기화되지 않는다.
헷갈리면 진단을 통째로 틀리게 하므로 먼저 익힌다.

| | Objeto / 대상 | Tabla / 테이블 | Cuándo baja / 줄어드는 시점 |
|---|---|---|---|
| **Stock de material / 자재 재고** | telas, avíos / 원단·부자재 | `mes_materials.current_stock` | al emitir el Cut Ticket / **Cut Ticket 발행** |
| **Stock de producto / 상품 재고** | terminados, variantes / 완제품·변형 | `products.stock` (+ libro `stocks`) | venta, movimiento, cierre de producción / 판매·이동·생산완료 |

**ES**
- La vía real de consumo de material es el **Cut Ticket** (módulo `talleres`).
- La vía MES `work-order` existe en el código pero usa otro almacén: busca un **producto espejo**
  con `products.sku = material.code` y mueve el libro `stocks`. Si no hay espejo, **solo deja un warning
  y sigue de largo**. En producción hay 0 espejos, así que esa vía está inactiva. Verificar por Cut Ticket.

**KO**
- 자재 소비의 **실사용 경로는 Cut Ticket** 이다(`talleres` 모듈).
- MES `작업지시(work-order)` 경로도 코드에 있으나 다른 저장소를 쓴다 —
  `products.sku = material.code` 인 **미러 상품**을 찾아 `stocks` 원장을 움직인다.
  미러 상품이 없으면 **경고 로그만 남기고 조용히 건너뛴다.** 운영에는 미러가 0건이므로
  이 경로는 사실상 비활성이다. 검증은 Cut Ticket 경로로 한다.

> **ES** — Consumo de material = 0 **no** es necesariamente un bug. Casi siempre el BOM está vacío.
> Los datos de producción anteriores al 2026-07-31 estaban exactamente así (2 BOM, 0 ítems, 0 consumos).
> **KO** — **자재 소비가 0건이라고 곧 버그는 아니다.** 대부분 BOM 이 비어 있어서다.
> 2026-07-31 이전 운영 데이터가 정확히 그 상태였다(BOM 2건, 항목 0개, 소비 0건).

---

## 1. Preparación / 사전 준비

### 1-1. Cuenta / 계정

**ES** — **No usar la cuenta de producción (`admin@cool`) para verificar.** `active_sessions` admite
una sesión por usuario: si entrás con la misma cuenta, **el usuario real queda expulsado al instante**.
Crear una cuenta aparte. BOM, lotes y Cut Ticket exigen `@Auth(admin, superadmin, gerente)`,
por lo tanto hace falta el rol **`gerente`**.

**KO** — **운영 계정(admin@cool)을 검증에 쓰지 말 것.** `active_sessions` 는 유저당 1개라
같은 계정으로 로그인하면 **실사용자가 즉시 튕긴다.** 검증용 계정을 따로 만든다.
BOM·로트·Cut Ticket 은 `@Auth(admin, superadmin, gerente)` 이므로 **`gerente` 역할**이 필요하다.

| Campo / 항목 | Valor de ejemplo / 값(예시) |
|---|---|
| Usuario / 사용자 | `depogte@dummy.test` |
| Contraseña / 비밀번호 | `dep1010` |
| Rol / 역할 | `gerente` |
| Tienda / Sucursal · 매장 / 지점 | coolsistema(6) / coolsistema(6) |

> **ES** — ⚠️ Con el rol `inventory_clerk` (depósito) la app **rebota a `/unauthorized/` apenas iniciás sesión**.
> Los roles sin mapeo en `ValidRoles` (`inventory_clerk`, `accountant`, `viewer`) no pueden usar la app.
> Para esta verificación usar siempre `gerente`.
> **KO** — ⚠️ `inventory_clerk`(창고 담당) 역할로는 **로그인 직후 `/unauthorized/` 로 튕긴다.**
> `ValidRoles` 에 매핑이 없는 역할(`inventory_clerk`·`accountant`·`viewer`)은 앱을 못 쓴다.
> 이 검증에는 반드시 `gerente` 를 쓴다.

### 1-2. Diálogo de dispositivo nuevo / 새 기기 대화상자

**ES** — En el primer login aparece `Nuevo dispositivo detectado` →
`Mover desde un terminal existente` → elegir un terminal **que no esté en uso** → `Mover a este terminal`.

**KO** — 처음 로그인하면 `Nuevo dispositivo detectado` 가 뜬다 →
`Mover desde un terminal existente` → **사용 중이 아닌** 터미널 선택 → `Mover a este terminal`.

### 1-3. Diálogo de Caja — nunca confirmar / 캐하(Caja) 대화상자 — 절대 확인 누르지 말 것

**ES** — Durante el trabajo reaparece `Selecciona Caja y Terminal`. Si cargás `Monto inicial de hoy`
y tocás `Confirmar`, **se abre la caja y el excedente se transfiere a la Caja Fuerte.**
Durante la verificación tocar siempre **`Cancelar`**.

**KO** — 작업 중 `Selecciona Caja y Terminal` 이 반복해서 뜬다. `Monto inicial de hoy` 를 넣고
`Confirmar` 하면 **캐하가 개시되고 차액이 금고(Caja Fuerte)로 이체된다.**
검증 중에는 항상 **`Cancelar`** 를 누른다.

---

## 2. Procedimiento de verificación / 검증 절차

**ES** — Cada paso lleva el resultado en pantalla **y** la consulta de verificación en base.
No confiar solo en la pantalla: confirmar en la base.
**KO** — 각 단계마다 화면 결과와 **DB 확인 쿼리**를 함께 적었다. 화면만 믿지 말고 DB 로 확인한다.

Acceso a la base (solo lectura) / DB 접속(읽기 전용):

```bash
ssh jhkim-server "sudo -u postgres psql -p 5434 -d ventago -A -F' | ' -c \"<SQL>\""
```

### Paso 1 — Alta de proveedor / 단계 1 — 공급업체 등록

`Materia Prima` → `Proveedores` → **`Nuevo Proveedor`**

| Campo / 칸 | Ejemplo / 예시 |
|---|---|
| Nombre / 업체명 | `DUMMY Textil Andina` |
| CUIT | `30-11111111-1` |
| Teléfono / 전화 | `011-4444-0001` |
| Contacto / 담당자 | `Sr. Prueba Uno` |
| Condición de pago / 결제조건 | `30 días` |

**ES** — `Crear` → si aparece en la lista, listo. **KO** — `Crear` → 목록에 나타나면 성공.

![Paso 1 / 단계 1 — Proveedores.](img/01-proveedores.png)

```sql
SELECT id, name, cuit FROM mes_material_suppliers
 WHERE store_id=6 AND name LIKE 'DUMMY%' ORDER BY id;
```

### Paso 2 — Alta de material / 단계 2 — 자재 등록

`Materia Prima` → `Inventario` → pestaña `Materiales` → **`Nuevo material`**

**ES** — El material es **madre + color (codigoHijito)**. Sin al menos una fila de color no se guarda
(solo sale el toast `Agregá al menos un color`).
**KO** — 자재는 **madre + 색상(codigoHijito)** 구조다. 색상 행이 **최소 1개** 없으면 저장되지 않는다.

| Campo / 칸 | Ejemplo / 예시 |
|---|---|
| Código madre * | `DUM-TEL-01` |
| Nombre * | `DUMMY Tela algodon` |
| Unidad | `m (metro)` |
| **Precio estándar** | `4500` |
| **Proveedor (Materia Prima)** | `DUMMY Textil Andina` |
| Color | `AZUL` |
| Stock | `100` |
| Stock mín. | `20` |

> **ES** — ⚠️ **No dejar vacío `Precio estándar`.** Se guarda como 0 y entonces el costo y el margen
> del Cost Sheet (BOM) salen **todos en $0**. Está en la 3ª fila del formulario.
> El `Proveedor (Materia Prima)` se elige en el mismo formulario (visible también en el alta desde 2026-07-31).
> **KO** — ⚠️ **`Precio estándar` 를 비워 두지 말 것.** 0 으로 저장되면 BOM 원가·마진이 전부 $0 이 된다.
> 폼 3행에 있다. `Proveedor (Materia Prima)` 도 같은 폼에서 지정한다(2026-07-31 부터 신규 등록에도 노출).

![Paso 2 / 단계 2 — Materia Prima · Inventario.](img/02-materiales.png)

```sql
SELECT id, code, name, unit, standard_price, supplier_id, current_stock
  FROM mes_materials WHERE store_id=6 AND code LIKE 'DUM%' ORDER BY id;
```

**ES** — Esperado: se crean la fila madre y las filas hijas por color; el stock queda en **la hija**.
**KO** — 기대: madre 행 + 색상 자식 행이 각각 생성되고, 재고는 **색상 자식**에 붙는다.

### Paso 3 — Alta del producto terminado (madre) / 단계 3 — 완제품(madre) 상품 등록

`Productos` → completar `NOMBRE`, `PRECIO 1` → **`Guardar`**

**ES** — El BOM se engancha **solo a productos `código madre`**. Los hijos no aparecen en la lista de BOM.
**KO** — BOM 은 **`código madre` 상품에만** 걸린다. 자식 상품은 BOM 목록에 나오지 않는다.

```sql
SELECT id, sku, name, serial, str_prefix FROM products
 WHERE store_id=6 AND name ILIKE 'DUMMY%' ORDER BY id;
```

> **ES** — ⚠️ Si sale `Se alcanzó el máximo de 99 en este grupo`, el contador de serie del SKU pasó el tope (99).
> Ver §4 ①. **KO** — ⚠️ `Se alcanzó el máximo de 99 en este grupo` 오류가 뜨면 SKU 시리얼 카운터가
> 상한(99)을 넘은 것이다. §4 ① 참조.

### Paso 4 — Armado del BOM / 단계 4 — BOM 작성

`Talleres` → pestaña **`Cost Sheet (BOM)`**

1. **ES** elegir el producto del Paso 3 en `Producto (código madre)` / **KO** 드롭다운에서 단계 3 상품 선택
2. **`Crear BOM v1.0`**
3. **`Agregar material`** — **ES** elegir la **hija de color con stock** / **KO** 재고가 있는 **색상 자식** 선택
4. `Cantidad / prenda` — ej. `2`

**ES** — Los cambios se guardan solos (`Cambios se guardan automáticamente`).
Punto de control: que `Precio` y `Subtotal / prenda` se completen. Si sale `$0`, ese material no tiene `standard_price`.
**KO** — 변경은 자동 저장된다. **확인 포인트**: `Precio` 와 `Subtotal / prenda` 가 채워지는지.
`$0` 이면 그 자재의 `standard_price` 가 비어 있다는 뜻이다.

![Paso 4 / 단계 4 — Cost Sheet (BOM).](img/03-bom.png)

```sql
SELECT bi.id, bi.material_id, bi.quantity, bi.unit
  FROM mes_bom_items bi JOIN mes_bom b ON b.id=bi.bom_id
 WHERE b.product_id=<ID de producto / 상품ID>;
```

### Paso 5 — Crear lote / 단계 5 — 로트 생성

`Talleres` → `Lotes` → **`Nuevo Lote`**

| Campo / 칸 | Ejemplo / 예시 |
|---|---|
| Producto * | producto del Paso 3 / 단계 3 의 상품 |
| Cantidad Total * | `10` |

![Paso 5 / 단계 5 — Lotes.](img/04-lotes.png)

```sql
SELECT id, lote_number, product_id, total_quantity, cut_ticket_number
  FROM talleres_lotes WHERE product_id=<ID de producto / 상품ID>;
```

### Paso 6 — Emitir Cut Ticket ★ acá se consume el material / 단계 6 — Cut Ticket 발행 ★ 자재가 소비되는 지점

**ES** — **Anotar el stock del material antes de emitir.** / **KO** — **발행 전 자재 재고를 먼저 기록한다.**

```sql
SELECT id, code, current_stock FROM mes_materials WHERE id=<ID de material / 자재ID>;
```

`Talleres` → pestaña `Cut Ticket` → elegir lote → **`✂️ Configurar y Generar Cut Ticket`**
→ revisar el orden de etapas (corte → lavadero → costura → estampadero → planchero) → **`Configurar y Generar`**

![Paso 6 / 단계 6 — Cut Ticket.](img/05-cutticket.png)

---

## 3. Valores esperados — desviarse de esta tabla es regresión / 기대값 — 이 표와 다르면 회귀다

**ES** — Con `Q` = cantidad del BOM por prenda y `N` = cantidad del lote:
**KO** — BOM 수량 `Q`(벌당), 로트 수량 `N` 일 때:

| Verificación / 확인 항목 | Esperado / 기대값 |
|---|---|
| `talleres_lotes.cut_ticket_number` | `CT-YYYY-NNN` asignado / 부여됨 |
| fila nueva en `mes_material_movements` / 신규 행 | `type='SALIDA'`, `quantity = Q × N` |
| `reference` de esa fila / 그 행의 `reference` | el `CT-YYYY-NNN` emitido (trazabilidad) / 발행된 번호(추적성) |
| `mes_materials.current_stock` | **antes − (Q × N)** / **발행 전 − (Q × N)** |

### Medición real del 2026-07-31 / 2026-07-31 최초 실행 실측

| Ítem / 항목 | Valor / 값 |
|---|---|
| Producto / 상품 | `263701` (id 308) |
| BOM | `DUM-TEL-01-AZUL` **2 m/prenda**, Subtotal $9.000 |
| Lote / 로트 | `LOT-2026-007`, **10 prendas / 10벌** |
| Cut Ticket | **`CT-2026-012`** |
| Movimiento / 자재 이동 | `SALIDA 20.000`, `reference=CT-2026-012` |
| Stock de material / 자재 재고 | **100 → 80** (= 2 × 10) |

**ES — Flujo verificado y funcionando.** / **KO — 흐름 정상 동작 확인.**

### Criterios de falla / 실패 판정

**ES**
- No aparece la fila `SALIDA` → el BOM no tiene ítems de material (lo más común). Revisar el Paso 4
- `quantity ≠ Q × N` → defecto en el cálculo de consumo
- `current_stock` no baja → falló la transacción `consumeMaterialsFromBom`. Ver log de la API
- Dos filas `SALIDA` para el mismo Cut Ticket → **doble descuento**

**KO**
- `SALIDA` 행이 안 생김 → BOM 에 자재 항목이 없다(가장 흔함). 단계 4 를 다시 본다
- `quantity ≠ Q × N` → 소비량 계산 결함
- `current_stock` 이 안 줄어듦 → `consumeMaterialsFromBom` 트랜잭션 실패. API 로그 확인
- 같은 Cut Ticket 으로 `SALIDA` 가 2건 → **이중 차감**

```bash
ssh jhkim-server "docker logs --since 10m api_ventago 2>&1 | grep -a consumeMaterialsFromBom | tail -10"
```

---

## 4. Limitaciones conocidas — estado / 알려진 제약 — 처리 상태 (2026-07-31)

| # | Limitación / 제약 | Estado / 상태 |
|---|---|---|
| ① | Contador de serie del SKU contaminado / SKU 시리얼 카운터 오염 | **Corregido en producción / 운영 복구 완료** — `migrations/sku-serials-recalc.sql`, 11 grupos, 0 restantes |
| ② | `prefix` vacío → 400 / `prefix` 빈 값 전송 | **Corregido / 수정됨** |
| ③ | Precio y proveedor en el formulario de material / 자재 폼 단가·공급업체 | **Corregido / 수정됨** |
| ④ | Diálogo de Caja repetido / 캐하 대화상자 반복 | **Corregido / 수정됨** |
| ⑤ | Falla de color poco clara / 색상 미입력 원인 불명확 | **Corregido / 수정됨** |

### ① Contador de serie del SKU / SKU 시리얼 카운터 오염

**ES** — Un backfill del 2026-07-16 dejó `category_id × 10` en `sku_serials.last_serial` (p. ej. categoría 27 → 270).
El tope del código es `MAX_SERIAL = 99`, así que el alta automática de productos quedaba **bloqueada**
con `SKU_SERIAL_EXHAUSTED`.

**KO** — 2026-07-16 백필이 `sku_serials.last_serial` 에 `category_id × 10` 을 넣었다(예: 카테고리 27 → 270).
코드 상한이 `MAX_SERIAL = 99` 라 자동 SKU 상품 생성이 통째로 막혔다.

```sql
SELECT store_id, count(*) grupos, count(*) FILTER (WHERE last_serial > 99) excedidos, max(last_serial)
  FROM sku_serials GROUP BY store_id ORDER BY store_id;
```

**Solución de fondo (aplicada) / 근본 복구 (적용 완료)** — `api-ventago/migrations/sku-serials-recalc.sql`

**ES** — Devuelve el contador al **máximo serial realmente usado en ese grupo**. Como `products.serial`
quedó contaminado por el mismo backfill (>99), solo se confían los valores **1–99**; si no hay, queda 0
(el siguiente reparto será 1). Aplicado el 2026-07-31 en producción (5434): 11 grupos actualizados,
**0 grupos por encima de 99**. En local (5432) no había contaminación.

**KO** — 카운터를 **그 그룹에서 실제로 쓰인 최대 serial** 로 되돌린다. `products.serial` 도 같은 백필로
오염돼(>99) **1~99 범위 값만** 신뢰하고, 없으면 0(다음 발급 = 1)으로 둔다. 2026-07-31 운영(5434) 적용 완료 —
11개 그룹 갱신, **초과 그룹 0**. 로컬(5432)은 오염이 없어 적용 불필요.

| store | prefix | category | antes / 전 | después / 후 |
|---|---|---|---|---|
| 6 | 25 | 10·20·27·28·29·30·31·32·37·43 | 102~430 | **0** |
| 11 | 25 | 56 | 560 | **5** |

```bash
ssh jhkim-server "sudo -u postgres psql -p 5434 -d ventago -v ON_ERROR_STOP=1 -f -" \
  < api-ventago/migrations/sku-serials-recalc.sql
```

**ES** — Workaround si vuelve a pasar (99 usados en un grupo): `Configuración` → `Productos` → `Parámetros` →
`Prefijo para SKU` → `Editar` y subir el valor (`25` → `26`). Un prefijo nuevo abre un grupo nuevo desde 1.
**KO** — 재발 시(한 그룹에 99개를 채운 경우) 우회: `Configuración` → `Productos` → `Parámetros` →
`Prefijo para SKU` → `Editar` 로 값을 올린다(`25` → `26`). 새 prefix 는 새 시리얼 그룹이라 1부터 시작한다.

### ② `prefix` vacío → 400 / `prefix` 빈 값 전송 → 400

**ES** — Síntoma: `GET /products/next-serial?prefix=&...` devolvía `prefix es requerido` y el usuario veía
un cartel rojo, aunque el alta del producto igual funcionaba (el servidor usa su propio prefijo).
Corrección en dos capas: el front (`BasicDataCard`) **no llama** a next-serial hasta tener el prefijo,
y el servidor (`products.service.getNextSerial`) **completa** el prefijo con la configuración de la tienda
en vez de responder 400.

**KO** — 증상: `GET /products/next-serial?prefix=&...` 가 `prefix es requerido` 400 을 돌려줘 붉은 배너가 떴다
(상품 생성 자체는 서버 prefix 로 성공). 수정 두 겹: 프론트(`BasicDataCard`)는 prefix 로딩 전 호출하지 않고,
서버(`products.service.getNextSerial`)는 400 대신 매장 설정으로 보완한다.

### ③ Precio y proveedor en el formulario de material / 자재 폼 단가·공급업체

**ES** — El formulario realmente usado es el de la primera pestaña (`TelasMadreView`), y no tenía
ni precio ni proveedor: `standard_price` quedaba en 0 y el Cost Sheet salía todo en $0.
Se agregaron `Precio estándar` y `Proveedor (Materia Prima)`, y ahora se envían tanto a la madre
como a las hijas de color.

**KO** — 실제 쓰이는 폼은 첫 탭(`TelasMadreView`)이었고 단가·공급업체 칸이 없었다 →
`standard_price` 가 0 으로 남아 Cost Sheet 가 전부 $0. `Precio estándar` 와 `Proveedor (Materia Prima)` 를
추가했고, madre 와 색상 자식 양쪽에 저장한다.

### ④ Diálogo de Caja repetido / 캐하 대화상자 반복

**ES** — Causa: si `/cash-register/status` fallaba (sin permiso, sin terminal asignado…), el front abría
el modal **sin condición**, y como el layout se vuelve a montar al cambiar de pantalla, reaparecía siempre.
Corrección: también en el camino de error se respeta el "ya lo vi hoy" (localStorage) → **una vez por día**.

**KO** — 원인: `/cash-register/status` 조회 실패 시(권한 없음·터미널 미배정 등) 프론트가 **조건 없이** 모달을 다시 열었다.
화면 이동마다 레이아웃이 재마운트되므로 계속 떴다. 수정: 실패 경로에서도 "오늘 이미 봄"(localStorage)을 존중해 **하루 1회**.

### ⑤ Falla por color no cargado / 색상 미입력 시 저장 실패

**ES** — Antes solo salía el toast `Agregá al menos un color`. Ahora el campo `Color` de la fila con problema
se marca en rojo con el motivo debajo; los colores repetidos se señalan igual.

**KO** — `Agregá al menos un color` 토스트만 뜨던 것을, 문제 행의 `Color` 칸을 빨갛게 표시하고 사유를 아래에 남기도록 바꿨다.
색상 중복도 같은 방식으로 표시한다.

---

## 5. Cuidados de la corrida piloto / 시범 운행 주의사항 (2026-07-31)

**ES** — Solo los puntos que costaron tiempo real de diagnóstico. Revisar en este orden.
**KO** — 원인 찾는 데 시간이 오래 걸린 항목만 순서대로 모았다.

### 5-1. Sin precio, el costo entero sale $0 / 단가를 비우면 원가가 통째로 $0

`Materia Prima` → `Inventario` → `Materiales` → `Nuevo material`

**ES** — Completar siempre `Precio estándar`. Vacío se guarda 0 y el `Precio`, el `Subtotal / prenda`
y el margen del Cost Sheet quedan en $0. Elegir también `Proveedor (Materia Prima)`: es el camino
para conseguir el contacto cuando el stock se agota.

**KO** — `Precio estándar` 를 반드시 채운다. 비우면 0 으로 저장되고 Cost Sheet 의 `Precio` ·
`Subtotal / prenda` · 마진이 전부 $0 이 된다. `Proveedor (Materia Prima)` 도 지정한다 —
재고가 바닥났을 때 연락처를 찾는 경로다.

![5-1 — Nuevo material: precio y proveedor / 자재 등록 — 단가·공급자](img/06-material-precio-proveedor.png)

> **ES** — Ambos campos se agregaron el 2026-07-31. Los materiales creados antes tienen `standard_price`
> vacío: hay que abrirlos y cargar el precio para que el BOM calcule costo.
> **KO** — 두 칸은 2026-07-31 에 추가됐다. 이전에 만든 자재는 `standard_price` 가 비어 있으니
> 열어서 단가를 채워야 BOM 원가가 산출된다.

### 5-2. Mínimo un color / 색상은 최소 1개

**ES** — El material es madre + color (codigoHijito), así que hace falta al menos una fila de color.
Si guardás sin color, ese campo `Color` se pone rojo con el motivo debajo. Dos filas con el mismo color
se bloquean igual (los códigos hijos chocarían).

**KO** — 자재는 madre + 색상(codigoHijito) 구조라 색상 행이 최소 1개 필요하다. 비운 채 `Guardar` 하면
해당 `Color` 칸이 빨갛게 변하고 사유가 아래에 뜬다. 같은 색을 두 행에 넣어도 같은 방식으로 막힌다(자식 code 충돌).

![5-2 — Color faltante marcado en rojo / 색상 미입력 빨간 표시](img/07-color-error.png)

### 5-3. El SKU lo asigna el servidor / SKU 는 서버가 발급한다

**ES** — En `Productos`, con el campo `SKU` en `auto`, el servidor arma el código. Si el número se completa
sin cartel rojo, está bien.
**KO** — `Productos` 화면의 `SKU` 칸은 `auto` 상태에서 서버가 조립한다. 붉은 오류 배너 없이 번호가 채워지면 정상이다.

![5-3 — Productos con SKU automático / 자동 SKU 정상 화면](img/08-productos-sin-error.png)

**ES** — Si aparece `Se alcanzó el máximo de 99 en este grupo`, ese grupo (prefijo + categoría) agotó el contador.
Los 11 contadores contaminados se repararon el 2026-07-31, pero al llegar a 99 en un grupo vuelve a pasar:
ahí se sube el prefijo en `Configuración` → `Productos` → `Parámetros` → `Prefijo para SKU` → `Editar`.

**KO** — `Se alcanzó el máximo de 99 en este grupo` 가 뜨면 그 그룹(prefix+카테고리) 카운터가 99 를 넘긴 것이다.
2026-07-31 에 오염 카운터 11개를 복구했지만, 한 그룹에 99개를 채우면 다시 만난다. 그때는
`Configuración` → `Productos` → `Parámetros` → `Prefijo para SKU` → `Editar` 로 prefix 를 올린다.

![5-4 — Prefijo para SKU / 접두 설정](img/09-prefijo-sku.png)

### 5-4. Cuentas y diálogos / 계정과 대화상자

**ES**
- No iniciar sesión con la cuenta de producción: `active_sessions` es única por usuario y expulsa al usuario real (§1-1).
- `Selecciona Caja y Terminal` → siempre `Cancelar`; `Confirmar` abre la caja y transfiere a la Caja Fuerte (§1-3).
  Desde la corrección del 2026-07-31 aparece una vez por día.
- Los roles `inventory_clerk`, `accountant`, `viewer` rebotan a `/unauthorized/`. La cuenta de prueba va con `gerente`.

**KO**
- 운영 계정으로 로그인하지 말 것 — `active_sessions` 는 유저당 1개라 실사용자가 튕긴다(§1-1).
- `Selecciona Caja y Terminal` 은 항상 `Cancelar` — `Confirmar` 하면 캐하 개시 + 금고 이체(§1-3).
  2026-07-31 수정으로 하루 1회만 뜬다.
- `inventory_clerk` · `accountant` · `viewer` 역할은 `/unauthorized/` 로 튕긴다. 검증 계정은 `gerente` 로 만든다.

### 5-5. Si el material no baja, mirar el BOM / 자재가 줄지 않으면 BOM 부터 본다

**ES** — Si emitiste el Cut Ticket y no hay `SALIDA` en `mes_material_movements`, casi siempre el BOM
no tiene ítems de material. La pantalla se ve normal, así que hay que confirmarlo con las consultas de §3.
El material del BOM tiene que ser la **hija de color con stock** (la fila madre no tiene stock).

**KO** — Cut Ticket 을 발행했는데 `mes_material_movements` 에 `SALIDA` 가 없으면 거의 항상 BOM 에
자재 항목이 없다. 화면은 정상으로 보이므로 §3 쿼리로 확인한다. BOM 자재는 **재고가 붙은 색상 자식**을
골라야 한다(madre 행에는 재고가 없다).

---

## 6. Limpieza (después de verificar) / 정리 (검증 후)

**ES** — Los datos de prueba se crean con prefijo `DUMMY` / `DUM-`. Para limpiar:
**KO** — 검증 데이터는 `DUMMY` / `DUM-` 접두를 붙여 만든다. 정리 시:

```sql
-- Consulta previa: confirmar el objetivo antes de borrar / 확인용 조회 (삭제 전 반드시 대상 확인)
SELECT id, code, name FROM mes_materials WHERE code LIKE 'DUM%';
SELECT id, name FROM mes_material_suppliers WHERE name LIKE 'DUMMY%';
SELECT id, sku, name FROM products WHERE name ILIKE 'DUMMY%';
SELECT id, lote_number FROM talleres_lotes WHERE product_id IN (...);
```

> **ES** — **Las ventas no se borran.** Si se generó una venta durante la prueba, se **anula** desde la pantalla.
> Los movimientos de material (`mes_material_movements`) también son libro: no se borran, se compensan
> con un movimiento inverso.
> **KO** — **판매는 지울 수 없다.** 검증 중 판매가 생겼다면 화면에서 **anular**(역분개) 한다.
> 자재 이동(`mes_material_movements`)도 원장이므로 지우지 말고 반대 이동으로 상쇄한다.

**ES** — Si cambiaste `Prefijo para SKU`, decidí si lo volvés al valor original; para volver, primero
tiene que estar sano el contador de ①.
**KO** — `Prefijo para SKU` 를 바꿨다면 되돌릴지 결정한다 — 되돌리려면 ①의 카운터가 정상이어야 한다.

---

## Apéndice — consulta de control en un solo paso / 부록 — 한 번에 확인하는 쿼리

```sql
SELECT
  (SELECT count(*) FROM mes_materials  WHERE store_id=6)            AS materiales,
  (SELECT count(*) FROM mes_bom)                                     AS boms,
  (SELECT count(*) FROM mes_bom_items WHERE material_id IS NOT NULL) AS items_material,
  (SELECT count(*) FROM talleres_lotes WHERE cut_ticket_number IS NOT NULL) AS cut_tickets,
  (SELECT count(*) FROM mes_material_movements WHERE type='SALIDA')  AS salidas;
```

**ES** — Si `items_material` es 0 pero hay `cut_tickets`, esas emisiones **no consumieron material**.
**KO** — `items_material` 이 0 인데 `cut_tickets` 가 있다면, 그 발행들은 **자재를 소비하지 않았다.**
