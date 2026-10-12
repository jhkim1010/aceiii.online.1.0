# 102-09 Borradores de manuales (para revisión del usuario — D-07)

Estado: **BORRADOR. Nada de esto está en `api-ventago/manuales/`.** Entra sólo lo que el usuario apruebe.
Generado: 2026-10-12. Orden D-08: producción primero (R1), luego fallos de la prueba fija es (F1–F9), luego ko (K1–K10).

## Medición previa (búsqueda sin modelo, `preguntas-asistente.spec.ts`)

| | Hoy | Con TODOS los borradores aplicados (medido en copia, no en `manuales/`) |
|---|---|---|
| es | 17/26 | **25/26** (sólo falla «¿Cómo cargo un artículo nuevo?», ver F5) |
| ko, sólo textos de manual | 18/28 | 18/28 (los textos no bastan: las palabras coreanas no se traducen) |
| ko, textos + tabla K-T (fuera de `files_modified`, requiere OK) | 18/28 | **26/28** |

Datos reales de producción (SELECT sobre `chat_messages`, 60 días, sólo la pregunta, sin datos de ventas — T-102-33):
- 2026-10-12 · store 22 · «opcion de redondeo»
- 2026-10-12 · store 22 · «donde puedo redondear la moneda»
- 2026-09-30 · store 0 · «완전히 아무것도 모르는 사람을 위한 매뉴얼이 존재하는가» → orientación general, **no es un tema de manual: no se escribe nada** (ver K0).
- Las filas de 10-08/10-09 son códigos de soporte, no preguntas (las atiende el aviso de soporte).

Reglas respetadas: no se renombra ningún `## ` existente (esperado y slug); `soporte_remoto_ko.md` no se toca (D-06); no hay manuales coreanos (D-05).

---

## R1 — REDONDEO (pregunta real de una tienda)

- **Origen:** pregunta real, store 22, 2026-10-12 («opcion de redondeo», «donde puedo redondear la moneda»). Además 102-01 sacó `반올림→redondeo` de la tabla porque ningún manual hablaba de redondeo.
- **Tipo:** sección nueva.
- **Destino:** `api-ventago/manuales/manual_producto.md`, al final, nuevo `## 11. Redondeo de precios y de la cotización (opción de redondeo)`.
- **Texto propuesto:**

```markdown
## 11. Redondeo de precios y de la cotización (opción de redondeo)

El redondeo hace que un precio calculado quede en un número "redondo" (por ejemplo, múltiplo de 10 o de 100). Se configura en dos lugares, según qué precio se quiere redondear.

### A. Redondeo de los precios de venta (Precio 1, Precio 2…)

Cada nivel de precio tiene su propia regla de redondeo.

Pasos:
1. Entre al menú «Precios» (Gestión de Precios) y seleccione los productos.
2. En la fila del nivel de precio tilde «Redondeo» y elija el paso: 10, 50, 100, 500 o 1000.
3. Con las flechas elija el sentido: ↑ «Redondear hacia arriba» o ↓ «Redondear hacia abajo».
4. Al aplicar el ajuste, la regla queda guardada en ese nivel de precio.

Para un nivel de precio nuevo («Agregar nuevo precio»): active «Habilitar Redondeo», elija «Precisión» (10, 50, 100, 500, 1000) y «Tipo de Redondeo» (Hacia arriba, Hacia abajo o Redondeo normal).

### B. Redondeo del precio base calculado con la cotización de moneda extranjera

Sirve para productos cuyo costo está en moneda extranjera (dólar, yuan o euro).

Pasos:
1. Entre a «Configuración» → pestaña «Productos» (ruta /configuracion/productos) y busque la tarjeta «Cotización de moneda extranjera».
2. Presione «Cargar» (o «Cambiar» si ya hay cotización).
3. Cargue el valor y elija «Redondeo base» («Sin redondeo», $10, $50, $100, $500 o $1.000) y «Hacia» («↑ arriba» o «≈ cercano»).

Nota: la tarjeta «Moneda» solo define el símbolo y el formato con que se muestran los precios; no redondea ni convierte.
```

- **Evidencia:**
  - Checkbox «Redondeo» + pasos 10/50/100/500/1000 + flechas «Redondear hacia arriba/abajo»: `ventago-app/src/views/prices/components/BulkPricePercentageConfig.tsx:14` (pasos), `:37` (label), `:53` y `:62` (tooltips).
  - La regla se guarda al aplicar: `ventago-app/src/views/prices/components/BulkPriceRules.tsx:236-273` (arma `roundingEnabled/roundingStep/roundingType`) y `:294` (`PUT /price-types`).
  - «Agregar nuevo precio»: `BulkPriceRules.tsx:367`; modal: `views/prices/components/AddPriceTypeModal.tsx:58` (opciones de precisión), `:267` («Habilitar Redondeo»), `:282` («Precisión»), `:296-305` («Tipo de Redondeo»: Hacia arriba / Hacia abajo / Redondeo normal).
  - Cálculo real (subir = `ceil`, bajar = `floor`, normal = `round`): `ventago-app/src/utils/price-calculator.ts:76-78`.
  - Cotización: tarjeta `views/config/productos/currency/CotizacionCard.tsx` (título «Cotización de moneda extranjera», botón `:127` «Cambiar»/«Cargar»); diálogo `components/cotizacion/CotizacionImpactoDialog.tsx:64` (pasos 0/10/50/100/500/1000), `:190` («Redondeo base», «Sin redondeo»), `:204-211` («Hacia»: «↑ arriba» / «≈ cercano»). Se muestra en `views/config/productos/ConfigurationView.tsx:140`.
  - Moneda de las 3 opciones (USD/CNY/EUR): `CotizacionCard.tsx` (comentario del encabezado, 2026-10-05) y `INFO_MONEDA`.
  - «Moneda» no redondea ni convierte: `views/config/productos/currency/CurrencyCard.tsx:70` (tooltip «No realiza conversión de tipo de cambio»).
  - Ruta «Configuración → pestaña Productos»: ya la usa `manual_producto.md:98` (§10).
  - **Sin evidencia / preguntar al usuario:** (1) el nombre exacto del ítem del menú lateral que lleva a `/configuracion/productos` y a `/precios` (el código sólo muestra la ruta; el manual existente dice «Precios» y «Configuración → Productos»); (2) si el cajero necesita permiso: «Cargar/Cambiar» exige la función `cambiar-precio-individual` y «Agregar nuevo precio» `crear-tipo-de-precio` (`CotizacionCard.tsx` y `BulkPriceRules.tsx:366`) — no lo escribí; ¿se agrega «necesita el permiso…»?
- **Pregunta de prueba que debería acertar:** «opcion de redondeo» → medido: queda 1ª; «donde puedo redondear la moneda» → 1ª; «¿Cómo redondeo los precios?» → 1ª. Sugerencia: agregar estas a `preguntas-asistente.ts` (plan 05 es dueño del archivo; no está en `files_modified` de este plan, lo dejo como pregunta).
- **Aprobación:** [ ] aprobado  [ ] con cambios: ______  [ ] rechazado

---

## Fallos es (F1–F9) — todos de vocabulario: el manual ya describe la operación, falta la palabra del cajero

Regla común: se agrega **una línea** dentro de la sección esperada (no se renombra el `## `). Evidencia = la operación ya documentada en esa sección (archivo:línea) + la pantalla real. Las palabras coloquiales (fiar, local, mercadería…) provienen de la propia pregunta de la prueba fija; no agregan funciones.

### F1 — Pago mixto
- **Origen:** fila de prueba «El cliente quiere pagar una parte con tarjeta y el resto en efectivo» (hoy 1ª: venta a crédito).
- **Tipo:** sinónimos en sección existente.
- **Destino:** `manual_ventas.md` → `## 5. Medios de pago y pago mixto`, después de la frase «También se puede dividir el pago entre varios medios.»
- **Texto propuesto:** «Pago mixto (pago dividido o combinado): cuando el cliente quiere pagar una parte con tarjeta y el resto en efectivo, se carga cada medio con su monto hasta cubrir el total.»
- **Evidencia:** `manual_ventas.md:53` y paso 4 (`:58`, «Agregar Métodos de Pago», «+», «Aceptar» se habilita al igualar el total); pantalla `views/homes/components/ProductList/components/PaymentSummaryModal.tsx:742`. «Tarjeta» como medio: el resumen diario lo reconoce por nombre (`api-ventago/src/app/sales/daily-summary.util.ts:84`). **Pregunta al usuario:** los medios dependen de cada tienda; ¿se deja «tarjeta» como ejemplo?
- **Pregunta de prueba:** la de arriba (medido: pasa a acertar).
- **Aprobación:** [ ] aprobado  [ ] con cambios: ______  [ ] rechazado

### F2 — Dejar la venta en espera
- **Origen:** fila «Tengo que dejar una venta en espera y seguir después».
- **Tipo:** sinónimos. **Destino:** `manual_ventas.md` → `## 6. Suspender y retomar una venta`, tras la primera frase.
- **Texto propuesto:** «También se dice: dejar la venta en espera, en pausa o pendiente, y seguir después.»
- **Evidencia:** `manual_ventas.md:63-70`; botón «Suspender (Ctrl+S)» `ProductList.tsx:3579`; lista «Ventas Suspendidas» `views/homes/components/DraftAndDebtors/DraftAndDebtorsList.tsx:473`.
- **Pregunta de prueba:** la de arriba.
- **Aprobación:** [ ] aprobado  [ ] con cambios: ______  [ ] rechazado

### F3 — Devolver la seña
- **Origen:** fila «El cliente se arrepintió y quiere que le devuelva la seña».
- **Tipo:** sinónimos. **Destino:** `credito_senia_favor.md` → `## Cómo cancelar una Seña`, antes de «Si el cliente cancela la reserva…».
- **Texto propuesto:** «También se dice: devolver la seña, reembolso de la seña; el cliente se arrepintió.»
- **Evidencia:** `credito_senia_favor.md:137-155` (opción «Reembolsar en efectivo»); pantalla `views/cuentas-corrientes/SeniaCancelDialog.tsx:64` («Cancelar Seña») y `:88` («Reembolsar en efectivo»); ícono `ClientLedgerView.tsx:290`.
- **Pregunta de prueba:** la de arriba.
- **Aprobación:** [ ] aprobado  [ ] con cambios: ______  [ ] rechazado

### F4 — «Fiar»
- **Origen:** fila «¿Cómo le fío a un cliente?».
- **Tipo:** sinónimos. **Destino:** `credito_senia_favor.md` → `## Cómo vender a crédito`, antes del paso 1.
- **Texto propuesto:** «También se dice: fiar (le fío al cliente), dar fiado, vender a cuenta.»
- **Evidencia:** `credito_senia_favor.md:48-52` (misma operación); `venta_a_credito.md:196` ya usa «fiado total» en un título.
- **Pregunta de prueba:** la de arriba.
- **Aprobación:** [ ] aprobado  [ ] con cambios: ______  [ ] rechazado

### F5 — Cargar un artículo nuevo
- **Origen:** fila «¿Cómo cargo un artículo nuevo?» (hoy 1ª: Nueva Venta / fiado total).
- **Tipo:** sinónimos. **Destino:** `manual_producto.md` → `## 1. Alta de producto simple`, antes de «Un producto simple…».
- **Texto propuesto:** «¿Cómo cargo un artículo nuevo? Se da de alta como producto nuevo (alta de artículo, cargar mercadería nueva).»
- **Evidencia:** `manual_producto.md:5-15`; pantalla `views/products/list/ProductsView.tsx:1962` («＋ Entrada de stock»).
- **Nota:** aun con esto la búsqueda sigue poniendo «Nueva Venta» primero (mide 25/26, ésta es la que queda). Para arreglarla habría que bajar el peso de «artículo» en esa sección: queda como pregunta, no lo toqué.
- **Pregunta de prueba:** la de arriba (con el texto: sigue ✗).
- **Aprobación:** [ ] aprobado  [ ] con cambios: ______  [ ] rechazado

### F6 — Stock por local
- **Origen:** fila «¿Cuánto me queda de un artículo en cada local?».
- **Tipo:** sinónimos. **Destino:** `manual_stock.md` → `## 1. Consulta de stock por sucursal y variante`, tras la primera frase.
- **Texto propuesto:** «Para saber cuánto queda de un artículo en cada local (sucursal, tienda, negocio), se consulta acá.»
- **Evidencia:** `manual_stock.md:5-13`; `views/reports-v2/nuevo/stock/ResumenSucursales.tsx:8` (una tarjeta por sucursal).
- **Pregunta de prueba:** la de arriba.
- **Aprobación:** [ ] aprobado  [ ] con cambios: ______  [ ] rechazado

### F7 — Mandar mercadería de un local a otro
- **Origen:** fila «Quiero mandar mercadería de un local a otro».
- **Tipo:** sinónimos. **Destino:** `manual_stock.md` → `## 2. Movimientos entre sucursales (movido)`, tras la primera frase.
- **Texto propuesto:** «También se dice: mandar, pasar o transferir mercadería de un local a otro.»
- **Evidencia:** `manual_stock.md:15-23`; botón «Registrar Movimiento» `ProductList.tsx:3539`.
- **Pregunta de prueba:** la de arriba.
- **Aprobación:** [ ] aprobado  [ ] con cambios: ______  [ ] rechazado

### F8 — Mandar prendas a coser a un taller
- **Origen:** fila «¿Cómo mando prendas a coser a un taller?».
- **Tipo:** sinónimos. **Destino:** `manual_talleres.md` → `## 5. Envíos a taller`, tras la primera frase.
- **Texto propuesto:** «Sirve para mandar prendas a coser (costura, confección) a un taller.»
- **Evidencia:** `manual_talleres.md:39-46`; `views/talleres/tabs/EnviosTab.tsx:150` («Nuevo Envio»), `views/talleres/envios/EnvioFormDialog.tsx:313` («Registrar envío»). **Pregunta al usuario:** «confección» no aparece en el código de la pantalla; es vocabulario de la industria, ¿lo dejamos?
- **Pregunta de prueba:** la de arriba.
- **Aprobación:** [ ] aprobado  [ ] con cambios: ______  [ ] rechazado

### F9 — Compré rollos de tela
- **Origen:** fila «Compré rollos de tela, ¿dónde los cargo?».
- **Tipo:** sinónimos. **Destino:** `manual_materiaprima.md` → `## 3. Ingreso de compra: proveedor, rollos y costo`, tras la primera frase.
- **Texto propuesto:** «Cuando se compran rollos de tela, se cargan acá (compra de tela).»
- **Evidencia:** `manual_materiaprima.md:23-30`; «Reponer stock» `views/materia-prima/TelasMadreView.tsx:552`.
- **Pregunta de prueba:** la de arriba.
- **Aprobación:** [ ] aprobado  [ ] con cambios: ______  [ ] rechazado

---

## Fallos ko (K1–K10) — prioridad pantallas de gestión (D-04)

Los 10 fallos ko de 102-05. Los **textos F1–F9 y R1 ya cubren la sección destino**; lo que falta es que las palabras coreanas lleguen a esas palabras españolas, y eso lo hace la tabla `terminos-ko-es.ts` (no un manual coreano, D-05). Esa tabla **no está en `files_modified` de este plan**, por eso K-T es una propuesta que necesita tu OK explícito.

| # | Pregunta ko (prueba) | Tipo | Destino (sección esperada, sin renombrar) | Texto propuesto | Evidencia | Pregunta de prueba |
|---|---|---|---|---|---|---|
| K1 | 판매 처음 할 때 어디서부터 시작해요? | tabla | `manual_ventas.md` § 2 Nueva Venta | sin texto de manual; tabla: 처음/시작 → nueva, venta | `manual_ventas.md:17` | la misma |
| K2 | 손님이 카드로 일부, 나머지는 현금으로 낸대요 | F1 + tabla | § 5 pago mixto | texto F1; tabla: 일부/나머지 → mixto, pago | F1 | la misma |
| K3 | 손님이 마음 바꿔서 계약금 돌려달래요 | F3 + tabla | `credito_senia_favor.md` Cómo cancelar una Seña | texto F3; tabla: 돌려/반환 → devolver, reembolsar | F3 | la misma |
| K4 | 외상값 갚으러 손님이 왔는데 어디서 받아요? | tabla | `cobro_credito.md` Flujo paso a paso — cobrar un pago | tabla: 갚/수금 → cobrar, deuda | `cobro_credito.md:39` | la misma |
| K5 | 손님이 맡겨둔 돈이 있는데 이번 구매에 쓰려면요? | tabla | `credito_senia_favor.md` Cómo usar el saldo a favor | tabla: 맡겨둔/잔액 → favor, saldo (hoy «(nada)») | `credito_senia_favor.md:97-112`; chip «Usar Saldo a favor» | la misma |
| K6 | 가격 한꺼번에 올리는 방법 좀 알려주세요 | tabla | `manual_producto.md` § 5 Gestión de precios | tabla: 올리/인상 → precio, ajuste | `manual_producto.md:48-56` | la misma |
| K7 | 다른 매장으로 물건 옮기려면요? | F7 + tabla | § 2 Movimientos entre sucursales | texto F7; tabla: 옮기 → movido, mercaderia | F7 | la misma |
| K8 | 공방에 옷 봉제 맡기려면 어떻게 보내요? | F8 + tabla | § 5 Envíos a taller | texto F8; tabla: 맡기 → envio, taller | F8 | la misma |
| K9 | 원단 롤 샀는데 어디에 입력해요? | F9 + tabla | `manual_materiaprima.md` § 3 | texto F9; tabla: 입력/샀 → compra, entrada | F9 | la misma |
| K10 | 지원팀이 제 화면을 봐줬으면 좋겠어요 | — | `soporte_remoto.md` | **no se propone nada**: el único texto coreano de soporte es `soporte_remoto_ko.md` y no se toca (D-06). Queda ✗. | — | — |

### K-T — Propuesta de tabla (requiere tu OK; archivo `api-ventago/src/app/chat/knowledge/terminos-ko-es.ts`)

Entradas medidas en una copia (no aplicadas): `반올림/올림 → redondeo, precio` (re-agrega la que 102-01 eliminó, ahora existe `redondeo` por R1), `일부/나머지 → mixto, pago`, `돌려/반환 → devolver, reembolsar`, `갚/수금 → cobrar, deuda`, `맡겨둔/잔액 → favor, saldo`, `올리/인상 → precio, ajuste`, `옮기 → movido, mercaderia`, `맡기/보내어 → envio, taller`, `입력/샀 → compra, entrada`, `처음/시작 → nueva, venta`.
Medido: ko **18/28 → 26/28** (con F1–F9 y R1 aplicados). Quedan ✗: K6 (`가격 한꺼번에 올리는 방법`: la sección de redondeo le gana a «Gestión de precios») y K10. Primer intento con `받아` como clave de cobro rompió «계약금 받아 놓으려면» (seña): quitada.
Dependencia: la prueba anti-typo de la tabla exige que `redondeo` exista en los manuales → R1 tiene que entrar antes o con la tabla.
- **Aprobación K-T:** [ ] aprobado  [ ] con cambios: ______  [ ] rechazado (si se rechaza, el mínimo ko no sube y K1–K9 quedan como están)

### K0 — «완전히 아무것도 모르는 사람을 위한 매뉴얼이 존재하는가» (store 0, 09-30)
Es una pregunta de orientación («¿existe un manual para quien no sabe nada?»), no un tema. **Sin evidencia de qué responder; no se escribe nada.** Pregunta al usuario: ¿se quiere una respuesta fija de «qué puedo preguntarte» en el asistente (eso sería un cambio de producto, no de manual)?

---

## Mínimos de búsqueda a subir en Task 3 (si se aprueba todo)

`MINIMO_ACIERTOS_ES` 17 → 25 · `MINIMO_ACIERTOS_KO` 18 → 26 (sólo si K-T aprobada; si no, 18). Si se aprueba parte, se re-mide y se sube sólo al valor medido.

## Qué se necesita de vos

Para cada entrada (R1, F1–F9, K-T): «aprobado», «aprobado con cambios (cuáles)» o «rechazado». Preguntas abiertas: nombres de menú de R1, «tarjeta» en F1, «confección» en F8, la regla de permisos en R1, y K0.
