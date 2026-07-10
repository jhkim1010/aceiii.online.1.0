# Factura Electrónica — Plan 1: 백엔드 기반 + 발급 코어 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ventago(api-ventago) 안에서 판매건을 AFIP ws 게이트웨이로 보내 CAE를 발급받고 DB에 기록하는 백엔드 코어를 만든다 (REST/PDF/프론트는 Plan 2~3).

**Architecture:** NestJS 신규 모듈 `src/app/afip/`. 순수 로직(code-maps, qr-builder, partial-invoice)은 CoolSyncro에서 이식하여 jest 단위테스트로 검증. 발급은 swappable `CaeProvider` 인터페이스 뒤의 `rest-gateway.provider`(ws)가 담당. 오케스트레이션 서비스가 발행자 로드 → comprobante 자동선택 → 부분발급 스케일 → 게이트웨이 호출 → afip_vouchers/sales 저장을 조율한다. 게이트웨이 HTTP 호출은 DB 트랜잭션 밖에서 실행(pool 낭비 방지).

**Tech Stack:** NestJS 11, Sequelize + sequelize-typescript(`underscored:true`), PostgreSQL(운영 PG10 / 로컬 PG18), axios, jest + ts-jest.

## Global Constraints

- Sequelize `underscored: true` — 모델 camelCase 속성 → DB snake_case 컬럼. SQL 직접 실행 시 snake_case.
- PostgreSQL pool min=10/max=80 유지. **게이트웨이 HTTP 호출은 DB connection 점유 밖에서** 실행.
- 마이그레이션은 additive만, 운영 PG10 문법 호환(`ADD COLUMN IF NOT EXISTS`는 PG10 지원 — 사용 가능; `CREATE TABLE IF NOT EXISTS` 사용 가능). `api-ventago/migrations/`에 SQL 파일.
- 멀티테넌트: 모든 쿼리에 `store_id` 격리 + 소유권 검증.
- 주석 한국어, 식별자 영어.
- 테스트: `*.spec.ts`, `npm test -- --testPathPattern=<name>`.
- ESLint: `newline-before-return`, `lines-around-comment`, `no-unused-vars` 위반 시 빌드 실패. `return` 위·주석 위 빈 줄 필수.
- CAE 발급은 **비멱등** — ambiguous(타임아웃/5xx) 응답 시 재발급 절대 금지, `afip_status='verificar'`로만 표시.
- 금액 반올림: 센트(×100) 정수 공간 연산(BigDecimal DOWN 미러).

---

### Task 1: DB 마이그레이션 + Sequelize 모델

**Files:**
- Create: `api-ventago/migrations/afip-factura-electronica.sql`
- Create: `api-ventago/src/app/afip/models/afip-issuer.model.ts`
- Create: `api-ventago/src/app/afip/models/afip-voucher.model.ts`
- Modify: `api-ventago/src/app/sales/sales.model.ts` (afip 요약 컬럼 6개)
- Modify: `api-ventago/src/app/store/config/storeConfig.model.ts` (플래그 5개)

**Interfaces:**
- Produces: `AfipIssuer` 모델 (필드: `id, storeId, puntoVenta, cuit, coolUser, ivaCondition('RI'|'MONO'|'EXENTO'), razonSocial, razonSocialL2, domicilio, ingresosBrutos, inicioActividad, telefono`), `AfipVoucher` 모델 (필드: `id, storeId, saleId, cae, caeVto, puntoVenta, afipNumber, tipoComprobante, docTipo, docNro, impTotal, netoGravado, ivaLiquidado, ivaAlicuota, invoicePct, notaCredito, notaDebito, caeAnterior`). `Sale`에 `cae, caeVto, puntoVenta, afipNumber, tipoComprobante, afipStatus`. `StoreConfig`에 `useFacturaElectronica, afipProvider, afipProduction, afipAutoIssue, afipDefaultPct`.

- [ ] **Step 1: 마이그레이션 SQL 작성**

Create `api-ventago/migrations/afip-factura-electronica.sql`:

```sql
-- Factura Electrónica (AFIP) — Plan 1 스키마. additive, PG10 호환.

-- 1) 발행자 (매장/PV별)
CREATE TABLE IF NOT EXISTS afip_issuers (
  id                serial PRIMARY KEY,
  store_id          integer NOT NULL REFERENCES stores(id),
  punto_venta       integer NOT NULL,
  cuit              varchar(13) NOT NULL,
  cool_user         varchar(100),
  iva_condition     varchar(10) NOT NULL DEFAULT 'RI',
  razon_social      varchar(200),
  razon_social_l2   varchar(200),
  domicilio         varchar(250),
  ingresos_brutos   varchar(50),
  inicio_actividad  varchar(20),
  telefono          varchar(50),
  created_at        timestamp with time zone NOT NULL DEFAULT now(),
  updated_at        timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT uq_afip_issuer_store_pv UNIQUE (store_id, punto_venta)
);

-- 2) CAE 발급 로그
CREATE TABLE IF NOT EXISTS afip_vouchers (
  id                serial PRIMARY KEY,
  store_id          integer NOT NULL REFERENCES stores(id),
  sale_id           integer NOT NULL REFERENCES sales(id),
  cae               varchar(20) NOT NULL,
  cae_vto           date NOT NULL,
  punto_venta       integer NOT NULL,
  afip_number       integer NOT NULL,
  tipo_comprobante  integer NOT NULL,
  doc_tipo          integer NOT NULL,
  doc_nro           varchar(20),
  imp_total         numeric(15,2) NOT NULL,
  neto_gravado      numeric(15,2),
  iva_liquidado     numeric(15,2),
  iva_alicuota      integer,
  invoice_pct       numeric(5,2) NOT NULL DEFAULT 100,
  nota_credito      boolean NOT NULL DEFAULT false,
  nota_debito       boolean NOT NULL DEFAULT false,
  cae_anterior      varchar(20),
  created_at        timestamp with time zone NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_afip_vouchers_sale ON afip_vouchers(sale_id);
CREATE INDEX IF NOT EXISTS idx_afip_vouchers_store_created ON afip_vouchers(store_id, created_at);

-- 3) sales 요약 컬럼
ALTER TABLE sales ADD COLUMN IF NOT EXISTS cae varchar(20);
ALTER TABLE sales ADD COLUMN IF NOT EXISTS cae_vto date;
ALTER TABLE sales ADD COLUMN IF NOT EXISTS punto_venta integer;
ALTER TABLE sales ADD COLUMN IF NOT EXISTS afip_number integer;
ALTER TABLE sales ADD COLUMN IF NOT EXISTS tipo_comprobante integer;
ALTER TABLE sales ADD COLUMN IF NOT EXISTS afip_status varchar(15) NOT NULL DEFAULT 'no';

-- 4) store_configs 플래그
ALTER TABLE store_configs ADD COLUMN IF NOT EXISTS use_factura_electronica boolean NOT NULL DEFAULT false;
ALTER TABLE store_configs ADD COLUMN IF NOT EXISTS afip_provider varchar(5) NOT NULL DEFAULT 'ws';
ALTER TABLE store_configs ADD COLUMN IF NOT EXISTS afip_production boolean NOT NULL DEFAULT false;
ALTER TABLE store_configs ADD COLUMN IF NOT EXISTS afip_auto_issue boolean NOT NULL DEFAULT false;
ALTER TABLE store_configs ADD COLUMN IF NOT EXISTS afip_default_pct numeric(5,2) NOT NULL DEFAULT 100;
```

- [ ] **Step 2: 로컬 PG18에 마이그레이션 적용 (검증)**

Run:
```bash
psql "postgresql://postgres:wkrdjqwnd@127.0.0.1:5432/ventago" -f api-ventago/migrations/afip-factura-electronica.sql
```
Expected: `CREATE TABLE` / `ALTER TABLE` 출력, 에러 없음. 재실행해도 idempotent(IF NOT EXISTS).

- [ ] **Step 3: AfipIssuer 모델 작성**

Create `api-ventago/src/app/afip/models/afip-issuer.model.ts`:

```ts
import { Column, DataType, ForeignKey, Model, Table } from 'sequelize-typescript';
import { Store } from '../../store/store.model';

// 발행자(매장/PV별 AFIP 아이덴티티). CAE 발행엔 cuit+puntoVenta(+coolUser)만 필요,
// 나머지 필드는 영수증/PDF 출력용.
@Table({ tableName: 'afip_issuers', timestamps: true })
export class AfipIssuer extends Model {
  @ForeignKey(() => Store)
  @Column({ allowNull: false })
  storeId: number;

  @Column({ allowNull: false })
  puntoVenta: number;

  @Column({ type: DataType.STRING(13), allowNull: false })
  cuit: string;

  @Column({ type: DataType.STRING(100) })
  coolUser: string;

  @Column({ type: DataType.STRING(10), allowNull: false, defaultValue: 'RI' })
  ivaCondition: string;

  @Column({ type: DataType.STRING(200) })
  razonSocial: string;

  @Column({ type: DataType.STRING(200) })
  razonSocialL2: string;

  @Column({ type: DataType.STRING(250) })
  domicilio: string;

  @Column({ type: DataType.STRING(50) })
  ingresosBrutos: string;

  @Column({ type: DataType.STRING(20) })
  inicioActividad: string;

  @Column({ type: DataType.STRING(50) })
  telefono: string;
}
```

- [ ] **Step 4: AfipVoucher 모델 작성**

Create `api-ventago/src/app/afip/models/afip-voucher.model.ts`:

```ts
import { Column, DataType, ForeignKey, Model, Table } from 'sequelize-typescript';
import { Store } from '../../store/store.model';
import { Sale } from '../../sales/sales.model';

// CAE 발급 로그. imp_total = 발급액(실판매 × invoice_pct). sales.total 은 실판매액 불변.
@Table({ tableName: 'afip_vouchers', timestamps: true, updatedAt: false })
export class AfipVoucher extends Model {
  @ForeignKey(() => Store)
  @Column({ allowNull: false })
  storeId: number;

  @ForeignKey(() => Sale)
  @Column({ allowNull: false })
  saleId: number;

  @Column({ type: DataType.STRING(20), allowNull: false })
  cae: string;

  @Column({ type: DataType.DATEONLY, allowNull: false })
  caeVto: string;

  @Column({ allowNull: false })
  puntoVenta: number;

  @Column({ allowNull: false })
  afipNumber: number;

  @Column({ allowNull: false })
  tipoComprobante: number;

  @Column({ allowNull: false })
  docTipo: number;

  @Column({ type: DataType.STRING(20) })
  docNro: string;

  @Column({ type: DataType.DECIMAL(15, 2), allowNull: false })
  impTotal: number;

  @Column({ type: DataType.DECIMAL(15, 2) })
  netoGravado: number;

  @Column({ type: DataType.DECIMAL(15, 2) })
  ivaLiquidado: number;

  @Column
  ivaAlicuota: number;

  @Column({ type: DataType.DECIMAL(5, 2), allowNull: false, defaultValue: 100 })
  invoicePct: number;

  @Column({ type: DataType.BOOLEAN, allowNull: false, defaultValue: false })
  notaCredito: boolean;

  @Column({ type: DataType.BOOLEAN, allowNull: false, defaultValue: false })
  notaDebito: boolean;

  @Column({ type: DataType.STRING(20) })
  caeAnterior: string;
}
```

- [ ] **Step 5: sales.model.ts 에 afip 요약 컬럼 추가**

In `api-ventago/src/app/sales/sales.model.ts`, add inside the `Sale` class (after existing columns, follow file's `@Column` style):

```ts
  // Factura Electrónica — 발급 요약 (권위 로그는 afip_vouchers). total 은 실판매액 불변.
  @Column({ type: DataType.STRING(20) })
  cae: string;

  @Column({ type: DataType.DATEONLY })
  caeVto: string;

  @Column
  puntoVenta: number;

  @Column
  afipNumber: number;

  @Column
  tipoComprobante: number;

  // 발급 상태: no(대기) | en_progreso | facturado | verificar(ambiguous) | cancelado
  @Column({ type: DataType.STRING(15), allowNull: false, defaultValue: 'no' })
  afipStatus: string;
```

Ensure `DataType` is imported in the file (add to the `sequelize-typescript` import if missing).

- [ ] **Step 6: storeConfig.model.ts 에 플래그 추가**

In `api-ventago/src/app/store/config/storeConfig.model.ts`, add inside the class:

```ts
  // Factura Electrónica 활성 + 운영 플래그
  @Column({ field: 'use_factura_electronica', type: DataType.BOOLEAN, defaultValue: false })
  useFacturaElectronica: boolean;

  @Column({ field: 'afip_provider', type: DataType.STRING(5), defaultValue: 'ws' })
  afipProvider: string;

  @Column({ field: 'afip_production', type: DataType.BOOLEAN, defaultValue: false })
  afipProduction: boolean;

  @Column({ field: 'afip_auto_issue', type: DataType.BOOLEAN, defaultValue: false })
  afipAutoIssue: boolean;

  @Column({ field: 'afip_default_pct', type: DataType.DECIMAL(5, 2), defaultValue: 100 })
  afipDefaultPct: number;
```

- [ ] **Step 7: 빌드 확인 + 커밋**

Run: `cd api-ventago && npx tsc --noEmit -p tsconfig.json`
Expected: 에러 없음 (신규 모델 타입 정상).

```bash
git add api-ventago/migrations/afip-factura-electronica.sql \
  api-ventago/src/app/afip/models/ \
  api-ventago/src/app/sales/sales.model.ts \
  api-ventago/src/app/store/config/storeConfig.model.ts
git commit -m "feat(afip): 스키마 마이그레이션 + AfipIssuer/AfipVoucher 모델 + sales/store_configs 컬럼"
```

---

### Task 2: code-maps (comprobante/IVA/문서 결정 로직 + C 계열)

**Files:**
- Create: `api-ventago/src/app/afip/code-maps.ts`
- Test: `api-ventago/src/app/afip/code-maps.spec.ts`

**Interfaces:**
- Consumes: `isValidCuit` from `../client-import/validators/cuit.validator` (11자리 CUIT 판별에 재사용 가능하나 여기선 길이 기반 유지).
- Produces: `INVOICE_TYPE`, `DOCUMENT_TYPE`, `IVA`, `COND_IVA_RECEPTOR`, `condIvaReceptorFor({cbteTipo,resiva})`, `tipoToCbteTipo(tipo)`, `creditNoteTypeOf(tipo)`, `debitNoteTypeOf(letter)`, `ivaForResiva(resiva)`, `decideComprobante(ivaCondition, {docNro, resiva, configInvoiceType})`, `decideDocumentType({docNro})`, `computeNetoIva({tpago, ivaBase})`. `decideComprobante` 반환: `'A'|'B'|'C'|'M'|'E'`.

- [ ] **Step 1: 실패 테스트 작성 (C 계열 + 발행자 분기 포함)**

Create `api-ventago/src/app/afip/code-maps.spec.ts`:

```ts
import {
  INVOICE_TYPE, decideComprobante, decideDocumentType,
  creditNoteTypeOf, computeNetoIva, condIvaReceptorFor,
} from './code-maps';

describe('afip code-maps', () => {
  it('C 계열 CbteTipo 코드', () => {
    expect(INVOICE_TYPE.C).toBe(11);
    expect(INVOICE_TYPE.NCC).toBe(13);
    expect(INVOICE_TYPE.NDC).toBe(12);
  });

  describe('decideComprobante — 발행자 IVA 조건 분기', () => {
    it('Monotributo 발행자는 수신자 무관 항상 C', () => {
      expect(decideComprobante('MONO', { docNro: '20304050609' })).toBe('C');
      expect(decideComprobante('MONO', { docNro: '' })).toBe('C');
      expect(decideComprobante('MONO', { docNro: '30111222' })).toBe('C');
    });
    it('MONO도 수출(resiva=-1)은 E', () => {
      expect(decideComprobante('MONO', { docNro: '', resiva: '-1' })).toBe('E');
    });
    it('RI 발행자 + CUIT(11자리) 수신자 → A', () => {
      expect(decideComprobante('RI', { docNro: '20304050609' })).toBe('A');
    });
    it('RI + config M → M', () => {
      expect(decideComprobante('RI', { docNro: '20304050609', configInvoiceType: 'M' })).toBe('M');
    });
    it('RI + DNI/문서없음 → B', () => {
      expect(decideComprobante('RI', { docNro: '30111222' })).toBe('B');
      expect(decideComprobante('RI', { docNro: '' })).toBe('B');
    });
    it('RI + 수출 → E', () => {
      expect(decideComprobante('RI', { docNro: '', resiva: '-1' })).toBe('E');
    });
  });

  describe('decideDocumentType', () => {
    it('11자리 → CUIT(80), 그 외 → DNI(96), 없음 → 99', () => {
      expect(decideDocumentType({ docNro: '20304050609' })).toBe(80);
      expect(decideDocumentType({ docNro: '30111222' })).toBe(96);
      expect(decideDocumentType({ docNro: '' })).toBe(99);
    });
  });

  it('creditNoteTypeOf — C 포함', () => {
    expect(creditNoteTypeOf('C')).toBe('NCC');
    expect(creditNoteTypeOf('A')).toBe('NCA');
    expect(creditNoteTypeOf('B')).toBe('NCB');
    expect(creditNoteTypeOf('M')).toBe('NCM');
  });

  it('computeNetoIva — 21% 분해 (센트 정수 연산)', () => {
    // 7000 / 1.21 = 5785.12(DOWN) → neto=5785.12, impuesto=1214.88
    const { neto, impuesto } = computeNetoIva({ tpago: 7000, ivaBase: 1.21 });
    expect(neto).toBe(5785.12);
    expect(impuesto).toBe(1214.88);
  });

  it('condIvaReceptorFor — A계열은 RI(1), B exento(4), 기본 Consumidor(5)', () => {
    expect(condIvaReceptorFor({ cbteTipo: 1 })).toBe(1);
    expect(condIvaReceptorFor({ cbteTipo: 6, resiva: '4' })).toBe(4);
    expect(condIvaReceptorFor({ cbteTipo: 6 })).toBe(5);
  });
});
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd api-ventago && npm test -- --testPathPattern=code-maps.spec`
Expected: FAIL — `Cannot find module './code-maps'`.

- [ ] **Step 3: code-maps.ts 구현 (CoolSyncro 이식 + C 계열 + decideComprobante)**

Create `api-ventago/src/app/afip/code-maps.ts`:

```ts
// AFIP 전자 인보이스 상수 및 코드 결정 로직 (CoolSyncro code-maps.js 이식 + Ventago C 계열 추가).
// AFIP 공식 CbteTipo: C=11, NDC=12, NCC=13. NCM=53, NDM=52 (Java swap 버그 정정 유지).

export const INVOICE_TYPE = Object.freeze({
  A: 1, B: 6, C: 11, E: 19, M: 51,
  NCA: 3, NCB: 8, NCC: 13, NCM: 53, NCE: 21,
  NDA: 2, NDB: 7, NDC: 12, NDM: 52, NDE: 20,
});

export const DOCUMENT_TYPE = Object.freeze({
  FINAL_CONSUMER: 99, CUIT: 80, CUIL: 86, DNI: 96, PASSPORT: 94,
});

export const IVA = Object.freeze({
  EXEMPT: Object.freeze({ type: 3, porcentage: 0, base: 1 }),
  CLIENT_EXTERIOR: Object.freeze({ type: 9, porcentage: 0, base: 1 }),
  INTERNATIONAL: Object.freeze({ type: 4, porcentage: 10.5, base: 1.105 }),
  NATIONAL: Object.freeze({ type: 5, porcentage: 21, base: 1.21 }),
});

export const COND_IVA_RECEPTOR = Object.freeze({
  RESPONSABLE_INSCRIPTO: 1, SUJETO_EXENTO: 4, CONSUMIDOR_FINAL: 5,
  MONOTRIBUTO: 6, CLIENTE_EXTERIOR: 9,
});

// CondicionIVAReceptorId 결정 (RG 5616).
export function condIvaReceptorFor({ cbteTipo, resiva }: { cbteTipo?: number; resiva?: string } = {}): number {
  const t = Number(cbteTipo);

  if ([1, 2, 3, 51, 52, 53].includes(t)) {
    return COND_IVA_RECEPTOR.RESPONSABLE_INSCRIPTO;
  }

  if ([19, 20, 21].includes(t)) {
    return COND_IVA_RECEPTOR.CLIENTE_EXTERIOR;
  }

  if (resiva === '4') {
    return COND_IVA_RECEPTOR.SUJETO_EXENTO;
  }

  return COND_IVA_RECEPTOR.CONSUMIDOR_FINAL;
}

// tipo 문자열 → CbteTipo. 알 수 없는 tipo는 즉시 throw.
export function tipoToCbteTipo(tipo: string): number {
  const code = (INVOICE_TYPE as Record<string, number>)[tipo];

  if (code === undefined) {
    throw new Error('Tipo de factura no válido');
  }

  return code;
}

export function creditNoteTypeOf(tipo: string): string {
  const map: Record<string, string> = { A: 'NCA', B: 'NCB', C: 'NCC', M: 'NCM', E: 'NCE' };
  const result = map[tipo];

  if (result === undefined) {
    throw new Error(`Tipo no válido para nota de crédito: ${tipo}`);
  }

  return result;
}

export function debitNoteTypeOf(letter: string): string {
  const map: Record<string, string> = { A: 'NDA', B: 'NDB', C: 'NDC', M: 'NDM', E: 'NDE' };
  const result = map[letter];

  if (result === undefined) {
    throw new Error(`Tipo no válido para nota de débito: ${letter}`);
  }

  return result;
}

export function ivaForResiva(resiva?: string) {
  if (resiva === '4') {
    return IVA.EXEMPT;
  }

  if (resiva === '-1') {
    return IVA.CLIENT_EXTERIOR;
  }

  return IVA.NATIONAL;
}

// 발급 comprobante tipo 결정 — 발행자 IVA 조건 우선 분기 (Ventago 확장).
//   - resiva='-1' → 'E' (수출, 발행자 무관)
//   - 발행자 MONO → 항상 'C' (Monotributista는 C만 발급)
//   - 발행자 RI/EXENTO + 수신자 CUIT(11자리) → 'A' (config M이면 'M')
//   - 그 외 → 'B'
export function decideComprobante(
  ivaCondition: string,
  { docNro, resiva, configInvoiceType }: { docNro?: string; resiva?: string; configInvoiceType?: string },
): string {
  if (resiva === '-1') {
    return 'E';
  }

  if (ivaCondition === 'MONO') {
    return 'C';
  }

  const doc = typeof docNro === 'string' ? docNro : '';

  if (doc.length === 11) {
    if (configInvoiceType && configInvoiceType.toUpperCase() === 'M') {
      return 'M';
    }

    return 'A';
  }

  return 'B';
}

export function decideDocumentType({ docNro }: { docNro?: string } = {}): number {
  const doc = typeof docNro === 'string' ? docNro : '';

  if (doc.length === 11) {
    return DOCUMENT_TYPE.CUIT;
  }

  if (doc.length > 0) {
    return DOCUMENT_TYPE.DNI;
  }

  return DOCUMENT_TYPE.FINAL_CONSUMER;
}

// 총액을 IVA 배수로 나눠 neto/impuesto 계산. 센트(×100) 정수 연산 = BigDecimal DOWN scale=2.
export function computeNetoIva({ tpago, ivaBase }: { tpago: number; ivaBase: number }): { neto: number; impuesto: number } {
  if (typeof tpago !== 'number' || typeof ivaBase !== 'number' || ivaBase === 0) {
    throw new Error('computeNetoIva: tpago 와 ivaBase 는 0이 아닌 숫자여야 합니다');
  }

  const tpago100 = Math.round(tpago * 100);
  const neto100 = Math.floor((tpago / ivaBase) * 100);
  const impuesto100 = tpago100 - neto100;

  return { neto: neto100 / 100, impuesto: impuesto100 / 100 };
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd api-ventago && npm test -- --testPathPattern=code-maps.spec`
Expected: PASS (모든 it 통과).

- [ ] **Step 5: 커밋**

```bash
git add api-ventago/src/app/afip/code-maps.ts api-ventago/src/app/afip/code-maps.spec.ts
git commit -m "feat(afip): code-maps 이식 + C 계열(C/NCC/NDC) + decideComprobante 발행자 IVA 분기"
```

---

### Task 3: qr-builder (AFIP QR URL)

**Files:**
- Create: `api-ventago/src/app/afip/qr-builder.ts`
- Test: `api-ventago/src/app/afip/qr-builder.spec.ts`

**Interfaces:**
- Produces: `buildQrUrl({ caeDate, cuit, ptoVta, tipoCmp, nroCmp, importe, docTipo, docNro, cae })` → `string`. `URL_BASE`. 이미지 렌더는 하지 않음(Plan 2 PDF에서 `qrcode` 사용). CoolSyncro와 달리 `docTipo`/`docNro`를 명시 인자로 받아 QR의 tipoDocRec가 실제 발급 DocTipo와 일치하도록 개선.

- [ ] **Step 1: 실패 테스트 작성**

Create `api-ventago/src/app/afip/qr-builder.spec.ts`:

```ts
import { buildQrUrl, URL_BASE } from './qr-builder';

describe('afip qr-builder', () => {
  it('필수값으로 base64 페이로드 URL 생성', () => {
    const url = buildQrUrl({
      caeDate: '2026-07-09', cuit: '20-95092843-4', ptoVta: 5,
      tipoCmp: 6, nroCmp: 12, importe: 7000, docTipo: 99, docNro: '', cae: '75140000000123',
    });
    expect(url.startsWith(URL_BASE)).toBe(true);
    const json = JSON.parse(Buffer.from(url.slice(URL_BASE.length), 'base64').toString('utf-8'));
    expect(json).toMatchObject({
      ver: 1, fecha: '2026-07-09', cuit: 20950928434, ptoVta: 5,
      tipoCmp: 6, nroCmp: 12, importe: 7000, moneda: 'PES', ctz: 1,
      tipoDocRec: 99, nroDocRec: 99999999999, tipoCodAut: 'E', codAut: 75140000000123,
    });
  });

  it('docNro 있으면 tipoDocRec=docTipo, nroDocRec=숫자', () => {
    const url = buildQrUrl({
      caeDate: '2026-07-09', cuit: '20950928434', ptoVta: 5,
      tipoCmp: 1, nroCmp: 3, importe: 10000, docTipo: 80, docNro: '20304050609', cae: '75140000000999',
    });
    const json = JSON.parse(Buffer.from(url.slice(URL_BASE.length), 'base64').toString('utf-8'));
    expect(json.tipoDocRec).toBe(80);
    expect(json.nroDocRec).toBe(20304050609);
  });

  it('필수 파라미터 누락 시 throw', () => {
    expect(() => buildQrUrl({ cuit: '20950928434', cae: '1' } as never)).toThrow();
  });
});
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd api-ventago && npm test -- --testPathPattern=qr-builder.spec`
Expected: FAIL — module 없음.

- [ ] **Step 3: qr-builder.ts 구현**

Create `api-ventago/src/app/afip/qr-builder.ts`:

```ts
// AFIP QR URL 빌더 (RG 4892). CoolSyncro qr-builder.js 이식 + docTipo/docNro 명시 인자화.
// QR 이미지는 여기서 만들지 않음 — Plan 2 PDF 생성기가 qrcode로 렌더.

export const URL_BASE = 'https://www.afip.gob.ar/fe/qr/?p=';

export interface QrParams {
  caeDate: string;   // 'YYYY-MM-DD'
  cuit: string;      // 하이픈 포함 가능
  ptoVta: number;
  tipoCmp: number;   // CbteTipo
  nroCmp: number;    // afip_number
  importe: number;   // 발급 총액
  docTipo: number;   // 80/96/99
  docNro?: string;
  cae: string;
}

export function buildQrUrl({ caeDate, cuit, ptoVta, tipoCmp, nroCmp, importe, docTipo, docNro, cae }: QrParams): string {
  if (!caeDate) {
    throw new Error('[qr-builder] caeDate 는 필수입니다 (YYYY-MM-DD)');
  }

  if (!cuit) {
    throw new Error('[qr-builder] cuit 은 필수입니다');
  }

  if (!cae) {
    throw new Error('[qr-builder] cae 는 필수입니다');
  }

  const hasDoc = docNro !== null && docNro !== undefined && String(docNro) !== '';

  const payload = {
    ver: 1,
    fecha: caeDate,
    cuit: Number(String(cuit).replace(/-/g, '')),
    ptoVta: Number(ptoVta),
    tipoCmp: Number(tipoCmp),
    nroCmp: Number(nroCmp),
    importe: Number(importe),
    moneda: 'PES',
    ctz: 1,
    tipoDocRec: hasDoc ? Number(docTipo) : 99,
    nroDocRec: hasDoc ? Number(docNro) : 99999999999,
    tipoCodAut: 'E',
    codAut: Number(cae),
  };

  const b64 = Buffer.from(JSON.stringify(payload), 'utf-8').toString('base64');

  return URL_BASE + b64;
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd api-ventago && npm test -- --testPathPattern=qr-builder.spec`
Expected: PASS.

- [ ] **Step 5: 커밋**

```bash
git add api-ventago/src/app/afip/qr-builder.ts api-ventago/src/app/afip/qr-builder.spec.ts
git commit -m "feat(afip): qr-builder 이식 (AFIP QR RG 4892) + docTipo 명시 인자화"
```

---

### Task 4: partial-invoice (부분 발급 스케일 계산)

**Files:**
- Create: `api-ventago/src/app/afip/partial-invoice.ts`
- Test: `api-ventago/src/app/afip/partial-invoice.spec.ts`

**Interfaces:**
- Produces: `applyPartial(items: PartialLineInput[], realTotal: number, pct: number)` → `{ lines: PartialLine[]; impTotal: number }`. `PartialLineInput = { cantidad: number; precioUnitario: number; subtotal: number; descripcion?: string }`. `PartialLine = { cantidad; precioUnitario; subtotal; descripcion? }`. cantidad 불변, precioUnitario·subtotal은 factor 스케일, 반올림 잔차는 마지막 라인 subtotal에서 보정하여 Σsubtotal === impTotal 보장.

- [ ] **Step 1: 실패 테스트 작성**

Create `api-ventago/src/app/afip/partial-invoice.spec.ts`:

```ts
import { applyPartial } from './partial-invoice';

describe('applyPartial (부분 발급 스케일)', () => {
  const items = [
    { cantidad: 2, precioUnitario: 3500, subtotal: 7000, descripcion: 'Remera' },
    { cantidad: 1, precioUnitario: 3000, subtotal: 3000, descripcion: 'Pantalón' },
  ];

  it('100%는 원본 유지', () => {
    const { lines, impTotal } = applyPartial(items, 10000, 100);
    expect(impTotal).toBe(10000);
    expect(lines[0].subtotal).toBe(7000);
    expect(lines[1].subtotal).toBe(3000);
  });

  it('70%는 수량 유지·금액 스케일, impTotal=7000', () => {
    const { lines, impTotal } = applyPartial(items, 10000, 70);
    expect(impTotal).toBe(7000);
    expect(lines[0].cantidad).toBe(2);       // 수량 불변
    expect(lines[1].cantidad).toBe(1);
    // Σsubtotal === impTotal
    expect(lines[0].subtotal + lines[1].subtotal).toBe(7000);
  });

  it('반올림 잔차는 마지막 라인에서 보정 (Σ === impTotal)', () => {
    // 33.333...% 케이스 — 라인별 반올림 합이 impTotal과 어긋나지 않아야 함
    const { lines, impTotal } = applyPartial(items, 10000, 33.33);
    const sum = lines.reduce((a, l) => a + l.subtotal, 0);
    expect(Number(sum.toFixed(2))).toBe(impTotal);
  });

  it('잘못된 pct는 throw', () => {
    expect(() => applyPartial(items, 10000, 0)).toThrow();
    expect(() => applyPartial(items, 10000, 150)).toThrow();
  });
});
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd api-ventago && npm test -- --testPathPattern=partial-invoice.spec`
Expected: FAIL — module 없음.

- [ ] **Step 3: partial-invoice.ts 구현**

Create `api-ventago/src/app/afip/partial-invoice.ts`:

```ts
// 부분 발급 스케일 계산. 품목 수량(cantidad)은 유지, 금액만 factor(pct/100)로 축소.
// 반올림 잔차는 마지막 라인 subtotal에서 보정 → Σsubtotal === impTotal 보장.

export interface PartialLineInput {
  cantidad: number;
  precioUnitario: number;
  subtotal: number;
  descripcion?: string;
}

export type PartialLine = PartialLineInput;

const round2 = (n: number): number => Math.round(n * 100) / 100;

export function applyPartial(
  items: PartialLineInput[],
  realTotal: number,
  pct: number,
): { lines: PartialLine[]; impTotal: number } {
  if (typeof pct !== 'number' || pct <= 0 || pct > 100) {
    throw new Error(`applyPartial: pct는 0 초과 100 이하여야 합니다 (받은 값: ${pct})`);
  }

  const factor = pct / 100;
  const impTotal = round2(realTotal * factor);

  const lines: PartialLine[] = items.map((it) => ({
    cantidad: it.cantidad,
    precioUnitario: round2(it.precioUnitario * factor),
    subtotal: round2(it.subtotal * factor),
    descripcion: it.descripcion,
  }));

  // 반올림 잔차 보정 — 마지막 라인 subtotal 조정
  if (lines.length > 0) {
    const sum = round2(lines.reduce((a, l) => a + l.subtotal, 0));
    const residue = round2(impTotal - sum);

    if (residue !== 0) {
      const last = lines[lines.length - 1];
      last.subtotal = round2(last.subtotal + residue);
    }
  }

  return { lines, impTotal };
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd api-ventago && npm test -- --testPathPattern=partial-invoice.spec`
Expected: PASS.

- [ ] **Step 5: 커밋**

```bash
git add api-ventago/src/app/afip/partial-invoice.ts api-ventago/src/app/afip/partial-invoice.spec.ts
git commit -m "feat(afip): partial-invoice 부분 발급 스케일(수량 유지·금액 축소·잔차 보정)"
```

---

### Task 5: CaeProvider 인터페이스 + factory + rest-gateway(ws) provider

**Files:**
- Create: `api-ventago/src/app/afip/providers/provider.interface.ts`
- Create: `api-ventago/src/app/afip/providers/rest-gateway.provider.ts`
- Create: `api-ventago/src/app/afip/providers/soap-direct.provider.ts`
- Create: `api-ventago/src/app/afip/providers/cae-provider.factory.ts`
- Test: `api-ventago/src/app/afip/providers/cae-provider.factory.spec.ts`
- Test: `api-ventago/src/app/afip/providers/rest-gateway.provider.spec.ts`

**Interfaces:**
- Consumes: `axios` (주입 가능하도록 `deps.http` 옵션).
- Produces: `VoucherRequest = { point: number; type: number; docType: number; docNro?: string; amount: number; iva: number; ivaType: number; condIvaReceptor: number; cuit: string; coolUser?: string; production: boolean; asoc?: { type: number; point: number; number: number } }`. `IssueResult = { cae?: string; caeDate?: string; number?: number; total?: number; error?: string; ambiguous?: boolean }`. `CaeProvider` 인터페이스(`issueCae`, `getLastVoucher`, `getStatus`). `selectCaeProvider({ provider, deps })` → `CaeProvider`. `createRestGatewayProvider(deps?)`, `createSoapDirectProvider()`(throw NotImplemented).

- [ ] **Step 1: 인터페이스 + soap 스텁 작성**

Create `api-ventago/src/app/afip/providers/provider.interface.ts`:

```ts
// CAE 발급 provider 계약 (ws | soap 스왑 경계).

export interface VoucherRequest {
  point: number;            // punto de venta
  type: number;             // CbteTipo
  docType: number;          // 80/96/99
  docNro?: string;
  amount: number;           // neto
  iva: number;              // impuesto
  ivaType: number;          // AFIP IVA Id (예: 5=21%)
  condIvaReceptor: number;  // RG 5616
  cuit: string;             // 발행자
  coolUser?: string;        // 게이트웨이 인증서 폴더 키
  production: boolean;
  asoc?: { type: number; point: number; number: number }; // NC/ND 원본 참조
}

export interface IssueResult {
  cae?: string;
  caeDate?: string;   // 'YYYY-MM-DD'
  number?: number;    // afip_number
  total?: number;
  error?: string;
  ambiguous?: boolean; // true면 재발급 절대 금지
}

export interface CaeProvider {
  issueCae(req: VoucherRequest): Promise<IssueResult>;
  getLastVoucher(point: number, cbteTipo: number, req: Pick<VoucherRequest, 'cuit' | 'coolUser' | 'production'>): Promise<number | null>;
  getStatus(): Promise<{ ok: boolean; detail?: unknown }>;
}
```

Create `api-ventago/src/app/afip/providers/soap-direct.provider.ts`:

```ts
// SOAP 직접 provider — Plan 후속에서 WSAA cert + WSFEv1로 구현. 현재는 미구현 가드.
import { CaeProvider } from './provider.interface';

export function createSoapDirectProvider(): CaeProvider {
  const notImplemented = (): never => {
    throw new Error('SOAP 직접 provider는 아직 구현되지 않았습니다 (afip_provider=ws 사용)');
  };

  return {
    issueCae: notImplemented,
    getLastVoucher: notImplemented,
    getStatus: notImplemented,
  };
}
```

- [ ] **Step 2: rest-gateway 실패 테스트 작성**

Create `api-ventago/src/app/afip/providers/rest-gateway.provider.spec.ts`:

```ts
import { createRestGatewayProvider } from './rest-gateway.provider';
import { VoucherRequest } from './provider.interface';

const baseReq: VoucherRequest = {
  point: 5, type: 6, docType: 99, docNro: '', amount: 5785.12, iva: 1214.88,
  ivaType: 5, condIvaReceptor: 5, cuit: '20950928434', coolUser: 'ace', production: false,
};

describe('rest-gateway provider (ws)', () => {
  it('성공 응답을 IssueResult로 매핑', async () => {
    const http = {
      post: jest.fn().mockResolvedValue({ data: { cae: '75140000000123', caeDate: '2026-07-09', number: 12, total: 7000 } }),
      get: jest.fn(),
    };
    const provider = createRestGatewayProvider({ http } as never);
    const res = await provider.issueCae(baseReq);
    expect(res).toMatchObject({ cae: '75140000000123', caeDate: '2026-07-09', number: 12 });
    expect(http.post).toHaveBeenCalledTimes(1);
  });

  it('타임아웃(ECONNABORTED)은 ambiguous=true, 재발급 금지 신호', async () => {
    const http = {
      post: jest.fn().mockRejectedValue({ code: 'ECONNABORTED' }),
      get: jest.fn(),
    };
    const provider = createRestGatewayProvider({ http } as never);
    const res = await provider.issueCae(baseReq);
    expect(res.ambiguous).toBe(true);
    expect(res.error).toBeDefined();
    expect(res.cae).toBeUndefined();
  });

  it('4xx(잘못된 요청)은 fatal error, ambiguous 아님', async () => {
    const http = {
      post: jest.fn().mockRejectedValue({ response: { status: 400, data: { message: 'bad' } } }),
      get: jest.fn(),
    };
    const provider = createRestGatewayProvider({ http } as never);
    const res = await provider.issueCae(baseReq);
    expect(res.error).toBeDefined();
    expect(res.ambiguous).toBeFalsy();
  });
});
```

- [ ] **Step 3: 테스트 실패 확인**

Run: `cd api-ventago && npm test -- --testPathPattern=rest-gateway.provider.spec`
Expected: FAIL — module 없음.

- [ ] **Step 4: rest-gateway.provider.ts 구현**

Create `api-ventago/src/app/afip/providers/rest-gateway.provider.ts`:

```ts
// ws — coolsistema 인보이스 게이트웨이 REST provider.
// 인증서는 게이트웨이가 coolUser별 보관. Ventago는 voucher 요청만 전송.
// 게이트웨이 실패 분류(FIX-A): ambiguous(타임아웃/5xx)는 재발급 금지, fatal(4xx)은 즉시 실패.
import axios, { AxiosInstance } from 'axios';
import { CaeProvider, IssueResult, VoucherRequest } from './provider.interface';

const GATEWAY_BASE = 'https://invoice.coolsistema.com/api';

interface Deps {
  http?: AxiosInstance;
  timeoutMs?: number;
}

// ambiguous = CAE가 발급됐을 수도 있음 → 절대 재발급 금지.
function classifyError(err: any): { ambiguous: boolean; message: string } {
  const code = err?.code;
  const status = err?.response?.status;

  if (code === 'ECONNABORTED' || code === 'ETIMEDOUT' || code === 'ECONNRESET' || (typeof status === 'number' && status >= 500)) {
    return { ambiguous: true, message: `게이트웨이 응답 불확실(${code || status}) — 발급 여부 확인 필요` };
  }

  const detail = err?.response?.data?.message || err?.message || String(code || 'error');

  return { ambiguous: false, message: `게이트웨이 발급 실패: ${detail}` };
}

export function createRestGatewayProvider(deps: Deps = {}): CaeProvider {
  const http = deps.http || axios.create({ timeout: deps.timeoutMs ?? 30000 });

  return {
    async issueCae(req: VoucherRequest): Promise<IssueResult> {
      try {
        const { data } = await http.post(`${GATEWAY_BASE}/invoice`, req, {
          params: { client: req.coolUser || req.cuit, production: req.production },
        });

        return { cae: data.cae, caeDate: data.caeDate, number: data.number, total: data.total };
      } catch (err) {
        const { ambiguous, message } = classifyError(err);

        return { error: message, ambiguous };
      }
    },

    async getLastVoucher(point, cbteTipo, req): Promise<number | null> {
      try {
        const { data } = await http.get(`${GATEWAY_BASE}/afip/last/${point}/${cbteTipo}`, {
          params: { client: req.coolUser || req.cuit, production: req.production },
        });

        return typeof data?.number === 'number' ? data.number : null;
      } catch {
        return null;
      }
    },

    async getStatus() {
      try {
        const { data } = await http.get(`${GATEWAY_BASE}/afip/status`);

        return { ok: true, detail: data };
      } catch (err) {
        return { ok: false, detail: (err as Error).message };
      }
    },
  };
}
```

- [ ] **Step 5: rest-gateway 테스트 통과 확인**

Run: `cd api-ventago && npm test -- --testPathPattern=rest-gateway.provider.spec`
Expected: PASS.

- [ ] **Step 6: factory 실패 테스트 작성**

Create `api-ventago/src/app/afip/providers/cae-provider.factory.spec.ts`:

```ts
import { selectCaeProvider } from './cae-provider.factory';

describe('selectCaeProvider', () => {
  it("'ws'/미지정/오타는 REST 게이트웨이 provider", () => {
    expect(selectCaeProvider({ provider: 'ws' })).toHaveProperty('issueCae');
    expect(selectCaeProvider({ provider: undefined as never })).toHaveProperty('issueCae');
    expect(selectCaeProvider({ provider: 'xxx' })).toHaveProperty('issueCae');
  });

  it("'soap'는 soap provider (호출 시 미구현 throw)", () => {
    const p = selectCaeProvider({ provider: 'soap' });
    expect(() => p.getStatus()).toThrow(/구현되지 않/);
  });
});
```

- [ ] **Step 7: factory 구현 + 테스트 통과**

Create `api-ventago/src/app/afip/providers/cae-provider.factory.ts`:

```ts
// provider 셀렉터. 'soap'로 정확히 지정된 경우만 직접 모드, 그 외 전부 ws 안전 폴백.
import { CaeProvider } from './provider.interface';
import { createRestGatewayProvider } from './rest-gateway.provider';
import { createSoapDirectProvider } from './soap-direct.provider';

export function selectCaeProvider({ provider, deps }: { provider?: string; deps?: object }): CaeProvider {
  if (typeof provider === 'string' && provider.toLowerCase() === 'soap') {
    return createSoapDirectProvider();
  }

  return createRestGatewayProvider(deps || {});
}
```

Run: `cd api-ventago && npm test -- --testPathPattern="cae-provider.factory.spec|rest-gateway.provider.spec"`
Expected: PASS (양쪽 spec 전부).

- [ ] **Step 8: 커밋**

```bash
git add api-ventago/src/app/afip/providers/
git commit -m "feat(afip): CaeProvider 인터페이스 + ws rest-gateway provider + soap 스텁 + factory"
```

---

### Task 6: AfipIssuerService (발행자 로드)

**Files:**
- Create: `api-ventago/src/app/afip/afip-issuer.service.ts`
- Test: `api-ventago/src/app/afip/afip-issuer.service.spec.ts`

**Interfaces:**
- Consumes: `AfipIssuer` 모델(Task 1).
- Produces: `AfipIssuerService.loadIssuer(storeId, puntoVenta)` → `AfipIssuer`(없으면 throw `NotFoundException`). `AfipIssuerService.listPuntosDeVenta(storeId)` → `{ puntoVenta, cuit, ivaCondition }[]`.

- [ ] **Step 1: 실패 테스트 작성**

Create `api-ventago/src/app/afip/afip-issuer.service.spec.ts`:

```ts
import { NotFoundException } from '@nestjs/common';
import { AfipIssuerService } from './afip-issuer.service';

describe('AfipIssuerService', () => {
  const makeModel = (rows: any[]) => ({
    findOne: jest.fn(({ where }: any) =>
      Promise.resolve(rows.find((r) => r.storeId === where.storeId && r.puntoVenta === where.puntoVenta) || null)),
    findAll: jest.fn(({ where }: any) => Promise.resolve(rows.filter((r) => r.storeId === where.storeId))),
  });

  it('loadIssuer — 매칭 행 반환', async () => {
    const model = makeModel([{ storeId: 9, puntoVenta: 5, cuit: '20950928434', ivaCondition: 'RI' }]);
    const svc = new AfipIssuerService(model as never);
    const issuer = await svc.loadIssuer(9, 5);
    expect(issuer.cuit).toBe('20950928434');
  });

  it('loadIssuer — 없으면 NotFoundException', async () => {
    const svc = new AfipIssuerService(makeModel([]) as never);
    await expect(svc.loadIssuer(9, 5)).rejects.toBeInstanceOf(NotFoundException);
  });

  it('listPuntosDeVenta — 매장 PV 목록', async () => {
    const model = makeModel([
      { storeId: 9, puntoVenta: 5, cuit: '20950928434', ivaCondition: 'RI' },
      { storeId: 9, puntoVenta: 6, cuit: '20950928434', ivaCondition: 'RI' },
    ]);
    const svc = new AfipIssuerService(model as never);
    const list = await svc.listPuntosDeVenta(9);
    expect(list).toHaveLength(2);
    expect(list[0]).toMatchObject({ puntoVenta: 5, cuit: '20950928434', ivaCondition: 'RI' });
  });
});
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd api-ventago && npm test -- --testPathPattern=afip-issuer.service.spec`
Expected: FAIL — module 없음.

- [ ] **Step 3: afip-issuer.service.ts 구현**

Create `api-ventago/src/app/afip/afip-issuer.service.ts`:

```ts
import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectModel } from '@nestjs/sequelize';
import { AfipIssuer } from './models/afip-issuer.model';

@Injectable()
export class AfipIssuerService {
  constructor(
    @InjectModel(AfipIssuer)
    private readonly issuerModel: typeof AfipIssuer,
  ) {}

  // 매장/PV로 발행자 로드. 미등록 PV는 발급 차단(NotFound).
  async loadIssuer(storeId: number, puntoVenta: number): Promise<AfipIssuer> {
    const issuer = await this.issuerModel.findOne({ where: { storeId, puntoVenta } });

    if (!issuer) {
      throw new NotFoundException(`발행자 미등록: store ${storeId}, PV ${puntoVenta}`);
    }

    return issuer;
  }

  // 매장의 PV 목록 (프론트 드롭다운 + 발급 검증용).
  async listPuntosDeVenta(storeId: number): Promise<{ puntoVenta: number; cuit: string; ivaCondition: string }[]> {
    const rows = await this.issuerModel.findAll({ where: { storeId } });

    return rows.map((r) => ({ puntoVenta: r.puntoVenta, cuit: r.cuit, ivaCondition: r.ivaCondition }));
  }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd api-ventago && npm test -- --testPathPattern=afip-issuer.service.spec`
Expected: PASS.

- [ ] **Step 5: 커밋**

```bash
git add api-ventago/src/app/afip/afip-issuer.service.ts api-ventago/src/app/afip/afip-issuer.service.spec.ts
git commit -m "feat(afip): AfipIssuerService (매장/PV 발행자 로드 + PV 목록)"
```

---

### Task 7: AfipVoucherService (발급 오케스트레이션)

**Files:**
- Create: `api-ventago/src/app/afip/afip-voucher.service.ts`
- Test: `api-ventago/src/app/afip/afip-voucher.service.spec.ts`

**Interfaces:**
- Consumes: `AfipIssuerService.loadIssuer`(Task 6), `decideComprobante`/`decideDocumentType`/`tipoToCbteTipo`/`ivaForResiva`/`computeNetoIva`/`condIvaReceptorFor`(Task 2), `applyPartial`(Task 4), `buildQrUrl`(Task 3), `selectCaeProvider`(Task 5), `AfipVoucher`/`Sale` 모델.
- Produces: `AfipVoucherService.issue({ storeId, saleId, puntoVenta, invoicePct, sale, receptor })` → `{ ok: boolean; reason?: string; cae?: string; voucherId?: number; qrUrl?: string; ambiguous?: boolean }`. `sale` = { id, total, items: {cantidad, precioUnitario, subtotal, descripcion}[] }, `receptor` = { docNro?, resiva? }. 게이트웨이 호출은 DB 저장과 분리(호출 전 상태 클레임, 호출 후 결과 저장).

- [ ] **Step 1: 실패 테스트 작성 (성공 + ambiguous 경로)**

Create `api-ventago/src/app/afip/afip-voucher.service.spec.ts`:

```ts
import { AfipVoucherService } from './afip-voucher.service';

const sale = {
  id: 4821, total: 10000,
  items: [
    { cantidad: 2, precioUnitario: 3500, subtotal: 7000, descripcion: 'Remera' },
    { cantidad: 1, precioUnitario: 3000, subtotal: 3000, descripcion: 'Pantalón' },
  ],
};

function build(providerResult: any) {
  const issuerService = { loadIssuer: jest.fn().mockResolvedValue({ storeId: 9, puntoVenta: 5, cuit: '20950928434', coolUser: 'ace', ivaCondition: 'RI' }) };
  const provider = { issueCae: jest.fn().mockResolvedValue(providerResult), getLastVoucher: jest.fn(), getStatus: jest.fn() };
  const voucherModel = { create: jest.fn().mockResolvedValue({ id: 555 }) };
  const saleModel = { update: jest.fn().mockResolvedValue([1]) };
  const svc = new AfipVoucherService(issuerService as never, voucherModel as never, saleModel as never);
  (svc as any)._provider = provider; // 테스트: provider 주입
  return { svc, provider, voucherModel, saleModel };
}

describe('AfipVoucherService.issue', () => {
  it('성공 — 70% 발급 시 imp_total=7000 저장 + sale facturado', async () => {
    const { svc, provider, voucherModel, saleModel } = build({ cae: '75140000000123', caeDate: '2026-07-09', number: 12, total: 7000 });
    const res = await svc.issue({ storeId: 9, saleId: 4821, puntoVenta: 5, invoicePct: 70, sale, receptor: { docNro: '' } });
    expect(res.ok).toBe(true);
    expect(res.cae).toBe('75140000000123');
    // provider에 전달된 amount는 neto(7000/1.21 DOWN)
    expect(provider.issueCae).toHaveBeenCalledWith(expect.objectContaining({ type: 6, point: 5, amount: 5785.12, iva: 1214.88 }));
    // voucher 저장 imp_total=7000, invoice_pct=70
    expect(voucherModel.create).toHaveBeenCalledWith(expect.objectContaining({ impTotal: 7000, invoicePct: 70, cae: '75140000000123' }));
    // sale facturado로 업데이트
    expect(saleModel.update).toHaveBeenCalledWith(expect.objectContaining({ afipStatus: 'facturado', cae: '75140000000123' }), expect.anything());
    expect(res.qrUrl).toContain('afip.gob.ar/fe/qr');
  });

  it('ambiguous — verificar 상태, voucher 미저장', async () => {
    const { svc, voucherModel, saleModel } = build({ error: '응답 불확실', ambiguous: true });
    const res = await svc.issue({ storeId: 9, saleId: 4821, puntoVenta: 5, invoicePct: 100, sale, receptor: { docNro: '' } });
    expect(res.ok).toBe(false);
    expect(res.ambiguous).toBe(true);
    expect(voucherModel.create).not.toHaveBeenCalled();
    expect(saleModel.update).toHaveBeenCalledWith(expect.objectContaining({ afipStatus: 'verificar' }), expect.anything());
  });

  it('fatal — no 상태 복구, voucher 미저장', async () => {
    const { svc, voucherModel, saleModel } = build({ error: 'bad request', ambiguous: false });
    const res = await svc.issue({ storeId: 9, saleId: 4821, puntoVenta: 5, invoicePct: 100, sale, receptor: { docNro: '' } });
    expect(res.ok).toBe(false);
    expect(voucherModel.create).not.toHaveBeenCalled();
    expect(saleModel.update).toHaveBeenLastCalledWith(expect.objectContaining({ afipStatus: 'no' }), expect.anything());
  });
});
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd api-ventago && npm test -- --testPathPattern=afip-voucher.service.spec`
Expected: FAIL — module 없음.

- [ ] **Step 3: afip-voucher.service.ts 구현**

Create `api-ventago/src/app/afip/afip-voucher.service.ts`:

```ts
import { Injectable } from '@nestjs/common';
import { InjectModel } from '@nestjs/sequelize';
import { AfipIssuerService } from './afip-issuer.service';
import { AfipVoucher } from './models/afip-voucher.model';
import { Sale } from '../sales/sales.model';
import { selectCaeProvider } from './providers/cae-provider.factory';
import { CaeProvider, VoucherRequest } from './providers/provider.interface';
import {
  decideComprobante, decideDocumentType, tipoToCbteTipo, ivaForResiva,
  computeNetoIva, condIvaReceptorFor,
} from './code-maps';
import { applyPartial, PartialLineInput } from './partial-invoice';
import { buildQrUrl } from './qr-builder';

interface IssueInput {
  storeId: number;
  saleId: number;
  puntoVenta: number;
  invoicePct: number;
  sale: { id: number; total: number; items: PartialLineInput[] };
  receptor: { docNro?: string; resiva?: string };
  production?: boolean;
}

@Injectable()
export class AfipVoucherService {
  // 기본 provider (테스트는 _provider로 override). 실제는 store_configs.afip_provider로 선택.
  private _provider: CaeProvider = selectCaeProvider({ provider: 'ws' });

  constructor(
    private readonly issuerService: AfipIssuerService,
    @InjectModel(AfipVoucher) private readonly voucherModel: typeof AfipVoucher,
    @InjectModel(Sale) private readonly saleModel: typeof Sale,
  ) {}

  async issue(input: IssueInput): Promise<{ ok: boolean; reason?: string; cae?: string; voucherId?: number; qrUrl?: string; ambiguous?: boolean }> {
    const { storeId, saleId, puntoVenta, invoicePct, sale, receptor } = input;

    // 1) 발행자 로드 + comprobante 결정
    const issuer = await this.issuerService.loadIssuer(storeId, puntoVenta);
    const tipo = decideComprobante(issuer.ivaCondition, { docNro: receptor.docNro, resiva: receptor.resiva });
    const cbteTipo = tipoToCbteTipo(tipo);
    const docType = decideDocumentType({ docNro: receptor.docNro });

    // 2) 부분 발급 스케일 → neto/iva
    const { impTotal } = applyPartial(sale.items, sale.total, invoicePct);
    const ivaItem = ivaForResiva(receptor.resiva);
    const { neto, impuesto } = computeNetoIva({ tpago: impTotal, ivaBase: ivaItem.base });
    const condIva = condIvaReceptorFor({ cbteTipo, resiva: receptor.resiva });

    const req: VoucherRequest = {
      point: puntoVenta, type: cbteTipo, docType, docNro: receptor.docNro,
      amount: neto, iva: impuesto, ivaType: ivaItem.type, condIvaReceptor: condIva,
      cuit: issuer.cuit, coolUser: issuer.coolUser, production: input.production ?? false,
    };

    // 3) 발급 직전 상태 클레임 (en_progreso)
    await this.saleModel.update({ afipStatus: 'en_progreso' }, { where: { id: saleId } });

    // 4) 게이트웨이 호출 (DB 저장과 분리)
    const result = await this._provider.issueCae(req);

    // 5) ambiguous → 재발급 금지, verificar
    if (result.ambiguous) {
      await this.saleModel.update({ afipStatus: 'verificar' }, { where: { id: saleId } });

      return { ok: false, reason: result.error, ambiguous: true };
    }

    // 6) fatal → no 복구
    if (result.error || !result.cae) {
      await this.saleModel.update({ afipStatus: 'no' }, { where: { id: saleId } });

      return { ok: false, reason: result.error || 'CAE 미발급' };
    }

    // 7) 성공 → voucher 저장 + sale facturado
    const voucher = await this.voucherModel.create({
      storeId, saleId, cae: result.cae, caeVto: result.caeDate, puntoVenta,
      afipNumber: result.number, tipoComprobante: cbteTipo, docTipo: docType, docNro: receptor.docNro,
      impTotal, netoGravado: neto, ivaLiquidado: impuesto, ivaAlicuota: ivaItem.type,
      invoicePct, notaCredito: false, notaDebito: false,
    });

    await this.saleModel.update(
      { afipStatus: 'facturado', cae: result.cae, caeVto: result.caeDate, puntoVenta, afipNumber: result.number, tipoComprobante: cbteTipo },
      { where: { id: saleId } },
    );

    // 8) QR URL (Plan 2 PDF에서 이미지 렌더)
    const qrUrl = buildQrUrl({
      caeDate: result.caeDate!, cuit: issuer.cuit, ptoVta: puntoVenta, tipoCmp: cbteTipo,
      nroCmp: result.number!, importe: impTotal, docTipo: docType, docNro: receptor.docNro, cae: result.cae,
    });

    return { ok: true, cae: result.cae, voucherId: voucher.id, qrUrl };
  }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd api-ventago && npm test -- --testPathPattern=afip-voucher.service.spec`
Expected: PASS (성공/ambiguous/fatal 3경로).

- [ ] **Step 5: 커밋**

```bash
git add api-ventago/src/app/afip/afip-voucher.service.ts api-ventago/src/app/afip/afip-voucher.service.spec.ts
git commit -m "feat(afip): AfipVoucherService 발급 오케스트레이션(부분발급+comprobante 자동선택+ambiguous 안전처리)"
```

---

### Task 8: AfipModule 배선 + 앱 등록

**Files:**
- Create: `api-ventago/src/app/afip/afip.module.ts`
- Modify: `api-ventago/src/app/app.module.ts` (AfipModule import)

**Interfaces:**
- Consumes: 모든 Task 1~7 산출물.
- Produces: `AfipModule` — `AfipIssuer`/`AfipVoucher`/`Sale` 모델 등록 + `AfipIssuerService`/`AfipVoucherService` provider 등록·export.

- [ ] **Step 1: afip.module.ts 작성**

Create `api-ventago/src/app/afip/afip.module.ts`:

```ts
import { Module } from '@nestjs/common';
import { SequelizeModule } from '@nestjs/sequelize';
import { AfipIssuer } from './models/afip-issuer.model';
import { AfipVoucher } from './models/afip-voucher.model';
import { Sale } from '../sales/sales.model';
import { AfipIssuerService } from './afip-issuer.service';
import { AfipVoucherService } from './afip-voucher.service';

@Module({
  imports: [SequelizeModule.forFeature([AfipIssuer, AfipVoucher, Sale])],
  providers: [AfipIssuerService, AfipVoucherService],
  exports: [AfipIssuerService, AfipVoucherService],
})
export class AfipModule {}
```

- [ ] **Step 2: app.module.ts에 등록**

In `api-ventago/src/app/app.module.ts`, add `import { AfipModule } from './afip/afip.module';` near other module imports, and add `AfipModule` to the `imports: [...]` array (follow file's existing formatting — blank line rules).

- [ ] **Step 3: 전체 빌드 + 전체 afip 테스트**

Run:
```bash
cd api-ventago && npx tsc --noEmit -p tsconfig.json && npm test -- --testPathPattern=afip
```
Expected: 컴파일 에러 없음 + 모든 afip spec PASS.

- [ ] **Step 4: ESLint 확인**

Run: `cd api-ventago && npx eslint "src/app/afip/**/*.ts"`
Expected: 에러 없음 (newline-before-return / lines-around-comment 위반 없음).

- [ ] **Step 5: 커밋**

```bash
git add api-ventago/src/app/afip/afip.module.ts api-ventago/src/app/app.module.ts
git commit -m "feat(afip): AfipModule 배선 + app.module 등록 (Plan 1 백엔드 코어 완료)"
```

---

## Self-Review

**Spec coverage (Plan 1 범위):**
- 마이그레이션/모델(§2) → Task 1 ✅
- comprobante 자동선택 A/B/C/M + IVA 분해(§5) → Task 2 ✅
- AFIP QR(§F/qr) → Task 3 ✅
- 부분 발급(§6/D9) → Task 4 ✅
- provider seam ws + soap 스텁(§1.1/D1) → Task 5 ✅
- 발행자 로드(§3.3-2) → Task 6 ✅
- 발급 오케스트레이션 + ambiguous 안전(§3.3) → Task 7 ✅
- 모듈 배선 → Task 8 ✅
- Plan 2 이관: REST 컨트롤러(§4), PDF/출력(§8), 자동발급 훅(§3.2). Plan 3: 프론트(§7). Plan 4: NC/ND(§3.4).

**Placeholder scan:** 모든 step에 실제 코드/명령/기대출력 포함. TBD/TODO 없음.

**Type consistency:** `VoucherRequest`/`IssueResult`(Task 5) ↔ `AfipVoucherService`(Task 7) 사용 일치. `decideComprobante(ivaCondition, {docNro,resiva,configInvoiceType})` 시그니처 Task 2 정의 ↔ Task 7 호출 일치. `applyPartial → {lines, impTotal}` Task 4 ↔ Task 7 `impTotal` 사용 일치. `buildQrUrl` docTipo 인자 Task 3 ↔ Task 7 전달 일치.

**주의 (Plan 2 착수 전 확인):** Task 7의 `_provider`는 테스트 주입용 기본값. 실제 발급 시 `store_configs.afip_provider`로 provider를 선택하도록 REST 컨트롤러(Plan 2)에서 주입/구성해야 함 — Plan 2 Task에 명시할 것.
