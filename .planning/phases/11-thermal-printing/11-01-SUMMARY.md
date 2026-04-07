---
phase: 11
plan: 01
subsystem: print-agent
tags: [electron, escpos, thermal-printing, html-to-png, raster]
requires: []
provides:
  - formatInvoiceHtml(data) — HTML ticket generator
  - renderHtmlToPng(html, width) — Electron offscreen renderer
  - printTicket(data, printerConfig) — 3-stage pipeline
  - printImage(pngBuffer, printerConfig) — ESC/POS raster output
affects: [print-agent/src]
tech-stack:
  added: [electron-offscreen-rendering, escpos.Image, D24 raster mode]
  patterns: [singleton offscreen window, serial promise queue, immediate device.close]
key-files:
  created:
    - print-agent/src/renderer-engine.js
    - print-agent/src/print-pipeline.js
    - print-agent/ticket-preview.html
  modified:
    - print-agent/src/formatter.js
    - print-agent/src/printer.js
decisions:
  - Singleton offscreen BrowserWindow + serial queue avoids Chromium process pool waste
  - Per-item discounts rendered in subtotal section (not in product row)
  - escpos D24 raster mode chosen over text mode for color/bold/2-line wrap support
  - device.close() immediately after print — no connection pooling for thermal printer
metrics:
  duration: reconciled
  completed: 2026-04-06
---

# Phase 11 Plan 01: 그래픽 출력 파이프라인 코어 Summary

HTML→PNG→ESC/POS raster pipeline that prints modern color thermal tickets on 80mm paper using Electron's bundled Chromium for rendering.

## What Was Built

### 1. `src/formatter.js` — HTML ticket generator
`formatInvoiceHtml(data)` returns a complete 80mm-wide HTML document containing:
- Top banner: `DOCUMENTO NO VÁLIDO COMO FACTURA` (black bg, white text)
- Store header (uppercase bold name, address, phone, CUIT)
- Ticket meta (number/copy, date, time, seller, client)
- 4-column product table (Cnt / Descripción / P.Unit / SubTot)
- Subtotal section with colored rows:
  - `Subtotal` — bold #333
  - `+ Recargo` — blue #1565c0
  - `− Descuento` — red #c62828
  - `− Desc. {item}` — red (per-item discounts moved here)
  - `+ Envío` — blue (only if `transport > 0`)
  - `TOTAL` — black bg, white 30px
- Payment methods with ★ icon
- Footer thank-you message
- Product names limited to 2 lines via `-webkit-line-clamp: 2`

Backwards-compatible `formatInvoice(data, width)` text fallback retained.

### 2. `src/renderer-engine.js` — Electron offscreen renderer
`renderHtmlToPng(html, width = 576, timeout = 10000)` returns a PNG `Buffer`.
- Singleton `offscreenWin` created once and reused (no pool waste)
- Serial promise queue prevents concurrent renders
- `offscreen: true`, `webSecurity: false`
- Auto-height: reads `document.body.scrollHeight` then `setSize(576, h)`
- Uses `capturePage()` → NativeImage → PNG
- Requires Electron `app.whenReady()`

### 3. `src/print-pipeline.js` — orchestrator
`printTicket(data, printerConfig)` chains the 3 stages:
1. `formatInvoiceHtml(data)` → HTML
2. `renderHtmlToPng(html, 576)` → PNG Buffer
3. `printImage(pngBuffer, printerConfig)` → printer

Each stage throws on failure for the IPC layer to surface as `print_ack` errors.

### 4. `src/printer.js` — ESC/POS output
- `printImage(pngBuffer, printerConfig)` — `escpos.Image.load()` + `printer.image(img, 'D24')`
- `printReceipt(lines, printerConfig)` — text fallback retained
- `testConnection(printerConfig)` — returns `{ ok, message }`
- Supports USB (`vendorId`/`productId`) and network (`host`/`port`)
- `device.close()` called immediately after each print

## Verification

`ticket-preview.html` committed as the visual verification artifact. Sample data exercises every styled row (recharge, discount, item discount, transport, multi-line product name, payment method with cuotas).

Visual checklist (all passing):
- [x] Subtotal row bold
- [x] `+ Recargo` blue
- [x] `− Descuento` red
- [x] `− Desc. {item}` red
- [x] `+ Envío` blue
- [x] TOTAL block black bg / white / large
- [x] Long product names wrap to 2 lines
- [x] No discount row inside product table

## Commits

| Hash | Message |
|------|---------|
| 5a43b9a | feat(11-01): add HTML ticket formatter with color subtotals |
| 59d2dd1 | feat(11-01): add HTML→PNG→ESC/POS raster pipeline |
| 653b060 | chore(11-01): add ticket-preview.html visual verification artifact |

(committed inside the nested `print-agent/` git repository)

## Deviations from Plan

State reconciliation: plan was marked `status: completed` and all deliverables existed on disk in `print-agent/`, but were uncommitted (showing as `M`/`??` in git status) and no SUMMARY.md existed. Action taken: committed the existing Wave 1 files into the print-agent repo as 3 atomic commits and authored this SUMMARY. The `renderer/` directory (HTML setup wizard) was intentionally left untracked because it belongs to Wave 2 (plan 11-02).

No code changes were required — all functionality already matched plan spec.

## Known Stubs

None. All four files are functionally complete per the plan's done-criteria.

## Self-Check: PASSED

- print-agent/src/formatter.js — FOUND
- print-agent/src/renderer-engine.js — FOUND
- print-agent/src/print-pipeline.js — FOUND
- print-agent/src/printer.js — FOUND
- print-agent/ticket-preview.html — FOUND
- commit 5a43b9a — FOUND in print-agent repo
- commit 59d2dd1 — FOUND in print-agent repo
- commit 653b060 — FOUND in print-agent repo
