# Métodos de pago — una sola lista (global + tienda) y duplicados unidos

2026-10-22 · mockup only (no code, DB or push yet) · `mockup.png` / `mockup.html` (example: coolsistema, store 6, real prod data)

> User: «metodos de pago 부분이 global 과 local 을 나누는 이유가 없어. 하나로 통합… 중복된 것도 수정…
> 하나로 합치면서 높이를 2배로 하고 옆에 작은 2개가 존재하게»

## Layout
- Configuración › Ventas, grid 2 × 3: **Métodos de Pago spans rows 1–2 on the left**; Descuentos in row 3.
  Vendedores, Recargos and Transportes stay on the right. The «Métodos globales» card goes away.

## Unified list
- One row per method. Columns: Nombre · Origen (Sistema/Tienda) · Opciones · Ajuste · Ventas · ¿Activado? · Actions.
- ¿Activado?
  - Sistema rows → the current hide toggle (`store_payment_methods_hidden`).
  - Tienda rows → `is_active`.
  - 🔒 rows (efectivo, reservado) cannot be turned off.
  - Existing confirmation dialogs stay: Crédito/Favor/Seña turn off a POS function.
- Edit/delete
  - Tienda rows: as today.
  - Sistema rows: name and delete are locked.
  - Per-store options/adjustment: decision D3.

## Duplicates (prod, 2026-10-22)

Store-owned rows that mean the same as a system row:
- Banco (sin detalle)
- Saldo a favor
- Tarjeta de crédito / TARJETA DE CREDITO
- Tarjeta de Débito
- MercadoPago
- Efectivo
- Reservado
- Crédito

They also exist in stores 19, 25, 26, 28, 30 and 68, not only coolsistema. They are real data, for example:
- store 25 «Tarjeta de crédito»: 23,511 sale lines.
- store 26 «Banco (sin detalle)»: 9,773 sale lines.

## Decisions
- **D1 how to merge**
  - (a) Real data merge: move `sale_payment_methods`, `credit_payments`, `online_orders` and discounts to the system id, then delete the store row.
  - (b) Display only: show them as one row, keep the ids.
  - Recommendation: **(a)**. With (b), «Saldo a favor» still isn't recognized by the POS favor function (slug `saldo-a-favor` ≠ `favor`), and the next report shows them as two again.
- **D2 scope**: coolsistema first (practice store), check the screen and reports, then the other 6 stores one at a time. Each is prod DML: show SQL and row counts and get approval.
- **D3 per-store options/adjustment** (coolsistema #54: +10 %, 2 options)
  - System rows are shared by every store, so per-store options need a new table (store_id, payment_method_id, adjust, options).
  - Alternative: keep #54 as its own store method («Tarjeta de crédito (con recargo)»).
- **D4 history**: old sales print/show the merged name (e.g. «Saldo a favor» → «Favor»). Totals don't change.
