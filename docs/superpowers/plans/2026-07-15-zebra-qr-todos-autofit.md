# Zebra QR — 전체 SKU 검색 / 일괄 출력 / QR 확대 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** zebra-agent QR 탭에서 전체 SKU 를 이름/SKU 로 검색해 일괄 출력할 수 있게 하고, QR 코드를 ECC Q→M + 자동맞춤으로 약 25% 확대한다.

**Architecture:** 백엔드는 이미 매장 parent 상품 전체를 읽어 NUEVO/CAMBIO/동일을 판정하고 "동일"만 버리고 있다. 버리지 않고 `IGUAL` 로 반환 + DB where 에 `iLike` 필터를 붙여 전체 검색과 일괄 출력을 동시에 푼다(신규 테이블·이벤트 0). QR 은 `splitRatio` 고정 비율을 폐기하고 URL 길이에서 모듈 수를 역산해 높이·폭 제약 안에서 실효 magnification 을 구한다.

**Tech Stack:** NestJS 11 + Sequelize (api-ventago), Electron 28 + vanilla JS (zebra-agent), Socket.io WS ack, ZPL II

**설계 문서:** `docs/superpowers/specs/2026-07-15-zebra-qr-todos-autofit-design.md`

## Global Constraints

- **DB 마이그레이션 0.** 스키마 변경 없음. 로컬(5432)/운영(5434) 모두 손대지 않는다.
- **IDOR 불변:** `branchId` 는 항상 `client.data.branchId`(API key 도출)에서만 온다. payload 의 branch/store 는 절대 신뢰하지 않는다.
- **하위호환:** 구 에이전트가 `scope` 를 안 보내면 서버는 `delta` 로 폴백해 **현행과 완전히 동일한 결과**를 낸다. 회귀 0 이 요구사항이다.
- **pool 보호:** QR 조회는 5 SELECT 고정(Branch/products/prices/qr_log/priceType). N+1 금지. `limit: 5000` 유지. 검색 필터는 **DB where** 에서 — 5000행 읽고 인메모리로 버리지 않는다.
- **주석은 한국어, 함수/변수명은 영어** (CLAUDE.md).
- ZPL 상수 (203dpi): `QR_MARGIN = 10`, `QR_GAP = 12`, `QR_WIDTH_CAP = 0.55`, `MAX_QR_MODULE = 10`, 1mm = 8 dot.
- zebra-agent 테스트는 **jest 가 아니다.** plain node 스크립트: `node test/qr-label.test.js`. `ok(name, cond)` 헬퍼 + 말미 `console.log(\`\n${passed} checks passed ✅\`)` 패턴을 따른다.
- api-ventago 테스트는 jest: `npx jest src/app/print`.
- **`git add -A` / `git add .` 금지.** 이 모노레포엔 3rd-party WIP 가 있다. 항상 파일명을 명시해 add 한다.

---

### Task 1: 백엔드 — `getQrItems` (scope + 검색 필터)

**Files:**
- Modify: `api-ventago/src/app/print/print.service.ts:180-289` (`getPendingQrDelta` → `getQrItems`)
- Test: `api-ventago/src/app/print/print.service.qr.spec.ts`

**Interfaces:**
- Consumes: 없음 (첫 태스크)
- Produces:
  ```ts
  async getQrItems(
    branchId: number,
    priceTypeId: number,
    opts?: { scope?: 'delta' | 'all'; q?: string },
  ): Promise<Array<{
    productId: number; code: string; name: string;
    price: number; priceLabel: string;
    status: 'NUEVO' | 'CAMBIO' | 'IGUAL';
    oldName?: string; oldPrice?: number; qrUrl: string;
  }>>
  ```
  Task 2(게이트웨이)가 이 이름·시그니처로 호출한다. **`getPendingQrDelta` 는 남기지 않는다** — 호출자는 게이트웨이 1곳뿐이며 Task 2 에서 치환한다.

- [ ] **Step 1: 실패하는 테스트 작성**

`print.service.qr.spec.ts` 의 기존 `describe` 블록 **안**, `afterEach(() => jest.restoreAllMocks());` 바로 아래에 추가한다. 기존 `makeService()` 헬퍼를 그대로 쓴다 (픽스처: parent 상품 3개 id 10/11/12, prices 10→1500·11→2500, 12 는 prices 없음 → base 3000).

```ts
  describe('getQrItems — scope / 검색 필터', () => {
    // 회귀 가드: scope 미지정 = 기존 getPendingQrDelta 와 동일 결과 (IGUAL 없음)
    it('scope 미지정 → 동일 항목 제외 (NUEVO/CAMBIO 만)', async () => {
      const { svc } = makeService({
        // 10 은 스냅샷과 완전 동일 → 제외되어야 함
        logs: [{ productId: 10, printedName: 'Remera', printedPrice: 1500 }],
      });

      const items = await svc.getQrItems(BRANCH_ID, PRICE_TYPE_ID);

      expect(items.map((i: any) => i.productId).sort()).toEqual([11, 12]);
      expect(items.every((i: any) => i.status !== 'IGUAL')).toBe(true);
    });

    it("scope='all' → 동일 항목도 IGUAL 로 포함", async () => {
      const { svc } = makeService({
        logs: [{ productId: 10, printedName: 'Remera', printedPrice: 1500 }],
      });

      const items = await svc.getQrItems(BRANCH_ID, PRICE_TYPE_ID, {
        scope: 'all',
      });

      expect(items.map((i: any) => i.productId).sort()).toEqual([10, 11, 12]);
      const igual = items.find((i: any) => i.productId === 10);
      expect(igual.status).toBe('IGUAL');
      // IGUAL 도 출력 가능해야 하므로 qrUrl/price 가 채워져 있어야 한다
      expect(igual.qrUrl).toContain('p=10');
      expect(igual.price).toBe(1500);
    });

    it("scope='all' 이어도 CAMBIO 는 old 값을 유지", async () => {
      const { svc } = makeService({
        logs: [{ productId: 11, printedName: 'Pantalón', printedPrice: 999 }],
      });

      const items = await svc.getQrItems(BRANCH_ID, PRICE_TYPE_ID, {
        scope: 'all',
      });

      const cambio = items.find((i: any) => i.productId === 11);
      expect(cambio.status).toBe('CAMBIO');
      expect(cambio.oldPrice).toBe(999);
      expect(cambio.price).toBe(2500);
    });

    it('q 2자 이상 → DB where 에 sku/name iLike 추가 (인메모리 필터 아님)', async () => {
      const { svc, productRepo } = makeService();

      await svc.getQrItems(BRANCH_ID, PRICE_TYPE_ID, { q: 'rem' });

      const where = productRepo.findAll.mock.calls[0][0].where;
      const orKey = Object.getOwnPropertySymbols(where).find(
        (s) => String(s) === 'Symbol(or)',
      );
      expect(orKey).toBeDefined();
      const or = where[orKey as symbol];
      expect(or).toHaveLength(2);
      expect(JSON.stringify(or)).toContain('%rem%');
      // 필터가 걸려도 매장 격리와 parent 조건은 유지
      expect(where.storeId).toBe(STORE_ID);
      expect(where.isParent).toBe(true);
    });

    it('q 1자 이하 → 필터 없음 (전체)', async () => {
      const { svc, productRepo } = makeService();

      await svc.getQrItems(BRANCH_ID, PRICE_TYPE_ID, { q: 'r' });

      const where = productRepo.findAll.mock.calls[0][0].where;
      expect(Object.getOwnPropertySymbols(where)).toHaveLength(0);
    });

    it('q 공백만 → 필터 없음', async () => {
      const { svc, productRepo } = makeService();

      await svc.getQrItems(BRANCH_ID, PRICE_TYPE_ID, { q: '   ' });

      const where = productRepo.findAll.mock.calls[0][0].where;
      expect(Object.getOwnPropertySymbols(where)).toHaveLength(0);
    });

    it('pool 보호 — 쿼리 수는 scope/q 와 무관하게 고정', async () => {
      const { svc, productRepo, pricesRepo, qrLogRepo, priceTypeRepo } =
        makeService();

      await svc.getQrItems(BRANCH_ID, PRICE_TYPE_ID, { scope: 'all', q: 'rem' });

      expect(productRepo.findAll).toHaveBeenCalledTimes(1);
      expect(pricesRepo.findAll).toHaveBeenCalledTimes(1);
      expect(qrLogRepo.findAll).toHaveBeenCalledTimes(1);
      expect(priceTypeRepo.findByPk).toHaveBeenCalledTimes(1);
    });
  });
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd api-ventago && npx jest src/app/print/print.service.qr.spec.ts -t 'getQrItems'`
Expected: FAIL — `svc.getQrItems is not a function`

- [ ] **Step 3: 구현**

`print.service.ts:180` 의 시그니처와 JSDoc 을 교체한다:

```ts
  // Phase 38 → 2026-07-15 확장 — 지점별 QR 항목 조회 (D-3/D-4/D-6).
  // scope='delta'(기본): NUEVO/CAMBIO 만 (동일 제외 — 기존 getPendingQrDelta 와 동일 결과).
  // scope='all': 동일 항목도 IGUAL 로 포함 → 전체 SKU 검색/일괄 출력용.
  // q(2자 이상): sku/name 부분일치. DB where 에서 거른다 — 5000행 읽고 버리면 pool 낭비.
  // store/branch 는 호출자(gateway)가 API key 로 도출한 branchId 로만 결정한다 (D-6, IDOR 안전).
  // pool 보호: Branch/products/prices/log/priceType 최소 쿼리 세트(≈5 SELECT), N+1 없음.
  async getQrItems(
    branchId: number,
    priceTypeId: number,
    opts?: { scope?: 'delta' | 'all'; q?: string },
  ): Promise<
    Array<{
      productId: number;
      code: string;
      name: string;
      price: number;
      priceLabel: string;
      status: 'NUEVO' | 'CAMBIO' | 'IGUAL';
      oldName?: string;
      oldPrice?: number;
      qrUrl: string;
    }>
  > {
    // 화이트리스트 — 'all' 이 아니면 무조건 delta (구 에이전트 미전송 시 폴백)
    const scope = opts?.scope === 'all' ? 'all' : 'delta';
    const q = (opts?.q || '').trim();
```

이어서 상품 조회(`this.productRepo.findAll`)의 `where` 만 교체한다. 나머지(attributes/limit)는 그대로:

```ts
    const products: any[] = await this.productRepo.findAll({
      where: {
        storeId,
        isParent: true,
        status: 'active',
        // 2자 미만은 필터 없음(전체) — 검색칸은 선택 사항이고 비우면 전체가 정상 동작
        ...(q.length >= 2
          ? {
              [Op.or]: [
                { sku: { [Op.iLike]: `%${q}%` } },
                { name: { [Op.iLike]: `%${q}%` } },
              ],
            }
          : {}),
      } as any,
      attributes: ['id', 'name', 'sku', 'price'],
      limit: 5000,
    });
```

마지막으로 in-memory 조인 루프의 "동일 → 제외" 분기를 교체한다 (`print.service.ts:275-285` 부근):

```ts
      const nameChanged = p.name !== log.name;
      const priceChanged = Number(current) !== Number(log.price);

      if (nameChanged || priceChanged) {
        result.push({
          ...base,
          status: 'CAMBIO',
          oldName: log.name,
          oldPrice: log.price,
        });
      } else if (scope === 'all') {
        // 동일 — delta 모드에선 제외, all 모드에선 재출력 대상으로 포함
        result.push({ ...base, status: 'IGUAL' });
      }
```

`Op` 는 이미 이 파일에서 `searchProductsForAgent` 가 쓰고 있으므로 import 추가 불필요하다. 확인만: `grep -n "^import.*Op" src/app/print/print.service.ts`

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd api-ventago && npx jest src/app/print`
Expected: PASS — 기존 QR 델타 테스트 전부 + 신규 7개. 기존 테스트 중 `getPendingQrDelta` 를 호출하는 것이 있으면 `getQrItems` 로 치환한다 (동작 동일).

- [ ] **Step 5: 커밋**

```bash
cd api-ventago
git add src/app/print/print.service.ts src/app/print/print.service.qr.spec.ts
git commit -m "feat(print): getQrItems — scope=all(IGUAL 포함) + sku/name 검색 필터

전체 SKU 검색/일괄 출력용. scope 기본 delta 는 기존 결과와 동일(회귀 0).
검색은 DB where 의 iLike — 5000행 읽고 인메모리로 버리지 않는다(pool 보호).
쿼리 수 5 SELECT 고정 유지."
```

---

### Task 2: 백엔드 — 게이트웨이 `get_qr_pending` scope/q 전달

**Files:**
- Modify: `api-ventago/src/app/print/print.gateway.ts:324-357`
- Test: `api-ventago/src/app/print/print.gateway.qr.spec.ts` (신규 — `ls src/app/print/*.spec.ts` 로 기존 게이트웨이 spec 이 있으면 거기에 `describe` 추가)

**Interfaces:**
- Consumes: Task 1 의 `getQrItems(branchId, priceTypeId, { scope, q })`
- Produces: WS ack `get_qr_pending` 이 payload `{ priceTypeId, scope?, q? }` 를 받는다. Task 5(main.js)가 이 계약으로 emit 한다.

- [ ] **Step 1: 실패하는 테스트 작성**

Create `api-ventago/src/app/print/print.gateway.qr.spec.ts`:

```ts
import { PrintGateway } from './print.gateway';

// get_qr_pending 핸들러 단위 테스트 — IDOR 가드 + scope 화이트리스트 + q 정규화.
// 위치 인자 생성자를 우회하고(Object.create) printService 만 mock 으로 주입한다.
describe('PrintGateway — get_qr_pending', () => {
  const BRANCH_ID = 3;
  const PRICE_TYPE_ID = 2;

  const makeGateway = () => {
    const printService = { getQrItems: jest.fn().mockResolvedValue([]) } as any;
    const gw: any = Object.create(PrintGateway.prototype);
    gw.printService = printService;
    gw.logger = { warn: jest.fn(), log: jest.fn() };

    return { gw, printService };
  };

  const client = (branchId?: number) => ({ data: { branchId } }) as any;

  it('branchId 없음 → NOT_AUTHENTICATED', async () => {
    const { gw, printService } = makeGateway();

    const res = await gw.handleGetQrPending(client(undefined), {
      priceTypeId: PRICE_TYPE_ID,
    });

    expect(res).toEqual({ ok: false, error: 'NOT_AUTHENTICATED' });
    expect(printService.getQrItems).not.toHaveBeenCalled();
  });

  it('priceTypeId 없음 → PRICE_TYPE_REQUIRED', async () => {
    const { gw } = makeGateway();

    const res = await gw.handleGetQrPending(client(BRANCH_ID), {});

    expect(res).toEqual({ ok: false, error: 'PRICE_TYPE_REQUIRED' });
  });

  it('scope 미전송(구 에이전트) → delta 폴백', async () => {
    const { gw, printService } = makeGateway();

    await gw.handleGetQrPending(client(BRANCH_ID), {
      priceTypeId: PRICE_TYPE_ID,
    });

    expect(printService.getQrItems).toHaveBeenCalledWith(
      BRANCH_ID,
      PRICE_TYPE_ID,
      { scope: 'delta', q: '' },
    );
  });

  it("scope='all' → all 전달", async () => {
    const { gw, printService } = makeGateway();

    await gw.handleGetQrPending(client(BRANCH_ID), {
      priceTypeId: PRICE_TYPE_ID,
      scope: 'all',
      q: 'camisa',
    });

    expect(printService.getQrItems).toHaveBeenCalledWith(
      BRANCH_ID,
      PRICE_TYPE_ID,
      { scope: 'all', q: 'camisa' },
    );
  });

  it('임의 scope 값 → delta 로 폴백 (화이트리스트)', async () => {
    const { gw, printService } = makeGateway();

    await gw.handleGetQrPending(client(BRANCH_ID), {
      priceTypeId: PRICE_TYPE_ID,
      scope: '../../etc',
    });

    expect(printService.getQrItems).toHaveBeenCalledWith(
      BRANCH_ID,
      PRICE_TYPE_ID,
      { scope: 'delta', q: '' },
    );
  });

  it('IDOR — payload 의 branchId 는 무시하고 client.data.branchId 만 사용', async () => {
    const { gw, printService } = makeGateway();

    await gw.handleGetQrPending(client(BRANCH_ID), {
      priceTypeId: PRICE_TYPE_ID,
      branchId: 999,
      storeId: 999,
    } as any);

    expect(printService.getQrItems).toHaveBeenCalledWith(
      BRANCH_ID,
      PRICE_TYPE_ID,
      { scope: 'delta', q: '' },
    );
  });

  it('q 200자 초과 → 절단', async () => {
    const { gw, printService } = makeGateway();

    await gw.handleGetQrPending(client(BRANCH_ID), {
      priceTypeId: PRICE_TYPE_ID,
      q: 'x'.repeat(500),
    });

    expect(printService.getQrItems.mock.calls[0][2].q).toHaveLength(200);
  });

  it('서비스 예외 → ok:false (throw 전파 안 함)', async () => {
    const { gw, printService } = makeGateway();
    printService.getQrItems.mockRejectedValue(new Error('boom'));

    const res = await gw.handleGetQrPending(client(BRANCH_ID), {
      priceTypeId: PRICE_TYPE_ID,
    });

    expect(res.ok).toBe(false);
    expect(res.error).toBe('boom');
  });
});
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd api-ventago && npx jest src/app/print/print.gateway.qr.spec.ts`
Expected: FAIL — `scope 미전송 → delta 폴백` 등이 `getQrItems` 미호출/인자 불일치로 실패 (현행 핸들러는 `getPendingQrDelta(branchId, priceTypeId)` 를 2인자로 호출)

- [ ] **Step 3: 구현**

`print.gateway.ts:324-357` 의 핸들러를 교체한다:

```ts
  // get_qr_pending — zebra-agent QR 항목 요청 (ack).
  //   scope='delta'(기본, 구 에이전트 폴백) = NUEVO/CAMBIO 만
  //   scope='all' = 동일 항목도 IGUAL 로 포함 (전체 SKU 검색/일괄 출력)
  //   q = sku/name 부분일치 (2자 이상일 때 서비스가 필터)
  // branchId 는 handleConnection 이 API key 로 세팅한 client.data.branchId 만 사용한다
  // (payload 의 branch/store 는 절대 신뢰하지 않는다 — D-6 IDOR 안전).
  @SubscribeMessage('get_qr_pending')
  async handleGetQrPending(
    @ConnectedSocket() client: Socket,
    @MessageBody() payload: { priceTypeId?: number; scope?: string; q?: string },
  ) {
    const branchId = client.data?.branchId;

    if (!branchId) {
      return { ok: false, error: 'NOT_AUTHENTICATED' };
    }

    const priceTypeId = Number(payload?.priceTypeId);

    if (!priceTypeId) {
      return { ok: false, error: 'PRICE_TYPE_REQUIRED' };
    }

    // 화이트리스트 — 'all' 외 모든 값(미전송/오타/주입 시도)은 delta
    const scope = payload?.scope === 'all' ? 'all' : 'delta';
    const q = String(payload?.q || '')
      .trim()
      .slice(0, 200);

    try {
      const items = await this.printService.getQrItems(branchId, priceTypeId, {
        scope,
        q,
      });

      return { ok: true, items };
    } catch (err: any) {
      this.logger.warn(
        `get_qr_pending 실패 (branch ${branchId}, scope ${scope}): ${err?.message}`,
      );

      return { ok: false, error: err?.message };
    }
  }
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd api-ventago && npx jest src/app/print`
Expected: PASS (게이트웨이 8개 + Task 1 의 서비스 테스트 전부)

`getPendingQrDelta` 잔존 참조가 없는지 확인:
Run: `cd api-ventago && grep -rn "getPendingQrDelta" src/`
Expected: 출력 없음

- [ ] **Step 5: 커밋**

```bash
cd api-ventago
git add src/app/print/print.gateway.ts src/app/print/print.gateway.qr.spec.ts
git commit -m "feat(print): get_qr_pending 에 scope/q 전달 + 화이트리스트

scope 는 'all' 외 전부 delta 폴백 → 구 에이전트 하위호환.
branchId 는 계속 client.data 만 사용(IDOR 불변) — payload branch/store 무시 테스트 추가."
```

---

### Task 3: zebra-agent — QR 자동맞춤 순수 함수

**Files:**
- Modify: `zebra-agent/src/zpl-formatter.js` (상수 블록 + `module.exports`)
- Test: `zebra-agent/test/qr-fit.test.js` (신규)

**Interfaces:**
- Consumes: 없음
- Produces (`module.exports` 에 추가):
  ```js
  utf8Len(s) -> number
  qrModuleCount(byteLen) -> number      // 21|25|29|33|37|41|45|49|53|57
  effectiveQrModule(qrUrl, cap, heightDots, regionDots) -> number
  QR_MARGIN = 10, QR_GAP = 12, QR_WIDTH_CAP = 0.55, MAX_QR_MODULE = 10
  ```
  Task 4(`renderQrBlock`)와 Task 6(renderer 프리뷰)이 이 계약을 쓴다. **Task 3 에서는 아무도 호출하지 않는다** — 순수 함수만 만들고 배선은 Task 4.

- [ ] **Step 1: 실패하는 테스트 작성**

Create `zebra-agent/test/qr-fit.test.js`:

```js
/**
 * QR 자동맞춤 순수 함수 단위 테스트.
 * 실행: node test/qr-fit.test.js
 *
 * 검증 대상 (2026-07-15 설계 D-4/D-6/D-7):
 *  - qrModuleCount: ECC M byte capacity 경계
 *  - effectiveQrModule: 사용자 상한(cap) / 높이 제약 / 폭 55% 캡 중 최솟값
 */
const assert = require('assert');
const {
  utf8Len,
  qrModuleCount,
  effectiveQrModule,
  QR_MARGIN,
  QR_WIDTH_CAP,
  MAX_QR_MODULE,
} = require('../src/zpl-formatter');

let passed = 0;
function ok(name, cond) {
  assert.ok(cond, name);
  passed += 1;
  console.log('  ✓', name);
}

console.log('QR 자동맞춤 (ECC M + 높이/폭 제약)\n');

// ── A) utf8Len ────────────────────────────────────────────────────────────
ok('A: ASCII 길이', utf8Len('abc') === 3);
ok('A: 멀티바이트는 byte 로 계산', utf8Len('ñ') === 2);
ok('A: null/undefined → 0', utf8Len(null) === 0 && utf8Len(undefined) === 0);

// ── B) qrModuleCount — ECC M byte capacity 경계 ───────────────────────────
ok('B: 14byte → v1(21모듈)', qrModuleCount(14) === 21);
ok('B: 15byte → v2(25모듈)', qrModuleCount(15) === 25);
ok('B: 42byte → v3(29모듈)', qrModuleCount(42) === 29);
ok('B: 43byte → v4(33모듈)', qrModuleCount(43) === 33);
ok('B: 62byte → v4(33모듈)', qrModuleCount(62) === 33);
ok('B: 63byte → v5(37모듈)', qrModuleCount(63) === 37);
ok('B: 213byte → v10(57모듈)', qrModuleCount(213) === 57);
ok('B: 용량 초과(214byte) → 최대 57 (방어)', qrModuleCount(214) === 57);

// ── C) 실측 — 딥링크 50byte, 50x25mm 라벨 ─────────────────────────────────
// 'https://ventago.coolsistema.com/m/stock?s=6&p=1234' = 50 byte
// ECC M: 50 <= 62 → v4 = 33 모듈  (ECC Q 였다면 v5 = 37 모듈)
const url = 'https://ventago.coolsistema.com/m/stock?s=6&p=1234';
ok('C: 딥링크 50byte', utf8Len(url) === 50);
ok('C: ECC M → 33모듈 (Q의 37에서 축소)', qrModuleCount(utf8Len(url)) === 33);

// region 400(50mm), H 200(25mm), cap 6
//   byHeight = floor((200-20)/33) = 5
//   byWidth  = floor((400*0.55-10)/33) = floor(210/33) = 6
//   → min(6, 5, 6) = 5   ← ECC Q 시절 4 에서 확대
ok('C: 50x25 + cap 6 → module 5', effectiveQrModule(url, 6, 200, 400) === 5);

// ── D) 제약별로 누가 이기는지 ──────────────────────────────────────────────
// cap 이 이김: cap 3 < byHeight 5
ok('D: cap 이 최소 → cap 반환', effectiveQrModule(url, 3, 200, 400) === 3);

// 높이가 이김: cap 10, H 200 → byHeight 5, byWidth 6
ok('D: 높이 제약이 최소 → 5', effectiveQrModule(url, 10, 200, 400) === 5);

// 폭이 이김: region 200(25mm), H 400(50mm)
//   byHeight = floor(380/33) = 11
//   byWidth  = floor((200*0.55-10)/33) = floor(100/33) = 3
ok('D: 폭 55% 캡이 최소 → 3', effectiveQrModule(url, 10, 400, 200) === 3);

// ── E) 경계/방어 ──────────────────────────────────────────────────────────
ok('E: 최소 1 보장 (라벨이 아주 작아도 0/음수 금지)',
  effectiveQrModule(url, 10, 30, 30) === 1);
ok('E: cap 은 MAX_QR_MODULE 로 클램프',
  effectiveQrModule(url, 999, 4000, 4000) === MAX_QR_MODULE);
ok('E: cap 미지정 → 기본 6 상한', effectiveQrModule(url, undefined, 200, 400) === 5);
ok('E: cap 0/음수 → 최소 1 이상', effectiveQrModule(url, 0, 200, 400) >= 1);

// ── F) 텍스트 침범 불가 — QR 폭이 region 의 55% 를 절대 못 넘음 ────────────
for (const cap of [1, 3, 5, 8, 10]) {
  const m = effectiveQrModule(url, cap, 400, 400);
  const qrRight = QR_MARGIN + qrModuleCount(utf8Len(url)) * m;
  ok(`F: cap ${cap} → QR 우측끝(${qrRight}) <= region*${QR_WIDTH_CAP}(${400 * QR_WIDTH_CAP})`,
    qrRight <= 400 * QR_WIDTH_CAP);
}

console.log(`\n${passed} checks passed ✅`);
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd zebra-agent && node test/qr-fit.test.js`
Expected: FAIL — `TypeError: utf8Len is not a function`

- [ ] **Step 3: 구현**

`zpl-formatter.js` 의 `MIN_SCANNABLE_MODULE_WIDTH = 2;` 선언(175행 부근) **바로 아래**에 추가:

```js
// ── QR 자동맞춤 (2026-07-15 D-4/D-6/D-7) ──────────────────────────────────
// ZPL ^BQ 가 받는 magnification 범위 상한
const MAX_QR_MODULE = 10;
const QR_MARGIN = 10;   // 라벨 여백 (dot)
const QR_GAP = 12;      // QR 과 텍스트 사이 간격 (dot)
const QR_WIDTH_CAP = 0.55; // QR 이 쓸 수 있는 최대 폭 비율 → 텍스트에 45% 보장

// QR byte 용량표 (ECC M, byte mode) — [모듈수, 최대 byte]
// ECC Q(25% 복원) → M(15%) 으로 낮춰 같은 URL 을 더 낮은 version 에 담는다.
// 50byte 딥링크: Q 면 v5(37모듈), M 이면 v4(33모듈) → 같은 높이에서 약 25% 확대.
const QR_ECC_M_CAPACITY = [
  [21, 14], [25, 26], [29, 42], [33, 62], [37, 84],
  [41, 106], [45, 122], [49, 152], [53, 180], [57, 213],
];

/**
 * 문자열의 UTF-8 byte 길이.
 * Buffer 가 아니라 TextEncoder 를 쓴다 — renderer(브라우저 컨텍스트)의 프리뷰가
 * 같은 계산을 해야 실물과 어긋나지 않기 때문.
 * @param {string} s
 * @returns {number}
 */
function utf8Len(s) {
  return new TextEncoder().encode(String(s == null ? '' : s)).length;
}

/**
 * byte 길이 → QR 한 변의 모듈 수 (ECC M).
 * @param {number} byteLen
 * @returns {number} 21|25|29|33|37|41|45|49|53|57 (용량 초과 시 최대 57)
 */
function qrModuleCount(byteLen) {
  for (const [modules, cap] of QR_ECC_M_CAPACITY) {
    if (byteLen <= cap) return modules;
  }

  return QR_ECC_M_CAPACITY[QR_ECC_M_CAPACITY.length - 1][0];
}

/**
 * QR magnification 자동 조절 — 사용자 상한(cap) / 라벨 높이 / 폭 55% 캡의 최솟값.
 * 바코드 moduleWidth 와 같은 패턴: 사용자 설정은 "상한"이고 실물이 안 들어가면 줄인다.
 * 폭 캡 덕에 QR 이 이름/가격 영역을 구조적으로 침범할 수 없다.
 * @param {string} qrUrl - 인코딩할 딥링크
 * @param {number} cap - 사용자 상한 (#qr-module)
 * @param {number} heightDots - 라벨 높이 (dot)
 * @param {number} regionDots - 상품 1장 폭 (dot)
 * @returns {number} 적용할 magnification (1 이상)
 */
function effectiveQrModule(qrUrl, cap, heightDots, regionDots) {
  const modules = qrModuleCount(utf8Len(qrUrl));
  const capped = Math.max(1, Math.min(MAX_QR_MODULE, cap || 6));
  const byHeight = Math.floor((heightDots - 2 * QR_MARGIN) / modules);
  const byWidth = Math.floor((regionDots * QR_WIDTH_CAP - QR_MARGIN) / modules);

  return Math.max(1, Math.min(capped, byHeight, byWidth));
}
```

`module.exports` 에 추가 (기존 항목 유지):

```js
  utf8Len,
  qrModuleCount,
  effectiveQrModule,
  MAX_QR_MODULE,
  QR_MARGIN,
  QR_GAP,
  QR_WIDTH_CAP,
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd zebra-agent && node test/qr-fit.test.js`
Expected: PASS — `26 checks passed ✅`

기존 테스트가 아직 안 깨졌는지 확인 (Task 3 은 배선 전이라 그대로여야 함):
Run: `cd zebra-agent && node test/qr-label.test.js && node test/print-flow.test.js`
Expected: 둘 다 PASS (32 / 42)

- [ ] **Step 5: 커밋**

```bash
cd zebra-agent
git add src/zpl-formatter.js test/qr-fit.test.js
git commit -m "feat(zebra): QR 자동맞춤 순수 함수 (ECC M 용량표 + 높이/폭 제약)

qrModuleCount(ECC M byte capacity) / effectiveQrModule(cap·높이·폭55% 최솟값).
폭 55% 캡으로 QR 이 이름/가격을 침범할 수 없게 한다.
Buffer 대신 TextEncoder — renderer 프리뷰가 같은 계산을 써야 하므로.
아직 배선 전(호출자 없음)."
```

---

### Task 4: zebra-agent — QR 라벨에 자동맞춤 + ECC M 배선

**Files:**
- Modify: `zebra-agent/src/zpl-formatter.js:504-590` (`renderQrBlock`, `formatQrLabel`)
- Test: `zebra-agent/test/qr-label.test.js` (기존 — ECC/splitRatio 단언 갱신)

**Interfaces:**
- Consumes: Task 3 의 `qrModuleCount`, `effectiveQrModule`, `utf8Len`, `QR_MARGIN`, `QR_GAP`
- Produces: `formatQrLabel({ qrUrl, name, price, priceLabel, layout })` — `layout.splitRatio` 를 **더 이상 읽지 않는다**. `layout.qrModule` 은 상한(기본 6). Task 6(renderer)이 이 계약에 맞춰 입력을 정리한다.

**주의:** 기존 `qr-label.test.js` 의 A/B/D/E 단언이 `^FDQA,` 와 `splitRatio` 좌표를 검증한다. ECC M 전환과 splitRatio 폐기의 필연적 결과이므로 **이 태스크에서 함께 갱신한다.**

- [ ] **Step 1: 실패하는 테스트 작성 (기존 단언 갱신 + 신규)**

`test/qr-label.test.js` 를 편집한다.

먼저 상단 주석 블록의 검증 대상 목록을 교체:

```js
/**
 * formatQrLabel 단위 테스트 — QR 배치 델타 라벨
 * 실행: node test/qr-label.test.js
 *
 * 검증 대상 (Phase 38 D-8/D-9/D-10, Phase 37 파서 계약, 2026-07-15 D-5/D-7):
 *  - QR 인코딩 값이 입력 qrUrl 과 byte-identical (딥링크 /m/stock?s=&p= 훼손 없음)
 *  - ECC M (^FDMA) — Q 에서 낮춰 같은 높이에 더 큰 QR
 *  - QR 실측 폭에서 역산한 좌우 배치 (splitRatio 폐기)
 *  - layout.mode='doble' → 같은 상품 2장 (^BQN 2회, 이름 2회)
 *  - layout 수치(widthMm/heightMm/qrModule/fontSize) 가 ZPL 에 반영
 *  - sanitize (^,~ 제거) / 긴 이름 줄바꿈
 */
```

import 를 확장:

```js
const {
  formatQrLabel,
  qrModuleCount,
  utf8Len,
  effectiveQrModule,
  QR_MARGIN,
  QR_GAP,
} = require('../src/zpl-formatter');
```

`ok('A: QR 인코딩 = qrUrl byte-identical', ...)` 를 교체:

```js
ok('A: QR 인코딩 = qrUrl byte-identical', zplA.includes(`^FDMA,${qrUrl}^FS`));
ok('A: ECC M 사용 (Q 아님)', /\^FDMA,/.test(zplA) && !/\^FDQA,/.test(zplA));
```

`ok('B: qrModule 기본 4 → ^BQN,2,4', ...)` 를 교체 — 기본 cap 6, 50x25 에서 높이 제약이 실효 5 로 결정:

```js
// 기본 cap 6 이지만 25mm 높이(200dot)/33모듈 → 실효 5
ok('B: 기본 cap 6 + 50x25 → ^BQN,2,5', /\^BQN,2,5\^FDMA,/.test(zplA));
```

**변수 충돌 주의:** 기존 파일 48-57행이 이미 `region`, `splitRatio`, `splitX`, `qrLine`, `nameLine`, `xOf` 를 `const` 로 선언한다. 아래는 **그 블록을 통째로 교체**하는 것이며, `region`/`xOf`/`qrLine`/`nameLine` 은 **재선언하지 말고 기존 이름을 그대로 재사용**한다. 새로 `const region` 을 쓰면 `SyntaxError: Identifier 'region' has already been declared` 가 난다.

D) 블록 48-57행(`// D) 1:3 좌우 배치` ~ `ok('D: 이름은 우 3/4 ...')`)을 아래로 교체:

```js
// D) 좌우 배치 — QR 실측 폭에서 역산 (splitRatio 폐기)
//    50byte URL → 33모듈, 50x25 라벨에서 module 5 → qrRight 175, textX 187
const region = 400;
const modulesD = qrModuleCount(utf8Len(qrUrl));
const moduleD = effectiveQrModule(qrUrl, 6, 200, region);
const qrRightD = QR_MARGIN + modulesD * moduleD;
const textXD = qrRightD + QR_GAP;
const qrLine = zplA.split('\n').find((l) => /\^BQN/.test(l));
const nameLine = zplA.split('\n').find((l) => /\^FDREMERA/.test(l));
const xOf = (l) => parseInt(l.match(/\^FO(\d+),/)[1], 10);

ok('D: 실측 — 33모듈 × module 5', modulesD === 33 && moduleD === 5);
ok('D: QR 은 좌측 margin 에서 시작', xOf(qrLine) === QR_MARGIN);
ok('D: 텍스트는 QR 우측끝 + gap 에서 시작', xOf(nameLine) === textXD);
ok('D: QR 과 텍스트가 겹치지 않음', xOf(nameLine) > qrRightD);

// D-2) 침범 불가 회귀 가드 — cap 을 최대로 올려도 텍스트를 못 덮는다
const zplD2 = formatQrLabel({ ...base, layout: { qrModule: 10 } });
const qrLineD2 = zplD2.split('\n').find((l) => /\^BQN/.test(l));
const nameLineD2 = zplD2.split('\n').find((l) => /\^FDREMERA/.test(l));
const moduleD2 = Number(/\^BQN,2,(\d+)/.exec(qrLineD2)[1]);
ok('D-2: cap 10 이어도 QR 우측끝 < 텍스트 x',
  QR_MARGIN + modulesD * moduleD2 < xOf(nameLineD2));
```

E) 블록에서 `splitRatio: 0.5,` 를 layout 에서 **삭제**:

```js
// E) layout 수치 변경 반영 — qrModule(상한)/fontSize/치수
const zplE = formatQrLabel({
  ...base,
  layout: { widthMm: 100, heightMm: 50, qrModule: 8, fontSize: 30 },
});
```

`ok('E: qrModule=8 → ^BQN,2,8', /\^BQN,2,8\^FDQA,/.test(zplE));` 를 교체 (100x50 → region 800, H 400. byHeight=floor(380/33)=11, byWidth=floor(430/33)=13 → min(8,11,13)=8, cap 이 이김):

```js
ok('E: qrModule=8 → ^BQN,2,8', /\^BQN,2,8\^FDMA,/.test(zplE));
```

`const splitXe = ...` 와 `ok('E: splitRatio=0.5 → 이름 x >= 400', ...)` 두 줄은 **삭제**한다. 기존 `const nameLineE` 선언은 **그대로 두고** 단언만 교체:

```js
const nameLineE = zplE.split('\n').find((l) => /\^FDREMERA/.test(l));
ok('E: 큰 라벨에서도 텍스트가 QR 우측에 위치',
  xOf(nameLineE) === QR_MARGIN + modulesD * 8 + QR_GAP);
```

말미 K-2 단언 아래에 신규 추가:

```js
// L) splitRatio 는 폐기 — 잔존 설정이 있어도 무시 (하위호환, 무해)
const zplL = formatQrLabel({ ...base, layout: { splitRatio: 0.5 } });
const zplLNoSplit = formatQrLabel({ ...base, layout: {} });
ok('L: 잔존 splitRatio 는 결과에 영향 없음', zplL === zplLNoSplit);
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd zebra-agent && node test/qr-label.test.js`
Expected: FAIL — `AssertionError: A: QR 인코딩 = qrUrl byte-identical` (현행은 `^FDQA,` 를 냄)

- [ ] **Step 3: 구현**

`zpl-formatter.js:504-539` 의 `renderQrBlock` 을 교체:

```js
/**
 * 단일 상품 QR 블록 렌더 (offsetX 적용 — doble 오른쪽 복제본용)
 * 좌 = QR(qrUrl 인코딩, 자동맞춤), 우 = 제품명(줄바꿈) + `{priceLabel}: {price}`.
 * 좌우 경계는 고정 비율이 아니라 QR 실측 폭에서 역산한다 (2026-07-15 D-5).
 * @param {Object} p - { qrUrl, name, price, priceLabel, qrModule, fontSize, region, height, offsetX }
 * @returns {string[]} ZPL 라인 배열
 */
function renderQrBlock(p) {
  const { qrUrl, name, price, priceLabel, qrModule, fontSize, region, height, offsetX } = p;
  const lines = [];

  // qrModule 은 사용자 상한 — 라벨 높이/폭에 맞춰 실효값을 산출한다
  const modules = qrModuleCount(utf8Len(qrUrl));
  const module = effectiveQrModule(qrUrl, qrModule, height, region);

  // 좌 QR — qrUrl 을 훼손 없이 인코딩 (Phase 37 파서 계약: sanitize 는 ^,~ 만 제거, 딥링크엔 없음)
  // ECC M(^FDMA) — Q 에서 낮춰 같은 높이에 더 큰 QR (D-7)
  lines.push(`^FO${offsetX + QR_MARGIN},${QR_MARGIN}^BQN,2,${module}^FDMA,${sanitize(qrUrl)}^FS`);

  // 우 패널 — QR 우측끝에서 gap 만큼 띄운 지점부터. 폭 55% 캡 덕에 항상 텍스트 자리가 남는다.
  const qrRight = QR_MARGIN + modules * module;
  const textX = offsetX + qrRight + QR_GAP;
  const availW = Math.max(1, region - qrRight - QR_GAP - QR_MARGIN);

  let y = QR_MARGIN;
  const nameLines = wrapQrText(sanitize(name || ''), fontSize, availW);
  for (const ln of nameLines) {
    lines.push(`^FO${textX},${y}^A0N,${fontSize},${fontSize}^FD${ln}^FS`);
    y += fontSize + 4;
  }

  // 가격줄 — `{priceLabel}: {price}` (이름 아래)
  const priceFs = Math.max(14, Math.round(fontSize * 0.9));
  const priceText = `${sanitize(priceLabel || '')}: ${formatPrice(price)}`.trim();
  lines.push(`^FO${textX},${y}^A0N,${priceFs},${priceFs}^FD${priceText}^FS`);

  return lines;
}
```

`formatQrLabel` 에서 3곳을 고친다:

JSDoc 의 layout 설명:
```js
 * @param {Object} [args.layout] - { widthMm, heightMm, qrModule, fontSize, mode, darkness, speed }
 *   qrModule 은 상한(기본 6) — 라벨 높이/폭이 실효값을 줄일 수 있다. splitRatio 는 폐기됨.
```

기본값 (`zpl-formatter.js:556-557`):
```js
  const qrModule = cfg.qrModule || 6;
```
→ `const splitRatio = cfg.splitRatio || 0.25;` 줄은 **삭제**.

blockArgs (`zpl-formatter.js:577`):
```js
  const blockArgs = { qrUrl, name, price, priceLabel, qrModule, fontSize, region, height: H };
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd zebra-agent && node test/qr-label.test.js && node test/qr-fit.test.js && node test/print-flow.test.js`
Expected: 셋 다 PASS

`splitRatio` 잔존 참조 확인:
Run: `cd zebra-agent && grep -n "splitRatio" src/zpl-formatter.js`
Expected: 출력 없음

- [ ] **Step 5: 커밋**

```bash
cd zebra-agent
git add src/zpl-formatter.js test/qr-label.test.js
git commit -m "feat(zebra): QR 확대 — ECC Q→M + 자동맞춤 배선, splitRatio 폐기

^FDQA → ^FDMA (복원력 25%→15%). 50byte 딥링크가 v5(37모듈)→v4(33모듈) 로
내려가 25mm 높이에서 module 4→5 (약 25% 확대).
좌우 경계는 고정 비율 대신 QR 실측 폭에서 역산 — 고정 비율은 qrModule 을
올렸을 때 QR 이 텍스트를 덮는 원인이었다.
기존 테스트의 ^FDQA/splitRatio 단언을 갱신(ECC/좌표 계약 변경의 필연)."
```

---

### Task 5: zebra-agent — IPC `qr:fetch` (scope/q 전달)

**Files:**
- Modify: `zebra-agent/main.js:545-559` (`qr:fetchPending` → `qr:fetch`)
- Modify: `zebra-agent/preload.js:45`

**Interfaces:**
- Consumes: Task 2 의 WS 계약 `get_qr_pending { priceTypeId, scope, q }`
- Produces: `window.api.qrFetch({ priceTypeId, scope, q })` → `{ ok, items }`. Task 6(renderer)이 이 이름으로 호출한다.

**테스트 없음 — 의도적.** `ipcMain.handle` 은 Electron 런타임에 묶여 있어 단위 테스트가 불가능하고, 이 태스크의 로직은 payload 를 그대로 전달하는 것뿐이다. `scope` 화이트리스트는 **서버가 권위**(Task 2 에서 테스트됨)이므로 클라이언트에 중복 구현하지 않는다. 검증은 기존 3개 스위트 회귀 + grep + Task 6 의 UAT.

- [ ] **Step 1: main.js 핸들러 교체**

`main.js:545-559` 의 `qr:fetchPending` 핸들러를 교체:

```js
// QR 항목 조회 — scope='delta'(변경분, 기본) | 'all'(전체 + 이름/SKU 검색)
// scope/q 검증은 서버(get_qr_pending)가 권위 — 여기서 중복 검사하지 않는다.
ipcMain.handle('qr:fetch', async (_event, { priceTypeId, scope, q } = {}) => {
  if (!wsConnection || connectionStatus !== 'connected') {
    return { ok: false, error: 'No conectado al servidor' };
  }

  const ptId = Number(priceTypeId);

  if (!ptId) {
    return { ok: false, error: 'Seleccioná un nivel de precio' };
  }

  try {
    const res = await wsConnection.timeout(10000).emitWithAck('get_qr_pending', {
      priceTypeId: ptId,
      scope: scope === 'all' ? 'all' : 'delta',
      q: String(q || '').trim(),
    });

    if (!res?.ok) return { ok: false, error: res?.error || 'Sin respuesta' };

    return { ok: true, items: res.items || [] };
  } catch (err) {
    return { ok: false, error: err.message || 'Timeout' };
  }
});
```

- [ ] **Step 2: preload.js 브리지 교체**

`preload.js:45` 를 교체:

```js
  qrFetch: (args) => ipcRenderer.invoke('qr:fetch', args),
```

- [ ] **Step 3: 회귀 없음 확인**

Run: `cd zebra-agent && node test/print-flow.test.js && node test/qr-label.test.js && node test/qr-fit.test.js`
Expected: 셋 다 PASS (이 태스크는 순수 함수를 안 건드리므로 전부 그대로 통과해야 한다)

구 이름 잔존 확인 (renderer 는 Task 6 에서 고치므로 아직 남아 있다):
Run: `cd zebra-agent && grep -rn "qrFetchPending\|qr:fetchPending" main.js preload.js`
Expected: 출력 없음

Run: `cd zebra-agent && node -c main.js && node -c preload.js`
Expected: 문법 오류 없음 (출력 없음)

- [ ] **Step 4: 커밋**

```bash
cd zebra-agent
git add main.js preload.js
git commit -m "feat(zebra): qr:fetch — scope/q 를 get_qr_pending 으로 전달

qr:fetchPending(priceTypeId) → qr:fetch({priceTypeId, scope, q}).
scope 화이트리스트는 서버가 권위 — 클라이언트에 중복 구현하지 않는다."
```

---

### Task 6: zebra-agent — QR 탭 UI (전체/검색 + IGUAL + 대량 확인)

**Files:**
- Modify: `zebra-agent/renderer/index.html`
  - CSS `.qr-badge` (107-110행 부근) — `igual` 추가
  - HTML QR 측정 카드 (520-537행) — `#qr-split-ratio` 제거, `#qr-module` 라벨/기본값
  - HTML QR 검색 카드 (542-560행) — scope 세그먼트 + 검색 input
  - JS TAB3 (1667-1990행) — layout/프리뷰/검색/렌더/출력
- Test: 수동 UAT (Electron) — renderer 는 자동 테스트 하네스가 없다

**Interfaces:**
- Consumes: Task 5 의 `api.qrFetch({ priceTypeId, scope, q })`, Task 3 의 상수(`QR_MARGIN`/`QR_GAP`/`QR_WIDTH_CAP`/`MAX_QR_MODULE`)와 동일한 공식
- Produces: 없음 (최종 태스크)

**중요 — spec 이 놓친 동작:** 현행 `index.html:1969` 는 출력 성공 행을 `tr.remove()` 로 지운다. 델타 모드에선 맞지만(더 이상 pending 아님) **전체 모드에선 방금 출력한 상품이 목록에서 사라져 재출력이 불가능해진다.** 전체 모드는 행을 남기고 `IGUAL` 로 재배지 + 체크 해제한다.

**renderer 는 `zpl-formatter.js` 를 import 할 수 없다** (Electron contextIsolation). 현행 프리뷰도 `drawBarcode` 로직을 미러링 중이다. 상수·공식을 복제하되 Task 3 과 **정확히 같은 값**을 써야 한다.

- [ ] **Step 1: CSS — IGUAL 배지 추가**

`index.html:110` 의 `.qr-badge.cambio` 줄 아래에 추가:

```css
    .qr-badge.igual { background:#0f3460; border:1px solid #555; color:#888; }
```

- [ ] **Step 2: HTML — 측정 카드에서 splitRatio 제거**

`index.html:527-530` 을 교체:

```html
            <label for="qr-module">Tamaño QR (máx)</label>
            <input type="number" id="qr-module" min="1" max="10" step="1" value="6"
              title="Tope del tamaño. El alto de la etiqueta puede reducirlo automáticamente para que el QR no tape el texto.">
```

(`<label for="qr-split-ratio">` 와 `<input id="qr-split-ratio">` 두 줄은 삭제)

`index.html:517` 의 hint 를 교체:

```html
          <div class="preview-hint">QR a la izquierda (auto-ajuste) / nombre + precio a la derecha</div>
```

- [ ] **Step 3: HTML — scope 세그먼트 + 검색칸**

`index.html:543` 의 카드 제목을 교체:

```html
          <div class="card-title">Etiquetas QR</div>
```

`index.html:556` 의 `<button class="btn btn-primary" id="qr-buscar">Buscar cambios</button>` 를 포함한 `<div style="display:flex; justify-content:space-between; ...">` 블록 **바로 위**에 scope 행을 삽입:

```html
          <div style="display:flex; gap:8px; align-items:center; margin-bottom:10px;">
            <div class="qr-seg">
              <label><input type="radio" name="qr-scope" id="qr-scope-delta" value="delta" checked><span>Cambios</span></label>
              <label><input type="radio" name="qr-scope" id="qr-scope-all" value="all"><span>Todos</span></label>
            </div>
            <input type="text" id="qr-query" placeholder="nombre / SKU" disabled
              style="flex:1; padding:6px 8px; background:#0f3460; border:1px solid #2a2a4a;
                     border-radius:6px; color:#e0e0e0; font-size:12px;">
          </div>
```

그리고 `id="qr-buscar"` 버튼의 텍스트를 `Buscar` 로 바꾼다.

- [ ] **Step 4: JS — layout 에서 splitRatio 제거 + 자동맞춤 미러**

`index.html:1676` 을 교체:

```js
  const QR_DEFAULT_LAYOUT = { widthMm: 50, heightMm: 25, qrModule: 6, fontSize: 22 };

  // ── zpl-formatter.js 의 QR 자동맞춤 미러 (renderer 는 main 모듈을 import 할 수 없다) ──
  // 값이 어긋나면 프리뷰와 실물이 달라진다. src/zpl-formatter.js 와 항상 같이 고칠 것.
  const QR_MARGIN = 10;
  const QR_GAP = 12;
  const QR_WIDTH_CAP = 0.55;
  const MAX_QR_MODULE = 10;
  const QR_ECC_M_CAPACITY = [
    [21, 14], [25, 26], [29, 42], [33, 62], [37, 84],
    [41, 106], [45, 122], [49, 152], [53, 180], [57, 213],
  ];

  function qrUtf8Len(s) {
    return new TextEncoder().encode(String(s == null ? '' : s)).length;
  }

  function qrModuleCount(byteLen) {
    for (const [modules, cap] of QR_ECC_M_CAPACITY) {
      if (byteLen <= cap) return modules;
    }

    return QR_ECC_M_CAPACITY[QR_ECC_M_CAPACITY.length - 1][0];
  }

  function effectiveQrModule(qrUrl, cap, heightDots, regionDots) {
    const modules = qrModuleCount(qrUtf8Len(qrUrl));
    const capped = Math.max(1, Math.min(MAX_QR_MODULE, cap || 6));
    const byHeight = Math.floor((heightDots - 2 * QR_MARGIN) / modules);
    const byWidth = Math.floor((regionDots * QR_WIDTH_CAP - QR_MARGIN) / modules);

    return Math.max(1, Math.min(capped, byHeight, byWidth));
  }

  // 프리뷰용 대표 딥링크 (실제 URL 과 같은 길이대 — 50byte 안팎)
  const QR_SAMPLE_URL = 'https://ventago.coolsistema.com/m/stock?s=6&p=1234';
```

`qrLoadLayout` 에서 `$('#qr-split-ratio').value = l.splitRatio;` 줄 **삭제**.

`qrReadLayout` 에서 `splitRatio: num('#qr-split-ratio', 0.25),` 줄 **삭제**, `qrModule` 기본값을 6으로:

```js
      qrModule: Math.round(num('#qr-module', 6)),
```

- [ ] **Step 5: JS — 프리뷰를 실측 역산으로**

`index.html:1728-1736` 의 "좌 QR 패널 폭 = splitRatio" ~ 의사 QR 그리드 블록을 교체:

```js
    // 좌 QR 패널 폭 — 실물과 같은 자동맞춤 계산에서 역산 (고정 비율 아님)
    const region = Math.round(l.widthMm * 8);
    const H = Math.round(l.heightMm * 8);
    const modules = qrModuleCount(qrUtf8Len(QR_SAMPLE_URL));
    const module = effectiveQrModule(QR_SAMPLE_URL, l.qrModule, H, region);
    const qrRight = QR_MARGIN + modules * module;
    const pct = Math.max(10, Math.min(QR_WIDTH_CAP * 100, (qrRight / region) * 100));
    box.querySelector('.qp-qr').style.flexBasis = pct + '%';

    // 의사 QR 그리드 — 실제 모듈 수를 그대로 반영 (33×33 등)
    const grid = $('#qr-preview-grid');
    const cells = modules;
    grid.style.gridTemplateColumns = `repeat(${cells}, 1fr)`;
    grid.style.gridTemplateRows = `repeat(${cells}, 1fr)`;
    grid.textContent = '';
    for (let i = 0; i < cells * cells; i++) {
      const c = document.createElement('i');
      // 결정적 패턴 + 위치검출 사각형 3개 모서리
      const r = Math.floor(i / cells), col = i % cells;
      const finder = (r < 3 && col < 3) || (r < 3 && col >= cells - 3) || (r >= cells - 3 && col < 3);
      const on = finder || ((r * 7 + col * 13 + r * col) % 3 === 0);
      c.style.background = on ? '#111' : '#fff';
      grid.appendChild(c);
    }
```

`index.html:1798` 의 input 리스너 배열에서 `'#qr-split-ratio'` 를 제거:

```js
  ['#qr-width-mm', '#qr-height-mm', '#qr-module', '#qr-font-size']
    .forEach(sel => { $(sel).addEventListener('input', renderPreview); });
```

- [ ] **Step 6: JS — scope 토글 + 검색 + qrFetch**

`index.html:1674` 아래에 현재 scope 를 읽는 helper 를 추가:

```js
  const qrScope = () => ($('#qr-scope-all').checked ? 'all' : 'delta');
```

scope 라디오에 리스너 추가 (`#qr-save-layout` 리스너 위에):

```js
  // scope 전환 — 검색칸은 Todos 에서만 (Cambios 는 전량 검토가 목적)
  ['#qr-scope-delta', '#qr-scope-all'].forEach(sel => {
    $(sel).addEventListener('change', () => {
      const all = qrScope() === 'all';
      $('#qr-query').disabled = !all;
      if (!all) $('#qr-query').value = '';
      $('#qr-buscar').textContent = all ? 'Buscar' : 'Buscar cambios';
    });
  });

  // 검색칸 Enter → Buscar
  $('#qr-query').addEventListener('keydown', (e) => {
    if (e.key === 'Enter') $('#qr-buscar').click();
  });
```

`#qr-buscar` 리스너(1814-1845행)를 교체:

```js
  // ── Buscar → qrFetch(scope, q) → 테이블 ──
  $('#qr-buscar').addEventListener('click', async () => {
    const priceTypeId = Number($('#qr-price-type').value);
    if (!priceTypeId) { qrBanner('error', 'Seleccioná un nivel de precio.'); return; }

    const scope = qrScope();
    const q = scope === 'all' ? $('#qr-query').value.trim() : '';

    qrBanner('info', scope === 'all' ? 'Buscando etiquetas...' : 'Buscando cambios...');
    $('#qr-buscar').disabled = true;
    let r;
    try {
      r = await api.qrFetch({ priceTypeId, scope, q });
    } catch (err) {
      qrBanner('error', 'Error al buscar: ' + (err?.message || err));
      $('#qr-buscar').disabled = false;

      return;
    }
    $('#qr-buscar').disabled = false;

    if (!r?.ok) {
      qrBanner('error', 'Error al buscar: ' + (r?.error || 'sin respuesta'));

      return;
    }

    currentDelta = Array.isArray(r.items) ? r.items : [];
    renderQrDelta();

    if (currentDelta.length === 0) {
      qrBanner('info', q
        ? `Sin resultados para "${q}".`
        : (scope === 'all'
          ? 'No hay productos con código madre en esta sucursal.'
          : 'Sin cambios — no hay etiquetas nuevas ni modificadas.'));
    } else {
      qrBanner('ok', currentDelta.length + ' etiqueta(s) encontrada(s).');
    }
  });
```

- [ ] **Step 7: JS — IGUAL 배지 렌더**

`renderQrDelta` 의 상태 배지 블록(1863-1869행)을 교체:

```js
      // 상태 배지 — NUEVO(gold) / CAMBIO(orange) / IGUAL(muted, 전체 모드 전용)
      const tdSt = document.createElement('td');
      const badge = document.createElement('span');
      const st = item.status === 'NUEVO' || item.status === 'IGUAL' ? item.status : 'CAMBIO';
      badge.className = 'qr-badge ' + st.toLowerCase();
      badge.textContent = st;
      tdSt.appendChild(badge);
```

이어지는 `const isNuevo = item.status === 'NUEVO';` 를 쓰는 이름/가격 블록은 `CAMBIO` 일 때만 old 값을 병기해야 한다. 1866행의 `const isNuevo` 선언을 배지 블록 위로 올리고 아래처럼 바꾼다:

```js
      // old 값 병기는 CAMBIO 에서만 (IGUAL 은 old 가 곧 현재값이라 의미 없음)
      const isCambio = item.status === 'CAMBIO';
```

그리고 이름/가격 블록의 `!isNuevo` 두 곳을 `isCambio` 로 교체:

```js
      const tdName = document.createElement('td');
      tdName.textContent = item.name || '-';
      if (isCambio && item.oldName && item.oldName !== item.name) {
        tdName.title = 'Antes: ' + item.oldName;
      }
```
```js
      const tdPrice = document.createElement('td');
      if (isCambio && item.oldPrice != null && Number(item.oldPrice) !== Number(item.price)) {
```

- [ ] **Step 8: JS — 대량 확인 배너 + 출력 후 행 처리**

`#qr-print-btn` 리스너(1927행)의 `if (items.length === 0) return;` **아래**에 확인 게이트를 삽입:

```js
    // 대량 출력 확인 — 100건 초과 시에만 (D-8). 상한은 두지 않는다.
    const mode = $('#qr-mode-doble').checked ? 'doble' : 'simple';
    const sheets = mode === 'doble' ? items.length * 2 : items.length;
    if (items.length > 100 && !(await qrConfirmBulk(items.length, sheets))) {
      qrBanner('info', 'Impresión cancelada.');

      return;
    }
```

기존의 `const mode = $('#qr-mode-doble').checked ? 'doble' : 'simple';` 줄(1935행)은 위로 옮겼으므로 **삭제**한다.

`qrBanner` 함수 아래에 확인 헬퍼를 추가한다. **`confirm()` 은 쓰지 않는다** — Electron 모달 다이얼로그는 세션을 블록한다:

```js
  // 대량 출력 확인 — 인라인 배너 (네이티브 confirm 은 Electron 세션을 블록하므로 금지)
  function qrConfirmBulk(count, sheets) {
    return new Promise((resolve) => {
      const el = $('#qr-status');
      el.className = 'qr-banner show warn';
      el.textContent = '';

      const msg = document.createElement('span');
      msg.textContent = `⚠ ${count} etiquetas seleccionadas (${sheets} impresiones). ¿Imprimir todo? `;

      const yes = document.createElement('button');
      yes.className = 'btn btn-primary';
      yes.style.marginLeft = '8px';
      yes.textContent = 'Imprimir';

      const no = document.createElement('button');
      no.className = 'btn btn-secondary';
      no.style.marginLeft = '6px';
      no.textContent = 'Cancelar';

      const done = (v) => { yes.disabled = true; no.disabled = true; resolve(v); };
      yes.addEventListener('click', () => done(true));
      no.addEventListener('click', () => done(false));

      el.appendChild(msg); el.appendChild(yes); el.appendChild(no);
    });
  }
```

`.qr-banner.warn` CSS 가 없으면 `.qr-badge.igual` 줄 아래에 추가:

```css
    .qr-banner.warn { background:rgba(245,166,35,.12); border:1px solid #f5a623; color:#f5a623; }
```

출력 후 행 처리(1960-1973행)를 교체 — **전체 모드는 행을 지우지 않는다**:

```js
    // 델타 모드: 성공분은 더 이상 pending 이 아니므로 행 제거.
    // 전체 모드: 재출력이 목적이므로 행을 남기고 IGUAL 로 재배지 + 체크 해제.
    const isAll = qrScope() === 'all';
    $$('#qr-delta-list tr').forEach(tr => {
      const pid = Number(tr.dataset.productId);
      const cb = tr.querySelector('input[type="checkbox"]');
      if (!cb || !cb.checked) return;
      if (failedIds.includes(pid)) {
        tr.classList.add('qr-failed');

        return;
      }
      if (!isAll) {
        tr.remove();

        return;
      }
      // 출력 성공 → 스냅샷이 갱신되었으므로 이제 IGUAL
      tr.classList.remove('qr-failed');
      cb.checked = false;
      const badge = tr.querySelector('.qr-badge');
      if (badge) { badge.className = 'qr-badge igual'; badge.textContent = 'IGUAL'; }
    });

    // currentDelta — 전체 모드는 유지(상태만 IGUAL), 델타 모드는 성공분 제거
    if (isAll) {
      currentDelta = currentDelta.map(it =>
        selectedIds.includes(Number(it.productId)) && !failedIds.includes(Number(it.productId))
          ? { ...it, status: 'IGUAL' }
          : it);
    } else {
      currentDelta = currentDelta.filter(it =>
        !selectedIds.includes(Number(it.productId)) || failedIds.includes(Number(it.productId)));
    }

    $('#qr-select-all').checked = false;
    qrUpdateSelection();
```

(교체 후 이어지는 `if (failedIds.length > 0) { qrBanner('error', ...) }` 블록은 그대로 둔다. 단 `qrUpdateSelection()` 이 그 아래에 또 있으면 중복이므로 하나만 남긴다.)

- [ ] **Step 9: 자동 테스트 재확인 (회귀 없음)**

Run: `cd zebra-agent && node test/qr-label.test.js && node test/qr-fit.test.js && node test/print-flow.test.js`
Expected: 셋 다 PASS (renderer 변경은 이 테스트들과 무관해야 함)

구 API 잔존 확인:
Run: `cd zebra-agent && grep -rn "qrFetchPending\|qr-split-ratio\|splitRatio" renderer/index.html main.js preload.js src/`
Expected: 출력 없음

renderer 미러 상수가 원본과 일치하는지 눈으로 대조:
Run: `cd zebra-agent && grep -n "QR_WIDTH_CAP\|MAX_QR_MODULE\|QR_MARGIN = \|QR_GAP = " src/zpl-formatter.js renderer/index.html`
Expected: 양쪽 값이 `0.55 / 10 / 10 / 12` 로 동일

- [ ] **Step 10: 커밋**

```bash
cd zebra-agent
git add renderer/index.html
git commit -m "feat(zebra): QR 탭 — Cambios/Todos 토글 + 이름·SKU 검색 + 일괄 출력

- scope 세그먼트. Todos 에서만 검색칸 활성(Cambios 는 전량 검토가 목적)
- IGUAL 배지(muted) — 이미 출력한 라벨도 재출력 대상
- 100건 초과 시 인라인 확인 배너(네이티브 confirm 은 Electron 세션을 블록하므로 금지)
- 출력 후 행 처리 분기: 델타=제거 / 전체=IGUAL 재배지+체크해제
  (전체 모드에서 행을 지우면 방금 출력한 상품이 사라져 재출력 불가)
- splitRatio 입력 제거, 프리뷰를 실측 자동맞춤 역산으로 (의사 QR 격자도 실제 모듈 수)"
```

---

## 수동 UAT (구현 후 필수)

renderer 는 자동 테스트 하네스가 없다. Electron 실행 후 확인:

```bash
cd zebra-agent && npm start
```

1. **Cambios 모드 회귀** — 검색칸 비활성, `Buscar cambios` 가 기존과 동일 동작(NUEVO/CAMBIO 만)
2. **Todos 모드** — 검색칸 활성, 비우고 Buscar → 전체 목록에 IGUAL 표시
3. **검색** — `camisa` 입력 → 이름/SKU 부분일치만. 없는 값 → `Sin resultados para "..."`
4. **일괄 출력** — 전체 선택 → 100 초과면 확인 배너 → Imprimir → 행이 남고 IGUAL 로 바뀜
5. **QR 확대 (핵심)** — 실물 라벨의 QR 이 이전보다 크고, **스캔이 되는지 확인**
   - ECC M + quiet zone 2모듈이 이 설계의 최대 리스크
   - 실패 시 1차 대응: `QR_MARGIN` 을 `4 * module` 로 (단 module 이 다시 4로 내려가 확대 효과 상쇄)
6. **프리뷰 일치** — 프리뷰의 QR 폭 비율이 실물과 비슷한지
7. **텍스트 침범 없음** — `Tamaño QR (máx)` 를 10 으로 올려도 이름/가격이 안 덮이는지

## 배포

- **DB 마이그레이션 없음.**
- 백엔드: **Jenkins 수동 빌드** (`api-new-coolsistema`). git push 는 자동배포 안 됨.
- zebra-agent: 태그 push → GitHub Actions `build-zebra-agent.yml`
- **순서 무관** — 구 에이전트는 `scope` 미전송 → 서버 `delta` 폴백. 신 에이전트 + 구 서버는 `scope` 가 무시되어 Todos 가 델타처럼 동작(기능 미노출, 오작동 아님).
- 이미 커밋된 `1d5eca1`(바코드 moduleWidth 기본값 3)도 같은 태그 빌드에 실린다.
