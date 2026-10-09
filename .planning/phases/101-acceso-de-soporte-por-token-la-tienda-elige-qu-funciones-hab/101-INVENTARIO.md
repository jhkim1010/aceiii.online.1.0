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

---

## Revisión 2 (2026-10-09 01:10–01:30, tras consulta a CODEX)

CODEX calificó la primera pasada como «prueba de humo»: lista de GET manual, semillas con
fallback `|| 1`, regex de costo estrecha, una sola combinación de alcances, sin IDOR. Se midió:

1. **GET de montaje faltantes** — extracción de vistas/hooks (/ventas, /productos, /facturacion,
   /sucursales, /impresoras, /usuarios, /configuracion, layout global): **37 GET no estaban** en la
   lista. Probados con un grant de los 4 ver_*:
   - **`GET /terminal` → 200 con `box.branch.apiKey`** (D-10). `Branch.toJSON()` borra apiKey sólo en el
     nivel superior; anidado sale tal cual. Lo pide SalesListToolbar al montar /ventas. Producción:
     0/35 branches con api_key (sin valor expuesto hoy). **Corregido** en api `4ee515c8` (+ mutantes 22–23).
     Recuento de la clase: 8 includes de Branch sin `attributes`; con agente sólo éste llega a un 200
     (`/box`, `/cash-register/*`, `/branch`, `/sales/:id` verificados sin la clave).
   - 17 más dan 200 sin secretos ni costo → agregados como «ok».
   - 20 dan 403 al montar (gastos, tienda online, catálogos de configuración, layout) → «EXCL-montaje»:
     la región muestra SinAlcance o el layout ya los salta para el agente.
2. **Semillas sin fallback** — al quitar `|| 1`, `/online-orders/venta-vista` vino vacío (filtra por día):
   el `orderId=1` de la primera pasada **era el fallback** (coincidió con un pedido de la tienda 6).
   Ahora el pedido sale de la DB local de esa tienda y el script falla si no hay semilla.
3. **Costo amplio** (sin mayúsculas: cost/costo/ganancia/profit/margen/margin/markup/purchase/compra):
   3 falsos positivos revisados a mano (`shippingCost`, `productosConCosto` = conteo, slugs
   `reporte-ganancia`/`ver-costo-producto`). **Control:** el mismo detector sobre `/products/by-store`
   del admin marca `cost,costCurrency,markupPct,costPorVariacion`.
4. **IDOR** (grant de la tienda 6, ids de la tienda 9): `/sales/9` 404, `/products/93/inventory` 404,
   11 rutas `:storeId=9` → 403; `/sales/all?storeId=9` devuelve datos de la tienda 6 (ignora el parámetro);
   `/branch/14/details` 200 `{boxCount:0,terminalCount:0}` mientras la DB tiene 1 caja/5 terminales
   en esa sucursal → los hooks de tenant filtran, sin fuga.
5. **Matriz por alcance individual** (grants 98–101): cada ver_* abre sólo su grupo; catálogo común
   abierto para todos; `/sales/:id` también con ver_facturas (detalle de comprobante, por diseño).
6. **Errores**: el 404 ajeno trae sólo `{message,error,statusCode}` (sin stack ni SQL).

Resultado final del script: **99 filas, 0 no-ok** (grant 105).

### Observado, no corregido (preexistente / fuera de alcance)
- `GET /store/:id` (abierto a cualquier ver_*) incluye `afipConstanciaKey`, `domicilioCertKey`,
  `telegramChatId`. El `/minio/:filename` público rechaza claves no-imagen/con ruta
  (`isPubliclyServable`), así que la clave sola no baja el documento. Ya estaba en la lista de
  preguntas del HANDOFF.
- `GET /products/all` 500 (sigue igual).

### Tabla final (grant 105)
| pantalla | GET | HTTP | secretos | costo | veredicto |
|---|---|---|---|---|---|
| Ventas | /sales/all | 200 | 0 | no | ok |
| Ventas | /sales/daily-summary | 200 | 0 | no | ok |
| Ventas | /sales/daily-stats | 200 | 0 | no | ok |
| Ventas | /online-orders/venta-vista | 200 | 0 | no | ok |
| Ventas | /online-orders/cobros-resumen | 200 | 0 | no | ok |
| Ventas | /expenses/daily-summary | 200 | 0 | no | ok |
| Ventas | /cash-register/status | 200 | 0 | no | ok |
| Ventas | /box | 200 | 0 | no | ok |
| Ventas detalle | /sales/176 | 200 | 0 | no | ok |
| Ventas detalle | /online-orders/1 | 200 | 0 | no | ok |
| Productos | /products/by-store | 200 | 0 | no | ok |
| Productos | /products/stock-today | 200 | 0 | no | ok |
| Productos | /products/307/inventory | 200 | 0 | no | ok |
| Productos | /cotizacion/actual | 200 | 0 | no | ok |
| Productos | /cotizacion/moneda | 200 | 0 | no | ok |
| Productos | /configuration/by-store | 200 | 0 | no | ok |
| Productos | /branch/store/6 | 200 | 0 | no | ok |
| Catalogo comun | /categories/by-store | 200 | 0 | no | ok |
| Catalogo comun | /subcategories/by-store | 200 | 0 | no | ok |
| Catalogo comun | /sizes/by-store | 200 | 0 | no | ok |
| Catalogo comun | /colors/by-store | 200 | 0 | no | ok |
| Catalogo comun | /seasons/by-store | 200 | 0 | no | ok |
| Catalogo comun | /origins/by-store | 200 | 0 | no | ok |
| Catalogo comun | /suppliers/by-store | 200 | 0 | no | ok |
| Catalogo comun | /price-types | 200 | 0 | no | ok |
| Catalogo comun | /price-types/all | 200 | 0 | no | ok |
| Catalogo comun | /payment-methods/all | 200 | 0 | no | ok |
| Catalogo comun | /discounts/all | 200 | 0 | no | ok |
| Catalogo comun | /sellers | 200 | 0 | no | ok |
| Catalogo comun | /expenses/categories/all | 200 | 0 | no | ok |
| Facturacion | /afip/emitidas | 200 | 0 | no | ok |
| Facturacion | /afip/pendientes | 200 | 0 | no | ok |
| Facturacion | /afip/verificar | 200 | 0 | no | ok |
| Facturacion | /afip/notas/pendientes | 200 | 0 | no | ok |
| Facturacion | /afip/issuers | 200 | 0 | no | ok |
| Facturacion | /afip/issue/opciones | 200 | 0 | no | ok |
| Sucursales | /branch/6/details | 200 | 0 | no | ok |
| Sucursales | /branch/price-types-disabled | 200 | 0 | no | ok |
| Sucursales | /terminal/by-branch/6 | 200 | 0 | no | ok |
| Sucursales | /print/agents/6 | 200 | 0 | no | ok |
| Sucursales | /integrations/wp/channels/branch/6 | 200 | 0 | no | ok |
| Impresoras | /print/overview | 200 | 0 | no | ok |
| Impresoras | /print/thermal-agents | 200 | 0 | no | ok |
| Impresoras | /print/terminal/6/printers | 200 | 0 | no | ok |
| Usuarios | /users/store/6 | 200 | 0 | no | ok |
| Configuracion | /store/6 | 200 | 0 | no | ok |
| Configuracion | /store-config/6 | 200 | 0 | no | ok |
| Configuracion | /store-whatsapp-config/6 | 200 | 0 | no | ok |
| Configuracion | /mercadopago/accounts | 200 | 0 | no | ok |
| Contexto agente | /agente/tienda/contexto | 200 | 0 | no | ok |
| Permisos (D-12) | /functions/structure | 200 | 0 | no | ok |
| Permisos (D-12) | /role/store/6 | 200 | 0 | no | ok |
| Permisos (D-12) | /functions/acciones-de-guardia | 200 | 0 | no | ok |
| Ventas | /terminal | 200 | 0 | no | ok |
| Ventas | /cash-register/cierre | 200 | 0 | no | ok |
| Productos | /products/by-parent | 200 | 0 | no | ok |
| Productos | /module-alias | 200 | 0 | no | ok |
| Productos | /integrations/wp/channels | 200 | 0 | no | ok |
| Productos | /cotizacion/historial | 200 | 0 | no | ok |
| Usuarios | /role | 200 | 0 | no | ok |
| Usuarios | /users | 200 | 0 | no | ok |
| Permisos (D-12) | /permissions/por-funcion | 200 | 0 | no | ok |
| Layout | /branch | 200 | 0 | no | ok |
| Catalogo comun | /categories | 200 | 0 | no | ok |
| Catalogo comun | /subcategories | 200 | 0 | no | ok |
| Catalogo comun | /sizes | 200 | 0 | no | ok |
| Catalogo comun | /colors | 200 | 0 | no | ok |
| Catalogo comun | /seasons | 200 | 0 | no | ok |
| Catalogo comun | /origins | 200 | 0 | no | ok |
| Catalogo comun | /suppliers | 200 | 0 | no | ok |
| EXCL-montaje Ventas | /expenses/search | 403 | 0 | no | ok |
| EXCL-montaje Productos | /shop/6/theme/settings | 403 | 0 | no | ok |
| EXCL-montaje Sucursales | /box/store/6 | 403 | 0 | no | ok |
| EXCL-montaje Config | /store/type-of-payers-catalog | 403 | 0 | no | ok |
| EXCL-montaje Config | /store/6/fe-documents | 403 | 0 | no | ok |
| EXCL-montaje Config | /afip/issuers/certificados | 403 | 0 | no | ok |
| EXCL-montaje Config | /recharges/all | 403 | 0 | no | ok |
| EXCL-montaje Config | /transportes | 403 | 0 | no | ok |
| EXCL-montaje Config | /repartidores | 403 | 0 | no | ok |
| EXCL-montaje Config | /onboarding/referral/mine | 403 | 0 | no | ok |
| EXCL-montaje Config | /whatsapp/store-config | 403 | 0 | no | ok |
| EXCL-montaje Config | /integrations/tiendanube/channels | 403 | 0 | no | ok |
| EXCL-montaje Config | /watch/devices | 403 | 0 | no | ok |
| EXCL-montaje Config | /vto/usage | 403 | 0 | no | ok |
| EXCL-montaje Config | /shop/6/slug | 403 | 0 | no | ok |
| EXCL-montaje Config | /legacy-import/clientes-por-confirmar | 403 | 0 | no | ok |
| EXCL-layout | /notas/unread | 403 | 0 | no | ok |
| EXCL-layout | /cash-register/open | 403 | 0 | no | ok |
| EXCL-layout | /team-chat/unread | 403 | 0 | no | ok |
| EXCL-layout | /admin-console/my-notices | 403 | 0 | no | ok |
| EXCLUIDO | /online-orders/1/confirm-link | 403 | 0 | no | ok |
| EXCLUIDO | /sellers/devices | 403 | 0 | no | ok |
| EXCLUIDO | /afip/cert | 403 | 0 | no | ok |
| EXCLUIDO | /audit-log | 403 | 0 | no | ok |
| EXCLUIDO | /afip/padron/estado | 403 | 0 | no | ok |
| EXCLUIDO | /sales/176/printers | 403 | 0 | no | ok |
| EXCLUIDO | /afip/iibb | 403 | 0 | no | ok |
| EXCLUIDO | /terminal/store/6 | 403 | 0 | no | ok |
| EXCLUIDO | /integrations/commerce/config | 403 | 0 | no | ok |

# filas no-ok: 0

# denegados del grant (route|n):
