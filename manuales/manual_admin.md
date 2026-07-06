# Manual de Administración (VentaGO)

Este manual está dirigido a dueños y administradores. Cubre la estructura de la tienda (sucursales, cajas, terminales), la gestión de usuarios y permisos, la seguridad de sesiones, los gastos, los agentes de impresión y los tableros de control.

## 1. Estructura: tienda → sucursal → caja → terminal

VentaGO organiza la operación en cuatro niveles: la tienda (empresa), sus sucursales, las cajas de cada sucursal y los terminales (puestos) de cada caja. Al crear una sucursal, se genera automáticamente una caja y un terminal por defecto.

Pasos:
1. Entre a «Sucursales» para ver y administrar las sucursales de la tienda.
2. Cree una sucursal nueva con su nombre y dirección; la caja y el terminal por defecto se crean solos.
3. Agregue cajas o terminales adicionales solo si la sucursal tiene más de un puesto de cobro.

Consejo: El terminal es la unidad a la que se asignan impresoras (comandera y Zebra).

## 2. Usuarios, roles y permisos

Cada empleado tiene su usuario con un rol (vendedor, gerente, administrador…). El rol define qué menús y acciones puede usar.

Pasos:
1. Entre a «Usuarios» y cree el usuario con su correo, nombre y sucursal asignada.
2. Asigne el rol adecuado. Los permisos finos (por función) se administran en la pantalla de roles.
3. Para dar de baja a un empleado, desactive su usuario: el historial de sus operaciones se conserva.

Consejo: Dé permisos de anulación de ventas y ajustes de stock solo a encargados.

## 3. Seguridad de sesión: dispositivos e IPs

VentaGO bloquea el doble inicio de sesión: al entrar desde otro equipo, la sesión anterior se cierra. Además, cada computadora (huella del navegador) y cada conexión (IP pública) deben estar registradas.

Pasos:
1. Cuando un empleado usa una PC nueva, el sistema pide registrar el terminal: verifique que la sucursal elegida sea correcta.
2. Cuando cambia el internet de la sucursal (IP nueva), autorice el registro de la IP.
3. Ante avisos de «sesión expirada» frecuentes, revise si dos personas comparten el mismo usuario.

## 4. Configuración de la tienda: logo y datos

En «Configuración» se cargan el logo, el alias comercial y los datos de la tienda que aparecen en la barra lateral y en los tickets.

Pasos:
1. Suba el logo (imagen cuadrada recomendada): se muestra en la barra lateral y en la pantalla de inicio de sesión de su equipo.
2. Complete alias, dirección y datos fiscales usados en la impresión de tickets.

## 5. Gastos: categorías y registro

El módulo «Gastos» registra las salidas de dinero (alquiler, servicios, compras menores) con su categoría, para verlas luego en los reportes financieros.

Pasos:
1. Defina primero las categorías de gasto (alquiler, luz, limpieza…).
2. Registre cada gasto con fecha, monto, categoría y sucursal; adjunte comprobante si corresponde.
3. Los gastos pagados desde la caja se descuentan del arqueo del día.

## 6. Agentes de impresión (comandera y Zebra)

Los agentes son programas instalados en una PC de la sucursal que conectan las impresoras con VentaGO: el agente térmico imprime tickets/comandas y el agente Zebra imprime etiquetas. Cada agente se autentica con su API Key.

Pasos:
1. En «Sucursales → Impresora», cree el agente (térmico o Zebra) con una etiqueta descriptiva: se genera su API Key.
2. Instale la app del agente en la PC de la sucursal (menú Descargas) e ingrese solo la API Key.
3. Verifique el estado «en línea» y haga una impresión de prueba desde la misma pantalla.
4. Asigne en cada terminal qué agente térmico y qué agente Zebra usa (mapeo por terminal).

Consejo: Una sucursal puede tener varios agentes (por ejemplo comandera de cocina y de barra).

## 7. Clientes: cuentas corrientes y créditos

Los clientes registrados pueden comprar a cuenta corriente (crédito) y mantener saldo a favor. El módulo de cuentas corrientes muestra deudas, pagos y movimientos.

Pasos:
1. Registre al cliente con su documento (CUIT/DNI) para habilitar cuenta corriente.
2. Consulte la deuda en «Cuentas corrientes» y registre los pagos que el cliente hace.
3. Las devoluciones pueden dejarse como saldo a favor para futuras compras.

Consejo: Cargue siempre el documento del cliente: sin CUIT/DNI válido no se comparte entre sucursales.

## 8. Dashboards: lectura de indicadores

Los tableros muestran ventas por día, sucursal y vendedor, productos más vendidos y evolución de la caja, para decidir con datos.

Pasos:
1. Entre a «Dashboards» y elija el período y la sucursal a analizar.
2. Compare ventas contra días o semanas anteriores para detectar tendencias.

## 9. Auditoría de acciones

El registro de auditoría guarda quién hizo qué y cuándo (altas, cambios de precio, anulaciones), útil para revisar operaciones sensibles.

Pasos:
1. Entre al registro de auditoría y filtre por usuario, módulo o fecha.
2. Revise especialmente anulaciones de ventas y cambios masivos de precios.
