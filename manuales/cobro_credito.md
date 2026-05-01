# Manual: Cómo cobrar un crédito (cuando el cliente viene a pagar)

Este manual explica qué hacer cuando un cliente que tiene una deuda en
cuenta corriente viene a la tienda a pagar (total o parcial).

---

## Conceptos básicos del cobro

Cuando el cliente trae plata para saldar deuda, el sistema **distribuye
el pago automáticamente con el método FIFO** (First In First Out): se
salda primero la deuda más antigua y luego las siguientes.

**Tres tipos de operación de cobro:**

1. **Pago de deuda (`credit_payment`)** — cliente paga una o varias
   deudas. Si paga más de lo que debe, la diferencia se acredita como
   **saldo a favor** automáticamente.
2. **Adelanto / saldo a favor (`favor_advance`)** — cliente deja plata
   sin tener deuda, para usar en compras futuras.
3. **Aplicar favor (`apply_favor`)** — el cliente prefiere usar su
   saldo a favor para saldar una deuda corriente. Esto se hace desde
   el modal de pago en la venta, no desde acá.

---

## Dónde está el módulo de cobros

**Sidebar → Venta → Cuentas Corrientes**

Esa pantalla muestra:
- **Aging** (cuadro de envejecimiento de deudas) — 4 tarjetas con la
  suma total de deudas según antigüedad: 0-30 / 31-60 / 61-90 / 90+ días.
- **Top deudores** — lista de los 20 clientes con más deuda, con buscador
  por nombre o documento.

---

## Flujo paso a paso — cobrar un pago

### Paso 1 — Encontrar al cliente

**Opción A — desde Top deudores:**
1. En la pantalla **Cuentas Corrientes**, escribir parte del nombre o
   DNI/CUIT en el buscador del recuadro "Top 20 deudores".
2. Hacer clic en la fila del cliente.

**Opción B — desde la lista de Cuentas Corrientes (si tiene poca deuda):**
1. Si el cliente no aparece en el top 20, abrir el módulo y filtrar por
   nombre. (En la versión actual, el listado está limitado a top 20 —
   para clientes fuera del top, abrir directamente la URL
   `/cuentas-corrientes/<id>` o buscar al cliente desde Nueva Venta).

### Paso 2 — Revisar la información del cliente

Al hacer clic en el cliente, se abre la pantalla con:

- **Tarjetas de saldo** (4):
  - 🔴 **Deuda corriente** — lo que el cliente debe ahora.
  - 🔵 **Seña reservada** — Seña activa (ver manual `venta_con_senia.md`).
  - 🟢 **Saldo a favor** — plata del cliente disponible.
  - ⚪ **Estado / Plazo** — Activo / En revisión / Bloqueado +
    días de plazo de pago configurados.
- **Movimientos del cliente** (libro mayor) — todas las operaciones del
  cliente en orden cronológico, con saldos después de cada movimiento.

### Paso 3 — Hacer clic en "Registrar pago"

Si la deuda corriente es > 0, el botón verde **"Registrar pago"** está
habilitado en la esquina superior derecha. Hacer clic.

### Paso 4 — Llenar el modal de pago

Se abre el modal **"Registrar pago — [Cliente]"**:

1. **Tipo de operación:**
   - **Pago de deuda (FIFO)** — el monto se aplica a la deuda más vieja
     primero. Es la opción por defecto si hay deuda.
   - **Adelanto / saldo a favor** — usar solo si el cliente paga sin
     tener deuda, o si quiere dejar plata para futuras compras.

2. **Monto** — cuánto está pagando el cliente. El campo viene
   pre-cargado con la deuda total. Editar si paga menos o más:
   - Si paga **menos** que la deuda → cancela las deudas más viejas
     hasta donde alcance.
   - Si paga **más** que la deuda → cancela todas las deudas y el
     **excedente se acredita como saldo a favor automáticamente**
     (un alert en azul lo avisa).

3. **Método de pago** — cómo paga el cliente: efectivo, transferencia,
   tarjeta de crédito, mercado pago, etc. Por defecto viene "Efectivo".

4. **N° de recibo** — obligatorio. Escribir el número del recibo físico
   o talón que se le entrega al cliente.

5. **Nota** (opcional) — observación libre para auditoría.

### Paso 5 — Confirmar

1. Hacer clic en **"Registrar pago"**.
2. El sistema:
   - Crea el registro de pago en el sistema.
   - Distribuye el monto con FIFO (más vieja primero).
   - Si sobra, lo acredita como saldo a favor.
   - Actualiza los chips del cliente (Deuda baja, Favor sube si hay
     excedente).
   - Registra el movimiento en el ledger del cliente.
3. Aparece un toast verde de confirmación.
4. La pantalla se refresca automáticamente con los nuevos saldos y un
   nuevo movimiento "Pago recibido" en la tabla.

### Paso 6 — Entregar el comprobante

Imprimir o entregar el recibo físico al cliente con el N° que se ingresó.

---

## Casos especiales

### El cliente paga más de lo que debe

Si la deuda es $5.000 y el cliente paga $7.000:
- Las deudas se saldan: $5.000 aplicados.
- Sobran $2.000 → se acreditan como **saldo a favor**.
- El chip 🟢 del cliente sube de 0 a $2.000.

El cliente puede usar ese saldo a favor en su próxima compra
(haciendo clic en "Usar Saldo a favor" en el modal de pago).

### El cliente paga sin tener deuda (adelanto)

1. Tipo de operación → **"Adelanto / saldo a favor"**.
2. Monto que entrega.
3. Método y N° de recibo.
4. Confirmar.

El monto entero va a saldo a favor, sin tocar deudas (porque no hay).

### Pago parcial — el cliente solo paga una parte

Procedimiento normal:
- Monto = lo que efectivamente paga.
- Tipo = "Pago de deuda (FIFO)".

Las deudas más viejas se cancelan en orden. Las más nuevas siguen
abiertas.

### El cliente quiere usar su saldo a favor para saldar deuda

Esto se hace **desde la venta nueva**, no desde Cuentas Corrientes:
1. Abrir Nueva Venta con ese cliente.
2. Ir al modal de pago.
3. Si el cliente tiene saldo a favor, aparece el chip
   "Usar Saldo a favor: $XXX". Hacer clic.

Si el objetivo es solamente "convertir saldo a favor en pago de deuda
sin venta nueva", usar el endpoint `apply_favor` (en versiones
posteriores se agregará el botón visual; por ahora hablar con el
administrador).

### Devolución de mercadería + saldo a favor

Cuando el cliente devuelve una prenda:
1. Hacer la devolución en el módulo de ventas (botón "Devolver Ropa").
2. El sistema acredita el monto como saldo a favor automáticamente.
3. El cliente puede pedir efectivo o usarlo en compras futuras.
4. Para entregar efectivo, registrar como "salida de caja" con el
   monto del saldo, anotando "Devolución a cliente <nombre>" en la nota.

### El cliente dice que ya pagó pero su deuda sigue en el sistema

1. Verificar la tabla **Movimientos del cliente** — todos los pagos
   recibidos están listados con fecha y N° de recibo.
2. Si el pago no aparece, posibles causas:
   - El operador anterior no registró el pago en el sistema.
   - Se registró a otro cliente con nombre similar.
3. Buscar el recibo físico → verificar quién atendió → registrar el
   pago atrasado con la fecha de la nota.

---

## Estado del cliente — qué hacer si está "En revisión" o "Bloqueado"

- **En revisión (chip naranja "EN REVISIÓN"):** se puede cobrar
  normalmente, pero NO se le puede vender más a crédito hasta que el
  administrador lo cambie a Activo.
- **Bloqueado (chip rojo "BLOQUEADO"):** se puede cobrar normalmente,
  pero el cliente no puede comprar a crédito por ningún motivo. Si se
  saldó toda la deuda y el cliente quiere volver a operar, hablar con
  el administrador para cambiar el estado.

Para cambiar el estado del cliente:
1. En la pantalla del cliente (Cuentas Corrientes > [cliente]), hacer
   clic en **"Política"** (esquina superior derecha).
2. En el modal, cambiar el estado y guardar.
3. **Importante:** este cambio queda registrado y solo deberían hacerlo
   admin / gerente.

---

## Errores comunes

| Mensaje | Causa | Solución |
|---|---|---|
| "Indique un número de recibo" | Campo N° de recibo vacío | Escribir el número del talón físico |
| "El monto debe ser mayor a cero" | Monto = 0 | Ingresar un monto > 0 |
| "Cliente sin storeId" | Bug muy raro — sesión inválida | Cerrar sesión y volver a entrar |
| El monto se aplicó pero la deuda no bajó tanto como esperaba | El cliente tenía descuentos o intereses pendientes — FIFO los aplica primero | Revisar la tabla de movimientos para ver el detalle |

---

## Resumen rápido — cobro estándar

1. **Sidebar → Cuentas Corrientes** → buscar al cliente → click.
2. Click en **"Registrar pago"**.
3. Llenar: monto, método, N° de recibo.
4. **"Registrar pago"** → confirmar.
5. Entregar recibo físico al cliente.

Listo. El cliente se va con su deuda actualizada (o saldada).
