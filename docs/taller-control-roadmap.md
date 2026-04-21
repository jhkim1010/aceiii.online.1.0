# Roadmap de Control de Talleres (Subcontratación CMT)
## Ventago POS/ERP — MVP 4-6 semanas

**Fecha:** 2026-04-20
**Autor:** Marcos (con asistencia de Claude)
**Alcance:** Módulo `api-ventago/src/app/subcon/*` y `ventago-app/src/views/talleres/*`
**Objetivo:** Llevar el control de talleres (subcontratistas CMT) de un nivel "registro contable" a un nivel "operativo realista" — inspirado en Zedonk, AIMS 360 y Apparel Magic — sin inflar el sistema.

---

## 1. Contexto actual

### 1.1 Modelo de datos existente

El módulo `subcon/` ya cubre los cimientos de un flujo CMT (Cut-Make-Trim):

| Tabla | Rol | Observación |
|---|---|---|
| `talleres_vendors` | Maestro de taller | Tiene `pinHash` para portal, rating 0-5, `settlementTerms` libre |
| `talleres_etapas` | Fases de proceso (Corte, Confección, Planchado…) | Definibles por tienda |
| `talleres_vendor_etapas` | M:N vendor↔etapa con `unitPrice` | Tarifario por vendor/etapa |
| `talleres_lotes` | Lote de producción por `productId` | `availableQuantity` decrece al enviar |
| `talleres_envios` | Envío físico a un vendor en una etapa | `pendingQuantity`, `sourceRecepcionId` (encadenable) |
| `talleres_recepciones` | Recepción/retorno de un envío | `receivedQuantity` + `rejectedQuantity` |
| `talleres_envio_materiales` | Materiales entregados con el envío | Consumo de almacén |
| `talleres_orders` | Pedido global (legacy) | Estado REQUESTED→IN_PROGRESS→DELIVERED→SETTLED |
| `talleres_deliveries` / `talleres_defects` | Entregas y defectos (legacy) | — |
| `talleres_settlements` / `talleres_payments` | Liquidación y pago | `SubconSettlement`/`SubconPayment` |

### 1.2 Frontend existente

Vistas bajo `ventago-app/src/views/talleres/`:
- `TalleresMainView` (hub con tabs)
- `vendors`, `etapas`, `lotes`, `envios`, `pedidos`, `deliveries`, `defects`, `liquidaciones`
- `control/talleres_ControlPanel.tsx` (panel agregador)
- Hooks SWR: `useTalleresEtapas`, `useTalleresVendors`, `useTalleresEnvios`

### 1.3 Problemas observados en el log `2026-04-20`

```
column "pin_hash" does not exist
  → GET /api/talleres/vendors/all (500)
  → POST /api/talleres/vendors (500)
```

La migración del campo `pin_hash` (portal de vendor) **no se aplicó en producción/local actual**. El modelo lo declara pero la tabla aún no lo tiene. Esto bloquea el listado y alta de vendors. **Debe resolverse antes de cualquier Fase nueva.**

Otros errores del log (`product_branches`, `use_variants`, `s.store_id` ungrouped) no son del dominio `talleres/` pero conviene agruparlos en la misma ronda de estabilización.

---

## 2. Benchmark — Sistemas reales de referencia

Resumen de lo que hacen los líderes del sector **moda/confección** para control de subcontratistas (CMT). Se selecciona **sólo lo aplicable a un MVP ligero**.

### 2.1 Zedonk (boutique UK, marcas de diseño)
- **Cut Tickets**: ficha de corte por lote con tallas/colores, materiales consumidos, taller asignado, fecha prometida.
- **WIP por etapa**: cada unidad tiene un estado por etapa (Cut→Sew→Finish→QC→Ready).
- **Cost Sheet por estilo**: desglose CMT + materiales + overhead, auto-cálculo de margen.
- **Due date alerts**: 3 niveles — a tiempo / riesgo (≤48h) / atrasado.

### 2.2 AIMS 360 (mid-market US apparel)
- **Contractor Portal**: cada taller entra con PIN y ve sólo sus órdenes; marca "started / in progress / completed" por unidad.
- **Bundle tracking**: envío agrupado con código (BUNDLE-YYYY-NNN), se escanea al salir y entrar.
- **Penalty rules**: configurable por vendor — %descuento por retraso por día, % por bulto defectuoso.

### 2.3 Apparel Magic
- **Cuts & Bundles workflow**: corte→fajos→tickets por fajo→confección→QC→almacén. Cada fajo lleva ticket impreso con barcode.
- **Pay Rate Grid**: tarifa por operación (coser cuello, pegar manga, ojales) → suma = costo total por prenda.
- **Claims / Chargebacks**: registro de descuentos al vendor con motivo y documento adjunto.

### 2.4 Lo que **NO** copiamos (demasiado pesado para MVP)
- Ticket con barcode por fajo → requiere zebra-agent dedicado + escaneo (Fase 2+).
- Pay Rate Grid por operación (cuello, manga, dobladillo) → la granularidad actual `vendor_etapa.unitPrice` es suficiente.
- EDI / integración aduanera.
- Módulos de nómina para operarios internos del taller.

### 2.5 Principios que adoptamos
1. **Una unidad sólo está en una etapa a la vez** (estado atómico).
2. **El envío (bundle) es la unidad de trabajo**, no la prenda individual.
3. **Toda reducción de pago al vendor debe tener documento y motivo** (auditoría).
4. **El vendor ve sólo lo suyo** (principio de mínimo privilegio en el portal).
5. **Alerta temprana > reporte tardío** — semáforo de fechas, no listados pasivos.

---

## 3. Roadmap MVP — 4 a 6 semanas

Timeline agresivo: **una semana = una ola** + Fase 0 previa obligatoria.

### Fase 0 — Estabilización (3-5 días, **bloqueante**)

Sin esto no avanza nada. Viene directamente del log del 2026-04-20.

- [ ] **Migración `pin_hash`** en `talleres_vendors`
  ```sql
  ALTER TABLE talleres_vendors
    ADD COLUMN IF NOT EXISTS pin_hash VARCHAR(255),
    ADD COLUMN IF NOT EXISTS pin_updated_at TIMESTAMP;
  ```
  Aplicar en local + operación (`srv803182`, contenedor `dbpostgres`).
- [ ] Verificar resto de migraciones pendientes del módulo (`talleres_*`) — ejecutar `list_migrations` contra `ventago`.
- [ ] Smoke test: `GET /api/talleres/vendors/all`, `POST /api/talleres/vendors` → 200.
- [ ] Revisar que `SubconModule` no cree **conexiones extra** al pool (usar el `sequelize` por defecto, pool max=50, sin instancias paralelas).

**Entregable:** log limpio de errores `talleres/*` durante 24h.

---

### Fase 1 — Semáforo de Estado & Tablero Kanban (Semana 1)

**Objetivo:** que con una mirada se sepa qué lote está en qué taller, en qué etapa, y si llega tarde.

#### 1.1 Backend
- [ ] Campo calculado (virtual o endpoint agregador) `envio.healthStatus`:
  - `ON_TRACK` — `dueDate` ≥ hoy + 2d
  - `AT_RISK` — `dueDate` entre hoy y hoy+2d
  - `LATE` — `dueDate` < hoy y `pendingQuantity` > 0
- [ ] Endpoint `GET /api/talleres/control/kanban?branchId=X`
  - Responde `{ etapas: [...], envios: [...groupBy etapaId] }`
  - **Cache 30s** en memoria (`MemoryCacheService`) — no crear índices nuevos en pool.

#### 1.2 Frontend
- [ ] Vista `talleres_ControlPanel.tsx` → **Kanban por etapa**
  - Columnas = `etapas` (ordenadas por `order`)
  - Tarjetas = envíos activos con `vendor.name`, `lote.loteNumber`, `pendingQuantity`, badge de semáforo
  - Drag-drop **visual** (sin mover DB) para reordenar prioridad — se persiste en `envio.priority` (nuevo campo `INTEGER DEFAULT 0`).
- [ ] Filtros rápidos: `vendor`, `producto`, `sólo atrasados`.

**Esfuerzo estimado:** 3-4 días.
**Dependencias:** ninguna más allá de Fase 0.

---

### Fase 2 — Control de Calidad & Rework (Semana 2)

**Objetivo:** cuando llega un envío, registrar la recepción **con QC estructurado**, no solo un número.

#### 2.1 Backend — Ampliar `recepciones`
- [ ] Nueva tabla `talleres_qc_items`
  ```
  id, recepcion_id, defect_code (FK), quantity, severity (MINOR|MAJOR|CRITICAL), action (ACCEPT|REWORK|SCRAP|CLAIM), photo_url (MinIO), notes
  ```
- [ ] Nueva tabla `talleres_defect_codes` (catálogo por tienda)
  - Ejemplos semilla: `COSTURA_ABIERTA`, `MANCHA`, `TALLA_INCORRECTA`, `FALTA_ACCESORIO`, `COLOR_DIFERENTE`.
- [ ] Endpoint `POST /api/talleres/recepciones` — acepta `qcItems[]` en el mismo payload.
- [ ] Regla de negocio:
  - Si `action=REWORK` → generar automáticamente `Envio` hijo con `sourceRecepcionId` al mismo vendor y etapa.
  - Si `action=SCRAP` → descontar de `lote.availableQuantity` y registrar pérdida.
  - Si `action=CLAIM` → crear `SubconDefect` con `deductionAmount` para la liquidación.

#### 2.2 Frontend
- [ ] Modal de recepción con tabla editable de QC (código, cantidad, severidad, foto).
- [ ] Subida de foto vía MinIO (`MinioService.uploadFile`) — carpeta `talleres/qc/{storeId}/{recepcionId}/`.
- [ ] Vista `talleres_DefectsListView` → agregar columna "foto" y filtro por `defect_code`.
- [ ] **Scorecard por vendor** en `VendorDetailPanel`:
  - `defectRate = Σdefect_qty / Σreceived_qty` últimos 90 días
  - `onTimeRate = envíos entregados ≤ dueDate / total`
  - `reworkRate`

**Esfuerzo estimado:** 4-5 días.

---

### Fase 3 — Tarifario y Liquidación Automática (Semana 3)

**Objetivo:** que la liquidación se genere sola a partir de recepciones aceptadas, restando defectos.

#### 3.1 Backend
- [ ] Reforzar `VendorEtapa`:
  - Añadir `effectiveFrom`, `effectiveTo` (historización de tarifas).
  - Validación: sólo una tarifa activa por `(vendor, etapa)` en un momento dado.
- [ ] Servicio `SubconSettlementService.generateForPeriod(vendorId, from, to)`
  - Junta todas las `Recepcion.receivedQuantity - rejectedQuantity` del período.
  - Multiplica por `VendorEtapa.unitPrice` vigente en la fecha de recepción.
  - Resta `SubconDefect.deductionAmount` del mismo período.
  - Devuelve borrador `SubconSettlement` + líneas detalle.
- [ ] Endpoint `POST /api/talleres/settlements/draft` (idempotente por `(vendorId, periodStart, periodEnd)`).
- [ ] Endpoint `POST /api/talleres/settlements/:id/confirm` → bloquea edición, cambia estado a `CONFIRMED`.

#### 3.2 Frontend
- [ ] Vista `talleres_LiquidacionesListView` → botón "Generar borrador" (selector vendor + rango).
- [ ] Detalle de liquidación con desglose línea por línea (envío → recepción → etapa → unidad × precio).
- [ ] Exportar PDF (usar plantilla DOCX→PDF existente o jsPDF ligero).

**Esfuerzo estimado:** 4-5 días.
**Cuidado con el pool:** la generación de borrador debe usar **una sola transacción** con `Promise.all` para las queries de lectura, luego un único `bulkCreate` de líneas.

---

### Fase 4 — Portal del Vendor (Semana 4)

**Objetivo:** el taller entra con su PIN y ve/actualiza sus envíos sin llamar por WhatsApp.

El módulo `vendor-portal` ya existe parcialmente (`VendorPortalModule`, `pinHash`). Completar el flujo.

#### 4.1 Backend
- [ ] `POST /api/vendor-portal/login` (vendorId + PIN) → JWT corto (4h) con scope `vendor:{id}`.
- [ ] Guard `VendorScopeGuard` — filtra toda query por `vendorId` del token.
- [ ] Endpoints mínimos:
  - `GET /vendor-portal/envios` (sólo suyos, status ≠ COMPLETED)
  - `POST /vendor-portal/envios/:id/start` → marca `startedAt`
  - `POST /vendor-portal/envios/:id/progress` → actualiza `% avance`
- [ ] **NO** permitir al vendor editar `unitPrice` ni ver otras vendors.

#### 4.2 Frontend
- [ ] Página pública `/vendor-portal/login` (fuera del layout principal de Ventago).
- [ ] Vista ligera: lista de envíos, botón "Marcar iniciado", campo "% avance", nota.
- [ ] **Mobile first** — los talleres entran desde celular.
- [ ] Notificación realtime (Socket.io, namespace `/vendor-portal`) cuando hay nuevo envío.

**Esfuerzo estimado:** 5 días.

---

### Fase 5 — Alertas, Reportería & Dashboard (Semana 5, opcional en MVP)

**Objetivo:** convertir el Kanban en información accionable.

- [ ] Cron diario 08:00 (`@nestjs/schedule`) — revisa envíos atrasados, envía notificación al owner del `branchId`.
- [ ] Dashboard `talleres/dashboard`:
  - Envíos por estado (ON_TRACK/AT_RISK/LATE) — donut.
  - Top 5 vendors por volumen del mes — bar.
  - Evolución defect rate últimas 12 semanas — line.
  - Backlog por etapa — stacked bar.
- [ ] Exportación Excel (usar skill `xlsx`) — listado de envíos con filtros actuales.

**Esfuerzo estimado:** 3-4 días.

---

### Fase 6 — Buffer & Pulido (Semana 6)

- [ ] Migración definitiva a producción (`srv803182`), validación `list_migrations`.
- [ ] Carga de datos reales para 1-2 talleres piloto.
- [ ] Revisión de índices:
  - `talleres_envios (vendor_id, status, due_date)`
  - `talleres_recepciones (envio_id, recepcion_date)`
  - `talleres_settlements (vendor_id, period_start, period_end)`
- [ ] Revisión de queries N+1 (sobre todo en Kanban, suele ser el cuello de botella).
- [ ] Docs de usuario final (`docs/manuales/talleres.md`) — en español.
- [ ] Capacitación al usuario (2 sesiones, 1h cada una).

---

## 4. Arquitectura resumida (post-MVP)

```
┌─────────────────────────────────────────────────────────────┐
│                     FRONTEND (ventago-app)                  │
│  ┌────────────┐  ┌────────────┐  ┌────────────────────┐     │
│  │  Kanban    │  │ Liquidar.  │  │ Vendor Portal      │     │
│  │  Control   │  │ (draft)    │  │ (mobile, PIN)      │     │
│  └─────┬──────┘  └─────┬──────┘  └─────────┬──────────┘     │
└────────┼────────────────┼───────────────────┼───────────────┘
         │ SWR 30s        │                   │ JWT 4h scope
         ▼                ▼                   ▼
┌─────────────────────────────────────────────────────────────┐
│                  BACKEND (api-ventago)                      │
│  /api/talleres/*          /api/vendor-portal/*              │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ EnvioService  RecepcionService  SettlementService     │  │
│  │ QcService     DefectCodeService VendorPortalService   │  │
│  └───────────────────┬───────────────────────────────────┘  │
│           MemoryCache (30s kanban, 60s refs)                │
└───────────────────────┬─────────────────────────────────────┘
                        │ pool max=50, sin duplicar
                        ▼
┌─────────────────────────────────────────────────────────────┐
│               PostgreSQL 15 (ventago)                       │
│  talleres_vendors       talleres_etapas                     │
│  talleres_vendor_etapas talleres_lotes                      │
│  talleres_envios        talleres_recepciones                │
│  talleres_qc_items (nuevo)  talleres_defect_codes (nuevo)   │
│  talleres_settlements   talleres_payments                   │
└─────────────────────────────────────────────────────────────┘
```

---

## 5. Reglas transversales (aplican a todas las fases)

### 5.1 PostgreSQL — pool
- **No crear nuevas instancias `Sequelize`**. Usar el singleton de `DatabaseModule`.
- Pool **`max=50`**, no tocar. Si una query satura, optimizar SQL o cachear, **no aumentar pool**.
- Transacciones: cerrar siempre en `finally` (commit o rollback). Auditar en Fase 0.
- Toda query del Kanban/Dashboard debe pasar por `MemoryCacheService` (TTL 30s).

### 5.2 Sequelize / naming
- `underscored: true` está global. Modelos en `camelCase`, DB en `snake_case` (ej. `dueDate` → `due_date`).
- Migraciones SQL crudas en `api-ventago/migrations/*.sql` — ejecutar en contenedor Docker del srv803182.

### 5.3 Frontend / performance
- **Nunca** `useEffect + apiConnector.get` para datos de referencia. Usar/crear SWR hook en `src/hooks/api/`.
- `pageSize` máximo 50.
- Código dividido con `next/dynamic({ ssr: false })` para vistas nuevas de talleres.
- `React.memo` en tarjetas Kanban (alto tráfico de render).

### 5.4 ESLint (bloquea build)
- Línea vacía antes de `return`.
- Línea vacía antes de `//` comentario.
- Sin imports no usados.

### 5.5 Seguridad portal vendor
- PIN hasheado con bcrypt (`saltRounds=10`).
- JWT vendor-scope ≠ JWT de usuario interno (distinto `secret` / `audience`).
- Logs de login en `vendor_portal_audit` (vendorId, ip, result, timestamp).

---

## 6. Riesgos y mitigaciones

| Riesgo | Impacto | Mitigación |
|---|---|---|
| Migración `pin_hash` olvidada en prod (ya ocurrió) | Alto — módulo caído | Fase 0 obligatoria + `IF NOT EXISTS` + verificación `list_migrations` |
| Kanban con N+1 queries | Medio — lentitud visible | Cache 30s + eager `include` explícito + índice `(vendor_id,status,due_date)` |
| Borrador de liquidación mal calculado | Alto — problema legal | Estado `DRAFT`→`CONFIRMED`, CONFIRMED es inmutable, pruebas unitarias sobre `generateForPeriod` |
| Portal vendor con PIN débil | Medio — suplantación | PIN mín. 6 dígitos, rate limit 5 intentos/15min, bloqueo tras fallos |
| Crecimiento del pool por Socket.io vendor-portal | Alto | Socket.io namespace separado, sin query DB en `connect` (sólo auth JWT cacheado) |
| Fotos QC saturan MinIO | Bajo-Medio | Resize en cliente a max 1280px antes de upload, política de retención 2 años |

---

## 7. Entregables finales (al día 30-42)

1. Migraciones SQL aplicadas (`talleres_qc_items`, `talleres_defect_codes`, campos nuevos en `vendors`/`envios`).
2. 8-10 endpoints nuevos en `api/talleres/*` y `api/vendor-portal/*`.
3. 4 vistas nuevas/mejoradas en `ventago-app` (Kanban, QC Modal, Liquidación detalle, Portal vendor).
4. 3 hooks SWR nuevos (`useTalleresKanban`, `useTalleresQcCodes`, `useVendorScorecard`).
5. Documentación de usuario en `docs/manuales/talleres.md`.
6. 1 taller piloto operando en real durante la última semana.

---

## 8. Fuera de alcance (Fase 2+ del producto)

Documentado para que se sepa que se **decidió conscientemente** dejarlo para después:

- Código de barras por fajo (requiere zebra-agent integrado con envíos).
- Tarifa por operación atómica (coser cuello vs pegar manga).
- Chat/WhatsApp integrado con vendor (actualmente portal + notificación).
- Firma electrónica de liquidación.
- Conciliación contable automática con módulo `gastos/`.
- Previsión de capacidad por vendor (¿cuántas prendas/día puede absorber?).
- App móvil nativa para vendor (el portal mobile-web cubre el MVP).

---

## 9. Siguientes pasos inmediatos (esta semana)

1. **Hoy** — Aplicar migración `pin_hash` en local y verificar que `GET /api/talleres/vendors/all` responde 200.
2. **Día +1** — Inventario de migraciones pendientes en srv803182 (`list_migrations`).
3. **Día +2** — Kick-off Fase 1: diseño UI del Kanban (mock en Figma o directamente componente dummy).
4. **Día +3** — Crear rama `feature/talleres-kanban` y primer endpoint `/api/talleres/control/kanban`.

---

**Revisión del roadmap:** revisar al final de cada Fase con el último log (`api-ventago/logs/combined-YYYY-MM-DD.log`) para detectar errores nuevos del dominio `talleres/*` y ajustar prioridades.
