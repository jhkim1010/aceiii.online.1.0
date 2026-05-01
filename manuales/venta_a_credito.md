# Manual: Cómo vender a crédito

Este manual explica paso a paso cómo registrar una venta a crédito (deuda
del cliente, "fiado", "a cuenta corriente") en Ventago.

---

## Conceptos básicos del crédito

**Crédito (cuenta corriente, fiado, a cuenta)** — el cliente se lleva la
mercadería sin pagar (o pagando solo una parte). Lo que queda se registra
como deuda en su cuenta corriente, y el cliente promete pagar después.

**Seña (reserva, anticipo)** — concepto distinto del crédito. La Seña es
plata que el cliente PAGA por adelantado para reservar una mercadería.
Para Seña usar el manual `venta_con_senia.md`.

**Saldo a favor (favor, crédito a favor)** — plata que el cliente tiene a
su favor en la tienda (por ejemplo, devolvió una prenda y todavía no la
volvió a usar). Solo se aplica si el cliente lo pide explícitamente.

**Política del cliente:**
- `Activo` — acepta nuevas ventas a crédito.
- `En revisión` — está pausado, no acepta nuevas deudas hasta revisión
  del administrador.
- `Bloqueado` — no acepta crédito por ningún motivo (mora muy alta,
  cliente moroso recurrente, etc.).

---

## Requisitos para vender a crédito

1. El cliente debe estar identificado en el sistema con DNI o CUIT
   válidos. Si el cliente nunca compró antes, registrarlo primero (ver
   sección "Cliente nuevo en el momento").
2. El cliente debe estar en estado `Activo`. Si está `En revisión` o
   `Bloqueado`, el método "Crédito" no aparece en la lista de pagos.
3. El monto a fiar no puede superar el límite de crédito del cliente
   (si tiene uno configurado).

---

## Flujo paso a paso — venta a crédito

### Paso 1 — Ingresar al cliente

Hay tres formas de elegir el cliente:

**Opción A — Cliente conocido (CUIT/DNI):**
1. En la pantalla **Nueva Venta**, hacer clic en el campo `Nº CUIT / DNI`.
2. Escribir el CUIT (11 dígitos) o DNI (7-8 dígitos).
3. El sistema busca automáticamente y completa el formulario con los
   datos del cliente.

**Opción B — Cliente conocido por nombre:**
1. En la lista de la derecha, **"Lista de los Clientes"**, escribir parte
   del nombre o documento.
2. Hacer clic en el cliente para seleccionarlo.

**Opción C — Cliente nuevo en el momento (sin CUIT/DNI todavía):**
1. Hacer clic en el campo `Nº CUIT / DNI`.
2. Sin escribir nada, presionar **`Tab`**.
3. El sistema asigna automáticamente un número de serie temporal con
   prefijo de la tienda. Ejemplo: `S9-00001`.
4. El cursor pasa automáticamente al campo `Nombre y Apellido`.
5. Escribir el nombre del cliente y completar la venta normalmente.
6. Más adelante, cuando el cliente traiga su CUIT/DNI real, el
   administrador edita la ficha del cliente y cambia el documento
   temporal por el real (la deuda y todo el historial se mantiene).

### Paso 2 — Verificar la información del cliente

Una vez seleccionado el cliente, en la tarjeta de **Info de Cliente**
aparecen unos chips de colores:

- 🔴 **Deuda** (en rojo) — monto que el cliente debe.
- 🔵 **Seña** (en azul) — monto que el cliente ya pagó por adelantado.
- 🟢 **A favor** (en verde) — saldo a favor del cliente.
- ⚠️ **EN REVISIÓN** o **BLOQUEADO** — si aparece, no se puede vender a
  crédito. Avisar al administrador.

### Paso 3 — Cargar los productos

Agregar los productos a la venta como en cualquier otra venta:
escanear código, elegir talles/colores, ingresar cantidad, etc.

### Paso 4 — Elegir "Crédito" como método de pago

1. Hacer clic en el botón de pagos (o presionar el atajo correspondiente).
2. En el modal **"Agregar Métodos de Pago"**, en el desplegable de método
   buscar **"Crédito"**.
3. **Importante:** "Crédito" solo aparece si el cliente está identificado
   y su estado es `Activo`.
4. Ingresar el monto que queda fiado. Puede ser:
   - **Fiado total** — todo el monto va a crédito (el cliente no paga
     nada en el momento).
   - **Fiado parcial** — el cliente paga una parte en efectivo /
     transferencia / tarjeta, y el resto va a crédito. En ese caso
     agregar dos líneas de pago: la parte cash y la parte Crédito.
5. Confirmar.

### Paso 5 — Aplicar saldo a favor (opcional)

Si el cliente tiene saldo a favor, en la parte superior del modal aparece
un chip clicable: **"Usar Saldo a favor: $XXX"**.

- El saldo a favor **NO se descuenta automáticamente** — se aplica solo
  si el operador hace clic en el chip. Esto es para evitar consumir el
  saldo del cliente sin su autorización.
- Al hacer clic, se agrega una línea de pago "Saldo a favor" por el
  monto que corresponde.

### Paso 6 — Confirmar la venta

1. Verificar que **Total** = suma de pagos (Crédito + cash + favor + ...).
2. Presionar **F2** o el botón **"Generar Venta"** para confirmar.
3. El sistema:
   - Crea la venta normalmente.
   - Suma el monto de Crédito a la deuda corriente del cliente.
   - Registra el movimiento en el ledger (libro mayor) del cliente.
   - Imprime el ticket si está marcado.
4. El operador verá un toast de confirmación.

---

## Casos especiales

### Cliente nuevo, sin CUIT, sin nombre completo

Si el cliente entra apurado y solo da un nombre de pila:
1. `Tab` en CUIT → sistema asigna número temporal.
2. Escribir el nombre de pila (ej: "Juan").
3. Presionar **F2**: el sistema crea automáticamente el cliente temporal
   con el documento temporal y procede con la venta.

Después, cuando el cliente vuelva con su DNI, editar la ficha y poner el
DNI real. La deuda no se pierde.

### Cliente con deuda alta — quiere fiar más

1. Verificar el chip rojo de deuda en la tarjeta del cliente.
2. Si el monto + nueva venta supera el límite de crédito, el sistema
   rechaza el método "Crédito" automáticamente con un mensaje de error.
3. Hablar con el cliente:
   - Que pague una parte de la deuda primero (ver `cobro_credito.md`).
   - O esperar a que el administrador suba el límite del cliente.

### Cliente bloqueado — quiere fiar igual

NO hacer la venta a crédito. Si el cliente insiste:
- Avisar al administrador / dueño de la tienda.
- Solo el administrador puede cambiar el estado del cliente desde el
  módulo **Cuentas Corrientes** > Política del cliente.

### Vender con seña en lugar de crédito

Si el cliente quiere reservar una mercadería pagando una parte por
adelantado, eso es **Seña**, no crédito. Ver el manual
`venta_con_senia.md`.

---

## Suspender una venta a crédito

Si el cliente está apurado o falta algún dato:
1. Hacer clic en el botón **Suspender**.
2. La venta queda pendiente con todos los datos guardados (cliente,
   productos, vendedor, provincia).
3. Cuando el cliente vuelva, abrir la lista **"Ventas Suspendidas"** en
   la columna derecha y hacer clic en su venta para retomarla.
4. Continuar con el flujo normal de pago a crédito.

---

## Errores comunes

| Mensaje | Causa | Solución |
|---|---|---|
| "Crédito" no aparece en métodos de pago | Cliente no seleccionado, o estado distinto de `Activo` | Verificar tarjeta del cliente, hablar con admin si está bloqueado |
| "Cliente sin documento válido" | El cliente legacy no tiene DNI/CUIT | Editar ficha del cliente y agregar el documento, o usar Tab para asignar temporal |
| "Excede el límite de crédito" | Suma de deuda + nueva venta > límite | Cobrar antes, o pedir al admin que aumente el límite |
| Aparece "Consumidor Final" en lugar del nombre | El operador no seleccionó al cliente — la venta sale anónima | Seleccionar cliente primero, o usar Tab + F2 para crear temporal |

---

## Resumen rápido — cliente nuevo, fiado total

1. Click en CUIT → `Tab` → número temporal.
2. Escribir nombre.
3. Cargar productos.
4. Pagos → "Crédito" → monto total.
5. **F2** → confirmar.

Listo. El cliente se va con la mercadería y el sistema sabe cuánto debe.
