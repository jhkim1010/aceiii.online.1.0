# Manual de Producto (VentaGO)

Este manual explica cómo cargar y administrar productos en VentaGO: productos simples, códigos madre con variantes de color y talla, precios por nivel, reposición de stock, etiquetas de código de barras y publicación en la tienda online.

## 1. Alta de producto simple

Un producto simple no tiene variantes. Se carga desde el menú «Productos» con sus datos básicos, precios y stock inicial.

Pasos:
1. Entre a «Productos» y presione el botón de nuevo producto.
2. Complete los datos básicos: nombre, categoría, temporada, origen y proveedor. El SKU se genera automáticamente con el prefijo configurado.
3. Cargue los precios de cada nivel habilitado (por ejemplo Precio 1 minorista, Precio 2 mayorista).
4. Indique el stock inicial por sucursal si corresponde y guarde.

Consejo: Active «publicar» solo cuando el artículo esté listo para venderse.

## 2. Código madre y variantes (colores × tallas)

El código madre agrupa un modelo con todas sus combinaciones de color y talla. Cada combinación es una variante con su propio código y stock.

Pasos:
1. En el alta de producto, marque la opción de código madre (códigos madres).
2. Seleccione los colores y las tallas del modelo: el sistema genera la matriz de variantes.
3. Cargue las cantidades por combinación en la tabla de variantes y guarde.
4. Para reponer stock de un modelo existente, seleccione su código madre: el formulario se completa solo y solo debe cargar las cantidades nuevas.

Consejo: Si al crear artículos nuevos no aparecen tallas o colores nuevos, actualice la página para recargar los catálogos.

## 3. Catálogos: categorías, tallas, colores y más

Los catálogos (categorías, subcategorías, tallas, colores, temporadas, orígenes, proveedores) se administran una sola vez y se reutilizan en todos los productos.

Pasos:
1. Entre a la configuración de productos para administrar cada catálogo.
2. Agregue los valores nuevos (por ejemplo una talla o un color) antes de cargar los productos que los usan.
3. Evite duplicados con distinta escritura (por ejemplo «Rojo» y «ROJO»): dificultan los reportes.

## 4. Imágenes del producto

Cada producto puede tener imágenes que se muestran en el POS y en la tienda online.

Pasos:
1. En la edición del producto, use la sección de imágenes para subir los archivos (JPG o PNG).
2. La primera imagen es la principal: se usa como miniatura en listados y en la tienda.

Consejo: Use fotos cuadradas y livianas (menos de 1 MB) para que las pantallas carguen rápido.

## 5. Gestión de precios

El menú «Precios» permite ajustar precios de forma masiva: por porcentaje, por monto fijo, por categoría o por código madre (todas las variantes juntas).

Pasos:
1. Entre al menú «Precios» y filtre los artículos a modificar (por categoría, proveedor o código).
2. Elija el tipo de ajuste (porcentaje o monto) y el nivel de precio a modificar.
3. Con código madre, el cambio se aplica a todas las variantes del modelo en una sola operación.
4. Revise la vista previa de los precios nuevos antes de confirmar.

## 6. Reingreso y reposición de stock

Cuando llega mercadería de un modelo ya cargado, no se crea un producto nuevo: se repone stock usando el código madre existente.

Pasos:
1. En el alta/reposición, busque y seleccione el código madre del modelo.
2. El formulario y la matriz de variantes se completan automáticamente con los datos existentes.
3. Cargue solo las cantidades que ingresan por combinación y confirme.

## 7. Etiquetas de código de barras (Zebra)

Las etiquetas se imprimen con el agente Zebra en tres formatos: 50×25 simple, 50×25 doble y 100×25 cartulina.

Pasos:
1. Desde el listado de productos, seleccione los artículos y use «Imprimir x ZPL».
2. Elija el formato de etiqueta y la cantidad por artículo.
3. Confirme la impresora Zebra de destino (agente en línea) y envíe la impresión.

Consejo: Si el agente figura fuera de línea, revise la PC donde está instalado (ícono de la app Zebra Agent).

## 8. Importación masiva de códigos

Para cargas grandes (por ejemplo migración inicial), VentaGO permite importar productos y códigos desde un archivo.

Pasos:
1. Prepare el archivo con el formato indicado en la pantalla de importación (columnas de código, nombre, precios, stock).
2. Suba el archivo y revise la vista previa: el sistema marca filas con errores.
3. Confirme la importación y verifique algunos artículos al azar.

## 9. Publicación en la tienda online

Los artículos publicados aparecen en la tienda online de la marca. La publicación se controla por artículo.

Pasos:
1. En la edición del producto, active la opción de publicación online.
2. Verifique que el artículo tenga imagen, precio y stock: son requisitos para mostrarse bien en la tienda.
3. Para retirar un artículo de la tienda, desactive la publicación (no hace falta borrarlo).

## 10. Parámetros: prefijo de SKU

El prefijo de SKU define cómo empiezan los códigos generados automáticamente (por ejemplo «25» para la temporada 2025).

Pasos:
1. Entre a la configuración de productos → «Parámetros» y edite «Prefijo para SKU».
2. Guarde y verifique creando un producto de prueba: el SKU nuevo debe empezar con el prefijo cargado.

Consejo: Cambiar el prefijo no modifica los códigos ya generados; solo afecta a los productos nuevos.
