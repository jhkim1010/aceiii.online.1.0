import { ForbiddenException } from '@nestjs/common';
import { SalesController } from './sales.controller';
import { SaleStatus } from './sales.model';

describe('SalesController', () => {
  let controller: SalesController;
  let salesService: any;
  let salesCreateService: any;

  const adminUser = { id: 1, storeId: 10, roles: ['admin'] } as any;
  const superadminUser = { id: 1, storeId: null, roles: ['superadmin'] } as any;
  const vendedorUser = { id: 5, storeId: 10, roles: ['vendedor'] } as any;

  beforeEach(() => {
    salesService = {
      findAll: jest.fn().mockResolvedValue([{ id: 1 }]),
      findOne: jest.fn(),
      findFilteredByStore: jest
        .fn()
        .mockResolvedValue({ count: 2, rows: [{ id: 1 }, { id: 2 }] }),
      findSalesByStore: jest
        .fn()
        .mockResolvedValue({ count: 1, rows: [{ storeId: 10, total: 50000 }] }),
      findSalesByStoreFiltered: jest
        .fn()
        .mockResolvedValue({ count: 1, rows: [{ id: 1 }] }),
      addPaymentMethods: jest
        .fn()
        .mockResolvedValue({ id: 1, status: SaleStatus.PAID }),
      update: jest.fn().mockResolvedValue({ id: 1, totalAmount: 5000 }),
      delete: jest.fn().mockResolvedValue(undefined),
    };
    salesCreateService = {
      create: jest.fn().mockResolvedValue({
        id: 10,
        totalAmount: 5000,
        status: SaleStatus.PAID,
      }),
      nullifySale: jest.fn().mockResolvedValue({
        id: 11,
        status: SaleStatus.NULLIFICATION,
        nullifiedSaleId: 10,
      }),
    };

    const salesModifyService: any = { modifySale: jest.fn() };

    controller = new SalesController(
      salesService,
      salesCreateService,
      salesModifyService,
    );
  });

  // ══════════════════════════════════════════
  // POST /sales — 판매 생성 (현금, MercadoPago)
  // ══════════════════════════════════════════

  describe('POST /sales — 판매 생성', () => {
    const baseSaleDto = {
      clientId: 5,
      status: 'Pagado',
      items: [
        {
          productId: 1,
          quantity: 2,
          price: 1500,
          subtotal: 3000,
          discountAmount: 0,
        },
      ],
      subtotal: 3000,
      discountAmount: 0,
      totalAmount: 3000,
    } as any;

    it('현금(efectivo) 판매 생성 — storeId/userId 자동 주입', async () => {
      const dto = {
        ...baseSaleDto,
        paymentMethods: [{ paymentMethodId: 1, amount: 3000 }], // efectivo
      };

      const result = await controller.create(dto, adminUser);

      expect(result.id).toBe(10);
      // Phase 64 W1 — 두 번째 인자는 멱등키 옵션. 헤더 미전송이면 undefined(현행 동작 유지).
      expect(salesCreateService.create).toHaveBeenCalledWith(
        expect.objectContaining({ storeId: 10, userId: 1 }),
        { idempotencyKey: undefined },
      );
    });

    it('MercadoPago 판매 생성', async () => {
      const dto = {
        ...baseSaleDto,
        paymentMethods: [{ paymentMethodId: 3, amount: 3000, optionId: 1 }], // mercadopago + option
      };

      const result = await controller.create(dto, vendedorUser);

      expect(result.id).toBe(10);
      expect(salesCreateService.create).toHaveBeenCalledWith(
        expect.objectContaining({ storeId: 10, userId: 5 }),
        { idempotencyKey: undefined },
      );
    });

    it('복합 결제 (현금 + MercadoPago)', async () => {
      const dto = {
        ...baseSaleDto,
        totalAmount: 5000,
        paymentMethods: [
          { paymentMethodId: 1, amount: 2000 }, // efectivo
          { paymentMethodId: 3, amount: 3000 }, // mercadopago
        ],
      };

      const result = await controller.create(dto, adminUser);

      expect(result.id).toBe(10);
      const calledDto = salesCreateService.create.mock.calls[0][0];
      expect(calledDto.paymentMethods).toHaveLength(2);
    });

    it('Borrador(초안) 상태로 생성 — Generar Venta 전 단계', async () => {
      const dto = {
        ...baseSaleDto,
        status: 'Borrador',
        paymentMethods: [],
        totalAmount: 0,
      };

      await controller.create(dto, vendedorUser);

      expect(salesCreateService.create).toHaveBeenCalledWith(
        expect.objectContaining({ status: 'Borrador' }),
        { idempotencyKey: undefined },
      );
    });

    it('결제 부족 시 Pendiente por pagar 상태', async () => {
      salesCreateService.create.mockResolvedValue({
        id: 10,
        totalAmount: 5000,
        status: SaleStatus.PENDING_PAYMENT,
      });

      const dto = {
        ...baseSaleDto,
        totalAmount: 5000,
        paymentMethods: [{ paymentMethodId: 1, amount: 2000 }], // 부족
      };

      const result = await controller.create(dto, adminUser);

      expect(result.status).toBe(SaleStatus.PENDING_PAYMENT);
    });
  });

  // ══════════════════════════════════════════
  // GET — 판매 조회
  // ══════════════════════════════════════════

  describe('GET /sales — 전체 조회', () => {
    it('모든 판매 반환', async () => {
      const result = await controller.findAll();

      expect(result).toEqual([{ id: 1 }]);
    });
  });

  describe('GET /sales/all — 페이지네이션 + 필터', () => {
    it('storeId 기반 필터링 + 페이지네이션', async () => {
      const result = await controller.findFiltered(
        adminUser,
        '0',
        '20',
        '2026-01-01',
        '2026-12-31',
        'Juan',
      );

      expect(result.count).toBe(2);
      expect(result.page).toBe(0);
      expect(result.pageSize).toBe(20);
      // [Phase 73-09] 필터 인자가 이후 phase 들에서 늘었다(Phase 35 activityType/branch/direction,
      // boxId 등). 전체 객체 비교는 필터가 추가될 때마다 깨지므로, 이 테스트가 지키려는 것
      // — 페이지·매장 스코프·전달된 필터 — 만 확인한다.
      expect(salesService.findFilteredByStore).toHaveBeenCalledWith(
        0,
        20,
        10,
        expect.objectContaining({
          startDate: '2026-01-01',
          endDate: '2026-12-31',
          clientName: 'Juan',
        }),
      );
    });

    it('필터 없이 호출 시 null 기본값', async () => {
      await controller.findFiltered(adminUser, '0', '10');

      expect(salesService.findFilteredByStore).toHaveBeenCalledWith(
        0,
        10,
        10,
        expect.objectContaining({
          startDate: null,
          endDate: null,
          clientName: null,
        }),
      );
    });
  });

  describe('GET /sales/by-store — 매장별 집계 (superadmin)', () => {
    it('매장별 판매 집계 반환', async () => {
      const result = await controller.findSalesByStore('0', '10', 'Naif');

      expect(result.count).toBe(1);
      expect(salesService.findSalesByStore).toHaveBeenCalled();
    });
  });

  describe('GET /sales/:id — 단일 판매 조회', () => {
    it('ID로 판매 조회', async () => {
      // [Phase 73-09] Phase 67 에서 @GetUser 인자가 추가됐는데 이 호출이 갱신되지 않아
      // spec 이 컴파일되지 않았고, jest 가 이 파일 전체를 0건 실행하고 있었다.
      salesService.findOne.mockResolvedValue({
        id: 5,
        storeId: 10,
        totalAmount: 8000,
      });

      const result = await controller.findOneAdmin('5', adminUser);

      expect(result).toEqual({ id: 5, storeId: 10, totalAmount: 8000 });
    });

    // Phase 67 이 이 경로에 매장 경계 검사를 넣은 이유 — 형제 핸들러에만 있어서
    // 타 매장 판매 상세가 그대로 노출되고 있었다. 그 검사를 여기서 고정한다.
    it('타 매장 판매는 403 (매장 경계)', async () => {
      salesService.findOne.mockResolvedValue({ id: 5, storeId: 99 });

      await expect(controller.findOneAdmin('5', adminUser)).rejects.toThrow(
        ForbiddenException,
      );
    });

    it('superadmin 은 타 매장 판매도 조회한다', async () => {
      salesService.findOne.mockResolvedValue({ id: 5, storeId: 99 });

      await expect(
        controller.findOneAdmin('5', superadminUser),
      ).resolves.toMatchObject({ id: 5 });
    });
  });

  describe('GET /sales/by-store/:storeId — 특정 매장 판매', () => {
    it('특정 매장의 판매 페이지네이션', async () => {
      const result = await controller.findSalesByStoreFiltered(
        '10',
        '0',
        '20',
        'Maria',
        '5',
        '2026-01-01',
        '2026-12-31',
      );

      expect(result.count).toBe(1);
      expect(salesService.findSalesByStoreFiltered).toHaveBeenCalledWith(
        0,
        20,
        10,
        {
          clientName: 'Maria',
          userId: 5,
          startDate: '2026-01-01',
          endDate: '2026-12-31',
        },
      );
    });
  });

  // ══════════════════════════════════════════
  // POST /sales/:id/nullify — 판매 무효화 (Anular)
  // ══════════════════════════════════════════

  describe('POST /sales/:id/nullify — 판매 무효화', () => {
    it('같은 store의 판매 무효화 성공', async () => {
      salesService.findOne.mockResolvedValue({
        id: 10,
        storeId: 10,
        status: SaleStatus.PAID,
      });

      const result = await controller.nullifySale('10', adminUser);

      expect(result.status).toBe(SaleStatus.NULLIFICATION);
      expect(result.nullifiedSaleId).toBe(10);
      expect(salesCreateService.nullifySale).toHaveBeenCalledWith(10, 1);
    });

    it('다른 store의 판매 무효화 시 에러 (admin)', async () => {
      salesService.findOne.mockResolvedValue({
        id: 10,
        storeId: 999,
        status: SaleStatus.PAID,
      });

      await expect(controller.nullifySale('10', adminUser)).rejects.toThrow(
        'No tienes permiso',
      );
    });

    it('superadmin은 다른 store 판매도 무효화 가능', async () => {
      salesService.findOne.mockResolvedValue({
        id: 10,
        storeId: 999,
        status: SaleStatus.PAID,
      });

      const result = await controller.nullifySale('10', superadminUser);

      expect(result.status).toBe(SaleStatus.NULLIFICATION);
    });
  });

  // ══════════════════════════════════════════
  // POST /sales/:id/payments — 결제 수단 추가
  // ══════════════════════════════════════════

  describe('POST /sales/:id/payments — 결제 수단 추가', () => {
    it('기존 판매에 결제 수단 추가 → PAID', async () => {
      const result = await controller.addPaymentMethods(1, [
        { paymentMethodId: 1, amount: 5000 },
      ]);

      expect(result.status).toBe(SaleStatus.PAID);
      expect(salesService.addPaymentMethods).toHaveBeenCalledWith(1, [
        { paymentMethodId: 1, amount: 5000 },
      ]);
    });
  });

  // ══════════════════════════════════════════
  // PUT /sales/:id — 판매 수정
  // ══════════════════════════════════════════

  describe('PUT /sales/:id — 판매 수정', () => {
    it('같은 store 판매 수정 성공', async () => {
      salesService.findOne.mockResolvedValue({ id: 1, storeId: 10 });

      const result = await controller.updateSale(
        1,
        { notes: 'updated' } as any,
        adminUser,
      );

      expect(result).toEqual({ id: 1, totalAmount: 5000 });
      expect(salesService.update).toHaveBeenCalledWith(1, { notes: 'updated' });
    });

    it('다른 store 판매 수정 시 에러', async () => {
      salesService.findOne.mockResolvedValue({ id: 1, storeId: 999 });

      await expect(
        controller.updateSale(1, { notes: 'x' } as any, adminUser),
      ).rejects.toThrow('No tienes permiso');
    });
  });

  // ══════════════════════════════════════════
  // DELETE /sales/:id — 판매 삭제
  // ══════════════════════════════════════════

  describe('DELETE /sales/:id — 판매 삭제', () => {
    it('같은 store 판매 삭제 성공', async () => {
      salesService.findOne.mockResolvedValue({
        id: 1,
        storeId: 10,
        totalAmount: 5000,
        clientId: 5,
      });

      const result = await controller.deleteSale(1, adminUser);

      expect(result).toEqual({
        id: 1,
        totalAmount: 5000,
        clientId: 5,
        deleted: true,
      });
      expect(salesService.delete).toHaveBeenCalledWith(1);
    });

    it('다른 store 판매 삭제 시 에러', async () => {
      salesService.findOne.mockResolvedValue({ id: 1, storeId: 999 });

      await expect(controller.deleteSale(1, adminUser)).rejects.toThrow(
        'No tienes permiso',
      );
    });

    it('superadmin은 다른 store 판매도 삭제 가능', async () => {
      salesService.findOne.mockResolvedValue({
        id: 1,
        storeId: 999,
        totalAmount: 3000,
        clientId: 1,
      });

      const result = await controller.deleteSale(1, superadminUser);

      expect(result.deleted).toBe(true);
    });
  });
});
