---
phase: 111-app-m-vil-ventago-vender-desde-el-celular-con-factura-electr
plan: 19
subsystem: mobile
tags: [flutter, afip, fiscal, share, print, colibri]
requires: ["111-13", "111-06", "111-05"]
provides:
  - "fiscal_state (estado -> UI), fiscal_repository"
  - "Rutas AppPaths.venta(id), compartir(saleId), sinEmitir (cierra los huecos de 111-12 y 111-13)"
key-files:
  created:
    - colibri/lib/features/venta/fiscal/{fiscal_state,fiscal_repository,venta_cobrada_screen,sin_emitir_screen}.dart
    - colibri/lib/features/venta/share/{share_service,compartir_screen}.dart
    - colibri/lib/features/venta/print/print_button.dart
    - colibri/test/fiscal_state_test.dart
  modified:
    - colibri/lib/features/venta/venta_routes.dart
    - colibri/lib/features/venta/cobro/cobro_screen.dart
    - colibri/lib/core/contracts/pos_contracts.dart
decisions:
  - "parseFiscalEstado: estado desconocido o ausente = verificar (fail-safe, nunca ofrece emitir otra vez); 'no_solicitada' es explicito"
  - "Tras un corte de red en la emision NO se repite el POST: se consulta GET fiscal y se sigue fiscal_state"
metrics:
  colibri-commits: edf68ec, 101c93a
  tests: 131 (flutter test), analyze 0 issues
  completed: 2026-10-16
---

# Phase 111 Plan 19: Factura manual, sin emitir, compartir e imprimir Summary

Despues del cobro, Colibri emite la factura solo con el boton (tambien si se cobro como ticket), muestra los seis estados fiscales con honestidad, lista todas las «sin emitir» sin limite de dias, comparte el PDF por la hoja del telefono e imprime solo por boton.

## Commits (submodulo colibri, pusheado al remoto privado)
- edf68ec estado fiscal (seis estados, desconocido = verificar) y repositorio fiscal; 9 tests
- 101c93a pantallas: venta cobrada, sin emitir, compartir, boton de impresion, rutas
- Raiz: solo gitlink + este SUMMARY. Monorepo raiz, api-ventago y ventago-app NO pusheados.

## Verificacion
`flutter analyze`: 0 issues. `flutter test`: 131 pasan. Greps: sin `wa.me`/`api.whatsapp` en lib; `/invoice` solo en fiscal_repository y se llama desde `_emitir` (onPressed de dos botones: Emitir y Reintentar); `/print` solo en fiscal_repository y se llama desde print_button; `hoy` ausente en sin_emitir_screen; `SharePlus.instance.share` y `delete` presentes en share_service.

## Deviations from Plan
- [Rule 3] Rutas `colibri/` en lugar de `ventago-movil/`; commit en el submodulo y gitlink aparte. Se pusheo solo colibri (permitido por el usuario).
- [Rule 2] `parseFiscalEstado` (pos_contracts.dart) cambio su default de noSolicitada a verificar: con el default anterior un estado desconocido habria ofrecido emitir.
- `cobro_screen` ahora pasa `extra: sale` a la ruta venta para mostrar el resumen de pagos (el servidor no tiene endpoint de detalle de venta en este plan).
- `/invoice` esta tras dos botones (Emitir y Reintentar), ambos onPressed; ninguno automatico.

## Known Stubs / limites
- «Corregir datos» abre la pantalla de cliente, que trabaja sobre el cliente del carrito (ya vaciado tras cobrar); `SaleFiscalResponse` no trae el id del cliente. Hay que verificar/ajustar en UAT; no se corrigio un cliente concreto de la venta.
- El telefono/mail del cliente como pista en compartir no se muestra: ningun contrato lo expone (solo nombre del receptor).
- Con varias impresoras se envia sin `printerAgentId` (el servidor decide); no hay selector.
- No se intercepta el boton «atras» del sistema en una venta sin emitir; la pregunta «¿Dejar pendiente?» sale solo con «Nueva venta».
- Sin tests de widget; nada probado en dispositivo ni contra AFIP/impresora/API reales. Leyenda «COMPROBANTE NO VÁLIDO COMO FACTURA» aprobada por el usuario; la pantalla Compartir la muestra para el ticket.

## Notes
STATE.md y ROADMAP.md quedan SIN commitear a proposito.

## Self-Check: PASSED
Commits edf68ec y 101c93a existen en colibri; archivos creados presentes.
