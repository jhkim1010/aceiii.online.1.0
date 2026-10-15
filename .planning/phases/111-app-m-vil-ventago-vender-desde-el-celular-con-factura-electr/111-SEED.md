# Phase 111 — App móvil Ventago (semilla para discuss/plan)

Pedido del usuario (2026-10-14): «핸드폰에서도 판매 (정식 영수증 발송 포함), 스톡 추가,
각종 보고서를 확인할 수 있는 앱».

## Alcance pedido
1. Venta desde el celular — incluida factura electrónica AFIP (SOAP directo, F10 manual: la
   emisión automática está PROHIBIDA) y envío del comprobante (WhatsApp / mail).
2. Carga de stock (ingreso).
3. Consulta de los reportes principales.

## Hechos a tener en cuenta (verificar en discuss)
- Ya hay apps Flutter que consumen la API (/api/reports/* lo usan dos apps — memoria
  reports-api-has-flutter-consumers) y ventago-admin-app (login con token de dispositivo).
  Decidir: app nueva / extender una existente / PWA del web actual.
- Web/POS no tiene refresh token (memoria no-user-refresh-token-flow).
- Sesión: un usuario = una sesión activa (active_sessions) + terminal/IP registrados —
  el celular choca con esto si el mismo usuario vende en el POS.
- Venta con factura: caja abierta por box (regla de caja), numeración por sucursal,
  receptor IVA (RG 5616) e IIBB por domicilio del comprador.
- Reportes: /api/reports/* y reports-v2; tablas con cabecera fija (table-viewport).
