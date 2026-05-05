---
phase: 29
plan: 02b
type: execute
wave: 1
depends_on: [02]
files_modified:
  - api-ventago/src/app/mercadopago/models/mp-account.model.ts
  - api-ventago/src/app/mercadopago/models/mp-payment-intent.model.ts
  - api-ventago/src/app/mercadopago/models/mp-wallet.model.ts
  - api-ventago/src/app/mercadopago/models/mp-movement.model.ts
  - api-ventago/src/app/mercadopago/models/mp-refund.model.ts
  - api-ventago/src/app/mercadopago/models/mp-refund-attempt.model.ts
  - api-ventago/src/app/mercadopago/models/mp-transfer.model.ts
  - api-ventago/src/app/mercadopago/crypto/mp-token-crypto.service.ts
  - api-ventago/src/app/mercadopago/crypto/mp-token-crypto.service.spec.ts
  - api-ventago/src/app/mercadopago/mercadopago.module.ts
  - api-ventago/src/app/app.module.ts
autonomous: true
requirements:
  - MP-POS-01
  - MP-POS-02
  - MP-POS-03
  - MP-POS-05
  - MP-POS-06
  - MP-POS-07

must_haves:
  truths:
    - "All 7 Sequelize models load with correct snake_case column mapping (matches Plan 02 DDL)"
    - "AES-256-GCM encrypt/decrypt round-trips correctly for any UTF-8 string"
    - "MpTokenCryptoService throws at boot if MP_TOKEN_ENCRYPTION_KEY is missing or wrong length"
    - "MercadopagoModule is registered in app.module.ts and starts without errors"
    - "Token round-trip preserves binary data without UTF-8 corruption"
    - "Tamper detection: modified ciphertext or auth tag throws on decrypt"
  artifacts:
    - path: "api-ventago/src/app/mercadopago/crypto/mp-token-crypto.service.ts"
      provides: "AES-256-GCM encrypt/decrypt"
      contains: "aes-256-gcm"
    - path: "api-ventago/src/app/mercadopago/crypto/mp-token-crypto.service.spec.ts"
      provides: "Unit tests for crypto service (round-trip, tamper detection, missing key)"
    - path: "api-ventago/src/app/mercadopago/mercadopago.module.ts"
      provides: "Module registering all 7 mp_* models + MpTokenCryptoService"
      contains: "SequelizeModule.forFeature"
    - path: "api-ventago/src/app/mercadopago/models/mp-account.model.ts"
      provides: "MpAccount model — OAuth tokens (encrypted) + scope"
      contains: "tableName: 'mp_accounts'"
    - path: "api-ventago/src/app/mercadopago/models/mp-payment-intent.model.ts"
      provides: "MpPaymentIntent model — QR + payment lifecycle"
      contains: "tableName: 'mp_payment_intents'"
    - path: "api-ventago/src/app/mercadopago/models/mp-wallet.model.ts"
      provides: "MpWallet model — virtual Caja MP balance"
      contains: "tableName: 'mp_wallets'"
    - path: "api-ventago/src/app/mercadopago/models/mp-movement.model.ts"
      provides: "MpMovement model — credit/debit ledger"
      contains: "tableName: 'mp_movements'"
    - path: "api-ventago/src/app/mercadopago/models/mp-refund.model.ts"
      provides: "MpRefund model"
      contains: "tableName: 'mp_refunds'"
    - path: "api-ventago/src/app/mercadopago/models/mp-refund-attempt.model.ts"
      provides: "MpRefundAttempt model — retry log"
      contains: "tableName: 'mp_refund_attempts'"
    - path: "api-ventago/src/app/mercadopago/models/mp-transfer.model.ts"
      provides: "MpTransfer model — MP→cash audit"
      contains: "tableName: 'mp_transfers'"
  key_links:
    - from: "api-ventago/src/app/app.module.ts"
      to: "MercadopagoModule"
      via: "imports array"
      pattern: "MercadopagoModule"
    - from: "api-ventago/src/app/mercadopago/crypto/mp-token-crypto.service.ts"
      to: "process.env.MP_TOKEN_ENCRYPTION_KEY"
      via: "constructor read + length validation"
      pattern: "MP_TOKEN_ENCRYPTION_KEY"
    - from: "api-ventago/src/app/mercadopago/models/mp-account.model.ts"
      to: "mp_accounts table"
      via: "tableName: 'mp_accounts'"
      pattern: "tableName: 'mp_accounts'"
---

<objective>
Wave 1b — Code substrate: Build the AES-256-GCM crypto service with full unit tests + boot validation, define all 7 Sequelize-typescript models matching the snake_case DDL from Plan 02, and register the new MercadopagoModule in app.module.ts so all subsequent waves (03 OAuth, 04 QR, 05 webhook, 06–09) can inject these primitives.

Purpose: Plan 02 created the DB tables; this plan creates the TypeScript representation. Splitting from Plan 02 keeps each plan within the 15-file budget and makes the schema independently runnable on prod (ops can apply Plan 02 SQL on srv803182, then deploy Plan 02b code without coordination).

Output: 7 Sequelize models (compile under TS strict), 1 production-ready crypto service with 100% test coverage on encrypt/decrypt/boot-validation paths, and a registered NestJS module exporting MpTokenCryptoService for downstream plans.
</objective>

<execution_context>
@/Users/marcoskim/Trabajos_Programming/ACE_online_1.0/.claude/get-shit-done/workflows/execute-plan.md
@/Users/marcoskim/Trabajos_Programming/ACE_online_1.0/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/STATE.md
@.planning/phases/29-pos-mercadopago-qr-din-mico/29-CONTEXT.md
@.planning/phases/29-pos-mercadopago-qr-din-mico/29-SPEC.md
@.planning/phases/29-pos-mercadopago-qr-din-mico/29-RESEARCH.md
@.planning/phases/29-pos-mercadopago-qr-din-mico/29-PATTERNS.md
@.planning/phases/29-pos-mercadopago-qr-din-mico/29-02-SUMMARY.md
@CLAUDE.md
@api-ventago/src/app/print/branch-agent.model.ts
@api-ventago/src/app/box/box.model.ts
@api-ventago/src/app/print/print.module.ts
</context>

<interfaces>
<!-- Sequelize model exports (other plans will import these) -->

```typescript
// api-ventago/src/app/mercadopago/models/mp-account.model.ts
export class MpAccount extends Model {
  declare id: number;
  declare storeId: number;
  declare branchId: number | null;
  declare mpUserId: string;        // string — MP user ids can be large
  declare accessToken: string;     // ENCRYPTED — always pass through MpTokenCryptoService.decrypt
  declare refreshToken: string;    // ENCRYPTED
  declare publicKey: string | null;
  declare environment: 'sandbox' | 'production';
  declare externalPosId: string | null;  // RESEARCH §Pitfall 3 — set after Store/POS registration
  declare expiresAt: Date | null;
  declare connectedAt: Date;
  declare disconnectedAt: Date | null;
}

// api-ventago/src/app/mercadopago/models/mp-payment-intent.model.ts
export class MpPaymentIntent extends Model {
  declare id: number;
  declare mpAccountId: number;
  declare storeId: number;
  declare branchId: number | null;
  declare terminalId: number;
  declare pendingVentaId: number;
  declare amount: number;
  declare mpOrderId: string | null;
  declare qrData: string | null;
  declare paymentId: string | null;       // UNIQUE — idempotency lock
  declare status: 'pending' | 'approved' | 'cancelled' | 'expired' | 'failed';
  declare expiresAt: Date;
  declare approvedAt: Date | null;
}

// api-ventago/src/app/mercadopago/models/mp-wallet.model.ts
export class MpWallet extends Model {
  declare id: number;
  declare mpAccountId: number;     // UNIQUE — 1 wallet per mp_account
  declare storeId: number;
  declare branchId: number | null;
  declare balance: number;          // NUMERIC(14,2)
  declare currency: string;         // CHAR(3) default 'ARS'
  declare lastSyncedAt: Date | null;
}

// api-ventago/src/app/mercadopago/models/mp-movement.model.ts
export class MpMovement extends Model {
  declare id: number;
  declare mpWalletId: number;
  declare type: 'credit' | 'debit' | 'transfer_out' | 'transfer_in' | 'refund_debit';
  declare amount: number;
  declare saleId: number | null;
  declare refundId: number | null;
  declare mpPaymentId: string | null;
  declare transferId: number | null;
  declare note: string | null;
}

// api-ventago/src/app/mercadopago/models/mp-refund.model.ts
export class MpRefund extends Model {
  declare id: number;
  declare saleId: number;
  declare mpPaymentId: string;
  declare refundId: string;        // MP refund_id from /v1/payments/{id}/refunds
  declare amount: number;
  declare status: string;          // mirror MP status
}

// api-ventago/src/app/mercadopago/models/mp-refund-attempt.model.ts
export class MpRefundAttempt extends Model {
  declare id: number;
  declare saleId: number;
  declare mpPaymentId: string;
  declare attemptNo: number;
  declare status: 'pending' | 'success' | 'failed';
  declare errorMessage: string | null;
  declare attemptedAt: Date;
}

// api-ventago/src/app/mercadopago/models/mp-transfer.model.ts
export class MpTransfer extends Model {
  declare id: number;
  declare mpWalletId: number;
  declare targetBoxId: number;
  declare amount: number;
  declare userId: number;
  declare note: string | null;
  declare transferredAt: Date;
}

// api-ventago/src/app/mercadopago/crypto/mp-token-crypto.service.ts
@Injectable()
export class MpTokenCryptoService {
  encrypt(plaintext: string): string;        // returns "iv_b64:tag_b64:ct_b64"
  decrypt(encoded: string): string;          // throws on tamper or malformed
}
```

<!-- analog patterns -->
- branch-agent.model.ts (line 14): tableName + timestamps decorator
- box.model.ts (lines 17-46): FK + BelongsTo + storeId/branchId pattern
- print.module.ts (lines 13-19): SequelizeModule.forFeature pattern
</interfaces>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: Build MpTokenCryptoService (AES-256-GCM) with full unit test coverage</name>
  <read_first>
    - .planning/phases/29-pos-mercadopago-qr-din-mico/29-RESEARCH.md (Pattern 2 lines 332-380 — full crypto service code; §Anti-Patterns "Reusing the same IV", "Storing tokens plaintext")
    - .planning/phases/29-pos-mercadopago-qr-din-mico/29-PATTERNS.md (lines 318-329 — "use RESEARCH.md Pattern 2 verbatim")
    - .planning/phases/29-pos-mercadopago-qr-din-mico/29-CONTEXT.md (D-A1-05: AES-256-GCM, master key MP_TOKEN_ENCRYPTION_KEY, format ${iv}:${authTag}:${ciphertext} base64)
    - api-ventago/src/app/payment-methods/payment-methods.module.ts (jest spec colocation pattern in this codebase)
    - api-ventago/package.json (jest config — find testRegex pattern, ensure spec file matches)
  </read_first>
  <behavior>
    - Test 1 (RED → GREEN): encrypt(plaintext) returns 3-part base64 string `iv:tag:ct`
    - Test 2: decrypt(encrypt(x)) === x for ASCII strings
    - Test 3: decrypt(encrypt(x)) === x for UTF-8 multi-byte (Korean: '한글토큰', Spanish accents: 'señaña')
    - Test 4: Two encryptions of same plaintext yield DIFFERENT ciphertexts (random IV per call)
    - Test 5: Tampering with the ciphertext throws (auth tag verification)
    - Test 6: Tampering with the auth tag throws
    - Test 7: Constructor throws if MP_TOKEN_ENCRYPTION_KEY env is missing
    - Test 8: Constructor throws if MP_TOKEN_ENCRYPTION_KEY is wrong length (not 64 hex chars)
    - Test 9: Constructor accepts valid 64-char hex key
  </behavior>
  <action>
    1. Create `api-ventago/src/app/mercadopago/crypto/mp-token-crypto.service.ts` with this exact content (verbatim from RESEARCH §Pattern 2 + ESLint blank-lines):
       ```typescript
       import { Injectable } from '@nestjs/common';
       import { createCipheriv, createDecipheriv, randomBytes } from 'crypto';

       const ALGO = 'aes-256-gcm';
       const IV_LEN = 12;     // 96-bit, GCM standard (NEVER reuse with same key)
       const TAG_LEN = 16;
       const KEY_HEX_LEN = 64; // 32 bytes hex

       @Injectable()
       export class MpTokenCryptoService {
         private readonly key: Buffer;

         constructor() {
           const hex = process.env.MP_TOKEN_ENCRYPTION_KEY;

           if (!hex || hex.length !== KEY_HEX_LEN) {
             throw new Error(
               'MP_TOKEN_ENCRYPTION_KEY must be 32 bytes hex (64 hex chars)',
             );
           }
           this.key = Buffer.from(hex, 'hex');

           if (this.key.length !== 32) {
             throw new Error(
               'MP_TOKEN_ENCRYPTION_KEY decoded length must be 32 bytes (invalid hex)',
             );
           }
         }

         // 평문 → "iv_b64:tag_b64:ct_b64"
         encrypt(plaintext: string): string {
           // 96-bit IV — 호출마다 신규 생성 (GCM 보안의 핵심)
           const iv = randomBytes(IV_LEN);
           const cipher = createCipheriv(ALGO, this.key, iv);
           const ct = Buffer.concat([cipher.update(plaintext, 'utf8'), cipher.final()]);
           const tag = cipher.getAuthTag();

           return [
             iv.toString('base64'),
             tag.toString('base64'),
             ct.toString('base64'),
           ].join(':');
         }

         // "iv_b64:tag_b64:ct_b64" → 평문
         decrypt(encoded: string): string {
           const parts = encoded.split(':');

           if (parts.length !== 3) {
             throw new Error('Invalid encrypted token format');
           }
           const [ivB64, tagB64, ctB64] = parts;

           if (!ivB64 || !tagB64 || !ctB64) {
             throw new Error('Invalid encrypted token format');
           }
           const iv = Buffer.from(ivB64, 'base64');
           const tag = Buffer.from(tagB64, 'base64');
           const ct = Buffer.from(ctB64, 'base64');

           if (iv.length !== IV_LEN) {
             throw new Error(`IV length must be ${IV_LEN} bytes`);
           }
           if (tag.length !== TAG_LEN) {
             throw new Error(`Auth tag length must be ${TAG_LEN} bytes`);
           }
           const decipher = createDecipheriv(ALGO, this.key, iv);

           decipher.setAuthTag(tag);
           const pt = Buffer.concat([decipher.update(ct), decipher.final()]);

           return pt.toString('utf8');
         }
       }
       ```
    2. Create `api-ventago/src/app/mercadopago/crypto/mp-token-crypto.service.spec.ts`:
       ```typescript
       /* eslint-disable @typescript-eslint/no-explicit-any */
       // Phase 29 — MpTokenCryptoService unit tests (RED → GREEN)
       import { MpTokenCryptoService } from './mp-token-crypto.service';

       const VALID_KEY = 'a'.repeat(64); // 64 hex chars (32 bytes when decoded)
       const SHORT_KEY = 'a'.repeat(32);
       const NON_HEX = 'z'.repeat(64);   // 64 chars but not hex

       describe('MpTokenCryptoService', () => {
         let originalKey: string | undefined;

         beforeEach(() => {
           originalKey = process.env.MP_TOKEN_ENCRYPTION_KEY;
           process.env.MP_TOKEN_ENCRYPTION_KEY = VALID_KEY;
         });

         afterEach(() => {
           if (originalKey === undefined) delete process.env.MP_TOKEN_ENCRYPTION_KEY;
           else process.env.MP_TOKEN_ENCRYPTION_KEY = originalKey;
         });

         describe('constructor (boot validation)', () => {
           it('accepts a valid 64-char hex key', () => {
             expect(() => new MpTokenCryptoService()).not.toThrow();
           });

           it('throws if env var is missing', () => {
             delete process.env.MP_TOKEN_ENCRYPTION_KEY;
             expect(() => new MpTokenCryptoService()).toThrow(/must be 32 bytes hex/);
           });

           it('throws if env var is wrong length', () => {
             process.env.MP_TOKEN_ENCRYPTION_KEY = SHORT_KEY;
             expect(() => new MpTokenCryptoService()).toThrow(/must be 32 bytes hex/);
           });

           it('throws if env var contains non-hex characters', () => {
             process.env.MP_TOKEN_ENCRYPTION_KEY = NON_HEX;
             expect(() => new MpTokenCryptoService()).toThrow(/decoded length/);
           });
         });

         describe('encrypt / decrypt round-trip', () => {
           it('round-trips ASCII plaintext', () => {
             const svc = new MpTokenCryptoService();
             const plain = 'APP_USR-1234567890-052625-abcdef-9876543';
             const enc = svc.encrypt(plain);

             expect(enc).not.toBe(plain);
             expect(enc.split(':')).toHaveLength(3);
             expect(svc.decrypt(enc)).toBe(plain);
           });

           it('round-trips UTF-8 multi-byte (Korean + Spanish accents)', () => {
             const svc = new MpTokenCryptoService();
             const plain = '한글토큰-señaña-ñoño-Niño';
             const enc = svc.encrypt(plain);

             expect(svc.decrypt(enc)).toBe(plain);
           });

           it('produces DIFFERENT ciphertexts for same plaintext (random IV)', () => {
             const svc = new MpTokenCryptoService();
             const plain = 'same-input';
             const e1 = svc.encrypt(plain);
             const e2 = svc.encrypt(plain);

             expect(e1).not.toBe(e2);                  // IV differs
             expect(svc.decrypt(e1)).toBe(plain);     // both decrypt
             expect(svc.decrypt(e2)).toBe(plain);
           });
         });

         describe('tamper detection', () => {
           it('throws when ciphertext is tampered', () => {
             const svc = new MpTokenCryptoService();
             const enc = svc.encrypt('payload');
             const [iv, tag, ct] = enc.split(':');
             const tampered = `${iv}:${tag}:${ct.slice(0, -1)}A`;

             expect(() => svc.decrypt(tampered)).toThrow();
           });

           it('throws when auth tag is tampered', () => {
             const svc = new MpTokenCryptoService();
             const enc = svc.encrypt('payload');
             const [iv, tag, ct] = enc.split(':');
             const tamperedTag = `${tag.slice(0, -1)}A`;
             const tampered = `${iv}:${tamperedTag}:${ct}`;

             expect(() => svc.decrypt(tampered)).toThrow();
           });

           it('throws on malformed format (not 3 parts)', () => {
             const svc = new MpTokenCryptoService();

             expect(() => svc.decrypt('only-one-part')).toThrow(/format/);
             expect(() => svc.decrypt('two:parts')).toThrow(/format/);
             expect(() => svc.decrypt('a:b:c:d')).toThrow(/format/);
           });

           it('throws on empty string', () => {
             const svc = new MpTokenCryptoService();

             expect(() => svc.decrypt('')).toThrow();
           });
         });
       });
       ```
    3. Run `cd api-ventago && npx jest --testPathPattern=mp-token-crypto --bail` — must pass all tests (~10 tests, <2s).
  </action>
  <verify>
    <automated>cd api-ventago &amp;&amp; npx jest --testPathPattern=mp-token-crypto --bail 2&gt;&amp;1 | tail -10 | grep -E "Tests:.*passed.*total"</automated>
  </verify>
  <acceptance_criteria>
    - `cd api-ventago && npx jest --testPathPattern=mp-token-crypto` exits 0
    - Test count is at least 10 (constructor: 4, round-trip: 3, tamper: 4)
    - 0 failed tests
    - `grep "aes-256-gcm" api-ventago/src/app/mercadopago/crypto/mp-token-crypto.service.ts` returns at least 1 line
    - `grep -E "(getAuthTag|setAuthTag)" api-ventago/src/app/mercadopago/crypto/mp-token-crypto.service.ts` returns at least 2 lines (both required for GCM)
    - `grep "randomBytes(IV_LEN)" api-ventago/src/app/mercadopago/crypto/mp-token-crypto.service.ts` returns 1 line (IV is random per call)
    - No plaintext key handling outside constructor
  </acceptance_criteria>
  <done>MpTokenCryptoService passes all 10 unit tests including tamper detection + boot validation.</done>
</task>

<task type="auto" tdd="false">
  <name>Task 2: Define 7 Sequelize models + register MercadopagoModule in app.module.ts</name>
  <read_first>
    - api-ventago/src/app/print/branch-agent.model.ts (full file — model template, declare keyword, FK + BelongsTo, JSONB, snake_case via underscored:true global)
    - api-ventago/src/app/box/box.model.ts (lines 17-46 — store/branch FK pattern)
    - api-ventago/src/app/print/print.module.ts (full file — SequelizeModule.forFeature pattern)
    - api-ventago/src/app/app.module.ts (current imports list + structure to add MercadopagoModule)
    - .planning/phases/29-pos-mercadopago-qr-din-mico/29-RESEARCH.md (lines 624-678 — mp-payment-intent.model.ts exemplar)
    - .planning/phases/29-pos-mercadopago-qr-din-mico/29-PATTERNS.md (lines 88-176 — model pattern assignments per file)
    - api-ventago/src/app/store/store.model.ts (Store model — for FK BelongsTo)
    - api-ventago/src/app/branch/branch.model.ts (Branch model — for FK BelongsTo)
    - api-ventago/src/app/terminal/terminal.model.ts (Terminal model — for FK BelongsTo on intents)
    - api-ventago/src/app/users/users.model.ts (Users model — for FK BelongsTo on transfers)
    - api-ventago/src/app/sales/sales.model.ts (Sale model — for FK BelongsTo on movements/refunds)
    - api-ventago/src/app/box/box.model.ts (Box model — for FK BelongsTo on transfers)
  </read_first>
  <behavior>
    - All 7 models compile with TypeScript strict mode (use `declare` keyword on every column field)
    - Each model has explicit `@Table({ tableName: 'mp_*', timestamps: true })` decorator
    - All FK columns use `@ForeignKey(() => RelatedModel)` + `@BelongsTo(() => RelatedModel)` pairs
    - mp_account access_token / refresh_token columns are TEXT (encrypted)
    - mp_payment_intent.paymentId is unique (matches DB UNIQUE)
    - mp_wallet.mpAccountId is unique
    - MercadopagoModule registers all 7 models via SequelizeModule.forFeature
    - app.module.ts imports MercadopagoModule
    - Backend boots cleanly with the new module registered (`npm run build` passes, no schema drift errors from Sequelize)
  </behavior>
  <action>
    1. Create `api-ventago/src/app/mercadopago/models/mp-account.model.ts`:
       ```typescript
       import {
         BelongsTo, Column, DataType, ForeignKey, Model, Table,
       } from 'sequelize-typescript';
       import { Store } from '../../store/store.model';
       import { Branch } from '../../branch/branch.model';

       // underscored:true 전역 설정 → DB 컬럼은 snake_case
       @Table({ tableName: 'mp_accounts', timestamps: true })
       export class MpAccount extends Model {
         @ForeignKey(() => Store)
         @Column({ type: DataType.INTEGER, allowNull: false })
         declare storeId: number;

         @BelongsTo(() => Store, { onDelete: 'CASCADE', foreignKey: 'storeId' })
         store?: Store;

         @ForeignKey(() => Branch)
         @Column({ type: DataType.INTEGER, allowNull: true })
         declare branchId: number | null;

         @BelongsTo(() => Branch, { onDelete: 'CASCADE', foreignKey: 'branchId' })
         branch?: Branch;

         @Column({ type: DataType.STRING(64), allowNull: false })
         declare mpUserId: string;

         // AES-256-GCM 암호화 (iv_b64:tag_b64:ct_b64) — MpTokenCryptoService 통과 필수
         @Column({ type: DataType.TEXT, allowNull: false })
         declare accessToken: string;

         @Column({ type: DataType.TEXT, allowNull: false })
         declare refreshToken: string;

         @Column({ type: DataType.STRING(255), allowNull: true })
         declare publicKey: string | null;

         @Column({ type: DataType.STRING(16), allowNull: false, defaultValue: 'sandbox' })
         declare environment: 'sandbox' | 'production';

         // RESEARCH §Pitfall 3 — Store/POS 등록 후 채워짐
         @Column({ type: DataType.STRING(60), allowNull: true })
         declare externalPosId: string | null;

         @Column({ type: DataType.DATE, allowNull: true })
         declare expiresAt: Date | null;

         @Column({ type: DataType.DATE, allowNull: false, defaultValue: DataType.NOW })
         declare connectedAt: Date;

         @Column({ type: DataType.DATE, allowNull: true })
         declare disconnectedAt: Date | null;
       }
       ```
    2. Create `api-ventago/src/app/mercadopago/models/mp-payment-intent.model.ts`:
       ```typescript
       import {
         BelongsTo, Column, DataType, ForeignKey, Model, Table,
       } from 'sequelize-typescript';
       import { Store } from '../../store/store.model';
       import { Branch } from '../../branch/branch.model';
       import { Terminal } from '../../terminal/terminal.model';
       import { MpAccount } from './mp-account.model';

       @Table({ tableName: 'mp_payment_intents', timestamps: true })
       export class MpPaymentIntent extends Model {
         @ForeignKey(() => MpAccount)
         @Column({ type: DataType.INTEGER, allowNull: false })
         declare mpAccountId: number;

         @BelongsTo(() => MpAccount) mpAccount?: MpAccount;

         @ForeignKey(() => Store)
         @Column({ type: DataType.INTEGER, allowNull: false })
         declare storeId: number;

         @ForeignKey(() => Branch)
         @Column({ type: DataType.INTEGER, allowNull: true })
         declare branchId: number | null;

         @ForeignKey(() => Terminal)
         @Column({ type: DataType.INTEGER, allowNull: false })
         declare terminalId: number;

         @Column({ type: DataType.INTEGER, allowNull: false })
         declare pendingVentaId: number;

         @Column({ type: DataType.NUMERIC(14, 2), allowNull: false })
         declare amount: number;

         @Column({ type: DataType.STRING(64), allowNull: true })
         declare mpOrderId: string | null;

         @Column({ type: DataType.TEXT, allowNull: true })
         declare qrData: string | null;

         // 멱등성 핵심 — webhook 중복 차단
         @Column({ type: DataType.STRING(32), allowNull: true, unique: true })
         declare paymentId: string | null;

         @Column({
           type: DataType.STRING(20),
           allowNull: false,
           defaultValue: 'pending',
         })
         declare status: 'pending' | 'approved' | 'cancelled' | 'expired' | 'failed';

         @Column({ type: DataType.DATE, allowNull: false })
         declare expiresAt: Date;

         @Column({ type: DataType.DATE, allowNull: true })
         declare approvedAt: Date | null;
       }
       ```
    3. Create `api-ventago/src/app/mercadopago/models/mp-wallet.model.ts`:
       ```typescript
       import {
         BelongsTo, Column, DataType, ForeignKey, Model, Table,
       } from 'sequelize-typescript';
       import { Store } from '../../store/store.model';
       import { Branch } from '../../branch/branch.model';
       import { MpAccount } from './mp-account.model';

       @Table({ tableName: 'mp_wallets', timestamps: true })
       export class MpWallet extends Model {
         @ForeignKey(() => MpAccount)
         @Column({ type: DataType.INTEGER, allowNull: false, unique: true })
         declare mpAccountId: number;

         @BelongsTo(() => MpAccount) mpAccount?: MpAccount;

         @ForeignKey(() => Store)
         @Column({ type: DataType.INTEGER, allowNull: false })
         declare storeId: number;

         @ForeignKey(() => Branch)
         @Column({ type: DataType.INTEGER, allowNull: true })
         declare branchId: number | null;

         @Column({ type: DataType.NUMERIC(14, 2), allowNull: false, defaultValue: 0 })
         declare balance: number;

         @Column({ type: DataType.CHAR(3), allowNull: false, defaultValue: 'ARS' })
         declare currency: string;

         @Column({ type: DataType.DATE, allowNull: true })
         declare lastSyncedAt: Date | null;
       }
       ```
    4. Create `api-ventago/src/app/mercadopago/models/mp-movement.model.ts`:
       ```typescript
       import {
         BelongsTo, Column, DataType, ForeignKey, Model, Table,
       } from 'sequelize-typescript';
       import { Sale } from '../../sales/sales.model';
       import { MpWallet } from './mp-wallet.model';

       @Table({ tableName: 'mp_movements', timestamps: true, updatedAt: false })
       export class MpMovement extends Model {
         @ForeignKey(() => MpWallet)
         @Column({ type: DataType.INTEGER, allowNull: false })
         declare mpWalletId: number;

         @BelongsTo(() => MpWallet) mpWallet?: MpWallet;

         @Column({ type: DataType.STRING(16), allowNull: false })
         declare type: 'credit' | 'debit' | 'transfer_out' | 'transfer_in' | 'refund_debit';

         @Column({ type: DataType.NUMERIC(14, 2), allowNull: false })
         declare amount: number;

         @ForeignKey(() => Sale)
         @Column({ type: DataType.INTEGER, allowNull: true })
         declare saleId: number | null;

         @Column({ type: DataType.INTEGER, allowNull: true })
         declare refundId: number | null;

         @Column({ type: DataType.STRING(32), allowNull: true })
         declare mpPaymentId: string | null;

         @Column({ type: DataType.INTEGER, allowNull: true })
         declare transferId: number | null;

         @Column({ type: DataType.STRING(255), allowNull: true })
         declare note: string | null;
       }
       ```
    5. Create `api-ventago/src/app/mercadopago/models/mp-refund.model.ts`:
       ```typescript
       import {
         BelongsTo, Column, DataType, ForeignKey, Model, Table,
       } from 'sequelize-typescript';
       import { Sale } from '../../sales/sales.model';

       @Table({ tableName: 'mp_refunds', timestamps: true })
       export class MpRefund extends Model {
         @ForeignKey(() => Sale)
         @Column({ type: DataType.INTEGER, allowNull: false })
         declare saleId: number;

         @BelongsTo(() => Sale) sale?: Sale;

         @Column({ type: DataType.STRING(32), allowNull: false })
         declare mpPaymentId: string;

         @Column({ type: DataType.STRING(32), allowNull: false, unique: true })
         declare refundId: string;

         @Column({ type: DataType.NUMERIC(14, 2), allowNull: false })
         declare amount: number;

         @Column({ type: DataType.STRING(32), allowNull: false, defaultValue: 'approved' })
         declare status: string;
       }
       ```
    6. Create `api-ventago/src/app/mercadopago/models/mp-refund-attempt.model.ts`:
       ```typescript
       import {
         BelongsTo, Column, DataType, ForeignKey, Model, Table,
       } from 'sequelize-typescript';
       import { Sale } from '../../sales/sales.model';

       @Table({ tableName: 'mp_refund_attempts', timestamps: true })
       export class MpRefundAttempt extends Model {
         @ForeignKey(() => Sale)
         @Column({ type: DataType.INTEGER, allowNull: false })
         declare saleId: number;

         @BelongsTo(() => Sale) sale?: Sale;

         @Column({ type: DataType.STRING(32), allowNull: false })
         declare mpPaymentId: string;

         @Column({ type: DataType.INTEGER, allowNull: false })
         declare attemptNo: number;

         @Column({ type: DataType.STRING(16), allowNull: false, defaultValue: 'pending' })
         declare status: 'pending' | 'success' | 'failed';

         @Column({ type: DataType.STRING(500), allowNull: true })
         declare errorMessage: string | null;

         @Column({ type: DataType.DATE, allowNull: false, defaultValue: DataType.NOW })
         declare attemptedAt: Date;
       }
       ```
    7. Create `api-ventago/src/app/mercadopago/models/mp-transfer.model.ts`:
       ```typescript
       import {
         BelongsTo, Column, DataType, ForeignKey, Model, Table,
       } from 'sequelize-typescript';
       import { Box } from '../../box/box.model';
       import { Users } from '../../users/users.model';
       import { MpWallet } from './mp-wallet.model';

       @Table({ tableName: 'mp_transfers', timestamps: true })
       export class MpTransfer extends Model {
         @ForeignKey(() => MpWallet)
         @Column({ type: DataType.INTEGER, allowNull: false })
         declare mpWalletId: number;

         @BelongsTo(() => MpWallet) mpWallet?: MpWallet;

         @ForeignKey(() => Box)
         @Column({ type: DataType.INTEGER, allowNull: false })
         declare targetBoxId: number;

         @Column({ type: DataType.NUMERIC(14, 2), allowNull: false })
         declare amount: number;

         @ForeignKey(() => Users)
         @Column({ type: DataType.INTEGER, allowNull: false })
         declare userId: number;

         @Column({ type: DataType.STRING(255), allowNull: true })
         declare note: string | null;

         @Column({ type: DataType.DATE, allowNull: false, defaultValue: DataType.NOW })
         declare transferredAt: Date;
       }
       ```
    8. Create `api-ventago/src/app/mercadopago/mercadopago.module.ts`:
       ```typescript
       import { Module } from '@nestjs/common';
       import { SequelizeModule } from '@nestjs/sequelize';

       import { MpAccount } from './models/mp-account.model';
       import { MpPaymentIntent } from './models/mp-payment-intent.model';
       import { MpWallet } from './models/mp-wallet.model';
       import { MpMovement } from './models/mp-movement.model';
       import { MpRefund } from './models/mp-refund.model';
       import { MpRefundAttempt } from './models/mp-refund-attempt.model';
       import { MpTransfer } from './models/mp-transfer.model';

       import { MpTokenCryptoService } from './crypto/mp-token-crypto.service';

       // Phase 29: Wave 1 모듈 골격 — 모든 mp_* 모델 + 암호화 서비스 등록
       // 추가 컨트롤러/서비스는 Plans 03~09 에서 점진적으로 추가
       @Module({
         imports: [
           SequelizeModule.forFeature([
             MpAccount,
             MpPaymentIntent,
             MpWallet,
             MpMovement,
             MpRefund,
             MpRefundAttempt,
             MpTransfer,
           ]),
         ],
         providers: [MpTokenCryptoService],
         exports: [MpTokenCryptoService, SequelizeModule],
       })
       export class MercadopagoModule {}
       ```
    9. Edit `api-ventago/src/app/app.module.ts`:
       - Add `import { MercadopagoModule } from './mercadopago/mercadopago.module';` to the imports section (alphabetical with other module imports)
       - Add `MercadopagoModule` to the `imports: [...]` array of the `@Module({})` decorator (preserve existing order convention)
    10. Verify backend boots: `cd api-ventago && npm run build` (TypeScript compile passes — Sequelize model loading is verified at boot, but build catches type errors first).
    11. Run jest crypto spec to confirm nothing broke: `cd api-ventago && npx jest --testPathPattern=mp-token-crypto`
  </action>
  <verify>
    <automated>cd api-ventago &amp;&amp; npm run build 2&gt;&amp;1 | tail -5 &amp;&amp; ls api-ventago/src/app/mercadopago/models/ | wc -l &amp;&amp; grep -l "MercadopagoModule" api-ventago/src/app/app.module.ts &amp;&amp; npx jest --testPathPattern=mp-token-crypto --bail 2&gt;&amp;1 | tail -5 | grep "passed"</automated>
  </verify>
  <acceptance_criteria>
    - All 7 model files exist under `api-ventago/src/app/mercadopago/models/`
    - `cd api-ventago && npm run build` exits 0 (TypeScript strict mode compiles all models)
    - `grep -c "tableName: 'mp_" api-ventago/src/app/mercadopago/models/*.ts` returns 7 (one per model)
    - `grep -c "declare " api-ventago/src/app/mercadopago/models/mp-payment-intent.model.ts` returns at least 11 (every column field uses `declare`)
    - `grep "MercadopagoModule" api-ventago/src/app/app.module.ts` returns at least 2 lines (import + array entry)
    - `grep "SequelizeModule.forFeature" api-ventago/src/app/mercadopago/mercadopago.module.ts` returns 1 line
    - `grep -E "^\s+Mp(Account|PaymentIntent|Wallet|Movement|Refund|RefundAttempt|Transfer),?$" api-ventago/src/app/mercadopago/mercadopago.module.ts | wc -l` returns 7 (all 7 models in forFeature)
    - `grep "MpTokenCryptoService" api-ventago/src/app/mercadopago/mercadopago.module.ts` returns at least 2 lines (import + provider)
    - Crypto spec still passes (10 tests green)
  </acceptance_criteria>
  <done>7 models compile, MercadopagoModule registers all models + crypto service, app.module.ts wires it up, build passes, crypto tests still green.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| App boot ↔ MP_TOKEN_ENCRYPTION_KEY env | Constructor reads env once; throws if invalid (fail-fast) |
| Sequelize model layer ↔ DB | Parameterized queries; underscored:true global mapping; no raw user input concatenation |
| AES-256-GCM ciphertext ↔ DB storage | Tokens NEVER plaintext; auth tag verification on every decrypt |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-29-02 | I (Information Disclosure) | mp_accounts.access_token + refresh_token | mitigate | AES-256-GCM via MpTokenCryptoService (Pattern 2 verbatim from RESEARCH); 96-bit IV per encryption (never reuse — anti-pattern enforced); auth tag detects tampering. Tests prove tamper detection (Test 5/6 above). |
| T-29-08 | T (Tampering) | MP_TOKEN_ENCRYPTION_KEY env var | mitigate | Constructor validates length (64 hex chars = 32 bytes) + decoded buffer length. Throws clear error at boot — service won't start with bad key. Tests cover 4 boot validation paths (missing/short/non-hex/valid). |
</threat_model>

<verification>
- 10 MpTokenCryptoService unit tests pass
- All 7 Sequelize models compile under TypeScript strict mode
- MercadopagoModule registered in app.module.ts; backend builds without error
- All 7 model files have correct `tableName` matching Plan 02 DDL
</verification>

<success_criteria>
- 7 Sequelize models export classes matching the table schemas from Plan 02
- MpTokenCryptoService passes all 10 unit tests (encrypt/decrypt round-trip, tamper detection, boot validation)
- `npm run build` in api-ventago exits 0
- MercadopagoModule registered in app.module.ts and exports MpTokenCryptoService for downstream plans (03 OAuth, 04 QR, 05 webhook, 09 refunds)
</success_criteria>

<output>
After completion, create `.planning/phases/29-pos-mercadopago-qr-din-mico/29-02b-SUMMARY.md` with:
- Sequelize model class names + their table mappings
- MpTokenCryptoService API surface (encrypt/decrypt signatures + boot validation)
- Confirmation that backend builds + boots
- MercadopagoModule exports list (for downstream plan injection)
</output>
