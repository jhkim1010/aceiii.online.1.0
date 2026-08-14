import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { Sequelize } from 'sequelize-typescript';
import { QueryTypes } from 'sequelize';
import { Users } from '../users/users.model';
import { Sale, SaleStatus } from './sales.model';
import { SalesService } from './sales.service';
import { SalesCreateService } from './sales-create.service';
import { AfipVoucher } from '../afip/models/afip-voucher.model';
import { Store } from '../store/store.model';
import { DEFAULT_STORE_TZ } from 'src/common/constants/timezone';
import { isSuperAdminUser } from 'src/common/tenant/tenant-user.util';

/**
 * 이미 등록된 판매의 수정.
 *
 * 두 갈래이고, **어느 쪽인지는 서버가 정한다.**
 *   (a) 덮어쓰기  — 품목(종류·수량)과 금액이 그대로면 같은 번호를 유지하고 제자리 수정.
 *                   결제수단·손님·판매원·pedido 가 무엇이 바뀌든 여기에 해당한다.
 *   (b) 대체      — 금액이나 수량이 바뀌면 원본을 덮지 않고 **오늘 날짜로** 세 행을 남긴다:
 *                   ① 원본 +100,000 'Anulado'
 *                   ② 역분개 -100,000 'Anulación' (원본 번호·날짜를 notes 에 기록)
 *                   ③ 새 판매 +90,000 (replacesSaleId → ①)
 *
 * ★ 판정을 클라이언트가 보내면 안 된다. 화면이 낡은 스냅샷을 들고 잘못 분기하면
 *   금액이 바뀌었는데 덮어써서 **이력 없이 돈이 달라진다.** 서버가 원본을 잠그고 비교한다.
 * ★ ②③ 이 오늘 날짜인 이유: 원본 날짜로 소급하면 그날 구간이 이미 정산됐을 수 있고
 *   (box_settlements) 확정된 정산이 어긋난다. 현금도 지금 이 서랍에서 오간다.
 * ★ 영수증(CAE) 발행 건은 손대지 않는다 — 세무 문서가 걸린 순간 이 경로의 문제가 아니다.
 */
@Injectable()
export class SalesModifyService {
  private readonly logger = new Logger(SalesModifyService.name);

  /** 일반 사용자가 소급할 수 있는 날짜 수 (오늘 포함 어제까지). */
  private static readonly RETRO_DAYS_DEFAULT = 1;

  /** admin/superadmin 소급 한도 (1개월). */
  private static readonly RETRO_DAYS_ADMIN = 30;

  constructor(
    private readonly salesService: SalesService,
    private readonly salesCreateService: SalesCreateService,
    private readonly sequelize: Sequelize,
  ) {}

  async modifySale(
    saleId: number,
    dto: any,
    user: Users,
    idempotencyKey?: string,
  ): Promise<{
    mode: 'overwrite' | 'replace';
    saleId: number;
    reversalSaleId?: number;
    dailyNumber?: number;
  }> {
    const original = await this.salesService.findOne(saleId);
    if (!original) {
      throw new NotFoundException(`Venta ID ${saleId} no encontrada`);
    }
    if (original.storeId !== user.storeId && !isSuperAdminUser(user)) {
      throw new ForbiddenException('[ERR-MOD-001] Venta de otra tienda');
    }

    await this.assertModifiable(original, user);

    const overwrite = this.isMoneyUnchanged(original, dto);

    if (overwrite) {
      await this.overwriteInPlace(original, dto, user);

      return {
        mode: 'overwrite',
        saleId: original.id,
        dailyNumber: original.dailyNumber,
      };
    }

    return this.replaceWithReversal(original, dto, user, idempotencyKey);
  }

  // ── 수정 가능 여부 ─────────────────────────────────────────────────────────

  private async assertModifiable(original: Sale, user: Users): Promise<void> {
    if (
      original.status === SaleStatus.NULLIFIED ||
      original.status === SaleStatus.NULLIFICATION ||
      original.nullifiedSaleId
    ) {
      throw new BadRequestException(
        '[ERR-MOD-002] No se puede modificar una venta anulada ni una anulación',
      );
    }

    // ★ 영수증 발행 여부는 `status` 로 판정하면 안 된다. 운영 sales.status 에는
    //   'Facturado' 가 **한 건도 없고**(Pagado/Borrador/Anulado/Anulación 뿐) CAE 를 받은
    //   판매도 'Pagado' 로 남는다. 실제 근거는 afip_vouchers 행의 존재다.
    const invoiced = await AfipVoucher.count({ where: { saleId: original.id } });
    if (invoiced > 0) {
      throw new BadRequestException(
        '[ERR-MOD-003] Esta venta tiene comprobante fiscal emitido. ' +
          'No se modifica desde acá — corresponde nota de crédito.',
      );
    }

    const localToday = await this.storeLocalDate(Number(original.storeId));
    const isAdmin = isSuperAdminUser(user) || this.hasAdminRole(user);
    const days = isAdmin
      ? SalesModifyService.RETRO_DAYS_ADMIN
      : SalesModifyService.RETRO_DAYS_DEFAULT;
    const oldest = this.shiftDate(localToday, -days);

    // saleDayLocal 이 비어 있는 레거시 판매는 날짜를 신뢰할 수 없으므로 막는다 —
    // 소급 한도의 근거가 없는 채로 통과시키면 한도가 있으나 마나가 된다.
    const day = original.saleDayLocal;
    if (!day) {
      throw new BadRequestException(
        '[ERR-MOD-004] La venta no tiene fecha de jornada — no se puede modificar',
      );
    }
    if (String(day) < oldest) {
      throw new BadRequestException(
        `[ERR-MOD-005] Solo se pueden modificar ventas desde ${oldest} ` +
          `(esta es del ${String(day)})`,
      );
    }
  }

  private hasAdminRole(user: Users): boolean {
    const roles = Array.isArray((user as any)?.roles) ? (user as any).roles : [];

    return roles.some((r: string) =>
      ['admin', 'superadmin', 'store_owner', 'store_admin'].includes(r),
    );
  }

  // ── a/b 판정 ───────────────────────────────────────────────────────────────

  /**
   * "금액과 수량에 변동이 없나" — 있으면 덮어쓰기(a), 없으면 대체(b).
   *
   * ★ 종류도 본다. 같은 값·같은 수량이라도 **다른 상품**으로 바뀌면 가져가는 물건이
   *   달라진 것이므로 대체다(재고가 달라진다).
   * ★ 단가까지 본다. 수량과 총액이 같아도 단가 조합이 다르면 다른 판매다.
   */
  private isMoneyUnchanged(original: Sale, dto: any): boolean {
    const before = this.itemFingerprint(original.items ?? []);
    const after = this.itemFingerprint(dto?.items ?? []);
    if (before !== after) return false;

    return (
      this.money(original.totalAmount) === this.money(dto?.totalAmount) &&
      this.money(original.subtotal) === this.money(dto?.subtotal) &&
      this.money(original.discountAmount) === this.money(dto?.discountAmount) &&
      this.money(original.transport) === this.money(dto?.transport)
    );
  }

  /** (productId, quantity, price) 다중집합을 순서 무관 문자열로. */
  private itemFingerprint(items: any[]): string {
    return items
      .map(
        (it) =>
          `${Number(it.productId ?? it.product?.id ?? 0)}:` +
          `${Number(it.quantity) || 0}:${this.money(it.price)}`,
      )
      .sort()
      .join('|');
  }

  /** 소수 오차로 a/b 가 갈리지 않게 2자리로 고정한다. */
  private money(v: any): string {
    return (Number(v) || 0).toFixed(2);
  }

  // ── (a) 덮어쓰기 ───────────────────────────────────────────────────────────

  private async overwriteInPlace(
    original: Sale,
    dto: any,
    user: Users,
  ): Promise<void> {
    const branchId = await this.salesCreateService.resolveSaleBranchIdPublic(
      original,
    );

    await this.sequelize.transaction(async (t) => {
      // 원본을 잠근다 — 판정과 쓰기 사이에 다른 요청이 이 판매를 바꾸면 안 된다.
      const locked = await Sale.findByPk(original.id, {
        lock: t.LOCK.UPDATE,
        transaction: t,
      });
      if (!locked) {
        throw new NotFoundException(`Venta ID ${original.id} no encontrada`);
      }
      if (
        locked.status === SaleStatus.NULLIFIED ||
        locked.status === SaleStatus.NULLIFICATION
      ) {
        throw new BadRequestException(
          '[ERR-MOD-002] No se puede modificar una venta anulada ni una anulación',
        );
      }

      const efectivoBefore = await this.efectivoTotalOf(original.id, t);

      // 결제수단 교체. 품목·금액은 정의상 그대로라 건드리지 않는다.
      await this.sequelize.query(
        'DELETE FROM sale_payment_methods WHERE sale_id = :saleId',
        { replacements: { saleId: original.id }, transaction: t },
      );
      for (const pm of dto?.paymentMethods ?? []) {
        await this.sequelize.query(
          `INSERT INTO sale_payment_methods (sale_id, payment_method_id, option_id, amount, created_at, updated_at)
           VALUES (:saleId, :pmId, :optionId, :amount, NOW(), NOW())`,
          {
            replacements: {
              saleId: original.id,
              pmId: Number(pm.paymentMethodId),
              optionId: pm.optionId ?? null,
              amount: Number(pm.amount) || 0,
            },
            transaction: t,
          },
        );
      }

      const efectivoAfter = await this.efectivoTotalOf(original.id, t);

      // 돈과 무관한 필드들 — 손님·판매원·메모.
      await locked.update(
        {
          ...(dto.clientId !== undefined ? { clientId: dto.clientId } : {}),
          ...(dto.storeClientId !== undefined
            ? { storeClientId: dto.storeClientId }
            : {}),
          ...(dto.sellerId !== undefined ? { sellerId: dto.sellerId } : {}),
          ...(dto.notes !== undefined ? { notes: dto.notes } : {}),
        },
        { transaction: t },
      );

      // ★ 서랍 현금이 달라졌으면 그 차이를 **지금 열린 카하**에 보정한다.
      //   이걸 빠뜨리면 "결제수단만 바꿨는데 서랍이 안 맞는" 상태가 조용히 남는다.
      await this.salesCreateService.applyCashDeltaForModification(
        efectivoAfter - efectivoBefore,
        user.id,
        branchId,
        `Modificación de medio de pago — venta #${locked.dailyNumber || locked.id} ` +
          `del ${locked.saleDayLocal ?? '?'} (ID: ${locked.id})`,
        t,
      );

      // ★ 무엇이 무엇으로 바뀌었는지 남긴다. 덮어쓰기는 이력이 사라지기 쉬운 형태라
      //   "누가 언제 efectivo→tarjeta 로 바꿨나" 가 반드시 기록되어야 한다.
      this.logger.log(
        JSON.stringify({
          event: 'sale_modified',
          mode: 'overwrite',
          saleId: original.id,
          saleDay: original.saleDayLocal,
          efectivoBefore,
          efectivoAfter,
          by: user.id,
        }),
      );
    });
  }

  /** 그 판매의 efectivo 결제 합계. 생성·취소와 같은 기준(slug='efectivo')을 쓴다. */
  private async efectivoTotalOf(saleId: number, t: any): Promise<number> {
    const rows = await this.sequelize.query<{ total: string }>(
      `SELECT COALESCE(SUM(spm.amount), 0) AS total
         FROM sale_payment_methods spm
         JOIN payment_methods pm ON pm.id = spm.payment_method_id
        WHERE spm.sale_id = :saleId AND pm.slug = 'efectivo'`,
      {
        replacements: { saleId },
        type: QueryTypes.SELECT,
        transaction: t,
      },
    );

    return Number(rows?.[0]?.total) || 0;
  }

  // ── (b) 대체 ───────────────────────────────────────────────────────────────

  private async replaceWithReversal(
    original: Sale,
    dto: any,
    user: Users,
    idempotencyKey?: string,
  ): Promise<{
    mode: 'replace';
    saleId: number;
    reversalSaleId: number;
    dailyNumber?: number;
  }> {
    // ★ 두 단계를 한 동작으로 묶는 근거가 멱등키다. 중간에 끊겨 재시도하면
    //   "취소만 되고 새 판매가 없는" 상태나 역분개 2건이 남는다.
    const reversal = await this.salesCreateService.nullifySale(
      original.id,
      user.id,
    );

    const created = await this.salesCreateService.create(
      {
        ...dto,
        storeId: original.storeId,
        userId: user.id,

        // 새 판매는 **오늘** 이다(create 가 오늘로 채번한다). 원본 날짜로 소급하면
        // 그날 구간이 이미 정산됐을 수 있어 확정된 정산이 어긋난다.
        replacesSaleId: original.id,
      } as any,
      { idempotencyKey },
    );

    this.logger.log(
      JSON.stringify({
        event: 'sale_modified',
        mode: 'replace',
        originalSaleId: original.id,
        originalDay: original.saleDayLocal,
        reversalSaleId: (reversal as any)?.id ?? null,
        newSaleId: (created as any)?.id ?? null,
        by: user.id,
      }),
    );

    return {
      mode: 'replace',
      saleId: Number((created as any)?.id),
      reversalSaleId: Number((reversal as any)?.id),
      dailyNumber: (created as any)?.dailyNumber,
    };
  }

  // ── 유틸 ───────────────────────────────────────────────────────────────────

  /** 매장 현지 오늘(YYYY-MM-DD). 자동 마감·정산과 같은 정의. */
  private async storeLocalDate(storeId: number): Promise<string> {
    const store = await Store.findByPk(storeId, { attributes: ['timezone'] });
    const tz = store?.timezone || DEFAULT_STORE_TZ;

    return new Intl.DateTimeFormat('en-CA', {
      timeZone: tz,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    }).format(new Date());
  }

  /** YYYY-MM-DD 를 days 만큼 옮긴다. UTC 로 계산해 DST 에 흔들리지 않게. */
  private shiftDate(date: string, days: number): string {
    const d = new Date(`${date}T00:00:00Z`);
    d.setUTCDate(d.getUTCDate() + days);

    return d.toISOString().slice(0, 10);
  }
}
