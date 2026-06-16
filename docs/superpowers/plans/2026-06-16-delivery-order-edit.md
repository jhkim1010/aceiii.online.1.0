# 배달 주문 편집 기능 (Delivery Order Edit) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 보드(`DeliveryBoard`)에서 이미 접수된 배달 주문의 품목(En cocina 까지)과 메타정보(고객/주소/결제수단/canal/앱주문번호, En camino 전까지)를 편집할 수 있게 한다.

**Architecture:** 신규 `PATCH /restaurant-delivery/:id`(부분 편집) + `GET /restaurant-delivery/:id`(프리필 상세) 엔드포인트. 편집은 Sale `DRAFT` 구간(en_cocina~listo)에서만 → `SaleItem` 교체 + `totalAmount` 재계산으로 재고/현금 무영향. QR 결제는 미결제 인텐트 cancel+recreate, 결제완료(approved)면 편집 차단. 품목 변경 시 코만다 `MODIFICADO` 재출력. 프론트는 기존 `NuevoPedidoModal`을 편집 모드로 확장(DRY).

**Tech Stack:** NestJS 11 + Sequelize (백엔드), Jest (테스트), Next.js 13 + MUI 5 (프론트), Electron print-agent (comanda 템플릿).

**참조 설계:** `docs/superpowers/specs/2026-06-16-delivery-order-edit-design.md`

---

## File Structure

**백엔드 (`api-ventago/`):**
- Modify: `src/app/restaurant-delivery/dto/restaurant-delivery.dto.ts` — `UpdateDeliveryOrderDto` 추가
- Modify: `src/app/mercadopago/qr/mp-qr.service.ts` — `findActiveIntentByVenta()` 헬퍼 추가
- Modify: `src/app/restaurant-delivery/restaurant-delivery.service.ts` — `getOrderDetail()`, `updateOrder()`, `reconcileQrIntent()` 추가
- Modify: `src/app/restaurant-delivery/restaurant-delivery.controller.ts` — `GET /:id`, `PATCH /:id` 라우트
- Modify: `src/app/restaurant-delivery/restaurant-delivery.service.spec.ts` — 단위 테스트 추가

**프린터 (`print-agent/`):**
- Modify: `src/formatter.js` — `data.modified` 시 `MODIFICADO` 배너

**프론트 (`ventago-app/`):**
- Modify: `src/views/restaurante/components/NuevoPedidoModal.tsx` — 편집 모드
- Modify: `src/views/restaurante/DeliveryBoard.tsx` — Editar 버튼 + 모달 공용

---

## Task 1: `UpdateDeliveryOrderDto` 추가

**Files:**
- Modify: `api-ventago/src/app/restaurant-delivery/dto/restaurant-delivery.dto.ts`

- [ ] **Step 1: DTO 클래스 추가**

`restaurant-delivery.dto.ts` 파일 맨 끝(`TransitionDto` 아래)에 추가. `DeliveryOrderItemDto`는 같은 파일에 이미 존재하므로 재사용한다.

```typescript
// 주문 편집 본문 — 모든 필드 optional(부분 편집). 상태별 편집 가드는 서비스에서 강제.
// items 제공 시 전체 교체(델타 아님). terminalId 는 QR 인텐트 재생성 시 필요(서비스 검증).
export class UpdateDeliveryOrderDto {
  @IsOptional()
  @IsArray()
  @ArrayMinSize(1)
  @ValidateNested({ each: true })
  @Type(() => DeliveryOrderItemDto)
  items?: DeliveryOrderItemDto[];

  @IsOptional()
  @IsEnum(PaymentMode)
  paymentMode?: PaymentMode;

  @IsOptional()
  @IsEnum(DeliveryCanal)
  canal?: DeliveryCanal;

  @IsOptional()
  @IsInt()
  terminalId?: number;

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  address?: string;

  @IsOptional()
  @IsInt()
  clientId?: number;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  customerName?: string;

  @IsOptional()
  @IsString()
  @MaxLength(40)
  customerPhone?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  externalRef?: string;
}
```

- [ ] **Step 2: 컴파일 확인**

Run: `cd api-ventago && npx tsc --noEmit -p tsconfig.json 2>&1 | grep -i "restaurant-delivery.dto" || echo "OK no DTO errors"`
Expected: `OK no DTO errors` (기존 import `ArrayMinSize/IsArray/ValidateNested/Type/IsEnum/IsInt/IsString/MaxLength/IsOptional` 모두 이미 존재 — no-unused-vars 영향 없음)

- [ ] **Step 3: Commit**

```bash
git -C api-ventago add src/app/restaurant-delivery/dto/restaurant-delivery.dto.ts
git -C api-ventago commit -m "feat(40-edit): UpdateDeliveryOrderDto for partial order edit"
```

---

## Task 2: `findActiveIntentByVenta()` 헬퍼 (MpQrService)

**Files:**
- Modify: `api-ventago/src/app/mercadopago/qr/mp-qr.service.ts`

`cancelIntent`은 `intentId`를 받지만, 편집 시점엔 `sale.id`만 알고 있어 활성 인텐트를 조회하는 경로가 필요하다. `this.intentModel`은 이미 주입되어 있다(`cancelIntent`의 `this.intentModel.findByPk` 사용 확인).

- [ ] **Step 1: 헬퍼 메서드 추가**

`mp-qr.service.ts`의 `cancelIntent(...)` 메서드 **바로 아래**에 추가:

```typescript
  // 편집 시 활성(미결제/결제완료) 인텐트 조회 — pendingVentaId(=sale.id) 기준 최신 1건.
  // 'pending' → cancel/recreate 대상, 'approved' → 편집 차단 신호. terminal(cancelled/expired/failed) 제외.
  async findActiveIntentByVenta(
    pendingVentaId: number,
  ): Promise<{ id: number; status: string } | null> {
    const intent = await this.intentModel.findOne({
      where: { pendingVentaId, status: ['pending', 'approved'] as any },
      order: [['id', 'DESC']],
    });

    return intent ? { id: intent.id, status: intent.status } : null;
  }
```

- [ ] **Step 2: 컴파일 확인**

Run: `cd api-ventago && npx tsc --noEmit -p tsconfig.json 2>&1 | grep -i "mp-qr.service" || echo "OK"`
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git -C api-ventago add src/app/mercadopago/qr/mp-qr.service.ts
git -C api-ventago commit -m "feat(40-edit): MpQrService.findActiveIntentByVenta lookup"
```

---

## Task 3: `getOrderDetail()` 서비스 (프리필 상세) — TDD

**Files:**
- Modify: `api-ventago/src/app/restaurant-delivery/restaurant-delivery.service.ts`
- Test: `api-ventago/src/app/restaurant-delivery/restaurant-delivery.service.spec.ts`

- [ ] **Step 1: 실패 테스트 작성**

`restaurant-delivery.service.spec.ts`의 마지막 `describe`/테스트 뒤, 파일 닫는 `});` **앞**에 추가. (`build()` 헬퍼는 파일 상단에 이미 정의됨 — `sequelize.query`는 기본 `[]` 반환하므로 items 모킹을 위해 override)

```typescript
  describe('getOrderDetail', () => {
    it('storeId 스코프로 delivery + items 를 반환한다', async () => {
      const ctx = build();
      ctx.deliveryRow.tipo = DeliveryTipo.DELIVERY;
      ctx.deliveryRow.customerName = 'Ana';
      ctx.sequelize.query.mockResolvedValueOnce([
        { productId: 10, qty: 2, price: 1500, customName: null, name: 'Pizza' },
      ]);

      const detail = await ctx.service.getOrderDetail(9, 77);

      expect(ctx.deliveryModel.findOne).toHaveBeenCalledWith({
        where: { id: 77, storeId: 9 },
      });
      expect(detail.id).toBe(77);
      expect(detail.items).toEqual([
        { productId: 10, name: 'Pizza', price: 1500, qty: 2 },
      ]);
    });

    it('없는 주문이면 NotFoundException', async () => {
      const ctx = build();
      ctx.deliveryModel.findOne.mockResolvedValueOnce(null);

      await expect(ctx.service.getOrderDetail(9, 999)).rejects.toThrow(
        'Pedido no encontrado',
      );
    });
  });
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd api-ventago && npx jest restaurant-delivery.service.spec --silent 2>&1 | tail -20`
Expected: FAIL — `service.getOrderDetail is not a function`

- [ ] **Step 3: `getOrderDetail` 구현**

`restaurant-delivery.service.ts`의 `getBoard(...)` 메서드 **바로 아래**에 추가. (`QueryTypes`, `NotFoundException`는 이미 import됨)

```typescript
  // ── 편집 프리필 상세 (주문 편집) ──
  // storeId 스코프 delivery + sale_items(상품명 LEFT JOIN). 모달 cart/메타 프리필 전용.
  async getOrderDetail(storeId: number, deliveryId: number): Promise<any> {
    const d = await this.deliveryModel.findOne({
      where: { id: deliveryId, storeId },
    });
    if (!d) {
      throw new NotFoundException('Pedido no encontrado');
    }

    const items: any[] = await this.sequelize.query(
      `SELECT si.product_id  AS "productId",
              si.quantity    AS "qty",
              si.price       AS "price",
              si.custom_name AS "customName",
              p.name         AS "name"
         FROM sale_items si
         LEFT JOIN products p ON p.id = si.product_id
        WHERE si.sale_id = :saleId
        ORDER BY si.id ASC`,
      { replacements: { saleId: d.saleId }, type: QueryTypes.SELECT },
    );

    return {
      id: d.id,
      saleId: d.saleId,
      status: d.status,
      tipo: d.tipo,
      canal: d.canal,
      paymentMode: d.paymentMode,
      customerName: d.customerName ?? null,
      customerPhone: d.customerPhone ?? null,
      address: d.address ?? null,
      clientId: d.clientId ?? null,
      externalRef: d.externalRef ?? null,
      repartidorId: d.repartidorId ?? null,
      items: items.map((i) => ({
        productId: i.productId,
        name: i.customName ?? i.name ?? 'Producto',
        price: Number(i.price) || 0,
        qty: Number(i.qty) || 0,
      })),
    };
  }
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd api-ventago && npx jest restaurant-delivery.service.spec --silent 2>&1 | tail -20`
Expected: PASS (getOrderDetail describe 2건 포함)

- [ ] **Step 5: Commit**

```bash
git -C api-ventago add src/app/restaurant-delivery/restaurant-delivery.service.ts src/app/restaurant-delivery/restaurant-delivery.service.spec.ts
git -C api-ventago commit -m "feat(40-edit): getOrderDetail for edit prefill"
```

---

## Task 4: `updateOrder()` — 상태 가드 + 품목/메타 편집 (TDD)

**Files:**
- Modify: `api-ventago/src/app/restaurant-delivery/restaurant-delivery.service.ts`
- Test: `api-ventago/src/app/restaurant-delivery/restaurant-delivery.service.spec.ts`

QR 인텐트 재조정(Task 5)을 위해 `mpQrService` 모킹에 `findActiveIntentByVenta`/`cancelIntent`를 추가해야 한다. 먼저 `build()` 헬퍼의 mpQrService 모킹을 확장한다.

- [ ] **Step 1: `build()` 의 mpQrService 모킹 확장**

`restaurant-delivery.service.spec.ts`의 `build()` 내 `mpQrService` 정의를 다음으로 교체:

```typescript
    const mpQrService = {
      createIntent: jest.fn().mockResolvedValue({ intentId: 1, qrData: 'q', expiresAt: new Date() }),
      cancelIntent: jest.fn().mockResolvedValue({ ok: true }),
      findActiveIntentByVenta: jest.fn().mockResolvedValue(null),
    };
```

- [ ] **Step 2: 실패 테스트 작성 (품목/메타 가드)**

`restaurant-delivery.service.spec.ts` 닫는 `});` 앞에 추가:

```typescript
  describe('updateOrder — guards & edits', () => {
    it('en_cocina 에서 품목 교체 + totalAmount 재계산', async () => {
      const ctx = build();
      ctx.deliveryRow.status = DeliveryStatus.EN_COCINA;
      ctx.deliveryRow.tipo = DeliveryTipo.TAKEAWAY;

      await ctx.service.updateOrder(9, 1, 77, {
        items: [{ productId: 10, qty: 3, price: 1000 }],
      });

      expect(ctx.saleItemModel.destroy).toHaveBeenCalledWith({
        where: { saleId: 555 },
        transaction: { id: 'tx' },
      });
      expect(ctx.saleItemModel.bulkCreate).toHaveBeenCalled();
      expect(ctx.sale.update).toHaveBeenCalledWith(
        { totalAmount: 3000 },
        { transaction: { id: 'tx' } },
      );
      expect(ctx.gateway.emitDeliveryUpdated).toHaveBeenCalled();
    });

    it('listo 에서 품목 편집은 차단(400)', async () => {
      const ctx = build();
      ctx.deliveryRow.status = DeliveryStatus.LISTO;

      await expect(
        ctx.service.updateOrder(9, 1, 77, {
          items: [{ productId: 10, qty: 1, price: 500 }],
        }),
      ).rejects.toThrow('No se pueden editar los productos en este estado');
    });

    it('listo 에서 메타 편집은 허용', async () => {
      const ctx = build();
      ctx.deliveryRow.status = DeliveryStatus.LISTO;
      ctx.deliveryRow.tipo = DeliveryTipo.TAKEAWAY;

      await ctx.service.updateOrder(9, 1, 77, { customerName: 'Nuevo' });

      expect(ctx.deliveryRow.update).toHaveBeenCalledWith(
        { customerName: 'Nuevo' },
        { transaction: { id: 'tx' } },
      );
    });

    it('en_camino 에서 메타 편집은 차단(400)', async () => {
      const ctx = build();
      ctx.deliveryRow.status = DeliveryStatus.EN_CAMINO;

      await expect(
        ctx.service.updateOrder(9, 1, 77, { customerName: 'X' }),
      ).rejects.toThrow('No se pueden editar los datos del pedido en este estado');
    });

    it('delivery 인데 주소를 비우면 차단(400)', async () => {
      const ctx = build();
      ctx.deliveryRow.status = DeliveryStatus.EN_COCINA;
      ctx.deliveryRow.tipo = DeliveryTipo.DELIVERY;
      ctx.deliveryRow.address = 'Calle 1';

      await expect(
        ctx.service.updateOrder(9, 1, 77, { address: '' }),
      ).rejects.toThrow('La dirección es obligatoria');
    });

    it('QR 결제완료(approved) 주문은 편집 차단(400)', async () => {
      const ctx = build();
      ctx.deliveryRow.status = DeliveryStatus.EN_COCINA;
      ctx.mpQrService.findActiveIntentByVenta.mockResolvedValueOnce({ id: 5, status: 'approved' });

      await expect(
        ctx.service.updateOrder(9, 1, 77, { customerName: 'X' }),
      ).rejects.toThrow('ya fue pagado con QR');
    });

    it('품목 변경 & en_cocina 면 MODIFICADO 코만다 재출력', async () => {
      const ctx = build();
      ctx.deliveryRow.status = DeliveryStatus.EN_COCINA;
      ctx.deliveryRow.tipo = DeliveryTipo.TAKEAWAY;

      await ctx.service.updateOrder(9, 1, 77, {
        items: [{ productId: 10, qty: 1, price: 800 }],
      });

      expect(ctx.printService.emitPrintTemp).toHaveBeenCalledWith(
        3,
        expect.objectContaining({ kind: 'comanda', delivery: true, modified: true }),
      );
    });
  });
```

- [ ] **Step 3: 테스트 실패 확인**

Run: `cd api-ventago && npx jest restaurant-delivery.service.spec --silent 2>&1 | tail -20`
Expected: FAIL — `service.updateOrder is not a function`

- [ ] **Step 4: 편집 상태 상수 + `updateOrder` 구현 (QR 재조정 제외)**

`restaurant-delivery.service.ts` 클래스 내부, `TransitionOpts` 인터페이스 import 아래 — 클래스 상단 `private readonly logger` 다음 줄에 상수 추가:

```typescript
  // 편집 창(D-edit): 품목은 주방 완료(listo) 전까지, 메타는 배차(en_camino) 전까지.
  private readonly ITEM_EDIT_STATES: DeliveryStatus[] = [
    DeliveryStatus.NUEVO,
    DeliveryStatus.EN_COCINA,
  ];
  private readonly META_EDIT_STATES: DeliveryStatus[] = [
    DeliveryStatus.NUEVO,
    DeliveryStatus.EN_COCINA,
    DeliveryStatus.LISTO,
  ];
```

그리고 `cancel(...)` 메서드 **바로 위**에 `updateOrder` 추가:

```typescript
  // ── 주문 편집 (주문 편집 feature) ──
  // 단일 TX: 상태 가드 → 품목 교체(+total 재계산) → 메타 패치 → 코만다 재출력 → 카드 emit.
  // QR 인텐트 재조정은 TX 커밋 후(외부 HTTP) reconcileQrIntent 에서 수행.
  async updateOrder(
    storeId: number,
    userId: number,
    deliveryId: number,
    dto: {
      items?: { productId: number; qty: number; price: number; customName?: string }[];
      customerName?: string;
      customerPhone?: string;
      address?: string;
      paymentMode?: PaymentMode;
      canal?: DeliveryCanal;
      externalRef?: string;
      clientId?: number;
      terminalId?: number;
    },
  ): Promise<RestaurantDelivery> {
    const result = await this.sequelize.transaction(async (t) => {
      const d = await this.deliveryModel.findOne({
        where: { id: deliveryId, storeId },
        transaction: t,
      });
      if (!d) {
        throw new NotFoundException('Pedido no encontrado');
      }

      // QR 결제완료면 전면 차단(정합성 보호)
      const activeIntent = await this.mpQrService.findActiveIntentByVenta(d.saleId);
      if (activeIntent && activeIntent.status === 'approved') {
        throw new BadRequestException(
          'El pedido ya fue pagado con QR y no puede editarse',
        );
      }

      const editingItems = Array.isArray(dto.items);
      const editingMeta =
        dto.customerName !== undefined ||
        dto.customerPhone !== undefined ||
        dto.address !== undefined ||
        dto.paymentMode !== undefined ||
        dto.canal !== undefined ||
        dto.externalRef !== undefined ||
        dto.clientId !== undefined;

      if (!editingItems && !editingMeta) {
        throw new BadRequestException('No hay cambios para guardar');
      }
      if (editingItems && !this.ITEM_EDIT_STATES.includes(d.status)) {
        throw new BadRequestException(
          'No se pueden editar los productos en este estado',
        );
      }
      if (editingMeta && !this.META_EDIT_STATES.includes(d.status)) {
        throw new BadRequestException(
          'No se pueden editar los datos del pedido en este estado',
        );
      }

      const sale = await this.saleModel.findOne({
        where: { id: d.saleId },
        transaction: t,
      });
      if (!sale) {
        throw new NotFoundException('Venta del pedido no encontrada');
      }

      const oldPaymentMode = d.paymentMode;
      let totalChanged = false;

      // 품목 전체 교체 + totalAmount 재계산(서버 진실 — 클라 total 무시)
      if (editingItems) {
        if (!dto.items || dto.items.length === 0) {
          throw new BadRequestException('El pedido no tiene items');
        }
        await this.saleItemModel.destroy({
          where: { saleId: sale.id },
          transaction: t,
        });
        await this.saleItemModel.bulkCreate(
          dto.items.map((i) => ({
            saleId: sale.id,
            productId: i.productId,
            quantity: i.qty,
            price: i.price,
            subtotal: i.price * i.qty,
            customName: i.customName ?? null,
          })) as any,
          { transaction: t },
        );
        const newTotal = dto.items.reduce((acc, i) => acc + i.price * i.qty, 0);
        totalChanged = Number(sale.totalAmount) !== newTotal;
        await sale.update({ totalAmount: newTotal }, { transaction: t });
      }

      // 메타 패치 — 허용 필드만. 빈 문자열은 null 로 정규화.
      const patch: Record<string, any> = {};
      if (dto.customerName !== undefined) patch.customerName = dto.customerName || null;
      if (dto.customerPhone !== undefined) patch.customerPhone = dto.customerPhone || null;
      if (dto.address !== undefined) patch.address = dto.address || null;
      if (dto.paymentMode !== undefined) patch.paymentMode = dto.paymentMode;
      if (dto.canal !== undefined) patch.canal = dto.canal;
      if (dto.externalRef !== undefined) patch.externalRef = dto.externalRef || null;
      if (dto.clientId !== undefined) patch.clientId = dto.clientId ?? null;

      // delivery 면 주소 필수(편집으로 비울 수 없음)
      const resultAddress =
        patch.address !== undefined ? patch.address : d.address;
      if (d.tipo === DeliveryTipo.DELIVERY && !resultAddress) {
        throw new BadRequestException(
          'La dirección es obligatoria para envíos a domicilio',
        );
      }

      if (Object.keys(patch).length > 0) {
        await d.update(patch, { transaction: t });
      }

      // 품목 변경 & en_cocina(주방 보유) → MODIFICADO 코만다 재출력
      if (editingItems && d.status === DeliveryStatus.EN_COCINA) {
        this.printService.emitPrintTemp(d.branchId, {
          kind: 'comanda',
          delivery: true,
          modified: true,
          saleId: sale.id,
          customerName: d.customerName,
          address: d.address,
          items: (dto.items || []).map((i) => ({
            productId: i.productId,
            name: i.customName ?? null,
            qty: i.qty,
          })),
        });
      }

      // 보드 푸시 — 갱신된 total 포함 카드
      this.deliveryGateway.emitDeliveryUpdated(d.branchId, this.toCard(d, sale));

      return {
        delivery: d,
        sale,
        totalChanged,
        oldPaymentMode,
        newPaymentMode: d.paymentMode,
      };
    });

    // QR 인텐트 재조정 (TX 커밋 후 외부 HTTP — Task 5 에서 구현)
    await this.reconcileQrIntent(storeId, userId, result.delivery, result.sale, {
      totalChanged: result.totalChanged,
      oldPaymentMode: result.oldPaymentMode,
      newPaymentMode: result.newPaymentMode,
      terminalId: dto.terminalId,
    });

    return result.delivery;
  }
```

- [ ] **Step 5: 임시 `reconcileQrIntent` 스텁 추가 (Task 5 에서 본구현)**

`updateOrder` 바로 아래에 임시 no-op 스텁을 추가해 컴파일/테스트가 통과하도록 한다(Task 5 가 본구현으로 교체):

```typescript
  // QR 인텐트 재조정 — Task 5 에서 본구현. (스텁: 아무 동작 안 함)
  private async reconcileQrIntent(
    _storeId: number,
    _userId: number,
    _d: RestaurantDelivery,
    _sale: Sale,
    _ctx: {
      totalChanged: boolean;
      oldPaymentMode: PaymentMode;
      newPaymentMode: PaymentMode;
      terminalId?: number;
    },
  ): Promise<void> {
    return undefined;
  }
```

- [ ] **Step 6: `DeliveryCanal` import 확인 및 추가**

`updateOrder` 시그니처가 `DeliveryCanal`을 참조한다. `restaurant-delivery.service.ts` 상단 import 블록을 확인:

Run: `cd api-ventago && grep -n "DeliveryCanal" src/app/restaurant-delivery/restaurant-delivery.service.ts | head`

`import { DeliveryStatus, DeliveryTipo, PaymentMode, RestaurantDelivery }` 에 `DeliveryCanal`이 없으면 추가:

```typescript
import {
  DeliveryCanal,
  DeliveryStatus,
  DeliveryTipo,
  PaymentMode,
  RestaurantDelivery,
} from './restaurant-delivery.model';
```

- [ ] **Step 7: 테스트 통과 확인**

Run: `cd api-ventago && npx jest restaurant-delivery.service.spec --silent 2>&1 | tail -25`
Expected: PASS — updateOrder describe 7건 + 기존 테스트 모두 green

- [ ] **Step 8: Commit**

```bash
git -C api-ventago add src/app/restaurant-delivery/restaurant-delivery.service.ts src/app/restaurant-delivery/restaurant-delivery.service.spec.ts
git -C api-ventago commit -m "feat(40-edit): updateOrder with status guards + item/meta edit"
```

---

## Task 5: `reconcileQrIntent()` 본구현 — QR 인텐트 재조정 (TDD)

**Files:**
- Modify: `api-ventago/src/app/restaurant-delivery/restaurant-delivery.service.ts`
- Test: `api-ventago/src/app/restaurant-delivery/restaurant-delivery.service.spec.ts`

규칙: `cancel` = 활성 pending 인텐트 존재 AND (QR 이탈 OR 총액 변동). `create` = 결과 QR AND (타수단→QR OR 총액 변동). create 시 `terminalId` 없으면 400.

- [ ] **Step 1: 실패 테스트 작성**

`restaurant-delivery.service.spec.ts` 닫는 `});` 앞에 추가:

```typescript
  describe('updateOrder — QR intent reconciliation', () => {
    it('QR 유지 + 총액 변동 → 미결제 인텐트 cancel + recreate', async () => {
      const ctx = build();
      ctx.deliveryRow.status = DeliveryStatus.EN_COCINA;
      ctx.deliveryRow.tipo = DeliveryTipo.TAKEAWAY;
      ctx.deliveryRow.paymentMode = PaymentMode.QR;
      ctx.sale.totalAmount = 1000; // 기존 total
      ctx.mpQrService.findActiveIntentByVenta
        .mockResolvedValueOnce(null) // updateOrder 내 approved 가드용 (TX 안)
        .mockResolvedValueOnce({ id: 5, status: 'pending' }); // reconcile 용

      await ctx.service.updateOrder(9, 1, 77, {
        items: [{ productId: 10, qty: 2, price: 2000 }], // 새 total 4000
        terminalId: 12,
      });

      expect(ctx.mpQrService.cancelIntent).toHaveBeenCalledWith(5, 1);
      expect(ctx.mpQrService.createIntent).toHaveBeenCalledWith(
        expect.objectContaining({ pendingVentaId: 555, terminalId: 12, amount: 4000 }),
      );
    });

    it('QR → efectivo 전환 → 미결제 인텐트 cancel 만(생성 없음)', async () => {
      const ctx = build();
      ctx.deliveryRow.status = DeliveryStatus.EN_COCINA;
      ctx.deliveryRow.tipo = DeliveryTipo.TAKEAWAY;
      ctx.deliveryRow.paymentMode = PaymentMode.QR;
      ctx.mpQrService.findActiveIntentByVenta
        .mockResolvedValueOnce(null)
        .mockResolvedValueOnce({ id: 5, status: 'pending' });

      await ctx.service.updateOrder(9, 1, 77, { paymentMode: PaymentMode.EFECTIVO });

      expect(ctx.mpQrService.cancelIntent).toHaveBeenCalledWith(5, 1);
      expect(ctx.mpQrService.createIntent).not.toHaveBeenCalled();
    });

    it('efectivo → QR 전환 → 인텐트 생성(terminalId 필요)', async () => {
      const ctx = build();
      ctx.deliveryRow.status = DeliveryStatus.EN_COCINA;
      ctx.deliveryRow.tipo = DeliveryTipo.TAKEAWAY;
      ctx.deliveryRow.paymentMode = PaymentMode.EFECTIVO;

      await ctx.service.updateOrder(9, 1, 77, {
        paymentMode: PaymentMode.QR,
        terminalId: 12,
      });

      expect(ctx.mpQrService.createIntent).toHaveBeenCalledWith(
        expect.objectContaining({ pendingVentaId: 555, terminalId: 12 }),
      );
    });

    it('QR 생성 필요한데 terminalId 없으면 400', async () => {
      const ctx = build();
      ctx.deliveryRow.status = DeliveryStatus.EN_COCINA;
      ctx.deliveryRow.tipo = DeliveryTipo.TAKEAWAY;
      ctx.deliveryRow.paymentMode = PaymentMode.EFECTIVO;

      await expect(
        ctx.service.updateOrder(9, 1, 77, { paymentMode: PaymentMode.QR }),
      ).rejects.toThrow('Seleccioná una terminal');
    });

    it('QR 무관(efectivo 유지) → 인텐트 호출 없음', async () => {
      const ctx = build();
      ctx.deliveryRow.status = DeliveryStatus.EN_COCINA;
      ctx.deliveryRow.tipo = DeliveryTipo.TAKEAWAY;
      ctx.deliveryRow.paymentMode = PaymentMode.EFECTIVO;

      await ctx.service.updateOrder(9, 1, 77, { customerName: 'Ana' });

      expect(ctx.mpQrService.cancelIntent).not.toHaveBeenCalled();
      expect(ctx.mpQrService.createIntent).not.toHaveBeenCalled();
    });
  });
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd api-ventago && npx jest restaurant-delivery.service.spec --silent 2>&1 | tail -25`
Expected: FAIL — 스텁이 no-op 이라 cancelIntent/createIntent 미호출

- [ ] **Step 3: `reconcileQrIntent` 본구현으로 교체**

Task 4 에서 추가한 스텁 `reconcileQrIntent` 전체를 다음으로 교체:

```typescript
  // ── QR 인텐트 재조정 (주문 편집) ──
  // cancel: 활성 pending 인텐트 존재 AND (QR 이탈 OR 총액 변동).
  // create: 결과 QR AND (타수단→QR OR 총액 변동). terminalId 부재 시 400.
  // 외부 MP HTTP 호출이므로 TX 밖에서 수행(createOrder 패턴 동일).
  private async reconcileQrIntent(
    storeId: number,
    userId: number,
    d: RestaurantDelivery,
    sale: Sale,
    ctx: {
      totalChanged: boolean;
      oldPaymentMode: PaymentMode;
      newPaymentMode: PaymentMode;
      terminalId?: number;
    },
  ): Promise<void> {
    const wasQr = ctx.oldPaymentMode === PaymentMode.QR;
    const isQr = ctx.newPaymentMode === PaymentMode.QR;
    if (!wasQr && !isQr) {
      return;
    }

    const needCreate = isQr && (!wasQr || ctx.totalChanged);

    // create 가 필요한데 terminal 이 없으면 아무 것도 하기 전에 차단
    if (needCreate && !ctx.terminalId) {
      throw new BadRequestException(
        'Seleccioná una terminal para el cobro con QR',
      );
    }

    // 기존 미결제 인텐트 정리 — QR 이탈 또는 총액 변동 시
    if (!isQr || ctx.totalChanged) {
      const active = await this.mpQrService.findActiveIntentByVenta(sale.id);
      if (active && active.status === 'pending') {
        await this.mpQrService.cancelIntent(active.id, userId);
      }
    }

    // 새 인텐트 생성 — 새 총액으로
    if (needCreate) {
      await this.mpQrService.createIntent({
        storeId,
        branchId: d.branchId,
        terminalId: ctx.terminalId as number,
        amount: Number(sale.totalAmount),
        pendingVentaId: sale.id,
      } as any);
    }
  }
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd api-ventago && npx jest restaurant-delivery.service.spec --silent 2>&1 | tail -25`
Expected: PASS — QR reconciliation describe 5건 + 전체 green

- [ ] **Step 5: Commit**

```bash
git -C api-ventago add src/app/restaurant-delivery/restaurant-delivery.service.ts src/app/restaurant-delivery/restaurant-delivery.service.spec.ts
git -C api-ventago commit -m "feat(40-edit): reconcileQrIntent cancel+recreate on edit"
```

---

## Task 6: 컨트롤러 라우트 — `GET /:id` + `PATCH /:id`

**Files:**
- Modify: `api-ventago/src/app/restaurant-delivery/restaurant-delivery.controller.ts`

라우트 순서 주의: 구체 경로(`order`, `board/:branchId`, `payout/reconcile`)는 이미 위에 있다. `:id` 동적 경로는 `cancel`(`@Post(':id/cancel')`)·`transition`(`@Patch(':id/transition')`) 같은 더 구체적인 `:id/...` 경로 **아래**에 두어야 충돌이 없다 → 파일 맨 끝(`reconcilePayout` 뒤, 클래스 닫기 `}` 앞)에 추가.

- [ ] **Step 1: DTO import 추가**

`restaurant-delivery.controller.ts` 상단 import 의 `{ CreateDeliveryOrderDto, TransitionDto }` 를 다음으로 교체:

```typescript
import {
  CreateDeliveryOrderDto,
  TransitionDto,
  UpdateDeliveryOrderDto,
} from './dto/restaurant-delivery.dto';
```

- [ ] **Step 2: 두 라우트 추가**

`reconcilePayout(...)` 메서드 **바로 아래**, 클래스 닫는 `}` 앞에 추가:

```typescript

  // 편집 프리필 상세 — items 포함. storeId 스코프(IDOR). :id/* 구체 경로 뒤에 선언.
  @Get(':id')
  @Auth()
  async detail(@Param('id') id: string, @GetUser() user: any) {
    return this.service.getOrderDetail(user.storeId, +id);
  }

  // 주문 편집 — 품목(en_cocina 까지)/메타(en_camino 전까지). 상태 가드는 서비스에서 강제.
  @Patch(':id')
  @Auth()
  async update(
    @Param('id') id: string,
    @Body() dto: UpdateDeliveryOrderDto,
    @GetUser() user: any,
  ) {
    return this.service.updateOrder(user.storeId, user.id, +id, dto);
  }
```

- [ ] **Step 3: 컴파일 + 전체 테스트 확인**

Run: `cd api-ventago && npx tsc --noEmit -p tsconfig.json 2>&1 | grep -iE "restaurant-delivery" || echo "OK"; npx jest restaurant-delivery --silent 2>&1 | tail -5`
Expected: `OK` + 테스트 PASS

- [ ] **Step 4: Commit**

```bash
git -C api-ventago add src/app/restaurant-delivery/restaurant-delivery.controller.ts
git -C api-ventago commit -m "feat(40-edit): GET/:id detail + PATCH/:id edit routes"
```

---

## Task 7: print-agent — `MODIFICADO` 배너

**Files:**
- Modify: `print-agent/src/formatter.js`

`formatTempTicketHtml(data)`(line ~666)의 본문에서 최상단 배너(`data.ticketType === 'invoiced' ? ... : ...`) 출력 직후에 `data.modified` 배너를 추가한다.

- [ ] **Step 1: MODIFICADO 배너 삽입**

`formatter.js`의 `formatTempTicketHtml` 내, 배너 분기 블록을 찾는다:

```javascript
${data.ticketType === 'invoiced'
    ? '<div class="banner">COMPROBANTE DE VENTA — NO VÁLIDO COMO FACTURA</div>'
    : '<div class="banner">PRESUPUESTO TEMPORAL</div>'}
```

이 블록 **바로 아래**에 추가:

```javascript
${data.modified
    ? '<div style="text-align:center; margin:6px 12px; padding:6px; border:3px solid #c62828; color:#c62828; font-size:22px; font-weight:bold; letter-spacing:2px;">*** MODIFICADO ***</div>'
    : ''}
```

- [ ] **Step 2: 구문 확인**

Run: `cd print-agent && node -e "require('./src/formatter.js'); console.log('formatter OK')"`
Expected: `formatter OK` (구문 에러 없음)

- [ ] **Step 3: Commit**

```bash
git -C print-agent add src/formatter.js
git -C print-agent commit -m "feat(40-edit): MODIFICADO banner on edited comanda"
```

---

## Task 8: 프론트 — `NuevoPedidoModal` 편집 모드

**Files:**
- Modify: `ventago-app/src/views/restaurante/components/NuevoPedidoModal.tsx`

편집 모드: `editCard` prop 제공 시 `GET /restaurant-delivery/:id`로 상세를 불러와 cart·메타 프리필, tipo 고정, 제목/버튼 변경, 저장 시 `PATCH`. 상태 기반 enable/disable.

- [ ] **Step 1: props 인터페이스 확장**

`NuevoPedidoModalProps` 인터페이스를 다음으로 교체:

```typescript
interface NuevoPedidoModalProps {
  open: boolean
  branchId?: number
  editCard?: { id: number; status: string } | null
  onClose: () => void
  onCreated: () => void
}
```

함수 시그니처도 교체:

```typescript
const NuevoPedidoModal = ({ open, branchId, editCard, onClose, onCreated }: NuevoPedidoModalProps) => {
```

- [ ] **Step 2: 편집 모드 파생 상태 + 편집 창 계산 추가**

`const isDelivery = tipo === 'delivery'` 줄 **위**에 추가:

```typescript
  // 편집 모드 — editCard 존재 시. 상태 기반 편집 창 계산.
  const isEditMode = !!editCard
  const editStatus = editCard?.status ?? ''
  const canEditItems = !isEditMode || ['nuevo', 'en_cocina'].includes(editStatus)
  const canEditMeta = !isEditMode || ['nuevo', 'en_cocina', 'listo'].includes(editStatus)
```

- [ ] **Step 3: 편집 프리필 로드 effect 추가**

메뉴 로드 `useEffect` **아래**에 편집 상세 프리필 effect 추가:

```typescript
  // 편집 모드 — 상세 로드 후 cart/메타 프리필. open & editCard 변할 때만.
  useEffect(() => {
    if (!open || !editCard) return undefined
    let cancelled = false

    const fetchDetail = async () => {
      try {
        const res: any = await apiConnector.get(`/restaurant-delivery/${editCard.id}`)
        if (cancelled || !res) return
        setTipo((res.tipo as Tipo) ?? 'delivery')
        setCanal((res.canal as Canal) ?? 'whatsapp')
        setPaymentMode((res.paymentMode as PaymentMode) ?? 'efectivo')
        setCustomerName(res.customerName ?? '')
        setCustomerPhone(res.customerPhone ?? '')
        setAddress(res.address ?? '')
        setClientId(res.clientId ?? null)
        setExternalRef(res.externalRef ?? '')
        setCart(
          (res.items ?? []).map((i: any) => ({
            productId: i.productId,
            name: i.name,
            price: Number(i.price) || 0,
            qty: Number(i.qty) || 0,
          })),
        )
      } catch (err: any) {
        if (cancelled) return
        const msg = err?.response?.data?.message || err?.message || 'Error al cargar el pedido'
        setSubmitError(msg)
        toast.error(`No se pudo cargar el pedido: ${msg}`)
      }
    }

    fetchDetail()

    return () => {
      cancelled = true
    }
  }, [open, editCard])
```

- [ ] **Step 4: `handleSubmit` 을 생성/편집 분기로 교체**

`handleSubmit` 의 제출 블록(`setSubmitting(true)` 부터 `finally` 까지)을 다음으로 교체. 기존 payload 빌드(검증·payload 구성)는 그대로 두고, 마지막 try 블록만 분기:

```typescript
    setSubmitting(true)
    setSubmitError(null)
    try {
      if (isEditMode && editCard) {
        // 편집 — terminalId 는 QR 인텐트 재생성 대비 항상 동봉(서버가 필요 시 사용)
        const editPayload: Record<string, any> = {
          customerName: customerName.trim() || undefined,
          customerPhone: customerPhone.trim() || undefined,
          paymentMode,
          canal,
          externalRef: externalRef.trim() || undefined,
          clientId: clientId ?? undefined,
        }
        if (tipo === 'delivery') editPayload.address = address.trim()
        if (canEditItems) {
          editPayload.items = cart.map((l) => ({ productId: l.productId, price: l.price, qty: l.qty }))
        }
        if (paymentMode === 'qr' && terminalId) editPayload.terminalId = terminalId

        await apiConnector.patch(`/restaurant-delivery/${editCard.id}`, editPayload)
        toast.success('Pedido actualizado')
      } else {
        await apiConnector.post('/restaurant-delivery/order', payload)
        toast.success('Pedido enviado a cocina')
      }
      resetForm()
      onCreated()
    } catch (err: any) {
      const msg = err?.response?.data?.message || err?.message || '주문 저장 오류'
      setSubmitError(msg)
      toast.error(`No se pudo guardar el pedido: ${msg}`)
    } finally {
      setSubmitting(false)
    }
```

`terminalId` 상수는 기존 `handleSubmit` 안에서 이미 선언되어 있다(`const terminalId: number | null = (user as any)?.terminalId ?? null`). 편집 분기에서 사용하므로, 이 선언이 QR 검증 블록보다 위(payload 빌드 전)에 있는지 확인하고, 아니면 함수 상단으로 이동한다.

- [ ] **Step 5: tipo 토글 비활성화 + 제목/버튼 라벨 분기**

`ToggleButtonGroup` 에 `disabled={isEditMode}` 추가:

```typescript
        <ToggleButtonGroup
          exclusive
          size='small'
          value={tipo}
          onChange={(_e, v) => v && setTipo(v as Tipo)}
          disabled={isEditMode}
          sx={{ mb: 2, mt: 1 }}
        >
```

`DialogTitle` 교체:

```typescript
      <DialogTitle sx={{ fontWeight: 700 }}>{isEditMode ? 'Editar pedido' : 'Nuevo pedido'}</DialogTitle>
```

저장 버튼 라벨 교체 (`Enviar a cocina` 텍스트):

```typescript
          {isEditMode ? 'Guardar cambios' : 'Enviar a cocina'}
```

- [ ] **Step 6: 품목 섹션 비활성화 (편집 창 종료 시)**

메뉴 그리드 상품 클릭과 수량 조절을 `canEditItems` 로 가드한다.

상품 카드 `onClick` 교체:

```typescript
                onClick={() => canEditItems && addToCart(p)}
```

상품 카드 `sx` 의 `cursor` 와 hover 를 조건부로:

```typescript
                sx={{
                  p: 1,
                  backgroundColor: '#f4f4f8',
                  border: '1px solid rgba(0,0,0,0.10)',
                  borderRadius: 1,
                  cursor: canEditItems ? 'pointer' : 'not-allowed',
                  opacity: canEditItems ? 1 : 0.5,
                  '&:hover': { borderColor: canEditItems ? '#f5a623' : 'rgba(0,0,0,0.10)' },
                }}
```

코만다 수량 IconButton 두 곳에 `disabled={!canEditItems}` 추가:

```typescript
                  <IconButton size='small' disabled={!canEditItems} onClick={() => changeQty(l.productId, -1)} sx={{ color: '#1f1f33' }}>
                    <Icon icon='mdi:minus' width={14} />
                  </IconButton>
```

```typescript
                  <IconButton size='small' disabled={!canEditItems} onClick={() => changeQty(l.productId, 1)} sx={{ color: '#1f1f33' }}>
                    <Icon icon='mdi:plus' width={14} />
                  </IconButton>
```

- [ ] **Step 7: 메타 필드 비활성화 (편집 창 종료 시)**

고객/주소/Cobro/canal 입력에 `disabled={!canEditMeta}` 추가. 해당 컴포넌트들:
- Teléfono `TextField` → `disabled={!canEditMeta}`
- Nombre del cliente `TextField` → `disabled={!canEditMeta}`
- Dirección de entrega `TextField` → `disabled={!canEditMeta}`
- Cobro `select TextField` → `disabled={!canEditMeta}`
- N.º de pedido (app) `TextField` → `disabled={!canEditMeta}`
- canal `Chip` 들 → `disabled={!canEditMeta}` (MUI Chip 은 `disabled` 지원)

예 (Teléfono):

```typescript
          <TextField
            size='small'
            label='Teléfono'
            value={customerPhone}
            onChange={(e) => setCustomerPhone(e.target.value)}
            onBlur={handleLookupClient}
            disabled={!canEditMeta}
            sx={{ flex: 1 }}
          />
```

canal Chip 예:

```typescript
              <Chip
                key={c}
                label={c}
                clickable
                disabled={!canEditMeta}
                color={canal === c ? 'primary' : 'default'}
                onClick={() => canEditMeta && setCanal(c)}
                sx={{ textTransform: 'capitalize' }}
              />
```

- [ ] **Step 8: 저장 버튼 disabled 조건 보정**

편집 모드에서 품목 편집 불가 상태(listo)면 cart 가 비어있지 않아도 메타만 저장 가능해야 한다. 저장 버튼 `disabled` 교체:

```typescript
          disabled={submitting || (canEditItems && cart.length === 0)}
```

- [ ] **Step 9: ESLint 점검**

Run: `cd ventago-app && npx eslint src/views/restaurante/components/NuevoPedidoModal.tsx`
Expected: exit 0 (위반 0). 위반 시 `newline-before-return`/`lines-around-comment` 우선 수정.

- [ ] **Step 10: Commit**

```bash
git -C ventago-app add src/views/restaurante/components/NuevoPedidoModal.tsx
git -C ventago-app commit -m "feat(40-edit): NuevoPedidoModal edit mode (prefill + PATCH)"
```

---

## Task 9: 프론트 — `DeliveryCardItem` Editar 버튼 + `DeliveryBoard` 모달 공용

**Files:**
- Modify: `ventago-app/src/views/restaurante/DeliveryBoard.tsx`

- [ ] **Step 1: 편집 창 상수 + `DeliveryBoard` 에 editCard state 추가**

`COLUMNS` 정의 아래(컴포넌트 밖)에 상수 추가:

```typescript
// 편집 진입 가능 상태 — 품목/메타 중 하나라도 편집 가능하면 Editar 노출(nuevo/en_cocina/listo)
const EDITABLE_STATES = ['nuevo', 'en_cocina', 'listo']
```

`DeliveryBoard` 컴포넌트 내 `const [modalOpen, setModalOpen] = useState(false)` 아래에 추가:

```typescript
  const [editCard, setEditCard] = useState<DeliveryCard | null>(null)

  // 편집 모달 오픈 — 카드 클릭(연필). 생성 모달과 단일 인스턴스 공용.
  const openEdit = useCallback((card: DeliveryCard) => {
    setEditCard(card)
    setModalOpen(true)
  }, [])
```

- [ ] **Step 2: "Nuevo pedido" 버튼/빈공간이 생성 모드로 열도록 보정**

`onClick={() => setModalOpen(true)}`(헤더 버튼)과 `onAddOrder={col.key === 'nuevo' ? () => setModalOpen(true) : undefined}`(컬럼) 를 각각 `editCard` 초기화 포함으로 교체:

헤더 버튼:

```typescript
          onClick={() => { setEditCard(null); setModalOpen(true) }}
```

컬럼 prop:

```typescript
              onAddOrder={col.key === 'nuevo' ? () => { setEditCard(null); setModalOpen(true) } : undefined}
```

- [ ] **Step 3: `onEdit` 를 컬럼/카드까지 전달**

`BoardColumn` 호출에 `onEdit={openEdit}` 추가:

```typescript
            <BoardColumn
              key={col.key}
              column={col}
              cards={cardsByStatus.get(col.key) ?? []}
              nowMs={nowMs}
              formatPrice={formatPrice}
              riderName={riderName}
              onAdvance={handleTransition}
              onAssign={openAssign}
              onEdit={openEdit}
              onAddOrder={col.key === 'nuevo' ? () => { setEditCard(null); setModalOpen(true) } : undefined}
            />
```

- [ ] **Step 4: 모달 렌더에 editCard 전달 + 닫기 시 초기화**

`NuevoPedidoModal` 렌더 블록 교체:

```typescript
      {modalOpen && (
        <NuevoPedidoModal
          open
          branchId={branchId}
          editCard={editCard ? { id: editCard.id, status: editCard.status } : null}
          onClose={() => { setModalOpen(false); setEditCard(null) }}
          onCreated={() => {
            mutate()
            setModalOpen(false)
            setEditCard(null)
          }}
        />
      )}
```

- [ ] **Step 5: `BoardColumn` 에 onEdit prop 전달**

`BoardColumn` 의 props 타입과 구조분해에 `onEdit` 추가:

```typescript
const BoardColumn = ({
  column,
  cards,
  nowMs,
  formatPrice,
  riderName,
  onAdvance,
  onAssign,
  onEdit,
  onAddOrder,
}: {
  column: ColumnDef
  cards: DeliveryCard[]
  nowMs: number
  formatPrice: (n: number) => string
  riderName: Map<number, string>
  onAdvance: (card: DeliveryCard, toStatus: string) => void
  onAssign: (e: React.MouseEvent<HTMLElement>, card: DeliveryCard) => void
  onEdit: (card: DeliveryCard) => void
  onAddOrder?: () => void
}) => {
```

`DeliveryCardItem` 렌더에 `onEdit={onEdit}` 전달:

```typescript
          <DeliveryCardItem
            key={card.id}
            card={card}
            nowMs={nowMs}
            formatPrice={formatPrice}
            riderName={riderName}
            onAdvance={onAdvance}
            onAssign={onAssign}
            onEdit={onEdit}
          />
```

- [ ] **Step 6: `DeliveryCardItem` 에 Editar 버튼 추가**

`DeliveryCardItem` props 타입/구조분해에 `onEdit` 추가:

```typescript
const DeliveryCardItem = ({
  card,
  nowMs,
  formatPrice,
  riderName,
  onAdvance,
  onAssign,
  onEdit,
}: {
  card: DeliveryCard
  nowMs: number
  formatPrice: (n: number) => string
  riderName: Map<number, string>
  onAdvance: (card: DeliveryCard, toStatus: string) => void
  onAssign: (e: React.MouseEvent<HTMLElement>, card: DeliveryCard) => void
  onEdit: (card: DeliveryCard) => void
}) => {
```

액션 `Box`(`{/* 액션 — Listo: Asignar ... */}`) 안, `next &&` 버튼 **앞**에 Editar 버튼 추가. 편집 창 상태일 때만 노출:

```typescript
        {EDITABLE_STATES.includes(card.status) && (
          <Button
            size="small"
            variant="outlined"
            startIcon={<Icon icon="mdi:pencil" />}
            onClick={() => onEdit(card)}
            sx={{ color: '#9a9ab0', borderColor: 'rgba(255,255,255,0.2)', fontSize: 11 }}
          >
            Editar
          </Button>
        )}
```

- [ ] **Step 7: ESLint 점검**

Run: `cd ventago-app && npx eslint src/views/restaurante/DeliveryBoard.tsx`
Expected: exit 0

- [ ] **Step 8: Commit**

```bash
git -C ventago-app add src/views/restaurante/DeliveryBoard.tsx
git -C ventago-app commit -m "feat(40-edit): Editar button on delivery card + shared modal"
```

---

## Task 10: 통합 검증 (빌드 + lint + 브라우저 UAT)

**Files:** 없음(검증 전용)

- [ ] **Step 1: 백엔드 전체 테스트**

Run: `cd api-ventago && npx jest restaurant-delivery --silent 2>&1 | tail -8`
Expected: 모든 suite PASS

- [ ] **Step 2: 백엔드 타입체크**

Run: `cd api-ventago && npx tsc --noEmit -p tsconfig.json 2>&1 | grep -iE "restaurant-delivery|mp-qr" || echo "OK"`
Expected: `OK`

- [ ] **Step 3: 프론트 ESLint (eslint-guardian 에이전트)**

eslint-guardian 서브에이전트로 `NuevoPedidoModal.tsx` + `DeliveryBoard.tsx` 위반 점검. 위반 시 수정.

- [ ] **Step 4: 프론트 빌드 스모크**

Run: `cd ventago-app && npx tsc --noEmit 2>&1 | grep -iE "restaurante/(DeliveryBoard|components/NuevoPedidoModal)" || echo "OK"`
Expected: `OK`

- [ ] **Step 5: 브라우저 UAT (preview)**

dev 서버 기동 후 보드에서:
1. En cocina 카드 → **Editar** → 품목 추가/삭제 + 수량 변경 → Guardar → 보드 total 갱신 확인.
2. Listo 카드 → Editar → 품목 섹션 비활성 + 고객명/주소 수정 가능 확인.
3. En camino 카드 → Editar 버튼 미노출 확인.
4. (가능 시) efectivo→QR 전환 저장 → QR 인텐트 생성 흐름 확인.

검증 결과를 스크린샷/콘솔로 공유.

- [ ] **Step 6: 최종 상태 커밋(루트 서브모듈 포인터)**

```bash
git add api-ventago ventago-app print-agent
git commit -m "feat(40-edit): delivery order edit — backend + modal + comanda + board"
```

---

## Self-Review 결과

- **Spec coverage:** §3 편집 창(Task 4 상수/가드), §4.1 엔드포인트(Task 6), §4.2 updateOrder(Task 4)/QR 재조정(Task 5)/코만다(Task 4 emit + Task 7 템플릿), §4.3 에러(BadRequest 메시지 전반), §5 프론트(Task 8/9), §6 테스트(Task 3/4/5) — 전 항목 매핑됨.
- **Type consistency:** `findActiveIntentByVenta`(Task 2)→Task 4/5 사용, `reconcileQrIntent` 시그니처 Task 4 스텁=Task 5 본구현 동일, `updateOrder` dto 형태=컨트롤러 `UpdateDeliveryOrderDto`(Task 1) 필드와 일치, `editCard:{id,status}` 형태 Task 8/9 일치.
- **Placeholder scan:** 모든 코드 스텝에 실제 코드 포함, TBD/TODO 없음.
- **주의(실행 중 확인):** `MpQrService` 의 인텐트 모델 주입 프로퍼티명이 `this.intentModel` 임을 Task 2 에서 재확인(다르면 grep 으로 실제명 사용). 운영 PG10 에서 `payment_methods` 테이블 raw query 는 기존 코드(`"PaymentMethods"`)와 케이스가 다를 수 있으나, 본 plan 의 신규 raw query 는 `sale_items`/`products`(snake, 확인됨)만 사용.
