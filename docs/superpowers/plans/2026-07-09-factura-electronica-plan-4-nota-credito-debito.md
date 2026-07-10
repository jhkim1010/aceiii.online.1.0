# Factura Electrónica — Plan 4: Nota de Crédito / Débito Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 발급된 comprobante에 대해 Nota de Crédito(전체/부분)와 Nota de Débito를 발급하고, Emitidas UI 액션에 연결한다.

**Architecture:** `NotaCreditoService`/`NotaDebitoService`가 원본 `AfipVoucher`를 로드해 `asoc`(원본 참조)를 포함한 voucher 요청을 빌드하고 Plan 1 provider로 발급한다. 새 `afip_voucher` 행(`nota_credito`/`nota_debito`=true, `cae_anterior`=원본 CAE)을 저장한다. 중복 NC는 `cae_anterior` 조회로 차단.

**Tech Stack:** NestJS 11, Sequelize, Plan 1~3 산출물.

## Global Constraints

- `creditNoteTypeOf`/`debitNoteTypeOf`(Plan 1 code-maps) 재사용 — C 포함(NCC/NDC).
- 발급은 provider 뒤에서, ambiguous 안전 처리(재발급 금지) Plan 1 규칙 동일.
- 중복 NC 방지: 같은 원본 CAE에 이미 `nota_credito` 행 있으면 거부.
- `asoc = { type: 원본 CbteTipo, point: 원본 puntoVenta, number: 원본 afipNumber }` (게이트웨이 CbtesAsoc).
- 부분 NC: `items`로 선택 라인 금액만 역발급. 미지정 시 원본 `imp_total` 전액.
- 실패 = `{ ok:false, reason }` (프론트 토스트).

---

### Task 1: NotaCreditoService (전체/부분 NC)

**Files:**
- Create: `api-ventago/src/app/afip/nota-credito.service.ts`
- Test: `api-ventago/src/app/afip/nota-credito.service.spec.ts`
- Modify: `api-ventago/src/app/afip/afip.module.ts`

**Interfaces:**
- Consumes: `AfipVoucher`/`Sale` 모델, `AfipIssuerService`, `selectCaeProvider`, code-maps(`creditNoteTypeOf`, `tipoToCbteTipo`, `condIvaReceptorFor`, `ivaForResiva`, `computeNetoIva`, `letraOf`), `buildQrUrl`.
- Produces: `NotaCreditoService.emit({ storeId, voucherId, items?, production? })` → `{ ok; reason?; ncCae?; ncVoucherId?; qrUrl?; ambiguous? }`. `letraOf(cbteTipo)` → 'A'|'B'|'C'|'M'|'E'.

- [ ] **Step 1: letraOf 헬퍼 추가 (code-maps)**

Append to `api-ventago/src/app/afip/code-maps.ts`:

```ts
// CbteTipo → letra (NC/ND 파생 + PDF 표기용).
export function letraOf(cbteTipo: number): string {
  if ([1, 2, 3].includes(cbteTipo)) {
    return 'A';
  }

  if ([51, 52, 53].includes(cbteTipo)) {
    return 'M';
  }

  if ([11, 12, 13].includes(cbteTipo)) {
    return 'C';
  }

  if ([19, 20, 21].includes(cbteTipo)) {
    return 'E';
  }

  return 'B';
}
```

- [ ] **Step 2: 실패 테스트 작성 (성공 + 중복 거부)**

Create `api-ventago/src/app/afip/nota-credito.service.spec.ts`:

```ts
import { NotaCreditoService } from './nota-credito.service';

const original = { id: 5, storeId: 9, saleId: 4821, cae: '75140000000123', puntoVenta: 5, afipNumber: 12, tipoComprobante: 6, docTipo: 99, docNro: '', impTotal: 7000 };

function build(opts: { existingNc?: boolean; providerResult?: any } = {}) {
  const voucherModel = {
    findOne: jest.fn().mockImplementation(({ where }: any) => {
      if (where.id === 5) {
        return Promise.resolve(original);
      }

      // 중복 NC 조회
      if (where.caeAnterior) {
        return Promise.resolve(opts.existingNc ? { id: 99 } : null);
      }

      return Promise.resolve(null);
    }),
    create: jest.fn().mockResolvedValue({ id: 777 }),
  };
  const issuerSvc = { loadIssuer: jest.fn().mockResolvedValue({ cuit: '20950928434', coolUser: 'ace', ivaCondition: 'RI' }) };
  const provider = { issueCae: jest.fn().mockResolvedValue(opts.providerResult ?? { cae: '75149999999999', caeDate: '2026-07-09', number: 3, total: 7000 }), getLastVoucher: jest.fn(), getStatus: jest.fn() };
  const svc = new NotaCreditoService(voucherModel as never, issuerSvc as never);
  (svc as any)._provider = provider;

  return { svc, voucherModel, provider };
}

describe('NotaCreditoService.emit', () => {
  it('전액 NC 성공 — NCB(tipo 8) + asoc 원본 참조', async () => {
    const { svc, voucherModel, provider } = build();
    const res = await svc.emit({ storeId: 9, voucherId: 5 });
    expect(res.ok).toBe(true);
    expect(res.ncCae).toBe('75149999999999');
    expect(provider.issueCae).toHaveBeenCalledWith(expect.objectContaining({
      type: 8, asoc: { type: 6, point: 5, number: 12 },
    }));
    expect(voucherModel.create).toHaveBeenCalledWith(expect.objectContaining({ notaCredito: true, caeAnterior: '75140000000123' }));
  });

  it('이미 NC 있으면 거부', async () => {
    const { svc } = build({ existingNc: true });
    const res = await svc.emit({ storeId: 9, voucherId: 5 });
    expect(res.ok).toBe(false);
    expect(res.reason).toMatch(/ya|nota|crédito|existe/i);
  });

  it('ambiguous → 재발급 금지', async () => {
    const { svc, voucherModel } = build({ providerResult: { error: 'timeout', ambiguous: true } });
    const res = await svc.emit({ storeId: 9, voucherId: 5 });
    expect(res.ambiguous).toBe(true);
    expect(voucherModel.create).not.toHaveBeenCalled();
  });
});
```

- [ ] **Step 3: 테스트 실패 확인**

Run: `cd api-ventago && npm test -- --testPathPattern=nota-credito.service.spec`
Expected: FAIL — module 없음.

- [ ] **Step 4: NotaCreditoService 구현**

Create `api-ventago/src/app/afip/nota-credito.service.ts`:

```ts
import { Injectable } from '@nestjs/common';
import { InjectModel } from '@nestjs/sequelize';
import { AfipVoucher } from './models/afip-voucher.model';
import { AfipIssuerService } from './afip-issuer.service';
import { selectCaeProvider } from './providers/cae-provider.factory';
import { CaeProvider } from './providers/provider.interface';
import { creditNoteTypeOf, tipoToCbteTipo, letraOf, condIvaReceptorFor, ivaForResiva, computeNetoIva } from './code-maps';
import { buildQrUrl } from './qr-builder';

interface EmitInput {
  storeId: number;
  voucherId: number;
  items?: { subtotal: number }[]; // 부분 NC — 역발급할 라인 금액
  production?: boolean;
}

@Injectable()
export class NotaCreditoService {
  private _provider: CaeProvider = selectCaeProvider({ provider: 'ws' });

  constructor(
    @InjectModel(AfipVoucher) private readonly voucherModel: typeof AfipVoucher,
    private readonly issuerService: AfipIssuerService,
  ) {}

  async emit(input: EmitInput): Promise<{ ok: boolean; reason?: string; ncCae?: string; ncVoucherId?: number; qrUrl?: string; ambiguous?: boolean }> {
    const original = await this.voucherModel.findOne({ where: { storeId: input.storeId, id: input.voucherId } });

    if (!original) {
      return { ok: false, reason: 'Comprobante original no encontrado' };
    }

    // 중복 NC 방지
    const existing = await this.voucherModel.findOne({ where: { storeId: input.storeId, caeAnterior: original.cae, notaCredito: true } as never });

    if (existing) {
      return { ok: false, reason: 'Ya existe una nota de crédito para este comprobante' };
    }

    const issuer = await this.issuerService.loadIssuer(input.storeId, original.puntoVenta);
    const letra = letraOf(original.tipoComprobante);
    const ncTipo = creditNoteTypeOf(letra);
    const cbteTipo = tipoToCbteTipo(ncTipo);

    // 부분 NC면 선택 라인 합, 아니면 전액
    const impTotal = input.items && input.items.length > 0
      ? Number(input.items.reduce((a, l) => a + Number(l.subtotal), 0).toFixed(2))
      : Number(original.impTotal);

    const ivaItem = ivaForResiva(undefined);
    const { neto, impuesto } = computeNetoIva({ tpago: impTotal, ivaBase: ivaItem.base });
    const condIva = condIvaReceptorFor({ cbteTipo, resiva: undefined });

    const req = {
      point: original.puntoVenta, type: cbteTipo, docType: original.docTipo, docNro: original.docNro,
      amount: neto, iva: impuesto, ivaType: ivaItem.type, condIvaReceptor: condIva,
      cuit: issuer.cuit, coolUser: issuer.coolUser, production: input.production ?? false,
      asoc: { type: original.tipoComprobante, point: original.puntoVenta, number: original.afipNumber },
    };

    const result = await this._provider.issueCae(req);

    if (result.ambiguous) {
      return { ok: false, reason: result.error, ambiguous: true };
    }

    if (result.error || !result.cae) {
      return { ok: false, reason: result.error || 'CAE de NC no emitido' };
    }

    const nc = await this.voucherModel.create({
      storeId: input.storeId, saleId: original.saleId, cae: result.cae, caeVto: result.caeDate,
      puntoVenta: original.puntoVenta, afipNumber: result.number, tipoComprobante: cbteTipo,
      docTipo: original.docTipo, docNro: original.docNro, impTotal, netoGravado: neto, ivaLiquidado: impuesto,
      ivaAlicuota: ivaItem.type, invoicePct: 100, notaCredito: true, notaDebito: false, caeAnterior: original.cae,
    } as never);

    const qrUrl = buildQrUrl({
      caeDate: result.caeDate!, cuit: issuer.cuit, ptoVta: original.puntoVenta, tipoCmp: cbteTipo,
      nroCmp: result.number!, importe: impTotal, docTipo: original.docTipo, docNro: original.docNro, cae: result.cae,
    });

    return { ok: true, ncCae: result.cae, ncVoucherId: nc.id, qrUrl };
  }
}
```

- [ ] **Step 5: 테스트 통과 확인 + 모듈 등록**

In `afip.module.ts`, add `NotaCreditoService` to providers/exports.

Run: `cd api-ventago && npm test -- --testPathPattern=nota-credito.service.spec`
Expected: PASS (전액/중복/ambiguous).

- [ ] **Step 6: 커밋**

```bash
git add api-ventago/src/app/afip/nota-credito.service.ts api-ventago/src/app/afip/nota-credito.service.spec.ts api-ventago/src/app/afip/code-maps.ts api-ventago/src/app/afip/afip.module.ts
git commit -m "feat(afip): NotaCreditoService(전액/부분 NC + asoc 원본참조 + 중복차단) + letraOf"
```

---

### Task 2: NotaDebitoService

**Files:**
- Create: `api-ventago/src/app/afip/nota-debito.service.ts`
- Test: `api-ventago/src/app/afip/nota-debito.service.spec.ts`
- Modify: `api-ventago/src/app/afip/afip.module.ts`

**Interfaces:**
- Consumes: 동일(code-maps `debitNoteTypeOf`).
- Produces: `NotaDebitoService.emit({ storeId, voucherId, production? })` → `{ ok; reason?; ndCae?; ndVoucherId?; qrUrl?; ambiguous? }`. 주로 오발급 NC 되돌리기(NC를 asoc로 참조, 전액 역발급).

- [ ] **Step 1: 실패 테스트 작성**

Create `api-ventago/src/app/afip/nota-debito.service.spec.ts`:

```ts
import { NotaDebitoService } from './nota-debito.service';

const nc = { id: 77, storeId: 9, saleId: 4821, cae: '75149999999999', puntoVenta: 5, afipNumber: 3, tipoComprobante: 8, docTipo: 99, docNro: '', impTotal: 7000 };

function build(providerResult?: any) {
  const voucherModel = { findOne: jest.fn().mockResolvedValue(nc), create: jest.fn().mockResolvedValue({ id: 888 }) };
  const issuerSvc = { loadIssuer: jest.fn().mockResolvedValue({ cuit: '20950928434', coolUser: 'ace', ivaCondition: 'RI' }) };
  const provider = { issueCae: jest.fn().mockResolvedValue(providerResult ?? { cae: '75148888888888', caeDate: '2026-07-09', number: 4, total: 7000 }), getLastVoucher: jest.fn(), getStatus: jest.fn() };
  const svc = new NotaDebitoService(voucherModel as never, issuerSvc as never);
  (svc as any)._provider = provider;

  return { svc, voucherModel, provider };
}

describe('NotaDebitoService.emit', () => {
  it('NC(tipo 8) 되돌리기 → NDB(tipo 7) + asoc NC 참조', async () => {
    const { svc, voucherModel, provider } = build();
    const res = await svc.emit({ storeId: 9, voucherId: 77 });
    expect(res.ok).toBe(true);
    expect(provider.issueCae).toHaveBeenCalledWith(expect.objectContaining({ type: 7, asoc: { type: 8, point: 5, number: 3 } }));
    expect(voucherModel.create).toHaveBeenCalledWith(expect.objectContaining({ notaDebito: true, caeAnterior: '75149999999999' }));
  });
});
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd api-ventago && npm test -- --testPathPattern=nota-debito.service.spec`
Expected: FAIL — module 없음.

- [ ] **Step 3: NotaDebitoService 구현**

Create `api-ventago/src/app/afip/nota-debito.service.ts`:

```ts
import { Injectable } from '@nestjs/common';
import { InjectModel } from '@nestjs/sequelize';
import { AfipVoucher } from './models/afip-voucher.model';
import { AfipIssuerService } from './afip-issuer.service';
import { selectCaeProvider } from './providers/cae-provider.factory';
import { CaeProvider } from './providers/provider.interface';
import { debitNoteTypeOf, tipoToCbteTipo, letraOf, condIvaReceptorFor, ivaForResiva, computeNetoIva } from './code-maps';
import { buildQrUrl } from './qr-builder';

interface EmitInput {
  storeId: number;
  voucherId: number; // 되돌릴 원본(주로 NC)
  production?: boolean;
}

@Injectable()
export class NotaDebitoService {
  private _provider: CaeProvider = selectCaeProvider({ provider: 'ws' });

  constructor(
    @InjectModel(AfipVoucher) private readonly voucherModel: typeof AfipVoucher,
    private readonly issuerService: AfipIssuerService,
  ) {}

  async emit(input: EmitInput): Promise<{ ok: boolean; reason?: string; ndCae?: string; ndVoucherId?: number; qrUrl?: string; ambiguous?: boolean }> {
    const original = await this.voucherModel.findOne({ where: { storeId: input.storeId, id: input.voucherId } });

    if (!original) {
      return { ok: false, reason: 'Comprobante a revertir no encontrado' };
    }

    const issuer = await this.issuerService.loadIssuer(input.storeId, original.puntoVenta);
    const letra = letraOf(original.tipoComprobante);
    const ndTipo = debitNoteTypeOf(letra);
    const cbteTipo = tipoToCbteTipo(ndTipo);

    const impTotal = Number(original.impTotal);
    const ivaItem = ivaForResiva(undefined);
    const { neto, impuesto } = computeNetoIva({ tpago: impTotal, ivaBase: ivaItem.base });
    const condIva = condIvaReceptorFor({ cbteTipo, resiva: undefined });

    const req = {
      point: original.puntoVenta, type: cbteTipo, docType: original.docTipo, docNro: original.docNro,
      amount: neto, iva: impuesto, ivaType: ivaItem.type, condIvaReceptor: condIva,
      cuit: issuer.cuit, coolUser: issuer.coolUser, production: input.production ?? false,
      asoc: { type: original.tipoComprobante, point: original.puntoVenta, number: original.afipNumber },
    };

    const result = await this._provider.issueCae(req);

    if (result.ambiguous) {
      return { ok: false, reason: result.error, ambiguous: true };
    }

    if (result.error || !result.cae) {
      return { ok: false, reason: result.error || 'CAE de ND no emitido' };
    }

    const nd = await this.voucherModel.create({
      storeId: input.storeId, saleId: original.saleId, cae: result.cae, caeVto: result.caeDate,
      puntoVenta: original.puntoVenta, afipNumber: result.number, tipoComprobante: cbteTipo,
      docTipo: original.docTipo, docNro: original.docNro, impTotal, netoGravado: neto, ivaLiquidado: impuesto,
      ivaAlicuota: ivaItem.type, invoicePct: 100, notaCredito: false, notaDebito: true, caeAnterior: original.cae,
    } as never);

    const qrUrl = buildQrUrl({
      caeDate: result.caeDate!, cuit: issuer.cuit, ptoVta: original.puntoVenta, tipoCmp: cbteTipo,
      nroCmp: result.number!, importe: impTotal, docTipo: original.docTipo, docNro: original.docNro, cae: result.cae,
    });

    return { ok: true, ndCae: result.cae, ndVoucherId: nd.id, qrUrl };
  }
}
```

- [ ] **Step 4: 테스트 통과 + 모듈 등록**

In `afip.module.ts`, add `NotaDebitoService` to providers/exports.

Run: `cd api-ventago && npm test -- --testPathPattern=nota-debito.service.spec`
Expected: PASS.

- [ ] **Step 5: 커밋**

```bash
git add api-ventago/src/app/afip/nota-debito.service.ts api-ventago/src/app/afip/nota-debito.service.spec.ts api-ventago/src/app/afip/afip.module.ts
git commit -m "feat(afip): NotaDebitoService (NC 되돌리기, NDx + asoc 참조)"
```

---

### Task 3: NC/ND 컨트롤러 엔드포인트

**Files:**
- Modify: `api-ventago/src/app/afip/afip.controller.ts`

**Interfaces:**
- Consumes: `NotaCreditoService.emit`, `NotaDebitoService.emit`.
- Produces: `POST /afip/vouchers/:id/nota-credito`(body: `{ items? }`), `POST /afip/vouchers/:id/nota-debito`.

- [ ] **Step 1: 엔드포인트 추가**

In `afip.controller.ts` (inject `NotaCreditoService`, `NotaDebitoService`):

```ts
  @Post('vouchers/:id/nota-credito')
  @Auth(ValidRoles.admin, ValidRoles.superadmin, ValidRoles.gerente)
  async notaCredito(@Param('id', ParseIntPipe) id: number, @Body('items') items: { subtotal: number }[], @GetUser() user: Users) {
    return this.ncService.emit({ storeId: user.storeId, voucherId: id, items });
  }

  @Post('vouchers/:id/nota-debito')
  @Auth(ValidRoles.admin, ValidRoles.superadmin, ValidRoles.gerente)
  async notaDebito(@Param('id', ParseIntPipe) id: number, @GetUser() user: Users) {
    return this.ndService.emit({ storeId: user.storeId, voucherId: id });
  }
```

- [ ] **Step 2: 빌드 + 전체 afip 테스트 + 커밋**

Run: `cd api-ventago && npx tsc --noEmit -p tsconfig.json && npm test -- --testPathPattern=afip`
Expected: 빌드 OK + 모든 afip spec PASS.

```bash
git add api-ventago/src/app/afip/afip.controller.ts
git commit -m "feat(afip): NC/ND 엔드포인트 (POST vouchers/:id/nota-credito|nota-debito)"
```

---

### Task 4: Emitidas UI — NC 확인 모달 + ND 액션

**Files:**
- Create: `ventago-app/src/views/facturacion/NotaModal.tsx`
- Modify: `ventago-app/src/views/facturacion/EmitidasPanel.tsx`

**Interfaces:**
- Consumes: `afipService.notaCredito`, `afipService.notaDebito`.
- Produces: `NotaModal({ voucher, kind:'credito'|'debito', onClose, onDone })` — 확인 모달(원본 정보 + 사유 확인) → 발급 → 성공/실패 토스트. EmitidasPanel의 즉시 호출을 모달 경유로 교체.

- [ ] **Step 1: NotaModal 구현**

Create `ventago-app/src/views/facturacion/NotaModal.tsx`:

```tsx
import React, { useState } from 'react'
import { Alert, Button, Dialog, DialogActions, DialogContent, DialogTitle, Typography } from '@mui/material'
import { afipService } from 'src/services/afip.service'

interface Props { voucher: any; kind: 'credito' | 'debito'; onClose: () => void; onDone: () => void }

const NotaModal = ({ voucher, kind, onClose, onDone }: Props) => {
  const [error, setError] = useState<string | null>(null)
  const [sending, setSending] = useState(false)

  const confirm = async () => {
    setSending(true)
    setError(null)
    try {
      const res: any = kind === 'credito'
        ? await afipService.notaCredito(voucher.id)
        : await afipService.notaDebito(voucher.id)

      if (!res?.ok) {
        setError(res?.reason || 'Error al emitir la nota')

        return
      }

      onDone()
    } catch (e: any) {
      setError(e?.message || 'Error de red')
    } finally {
      setSending(false)
    }
  }

  return (
    <Dialog open onClose={onClose} maxWidth="xs" fullWidth>
      <DialogTitle>Nota de {kind === 'credito' ? 'Crédito' : 'Débito'}</DialogTitle>
      <DialogContent>
        {error && <Alert severity="error" sx={{ mb: 2 }}>{error}</Alert>}
        <Typography variant="body2">
          Comprobante original CAE {voucher.cae} · ${Number(voucher.impTotal).toLocaleString()}
        </Typography>
        <Typography variant="body2" sx={{ mt: 1 }}>¿Confirmar emisión de la nota?</Typography>
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose}>Cancelar</Button>
        <Button variant="contained" disabled={sending} onClick={confirm}>Emitir</Button>
      </DialogActions>
    </Dialog>
  )
}

export default NotaModal
```

- [ ] **Step 2: EmitidasPanel에서 모달 경유로 교체**

In `EmitidasPanel.tsx`, replace the inline `onClick={async () => { await afipService.notaCredito(...) }}` with a state-driven modal:

```tsx
// 상단에 추가
const [nota, setNota] = useState<{ voucher: any; kind: 'credito' | 'debito' } | null>(null)
```

Replace the acción cell:

```tsx
<TableCell>
  {v.notaCredito ? (
    <Typography variant="caption" color="text.secondary">NC emitida</Typography>
  ) : (
    <>
      <Button size="small" onClick={() => setNota({ voucher: v, kind: 'credito' })}>NC</Button>
      <Button size="small" color="inherit" onClick={() => setNota({ voucher: v, kind: 'debito' })}>ND</Button>
    </>
  )}
</TableCell>
```

Add before the closing `</Card>`:

```tsx
{nota && (
  <NotaModal
    voucher={nota.voucher}
    kind={nota.kind}
    onClose={() => setNota(null)}
    onDone={() => { setNota(null); mutate() }}
  />
)}
```

Add `import NotaModal from './NotaModal'`.

- [ ] **Step 3: 타입체크 + eslint + 커밋**

Run: `cd ventago-app && npx tsc --noEmit && npx eslint "src/views/facturacion/**/*.tsx"`
Expected: 에러 없음. (위반 시 eslint-guardian 서브에이전트)

```bash
git add ventago-app/src/views/facturacion/NotaModal.tsx ventago-app/src/views/facturacion/EmitidasPanel.tsx
git commit -m "feat(afip-ui): NC/ND 확인 모달 + Emitidas 액션 연결"
```

---

## Self-Review

**Spec coverage (Plan 4 범위):**
- Nota de Crédito 전액/부분 + asoc + 중복차단(§3.4) → Task 1 ✅
- Nota de Débito(NC 되돌리기)(§3.4) → Task 2 ✅
- NC/ND 엔드포인트(§4) → Task 3 ✅
- Emitidas NC/ND UI(§7.1) → Task 4 ✅

**Placeholder scan:** 모든 step 실제 코드/명령 포함. 없음.

**Type consistency:** `creditNoteTypeOf`/`debitNoteTypeOf`/`letraOf`(Plan 1 code-maps + Task 1) ↔ NC/ND 서비스 사용 일치. `asoc:{type,point,number}`(Plan 1 VoucherRequest) ↔ NC/ND 빌드 일치. `afipService.notaCredito/notaDebito`(Plan 3 Task 1) ↔ NotaModal(Task 4) 호출 일치. `emit()` 반환 `{ok,reason,ambiguous}` ↔ 컨트롤러/UI 일치.

**실행 전 확인:** NC의 IVA 분해를 원본 tipo/resiva 기준으로 정밀화할지(현재 NATIONAL 21% 가정) — 원본 voucher의 iva_alicuota를 재사용하도록 개선 여지. 부분 NC의 `items` 프론트 선택 UI는 후속(현재 API는 지원, UI는 전액만).

---

## 전체 4개 플랜 완료 후

**통합 검증(수동):**
1. 로컬 마이그레이션 적용 → afip_issuers에 테스트 발행자(RI, PV 5) 시드.
2. store_configs.use_factura_electronica=true.
3. 판매 생성 → Facturación Pendientes 확인 → 70% 발급(homologación) → CAE 수신 → QR 스캔 검증 → 감열 출력.
4. Emitidas에서 NC 발급 → 원본 asoc 확인.
5. 운영 배포 전: PG10 마이그레이션 문법 검증 + 게이트웨이 homologación E2E + soap 미전환 확인.

**후속(별도 플랜):** CITI Ventas 월보고, soap-direct provider 구현, Factura E(WSFEX), day-close 자동 복구, 디지털 전송(WhatsApp/이메일) 실연동, 부분 NC 라인 선택 UI.
