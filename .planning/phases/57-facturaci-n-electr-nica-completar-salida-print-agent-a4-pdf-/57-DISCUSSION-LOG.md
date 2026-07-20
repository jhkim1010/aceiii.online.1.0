# Phase 57 — Discussion Log

**Date:** 2026-07-20
**Mode:** discuss (default)

SPEC.md loaded (7 requirements locked) → discussion focused on HOW only.

## Gray areas presented (multiSelect)
1. print_invoice socket payload + QR ✅ discutido
2. A4 líneas + partial % ✅ discutido
3. manager /data/header integración + caché → Claude's discretion (D-07)
4. A/M migración + backfill + gate IVA → Claude's discretion (D-08)

## Área 1 — payload + QR
| Pregunta | Opciones | Elegido |
|----------|----------|---------|
| ¿Cómo renderizar el QR escaneable? | print-agent genera de qrUrl / backend envía PNG | **print-agent genera (qrcode dep)** → D-01 |
| ¿Estructura del payload factura? | backend estructurado / raw voucher+sale | **backend estructurado** → D-02 |

Hallazgo: el `fiscal-formatter` actual imprime el QR como texto de URL, no como código escaneable (D-03).

## Área 2 — A4 líneas + partial
| Pregunta | Opciones | Elegido |
|----------|----------|---------|
| ¿Fuente de líneas A4? | factura estructurada común / a4 carga sale.items aparte | **factura común (buildFactura)** → D-04 |
| ¿Partial % (invoice_pct)? | reusar applyPartial (= preview F10) / línea sintética | **applyPartial, = preview F10** → D-05 |

## Claude's discretion (áreas no seleccionadas)
- D-07: manager PV/coolUser resolución en loadIssuer, caché cuit+sucursal TTL 60s, fallback a puntoVenta local. ⚠ verificar endpoint Node vivo en plan (path Java dio 404).
- D-08: invoice_type default 'A', gate M solo si IVA=RI, selector solo RI.

## Deferred
- SOAP directo, envío digital PDF, Factura C — fases propias.
