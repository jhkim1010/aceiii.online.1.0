# Manual de Materia Prima (VentaGO)

Este manual explica la gestión de materia prima (telas): alta de materiales con variantes de color, compra en rollos o kilos con consumo en metros, movimientos de inventario (consumo, merma, retazos), proveedores y sus pagos.

## 1. Alta de materiales: telas madre y colores

Cada tela se registra una vez como «tela madre» con sus variantes de color. El código de material identifica tela + color.

Pasos:
1. Entre a «Materia prima» y cree la tela con su nombre, composición y proveedor habitual.
2. Agregue los colores de la tela: cada color es una variante con su propio código y stock.
3. Defina la unidad de compra (rollo o kg) y el rendimiento en metros.

## 2. Unidades duales: rollo/kg ↔ metros

Las telas se compran en rollos o kilos, pero la producción consume metros. VentaGO guarda la verdad del stock en la unidad de consumo (metros) y convierte automáticamente al ingresar compras.

Pasos:
1. Al ingresar una compra, cargue la cantidad en la unidad de compra (por ejemplo 3 rollos o 25 kg).
2. El sistema convierte a metros con el rendimiento configurado y suma al stock.
3. Si el rendimiento real difiere (rollo más corto), ajuste los metros al ingresar.

## 3. Ingreso de compra: proveedor, rollos y costo

Cada ingreso registra proveedor, cantidad, costo unitario y fecha, alimentando el stock y la cuenta del proveedor.

Pasos:
1. Cree el ingreso eligiendo proveedor y tela/color.
2. Cargue cantidad (unidad de compra), costo y observaciones (número de remito).
3. Confirme: el stock en metros aumenta y la deuda con el proveedor queda registrada.

## 4. Inventario: consulta de stock de telas

La pantalla de inventario muestra el saldo en metros por tela y color, con su valorización.

Pasos:
1. Filtre por tela, color o proveedor para encontrar el material.
2. Revise el saldo antes de planificar cortes de producción.

## 5. Movimientos: consumo, merma y retazos

Todos los cambios de stock quedan como movimientos: consumo de producción, merma (pérdida) y retazos que vuelven como ajuste.

Pasos:
1. El consumo se genera desde el ticket de corte de talleres (metros usados).
2. La merma registrada se descuenta del stock como pérdida.
3. Los retazos aprovechables se reingresan con un ajuste positivo.

## 6. Proveedores de materia prima

Los proveedores de tela se administran con sus datos de contacto y condiciones, separados de los proveedores de mercadería.

Pasos:
1. Registre el proveedor con nombre, CUIT y contacto.
2. Asocie las telas que le compra para agilizar los ingresos.

## 7. Pagos a proveedores

La sección «Pagos» muestra la deuda por proveedor y permite registrar pagos parciales o totales.

Pasos:
1. Abra «Materia prima → Pagos» y elija el proveedor.
2. Registre el pago con fecha, monto y medio (efectivo, transferencia).
3. El saldo pendiente se actualiza y queda el historial de pagos.

## 8. Códigos de material y etiquetas

Cada tela/color tiene un código propio que puede imprimirse en etiqueta para identificar rollos en el depósito.

Pasos:
1. Consulte el código del material en su detalle.
2. Imprima la etiqueta con el agente Zebra para pegarla en el rollo.
