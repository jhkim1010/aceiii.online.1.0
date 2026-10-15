# Phase 111: App móvil Ventago — vender (con factura AFIP + envío), cargar stock, ver reportes - Context

**Gathered:** 2026-10-14
**Status:** Ready for planning

<domain>
## Phase Boundary

Una app nueva para celular (Android + iPhone) con la que el personal de la tienda:
1. **vende**: busca/escanea, elige talle×color, arma el carrito, identifica al cliente, **cobra de verdad**
   (a diferencia de mobile-sales-app, que sólo deja la venta en espera), **emite la factura AFIP con un
   toque manual** y **envía el comprobante** al cliente;
2. **carga stock** (ingreso) escaneando;
3. **consulta reportes**: resumen de ventas del día, caja, stock/más vendidos.

Fuera: devoluciones, anulaciones y notas de crédito (siguen en la web).

Pedido original (usuario, 2026-10-14): «핸드폰에서도 판매 (정식 영수증 발송 포함), 스톡 추가, 각종 보고서를 확인할 수 있는 앱».
</domain>

<decisions>
## Implementation Decisions

### App y plataforma
- **D-01:** **App nueva** (no se extiende mobile-sales-app ni tienda-admin-app — decisión del usuario).
  Se pueden copiar piezas (lector, grilla talle×color, pantallas de reportes), pero es un proyecto aparte.
- **D-02:** **Android + iPhone.** Implica build iOS, App Store y entorno de build en Mac (planificar desde el inicio).

### El celular es una terminal (idea del usuario)
- **D-03:** Cada celular se registra como **una terminal más** dentro de una **caja (box) existente** de la sucursal
  (jerarquía Store → Branch → Box → Terminal). La venta lleva ese `terminal_id`; el dinero entra en la **sesión de
  caja ya abierta de ese cajón** — regla «돈은 서랍 단위로만 모인다»: la app **nunca abre una segunda sesión**.
- **D-04:** Registro: **en el primer login, un encargado lo aprueba** desde la web eligiendo sucursal y caja
  (mismo modelo que el registro de terminal del POS web). Un celular perdido se da de baja desde la web.
- **D-05:** Sin caja abierta no se cobra: el botón se apaga y dice por qué; un encargado puede abrirla (acá o en la PC).
- Hecho verificado: la sesión móvil **ya es independiente** de la del escritorio (`mobile_sessions`, Phase 37 D-06 —
  el login móvil nunca toca `active_sessions`). Por eso usar el celular no corta el POS de la PC del mismo usuario.

### Quién puede qué
- **D-06:** **Los mismos permisos de la web** (roles + permisos individuales): vender = permiso de venta,
  ingreso = permiso de stock, reportes = permiso de reportes. Pueden entrar admin y gerente además de vendedor
  (hoy el login móvil sólo admite vendedor/revendedor — hay que ampliarlo). El servidor rechaza con la misma lista.

### Cobro
- **D-07:** **Mismos medios de pago que el POS web** de esa tienda (efectivo, transferencia, QR MP, tarjeta,
  cuenta corriente, pago mixto); los medios que la tienda ocultó no aparecen.
- **D-08:** Cobro **auditable**: por medio, importe aplicado / recibido / vuelto / referencia, y la cuenta
  completa visible; si no cierra, no se confirma. Confirmar se bloquea al tocar (idempotencia — no se cobra dos veces).
  Si se corta después de confirmar → «Cobro en verificación»: se consulta al servidor por esa clave, no se reenvía.
- **D-09:** **Sin conexión no se cobra ni se factura.** El carrito queda guardado en el celular y no se pierde.
  (Nada de ventas offline encoladas.)

### Factura AFIP
- **D-10:** La emisión es **siempre un toque manual** (equivalente a F10). Nunca automática — ni al cobrar ni al reconectar.
- **D-11:** «Datos para facturar» separados del cliente comercial: documento, condición IVA del **padrón AFIP**
  (RG 5616), domicilio del comprador (IIBB) y tipo de comprobante; se validan antes de cobrar.
- **D-12:** Estados visibles: sin emitir / emitiendo / emitida (número + CAE) / rechazada (motivo + corregir + reintentar).
  Salir sin emitir pide confirmación y deja la venta «sin emitir» con contador visible.

### Envío del comprobante
- **D-13:** **Compartir desde el celular**: se genera el PDF (con QR AFIP) y se abre WhatsApp / mail del teléfono;
  la vendedora elige el contacto. El servidor no envía mensajes. La factura se comparte sólo con CAE;
  antes, sólo «ticket no fiscal».

### Impresión
- **D-14:** **Sólo con botón**: la terminal del celular puede tener mapeada una comandera de la sucursal
  (igual que una terminal web, vía print-agent). **Nunca impresión automática** (regla «중복 인쇄는 결단코 금지»).

### Stock
- **D-15:** Ingreso por escaneo continuo con vibración/sonido, «Deshacer último», edición por fila, nota/proveedor;
  nada se guarda hasta «Confirmar ingreso». Se registra como movimiento del libro `stocks` (append-only),
  por `product_branch_id`, en una sola transacción.

### Reportes
- **D-16:** Tres: **resumen del día** (ventas netas, cobrado, facturado, sin emitir, por medio de pago),
  **caja** (efectivo esperado, ingresos/egresos de la sesión abierta), **stock y más vendidos**.
  Mismos números que la web (mismos endpoints) y cada número dice qué cuenta.

### Claude's Discretion
- Framework (Flutter, como las demás apps), estructura del proyecto, librerías.
- Reusar en el servidor la ruta de login `/mobile/auth/*` + `mobile_sessions` o ampliarla.
- Endpoints: preferir los mismos que usa el POS web (venta, AFIP, caja, reportes) antes que crear paralelos.
- Diseño visual: tema Ventago (navy #1a1a2e + gold #f5a623), siguiendo el mockup.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Mockup y semilla
- `.planning/phases/111-app-m-vil-ventago-vender-desde-el-celular-con-factura-electr/mockup.html` (+ `mockup.png`) — 10 pantallas v2, revisadas con CODEX en 2 rondas
- `.planning/phases/111-app-m-vil-ventago-vender-desde-el-celular-con-factura-electr/111-SEED.md` — pedido y hechos iniciales

### Reglas del proyecto que la app no puede romper
- `CLAUDE.md` § «카하(Box) 규칙» — una sola sesión abierta por cajón
- `CLAUDE.md` § «쓰기 경로 규약 (Phase 64)» — una transacción, `stocks` append-only, Idempotency-Key en ventas, `allowSaleWithoutStock`
- `CLAUDE.md` § «세션 & 터미널 보안» — registro de terminal / dispositivo

### Código existente a estudiar
- `api-ventago/src/app/mobile/auth/mobile-auth.service.ts` — login móvil independiente (D-06 de Phase 37)
- `api-ventago/src/app/mobile/dto/mobile-create-sale.dto.ts` — la venta móvil actual (sin pago, en espera)
- `mobile-sales-app/lib/features/{catalog,product,scanner,cart}` — lector y grilla talle×color reutilizables
- `tienda-admin-app/lib/features/reportes/reportes_repository.dart` — consumo de `/reports/*`

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- mobile-sales-app: lector de códigos (`/mobile/scan/{code}`), grilla stock talle×color (`/mobile/stock/{id}`), carrito con variantes, selección de sucursal, sesión por dispositivo (`x-mobile-session-token`).
- tienda-admin-app: pantallas de reportes y caja (`/cash-register/*`, `/dashboards/sales/*`, `/reports/{slug}`).
- Backend: emisión AFIP SOAP con receptor IVA (RG 5616), numeración por sucursal (`uq_sales_branch_daylocal_dn`), Idempotency-Key en creación de venta, print-agent por terminal (`terminals.thermal_agent_id`).

### Established Patterns
- Nada de AFIP ni de comprobantes en las apps móviles: es trabajo nuevo.
- `sales.branch_id` es la sucursal autoritativa; `terminal_id` es el único FK directo hacia box/branch.

### Integration Points
- Registro de terminal (web, encargado) → `terminals` + vínculo con el dispositivo.
- Creación de venta con pago (mismo servicio que el POS web), emisión AFIP manual, PDF de factura.
- Ingreso de stock: mismo servicio de ingreso que la web.

</code_context>

<specifics>
## Specific Ideas

- «앱은 하나의 새 터미널처럼 작동하게 하면 충돌을 피할 수 있지 않은가?» — usuario. Adoptado como D-03.
- Mockup v2: escanear abajo al pulgar; hoja inferior con la variante en letras grandes; una fila por variante;
  ecuación del cobro visible; contador de «facturas sin emitir» en el inicio y en Reportes.

</specifics>

<deferred>
## Deferred Ideas

- Devoluciones, anulaciones y notas de crédito desde el celular (CODEX 2ª ronda) — fase propia.
- Ventas offline encoladas.
- Envío del comprobante desde el servidor (WhatsApp Business API / mail automático).
- Impresora bluetooth portátil.
- El resto de los reportes web (`/reports/*`, 15 slugs).

</deferred>
