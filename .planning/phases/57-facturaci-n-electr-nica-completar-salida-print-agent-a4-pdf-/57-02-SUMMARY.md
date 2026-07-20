---
phase: 57-facturaci-n-electr-nica-completar-salida-print-agent-a4-pdf-
plan: 02
subsystem: print-agent (salida fiscal ESC/POS)
tags: [afip, factura-electronica, print-agent, escpos, qr, wiring-gap]
requires:
  - "backend buildFactura (Plan 01) que produce la shape factura D-02"
  - "socket event print_invoice con payload.factura (emitPrintInvoice)"
provides:
  - "formatFiscalHtml(factura) async — renderiza el comprobante D-02 completo con QR imagen escaneable"
  - "print_invoice handler bifurcado en payload.factura (path fiscal vs control ticket)"
affects:
  - "print-agent/src/fiscal-formatter.js"
  - "print-agent/main.js (print_invoice + print_fiscal handlers)"
tech-stack:
  added: []
  patterns:
    - "qrcode@^1.5.4 QRCode.toDataURL -> <img data-uri> (patrón qr-formatter.js Phase 38, hoisted desde root node_modules)"
    - "HTML standalone -> renderHtmlToPng(576) -> printImage (pipeline Phase 11)"
key-files:
  created: []
  modified:
    - "print-agent/src/fiscal-formatter.js (reescrito async, shape D-02)"
    - "print-agent/main.js (branch fiscal + fix hermano print_fiscal)"
decisions:
  - "fiscal-formatter genera HTML standalone en vez de extender formatInvoiceHtml (la shape factura D-02 es independiente del control-ticket; main.js pasa SOLO payload.factura, no el payload de control)"
  - "El path fiscal se gatea con printFiscal (coherente con el handler hermano print_fiscal), no printControl"
  - "print_fiscal hermano actualizado a await formatFiscalHtml(payload.factura||payload) porque el rewrite hizo la función async"
metrics:
  duration: 8min
  tasks: 2
  files: 2
  completed: 2026-07-20
---

# Phase 57 Plan 02: Salida fiscal ESC/POS del print-agent (factura D-02 + QR imagen) Summary

Reescritura de `fiscal-formatter.js` para consumir la shape `factura` D-02 del backend y renderizar el comprobante ESC/POS completo (letra chip + COD, emisor, receptor A/M vs B, ítems, IVA 21% discriminado, CAE/Vto, QR RG 4892 escaneable, leyenda AFIP/ARCA), más el cableado de `main.js::print_invoice` para bifurcar al path fiscal cuando llega `payload.factura` (WIRING GAP #1 cerrado).

## What Was Built

### Task 1 — `fiscal-formatter.js` reescrito (async, shape D-02, QR imagen) — commit `dcf22c5`
- `formatFiscalHtml` pasó de sync (shape `data.afip`, QR-como-texto) a **`async function formatFiscalHtml(factura)`** que consume la shape D-02 directamente.
- Requiere `const QRCode = require('qrcode')` (1.5.4, ya instalado vía hoisting del root `node_modules` del monorepo — no se instaló nada).
- Orden de render (paridad `CoolSyncro/thermal-generator.js`): caja de letra 40pt + `COD. NN` → N° comprobante + fecha → EMISOR (razonSocial/CUIT/domicilio/Cond.IVA/IIBB/Inicio act.) → RECEPTOR (si `receptor.tipo==='identificado'` → Cliente/CUIT/Cond.IVA/Domicilio; si `'consumidorFinal'` → "Consumidor Final" + Doc opcional) → tabla de ítems (desc con clamp 2 líneas CSS) → **IVA 21% discriminado SOLO si `factura.ivaDiscrim`** (Subtotal=neto, IVA 21%=iva21) → TOTAL → CAE N° + Vencimiento CAE → **QR imagen escaneable** (`QRCode.toDataURL(qrUrl, {margin:1,width:360})` → `<img class="qr">`) → leyenda "Comprobante autorizado — AFIP/ARCA".
- Helper local `escapeHtml(s)` aplicado a **todo campo de texto** antes de interpolar (T-57-04); `qrUrl` entra SOLO en `QRCode.toDataURL`, nunca como innerHTML/href.
- Eliminado el bloque "Verificar en AFIP: <texto url>". El print-agent nunca re-deriva letra/IVA — solo renderiza los campos ya decididos por el backend (T-57-03).
- Smoke node (Factura A) imprime `FISCAL_A_OK`; verificación adicional (Factura B) confirma que B no muestra IVA y muestra "Consumidor Final".

### Task 2 — `main.js::print_invoice` bifurca en `payload.factura` (WIRING GAP #1) — commit `ccdf560`
- Dentro del `try` existente del handler `print_invoice`, antes de `printTicket`: si `payload.factura` presente → gate `printFiscal` → `formatFiscalHtml(payload.factura)` + `renderHtmlToPng(html,576,10000)` + `printImage` + `print_ack{status:'ok'}` + `return`.
- El path no-fiscal (`printTicket` → control ticket) queda **exactamente igual** — sin regresión (T-57-05; grep confirma `printTicket(payload` persiste).
- `node --check main.js` limpio; imports `formatFiscalHtml`/`renderHtmlToPng`/`printImage` ya presentes.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Handler hermano `print_fiscal` roto por el cambio de contrato de `formatFiscalHtml`**
- **Found during:** Task 2
- **Issue:** El rewrite de Task 1 convirtió `formatFiscalHtml` en async con la nueva shape D-02. El handler hermano `print_fiscal` (`main.js:~1010`) llamaba `const html = formatFiscalHtml(payload)` de forma síncrona con la shape antigua → tras el rewrite `html` sería una `Promise` y `renderHtmlToPng` fallaría. Es código actualmente no usado por `dispatch()` pero presente, así que el rewrite introducía un bug latente.
- **Fix:** `const html = await formatFiscalHtml(payload.factura || payload);` (await + shape D-02, con fallback al payload).
- **Files modified:** print-agent/main.js
- **Commit:** ccdf560

### Design deviations (documented, not asked — within Rule 3)

**2. HTML standalone en vez de extender `formatInvoiceHtml`**
- El plan sugería "mantener el patrón de inyección CSS (`html.replace('</body>', ...)`)" extendiendo el control ticket base. Se construyó en cambio un **documento HTML standalone** (mismo enfoque que `qr-formatter.js`, el analog de QR citado). Razón: la shape `factura` D-02 es independiente de los datos del control-ticket, y `main.js` pasa SOLO `payload.factura` (no el payload de control), por lo que extender `formatInvoiceHtml(factura)` renderizaría un control-ticket vacío/roto. El smoke test del plan pasa únicamente el objeto `factura`, confirmando el contrato standalone. Se eliminó el `require('./formatter')` innecesario.

## Threat Model Compliance

| Threat ID | Disposition | Applied |
|-----------|-------------|---------|
| T-57-03 (Tampering — re-derivar letra/IVA) | mitigate | ✅ formatter consume SOLO `factura.*`; no importa/reimplementa decideComprobante ni computeNetoIva |
| T-57-04 (Injection en HTML render Electron) | mitigate | ✅ `escapeHtml()` sobre todo campo de texto; `qrUrl` solo dentro de `QRCode.toDataURL` |
| T-57-05 (Regresión control tickets no-AFIP) | mitigate | ✅ branch fiscal solo si `payload.factura`; `printTicket(payload` intacto (grep confirmado) |

## Verification

- `node --check main.js` → exit 0
- Smoke Factura A → `FISCAL_A_OK` (contiene `<img`, `IVA 21`, CUIT emisor)
- Smoke Factura B → `FISCAL_B_OK` (sin `IVA 21`, con "Consumidor Final")
- Acceptance greps: `QRCode.toDataURL` ✅, `async function formatFiscalHtml` ✅, `! Verificar en AFIP` ✅, `ivaDiscrim` ✅, `formatFiscalHtml(payload.factura` ✅, `printTicket(payload` (no regresión) ✅
- **Pendiente (manual, homologación — 57-VALIDATION.md):** emitir Factura A y B reales, escanear el QR del ticket → debe decodificar a `afip.gob.ar/fe/qr` con `codAut=CAE`; A muestra IVA 21%, B no. Requiere el backend Plan 01 emitiendo `payload.factura` y un print-agent con el nuevo build desplegado.

## Known Stubs

Ninguno. `formatFiscalHtml` consume todos los campos D-02; no hay placeholders ni datos mock.

## Deployment Note

El print-agent en operación necesita un **rebuild + reinstalación** (`push-both.sh` → GitHub Actions `build-print-agent.yml` → reinstalar en PC de operación) para recibir este código — acción del usuario, no del ejecutor. En dev (`npm run dev:print`) el código nuevo aplica al instante. Sin el rebuild, la salida fiscal en operación no cambia (mismo gate que el blocker 39-03 registrado en STATE.md).

## Self-Check: PASSED

- `print-agent/src/fiscal-formatter.js` — FOUND (modificado, smoke FISCAL_A_OK/FISCAL_B_OK)
- `print-agent/main.js` — FOUND (node --check OK, branch fiscal presente)
- Commit `dcf22c5` — FOUND (Task 1)
- Commit `ccdf560` — FOUND (Task 2)
