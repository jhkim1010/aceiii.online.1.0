# CodigoMadre QR 감열 출력 Implementation Plan (Phase 38)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** CodigoVista의 CodigoMadre View parent 행에 QR 출력 버튼을 추가하여, print-agent(감열)로 QR(딥링크 URL) + 코드 + 제품명 + 선택 가격 라벨을 출력한다.

**Architecture:** 프론트 버튼 → price-type 선택 → `POST /print/qr` → 백엔드가 Product/가격 조회 + 딥링크 URL 조립 후 `print_qr`를 `branch:{branchId}` 룸에 emit (기존 `emitPrintBarcode` 패턴) → print-agent가 `qrcode`로 QR HTML 생성 → 기존 `renderHtmlToPng(576)→printImage` 파이프라인(fiscal과 동일)으로 감열 출력.

**Tech Stack:** NestJS 11 + Sequelize (api-ventago), Electron + escpos + `qrcode` (print-agent), Next.js 13 + MUI 5 (ventago-app). Jest (백엔드). 로컬 dev = PG18 호스트 + npm (docker 없음).

**선행 설계:** [docs/superpowers/specs/2026-06-11-codigomadre-qr-thermal-print-design.md](../specs/2026-06-11-codigomadre-qr-thermal-print-design.md)

---

## 범위 (Phase 38 = Half A, 데스크탑 QR 출력)

모바일 스캔/`/m/stock` 해석/크로스 지점 변형 재고 뷰(Half B)는 **Phase 37 mobile 범위** — 이 계획 범위 외.

---

## File Structure

**Backend (api-ventago):**
- Modify: `src/app/print/print.service.ts` — `buildQrPayload()` + `emitPrintQr()`
- Modify: `src/app/print/print.controller.ts` — `POST /print/qr`
- Modify: `src/app/print/print.module.ts` — Product/Prices/PriceType 모델 import
- Test: `src/app/print/print.service.spec.ts` (신규)

**print-agent:**
- Create: `src/qr-formatter.js` — `formatQrHtml(payload)` (순수 함수, `qrcode` 사용)
- Modify: `main.js` — `print_qr` 핸들러
- Modify: `package.json` — `qrcode` 의존성
- Test: `test/qr-formatter.smoke.js` (node assert 스모크)

**Frontend (ventago-app):**
- Modify: `src/views/codigo-vista/CodigoVistaView.tsx` — parent 행 QR 버튼 + price-type Popover + handlePrintQr

---

## Task 1: 백엔드 — buildQrPayload + emitPrintQr (PrintService)

**Files:**
- Modify: `api-ventago/src/app/print/print.service.ts`
- Modify: `api-ventago/src/app/print/print.module.ts`
- Test: `api-ventago/src/app/print/print.service.spec.ts`

- [ ] **Step 1: 실패하는 테스트 작성**

Create `api-ventago/src/app/print/print.service.spec.ts`:

```typescript
import { PrintService } from './print.service';

describe('PrintService — QR (Phase 38)', () => {
  const makeService = (overrides: any = {}) => {
    const productRepo = {
      findByPk: jest.fn().mockResolvedValue(
        overrides.product ?? { id: 10, sku: 'CM-001', name: 'Remera', storeId: 6 },
      ),
    } as any;
    const pricesRepo = {
      findOne: jest.fn().mockResolvedValue(overrides.price ?? { amount: 1500 }),
    } as any;
    const priceTypeRepo = {
      findByPk: jest.fn().mockResolvedValue(overrides.priceType ?? { id: 2, name: 'Minorista' }),
    } as any;
    const emit = jest.fn();
    const gateway = { server: { to: jest.fn().mockReturnValue({ emit }) } } as any;

    const svc: any = Object.create(PrintService.prototype);
    svc.productRepo = productRepo;
    svc.pricesRepo = pricesRepo;
    svc.priceTypeRepo = priceTypeRepo;
    svc.gateway = gateway;

    return { svc, productRepo, pricesRepo, priceTypeRepo, gateway, emit };
  };

  it('buildQrPayload: Product/가격/priceType 조회 + 딥링크 URL 조립', async () => {
    const { svc } = makeService();
    const payload = await svc.buildQrPayload(10, 2);
    expect(payload.code).toBe('CM-001');
    expect(payload.name).toBe('Remera');
    expect(payload.price).toBe(1500);
    expect(payload.priceLabel).toBe('Minorista');
    expect(payload.qrUrl).toContain('s=6');
    expect(payload.qrUrl).toContain('p=10');
    expect(payload.qrUrl).toContain('/m/stock');
  });

  it('buildQrPayload: Product 없으면 PRODUCT_NOT_FOUND', async () => {
    const { svc } = makeService({ product: null });
    await expect(svc.buildQrPayload(999, 2)).rejects.toThrow('PRODUCT_NOT_FOUND');
  });

  it('buildQrPayload: 가격 행 없으면 price=null (priceLabel 유지)', async () => {
    const { svc } = makeService({ price: null });
    const payload = await svc.buildQrPayload(10, 2);
    expect(payload.price).toBeNull();
  });

  it('emitPrintQr: branch 룸에 print_qr emit', () => {
    const { svc, gateway, emit } = makeService();
    svc.emitPrintQr(6, { code: 'CM-001' });
    expect(gateway.server.to).toHaveBeenCalledWith('branch:6');
    expect(emit).toHaveBeenCalledWith('print_qr', { code: 'CM-001' });
  });
});
```

> 생성자 인자명(`productRepo`/`pricesRepo`/`priceTypeRepo`/`gateway`)은 Step 3에서 실제로 그 이름으로 주입한다. 기존 `gateway` 필드명은 print.service.ts에 이미 존재(확인). `Object.create` 우회는 DI 복잡성 회피용.

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd api-ventago && npx jest print.service.spec --silent`
Expected: FAIL — `buildQrPayload is not a function`.

- [ ] **Step 3: PrintService 구현**

In `api-ventago/src/app/print/print.service.ts`:

(a) 상단 import 추가 (경로는 기존 import 스타일 확인 후 맞춤):
```typescript
import { Product } from '../products/products.model';
import { Prices } from '../prices/prices.model';
import { PriceType } from '../prices/types/priceType.model';
import { InjectModel } from '@nestjs/sequelize';
```

(b) 생성자에 모델 주입 추가 (기존 `agentRepo`, `gateway` 주입 옆에):
```typescript
    @InjectModel(Product) private readonly productRepo: typeof Product,
    @InjectModel(Prices) private readonly pricesRepo: typeof Prices,
    @InjectModel(PriceType) private readonly priceTypeRepo: typeof PriceType,
```
> 기존 생성자가 어떤 데코레이터/스타일로 `agentRepo`(BranchAgent)를 주입하는지 먼저 읽고 동일 스타일로 추가.

(c) `emitPrintBarcode` 뒤에 메서드 추가:
```typescript
  // Phase 38 — QR 라벨 페이로드 조립 (Product + 가격 + 딥링크 URL)
  async buildQrPayload(parentProductId: number, priceTypeId: number) {
    const product = await this.productRepo.findByPk(parentProductId);

    if (!product) {
      throw new Error('PRODUCT_NOT_FOUND');
    }

    const priceRow = await this.pricesRepo.findOne({
      where: { productId: parentProductId, priceTypeId },
    });
    const priceType = await this.priceTypeRepo.findByPk(priceTypeId);

    const webBase = process.env.PUBLIC_WEB_URL || 'https://ventago.coolsistema.com';
    const qrUrl = `${webBase}/m/stock?s=${product.storeId}&p=${parentProductId}`;

    return {
      qrUrl,
      code: product.sku,
      name: product.name,
      price: priceRow ? Number(priceRow.amount) : null,
      priceLabel: priceType ? priceType.name : '',
    };
  }

  // Phase 38 — QR 라벨 출력 emit (emitPrintBarcode 패턴)
  emitPrintQr(branchId: number, data: any, agentId?: number): void {
    try {
      if (agentId) {
        this.agentRepo.findByPk(agentId).then((agent) => {
          if (agent?.socketId) {
            this.gateway.server?.to(agent.socketId).emit('print_qr', data);
          }
        });
      } else {
        this.gateway.server?.to(`branch:${branchId}`).emit('print_qr', data);
      }
    } catch (err) {
      console.error('[PrintService] emitPrintQr 실패:', err);
    }
  }
```
> `product.storeId` 속성명은 Product 모델의 `store_id` → `storeId`(underscored) 매핑 확인. `priceRow.amount`는 prices.model.ts의 `amount` 컬럼.

(d) `print.module.ts`의 `SequelizeModule.forFeature([...])`에 `Product, Prices, PriceType` 추가:
```typescript
import { Product } from '../products/products.model';
import { Prices } from '../prices/prices.model';
import { PriceType } from '../prices/types/priceType.model';
// forFeature([BranchAgent, Sale, Product, Prices, PriceType])
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd api-ventago && npx jest print.service.spec --silent`
Expected: PASS (4 tests).

- [ ] **Step 5: 빌드 + Commit**

Run: `cd api-ventago && npx tsc --noEmit -p tsconfig.json` (0 errors)
```bash
cd api-ventago
git add src/app/print/print.service.ts src/app/print/print.module.ts src/app/print/print.service.spec.ts
git commit -m "feat(38): PrintService buildQrPayload + emitPrintQr (QR 라벨 페이로드/emit)"
```

---

## Task 2: 백엔드 — POST /print/qr 엔드포인트

**Files:**
- Modify: `api-ventago/src/app/print/print.controller.ts`

- [ ] **Step 1: 엔드포인트 추가**

In `api-ventago/src/app/print/print.controller.ts`, `printBarcode`(POST /print/barcode) 뒤에 추가 (동일 가드/스타일):

```typescript
  // POST /print/qr — CodigoMadre QR 라벨 출력 emit (Phase 38)
  @Post('qr')
  async printQr(@Body() body: any, @Req() req: any) {
    const branchId =
      body?.branchId || req?.user?.branchId || req?.user?.sucursalId || 0;

    if (!branchId) {
      return { ok: false, error: 'branchId requerido' };
    }

    if (!body?.parentProductId || !body?.priceTypeId) {
      return { ok: false, error: 'parentProductId/priceTypeId requerido' };
    }

    try {
      const payload = await this.printService.buildQrPayload(
        Number(body.parentProductId),
        Number(body.priceTypeId),
      );

      this.printService.emitPrintQr(
        branchId,
        { ...payload, branchId, ts: Date.now() },
        body.agentId,
      );

      return { ok: true, branchId };
    } catch (err) {
      const code = err instanceof Error ? err.message : 'UNKNOWN';

      return { ok: false, error: code };
    }
  }
```
> `@UseGuards(AuthGuard('jwt'))`는 클래스 레벨에 이미 적용됨(확인). printBarcode와 동일 posture.

- [ ] **Step 2: 빌드 확인**

Run: `cd api-ventago && npx tsc --noEmit -p tsconfig.json`
Expected: 0 errors.

- [ ] **Step 3: 수동 스모크 (dev api 실행 시, 선택)**

dev는 로컬 PG18 + `npm run dev:api`(docker 아님). api 실행 중이면:
`curl -s -X POST http://localhost:5002/api/print/qr -H "Authorization: Bearer <JWT>" -H "Content-Type: application/json" -d '{"branchId":1,"parentProductId":<id>,"priceTypeId":<id>}'`
Expected: `{"ok":true,"branchId":1}` (에이전트 미연결이어도 ok — emit fire-and-forget). JWT 없으면 SKIP.

- [ ] **Step 4: Commit**

```bash
cd api-ventago
git add src/app/print/print.controller.ts
git commit -m "feat(38): POST /print/qr 엔드포인트 (buildQrPayload + emitPrintQr)"
```

---

## Task 3: print-agent — qr-formatter (QR HTML 빌더)

**Files:**
- Create: `print-agent/src/qr-formatter.js`
- Modify: `print-agent/package.json` (qrcode 의존성)
- Test: `print-agent/test/qr-formatter.smoke.js`

- [ ] **Step 1: qrcode 의존성 추가 + 설치**

Run:
```bash
cd print-agent && npm install qrcode --save
```
Expected: `package.json` dependencies에 `qrcode` 추가, `node_modules/qrcode` 존재.

- [ ] **Step 2: 실패하는 스모크 테스트 작성**

Create `print-agent/test/qr-formatter.smoke.js`:

```javascript
const assert = require('assert');
const { formatQrHtml } = require('../src/qr-formatter');

(async () => {
  const html = await formatQrHtml({
    qrUrl: 'https://ventago.coolsistema.com/m/stock?s=6&p=10',
    code: 'CM-001',
    name: 'Remera',
    price: 1500,
    priceLabel: 'Minorista',
  });

  assert(typeof html === 'string', 'html must be string');
  assert(html.includes('data:image'), 'QR img data-uri present');
  assert(html.includes('CM-001'), 'code present');
  assert(html.includes('Remera'), 'name present');
  assert(html.includes('1500'), 'price present');
  assert(html.includes('Minorista'), 'priceLabel present');

  console.log('qr-formatter smoke OK');
})().catch((e) => { console.error(e); process.exit(1); });
```

- [ ] **Step 3: 스모크 실패 확인**

Run: `cd print-agent && node test/qr-formatter.smoke.js`
Expected: FAIL — `Cannot find module '../src/qr-formatter'`.

- [ ] **Step 4: qr-formatter.js 구현**

Create `print-agent/src/qr-formatter.js` (fiscal-formatter.js 의 HTML 스타일 참고 — 576px/80mm):

```javascript
const QRCode = require('qrcode');

// Phase 38 — CodigoMadre QR 라벨 HTML 생성.
// renderHtmlToPng(html, 576) → printImage 파이프라인용 (fiscal 패턴 동일).
// 가격이 null 이면 가격 줄 생략.
async function formatQrHtml(payload) {
  const { qrUrl, code, name, price, priceLabel } = payload || {};
  const qrDataUri = await QRCode.toDataURL(String(qrUrl || ''), {
    margin: 1,
    width: 360,
  });

  const priceLine =
    price != null
      ? `<div class="price">${priceLabel ? priceLabel + ': ' : ''}$ ${price}</div>`
      : '';

  return `<!DOCTYPE html>
<html><head><meta charset="utf-8"><style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { width: 576px; font-family: monospace; text-align: center; padding: 16px 0; }
  .qr { width: 360px; height: 360px; margin: 0 auto; }
  .code { font-size: 34px; font-weight: bold; margin-top: 12px; }
  .name { font-size: 26px; margin-top: 6px; }
  .price { font-size: 30px; font-weight: bold; margin-top: 10px; }
</style></head><body>
  <img class="qr" src="${qrDataUri}" />
  <div class="code">${code || ''}</div>
  <div class="name">${name || ''}</div>
  ${priceLine}
</body></html>`;
}

module.exports = { formatQrHtml };
```

- [ ] **Step 5: 스모크 통과 확인**

Run: `cd print-agent && node test/qr-formatter.smoke.js`
Expected: `qr-formatter smoke OK`.

- [ ] **Step 6: Commit**

```bash
cd print-agent
git add src/qr-formatter.js test/qr-formatter.smoke.js package.json package-lock.json
git commit -m "feat(38): qr-formatter QR 라벨 HTML 빌더 + qrcode 의존성"
```

---

## Task 4: print-agent — print_qr 핸들러 (main.js)

**Files:**
- Modify: `print-agent/main.js`

- [ ] **Step 1: import + 핸들러 추가**

In `print-agent/main.js`:

(a) 상단 require 블록 (다른 formatter require 옆, line ~9-12)에 추가:
```javascript
const { formatQrHtml } = require('./src/qr-formatter');
```

(b) `wsConnection.on('print_fiscal', ...)` 핸들러 뒤에 추가 (print_fiscal 패턴 그대로, QR 전용):
```javascript
  // Phase 38 — CodigoMadre QR 라벨 출력
  wsConnection.on('print_qr', async (payload) => {
    const printerCfg = getActivePrinterCfg();
    const start = Date.now();
    const code = payload?.code || '?';

    broadcastLog(`🖨 print_qr ${code} — imprimiendo...`);

    try {
      const html = await formatQrHtml(payload);
      const png = await renderHtmlToPng(html, 576);

      await printImage(png, printerCfg);
      broadcastLog(`✅ print_qr ${code} — OK (${Date.now() - start}ms)`);
      wsConnection.emit('print_ack', { code, status: 'ok', ts: Date.now() });
    } catch (err) {
      broadcastLog(`❌ print_qr ${code} — ${err.message}`);
      wsConnection.emit('print_ack', { code, status: 'error', error: err.message, ts: Date.now() });
    }
  });
```
> `getActivePrinterCfg`, `renderHtmlToPng`, `printImage`, `broadcastLog`는 print_fiscal 핸들러가 쓰는 동일 심볼 — 이미 파일에 존재. 핸들러를 print_fiscal과 같은 `setupSocket`/연결 함수 스코프 안에 배치 (print_fiscal `wsConnection.on`이 있는 그 블록).

- [ ] **Step 2: 문법 검증**

Run: `cd print-agent && node -c main.js`
Expected: 문법 에러 없음 (no output / exit 0).

- [ ] **Step 3: Commit**

```bash
cd print-agent
git add main.js
git commit -m "feat(38): print_qr 핸들러 — formatQrHtml→renderHtmlToPng→printImage"
```

---

## Task 5: 프론트 — CodigoVista QR 버튼 + price-type Popover

**Files:**
- Modify: `ventago-app/src/views/codigo-vista/CodigoVistaView.tsx`

- [ ] **Step 1: 현재 행 렌더링 + price-type 데이터 + import 파악**

Run: `sed -n '1,30p;355,470p;1420,1520p' ventago-app/src/views/codigo-vista/CodigoVistaView.tsx`
확인: ① 상단 import (apiConnector default import 존재), ② `/price-types` fetch 결과가 어떤 state 변수에 담기는지(price-types 목록 재사용), ③ parent 행 `filtered.map(...)`에서 `p.productId`/`p.isParent`/`p.code`/`p.name` 접근, ④ MUI `IconButton`/`Popover`/`MenuItem` import 여부, ⑤ 성공/에러 토스트(snackbar) 패턴.

- [ ] **Step 2: BranchContext + 상태 + 핸들러 추가**

import 추가 (상단 import 블록):
```typescript
import { useContext } from 'react'
import { IconButton, Popover, MenuList, MenuItem, ListItemText } from '@mui/material'

import { BranchContext } from 'src/context/BranchContext'
```
> 이미 import된 심볼(IconButton 등)은 중복 추가하지 말 것 — Step 1에서 확인 후 없는 것만 추가.

컴포넌트 본문에 추가 (price-types 목록 변수명은 Step 1에서 확인한 실제 state명으로 대체):
```typescript
  const { selectedBranchId } = useContext(BranchContext)
  const [qrAnchor, setQrAnchor] = useState<null | HTMLElement>(null)
  const [qrTarget, setQrTarget] = useState<{ productId: number; name: string } | null>(null)

  const openQrMenu = (e: React.MouseEvent<HTMLElement>, row: any) => {
    e.stopPropagation()
    setQrTarget({ productId: row.productId, name: row.name })
    setQrAnchor(e.currentTarget)
  }

  const handlePrintQr = async (priceTypeId: number) => {
    setQrAnchor(null)

    if (!selectedBranchId || !qrTarget) {
      // 에러는 인라인/글로벌 토스트로 노출 (에러 가시성 규약)
      return
    }

    try {
      await apiConnector.post('/print/qr', {
        branchId: selectedBranchId,
        parentProductId: qrTarget.productId,
        priceTypeId,
      })
    } catch (error) {
      console.error('QR 출력 실패', error)
    }
  }
```

- [ ] **Step 3: parent 행에 QR 버튼 셀 추가**

`filtered.map((p, rowIdx) => ...)`의 TableRow 안, code 셀 근처에 (parent 행만):
```tsx
                {p.isParent && (
                  <IconButton
                    size="small"
                    onClick={e => openQrMenu(e, p)}
                    title="Imprimir QR"
                  >
                    <Icon icon="tabler:qrcode" />
                  </IconButton>
                )}
```
> `Icon`은 `@iconify/react`에서 이미 import됨(CodigoVistaView 상단 확인). 행 클릭(편집 패널)과 분리되도록 `e.stopPropagation()`은 openQrMenu에서 처리됨. 테이블 컬럼 구조상 별도 `<TableCell>`이 필요하면 헤더에도 빈 셀 1개 추가.

- [ ] **Step 4: price-type Popover 렌더 (컴포넌트 return 하단, 테이블 뒤)**

`<priceTypes 변수>`는 Step 1에서 확인한 실제 price-types 배열 state명으로 대체:
```tsx
      <Popover
        open={Boolean(qrAnchor)}
        anchorEl={qrAnchor}
        onClose={() => setQrAnchor(null)}
        anchorOrigin={{ vertical: 'bottom', horizontal: 'left' }}
      >
        <MenuList dense>
          {(priceTypes || []).map((pt: any) => (
            <MenuItem key={pt.id} onClick={() => handlePrintQr(pt.id)}>
              <ListItemText primary={pt.name} />
            </MenuItem>
          ))}
        </MenuList>
      </Popover>
```

- [ ] **Step 5: ESLint + 타입 체크 (CRITICAL — warning 도 빌드 차단)**

Run: `cd ventago-app && npx eslint src/views/codigo-vista/CodigoVistaView.tsx`
Expected: 0 problems (newline-before-return / lines-around-comment / no-unused-vars 준수).
Run: `cd ventago-app && npx tsc --noEmit`
Expected: 0 errors.

> 이 시점에 eslint-guardian subagent 추가 점검 권장 (프로젝트 규약).

- [ ] **Step 6: Commit**

```bash
cd ventago-app
git add src/views/codigo-vista/CodigoVistaView.tsx
git commit -m "feat(38): CodigoVista CodigoMadre 행 QR 출력 버튼 + price-type Popover"
```

---

## Self-Review (작성자 체크 완료)

- **Spec coverage:** 설계 Success Criteria 1(parent 행 버튼)=Task5, 2(price-type Popover)=Task5, 3(POST /print/qr + emit)=Task1·2, 4(print-agent QR 출력)=Task3·4, 5(딥링크 URL)=Task1, 6(에러 토스트)=Task5, 7(현재 지점 라우팅)=Task1·2(branchId), 8(ESLint/tsc/빌드)=각 Task 검증 스텝.
- **Placeholder scan:** 각 코드 스텝에 실제 코드 포함. "Step 1에서 확인" 지시는 기존 코드(변수명/import) 의존부로 확인 명령(Run) 동반.
- **Type consistency:** `buildQrPayload(parentProductId, priceTypeId)` → `{qrUrl, code, name, price, priceLabel}`, `emitPrintQr(branchId, data, agentId?)`, `formatQrHtml(payload)`, `POST /print/qr {branchId, parentProductId, priceTypeId, agentId?}`, 이벤트 `print_qr` — 전 태스크 일관.

## 알려진 검증 의존 항목 (실행 중 확인)

- PrintService 생성자의 기존 주입 스타일(`@InjectModel(BranchAgent) agentRepo`) — 동일 스타일로 Product/Prices/PriceType 주입.
- Product `storeId` / Prices `amount` / PriceType `name` 속성명 (underscored 매핑).
- CodigoVistaView의 price-types state 변수명 + 이미 import된 MUI 심볼.
- print-agent `print_qr` 핸들러를 `wsConnection.on('print_fiscal')`과 동일한 함수 스코프에 배치.
- print-agent 변경 → push 시 `build-print-agent.yml` 태그 자동 증가 (CI).
