# Endpoints /prediccion — verificación local (119-16)

API: dev build propio en :5012 contra la DB LOCAL 5432 (log de arranque: conexión 127.0.0.1:5432; CRON_ENABLED=false). Token real de perm.admin@dummy.test (admin, store 6) por /auth/login; superadmin sin tienda (user 1) con JWT firmado localmente (sin contraseña conocida). Sin tokens en este archivo.

| Caso | Ruta | Esperado | Obtenido | Resultado | Extracto |
|---|---|---|---|---|---|
| sin token | `GET /estado` | 401 | 401 | OK | `{"message":"Unauthorized","statusCode":401}` |
| estado | `GET /estado` | 200 | 200 | OK | `{"enabled":true,"watermark":"2026-10-18","cadena":{"id":221,"status":"done","paso":"simulacion","startedAt":"2` |
| datos-usados | `GET /datos-usados` | 200 | 200 | OK | `{"store_id":6,"desde":"2025-11-23","hasta":"2026-10-18","semanas":48,"tickets":2195,"unidades_netas":3392,"uni` |
| analisis/modelos | `GET /analisis/modelos?pageSize=10` | 200 | 200 | OK | `{"data":[{"modelId":245,"nombre":"[REMERA/GENERAL] MC BATIK","sku":"250627001","categoria":"REMERA","temporada` |
| analisis/modelos orden vendido | `GET /analisis/modelos?orden=vendido&pageSize=5` | 200 | 200 | OK | `{"data":[{"modelId":140,"nombre":"[ABRIGOS/CHINA] 바추카","sku":"251637001","categoria":"ABRIGOS","temporad` |
| talles | `GET /analisis/modelos/79/talles` | 200 | 200 | OK | `{"modelId":79,"filas":[{"productId":82,"talle":"S","color":"AMARILLO","vendido":28,"participacion":0.098939929` |
| fundamento | `GET /analisis/modelos/79/fundamento` | 200 | 200 | OK | `{"modelId":79,"nombre":"[jean] 똘똘이","sellThrough":{"valor":0.7526595744680851,"vendidoNeto":283,"ingreso` |
| analisis/atributos fabric | `GET /analisis/atributos?dimension=fabric` | 200 | 200 | OK | `{"combinaciones":[{"clave":"algodon","nModelos":2,"referencia":true,"sellThrough":0.8669778296382731,"velocida` |
| analisis/atributos nivel=variante invalido | `GET /analisis/atributos?dimension=variante` | 400 | 400 | OK | `{"message":["dimension must be one of the following values: fabric, fit, price_band, categoria, temporada, fab` |
| atributos lista | `GET /atributos?pageSize=10` | 200 | 200 | OK | `{"data":[{"modelId":333,"nombre":"[ABRIGOS] ZZ TEST UAT 7007","sku":"263702","fabric":null,"fit":null,"priceBa` |
| atributos PUT | `PUT /atributos/19` | 200 | 200 | OK | `{"productId":19,"fabric":"Algodón","fit":"Regular","priceBand":"medio"}` |
| atributos PUT priceBand invalido | `PUT /atributos/19` | 400 | 400 | OK | `{"message":["priceBand must be one of the following values: bajo, medio, alto"],"error":"Bad Request","statusC` |
| atributos PUT producto ajeno | `PUT /atributos/93` | 404 | 404 | OK | `{"message":"Producto no encontrado","error":"Not Found","statusCode":404}` |
| configuracion GET | `GET /configuracion` | 200 | 200 | OK | `{"enabled":true,"leadTimeDays":21,"moqUnidades":1,"crDefault":null,"fillRateObjetivo":0.9,"reviewPeriodDays":7` |
| configuracion PUT leadTime (admin) | `PUT /configuracion` | 200 | 200 | OK | `{"enabled":true,"leadTimeDays":21,"moqUnidades":1,"crDefault":null,"fillRateObjetivo":0.9,"reviewPeriodDays":7` |
| configuracion PUT enabled por admin de tienda | `PUT /configuracion` | 403 | 403 | OK | `{"message":"Sólo el superadmin puede habilitar o deshabilitar la predicción","error":"Forbidden","statusCode` |
| configuracion PUT lead fuera de rango | `PUT /configuracion` | 400 | 400 | OK | `{"message":["leadTimeDays must not be greater than 365"],"error":"Bad Request","statusCode":400}` |
| backtest/ultimo | `GET /backtest/ultimo` | 200 | 200 | OK | `{"run":{"id":222,"dataThrough":"2026-10-18","isSynthetic":true,"disclaimer":"Datos sintéticos — validación` |
| backtest puntos modelo | `GET /backtest/182/puntos?nivel=modelo&clave=118&modelo=media_movil_8` | 200 | 200 | OK | `{"run":{"id":182,"dataThrough":"2026-10-18","isSynthetic":true,"disclaimer":"Datos sintéticos — validación` |
| backtest puntos nivel=variante | `GET /backtest/182/puntos?nivel=variante&clave=118&modelo=media_movil_8` | 400 | 400 | OK | `{"message":["nivel must be one of the following values: categoria, modelo"],"error":"Bad Request","statusCode"` |
| backtest puntos run ajeno | `GET /backtest/84/puntos?nivel=modelo&clave=118&modelo=media_movil_8` | 404 | 404 | OK | `{"message":"Corrida no encontrada","error":"Not Found","statusCode":404}` |
| simulacion/ultimo | `GET /simulacion/ultimo` | 200 | 200 | OK | `{"run":{"id":223,"dataThrough":"2026-10-18","isSynthetic":true,"disclaimer":"Datos sintéticos — validación` |
| simulacion trazas | `GET /simulacion/183/trazas?modelId=79` | 200 | 200 | OK | `[{"modelId":79,"origin":"2026-03-09","estado":"sin_distribucion"},{"modelId":79,"origin":"2026-04-06","estado"` |
| simulacion traza | `GET /simulacion/183/traza?modelId=79&origin=2026-04-06` | 200 | 200 | OK | `{"estado":"ok","motivo":null,"pasos":{"moq":{"moq":1,"antes":0,"despues":0},"margen":{"n":6,"cr":0.5,"cuantil"` |
| simulacion trazas run ajeno | `GET /simulacion/84/trazas?modelId=79` | 404 | 404 | OK | `{"message":"Corrida no encontrada","error":"Not Found","statusCode":404}` |
| fundamento modelId ajeno | `GET /analisis/modelos/731499/fundamento` | 404 | 404 | OK | `{"message":"Modelo no encontrado","error":"Not Found","statusCode":404}` |
| talles modelId ajeno | `GET /analisis/modelos/731499/talles` | 404 | 404 | OK | `{"message":"Modelo no encontrado","error":"Not Found","statusCode":404}` |
| superadmin sin tienda | `GET /estado` | 400 | 400 | OK | `{"message":"Elegí una tienda para ver la predicción (superadmin sin tienda)","error":"Bad Request","statusCo` |
| superadmin PUT configuracion sin tienda | `PUT /configuracion` | 400 | 400 | OK | `{"message":"Elegí una tienda para ver la predicción (superadmin sin tienda)","error":"Bad Request","statusCo` |
| superadmin con storeId=6 | `GET /estado?storeId=6` | 200 | 200 | OK | `{"enabled":true,"watermark":"2026-10-18","cadena":{"id":221,"status":"done","paso":"simulacion","startedAt":"2` |
| admin pide storeId de otra tienda | `GET /estado?storeId=9` | 403 | 403 | OK | `{"message":"No tienes permiso para consultar la predicción de otra tienda","error":"Forbidden","statusCode":4` |
| superadmin PUT enabled (X-Store-Id: 6) | `PUT /configuracion` | 200 | 200 | OK | `{"enabled":true,"leadTimeDays":21,"moqUnidades":1,"crDefault":null,"fillRateObjetivo":0.9,"reviewPeriodDays":7` |
| ejecutar | `POST /ejecutar` | 201 | 201 | OK | `{"estado":"iniciado","runId":224}` |
| ejecutar inmediato (en_curso o iniciado) | `POST /ejecutar` | 201 | 201 | OK | `{"estado":"en_curso"}` |

Total: 34 OK / 0 discrepancias.

Hallazgo corregido durante la verificación: POST /ejecutar con una corrida 'running' de otro worker/cron devolvía HTTP 500 ("current transaction is aborted") en vez de {estado:'en_curso'}; causa: retry.max=3 del pool reintenta el INSERT dentro de la transacción abortada. Corregido con ON CONFLICT DO NOTHING en crearRun (commit 96e10995, + spec run-registro.spec.ts).
Nota X-Store-Id: el superadmin elige tienda con el header X-Store-Id (el token no basta); PUT /configuracion {enabled} con superadmin + X-Store-Id: 6 -> 200; con admin de tienda -> 403.
