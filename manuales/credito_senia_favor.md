# Manual de Cuenta Corriente — Crédito · Seña · Favor

Este manual describe cómo operar la cuenta corriente de los clientes en
Ventago: ventas a crédito, registro de señas (reservas) y manejo del saldo
a favor.

## Conceptos básicos

En Ventago la cuenta corriente del cliente tiene tres bolsillos separados:

- **Crédito (deuda)**: el cliente se llevó la mercadería y pagará después.
  Se acumula hasta el límite autorizado y tiene fecha de vencimiento.
  Columna en DB: `store_clients.balance`.
- **Seña (reserva)**: el cliente paga adelantado para reservar una venta
  específica (ej: un sofá a entregar). Está atada a esa venta hasta
  retirarla. Columna: `store_clients.senia_balance`.
- **Favor (saldo libre)**: dinero del cliente que está en la tienda sin
  asignar a ninguna venta. Se puede usar en su próxima compra (con su
  consentimiento). Columna: `store_clients.favor_balance`.

**REGLA DE ORO:** los tres saldos son INDEPENDIENTES. Un cliente puede tener
al mismo tiempo $50.000 de deuda + $80.000 reservados como seña + $5.000
libres como favor. Cada uno se mueve por separado.

Todos los movimientos quedan registrados en `credit_ledger` (libro mayor
inmutable, append-only).

## Requisitos para crédito y seña

**SIN DNI/CUIT NO HAY CRÉDITO NI SEÑA.** Si el cliente quiere comprar a
crédito o dejar una seña, primero hay que cargar el documento. El sistema
bloquea la operación si el cliente no tiene documento válido.

**Documentos aceptados:**

- DNI: 7 u 8 dígitos numéricos — válido para crédito y seña.
- CUIT/CUIL: 11 dígitos con dígito verificador correcto (mod-11) — válido.
- Pasaporte: alfanumérico — solo con autorización del supervisor.
- Sin documento: NO permite crédito ni seña, solo ventas en efectivo.

**Estados del cliente (credit_status):**

- `active`: cliente normal, todas las operaciones permitidas.
- `hold`: en revisión. Pausa temporal. Solo recibir pagos. No hay nuevo
  crédito ni seña.
- `blocked`: suspendido permanentemente (mora dura, cheque rechazado).
  Solo recibir pagos.

## Cómo vender a crédito

Cuando el cliente se lleva la mercadería sin pagar todo:

1. Abrir Nueva Venta y agregar los productos al carrito.
2. Seleccionar el cliente (botón "Cambiar cliente"). Si no existe,
   registrarlo con DNI o CUIT primero.
3. En Forma de Pago, agregar **Crédito (cuenta corriente)**. El monto se
   carga automáticamente con la diferencia que falta cobrar.
4. Verificar la fecha de vencimiento (default: 30 días). Se puede cambiar
   hasta 90 días sin autorización; más requiere supervisor.
5. Si el cliente paga una parte ahora (efectivo, tarjeta), agregar también
   esa forma de pago. La parte restante va a crédito.
6. Confirmar venta con `F12`.

**Atención al límite de crédito:** si la deuda actual + esta venta supera
el límite del cliente, el sistema bloquea la operación. Soluciones:

- Pedir un pago parcial al cliente para bajar la deuda primero.
- Llamar al supervisor para autorización con PIN (`F11`).

## Cómo registrar una Seña

Cuando el cliente quiere reservar un producto que se llevará después
(mueble a entregar, encargo, producto de proveedor):

1. Ir a "Seña / Reservas" en el menú lateral, o usar el botón "+ Nueva Seña"
   desde la ficha del cliente.
2. Cargar el producto, cantidad y precio estimado.
3. Indicar la fecha estimada de retiro (referencia, no bloquea nada).
4. Cargar el monto de Seña que el cliente deja ahora. Sugerencias rápidas:
   30%, 50%, 70% del total.
5. Elegir la forma de cobro de la seña (efectivo, transferencia, tarjeta).
6. Confirmar e imprimir el recibo. La venta queda en estado "Borrador"
   hasta que vaya a retirar.

**IMPORTANTE:** el dinero de la seña NUNCA se mezcla con la deuda del
cliente. Si el cliente cancela la reserva, hay que devolverlo o pasarlo
a favor.

Backend: registra en `sale_senias` (status=active) + `credit_ledger`
movement_type=`senia_in`. Sale se crea con status=DRAFT.

## Cómo aplicar Seña al confirmar venta

Cuando el cliente vuelve a retirar lo que reservó:

1. Buscar la venta reservada en "Reservas activas" del cliente o en el
   panel de Señas pendientes.
2. Hacer clic en "Confirmar venta" sobre esa reserva. Se carga al carrito
   con todos los productos y precios originales.
3. Ajustar precios o cantidades si hubo cambios desde la reserva (ej:
   cambio de talle).
4. En Forma de Pago, el sistema agrega automáticamente "Seña existente"
   con el monto que el cliente había dejado.
5. Cobrar la diferencia en efectivo, tarjeta o crédito según corresponda.
6. Confirmar venta con `F12`.

**Casos especiales:**

- Seña = Total: la venta se cobra completa solo con la seña, sin diferencia.
- Seña < Total: la diferencia se cobra como una venta normal.
- Seña > Total (producto salió más barato): el sobrante se puede pasar a
  favor del cliente o devolver en efectivo. Decisión del supervisor.

Backend: ledger registra `senia_apply`, `sale_senias.status` pasa a
`applied`.

## Cómo usar el saldo a favor del cliente

**POLÍTICA IMPORTANTE:** el favor del cliente NO se aplica automáticamente.
Es plata del cliente, así que el sistema solo lo informa y el cajero debe
preguntarle si quiere usarlo.

Cuando el cliente tiene saldo a favor disponible, al abrir la pantalla de
venta aparece un aviso violeta arriba del módulo de pagos:

> 💰 Este cliente tiene $X a favor disponible. ¿Quiere usarlo en esta venta?

**Pasos:**

1. Preguntar al cliente: "¿Querés usar tu saldo a favor en esta compra?"
2. Si dice **sí**: tocar `F9` o el botón "Usar favor". Se agrega como forma
   de pago.
3. Se puede ajustar el monto a usar (no necesariamente todo el favor).
4. Si dice **no**: tocar "No usar" o cerrar el aviso. El favor queda
   intacto para la próxima compra.

Backend: ledger registra `favor_apply` con el monto explícito que el
cliente decidió usar. Si `favor_balance < monto pedido` →
`BadRequestException`.

## Cómo cobrar una deuda existente (FIFO)

Cuando el cliente viene a pagar lo que debía:

1. Buscar al cliente en "Cuenta corriente" o desde la ficha del cliente.
2. Hacer clic en "+ Registrar pago".
3. Cargar el monto recibido. Botones rápidos: "Cancelar deuda total",
   "+ $50.000", etc.
4. Elegir la forma de cobro (efectivo, transferencia, tarjeta, cheque).
5. El sistema muestra la distribución automática FIFO: aplica el dinero
   a las ventas a crédito MÁS ANTIGUAS primero. Si sobra, queda en favor
   del cliente.
6. Confirmar e imprimir recibo. El cliente se lleva su comprobante.

**Tipos de cobro disponibles (paymentKind):**

- **Pago de crédito (FIFO)**: el cliente trae plata para bajar la deuda.
  El sobrante queda en favor.
- **Adelanto a Favor**: el cliente quiere dejar plata sin tener deuda
  actual. Va directo al favor.
- **Aplicar favor a deuda**: el cliente tiene favor y deuda al mismo
  tiempo y quiere usar el favor para bajar la deuda. SIEMPRE con
  autorización del cliente.

Backend: cada pago genera 1 fila en `credit_payments` + N filas en
`credit_ledger` (movement_type=`payment_in` para cada venta saldada,
`favor_in` para sobrante).

## Cómo cancelar una Seña

Si el cliente cancela la reserva, hay dos opciones:

**Pasos:**

1. Buscar la Seña activa en la ficha del cliente o en "Reservas activas".
2. Hacer clic en "Cancelar Seña" sobre esa reserva.
3. Elegir una de las dos opciones:
   - **Devolución en efectivo**: se entrega el dinero al cliente. Sale
     plata de la caja.
   - **Pasar a favor**: el dinero queda en el favor del cliente para usar
     en otra compra. No sale plata de la caja.
4. Confirmar e imprimir comprobante.

**Recomendación:** ofrecer siempre primero "pasar a favor" — es más rápido
para el cliente y no afecta la caja. Solo devolver en efectivo si el
cliente lo pide explícitamente.

Backend:

- Devolución → ledger `movement_type=senia_refund` + `sale_senias.status=refunded`.
- Pasar a favor → ledger pareado: `senia_to_favor` + `favor_in` (mismo
  monto). `sale_senias.status=converted`.

## Errores comunes y soluciones

Mensajes de error que el sistema puede mostrar al operar a
crédito/seña/favor:

- **CRÉDITO requiere DNI/CUIT del cliente**: el cliente no tiene documento
  cargado. *Solución:* editar el cliente, agregar DNI o CUIT, reintentar
  la venta.
- **Documento '...' inválido**: el DNI/CUIT cargado no tiene el formato
  correcto. *Solución:* revisar que el DNI tenga 7-8 dígitos numéricos,
  o que el CUIT tenga 11 dígitos con el verificador correcto (mod-11).
- **Cliente bloqueado para nuevas operaciones a crédito**: el cliente
  está marcado como Bloqueado. *Solución:* solo el supervisor puede
  liberar al cliente. Hasta entonces, solo recibir pagos.
- **Cliente en revisión (hold)**: cliente en pausa temporal. *Solución:*
  pedir autorización al supervisor o esperar que se libere.
- **Límite de crédito excedido**: la deuda actual + esta venta superaría
  el límite del cliente. *Solución:* pedir un pago parcial al cliente, o
  autorización del supervisor.
- **Favor insuficiente**: se quiso usar más favor del que el cliente
  tiene. *Solución:* ajustar el monto al favor disponible o cobrar la
  diferencia con otra forma de pago.
- **SEÑA requiere DNI/CUIT**: la seña también necesita documento.
  *Solución:* cargar DNI/CUIT en la ficha del cliente antes de registrar
  la seña.
- **Seña insuficiente**: se intentó aplicar más seña de la que estaba
  disponible para esa venta. *Solución:* verificar el monto original de
  la seña en la reserva.

## Preguntas frecuentes

**¿Qué pasa si el cliente paga más de lo que debe?**
El sobrante queda automáticamente en su FAVOR. El sistema lo informa en
la pantalla de cobro antes de confirmar.

**¿Puedo aplicar el favor de un cliente a otro?**
NO. El favor es del cliente y solo puede usarse en sus propias compras.
No es transferible.

**¿Puedo cobrar una seña que no es de este cliente?**
NO. Cada seña está atada al cliente y a la venta específica donde se
reservó.

**¿La seña tiene fecha de vencimiento?**
No automática, pero el sistema avisa cuando una seña está activa hace más
de 30 días desde la fecha de retiro estimada. En ese caso conviene
contactar al cliente o pasar la seña a favor.

**¿Qué pasa si registré una venta a crédito por error?**
NO se puede borrar el movimiento del libro mayor (es histórico). Hay que
generar un movimiento INVERSO: registrar un pago o un ajuste del mismo
monto, con la nota explicando el error. El supervisor debe autorizar
este tipo de ajustes.

**¿El cliente puede ver su cuenta corriente?**
SÍ. En el panel del cajero hay una opción para imprimir el "Resumen de
cuenta corriente" del cliente con todos sus movimientos: ventas a crédito,
pagos, señas, favor.

**¿Cómo se diferencia el favor de la seña en el reporte?**
En "Cuentas por cobrar" hay tres columnas separadas: Crédito (deuda),
Seña (atada a venta específica), Favor (libre). En modo "Unificado"
(algunas sucursales), se muestran sumadas como "Saldo a favor", pero el
detalle siempre está disponible al abrir cada cliente.

**¿Qué teclas rápidas hay en la pantalla de venta?**
`F2`=productos · `F9`=usar favor (toggle) · `F10`=todo a crédito ·
`F11`=PIN de supervisor · `F12`=confirmar venta.
