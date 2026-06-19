# Phase 42: Retail Delivery — Despacho / Cuentas por cobrar / Historial - Pattern Map

**Mapped:** 2026-06-19
**Files analyzed:** 24 (new + modified)
**Analogs found:** 22 / 24 (2 partial-only — Pitfall-1 deliver split + CobroModal)

## File Classification

### Backend (api-ventago)

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `transportes/transportes.model.ts` | model | CRUD | `repartidores/repartidores.model.ts` | exact |
| `transportes/transportes.service.ts` | service | CRUD | `repartidores/repartidores.service.ts` | exact |
| `transportes/transportes.controller.ts` | controller | request-response | `repartidores/repartidores.controller.ts` | exact |
| `transportes/transportes.module.ts` | config | — | `repartidores/repartidores.module.ts` | exact |
| `transportes/dto/transporte.dto.ts` | dto | request-response | `repartidores/dto/repartidor.dto.ts` | exact |
| `transportes/transportes.service.spec.ts` | test | — | `repartidores/repartidores.service.spec.ts` | exact |
| `online-orders/online-order.model.ts` (MODIFY) | model | — | self (add cols) | self |
| `online-orders/online-orders.service.ts` (MODIFY) | service | event-driven (state transition) | self `runStatusTx` + Phase 40 `restaurant-delivery.service.ts` | exact |
| `online-orders/online-orders.controller.ts` (MODIFY) | controller | request-response | self + `repartidores.controller.ts` | exact |
| `online-orders/dto/ship-online-order.dto.ts` (MODIFY) | dto | request-response | self | self |
| `online-orders/online-order-sales-mirror.service.ts` (MODIFY — Pitfall 1) | service | transform | self `createMirror` L52 | partial (no analog for split) |
| `online-orders/online-orders-board.gateway.ts` (NEW) | gateway | pub-sub | `restaurant-delivery/restaurant-delivery.gateway.ts` | exact |
| `migrations/42-01-transportes.sql` | migration | — | `migrations/40-01-repartidores.sql` | exact |
| `migrations/42-02-online-orders-cols.sql` | migration | — | `migrations/39-03` + `40-01` ALTER | role-match |
| `migrations/42-03-store-config-use-envios.sql` | migration | — | `migrations/39-03-store-config-restaurant.sql` | exact |

### Frontend (ventago-app)

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `views/ventas-online/VentasOnlineView.tsx` (MODIFY — 3-tab) | component | — | self (tab structure) | self |
| `views/ventas-online/DespachoBoard.tsx` (NEW) | component | pub-sub (socket) | `views/restaurante/DeliveryBoard.tsx` | exact |
| `views/ventas-online/CuentasPorCobrarTab.tsx` (NEW) | component | CRUD | `VentasOnlineView` ReturnsTable + `RiderSettlementView.tsx` | role-match |
| `views/ventas-online/HistorialTab.tsx` (NEW) | component | CRUD | `DeliveryBoard` Historial view | role-match |
| `views/ventas-online/components/EnvioTimeline.tsx` (NEW) | component | request-response | (Phase 32 stocks-historial-drawer — see note) | partial |
| `views/ventas-online/components/CobroModal.tsx` (NEW) | component | request-response | `homes/.../PaymentSummaryModal.tsx` | partial (useSaleProducts coupling) |
| `views/configuracion/.../TransporteCard.tsx` (NEW) | component | CRUD | `views/configuracion/restaurante/RepartidoresCard.tsx` | exact |
| `hooks/api/useTransportes.ts` (NEW) | hook | CRUD | `hooks/api/useRepartidores.ts` | exact |
| `hooks/api/useDespachoBoard.ts` (NEW) | hook | CRUD | `hooks/api/useDeliveryBoard.ts` | exact |
| `configs/envioLabels.ts` (NEW) | config | — | `configs/deliveryLabels.ts` | exact |

---

## Pattern Assignments

### `transportes/transportes.model.ts` (model, CRUD)

**Analog:** `api-ventago/src/app/repartidores/repartidores.model.ts` (full file, 38 lines)

Copy 1:1. Drop `phone` (D-04 scope = `{id, storeId, name, isActive, createdAt}`). Keep explicit `field:` snake_case decorators (Phase 39/40 convention even though `underscored:true` is global).

```typescript
// repartidores.model.ts:16-37 → transportes.model.ts
@Table({ tableName: 'transportes', timestamps: true })
export class Transporte extends Model {
  @ForeignKey(() => Store)
  @Column({ field: 'store_id', type: DataType.INTEGER, allowNull: false })
  storeId: number;

  @BelongsTo(() => Store, { onDelete: 'CASCADE' })
  store: Store;

  @Column({ type: DataType.STRING(120), allowNull: false })
  name: string;

  @Column({ field: 'is_active', type: DataType.BOOLEAN, allowNull: false, defaultValue: true })
  isActive: boolean;
}
```

---

### `transportes/transportes.service.ts` (service, CRUD)

**Analog:** `api-ventago/src/app/repartidores/repartidores.service.ts` (full file, 80 lines)

Copy 1:1, removing `phone`. Critical patterns to preserve:
- **IDOR guard:** every query carries `storeId` in WHERE. `findScoped(id, storeId)` throws `NotFoundException` on cross-store miss (lines 69-79).
- **Single SELECT, no JOIN** (`findByStore`, lines 34-47) — pool 절약 (CLAUDE.md 성능 규약).
- **`activeOnly` param** (lines 38-41) — drives the despacho dropdown source (D-04 — isActive=false excluded).
- **Soft toggle only** — no hard delete; `update` patches `isActive` (lines 51-66).

```typescript
// repartidores.service.ts:34-47 — findByStore(activeOnly) → dropdown source
async findByStore(storeId: number, activeOnly = false): Promise<Transporte[]> {
  const where: Record<string, any> = { storeId };
  if (activeOnly) { where.isActive = true; }

  return this.transporteModel.findAll({ where, order: [['id', 'ASC']] });
}
```

---

### `transportes/transportes.controller.ts` (controller, request-response)

**Analog:** `api-ventago/src/app/repartidores/repartidores.controller.ts` (full file, 41 lines)

Copy 1:1. Every route `@Auth()`; `storeId` always from `@GetUser()` (never request body — IDOR).

```typescript
// repartidores.controller.ts:13-40
@Controller('transportes')
export class TransportesController {
  constructor(private readonly service: TransportesService) {}

  @Get() @Auth()
  async findAll(@GetUser() user: any) { return this.service.findByStore(user.storeId); }

  @Post() @Auth()
  async create(@Body() dto: CreateTransporteDto, @GetUser() user: any) {
    return this.service.create(user.storeId, dto);
  }

  @Put(':id') @Auth()
  async update(@Param('id') id: string, @Body() dto: UpdateTransporteDto, @GetUser() user: any) {
    return this.service.update(+id, user.storeId, dto);
  }
}
```

---

### `transportes/dto/transporte.dto.ts` (dto)

**Analog:** `api-ventago/src/app/repartidores/dto/repartidor.dto.ts` (full file)

Copy `CreateRepartidorDto`/`UpdateRepartidorDto`, drop `phone`. `name` required (`@IsString @MaxLength(120)`); `isActive?` optional on update (`@IsOptional @IsBoolean`).

---

### `transportes/transportes.module.ts` (config)

**Analog:** `api-ventago/src/app/repartidores/repartidores.module.ts`

```typescript
@Module({
  imports: [SequelizeModule.forFeature([Transporte])],
  controllers: [TransportesController],
  providers: [TransportesService],
  exports: [TransportesService, SequelizeModule],  // online-orders module consumes for name mirror
})
export class TransportesModule {}
```
Register in `app.module.ts` imports.

---

### `online-orders/online-order.model.ts` (MODIFY — add columns)

**Analog:** self (existing column block, lines 53-177)

Add the following columns matching existing decorator style. Note `transporteId` must be a **plain INTEGER column without `@ForeignKey`** — the model already documents (lines 14-16, 157-160) that `@ForeignKey` causes a NestJS boot hang from bidirectional association registration; DB-level FK lives in the migration only.

```typescript
// after existing timestamps (model already has confirmedAt/shippedAt/deliveredAt/cancelledAt L131-141)
@Column({ type: DataType.DATE, allowNull: true })
preparedAt: Date | null;        // "Listo p/ despacho" 파생 (D-03)

@Column({ type: DataType.DATE, allowNull: true })
dispatchedAt: Date | null;      // En tránsito 시점 (D-02)

// transporteId — NO @ForeignKey (boot-hang guard, see model L14-16/157-160). DB FK in migration.
@Column({ type: DataType.INTEGER, allowNull: true })
transporteId: number | null;    // D-05
```

**D-05 mirror:** keep existing `shippingCarrier` (STRING(60), L110-111) and fill it with `transporte.name` on ship. **D-03 derivation:** prefer deriving "Listo" from `preparedAt != null && dispatchedAt == null` rather than adding a `READY` enum value (Pitfall 5 — avoid enum↔CHECK desync). **Nota storage (Open Q 3):** use existing `metadata` JSONB (L127-128, `defaultValue: {}`) for a `timeline_notes` array — avoid a new table.

---

### `online-orders/online-orders.service.ts` (MODIFY — service, state transition)

**Analog:** self `runStatusTx` (L801-858) + `shipOrder`/`deliverOrder`/`cancelOrder` (L303-428)

**Pattern 1 — `runStatusTx` side-effect callback (L801-858):** lock (`t.LOCK.UPDATE`) → validate `fromStatuses` → run `sideEffect(order, t)` → save status → commit. New logic goes inside the ship/cancel side-effects. SERIALIZABLE for any tx touching stock/accounting/credit.

**RD-3/RD-4 — ship credit gate** extends existing `shipOrder` (L303-328):
```typescript
// existing shipOrder L317-323 side-effect — extend with:
(order, t) => {
  order.transporteId = dto.transporteId;
  order.shippingCarrier = transporte.name;   // D-05 하위호환 미러
  order.trackingCode = dto.trackingCode;
  order.dispatchedAt = new Date();           // 신규 타임스탬프
  // D-06: saldo = total − 기수령. >0 이면 sale_credit (외상축은 ship 에서 결정)
  //       완납이면 외상 미발생. 매출/재고 인식은 deliver 에 그대로(Pitfall 1).
  return Promise.resolve();
}
```

**RD-6 — cancel favor branch** extends existing `cancelOrder` (L378-428). The existing `wasCommitted` branch already calls `nullifyMirror` (L405-406); add the Devolver(caja 역movement) vs Favor(`appendMovement` favor_in) fork **inside** this same SERIALIZABLE tx. **Do not break the existing nullifyMirror path** (RD-12 회귀).

**Pattern 4 — emit after commit:** `runStatusTx` returns after `t.commit()` (L845). Call `boardGateway.emitEnvioUpdated(branchId, card)` **after** the returned promise resolves, never inside the tx (Phase 40 `restaurant-delivery.service.ts:180` 패턴).

**Pitfall 3 — cobro tx nesting:** cobro is a **separate operation**, not inside `runStatusTx`. `CreditPaymentService.registerPayment` opens its **own** SERIALIZABLE tx (see credit-payment below) — never wrap it in another tx.

---

### `online-orders/online-order-sales-mirror.service.ts` (MODIFY — Pitfall 1, ★ highest risk)

**Analog:** self `createMirror` (L52-159) — **no clean analog for the split**, this is the integration risk.

Current behavior (L113 `status: SaleStatus.PAID`, L148-156 `sale_payment_methods` = full `totalAmount`, and `deliverOrder` L355 `paymentStatus = PAID` unconditional). For Phase 42:
- **Keep:** `source: SaleSource.ONLINE` (L116), `activityType: SaleActivityType.SALE` (L119), idempotency via `online_order_id` UNIQUE (L57-68), dailyNumber logic (L78-89). **These are RD-10/RD-12 invariants — must not change.**
- **Change:** `deliverOrder` L355 `paymentStatus = PAID` → conditional ("잔액 0 → PAID, 잔액>0 → keep status"). `sale_payment_methods` (L148-156) should reflect **실수령액만**, with the shortfall as `sale_credit` (decided at ship per D-06).
- **Regression gate (RD-12):** 완납 주문 deliver must still produce mirror PAID + 매출 반영 exactly as today.

```typescript
// online-order-sales-mirror.service.ts:148-156 — current full-amount payment row (REPLACE with 실수령액)
if (order.paymentMethodId) {
  await SalePaymentMethod.create(
    { saleId: sale.id, paymentMethodId: order.paymentMethodId, amount: totalAmount },
    { transaction: t },
  );
}
```

---

### `online-orders/online-orders-board.gateway.ts` (NEW — gateway, pub-sub)

**Analog:** `api-ventago/src/app/restaurant-delivery/restaurant-delivery.gateway.ts` (full file, 99 lines) — copy near-verbatim, new namespace `/envios`, new event `envio_updated` (Research Open Q 2 — separate gateway for domain separation).

```typescript
// restaurant-delivery.gateway.ts:20-98 → online-orders-board.gateway.ts
@WebSocketGateway({ namespace: '/envios', cors: { origin: '*' } })
export class OnlineOrdersBoardGateway implements OnGatewayConnection {
  @WebSocketServer() server: Server;
  constructor(private readonly jwtService: JwtService,
    @InjectModel(Branch) private readonly branchModel: typeof Branch) {}

  // L32-58: handshake.auth.token JWT verify (process.env.JWT_SECRET_KEY) → disconnect on fail.
  //         store client.data.storeId for join authz.
  // L62-89: @SubscribeMessage('join') — branch must belong to user's store (IDOR guard).
  //         client.join(`branch:${branchId}`)

  emitEnvioUpdated(branchId: number, card: any): void {
    this.server?.to(`branch:${branchId}`).emit('envio_updated', card);
  }
}
```
Register provider + export in online-orders.module; inject `JwtModule`/`Branch` model (see restaurant-delivery.module for DI wiring).

---

### `migrations/42-01-transportes.sql`

**Analog:** `api-ventago/migrations/40-01-repartidores.sql` (full file)

```sql
-- 42-01-transportes.sql (PG10/15/18 — SERIAL, snake_case, TIMESTAMP WITH TIME ZONE)
BEGIN;
CREATE TABLE IF NOT EXISTS transportes (
  id SERIAL PRIMARY KEY,
  store_id INTEGER NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  name VARCHAR(120) NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_transportes_store ON transportes (store_id);
COMMIT;
```

---

### `migrations/42-02-online-orders-cols.sql`

**Analog:** `40-01` ALTER idioms + RESEARCH §Code Examples. All columns nullable → 기존 행 영향 0 (RD-12).

```sql
BEGIN;
ALTER TABLE online_orders ADD COLUMN IF NOT EXISTS prepared_at TIMESTAMP WITH TIME ZONE NULL;
ALTER TABLE online_orders ADD COLUMN IF NOT EXISTS dispatched_at TIMESTAMP WITH TIME ZONE NULL;
ALTER TABLE online_orders ADD COLUMN IF NOT EXISTS transporte_id INTEGER NULL
  REFERENCES transportes(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_online_orders_transporte ON online_orders (transporte_id);
COMMIT;
```
Run **after** 42-01 (FK dependency). Verify current columns against `.planning/intel/db-schema-tables.md:992-1029` before writing (D-02 — 추측 금지).

---

### `migrations/42-03-store-config-use-envios.sql`

**Analog:** `api-ventago/migrations/39-03-store-config-restaurant.sql` (full file) — exact pattern, `DEFAULT false` → 기존 매장 자동 OFF (회귀-0 근거 동일).

```sql
BEGIN;
ALTER TABLE store_configs ADD COLUMN IF NOT EXISTS use_envios BOOLEAN NOT NULL DEFAULT false;
COMMIT;
```

---

### `views/ventas-online/VentasOnlineView.tsx` (MODIFY — 3-tab)

**Analog:** self (Tabs block L196-205, tab state L126, content switch L248-250)

Current tabs `Pedidos/Envíos/Devoluciones` → re-target to `Despacho/Cuentas por cobrar/Historial` (D-12). **RD-12 regression gate:** for `use_envios=false` stores, the page must keep working (decide via `useStoreConfig().useEnvios` whether to show 3-tab upgrade vs legacy tabs).

```tsx
// VentasOnlineView.tsx:196-204 pattern
<Tabs value={tab} onChange={(_, v) => setTab(v as typeof tab)} sx={{ ... }}>
  <Tab label='Despacho' value='despacho' />
  <Tab label='Cuentas por cobrar' value='cobrar' />
  <Tab label='Historial' value='historial' />
</Tabs>
// content switch L248-250 pattern:
{tab === 'despacho' && <DespachoBoard />}
{tab === 'cobrar'   && <CuentasPorCobrarTab />}
{tab === 'historial'&& <HistorialTab />}
```

---

### `views/ventas-online/DespachoBoard.tsx` (NEW — component, socket pub-sub)

**Analog:** `ventago-app/src/views/restaurante/DeliveryBoard.tsx` (full, esp. L33-37 WS host, L144-174 socket effect, L177-186 grouping)

Copy the kanban + socket structure; re-map columns and namespace.
```tsx
// WS host (L33-37) — change namespace to /envios
const WS_HOST = process.env.NODE_ENV === 'development'
  ? 'http://localhost:5002/envios'
  : 'https://newapi.coolsistema.com/envios'

// COLUMNS (L46-53) → retail status machine (D-03 derivation):
const COLUMNS = [
  { key: 'nuevo', label: 'Nuevo' },              // PENDING/CONFIRMED
  { key: 'preparando', label: 'Preparando' },    // PREPARING
  { key: 'listo', label: 'Listo p/ despacho' },  // preparedAt set, not dispatched
  { key: 'en_transito', label: 'En tránsito' },  // SHIPPED
  { key: 'entregado', label: 'Entregado' },       // DELIVERED
]
```

**Socket subscribe pattern (L144-174) — copy verbatim, swap event name:**
```tsx
const socket = io(WS_HOST, { transports: ['websocket'], auth: { token: localStorage.getItem('accessToken') } })
socket.on('connect', () => socket.emit('join', { branchId }))
socket.on('envio_updated', (card) => {                 // was delivery_updated
  mutateRef.current((prev) => { /* merge by id, no full refetch */ }, false)
})
return () => { socket.off('envio_updated'); socket.disconnect() }
```
Keep `mutateRef` pattern (L136-141) so the socket effect does not reconnect on every `cards` change. Master-detail ≈75/25 with `EnvioTimeline` on the right (D-12 / Phase 32 drawer pattern).

---

### `views/ventas-online/components/TransporteCard.tsx` (NEW) — actually `views/configuracion/...`

**Analog:** `ventago-app/src/views/configuracion/restaurante/RepartidoresCard.tsx` (full, 236 lines) — copy 1:1, drop `phone` field.

Key patterns:
- **Gate (L42):** `if (!useEnvios) return null` — replace `useRestaurantMode` with `useStoreConfig().useEnvios` (new flag, mirror lines 27/42).
- **Double error surface (L45-48):** inline `Alert` + `toast.error` (feedback_error_visibility memory).
- **apiConnector.put for toggle (L79):** `apiConnector.put('/transportes/${id}', { isActive: !r.isActive })`.
- **Theme:** `NAVY_BG='#0f0f1e'`, `GOLD='#f5a623'` (L21-22), Switch gold styling (L214-217). Matches sketch-findings skill.
- Register card in `views/configuracion/...ConfigView.tsx` (see `RestauranteConfigView.tsx` for placement).

---

### `hooks/api/useTransportes.ts` (NEW)

**Analog:** `ventago-app/src/hooks/api/useRepartidores.ts` (full file)
```typescript
export interface TransporteRow { id: number; name: string; isActive: boolean }
export function useTransportes() {
  const { data, error, isLoading, mutate } = useApi<TransporteRow[]>(
    '/transportes', { dedupingInterval: 300000 },  // 5분 dedup (CLAUDE.md SWR 규약)
  )
  return { transportes: data ?? [], error, isLoading, mutate }
}
```

---

### `hooks/api/useDespachoBoard.ts` (NEW)

**Analog:** `ventago-app/src/hooks/api/useDeliveryBoard.ts` (full file) — copy `EnvioCard` interface + branchId-gated fetch. **No polling option** (D-11 — socket push only).
```typescript
export function useDespachoBoard(branchId?: number) {
  const { data, error, isLoading, mutate } = useApi<EnvioCard[]>(
    branchId ? `/online-orders/board/${branchId}` : null,  // null key → skip
  )
  return { cards: data ?? [], error, isLoading, mutate }
}
```

---

### `configs/envioLabels.ts` (NEW)

**Analog:** `ventago-app/src/configs/deliveryLabels.ts` (full file) — copy `canalLabel`/`statusLabel`/`statusColor` shape. Channels per spec §5.2: Web/WhatsApp/Teléfono/MercadoLibre/Instagram. Status labels = retail machine (Nuevo/Preparando/Listo p/ despacho/En tránsito/Entregado). Note ESLint `newline-before-return` already satisfied in analog.

---

### `views/ventas-online/components/CobroModal.tsx` (NEW — partial analog)

**Analog:** `ventago-app/src/views/homes/components/ProductList/components/PaymentSummaryModal.tsx` — **NOT directly reusable** (D-09 confirmed).

Coupling found (head, line ~57): `const { setPaymentMethods, paymentMethods, selectedClient } = useSaleProducts()` — bound to POS sale context. Conclusion:
- **Reuse (extract/copy):** split UI layout, payment-method row, "Aplicar saldo a favor" chip pattern, credito virtual-slug handling (head doc L SLUG_CREDITO etc).
- **New (delivery-specific):** `saldoPendiente` (외상) context, `payment_in` vs `SalePaymentMethod` branch, `registerPayment` wiring. Inject dependencies via **props** instead of `useSaleProducts`.
- Payment methods per D-09: Efectivo · Transferencia · Cheque(banco/número) · Tarjeta · QR (existing store `PaymentMethod`).

---

### `views/ventas-online/CuentasPorCobrarTab.tsx` + `HistorialTab.tsx` (NEW — role-match)

**Analogs:** table/empty/loading structure from `VentasOnlineView` `ReturnsTable` (L433-483); CxC client-balance UI references `views/restaurante/components/RiderSettlementView.tsx`; Historial date-range filter from `DeliveryBoard` Historial view (L86-108 `fromDate/toDate/toExclusive` + `useDeliveryHistory`). Cuentas por cobrar lists only `saldo>0` in red (D-07/spec §5.5); StoreClient.balance shown per client.

---

### `views/ventas-online/components/EnvioTimeline.tsx` (NEW — partial)

**Analog:** Phase 32 stocks-historial-drawer (right ≈25% master-detail, cited in CONTEXT D-12 / spec §5.1) — locate via Glob if planner needs concrete excerpt; not read here. Merge `orderedAt/preparedAt/dispatchedAt/deliveredAt` + payment events (`SalePaymentMethod` + `CreditLedger`) chronologically (CONTEXT Claude's Discretion / spec §5.3). Action buttons 🎫 Ticket / 🧾 Recibo use `print.service.emitPrintTemp` (see restaurant-delivery.service.ts:166 fire-and-forget pattern).

---

## Shared Patterns

### Credit ledger — append-only, external tx required (D-06, D-08)
**Source:** `api-ventago/src/app/credit/services/credit-ledger.service.ts:91-149`
**Apply to:** `online-orders.service` ship credit gate (sale_credit), cancel→favor (favor_in)
```typescript
// appendMovement REQUIRES caller's transaction (throws if missing — L109-113).
// Locks store_clients FOR UPDATE (L133-138). sale_credit/favor_apply REQUIRE saleId (L120-131).
await this.creditLedgerService.appendMovement({
  storeId, storeClientId,
  movementType: 'sale_credit',   // bucket=credito, + (MOVEMENT_SIGN L62-74)
  amount: saldoPendiente,
  saleId: mirrorSale.id,         // venta 링크 필수 (DB CHECK)
  branchId, userId,
  note: `Envío #${order.orderNumber} despachado con saldo`,
  transaction: t,                // ★ 외부 tx 주입 — never call without it
});
```
**Anti-pattern:** never UPDATE/DELETE a ledger row (append-only); 정정은 reverse movement only.

### Credit payment — FIFO, OWN tx (D-07 cobro)
**Source:** `api-ventago/src/app/credit/services/credit-payment.service.ts:70-80`
**Apply to:** cobro that pays down 외상
```typescript
// registerPayment opens its OWN SERIALIZABLE tx (L73-75) — do NOT nest inside runStatusTx (Pitfall 3).
// paymentKind: 'credit_payment' = FIFO sale_credit → payment_in (parent_ledger_id), 잔여 → favor_in.
await this.creditPaymentService.registerPayment({
  storeId, storeClientId,
  paymentKind: 'credit_payment',
  totalAmount: cobroAmount,
  paymentMethodId, /* receiptNo, branchId, userId, note */
});
```

### caja movement (D-10 cobro→caja)
**Source:** `api-ventago/src/app/box-operation/box-operation.service.ts:16-32`
**Apply to:** each cobro (신규 결제분) → box movement so control-de-caja 마감 일치
```typescript
await this.boxOperationService.addOperation(
  { cashRegisterId, userId, terminalId, amount, type, executionType, description },
  t,  // optional tx
);
```
**Pitfall 4:** 신규 결제분 cobro requires an open caja (closingTime=null cashRegister). Borrow Phase 40 "Abrí la caja antes" guard.

### Multitenant / IDOR
**Source:** `repartidores.service.ts:69-79` (findScoped NotFound) + `repartidores.controller.ts` (storeId from `@GetUser`)
**Apply to:** all transportes + online-orders board endpoints. Gateway join authz: `restaurant-delivery.gateway.ts:62-89` (branch must belong to user's store).

### use_envios gate (config flag)
**Source:** `storeConfig.model.ts:70-71` (useRestaurantMode) + `StoreConfigContext.tsx:18-80` (state/default/fetch mapping) + `RepartidoresCard.tsx:42` (`if (!useRestaurantMode) return null`)
**Apply to:** add `useEnvios` to StoreConfig model, context state/default(false)/fetch-mapping, and gate TransporteCard + 3-tab upgrade.

### Sales mirror invariants (RD-10/RD-12 — must NOT change)
**Source:** `online-order-sales-mirror.service.ts:116,119` — `source: SaleSource.ONLINE`, `activityType: SaleActivityType.SALE`, idempotency via online_order_id UNIQUE (L57-68). 매출/재고 보고서 자동 반영.

---

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `online-order-sales-mirror.service.ts` payment-split branch | service | transform | No existing code splits mirror payment into 실수령 + sale_credit — this is the Pitfall-1 novel logic; planner derives from D-06/Phase 40 D-01 principle, not a copy |
| `CobroModal.tsx` delivery-saldo wiring | component | request-response | PaymentSummaryModal is POS-coupled (useSaleProducts); only UI fragments reusable, the saldo/payment_in branch is new |

---

## Metadata

**Analog search scope:** `api-ventago/src/app/{repartidores,restaurant-delivery,online-orders,credit,box-operation,store/config}`, `api-ventago/migrations/{39,40}-*`, `ventago-app/src/{views/restaurante,views/ventas-online,views/configuracion/restaurante,views/homes/...,hooks/api,configs,context}`
**Files scanned:** ~24 read in full or in load-bearing sections
**Pattern extraction date:** 2026-06-19
