# Phase 40: Restaurante Delivery — Despacho y Cobro - Pattern Map

**Mapped:** 2026-06-16
**Files analyzed:** 24 (new/modified)
**Analogs found:** 23 / 24

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `api-ventago/migrations/40-01-repartidores.sql` | migration | CRUD | `migrations/39-01-restaurant-tables.sql` + `restaurant-elements.sql` | exact |
| `api-ventago/migrations/40-02-restaurant-deliveries.sql` | migration | CRUD | `migrations/39-01-restaurant-tables.sql` (cyclic FK note) | exact |
| `api-ventago/migrations/40-03-rider-settlements.sql` | migration | CRUD | `migrations/39-01-restaurant-tables.sql` | exact |
| `api-ventago/migrations/40-04-sales-source-delivery.sql` | migration | transform | `migrations/phase28-full-online-integration.sql` L205-219 | exact |
| `.../app/repartidores/repartidores.model.ts` | model | CRUD | `restaurant-tables/restaurant-tables.model.ts` | exact |
| `.../app/repartidores/repartidores.service.ts` | service | CRUD | `restaurant-tables/restaurant-tables.service.ts` | exact |
| `.../app/repartidores/repartidores.controller.ts` | controller | request-response | `restaurant-tables/restaurant-tables.controller.ts` | exact |
| `.../app/repartidores/dto/repartidor.dto.ts` | dto | transform | `restaurant-tables/dto/restaurant-table.dto.ts` | exact |
| `.../app/repartidores/repartidores.module.ts` | module | — | `restaurant-tables/restaurant-tables.module.ts` | exact |
| `.../app/restaurant-delivery/restaurant-delivery.model.ts` | model | CRUD | `restaurant-tables.model.ts` + `sales.model.ts` (enum↔CHECK, FK constraints:false) | exact |
| `.../app/restaurant-delivery/restaurant-delivery.service.ts` | service | event-driven | `sales/restaurant-sale/restaurant-sale.service.ts` | exact |
| `.../app/restaurant-delivery/restaurant-delivery.controller.ts` | controller | request-response | `sales/restaurant-sale/restaurant-sale.controller.ts` | exact |
| `.../app/restaurant-delivery/dto/*.dto.ts` | dto | transform | `restaurant-sale/dto/restaurant-sale.dto.ts` + `restaurant-table.dto.ts` | exact |
| `.../app/restaurant-delivery/restaurant-delivery.gateway.ts` | gateway | pub-sub | `print/print.gateway.ts` (namespace + `branch:{id}` room) | role-match |
| `.../app/rider-settlement/rider-settlement.model.ts` | model | CRUD | `restaurant-tables.model.ts` + `sales-payment-method.model.ts` (HasMany item) | exact |
| `.../app/rider-settlement/rider-settlement.service.ts` | service | CRUD | `restaurant-sale.service.ts` (`recordBoxOperation`) + `box-operation.service.ts` | exact |
| `.../app/rider-settlement/rider-settlement.controller.ts` | controller | request-response | `restaurant-sale.controller.ts` | exact |
| `.../app/restaurant-delivery/delivery-payout-csv.service.ts` | service | file-I/O | `restaurant-sale.service.ts` (TX pattern) + MinioService | role-match |
| `ventago-app/src/hooks/api/useRepartidores.ts` | hook | request-response | `hooks/api/useRestaurantTables.ts` | exact |
| `ventago-app/src/hooks/api/useDeliveryBoard.ts` | hook | request-response | `hooks/api/useSalonSummary.ts` | exact |
| `ventago-app/src/views/restaurante/DeliveryBoard.tsx` | component | event-driven | `views/restaurante/SalonView.tsx` | role-match |
| `ventago-app/src/views/restaurante/components/NuevoPedidoModal.tsx` | component | request-response | `views/restaurante/components/OrderModal.tsx` | exact |
| `ventago-app/src/views/restaurante/components/RiderSettlementView.tsx` | component | CRUD | `views/restaurante/SalonView.tsx` (SWR + apiConnector) | role-match |
| `ventago-app/src/views/configuracion/restaurante/RepartidoresCard.tsx` | component | CRUD | `views/configuracion/restaurante/SalonEditor.tsx` | role-match |

## Pattern Assignments

### `migrations/40-01-repartidores.sql` (migration, CRUD)

**Analog:** `migrations/restaurant-elements.sql` (cleanest single-table idempotent template)

**Full idempotent table + CHECK + index pattern** (restaurant-elements.sql L17-56):
```sql
BEGIN;

CREATE TABLE IF NOT EXISTS repartidores (
  id          SERIAL PRIMARY KEY,                                   -- NOT GENERATED AS IDENTITY (PG10)
  store_id    INTEGER NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  name        VARCHAR(120) NOT NULL,
  phone       VARCHAR(40) NULL,
  is_active   BOOLEAN NOT NULL DEFAULT TRUE,
  created_at  TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_repartidores_store ON repartidores (store_id);

COMMIT;
```

**Pattern rules to replicate:**
- `SERIAL` not `GENERATED AS IDENTITY` (PG10 compat — Phase 26/29 decision)
- `TIMESTAMP WITH TIME ZONE` for all timestamps
- `CREATE TABLE IF NOT EXISTS` + `CREATE INDEX IF NOT EXISTS` for idempotency
- `store_id INTEGER NOT NULL REFERENCES stores(id) ON DELETE CASCADE` (multi-tenant, snake_case)

---

### `migrations/40-02-restaurant-deliveries.sql` (migration, CRUD)

**Analog:** `migrations/39-01-restaurant-tables.sql` (cyclic-FK ordering note L6-9) + `restaurant-elements.sql` (CHECK guard pattern)

**enum CHECK guard via DO block** (39-01-restaurant-tables.sql L43-67):
```sql
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conname = 'chk_rd_status' AND conrelid = 'restaurant_deliveries'::regclass
  ) THEN
    ALTER TABLE restaurant_deliveries ADD CONSTRAINT chk_rd_status
      CHECK (status IN ('nuevo','en_cocina','listo','en_camino','entregado','por_cobrar','conciliacion','liquidado','cancelado'));
  END IF;
  -- repeat block for chk_rd_tipo (delivery|takeaway), chk_rd_canal (whatsapp|telefono|app|otro),
  -- chk_rd_payment_mode (efectivo|qr|app)
END$$;
```

**Table essentials** (mirror 39-01 columns + Phase 40 fields). `sale_id` 1:1 enforced via partial unique index (sales.model.ts:182 onlineOrderId precedent + phase28 L232):
```sql
CREATE TABLE IF NOT EXISTS restaurant_deliveries (
  id              SERIAL PRIMARY KEY,
  store_id        INTEGER NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  branch_id       INTEGER NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  sale_id         INTEGER NOT NULL REFERENCES sales(id) ON DELETE CASCADE,
  status          VARCHAR(20) NOT NULL DEFAULT 'nuevo',
  tipo            VARCHAR(16) NOT NULL DEFAULT 'delivery',
  canal           VARCHAR(16) NOT NULL DEFAULT 'whatsapp',
  client_id       INTEGER NULL REFERENCES clients(id) ON DELETE SET NULL,  -- verify FK target in db-schema-fks.md
  customer_name   VARCHAR(120) NULL,
  customer_phone  VARCHAR(40) NULL,
  address         TEXT NULL,
  payment_mode    VARCHAR(16) NOT NULL DEFAULT 'efectivo',
  repartidor_id   INTEGER NULL REFERENCES repartidores(id) ON DELETE SET NULL,
  ordered_at      TIMESTAMP WITH TIME ZONE NULL,
  ready_at        TIMESTAMP WITH TIME ZONE NULL,
  dispatched_at   TIMESTAMP WITH TIME ZONE NULL,
  delivered_at    TIMESTAMP WITH TIME ZONE NULL,
  settled_at      TIMESTAMP WITH TIME ZONE NULL,
  external_ref    VARCHAR(120) NULL,
  metadata        JSONB NULL,
  created_at      TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- 1:1 sale↔delivery (phase28 sales_online_order_uniq precedent, L232)
CREATE UNIQUE INDEX IF NOT EXISTS idx_rd_sale_uniq ON restaurant_deliveries (sale_id);
CREATE INDEX IF NOT EXISTS idx_rd_branch_status ON restaurant_deliveries (branch_id, status);
CREATE INDEX IF NOT EXISTS idx_rd_store ON restaurant_deliveries (store_id);
```
**Note:** verify `clients` PK column name in `.planning/intel/db-schema-fks.md` before specifying the FK target (model uses `clientId` BelongsTo `Clients`).

---

### `migrations/40-04-sales-source-delivery.sql` (migration, transform)

**Analog:** `migrations/phase28-full-online-integration.sql` L205-219 — this is the EXACT precedent for extending the `sales.source` CHECK.

**CHECK constraint swap (must DROP old + ADD new — `IF NOT EXISTS` doesn't apply to CHECK)** (adapt phase28 L209-220):
```sql
BEGIN;

DO $$
BEGIN
  -- drop existing source CHECK if present (it lists only pos/online/factura)
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'sales_source_check' AND conrelid = 'sales'::regclass
  ) THEN
    ALTER TABLE sales DROP CONSTRAINT sales_source_check;
  END IF;

  ALTER TABLE sales
    ADD CONSTRAINT sales_source_check
    CHECK (source IN ('pos','online','factura','delivery'));
END $$;

COMMIT;
```
**Critical:** the constraint name is `sales_source_check` (phase28 L214). Drop-then-add inside the same DO block keeps it idempotent and PG10/15/18 safe.

---

### `app/repartidores/repartidores.model.ts` (model, CRUD)

**Analog:** `restaurant-tables/restaurant-tables.model.ts`

**Store-scoped model + enum-free simple table** (restaurant-tables.model.ts L33-47):
```typescript
@Table({ tableName: 'repartidores', timestamps: true })
export class Repartidor extends Model {
  @ForeignKey(() => Store)
  @Column({ field: 'store_id', type: DataType.INTEGER, allowNull: false })
  storeId: number;

  @BelongsTo(() => Store, { onDelete: 'CASCADE' })
  store: Store;

  @Column({ type: DataType.STRING(120), allowNull: false })
  name: string;

  @Column({ type: DataType.STRING(40), allowNull: true })
  phone?: string;

  @Column({ field: 'is_active', type: DataType.BOOLEAN, allowNull: false, defaultValue: true })
  isActive: boolean;
}
```
**Rule:** `field:` explicit snake_case on every column (project relies on `underscored:true` but Phase 39 models declare `field:` explicitly — match that).

---

### `app/repartidores/repartidores.service.ts` (service, CRUD)

**Analog:** `restaurant-tables/restaurant-tables.service.ts` — copy the store-scoped CRUD + `findScoped` IDOR-guard verbatim.

**Store-scoped query + soft deactivate (NOT delete — REQ-1 preserves settlement history)** (restaurant-tables.service.ts L28-36, L59-80, L121-131):
```typescript
async findByStore(storeId: number, activeOnly = false): Promise<Repartidor[]> {
  const where: any = { storeId };
  if (activeOnly) where.isActive = true;

  return this.repartidorModel.findAll({ where, order: [['id', 'ASC']] });
}

async update(id: number, storeId: number, dto: UpdateRepartidorDto): Promise<Repartidor> {
  const row = await this.findScoped(id, storeId);   // NotFound = IDOR guard
  const patch: Record<string, any> = {};
  if (dto.name !== undefined) patch.name = dto.name;
  if (dto.phone !== undefined) patch.phone = dto.phone;
  if (dto.isActive !== undefined) patch.isActive = dto.isActive;   // soft toggle
  await row.update(patch);

  return row;
}

private async findScoped(id: number, storeId: number): Promise<Repartidor> {
  const row = await this.repartidorModel.findOne({ where: { id, storeId } });
  if (!row) throw new NotFoundException(`Repartidor con ID ${id} no encontrado`);

  return row;
}
```
**Rule:** REQ-1 — do NOT `destroy()`; deactivation = `isActive=false`. `findByStore(storeId, true)` feeds the dispatch dropdown (activeOnly).

---

### `app/repartidores/repartidores.controller.ts` (controller, request-response)

**Analog:** `restaurant-tables/restaurant-tables.controller.ts` — `@Auth()` on every route, `user.storeId` scoping.

**Auth + storeId scoping pattern** (restaurant-tables.controller.ts L22-46):
```typescript
@Controller('repartidores')
export class RepartidoresController {
  constructor(private readonly service: RepartidoresService) {}

  @Get()
  @Auth()
  async findAll(@GetUser() user: any) {
    return this.service.findByStore(user.storeId);
  }

  @Post()
  @Auth()
  async create(@Body() dto: CreateRepartidorDto, @GetUser() user: any) {
    return this.service.create(user.storeId, dto);
  }

  @Put(':id')
  @Auth()
  async update(@Param('id') id: string, @Body() dto: UpdateRepartidorDto, @GetUser() user: any) {
    return this.service.update(+id, user.storeId, dto);
  }
}
```
**Imports:** `import { Auth } from '../auth/decorators/auth.decorator'` + `import { GetUser } from '../auth/decorators/get-user.decorator'`.

---

### `app/repartidores/dto/repartidor.dto.ts` (dto, transform)

**Analog:** `restaurant-tables/dto/restaurant-table.dto.ts` — `class-validator` decorators, optional partial-update DTO.

**Pattern** (restaurant-table.dto.ts L15-29, L62-76):
```typescript
export class CreateRepartidorDto {
  @IsString() @MaxLength(120) name: string;
  @IsOptional() @IsString() @MaxLength(40) phone?: string;
}

export class UpdateRepartidorDto {
  @IsOptional() @IsString() @MaxLength(120) name?: string;
  @IsOptional() @IsString() @MaxLength(40) phone?: string;
  @IsOptional() @IsBoolean() isActive?: boolean;
}
```

---

### `app/repartidores/repartidores.module.ts` (module)

**Analog:** `restaurant-tables/restaurant-tables.module.ts` (verbatim shape):
```typescript
@Module({
  imports: [SequelizeModule.forFeature([Repartidor])],
  controllers: [RepartidoresController],
  providers: [RepartidoresService],
  exports: [RepartidoresService, SequelizeModule],   // RiderSettlementService consumes Repartidor
})
export class RepartidoresModule {}
```

---

### `app/restaurant-delivery/restaurant-delivery.model.ts` (model, CRUD)

**Analog:** `restaurant-tables.model.ts` (table shape) + `sales.model.ts` L37-54 (enum↔DB CHECK sync) + L218-223 (`constraints:false` BelongsTo for cyclic-FK avoidance).

**Enum mirrored to DB CHECK** (sales.model.ts L37-41 precedent):
```typescript
// DB CHECK chk_rd_status 와 동기화
export enum DeliveryStatus {
  NUEVO = 'nuevo', EN_COCINA = 'en_cocina', LISTO = 'listo',
  EN_CAMINO = 'en_camino', ENTREGADO = 'entregado', POR_COBRAR = 'por_cobrar',
  CONCILIACION = 'conciliacion', LIQUIDADO = 'liquidado', CANCELADO = 'cancelado',
}
export enum DeliveryTipo { DELIVERY = 'delivery', TAKEAWAY = 'takeaway' }
export enum PaymentMode { EFECTIVO = 'efectivo', QR = 'qr', APP = 'app' }
```

**Sale 1:1 BelongsTo without cyclic FK constraint** (sales.model.ts L218-223 pattern):
```typescript
@ForeignKey(() => Sale)
@Column({ field: 'sale_id', type: DataType.INTEGER, allowNull: false })
saleId: number;

@BelongsTo(() => Sale, { foreignKey: 'saleId', constraints: false })
sale?: Sale;

@Column({ field: 'metadata', type: DataType.JSONB, allowNull: true })
metadata?: Record<string, any>;
```
**Rule:** all timestamps (`ordered_at`/`ready_at`/`dispatched_at`/`delivered_at`/`settled_at`) declared with explicit `field:` snake_case + `DataType.DATE` + `allowNull:true`, mirroring sales.model.ts L226-239.

---

### `app/restaurant-delivery/restaurant-delivery.service.ts` (service, event-driven)

**Analog:** `sales/restaurant-sale/restaurant-sale.service.ts` — THE primary pattern source. Copy the single-TX sale↔meta sync, branchId-direct resolution, comanda emit, and box-operation via service.

**Order intake = single TX Sale(DRAFT) + RestaurantDelivery + comanda emit** (restaurant-sale.service.ts L80-150 → adapt for delivery, REQ-2/REQ-5):
```typescript
return this.sequelize.transaction(async (t) => {
  // 1. Sale 생성 — source='delivery', activityType='sale', tableId=null (매출 무오염)
  const sale = await this.saleModel.create({
    status: SaleStatus.DRAFT,
    activityType: SaleActivityType.SALE,
    source: SaleSource.DELIVERY,       // ← Phase 40 신규 enum 값
    tableId: null,
    storeId, userId,
    orderedAt: new Date(),
    saleDate: new Date(),
  } as any, { transaction: t });

  // 2. items bulkCreate + totalAmount = Σ subtotal (server truth, L155-162)
  // 3. RestaurantDelivery 생성 (saleId UNIQUE, status=en_cocina)
  const delivery = await this.deliveryModel.create({
    storeId, branchId: dto.branchId, saleId: sale.id,
    status: DeliveryStatus.EN_COCINA, tipo: dto.tipo, canal: dto.canal,
    paymentMode: dto.paymentMode, customerName: dto.customerName,
    customerPhone: dto.customerPhone, address: dto.address ?? null,
    repartidorId: dto.repartidorId ?? null, externalRef: dto.externalRef ?? null,
    orderedAt: new Date(),
  } as any, { transaction: t });

  // 4. comanda 출력 — 기존 emitPrintTemp 직접 재사용 (branchId 직접 해결, Pitfall 4)
  this.printService.emitPrintTemp(dto.branchId, {
    kind: 'comanda', saleId: sale.id, delivery: true,
    customerName: dto.customerName, address: dto.address, items: created.map(...),
  });

  // 5. 보드 푸시 — card-level payload emit (D-04)
  this.deliveryGateway.emitDeliveryUpdated(dto.branchId, this.toCard(delivery, sale));

  return delivery;
});
```

**State transition = timestamp record + card emit** (restaurant-sale.service.ts L321-368 markTiming precedent):
```typescript
async transition(storeId, deliveryId, toStatus, opts): Promise<RestaurantDelivery> {
  return this.sequelize.transaction(async (t) => {
    const d = await this.deliveryModel.findOne({ where: { id: deliveryId, storeId }, transaction: t });
    if (!d) throw new NotFoundException('Pedido no encontrado');

    // GUARD: En camino 전이는 repartidorId 필수 (REQ-6 AC)
    if (toStatus === DeliveryStatus.EN_CAMINO && !d.repartidorId && !opts?.repartidorId)
      throw new BadRequestException('Asigná un repartidor antes de despachar');

    const patch: any = { status: toStatus };
    if (toStatus === DeliveryStatus.LISTO) patch.readyAt = new Date();
    if (toStatus === DeliveryStatus.EN_CAMINO) { patch.dispatchedAt = new Date(); if (opts?.repartidorId) patch.repartidorId = opts.repartidorId; }
    if (toStatus === DeliveryStatus.ENTREGADO) patch.deliveredAt = new Date();
    await d.update(patch, { transaction: t });

    // Entregado → Sale DRAFT→PAID + SalePaymentMethod INSERT (D-01, 매출 즉시 인식)
    if (toStatus === DeliveryStatus.ENTREGADO) await this.settleSaleOnDelivery(d, t);

    this.deliveryGateway.emitDeliveryUpdated(d.branchId, this.toCard(d));
    return d;
  });
}
```

**Entregado → SalePaymentMethod (single payment, no split — D-01)** (restaurant-sale.service.ts settleSale L587-617 pattern, simplified):
```typescript
// efectivo → Sale PAID 이지만 box movement 는 안 함(라이더 정산까지 Por cobrar) — D-01/D-05 핵심 갭
// qr/app → Sale PAID + (qr=webhook 자동, app=Conciliación)
await this.pmModel.create({
  saleId: d.saleId, paymentMethodId: mappedMethodId, optionId: optId ?? null,
  amount: Number(sale.totalAmount),
} as any, { transaction: t });
await sale.update({ status: SaleStatus.PAID, closedAt: new Date() }, { transaction: t });
// efectivo: delivery.status → POR_COBRAR (NOT box-op here); qr: liquidado; app: conciliacion
```
**Cancel (D-02):** DRAFT → soft-delete sale + stock restore + `delivery.status=cancelado`; PAID → reuse existing `nullifySale` flow (Phase 29/35). Do NOT reimplement nullify.

**Constructor DI** mirrors restaurant-sale.service.ts L48-65: `@InjectModel(Sale)`, `@InjectModel(SaleItem)`, `@InjectModel(SalePaymentMethod)`, new `@InjectModel(RestaurantDelivery)`, `@InjectConnection() sequelize`, `PrintService`, `BoxOperationService`, new `RestaurantDeliveryGateway`.

---

### `app/restaurant-delivery/restaurant-delivery.gateway.ts` (gateway, pub-sub)

**Analog:** `print/print.gateway.ts` — copy the `@WebSocketGateway(namespace)` + `server.to(\`branch:${id}\`).emit(...)` room pattern (D-03/D-04). NEW namespace `/restaurant`, do NOT extend `/print-agent`.

**Gateway shell + room join** (print.gateway.ts L17-19, L81; print.service.ts L32-38):
```typescript
@WebSocketGateway({ namespace: '/restaurant', cors: { origin: '*' } })
export class RestaurantDeliveryGateway implements OnGatewayConnection {
  @WebSocketServer() server: Server;

  async handleConnection(client: Socket) {
    // 인증: print.gateway 의 API-Key 검증과 달리 JWT/session token (브라우저 보드 클라이언트)
    // client.handshake.auth.token = accessToken → validate → client.join(`branch:${branchId}`)
  }

  // 카드 payload emit (전체 재조회 회피, pool 절약 — D-04)
  emitDeliveryUpdated(branchId: number, card: any): void {
    try {
      this.server?.to(`branch:${branchId}`).emit('delivery_updated', card);
    } catch (err) {
      console.error('[RestaurantDeliveryGateway] emit 실패:', err);
    }
  }
}
```
**Difference from analog:** print.gateway authenticates Electron API-Key (branch_agents); this gateway authenticates browser JWT/sessionToken. Room key `branch:{id}` is identical. The comanda print still goes through `printService.emitPrintTemp` (separate channel — do not move it here).

---

### `app/rider-settlement/rider-settlement.model.ts` (model, CRUD)

**Analog:** `restaurant-tables.model.ts` (table) + `sales.model.ts` L241-251 (`@HasMany` for items) + `sales-payment-method.model.ts` (child-row model).

**Parent + child models** (HasMany pattern from sales.model.ts L241):
```typescript
@Table({ tableName: 'rider_settlements', timestamps: true })
export class RiderSettlement extends Model {
  @ForeignKey(() => Store) @Column({ field: 'store_id', ... }) storeId: number;
  @ForeignKey(() => Repartidor) @Column({ field: 'repartidor_id', ... }) repartidorId: number;
  @Column({ field: 'box_session_id', type: DataType.INTEGER, allowNull: true }) boxSessionId?: number; // cash_registers.id
  @Column({ field: 'expected_cash', type: DataType.FLOAT, defaultValue: 0 }) expectedCash: number;
  @Column({ field: 'received_cash', type: DataType.FLOAT, defaultValue: 0 }) receivedCash: number;
  @Column({ field: 'difference', type: DataType.FLOAT, defaultValue: 0 }) difference: number;
  @Column({ type: DataType.STRING(16), defaultValue: 'open' }) status: string; // open|partial|closed
  @HasMany(() => RiderSettlementItem) items: RiderSettlementItem[];
}
```
**Note:** `boxSessionId` references `cash_registers.id` (confirmed schema: `cash_registers` has `id`, `terminal_id`, `user_id`, `closing_time`, `store_id`). It is the open cash register session.

---

### `app/rider-settlement/rider-settlement.service.ts` (service, CRUD → caja)

**Analog:** `restaurant-sale.service.ts` `recordBoxOperation` L650-675 + `box-operation.service.ts` `addOperation` L16-32.

**Rendición → box movement (D-05/D-06: STRICTER than Phase 39 — block if no open caja)** (adapt recordBoxOperation L650-675):
```typescript
async registerRendition(storeId, userId, settlementId): Promise<RiderSettlement> {
  return this.sequelize.transaction(async (t) => {
    const settlement = await this.settlementModel.findOne({
      where: { id: settlementId, storeId }, transaction: t,
    });
    if (!settlement) throw new NotFoundException('Liquidación no encontrada');

    // D-06: 열린 cashRegister(closing_time=null) 필수 — 없으면 정산 차단 (Phase 39 와 달리 엄격)
    const cashRegister = await this.cashRegisterModel.findOne({
      where: { userId, closingTime: null }, transaction: t,
    });
    if (!cashRegister)
      throw new BadRequestException('Abrí la caja antes de registrar la rendición');

    // rendido 처리된 현금 주문 합계 = expectedCash a rendir
    const items = await this.itemModel.findAll({
      where: { settlementId: settlement.id, rendido: true }, transaction: t,
    });
    const total = items.reduce((a, it) => a + Number(it.amount), 0);

    // D-05: 집계 box movement 1건 (주문당 소액 다수 회피)
    await this.boxOperationService.addOperation({
      cashRegisterId: cashRegister.id, userId, terminalId: cashRegister.terminalId,
      amount: total, type: 'venta', executionType: 'automatico',
      description: `Rendición repartidor #${settlement.repartidorId}`,
    }, t);

    // rendido 주문만 RestaurantDelivery.status=liquidado + settledAt (REQ-7)
    await this.deliveryModel.update(
      { status: DeliveryStatus.LIQUIDADO, settledAt: new Date() },
      { where: { id: items.map(i => i.restaurantDeliveryId) }, transaction: t },
    );

    await settlement.update({ receivedCash: total, status: 'closed', closedAt: new Date() }, { transaction: t });
    return settlement;
  });
}
```
**Critical difference from Phase 39:** restaurant-sale.service.ts L661 *skips* box-op when no register; here (D-06) you *throw* — cash must hit caja to keep control-de-caja reconciled.

---

### `app/restaurant-delivery/delivery-payout-csv.service.ts` (service, file-I/O)

**Analog:** `restaurant-sale.service.ts` (TX) + MinioService (`MinioService.uploadFile(file, fileName)` → `{ fileName }`, per CLAUDE.md).

**Pattern (REQ-9, D-07/D-08):**
- `MinioService.uploadFile(csvFile, fileName)` — store original payout CSV (audit trail, D-07)
- Parse fixed-template CSV (externalRef + amount columns, D-08)
- Match `restaurant_deliveries.external_ref` exactly + exact amount equality (NO tolerance — out of scope)
- Matched → `status=conciliacion`→conciliado auto; unmatched/amount-mismatch → flagged red
- Add `MinioModule` to this module's `imports` (CLAUDE.md MinIO rule)

---

### `hooks/api/useRepartidores.ts` (hook, request-response)

**Analog:** `hooks/api/useRestaurantTables.ts` (verbatim shape)
```typescript
import { useApi } from 'src/hooks/useApi'

export interface RepartidorRow { id: number; name: string; phone: string | null; isActive: boolean }

export function useRepartidores() {
  const { data, error, isLoading, mutate } = useApi<RepartidorRow[]>(
    '/repartidores',
    { dedupingInterval: 300000 },   // 5분 dedup (CLAUDE.md SWR 규약)
  )

  return { repartidores: data ?? [], error, isLoading, mutate }
}
```

---

### `hooks/api/useDeliveryBoard.ts` (hook, request-response)

**Analog:** `hooks/api/useSalonSummary.ts` — typed interface + branch-keyed `useApi`. NO `refreshInterval` (board is Socket.io push, not polling — SPEC constraint). `mutate` is called on `delivery_updated` socket event to merge card payload.
```typescript
export function useDeliveryBoard(branchId?: number) {
  const { data, error, isLoading, mutate } = useApi<DeliveryCard[]>(
    branchId ? `/restaurant-delivery/board/${branchId}` : null,
    // no refreshInterval — Socket.io push via /restaurant gateway (D-03)
  )

  return { cards: data ?? [], error, isLoading, mutate }
}
```

---

### `views/restaurante/DeliveryBoard.tsx` (component, event-driven)

**Analog:** `views/restaurante/SalonView.tsx` — `BranchContext` + `useAuth` + branchId fallback (L17-21), SWR hook + `useMemo` derived maps (L31-68), MUI loading/Alert states. Kanban columns replace salón canvas.

**Branch resolution + Socket.io subscription** (SalonView.tsx L16-26 + new socket effect):
```typescript
const { user } = useAuth()
const { selectedBranchId } = useContext(BranchContext)
const branchId = selectedBranchId ?? (user as any)?.branchId ?? undefined
const { cards, isLoading, error, mutate } = useDeliveryBoard(branchId)

// Socket.io /restaurant gateway 구독 — delivery_updated 카드 병합 (D-04, 폴링 아님)
useEffect(() => {
  if (!branchId) return
  const socket = io(`${HOST}/restaurant`, { auth: { token: localStorage.getItem('accessToken') } })
  socket.emit('join', { branchId })
  socket.on('delivery_updated', (card) => { mutate(/* merge card */, false) })

  return () => { socket.disconnect() }
}, [branchId, mutate])
```
**Entry point (Claude's Discretion):** add as tab/segment beside SalonView; use `next/dynamic(() => import(...), { ssr: false })` per CLAUDE.md code-splitting. Columns: `Nuevo · En cocina · Listo · En camino · Por cobrar` (+ `Conciliación` for app). `Por cobrar` styled red (control core). `Listo` card "Asignar" → activo repartidor dropdown (`useRepartidores` filtered isActive).

---

### `views/restaurante/components/NuevoPedidoModal.tsx` (component, request-response)

**Analog:** `views/restaurante/components/OrderModal.tsx` — copy the menu picker (category tabs + `pickMenuPrice` L36-42 + CartLine L44-49), `useSellers({ excludeAdmins })`, `useCategoriesByStore`, `useFormatPrice`, `apiConnector.post`, `toast` error handling.

**Reuse the exact menu-picker block** (OrderModal.tsx L34-49, L88-90). Add on top:
- Tipo toggle (Delivery=address+rider required / Para llevar=both omitted — REQ-5 AC)
- Canal chip (whatsapp/telefono/app)
- Phone-based client autocomplete (Phase 34 `clients` + whatsapp) with inline create
- Cobro mode select (Efectivo default / QR / App)
- "Enviar a cocina" → `apiConnector.post('/restaurant-delivery/order', payload)`

**ESLint:** newline-before-return / lines-around-comment / no-unused-vars (OrderModal already conforms — match its spacing).

---

### `views/configuracion/restaurante/RepartidoresCard.tsx` (component, CRUD)

**Analog:** `views/configuracion/restaurante/SalonEditor.tsx` — MUI imports, NAVY_BG/GOLD theme constants (L24-26), `apiConnector` + `toast`, `useBranchByStore` precedent. List + inline-add-row + activo toggle + edit/delete.

**Gating (REQ-1 AC — card only when use_restaurant_mode=true):** consume `useStoreConfig().useRestaurantMode` (StoreConfigContext.tsx L24/L112) and render the card only when true:
```typescript
import { useStoreConfig } from 'src/context/StoreConfigContext'
const { useRestaurantMode } = useStoreConfig()
if (!useRestaurantMode) return null
```
Theme constants to reuse (SalonEditor.tsx L25-26): `const NAVY_BG = '#0f0f1e'; const GOLD = '#f5a623'`.

---

## Shared Patterns

### Single-Transaction sale↔meta sync
**Source:** `api-ventago/src/app/sales/restaurant-sale/restaurant-sale.service.ts` L80-172, L587-644
**Apply to:** restaurant-delivery.service.ts (order intake, transition, settle), rider-settlement.service.ts
```typescript
return this.sequelize.transaction(async (t) => {
  // 모든 sale + meta + box-op + emit 를 단일 TX 로 (drift 방지)
  // storeId 스코프 findOne (멀티테넌트 IDOR 방지)
  // branchId 직접 해결 (terminal 경로보다 신뢰 — Pitfall 4)
});
```

### Auth + storeId scoping (all controllers)
**Source:** `restaurant-tables/restaurant-tables.controller.ts` L16-17, L22-46
**Apply to:** repartidores / restaurant-delivery / rider-settlement controllers
```typescript
import { Auth } from '../auth/decorators/auth.decorator';
import { GetUser } from '../auth/decorators/get-user.decorator';
@Auth()  // every route; service receives user.storeId / user.id
```

### Enum ↔ DB CHECK synchronization
**Source:** `sales.model.ts` L37-54 + `restaurant-tables.model.ts` L14-29 + `39-01-restaurant-tables.sql` L43-67
**Apply to:** RestaurantDelivery status/tipo/canal/paymentMode enums + their CHECK constraints. TS enum value strings MUST equal CHECK string list exactly.

### comanda print (reuse, do not reimplement)
**Source:** `print/print.service.ts` `emitPrintTemp` L32-38 (room `branch:{id}`)
**Apply to:** restaurant-delivery.service.ts order intake — `this.printService.emitPrintTemp(branchId, { kind:'comanda', delivery:true, ... })` fire-and-forget. Separate from the new `/restaurant` gateway.

### box-operation via service (caja integration)
**Source:** `box-operation.service.ts` `addOperation` L16-32 + `restaurant-sale.service.ts` `recordBoxOperation` L650-675
**Apply to:** rider-settlement.service.ts. Always go through `BoxOperationService.addOperation` (never raw INSERT). cash register lookup = `findOne({ userId, closingTime: null })`.

### apiConnector (frontend HTTP)
**Source:** `services/api.service.ts` L161-214
**Apply to:** all new frontend views/hooks. `get/post/put/patch/remove(`...`)` — use `.remove()` not `.delete()`. CSV upload = `apiConnector.sendFile(path, formData)` (L179-186, multipart). Errors auto-surface via global error banner (no manual toast needed for API errors).

### SWR reference-data hook
**Source:** `hooks/api/useRestaurantTables.ts` + `useSalonSummary.ts`
**Apply to:** useRepartidores (5분 dedup), useDeliveryBoard (no refreshInterval — Socket.io push). All keyed on branchId/null for conditional fetch.

### Migration idempotency + PG10/15/18 compat
**Source:** `restaurant-elements.sql` L17-56, `39-01-restaurant-tables.sql`, `phase28...sql` L209-220
**Apply to:** all four 40-xx migrations. `SERIAL` (not GENERATED), `TIMESTAMP WITH TIME ZONE`, `CREATE TABLE/INDEX IF NOT EXISTS`, DO-block CHECK guards, `BEGIN;`/`COMMIT;`, snake_case columns. CHECK extension = DROP-then-ADD inside DO block (constraint `sales_source_check`).

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `restaurant-delivery.gateway.ts` (JWT auth path) | gateway | pub-sub | `/print-agent` gateway authenticates Electron API-Key against branch_agents; no existing browser-JWT Socket.io gateway exists. Room/emit pattern is reusable, but the `handleConnection` auth (validate JWT/sessionToken → join `branch:{id}`) has no direct analog — adapt from auth guard + print.gateway room join. |

**Partial-analog note:** `delivery-payout-csv.service.ts` has no existing CSV-parse-and-reconcile service in the codebase. The TX shape and MinIO upload are reusable; the fixed-template parse + externalRef exact-match logic is net-new (RESEARCH.md guidance applies).

## Metadata

**Analog search scope:** `api-ventago/src/app/{sales,restaurant-tables,box-operation,print,store/config}`, `api-ventago/migrations/`, `ventago-app/src/{views/restaurante,views/configuracion/restaurante,hooks/api,services,context}`
**Files scanned:** ~30
**Schema verified against:** `.planning/intel/db-schema-tables.md` (cash_registers: id/terminal_id/user_id/closing_time/store_id; box_operations: cash_register_id/user_id/terminal_id/amount/type/execution_type)
**Pattern extraction date:** 2026-06-16
