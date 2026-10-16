# HANDOFF 2026-10-15 (noche) — Alt+F12 «sólo factura» pendiente de DDL prod + resumen del día

## ★ PRIMERO: Alt+F12 está commiteado pero NO desplegado
- api `0517c134` y app `500eac04` — **commit sin push** (a propósito).
- El código nuevo usa la tabla `afip_facturas_sin_venta` y `afip_vouchers.sin_venta_id` →
  **la migración tiene que ir a prod ANTES del push de la api** (memoria
  migration-before-push-when-model-gains-columns).
- El usuario todavía NO aprobó el DDL de prod (se le pidió; respondió «handoff 준비»).
- Orden al aprobar: medir usuarios activos → prod
  `ssh jhkim-server "sudo -u postgres psql -p 5434 -d ventago -v ON_ERROR_STOP=1" < api-ventago/migrations/20261015-afip-facturas-sin-venta-a.sql`
  (sin --single-transaction: el archivo ya trae su lógica; VALIDATE al final) →
  `... < 20261015-afip-facturas-sin-venta-b.sql` (CONCURRENTLY, sin transacción) →
  comparar esquema local vs prod (tabla, 2 triggers, CHECK ck_afip_vouchers_un_duenio, FK,
  idx_afip_vouchers_sin_venta VALID) → push api → Jenkins por SHA → push app → Jenkins.
- Impacto prod: 0 filas cambiadas; afip_vouchers 32 filas, todas con sale_id (CHECK pasa).
- Local (5432) YA aplicado y probado.

## Alt+F12 — qué es
- Plan: `.planning/PLAN-2026-10-15-alt-f12-solo-factura.md` · mockup `.planning/mockups/2026-10-15-alt-f12-solo-factura/`.
- POS Alt+F12 → `SoloFacturaDialog` → `POST /afip/vouchers/sin-venta` → factura 100 % SIN venta
  (no stock, no caja, no reportes de ventas). Sin cliente = Consumidor Final.
- Servidor: `issue()` ahora trabaja sobre un «objetivo» (venta | sin_venta); guardas comunes en
  `emitirConGuardas`; `emitirSinVenta` (idempotencia por (store, key+huella), 409 si cambia el
  contenido, yaEmitida si ya facturó). Sin-venta: claim sólo desde no/error; rancio sin respuesta
  AFIP bloquea.
- ★ Aislamiento (usuario: «매장간에 데이터 오염이 없도록 절대적으로»): tienda sólo del token;
  sucursal/terminal/cliente verificados en código + triggers DB; JOINs de IIBB/Libro IVA/Excel/
  cockpit/watch con misma tienda (spec reforzado + mutante probado).
- Salida/PDF/emitidas/NC/ND usan `getFuenteFactura` (venta o foto del receptor).
- Catálogos de backup/restore/vaciado regenerados; se declararon también tablas de otras sesiones
  que estaban sin declarar (sales_numeros_borrados, wp_order_states refs, triggers sku/store_clients).
- Tests: itest `src/app/afip/sin-venta.itest.ts` 7/7 (AFIP falso, deja tiendas ZZ-SIN-VENTA-A/B
  como artefactos); afip+store+reports+watch 1785/1785; app solo-factura 4/4, atajos 20/20.
- Diferencia con el mockup (ya dicha al usuario): no hay chequeo de tope CF/DNI (tampoco en la
  venta) — se muestra el motivo de AFIP. Tipo A/B/C y PV los decide el servidor.
- ★ Harness Nest (`createImportHarness`) hoy NO arranca con módulos que traen WebsocketGateway
  (falta SocketCensusService) — el itest usa Sequelize directo + `new AfipVoucherService`.

## Desplegado hoy (todo con build SUCCESS)
- Tiendas (superadmin): orden por nombre · «W» WooCommerce en Apps.
- Sucursales: color/talle al crear y «Cambiar» en editar; columna Variantes en detalle superadmin;
  columna «Factura con»; Actions antes de Creado.
- Usuarios de Ventago (Sistema › Usuarios): roles admin/agent, confirmación con contraseña, último
  admin protegido, sesiones cerradas al cambiar.
- Facturación: Config › Facturación con tarjeta por CUIT (certificado por emisor, PV, «Lo usan»);
  selector de emisores en Editar sucursal; GET /afip/cert?issuerId; activar/revertir mueven los
  otros PV del mismo CUIT.
- POS: facturar 100 % = **Ctrl+F10** (antes Ctrl+F12). Historial de ventas: badge «F».

## Pendiente / a vigilar
- Aprobación del DDL prod de Alt+F12 (arriba).
- El usuario no vio aún en pantalla: tarjeta por CUIT, selector en Editar sucursal, Usuarios,
  creación de sucursal con variantes (no se puede loguear en prod por política de contraseñas).
- Kandente (store 31): falta crear 2 sucursales y marcar 3 como «Sin color y talle» (lo hace la tienda).
- Phase 112 (tienda pública legible por IA): sólo semilla (`.planning/phases/112-*/112-SEED.md`),
  el usuario dijo «나중에 천천히». ROADMAP.md tiene la entrada sin commitear (mezclado con WIP ajeno).
- Shaple (26): verificación real de cuenta local de cliente temporal.
- Conteo de usuarios activos excluye sólo user 1 y 61; admins/agents nuevos cuentan como empleados.
