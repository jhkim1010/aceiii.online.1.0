# Phase 57: Facturación Electrónica — Completar salida + A4 PDF + A/M + gateway parity - Research

**Researched:** 2026-07-20
**Domain:** AFIP electronic invoicing output layer (thermal ESC/POS, A4 PDF, gateway PV resolution) — NestJS/Sequelize backend + Electron print-agent + Next.js frontend
**Confidence:** HIGH (D-07 gateway endpoint live-verified; codebase gaps verified by direct file read + call-site grep, not inference)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** El **QR se genera en el print-agent** desde `qrUrl` (nueva dependencia `qrcode` en print-agent) y se renderiza como `<img src="data:image/png…">` dentro del pipeline HTML→PNG→ESC/POS existente (Phase 11). El backend NO envía el PNG — solo la `qrUrl`. Payload chico.
  - **Research correction (verified):** `qrcode@^1.5.4` is **already** a print-agent dependency (used by `src/qr-formatter.js`, Phase 38 CodigoMadre QR labels). No new dependency install needed — D-01's premise of "nueva dependencia" is stale; the pattern to reuse is `qr-formatter.js`'s `QRCode.toDataURL(url, {margin:1, width:N})`.
- **D-02:** El **backend calcula un payload `factura` estructurado** y el print-agent solo renderiza. Forma del payload: `{ letra:'A'|'B'|'M', cod:'NN', number, emisor{razonSocial,cuit,domicilio,condIva,iibb,inicioAct}, receptor{...|ConsumidorFinal}, items:[{cant,desc,pUnit,subtotal}], neto, iva21, total, ivaDiscrim:boolean, cae, caeVto, qrUrl }`. Las reglas AFIP (decidir letra, discriminar IVA) quedan **centralizadas en el backend**, nunca en el agente.
- **D-03:** El `fiscal-formatter.js` actual imprime el QR como **texto de URL** — se reemplaza por QR imagen escaneable. Además hoy no imprime letra/COD, ítems, receptor ni IVA discriminado — se agregan.
- **D-04:** **Fuente única `buildFactura(voucher, sale, issuer)`** produce el objeto `factura` estructurado (D-02); tanto el thermal (`fiscal-formatter`) como el A4 (`a4-generator`) consumen el MISMO objeto. Cero lógica de comprobante duplicada entre thermal y A4.
- **D-05:** **Partial (invoice_pct):** reusar el helper existente `applyPartial` / `partial-invoice` (el mismo que alimenta `previewPartial`) para producir las líneas escaladas. A4 y ticket muestran exactamente las mismas líneas que el preview F10, coherentes con `imp_total`. NO línea sintética.
- **D-06:** Botón **"A4 PDF"** en el panel Emitidas y en POS tras F10 → `GET /afip/vouchers/:id/pdf` (ya existe), abre/descarga el PDF **sin re-emitir CAE** (el `afip_number` no cambia).
- **D-07 (manager /data/header — resolución PV/coolUser):** Resolver PV + coolUser en `afip-issuer.service` (dentro de `loadIssuer` o un resolver dedicado), con **caché in-memory por `cuit+sucursal`, TTL ~60s**, y **fallback a `puntoVenta` local** si el header falla o `invoice_sucursal` no está seteado (con log del fallback). ⚠ Plan/execute DEBE verificar el endpoint real del gateway Node en vivo antes de cablear.
  - **Research resolution: VERIFIED LIVE in this session — see "D-07 Verified" section below.** Endpoint confirmed, host confirmed, response shape confirmed.
- **D-08 (A/M migración + gate por IVA):** `afip_issuers.invoice_type` default `'A'`; los issuers existentes quedan en `'A'` por el default (sin backfill explícito). `decideComprobante` aplica `'M'` **solo cuando IVA condición = RI Y invoice_type = 'M'**; si IVA ≠ RI se ignora el valor guardado. El selector A/M en ModalBranch es visible **solo para RI**.

### Claude's Discretion

None remaining unresolved after D-07 verification — the one open discretion item in CONTEXT.md (verify manager endpoint live) is now resolved with HIGH confidence (see below).

### Deferred Ideas (OUT OF SCOPE)

- **Modo SOAP directo (WSAA/WSFEv1)** — reemplazar el gateway por conexión AFIP directa; fase posterior.
- **Envío digital del comprobante (WhatsApp/email PDF)** — el output `digital` sigue stub; backlog CRM.
- **Factura C / letra C para Monotributo emisor** — el contrato CoolSyncro no la tiene; si se necesita, fase propia.

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| REQ-1 | print-agent — comprobante ESC/POS completo (letra/COD/emisor/receptor/ítems/IVA/CAE/QR/leyenda) | `print-agent/src/fiscal-formatter.js` current state read; **CRITICAL gap found**: `main.js` never calls `formatFiscalHtml` — `print_invoice` handler always uses plain `formatInvoiceHtml` via `printTicket()`. CoolSyncro `thermal-generator.js` gives the exact field layout/order to replicate (letra box, COD, emisor block, receptor block A/M vs B, items, Subtotal/IVA21%/TOTAL, CAE/Vto/QR, leyenda). |
| REQ-2 | QR RG 4892 en el ticket | `qr-builder.ts` (backend, already builds `qrUrl`) + `qr-formatter.js` (print-agent, already renders QR image via `qrcode`) — pattern to replicate verified, no new dependency needed. |
| REQ-3 | A4 PDF con líneas reales + discriminación IVA | **CRITICAL gap found**: `AfipVoucher` model has NO items/lines column; `AfipQueryService.getVoucher()` does not join `Sale`/`SaleItem`. `afip-output.service.ts` hardcodes `lines: []`. Fix path: load `Sale`+`SaleItem` for `voucher.saleId`, re-run `applyPartial(items, sale.totalAmount, voucher.invoicePct)` to reconstruct exact same lines shown at issue-time preview (D-05). CoolSyncro `generator.js`/`thermal-generator.js` give the exact IVA-discrimination math (`preuni/1.21`, `computeNetoIva`) already ported to `code-maps.ts`. |
| REQ-4 | A4 PDF on-demand button (Emitidas + POS) | `GET /afip/vouchers/:id/pdf` already exists and works end-to-end (controller → `dispatch({output:'pdf'})` → `generateA4Pdf`). `EmitidasPanel.tsx` currently has NO such button (only NC/ND actions) — pure frontend addition, low risk. |
| REQ-5 | `afip_issuers.invoice_type` (A/M) + ModalBranch selector (solo RI) + `decideComprobante` wiring | Exact precedent found: `afip-issuer-invoice-sucursal.sql` migration pattern + `UpsertIssuerDto`/`ModalBranch.tsx` field-add pattern (both already used for `invoiceSucursal` this same session). `code-maps.ts::decideComprobante` already has the A/M branch at :165-170 — just needs `issuer.invoiceType` wired as `configInvoiceType` param, gated by `issuer.ivaCondition === 'RI'`. |
| REQ-6 | Resolución PV/coolUser vía gateway `manager` | **VERIFIED LIVE** (this session) — see D-07 Verified section. Exact host, path, method, response shape, auth (none), and edge cases (invalid cuit → `null`, missing sucursal segment → falls through to SPA 404-equivalent) all confirmed via live `curl`. |
| REQ-7 | NC/ND reusan salida mejorada (sin regresión) | **CRITICAL gap found**: `nota-credito.service.ts`/`nota-debito.service.ts` never call `AfipOutputService.dispatch()` at all today — they only create the `AfipVoucher` row and return `{cae, qrUrl}`. There is currently ZERO print/PDF output wired for NC/ND. This is new wiring, not "fix existing wiring." |

</phase_requirements>

## Summary

The AFIP module in Ventago (`api-ventago/src/app/afip/`) has all the pure-logic pieces this phase needs already built and unit-tested: `code-maps.ts` (CbteTipo/IVA/letra/A-M branch), `qr-builder.ts` (RG 4892 payload), `partial-invoice.ts` (`applyPartial`), and skeleton `a4-generator.ts`. What is missing is **output wiring**, not just "richer formatters." Three wiring gaps were found during this research that are more fundamental than the SPEC's stated gaps and must be addressed for the phase's acceptance criteria to even be reachable:

1. **`print-agent/main.js`'s `print_invoice` handler never calls `fiscal-formatter.js`.** It unconditionally renders the plain control-ticket HTML (`formatInvoiceHtml`) via `print-pipeline.js::printTicket()`. `fiscal-formatter.js` (`formatFiscalHtml`) is currently dead code — never imported by `main.js`. Any AFIP-specific fields sent in the `print_invoice` payload today are silently dropped by the print-agent.
2. **`AfipController.issue()` never calls `AfipOutputService.dispatch()`.** The frontend `PartialInvoiceModal.tsx` lets the user pick `output: 'thermal'|'pdf'|'digital'` and its UI text promises "si es exitoso, se imprime en la comandera" — but the controller only echoes `dto.output` back in the JSON response; it never dispatches. Likewise, the POS auto-issue path (`sales-create.service.ts:506`, fire-and-forget `afipVoucherService.issueForSale()`) never calls `dispatch()` either. **Today, no code path automatically prints a fiscal ticket after CAE issuance** — the only dispatch call sites are `POST /vouchers/:id/reprint` (manual re-print, not wired to any UI button found) and `GET /vouchers/:id/pdf` (D-06's target, works).
3. **`AfipVoucher` (the DB model) stores only totals, never line items**, and `AfipQueryService.getVoucher()` does a bare `findOne` with no `Sale`/`SaleItem` include. This is *why* `lines: []` is hardcoded in `afip-output.service.ts` today — there is no join to get real items. The correct fix (consistent with D-05) is to load `Sale`+`SaleItem`+`Product` for `voucher.saleId` at dispatch time and re-run `applyPartial(items, sale.totalAmount, voucher.invoicePct)` — this reconstructs byte-identical lines to what F10's preview showed, with no new persisted snapshot.

The gateway-manager endpoint for PV resolution (D-07, previously unverified and flagged as the phase's single blocking research item) is now **fully verified live**: `GET https://manager.coolsistema.com/api/data/header/cuit/{cuit}/{sucursal}` returns HTTP 200 JSON with `{cuit, coolUser, name, condition, branchs:[{branchId, point, alias, comercialAddress}], ...}` for a registered CUIT+sucursal, `null` for an unregistered CUIT, and requires BOTH path segments (`cuit` and `sucursal`) or it silently falls through to the `manager.coolsistema.com` SPA (200 HTML, not JSON — a header-parsing bug trap). No auth is required (public GET, CORS `*`). The `invoice.coolsistema.com` host (used for CAE issuance itself) returns a genuine 404 for this same path — confirming CONTEXT.md's warning was about the *wrong host*, not a nonexistent route.

**Primary recommendation:** Build `buildFactura(voucher, sale, issuer)` as a new pure function (e.g. `api-ventago/src/app/afip/build-factura.ts`) that loads `Sale`+`SaleItem`+`Product`, re-runs `applyPartial`, and assembles the exact D-02 payload shape. Wire it into `afip-output.service.ts::dispatch()` for both `thermal` and `pdf` outputs. Separately (and just as importantly), wire `AfipOutputService.dispatch()` into `AfipController.issue()` (using `dto.output` and a `branchId` newly returned from `AfipVoucherService.issueForSale()`) and into `NotaCreditoService.emit()`/`NotaDebitoService.emit()` — without this, the phase's acceptance criteria ("emitiendo una Factura A... el ticket impreso contiene...") have no code path to exercise them.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Comprobante field assembly (letra/COD/emisor/receptor/items/IVA/CAE/QR) | API/Backend (`buildFactura`) | — | AFIP business rules (D-02) must be centralized, never duplicated in print-agent or frontend |
| QR image rendering | Print-agent (Electron) / API (A4 pdfkit) | — | `qrUrl` computed backend-side (`qr-builder.ts`); PNG rendering happens locally at each output tier (`qrcode` lib) to keep socket payload small (D-01) |
| ESC/POS thermal rendering | Print-agent (Electron) | — | HTML→PNG→ESC/POS pipeline (Phase 11) is print-agent-owned; backend never touches pixels |
| A4 PDF rendering | API/Backend (`a4-generator.ts`, pdfkit) | — | Server-side PDF generation, downloaded via HTTP — no Electron dependency |
| PV/coolUser resolution (gateway manager) | API/Backend (`afip-issuer.service.ts`) | External service (`manager.coolsistema.com`) | Must happen before CAE issuance; caching lives backend-side (in-memory, per-process) |
| Output dispatch trigger (thermal/pdf/digital selection) | API/Backend (`afip.controller.ts` → `AfipOutputService`) | Frontend (button/radio selection) | Frontend only *requests* an output; backend decides how to fulfill it (Socket.io emit vs PDF buffer) |
| A/M selection per branch | Frontend (`ModalBranch.tsx`, RI-gated) | API/Backend (`afip_issuers.invoice_type` + `decideComprobante`) | UI is a thin form; the actual A-vs-M business decision is re-validated backend-side at issue time (never trust client-only gating) |

## Standard Stack

### Core (already present — no installs needed)

| Library | Version (verified) | Purpose | Location |
|---------|---------|---------|----------|
| `qrcode` | `^1.5.4` | QR PNG/dataURL generation | **Both** `print-agent/package.json` and `api-ventago/package.json` — already installed on both sides `[VERIFIED: package.json read]` |
| `pdfkit` | `^0.14.0` | A4 PDF generation | `api-ventago/package.json` `[VERIFIED: package.json read]` |
| `escpos` / `escpos-network` / `escpos-usb` | `^3.0.0-alpha.x` | ESC/POS thermal printer driver | `print-agent/package.json` — unchanged by this phase (HTML→PNG→ESC/POS pipeline sits above this) |
| `axios` | (project version) | HTTP client for gateway calls | `api-ventago` — used by `rest-gateway.provider.ts` and will be reused for the manager `/data/header` call |

**No new dependencies are required for W1 or W2.** D-01's note about "nueva dependencia qrcode" is superseded — correct this in planning to avoid a wasted install task.

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| In-memory per-CUIT+sucursal cache (Map, TTL) for manager header | Redis / `MemoryCacheService` (project's existing 60s pattern) | `MemoryCacheService` (CLAUDE.md "인메모리 캐시" convention) is the more consistent choice project-wide — recommend using it instead of a bespoke `Map`, for consistency with other reference-data caches (60s TTL matches project convention exactly) |

## Architecture Patterns

### System Architecture Diagram

```
POS F10 confirm / Facturación "Facturar" (PartialInvoiceModal)
        │
        ▼
POST /afip/vouchers  (AfipController.issue)
        │
        ▼
AfipVoucherService.issueForSale()
        │  1. loadSaleWithReceptor(storeId, saleId)  ── Sale + SaleItem + Product + Client
        │  2. issuerService.loadIssuer(storeId, puntoVenta)
        │       │
        │       ▼ [NEW — D-07] resolvePvAndCoolUser(cuit, invoiceSucursal)
        │         ── in-memory cache (60s TTL) ──▶ hit? use cached {point, coolUser}
        │         ── miss ──▶ GET manager.coolsistema.com/api/data/header/cuit/{cuit}/{sucursal}
        │                       ├─ 200 + branchs[0] present → {point, coolUser} (cache + use)
        │                       ├─ 200 + branchs:[] or null → fallback to issuer.puntoVenta (log fallback)
        │                       └─ network error/timeout    → fallback to issuer.puntoVenta (log fallback)
        │  3. decideComprobante(issuer.ivaCondition, {docNro, resiva, configInvoiceType: issuer.invoiceType})
        │  4. applyPartial(items, sale.total, invoicePct) → {lines, impTotal}
        │  5. provider.issueCae(voucherRequest)  ── POST invoice.coolsistema.com/api/invoice/ar
        │  6. AfipVoucher.create({...totals, NO items})
        │
        ▼
[NEW — must wire] AfipController.issue() calls AfipOutputService.dispatch({voucherId, output: dto.output, branchId})
        │
        ▼
AfipOutputService.dispatch()
        │  1. queryService.getVoucher(storeId, voucherId)
        │  2. [NEW] load Sale+SaleItem+Product for voucher.saleId
        │  3. [NEW] buildFactura(voucher, sale, issuer) ── SINGLE SOURCE (D-04)
        │       ── applyPartial(items, sale.totalAmount, voucher.invoicePct) → same lines as F10 preview (D-05)
        │       ── assembles D-02 shape: {letra, cod, emisor, receptor, items, neto, iva21, total, ivaDiscrim, cae, caeVto, qrUrl}
        │
        ├─ output='thermal' ──▶ printService.emitPrintInvoice(branchId, {factura}, socketId)
        │                          │  Socket.io emit 'print_invoice' → print-agent /print-agent namespace
        │                          ▼
        │                    [NEW] main.js print_invoice handler:
        │                      if (payload.factura) → formatFiscalHtml(payload.factura) [rewritten, D-02/D-03]
        │                      else                 → formatInvoiceHtml(payload)  [existing control ticket, UNCHANGED]
        │                          │
        │                          ▼ renderHtmlToPng(html, 576) → printImage(pngBuffer) [pipeline UNCHANGED]
        │
        └─ output='pdf' ──▶ generateA4Pdf({issuer, voucher, factura.items, qrUrl}) → Buffer → HTTP response
                               (already the code path for GET /afip/vouchers/:id/pdf — D-06 button just calls this)

NC/ND separate flow (currently NO dispatch at all — R7 requires adding this):
POST /vouchers/:id/nota-credito → NotaCreditoService.emit() → AfipVoucher.create({notaCredito:true})
        │
        ▼ [NEW] must also call AfipOutputService.dispatch({voucherId: nc.id, output, branchId})
```

### Recommended Project Structure

```
api-ventago/src/app/afip/
├── build-factura.ts          # NEW — buildFactura(voucher, sale, issuer) → D-02 shape (D-04 single source)
├── afip-issuer.service.ts    # MODIFIED — add resolvePvAndCoolUser() (D-07), used inside loadIssuer path
├── afip-output.service.ts    # MODIFIED — dispatch() loads Sale+items, calls buildFactura, passes factura to both outputs
├── afip.controller.ts        # MODIFIED — issue() calls outputService.dispatch() after successful issueForSale()
├── code-maps.ts              # MODIFIED — decideComprobante already has A/M branch; just wire issuer.invoiceType + RI gate
├── pdf/a4-generator.ts       # MODIFIED — accept factura.items (A4Line[]) instead of hardcoded []
├── nota-credito.service.ts   # MODIFIED — emit() calls outputService.dispatch() (R7, NEW wiring)
├── nota-debito.service.ts    # MODIFIED — emit() calls outputService.dispatch() (R7, NEW wiring)
└── models/afip-issuer.model.ts  # MODIFIED — add invoiceType column (D-08)

print-agent/src/
├── fiscal-formatter.js       # REWRITTEN — consume D-02 factura shape, add QR <img>, items table, IVA discrim (D-01/D-02/D-03)
├── main.js                   # MODIFIED — print_invoice handler branches: payload.factura ? formatFiscalHtml : formatInvoiceHtml
└── qr-formatter.js           # REFERENCE ONLY — pattern to copy for QRCode.toDataURL usage (no change needed)

ventago-app/src/views/
├── facturacion/EmitidasPanel.tsx           # MODIFIED — add "A4 PDF" button (D-06)
└── admin/stores/details/components/ModalBranch.tsx  # MODIFIED — add invoiceType selector, RI-gated (D-08)

api-ventago/migrations/
└── afip-issuer-invoice-type.sql   # NEW — ADD COLUMN invoice_type, default 'A', apply 5432+5434
```

### D-07 Verified — Gateway Manager Endpoint (live, this session)

**Host + route (VERIFIED):**
```
GET https://manager.coolsistema.com/api/data/header/cuit/{cuit}/{sucursal}
```

**Verified live response (test CUIT `30710419414`, sucursal `1`):** `[VERIFIED: live curl, 2026-07-20]`
```json
{
  "configuration": { "pointLength": 5 },
  "_id": "63470adac4b5fd1235c644b9",
  "name": "Krencia S.R.L",
  "cuit": "30710419414",
  "condition": "IVA Responsable Inscripto",
  "initDate": "01/02/2008",
  "ingresos": "1177696-108",
  "email": "luis@krencia.com.ar",
  "phone": "1132094381",
  "branchs": [
    { "_id": "6a5d91fd58935eba26512496", "branchId": 1, "alias": "Krencia", "point": 10, "comercialAddress": "Vallese Felipe 3255 PB - CABA", "selected": true }
  ],
  "coolUser": "krencia",
  "isActive": true,
  "__v": 0
}
```
This exactly matches CoolSyncro's `rest-gateway-provider.js::getHeader()` expected shape (`branchs[0].point` = PV, `coolUser` = certificate directory key).

**Verified edge cases** `[VERIFIED: live curl, 2026-07-20]`:
| Case | Result |
|------|--------|
| `invoice.coolsistema.com` + same path (the host CONTEXT.md flagged as returning 404) | **HTTP 404** JSON `{"statusCode":404,"errorMessage":"ENOENT...public/index.html"}` — confirms this is the *wrong host*, not a nonexistent route. Do not point the D-07 call at `invoice.coolsistema.com`. |
| `manager.coolsistema.com` + valid cuit + sucursal with no registered branch (`sucursal=2` for a CUIT that only has branch 1) | HTTP 200, `branchs: []` (empty array, not null/error) — code must handle `branchs.length === 0` as "no PV resolved, fallback" |
| `manager.coolsistema.com` + unregistered/invalid cuit | HTTP 200, body is the **literal JSON value `null`** (not `{}`, not 404) — code must guard `if (header == null)` before accessing `.branchs` |
| `manager.coolsistema.com` + hyphenated CUIT format (`30-71041941-4`) | HTTP 200, body `null` — **CUIT must be sent digits-only** (strip hyphens before calling, same as `qr-builder.ts` already does: `String(cuit).replace(/-/g,'')`) |
| `manager.coolsistema.com` + cuit only, missing `/sucursal` segment | HTTP 200 but returns the **manager admin SPA's index.html** (Next.js catch-all), not JSON — a header-parsing bug trap if `sucursal` is ever omitted/undefined in the URL template. Always include both path segments. |
| Auth | **None required** — public GET, `Access-Control-Allow-Origin: *`. No API key/token needed for this call. |
| Response headers | `Content-Type: application/json; charset=utf-8`, served via `nginx/1.24.0` — confirms it's a real JSON API endpoint on that host, not a proxy artifact. |

**Implication for `afip-issuer.service.ts::loadIssuer` / new resolver:**
- Requires **both** `cuit` (digits-only) and `invoiceSucursal` (int) to call. If `issuer.invoiceSucursal` is `null` (unset — the common case per precondition "기존 행은 NULL"), skip the manager call entirely and use `issuer.puntoVenta` directly (no wasted network call).
- Must defensively check: response is `null` → fallback; `branchs` is empty array → fallback; `branchs[0].point` is not a finite number → fallback. Each fallback path should log (per D-07 requirement) which condition triggered it.
- Cache key must be `${cuit}:${sucursal}` (not just `cuit`) since different sucursales for the same CUIT return different `branchs` (verified: sucursal=2 returned `branchs:[]` while sucursal=1 returned the real branch for the same CUIT).

### Pattern: `buildFactura` reconstructs lines from `applyPartial`, never persists a snapshot

**What:** At dispatch time (thermal print, A4 PDF, or NC/ND), load `Sale`+`SaleItem`+`Product` for `voucher.saleId`, then call the *existing* `applyPartial(items, sale.totalAmount, voucher.invoicePct)` (same function `previewPartial` already uses) to regenerate `{lines, impTotal}`. Assert `impTotal === voucher.impTotal` as a sanity check (both derive from the same rounding logic, so they should match exactly).

**Why this and not a stored snapshot:** D-05 explicitly requires ticket/A4 to show the *same* lines as the F10 preview — the cleanest way to guarantee byte-identical output is to re-run the identical deterministic function, not to maintain a second copy of scaled line data that could drift.

**Example (pattern to follow, adapted from `afip-voucher.service.ts::buildPartialItems` + `previewPartial`):**
```typescript
// Source: api-ventago/src/app/afip/afip-voucher.service.ts (existing pattern, read this session)
private buildPartialItems(sale: Sale): PartialLineInput[] {
  return (sale.items || []).map((si) => ({
    cantidad: Number(si.quantity),
    precioUnitario: Number(si.price),
    subtotal: Number(si.subtotal),
    descripcion: si.product?.name || si.customName || 'Ítem',
  }));
}
// buildFactura would do: const items = buildPartialItems(sale);
//                        const { lines } = applyPartial(items, Number(sale.totalAmount), voucher.invoicePct);
```

### Anti-Patterns to Avoid

- **Do not duplicate the CbteTipo→letra mapping.** `afip-output.service.ts` currently has a **private duplicate** of `code-maps.ts::letraOf()` (its own `letra()` method, lines 93-103). When building `buildFactura`, replace this with the canonical `letraOf` import — do not add a third copy in the print-agent or frontend.
- **Do not trust `dto.output` from the frontend as authorization to skip backend validation.** The A/M gate (D-08) and IVA discrimination decision must be recomputed backend-side even though the frontend radio/selector exists — never let a client-supplied `invoiceType`/`output` flag bypass server-side `decideComprobante`.
- **Do not add a new `qrcode` dependency** to print-agent — it is already present and already used by `qr-formatter.js`. Adding a duplicate/conflicting version entry would be redundant.
- **Do not call the manager gateway on every issuance without `invoiceSucursal` set.** Since the existing `afip_issuers` rows have `invoice_sucursal = NULL` (precondition, no backfill), most current issuers will and should skip the manager call entirely (immediate fallback, zero extra latency/HTTP round-trip) until an operator explicitly sets `invoice_sucursal` per branch.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| QR image from URL | Custom canvas/SVG QR renderer | `qrcode` npm package (`QRCode.toDataURL`) — already installed both sides | Already proven working in this exact codebase (`qr-formatter.js`, Phase 38) and in CoolSyncro's parity reference |
| IVA neto/impuesto split from a gross total | Manual float division | `code-maps.ts::computeNetoIva({tpago, ivaBase})` | Already implemented with BigInt-based exact rounding (avoids float cent drift) — do not reimplement in the print-agent or a4-generator |
| CbteTipo / letra / NC/ND type derivation | New switch statements in print-agent or frontend | `code-maps.ts` (`INVOICE_TYPE`, `letraOf`, `creditNoteTypeOf`, `debitNoteTypeOf`) | Single source of AFIP code truth already tested (`code-maps.spec.ts`) |
| Partial-invoice line scaling | New scaling math for A4/thermal | `partial-invoice.ts::applyPartial` | Already handles rounding-residue correction (last-line adjustment) so `Σsubtotal === impTotal` — a subtle correctness requirement easy to get wrong from scratch |
| In-memory TTL cache for gateway header lookups | Bespoke `Map` + manual timestamp eviction | Project's existing `MemoryCacheService` (60s reference-data convention per CLAUDE.md) | Consistency with project-wide caching pattern; avoids yet another ad-hoc cache implementation |

**Key insight:** Every piece of AFIP business logic this phase needs (letra derivation, IVA math, partial scaling, QR payload) already exists, tested, in `api-ventago/src/app/afip/`. This phase is almost entirely a **wiring and formatting** phase, not a new-logic phase — the risk is in the wiring gaps (see Common Pitfalls), not in the AFIP math.

## Common Pitfalls

### Pitfall 1: Assuming `fiscal-formatter.js` is currently active
**What goes wrong:** A task like "extend `fiscal-formatter.js` with QR/items/IVA" could be implemented perfectly and still produce zero visible change on a printed ticket, because `main.js`'s `print_invoice` handler never calls it.
**Why it happens:** `fiscal-formatter.js` exists, is well-documented, and looks production-ready — but `git grep` shows it has no caller anywhere in `print-agent/` outside its own spec file (if any). `main.js:929` unconditionally calls `printTicket()` → `formatInvoiceHtml()`.
**How to avoid:** Any W1 plan MUST include a task to modify `main.js`'s `print_invoice` handler to branch on `payload.factura` presence (or an explicit `payload.isFiscal` flag) and call the fiscal path.
**Warning signs:** If the plan only touches `fiscal-formatter.js` and no file under `print-agent/*.js` (main.js/print-pipeline.js), this pitfall is present.

### Pitfall 2: Assuming CAE issuance already triggers printing
**What goes wrong:** Testing "emit Factura A → verify printed ticket" will find **no ticket printed at all**, not just an incomplete one, because `AfipController.issue()` and the POS auto-issue path never call `AfipOutputService.dispatch()`.
**Why it happens:** The frontend (`PartialInvoiceModal.tsx`) already has UI (`output` radio group) and copy ("se imprime en la comandera") implying this works — but the controller silently drops `dto.output` on the floor (`return {...result, output: dto.output}` — `output` is returned in the response JSON, never *acted on*).
**How to avoid:** W1/W2 plan must add: (a) `AfipVoucherService.issueForSale()` returns `branchId` (derivable the same way it's derived internally: `sale.user?.branchId`), (b) `AfipController.issue()` calls `this.outputService.dispatch({storeId, voucherId: result.voucherId, output: dto.output, branchId: result.branchId})` after a successful issue.
**Warning signs:** grep for `outputService.dispatch` call sites before and after the plan's changes — if `afip.controller.ts::issue()` isn't in the list, dispatch is still not wired.

### Pitfall 3: Assuming NC/ND already print (R7 is "no regression" in the SPEC, but there is nothing to regress)
**What goes wrong:** Treating R7 as "make sure NC/ND keep printing correctly" when in fact **NC/ND never printed anything before this phase** — `NotaCreditoService.emit()`/`NotaDebitoService.emit()` only persist the `AfipVoucher` row.
**Why it happens:** The SPEC's framing ("NC/ND reusan la salida mejorada, sin regresión") implies existing output that must be preserved. The actual codebase has zero output wiring for NC/ND.
**How to avoid:** Frame R7 as new wiring (same shape as the `AfipController.issue()` fix): after `nc = await this.voucherModel.create(...)`, call `outputService.dispatch({voucherId: nc.id, output: <caller-chosen>, branchId})`. Decide (during planning, low-risk discretion) whether NC/ND auto-print thermal immediately after emit, or expose an explicit UI action akin to D-06's A4 button — either satisfies R7, but the plan must pick one; today neither exists.
**Warning signs:** No `outputService` import in `nota-credito.service.ts`/`nota-debito.service.ts` before the plan's changes.

### Pitfall 4: `AfipVoucher.getVoucher()` has no item data — `lines: []` is not a bug to patch locally, it's a missing join
**What goes wrong:** Trying to fix R3 by editing only `pdf/a4-generator.ts` (making it accept a `lines` param) without also fixing `afip-output.service.ts::dispatch()` to actually populate that param with real data — the hardcoded `lines: []` call site is the actual defect.
**Why it happens:** `a4-generator.ts` already has a well-typed `A4Line[]` parameter — it *looks* ready to receive data, masking that no caller currently supplies any.
**How to avoid:** The fix must span: `afip-output.service.ts::dispatch()` loads `Sale`+`SaleItem`+`Product` (new query, `voucher.saleId` as the join key — `AfipQueryService.getVoucher()` currently does a bare `findOne`, no include), then calls `buildFactura`/`applyPartial` to get real lines, then passes them to `generateA4Pdf`.
**Warning signs:** Any plan/diff that touches `a4-generator.ts` but not `afip-output.service.ts` or `afip-query.service.ts` is incomplete for R3.

### Pitfall 5: CUIT format mismatches when calling the manager gateway
**What goes wrong:** `afip_issuers.cuit` may be stored with or without hyphens depending on data entry; the manager endpoint returns `null` for hyphenated CUIT (verified live). A silent `null` response (not an error) could be misread as "gateway is down" rather than "CUIT format is wrong," masking the real bug.
**Why it happens:** `qr-builder.ts` already strips hyphens (`String(cuit).replace(/-/g,'')`) for the QR payload — the same normalization must be applied before the manager call, but it's easy to forget since the manager call is a new code path.
**How to avoid:** Normalize `cuit` (digits-only) immediately before constructing the manager URL, exactly as `qr-builder.ts` does.
**Warning signs:** Manager calls always fallback for CUITs that "should" be registered — check for hyphens/spaces in the stored `cuit` value first.

## Code Examples

### Reference: CoolSyncro's field layout for the ESC/POS-equivalent thermal receipt (letra box + COD + emisor/receptor split + IVA discrimination)
```javascript
// Source: /Users/marcoskim/Trabajos_Programming/CoolSyncro/src/main/pdf/thermal-generator.js (read this session)
// Letra box + COD (AFIP standard) — pattern to replicate in fiscal-formatter.js HTML/CSS
const letra = letraOf(tipo, tipoSpec);
const cod = tipoSpec && tipoSpec.numTipo != null ? String(tipoSpec.numTipo).padStart(2, '0') : '';
// ... draws a bordered box with the letter, then "COD. NN" below it

// Receptor block — A/M gets full identity, B/E gets minimal (RG 1415)
function receptorLines (fventa, letra) {
  if (letra === 'A' || letra === 'M') {
    return [`Cliente: ${nombre}`, `CUIT: ${dni}`, `Cond. IVA: ${condIva}`, `Domicilio: ${domicilio}`, `Cond. venta: ${condicionVenta}`];
  }
  return [`Cliente: ${clienteLabel(f)}`, ...(f.dni ? [`Doc: ${f.dni}`] : [])];
}

// IVA discrimination — A/M only
if (letra === 'A' || letra === 'M') {
  const { neto, impuesto } = computeNetoIva({ tpago: total, ivaBase: 1.21 });
  // Subtotal (neto) + IVA 21% (impuesto) shown as separate lines before TOTAL
}
```

### Reference: existing print-agent QR rendering pattern to copy into `fiscal-formatter.js`
```javascript
// Source: print-agent/src/qr-formatter.js (read this session — already working code, Phase 38)
const QRCode = require('qrcode');
const qrDataUri = await QRCode.toDataURL(String(qrUrl || ''), { margin: 1, width: 360 });
// ... <img class="qr" src="${qrDataUri}" />
```

### Reference: existing backend receptor resolution (docNro/resIva) — needs extending for full identity block
```typescript
// Source: api-ventago/src/app/afip/afip-voucher.service.ts::resolveReceptor (read this session)
// Currently only extracts docNro + resIva — buildFactura's receptor{razonSocial, domicilio, condIva}
// needs sale.storeClient.globalClient.{fullname, address} or sale.client.{fullname, address} added.
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
// GlobalClient/Clients models both have: fullname, document, address, resIva (verified via model read)
// resIva is a code ('-1'/'4'/etc, see ivaForResiva) — NOT a display string. A small
// display-label map (RI/MONO/EXENTO/CF → "Responsable Inscripto"/etc.) must be added for
// the receptor.condIva display field in buildFactura — no existing helper does this today.
```

### Reference: existing migration + DTO + form pattern to replicate exactly for `invoice_type` (D-08)
```sql
-- Source: api-ventago/migrations/afip-issuer-invoice-sucursal.sql (this session's precondition — exact pattern to copy)
ALTER TABLE afip_issuers
  ADD COLUMN IF NOT EXISTS invoice_type varchar(1) DEFAULT 'A';
-- (Apply verbatim to 5432 local + 5434 prod per CLAUDE.md "DB 마이그레이션 적용 규칙")
```
```typescript
// Source: api-ventago/src/app/afip/dto/upsert-issuer.dto.ts (pattern for invoiceSucursal — replicate for invoiceType)
@IsOptional()
@IsIn(['A', 'M'])
invoiceType?: string;
```
```tsx
// Source: ventago-app/.../ModalBranch.tsx (pattern — watch ivaCondition, gate visibility)
// ivaCondition values are exactly: 'RI' | 'MONO' | 'EXENTO' (verified via <MenuItem> values read)
{watch('ivaCondition') === 'RI' && (
  <RadioGroup row {...register('invoiceType')} defaultValue="A">
    <FormControlLabel value="A" control={<Radio />} label="Puede emitir Factura A" />
    <FormControlLabel value="M" control={<Radio />} label="Solo Factura M" />
  </RadioGroup>
)}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|---------------|--------|
| QR printed as raw URL text on thermal ticket (`fiscal-formatter.js` current state) | QR printed as scannable image via `qrcode.toDataURL` | This phase (D-03) | AFIP RG 4892 requires a scannable QR, not text — current output does not satisfy the regulation |
| A4 PDF with `lines: []` (always empty) | A4 PDF with real reconstructed lines via `buildFactura`+`applyPartial` | This phase (R3) | A4 is currently non-functional as a real invoice document |
| No automatic print dispatch after CAE issuance | `AfipController.issue()` calls `outputService.dispatch()` | This phase (implicit, required for REQ-1/REQ-3 to be testable) | Without this, none of the formatter improvements are reachable from the primary "Facturar" flow |

**Deprecated/outdated:**
- `fiscal-formatter.js`'s current `data.afip = {tipo, puntoVenta, numero, cae, vtoCae, qrUrl}` shape — superseded by D-02's `factura` structured object. The current shape lacks items, emisor, receptor, and IVA discrimination entirely, and is not called by any live code path today.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `AfipVoucherService.issueForSale()` should be extended to return `branchId` (derived as `sale.user?.branchId`, same as its internal PV derivation) so the controller can wire `dispatch()` without an extra query | Common Pitfalls #2, Architecture Diagram | If wrong, the controller would need a separate `Sale` lookup to get `branchId` — slightly more code, same outcome; low risk either way |
| A2 | NC/ND (R7) should call `dispatch()` synchronously inside `emit()` right after `voucherModel.create()`, mirroring the main `issue()` flow, rather than exposing a separate manual "imprimir" button | Pitfall 3 | If the user/planner prefers a manual trigger (consistent with D-06's explicit A4 button pattern) instead of auto-print, the wiring location changes (controller vs service) but the core `dispatch()` gap still needs closing either way — low risk, discretion item for the planner |
| A3 | The receptor `condIva` display string (e.g. "Responsable Inscripto") needs a new small mapping helper since `resIva` on `Clients`/`GlobalClient` is a numeric-ish code, not a display label | Code Examples | If wrong (e.g. if `resIva` already stores display text in practice for some records), the receptor block may show a raw code instead of a label — cosmetic risk, easy to fix in review |
| A4 | Using the project's existing `MemoryCacheService` (60s TTL convention) for the D-07 gateway cache is preferable to a bespoke `Map`, even though D-07's original discretion note suggested a plain Map | Standard Stack, Alternatives Considered | Low risk — either implementation satisfies the "TTL ~60s in-memory cache" requirement; `MemoryCacheService` is a style/consistency recommendation, not a correctness requirement |

**If this table is empty:** N/A — see rows above. All CRITICAL findings (D-07 endpoint, wiring gaps 1-3) are `[VERIFIED]`, not assumed.

## Open Questions

1. **Should NC/ND auto-dispatch thermal print immediately on emit, or require an explicit UI action?**
   - What we know: Today neither happens (Pitfall 3). D-06 establishes a precedent of explicit on-demand action for A4 (not auto-triggered).
   - What's unclear: SPEC's R7 acceptance criterion ("emitir una NC... imprime un ticket") reads as if it should happen automatically as part of `emit()`, but doesn't explicitly forbid a manual trigger.
   - Recommendation: Auto-dispatch thermal on `emit()` success (mirrors the main `issue()` fix, minimal extra UI work, satisfies the literal acceptance wording "al emitir... imprime").

2. **Where should `branchId` come from when `AfipController.issue()` calls `dispatch()`?**
   - What we know: `issueForSale()` already internally derives `branchId = sale.user?.branchId` for PV lookup purposes but discards it before returning.
   - What's unclear: Whether to (a) add `branchId` to `issueForSale()`'s return type, or (b) have the controller do a second lightweight `Sale.findOne({attributes:['id'], include:[{model:Users,attributes:['branchId']}]})`.
   - Recommendation: (a) — avoids an extra query, minimal interface change, `issueForSale()` already has the value in scope.

3. **Display-label mapping for `receptor.condIva` in the D-02 payload — new helper or extend `code-maps.ts`?**
   - What we know: `code-maps.ts::condIvaReceptorFor` returns a numeric AFIP code (1/4/5/6/9), and `ivaForResiva` classifies by `resiva` string, but neither produces a Spanish display label ("IVA Responsable Inscripto" etc.) for the receptor block.
   - What's unclear: Whether this small map belongs in `code-maps.ts` (co-located with the other AFIP constant maps) or in the new `build-factura.ts`.
   - Recommendation: Add to `code-maps.ts` for consistency (single source of AFIP display constants) — a small `Record<number,string>` keyed by the `COND_IVA_RECEPTOR` values already exported there.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `manager.coolsistema.com` (external gateway host) | REQ-6 (D-07 PV resolution) | ✓ (verified live, this session) | — | Existing fallback to `issuer.puntoVenta` local value already specified by D-07 |
| `invoice.coolsistema.com` (CAE issuance gateway, existing) | Pre-existing (not new to this phase) | ✓ (verified live, `/health` → `{"connected":true}`) | — | N/A — already the production provider (`rest-gateway.provider.ts`) |
| `qrcode` npm package | REQ-1, REQ-2, REQ-3 | ✓ (already installed both sides) | `^1.5.4` | N/A |
| `pdfkit` npm package | REQ-3, REQ-4 | ✓ (already installed) | `^0.14.0` | N/A |
| Local PG 5432 / prod PG 5434 (for `invoice_type` migration) | REQ-5 | ✓ (per project convention — see CLAUDE.md DB migration rules) | PG18 both | N/A — must apply migration to both per project's mandatory dual-apply rule |

**Missing dependencies with no fallback:** None.

**Missing dependencies with fallback:** None — the only "external" new dependency (manager gateway) already has its fallback path specified by D-07 and verified working.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Jest `^29.7.0` (ts-jest) |
| Config file | `api-ventago/package.json` (`jest` key, `rootDir: "src"`) — no separate `jest.config.js` |
| Quick run command | `cd api-ventago && npx jest src/app/afip --silent` |
| Full suite command | `cd api-ventago && npm test` |

Existing AFIP spec files already present (extend, don't replace): `afip-issuer.service.spec.ts`, `afip-output.service.spec.ts`, `afip-query.service.spec.ts`, `afip-voucher.service.spec.ts`, `code-maps.spec.ts`, `qr-builder.spec.ts`, `partial-invoice.spec.ts`, `pdf/a4-generator.spec.ts`, `nota-credito.service.spec.ts`, `nota-debito.service.spec.ts`, `auto-issue.spec.ts`, `providers/rest-gateway.provider.spec.ts`, `providers/cae-provider.factory.spec.ts`.

print-agent has no visible `*.test.js` under `src/` in this read (verify at plan time whether print-agent has its own jest/node:test config — `package.json` scripts show only `electron`/`build` scripts, no `test` script). **Wave 0 gap likely: no automated test harness for print-agent formatter output** — thermal formatter correctness will likely rely on manual/visual verification (PNG snapshot) rather than automated assertions, consistent with how `formatInvoiceHtml`/`formatTempTicketHtml` are tested today (no spec files found for them either).

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| REQ-1/2/3 (fiscal-formatter.js output) | HTML contains QR `<img>`, letra, items, IVA (for A/M) | unit (string/DOM assertions on returned HTML) | `npx jest print-agent/src/fiscal-formatter` (if migrated to Jest) or `node --test` | ❌ Wave 0 — no existing spec for `fiscal-formatter.js` found |
| REQ-3 (a4-generator lines) | PDF byte output non-trivial, `lines.length > 0` reflected | unit | `cd api-ventago && npx jest src/app/afip/pdf/a4-generator.spec.ts` | ✅ file exists, needs new assertions for real lines |
| REQ-5 (decideComprobante A/M gate) | `decideComprobante('RI', {configInvoiceType:'M', docNro:<11 digits>})` → `'M'`; `decideComprobante('MONO', {configInvoiceType:'M',...})` → `'C'` (gate ignored) | unit | `cd api-ventago && npx jest src/app/afip/code-maps.spec.ts` | ✅ file exists, extend with A/M-gate cases |
| REQ-6 (manager header resolution) | mocked-http unit tests for cache hit/miss/fallback/null-response/empty-branchs | unit | `cd api-ventago && npx jest src/app/afip/afip-issuer.service.spec.ts` | ✅ file exists, needs new describe block for `resolvePvAndCoolUser` |
| REQ-7 (NC/ND dispatch wiring) | `emit()` calls `outputService.dispatch` with correct `voucherId`/`output` | unit (mock `AfipOutputService`) | `cd api-ventago && npx jest src/app/afip/nota-credito.service.spec.ts src/app/afip/nota-debito.service.spec.ts` | ✅ files exist, need new assertion for dispatch call |
| Pitfall 2 fix (issue() dispatch wiring) | `AfipController.issue()` calls `dispatch()` after success | unit/e2e | `cd api-ventago && npx jest src/app/afip/afip.controller` (no spec file found — new file needed) | ❌ Wave 0 — no `afip.controller.spec.ts` exists today |

### Sampling Rate

- **Per task commit:** `cd api-ventago && npx jest src/app/afip --silent`
- **Per wave merge:** `cd api-ventago && npm test` (full backend suite) + manual print-agent visual check (PNG output inspection, per project's existing pattern for `print-debug-*.png` on dev)
- **Phase gate:** Full backend suite green + ESLint clean (ventago-app) + tsc clean (api-ventago) before `/gsd-verify-work`, per SPEC.md's explicit acceptance criterion

### Wave 0 Gaps

- [ ] `api-ventago/src/app/afip/afip.controller.spec.ts` — new file, covers issue()→dispatch() wiring (Pitfall 2 fix)
- [ ] `api-ventago/src/app/afip/build-factura.spec.ts` — new file, covers D-04 single-source function + D-05 line reconstruction
- [ ] print-agent test harness for `fiscal-formatter.js` — no existing pattern found (`formatInvoiceHtml` also untested); if the project wants automated coverage here, this is new infrastructure, not an extension. Given no test script exists in `print-agent/package.json`, recommend scoping this as manual/visual verification (matches existing project convention) rather than introducing a new test framework mid-phase.

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | Partial | `@Auth(ValidRoles...)` decorators already gate all `afip.controller.ts` routes — unchanged by this phase |
| V4 Access Control | Yes | `requireStoreId(user)` pattern already enforces store-scoping on every AFIP route; `dispatch()`'s thermal branch already re-validates `branch.storeId` ownership before emitting (existing cross-tenant guard, verified in `afip-output.service.ts` read) — new `buildFactura` Sale/SaleItem load must keep the same `where: {storeId, id: saleId}` scoping pattern used by `loadSaleWithReceptor` |
| V5 Input Validation | Yes | New `invoiceType` DTO field must use `@IsIn(['A','M'])` (matches existing `ivaCondition` pattern `@IsIn(['RI','MONO','EXENTO'])`) — never trust a raw string from the frontend |
| V6 Cryptography | N/a | No new crypto in this phase (CAE/QR already backend-computed, no HMAC/signing added) |
| V13 API and Web Service | Yes | The new outbound call to `manager.coolsistema.com` is unauthenticated by the gateway's own design (verified — no auth header sent, none required) — this is an **external-service characteristic, not something Ventago controls**; document this in code comments so a future security review doesn't mistake it for a Ventago-side auth omission |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Cross-tenant data leak via `voucher.saleId` join (new Sale/SaleItem load in `dispatch()`) | Information Disclosure | Always scope the new Sale query by `{storeId, id: saleId}` — never `findByPk` alone. `voucher.storeId` is already available from `getVoucher(storeId, id)`'s existing scoping; reuse it. |
| SSRF-adjacent risk from constructing the manager URL with unsanitized `cuit`/`sucursal` | Tampering | Both values originate from `afip_issuers` (admin-managed, not end-user input) and are coerced to `Number`/digit-stripped string before use — low risk, but keep the `Number(sucursal)` / digits-only `cuit` coercion explicit in the new resolver (matches existing `qr-builder.ts` normalization pattern) |
| Double-CAE from retrying the manager header call inside a retry loop that also wraps the CAE POST | Repudiation / Tampering | Per D-07 and the existing `classifyTransportError`/`ambiguous` pattern in `rest-gateway.provider.ts` — the manager header GET must be its own isolated try/catch with NO retry-then-reissue coupling to the CAE POST; a failed/slow header lookup should fall back to local `puntoVenta` and proceed with a SINGLE CAE POST attempt, never trigger a second issuance attempt |

## Sources

### Primary (HIGH confidence — verified in this session)

- **Live HTTP verification** (`curl`, 2026-07-20) — `manager.coolsistema.com/api/data/header/cuit/{cuit}/{sucursal}` (200, real JSON), `invoice.coolsistema.com` same path (404, wrong host confirmed), edge cases (null cuit, empty branchs, missing segment, hyphenated cuit, CORS/auth headers)
- **Direct file reads (this session):** `api-ventago/src/app/afip/*.ts` (all files), `api-ventago/src/app/afip/models/*.ts`, `api-ventago/src/app/afip/providers/*.ts`, `api-ventago/src/app/afip/pdf/a4-generator.ts`, `api-ventago/src/app/afip/afip.controller.ts`, `print-agent/src/*.js` (fiscal-formatter, formatter, qr-formatter, print-pipeline, index.js), `print-agent/main.js` (print_invoice handler), `print-agent/package.json`, `api-ventago/package.json`, `ventago-app/src/views/facturacion/*.tsx`, `ventago-app/src/services/afip.service.ts`, `ventago-app/.../ModalBranch.tsx`, `api-ventago/src/app/print/print.service.ts`, `api-ventago/src/app/sales/sales-create.service.ts` (auto-issue call site), `api-ventago/src/app/clients/clients.model.ts`, `api-ventago/src/app/shared/global-clients/global-clients.model.ts`, `api-ventago/migrations/afip-issuer-*.sql`
- **`grep` call-site verification (this session):** confirmed `AfipOutputService.dispatch()` has exactly 3 call sites (all in `afip.controller.ts`), confirmed `nota-credito.service.ts`/`nota-debito.service.ts` have zero `dispatch`/`branchId` references, confirmed `qrcode` present in both `package.json` files
- **CoolSyncro reference (read-only parity source, this session):** `src/main/afip/rest-gateway-provider.js`, `src/main/afip/code-maps.js` (implied via Ventago's port), `src/main/pdf/generator.js`, `src/main/pdf/thermal-generator.js`

### Secondary (MEDIUM confidence)

- CONTEXT.md / SPEC.md (project documents, user-approved via `/gsd-discuss-phase` and `/gsd-spec-phase`) — treated as locked constraints, not independently re-verified beyond D-07

### Tertiary (LOW confidence)

- None — all claims in this research are either `[VERIFIED]` by direct file read/live HTTP call, or explicitly logged in the Assumptions table above.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — verified via direct `package.json` reads on both `print-agent` and `api-ventago`
- Architecture / wiring gaps: HIGH — verified via direct file reads + `grep` call-site enumeration, not inference
- D-07 gateway endpoint: HIGH — verified via live `curl` against production external host, multiple edge cases tested
- Pitfalls: HIGH — each pitfall corresponds to a specific file/line read this session, not a general pattern guess

**Research date:** 2026-07-20
**Valid until:** 30 days (stable internal codebase + a third-party gateway contract that has been stable enough for CoolSyncro's production use — re-verify D-07 live if execution is delayed past ~4-6 weeks, since it's an external, unversioned API)
