# POS Alt+F12 — sólo factura (sin venta) (2026-10-15)

Usuario: «현재 화면에 손님 정보와 item 정보를 다 입력한 후에 Alt + F12 를 누르면 "이 벤타는 벤타로
등록되지 않고 오직 영수증 발급만을 하게 된다" … 확인하면 오직 영수증 100% 발급 … 손님 정보가 없으면
consumidor final». Aprobado: «Alt + F12 는 영수증만 발급하는 기능으로 mock up 처럼 작동하게 해줘».
Mockup: `.planning/mockups/2026-10-15-alt-f12-solo-factura/mockup.png`.
(Parte A ya desplegada: facturar 100 % = Ctrl+F10.)

## Hechos
- `afip_vouchers.sale_id` NOT NULL FK; el guardia anti-duplicado (claim `en_progreso` / `verificar`
  / `error` / `facturado`, rancio 10 min, consulta del último número) vive en `sales.afip_*`.
- No hay tabla de ítems del comprobante: impresión/PDF reconstruyen desde `sale_items`.
- Reportes con INNER JOIN sales (un comprobante sin venta desaparecería): IIBB
  (`afip-iibb.service.ts:107`), Libro IVA propios (`reportes-arca.service.ts:191`), Excel por
  jurisdicción (`:90`, parte de sales), cockpit (`reportsFacturacionCockpit.service.ts`), watch
  (`facturacion.source.ts:71`). `listEmitidas` no necesita venta.
- 59 archivos leen `sales` → una «venta fantasma» contaminaría ventas/caja: descartado.

## Diseño
1. **Tabla nueva `afip_facturas_sin_venta`** = el «dueño» del claim (mismas columnas que usa el
   guardia en `sales`: afip_status, afip_error, cae, cae_vto, punto_venta, afip_number,
   tipo_comprobante, updated_at) + store_id, branch_id, terminal_id, user_id, **idempotency_key
   (UNIQUE por tienda)**, client_id / store_client_id, snapshot del receptor (nombre, doc, resiva,
   domicilio, email), province_id, items JSONB, total.
2. **`afip_vouchers`**: `sale_id` DROP NOT NULL + `sin_venta_id` FK + CHECK XOR (NOT VALID →
   VALIDATE). NC/ND copian el dueño que tenga el original.
3. **`issue()`**: el claim/verificar/error/facturado se hace sobre el «objetivo» (sales o
   sin-venta) — mismo código, otro modelo. `comprobantesVigentes` por objetivo (100 % ya emitido →
   no reemite).
4. **`POST /afip/vouchers/sin-venta`** (admin/gerente/vendedor como F10): items + cliente opcional
   + provinceId + issuerId/puntoVenta + branchId/terminalId + idempotencyKey. INSERT … ON CONFLICT
   (store_id, key): si ya existe con otro contenido → 409; si ya está facturado → devuelve el mismo
   comprobante; si no → `issue()` (el claim decide). Emisor = `resolveIssuerForSale` con la sucursal
   de la terminal. Receptor = el cliente elegido o Consumidor Final. Jurisdicción = la elegida o la
   del cliente (sin fallback a sucursal, igual que la venta).
5. **Salida** (térmica/PDF/email/reimpresión): construir la factura desde el snapshot cuando
   `sale_id` es NULL. Una sola impresión.
6. **Reportes fiscales**: LEFT JOIN sales + COALESCE al snapshot/sucursal del sin-venta en IIBB,
   Libro IVA, cockpit, watch; el Excel por jurisdicción suma también los sin-venta.
7. **Front**: Alt+F12 (sólo FE aprobada, online) abre `SoloFacturaDialog`: banner «NO se registra
   como venta», cliente o «Consumidor Final», tipo/PV, total 100 %, jurisdicción, salida;
   Enter emite, Esc cancela. Limpia el carrito sólo si ok. Emitidas: chip «Sin venta».
   Lista F1 + manual + guardia de atajos.
8. Tope CF (DNI): hoy no hay chequeo en la venta tampoco — AFIP rechaza (10015) y se muestra su
   motivo. (Diferencia con el mockup, se avisa al usuario.)

## Preguntas para CODEX
1. ¿El objetivo intercambiable en `issue()` deja algún camino donde un sin-venta pueda emitirse
   dos veces (doble click, reintento de red, dos cajas)?
2. ¿Qué otro consumidor de `afip_vouchers.sale_id` se rompe con NULL?
3. ¿Riesgos de aceptar precios del cliente (no hay venta que los respalde)?
