# Phase 29: POS Mercadopago — QR Dinámico - Pattern Map

**Mapped:** 2026-05-05
**Phase:** 29-pos-mercadopago-qr-din-mico
**Files analyzed:** 38 (NEW + MODIFY)
**Analogs found:** 36 / 38

---

## File Classification

### Backend — `api-ventago/`

| New/Modified File | NEW/MOD | Role | Data Flow | Closest Analog | Match |
|-------------------|---------|------|-----------|----------------|-------|
| `src/app/mercadopago/mercadopago.module.ts` | NEW | module | composition | `src/app/box/box.module.ts` | exact |
| `src/app/mercadopago/mercadopago.controller.ts` | NEW | controller | request-response | `src/app/box/box.controller.ts` | exact |
| `src/app/mercadopago/mercadopago.service.ts` | NEW | service | orchestrator | `src/app/print/print.service.ts` | exact |
| `src/app/mercadopago/oauth/mp-oauth.service.ts` | NEW | service | request-response | `src/app/print/print.service.ts` (validateApiKey) | role-match |
| `src/app/mercadopago/oauth/mp-oauth.controller.ts` | NEW | controller | request-response (302 redirect) | `src/app/box/box.controller.ts` | role-match |
| `src/app/mercadopago/api-client/mp-api-client.service.ts` | NEW | service | external HTTP | (no analog — first axios wrapper service) | none |
| `src/app/mercadopago/api-client/mp-store-pos.service.ts` | NEW | service | external HTTP | `src/app/print/print.service.ts` (one-shot create) | role-match |
| `src/app/mercadopago/crypto/mp-token-crypto.service.ts` | NEW | service | pure transform | (no analog — first crypto utility) | none |
| `src/app/mercadopago/webhook/mp-webhook.controller.ts` | NEW | controller | event-driven (public POST) | `src/app/box/box.controller.ts` | role-match |
| `src/app/mercadopago/webhook/mp-webhook.service.ts` | NEW | service | event-driven + transactional | `src/app/print/print.service.ts` (gateway emit) | role-match |
| `src/app/mercadopago/qr/mp-qr.controller.ts` | NEW | controller | CRUD | `src/app/box/box.controller.ts` | exact |
| `src/app/mercadopago/qr/mp-qr.service.ts` | NEW | service | CRUD + external HTTP | `src/app/box/box.service.ts` | role-match |
| `src/app/mercadopago/intents/mp-payment-intents.controller.ts` | NEW | controller | request-response (polling) | `src/app/box/box.controller.ts` (GET by id) | exact |
| `src/app/mercadopago/intents/mp-payment-intents.service.ts` | NEW | service | CRUD | `src/app/box/box.service.ts` | exact |
| `src/app/mercadopago/wallet/mp-wallet.service.ts` | NEW | service | CRUD + balance computation | `src/app/box/box.service.ts` (balance SUM SQL) | exact |
| `src/app/mercadopago/wallet/mp-wallet.controller.ts` | NEW | controller | CRUD | `src/app/box/box.controller.ts` | exact |
| `src/app/mercadopago/wallet/mp-transfer.service.ts` | NEW | service | transactional CRUD | `src/app/box/box.service.ts` (balance SQL pattern) | role-match |
| `src/app/mercadopago/refunds/mp-refund.service.ts` | NEW | service | external HTTP + transactional | `src/app/print/print.service.ts` (emit pattern) | role-match |
| `src/app/mercadopago/refunds/mp-refund.controller.ts` | NEW | controller | request-response | `src/app/box/box.controller.ts` | role-match |
| `src/app/mercadopago/cron/mp-token-refresh.cron.ts` | NEW | cron service | batch | (use `@nestjs/schedule` Cron — no exact analog in mapped files) | none |
| `src/app/mercadopago/cron/mp-wallet-reconcile.cron.ts` | NEW | cron service | batch | same as above | none |
| `src/app/mercadopago/models/mp-account.model.ts` | NEW | model | sequelize-typescript | `src/app/print/branch-agent.model.ts` | exact |
| `src/app/mercadopago/models/mp-payment-intent.model.ts` | NEW | model | sequelize-typescript | `src/app/print/branch-agent.model.ts` | exact |
| `src/app/mercadopago/models/mp-wallet.model.ts` | NEW | model | sequelize-typescript | `src/app/box/box.model.ts` | exact |
| `src/app/mercadopago/models/mp-movement.model.ts` | NEW | model | sequelize-typescript | `src/app/box/box.model.ts` | exact |
| `src/app/mercadopago/models/mp-refund.model.ts` | NEW | model | sequelize-typescript | `src/app/print/branch-agent.model.ts` | exact |
| `src/app/mercadopago/models/mp-refund-attempt.model.ts` | NEW | model | sequelize-typescript | `src/app/print/branch-agent.model.ts` | exact |
| `src/app/mercadopago/models/mp-transfer.model.ts` | NEW | model | sequelize-typescript | `src/app/box/box.model.ts` | exact |
| `src/app/mercadopago/dto/create-mp-qr.dto.ts` | NEW | dto | validation | `src/app/expenses/dto/create-expenses.dto.ts` | exact |
| `src/app/mercadopago/dto/mp-webhook.dto.ts` | NEW | dto | validation | `src/app/expenses/dto/create-expenses.dto.ts` | exact |
| `src/app/mercadopago/dto/transfer-mp-to-cash.dto.ts` | NEW | dto | validation | `src/app/expenses/dto/create-expenses.dto.ts` | exact |
| `src/common/socket/websocket.service.ts` | MOD | service | pub-sub | (self — extend with `emitToTerminal`) | self-extend |
| `src/common/socket/websocket.gateway.ts` | MOD | gateway | event-driven | (self — add `register_terminal` SubscribeMessage) | self-extend |
| `src/app/sales/sales-create.service.ts` | MOD | service | orchestrator | (self — extend `nullifySale` to call MpRefundService) | self-extend |
| `src/app/payment-methods/seed/payment-methods.seed.ts` | MOD (no-op) | seed | batch | (self — `mercadopago` slug already seeded) | self |
| `migrations/29-01-mp-accounts.sql` | NEW | migration | DDL | `migrations/26-01-step1-schema.sql` | exact |
| `migrations/29-02-mp-payment-intents.sql` | NEW | migration | DDL | `migrations/26-01-step1-schema.sql` | exact |
| `migrations/29-03-mp-wallets-movements.sql` | NEW | migration | DDL | `migrations/26-01-step1-schema.sql` | exact |
| `migrations/29-04-mp-refunds.sql` | NEW | migration | DDL | `migrations/26-01-step1-schema.sql` | exact |
| `migrations/29-05-mp-transfers.sql` | NEW | migration | DDL | `migrations/26-01-step1-schema.sql` | exact |
| `migrations/29-99-rollback.sql` | NEW | migration | DDL rollback | `migrations/26-99-rollback.sql` | exact |

### Frontend — `ventago-app/`

| New/Modified File | NEW/MOD | Role | Data Flow | Closest Analog | Match |
|-------------------|---------|------|-----------|----------------|-------|
| `package.json` | MOD | manifest | dep-add | (self — add `qrcode.react`) | self |
| `src/pages/configuracion/mercadopago/index.tsx` | NEW | page | shell+dynamic | `src/pages/configuracion/ventas/index.tsx` | exact |
| `src/views/mercadopago/McdpgConfigView.tsx` | NEW | view | composition | `src/views/cash-control/list/CashRegisterList.tsx` | role-match |
| `src/views/mercadopago/components/McdpgAccountCard.tsx` | NEW | component | presentational | `src/components/cards/CardFilter.tsx` (Card pattern) | role-match |
| `src/views/mercadopago/components/McdpgBranchToggleTable.tsx` | NEW | component | presentational + interaction | `src/views/cash-control/list/components/CashControlList.tsx` (table+actions) | role-match |
| `src/views/mercadopago/components/McdpgEnvironmentBadge.tsx` | NEW | component | presentational | (MUI `<Chip>` — inline) | role-match |
| `src/views/mercadopago/hooks/useMpAccounts.ts` | NEW | hook | SWR fetch | `src/hooks/api/useBranchByStore.ts` | exact |
| `src/views/mercadopago/hooks/useMpPaymentIntent.ts` | NEW | hook | SWR polling 5s | `src/hooks/api/usePriceTypes.ts` (with custom `refreshInterval`) | role-match |
| `src/views/mercadopago/hooks/useMpApprovedSocket.ts` | NEW | hook | socket subscriber | `src/components/team-chat/TeamChatPanel.tsx` (socket effect) | role-match |
| `src/types/mercadopago.ts` | NEW | types | type defs | (no analog — minimal) | none |
| `src/views/homes/components/ProductList/components/PaymentSummaryModal.tsx` | MOD | component | composition | (self — add MP row + side-panel grid) | self-extend |
| `src/views/homes/components/ProductList/components/McdpgQrPanel.tsx` | NEW | component | presentational + countdown timer | (self — colocated) | none |
| `src/views/homes/components/ProductList/ProductList.tsx` | MOD | view | composition | (self — wire `useMpApprovedSocket` to `handleSubmit("INVOICED")`) | self-extend |
| `src/components/banners/SandboxMpBanner.tsx` | NEW | component | presentational | (no exact analog — `<Alert severity="warning">` MUI primitive) | none |
| `src/views/cash-control/components/McdpgWalletRow.tsx` | NEW | component | presentational + actions | `src/views/cash-control/list/components/CashControlList.tsx` (action cell) | role-match |
| `src/views/cash-control/components/McdpgTransferModal.tsx` | NEW | component | modal form | `src/views/cash-control/list/components/ModalCashRegister.tsx` | exact |
| `src/views/cash-control/components/McdpgDetailModal.tsx` | NEW | component | modal table | `src/views/cash-control/list/components/ModalCashRegister.tsx` | role-match |
| `src/views/cash-control/list/components/CashControlList.tsx` | MOD | view | composition | (self — render `McdpgWalletRow` row in table) | self-extend |
| `src/views/sales/details/SalesDetailView.tsx` | MOD | view | composition | (self — add refund-failure section) | self-extend |
| `src/navigation/vertical/index.ts` | MOD | config | nav build | (self — push `Configuración › Mercadopago` child) | self-extend |
| `src/@core/theme/palette/index.ts` | MOD | config | palette | (self — extend `info`/`warning` for MP cyan + sandbox gold) | self-extend |

---

## Pattern Assignments — Backend

### `api-ventago/src/app/mercadopago/models/mp-account.model.ts` (model, sequelize-typescript)

**Analog:** `api-ventago/src/app/print/branch-agent.model.ts` (lines 1-63)

**Imports + decorator pattern** (lines 1-14):
```typescript
import {
  BelongsTo, Column, DataType, ForeignKey, Model, Table,
} from 'sequelize-typescript';
import { Branch } from '../branch/branch.model';
import { randomUUID } from 'crypto';

// underscored:true 전역 설정 → DB 컬럼은 snake_case
@Table({ tableName: 'branch_agents', timestamps: true })
export class BranchAgent extends Model {
```
For Phase 29 use `@Table({ tableName: 'mp_accounts', timestamps: true })` etc. Always include the **explicit `tableName`** comment about snake_case (CLAUDE.md rule).

**FK + BelongsTo + nullable pattern** (lines 16-22 + adapt):
```typescript
@ForeignKey(() => Branch)
@Column({ type: DataType.INTEGER, allowNull: false })
declare branchId: number;

@BelongsTo(() => Branch, { onDelete: 'CASCADE', foreignKey: 'branchId' })
branch?: Branch;
```
For `mp_account.branchId NULLABLE` → `allowNull: true` and `declare branchId: number | null`.

**JSONB column pattern** (lines 49-50):
```typescript
@Column({ type: DataType.JSONB, allowNull: true })
printerConfig: Record<string, any> | null;
```
Reuse for any `mp_*` row that needs JSON state.

**`declare` keyword pattern** — RESEARCH.md confirms TS strict mode requires `declare` for FK columns. Apply to **every** field on all 7 new models.

---

### `api-ventago/src/app/mercadopago/models/mp-payment-intent.model.ts` (model, sequelize-typescript)

**Analog:** `api-ventago/src/app/print/branch-agent.model.ts` + RESEARCH.md §"Sequelize-typescript model" (lines 624-678)

**Apply directly the RESEARCH.md exemplar** — it is already validated as the target shape. Key fields: `paymentId STRING(32) UNIQUE` (idempotency lock), `status ENUM('pending','approved','cancelled','expired','failed')`, `qrData TEXT`, `expiresAt DATE`.

**ENUM column** (RESEARCH.md line 666):
```typescript
@Column({
  type: DataType.ENUM('pending', 'approved', 'cancelled', 'expired', 'failed'),
  allowNull: false,
  defaultValue: 'pending',
})
declare status: 'pending' | 'approved' | 'cancelled' | 'expired' | 'failed';
```

**NUMERIC(14,2) for monetary** (RESEARCH.md line 651-652):
```typescript
@Column({ type: DataType.NUMERIC(14, 2), allowNull: false })
declare amount: number;
```

---

### `api-ventago/src/app/mercadopago/models/mp-wallet.model.ts` (model, sequelize-typescript)

**Analog:** `api-ventago/src/app/box/box.model.ts` (lines 17-46)

**Module-level table + storeId/branchId FK pattern** (lines 17-39):
```typescript
@Table({ timestamps: true })
export class Box extends Model {
  @PrimaryKey @AutoIncrement @Column id: number;
  @Column({ type: DataType.STRING, allowNull: false }) name: string;
  @ForeignKey(() => Store) @Column({ type: DataType.INTEGER, allowNull: false }) storeId: number;
  @BelongsTo(() => Store, { onDelete: 'CASCADE' }) store: Store;
  @ForeignKey(() => Branch) @Column({ type: DataType.INTEGER, allowNull: false }) branchId: number;
  @BelongsTo(() => Branch, { onDelete: 'CASCADE' }) branch: Branch;
```
For `mp_wallets`: same shape, but `branchId` NULLABLE (store-level wallet supported), add `mpAccountId UNIQUE FK`, `balance NUMERIC(14,2) DEFAULT 0`, `currency CHAR(3) DEFAULT 'ARS'`, `lastSyncedAt DATE`.

**`isDeleted` soft-delete pattern** (line 44-45) — apply if needed:
```typescript
@Column({ type: DataType.BOOLEAN, defaultValue: false })
isDeleted: boolean;
```
For Phase 29 wallets: skip — wallets always alive while mp_account active.

---

### `api-ventago/src/app/mercadopago/mercadopago.module.ts` (module, composition)

**Analog:** `api-ventago/src/app/box/box.module.ts` (lines 1-14) + `api-ventago/src/app/print/print.module.ts` (lines 1-19)

**Multi-model SequelizeModule.forFeature pattern** (`print.module.ts` lines 13-19):
```typescript
import { Module } from '@nestjs/common';
import { SequelizeModule } from '@nestjs/sequelize';
import { BranchAgent } from './branch-agent.model';
import { Sale } from '../sales/sales.model';
import { PrintService } from './print.service';
import { PrintGateway } from './print.gateway';
import { PrintController } from './print.controller';

@Module({
  imports: [SequelizeModule.forFeature([BranchAgent, Sale])],
  controllers: [PrintController],
  providers: [PrintService, PrintGateway],
  exports: [PrintService],
})
export class PrintModule {}
```
For `MercadopagoModule`: register all 7 mp_* models + `PaymentMethod` + `Sale` + `Branch` + `Box` + `Movements` (for transfer). Providers: 14+ services from RESEARCH.md project structure (oauth, api-client, crypto, webhook, qr, intents, wallet, refunds, transfer, cron). Controllers: 7 sub-controllers. Export `MercadopagoService` (so `SalesCreateService` can call refund).

---

### `api-ventago/src/app/mercadopago/qr/mp-qr.controller.ts` (controller, request-response)

**Analog:** `api-ventago/src/app/box/box.controller.ts` (lines 1-127)

**Imports + Auth decorator pattern** (lines 1-21):
```typescript
import { BadRequestException, Controller, Get, Param, Query, Post, Put, Delete, Body } from '@nestjs/common';
import { ParseIntPipe } from '@nestjs/common';
import { Audit } from 'src/common/decorators/audit.decorator';
import { Auth } from '../auth/decorators/auth.decorator';
import { ValidRoles } from '../auth/interfaces/valid-roles';
import { GetUser } from '../auth/decorators/get-user.decorator';
import { Users } from '../users/users.model';
```

**POST handler with Auth + Audit + GetUser** (lines 27-36):
```typescript
@Post('')
@Auth(ValidRoles.admin, ValidRoles.superadmin, ValidRoles.gerente)
@Audit({
  entityType: 'Caja',
  action: 'create',
  getDescription: (body: any) => `Caja creada: ${body.name}`,
})
async create(@Body() body: any, @GetUser() user?: Users): Promise<any> {
  return super.create(body, user);
}
```
For MP QR controller — `POST /mercadopago/qr` with `@Auth(admin, gerente, vendedor)` + `@Audit({ entityType: 'McdpgQR', action: 'create', getDescription: (body) => 'QR gerado' })` + DTO `CreateMpQrDto`.

**Roles allowed for QR generation** — vendedor MUST be allowed (POS use case). Transfer endpoint (`POST /wallets/:id/transfer`) → `@Auth(admin, gerente)` only (vendedor blocked per CONTEXT.md "Specific Ideas").

---

### `api-ventago/src/app/mercadopago/wallet/mp-wallet.service.ts` (service, balance computation)

**Analog:** `api-ventago/src/app/box/box.service.ts` (lines 12-104)

**Service constructor + InjectModel pattern** (lines 12-15):
```typescript
@Injectable()
export class BoxService extends CrudService<Box> {
  constructor(@InjectModel(Box) private readonly boxModel: typeof Box) {
    super(boxModel);
  }
```
For MP wallet — extend `CrudService<MpWallet>` similarly.

**Raw SQL balance computation pattern** (lines 60-95):
```typescript
const balances = await sequelize.query<{ box_id: number; balance: string; }>(
  `
  SELECT
    cr.box_id AS box_id,
    COALESCE(SUM(cr.initial_amount), 0)
    + COALESCE(SUM(CASE WHEN bo.type IN ('venta','ingreso') THEN bo.amount ELSE 0 END), 0)
    - COALESCE(SUM(CASE WHEN bo.type IN ('gasto','retiro') THEN bo.amount ELSE 0 END), 0) AS balance
  FROM cash_registers cr
  LEFT JOIN box_operations bo ON bo.cash_register_id = cr.id
  WHERE cr.box_id IN (:boxIds) AND cr.closing_time IS NULL
  GROUP BY cr.box_id
  `,
  { replacements: { boxIds }, type: QueryTypes.SELECT },
);
```
For MP wallet reconcile: same shape — `SELECT mw.id, COALESCE(SUM(CASE WHEN type='credit' THEN amount END),0) - COALESCE(SUM(CASE WHEN type='debit' THEN amount END),0) AS balance FROM mp_wallets mw LEFT JOIN mp_movements mv ON mv.mp_wallet_id = mw.id GROUP BY mw.id`.

**snake_case in raw SQL** (line 69-72) — confirms CLAUDE.md rule. All MP migration SQL + raw queries MUST use snake_case (`mp_wallet_id`, `created_at`, etc.).

**Error handling around balance calc** (lines 87-93):
```typescript
} catch (err) {
  // 잔액 계산 실패 시에도 box 목록은 정상 반환 (기본값 0)
  console.error('[BoxService] Balance 계산 실패:', (err as Error).message);
}
```
Apply identically to MP wallet — UI 표시 우선, balance 0 fallback.

---

### `api-ventago/src/app/mercadopago/wallet/mp-transfer.service.ts` (service, transactional CRUD)

**Analog:** `api-ventago/src/app/box/box.service.ts` (raw SQL pattern) + RESEARCH.md Pattern 3 (transaction)

**Sequelize transaction pattern** (RESEARCH.md lines 407-429):
```typescript
await this.sequelize.transaction(async (t) => {
  const intent = await this.intentModel.findByPk(intentId, {
    lock: t.LOCK.UPDATE,    // SELECT ... FOR UPDATE (PG row lock)
    transaction: t,
  });
  if (!intent) { /* warn */ return; }
  if (intent.paymentId) { /* already processed */ return; }
  await intent.update({ paymentId, status: 'approved', approvedAt: new Date() }, { transaction: t });
  await this.walletService.creditOnSale(intent, payment, t);
});
```
For MP→cash transfer: `BEGIN TX → SELECT FOR UPDATE mp_wallets WHERE id=? → check balance >= amount → INSERT mp_movements (debit, type='transfer_out') → INSERT movements (credit, type='mp_transfer') in box → UPDATE mp_wallets.balance, box balance → INSERT mp_transfers row → COMMIT`. Throw `BadRequestException('Saldo insuficiente')` if balance check fails.

---

### `api-ventago/src/app/mercadopago/api-client/mp-api-client.service.ts` (service, external HTTP)

**No close codebase analog.** Use **RESEARCH.md Pattern 1** (lines 281-323) verbatim.

Key requirements:
- Per-call `accessToken` injection (multi-tenant)
- `X-Idempotency-Key` opt-in (refunds + critical writes)
- Timeout 10s
- Logger.error with `mpStatus` + `mpError` body for debug
- Throws `BadRequestException({ message, mpStatus, mpError })` so frontend axios interceptor surfaces error to toast (CLAUDE.md error visibility rule)

---

### `api-ventago/src/app/mercadopago/crypto/mp-token-crypto.service.ts` (service, pure transform)

**No close codebase analog.** Use **RESEARCH.md Pattern 2** (lines 332-380) verbatim.

Key requirements (from RESEARCH.md anti-patterns):
- AES-256-GCM only
- Random 12-byte IV per encryption (NEVER reuse)
- Format `${iv_b64}:${tag_b64}:${ct_b64}`
- Master key from `MP_TOKEN_ENCRYPTION_KEY` env (32 bytes hex = 64 chars)
- Throw on missing/wrong-length key in constructor (fail fast at boot)

---

### `api-ventago/src/app/mercadopago/webhook/mp-webhook.service.ts` (service, event-driven + transactional)

**Analog:** `api-ventago/src/app/print/print.service.ts` (lines 22-67) — emit pattern, plus RESEARCH.md Pattern 3.

**Re-fetch BEFORE transaction** (RESEARCH.md Pitfall 6 + Pattern 3):
```typescript
// 1) Fetch MP API outside lock window — avoids holding row lock during slow HTTP
const account = await this.mpAccountModel.findByPk(mpAccountId);
const accessToken = this.crypto.decrypt(account.accessToken);
const payment = await this.mpApi.get<MpPayment>(`/v1/payments/${mpPaymentId}`, accessToken);
if (payment.status !== 'approved') return;

// 2) Tiny critical section — SELECT FOR UPDATE + UPDATE
await this.sequelize.transaction(async (t) => { /* ... */ });

// 3) Emit Socket.io OUTSIDE transaction
await this.websocket.emitToTerminal(intent.terminalId, 'mercadopago:approved', payload);
```

**emit pattern from print.service.ts** (lines 22-29):
```typescript
emitPrintTemp(branchId: number, data: any): void {
  try {
    this.gateway.server?.to(`branch:${branchId}`).emit('print_temp', data);
  } catch (err) {
    console.error('[PrintService] emitPrintTemp 실패:', err);
  }
}
```
Apply: `this.websocket.emitToTerminal(terminalId, 'mercadopago:approved', payload)` wrapped in try/catch, log on failure (polling will catch up — never throw).

---

### `api-ventago/src/common/socket/websocket.service.ts` (service, pub-sub) — MODIFY

**Self-extend** following the existing Map pattern (lines 7-14):
```typescript
private clients: Map<string, Socket> = new Map();
private apiKeyClients: Map<string, Set<string>> = new Map();
private userClients: Map<number, Set<string>> = new Map();
private storeClients: Map<number, Set<string>> = new Map();
```

**Add per RESEARCH.md Pattern 4** (lines 446-462):
```typescript
private terminalClients: Map<number, Set<string>> = new Map();

registerTerminal(client: Socket, terminalId: number) {
  this.clients.set(client.id, client);
  (client as any).terminalId = terminalId;
  client.join(`terminal:${terminalId}`);
  if (!this.terminalClients.has(terminalId)) {
    this.terminalClients.set(terminalId, new Set());
  }
  this.terminalClients.get(terminalId)!.add(client.id);
}

emitToTerminal(terminalId: number, event: string, payload: any) {
  // socket.io room broadcast — most efficient (server-side fan-out)
  this.server.to(`terminal:${terminalId}`).emit(event, payload);
}
```

**Existing emitToApiKey pattern** (lines 39-46) shows iterative variant — prefer the `server.to(room).emit()` form for new methods (RESEARCH.md confirms more efficient).

**Cleanup on disconnect** — extend `unregisterClient(client)` to remove from `terminalClients` Map too (mirror the `apiKeyClients` cleanup at lines 31-37).

---

### `api-ventago/src/common/socket/websocket.gateway.ts` (gateway, event-driven) — MODIFY

**Self-extend** following the `register_user` SubscribeMessage pattern (lines 46-55):
```typescript
@SubscribeMessage('register_user')
handleRegisterUser(@ConnectedSocket() client: Socket, @MessageBody() data: any) {
  const { userId, storeId } = data;
  if (userId && storeId) {
    this.websocketService.registerUser(client, userId, storeId);
  }
}
```

**Add (per RESEARCH.md Pattern 4 lines 467-475):**
```typescript
@SubscribeMessage('register_terminal')
handleRegisterTerminal(
  @ConnectedSocket() client: Socket,
  @MessageBody() data: { terminalId: number },
) {
  if (data?.terminalId) {
    this.websocketService.registerTerminal(client, data.terminalId);
  }
}
```

---

### `api-ventago/src/app/mercadopago/dto/create-mp-qr.dto.ts` (dto, validation)

**Analog:** `api-ventago/src/app/expenses/dto/create-expenses.dto.ts` (lines 1-40)

**class-validator decorator pattern** (lines 1-30):
```typescript
import { IsString, IsOptional, IsNumber, IsBoolean, IsDateString } from 'class-validator';

export class CreateExpensesDto {
  @IsNumber({}, { message: 'El storeId es requerido' })
  readonly storeId: number;

  @IsNumber({}, { message: 'El branchId es requerido' })
  readonly branchId: number;

  @IsNumber({}, { message: 'El monto es requerido' })
  amount: number;
  // ...
  @IsOptional()
  @IsBoolean()
  affectsBox: boolean;
}
```
For `CreateMpQrDto`: `storeId, branchId?, amount, pendingVentaId, terminalId` — all `@IsNumber` with Spanish messages. Use `readonly` for FK ids.

---

### `api-ventago/migrations/29-01-mp-accounts.sql` and other 29-XX migrations (DDL)

**Analog:** `api-ventago/migrations/26-01-step1-schema.sql` (lines 1-90)

**Header comment pattern** (lines 1-13):
```sql
-- =============================================================================
-- Phase 26 Wave 1 — Step 1: expense_categories 테이블 스키마 + 트리거 + 인덱스
-- =============================================================================
-- 목적: 새 자기참조 트리 테이블 생성 (adjacency list + materialized path 패턴)
-- 실행 순서: 반드시 step1 을 먼저 실행 (다른 step 은 이 테이블에 의존)
-- Idempotency: 모든 CREATE 에 IF NOT EXISTS 사용. 트리거 함수는 CREATE OR REPLACE.
--              같은 SQL 을 두 번 실행해도 에러 없이 통과.
-- PG10 호환 참고사항:
--   EXECUTE PROCEDURE 사용 (PG11+ EXECUTE FUNCTION 아님)
--   SERIAL 사용 (GENERATED AS IDENTITY 아님)
--   ltree 확장 미사용 (운영 서버에 미설치)
-- =============================================================================
```
**Apply this header to every 29-XX SQL file.** Customize purpose + run-order line.

**BEGIN/COMMIT wrap** — required (line 15 + last line):
```sql
BEGIN;
-- table + indexes + constraints
COMMIT;
```

**Idempotent CREATE pattern** (lines 21-44):
```sql
CREATE TABLE IF NOT EXISTS expense_categories (
  id          SERIAL PRIMARY KEY,           -- PG10/15 호환 (NOT GENERATED AS IDENTITY)
  store_id    INTEGER NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  parent_id   INTEGER REFERENCES expense_categories(id) ON DELETE RESTRICT,
  name        VARCHAR(120) NOT NULL,
  ...
  created_at  TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMP NOT NULL DEFAULT NOW()
);
```

**CHECK constraint guarded by DO block** (lines 45-58) — required pattern for re-runnable migrations:
```sql
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conname = 'chk_no_self_parent' AND conrelid = 'expense_categories'::regclass
  ) THEN
    ALTER TABLE expense_categories
      ADD CONSTRAINT chk_no_self_parent
      CHECK (parent_id IS NULL OR parent_id <> id);
  END IF;
END$$;
```
For Phase 29: same pattern for `chk_mp_account_environment` (`environment IN ('sandbox','production')`), `chk_mp_intent_status` (status enum CHECK).

**Partial UNIQUE index pattern** (lines 80-90) — exactly what `mp_accounts(store_id, COALESCE(branch_id,0))` constraint needs. **For PG10 compat, prefer two partial UNIQUE indexes** (one for `branch_id IS NULL`, one for `branch_id IS NOT NULL`) instead of `COALESCE` in UNIQUE — this matches the proven Phase 26 pattern.

**Reference also `migrations/26-99-rollback.sql`** for the `29-99-rollback.sql` shape (DROP TABLE IF EXISTS … CASCADE in reverse FK order).

---

### `api-ventago/src/app/sales/sales-create.service.ts` (service, orchestrator) — MODIFY

**Self-extend** existing `nullifySale(saleId, userId)` at line 300.

**Pattern to add inside nullifySale:**
1. After existing nullify logic completes successfully, iterate `sale.paymentMethods`
2. For each payment with `slug === 'mercadopago' && mp_payment_id`, call `await this.mpRefundService.refundForSale(sale, payment)`
3. Aggregate results into return shape: `{ ...sale, mpRefundFailed?: true, mpErrorMsg?, mpAttemptId? }`

**Inject MpRefundService** via constructor — `MercadopagoModule` exports it.

**Do NOT throw** if MP refund fails — sale nullification must succeed, MP failure surfaces via the new `mpRefundFailed` flag (per SPEC MP-POS-07).

---

### `api-ventago/src/app/payment-methods/seed/payment-methods.seed.ts` — NO CHANGE

**Analog:** self (lines 35-39) — `mercadopago` slug already seeded:
```typescript
{ title: 'Mercadopago', slug: 'mercadopago', is_active: true, type: 'minorista' },
```
**Confirms CONTEXT.md "Reusable Assets" item.** Phase 29 reuses the existing slug as-is. No PaymentMethodsOption needed (MP doesn't have sub-options like cards).

---

## Pattern Assignments — Frontend

### `ventago-app/src/pages/configuracion/mercadopago/index.tsx` (page, shell+dynamic)

**Analog:** `ventago-app/src/pages/configuracion/ventas/index.tsx` (lines 1-19)

**Full file pattern (use as template):**
```typescript
import dynamic from 'next/dynamic'
import WithAccess from "src/configs/withAccess"

// MP 설정 뷰 — OAuth + 카드 + 테이블 포함, 필요 시에만 로드 (300ms P95 목표)
const McdpgConfigView = dynamic(() => import('src/views/mercadopago/McdpgConfigView'), { ssr: false })

const McdpgConfigPage = () => {
  return (
    <WithAccess allowedApps={["admin"]} allowedModules={["configuracion-mercadopago"]}>
      <McdpgConfigView/>
    </WithAccess>
  )
}
McdpgConfigPage.acl = { action: 'read', subject: 'configuracion' }

export default McdpgConfigPage
```
**Required:** `next/dynamic` with `ssr: false` (CLAUDE.md performance rule), `WithAccess` wrapper, `acl` prop on default export.

---

### `ventago-app/src/views/mercadopago/hooks/useMpAccounts.ts` (hook, SWR fetch)

**Analog:** `ventago-app/src/hooks/api/useBranchByStore.ts` (lines 1-11)

**Full pattern:**
```typescript
import { useApi } from 'src/hooks/useApi'
import { useAuth } from 'src/hooks/useAuth'

// 매장의 MP 계정 목록 — store-level + branch-level 모두 반환
// SWR 5분 dedup (참조 데이터 정책 — CLAUDE.md)
export function useMpAccounts() {
  const { user } = useAuth()
  const storeId = user?.storeId

  return useApi<any[]>(storeId ? `/mercadopago/accounts?storeId=${storeId}` : null)
}
```
**Required:** Conditional null key (returns `null` if `storeId` undefined → SWR skips fetch — RESEARCH.md anti-pattern §"Polling without intentId guard").

**`useApi` wrapper** (`ventago-app/src/hooks/useApi.ts`) — already wraps `useSWR` with `apiConnector.get` fetcher. Reuse for ALL MP SWR hooks (consistent error handling).

---

### `ventago-app/src/views/mercadopago/hooks/useMpPaymentIntent.ts` (hook, SWR polling 5s)

**Analog:** `ventago-app/src/hooks/api/usePriceTypes.ts` (extended) + RESEARCH.md Pattern 5 (lines 505-517)

**Full pattern (RESEARCH.md verbatim):**
```typescript
import useSWR from 'swr'

// SWR refreshInterval=5000 → 5초 polling (webhook fallback — D-A2-03)
// QR 모달 unmount 시 자동 정리, mutate() 로 즉시 갱신 가능
export function useMpPaymentIntent(intentId: number | null) {
  const { data, mutate } = useSWR(
    intentId ? `/mercadopago/payment-intents/${intentId}` : null,
    {
      refreshInterval: 5000,
      revalidateOnFocus: false,
      dedupingInterval: 0,    // polling 시엔 dedup 무력화 (5초 간격 보장)
    }
  )

  return { intent: data, mutate }
}
```
**Critical:** `dedupingInterval: 0` overrides global SWR 5분 default (참조 데이터 vs polling — 다른 정책, CONTEXT.md "Established Patterns").

---

### `ventago-app/src/views/mercadopago/hooks/useMpApprovedSocket.ts` (hook, socket subscriber)

**Analog:** `ventago-app/src/components/team-chat/TeamChatPanel.tsx` (lines 34, 49-85)

**WS_URL constant pattern** (line 34):
```typescript
const WS_URL = process.env.NODE_ENV === 'development'
  ? 'http://localhost:5002/realtime'
  : 'https://newapi.coolsistema.com/realtime'
// or read from process.env.NEXT_PUBLIC_WS_URL
```
**Verify exact URL value** by reading `team-chat/TeamChatPanel.tsx` line 34 in implementation.

**Socket effect pattern** (lines 49-85):
```typescript
useEffect(() => {
  if (!terminalId) return
  const socket = io(WS_URL, { transports: ['websocket'] })

  socket.on('connect', () => {
    socket.emit('register_terminal', { terminalId })
  })

  socket.on('mercadopago:approved', (payload: McdpgApprovedPayload) => {
    onApproved(payload)    // ref-stable callback
  })

  return () => {
    socket.disconnect()
  }
}, [terminalId, onApproved])
```
**Cleanup on unmount** — required (memory leak otherwise).

---

### `ventago-app/src/views/cash-control/components/McdpgTransferModal.tsx` (component, modal form)

**Analog:** `ventago-app/src/views/cash-control/list/components/ModalCashRegister.tsx` (modal pattern)

**Inspect for:**
- `<Dialog open onClose>` MUI structure
- `useForm` (react-hook-form) + Yup validation pattern
- Submit handler that calls `apiConnector.post` then `refresh()` callback
- `<DialogActions>` cancel + confirm button layout

**Apply for transfer modal:**
- amount input (mono font, currency mask) + 25/50/100% quick-fill buttons
- Caja destino `<Select>` — list from `useBox` hook (existing in cash-control/hooks/useBox.tsx)
- Note `<TextField multiline>`
- On submit: `apiConnector.post('/mercadopago/transfers', body)` then mutate SWR caches

---

### `ventago-app/src/views/cash-control/list/components/CashControlList.tsx` (view, composition) — MODIFY

**Self-extend** existing pattern (lines 22-156).

**Action cell pattern** (lines 70-105) — copy for `McdpgWalletRow` row actions:
```typescript
<WithFunctionAccess functionSlug="cerrar-caja">
  <Tooltip title="Cerrar Caja" arrow placement="top">
    <IconButton color="warning" onClick={() => handleCloseCashRegister(row)}>
      <Icon icon="tabler:lock" />
    </IconButton>
  </Tooltip>
</WithFunctionAccess>
```
For MP wallet row — `<Button color="warning" variant="contained" size="small">Transferir →</Button>` wrapped in `<WithFunctionAccess functionSlug="mp-transfer">` (or admin/gerente role check).

**Add Caja MP row above the regular FullTable** — render `<McdpgWalletRow walletId={...} onTransfer={openTransferModal} onDetail={openDetailModal} />` for each MP wallet of the current store, fetched via `useMpWallets()` SWR hook.

---

### `ventago-app/src/views/homes/components/ProductList/components/PaymentSummaryModal.tsx` (component) — MODIFY

**Self-extend** existing modal at lines 50-560.

**Existing imports already include** (line 2): `Box, Button, Dialog, ..., Alert, AlertTitle, Stack, Chip, IconButton, Table, TableBody, TableCell` — sufficient for MP additions.

**Existing inline error pattern** (lines 89-93, 119-120):
```typescript
const [pmFetchError, setPmFetchError] = useState<string | null>(null);
// ...
setAvailablePaymentMethods(list);
setPmFetchError(null);
```
Reuse for MP-specific errors (`<Alert severity="error">` inline + toast — CLAUDE.md error visibility).

**SLUG constants pattern** (lines 29-31):
```typescript
const SLUG_CREDITO = "credito";
const SLUG_FAVOR = "favor";
const SLUG_SENIA = "senia";
```
Add: `const SLUG_MERCADOPAGO = "mercadopago";`.

**MP row + side-panel grid layout** — per UI-SPEC §"Surface 2 — PaymentSummaryModal modal grid":
```typescript
sx={{
  display: 'grid',
  gridTemplateColumns: mpSelected ? '1fr 320px' : '1fr',
  maxWidth: mpSelected ? 920 : 600,
  gap: 0,
}}
```
Right panel: `<McdpgQrPanel />` colocated in same directory.

**Auto-trigger handleSubmit pattern** — wire `useMpApprovedSocket` + `useMpPaymentIntent` so when `intent.status === 'approved'`:
```typescript
const processedIntentRef = useRef<number | null>(null);
const onApproved = useCallback((intentId) => {
  if (processedIntentRef.current === intentId) return;  // 멱등 가드 (RESEARCH.md Pitfall 5)
  processedIntentRef.current = intentId;
  setTimeout(() => handleSubmit("INVOICED", paymentMethods), 600);  // ~600ms — UI-SPEC delay
}, [handleSubmit, paymentMethods]);
```

**Reference `ProductList.tsx:1162`** — that's where `handleSubmit("INVOICED", paymentMethods)` is defined. Modal must lift the trigger via prop callback or shared context.

---

### `ventago-app/src/views/sales/details/SalesDetailView.tsx` (view) — MODIFY

**Self-extend** existing view (lines 71-90).

**Inject refund-failure section** below `<ActionButtons />` when `sales.mpRefundFailed === true`. Per UI-SPEC §"Surface 5":
- `<Alert severity="error">` with code block + 3 buttons (Reintentar / MP Dashboard / Ver historial)
- Toast fired via `react-toastify` `toast.error(...)` (existing import in PaymentSummaryModal at line 6)
- Attempt history list (always visible if `attempts.length > 0`)

**Refresh after retry:** call `getSales()` callback (already memoized at line 24-37).

---

### `ventago-app/src/navigation/vertical/index.ts` (config) — MODIFY

**Self-extend** existing pattern at lines 93/110:
```typescript
children.push({ title: t('nav_expense_categories'), icon: 'tabler:category', path: '/configuracion/categorias-gastos', action: 'read', subject: 'configuracion' });
```

**Add (mirror exact shape):**
```typescript
children.push({
  title: t('nav_mercadopago'),
  icon: 'tabler:brand-mercedes',  // or 'logos:mercado-pago'
  path: '/configuracion/mercadopago',
  action: 'read',
  subject: 'configuracion',
});
```
Add `nav_mercadopago` translation to es/en locale files.

**Existing `getAppChildren('admin')`** scope — mp config only visible for admin/superadmin (matches CONTEXT.md branch-level OAuth = admin task).

---

### `ventago-app/src/@core/theme/palette/index.ts` (config) — MODIFY

**Self-extend** existing palette (lines 23-110).

**Existing `info`** (lines 64-69):
```typescript
info: { light: '#1FD5EB', main: '#00CFE8', dark: '#00B6CC', contrastText: whiteColor },
```
**Per UI-SPEC `theme.md`**, override to MP brand cyan:
```typescript
info: { light: '#33c1ee', main: '#00b1ea', dark: '#0091bf', contrastText: '#1a1a2e' },
```
**Existing `warning`** (lines 58-63):
```typescript
warning: { light: '#FFAB5A', main: '#FF9F43', dark: '#E08C3B', contrastText: whiteColor },
```
**Override to sandbox gold per UI-SPEC:**
```typescript
warning: { light: '#f8be5d', main: '#f5a623', dark: '#cc8a1d', contrastText: '#1a1a2e' },
```
**Caution:** This is a global palette change — verify no existing UI assumes default MUI orange `warning`. Phase 29 reuses primary gold for sandbox so the existing `primary` (`#05a7cf` cyan) may also need decision (UI-SPEC says primary becomes gold). Discuss with planner whether to fully migrate primary or only `info`+`warning` for Phase 29.

---

### `ventago-app/package.json` — MODIFY

**Add to dependencies** (alphabetical order between `qrcode` family or near `react`):
```json
"qrcode.react": "^4.2.0",
```
RESEARCH.md confirms version. Run `npm install qrcode.react@^4.2.0` in `ventago-app/`.

---

## Shared Patterns (Cross-Cutting)

### Pattern A — DB underscored mapping

**Source:** `api-ventago/src/app/print/branch-agent.model.ts` line 14 (comment) + project-wide Sequelize config

**Apply to:** All 7 new mp_* models + every raw SQL query

**Rule:** Model uses camelCase (`mpAccountId`, `expiresAt`); DB uses snake_case (`mp_account_id`, `expires_at`). Sequelize-typescript `underscored: true` global setting handles auto-mapping. Migrations and `sequelize.query()` raw SQL **must** use snake_case.

**Excerpt** (`branch-agent.model.ts` line 14):
```typescript
// underscored:true 전역 설정 → DB 컬럼은 snake_case
@Table({ tableName: 'branch_agents', timestamps: true })
```

---

### Pattern B — Auth + Audit + Role gating on controllers

**Source:** `api-ventago/src/app/box/box.controller.ts` (lines 27-45)

**Apply to:** All 7 new MP REST endpoints (qr, oauth, webhook excluded, intents, wallet, transfer, refund)

**Excerpt:**
```typescript
@Post('')
@Auth(ValidRoles.admin, ValidRoles.superadmin, ValidRoles.gerente)
@Audit({
  entityType: 'Caja',
  action: 'create',
  getDescription: (body: any) => `Caja creada: ${body.name}`,
})
async create(@Body() body: any, @GetUser() user?: Users): Promise<any> {
  return super.create(body, user);
}
```

**Role matrix for Phase 29:**
| Endpoint | Roles |
|----------|-------|
| `POST /mercadopago/qr` | admin, gerente, vendedor (POS use) |
| `DELETE /mercadopago/qr/:id` | admin, gerente, vendedor |
| `GET /mercadopago/payment-intents/:id` | admin, gerente, vendedor (polling) |
| `GET /mercadopago/oauth/start` | admin, superadmin |
| `GET /mercadopago/oauth/callback` | (no Auth — public callback, validated by HMAC state) |
| `POST /mercadopago/webhook` | (no Auth — public, validated by re-fetch) |
| `POST /mercadopago/wallets/:id/transfer` | admin, gerente |
| `POST /mercadopago/refunds/:attemptId/retry` | admin, gerente |

---

### Pattern C — Error visibility (inline Alert + global toast)

**Source:** `ventago-app/src/views/homes/components/ProductList/components/PaymentSummaryModal.tsx` (lines 6, 89-120) + memory `feedback_error_visibility`

**Apply to:** All MP UI surfaces (configuracion, payment modal, sales detail, transfer modal)

**Excerpt** (toast import + state pattern):
```typescript
import { toast } from "react-toastify";
// ...
const [pmFetchError, setPmFetchError] = useState<string | null>(null);
// ...
} catch (error: any) {
  setPmFetchError('No se pudo cargar la configuración. Reintentá.');
  toast.error('No se pudo cargar la configuración');
}
```
**Mandatory:** Both inline `<Alert severity="error">{pmFetchError}</Alert>` AND `toast.error(...)` for every error.

---

### Pattern D — Frontend SWR with `useApi` wrapper

**Source:** `ventago-app/src/hooks/useApi.ts` (full file, 18 lines)

**Apply to:** All MP SWR hooks (`useMpAccounts`, `useMpWallets`, `useMpMovements`, `useMpRefundAttempts`, etc.)

**Excerpt:**
```typescript
import useSWR from 'swr'
import type { SWRConfiguration } from 'swr'

export function useApi<T = unknown>(url: string | null, options?: SWRConfiguration) {
  const { data, error, isLoading, mutate } = useSWR<T>(url, options)
  return { data, error, isLoading, mutate }
}
```
**Exception:** `useMpPaymentIntent` (polling) uses raw `useSWR` because it needs custom `refreshInterval: 5000` + `dedupingInterval: 0` (different policy from 5min reference-data dedup).

---

### Pattern E — Module-level Sequelize transaction with row lock

**Source:** RESEARCH.md Pattern 3 (lines 407-429) — no exact codebase analog (Phase 29 is the first to use SELECT FOR UPDATE in service layer)

**Apply to:** `MpWebhookService.processPayment`, `MpPaymentIntentsService.markApproved`, `MpTransferService.transfer`

**Required syntax:**
```typescript
await this.sequelize.transaction(async (t) => {
  const row = await this.model.findByPk(id, {
    lock: t.LOCK.UPDATE,    // explicit — NOT lock: true (RESEARCH.md Pitfall 9)
    transaction: t,
  });
  // check + update + related inserts
});
```
**Inject Sequelize:** `constructor(@InjectConnection() private sequelize: Sequelize)`.

---

### Pattern F — apiConnector.remove() (NOT .delete())

**Source:** Memory `feedback_api_connector` + CLAUDE.md "주의 사항"

**Apply to:** Frontend MP UI delete operations (disconnect account, cancel QR)

**Rule:**
```typescript
// ✓ correct
await apiConnector.remove(`/mercadopago/accounts/${id}`)
// ✗ wrong — does not exist
await apiConnector.delete(`/mercadopago/accounts/${id}`)
```

---

### Pattern G — ESLint blank line before return + before comments

**Source:** CLAUDE.md "ESLint 규칙" + memory `feedback_eslint_check`

**Apply to:** Every new `.ts`/`.tsx` file

**Required:**
```typescript
// blank line above this comment

// blank line above this comment too
function foo() {
  doStuff();

  return value;    // blank line above return
}
```
**Verification:** Run `npm run lint` in both `api-ventago/` and `ventago-app/` before commit. Frontend treats Warning as build error.

---

### Pattern H — apiConnector axios interceptor (no manual token handling)

**Source:** `ventago-app/src/services/api.service.ts` (lines 29-105 — interceptors auto-inject `Authorization` + `x-session-token`)

**Apply to:** All MP frontend calls — just use `apiConnector.get/post/put/remove`. No need to manually attach headers.

```typescript
import apiConnector from 'src/services/api.service'

// Auto headers: Authorization Bearer + x-session-token + sessionId
const intent = await apiConnector.post('/mercadopago/qr', { storeId, amount, pendingVentaId, terminalId })
```

---

### Pattern I — `next/dynamic` code-splitting for new pages

**Source:** `ventago-app/src/pages/configuracion/ventas/index.tsx` (line 5) + `ventago-app/src/pages/control-de-caja/index.tsx` (line 5) + CLAUDE.md "300ms 타겟"

**Apply to:** `pages/configuracion/mercadopago/index.tsx` (mandatory — heavy view with cards + tables + OAuth flow)

**Excerpt:**
```typescript
const McdpgConfigView = dynamic(
  () => import('src/views/mercadopago/McdpgConfigView'),
  { ssr: false },
)
```

---

### Pattern J — `WithAccess` + `acl` ACL gating

**Source:** `ventago-app/src/pages/configuracion/ventas/index.tsx` (lines 9-16)

**Apply to:** New MP page — gate to admin app + `configuracion-mercadopago` module slug.

**Excerpt:**
```typescript
<WithAccess allowedApps={["admin"]} allowedModules={["configuracion-mercadopago"]}>
  <McdpgConfigView/>
</WithAccess>
// ...
McdpgConfigPage.acl = { action: 'read', subject: 'configuracion' }
```
**Requires:** Add `configuracion-mercadopago` module slug to backend module seeder if not present, or reuse existing `configuracion` subject (CONTEXT.md says CASL `configuracion_admin` is acceptable).

---

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `api-ventago/src/app/mercadopago/api-client/mp-api-client.service.ts` | service | external HTTP | First codebase service that wraps axios for outbound REST calls — use RESEARCH.md Pattern 1 verbatim |
| `api-ventago/src/app/mercadopago/crypto/mp-token-crypto.service.ts` | service | pure transform | First column-encryption service — use RESEARCH.md Pattern 2 verbatim |
| `api-ventago/src/app/mercadopago/cron/*.cron.ts` | cron | batch | No mapped codebase cron analog; use `@nestjs/schedule` `@Cron(CronExpression.EVERY_DAY_AT_2AM)` per nest docs |
| `ventago-app/src/views/homes/components/ProductList/components/McdpgQrPanel.tsx` | component | presentational + countdown | Greenfield component; use UI-SPEC §"QR side-panel" + theme tokens directly |
| `ventago-app/src/components/banners/SandboxMpBanner.tsx` | component | presentational | Greenfield; use MUI `<Alert severity="warning">` + UI-SPEC §"Surface 3" copy/style directly |
| `ventago-app/src/types/mercadopago.ts` | types | type defs | Trivial — TS interfaces per CONTEXT.md model field list |

For all "no analog" files, planner should reference **UI-SPEC.md** (frontend) or **RESEARCH.md Patterns 1-5** (backend) directly.

---

## Metadata

**Analog search scope:**
- `api-ventago/src/app/{box,print,sales,expenses,payment-methods,chat,team-chat}/`
- `api-ventago/src/common/{socket,cache,crud}/`
- `api-ventago/migrations/26-*.sql`
- `ventago-app/src/{pages,views,hooks,components,services,navigation,@core/theme}/`

**Files scanned:** ~45 files Read end-to-end + 30 grep/glob targeted lookups

**Pattern extraction date:** 2026-05-05

**Key validations:**
- ✓ snake_case rule confirmed in `box.model.ts` lines 30, 36 + `branch-agent.model.ts` line 14 + `box.service.ts` lines 69-72
- ✓ `emitToTerminal` pattern absent from current `websocket.service.ts` — confirms NEW addition needed
- ✓ `mercadopago` slug already in `payment-methods.seed.ts` line 35-39 — confirms reuse, no migration needed
- ✓ `register_user` SubscribeMessage in `websocket.gateway.ts` line 46-55 → analog for new `register_terminal`
- ✓ `team-chat/TeamChatPanel.tsx` line 52-85 → frontend Socket.io connection pattern with auto-disconnect cleanup
- ✓ `cash-control/list/CashRegisterList.tsx` exists — confirms structure for new `McdpgWalletRow` injection
- ✓ `ProductList.tsx:1162` `handleSubmit("INVOICED", paymentMethods)` — confirmed at line 1162 (CONTEXT.md said 1153 — close enough, planner verifies in implementation)
- ✓ Migration phase pattern `26-XX-step1-schema.sql` → `29-XX-mp-*.sql` shape confirmed
- ✓ DTO pattern from `expenses/dto/create-expenses.dto.ts` — class-validator with Spanish messages
