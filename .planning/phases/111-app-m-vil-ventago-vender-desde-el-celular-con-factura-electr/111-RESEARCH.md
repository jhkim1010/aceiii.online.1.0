# Phase 111: App móvil Ventago — Research

**Researched:** 2026-10-15
**Domain:** NestJS mobile-POS API (terminal registration, real sale + payment, manual AFIP, stock ingreso, reports) + new Flutter app (Android + iOS)
**Confidence:** HIGH on server facts (all read from code, file:line cited); MEDIUM on Flutter/iOS/CI (no iOS signing exists in repo today); LOW only where tagged `[ASSUMED]`

All paths below are relative to `/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/`. Server paths are under `api-ventago/src/app/`. Local DB (PG18 :5432) was queried read-only; prod (:5434) was queried read-only for two facts (marked).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** **App nueva** (no se extiende mobile-sales-app ni tienda-admin-app — decisión del usuario). Se pueden copiar piezas (lector, grilla talle×color, pantallas de reportes), pero es un proyecto aparte.
- **D-02:** **Android + iPhone.** Implica build iOS, App Store y entorno de build en Mac (planificar desde el inicio).
- **D-03:** Cada celular se registra como **una terminal más** dentro de una **caja (box) existente** de la sucursal (jerarquía Store → Branch → Box → Terminal). La venta lleva ese `terminal_id`; el dinero entra en la **sesión de caja ya abierta de ese cajón** — regla «돈은 서랍 단위로만 모인다»: la app **nunca abre una segunda sesión**.
- **D-04:** Registro: **en el primer login, un encargado lo aprueba** desde la web eligiendo sucursal y caja (mismo modelo que el registro de terminal del POS web). Un celular perdido se da de baja desde la web.
- **D-05:** Sin caja abierta no se cobra: el botón se apaga y dice por qué; un encargado puede abrirla (acá o en la PC).
- Hecho verificado: la sesión móvil **ya es independiente** de la del escritorio (`mobile_sessions`, Phase 37 D-06 — el login móvil nunca toca `active_sessions`). Por eso usar el celular no corta el POS de la PC del mismo usuario.
- **D-06:** **Los mismos permisos de la web** (roles + permisos individuales): vender = permiso de venta, ingreso = permiso de stock, reportes = permiso de reportes. Pueden entrar admin y gerente además de vendedor (hoy el login móvil sólo admite vendedor/revendedor — hay que ampliarlo). El servidor rechaza con la misma lista.
- **D-07:** **Mismos medios de pago que el POS web** de esa tienda (efectivo, transferencia, QR MP, tarjeta, cuenta corriente, pago mixto); los medios que la tienda ocultó no aparecen.
- **D-08:** Cobro **auditable**: por medio, importe aplicado / recibido / vuelto / referencia, y la cuenta completa visible; si no cierra, no se confirma. Confirmar se bloquea al tocar (idempotencia — no se cobra dos veces). Si se corta después de confirmar → «Cobro en verificación»: se consulta al servidor por esa clave, no se reenvía.
- **D-09:** **Sin conexión no se cobra ni se factura.** El carrito queda guardado en el celular y no se pierde. (Nada de ventas offline encoladas.)
- **D-10:** La emisión es **siempre un toque manual** (equivalente a F10). Nunca automática — ni al cobrar ni al reconectar.
- **D-11:** «Datos para facturar» separados del cliente comercial: documento, condición IVA del **padrón AFIP** (RG 5616), domicilio del comprador (IIBB) y tipo de comprobante; se validan antes de cobrar.
- **D-12:** Estados visibles: sin emitir / emitiendo / emitida (número + CAE) / rechazada (motivo + corregir + reintentar). Salir sin emitir pide confirmación y deja la venta «sin emitir» con contador visible.
- **D-13:** **Compartir desde el celular**: se genera el PDF (con QR AFIP) y se abre WhatsApp / mail del teléfono; la vendedora elige el contacto. El servidor no envía mensajes. La factura se comparte sólo con CAE; antes, sólo «ticket no fiscal».
- **D-14:** **Sólo con botón**: la terminal del celular puede tener mapeada una comandera de la sucursal (igual que una terminal web, vía print-agent). **Nunca impresión automática** (regla «중복 인쇄는 결단코 금지»).
- **D-15:** Ingreso por escaneo continuo con vibración/sonido, «Deshacer último», edición por fila, nota/proveedor; nada se guarda hasta «Confirmar ingreso». Se registra como movimiento del libro `stocks` (append-only), por `product_branch_id`, en una sola transacción.
- **D-16:** Tres: **resumen del día** (ventas netas, cobrado, facturado, sin emitir, por medio de pago), **caja** (efectivo esperado, ingresos/egresos de la sesión abierta), **stock y más vendidos**. Mismos números que la web (mismos endpoints) y cada número dice qué cuenta.

### Claude's Discretion
- Framework (Flutter, como las demás apps), estructura del proyecto, librerías.
- Reusar en el servidor la ruta de login `/mobile/auth/*` + `mobile_sessions` o ampliarla.
- Endpoints: preferir los mismos que usa el POS web (venta, AFIP, caja, reportes) antes que crear paralelos.
- Diseño visual: tema Ventago (navy #1a1a2e + gold #f5a623), siguiendo el mockup.

### Deferred Ideas (OUT OF SCOPE)
- Devoluciones, anulaciones y notas de crédito desde el celular (CODEX 2ª ronda) — fase propia.
- Ventas offline encoladas.
- Envío del comprobante desde el servidor (WhatsApp Business API / mail automático).
- Impresora bluetooth portátil.
- El resto de los reportes web (`/reports/*`, 15 slugs).
</user_constraints>

<phase_requirements>
## Phase Requirements

No REQ IDs were assigned (phase_req_ids null). CONTEXT decisions D-01..D-16 are the requirements.

| ID | Description | Research Support |
|----|-------------|------------------|
| D-01/D-02 | New Flutter app, Android + iOS | §Flutter: stack, repo layout, CI gap (no signed iOS path exists), env audit |
| D-03/D-05 | Phone = terminal in an existing box; money goes to the box's open session; no 2nd session | §Q2, §Q3: `offlineCash` opt precedent + `getOpenCashRegisterByBox`; web resolves drawer by branch/user — NOT by the phone's terminal |
| D-04 | Manager approves the device on first login, can revoke | §Q2: web has NO approval flow today; new table + guard + web screen |
| D-06 | Same permissions as web; server rejects with same list | §Q1, §Q9: JWT is shared with web; `@FunctionGuard` slugs; ingreso has NO server guard today |
| D-07/D-08 | Web payment methods, auditable cobro, idempotent, "en verificación" | §Q3: `GET /payment-methods`, `Idempotency-Key`; no GET-by-key; no columns for received/vuelto/reference |
| D-10/D-11/D-12 | Manual AFIP, receptor data, states | §Q4: `POST /afip/vouchers`, `preview` (estado), receptor comes from sale's client |
| D-13 | Share PDF | §Q4: `GET /afip/vouchers/:id/pdf?formato=`; non-fiscal ticket PDF does not exist |
| D-14 | Print only by button | §Q5: `POST /sales/:id/reprint`, `POST /afip/vouchers/:id/reprint`; suppress auto paths |
| D-15 | Stock ingreso | §Q6: `ingresarStockPorProductos` is the single ledger writer but cannot write `type NULL` |
| D-16 | Three reports | §Q7: endpoints + gaps (no "sin emitir" aggregate) |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

Treated as locked (same authority as CONTEXT decisions):
- **Caja:** one open session per box; never reopen; app never opens a second session. DB enforces with `uq_cash_registers_abierta_por_box` (verified present local AND prod `[VERIFIED: ssh prod psql 2026-10-15]`).
- **Write path (Phase 64):** one transaction per business action; `stocks` append-only by `product_branch_id`; helpers take `transaction` as required arg; no external I/O inside a tx; after-commit failure never changes response; sale creation supports `Idempotency-Key`; respect `allowSaleWithoutStock`; lock order `productId` ascending; read stock only from `stock_balances`/views, never `products.stock`.
- **AFIP:** emission is manual only (`AUTO_EMISION_PROHIBIDA = true`, `afip/auto-issue.ts:4`). **No duplicate / automatic printing.**
- **Tenant isolation is absolute** (never `store=undefined`); `global_clients` is never touched.
- **Migrations:** local (5432) + prod (5434) together; W4 conventions (additive, nullable, `CREATE INDEX CONCURRENTLY`, `lock_timeout`, `CHECK ... NOT VALID`); new-table owner/sequence → `coolsistema` DO block; `-- perm-cache:` line if touching permission tables; enforced by `src/common/migrations/migration-conventions.spec.ts`.
- **Day-time rule:** no prod push/DDL 08–16 BA time unless ≤10 active users (measure before each push). Push is default after verification; report after.
- **Dates:** DB is UTC; "today" must use the store timezone.
- **Tooling:** use `grep -a` in this repo; jest always `--maxWorkers=1`, never bare `jest`; app eslint treats warnings as errors; spec must not import outside `rootDir`; `@Column` needs explicit `type`; do not use `git add -A`; pre-commit gate runs api tsc + jest on changed module dir.
- **Skills:** `sketch-findings-ace-online` for theme (navy #1a1a2e + gold #f5a623).

## Summary

The server already contains almost every business capability the app needs, but **all of it is reachable only through the web path, which resolves "which drawer / which terminal / which branch" from the *user*, not from a device**. The mobile access token is the *same JWT* the web uses (`mobile-auth.service.ts:303`, signed with the shared secret), and the global guard (`JwtGlobalGuard`) only needs a valid JWT. So a mobile token can technically call `POST /sales`, `POST /afip/vouchers`, etc. today — but that bypasses `x-mobile-session-token`, any device approval/revocation, and the terminal→box binding (D-03). Therefore: **build `/mobile/pos/*` wrapper endpoints behind `JwtGlobalGuard + MobileScopeGuard + a new approved-terminal guard + @FunctionGuard`, that call the existing exported services** (`SalesCreateService`, `AfipVoucherService`, `AfipOutputService`, `CashRegisterService`, `ProductStockService`). All required services are already exported from their modules.

Five facts drive the plan (each is verified in code, see Q-sections): (1) the web decides the drawer by `branchId`→ latest open register in the *branch*, falling back to the *user* — wrong for a phone bound to one box; but `CreateSaleOpts.offlineCash {boxId, terminalId}` already exists and does exactly "this box's open session + this terminal_id", so the wrapper reuses it (and must pre-check box open itself, because card-only sales never touch the register). (2) `Idempotency-Key` works (replay returns the stored response) but there is **no query-by-key endpoint**, and `sale_payment_methods` has **no columns for received/vuelto/reference** (D-08). (3) AFIP receptor data is read **from the sale's client record** at emission time — there is no per-emission override, so "Datos para facturar" must persist to the client before emitting; and there is **no durable "wanted an invoice but not emitted yet" marker** (`sales.afip_status` is `no`/`facturado` only in practice; "sin emitir" counter needs new state). (4) Stock ingreso on the web is `type IS NULL` rows, but the only safe ledger writer (`ProductStockService.ingresarStockPorProductos`) defaults to `type='production'` and cannot express NULL; web ingreso routes (`PUT /products/:id/correct-today`) are bare `@Auth()` with **no function guard**, so "server rejects with the same list" has no list for ingreso yet. (5) Terminal registration on the web has **no approval** (any logged-in user self-registers via `POST /session/register-terminal`) and it also creates an `active_sessions` row — so D-04 is a net-new feature, not a reuse.

**Primary recommendation:** Add a new `mobile_devices` table (pending/approved/revoked, bound to a `terminals` row) + `MobileTerminalGuard`; add `api-ventago/src/app/mobile/pos/` wrappers (caja status, payment methods, create sale with `offlineCash`+`suppressAutoPrint`, sale-by-key, AFIP preview/emit/pdf, print-by-button, ingreso, reports) that delegate to existing services; add a Flutter app in a **new repo/submodule** (copy scanner/matrix/dio pieces from `mobile-sales-app`), with iOS built on a Mac runner. Ship server first (additive only), app second.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Device registration/approval/revocation | API / Backend | Web admin UI (manager) | Revocation must be enforced server-side on every request; web only edits state |
| Auth + permission enforcement | API / Backend | — | `FunctionPermissionService.isAllowed` is single source; app flags are not a boundary (memory: frontend-flag-is-not-a-security-boundary) |
| Which drawer/terminal/branch a sale uses | API / Backend | — | Derived from the approved device row, never from request body |
| Cart, scanner, matrix, tap targets | Mobile client | — | Pure UI; cart persisted locally (D-09) |
| Money math (applied/received/change) | Mobile client (display) | API (authoritative total check) | Server re-checks `sum(applied) == total` (`determineSaleStatus`, `sales-create.service.ts:3019`) |
| Idempotency | Mobile client generates + persists key | API enforces + exposes lookup | Key must survive app kill before request is sent |
| AFIP emission & state machine | API / Backend (existing) | Mobile (button + state display) | `afip_status` atomic claim lives in `afip-voucher.service.ts:~700` |
| Invoice PDF rendering | API / Backend (existing `generateA4Pdf`/`generateTicketPdf`) | Mobile (download + share sheet) | QR/CAE rendering is server code |
| Non-fiscal ticket PDF | API / Backend (NEW) | — | No renderer exists; must not be hand-built on the phone |
| Sharing to WhatsApp/mail | Mobile client | — | D-13: OS share sheet; server sends nothing |
| Thermal print | API → print-agent (existing socket) | — | `sale.terminal_id → terminals.thermal_agent_id` |
| Stock ingreso write | API / Backend | — | Single transaction, ledger by `product_branch_id` |
| Reports | API (existing endpoints + 1–2 small aggregates) | Mobile (render) | Same numbers as web |

## Standard Stack

### Core (server) — everything already in the repo
| Library | Version | Purpose | Why |
|---------|---------|---------|-----|
| NestJS 11 + sequelize-typescript | repo | wrappers/guards/models | project standard (CLAUDE.md) |
| `pdfkit` ^0.14.0, `qrcode` ^1.5.4 | repo `api-ventago/package.json:64,66` | PDF for non-fiscal ticket | already used by `afip/pdf/ticket-generator.ts` |

### Core (Flutter) — copy from `mobile-sales-app/pubspec.yaml`
| Library | Version in repo → latest on pub.dev | Purpose | Note |
|---------|-----------------------------------|---------|------|
| Flutter / Dart | installed 3.44.8 / 3.12.2 `[VERIFIED: flutter --version]`; apps use `sdk: ^3.11.0` | — | |
| flutter_riverpod (+hooks_riverpod) | ^3.3.1 → 3.4.3 `[VERIFIED: pub.dev API]` | state mgmt | `mobile-sales-app` + `talleres-vendor-app` use v3; admin apps use v2 → **use v3 (newest apps)** |
| go_router | ^17.2.0 → 18.1.0 | navigation | as mobile-sales-app |
| dio | ^5.9.2 → 5.11.1 | HTTP | copy `core/network/dio_client.dart` (injects JWT + `x-mobile-session-token`, handles 401 codes) |
| flutter_secure_storage | ^10.0.0 → 11.2.0 | token + device salt | |
| mobile_scanner | ^7.2.0 → 7.4.2 | barcode/QR scan | already proven in `lector_screen.dart` (415 lines) |
| connectivity_plus | ^6.1.0 → 7.3.2 | online indicator (D-09) | |
| intl | ^0.20.2 | es-AR money/dates | |
| crypto | ^3.0.7 | device fingerprint SHA-256 | copy `core/device/device_fingerprint.dart` |

### Supporting (new to this app)
| Library | Version | Purpose | When |
|---------|---------|---------|------|
| share_plus | 13.3.1 (2026-10-01), publisher fluttercommunity.dev `[VERIFIED: pub.dev API + pub.dev/packages/share_plus]` | Share PDF file to WhatsApp/mail (D-13). API: `SharePlus.instance.share(ShareParams(text:, files:[XFile(path)]))`; on iPad pass `sharePositionOrigin` | invoice/ticket send screen |
| path_provider | 2.1.6, publisher flutter.dev `[VERIFIED: pub.dev API]` | temp file for downloaded PDF bytes | before share |
| shared_preferences | 2.5.6, flutter.dev | persist cart draft + pending Idempotency-Key (D-09/D-08) | cart, cobro |
| uuid | 4.6.0, publisher yuli.dev `[VERIFIED: pub.dev API]` | v4 Idempotency-Key | per checkout attempt |
| package_info_plus | 10.2.2, fluttercommunity.dev | app version → update check | optional |

Haptics/sound for ingreso scan (D-15) need no package: `HapticFeedback.mediumImpact()` and `SystemSound.play(SystemSoundType.click)` are in `flutter/services.dart` `[ASSUMED — standard Flutter SDK API, not re-verified this session]`; "different sound on repeat within 2s" can reuse `Antirebote` logic from `mobile-sales-app/lib/features/scanner/logic/lector_logic.dart`.

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Share PDF file via share sheet (D-13, locked) | `wa.me/<number>?text=<public pdf link>` using `PdfTokenService.publicPdfUrl` (server already signs public links: `afip/pdf-token/pdf-token.service.ts`, used by `whatsapp/services/click-to-chat.service.ts:388`) | The mockup ⑦ shows "WhatsApp +54 11…" prefilled; a *file* cannot be attached to a prefilled `wa.me` number `[ASSUMED]`, only a link can. Share sheet = file but user picks contact. Raise to the user (Open Question 6) |
| Extend `mobile-sales-app` | — | Locked: new app (D-01) |

**Installation (Flutter):**
```bash
flutter create --org com.ventago --platforms=android,ios <app_name>
flutter pub add flutter_riverpod hooks_riverpod go_router dio flutter_secure_storage mobile_scanner connectivity_plus intl crypto share_plus path_provider shared_preferences uuid
```

## Package Legitimacy Audit

`slopcheck` is a pip/npm checker and does not cover pub.dev. Server side adds **no new packages**. Dart packages were checked against the pub.dev API (publisher, version, date) instead.

| Package | Registry | Version/Date | Publisher / usage | Source | slopcheck | Disposition |
|---------|----------|--------------|-------------------|--------|-----------|-------------|
| share_plus | pub.dev | 13.3.1 / 2026-10-01 | fluttercommunity.dev; 4,031 likes; ~4.58M dl/30d | github.com/fluttercommunity/plus_plugins | n/a (pub) | Approved |
| path_provider | pub.dev | 2.1.6 / 2026-06-15 | flutter.dev | flutter/packages | n/a | Approved |
| shared_preferences | pub.dev | 2.5.6 / 2026-10-05 | flutter.dev | flutter/packages | n/a | Approved |
| uuid | pub.dev | 4.6.0 / 2026-07-15 | yuli.dev | github.com/Daegalus/dart-uuid | n/a | Approved (alt: `Random.secure()` hex, no dep) |
| flutter_riverpod, go_router, dio, flutter_secure_storage, mobile_scanner, connectivity_plus, intl, crypto | pub.dev | already pinned in `mobile-sales-app/pubspec.yaml` | in production use | — | n/a | Approved (already in repo) |

**Packages removed:** none. **Packages flagged [SUS]:** none. Planner: no `checkpoint:human-verify` required for installs, but pin versions in `pubspec.yaml` and commit `pubspec.lock`.

## Architecture Patterns

### System Architecture Diagram

```
 Phone (Flutter)                                   API (NestJS, /api)                                  Existing services / DB
 ───────────────                                   ──────────────────                                  ──────────────────────
 login(usuario,pass,fingerprint) ─▶ POST /mobile/auth/login (public)
        ◀─ accessToken(JWT 6h) + mobileSessionToken + deviceStatus {pending|approved|revoked, terminal?}
        │
        │ pending ─▶ screen "esperando aprobación"  ◀── Manager (web UI) approves: picks Branch+Box → creates terminals row
        │                                                 POST /mobile/devices/:id/approve (editar-terminal)  → mobile_devices.status=approved
        ▼ approved
 every call: Authorization: Bearer JWT + x-mobile-session-token
        │
        ├─ GET  /mobile/pos/context ─▶ [JwtGlobalGuard → MobileScopeGuard → MobileTerminalGuard(approved, not revoked, terminal live)]
        │        ◀─ terminal, box, branch, caja{open?, sessionId}, paymentMethods, allowSaleWithoutStock, perms{venta,ingreso,reportes}
        │                                     └─▶ CashRegisterService.getOpenCashRegisterByBox(box)   (NOT user-based)
        │                                     └─▶ PaymentMethodsService.findAll(store)  (hidden filtered)
        │
        ├─ catalog/scan/stock (existing /mobile/*, + variantId)   ─▶ products, stock (stock_balances)
        │
        ├─ POST /mobile/pos/sales  (Idempotency-Key)  ─▶ pre-check box open ─▶ SalesCreateService.create(dto, {
        │        idempotencyKey, suppressAutoPrint:true, offlineCash:{boxId,terminalId} })   — ONE tx: sale+items+stocks+payments+idem claim
        │        ◀─ sale {id,dailyNumber,...}                       after-commit: ledger hook; NO print (printTicket omitted)
        ├─ GET  /mobile/pos/sales/by-key/:key ─▶ sale_idempotency_keys (store-scoped, read-only)  → "cobro en verificación"
        │
        ├─ GET  /mobile/pos/sales/:id/fiscal ─▶ AfipVoucherService.previewPartial(…) (estado: emitidos/enProgreso/verificar)
        ├─ POST /mobile/pos/sales/:id/invoice ─▶ AfipVoucherService.issueForSale(…)  (atomic afip_status claim; output='pdf' semantics, NO thermal)
        ├─ GET  /mobile/pos/vouchers/:id/pdf?formato=a4|80 ─▶ AfipOutputService.dispatch(output:'pdf')  → bytes → share_plus
        ├─ GET  /mobile/pos/sales/:id/ticket.pdf  (NEW pdfkit, "NO VÁLIDO COMO FACTURA") → share_plus
        ├─ POST /mobile/pos/sales/:id/print ─▶ SalesCreateService.reprintSale(saleId)  → sale.terminal_id → thermal_agent_id → print-agent socket
        │
        ├─ POST /mobile/pos/stock/ingreso ─▶ ProductStockService.ingresarStockPorProductos(tx)  (single tx, type NULL — needs change)
        └─ GET  /mobile/pos/reports/{day,caja,stock} ─▶ SalesService.getDailySummary / CashRegisterService.getCashRegisterWithOperationsById / reports
```

### Recommended Project Structure
```
api-ventago/src/app/mobile/
├── devices/            # NEW: mobile-device.model.ts, mobile-devices.service.ts, controller (approve/revoke/list), spec
├── guards/             # existing MobileScopeGuard + NEW mobile-terminal.guard.ts (+ spec)
├── pos/                # NEW module: pos.controller.ts, pos-sales.service.ts, pos-fiscal.service.ts, pos-stock.service.ts,
│                       #             pos-reports.service.ts, ticket-pdf.ts  (+ specs next to each)
└── ...existing auth/catalog/sales(+suspended)/stock
api-ventago/migrations/2026-10-1x-mobile-devices.sql   # + sales_payment audit columns if approved (Open Q3)
ventago-app/src/views/branches/…  or configuracion       # web: "Dispositivos móviles" approval screen
<new-flutter-repo>/lib/{core,features/{auth,device,pos(cart,payment,fiscal,share),stock_in,reports}}
```

### Pattern 1: Wrapper over existing service (the Phase 111 default)
**What:** New `/mobile/pos/*` controller class guarded by `@UseGuards(AuthGuard('jwt'), MobileScopeGuard, MobileTerminalGuard)` + per-route `@FunctionGuard(slug, action)`; derives `storeId` from `req.user`, `terminal/box/branch` from the approved device row; never trusts body for those.
**Example (precedent in repo):** `mobile/sales/mobile-sales.controller.ts:47` (`@UseGuards(AuthGuard('jwt'), MobileScopeGuard, RequireAttendanceGuard)` + `@FunctionGuard('crear-venta','create')` at line 46) and `buildScope()` — copy this shape.

### Pattern 2: Drawer + terminal override via `offlineCash`
**What:** `CreateSaleOpts.offlineCash` (`sales/sales-create.service.ts:262`) → `prep.resolvedTerminalId` overridden (`:381-383`) and every cash write (`registerCashOperation :3473`, `registrarReintegroEfectivo :3404`) goes through `resolveOfflineCashRegister :3315` → `getOpenCashRegisterByBox(boxId, {transaction, lock:true})`. This gives D-03 exactly: **that box's** open session, `sales.terminal_id = phone terminal`, no user/branch fallback, and it **locks** the register row (guards the auto-close race).
**Caveats:** (a) it only fires on cash paths — a card/transfer-only sale never resolves a register, so D-05 ("no caja, no cobro") needs an explicit **pre-check** in the wrapper (best-effort; race with auto-close is tolerable only because non-cash money doesn't land in the drawer); (b) the thrown `OfflineCashBoxClosedError` message says "venta offline" — map it to a mobile 409 `CAJA_CERRADA` in the wrapper rather than surfacing it; (c) rename/generalize the type (`CashTarget`) only if the planner wants; behavior must not change for offline sync (`offline-sync/offline-push.service.ts:316`).

### Pattern 3: Idempotency lifecycle (server contract already exists)
Client creates `uuid` **before** sending and persists it with the cart draft (so an app kill after tap is recoverable). `claim()` outcomes (`sale-idempotency.service.ts`): `proceed` / `replay` (returns stored response; re-POST of the identical body is safe) / `in_flight` → 409 "Solicitud de venta en curso" / `conflict` → 422 (same key, different body; body hash = `createSaleDto` after controller adds `storeId/userId`). **The wrapper must not inject time-varying fields** (e.g. `saleDate: new Date()`) into the DTO, or a retry hashes differently → 422.

### Anti-Patterns to Avoid
- **Letting the app call `POST /sales` directly with its JWT.** Works today but bypasses device approval/revocation and terminal binding; the sale would resolve its drawer by user/branch (`resolveOpenCashRegister :3278`) — wrong box when a branch has several (branch 6 has 4 per code comment).
- **Using `branchId` from the request body.** `prepareCreate` only checks the branch belongs to the store (`sales-create.service.ts:~883-905`), not that the user may sell there.
- **Reusing `setBranchScope` / `POST /mobile/auth/branch-scope`.** It lets any logged-in user self-select any store branch and **writes `user_branches` and `users.branch_id`** (`mobile-auth.service.ts:556-592`), which changes web behavior for that user (e.g. devolución branch check in `sales.controller.ts:~158`). In the new app the branch comes from the approved terminal only.
- **Calling `POST /session/register-terminal` or `move-terminal` from mobile.** They create `terminal_devices` + replace `active_sessions` (`session.service.ts:606-695`) → kills the PC session (violates the verified Phase 37 D-06 fact).
- **`POST /afip/vouchers` with `output:'thermal'` and `branchId`** — triggers an automatic thermal print after issue (`afip.controller.ts:~1296-1312`). Mobile must pass `output:'pdf'` (or omit `branchId`) and print only via an explicit button.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Sale+payment+stock+drawer in one tx | new sale writer | `SalesCreateService.create(dto, opts)` (exported by `SalesModule`) | 4,520-line service holds numbering (`uq_sales_branch_daylocal_dn`), stock guards, ledger, idempotency |
| Which drawer | user/branch lookup | `offlineCash` opt + `getOpenCashRegisterByBox` | the user-based `getOpenCashRegister` is the known inconsistency |
| AFIP emission + double-CAE protection | own state machine | `AfipVoucherService.issueForSale` (atomic `afip_status` claim, stale reclaim, AFIP re-check, `verificar`) | `afip-voucher.service.ts:~700-760` |
| Invoice PDF with QR | client-side PDF | `GET /afip/vouchers/:id/pdf` logic (`AfipOutputService.dispatch output:'pdf'`, `generateA4Pdf`/`generateTicketPdf`, formats a4/80/58) | QR/CAE correctness |
| Public invoice link | own tokens | `PdfTokenService.sign/publicPdfUrl` | already used by WhatsApp click-to-chat |
| Payment-method visibility | own list | `GET /payment-methods` (store rows + global rows, hidden/inactive filtered; `payment-methods.service.ts`, `store-payment-method-hidden.model.ts`) | D-07 |
| Stock ledger write | `Stocks.create` | `ProductStockService.ingresarStockPorProductos` (sorted by productId, `asegurarProductBranch`, `hojaEnSucursal` for "sin color y talle" branches) | memory: ledger writes hide behind injected models |
| Barcode scanning / debounce | custom | `mobile_scanner` + copy `Antirebote`, `lector_logic.dart` | tested (`test/lector_test.dart`) |
| Padrón AFIP lookup/complete client | direct AFIP | `POST /afip/padron/completar` (writes only empty fields of the store's `clients` row; uses the store's cert) | `afip.controller.ts:226` |

**Key insight:** every "new" backend behavior in this phase is a thin, guarded adapter. New *business logic* appears in exactly six places: device approval, box-open pre-check, payment-audit persistence, sale-by-key lookup, "sin emitir" intent, non-fiscal ticket PDF, and ingreso `type NULL`.

## Runtime State Inventory

Not a rename/refactor phase — omitted (greenfield app + additive server work). One note: the new device table starts empty in prod, and the existing `mobile_sessions` has **28 rows in prod** `[VERIFIED: prod psql read-only 2026-10-15]` belonging to the old vendedor app; they must keep working (old app unaffected → keep `/mobile/*` existing routes unchanged, add new ones).

## Answers to the 10 research questions

### Q1. Mobile auth, roles, guard chain, can mobile call web endpoints?
- **Login:** `POST /mobile/auth/login` (`mobile-auth.controller.ts`, `@Public`) → `loginMobile` (`mobile-auth.service.ts`). It verifies password with bcrypt (users.password), store/user status, then **does not actually restrict roles** — the only role gate is "revendedor without vendedor → 401 RESELLER_SCOPE_NOT_DEFINED" (`:232-241`). So admin/gerente *can already log in*; what is vendedor-only is the **scope model**: `scopeMode` is hard-coded `'vendedor'` (`:288`), response type says `role: 'vendedor'|'revendedor'` (`:74`), scope branches come from `user_branches` / self-selection (`:243-285`). CONTEXT's "hoy sólo vendedor/revendedor" is therefore about typing/scope, not a role check — extending = add device state + return real role slugs/permissions, not "unblock admin".
- **Tokens:** `accessToken = jwtService.sign(payload, {expiresIn: 6h})` (`:303`) with the **same payload shape/secret as the web** (`id,name,email,roles,storeId`). `mobileSessionToken` (UUID) is stored in `mobile_sessions` (`user_id, device_fingerprint` UNIQUE, `active_session_token` UNIQUE, `scope_branch_ids[]`).
- **How `req.user` is set:** `JwtGlobalGuard` (APP_GUARD, `app.module.ts:371`) runs `AuthGuard('jwt')` → `JwtStrategy.validate` loads the DB user by `id` (30 s cache) → `TenantContext.resolve({storeId,…})`. `MobileScopeGuard` (`guards/mobile-scope.guard.ts`) additionally reads `x-mobile-session-token`, 401 `MOBILE_SESSION_EXPIRED` if unknown, checks store not suspended (60 s cache), rejects `?branchId` outside session scope (403 `SCOPE_VIOLATION`), heartbeats, sets `req.scope`.
- **Permission guards:** `@FunctionGuard(slug, action)` = `AuthGuard('jwt') + FunctionPermissionGuard` → `FunctionPermissionService.isAllowed` (60 s per-worker cache `PERM_CACHE_TTL_MS`, `function-permission.service.ts:~20`). `@Auth(roles…)` = role check only. **They apply to mobile-session requests exactly like web** — they only look at `req.user`. Evidence: `mobile-sales.controller.ts:46` uses `@FunctionGuard('crear-venta','create')`.
- **Can a mobile token call web endpoints?** **Yes.** `SessionGuard` (`x-session-token`/`active_sessions`) is applied to only 3 controllers (attendance QR, shared-folders ×2) `[VERIFIED: grep]`; `/sales`, `/afip/*`, `/cash-register/*`, `/stocks/*`, `/products/*`, `/reports/*` need only a JWT. Consequence: **wrappers are required** for D-03/D-04/D-06 enforcement (device revocation, terminal binding, mandatory pre-checks); the web endpoints stay open to a stolen JWT regardless, which is the existing posture (6 h expiry, no refresh flow — memory `no-user-refresh-token-flow`).
- **Attendance gate:** `RequireAttendanceGuard` returns 403 `NOT_CLOCKED_IN` when `req.scope.mode === 'vendedor'` and no open attendance (`attendance/guards/require-attendance.guard.ts`). Since login sets `scopeMode='vendedor'` for **everyone**, an admin on the new app would be blocked unless clocked in. **Decision needed** (Open Q5): keep for role `vendedor` only; exempt admin/gerente.
- **Extension plan:** keep `/mobile/auth/login` and add `deviceStatus` (+ role slugs, permission snapshot) to its response; do not branch-self-select; return `requireDeviceApproval:true` analogous to the web's `requireTerminalRegistration` (CLAUDE.md "세션 & 터미널 보안").

### Q2. Terminal registration today vs. what D-04 needs
- **Web today:** `POST /session/register-terminal` (`session.controller.ts:98-118`, `@Auth()` any role) → `registerTerminalAndCreateSession` (`session.service.ts:606-695`): validates `boxId` belongs to store, **creates `terminals` row immediately**, creates `terminal_devices` (`device_fingerprint, device_token, public_ip, terminal_id, branch_id, store_id`; no status column — `db-schema-tables.md:4139`), and **replaces `active_sessions`**. No approval, no revoke state. IP→branch (`branch_ip_registries`) and fingerprint→terminal checks run at *web* login only.
- **`terminals` columns:** `id,name,box_id,status('activo'),is_deleted,store_id,thermal_agent_id,zebra_agent_id,…` — no "kind". Terminal CRUD guards exist: `crear-terminal` / `editar-terminal` / `eliminar-terminal` (`terminal/terminal.controller.ts:37,49,72`).
- **Recommendation (new table, not reuse):** `mobile_devices(id, store_id, device_fingerprint, label, requested_by_user_id, status CHECK in ('pending','approved','revoked'), terminal_id NULL→FK terminals, branch_id NULL, approved_by, approved_at, revoked_by, revoked_at, last_seen_at, created/updated)` with partial UNIQUE `(store_id, device_fingerprint) WHERE status <> 'revoked'`. Reasons not to reuse `terminal_devices`: it has no status; the web login path enumerates it by fingerprint (a phone row there could be matched by web flows); web registration semantics are "instant". Precedent for a device table + admin UI: `vendedor_devices` (`migrations/vendedor-devices.sql`; managed in Ventas settings › Vendedores › Dispositivos) — a *different* auth path (x-device-key) that does not need to be touched.
- **Approval flow:** first login of an unknown fingerprint → insert `pending` (idempotent on unique) → app shows "esperando aprobación" and polls `GET /mobile/pos/context`. Manager (web screen) calls `POST /mobile/devices/:id/approve {boxId}`: transaction = validate `Box` in store (+ its branch in store, as `session.service.ts:626-657` does) → create `terminals` row (`status:'activo'`, name e.g. `Móvil – <label>`) → set device `approved` + `terminal_id`. Revoke = set `revoked` and soft-delete/disable the terminal (`terminals.is_deleted`) — **never delete** it (sales reference `terminal_id`).
- **Guard:** `MobileTerminalGuard` after `MobileScopeGuard`: resolves device by session fingerprint → must be `approved`, terminal live, box live; cache 30–60 s via `MemoryCacheService` with `storeKey(...)` (pattern at `mobile-scope.guard.ts`), so revocation latency ≤ cache TTL — state it in UAT.
- **Permission for approve/revoke:** reuse `@FunctionGuard('editar-terminal','update')` — avoids seeding a new `functions` row (seeding touches permission tables → needs `-- perm-cache:` note, and CLAUDE/memory say sidebar derives from structure: "seed first").
- **Web UI location:** `ventago-app/src/views/branches/` (BranchList) and `pages/sucursales/[id]/…` already host terminals/printers (`views/impresoras/ImpresorasView.tsx`); a "Dispositivos móviles" tab there + `next/dynamic` code split per CLAUDE perf rules. Printer mapping for the phone terminal is the existing `terminals.thermal_agent_id` editor (`PUT /terminal/:id`).
- **Side effects to check:** terminals created for phones will appear in web pickers (`GET /terminal/by-branch/:id`, `move-terminal`). Either mark them (Open Q: add `terminals.kind` nullable, or name convention) or accept. `[ASSUMED]` nothing else enumerates terminals as physical POS machines.

### Q3. Sale creation with payment (web path) and how the phone maps to a drawer
- **Endpoint:** `POST /sales` (`sales.controller.ts:111-134`) `@FunctionGuard('crear-venta','create')`; header `Idempotency-Key` optional; controller overwrites `storeId`/`userId` from `req.user`; calls `SalesCreateService.create(dto, {idempotencyKey})`.
- **DTO** (`sales/dto/create-sales.dto.ts`): `clientId`(required number; web sends `5` for Consumidor Final and the server remaps to the store's own CF, `sales-create.service.ts:~690-720`), `storeClientId?`, `branchId?`, `sellerId?`, `provinceId?`, `status` (`SaleStatus`), `items[{productId, quantity, price?, total?, priceTypeId?, …}]`, `paymentMethods[{paymentMethodId, amount, optionId?, slug?, dueDate?, cheque?}]`, `discounts[]`, `recharges[]`, `subtotal,totalAmount,discountAmount,transport`, `printTicket?`, `printerAgentId?`. Web builds it at `ventago-app/src/views/homes/components/ProductList/ProductList.tsx:2486-2546`.
- **Items must be leaf/child variant ids.** The existing mobile catalog/stock return the *madre* id plus `variantQuantities` (used by suspended sales). `GET /mobile/stock/:productId` returns `{color,size,stock,stockByBranch}` **without the child `productId`** even though the query has it (`mobile-stock.service.ts:~99-119`). **Add `variantId` to `VariantStock` (additive).** `/mobile/scan/:code` already returns `variantId` (`mobile-catalog.service.ts:46-59`). Stock reads in that service sum the ledger (`aggregateStock`), contradicting the "read `stock_balances` only" rule — switch the new context/matrix reads to `stock_balances` (columns incl. `product_branch_id, branch_id, product_id, parent_id`, `available` — see `db-schema-tables.md:3168`).
- **Payment methods:** `GET /payment-methods` (roles admin/superadmin/vendedor/gerente/envioManager) returns store rows + global rows, with store-hidden (`store_payment_method_hidden`) and inactive filtered; web hook `usePaymentMethods`. Slugs seen: `efectivo`, `credito`, `banco…`, `mercadopago`, `tarjeta…`; web's quick-pay helper treats `credito` and `^banco([-_].*)?$` specially (`views/homes/utils/pago-rapido.ts`). Mixed payment = several `paymentMethods` rows whose amounts sum to the total (`determineSaleStatus :3019` compares in centavos → `PAID` else `PENDING_PAYMENT`). Cuenta corriente needs `storeClientId` (+ credit status); favor is a negative crédito applied automatically (memory `favor-is-negative-credito`); senia exists. Cash change: **the web sends the *applied* amount** (`amount: p.amount`); received/vuelto are screen-only.
- **D-08 gap:** `sale_payment_methods` has only `id, sale_id, payment_method_id, option_id, amount` (`db-schema-tables.md:2929`). "Recibido / vuelto / referencia / verificada" have nowhere to live. Options (Open Q3): (a) expand: nullable `received_amount double precision`, `change_amount`, `reference varchar(120)`, `reference_verified boolean` on `sale_payment_methods` (additive, W4-safe; new DTO fields on the mobile wrapper only, written in the same tx), or (b) append a structured line to `sales.notes`. Recommend (a).
- **Drawer resolution on the web (the problem):** `prepareCreate` resolves `resolvedTerminalId` via `resolveOpenCashRegister(userId, dtoBranchId)` (`:824-842`, impl `:3278-3304`) → branch-scoped `getOpenCashRegister` (`cashRegister.service.ts:2069-2108`: `where closingTime null`, box where `branchId`, **`order id DESC`** → "the latest open register in the branch") else *user*-scoped fallback. CLAUDE.md flags the user-based remainder (`getOpenCashRegister(userId)`, `status().openedToday(userId)`; `GET /cash-register/status` is `userId`-based at `cashRegister.controller.ts:102-124`). A phone bound to box B2 in a 4-box branch would therefore land in whichever box opened last → **must** use `offlineCash` (Pattern 2).
- **Mobile caja status:** new `GET /mobile/pos/context` returns `getOpenCashRegisterByBox(terminal.boxId)` (`cashRegister.service.ts:2119-2138`, exported) and, if open, totals from `getCashRegisterWithOperationsById` (`:1513-1553`: `{venta, ingreso, gasto, retiro, saldoFinal}` via `computeSaldoFinal`) — user-agnostic.
- **Open caja (D-05):** `POST /cash-register/open` (`cashRegister.controller.ts:344`, roles incl. vendedor; DTO needs `boxId, terminalId, userId`; `createCashRegister :179` returns the existing open session instead of creating a 2nd, DB unique index as backstop). Wrapper: `POST /mobile/pos/caja/open` gated by a function guard from the web's caja-open path; pass the phone's `boxId/terminalId`. `[ASSUMED]` which function slug the web uses for the open button (only `@Auth` roles seen) — planner must pick: recommend role check `admin|gerente` as D-05 says "un encargado".
- **Query by key (D-08 "en verificación"):** no endpoint exists (`grep` of controllers: only `sales`, `restaurant-delivery`, `reports` mention idempotency, all as header consumers). Table `sale_idempotency_keys(store_id, idempotency_key, request_hash, status processing|completed|failed, sale_id, response_body jsonb, expires_at 24 h)`. Add `GET /mobile/pos/sales/by-key/:key` → `{status, saleId?, sale?}` scoped by `req.user.storeId` (and ideally the terminal). Note: re-POST of the identical body also returns the replay, but `in_flight` gives 409, so a read-only lookup gives a clean state machine. Keys expire at 24 h; after expiry a re-POST would create a *new* sale — the app must clear the pending key when the lookup says `completed`/`not found`.
- **Pitfalls specific to mobile create:** don't send `printTicket`/`printerAgentId` (see Q5); set `suppressAutoPrint:true` anyway; don't add `saleDate`; `sellerId` defaults to the user's linked Seller if omitted (`prepareCreate :~725-750`); validate `totalAmount` is recomputed server-side? **No** — server trusts `totalAmount/subtotal` from the DTO and prices from `items[].price` (only `isReturn` lines are re-priced, `precio-actual.ts`); the wrapper should recompute total from items+discounts and reject mismatch (the cart screen mockup ③ warns on price change — needs a server price-check endpoint or re-fetch of catalog at checkout). Memory: POS sells at **madre** price except "costo por variación" (`pos-prices-from-madre-unless-costo-por-variacion`) — reuse catalog's `price` as the existing mobile app does.

### Q4. AFIP manual emission, receptor, states, PDF
- **Emit (F10 equivalent):** `POST /afip/vouchers` (`afip.controller.ts:1275`, roles admin/superadmin/gerente/vendedor, **no `@FunctionGuard`**): body `{saleId, issuerId?, puntoVenta?, invoicePct (0.01–100), provinceId?, output:'thermal'|'pdf'|'digital', branchId?, terminalId?}` (`dto/issue-voucher.dto.ts`) → `AfipVoucherService.issueForSale` (`:199`). Flow: load sale+receptor → resolve issuer by `sales.branch_id` (not the seller's branch) → autoProd gate → shared-cert-folder gate → `resolveJurisdiccion` (provinceId param → `sales.province_id` → client card province; **no branch fallback**, error "Preguntá al comprador de qué provincia es…" :~395-408) → `issue()` (`:630`): `decideComprobante(issuer.ivaCondition, {docNro, resiva})` (RI→A/B, Monotributo→C), `condIvaReceptorFor` (RG 5616), atomic `UPDATE sales SET afip_status='en_progreso' WHERE afip_status NOT IN ('en_progreso','verificar')` (3b), stale reclaim after 10 min with AFIP re-check (3c), provider call, `ambiguous` → `verificar` (never re-issue), failure → `afip_status='error'` + `afip_error`, success → voucher row + `afip_status='facturado'` + QR.
- **Receptor source (D-11 problem):** `resolveReceptor` (`:616`) reads `sale.storeClient.globalClient.{document,resIva}` else legacy `sale.client.{document,resIva}`. **There is no per-emission override.** "Datos para facturar" must therefore be saved to the sale's client record *before* `POST /afip/vouchers`. The web helper for this is `POST /afip/padron/completar {cuit, clientId}` (`:226`): checks the store's own `clients` row (`id,fullname,address,location,province_id,province_text,res_iva`), only consults AFIP if fields are empty, **writes only empty fields**, never `global_clients` (`padron-cliente.service.ts:130-210`). For Consumidor Final the receptor is `{docNro:''}` and `decideDocumentType` applies; the AFIP cap for CF without DNI is in `decideComprobante`/`decideDocumentType` (planner: read `afip/code-maps.ts`, `afip/condicion-iva-arca.ts` before fixing UI copy "tope de AFIP" — **not verified here**).
- **Sale province:** `sales.province_id` is a snapshot set at sale creation (`dto.provinceId` or client's) and wins over the client card at emission (`:~400`). Mobile must send `provinceId` in the sale if the buyer was asked (IIBB = buyer address, memory `iibb-jurisdiction-is-buyer-address`).
- **States/estado endpoint:** `GET /afip/vouchers/:saleId/preview?pct=100` (`:1625`) returns `{ok, lines, impTotal, tipo, issuedPct, emitidos[{id,tipo,puntoVenta,numero,cae,pct}], enProgreso, verificar}` — `estadoFacturacion` (`afip-voucher.service.ts:550-585`) was built so a modal that lost the response doesn't re-enable "Emitir" (2026-10-13 Cielo incident). **This is the "consulta, no reenvía" call for D-12.** `GET /afip/issue/opciones?saleId=` (`:785`) lists selectable issuers (CUIT/PV). Failed list: `GET /afip/pendientes` returns only `afip_status='error'` (`afip-query.service.ts:193`, limit 50). Stuck: `verificar` resolved only by gerente+ (`POST /afip/vouchers/:saleId/resolver`, `diagnostico`) — mobile shows "contactar encargado", never retries.
- **"Sin emitir" has no server representation.** `sales.afip_status` is `'no'` for 1,048,879 local rows and `'facturado'` for 16 (local `[VERIFIED: psql]`); `'no'` also means "customer never wanted an invoice". D-12's counter ("2 facturas sin emitir de hoy") needs a durable marker: recommend additive nullable `sales.invoice_pending_at timestamptz` (or `invoice_requested boolean`) set by the mobile wrapper when the seller chose a fiscal comprobante type at checkout / left the emit screen; counter = `invoice_pending_at IS NOT NULL AND afip_status NOT IN ('facturado')` for today's store-timezone window and the branch. Alternative (client-only list) is lost on reinstall/other device and was rejected by D-12's "contador visible". Needs the user's OK (Open Q4).
- **PDF:** `GET /afip/vouchers/:id/pdf?formato=a4|80|58` (`:1684`, roles incl. vendedor; `@AgentScope`) → `AfipOutputService.dispatch({output:'pdf', branchId:0})` → bytes (`application/pdf`). It does **not** print. `parsePdfFormato` defaults to A4. Voucher id comes from `preview.emitidos[].id` or the `issue` response `voucherId`. Share only when `cae` exists (D-13). QR URL via `buildQrUrl` (`afip/qr-builder.ts`) is embedded by the generators.
- **Non-fiscal ticket PDF:** **does not exist.** `print-invoice-items.ts` / `buildInvoiceData` feed the thermal agent, not a PDF. Add `GET /mobile/pos/sales/:id/ticket.pdf` rendering with `pdfkit` (already a dependency) in the style of `ticket-generator.ts` (80 mm), with an explicit "COMPROBANTE NO VÁLIDO COMO FACTURA" line `[ASSUMED: legend wording — confirm with user/accountant]`. Refuse for nullified sales (same rule as `reprintSale :3880-3887`). Do not render a CAE.
- **Public link alternative** (no auth, signed, non-expiring): `PdfTokenService` (`afip/pdf-token`), route `GET /api/afip/public/voucher/:token/pdf` (`public-pdf.controller.ts`). Useful if the user prefers a link in a prefilled `wa.me` message.

### Q5. Printing by button; unattended paths
- **Two unattended paths exist at sale creation** and both are in `afterCreateCommit` (`sales-create.service.ts:1329` `printTicket && !suppressAutoPrint`, and `:1369-1441` AFIP auto-issue→auto-thermal, gated by `shouldAutoIssue`). Today the second is dead code: `AUTO_EMISION_PROHIBIDA = true` makes `shouldAutoIssue` return false (`afip/auto-issue.ts:4,29`) — **do not rely on that constant alone**: the wrapper must still pass `suppressAutoPrint:true` and omit `printTicket`/`printerAgentId` so a future flag flip cannot print from a phone.
- **Button endpoints already exist:** non-fiscal `POST /sales/:id/reprint {printerAgentId?}` (`sales.controller.ts:433-472`) → `reprintSale :3852` → `resolveInvoiceTargetSocketId(sale.terminalId, branchId, {agentId, storeId})` → `PrintService` → single target socket, refuses when ambiguous/offline (`reason: ambiguous_target|agent_offline|printer_not_allowed|no_api_key`). `GET /sales/:id/printers` lists allowed comanderas (terminal's + `terminal_printers`). Fiscal: `POST /afip/vouchers/:id/reprint {branchId, terminalId}` (`:1658`, `manualReprint:true`). Because the sale's `terminal_id` is the phone terminal (Pattern 2), `thermal_agent_id` mapping on that terminal is used automatically (D-14) — the manager maps a comandera to the phone terminal in the existing editor.
- Wrapper: `POST /mobile/pos/sales/:id/print` and `/vouchers/:id/print` must (1) verify the sale/voucher belongs to the store (and optionally to this terminal's branch), (2) use `terminalId` from the approved device, never the body, (3) disable the button while in flight and surface the `reason` verbatim. Rule "중복 인쇄는 결단코 금지": there is no server de-dup for *manual* reprints by design (`manualReprint`), so UI must debounce and show last-printed time.

### Q6. Stock ingreso
- **Web ingreso is not `POST /stocks/movement`.** That route only accepts `movido|fallado|devuelto` (`stocks.service.ts:221`). Web ingreso for existing variants goes through `PUT /products/:id/correct-today` (absolute "new stock" for *today's* ingreso, `products.controller.ts:1077`, bare `@Auth()`) and new variants through `POST /products/variants/batch` (`@FunctionGuard('crear-producto','create')`, `:423`); the old additive route `POST /products/:id/inventory` is **deprecated and throws** (`productStock.service.ts:1145-1172`). Web ingreso ledger rows are **`type IS NULL`, `stock > 0`, `note NULL`, `operation_date`** — that is exactly what the canonical view `v_product_branch_daily_ingreso` counts as `ingreso` (`migrations/2026-08-07-daily-ingreso-include-correccion.sql`).
- **Single safe writer:** `ProductStockService.ingresarStockPorProductos({items[{productId,qty}], branchId, date?, note?, type?, tx})` (`productStock.service.ts:631`) → `writeStockRows (:679)`: groups by product, maps "sin color y talle" branches via `hojaEnSucursal`, `asegurarProductBranch`, ascending productId, `stockModel.bulkCreate`. **Landmine:** `const type = params.type ?? STOCK_TYPE.PRODUCTION` (`:688`) — omitting `type` writes `'production'`, which `STOCK_TYPES_EXCLUDED_FROM_FLOW` excludes from ingreso reports (`stocks.constants.ts`), and `StockMovementType` has no `null`. For mobile ingreso, add an explicit way to write `type: null` (e.g. `type?: StockMovementType | null` with `undefined → PRODUCTION` preserved for the subcon callers, `null → NULL`) and a spec asserting existing callers unchanged. Parent (madre) PB writes are rejected by `trg_stocks_leaf_only` (SQLSTATE 23514) → pre-filter with `madre-guard.ts`.
- **Note/proveedor:** `stocks.note` is free text; do not start it with `anulacion ingreso`/`correccion ingreso`/`ajuste de mov#`/`import `/`movido`/`fallado` (reserved prefixes, `stocks.constants.ts:69,120`). Prefer storing "Remito 4471 – Proveedor X" in `note` (one note for all rows of the batch). `stocks.source` exists (`MANUAL_ADJUST_SOURCE`, …); a new source value is optional and out of scope unless reports need to separate mobile ingresos (Open Q).
- **Wrapper:** `POST /mobile/pos/stock/ingreso {items[{productId(variantId), qty}], note, idempotencyKey}`; destination branch = terminal's branch (mockup ⑧ shows a "Destino" selector → restrict to branches the user is permitted; recommend terminal's branch only, plus admin may choose). One `sequelize.transaction` around everything; `qty` integer > 0; cap per request (e.g. 200 lines); tenant check each `productId` belongs to the store (the service itself does not check store — `Product.findAll({where:{id}})` only in `createStockMovement`; **verify/enforce in wrapper**). Idempotency for ingreso: the repo has no ingreso idempotency table → reuse `sale_idempotency_keys`? It is sale-shaped (`sale_id`). Recommend a tiny second table or storing the key in `stocks.note` is **not** safe; decide in Open Q. At minimum, response must be deterministic and the app must block double-tap and, on timeout, show "verificar movimientos" rather than retry.
- **Preview "stock 1 → 7" in mockup ⑧:** read `stock_balances.available` per `(product_id, branch_id)`; do not read `products.stock`.
- **Permission (D-06 gap):** none of the ingreso routes has a function guard (`correct-today`, `edit-madre-variants` bare `@Auth()`; `POST /stocks` is role-only). Closest slugs in `functions`: `editar-stock-de-producto` (module `productos`; used with action `delete` for today-delete at `products.controller.ts:~654`), `stock-movement` (module `stocks-reportes`, used for movidos/fallados/devolución). Recommend `@FunctionGuard('editar-stock-de-producto','update')` `[ASSUMED action semantics — check ACCIONES_EXIGIDAS_POR_GUARDS and role_function_actions seed so roles that can ingreso on the web are not locked out]`. **Before enforcing, run a read-only prod query** of which roles have that function/action, otherwise gerente/vendedor who ingreso on the web today get 403 (memory: `permission-rows-are-not-power`, `migration-union-widens-permissions`).

### Q7. Reports (same numbers as web)
- **(a) Day summary:** `GET /sales/daily-summary?startDate&endDate&branchId&terminalId` (`sales.controller.ts:339`, `@FunctionGuard('ver-ventas','read')`) → `{totalSales, voidSalesCount, totalAmount, totalItems, totalDiscount, totalTransport, byPaymentMethod, byStatus, buckets{efectivo,credito,banco,mercadopago,otro}, ledger{credito,senia,favor,efectivo,tarjeta,transferencia,mercadopago}, creditCashAdjustment|null}` (`sales.service.ts:1302-1330`). Also `GET /sales/daily-stats` (per-branch table with ventas/prendas/neto/movs). **Gaps vs mockup ⑨:** no "Facturado AFIP", no "Sin emitir" (see Q4), no "% vs same weekday". Facturado: `GET /reports/facturacion-report` (`reporte-facturacion`) or `GET /afip/emitidas?date=` (`:1261`); "cobrado" in the mockup = cash-basis (`creditCashAdjustment` is a cash-basis adjustment already added into `totalAmount`, `null` when branch/terminal filter is used → say so on screen, "cada número dice qué cuenta"). Add one small wrapper `GET /mobile/pos/reports/day` that composes `getDailySummary` + facturado count/sum from `afip_vouchers` (non-NC) + sin-emitir count, all for one store-timezone day. **Date trap:** controller default `today = new Date().toISOString().slice(0,10)` is **UTC** (`:331`); after 21:00 BA it is "tomorrow". The app must send explicit `startDate/endDate` computed in the store timezone (and the wrapper should default using the store's `timezone`).
- **(b) Caja:** `GET /cash-register/:id/resume` (`cashRegister.controller.ts:323`; service `getCashRegisterWithOperationsById` → `{cashRegister, totals{venta,ingreso,gasto,retiro,saldoFinal}}`) with the id from the box lookup. `saldoFinal = computeSaldoFinal(initialAmount, totals)` (`caja-balance.ts`; memory: formula duplicated in 9 places — **call this function, never recompute**). Per-operation list: `BoxOperation` via existing box-operation endpoints (not inspected in detail; planner to check `box-operation/` controller for ingresos/egresos listing and role guards). "Efectivo esperado" = `saldoFinal`.
- **(c) Stock & best sellers:** best sellers `GET /dashboards/sales/top-sold-products` (`salesDashboards.controller.ts:30`, bare `@Auth()`); stock summary `GET /reports/stocks-cockpit` (`@FunctionGuard('reporte-stocks','read')`, `reports.controller.ts:1155`) and `stocks-report` rows as used by `tienda-admin-app` (`reportes_repository.dart:230`). **Memory warning:** `/api/reports/*` has Flutter consumers (`tienda-admin-app`, `ventago-admin-app`) — add endpoints, never change response shapes.
- All `/reports/*` take `storeId` in the query but resolve through `resolveScopedStoreId(user, query.storeId)` (server forces user's store for non-superadmin) `[ASSUMED from naming — verify the helper before trusting a client `storeId`]`; the wrapper should ignore client `storeId` entirely.

### Q8. Flutter apps inventory & what to copy
| App | Flutter state / http | iOS project | Bundle / applicationId | CI |
|-----|----------------------|-------------|------------------------|----|
| `mobile-sales-app` | riverpod ^3.3.1, go_router ^17, dio ^5.9, secure_storage ^10, mobile_scanner ^7.2 | **yes** (`ios/`, Podfile) | iOS `com.ventago.mobileSalesApp`; Android `com.ventago.mobile_sales_app` | `.github/workflows/build-mobile-sales-app.yml` (tag `mobile-sales-app-v*`): APK + Windows + macOS + **iOS unsigned compile check only** |
| `talleres-vendor-app` | riverpod ^3.3.1, go_router | yes (`ios/`) | — | none seen |
| `tienda-admin-app`, `ventago-admin-app` | riverpod ^2.5.1, dio, secure_storage ^9, local_auth | **no iOS dir** | — | `build-tienda-admin-app.yml`, `build-admin-app.yml` |
| `despacho-app` | riverpod ^2.5, dio, socket_io_client | no iOS (`ios: false`) | — | `build-despacho-app.yml` |
- **Repo layout:** `mobile-sales-app` is a **git submodule** of a private repo (`.gitmodules`; CI fetches with `RELEASE_REPO_TOKEN`, releases to `jhkim1010/ventago-downloads`); the others are plain monorepo dirs (`git ls-files` shows files). CONTEXT says "proyecto aparte" — decide repo vs folder (Open Q7). Note memory: `mobile-sales-app` edits require committing inside the submodule then bumping the pointer.
- **iOS gap (D-02):** no signing, no ExportOptions, no fastlane/Codemagic anywhere; the only iOS job is `flutter build ios --release --no-codesign`. TestFlight/App Store requires an Apple Developer account, bundle id registration, certificates/profiles, and a macOS runner. Local machine has Xcode 27.0 + CocoaPods but **no JDK** (`java -version` fails) → Android release builds run in GitHub Actions (Temurin 17) as today, not locally. Dev iPhone installs from Xcode need an Apple ID. Recommended bundle ids `[ASSUMED]`: `com.ventago.movil` (both platforms, underscored android namespace as per Flutter default).
- **Copy list (with sizes):** `core/network/dio_client.dart` (JWT + `x-mobile-session-token`, 401 codes `MOBILE_SESSION_EXPIRED|SESSION_EXPIRED|INVALID_MOBILE_SESSION`), `core/device/device_fingerprint.dart`, `core/storage/secure_storage.dart`, `core/config/api_config.dart` (`--dart-define=BASE_URL`, prod default `https://newapi.coolsistema.com/api`), `core/theme/app_theme.dart`, `core/format/money.dart`, `features/scanner/{logic/lector_logic.dart,views/lector_screen.dart}` (+ `test/lector_test.dart`), `features/product/widgets/variant_stock_matrix.dart` (355 lines) & `variant_matrix_provider.dart`, `features/cart/providers/cart_provider.dart` (228 lines; extend with variant lines + persistence), `core/update/*` (self-update check). Reports UI patterns: `tienda-admin-app/lib/features/reportes/` (`reportes_repository.dart` consumes `/reports/{slug}` with `{data:[...]}` shape; `asInt/asNum` helpers in `shared/format.dart`).
- **Important existing-client behaviors to NOT copy:** 401 handler wipes storage and says "ingresaste en otro dispositivo" (wrong message for 6 h JWT expiry — the new app needs a re-login-preserving-cart path); branch self-selection screen; `comanda_screen.dart` posting `POST /mobile/sales` (suspended-sale semantics).
- **Sharing:** `share_plus` + temp file from `path_provider`; for iOS add nothing special in Info.plist for share; camera needs `NSCameraUsageDescription` (already needed by mobile_scanner; confirm in `mobile-sales-app/ios/Runner/Info.plist`).

### Q9. Permission mapping (server must reject with web's list)
Slugs verified in the local `functions` table and controllers:
| Action in app | Server check (recommended on `/mobile/pos/*`) | Evidence |
|---|---|---|
| Sell / create sale | `@FunctionGuard('crear-venta','create')` | `sales.controller.ts:113`, `mobile-sales.controller.ts:46`; module `nueva-venta` |
| Add payments to existing sale | (not needed in v1) `agregar-pagos-a-venta/update` | `sales.controller.ts:569` |
| Create client from sale | `crear-cliente-en-venta` / `editar-cliente-en-venta` exist as functions; `clients.controller.ts` uses `@Auth(roles)` | local `functions` table; `clients.controller.ts:127-165` |
| Issue AFIP | web: `@Auth(admin,superadmin,gerente,vendedor)` only (no function slug) → mobile: keep same roles + require `crear-venta/create` `[recommendation]` | `afip.controller.ts:1276-1282` |
| View/share invoice PDF | `@Auth(admin,superadmin,gerente,vendedor)`; scope `ver_facturas` | `afip.controller.ts:1684` |
| Re-print | `@Auth(vendedor,gerente,admin,superadmin)` | `sales.controller.ts:433` |
| Stock ingreso | **none today** → `editar-stock-de-producto` (see Q6) | `products.controller.ts:1077` |
| Open caja | `@Auth(admin,superadmin,vendedor,gerente)` today; D-05 says «encargado» → restrict to admin/gerente | `cashRegister.controller.ts:344` |
| Day summary | `ver-ventas/read` | `sales.controller.ts:341` |
| Caja report | `@Auth(...)` on `/cash-register/:id/resume`; box-operation reads: check | `cashRegister.controller.ts:323` |
| Sales/Facturación/Stock reports | `reporte-ventas`, `reporte-facturacion`, `reporte-stocks`, `reporte-items`, `reporte-ganancia` (cost/profit cards gated by `isAllowedStrict`) | `reports.controller.ts:293,572,1155,845` |
| Approve/revoke device | `editar-terminal/update` | `terminal.controller.ts:49` |
Return a **permission snapshot** in `/mobile/pos/context` (computed server-side with `FunctionPermissionService.isAllowed`) only for UI hiding; the guards remain the boundary. PERM cache is per-worker 60 s: a role revoked mid-shift can still sell for ≤60 s.

### Q10. Risks, landmines → see Common Pitfalls; Waves → see below; Validation → see Validation Architecture.

## Common Pitfalls

### Pitfall 1: Drawer chosen by branch/user instead of the phone's box
**What goes wrong:** cash lands in another box's session in a multi-box branch; sale `terminal_id` = terminal of whoever opened that session.
**Why:** `getOpenCashRegister(userId, branchId)` returns `id DESC` in branch (`cashRegister.service.ts:2094-2107`).
**Avoid:** always `offlineCash:{boxId,terminalId}` from the approved device; spec asserts `box_operations.cash_register_id` is the phone box's session and `sales.terminal_id` is the phone terminal (use the pattern of `sale-payment-tenant.itest.ts`).
**Warning sign:** `[VentasDebug][create]` log shows a different terminal than the device's.

### Pitfall 2: Card-only sale passes without a caja
**What goes wrong:** D-05 says no caja → no cobro, but non-cash sales never resolve a register, so the server happily sells.
**Avoid:** explicit pre-check in wrapper (`getOpenCashRegisterByBox`) → 409 `CAJA_CERRADA`; test with efectivo, transferencia-only and mixed.

### Pitfall 3: Auto print / auto issue from a phone sale
**Avoid:** omit `printTicket`, `printerAgentId`; pass `suppressAutoPrint:true`; AFIP `output:'pdf'`; DTO whitelist on the wrapper (reject unknown keys — global pipe is `transform:false`, see `declare-opening-amount.dto.ts` note, so values arrive raw; narrow with `Number()`). Add a spec that mocks `sendToprinters` and `afipOutputService.dispatch` and asserts zero calls (with a **control group**: web path with `printTicket:true` does call — memory `control-group-can-pass-too`).

### Pitfall 4: Emission retry creates a second CAE / confusing UI
**Avoid:** never "retry" blindly. On network loss call `GET …/preview` and branch on `emitidos.length`, `enProgreso` (poll every ~3 s), `verificar` (stop: "avisá al encargado"). Rejected (`afip_status='error'`) is re-issuable after fixing client data. Do not expose `resolver/liberar` to mobile.

### Pitfall 5: Receptor data edits don't reach AFIP
**What goes wrong:** user fixes CUIT/IVA condition in the app, but emission still uses the old client row → "Condición IVA del receptor obligatoria" again.
**Avoid:** persist fiscal data to the client row first (store `clients`/store_clients path), re-run `preview` to show the new `tipo`, then emit. Never write `global_clients` (absolute rule). `res_iva` is a **display string**, not a code (memory `res-iva-is-a-display-string-not-a-code`) — send the same strings the web combo uses.

### Pitfall 6: IIBB province missing → emission refused after the customer left
**Avoid:** ask for the buyer's province at checkout (validated before cobro per D-11) and send `provinceId` with the sale; `resolveJurisdiccion` refuses otherwise.

### Pitfall 7: Idempotency hash mismatch / expiry
See Pattern 3; also keys last 24 h and are per `(store_id,key)`.

### Pitfall 8: Ingreso written as `type='production'`
**Avoid:** extend `writeStockRows`/`ingresarStockPorProductos` to accept NULL type (Q6) + spec reading back the row `type IS NULL` and the view `v_product_branch_daily_ingreso.net` increasing; mutation-test the `?? PRODUCTION` default (memory: mutation survivors = call-site untested).

### Pitfall 9: Ingreso permission locks out roles that work on the web today
**Avoid:** measure role→function/action grants in prod (read-only) before shipping the guard; ship wrapper guard in the same release as an `-- perm-cache:` note if any seed DML is added.

### Pitfall 10: UTC "today"
All day-boundaries use store timezone (`stores.timezone`, `DEFAULT_STORE_TZ`); `daily-summary` defaults to UTC date. Test the 21:00–24:00 BA window.

### Pitfall 11: Migration ordering (model gains columns → migration BEFORE push)
Adding `Sale`/`SalePaymentMethod` model columns without prod migration first makes every sales query 500 (memory `migration-before-push-when-model-gains-columns`). Order: migration prod+local → verify both → push api → push app. New nullable columns only; `CREATE INDEX CONCURRENTLY` outside the single transaction; `sales.source` has a CHECK (`sales_source_check`) — do **not** add `'mobile'` without a W4-style `NOT VALID`+`VALIDATE` widening (alternative: keep `source='pos'` and mark by `terminal_id`).

### Pitfall 12: Revoked/lost phone keeps a valid 6 h JWT
Wrapper guard checks the device on every request (cache ≤60 s). Web endpoints still accept that JWT until expiry (existing posture). Document; optionally shorten mobile JWT (currently 6 h) — separate decision.

### Pitfall 13: New controllers vs agent-scope enumeration specs
`auth/guards/agent-readonly-scopes.*.spec.ts` enumerate controllers/handlers (manifests in `agent-scope-manifest.*.ts`, exclusions in `agent-scope-exclusions.ts`). `/mobile/*` is not obviously listed, but run those specs after adding controllers `[ASSUMED — not executed]`.

### Pitfall 14: Test/infra hazards in this repo
Never bare `jest` (20 GB); `--maxWorkers=1`; a spec importing outside `rootDir` runs 0 tests; `jest "N passed"` hides uncompiled suites; `NODE_OPTIONS` temp-file issue kills node; `@Column` without explicit `type` kills prod boot; `next build` kills a running dev server (web screen work).

### Pitfall 15: Flutter-side money/cart
Two `setState` from same closure loses one (memory `two-setstate-same-closure-loses-one`) — compose cart/payment mutations as pure functions in `.ts`-like pure Dart files with unit tests (app jest cannot import tsx; same idea: keep logic out of widgets). Persist cart + pending idempotency key atomically before network call.

## Code Examples

### Wrapper skeleton (copy of existing guard stack)
```typescript
// Source: api-ventago/src/app/mobile/sales/mobile-sales.controller.ts:46-47 (shape), sales-create.service.ts:262 (opts)
@Controller('mobile/pos')
@UseGuards(AuthGuard('jwt'), MobileScopeGuard, MobileTerminalGuard)
export class MobilePosController {
  @Post('sales')
  @FunctionGuard('crear-venta', 'create')
  async create(@Req() req: ReqWithDevice, @Body() dto: MobileCreatePosSaleDto,
               @Headers('idempotency-key') key: string) {
    if (!key) throw new BadRequestException('Idempotency-Key requerida');
    const { storeId, device } = this.ctx(req);          // device = approved row: terminalId, boxId, branchId
    await this.assertBoxOpen(device.boxId);             // D-05 (card-only sales never touch the register)
    const saleDto = { ...toCreateSaleDto(dto), storeId, userId: req.user.id, branchId: device.branchId }; // no saleDate/printTicket
    return this.sales.create(saleDto, {
      idempotencyKey: key,
      suppressAutoPrint: true,
      offlineCash: { boxId: device.boxId, terminalId: device.terminalId },
    });
  }
}
```

### AFIP "consulta, no reenvía"
```dart
// Flutter: after a network error on POST invoice
final st = await api.get('/mobile/pos/sales/$saleId/fiscal');   // wraps GET /afip/vouchers/:saleId/preview
if (st.emitidos.isNotEmpty) showEmitida(st.emitidos.last);       // never POST again
else if (st.enProgreso)     poll(every: 3.seconds);
else if (st.verificar)      showCallManager();
else                        enableRetryButton();                 // afip_status 'error' or untouched
```

### Share (verified API)
```dart
// Source: https://pub.dev/packages/share_plus
final dir = await getTemporaryDirectory();
final f = File('${dir.path}/factura-B-0003-00000418.pdf')..writeAsBytesSync(bytes);
await SharePlus.instance.share(ShareParams(text: 'Factura B 0003-00000418', files: [XFile(f.path)],
    sharePositionOrigin: box.localToGlobal(Offset.zero) & box.size)); // iPad
```

### Dio headers (existing)
`mobile-sales-app/lib/core/network/dio_client.dart`: `Authorization: Bearer <mobileToken>` + `x-mobile-session-token`. Add `Idempotency-Key` per request in the repository layer, not an interceptor.

## State of the Art

| Old | Current | Impact |
|-----|---------|--------|
| Mobile sale = suspended sale (`POST /mobile/sales`, no payment) | Real sale through `SalesCreateService` with device-bound drawer | New endpoints; old app unchanged |
| Auto AFIP issue after sale | **Prohibited** (2026-10-14); manual F10 only | wrapper never sets flags; `AUTO_EMISION_PROHIBIDA` |
| `products.stock` | `stock_balances` / `v_stock_*` | new reads must use balances |
| `POST /products/:id/inventory` | deprecated, throws | don't use |
| `Share.shareXFiles` (older share_plus) | `SharePlus.instance.share(ShareParams(...))` | use new API (v13) |

**Deprecated/outdated:** the `@aiondadotcom`-era notes about `http://62.72.7.245:5002` — agents/apps use `https://newapi.coolsistema.com/api` (CLAUDE.md).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | A file cannot be attached to a prefilled `wa.me/<number>` link; only text/link can | Alternatives | If wrong, mockup ⑦'s prefilled-number WhatsApp could attach the PDF; low |
| A2 | `HapticFeedback`/`SystemSound` suffice for scan feedback | Stack | Minor; add `audioplayers` if sounds insufficient |
| A3 | Recommended bundle id `com.ventago.movil` | Q8 | Reserve/registration conflict in App Store; confirm with owner |
| A4 | Phone terminals appearing in web terminal pickers is acceptable or needs a `kind` marker | Q2 | Web users might move a browser onto a phone terminal |
| A5 | `@FunctionGuard('editar-stock-de-producto','update')` is the right ingreso gate and matches existing role grants | Q6/Q9 | Wrong action → lock-out or over-grant; must check prod grants first |
| A6 | Non-fiscal ticket legend wording «COMPROBANTE NO VÁLIDO COMO FACTURA» | Q4 | Fiscal/legal wording; confirm with user/accountant |
| A7 | CF-without-DNI AFIP cap behavior (mockup ④ text) lives in `decideComprobante`/`decideDocumentType` | Q4 | UI copy may misstate the rule; read `afip/code-maps.ts` before wording |
| A8 | `/reports/*` ignore client `storeId` for non-superadmin (`resolveScopedStoreId`) | Q7 | Tenant leak if untrue; read helper |
| A9 | Which function slug gates "open caja" on web is unknown (only role `@Auth`) | Q3 | D-05 «encargado» rule must be chosen explicitly |
| A10 | `agent-readonly-scopes.*` specs don't need entries for `/mobile/*` | Pitfall 13 | A failing spec in the commit gate |
| A11 | No other code treats every `terminals` row as a physical POS | Q2 | Hidden UI/report impact |

## Open Questions (RESOLVED)

All resolved 2026-10-15 (user decisions D-17…D-22 in 111-CONTEXT.md + planner decisions recorded in the plans).

1. **Payment audit persistence (D-08).** — RESOLVED by D-17: nullable `sale_payment_methods.received_amount / change_amount / reference` (+ `mp_payment_intent_id` for D-21). → Plan 01 (DDL + models), Plan 05 (written in the sale tx).
2. **Ingreso idempotency.** — RESOLVED: table `mobile_stock_ingresos (store_id, idempotency_key UNIQUE, request_hash, status…)`, client-generated key. → Plan 01, Plan 07, Plan 12.
3. **Where to store "quiere factura / sin emitir".** — RESOLVED by D-17: nullable `sales.invoice_pending_at`, partial index CONCURRENTLY; counter/list have NO day window (D-12, checker 2026-10-15), only the day report is per day. → Plan 01, Plan 03 (query), Plan 04 (context counter), Plan 06 (list), Plan 08 (day report), Plans 10/19 (UI).
4. **Open-caja permission.** — RESOLVED by D-18: same roles as web `POST /cash-register/open` (admin, superadmin, vendedor, gerente). → Plan 04.
5. **Attendance gate.** — RESOLVED: no clock-in gate on any `/mobile/pos/*` route for any role, same as the web POS (the web has none on selling/opening). → Plan 04 Task 2 (acceptance grep: no `RequireAttendanceGuard`), Plan 10 (no app gate).
6. **WhatsApp prefilled number vs share sheet.** — RESOLVED by D-13: share sheet with the PDF file; no `wa.me` links. → Plan 19 (grep gate).
7. **Repo layout.** — RESOLVED by D-19: new private repo as submodule. → Plan 02.
8. **Apple Developer account / bundle id / signing.** — RESOLVED by D-20: account exists, the user signs; TestFlight as a human checkpoint; bundle id confirmed in Plan 02 Task 1 (A3). → Plan 02, Plan 14.
9. **Mobile JWT lifetime/refresh.** — RESOLVED: keep 6 h, no refresh flow in this phase; re-login keeps drafts and pending keys (Plan 16). The token is confined to `/mobile/pos/*` and revocation deletes the session, so a lost phone is cut off at once (D-22). → Plans 15, 16, 18.
10. **Price/total trust (promos).** — RESOLVED: the wrapper re-checks list prices and centavo arithmetic but does not recompute or alter promotions; `SalesCreateService` stays the only writer and validates `promotionId` exactly as for the web. The phone sends no promo fields in this phase, so a phone sale is recorded like a web sale where no promo was applied. (Surfaced to the user — automatic promos on the phone would be a new decision.) → Plan 05.
11. **`sales.source` for mobile sales.** — RESOLVED: unchanged (no override); phone sales are identified by `sales.terminal_id` → `mobile_devices.terminal_id`. → Plan 05 (acceptance grep: no `source:` in the wrapper).
12. **(added) Mercado Pago QR on the phone.** — RESOLVED by D-21: same dynamic flow as the web via `/mobile/pos/mp/*` wrapping `MpQrService`; intent linked to the payment line with a partial UNIQUE index. → Plans 01, 03, 04, 05, 17, 13.
13. **(added) Revoked phone token on web routes.** — RESOLVED by D-22: claim `cli='ventago-movil'` confined to `/mobile/pos/*` (HTTP + sockets); only the new app's logins carry it, so mobile-sales-app (which uses its token on `/attendance/punch`, `/products/:id/images`) is untouched. → Plan 18, Plan 15, Plan 16 (API-path gate), Plan 14 (UAT step 11).

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Flutter / Dart | app | ✓ | 3.44.8 / 3.12.2 | — |
| Xcode + CocoaPods | iOS build | ✓ | Xcode 27.0 (27A266a), pod at /opt/homebrew/bin | — |
| JDK (Android build) | local APK/AAB | ✗ | — | GitHub Actions `setup-java` Temurin 17 (as `build-mobile-sales-app.yml`) or install JDK 17 |
| Local PG18 :5432 `ventago` | migrations, itests | ✓ | queried | — |
| Prod PG18 :5434 via `ssh jhkim-server` | read-only checks, migration apply | ✓ | key works (no passphrase prompt this session) | — |
| GitHub Actions macOS runner + secrets | iOS CI | partially | unsigned check exists | need Apple signing secrets |
| Apple Developer account | TestFlight/App Store | unknown | — | **blocking for D-02 distribution** — human checkpoint |
| `ctx7` CLI / Context7 | docs | ✗ (not installed) | — | WebFetch of pub.dev used |

**Missing with no fallback:** Apple Developer account/signing (distribution only; development builds unaffected).
**Missing with fallback:** local JDK (use CI).

## Validation Architecture

> `.planning/config.json` has no `workflow.nyquist_validation` key → enabled.

### Test Framework
| Property | Value |
|----------|-------|
| API framework | Jest via `ts-jest` in `api-ventago` (`package.json` `"test": "jest"`); specs live next to modules; integration `*.itest.ts` run by `npm run test:itest` (`test/itest/jest-itest.json`, `--runInBand`, needs DB) |
| Flutter | `flutter_test` (as `mobile-sales-app/test/*.dart`: `lector_test.dart`, `scope_provider_test.dart`, …) |
| Web (if approval screen added) | app eslint (warnings = errors) + `tsc`; app jest cannot import `.tsx` → keep logic in `.ts` |
| Quick run (API) | `cd api-ventago && npx jest src/app/mobile --maxWorkers=1` (the commit gate runs the changed module directory) |
| Full suite | never bare `jest`; `npx jest --maxWorkers=1` (slow; CI) |
| Migrations | `npx jest src/common/migrations/migration-conventions.spec.ts --maxWorkers=1` |

### Phase Requirements → Test Map
| Req | Behavior | Type | Command / approach | Exists? |
|-----|----------|------|--------------------|---------|
| D-04 | unknown fingerprint → `pending`; approve creates terminal in store's box only; revoke → next request 401/403 within cache TTL; cross-store box rejected | unit (service) + guard spec | `npx jest src/app/mobile/devices src/app/mobile/guards --maxWorkers=1` | ❌ Wave 0 |
| D-03/D-05 | sale lands in phone box session; `sales.terminal_id`=phone terminal; closed box → 409 for efectivo **and** card-only; no second `cash_registers` row | itest (DB) + unit | follow `sales/sale-payment-tenant.itest.ts`, `cajas` specs (`caja-una-sesion-por-box.spec.ts`) | ❌ |
| D-06 | each wrapper route 403s without its slug; allowed with it; superadmin passes | unit (guard metadata reflect + `FunctionPermissionService` mock) — **assert the specific guard fires, not just exception type** (memory `test-can-pass-on-the-wrong-guard`) | ❌ |
| D-07 | hidden/inactive methods absent in context | unit | ❌ |
| D-08 | same key+body → same sale (replay); concurrent → one sale; by-key lookup states | unit w/ `SaleIdempotencyService` + itest | extend `sale-idempotency.service.spec.ts` pattern | ❌ |
| D-09 | (app) cart persists across kill; no network → cobrar disabled | flutter test | `flutter test test/cart_persistence_test.dart` | ❌ |
| D-10 | mobile sale never triggers AFIP issue/print; emission only via explicit endpoint; control group on web path | unit with mocks (+ mutation: flip `suppressAutoPrint`) | ❌ |
| D-11/D-12 | receptor change reflected in `preview.tipo`; states map (`emitidos/enProgreso/verificar/error`) | unit over `AfipVoucherService` (`afip-voucher-estado.spec.ts` exists as base) | partial ✅ |
| D-13 | PDF bytes start `%PDF`, voucher belongs to store; non-fiscal ticket refuses nullified sale | unit | ❌ |
| D-14 | print endpoint resolves terminal from device, ignores body terminalId | unit | ❌ |
| D-15 | ingreso writes `type IS NULL` rows by `product_branch_id`, single tx (rollback leaves 0 rows), madre rejected, cross-store product rejected, existing production callers unchanged | unit + itest | extend `productStock.ingreso-productos.spec.ts` | partial ✅ |
| D-16 | day summary uses store-TZ day (test 22:30 BA); caja totals equal `computeSaldoFinal` | unit | extend `daily-summary-terminal.spec.ts`, `caja-balance.spec.ts` | partial ✅ |

### Sampling Rate
- **Per task commit:** the module dir jest (what the gate runs) + `tsc`.
- **Per wave merge:** `npx jest src/app/mobile src/app/sales src/app/afip src/app/cashRegister src/app/products src/app/stocks --maxWorkers=1`, migrations convention spec, and `flutter analyze && flutter test` in the app.
- **Phase gate:** above green + manual UAT.
- **Mutation spot-checks** (project norm): remove `suppressAutoPrint`, remove box pre-check, change `offlineCash` → none, drop `type:null` — each must kill ≥1 test; a mutant that yields "Tests: 0" means compile error, not survival.

### Manual UAT (staging is NOT a prod copy; use local/prod-safe store)
1. Fresh install → login → "pendiente"; on web approve choosing branch+box → phone becomes active without re-login (poll).
2. PC POS user stays logged in while same user uses phone (no `active_sessions` change).
3. Close caja → cobrar disabled with reason; manager opens it (phone and PC) → exactly one open session in `cash_registers` for the box.
4. Sell efectivo+transferencia mixed; check `sale_payment_methods`, `box_operations(type='venta')` in the phone's box session, `sales.terminal_id`.
5. Kill app right after tapping Confirmar → reopen → "en verificación" resolves to the same sale; never two sales.
6. Emit Factura (homologation store) → CAE; airplane-mode mid-emit → reconnect → state via preview, no 2nd CAE; rejected case (missing IVA condition) → fix → retry.
7. Share PDF to WhatsApp & mail on Android and iPhone (iPad popover origin).
8. Print button with comandera mapped; confirm exactly one paper; confirm zero paper on sale creation.
9. Ingreso: scan same code twice <2 s (different sound), undo, edit row, confirm → check ledger rows `type IS NULL`, `stock_balances` increased, web "Ingreso" report shows it; abort mid-way → nothing saved.
10. Reports: compare each number with the web screen for the same day/branch; run after 21:00 BA to catch UTC bug.
11. Revoke phone on web → app blocked within ≤60 s.
12. Role matrix: vendedor / gerente / admin / "no roles" dummy account (memory `permission-test-accounts-exist`) per route.

### Wave 0 Gaps
- [ ] `api-ventago/src/app/mobile/devices/*.spec.ts`, `guards/mobile-terminal.guard.spec.ts`
- [ ] `api-ventago/src/app/mobile/pos/*.spec.ts` (+ one `*.itest.ts` for drawer/terminal)
- [ ] migration SQL + local/prod apply + `docs` of the schema regen (`./.planning/intel/db-schema.regen.sh`)
- [ ] Flutter project scaffold with `flutter test` + CI job
- [ ] fixtures: test store/branch with ≥2 boxes (to prove the drawer choice), one with `allowSaleWithoutStock=false`

## Security Domain

### Applicable ASVS Categories
| ASVS | Applies | Standard Control |
|------|---------|-----------------|
| V2 Authentication | yes | existing bcrypt login + JWT; device approval adds possession factor; no passwords stored on device (only tokens in `flutter_secure_storage`) |
| V3 Session Management | yes | `mobile_sessions` token rotation per login; revocation via device status; JWT 6 h, no refresh (documented gap) |
| V4 Access Control | **yes — core** | `@FunctionGuard` + store/branch/terminal derived server-side; tenant isolation (`TenantContext`); IDOR checks on `saleId`, `voucherId`, `productId`, `boxId` (every lookup `WHERE store_id = req.user.storeId`) |
| V5 Input Validation | yes | class-validator DTOs; `transform:false` → re-narrow with `Number()`; whitelist keys; amounts as centavos (`redondearMonto`, `mismoMonto`) |
| V6 Cryptography | limited | HMAC/JWT already in repo (`PdfTokenService`, `derivePrecioAuthKey`); never hand-roll |
| V8 Data protection | yes | PDFs contain customer CUIT/address: store only in app temp dir, delete after share; no logging of fiscal data client-side |
| V9 Communications | yes | HTTPS only (`https://newapi.coolsistema.com/api`); iOS ATS default; no cleartext |
| V13 API | yes | rate limit via global `ProxyThrottlerGuard`; idempotency keys scoped per store |

### Known Threat Patterns
| Pattern | STRIDE | Mitigation |
|---------|--------|-----------|
| Body-supplied `terminalId/branchId/boxId` (cash into another drawer/branch) | Tampering/Elevation | derive from approved device row only |
| Lost/stolen phone | Spoofing | revoke on web; guard cache ≤60 s; short JWT |
| Cross-tenant `saleId`/`voucherId` PDF/print | Info disclosure | store-scoped lookups; 404 not 403 for foreign ids (as `tiendaParaRevertir` in `sales.controller.ts:~60`) |
| Idempotency key reuse across stores | Tampering | keys are `(store_id, key)` unique; lookup filters by store |
| Duplicate CAE | Repudiation | existing atomic claim + `verificar`; never retry on uncertainty |
| Capability in URL | Info disclosure | do not put tokens in query strings (memory `capability-in-url-is-a-log-leak`); the existing public PDF link is a deliberate exception |
| Frontend permission flag as boundary | Elevation | server guards on every route (memory) |
| Log leakage | Info disclosure | `HttpLoggerMiddleware` logs requests — avoid sensitive fields in query |

## Recommended plan decomposition (waves)

**Wave 0 — decisions & scaffolding (human checkpoints):** resolve Open Q1–8 with the user (payment audit columns, sin-emitir marker, WhatsApp vs share, repo layout, Apple account); create fixtures; schema migration PR (local + prod, verify both). *Blocks everything else; no code push to prod before migration applied.*

**Wave 1 — Device & guard (server):** `mobile_devices` model + migration; login response extension (`deviceStatus`, roles); approve/revoke/list endpoints (`editar-terminal`); `MobileTerminalGuard`; specs. *Independent of Wave 2 internals.*

**Wave 2 — POS core (server):** `/mobile/pos/context` (caja by box, payment methods, flags, perms), catalog `variantId` + `stock_balances` reads, create sale wrapper (`offlineCash` + `suppressAutoPrint` + box pre-check + whitelist + total recompute), by-key lookup, open-caja wrapper, print-by-button wrappers, itest for drawer/terminal/no-print.

**Wave 3 — Fiscal & documents (server) [parallel with Wave 2 after Wave 1]:** fiscal-data update (client save + padrón completar), preview/state wrapper, emit wrapper (`output:'pdf'`), voucher PDF passthrough, non-fiscal ticket PDF, "sin emitir" marker/counter.

**Wave 4 — Stock & reports (server) [parallel]:** `type:NULL` support in ledger writer (+ regression spec for existing callers), ingreso wrapper + guard decision (after prod grant measurement), reports composites (day/caja/stock) with store-TZ.

**Wave 5 — Web approval UI:** "Dispositivos móviles" tab (pending list, approve with branch+box select, revoke, rename, printer mapping link). `next/dynamic`, SWR hook, lint clean. *Can run parallel to Waves 2–4 after Wave 1 API is frozen.*

**Wave 6 — Flutter app:** scaffold + CI (Android first); auth/device screens; sell flow (scan → matrix → cart → client/fiscal → cobro → emit → share); local persistence; ingreso; reports; update check. Contract tests against API fixtures. *Starts after Wave 2 API shapes are frozen (can start UI with mocks earlier).*

**Wave 7 — iOS & release:** bundle id, signing, TestFlight build job on macOS runner, camera/photo permission strings, App Store metadata; UAT list; deployment order (migration → api → web → app) respecting the 08–16 rule and the "paired changes" rule (state which side may ship first: server additive routes are safe to ship before the app/web).

## Sources

### Primary (HIGH — code read this session)
- `api-ventago/src/app/mobile/{auth,guards,sales,stock,catalog}/*`, `mobile.module.ts`
- `api-ventago/src/app/auth/guards/{jwt-global.guard,function-permission.guard,user-role.guard}.ts`, `decorators/{auth,function-guard}.decorator.ts`, `strategies/jwt.strategy.ts`, `services/function-permission.service.ts`, `app.module.ts:362-374`
- `api-ventago/src/app/session/*`, `terminal/terminal.controller.ts`
- `api-ventago/src/app/sales/{sales.controller,sales-create.service,sale-idempotency.service,offline-cash-target}.ts`, `dto/create-sales.dto.ts`
- `api-ventago/src/app/afip/{afip.controller,afip-voucher.service,afip-output.service,auto-issue,public-pdf,pdf-token,pdf/*}`
- `api-ventago/src/app/cashRegister/{cashRegister.controller,cashRegister.service}.ts`
- `api-ventago/src/app/{products/productStock.service,products/products.controller,stocks/*,payment-methods/*,reports/reports.controller,dashboards/sales/*}`
- `ventago-app/src/views/homes/components/ProductList/ProductList.tsx:2486-2870` (web sale payload + idempotency usage)
- `mobile-sales-app/**`, `tienda-admin-app/lib/features/reportes/reportes_repository.dart`, `.github/workflows/build-mobile-sales-app.yml`, `.gitmodules`
- Local PG18 `ventago` (functions, terminals, sales.afip_status/source, indexes, sale_idempotency_keys columns); prod PG18 read-only (`uq_cash_registers_abierta_por_box` present; `mobile_sessions` = 28 rows)
- pub.dev API (share_plus 13.3.1 etc.) and https://pub.dev/packages/share_plus (usage)

### Secondary (MEDIUM)
- `.planning/intel/db-schema-tables.md` (may lag DB — memory `intel-catalog-can-lag-the-database`; critical facts re-checked against DB where noted)

### Tertiary (LOW — assumptions)
- See Assumptions Log A1–A11.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH (Flutter deps already in repo; new ones verified on pub.dev)
- Architecture/server integration: HIGH (read from code with line refs; two prod facts verified)
- AFIP rules (CF cap wording, ticket legend): MEDIUM/LOW — flagged
- iOS distribution: MEDIUM — no existing signed pipeline to inspect
- Pitfalls: HIGH (most come from repo memory + code)

**Research date:** 2026-10-15
**Valid until:** ~2026-11-01 (this repo changes daily — re-read `sales-create.service.ts`, `afip.controller.ts`, `cashRegister.service.ts` diffs before executing; AFIP/RG 5616 behavior and `AUTO_EMISION_PROHIBIDA` may change)
