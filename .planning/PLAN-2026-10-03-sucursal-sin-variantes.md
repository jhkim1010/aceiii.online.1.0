# Sucursal «sin color y talle» — vender por código madre (2026-10-03)

Usuario: «una sucursal puede no usar color y talle: ocultar las variaciones y vender sólo con
color único / talle único o código madre. Que se elija en Admin › Sucursales.»
Aprobado: «모두 네 제안대로 하자. codex 제안 받고 시작».
Mockup: `.planning/sketches/sucursal-sin-variantes.png`. CODEX: `.team/reviews/manual-sucursal-sin-variantes.md`.

## Decisiones (aprobadas)
1. Ancla = variante por defecto del madre, SKU `<madre>-V` (Color Único / Talle Única) — la misma
   que crea `transferBalanceToDefaultVariant`. El stock sigue sólo en hojas (trg_stocks_leaf_only).
2. Activar: se CONSOLIDA el stock por variante de esa sucursal en `-V` (−N variante / +N `-V`,
   un lote, misma transacción, bajo lock). Desactivar: no reparte (el stock queda en `-V`).
3. Productos sin variantes: sin cambio.
4. Web: no se puede activar en una sucursal que es fuente de stock de un canal WP.

## Riesgos (CODEX) → respuesta
- Concurrencia al activar → advisory lock por sucursal + lock de filas, una transacción.
- Idempotencia → un `adjust_batch_id` por activación; re-activar con flag ya en true = no-op.
- Reservas abiertas (ventas suspendidas / pedidos web con hold) → se NIEGA activar mientras existan
  en esa sucursal (se listan).
- Trazabilidad → cada fila de consolidación lleva nota con SKU origen + batch.
- Devoluciones / anulaciones de ventas viejas por variante → el stock vuelve a `-V`
  (resolver), sale_items conserva el producto vendido.
- Etiquetas → el escáner acepta SKU de variante (alias) → se cuenta en `-V`.
- Guardia única en DB: en sucursal marcada, un INSERT de stock en una variante que no es `-V`
  FALLA (salvo la consolidación con `ventago.allow_variant_stock`). Caminos no mapeados fallan
  en voz alta en vez de ensuciar.
- `-V` nuevo en sucursales normales → no se muestra en la matriz si allí tiene stock 0.

## Fases
1. DB + núcleo API: columna `branches.vende_sin_variantes`, trigger guardia, servicio
   `variante-unica` (asegurar `-V` en lote · mapear producto→hoja por sucursal), endpoint
   preview + toggle con consolidación.
2. Caminos de escritura: venta (incl. cambio), movimientos (traspaso/devuelto), anulación,
   ingreso por lote, ingreso de producción.
3. Catálogo POS: colapsar madre → `-V` en sucursal marcada (sin matriz) + alias de SKU;
   ocultar `-V` con stock 0 en sucursales normales.
4. Pantallas: Admin › Sucursales (columna + diálogo con preview) · POS escáner por alias.

## Estado (2026-10-03 noche) — desplegado
- api `098c38f5` (fase 1) · `fd4f395f` (fase 2) · `586aea47` (fase 3) → Jenkins #1078 OK
- app `af49d826` (pantalla + escáner) → front #956/#957 OK
- migración aplicada en local (5432) y prod (5434). Ninguna sucursal marcada todavía.
- smoke prod: GET /branch/39/sin-variantes → 3.866 productos / 97.247 u. a agrupar, 1.072 madres sin -V.
- Tests: itest DB local 7/7 · sales 355 · stocks 15 · products/subcon/production 329 · app sku-escaneado 4.

## Pendiente / a vigilar
- Corrección del día y edición de variantes del madre NO están mapeadas a propósito: en sucursal
  marcada las rechaza la guardia de DB (mensaje claro). Si se necesitan, mapear lectura + escritura.
- Reportes por variante: la sucursal marcada aparece con stock en `-V` (Color Único / Talle Única).
- Probar en una tienda real: activar en una sucursal chica, vender, escanear etiqueta de variante,
  traspasar desde otra sucursal, anular.
