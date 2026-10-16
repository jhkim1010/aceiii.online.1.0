# Phase 112 — Tienda pública legible por IA (semilla para discuss/plan)

Pedido del usuario (2026-10-15): «지금 AI 에게 잘 검색되게 하기 위해서 다음 작업을 좀 준비해야겠어.
GSD phase 하나를 준비하자.» — con un plan de 3 etapas (abajo, resumido).

## Alcance de ESTA fase = Etapa 1 (+ la protección de la DB)
El propio plan dice «la etapa 1 sirve para todas las IA; empezar por los protocolos puede dar 0
exposición». Por eso 112 = etapa 1. Las etapas 2 y 3 quedan como fases siguientes (al final).

1. `tienda-app`: página de detalle de producto SSR `/[storeId]/p/[slug]` reusando
   `GET public/shop/:storeId/products/:slug`.
2. JSON-LD `Product` + `Offer` en cada página: precio ARS, `availability` según stock real,
   material · talle · color, marca, imágenes, tienda (`Organization`/`LocalBusiness`, dirección),
   `priceValidUntil`.
3. Título · descripción · OG por tienda y por producto (no un título común).
4. `sitemap.xml` y `robots.txt` por tienda; robots permite explícitamente GPTBot, OAI-SearchBot,
   Google-Extended, PerplexityBot, ClaudeBot.
5. `llms.txt` por tienda: presentación, categorías, enlace al feed/sitemap.
6. ★ Protección del pool: crawlers llegan en ráfaga. Nada de esto puede tocar la DB por pedido
   sin tope (POS se detiene si se agota el pool).

## Hechos verificados en el código (2026-10-15) — y lo que corrigen del plan
- **tienda-app = Next 13.3.2, Pages router, puerto 3060.** Rutas: `/` (redirect), `/[storeId]`
  (catálogo, **ya es SSR** `getServerSideProps` `[storeId]/index.tsx:48`), `/[storeId]/panel/diseno`.
  **No hay detalle de producto.** `getProduct()` existe sin uso (`src/services/shop-api.ts:79-84`).
- **La tienda se resuelve por subdominio** `<slug>.coolsistema.com` → `src/middleware.ts` (host
  header, `GET /public/shop/by-slug/:slug`, rewrite a `/[storeId]`). Sin dominios propios.
  ★ El middleware llama a la API **en cada pedido sin caché** (memoria
  `wildcard-subdomain-calls-api-per-request`: 563 404/día de nuestro propio front). Con crawlers
  esto se multiplica → **cachear subdominio→storeId (positivo y negativo) es requisito de 112.**
  ★ La URL canónica de producto/sitemap tiene que ser la del subdominio, no `/[storeId]`.
- **«Tienda — Ventago» no es tienda-app**: es la tienda vieja de un solo HTML que sirve la API
  (`shop-public/shop-storefront.page.ts:10`, `GET public/shop/:storeId/store`). Decidir si se
  retira o se le pone canonical hacia tienda-app (si no, compite como contenido duplicado).
  tienda-app hoy: `seoTitle || 'CoolShop — Tienda online'` sólo en el catálogo; sin canonical/OG/JSON-LD.
- **API pública** (`api-ventago/src/app/shop-public/`, todas `@Public()`): categorías, productos
  (pageSize ≤ 48), detalle por slug, `POST :storeId/checkout`, by-slug (Cache-Control 300 s), theme.
  Sólo productos `is_published_shop` + activos + **madre** (`parent_id IS NULL`).
- **DTO de producto** (`shop-catalog.service.ts:51-67`): id, name, slug, description,
  longDescription, price, priceOrig, stock, imageUrl(s), gender, material, categoryId.
  ★ **Faltan marca, talle, color, SKU/GTIN y nombre de categoría** (TODO :48 «no hay variantes»).
  El JSON-LD con talle/color pide exponer variantes (hijos) — trabajo de API, no sólo de front.
- **Precio** = `products.price` del madre (+ `price_orig` para tachado). Coincide con lo que cobra
  el POS (memoria `pos-prices-from-madre-unless-costo-por-variacion`) salvo tiendas con costo por
  variación → verificar.
- **Stock** = `v_stock_total_madre.available` = **suma de TODAS las sucursales**
  (`shop-catalog.service.ts:149-155`). ★ Para «disponible online» puede ser falso: p. ej. Kandente
  vende la web desde UNA sucursal (WEB) y las otras 3 sin color/talle. Decidir: ¿sucursal fuente
  de stock por tienda (como `stock_source_branch_id` de WooCommerce)?
- **DB de solo lectura**: `shop-readonly-db.service.ts` = `pg.Pool` propio (usuario `shop_readonly`),
  `max` = `SHOP_DB_POOL_MAX` (15) o **5 si no está aislado**; sin réplica (mismo host salvo
  `SHOP_DB_HOST`). Caché `MemoryCacheService.getOrLoad` 60 s por worker (lista/categorías/detalle),
  theme 5 min.
- **Rate limit**: sólo el global 600/60 s por IP (Redis), sin reglas por User-Agent ni bots.
- **Cron**: líder único (`main.ts:200-245`); `@Interval` se borran en no-líderes (memoria
  `non-leader-workers-lose-all-crons`). **No existe** todavía un cron que genere archivos a MinIO
  (lo más parecido: `delivery-payout-csv.service.ts`). MinIO: `uploadFile`, `subirStream`.
- **Datos de tienda para LocalBusiness**: stores.name/aliasName/address/logoUrl/timezone/slug;
  branches.addressCommercial/provinceId; theme: brand.displayName, logo, whatsapp/instagram/facebook.
  **No hay teléfono de tienda.** Tienda pública activa = `store_themes.enabled` + `is_published_shop`.
- **Despliegue de tienda-app: no se encontró Dockerfile/Jenkins** (`output: 'standalone'`,
  nginx `*.coolsistema.com → 127.0.0.1:3060`). Averiguar cómo se publica antes de planear.

## Preguntas para discuss
1. Stock «disponible»: ¿todas las sucursales (hoy) o una sucursal fuente por tienda?
2. Variantes en JSON-LD: ¿`ProductGroup` + `hasVariant` por talle/color, o `Product` madre con
   `additionalProperty`? (cambia la API)
3. Marca: ¿campo nuevo, o el nombre de la tienda por defecto?
4. `priceValidUntil`: ¿cuántos días? (Argentina: precios cambian seguido) y quién lo renueva.
5. Tienda vieja `public/shop/:storeId/store`: ¿retirar o canonical?
6. Sitemap/feed: ¿generado por cron líder a MinIO cada 15 min, o SSR con caché fuerte + CDN?
7. Rate limit por UA de bots: ¿cuánto por minuto por bot conocido?
8. ¿Qué tiendas entran primero? (hoy sólo las con theme habilitado)
9. Despliegue de tienda-app (dónde/cómo).

## Etapas siguientes (NO en 112 — candidatas a fases nuevas)
- **Etapa 2 (≈1 mes):** feed compatible con Google Merchant Center por tienda (XML/TSV, pre-generado);
  «puntaje de calidad para IA» en la carga de producto (falta material/talles/descripción);
  botón «generar descripción» (español, sólo con atributos reales).
- **Etapa 3 (≈3 meses):** perfil UCP en el dominio de la tienda (catalog/checkout sobre
  `POST :storeId/checkout`); MCP experimental del catálogo Ventago para probar «buscá vestidos
  talle L con stock» desde Claude/ChatGPT.

## Trampas que el plan ya señala (mantener)
- Datos estructurados exactos > textos SEO; descripciones con relleno bajan la confianza.
- Stock/precio equivocados destruyen la confianza: frecuencia de actualización + `priceValidUntil`
  + regla para marcar agotado.
- No empezar por ACP/UCP.

## Puntos de control (del plan)
- 1 semana: Rich Results Test sin errores en un producto real; `curl` sin JS muestra nombre·precio·stock;
  GPTBot/OAI-SearchBot en los logs.
- 1 mes: pg connections y slow queries (>100 ms) con tráfico de crawlers; menciones en ChatGPT/
  Gemini/Perplexity con 10 preguntas fijas por semana.
- 3 meses: % de tráfico con referrer de IA; pedidos vía IA; decidir UCP/MCP y plan de precios.
