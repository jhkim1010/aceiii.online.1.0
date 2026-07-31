# Producción paso a paso / 생산 기능 사용 설명서

> **Para quién es / 대상**: personal de tienda y depósito que usa Ventago (ACE III) en `app.coolsistema.com`.
> 매장·창고에서 Ventago(ACE III)를 쓰는 담당자용.
> **Qué vas a lograr / 무엇을 하게 되나**: cargar las telas y avíos, decir cuánto lleva cada prenda,
> abrir un lote de producción y emitir el Cut Ticket. Al emitirlo, el sistema descuenta solo el material que corresponde.
> 원단·부자재를 등록하고, 옷 한 벌에 얼마가 들어가는지 지정하고, 생산 로트를 열어 Cut Ticket 을 발행한다.
> 발행하는 순간 시스템이 필요한 자재만큼 재고를 자동으로 뺀다.
> Documento bilingüe: cada bloque va en español (**ES**) y coreano (**KO**).
> 이 문서는 스페인어(**ES**)·한국어(**KO**) 병기다.

---

## El recorrido completo / 전체 흐름

| # | Pantalla / 화면 | Qué hacés / 하는 일 |
|---|---|---|
| 1 | `Materia Prima` → `Proveedores` | Cargar a quién le comprás / 매입처 등록 |
| 2 | `Materia Prima` → `Inventario` | Cargar la tela o el avío, con precio / 자재를 단가와 함께 등록 |
| 3 | `Productos` | Cargar la prenda que vas a fabricar / 생산할 완제품 등록 |
| 4 | `Talleres` → `Cost Sheet (BOM)` | Decir cuánto material lleva cada prenda / 벌당 자재 소요량 지정 |
| 5 | `Talleres` → `Lotes` | Abrir el lote de producción / 생산 로트 개시 |
| 6 | `Talleres` → `Cut Ticket` | Emitir el corte — **acá baja el stock** / Cut Ticket 발행 — **여기서 재고가 빠진다** |

**ES** — Hacelo en este orden. Si salteás el paso 4, el Cut Ticket se emite igual pero **no descuenta nada**.
**KO** — 이 순서대로 한다. 4번을 건너뛰면 Cut Ticket 은 발행되지만 **아무 자재도 차감되지 않는다.**

---

## Antes de empezar / 시작 전 확인

**ES**
- Necesitás un usuario con rol **`gerente`** (o admin). Con roles de solo depósito la pantalla no abre.
- La primera vez que entrás desde una computadora nueva aparece `Nuevo dispositivo detectado`:
  elegí `Mover desde un terminal existente`, tocá un terminal **que nadie esté usando** y confirmá con `Mover a este terminal`.
- Si aparece `Selecciona Caja y Terminal` y **no vas a vender ahora**, tocá `Cancelar`.
  `Confirmar` abre la caja del día y transfiere el excedente a la Caja Fuerte.

**KO**
- **`gerente`**(또는 admin) 권한 계정이 필요하다. 창고 전용 역할로는 화면이 열리지 않는다.
- 새 컴퓨터에서 처음 접속하면 `Nuevo dispositivo detectado` 가 뜬다:
  `Mover desde un terminal existente` → **아무도 쓰지 않는** 터미널 선택 → `Mover a este terminal`.
- `Selecciona Caja y Terminal` 이 떴는데 **지금 판매할 게 아니면** `Cancelar` 를 누른다.
  `Confirmar` 하면 그 날 캐하가 개시되고 차액이 금고(Caja Fuerte)로 넘어간다.

---

## Paso 1 · Cargar el proveedor / 단계 1 · 공급업체 등록

`Materia Prima` → `Proveedores` → **`Nuevo Proveedor`**

| Campo / 칸 | Ejemplo / 예시 |
|---|---|
| Nombre / 업체명 | `Textil Andina` |
| CUIT | `30-11111111-1` |
| Teléfono / 전화 | `011-4444-0001` |
| Contacto / 담당자 | `Sr. Pérez` |
| Condición de pago / 결제조건 | `30 días` |

**ES** — Tocá `Crear`. Si aparece en la lista, quedó guardado.
**KO** — `Crear` 를 누른다. 목록에 나타나면 저장된 것이다.

![Pantalla de Proveedores / 공급업체 화면](img/01-proveedores.png)

---

## Paso 2 · Cargar la tela o el avío / 단계 2 · 자재(원단·부자재) 등록

`Materia Prima` → `Inventario` → pestaña `Materiales` → **`Nuevo material`**

**ES** — Un material se carga en dos niveles: el **código madre** (la tela en general) y una fila por **color**.
El stock vive en el color, no en la madre.
**KO** — 자재는 두 단계로 등록한다: **código madre**(원단 자체)와 **색상별 행**.
재고는 madre 가 아니라 색상 행에 붙는다.

| Campo / 칸 | Ejemplo / 예시 | Nota / 메모 |
|---|---|---|
| Código madre * | `TEL-001` | se autocompleta al elegir categoría / 카테고리 고르면 자동 생성 |
| Nombre * | `Denim 12oz` | |
| Unidad | `m (metro)` | cómo lo consumís / 소비 단위 |
| **Precio estándar** | `4500` | **obligatorio en la práctica / 사실상 필수** |
| **Proveedor** | `Textil Andina` | para reponer rápido / 재주문 연락처 |
| Color | `AZUL` | al menos uno / 최소 1개 |
| Stock | `100` | lo que tenés hoy / 현재 보유량 |
| Stock mín. | `20` | avisa cuando baja / 이 아래로 떨어지면 경고 |

![Nuevo material — precio y proveedor / 자재 등록 — 단가·공급자](img/06-material-precio-proveedor.png)

> **ES** — **Si dejás `Precio estándar` vacío, todo el costo sale $0.** El sistema lo guarda como cero
> y después el Cost Sheet muestra `Precio $0` y `Subtotal $0`. Cargalo aunque sea aproximado.
> **KO** — **`Precio estándar` 를 비우면 원가가 전부 $0 로 나온다.** 0 으로 저장되기 때문에
> Cost Sheet 에 `Precio $0` · `Subtotal $0` 이 뜬다. 대략값이라도 반드시 넣는다.

**ES** — ¿Varios colores de la misma tela? Cargá una fila por color con el botón `+`; el sistema arma
los códigos hijos solo (`TEL-001-AZUL`, `TEL-001-NEGRO`…).
**KO** — 같은 원단의 여러 색은 `+` 로 행을 추가한다. 자식 코드(`TEL-001-AZUL`, `TEL-001-NEGRO` …)는 자동 생성된다.

---

## Paso 3 · Cargar la prenda / 단계 3 · 완제품 등록

`Productos` → completá `NOMBRE` y `PRECIO 1` → **`Guardar`**

**ES** — Dejá el `SKU` en `auto`: lo arma el sistema. La receta (BOM) se engancha **solo al código madre**,
así que cargá primero la prenda madre y después sus variantes.
**KO** — `SKU` 는 `auto` 로 둔다 — 시스템이 만든다. 레시피(BOM)는 **código madre 상품에만** 걸리므로
madre 상품을 먼저 만들고 변형을 나중에 만든다.

![Productos con SKU automático / 자동 SKU 화면](img/08-productos-sin-error.png)

---

## Paso 4 · Decir cuánto lleva cada prenda (Cost Sheet / BOM) / 단계 4 · 벌당 소요량 지정

`Talleres` → pestaña **`Cost Sheet (BOM)`**

1. **ES** Elegí la prenda en `Producto (código madre)` / **KO** `Producto (código madre)` 에서 상품 선택
2. **`Crear BOM v1.0`**
3. **`Agregar material`** — **ES** elegí la fila **de color** (la que tiene stock) / **KO** 재고가 있는 **색상 행**을 고른다
4. `Cantidad / prenda` — **ES** cuánto entra en UNA prenda (ej. `2` metros) / **KO** 옷 **한 벌**에 들어가는 양(예: `2` m)

**ES** — Se guarda solo (`Cambios se guardan automáticamente`). Mirá que `Precio` y `Subtotal / prenda`
queden con números: si dicen `$0`, a ese material le falta el precio (volvé al Paso 2).
**KO** — 자동 저장된다(`Cambios se guardan automáticamente`). `Precio` 와 `Subtotal / prenda` 에 숫자가
들어오는지 본다. `$0` 이면 그 자재에 단가가 없다는 뜻이다(단계 2 로 돌아간다).

![Cost Sheet (BOM) / 원가표 화면](img/03-bom.png)

---

## Paso 5 · Abrir el lote / 단계 5 · 로트 생성

`Talleres` → `Lotes` → **`Nuevo Lote`**

| Campo / 칸 | Ejemplo / 예시 |
|---|---|
| Producto * | la prenda del Paso 3 / 단계 3 의 상품 |
| Cantidad Total * | `10` (prendas a producir / 생산할 벌수) |

**ES** — El lote es la orden de producción: agrupa las prendas que van juntas al taller.
**KO** — 로트는 생산 지시다 — 같이 작업장에 넘길 옷을 묶는다.

![Lotes / 로트 목록](img/04-lotes.png)

---

## Paso 6 · Emitir el Cut Ticket / 단계 6 · Cut Ticket 발행

`Talleres` → pestaña `Cut Ticket` → elegí el lote → **`✂️ Configurar y Generar Cut Ticket`**
→ revisá el orden de etapas (corte → lavadero → costura → estampadero → planchero) → **`Configurar y Generar`**

**ES** — **En este momento el sistema descuenta el material.** Si el BOM dice 2 m por prenda y el lote
es de 10 prendas, salen 20 m del stock de esa tela.
**KO** — **이 순간 자재가 차감된다.** BOM 이 벌당 2 m 이고 로트가 10벌이면 그 원단 재고에서 20 m 가 빠진다.

![Cut Ticket emitido / 발행된 Cut Ticket](img/05-cutticket.png)

---

## Cómo saber que salió bien / 제대로 됐는지 확인하는 법

**ES** — Sin tocar la base de datos, mirá estas tres cosas:

1. El lote muestra un número `CT-2026-0NN`. Si no lo tiene, el ticket no se emitió.
2. En `Materia Prima` → `Inventario`, el stock de esa tela **bajó** exactamente lo esperado
   (cantidad por prenda × prendas del lote).
3. En el Cost Sheet, `Subtotal / prenda` no está en `$0`.

**KO** — DB 를 보지 않고 화면에서 확인할 세 가지:

1. 로트에 `CT-2026-0NN` 번호가 붙었다. 없으면 발행되지 않은 것이다.
2. `Materia Prima` → `Inventario` 에서 그 원단 재고가 **정확히** 예상만큼 줄었다(벌당 소요량 × 로트 수량).
3. Cost Sheet 의 `Subtotal / prenda` 가 `$0` 이 아니다.

---

## Errores frecuentes y qué hacer / 자주 나는 오류와 해결

### “Agregá al menos un color”

**ES** — Falta elegir el color del material. El campo `Color` de la fila con problema queda **en rojo**
con el motivo debajo. Elegí un color y guardá. Si dos filas tienen el mismo color, cambiá una:
cada color arma un código distinto y no pueden repetirse.

**KO** — 자재 색상을 고르지 않았다. 문제 행의 `Color` 칸이 **빨갛게** 변하고 사유가 아래에 뜬다.
색을 고르고 저장한다. 두 행에 같은 색을 넣으면 하나를 바꾼다 — 색마다 코드가 달라져야 해서 중복은 불가하다.

![Color faltante marcado en rojo / 색상 미입력 빨간 표시](img/07-color-error.png)

### “Se alcanzó el máximo de 99 en este grupo”

**ES** — Ese grupo de SKU (prefijo + categoría) ya usó los 99 números disponibles.
Solución: `Configuración` → `Productos` → `Parámetros` → `Prefijo para SKU` → `Editar` y subí el número
(por ejemplo `25` → `26`). El prefijo nuevo empieza a numerar desde 1 y podés seguir cargando productos.

**KO** — 그 SKU 그룹(접두 + 카테고리)이 99번을 다 썼다는 뜻이다.
해결: `Configuración` → `Productos` → `Parámetros` → `Prefijo para SKU` → `Editar` 에서 값을 올린다
(예: `25` → `26`). 새 접두는 1번부터 다시 시작해서 바로 상품을 계속 등록할 수 있다.

![Prefijo para SKU / SKU 접두 설정](img/09-prefijo-sku.png)

### El costo del Cost Sheet sale $0 / Cost Sheet 원가가 $0 으로 나옴

**ES** — Al material le falta `Precio estándar`. Abrilo en `Materia Prima` → `Inventario`, cargá el precio
y volvé al Cost Sheet: se recalcula solo.
**KO** — 그 자재에 `Precio estándar` 가 없다. `Materia Prima` → `Inventario` 에서 열어 단가를 넣고
Cost Sheet 로 돌아오면 자동으로 다시 계산된다.

### Emití el Cut Ticket y el stock no bajó / Cut Ticket 을 냈는데 재고가 그대로

**ES** — Casi siempre el BOM quedó vacío: se creó la receta pero sin `Agregar material`.
Volvé al Paso 4, agregá el material y la cantidad por prenda, y emití un Cut Ticket nuevo para el próximo lote.
El ticket ya emitido no descuenta hacia atrás.

**KO** — 대부분 BOM 이 비어 있어서다 — 레시피만 만들고 `Agregar material` 을 안 한 경우다.
단계 4 로 돌아가 자재와 벌당 수량을 넣고, 다음 로트에서 새로 Cut Ticket 을 발행한다.
이미 발행된 티켓이 소급해서 차감하지는 않는다.

### La pantalla vuelve sola al login / 화면이 저절로 로그인으로 돌아감

**ES** — Alguien entró con la **misma cuenta** desde otra computadora. El sistema permite una sesión por
usuario. Volvé a entrar; si pasa seguido, pedí un usuario propio en vez de compartir uno.
**KO** — 다른 컴퓨터에서 **같은 계정**으로 로그인한 것이다. 계정당 세션은 1개다.
다시 로그인하면 되고, 자주 반복되면 계정을 공유하지 말고 개인 계정을 요청한다.

---

## Palabras que vas a ver / 자주 나오는 용어

| Término / 용어 | Qué significa / 뜻 |
|---|---|
| Código madre / 코드 마드레 | La tela o prenda “general”. No guarda stock por sí sola. / 원단·상품의 대표 코드. 자체 재고는 없다 |
| Código hijito / 자식 코드 | La variante por color (y talle). **Acá está el stock.** / 색상(·사이즈) 변형. **재고는 여기 있다** |
| BOM / Cost Sheet | La receta: cuánto material lleva una prenda. / 레시피 — 옷 한 벌의 자재 소요량 |
| Lote | La orden de producción de N prendas. / N벌짜리 생산 지시 |
| Cut Ticket | El corte emitido. Descuenta el material. / 발행된 재단 지시. 자재를 차감한다 |
| Stock mín. | Umbral de aviso de reposición. / 재주문 경고 기준 |

---

## Recordá / 기억할 것

**ES**
1. Sin `Precio estándar`, todos los costos salen $0.
2. Sin material en el BOM, el Cut Ticket no descuenta nada.
3. El stock siempre vive en el **color**, no en el código madre.
4. Si no vas a vender, en `Selecciona Caja y Terminal` tocá `Cancelar`.

**KO**
1. `Precio estándar` 가 없으면 원가가 전부 $0 이다.
2. BOM 에 자재가 없으면 Cut Ticket 이 아무것도 차감하지 않는다.
3. 재고는 언제나 **색상 행**에 있다 — madre 가 아니다.
4. 판매할 게 아니면 `Selecciona Caja y Terminal` 에서 `Cancelar` 를 누른다.
