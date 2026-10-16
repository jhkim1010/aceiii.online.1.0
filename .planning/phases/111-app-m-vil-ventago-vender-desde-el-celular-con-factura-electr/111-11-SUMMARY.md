---
phase: 111-app-m-vil-ventago-vender-desde-el-celular-con-factura-electr
plan: 11
subsystem: mobile
tags: [flutter, riverpod, cart, scanner, fiscal, colibri]
requires: ["111-10", "111-16", "111-04", "111-06"]
provides:
  - "Cart/CartItem puros en centavos + CartStore con escritura inmediata en LocalStore"
  - "Vender (busqueda 300 ms, recientes), escaner continuo, matriz talle x color, carrito con cart/check"
  - "Cliente y datos para facturar validado por fiscal/check"
affects: [111-13]
key-files:
  created:
    - colibri/lib/features/venta/cart/{cart_model,cart_store,carrito_screen}.dart
    - colibri/lib/features/venta/catalog/{catalog_repository,vender_screen}.dart
    - colibri/lib/features/venta/scanner/{lector_logic,escanear_screen}.dart
    - colibri/lib/features/venta/matrix/{variant_matrix,producto_screen}.dart
    - colibri/lib/features/venta/cliente/{cliente_repository,cliente_screen}.dart
    - colibri/test/{cart_model,cart_store,lector,cliente_faltan}_test.dart
  modified:
    - colibri/lib/features/venta/venta_routes.dart
key-decisions:
  - "Fila de carrito = CartItem (CartLine ya existe en pos_contracts como linea de cart/check)."
  - "Talles ordenados con compararTalles, port de orden-talles.ts (letras, numeros, resto natural)."
  - "El tope de consumidor final nunca se escribe en Dart: el mensaje de 'documento' no cita cifra."
  - "Se persiste solo clientId/provinceId/comprobante (T-111-60)."
metrics:
  colibri-commits: 5a61033, 6de298a, b67d8bd
  tests: 65 (flutter test), analyze 0 issues
---

# Phase 111 Plan 11: Flujo de venta hasta «Cobrar» Summary

Buscar o escanear, elegir variante en la matriz, armar un carrito por variante que sobrevive a matar la app, chequear precios/stock en el servidor y dejar los datos fiscales completos antes de cobrar.

## Commits (submodulo colibri, pusheado al remoto privado)
- Task 1: 5a61033 carrito puro + store persistente (14 tests)
- Task 2: 6de298a vender, escaner, matriz, carrito (lector_test 7)
- Task 3: b67d8bd cliente y datos para facturar (+ test de mensajes de faltan)
- Raiz: gitlink commiteado aparte; monorepo raiz, api-ventago y ventago-app NO pusheados.

## Verificacion
`flutter analyze`: No issues found. `flutter test`: 65 pasan. Greps: `/mobile/pos/fiscal/check` y `/fiscal/opciones` en cliente_repository; sin `'/provinces`; `cart/check` en repositorio y carrito.

## Deviations from Plan
- [Rule 3] Rutas `colibri/` en lugar de `ventago-movil/` (decision del usuario); push del repo privado colibri permitido por el orquestador.
- `lector_logic.dart` es una adaptacion (no copia literal): se quitaron `VariantStock`/`buscarVariante` (el servidor ya resuelve la variante por codigo) y `topeDisponible` recibe el stock numerico. `lector_test.dart` adaptado igual.
- Agregado `test/cliente_faltan_test.dart` (no listado) para los mensajes de `faltan`.
- Si el cart/check cambia precios, el carrito los muestra y pide volver a tocar «Cliente y cobro» (no avanza solo).

## Known Stubs
- `AppPaths.cobro` (boton «Cobrar ›») aun no tiene ruta registrada: la pantalla de cobro es de Plan 13. Hasta entonces el boton llevaria a una ruta inexistente.
- `PosCatalogItem.imageUrl/barcode` llegan `null` del servidor (Plan 04); la lista no muestra miniaturas.
- La forma exacta de las respuestas `GET /mobile/pos/clients` (lista o `{items}`) y `POST clients/padron` no esta en pos-contracts.ts: el parser acepta ambas y el padron solo se usa por exito/fallo y relectura del detalle. Sin crear cliente nuevo desde la app (no pedido en las tareas).

## Notes
- El escaner y las pantallas no tienen tests de widget; la logica probada vive en cart_model, cart_store, lector_logic y mensajeFaltante. Nada probado en dispositivo ni contra la API real.
- STATE.md y ROADMAP.md quedan sin commitear a proposito.

## Self-Check: PASSED
Commits 5a61033, 6de298a, b67d8bd existen en colibri; archivos creados presentes.
