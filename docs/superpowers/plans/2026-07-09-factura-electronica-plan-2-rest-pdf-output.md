# Factura Electrónica — Plan 2: REST API + PDF + 출력 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Plan 1의 발급 코어를 HTTP로 노출하고(REST 엔드포인트), 발급 결과를 A4/감열 영수증으로 출력·전달하며, 자동 발급 매장의 판매 완료 훅을 배선한다.

**Architecture:** `AfipController`가 Plan 1의 `AfipVoucherService`/`AfipIssuerService`를 감싼다. provider는 매장의 `store_configs.afip_provider`/`afip_production`로 선택. A4 PDF는 pdfkit+qrcode 서버 생성, 감열은 기존 `PrintService.emitPrintInvoice`(Socket.io→print-agent) 재사용. 자동 발급은 `sales-create.service` 완료 시점 훅.

**Tech Stack:** NestJS 11, Sequelize, pdfkit, qrcode, Socket.io(PrintService), jest.

## Global Constraints

- `@Auth(ValidRoles...)` + `@GetUser() user` → `user.storeId` 로 멀티테넌트 격리. superadmin 외 cross-store 금지.
- `apiConnector` 프론트 계약: DTO는 명시 타입. 응답 envelope 관례 유지.
- 게이트웨이 HTTP 호출은 DB connection 밖.
- 발급 실패는 예외 대신 `{ ok:false, reason }` 반환(프론트 토스트용). 컨트롤러는 4xx/유효성만 예외.
- ESLint: newline-before-return / lines-around-comment 준수.
- 자동 발급은 소매/기존 판매 흐름 회귀 절대 금지 — 훅은 `use_factura_electronica && afip_auto_issue` 게이트 뒤에서만, 실패해도 판매 저장은 성공 유지.
- PDF/QR: `qrcode` `QRCode.toDataURL(qrUrl, { width: 200 })`.

---

### Task 1: DTO + AfipController 조회 엔드포인트 + 발행자 CRUD

**Files:**
- Create: `api-ventago/src/app/afip/dto/issue-voucher.dto.ts`
- Create: `api-ventago/src/app/afip/dto/upsert-issuer.dto.ts`
- Create: `api-ventago/src/app/afip/afip.controller.ts`
- Create: `api-ventago/src/app/afip/afip-query.service.ts`
- Test: `api-ventago/src/app/afip/afip-query.service.spec.ts`
- Modify: `api-ventago/src/app/afip/afip.module.ts` (controller + query service 등록)

**Interfaces:**
- Consumes: `AfipIssuerService`(Plan 1), `AfipVoucher`/`Sale` 모델.
- Produces: `AfipQueryService.listPendientes(storeId)` → `Sale[]`(afip_status='no', activity_type='sale'), `listEmitidas(storeId, date)` → `AfipVoucher[]`+sale join, `getVoucher(storeId, id)`. `IssueVoucherDto = { saleId:number; puntoVenta:number; invoicePct:number; output:'thermal'|'pdf'|'digital' }`. `UpsertIssuerDto` (발행자 필드). 컨트롤러 라우트: `GET /afip/pendientes`, `GET /afip/emitidas?date=`, `GET /afip/issuers`, `POST/PUT /afip/issuers`, `DELETE /afip/issuers/:id`, `GET /afip/vouchers/:saleId/preview?pct=`.

- [ ] **Step 1: DTO 작성**

Create `api-ventago/src/app/afip/dto/issue-voucher.dto.ts`:

```ts
import { IsIn, IsInt, IsNumber, Max, Min } from 'class-validator';

export class IssueVoucherDto {
  @IsInt()
  saleId: number;

  @IsInt()
  puntoVenta: number;

  @IsNumber()
  @Min(0.01)
  @Max(100)
  invoicePct: number;

  @IsIn(['thermal', 'pdf', 'digital'])
  output: 'thermal' | 'pdf' | 'digital';
}
```

Create `api-ventago/src/app/afip/dto/upsert-issuer.dto.ts`:

```ts
import { IsIn, IsInt, IsOptional, IsString, Length } from 'class-validator';

export class UpsertIssuerDto {
  @IsOptional()
  @IsInt()
  id?: number;

  @IsInt()
  puntoVenta: number;

  @IsString()
  @Length(11, 13)
  cuit: string;

  @IsOptional()
  @IsString()
  coolUser?: string;

  @IsIn(['RI', 'MONO', 'EXENTO'])
  ivaCondition: string;

  @IsOptional() @IsString() razonSocial?: string;
  @IsOptional() @IsString() razonSocialL2?: string;
  @IsOptional() @IsString() domicilio?: string;
  @IsOptional() @IsString() ingresosBrutos?: string;
  @IsOptional() @IsString() inicioActividad?: string;
  @IsOptional() @IsString() telefono?: string;
}
```

- [ ] **Step 2: AfipQueryService 실패 테스트 작성**

Create `api-ventago/src/app/afip/afip-query.service.spec.ts`:

```ts
import { AfipQueryService } from './afip-query.service';

describe('AfipQueryService', () => {
  it('listPendientes — afip_status=no + store 격리', async () => {
    const saleModel = { findAll: jest.fn().mockResolvedValue([{ id: 1 }]) };
    const svc = new AfipQueryService(saleModel as never, {} as never);
    const rows = await svc.listPendientes(9);
    expect(rows).toHaveLength(1);
    expect(saleModel.findAll).toHaveBeenCalledWith(expect.objectContaining({
      where: expect.objectContaining({ storeId: 9, afipStatus: 'no' }),
    }));
  });

  it('listEmitidas — voucher store 격리 + 날짜 필터', async () => {
    const voucherModel = { findAll: jest.fn().mockResolvedValue([{ id: 5 }]) };
    const svc = new AfipQueryService({} as never, voucherModel as never);
    const rows = await svc.listEmitidas(9, '2026-07-09');
    expect(rows).toHaveLength(1);
    expect(voucherModel.findAll).toHaveBeenCalledWith(expect.objectContaining({
      where: expect.objectContaining({ storeId: 9 }),
    }));
  });
});
```

- [ ] **Step 3: 테스트 실패 확인**

Run: `cd api-ventago && npm test -- --testPathPattern=afip-query.service.spec`
Expected: FAIL — module 없음.

- [ ] **Step 4: AfipQueryService 구현**

Create `api-ventago/src/app/afip/afip-query.service.ts`:

```ts
import { Injectable } from '@nestjs/common';
import { InjectModel } from '@nestjs/sequelize';
import { Op } from 'sequelize';
import { Sale } from '../sales/sales.model';
import { AfipVoucher } from './models/afip-voucher.model';

@Injectable()
export class AfipQueryService {
  constructor(
    @InjectModel(Sale) private readonly saleModel: typeof Sale,
    @InjectModel(AfipVoucher) private readonly voucherModel: typeof AfipVoucher,
  ) {}

  // 발급 대기 판매 — afip_status='no', 매출건만(activity_type='sale' 무오염 규칙).
  async listPendientes(storeId: number): Promise<Sale[]> {
    return this.saleModel.findAll({
      where: { storeId, afipStatus: 'no', activityType: 'sale' } as never,
      order: [['id', 'DESC']],
      limit: 50,
    });
  }

  // 발급 완료 — 날짜별(created_at 하루 범위), 매장 격리.
  async listEmitidas(storeId: number, date: string): Promise<AfipVoucher[]> {
    const start = new Date(`${date}T00:00:00`);
    const end = new Date(`${date}T23:59:59.999`);

    return this.voucherModel.findAll({
      where: { storeId, createdAt: { [Op.between]: [start, end] } } as never,
      order: [['createdAt', 'DESC']],
    });
  }

  async getVoucher(storeId: number, id: number): Promise<AfipVoucher | null> {
    return this.voucherModel.findOne({ where: { storeId, id } });
  }
}
```

- [ ] **Step 5: 테스트 통과 확인**

Run: `cd api-ventago && npm test -- --testPathPattern=afip-query.service.spec`
Expected: PASS.

- [ ] **Step 6: AfipController 작성 (조회 + 발행자 CRUD + preview)**

Create `api-ventago/src/app/afip/afip.controller.ts`:

```ts
import { Body, Controller, Delete, Get, Param, ParseIntPipe, Post, Put, Query } from '@nestjs/common';
import { Auth } from '../auth/decorators/auth.decorator';
import { GetUser } from '../auth/decorators/get-user.decorator';
import { ValidRoles } from '../auth/interfaces/valid-roles';
import { Users } from '../users/users.model';
import { AfipIssuerService } from './afip-issuer.service';
import { AfipQueryService } from './afip-query.service';
import { InjectModel } from '@nestjs/sequelize';
import { AfipIssuer } from './models/afip-issuer.model';
import { UpsertIssuerDto } from './dto/upsert-issuer.dto';

@Controller('afip')
export class AfipController {
  constructor(
    private readonly issuerService: AfipIssuerService,
    private readonly queryService: AfipQueryService,
    @InjectModel(AfipIssuer) private readonly issuerModel: typeof AfipIssuer,
  ) {}

  @Get('issuers')
  @Auth(ValidRoles.admin, ValidRoles.superadmin, ValidRoles.gerente)
  async listIssuers(@GetUser() user: Users) {
    return this.issuerService.listPuntosDeVenta(user.storeId);
  }

  @Post('issuers')
  @Auth(ValidRoles.admin, ValidRoles.superadmin)
  async createIssuer(@Body() dto: UpsertIssuerDto, @GetUser() user: Users) {
    return this.issuerModel.create({ ...dto, storeId: user.storeId } as never);
  }

  @Put('issuers/:id')
  @Auth(ValidRoles.admin, ValidRoles.superadmin)
  async updateIssuer(@Param('id', ParseIntPipe) id: number, @Body() dto: UpsertIssuerDto, @GetUser() user: Users) {
    // IDOR 가드 — 본인 매장 발행자만
    await this.issuerModel.update({ ...dto } as never, { where: { id, storeId: user.storeId } });

    return this.issuerModel.findOne({ where: { id, storeId: user.storeId } });
  }

  @Delete('issuers/:id')
  @Auth(ValidRoles.admin, ValidRoles.superadmin)
  async deleteIssuer(@Param('id', ParseIntPipe) id: number, @GetUser() user: Users) {
    const n = await this.issuerModel.destroy({ where: { id, storeId: user.storeId } });

    return { deleted: n };
  }

  @Get('pendientes')
  @Auth(ValidRoles.admin, ValidRoles.superadmin, ValidRoles.gerente, ValidRoles.vendedor)
  async pendientes(@GetUser() user: Users) {
    return this.queryService.listPendientes(user.storeId);
  }

  @Get('emitidas')
  @Auth(ValidRoles.admin, ValidRoles.superadmin, ValidRoles.gerente, ValidRoles.vendedor)
  async emitidas(@GetUser() user: Users, @Query('date') date: string) {
    const day = date || new Date().toISOString().slice(0, 10);

    return this.queryService.listEmitidas(user.storeId, day);
  }
}
```

- [ ] **Step 7: 모듈 등록 + 빌드 + 커밋**

In `afip.module.ts`: add `AfipQueryService` to providers, `AfipController` to a `controllers: [AfipController]` array. Ensure `SequelizeModule.forFeature` already includes `AfipIssuer`, `AfipVoucher`, `Sale`.

Run: `cd api-ventago && npx tsc --noEmit -p tsconfig.json && npm test -- --testPathPattern=afip-query.service.spec`
Expected: 빌드 OK + PASS.

```bash
git add api-ventago/src/app/afip/dto/ api-ventago/src/app/afip/afip-query.service.ts api-ventago/src/app/afip/afip-query.service.spec.ts api-ventago/src/app/afip/afip.controller.ts api-ventago/src/app/afip/afip.module.ts
git commit -m "feat(afip): AfipController 조회 엔드포인트 + 발행자 CRUD + AfipQueryService"
```

---

### Task 2: 발급 엔드포인트 + provider store-config 배선 + preview

**Files:**
- Modify: `api-ventago/src/app/afip/afip-voucher.service.ts` (store_configs로 provider 선택 + sale/receptor 로드)
- Modify: `api-ventago/src/app/afip/afip.controller.ts` (POST /afip/vouchers, preview)
- Modify: `api-ventago/src/app/afip/afip.module.ts` (StoreConfig 모델 등록)
- Test: `api-ventago/src/app/afip/afip-voucher.service.spec.ts` (provider 선택 테스트 추가)

**Interfaces:**
- Consumes: Plan 1 `AfipVoucherService.issue`(내부 로직), `StoreConfig` 모델, `Sale` include(items+client).
- Produces: `AfipVoucherService.issueForSale({ storeId, saleId, puntoVenta, invoicePct })` — sale/items/receptor를 DB에서 로드하고 store_configs로 provider 선택 후 `issue()` 호출. `AfipVoucherService.previewPartial(storeId, saleId, pct)` → `{ lines, impTotal, tipo }`. 컨트롤러 `POST /afip/vouchers`(IssueVoucherDto), `GET /afip/vouchers/:saleId/preview?pct=`.

- [ ] **Step 1: provider 선택 테스트 추가**

Append to `api-ventago/src/app/afip/afip-voucher.service.spec.ts`:

```ts
describe('AfipVoucherService.resolveProvider', () => {
  it("store_configs.afipProvider='soap'면 soap provider", () => {
    const svc = new AfipVoucherService({} as never, {} as never, {} as never);
    const p = (svc as any).resolveProvider({ afipProvider: 'soap' });
    expect(() => p.getStatus()).toThrow(/구현되지 않/);
  });
  it("미지정/ws면 rest-gateway provider", () => {
    const svc = new AfipVoucherService({} as never, {} as never, {} as never);
    expect((svc as any).resolveProvider({ afipProvider: 'ws' })).toHaveProperty('issueCae');
    expect((svc as any).resolveProvider({})).toHaveProperty('issueCae');
  });
});
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd api-ventago && npm test -- --testPathPattern=afip-voucher.service.spec`
Expected: FAIL — `resolveProvider` 없음.

- [ ] **Step 3: AfipVoucherService에 provider 선택 + issueForSale/previewPartial 추가**

In `afip-voucher.service.ts`, add import for `StoreConfig` and inject it, then add methods. Replace the fixed `_provider` usage in `issue()` to accept an injected provider param. Add:

```ts
  // store_configs로 provider 선택 (테스트 override 가능)
  resolveProvider(config: { afipProvider?: string }): CaeProvider {
    if ((this as any)._provider) {
      return (this as any)._provider;
    }

    return selectCaeProvider({ provider: config.afipProvider });
  }

  // 판매 로드 → issue() 호출. 컨트롤러 진입점.
  async issueForSale(params: { storeId: number; saleId: number; puntoVenta: number; invoicePct: number }) {
    const { storeId, saleId, puntoVenta, invoicePct } = params;
    const sale = await this.saleModel.findOne({
      where: { storeId, id: saleId },
      include: [{ association: 'saleItems' }, { association: 'client' }],
    });

    if (!sale) {
      return { ok: false, reason: '판매를 찾을 수 없습니다' };
    }

    const config = await this.storeConfigModel.findOne({ where: { storeId } });
    (this as any)._resolvedProvider = this.resolveProvider(config || {});

    const items = ((sale as any).saleItems || []).map((si: any) => ({
      cantidad: Number(si.quantity), precioUnitario: Number(si.unitPrice), subtotal: Number(si.subtotal ?? si.quantity * si.unitPrice), descripcion: si.productName || si.description || 'Ítem',
    }));
    const receptor = { docNro: (sale as any).client?.document || '', resiva: (sale as any).client?.resiva };

    return this.issue({
      storeId, saleId, puntoVenta, invoicePct,
      sale: { id: sale.id, total: Number((sale as any).totalAmount), items },
      receptor,
      production: config?.afipProduction ?? false,
    });
  }

  // 부분 발급 미리보기 (발급 없이 스케일 계산 + tipo).
  async previewPartial(storeId: number, saleId: number, pct: number) {
    const issuerLike = { ivaCondition: 'RI' };
    const sale = await this.saleModel.findOne({ where: { storeId, id: saleId }, include: [{ association: 'saleItems' }, { association: 'client' }] });

    if (!sale) {
      return { ok: false, reason: '판매를 찾을 수 없습니다' };
    }

    const items = ((sale as any).saleItems || []).map((si: any) => ({
      cantidad: Number(si.quantity), precioUnitario: Number(si.unitPrice), subtotal: Number(si.subtotal ?? si.quantity * si.unitPrice), descripcion: si.productName || 'Ítem',
    }));
    const { lines, impTotal } = applyPartial(items, Number((sale as any).totalAmount), pct);
    const tipo = decideComprobante(issuerLike.ivaCondition, { docNro: (sale as any).client?.document, resiva: (sale as any).client?.resiva });

    return { ok: true, lines, impTotal, tipo };
  }
```

In `issue()`, replace `await this._provider.issueCae(req)` with `await ((this as any)._resolvedProvider || this._provider).issueCae(req)`.

> 주의: `saleItems`/`client` association 이름·필드(`quantity`,`unitPrice`,`subtotal`,`productName`,`totalAmount`,`document`,`resiva`)는 실제 `sales.model`/`sale_items` 컬럼명으로 확인 후 맞출 것(Sequelize include alias). `.planning/intel/db-schema-tables.md` 참조.

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd api-ventago && npm test -- --testPathPattern=afip-voucher.service.spec`
Expected: PASS (기존 3 + provider 선택 2).

- [ ] **Step 5: 컨트롤러 발급/preview 엔드포인트 추가**

In `afip.controller.ts`, inject `AfipVoucherService` and add:

```ts
  @Post('vouchers')
  @Auth(ValidRoles.admin, ValidRoles.superadmin, ValidRoles.gerente, ValidRoles.vendedor)
  async issue(@Body() dto: IssueVoucherDto, @GetUser() user: Users) {
    const result = await this.voucherService.issueForSale({
      storeId: user.storeId, saleId: dto.saleId, puntoVenta: dto.puntoVenta, invoicePct: dto.invoicePct,
    });

    return { ...result, output: dto.output };
  }

  @Get('vouchers/:saleId/preview')
  @Auth(ValidRoles.admin, ValidRoles.superadmin, ValidRoles.gerente, ValidRoles.vendedor)
  async preview(@Param('saleId', ParseIntPipe) saleId: number, @Query('pct') pct: string, @GetUser() user: Users) {
    return this.voucherService.previewPartial(user.storeId, saleId, Number(pct) || 100);
  }
```

Add imports for `IssueVoucherDto` and `AfipVoucherService`.

- [ ] **Step 6: 모듈에 StoreConfig 등록 + 빌드 + 커밋**

In `afip.module.ts`, add `StoreConfig` to `SequelizeModule.forFeature([...])`.

Run: `cd api-ventago && npx tsc --noEmit -p tsconfig.json && npm test -- --testPathPattern=afip-voucher.service.spec`
Expected: 빌드 OK + PASS.

```bash
git add api-ventago/src/app/afip/afip-voucher.service.ts api-ventago/src/app/afip/afip-voucher.service.spec.ts api-ventago/src/app/afip/afip.controller.ts api-ventago/src/app/afip/afip.module.ts
git commit -m "feat(afip): 발급/preview 엔드포인트 + store_configs provider 선택 + 판매 로드"
```

---

### Task 3: A4 PDF 생성기 (pdfkit + qrcode)

**Files:**
- Create: `api-ventago/src/app/afip/pdf/a4-generator.ts`
- Test: `api-ventago/src/app/afip/pdf/a4-generator.spec.ts`

**Interfaces:**
- Consumes: `pdfkit`, `qrcode`, `buildQrUrl`(Plan 1). issuer + voucher 데이터.
- Produces: `generateA4Pdf(input: A4Input)` → `Promise<Buffer>`. `A4Input = { issuer:{cuit,razonSocial,domicilio,ingresosBrutos,inicioActividad}; voucher:{cae,caeVto,puntoVenta,afipNumber,tipoComprobante,docNro,impTotal,netoGravado,ivaLiquidado}; tipoLetra:string; lines:{cantidad;precioUnitario;subtotal;descripcion}[]; qrUrl:string }`.

- [ ] **Step 1: 실패 테스트 작성 (PDF 매직바이트 + QR 임베드)**

Create `api-ventago/src/app/afip/pdf/a4-generator.spec.ts`:

```ts
import { generateA4Pdf } from './a4-generator';

const input = {
  issuer: { cuit: '20950928434', razonSocial: 'ACE SA', domicilio: 'Av. Siempre 123', ingresosBrutos: '123', inicioActividad: '01/01/2020' },
  voucher: { cae: '75140000000123', caeVto: '2026-07-19', puntoVenta: 5, afipNumber: 12, tipoComprobante: 6, docNro: '', impTotal: 7000, netoGravado: 5785.12, ivaLiquidado: 1214.88 },
  tipoLetra: 'B',
  lines: [{ cantidad: 2, precioUnitario: 2450, subtotal: 4900, descripcion: 'Remera' }],
  qrUrl: 'https://www.afip.gob.ar/fe/qr/?p=eyJ2ZXIiOjF9',
};

describe('generateA4Pdf', () => {
  it('유효한 PDF Buffer 반환 (%PDF- 헤더)', async () => {
    const buf = await generateA4Pdf(input);
    expect(Buffer.isBuffer(buf)).toBe(true);
    expect(buf.slice(0, 5).toString()).toBe('%PDF-');
    expect(buf.length).toBeGreaterThan(1000);
  });
});
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd api-ventago && npm test -- --testPathPattern=a4-generator.spec`
Expected: FAIL — module 없음.

- [ ] **Step 3: a4-generator.ts 구현**

Create `api-ventago/src/app/afip/pdf/a4-generator.ts`:

```ts
// A4 comprobante PDF (pdfkit + qrcode). CoolSyncro pdf/generator.js 패턴 이식.
import PDFDocument from 'pdfkit';
import * as QRCode from 'qrcode';

export interface A4Line {
  cantidad: number;
  precioUnitario: number;
  subtotal: number;
  descripcion: string;
}

export interface A4Input {
  issuer: { cuit: string; razonSocial: string; domicilio: string; ingresosBrutos: string; inicioActividad: string };
  voucher: { cae: string; caeVto: string; puntoVenta: number; afipNumber: number; tipoComprobante: number; docNro: string; impTotal: number; netoGravado: number; ivaLiquidado: number };
  tipoLetra: string;
  lines: A4Line[];
  qrUrl: string;
}

const money = (n: number): string => `$${Number(n).toFixed(2)}`;
const pad = (n: number, w: number): string => String(n).padStart(w, '0');

export async function generateA4Pdf(input: A4Input): Promise<Buffer> {
  const qrDataUrl = await QRCode.toDataURL(input.qrUrl, { width: 200, margin: 1 });
  const qrPng = Buffer.from(qrDataUrl.split(',')[1], 'base64');

  const doc = new PDFDocument({ size: 'A4', margin: 40 });
  const chunks: Buffer[] = [];
  doc.on('data', (c: Buffer) => chunks.push(c));
  const done = new Promise<Buffer>((resolve) => doc.on('end', () => resolve(Buffer.concat(chunks))));

  // 헤더 — 발행자 + comprobante 종류
  doc.fontSize(16).text(input.issuer.razonSocial, { continued: false });
  doc.fontSize(10).text(`CUIT: ${input.issuer.cuit}`);
  doc.text(input.issuer.domicilio);
  doc.text(`Ing. Brutos: ${input.issuer.ingresosBrutos}  ·  Inicio: ${input.issuer.inicioActividad}`);
  doc.moveDown(0.5);
  doc.fontSize(22).text(`FACTURA ${input.tipoLetra}`, { align: 'right' });
  doc.fontSize(10).text(`Pto Vta: ${pad(input.voucher.puntoVenta, 5)}  Nº: ${pad(input.voucher.afipNumber, 8)}`, { align: 'right' });
  doc.moveDown();

  // 품목 라인
  doc.fontSize(10);
  input.lines.forEach((l) => {
    doc.text(`${l.cantidad} x ${l.descripcion}   ${money(l.precioUnitario)}   ${money(l.subtotal)}`);
  });
  doc.moveDown(0.5);

  // 합계
  doc.text(`Neto: ${money(input.voucher.netoGravado)}   IVA: ${money(input.voucher.ivaLiquidado)}`);
  doc.fontSize(13).text(`TOTAL: ${money(input.voucher.impTotal)}`, { align: 'right' });
  doc.moveDown();

  // CAE + QR
  doc.fontSize(10).text(`CAE Nº: ${input.voucher.cae}`);
  doc.text(`Vencimiento CAE: ${input.voucher.caeVto}`);
  doc.image(qrPng, doc.page.width - 200, doc.y, { width: 140 });

  doc.end();

  return done;
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd api-ventago && npm test -- --testPathPattern=a4-generator.spec`
Expected: PASS (`%PDF-` 헤더 + 크기).

- [ ] **Step 5: 커밋**

```bash
git add api-ventago/src/app/afip/pdf/a4-generator.ts api-ventago/src/app/afip/pdf/a4-generator.spec.ts
git commit -m "feat(afip): A4 comprobante PDF 생성기 (pdfkit + AFIP QR 임베드)"
```

---

### Task 4: 출력 디스패치 (감열/A4/디지털) + 엔드포인트

**Files:**
- Create: `api-ventago/src/app/afip/afip-output.service.ts`
- Test: `api-ventago/src/app/afip/afip-output.service.spec.ts`
- Modify: `api-ventago/src/app/afip/afip.controller.ts` (pdf/reprint/send 엔드포인트)
- Modify: `api-ventago/src/app/afip/afip.module.ts` (PrintModule import)

**Interfaces:**
- Consumes: `PrintService.emitPrintInvoice(branchId, data, targetSocketId?)`, `generateA4Pdf`(Task 3), `buildQrUrl`, `AfipQueryService.getVoucher`, `AfipIssuerService`.
- Produces: `AfipOutputService.dispatch({ storeId, voucherId, output, branchId })` → `{ ok:boolean; pdf?:Buffer }`. output='thermal' → PrintService emit(감열), 'pdf' → generateA4Pdf Buffer 반환, 'digital' → 링크 전송(스텁, 후속 CRM 연동). 컨트롤러: `POST /afip/vouchers/:id/reprint`, `GET /afip/vouchers/:id/pdf`, `POST /afip/vouchers/:id/send`.

- [ ] **Step 1: 실패 테스트 작성**

Create `api-ventago/src/app/afip/afip-output.service.spec.ts`:

```ts
import { AfipOutputService } from './afip-output.service';

const voucher = { id: 5, storeId: 9, cae: '75140000000123', caeVto: '2026-07-19', puntoVenta: 5, afipNumber: 12, tipoComprobante: 6, docNro: '', impTotal: 7000, netoGravado: 5785.12, ivaLiquidado: 1214.88 };
const issuer = { cuit: '20950928434', razonSocial: 'ACE', domicilio: 'x', ingresosBrutos: '1', inicioActividad: '01/01/2020' };

function build() {
  const query = { getVoucher: jest.fn().mockResolvedValue(voucher) };
  const issuerSvc = { loadIssuer: jest.fn().mockResolvedValue(issuer) };
  const print = { emitPrintInvoice: jest.fn() };
  const svc = new AfipOutputService(query as never, issuerSvc as never, print as never);
  return { svc, print };
}

describe('AfipOutputService.dispatch', () => {
  it("thermal → PrintService.emitPrintInvoice 호출", async () => {
    const { svc, print } = build();
    const res = await svc.dispatch({ storeId: 9, voucherId: 5, output: 'thermal', branchId: 3 });
    expect(res.ok).toBe(true);
    expect(print.emitPrintInvoice).toHaveBeenCalledWith(3, expect.objectContaining({ cae: '75140000000123' }), undefined);
  });

  it("pdf → PDF Buffer 반환", async () => {
    const { svc } = build();
    const res = await svc.dispatch({ storeId: 9, voucherId: 5, output: 'pdf', branchId: 3 });
    expect(Buffer.isBuffer(res.pdf)).toBe(true);
    expect(res.pdf!.slice(0, 5).toString()).toBe('%PDF-');
  });
});
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd api-ventago && npm test -- --testPathPattern=afip-output.service.spec`
Expected: FAIL — module 없음.

- [ ] **Step 3: afip-output.service.ts 구현**

Create `api-ventago/src/app/afip/afip-output.service.ts`:

```ts
import { Injectable } from '@nestjs/common';
import { AfipQueryService } from './afip-query.service';
import { AfipIssuerService } from './afip-issuer.service';
import { PrintService } from '../print/print.service';
import { generateA4Pdf } from './pdf/a4-generator';
import { buildQrUrl } from './qr-builder';

interface DispatchInput {
  storeId: number;
  voucherId: number;
  output: 'thermal' | 'pdf' | 'digital';
  branchId: number;
  targetSocketId?: string;
}

@Injectable()
export class AfipOutputService {
  constructor(
    private readonly queryService: AfipQueryService,
    private readonly issuerService: AfipIssuerService,
    private readonly printService: PrintService,
  ) {}

  async dispatch(input: DispatchInput): Promise<{ ok: boolean; pdf?: Buffer; reason?: string }> {
    const voucher = await this.queryService.getVoucher(input.storeId, input.voucherId);

    if (!voucher) {
      return { ok: false, reason: 'Voucher를 찾을 수 없습니다' };
    }

    const issuer = await this.issuerService.loadIssuer(input.storeId, voucher.puntoVenta);
    const qrUrl = buildQrUrl({
      caeDate: voucher.caeVto, cuit: issuer.cuit, ptoVta: voucher.puntoVenta, tipoCmp: voucher.tipoComprobante,
      nroCmp: voucher.afipNumber, importe: Number(voucher.impTotal), docTipo: voucher.docTipo, docNro: voucher.docNro, cae: voucher.cae,
    });

    if (input.output === 'thermal') {
      // 기존 감열지 파이프라인 재사용 — print-agent가 QR+CAE 렌더
      this.printService.emitPrintInvoice(input.branchId, { cae: voucher.cae, caeVto: voucher.caeVto, qrUrl, voucher, issuer }, input.targetSocketId);

      return { ok: true };
    }

    if (input.output === 'pdf') {
      const pdf = await generateA4Pdf({
        issuer, voucher: voucher as never, tipoLetra: this.letra(voucher.tipoComprobante), lines: [], qrUrl,
      });

      return { ok: true, pdf };
    }

    // digital — 후속 CRM(WhatsApp/이메일) 연동. 현재는 링크 준비만.
    return { ok: true };
  }

  private letra(cbteTipo: number): string {
    if ([1, 2, 3, 51, 52, 53].includes(cbteTipo)) {
      return cbteTipo >= 51 ? 'M' : 'A';
    }

    if ([11, 12, 13].includes(cbteTipo)) {
      return 'C';
    }

    return 'B';
  }
}
```

> 참고: A4 라인 재구성은 voucher만으론 부족(원본 라인 미저장). 필요 시 sale_items에서 재조회하거나 afip_vouchers에 라인 JSON을 저장하는 컬럼을 추가할지 Plan 검토 항목. 현재는 합계만 렌더.

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd api-ventago && npm test -- --testPathPattern=afip-output.service.spec`
Expected: PASS.

- [ ] **Step 5: 컨트롤러 출력 엔드포인트 + 모듈 배선 + 커밋**

In `afip.controller.ts` add (inject `AfipOutputService`):

```ts
  @Post('vouchers/:id/reprint')
  @Auth(ValidRoles.admin, ValidRoles.superadmin, ValidRoles.gerente, ValidRoles.vendedor)
  async reprint(@Param('id', ParseIntPipe) id: number, @Body('branchId') branchId: number, @GetUser() user: Users) {
    return this.outputService.dispatch({ storeId: user.storeId, voucherId: id, output: 'thermal', branchId });
  }

  @Get('vouchers/:id/pdf')
  @Auth(ValidRoles.admin, ValidRoles.superadmin, ValidRoles.gerente, ValidRoles.vendedor)
  async pdf(@Param('id', ParseIntPipe) id: number, @GetUser() user: Users, @Res() res: any) {
    const out = await this.outputService.dispatch({ storeId: user.storeId, voucherId: id, output: 'pdf', branchId: 0 });
    res.setHeader('Content-Type', 'application/pdf');
    res.send(out.pdf);
  }
```

Add `@Res` import from `@nestjs/common`. In `afip.module.ts`, import `PrintModule` (or provide `PrintService`) and add `AfipOutputService` to providers.

Run: `cd api-ventago && npx tsc --noEmit -p tsconfig.json && npm test -- --testPathPattern=afip-output.service.spec`
Expected: 빌드 OK + PASS.

```bash
git add api-ventago/src/app/afip/afip-output.service.ts api-ventago/src/app/afip/afip-output.service.spec.ts api-ventago/src/app/afip/afip.controller.ts api-ventago/src/app/afip/afip.module.ts
git commit -m "feat(afip): 출력 디스패치(감열 emit/A4 PDF/디지털 스텁) + reprint/pdf 엔드포인트"
```

---

### Task 5: 자동 발급 훅 (afip_auto_issue 매장)

**Files:**
- Modify: `api-ventago/src/app/sales/sales-create.service.ts` (판매 완료 후 조건부 자동 발급)
- Modify: `api-ventago/src/app/sales/sales.module.ts` (AfipModule import)
- Test: `api-ventago/src/app/afip/auto-issue.spec.ts`

**Interfaces:**
- Consumes: `AfipVoucherService.issueForSale`, `StoreConfig`(use_factura_electronica + afip_auto_issue + afip_default_pct).
- Produces: 판매 저장 성공 후, 게이트가 켜진 매장이면 `issueForSale`를 fire-and-forget(실패해도 판매 성공 유지). 별도 반환 없음.

- [ ] **Step 1: 훅 로직 실패 테스트 작성 (순수 함수로 분리)**

Create `api-ventago/src/app/afip/auto-issue.spec.ts`:

```ts
import { shouldAutoIssue, pickAutoPct } from './auto-issue';

describe('auto-issue 게이트', () => {
  it('use_factura_electronica && afip_auto_issue 둘 다 true여야 발급', () => {
    expect(shouldAutoIssue({ useFacturaElectronica: true, afipAutoIssue: true })).toBe(true);
    expect(shouldAutoIssue({ useFacturaElectronica: true, afipAutoIssue: false })).toBe(false);
    expect(shouldAutoIssue({ useFacturaElectronica: false, afipAutoIssue: true })).toBe(false);
    expect(shouldAutoIssue(null)).toBe(false);
  });
  it('pickAutoPct — 설정값, 없으면 100', () => {
    expect(pickAutoPct({ afipDefaultPct: 70 })).toBe(70);
    expect(pickAutoPct({})).toBe(100);
  });
});
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd api-ventago && npm test -- --testPathPattern=auto-issue.spec`
Expected: FAIL — module 없음.

- [ ] **Step 3: auto-issue.ts 순수 게이트 구현**

Create `api-ventago/src/app/afip/auto-issue.ts`:

```ts
// 자동 발급 게이트 — 순수 판별. 소매 회귀 방지: 두 플래그 모두 켜진 매장만.

export function shouldAutoIssue(config: { useFacturaElectronica?: boolean; afipAutoIssue?: boolean } | null): boolean {
  if (!config) {
    return false;
  }

  return config.useFacturaElectronica === true && config.afipAutoIssue === true;
}

export function pickAutoPct(config: { afipDefaultPct?: number }): number {
  return typeof config.afipDefaultPct === 'number' ? config.afipDefaultPct : 100;
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd api-ventago && npm test -- --testPathPattern=auto-issue.spec`
Expected: PASS.

- [ ] **Step 5: sales-create.service에 훅 배선**

In `sales-create.service.ts`, after the sale is fully created/committed (find the return point of `create()`), add a guarded call. Inject `AfipVoucherService` and `StoreConfig` model. Add before `return completeSale;` (or equivalent):

```ts
    // Factura Electrónica 자동 발급 — 게이트 켜진 매장만, 실패해도 판매 성공 유지 (소매 무회귀)
    try {
      const feConfig = await this.storeConfigModel.findOne({ where: { storeId: saleDto.storeId } });

      if (shouldAutoIssue(feConfig)) {
        const pv = feConfig.afipDefaultPv ?? (await this.pickFirstPv(saleDto.storeId));

        if (pv) {
          void this.afipVoucherService
            .issueForSale({ storeId: saleDto.storeId, saleId: completeSale.id, puntoVenta: pv, invoicePct: pickAutoPct(feConfig) })
            .catch((e) => this.logger?.error?.(`[afip auto-issue] 실패(판매는 성공): ${e?.message}`));
        }
      }
    } catch (e) {
      // 자동 발급 판단 실패는 판매를 막지 않음
    }
```

Add imports `shouldAutoIssue`, `pickAutoPct` from `../afip/auto-issue`. Provide `pickFirstPv(storeId)` helper (query afip_issuers first PV) or use a configured default PV column. Import `AfipModule` in `sales.module.ts`.

> 주의: `afipDefaultPv` 컬럼은 store_configs에 없다면 `pickFirstPv`(afip_issuers 최소 PV 조회)로 대체. 자동 발급 매장은 PV가 반드시 1개 이상 등록돼 있어야 함.

- [ ] **Step 6: 빌드 + 회귀 확인 + 커밋**

Run: `cd api-ventago && npx tsc --noEmit -p tsconfig.json && npm test -- --testPathPattern="auto-issue|sales"`
Expected: 빌드 OK + 기존 sales 테스트 회귀 없음 + auto-issue PASS.

```bash
git add api-ventago/src/app/afip/auto-issue.ts api-ventago/src/app/afip/auto-issue.spec.ts api-ventago/src/app/sales/sales-create.service.ts api-ventago/src/app/sales/sales.module.ts
git commit -m "feat(afip): 자동 발급 훅(afip_auto_issue 게이트, 실패해도 판매 성공 유지)"
```

---

## Self-Review

**Spec coverage (Plan 2 범위):**
- REST 엔드포인트 13종(§4) → Task 1(조회+CRUD) + Task 2(발급/preview) + Task 4(reprint/pdf/send) ✅ (citi-ventas/day-close는 후속으로 스펙 §9에 명시)
- provider store-config 선택(§1.1, Plan 1 주의사항) → Task 2 ✅
- A4 PDF(§8) → Task 3 ✅
- 출력 감열/A4/디지털(§8/D6) → Task 4 ✅
- 자동 발급 훅(§3.2/D2) → Task 5 ✅

**Placeholder scan:** 모든 step 실제 코드/명령 포함. "후속" 표기는 스펙 §9 out-of-scope와 일치(플레이스홀더 아님). 단 Task 2 Step 3, Task 4 Step 3의 `saleItems`/라인 재조회는 실제 컬럼명 확인 주석으로 명시 — 실행자는 `.planning/intel/db-schema-tables.md`로 검증.

**Type consistency:** `IssueVoucherDto`(Task 1) ↔ 컨트롤러 issue(Task 2) 일치. `AfipVoucherService.issueForSale/previewPartial`(Task 2) ↔ 컨트롤러 호출 일치. `A4Input`(Task 3) ↔ `AfipOutputService.dispatch`의 generateA4Pdf 호출 일치. `shouldAutoIssue/pickAutoPct`(Task 5) 시그니처 일치.

**실행 전 확인:** `sales`의 items association alias와 `sale_items` 컬럼명(`quantity`/`unit_price`/`subtotal`/product name), `clients`/`store_clients`의 `document`/`resiva` 필드 실체 — 실행자가 스키마 intel로 검증 후 매핑.
