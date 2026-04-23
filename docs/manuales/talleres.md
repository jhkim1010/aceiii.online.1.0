# Manual de Talleres — Ventago

**Versión:** 1.0 (Wave 8, 2026-04-24)
**Audiencia:** Administradores y gerentes de marcas de indumentaria que utilizan Ventago para gestionar producción externa (talleres / CMT).

---

## 1. Introducción

Ventago Talleres es un módulo de control de producción externa (**CMT** — Cut, Make, Trim) inspirado en Zedonk. Permite:

- Planificar cortes (**Cut Ticket** — ticket de corte) y simular márgenes (**Cost Sheet** — hoja de costos) antes de producir.
- Monitorear el estado de cada **Envío** a taller con semáforo de salud (En curso / En riesgo / Atrasado).
- Registrar recepciones con **Control de Calidad (QC)** estructurado y generar retrabajos automáticos.
- Confirmar **Liquidaciones** con cálculo automático a partir de recepciones y tarifas vigentes.
- Recibir alertas diarias a las 08:00 sobre envíos atrasados.

El flujo general de trabajo es:

```
Lote → Cut Ticket → Envío → Recepción (+ QC) → Liquidación → Pago
```

<!-- screenshot: /docs/img/talleres-overview.png -->

---

## 2. Overview y KPIs

La pestaña **📊 Overview** es su punto de partida diario. Está diseñada para responder en 5 segundos: *"¿Dónde están los problemas hoy?"*.

### 4 KPIs principales (parte superior)

| KPI | Color | Significado |
|-----|-------|-------------|
| **Envíos atrasados** | 🔴 Rojo | Acción inmediata requerida — `dueDate < hoy` y aún hay unidades pendientes |
| **En riesgo** | 🟡 Naranja | Vencen en menos de 2 días |
| **En curso** | 🟢 Verde | Dentro del plazo |
| **Total activos** | Navy | Suma global de envíos `PENDING + PARTIAL` |

### 4 gráficos (grid 2×2)

- **Donut de estado** — distribución porcentual de envíos por salud.
- **Top 5 talleres** (últimos 30 días) — por volumen de unidades enviadas.
- **Tendencia de defectos** (12 semanas) — % de unidades defectuosas por semana.
- **Backlog por etapa** — cantidad pendiente por cada etapa del flujo.

### Acción inmediata (parte inferior)

La tabla al pie muestra los **5 envíos más atrasados** con:

- **Drilldown directo:** click en una fila → lleva a la pestaña Envíos filtrada por ese envío.
- **Chips rojos** con el número de días de atraso.
- **Botones disabled** "Reasignar taller" y "Extender plazo" (disponibles en futuras versiones).

<!-- screenshot: /docs/img/talleres-kpi-cards.png -->

---

## 3. Cut Ticket: creación y matriz de tallas (Wave 9)

El **Cut Ticket** (ticket de corte) es el origen de cada producción. Cada Lote tiene un Cut Ticket numerado (ej. `CT-2026-025`) con:

- **Matriz talla × color** — cantidad por combinación.
- **BOM snapshot** — materiales requeridos con precio del momento.
- **Routing path** — flujo de etapas (Corte → Confección → Planchado → QC → Empaque).
- **PDF A4 horizontal** — para pegar en la pared del taller.

<!-- screenshot: /docs/img/cut-ticket-matrix.png -->

### Cómo crear un Cut Ticket

1. Pestaña **Cut Ticket** → seleccione un Lote existente o cree uno nuevo.
2. Complete los 8 campos del header (estilo, temporada, fechas, etc.).
3. Edite la matriz talla × color (inputs numéricos, totales automáticos).
4. Revise el BOM (badges de stock SUFICIENTE / BAJO / AGOTADO).
5. Click **📄 PDF (re-impresión)** para generar el ticket.

**Atención:** una vez que se establece `cut_date`, la matriz queda congelada (read-only). Esta regla garantiza la trazabilidad del corte real contra lo planificado.

---

## 4. WIP y Kanban semáforo (Wave 5)

La pestaña **Pipeline** (Kanban) muestra todas los envíos activos organizados por etapa, con tarjetas de color según salud:

- 🟢 **Verde (ON_TRACK)** — `dueDate ≥ hoy + 2 días`
- 🟡 **Amarillo (AT_RISK)** — `dueDate ∈ [hoy, hoy+2)`
- 🔴 **Rojo (LATE)** — `dueDate < hoy` y quedan unidades pendientes

**Drag & drop:** reordene tarjetas dentro de la misma columna para ajustar prioridades (se guarda automáticamente vía PATCH).

**Filtros:** taller, producto, "sólo LATE".

<!-- screenshot: /docs/img/kanban-semaforo.png -->

---

## 5. Control de Calidad (QC) y Retrabajo (Wave 6)

Al recibir un envío, registre QC estructurado:

- **Código de defecto** (costura abierta / mancha / talla incorrecta / etc.) — catálogo configurable por matriz.
- **Severidad** — `menor` / `mayor` / `crítico`.
- **Acción:**
  - `ACCEPT` — aceptar con defecto leve.
  - `REWORK` — crea envío hijo automático para retrabajo.
  - `SCRAP` — descartar (reduce stock del lote).
  - `CLAIM` — descuento a taller (crea defect con `deductionAmount`).
- **Foto** — subida con redimensionado cliente a 1280px.

**Vendor Scorecard:** `defectRate`, `onTimeRate`, `reworkRate` de los últimos 90 días + sparkline de 12 semanas.

<!-- screenshot: /docs/img/qc-reception.png -->

---

## 6. Liquidaciones: generación automática y confirmación (Wave 7)

Genere liquidaciones (settlements) automáticamente por taller + período:

1. Pestaña **Liquidaciones** → **Generar borrador** → seleccione taller + fechas.
2. El sistema calcula: `Σ (recepciones netas × tarifa vigente en la fecha) − descuentos por defectos`.
3. Revise las líneas (envío → recepción → etapa → qty × unitPrice).
4. Click **Confirmar** — pasa a estado `CONFIRMED` (inmutable).
5. Descargue PDF con CUIT, expedidor, taller, líneas detalladas.

**Importante:** una vez confirmada, no se puede editar (para cumplimiento fiscal).

**Tarifas históricas:** cada tarifa (`VendorEtapa`) tiene `effectiveFrom` / `effectiveTo` — si cambia el precio hoy, las liquidaciones de ayer siguen usando el precio anterior (INV Wave 7).

<!-- screenshot: /docs/img/liquidacion-draft.png -->

---

## 7. Cost Sheet: simulación de márgenes (Wave 10)

Simule el margen de un estilo antes de producir:

- **Material cost** — `Σ (BOM.quantity × material.standardPrice)`.
- **CMT cost** — `Σ (tarifas vigentes de cada etapa del routing)`.
- **Overhead** — `(material + CMT) × overheadPct + shipping / loteSize`.
- **Total cost** — suma de los tres.
- **Margen** — `retailPrice − totalCost`, con % objetivo configurable.

**MarginCard** (fondo navy + dorado) muestra el % de margen:
- ✅ **Verde** si alcanza el objetivo (por defecto 50%).
- ⚠️ **Rojo** si está por debajo.

**Edición en vivo:** modifique `retail_price`, `target_margin_pct`, `overhead_pct`, etc. — se recalcula automáticamente con 500ms de debounce.

<!-- screenshot: /docs/img/cost-sheet-margin.png -->

---

## 8. Alertas y Cron 08:00 (Wave 8)

**Principio:** *"Alerta temprana > reporte tardío"*. Todos los días a las **08:00 (America/Bogota)** el sistema escanea automáticamente todos los envíos con `dueDate < hoy` y `pendingQuantity > 0` y genera una notificación tipo `LATE` a cada taller responsable.

### Canales de entrega

Los talleres reciben la alerta en:

- **App móvil** (Flutter — Portal de Talleres).
- **Correo electrónico** (si está configurado).
- **Dashboard del Portal** (campana de notificaciones).

### Reglas del cron

- **Duplicados:** el cron evita crear la misma alerta dos veces por día (una sola por envío por día, gracias al check `(vendorId, type='LATE', referenceId, createdAt >= hoy_medianoche)`).
- **Fallas:** si el cron falla (por ejemplo, caída de DB), el error se registra en logs (`this.logger.error`) pero no se propaga — el siguiente día se reintenta automáticamente.
- **Configuración:** el horario es fijo a las 08:00. Si necesita cambiarlo, contacte soporte.

### Verificación

- Los administradores pueden ver en la pestaña Overview la tabla **Acción inmediata** con los envíos LATE del día.
- En los logs del servidor: buscar la línea `LATE 알림 크론 완료`.

<!-- screenshot: /docs/img/cron-alert-mobile.png -->

---

## 9. Exportación a Excel y FAQs

### Exportación a Excel

En cada pestaña de lista (**Envíos** / **Talleres** / **Liquidaciones**) encontrará el botón **📥 Excel** en la parte superior derecha. Exporta los datos con los filtros actualmente aplicados — "lo que ve, es lo que obtiene".

El archivo descargado se llama `[tipo]-YYYY-MM-DD.xlsx` (por ejemplo, `envios-2026-04-24.xlsx`).

### FAQs

**¿Puedo editar una liquidación después de confirmarla?**
No. Una vez confirmada (`CONFIRMED`), la liquidación es inmutable por razones fiscales. Para correcciones, cree una nueva liquidación con ajustes.

**¿Qué pasa si un taller cambia su tarifa?**
Cree una nueva tarifa con `effectiveFrom = fecha de cambio`. Las liquidaciones anteriores no se ven afectadas (las líneas usan la tarifa vigente al momento de la recepción).

**¿El Cut Ticket se puede reimprimir?**
Sí, ilimitadamente. El número (`CT-YYYY-NNN`) es único y permanente.

**¿El Cost Sheet se actualiza solo cuando cambian los precios de los materiales?**
No automáticamente. Debe hacer click en **🔄 Recalcular** o editar cualquier campo para disparar el recálculo.

**¿Cómo saber si el cron de 08:00 funcionó?**
En los logs del servidor busque `LATE 알림 크론 완료`. Los talleres verán las notificaciones en su app móvil y en el Portal.

**¿Qué pasa si un envío tiene `dueDate` vacío?**
Se considera `ON_TRACK` siempre (sin fecha límite). No entra en el cron LATE.

**¿Puedo usar Ventago Talleres sin la app móvil de talleres (Portal de Talleres)?**
Sí. El módulo funciona solo con el admin. La app móvil es opcional y agrega visibilidad al taller.

**¿Cómo agrego una nueva etapa (ej. "Bordado")?**
Pestaña **Etapas** → **Nueva etapa** → configure `name`, `order` y tarifas por taller.

---

*Documento generado: 2026-04-24. Proyecto: Ventago POS/ERP. Módulo: Talleres (Phase 16 Wave 8).*
