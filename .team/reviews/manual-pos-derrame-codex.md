## Hallazgos

- **HIGH — “Quitar” usa estado viejo y puede deshacer la eliminación o agregar un pago inesperadamente.**  
  [PagoInline.tsx:326](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/ventago-app/src/views/homes/components/ProductList/components/PagoInline.tsx:326) y [PagoInline.tsx:385](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/ventago-app/src/views/homes/components/ProductList/components/PagoInline.tsx:385)

  Cada handler ejecuta:

  ```ts
  ponerMonto(metodo, 0)
  derramar(indice)
  ```

  Ambas funciones calculan el nuevo valor desde el mismo `paymentMethods` capturado por el render. Como las actualizaciones de React se agrupan, la segunda puede sustituir a la primera:

  - Si la venta ya está totalmente pagada, `derramarResto` devuelve la lista vieja y la línea reaparece: la ✕ parece no funcionar.
  - Si faltaba dinero, conserva la línea que se quería quitar y además puede completar el resto en la siguiente fila.
  - Esto contradice específicamente el comentario de que la ✕ “lo manda a la siguiente usable”.

  Debe hacerse como una única actualización funcional: primero quitar sobre `prev`, y luego derramar sobre esa lista resultante.

- **HIGH — Al vaciar la única línea, AutoEfectivo la repone antes del blur, por lo que el derrame no sucede y el cajero no recibe explicación.**  
  [PagoInline.tsx:318](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/ventago-app/src/views/homes/components/ProductList/components/PagoInline.tsx:318), [InvoiceAditional.tsx:174](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/ventago-app/src/views/homes/components/ProductList/components/InvoiceAditional.tsx:174), [InvoiceAditional.tsx:186](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/ventago-app/src/views/homes/components/ProductList/components/InvoiceAditional.tsx:186)

  `ponerMontoEnLista(..., 0)` elimina la única línea. AutoEfectivo observa `paymentMethods.length === 0`; como una edición inline no marca `manuallyEditedRef`, vuelve a crear Efectivo por el total completo.

  Caso concreto:

  1. Efectivo = 20.000.
  2. El cajero borra el contenido esperando que los 20.000 bajen a Banco.
  3. AutoEfectivo restaura Efectivo = 20.000.
  4. Al producirse el blur, el monto vuelve a coincidir con el capturado al enfocar, así que [PagoInline.tsx:224](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/ventago-app/src/views/homes/components/ProductList/components/PagoInline.tsx:224) no derrama.

  En una única línea Banco/Crédito, vaciarla puede además reemplazar silenciosamente el método por Efectivo.

- **MEDIUM — Una línea parcial restaurada puede ser sobrescrita por AutoEfectivo en el primer efecto.**  
  [InvoiceAditional.tsx:160](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/ventago-app/src/views/homes/components/ProductList/components/InvoiceAditional.tsx:160)

  Cuando `totalAnteriorRef.current === null`, cualquier línea única se considera automáticamente “seguía al total”. Aunque el efecto anterior marque el borrador como editado, esta rama no consulta `manuallyEditedRef` ni `draftWasRestored`.

  Por ejemplo, un borrador de 20.000 con una sola línea de 10.000 puede convertirse silenciosamente en 20.000. Este código precede al commit revisado, pero se cruza directamente con el nuevo flujo y puede borrar el monto cargado por el cajero.

- **LOW — El motivo del bloqueo deja de estar disponible para navegación por teclado/táctil.**  
  [PagoInline.tsx:348](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/ventago-app/src/views/homes/components/ProductList/components/PagoInline.tsx:348)

  El tooltip deshabilita sus listeners de foco y touch y sólo se abre con `onMouseEnter`. Un cajero que llega con teclado, o trabaja en pantalla táctil, ve la fila deshabilitada pero no puede obtener el motivo.

## `montoAlEnfocar === null`

No encontré un camino normal de escritura manual donde `onChange` ocurra sin un `focus` previo. Las actualizaciones externas —atajos, modal, AutoEfectivo— sí pueden cambiar el valor con el ref en `null`, pero no deberían considerarse ediciones de esa fila.

El problema práctico no es tanto un navegador saltándose `focus`, sino que las acciones programáticas “Quitar” eluden completamente esta protección y tienen la carrera de estado descrita arriba.

## Bucles

No encontré un bucle infinito:

- `derramarResto` sólo se ejecuta por eventos.
- AutoEfectivo vuelve a renderizar, pero deja de actualizar cuando el monto coincide.
- El timer del tooltip se limpia al desmontar.

## Mutación que sobreviven los 27 tests

Eliminar esta línea:

```ts
derramar(indice)
```

de [PagoInline.tsx:228](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/ventago-app/src/views/homes/components/ProductList/components/PagoInline.tsx:228) desactiva por completo el derrame en blur y **ninguno de los 27 tests falla**.

La suite sólo importa y prueba las utilidades de `pago-inline.ts`; no monta `PagoInline`, no prueba `focus → change → blur`, los botones ✕, el tooltip ni la convivencia con AutoEfectivo. Por eso verifica correctamente el algoritmo aislado, pero no que el producto llegue a invocarlo.

No pude volver a ejecutar Jest en este entorno de sólo lectura: Jest intentó crear su `haste-map` en el directorio temporal y recibió `EPERM`. El hueco de cobertura anterior se determina directamente por el contenido completo del spec y sus imports.