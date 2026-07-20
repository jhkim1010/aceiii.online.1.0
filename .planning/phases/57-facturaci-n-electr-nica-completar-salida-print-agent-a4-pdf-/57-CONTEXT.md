# Phase 57: Facturación Electrónica — Completar salida + A4 PDF + A/M + gateway parity - Context

**Gathered:** 2026-07-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Completar la salida de la factura electrónica AFIP de Ventago a paridad con CoolSyncro: el print-agent imprime el comprobante ESC/POS completo (letra/ítems/IVA/CAE/Vto/QR escaneable), el A4 PDF se emite on-demand con líneas reales, cada sucursal RI elige Factura A o solo M, y el punto de venta lo resuelve el gateway (manager) a partir del `invoice_sucursal`. Orden: W1 print-agent → W2 A4 → W3 A/M.

</domain>

<spec_lock>
## Requirements (locked via SPEC.md)

**7 requirements are locked.** See `57-SPEC.md` for full requirements, boundaries, and acceptance criteria.

Downstream agents MUST read `57-SPEC.md` before planning or implementing. Requirements are not duplicated here.

**In scope (from SPEC.md):**
- print-agent `fiscal-formatter.js` (ESC/POS) extendido: letra/COD, emisor/receptor, ítems, IVA 21% para A/M, CAE/Vto, QR, leyenda
- QR RG 4892 en el ticket (payload del backend `qr-builder.ts`)
- `a4-generator.ts` con ítems reales + discriminación IVA + QR + CAE (paridad `generator.js`)
- Botón "A4 PDF" on-demand en Emitidas y POS
- `afip_issuers.invoice_type` (A|M) + migración 5432/5434 + selector ModalBranch (solo RI) + wire a `decideComprobante`
- Resolución de PV/coolUser vía `manager /data/header` con caché y fallback
- NC/ND reusan la salida mejorada (sin regresión)

**Out of scope (from SPEC.md):**
- Modo SOAP directo WSAA/WSFEv1 (sigue stub)
- Factura C / Monotributo letra C (el contrato CoolSyncro no tiene C)
- Envío digital (WhatsApp/email del PDF)
- Cambiar el modelo de flags F10/F2 y Preferencias AFIP (ya aterrizado)
- Impresión térmica vía PDF pdf-to-printer (Windows-only, descartado)
- Migración retroactiva de comprobantes ya emitidos con A4 vacío

</spec_lock>

<decisions>
## Implementation Decisions

### print-agent — salida ESC/POS + QR (W1, discutido)
- **D-01:** El **QR se genera en el print-agent** desde `qrUrl` (nueva dependencia `qrcode` en print-agent) y se renderiza como `<img src="data:image/png…">` dentro del pipeline HTML→PNG→ESC/POS existente (Phase 11). El backend NO envía el PNG — solo la `qrUrl`. Payload chico.
- **D-02:** El **backend calcula un payload `factura` estructurado** y el print-agent solo renderiza. Forma del payload: `{ letra:'A'|'B'|'M', cod:'NN', number, emisor{razonSocial,cuit,domicilio,condIva,iibb,inicioAct}, receptor{...|ConsumidorFinal}, items:[{cant,desc,pUnit,subtotal}], neto, iva21, total, ivaDiscrim:boolean, cae, caeVto, qrUrl }`. Las reglas AFIP (decidir letra, discriminar IVA) quedan **centralizadas en el backend**, nunca en el agente.
- **D-03:** El `fiscal-formatter.js` actual imprime el QR como **texto de URL** ("Verificar en AFIP: https://…") — se reemplaza por QR imagen escaneable. Además hoy no imprime letra/COD, ítems, receptor ni IVA discriminado — se agregan.

### A4 PDF + fuente única (W2, discutido)
- **D-04:** **Fuente única `buildFactura(voucher, sale, issuer)`** produce el objeto `factura` estructurado (D-02); tanto el thermal (`fiscal-formatter`) como el A4 (`a4-generator`) consumen el MISMO objeto. Cero lógica de comprobante duplicada entre thermal y A4.
- **D-05:** **Partial (invoice_pct):** reusar el helper existente `applyPartial` / `partial-invoice` (el mismo que alimenta `previewPartial`) para producir las líneas escaladas. A4 y ticket muestran exactamente las mismas líneas que el preview F10, coherentes con `imp_total`. NO línea sintética.
- **D-06:** Botón **"A4 PDF"** en el panel Emitidas y en POS tras F10 → `GET /afip/vouchers/:id/pdf` (ya existe), abre/descarga el PDF **sin re-emitir CAE** (el `afip_number` no cambia).

### Claude's Discretion (áreas no seleccionadas para discutir)
- **D-07 (manager /data/header — resolución PV/coolUser):** Resolver PV + coolUser en `afip-issuer.service` (dentro de `loadIssuer` o un resolver dedicado), con **caché in-memory por `cuit+sucursal`, TTL ~60s**, y **fallback a `puntoVenta` local** si el header falla o `invoice_sucursal` no está seteado (con log del fallback). ⚠ **Plan/execute DEBE verificar el endpoint real del gateway Node en vivo antes de cablear** — el path estilo Java `GET /api/data/header/cuit/{cuit}/{sucursal}` devolvió **404** en `invoice.coolsistema.com` (es un servicio Node distinto del ejemplo Java). CoolSyncro apunta a `manager.coolsistema.com/api/data/header/...`; confirmar host (manager vs invoice) y ruta exacta contra el gateway vivo. Sin este dato verificado, mantener el envío actual de `point` local como comportamiento por defecto.
- **D-08 (A/M migración + gate por IVA):** `afip_issuers.invoice_type` default `'A'`; los issuers existentes quedan en `'A'` por el default (sin backfill explícito). `decideComprobante` aplica `'M'` **solo cuando IVA condición = RI Y invoice_type = 'M'**; si IVA ≠ RI se ignora el valor guardado. El selector A/M en ModalBranch es visible **solo para RI**.

### Precondición ya aterrizada (esta sesión — no re-abrir)
- `afip_issuers.invoice_sucursal` (columna + modelo + DTO + campo ModalBranch "Sucursal de invoice"), migración aplicada 5432 + 5434, commiteado.
- POS flujo F10 (F2 = venta sin factura, F10 = venta + preview de emisión) + sección Preferencias ▸ Ventas ▸ Facturación AFIP (toggle FE + % por defecto), commiteado.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Spec de este phase
- `.planning/phases/57-facturaci-n-electr-nica-completar-salida-print-agent-a4-pdf-/57-SPEC.md` — Requisitos, boundaries y acceptance criteria LOCKED. Leer antes de planificar.

### Referencia de paridad (CoolSyncro — proyecto Electron completo, read-only)
- `/Users/marcoskim/Trabajos_Programming/CoolSyncro/src/main/afip/code-maps.js` — CbteTipo (A=1,B=6,M=51; NCA=3,NCB=8,NCM=53; NDA=2,NDB=7,NDM=52), `decideInvoiceType` (CUIT→A, invoice_type='M'→M, else B, export→E), DocType, IVA, RG5616 COND_IVA_RECEPTOR
- `/Users/marcoskim/Trabajos_Programming/CoolSyncro/src/main/afip/rest-gateway-provider.js` — `POST invoice.coolsistema.com/api/invoice?prod&client={coolUser}&cuit={cuit}`; `getHeader/resolveHeaderInfo` → `GET manager.coolsistema.com/api/data/header/cuit/{cuit}/{sucursal}` → `branchs[0].point` + `coolUser` (caché por CUIT); clasificación retryable/ambiguous/fatal (anti doble-CAE)
- `/Users/marcoskim/Trabajos_Programming/CoolSyncro/src/main/afip/cae-issuer.js` — armado de `voucherRequest`, llamada a `decideInvoiceType`
- `/Users/marcoskim/Trabajos_Programming/CoolSyncro/src/main/afip/qr-builder.js` — payload QR RG 4892 (base `afip.gob.ar/fe/qr/?p=`, base64)
- `/Users/marcoskim/Trabajos_Programming/CoolSyncro/src/main/pdf/generator.js` — A4 pdfkit: letra chip + COD, emisor/receptor por letra, tabla ítems, IVA 21% discriminado para A/M, footer QR + CAE + Vto
- `/Users/marcoskim/Trabajos_Programming/CoolSyncro/src/main/pdf/thermal-generator.js` — layout térmico 80mm (referencia de campos, aunque Ventago usa ESC/POS no pdfkit)
- `/Users/marcoskim/Trabajos_Programming/CoolSyncro/src/main/afip/nota-credito.js`, `.../nota-debito.js` — flujo NC/ND, `asoc{type,point,number}` claves inglesas, `creditNote:true`

### Código Ventago a extender
- `api-ventago/src/app/afip/afip-output.service.ts` — `dispatch()`: thermal (`emitPrintInvoice`) + `pdf` (`generateA4Pdf` con `lines:[]` — a llenar); aquí vive el `buildFactura` (D-04)
- `api-ventago/src/app/afip/code-maps.ts` — `decideComprobante` (ya con rama A/M en :165-170), CbteTipo→letra
- `api-ventago/src/app/afip/pdf/a4-generator.ts` — A4 esqueleto, recibe `lines: A4Line[]`
- `api-ventago/src/app/afip/qr-builder.ts` — QR RG 4892 (reusar para `qrUrl`)
- `api-ventago/src/app/afip/partial-invoice.ts` — `applyPartial` (líneas escaladas por pct)
- `api-ventago/src/app/afip/afip-issuer.service.ts` — `loadIssuer` (punto de integración D-07)
- `api-ventago/src/app/afip/providers/rest-gateway.provider.ts` — provider reconciliado 2026-07-19
- `api-ventago/src/app/print/print.service.ts` — `emitPrintInvoice(branchId, data, socketId)`
- `print-agent/src/fiscal-formatter.js` — formatter ESC/POS (HTML→PNG), a extender (D-01/D-02/D-03)
- `ventago-app/src/views/facturacion/EmitidasPanel.tsx` — botón "A4 PDF" (D-06)
- `ventago-app/src/views/admin/stores/details/components/ModalBranch.tsx` — selector A/M solo RI (D-08)

### Proyecto
- `CLAUDE.md` (raíz) — Sequelize underscored, ESLint warning=error, migraciones 5432+5434, apiConnector.remove()
- `.claude/skills/sketch-findings-ace-online` — tema dark navy + gold para UI nueva (botón A4, selector A/M)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `qr-builder.ts` (backend) — genera la `qrUrl` RG 4892; el print-agent solo la recibe y la convierte a imagen con `qrcode`
- `applyPartial` / `partial-invoice.ts` — ya escala líneas por pct; A4 y ticket lo reusan (D-05), mismo output que `previewPartial` (F10)
- `decideComprobante` (code-maps.ts:165-170) — ya soporta la rama A/M; D-08 solo conecta `issuer.invoiceType` + gate IVA=RI
- Pipeline HTML→PNG→ESC/POS del print-agent (Phase 11) — cross-platform; se extiende, no se reemplaza
- `GET /afip/vouchers/:id/pdf` — endpoint A4 ya existe; D-06 solo agrega el botón UI

### Established Patterns
- Migraciones a `api-ventago/migrations/` + aplicar 5432 (local) y 5434 (prod, vía SSH) simultáneamente
- `afip_issuers` upsert hace `{...dto}` spread → agregar `invoice_type` al DTO/modelo lo persiste automáticamente (mismo patrón que `invoice_sucursal`)
- Anti doble-CAE: clasificación ambiguous/retryable/fatal en el provider — D-07 (llamada extra al manager) NO debe introducir reintentos sobre la emisión

### Integration Points
- `buildFactura` centralizado en `afip-output.service` (o helper propio) → alimenta thermal y A4
- `loadIssuer` → resolución manager PV/coolUser (D-07) antes de armar el `voucherRequest`
- print-agent socket `print_invoice` payload → nuevo campo `factura` estructurado (D-02)

</code_context>

<specifics>
## Specific Ideas

- Paridad explícita con CoolSyncro: la letra chip + "COD. NN", la discriminación de IVA 21% para A/M (P.Unit = preuni/1.21 + columna IVA), y el footer "Comprobante Autorizado AFIP/ARCA" con QR + CAE + Vto son el estándar visual a replicar tanto en ticket como en A4.
- El usuario expresó que "el punto de venta lo decide invoice" — D-07 (manager resuelve PV desde `invoice_sucursal`) es la materialización de esa intención.

</specifics>

<deferred>
## Deferred Ideas

- **Modo SOAP directo (WSAA/WSFEv1)** — reemplazar el gateway por conexión AFIP directa; fase posterior (fuera de scope explícito en SPEC).
- **Envío digital del comprobante (WhatsApp/email PDF)** — el output `digital` sigue stub; backlog CRM.
- **Factura C / letra C para Monotributo emisor** — el contrato CoolSyncro no la tiene; si se necesita, fase propia.

</deferred>

---

*Phase: 57-facturaci-n-electr-nica-completar-salida-print-agent-a4-pdf-*
*Context gathered: 2026-07-20*
