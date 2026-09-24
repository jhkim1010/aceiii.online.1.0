Revisé el commit y los cinco archivos completos. No encontré un `CRITICAL` ni un bucle de render reproducible, pero sí tres defectos concretos y un riesgo de concurrencia.

## Hallazgos

- **HIGH — El cambio de total no se reparte cuando existe una sola línea no-efectivo.**  
  [InvoiceAditional.tsx:166](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/ventago-app/src/views/homes/components/ProductList/components/InvoiceAditional.tsx:166) y [InvoiceAditional.tsx:214](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/ventago-app/src/views/homes/components/ProductList/components/InvoiceAditional.tsx:214)

  La rama `paymentMethods.length === 1` retorna antes de llamar a `repartirCambioDeTotal`. Solo sincroniza la línea si su monto era exactamente el total anterior.

  Secuencia:

  1. Total 10.000.
  2. Única línea: Banco 6.000.
  3. Se agrega un producto y el total pasa a 20.000.
  4. Como `6.000 !== 10.000`, `seguiaAlTotal` es falso.
  5. Banco queda en 6.000 en vez de absorber la diferencia y quedar en 16.000.

  Esto cobra de menos si otra validación permite continuar, o al menos deja la venta inesperadamente incompleta. La regla solicitada habla de “la fila más abajo con plata que no sea efectivo”, no exige que haya dos líneas. La función pura ya soporta este caso; la integración no la llama.

- **HIGH — Un método retirado o renombrado puede dejar plata fantasma que el combo no puede eliminar.**  
  [PagoInline.tsx:116](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/ventago-app/src/views/homes/components/ProductList/components/PagoInline.tsx:116)

  Para limpiar un método que salió de las ranuras se vuelve a buscar en el catálogo:

  ```ts
  paymentMethodsCatalog.find((m) => slugDe(m) === sl)
  ```

  Si la ranura persistida o un borrador contiene un slug que ya no está disponible, `find` devuelve `undefined`. `ponerMontoEnLista(lista, undefined, 0)` deliberadamente no cambia nada.

  Resultado: al reemplazar esa ranura, la línea vieja sigue en `paymentMethods`, continúa sumando en “Pagado” y puede viajar al backend, pero ya no aparece en ninguna fila editable. Es plata que desaparece visualmente sin desaparecer del cobro. La limpieza debe hacerse por slug directamente, aunque el método ya no esté en el catálogo.

- **MEDIUM — `localStorage` puede iniciar la caja con métodos duplicados, efectivo en filas inferiores o más/menos de tres ranuras.**  
  [SaleProductsContext.tsx:14](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/ventago-app/src/views/homes/hook/SaleProductsContext.tsx:14)

  `leerRanurasPago` acepta cualquier array y solo ejecuta `String(x)`. No valida:

  - cantidad de elementos;
  - slugs duplicados;
  - `efectivo`;
  - strings vacíos;
  - mayúsculas o espacios;
  - métodos que dejaron de existir.

  `reasignarRanuras` evita la colisión provocada por una selección nueva, pero no sanea todas las colisiones preexistentes. Por ejemplo, `["banco","banco","mercadopago"]` puede montar dos filas Banco. Ambas muestran y editan la misma línea; cambiar una altera la otra y el derrame puede saltar o pisar importes de manera difícil de explicar.

- **MEDIUM — Las escrituras del monto y del derrame usan snapshots de React y pueden perder una actualización concurrente.**  
  [PagoInline.tsx:90](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/ventago-app/src/views/homes/components/ProductList/components/PagoInline.tsx:90) y [PagoInline.tsx:200](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/ventago-app/src/views/homes/components/ProductList/components/PagoInline.tsx:200)

  Tanto la escritura como el `blur` hacen:

  ```ts
  setPaymentMethods(funcion(paymentMethods, ...))
  ```

  Las dos calculan sobre `paymentMethods` capturado por el render. Si coinciden en un mismo batch con otra escritura —por ejemplo una actualización de AutoEfectivo provocada por un cambio de total— la última asignación puede reconstruir la lista desde un snapshot anterior y pisar la otra.

  Deberían ser actualizaciones funcionales:

  ```ts
  setPaymentMethods(prev => ponerMontoEnLista(prev, metodo, monto))
  setPaymentMethods(prev => derramarResto(prev, filas, indice, total))
  ```

  Esto es especialmente importante porque las antiguas dos escrituras desde el mismo snapshot ya habían causado el defecto de “plata que reaparece” documentado en el propio commit.

## AutoEfectivo contra el `blur`

En el recorrido normal no se duplican: el `blur` completa hasta el total visible y luego `repartirCambioDeTotal` aplica solamente el delta del total; además `totalAnteriorRef` corta una segunda aplicación.

Pero sí pueden pelearse en una actualización batched porque ambos escriben arrays completos calculados desde estados capturados. El resultado depende del orden de commit: el derrame puede borrar el reparto de cambio de total, o AutoEfectivo puede borrar el último monto editado. No vi un bucle infinito: `totalAnteriorRef` se actualiza antes del rerender provocado por `setPaymentMethods`, por lo que la siguiente ejecución obtiene delta cero.

## Hueco de los 49 tests

Una mutación que no mataría ninguno de los 49 tests de `pago-inline.spec.ts` es:

```diff
- if (paymentMethods.length >= 2) {
+ if (paymentMethods.length >= 3) {
```

Incluso se podría eliminar por completo la llamada a `repartirCambioDeTotal` dentro de `InvoiceAditional` y esos 49 tests seguirían verdes: solo prueban la función pura, no que el efecto realmente la invoque. Esa mutación rompe el caso cotidiano de dos líneas —por ejemplo Efectivo + Banco— que es justamente el ejemplo principal del cambio.

También faltan pruebas de integración para:

- una única línea no-efectivo parcial al cambiar el total;
- `blur` y cambio de total en el mismo batch;
- ranuras corruptas o duplicadas restauradas desde `localStorage`;
- limpieza de una línea cuyo slug ya no existe en el catálogo.