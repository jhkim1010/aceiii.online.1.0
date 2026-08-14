import { BadRequestException } from '@nestjs/common';
import { SalesModifyService } from './sales-modify.service';
import { Sale, SaleStatus } from './sales.model';
import { AfipVoucher } from '../afip/models/afip-voucher.model';
import { Store } from '../store/store.model';

/**
 * 판매 수정 — a(덮어쓰기) / b(대체) 판정과 관문.
 *
 * ★ 판정이 틀리면 돈이 조용히 달라진다: 금액이 바뀌었는데 덮어쓰면 이력 없이 총액이
 *   변하고, 안 바뀌었는데 대체하면 번호가 3개씩 소모되며 일보가 어그러진다.
 * ★ 관문(영수증·소급한도)은 "화면에서 안 보이게 했다" 로는 지켜지지 않는다.
 */

const TODAY = '2026-08-14';

const buildOriginal = (over: Record<string, any> = {}) => ({
  id: 100,
  storeId: 6,
  status: SaleStatus.PAID,
  nullifiedSaleId: null,
  dailyNumber: 3,
  saleDayLocal: TODAY,
  subtotal: 100000,
  discountAmount: 0,
  transport: 0,
  totalAmount: 100000,
  items: [{ productId: 7, quantity: 2, price: 50000 }],
  ...over,
});

const makeService = () => {
  const salesService = { findOne: jest.fn() };
  const salesCreateService = {
    nullifySale: jest.fn().mockResolvedValue({ id: 201 }),
    create: jest.fn().mockResolvedValue({ id: 202, dailyNumber: 9 }),
    resolveSaleBranchIdPublic: jest.fn().mockResolvedValue(6),
    applyCashDeltaForModification: jest.fn().mockResolvedValue(undefined),
  };
  const sequelize = {
    transaction: jest.fn(async (cb: any) =>
      cb({ LOCK: { UPDATE: 'UPDATE' } } as any),
    ),
    query: jest.fn().mockResolvedValue([{ total: '0' }]),
  };

  const service = new SalesModifyService(
    salesService as any,
    salesCreateService as any,
    sequelize as any,
  );

  return { service, salesService, salesCreateService, sequelize };
};

const user = { id: 7, storeId: 6, roles: ['vendedor'] } as any;
const admin = { id: 8, storeId: 6, roles: ['admin'] } as any;

beforeEach(() => {
  jest.restoreAllMocks();
  jest.spyOn(AfipVoucher, 'count').mockResolvedValue(0 as any);
  jest
    .spyOn(Store, 'findByPk')
    .mockResolvedValue({ timezone: 'America/Argentina/Buenos_Aires' } as any);
  jest.spyOn(Sale, 'findByPk').mockResolvedValue({
    id: 100,
    status: SaleStatus.PAID,
    dailyNumber: 3,
    saleDayLocal: TODAY,
    update: jest.fn().mockResolvedValue(undefined),
  } as any);
});

describe('a/b 판정 — 금액과 수량이 그대로면 덮어쓰기', () => {
  it('결제수단만 바뀌면 덮어쓰기 (같은 번호 유지, 역분개 없음)', async () => {
    const { service, salesService, salesCreateService } = makeService();
    const original = buildOriginal();
    salesService.findOne.mockResolvedValue(original);

    const res = await service.modifySale(
      100,
      { ...original, paymentMethods: [{ paymentMethodId: 2, amount: 100000 }] },
      user,
    );

    expect(res.mode).toBe('overwrite');
    expect(res.saleId).toBe(100);
    expect(res.dailyNumber).toBe(3);
    expect(salesCreateService.nullifySale).not.toHaveBeenCalled();
    expect(salesCreateService.create).not.toHaveBeenCalled();
  });

  it('손님·판매원만 바뀌어도 덮어쓰기', async () => {
    const { service, salesService, salesCreateService } = makeService();
    const original = buildOriginal();
    salesService.findOne.mockResolvedValue(original);

    const res = await service.modifySale(
      100,
      { ...original, clientId: 99, sellerId: 5 },
      user,
    );

    expect(res.mode).toBe('overwrite');
    expect(salesCreateService.nullifySale).not.toHaveBeenCalled();
  });

  it('★ 금액이 바뀌면 대체 — 10만 → 9만', async () => {
    const { service, salesService, salesCreateService } = makeService();
    salesService.findOne.mockResolvedValue(buildOriginal());

    const res = await service.modifySale(
      100,
      {
        items: [{ productId: 7, quantity: 2, price: 45000 }],
        subtotal: 90000,
        totalAmount: 90000,
        discountAmount: 0,
        transport: 0,
      },
      user,
    );

    expect(res.mode).toBe('replace');
    expect(salesCreateService.nullifySale).toHaveBeenCalledWith(100, 7);
    expect(res.reversalSaleId).toBe(201);
    expect(res.saleId).toBe(202);
  });

  it('★ 수량이 바뀌면 대체', async () => {
    const { service, salesService, salesCreateService } = makeService();
    salesService.findOne.mockResolvedValue(buildOriginal());

    const res = await service.modifySale(
      100,
      {
        items: [{ productId: 7, quantity: 1, price: 50000 }],
        subtotal: 50000,
        totalAmount: 50000,
        discountAmount: 0,
        transport: 0,
      },
      user,
    );

    expect(res.mode).toBe('replace');
    expect(salesCreateService.nullifySale).toHaveBeenCalled();
  });

  it('★ 총액이 같아도 상품 종류가 바뀌면 대체 (재고가 달라진다)', async () => {
    const { service, salesService } = makeService();
    salesService.findOne.mockResolvedValue(buildOriginal());

    const res = await service.modifySale(
      100,
      {
        items: [{ productId: 8, quantity: 2, price: 50000 }],
        subtotal: 100000,
        totalAmount: 100000,
        discountAmount: 0,
        transport: 0,
      },
      user,
    );

    expect(res.mode).toBe('replace');
  });

  it('새 판매는 원본을 가리킨다 (replacesSaleId) — 세 건이 한 묶음으로 읽혀야 한다', async () => {
    const { service, salesService, salesCreateService } = makeService();
    salesService.findOne.mockResolvedValue(buildOriginal());

    await service.modifySale(
      100,
      { items: [], subtotal: 0, totalAmount: 0, discountAmount: 0, transport: 0 },
      user,
      'idem-123',
    );

    expect(salesCreateService.create).toHaveBeenCalledWith(
      expect.objectContaining({ replacesSaleId: 100 }),
      { idempotencyKey: 'idem-123' },
    );
  });
});

describe('관문', () => {
  it('★ 영수증(CAE) 발행 건은 손대지 않는다', async () => {
    const { service, salesService, salesCreateService } = makeService();
    salesService.findOne.mockResolvedValue(buildOriginal());
    jest.spyOn(AfipVoucher, 'count').mockResolvedValue(1 as any);

    await expect(
      service.modifySale(100, buildOriginal(), user),
    ).rejects.toThrow(/ERR-MOD-003/);
    expect(salesCreateService.nullifySale).not.toHaveBeenCalled();
  });

  it('이미 취소된 판매는 수정 불가', async () => {
    const { service, salesService } = makeService();
    salesService.findOne.mockResolvedValue(
      buildOriginal({ status: SaleStatus.NULLIFIED }),
    );

    await expect(
      service.modifySale(100, buildOriginal(), user),
    ).rejects.toThrow(/ERR-MOD-002/);
  });

  it('역분개 자체는 수정 불가', async () => {
    const { service, salesService } = makeService();
    salesService.findOne.mockResolvedValue(
      buildOriginal({ status: SaleStatus.NULLIFICATION, nullifiedSaleId: 99 }),
    );

    await expect(
      service.modifySale(100, buildOriginal(), user),
    ).rejects.toThrow(/ERR-MOD-002/);
  });

  it('★ 일반 사용자는 어제까지만 — 그제 판매는 거부', async () => {
    const { service, salesService } = makeService();
    salesService.findOne.mockResolvedValue(
      buildOriginal({ saleDayLocal: '2026-01-01' }),
    );

    await expect(
      service.modifySale(100, buildOriginal(), user),
    ).rejects.toThrow(/ERR-MOD-005/);
  });

  it('★ admin 은 1개월까지 — 같은 판매를 통과시킨다', async () => {
    const { service, salesService } = makeService();
    const day = new Date();
    day.setUTCDate(day.getUTCDate() - 10);
    const recent = day.toISOString().slice(0, 10);
    const original = buildOriginal({ saleDayLocal: recent });
    salesService.findOne.mockResolvedValue(original);

    const res = await service.modifySale(100, original, admin);

    expect(res.mode).toBe('overwrite');
  });

  it('admin 이라도 1개월을 넘으면 거부', async () => {
    const { service, salesService } = makeService();
    salesService.findOne.mockResolvedValue(
      buildOriginal({ saleDayLocal: '2020-01-01' }),
    );

    await expect(
      service.modifySale(100, buildOriginal(), admin),
    ).rejects.toThrow(/ERR-MOD-005/);
  });

  it('영업일이 없는 레거시 판매는 막는다 — 한도의 근거가 없다', async () => {
    const { service, salesService } = makeService();
    salesService.findOne.mockResolvedValue(
      buildOriginal({ saleDayLocal: null }),
    );

    await expect(
      service.modifySale(100, buildOriginal(), user),
    ).rejects.toThrow(/ERR-MOD-004/);
  });

  it('다른 매장 판매는 거부', async () => {
    const { service, salesService } = makeService();
    salesService.findOne.mockResolvedValue(buildOriginal({ storeId: 99 }));

    await expect(
      service.modifySale(100, buildOriginal(), user),
    ).rejects.toThrow(/ERR-MOD-001/);
  });
});

describe('덮어쓰기의 카하 보정', () => {
  it('★ efectivo 구성이 바뀌면 그 차액을 카하에 보정한다', async () => {
    const { service, salesService, salesCreateService, sequelize } =
      makeService();
    salesService.findOne.mockResolvedValue(buildOriginal());

    // 전 100,000 → 후 0 (efectivo → tarjeta)
    let call = 0;
    sequelize.query.mockImplementation((sql: string) => {
      if (String(sql).includes('SUM(spm.amount)')) {
        call += 1;

        return Promise.resolve([{ total: call === 1 ? '100000' : '0' }]);
      }

      return Promise.resolve([]);
    });
    await service.modifySale(
      100,
      { ...buildOriginal(), paymentMethods: [{ paymentMethodId: 2, amount: 100000 }] },
      user,
    );

    expect(salesCreateService.applyCashDeltaForModification).toHaveBeenCalledWith(
      -100000,
      7,
      6,
      expect.stringContaining('Modificación de medio de pago'),
      expect.anything(),
    );
  });
});
