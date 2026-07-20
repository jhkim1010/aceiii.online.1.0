# Phase 57: Facturación Electrónica — Completar salida + A4 PDF + A/M por sucursal + paridad de gateway — Specification

**Created:** 2026-07-19
**Ambiguity score:** 0.18 (gate: ≤ 0.20)
**Requirements:** 7 locked

## Goal

La factura electrónica de Ventago pasa de "CAE emitido pero salida incompleta" a **paridad con CoolSyncro**: el print-agent imprime el comprobante ESC/POS con CAE/Vto/QR/letra/ítems/IVA, el A4 PDF se puede emitir en cualquier momento con líneas reales, cada sucursal RI elige Factura A o solo M, y el punto de venta lo resuelve el gateway (manager) a partir del `invoice_sucursal`.

## Background

AFIP factura electrónica ya existe en Ventago (`api-ventago/src/app/afip/`, Phase 10 no formalizada — Plan 1-4 en main): emisión, NC/ND, QR builder, `decideComprobante` (con rama A/M en `code-maps.ts:165-170`), A4 generator esqueleto, y dispatch a print-agent por socket `print_invoice`. Gaps actuales medidos contra CoolSyncro (`/Users/marcoskim/Trabajos_Programming/CoolSyncro`, referencia Electron completa):

- **print-agent** (`print-agent/src/fiscal-formatter.js`) imprime un bloque fiscal básico, pero sin QR, sin discriminación de IVA para A/M, sin letra/COD, sin ítems formateados como comprobante AFIP.
- **A4 PDF** (`afip-output.service.ts:82`) se genera con `lines: []` — sin ítems, sin discriminación IVA, layout mínimo. No hay botón para emitir/descargar A4 on-demand desde Emitidas ni POS.
- **A/M por sucursal**: `decideComprobante` ya acepta `configInvoiceType==='M'`, pero no existe columna ni UI para fijarlo por sucursal — siempre resuelve A para receptor CUIT.
- **Gateway**: el provider reconciliado hoy (`rest-gateway.provider.ts`, 2026-07-19) envía `point` local a `POST /invoice/ar`. CoolSyncro resuelve PV vía `GET manager.coolsistema.com/api/data/header/cuit/{cuit}/{sucursal}` → `branchs[0].point` + `coolUser`, alineado con "el PV lo decide invoice".

**Ya aterrizado en esta sesión (precondición, aún sin commit al cierre del spec):**
- `afip_issuers.invoice_sucursal` (columna + modelo + DTO + campo ModalBranch "Sucursal de invoice"). Migración aplicada en local 5432 y prod 5434.
- POS: flujo F10 (F2 = venta sin factura, F10 = venta + preview de emisión) + sección Preferencias ▸ Ventas ▸ Facturación AFIP (toggle FE + % por defecto).

## Requirements

1. **print-agent — comprobante ESC/POS completo (W1)**: el ticket térmico impreso incluye todos los campos fiscales AFIP.
   - Current: `fiscal-formatter.js` imprime bloque fiscal parcial; sin QR, sin letra/COD, sin discriminación de IVA, ítems sin formato de comprobante
   - Target: el formatter ESC/POS (pipeline HTML→PNG→ESC/POS de Phase 11, cross-platform) renderiza: letra chip (A/B/M) + `COD. NN`, N° comprobante, fecha, emisor (razón social, CUIT, domicilio, cond. IVA, IIBB, inicio act.), receptor (A/M = CUIT+cond.IVA+domicilio; B = Consumidor Final), ítems, para A/M subtotal neto + columna IVA 21%, TOTAL, `CAE N°`, `Vencimiento CAE`, QR RG 4892, leyenda "Comprobante autorizado AFIP/ARCA"
   - Acceptance: emitiendo una Factura A y una Factura B en homologación, el ticket impreso (o su PNG renderizado) contiene CAE, Vto CAE, QR escaneable, letra correcta; para A aparece la columna IVA 21% discriminada, para B no

2. **QR RG 4892 en el ticket (W1)**: el QR del ticket usa el payload oficial AFIP.
   - Current: el ticket no imprime QR fiscal
   - Target: se genera el QR con base `https://www.afip.gob.ar/fe/qr/?p=` + payload base64 `{ver,fecha,cuit,ptoVta,tipoCmp,nroCmp,importe,moneda:'PES',ctz:1,tipoDocRec,nroDocRec,tipoCodAut:'E',codAut}` (reusar `qr-builder.ts` existente del backend; el print-agent recibe la URL/PNG por el payload del socket)
   - Acceptance: el QR impreso decodifica a una URL `afip.gob.ar/fe/qr/?p=<base64>` cuyo JSON contiene el `codAut` = CAE emitido y `nroCmp` = número AFIP del comprobante

3. **A4 PDF con líneas reales + layout de comprobante (W2)**: el A4 deja de salir vacío.
   - Current: `afip-output.service.ts:82` pasa `lines: []`; el A4 no lista ítems ni discrimina IVA
   - Target: `a4-generator.ts` recibe y renderiza los ítems de la venta (cantidad, descripción, P.Unit, subtotal), letra chip + COD, emisor/receptor por letra, para A/M P.Unit neto (`preuni/1.21`) + columna IVA 21% + Neto Gravado/IVA/TOTAL, QR, `CAE N°`, `Vencimiento CAE`, leyenda AFIP (paridad con CoolSyncro `generator.js`)
   - Acceptance: `GET /afip/vouchers/:id/pdf` de una Factura A con ≥2 ítems devuelve un PDF que lista los 2 ítems, muestra IVA 21% discriminado y Neto+IVA+TOTAL coherentes con `imp_total`; una Factura B muestra precios con IVA incluido sin columna IVA

4. **A4 PDF on-demand (W2)**: el A4 se puede emitir/descargar en cualquier momento tras la emisión.
   - Current: no hay entrada de UI para regenerar/descargar el A4 de un comprobante ya emitido
   - Target: botón "A4 PDF" en el panel Emitidas (y en POS tras F10) que llama `GET /afip/vouchers/:id/pdf` y abre/descarga el PDF; funciona para cualquier comprobante con CAE, sin re-emitir ni pedir nuevo CAE
   - Acceptance: desde Facturación ▸ Emitidas, hacer clic en "A4 PDF" de un comprobante emitido descarga/abre el PDF sin generar un nuevo CAE (el `afip_number` no cambia)

5. **Selección Factura A/M por sucursal (W3)**: cada sucursal RI decide si emite A o solo M.
   - Current: no existe columna ni UI; receptor CUIT siempre resuelve A
   - Target: columna `afip_issuers.invoice_type` (`'A'`|`'M'`, default `'A'`) + migración local 5432/prod 5434; selector en ModalBranch visible **solo cuando Cond. IVA = RI** ("Puede emitir Factura A" / "Solo Factura M"); `decideComprobante` recibe `issuer.invoiceType` de modo que receptor CUIT → A salvo `invoice_type==='M'` → M
   - Acceptance: con una sucursal RI marcada "Solo Factura M", emitir a un receptor con CUIT produce CbteTipo 51 (M); con la misma sucursal marcada "Puede emitir A" produce CbteTipo 1 (A); una sucursal MONO/EXENTO no muestra el selector

6. **Resolución de PV vía gateway manager (D2)**: el punto de venta lo decide invoice, no el valor local.
   - Current: el provider envía `issuer.puntoVenta` local a `POST /invoice/ar`; `manager` no se consulta
   - Target: antes de emitir, si `invoice_sucursal` está seteado, resolver `GET manager.coolsistema.com/api/data/header/cuit/{cuit}/{invoice_sucursal}` → `branchs[0].point` (PV) + `coolUser` (con caché por CUIT); usar ese `point`/`coolUser` en la emisión; fallback al `puntoVenta` local si el header falla o `invoice_sucursal` no está seteado
   - Acceptance: (plan-time) verificar el endpoint real del gateway Node en vivo; con un `invoice_sucursal` válido, el `point` usado en la emisión proviene de `branchs[0].point` del header manager, no del `puntoVenta` local; si el header no responde, cae al `puntoVenta` local y registra el fallback

7. **NC/ND conservan salida completa (regresión)**: notas de crédito/débito imprimen con el mismo detalle fiscal.
   - Current: NC/ND emiten y guardan, pero heredan la salida incompleta (sin QR/ítems/IVA en ticket)
   - Target: la ruta de impresión de NC/ND reusa el mismo formatter ESC/POS y A4 mejorados (R1-R4), con la letra derivada (NCA/NCB/NCM, NDA/NDB/NDM) y la referencia al comprobante original visible
   - Acceptance: emitir una NC sobre una Factura A imprime un ticket con letra "NC A", CAE propio, QR, ítems y IVA discriminado; el A4 de esa NC lista los ítems

## Boundaries

**In scope:**
- print-agent `fiscal-formatter.js` (ESC/POS) extendido: letra/COD, emisor/receptor, ítems, IVA 21% para A/M, CAE/Vto, QR, leyenda
- QR RG 4892 en el ticket (payload del backend `qr-builder.ts`)
- `a4-generator.ts` con ítems reales + discriminación IVA + QR + CAE (paridad `generator.js`)
- Botón "A4 PDF" on-demand en Emitidas y POS
- `afip_issuers.invoice_type` (A|M) + migración 5432/5434 + selector ModalBranch (solo RI) + wire a `decideComprobante`
- Resolución de PV/coolUser vía `manager /data/header` con caché y fallback
- NC/ND reusan la salida mejorada (sin regresión)

**Out of scope:**
- Modo SOAP directo WSAA/WSFEv1 — sigue siendo `soap-direct.provider` stub; este phase es solo gateway `ws` (decisión previa: SOAP es fase posterior)
- Factura C / Monotributo emisor con letra C — el contrato CoolSyncro no tiene C; fuera de alcance
- Envío digital (WhatsApp/email del PDF) — el output `digital` sigue stub; separate backlog
- Cambiar el modelo de flags de emisión (F10/F2, Preferencias AFIP) — ya aterrizado en esta sesión, no se re-abre
- Impresión térmica vía PDF (pdf-to-printer estilo CoolSyncro) — se descartó por Windows-only; se mantiene ESC/POS cross-platform (D1)
- Migración retroactiva de comprobantes ya emitidos con A4 vacío — solo emisiones nuevas y regeneración on-demand

## Constraints

- **Plataformas**: api-ventago (NestJS/Sequelize `underscored`), ventago-app (Next.js 13 Pages, MUI 5, ESLint warning=error → newline-before-return / lines-around-comment / no-unused-vars), print-agent (Electron ESC/POS, socket `/print-agent` namespace)
- **Migraciones**: `invoice_type` debe aplicarse a local 5432 **y** prod 5434 simultáneamente; SQL commit en `api-ventago/migrations/`; owner→coolsistema no necesario para ADD COLUMN
- **Sin regresión retail/restaurante**: el print-agent imprime también tickets de control no fiscales — los cambios al formatter no deben romper la impresión no-AFIP existente
- **Doble emisión**: se mantiene la clasificación ambiguous/retryable/fatal del provider — resolver PV vía manager no debe introducir reintentos que dupliquen CAE
- **QR/códigos AFIP**: CbteTipo A=1 B=6 M=51 E=19; NCA=3 NCB=8 NCM=53; NDA=2 NDB=7 NDM=52; DocType CUIT=80 DNI=96 CF=99; IVA 21%=code 5
- **pool PostgreSQL**: sin cambios al pool; el header manager es HTTP externo, no DB

## Acceptance Criteria

- [ ] El ticket ESC/POS de una Factura A en homologación imprime CAE, Vto CAE, QR escaneable, letra "A" + COD, ítems, IVA 21% discriminado
- [ ] El ticket de una Factura B no muestra columna IVA y muestra "Consumidor Final"
- [ ] El QR del ticket decodifica a `afip.gob.ar/fe/qr/?p=` con `codAut`=CAE y `nroCmp`=número AFIP
- [ ] `GET /afip/vouchers/:id/pdf` de una Factura A con ≥2 ítems lista los ítems y discrimina IVA 21%
- [ ] Botón "A4 PDF" en Emitidas descarga el PDF de un comprobante emitido sin re-emitir CAE
- [ ] `afip_issuers.invoice_type` existe en 5432 y 5434; migración commiteada en `migrations/`
- [ ] Sucursal RI "Solo Factura M" → CbteTipo 51 a receptor CUIT; "Puede emitir A" → CbteTipo 1
- [ ] El selector A/M no aparece para sucursal MONO/EXENTO
- [ ] Con `invoice_sucursal` seteado, el `point` emitido proviene de `manager /data/header` (branchs[0].point); si falla, fallback al puntoVenta local con log
- [ ] Una NC sobre Factura A imprime ticket con letra "NC A", CAE propio, QR e ítems
- [ ] La impresión de tickets de control no-AFIP existentes sigue funcionando (sin regresión)
- [ ] ESLint (ventago-app) y tsc (api-ventago) pasan en los archivos tocados

## Ambiguity Report

| Dimension          | Score | Min  | Status | Notes                                                        |
|--------------------|-------|------|--------|--------------------------------------------------------------|
| Goal Clarity       | 0.88  | 0.75 | ✓      | 3 workstreams + método de salida fijado (D1 ESC/POS)         |
| Boundary Clarity   | 0.80  | 0.70 | ✓      | SOAP/C/digital/PDF-térmico explícitamente fuera              |
| Constraint Clarity | 0.78  | 0.65 | ✓      | Plataformas, migraciones 5432/5434, códigos AFIP, no-regresión |
| Acceptance Criteria| 0.78  | 0.70 | ✓      | 12 checks pass/fail                                          |
| **Ambiguity**      | 0.18  | ≤0.20| ✓      | Único punto abierto: endpoint manager en vivo (verificar en plan) |

Status: ✓ = met minimum

## Interview Log

| Round | Perspective | Question summary | Decision locked |
|-------|-------------|------------------|-----------------|
| 0 | Researcher (pre-scout) | ¿Qué existe hoy vs CoolSyncro? | AfipModule con emisión/NC/ND/QR/A4-esqueleto/thermal-socket ya en main; gaps = QR/IVA/ítems en salida, A/M sin persistir, PV local | 
| 1 | Boundary/Decision | D1: ¿método de salida del print-agent? | Extender ESC/POS `fiscal-formatter` (cross-platform, reusa Phase 11); NO adoptar pdf-to-printer (Windows-only) |
| 1 | Boundary/Decision | D2: ¿resolución de PV del gateway? | Adoptar `manager /data/header` → point + coolUser (alineado con "PV lo decide invoice"); verificar endpoint en vivo en plan-phase; fallback a puntoVenta local |
| 1 | Boundary/Decision | D3: ¿cuándo mostrar el selector A/M? | Solo cuando Cond. IVA = RI |
| — | Prioridad | ¿Orden de los 3 workstreams? | W1 (print-agent) primero, luego W2 (A4), luego W3 (A/M) |

---

*Phase: 57-facturaci-n-electr-nica-completar-salida-print-agent-a4-pdf-*
*Spec created: 2026-07-19*
*Next step: /gsd:discuss-phase 57 — decisiones de implementación (cómo construir lo especificado arriba)*
