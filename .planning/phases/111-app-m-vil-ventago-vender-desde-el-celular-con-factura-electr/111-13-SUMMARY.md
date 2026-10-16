---
phase: 111-app-m-vil-ventago-vender-desde-el-celular-con-factura-electr
plan: 13
subsystem: mobile
tags: [flutter, cobro, mercadopago, idempotencia, colibri]
requires: ["111-11", "111-05", "111-17"]
provides:
  - "payment_math (centavos), checkout_machine (clave persistida + por clave), mp_qr_machine"
  - "Pantalla de cobro, panel QR MP, pagos MP sin venta, panel de caja cerrada; rutas AppPaths.cobro y mpPendientes"
key-files:
  created:
    - colibri/lib/features/venta/cobro/{payment_math,checkout_machine,mp_qr_machine,cobro_repository,cobro_screen,mp_qr_panel,mp_pendientes_screen,caja_cerrada_panel}.dart
    - colibri/test/{payment_math,checkout_machine,mp_qr_machine}_test.dart
  modified:
    - colibri/lib/features/venta/venta_routes.dart
decisions:
  - "Un solo punto libera la clave por codigo de negocio: _rechazar, solo si el codigo esta en kDefinitiveCodes (checkout_machine.dart:159 llama, :178-180 libera). Aparte, tras by-key completed se limpia (:171) y tras CLAVE_CONFLICTO + by-key sin venta (:228)."
  - "CAJA_CERRADA y demas rechazos no-MP NO borran el intent MP aprobado persistido; solo MP_* lo borran."
  - "PRECIO_CAMBIADO vuelve al carrito; los precios se actualizan en el cart/check de «Cliente y cobro» (no se reescriben desde el detalle del 409)."
metrics:
  colibri-commits: 0803ef8, 0e1ac0a
  tests: 102 (flutter test), analyze 0 issues
  completed: 2026-10-16
---

# Phase 111 Plan 13: Cobro con QR de Mercado Pago Summary

Cobro en el celular sin doble cobro: lineas de pago auditables, confirmacion idempotente con recuperacion por clave, QR dinamico de Mercado Pago como la web (D-21), caja cerrada y offline.

## Commits (submodulo colibri; pusheado al remoto privado)
- 0803ef8 logica pura: payment_math, checkout_machine, mp_qr_machine + 36 tests
- 0e1ac0a UI: cobro_screen, mp_qr_panel, mp_pendientes_screen, caja_cerrada_panel, repositorio, rutas
- Raiz: gitlink aparte. Monorepo raiz, api-ventago y ventago-app NO pusheados.

## Verificacion
- `flutter analyze`: No issues found. `flutter test`: 102 pasan (36 nuevos: 9 math, 14 checkout, 14 mp).
- Greps: `Idempotency-Key` y `mobile/pos/mp/qr` en cobro_repository; `mobile/pos/suspended` en cobro_repository; `abrirCaja` en caja_cerrada_panel; `Verificada` ausente en mp_qr_panel; sin `double ` en payment_math; sin qr_flutter/pretty_qr en pubspec.
- El test de doble toque encontro un bug real al escribirlo: el candado «enviando» se ponia despues de un await (guardar clave) y dejaba pasar un segundo POST. Corregido: candado sincrono antes de cualquier await.

## Deviations from Plan
- [Rule 3] Rutas `colibri/` en lugar de `ventago-movil/` (decision del usuario).
- `HEAD` del plan decia ≥26 tests: hay 36. Cubiertos: kill-tras-envio, EN_CURSO conserva clave, CLAVE_CONFLICTO por clave (completed y not_found), codigo 418, kill tras aprobar MP.
- Mantener la pantalla encendida mientras espera el QR: NO implementado (no hay API sin paquete nuevo).
- PRECIO_CAMBIADO: no se parsea `detail`; se vuelve al carrito (ver decisiones).

## Known Stubs
- `AppPaths.venta(saleId)` (destino tras cobrar) aun no tiene ruta: es de Plan 19. Hasta entonces `context.go` a esa ruta falla despues de cobrar (la venta y la limpieza del carrito ya ocurrieron).
- «Dejar en espera» usa el cuerpo `suspended` leido de pos-sales.service (items, subtotal, totalAmount, discountAmount, clientId, sellerId, provinceId); no probado contra la API real.
- Forma de `GET /mobile/pos/mp/intents`: el parser acepta lista o `{items}`.

## Notes
- Sin tests de widget; nada probado en dispositivo ni contra la API real. UAT (Plan 14): cobro con cada medio, QR real, corte de red tras Confirmar, y el camino degradado «almacenamiento local perdido tras aprobar MP» (lista desde el servidor + «Avisá al encargado», sin accion de cobro).
- Si «Retomar» en pagos sin venta: lleva a cobro; el cuerpo/clave persistidos se retoman por `restore()`; si solo hay intent aprobado, `resume()` lo deja aprobado y reabre la linea MP.
- STATE.md y ROADMAP.md quedan SIN commitear a proposito.

## Self-Check: PASSED
Commits 0803ef8 y 0e1ac0a existen en colibri; archivos creados presentes.
