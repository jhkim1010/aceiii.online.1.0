# Manual de Ventas (VentaGO)

Este manual explica el flujo completo de ventas en VentaGO: desde el inicio de sesión hasta el cierre de caja, incluyendo ventas con variantes (código madre), medios de pago, ventas suspendidas y el modo restaurante. Cada tema incluye capturas de pantalla reales del sistema.

## 1. Iniciar sesión y registro de terminal

VentaGO permite una sola sesión activa por usuario. La primera vez que se usa una computadora nueva o una conexión de internet nueva, el sistema pide registrar el terminal y la sucursal.

Pasos:
1. Abra el navegador y entre a app.coolsistema.com. Ingrese su usuario y contraseña.
2. Si es la primera vez en esta PC, aparecerá el aviso de registro de terminal: elija la sucursal y la caja que corresponden a este puesto.
3. Si la conexión de internet es nueva, el sistema pedirá asociar la IP a una sucursal. Confirme con el administrador antes de registrar.
4. Si aparece el mensaje «Sesión expirada», significa que alguien inició sesión con su usuario en otro equipo. Vuelva a iniciar sesión; la otra sesión se cerrará automáticamente.

Consejo: No comparta su usuario: cada vendedor debe tener el suyo, porque las ventas y la caja se registran por usuario.

## 2. Pantalla Nueva Venta: buscar y agregar artículos

La pantalla «Nueva venta» es el punto de venta (POS). Permite buscar artículos por código, por nombre o con lector de código de barras.

Pasos:
1. Entre al menú «Nueva venta». El cursor queda en el campo de búsqueda: escanee el código de barras o escriba el código o nombre del artículo.
2. Seleccione el artículo en la lista de resultados. Se agrega al carrito con cantidad 1.
3. Para cambiar la cantidad, edite el número en la columna de cantidad. Para quitar un artículo, use el ícono de eliminar de esa fila.
4. El total se actualiza automáticamente a medida que agrega artículos.

Consejo: Si el artículo no aparece, verifique con el administrador si está cargado y publicado para su sucursal.

## 3. Vender con código madre (color × talla)

Los productos con variantes se manejan con un «código madre». Al seleccionarlo, se abre la tabla de variantes para cargar cantidades por cada combinación de color y talla.

Pasos:
1. Busque el producto por su código madre o nombre y selecciónelo.
2. En la tabla de variantes (colores en filas, tallas en columnas) escriba la cantidad de cada combinación que lleva el cliente.
3. Confirme: las variantes se agregan a la venta. El sistema descuenta el stock de cada variante por separado.

Consejo: Aunque una variante figure sin stock, la venta no se bloquea: el stock puede quedar negativo y se corrige luego con un ajuste.

## 4. Niveles de precio, descuentos y promociones

Cada artículo puede tener varios niveles de precio (por ejemplo: minorista, mayorista). Además se pueden aplicar descuentos y promociones en la venta.

Pasos:
1. En la venta, seleccione el tipo de precio que corresponde al cliente (si su rol lo permite).
2. Para aplicar un descuento, use el campo de descuento del artículo o del total, según lo habilitado por el administrador.
3. Las promociones activas (por ejemplo 2×1) se aplican automáticamente y los artículos bonificados aparecen marcados.

## 5. Medios de pago y pago mixto

Al generar la venta se elige el medio de pago: efectivo, QR de MercadoPago, cuenta corriente (crédito), saldo a favor, u otros configurados. También se puede dividir el pago entre varios medios.

Pasos:
1. Presione «Generar venta». Se abre el modal de pago con el total.
2. Elija el medio de pago. Para efectivo, ingrese el monto recibido y el sistema calcula el vuelto.
3. Para QR MercadoPago, muestre el código al cliente y espere la confirmación automática del pago.
4. Para pago mixto, cargue un monto por cada medio hasta cubrir el total.
5. Para venta a cuenta corriente (crédito), seleccione el cliente registrado; la deuda queda asociada a su cuenta.

Consejo: El ticket se imprime automáticamente si la comandera está configurada (vea el tema de impresión).

## 6. Suspender y retomar una venta

Si el cliente necesita interrumpir la compra (por ejemplo, va a buscar otro producto), la venta puede suspenderse y retomarse después sin perder los artículos cargados.

Pasos:
1. Con artículos en el carrito, presione «Suspender venta». La venta queda guardada en la lista de suspendidas.
2. Para retomarla, abra la lista de ventas suspendidas y seleccione la venta. Los artículos vuelven al carrito.
3. Complete la venta normalmente con «Generar venta».

## 7. Historial: anular, devolver y reimprimir

El menú «Ventas» muestra el historial. Desde ahí se puede ver el detalle, anular una venta, registrar devoluciones y reimprimir tickets.

Pasos:
1. Entre al menú «Ventas» y filtre por fecha, sucursal o vendedor para encontrar la operación.
2. Abra el detalle para ver artículos, pagos y estado de la venta.
3. Para anular o devolver, use la acción correspondiente; el stock se reintegra automáticamente.
4. Para reimprimir el ticket, use el botón de impresión de la fila.

Consejo: Las anulaciones pueden requerir permiso de administrador según la configuración de su tienda.

## 8. Apertura y cierre de caja

La caja registra todo el movimiento de dinero del turno: apertura con monto inicial, ventas, gastos, retiros y cierre con arqueo.

Pasos:
1. Al comenzar el turno, abra la caja desde el menú «Caja» ingresando el monto inicial (fondo de caja).
2. Durante el día, las ventas en efectivo se suman automáticamente. Registre también gastos o retiros si corresponde.
3. Al cerrar, cuente el efectivo físico y cargue el monto: el sistema muestra la diferencia contra lo esperado.
4. El sobrante que se retira puede transferirse a la caja fuerte, donde queda registrado.

Consejo: El menú «Control de caja» permite al encargado revisar aperturas, cierres y diferencias de todas las cajas.

## 9. Modo restaurante: salón y mesas

En tiendas con modo restaurante, la venta se organiza por mesas en el plano del salón. Los colores indican el estado: libre, ocupada o por cobrar.

Pasos:
1. Al entrar a «Nueva venta» en una tienda restaurante se abre el salón con las mesas.
2. Toque una mesa libre u ocupada para tomar o modificar el pedido (comanda). El pedido se envía a la comandera de cocina.
3. Cuando la comida sale, marque «Servido». La mesa pasa a «Por cobrar» y muestra el tiempo de espera del pago.
4. Toque la mesa en rojo para cobrar. Se puede unir el pago de varias mesas si el cliente lo pide.

Consejo: El panel derecho «Resumen» muestra mesas activas, platos por servir y montos en tiempo real.

## 10. Impresión de tickets (comandera)

La impresión usa el agente de impresión instalado en una PC de la sucursal. Cada terminal puede tener asignada su propia impresora.

Pasos:
1. Verifique el indicador de impresora en el POS: verde significa agente conectado.
2. Al generar la venta, el ticket sale por la impresora asignada al terminal. Si no hay asignación, imprime la comandera general de la sucursal.
3. Si el ticket no sale, avise al administrador para revisar el agente (prueba de impresión desde Sucursales → Impresora).

Consejo: La venta queda registrada aunque falle la impresión: siempre se puede reimprimir desde el historial.
