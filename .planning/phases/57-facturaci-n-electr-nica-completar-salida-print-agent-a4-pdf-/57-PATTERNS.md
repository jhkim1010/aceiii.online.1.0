# Phase 57: Facturación Electrónica — Completar salida + A4 PDF + A/M + gateway parity - Pattern Map

**Mapped:** 2026-07-20
**Files analyzed:** 15
**Analogs found:** 15 / 15

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `api-ventago/src/app/afip/build-factura.ts` (NEW) | service/utility | transform | `api-ventago/src/app/afip/afip-voucher.service.ts` (`buildPartialItems`/`resolveReceptor`) + `CoolSyncro/src/main/pdf/thermal-generator.js` (field assembly order) | role-match (backend fn is new, but assembly inputs/shape are 1:1 with existing helpers) |
| `api-ventago/src/app/afip/afip-output.service.ts` (MODIFIED) | service | request-response / dispatch | itself (existing `dispatch()`) + `CoolSyncro/src/main/afip/rest-gateway-provider.js` (`issueCae` orchestration) | exact (extending existing file) |
| `api-ventago/src/app/afip/afip-issuer.service.ts` (MODIFIED — add `resolvePvAndCoolUser`) | service | request-response + external HTTP + cache | `CoolSyncro/src/main/afip/rest-gateway-provider.js` (`getHeader`/`resolveHeaderInfo`) for the HTTP/cache logic + `api-ventago/src/app/vto/vto.service.ts` / `sizes.service.ts` for the project's `MemoryCacheService` idiom | role-match (external-HTTP pattern from CoolSyncro, cache idiom from Ventago) |
| `api-ventago/src/app/afip/afip.controller.ts` (MODIFIED — `issue()` calls `dispatch()`) | controller | request-response | itself (existing `reprint`/`pdf` endpoints in same file) | exact |
| `api-ventago/src/app/afip/code-maps.ts` (MODIFIED — wire `invoiceType` + RI gate) | utility | transform | itself (`decideComprobante` already has the A/M branch at :165-170) + `CoolSyncro/src/main/afip/code-maps.js` (`decideInvoiceType`) | exact |
| `api-ventago/src/app/afip/pdf/a4-generator.ts` (MODIFIED — real lines + IVA discrim) | service (PDF gen) | file-I/O / transform | `CoolSyncro/src/main/pdf/generator.js` (A4 pdfkit, letra chip + COD + emisor/receptor + IVA table) | exact (explicit paridad target in SPEC) |
| `api-ventago/src/app/afip/nota-credito.service.ts` (MODIFIED — call `dispatch()` after `emit()`) | service | event-driven / CRUD | `api-ventago/src/app/afip/afip-voucher.service.ts::issue()` → controller `dispatch()` wiring pattern (same shape, new call site) | role-match |
| `api-ventago/src/app/afip/nota-debito.service.ts` (MODIFIED — same as NC) | service | event-driven / CRUD | same as `nota-credito.service.ts` (near-identical sibling file, read this session) | exact (sibling file) |
| `api-ventago/src/app/afip/models/afip-issuer.model.ts` (MODIFIED — add `invoiceType` column) | model | CRUD | itself (`invoiceSucursal` column added this same session, identical pattern) | exact |
| `api-ventago/src/app/afip/dto/upsert-issuer.dto.ts` (MODIFIED — add `invoiceType` field) | DTO | request-response validation | itself (`invoiceSucursal` field added this session) | exact |
| `api-ventago/migrations/afip-issuer-invoice-type.sql` (NEW) | migration | batch (DDL) | `api-ventago/migrations/afip-issuer-invoice-sucursal.sql` (same table, same session, exact `ADD COLUMN IF NOT EXISTS` pattern) | exact |
| `print-agent/src/fiscal-formatter.js` (REWRITTEN) | utility (HTML formatter) | transform | `CoolSyncro/src/main/pdf/thermal-generator.js` (field layout/order: letra box, COD, emisor, receptor A/M vs B, items, IVA discrim, CAE/QR/leyenda) + `print-agent/src/qr-formatter.js` (QR `data:image` rendering, same repo) | exact (CoolSyncro = explicit parity target; qr-formatter = working local QR pattern) |
| `print-agent/main.js` (MODIFIED — `print_invoice` handler branches on `payload.factura`) | event-driven handler (socket.io) | event-driven | itself — the sibling `print_fiscal` handler (lines 996-1023, already calls `formatFiscalHtml`+`renderHtmlToPng`+`printImage`) is the exact target shape to replicate inside `print_invoice` | exact (same file, sibling handler) |
| `ventago-app/src/views/facturacion/EmitidasPanel.tsx` (MODIFIED — "A4 PDF" button) | component | file-I/O (blob download) | `ventago-app/src/views/talleres/cut-ticket/CutTicketTab.tsx` (`handlePdf`, Wave 7 `apiConnector.get(path,{responseType:'blob'})` → `Blob`→`URL.createObjectURL`→anchor click pattern) | exact |
| `ventago-app/src/views/admin/stores/details/components/ModalBranch.tsx` (MODIFIED — `invoiceType` selector, RI-gated) | component / form | request-response (form) | itself (existing `ivaCondition` `<CustomTextField select>` + `MenuItem` block, lines 220-233, and the `invoiceSucursal` field added this session, lines 202-210) | exact |

## Pattern Assignments

### `api-ventago/src/app/afip/build-factura.ts` (NEW — service/utility, transform)

**Analog:** `api-ventago/src/app/afip/afip-voucher.service.ts` (line loading) + `CoolSyncro/src/main/pdf/thermal-generator.js` (field assembly order)

**Existing line-building helper to reuse verbatim** (`afip-voucher.service.ts:178-201`):
```typescript
private buildPartialItems(sale: Sale): PartialLineInput[] {
  return (sale.items || []).map((si) => ({
    cantidad: Number(si.quantity),
    precioUnitario: Number(si.price),
    subtotal: Number(si.subtotal),
    descripcion: si.product?.name || si.customName || 'Ítem',
  }));
}

// Phase 25 Pitfall 4 read-precedence 재현 (sales.service.ts resolveSaleClient 참고):
// storeClient → globalClient 우선, 없으면 legacy clients 폴백.
private resolveReceptor(sale: Sale): { docNro?: string; resiva?: string } {
  if (sale.storeClientId && sale.storeClient?.globalClient) {
    const gc = sale.storeClient.globalClient;
    return { docNro: gc.document || '', resiva: gc.resIva };
  }
  if (sale.clientId && sale.client) {
    return { docNro: sale.client.document || '', resiva: sale.client.resIva };
  }
  return { docNro: '' };
}
```

**Sale eager-load pattern to copy for the new Sale/SaleItem/Product join** (`afip-voucher.service.ts:155-176`):
```typescript
private loadSaleWithReceptor(storeId: number, saleId: number): Promise<Sale | null> {
  return this.saleModel.findOne({
    where: { storeId, id: saleId },
    include: [
      { model: SaleItem, include: [{ model: Product, attributes: ['id', 'name'] }] },
      { model: Users, required: false, attributes: ['id', 'branchId'] },
      { model: StoreClient, required: false, include: [{ model: GlobalClient, required: false }] },
      { model: Clients, required: false },
    ],
  });
}
```
**Security note (V4/cross-tenant):** always scope this new query by `{storeId, id: saleId}` — never `findByPk` alone.

**Line-scaling call (D-05) — reuse exactly, do not reimplement:**
```typescript
import { applyPartial } from './partial-invoice';
const { lines, impTotal } = applyPartial(items, Number(sale.totalAmount), voucher.invoicePct);
```

**Letra/CbteTipo — use canonical `code-maps.ts::letraOf`, NOT the private duplicate in `afip-output.service.ts` (`letra()` method, lines 93-103, to be deleted/replaced):**
```typescript
// api-ventago/src/app/afip/code-maps.ts:222-240
export function letraOf(cbteTipo: number): string {
  if ([1, 2, 3].includes(cbteTipo)) return 'A';
  if ([51, 52, 53].includes(cbteTipo)) return 'M';
  if ([11, 12, 13].includes(cbteTipo)) return 'C';
  if ([19, 20, 21].includes(cbteTipo)) return 'E';
  return 'B';
}
```

**IVA discrimination — use canonical `computeNetoIva`, NOT manual division:**
```typescript
// api-ventago/src/app/afip/code-maps.ts:193-219 (BigInt-based exact rounding)
export function computeNetoIva({ tpago, ivaBase }: { tpago: number; ivaBase: number }): { neto: number; impuesto: number }
```

**CoolSyncro field-order reference (target D-02 shape) — receptor A/M vs B split** (`CoolSyncro/src/main/pdf/thermal-generator.js:83-105`):
```javascript
function receptorLines (fventa, letra) {
  if (letra === 'A' || letra === 'M') {
    const lines = [`Cliente: ${nombre || '-'}`];
    if (f.dni) lines.push(`CUIT: ${f.dni}`);
    lines.push(`Cond. IVA: ${condIva}`);
    if (domicilio) lines.push(`Domicilio: ${domicilio}`);
    lines.push(`Cond. venta: ${condicionVenta(f.tipo_pago)}`);
    return lines;
  }
  // B/E — Consumidor Final
  const lines = [`Cliente: ${clienteLabel(f)}`];
  if (f.dni) lines.push(`Doc: ${f.dni}`);
  return lines;
}
```
Note: `receptor.condIva` needs a small display-label map (RI/MONO/EXENTO/CF → Spanish text) — none exists in `code-maps.ts` today (research Open Question 3, recommend adding there as a `Record<number,string>` keyed by `COND_IVA_RECEPTOR`).

---

### `api-ventago/src/app/afip/afip-output.service.ts` (MODIFIED)

**Analog:** itself (existing `dispatch()`, read in full this session)

**Current hardcoded gap to fix** (`afip-output.service.ts:77-87`):
```typescript
if (input.output === 'pdf') {
  const pdf = await generateA4Pdf({
    issuer,
    voucher: voucher as never,
    tipoLetra: this.letra(voucher.tipoComprobante),
    lines: [],          // ← BUG: always empty, must load Sale+SaleItem and call buildFactura
    qrUrl,
  });
  return { ok: true, pdf };
}
```

**Existing thermal emit call (payload shape needs the new `factura` field per D-02):**
```typescript
// afip-output.service.ts:67-72
this.printService.emitPrintInvoice(
  input.branchId,
  { cae: voucher.cae, caeVto: voucher.caeVto, qrUrl, voucher, issuer },
  input.targetSocketId,
);
```
**Wiring gotcha (verified this session, not in original research doc):** `emitPrintInvoice` emits socket event `'print_invoice'` (see `print.service.ts:103-113`), which is a **different** event from `'print_fiscal'` (`print.service.ts:120`, used elsewhere). The print-agent's `print_invoice` handler (`main.js:929`) unconditionally calls `printTicket()` → `formatInvoiceHtml()` (plain control ticket) — it never branches to `formatFiscalHtml`. Only the separate, currently-unused-by-dispatch `print_fiscal` handler (`main.js:996-1023`) already calls `formatFiscalHtml`. The W1 plan must either (a) branch `print_invoice`'s handler on `payload.factura` presence, per RESEARCH.md's recommendation, or (b) have `dispatch()` emit `'print_fiscal'` instead when a `factura` payload is present — pick one, document the choice.

**Cross-tenant guard already present — keep this shape for any new Sale/SaleItem load too:**
```typescript
// afip-output.service.ts:58-65
const branch = await this.branchModel.findOne({
  where: { id: input.branchId, storeId: input.storeId },
});
if (!branch) {
  return { ok: false, reason: 'Sucursal no pertenece a la tienda' };
}
```

---

### `api-ventago/src/app/afip/afip-issuer.service.ts` (MODIFIED — `resolvePvAndCoolUser`, D-07)

**Analog (HTTP + cache logic):** `CoolSyncro/src/main/afip/rest-gateway-provider.js::getHeader`/`resolveHeaderInfo` (lines 138-205)
**Analog (Ventago cache idiom):** `api-ventago/src/app/vto/vto.service.ts`, `api-ventago/src/app/sizes/sizes.service.ts`

**CoolSyncro getHeader (non-throw, host = manager, NOT invoice):**
```javascript
// CoolSyncro/src/main/afip/rest-gateway-provider.js:138-157
const MANAGER_PATH = 'https://manager.coolsistema.com/api';
const URL_HEADER = MANAGER_PATH + '/data/header/cuit/';

async function getHeader (cuit) {
  const sucursal = Number(fe.sucursal) || 1;
  const url = URL_HEADER + cuit + '/' + sucursal;
  try {
    const response = await retryWithBackoff(() => http.get(url, { timeout: timeoutMs }), { maxRetries: retries });
    return (response && response.data) || null;
  } catch (err) {
    logger.warn(`[afip-gateway] getHeader failed: ${safeMessage(err)}`);
    return null;   // non-throw — caller must fall back
  }
}
```
**D-07 VERIFIED live response shape (this session, `57-RESEARCH.md`):**
```
GET https://manager.coolsistema.com/api/data/header/cuit/{cuit}/{sucursal}
→ 200 { cuit, coolUser, name, condition, branchs:[{branchId, point, alias, comercialAddress}], ... }
→ 200 null                      (unregistered CUIT)
→ 200 { branchs: [] }           (registered CUIT, no matching sucursal)
```
Must guard: `if (header == null)` before `.branchs`; `branchs.length === 0` → fallback; `branchs[0].point` not finite → fallback. Strip hyphens from `cuit` before building the URL (same as `qr-builder.ts` already does: `String(cuit).replace(/-/g,'')`).

**Point extraction (CoolSyncro, port logic 1:1 for the `point` value):**
```javascript
// rest-gateway-provider.js:179-183
let point = null;
const branchs = header && Array.isArray(header.branchs) ? header.branchs : [];
if (branchs[0] && Number.isFinite(Number(branchs[0].point))) {
  point = Number(branchs[0].point);
}
```

**Ventago in-memory TTL cache idiom to use instead of a bespoke `Map`** (`sizes.service.ts:7-23,61-73`, `vto.service.ts:5,16-17,90-92,108-115`):
```typescript
import { MemoryCacheService } from 'src/common/cache/memory-cache.service';
const CACHE_TTL = 60_000; // 60s per D-07

constructor(
  @InjectModel(AfipIssuer) private readonly issuerModel: typeof AfipIssuer,
  private readonly cacheService: MemoryCacheService,
) {}

async resolvePvAndCoolUser(cuit: string, sucursal: number) {
  const cacheKey = `afip-header:${cuit}:${sucursal}`;
  const cached = this.cacheService.get<{point:number; coolUser:string}>(cacheKey);
  if (cached) return cached;

  // ...GET manager.coolsistema.com/api/data/header/cuit/{cuit}/{sucursal}, defensive checks...

  this.cacheService.set(cacheKey, result, CACHE_TTL);
  return result;
}
```
`MemoryCacheService` (already registered, no new module wiring needed for common cases): `api-ventago/src/common/cache/memory-cache.service.ts` — `get<T>(key)`, `set(key,value,ttlMs)`, `del(key)`, `delByPrefix(prefix)`.

**Existing `loadIssuer` to extend (integration point):**
```typescript
// afip-issuer.service.ts:13-25
async loadIssuer(storeId: number, puntoVenta: number): Promise<AfipIssuer> {
  const issuer = await this.issuerModel.findOne({ where: { storeId, puntoVenta } });
  if (!issuer) {
    throw new NotFoundException(`발행자 미등록: store ${storeId}, PV ${puntoVenta}`);
  }
  return issuer;
}
```
Per D-07: only call the manager resolver when `issuer.invoiceSucursal` is set (skip entirely, zero extra latency, if `null` — the common case today since no backfill was done).

**Anti-pattern to avoid (security/repudiation):** never let a failed/slow `resolvePvAndCoolUser` retry-loop couple with the CAE POST retry — it must be an isolated try/catch with a single fallback, never trigger a second `issueCae` attempt (see `rest-gateway.provider.ts`'s existing `classifyTransportError`/ambiguous handling for the pattern this must NOT interfere with).

---

### `api-ventago/src/app/afip/afip.controller.ts` (MODIFIED — wire `dispatch()` into `issue()`)

**Analog:** itself — `reprint`/`pdf` endpoints already show the exact `dispatch()` call shape to replicate inside `issue()`.

**Existing `issue()` (the gap — `dto.output` is echoed, never acted on):**
```typescript
// afip.controller.ts:170-186
@Post('vouchers')
@Auth(ValidRoles.admin, ValidRoles.superadmin, ValidRoles.gerente, ValidRoles.vendedor)
async issue(@Body() dto: IssueVoucherDto, @GetUser() user: Users) {
  const result = await this.voucherService.issueForSale({
    storeId: this.requireStoreId(user),
    saleId: dto.saleId,
    puntoVenta: dto.puntoVenta,
    invoicePct: dto.invoicePct,
  });
  return { ...result, output: dto.output };   // ← BUG: output never dispatched
}
```

**Target call shape to copy (already proven in `reprint`, lines 220-238):**
```typescript
@Post('vouchers/:id/reprint')
async reprint(@Param('id', ParseIntPipe) id: number, @Body('branchId') branchId: number, @GetUser() user: Users) {
  return this.outputService.dispatch({
    storeId: this.requireStoreId(user),
    voucherId: id,
    output: 'thermal',
    branchId,
  });
}
```
Research recommendation (Assumption A1/A2): extend `AfipVoucherService.issueForSale()`'s return type to include `branchId` (it already derives `sale.user?.branchId` internally at line 84, just needs to be returned) so the controller can call `dispatch()` without an extra query.

**IDOR guard pattern used throughout this controller — replicate for any new endpoint:**
```typescript
// afip.controller.ts:104-117
await this.issuerModel.update({ ...dto } as never, { where: { id, storeId: user.storeId } });
return this.issuerModel.findOne({ where: { id, storeId: user.storeId } });
```

---

### `api-ventago/src/app/afip/code-maps.ts` (MODIFIED — wire `invoiceType` + RI gate, D-08)

**Analog:** itself — `decideComprobante` already has the A/M branch, just needs the caller (issuer.invoiceType) wired.

**Existing function (no change to internals needed, D-08 is purely a call-site wiring task):**
```typescript
// code-maps.ts:147-174
export function decideComprobante(
  ivaCondition: string,
  { docNro, resiva, configInvoiceType }: { docNro?: string; resiva?: string; configInvoiceType?: string },
): string {
  if (resiva === '-1') return 'E';
  if (ivaCondition === 'MONO') return 'C';
  const doc = typeof docNro === 'string' ? docNro : '';
  if (doc.length === 11) {
    if (configInvoiceType && configInvoiceType.toUpperCase() === 'M') return 'M';
    return 'A';
  }
  return 'B';
}
```
D-08 requirement: caller passes `configInvoiceType: issuer.invoiceCondition === 'RI' ? issuer.invoiceType : undefined` (or equivalent explicit gate) so that IVA≠RI silently ignores a stored `'M'` value — do this at the call site in `afip-voucher.service.ts::issue()` (`code-maps.ts` itself needs zero logic change, per SPEC "ya soporta la rama").

**CoolSyncro reference for the same decision (parity check only, do not port — Ventago's version is already equivalent/extended):**
`CoolSyncro/src/main/afip/code-maps.js::decideInvoiceType` — CUIT→A, `invoice_type==='M'`→M, else B, export→E.

---

### `api-ventago/src/app/afip/pdf/a4-generator.ts` (MODIFIED — real lines + IVA discrimination)

**Analog:** `CoolSyncro/src/main/pdf/generator.js` (A4 pdfkit) — explicit paridad target per SPEC/CONTEXT.

**Current skeleton (already typed for `A4Line[]`, just needs a real caller — see `afip-output.service.ts` gap above):**
```typescript
// a4-generator.ts:5-34 — types already correct
export interface A4Line { cantidad: number; precioUnitario: number; subtotal: number; descripcion: string; }
export interface A4Input {
  issuer: { cuit, razonSocial, domicilio, ingresosBrutos, inicioActividad };
  voucher: { cae, caeVto, puntoVenta, afipNumber, tipoComprobante, docNro, impTotal, netoGravado, ivaLiquidado };
  tipoLetra: string;
  lines: A4Line[];
  qrUrl: string;
}
```
```typescript
// a4-generator.ts:39-96 — existing structure already close to CoolSyncro's; needs:
//   1) letra chip box (currently just text "FACTURA {tipoLetra}")
//   2) COD. NN line
//   3) receptor block (currently absent — only emisor + items + totals)
//   4) IVA-discrimination visibility gate (only for A/M, not B) — currently always prints Neto/IVA line unconditionally
const qrDataUrl = await QRCode.toDataURL(input.qrUrl, { width: 200, margin: 1 });
const qrPng = Buffer.from(qrDataUrl.split(',')[1], 'base64');
const doc = new PDFDocument({ size: 'A4', margin: 40 });
```

**CoolSyncro target layout — letra box, receptor split, IVA discrim only for A/M** (`CoolSyncro/src/main/pdf/thermal-generator.js:212-260`, same logic reused by `pdf/generator.js` for A4):
```javascript
const letra = letraOf(tipo, tipoSpec);
const cod = tipoSpec && tipoSpec.numTipo != null ? String(tipoSpec.numTipo).padStart(2, '0') : '';
doc.lineWidth(1).rect(boxX, y, boxW, boxH).stroke();
doc.font('Helvetica-Bold').fontSize(20).text(String(letra), boxX, y + 5, { width: boxW, align: 'center' });
// ...
if (letra === 'A' || letra === 'M') {
  const { neto, impuesto } = computeNetoIva({ tpago: total, ivaBase: 1.21 });
  doc.text('Subtotal', ...); doc.text(money(neto), ...);
  doc.text('IVA 21%', ...); doc.text(money(impuesto), ...);
}
doc.font('Helvetica-Bold').fontSize(9).text(`TOTAL: ${money(total)}`, ..., { align: 'right' });
```
Reuse Ventago's own `computeNetoIva` (`code-maps.ts`) instead of re-deriving — same BigInt-exact math already imported by `a4-generator.ts`'s sibling files.

---

### `print-agent/src/fiscal-formatter.js` (REWRITTEN — D-01/D-02/D-03)

**Analog (field layout/order to replicate in HTML/CSS):** `CoolSyncro/src/main/pdf/thermal-generator.js` (full read, lines 1-283)
**Analog (QR-image rendering, same repo, already working):** `print-agent/src/qr-formatter.js`

**Current state (superseded — QR-as-text, no items/letra/receptor/IVA):**
```javascript
// print-agent/src/fiscal-formatter.js:73-77 (current — to be replaced)
${afip.qrUrl ? `
<div class="afip-qr-url">
  <div class="afip-qr-label">Verificar en AFIP:</div>
  <div class="afip-qr-text">${afip.qrUrl}</div>
</div>` : ''}
```

**QR-image rendering pattern to copy verbatim** (`print-agent/src/qr-formatter.js:7,29-36`):
```javascript
const QRCode = require('qrcode');
// ...
const qrDataUri = await QRCode.toDataURL(String(qrUrl || ''), { margin: 1, width: 360 });
// ...
`<img class="qr" src="${qrDataUri}" />`
```
Note: `qrcode@^1.5.4` already installed in `print-agent/package.json` — no new dependency (RESEARCH.md correction to D-01's "nueva dependencia" premise).

**CoolSyncro field order/logic to port into the new HTML (`fiscal-formatter.js` becomes `async function` since QR rendering is async, same as `qr-formatter.js`'s `formatQrHtml`):**
```javascript
// 1. Letra box + COD (thermal-generator.js:212-219)
const letra = letraOf(tipo, tipoSpec);
const cod = tipoSpec && tipoSpec.numTipo != null ? String(tipoSpec.numTipo).padStart(2, '0') : '';
// bordered box, 20pt bold letter, "COD. NN" below

// 2. Receptor block — A/M full identity vs B/E minimal (thermal-generator.js:83-105)
function receptorLines (fventa, letra) {
  if (letra === 'A' || letra === 'M') {
    return [`Cliente: ${nombre}`, `CUIT: ${dni}`, `Cond. IVA: ${condIva}`, `Domicilio: ${domicilio}`, `Cond. venta: ${condicionVenta}`];
  }
  return [`Cliente: ${clienteLabel(f)}`, ...(f.dni ? [`Doc: ${f.dni}`] : [])];
}

// 3. IVA discrimination — A/M only (thermal-generator.js:249-259)
if (letra === 'A' || letra === 'M') {
  const { neto, impuesto } = computeNetoIva({ tpago: total, ivaBase: 1.21 });
  // "Subtotal" + neto, "IVA 21%" + impuesto, both before TOTAL
}

// 4. Footer legend (thermal-generator.js:276)
doc.text('Comprobante autorizado — AFIP/ARCA', ...)
```
Per D-02, the print-agent must receive the ALREADY-DECIDED `factura` object from the backend (`buildFactura`) — it does NOT re-derive letra/IVA itself; it only renders the fields it's given. So `fiscal-formatter.js`'s new signature becomes `async formatFiscalHtml(factura)` consuming the D-02 shape directly (letra/cod/emisor/receptor/items/neto/iva21/total/ivaDiscrim/cae/caeVto/qrUrl), not re-implementing the CoolSyncro decision logic.

**HTML/CSS structure convention already established in this file (keep for consistency, extend the block):**
```javascript
// fiscal-formatter.js:80-113 — existing CSS injection pattern (border-top separator, uppercase title, table-based key/value rows)
const afipCss = `<style> .afip-section { border-top: 3px solid #1a1a1a; padding: 10px 14px 8px; margin-top: 4px; } ... </style>`;
// insertion point:
html = html.replace('</body>', `${afipCss}${afipBlock}</body>`);
```

---

### `print-agent/main.js` (MODIFIED — `print_invoice` handler branches on `payload.factura`)

**Analog:** itself — the sibling `print_fiscal` handler (already correctly wired) is the exact target to replicate/merge into `print_invoice`.

**Target shape already proven in this file** (`main.js:996-1023`):
```javascript
wsConnection.on('print_fiscal', async (payload) => {
  if (!store.get('printFiscal')) { ... return; }
  const printerCfg = getActivePrinterCfg();
  try {
    const html = formatFiscalHtml(payload);
    const png  = await renderHtmlToPng(html, 576, 10000, broadcastLog);
    await printImage(png, printerCfg, broadcastLog);
    wsConnection.emit('print_ack', { invoiceId: payload?.invoiceId, status: 'ok', ts: Date.now() });
  } catch (err) { /* status:'error' ack, same shape as below */ }
});
```

**Current `print_invoice` handler (the gap — always plain control ticket, never fiscal, even with a `factura` payload):**
```javascript
// main.js:929-993 — unconditionally calls printTicket() → formatInvoiceHtml()
wsConnection.on('print_invoice', async (payload) => {
  if (!store.get('printControl')) { ... return; }
  const printerCfg = getActivePrinterCfg();
  // ...
  try {
    await printTicket(payload, printerCfg, broadcastLog);   // ← always plain, never formatFiscalHtml
    // ...ack ok
  } catch (err) { /* ack error */ }
});
```
**Wiring task for W1:** branch on `payload.factura` presence — if present, call `formatFiscalHtml(payload.factura)` + `renderHtmlToPng` + `printImage` directly (bypassing `printTicket`/`formatInvoiceHtml`); if absent, keep the existing `printTicket()` path unchanged (non-AFIP control tickets must not regress — SPEC constraint). Alternatively, have `afip-output.service.ts::dispatch()` emit `'print_fiscal'` instead of `'print_invoice'` when output is a fiscal voucher — either approach satisfies REQ-1, but the plan must pick one explicitly (see `afip-output.service.ts` pattern notes above).

**`printControl` vs `printFiscal` toggle:** note the two settings gates (`store.get('printControl')` vs `store.get('printFiscal')`) are already separate Electron-store flags — decide which one gates the AFIP path once merged (likely `printFiscal`, matching the existing fiscal-specific handler's semantics).

---

### `ventago-app/src/views/facturacion/EmitidasPanel.tsx` (MODIFIED — "A4 PDF" button, D-06)

**Analog:** `ventago-app/src/views/talleres/cut-ticket/CutTicketTab.tsx::handlePdf` — exact Wave 7 blob-download pattern, same `apiConnector`.

**Pattern to copy verbatim (adapt path + filename):**
```tsx
// CutTicketTab.tsx:97-123
const handlePdf = async () => {
  if (!cutTicket) return
  setPdfLoading(true)
  try {
    const resp = await apiConnector.get(
      `/talleres/lotes/${cutTicket.lote.id}/cut-ticket/pdf`,
      { responseType: 'blob' },
    )
    const blob = new Blob([(resp as any).data ?? resp], { type: 'application/pdf' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `cut-ticket-${cutTicket.meta!.cutTicketNumber}.pdf`
    document.body.appendChild(a)
    a.click()
    a.remove()
    URL.revokeObjectURL(url)
  } catch (err: any) {
    toast.error('PDF descarga falló')
  } finally {
    setPdfLoading(false)
  }
}
```
For D-06, adapt to: `apiConnector.get(`/afip/vouchers/${v.id}/pdf`, { responseType: 'blob' })`, filename e.g. `factura-${v.tipoComprobante}-${String(v.puntoVenta).padStart(5,'0')}-${String(v.afipNumber).padStart(8,'0')}.pdf`.

**Underlying `apiConnector` blob support (already present, no service-layer change needed):**
```typescript
// ventago-app/src/services/api.service.ts:155-174
interface GetBlobConfig { responseType: 'blob' | 'arraybuffer' | 'stream'; params?: Record<string, any> }
get: async <T>(path: string, configOrParams: GetBlobConfig | Record<string, any> = {}) => {
  if ('responseType' in configOrParams) {
    const { responseType, params } = configOrParams as GetBlobConfig
    return await repository.get<T>(path, { responseType, params }).then(({ data }) => data)
  }
  return await repository.get<T>(path, { params: configOrParams }).then(({ data }) => data)
},
```
(There is also a `downloadFile(path, fileName, params)` helper at `api.service.ts:197-213` that does the same blob→anchor dance server-side-driven-filename — either this or the inline `CutTicketTab` pattern works; `CutTicketTab`'s inline version is preferred here since it lets the component control the filename from voucher data client-side, matching D-06's per-row button in a table.)

**Button insertion point (existing table row structure, add a new `<Button>` next to NC/ND):**
```tsx
// EmitidasPanel.tsx:66-80 — existing "Acción" cell structure to extend
<TableCell>
  {v.notaCredito ? (
    <Typography variant='caption' color='text.secondary'>NC emitida</Typography>
  ) : (
    <>
      <Button size='small' onClick={() => setNota({ voucher: v, kind: 'credito' })}>NC</Button>
      <Button size='small' color='inherit' onClick={() => setNota({ voucher: v, kind: 'debito' })}>ND</Button>
    </>
  )}
  {/* NEW: A4 PDF button, always visible regardless of NC/ND state */}
</TableCell>
```

**POS-side counterpart (context, not a new file per SPEC — `output='pdf'` radio already exists):** `ventago-app/src/views/facturacion/PartialInvoiceModal.tsx:19,108-112` already has an `output` state (`'thermal'|'pdf'|'digital'`) wired to `POST /afip/vouchers` via `afipService.issue()` — the "POS tras F10" A4 button referenced in SPEC R4 is this existing radio + the controller-dispatch fix (Pitfall 2), not a new UI element. Confirm at plan-time whether R4's POS acceptance criterion is satisfied by fixing the controller wiring alone or needs an explicit post-issue "Descargar PDF" affordance in this modal too.

---

### `ventago-app/src/views/admin/stores/details/components/ModalBranch.tsx` (MODIFIED — `invoiceType` selector, RI-gated, D-08)

**Analog:** itself — the existing `ivaCondition` select (lines 220-233) and the `invoiceSucursal` field added this same session (lines 202-210) are the exact patterns to replicate for `invoiceType`.

**Existing `ivaCondition` select — copy this `CustomTextField select` shape:**
```tsx
// ModalBranch.tsx:220-233
<Grid item xs={6}>
  <CustomTextField
    select
    label="Condición IVA"
    fullWidth
    defaultValue="RI"
    {...register('ivaCondition')}
    error={Boolean(errors.ivaCondition)}
  >
    <MenuItem value="RI">Responsable Inscripto</MenuItem>
    <MenuItem value="MONO">Monotributo</MenuItem>
    <MenuItem value="EXENTO">Exento</MenuItem>
  </CustomTextField>
</Grid>
```

**RI-gating — no existing `watch()`-based conditional render in this file today (form uses `register`, not `watch`); the CONTEXT.md-suggested pattern needs `watch` added to the `useForm()` destructure:**
```tsx
// CONTEXT.md D-08 pattern (not yet in codebase — introduce watch() for this gate)
const { register, reset, handleSubmit, control, watch, formState: { errors } } = useForm({ ... });
// ...
{watch('ivaCondition') === 'RI' && (
  <Grid item xs={6}>
    <CustomTextField select label="Tipo de factura" fullWidth defaultValue="A" {...register('invoiceType')}>
      <MenuItem value="A">Puede emitir Factura A</MenuItem>
      <MenuItem value="M">Solo Factura M</MenuItem>
    </CustomTextField>
  </Grid>
)}
```

**Load-on-edit pattern to extend (issuer fetch already includes `ivaCondition`/`invoiceSucursal` — add `invoiceType`):**
```tsx
// ModalBranch.tsx:64-74
reset({
  ...base,
  cuit: issuer.cuit ?? "",
  pointOfSale: String(issuer.puntoVenta ?? base.pointOfSale ?? ""),
  invoiceSucursal: issuer.invoiceSucursal != null ? String(issuer.invoiceSucursal) : "",
  ivaCondition: issuer.ivaCondition ?? "RI",
  // NEW: invoiceType: issuer.invoiceType ?? "A",
  razonSocial: issuer.razonSocial ?? "",
  domicilio: issuer.domicilio ?? "",
  ingresosBrutos: issuer.ingresosBrutos ?? "",
  inicioActividad: issuer.inicioActividad ?? "",
});
```

**Submit pattern to extend (destructure + separate-upsert-call, already excludes AFIP fields from the branch payload):**
```tsx
// ModalBranch.tsx:89-113
const { cuit, ivaCondition, razonSocial, domicilio, ingresosBrutos, inicioActividad, invoiceSucursal, ...branchData } = data;
// NEW: add invoiceType to the destructure
// ...
await apiConnector.put(`/afip/issuers/by-branch/${branchId}`, {
  cuit: String(cuit).replace(/\D/g, ''),
  puntoVenta: Number(branchData.pointOfSale),
  invoiceSucursal: invoiceSucursal ? Number(invoiceSucursal) : undefined,
  ivaCondition,
  // NEW: invoiceType,
  razonSocial, domicilio, ingresosBrutos, inicioActividad,
});
```

---

### `api-ventago/src/app/afip/models/afip-issuer.model.ts` + `dto/upsert-issuer.dto.ts` + migration (D-08 scaffolding)

**Analog:** itself — the `invoiceSucursal` column/field added this same session is the exact pattern to replicate for `invoiceType`.

**Model column pattern to copy** (`afip-issuer.model.ts:31-33`):
```typescript
// cool-invoice 게이트웨이측 지점(sucursal) 고유번호. 게이트웨이가 이 값으로 punto de venta 결정.
@Column({ allowNull: true })
invoiceSucursal: number;
// NEW (D-08):
@Column({ type: DataType.STRING(1), allowNull: false, defaultValue: 'A' })
invoiceType: string;
```

**DTO field pattern to copy** (`upsert-issuer.dto.ts:16-19`):
```typescript
@IsOptional()
@IsInt()
invoiceSucursal?: number;
// NEW (D-08) — matches ivaCondition's @IsIn pattern at line 29:
@IsOptional()
@IsIn(['A', 'M'])
invoiceType?: string;
```

**Migration file pattern to copy exactly** (`api-ventago/migrations/afip-issuer-invoice-sucursal.sql`, full file):
```sql
-- afip_issuers 에 "Sucursal de invoice" 고유번호 추가.
-- 로컬(5432) + 운영(5434) 동시 적용.
ALTER TABLE afip_issuers
  ADD COLUMN IF NOT EXISTS invoice_sucursal integer;
COMMENT ON COLUMN afip_issuers.invoice_sucursal IS
  'cool-invoice 게이트웨이측 지점(sucursal) 고유번호. 게이트웨이가 이 값으로 punto de venta 결정.';
-- 운영(coolsistema role) owner 이전은 컬럼 추가만이라 불필요(테이블 owner 유지). 로컬은 무영향.
```
New file `afip-issuer-invoice-type.sql` should follow the identical shape:
```sql
ALTER TABLE afip_issuers
  ADD COLUMN IF NOT EXISTS invoice_type varchar(1) DEFAULT 'A';
COMMENT ON COLUMN afip_issuers.invoice_type IS
  'Tipo de factura para receptor CUIT: A (RI puede emitir A) | M (solo M). Solo aplica cuando iva_condition=RI.';
```
Apply to **both** local 5432 and prod 5434 per CLAUDE.md's mandatory dual-apply rule — owner/sequence transfer not needed for `ADD COLUMN` on an existing table.

---

## Shared Patterns

### AFIP business-logic single source of truth (D-04 anti-duplication)
**Source:** `api-ventago/src/app/afip/code-maps.ts` (letra, CbteTipo, IVA math), `api-ventago/src/app/afip/partial-invoice.ts` (`applyPartial`), `api-ventago/src/app/afip/qr-builder.ts` (`buildQrUrl`)
**Apply to:** `build-factura.ts`, `afip-output.service.ts`, `pdf/a4-generator.ts`, `print-agent/src/fiscal-formatter.js` (via the D-02 payload, never re-derives)
**Rule:** the print-agent and A4 generator only render the pre-decided `factura` object — they must never re-implement `letraOf`/`computeNetoIva`/`decideComprobante`. The current private `letra()` duplicate in `afip-output.service.ts:93-103` must be deleted and replaced with the canonical `letraOf` import.

### Cross-tenant scoping (V4 Access Control)
**Source:** `api-ventago/src/app/afip/afip-output.service.ts:58-65` (branch ownership check), `afip.controller.ts:104-117` (`storeId` IDOR guard), `afip-voucher.service.ts:155-176` (`{storeId, id: saleId}` scoping)
**Apply to:** any new Sale/SaleItem query inside `build-factura.ts` or `dispatch()`; `resolvePvAndCoolUser` cache keys must be `${cuit}:${sucursal}`, not just `cuit` (different sucursales for the same CUIT return different `branchs`).

### Anti double-CAE (ambiguous/retryable/fatal classification)
**Source:** `api-ventago/src/app/afip/providers/rest-gateway.provider.ts:39-67` (`classifyTransportError`, `isDefinitiveReject`), `CoolSyncro/src/main/afip/rest-gateway-provider.js:91-115` (`classifyVoucherPostFailure`)
**Apply to:** D-07's new manager `/data/header` call must be an isolated try/catch, non-retrying into the CAE POST — never let a slow/failed header lookup trigger a second `issueCae` attempt.

### In-memory 60s TTL cache convention
**Source:** `api-ventago/src/common/cache/memory-cache.service.ts` (`get<T>`, `set`, `del`, `delByPrefix`), used by `sizes.service.ts`, `vto.service.ts`, `colors.service.ts`, etc.
**Apply to:** `afip-issuer.service.ts::resolvePvAndCoolUser` (D-07 cache) — inject `MemoryCacheService`, key `afip-header:${cuit}:${sucursal}`, TTL `60_000`.

### Blob-download button (Wave 7 pattern)
**Source:** `ventago-app/src/views/talleres/cut-ticket/CutTicketTab.tsx:97-123` (`handlePdf`), underlying support in `ventago-app/src/services/api.service.ts:155-174,197-213`
**Apply to:** `EmitidasPanel.tsx`'s new "A4 PDF" button (D-06) — `apiConnector.get(path, { responseType: 'blob' })` → `Blob` → `URL.createObjectURL` → anchor `download` → `URL.revokeObjectURL`.

### RI-gated conditional form field
**Source:** `ventago-app/src/views/admin/stores/details/components/ModalBranch.tsx:220-233` (`ivaCondition` select, `MenuItem` values `'RI'|'MONO'|'EXENTO'`)
**Apply to:** the new `invoiceType` selector (D-08) — requires adding `watch` to this file's `useForm()` destructure (not currently used here) to conditionally render based on `watch('ivaCondition') === 'RI'`.

### Migration + DTO + model triple (dual-apply 5432/5434)
**Source:** `api-ventago/migrations/afip-issuer-invoice-sucursal.sql` + `models/afip-issuer.model.ts:31-33` + `dto/upsert-issuer.dto.ts:16-19` — all three added together this same session for `invoiceSucursal`.
**Apply to:** `invoiceType` (D-08) — replicate the exact same 3-file shape; CLAUDE.md mandates applying the SQL to local 5432 AND prod 5434 simultaneously, never one alone.

## No Analog Found

None — all 15 files/wiring points identified from CONTEXT.md/SPEC.md/RESEARCH.md have a concrete existing analog either in the Ventago codebase or the read-only CoolSyncro parity reference.

## Wiring Gaps Discovered This Session (relevant to pattern application, not just formatting)

These are not new files but existing call-site gaps the planner must account for — a purely formatter-focused plan will not make the SPEC's acceptance criteria reachable without also touching these:

1. **`print-agent/main.js`'s `print_invoice` handler never calls `formatFiscalHtml`** (verified: it calls `printTicket()`→`formatInvoiceHtml()` unconditionally; the sibling `print_fiscal` handler does call `formatFiscalHtml` but is a different, currently-dispatch-unused socket event). W1 plan must touch `main.js`, not just `fiscal-formatter.js`.
2. **`AfipController.issue()` never calls `AfipOutputService.dispatch()`** — `dto.output` is echoed in the response but never acted on. Without this, no code path exercises the improved formatters from the primary "Facturar" flow (verified: only `reprint`/`pdf`/`send` endpoints call `dispatch()` today).
3. **`NotaCreditoService.emit()`/`NotaDebitoService.emit()` never call `dispatch()`** — R7 ("NC/ND reusan la salida mejorada, sin regresión") has literally nothing to regress; this is new wiring, same shape as gap #2, applied to two more service files.
4. **`AfipQueryService.getVoucher()` does a bare `findOne`, no Sale/SaleItem join** — this is *why* `lines: []` is hardcoded; the fix must span `afip-output.service.ts::dispatch()` (or `build-factura.ts`) loading `Sale`+`SaleItem`+`Product`, not just editing `a4-generator.ts`'s signature.

## Metadata

**Analog search scope:** `api-ventago/src/app/afip/` (all files), `api-ventago/src/app/print/`, `api-ventago/src/common/cache/`, `api-ventago/migrations/`, `print-agent/src/`, `print-agent/main.js`, `ventago-app/src/views/facturacion/`, `ventago-app/src/views/admin/stores/details/components/`, `ventago-app/src/views/talleres/cut-ticket/`, `ventago-app/src/services/api.service.ts`, `/Users/marcoskim/Trabajos_Programming/CoolSyncro/src/main/afip/`, `/Users/marcoskim/Trabajos_Programming/CoolSyncro/src/main/pdf/` (read-only parity reference)
**Files scanned:** ~30 direct reads this session (backend AFIP module, print-agent formatter/pipeline/main.js, frontend facturación/admin views, CoolSyncro parity files, project cache/DTO conventions)
**Pattern extraction date:** 2026-07-20
