# 101-INVENTARIO — recorrido dinámico D-07 (local, 2026-10-09)

Método: `api-ventago/scripts/inventario-agente.sh` (sólo local). Admin local de la tienda 6 (`perm.admin@dummy.test`)
genera un código con los 4 `ver_*` por el flujo real, `agent@app` (id 257) lo canjea y se piden por API los GET
que cada pantalla hace (extraídos de `views/*` y `hooks/api/*`). Por cada 200: `camposSecretosEn(body)` y presencia
de claves de costo/ganancia (`cost|costCurrency|markupPct|costPorVariacion|ganancia|profit|margen|margin`).

## Hallazgos

1. **Los `denegado` de `support_access_events` NO sirven como lista de comunes faltantes.** Un handler sin
   `@AgentScope` se rechaza en `JwtGlobalGuard` (403 `AGENT_NO_SCOPE`) **antes** de consultar el grant, así que no deja
   evento. `denegado` sólo registra grant inválido/alcance equivocado. La evidencia equivalente es el **403 HTTP por
   ruta** del recorrido (columna HTTP). Grant 95: 57 `permitido`, 0 `denegado`.
2. Primera pasada (grant 93): 8 filas no-ok. Ninguna era un común faltante real:
   - `/sales/:id/printers` 403 → **excluido con motivo**: sólo lo llama «Reimprimir» (`useReprintPrinterPicker`, al hacer clic),
     botón oculto en modo soporte; `POST /sales/:id/reprint` jamás se abre (no-duplicate-print).
   - `/afip/iibb` 403 → **excluido por D-22** (descarga contable; 101-05 lo fija con mutante 17).
   - `/terminal/store/:id` 403 → sólo lo usa `views/admin/stores` (superadmin), no una pantalla de la tienda.
   - `/afip/issue/opciones`, `/branch/price-types-disabled`, `/mercadopago/accounts` 400 → faltaba el parámetro (`saleId`/`storeId`);
     con parámetro: 200 (el admin recibe el mismo 400 sin parámetro).
   - `/products/all` 500 → `Stocks is not associated to Product` también con el admin local; ninguna vista lo llama
     (preexistente, fuera de alcance → deferred).
   - `/functions/structure` 200 → **no es fuga**: D-12 incluye la pantalla de permisos en sólo lectura (marcado `ver_admin` en 101-09).
3. Segunda pasada (grant 95): **0 filas no-ok**, **secretos = 0 en todos los 200**, **costo = no** en todos los 200.
4. Control del detector de costo: el mismo `GET /products/by-store` con el admin trae `"cost":null,"costCurrency":null,"costPorVariacion":false`
   (405 claves) y el del agente 0 → el detector ve las claves y el filtro las quita (D-13).
5. Reconciliación `MODULOS_POR_ALCANCE` (configuracion) con la tabla de 101-08: menú = preferencias, inventario, envíos, restaurante, whatsapp
   (todas «Incluida»). `configurar-mercadopago` queda **fuera del menú**: la página usa `wallets`/`movements` (sin marca) además de
   `accounts`, y un ítem que abre casi todo en «Este código no permite ver esto» es un callejón sin salida. Sin cambios de código.
6. Sin marcas nuevas → no se tocaron controladores ni manifiestos de área (los 5 manifiestos quedan igual).

## Tabla (grant 95, tienda 6, alcances ver_ventas+ver_productos+ver_facturas+ver_admin)

| pantalla | GET | HTTP | secretos | costo | veredicto |
|---|---|---|---|---|---|
| Ventas | /sales/all | 200 | 0 | no | incluido |
| Ventas | /sales/daily-summary | 200 | 0 | no | incluido |
| Ventas | /sales/daily-stats | 200 | 0 | no | incluido |
| Ventas | /online-orders/venta-vista | 200 | 0 | no | incluido |
| Ventas | /online-orders/cobros-resumen | 200 | 0 | no | incluido |
| Ventas | /expenses/daily-summary | 200 | 0 | no | incluido |
| Ventas | /cash-register/status | 200 | 0 | no | incluido |
| Ventas | /box | 200 | 0 | no | incluido |
| Ventas detalle | /sales/176 | 200 | 0 | no | incluido |
| Ventas detalle | /online-orders/1 | 200 | 0 | no | incluido |
| Productos | /products/by-store | 200 | 0 | no | incluido |
| Productos | /products/stock-today | 200 | 0 | no | incluido |
| Productos | /products/307/inventory | 200 | 0 | no | incluido |
| Productos | /cotizacion/actual | 200 | 0 | no | incluido |
| Productos | /cotizacion/moneda | 200 | 0 | no | incluido |
| Productos | /configuration/by-store | 200 | 0 | no | incluido |
| Productos | /branch/store/6 | 200 | 0 | no | incluido |
| Catalogo comun | /categories/by-store | 200 | 0 | no | incluido |
| Catalogo comun | /subcategories/by-store | 200 | 0 | no | incluido |
| Catalogo comun | /sizes/by-store | 200 | 0 | no | incluido |
| Catalogo comun | /colors/by-store | 200 | 0 | no | incluido |
| Catalogo comun | /seasons/by-store | 200 | 0 | no | incluido |
| Catalogo comun | /origins/by-store | 200 | 0 | no | incluido |
| Catalogo comun | /suppliers/by-store | 200 | 0 | no | incluido |
| Catalogo comun | /price-types | 200 | 0 | no | incluido |
| Catalogo comun | /price-types/all | 200 | 0 | no | incluido |
| Catalogo comun | /payment-methods/all | 200 | 0 | no | incluido |
| Catalogo comun | /discounts/all | 200 | 0 | no | incluido |
| Catalogo comun | /sellers | 200 | 0 | no | incluido |
| Catalogo comun | /expenses/categories/all | 200 | 0 | no | incluido |
| Facturacion | /afip/emitidas | 200 | 0 | no | incluido |
| Facturacion | /afip/pendientes | 200 | 0 | no | incluido |
| Facturacion | /afip/verificar | 200 | 0 | no | incluido |
| Facturacion | /afip/notas/pendientes | 200 | 0 | no | incluido |
| Facturacion | /afip/issuers | 200 | 0 | no | incluido |
| Facturacion | /afip/issue/opciones | 200 | 0 | no | incluido |
| Sucursales | /branch/6/details | 200 | 0 | no | incluido |
| Sucursales | /branch/price-types-disabled | 200 | 0 | no | incluido |
| Sucursales | /terminal/by-branch/6 | 200 | 0 | no | incluido |
| Sucursales | /print/agents/6 | 200 | 0 | no | incluido |
| Sucursales | /integrations/wp/channels/branch/6 | 200 | 0 | no | incluido |
| Impresoras | /print/overview | 200 | 0 | no | incluido |
| Impresoras | /print/thermal-agents | 200 | 0 | no | incluido |
| Impresoras | /print/terminal/6/printers | 200 | 0 | no | incluido |
| Usuarios | /users/store/6 | 200 | 0 | no | incluido |
| Configuracion | /store/6 | 200 | 0 | no | incluido |
| Configuracion | /store-config/6 | 200 | 0 | no | incluido |
| Configuracion | /store-whatsapp-config/6 | 200 | 0 | no | incluido |
| Configuracion | /mercadopago/accounts | 200 | 0 | no | incluido |
| Contexto agente | /agente/tienda/contexto | 200 | 0 | no | incluido |
| Permisos (D-12) | /functions/structure | 200 | 0 | no | incluido |
| Permisos (D-12) | /role/store/6 | 200 | 0 | no | incluido |
| Permisos (D-12) | /functions/acciones-de-guardia | 200 | 0 | no | incluido |
| EXCLUIDO | /online-orders/1/confirm-link | 403 | 0 | no | excluido (403 correcto) |
| EXCLUIDO | /sellers/devices | 403 | 0 | no | excluido (403 correcto) |
| EXCLUIDO | /afip/cert | 403 | 0 | no | excluido (403 correcto) |
| EXCLUIDO | /audit-log | 403 | 0 | no | excluido (403 correcto) |
| EXCLUIDO | /afip/padron/estado | 403 | 0 | no | excluido (403 correcto) |
| EXCLUIDO | /sales/176/printers | 403 | 0 | no | excluido (403 correcto) |
| EXCLUIDO | /afip/iibb | 403 | 0 | no | excluido (403 correcto) |
| EXCLUIDO | /terminal/store/6 | 403 | 0 | no | excluido (403 correcto) |
| EXCLUIDO | /integrations/commerce/config | 403 | 0 | no | excluido (403 correcto) |

**Filas no-ok: 0**


`EXCLUIDO` = control negativo: debe seguir 403 (todos lo son). Motivos: confirm-link (token de entrega, GET con efecto), sellers/devices
(apiKey), afip/cert (carpeta de certificados), audit-log (IP/acciones de usuarios), afip/padron (llamada externa AFIP), sales/:id/printers
(sólo reimpresión), afip/iibb (D-22), terminal/store (superadmin), integrations/commerce/config (respuesta sin verificar, LOW).
