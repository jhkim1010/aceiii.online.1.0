import {
  BadRequestException,
  Body,
  Controller,
  ForbiddenException,
  Get,
  Headers,
  Param,
  Post,
  Put,
  Delete,
  Query,
} from '@nestjs/common';
import { SalesService } from './sales.service';
import { SalesCreateService } from './sales-create.service';
import { SalesModifyService } from './sales-modify.service';
import { CreateSaleDto } from './dto/create-sales.dto';
import { Sale } from './sales.model';
import { GetUser } from '../auth/decorators/get-user.decorator';
import { Users } from '../users/users.model';
import { Auth } from '../auth/decorators/auth.decorator';
import { ValidRoles } from '../auth/interfaces/valid-roles';
import { FunctionGuard } from '../auth/decorators/function-guard.decorator';
import { Audit } from '../../common/decorators/audit.decorator';
import {
  clampPage,
  clampPageSize,
  BULK_MAX_PAGE_SIZE,
} from '../../common/pagination/pagination.util';
import { OptionalDateStringPipe } from '../../common/pipes/optional-date-string.pipe';
import { isSuperAdminUser } from 'src/common/tenant/tenant-user.util';

@Controller('sales')
export class SalesController {
  constructor(
    private readonly salesService: SalesService,
    private readonly salesCreateService: SalesCreateService,
    private readonly salesModifyService: SalesModifyService,
  ) {}

  @Post()
  // 권한: crear-venta 기능 보유 역할만(가드가 매장별 role_function 판정). superadmin 우회.
  @FunctionGuard('crear-venta', 'create')
  @Audit({
    entityType: 'Venta',
    action: 'create',
    getDescription: (result, body, user) => {
      const total = result.totalAmount || body.totalAmount || 0;
      const clientName =
        result.client?.fullname || body.clientName || 'Cliente sin nombre';
      return `Venta creada por $${total} para cliente "${clientName}"`;
    },
  })
  async create(
    @Body() createSaleDto: CreateSaleDto,
    @GetUser() user: Users,
    // [Phase 64 W1] 선택 헤더 — 미전송이면 이전과 동일하게 동작한다(구버전 클라이언트 호환).
    // 재시도 시 같은 키를 유지해야 서버가 중복을 인식할 수 있다.
    @Headers('idempotency-key') idempotencyKey?: string,
  ): Promise<Sale> {
    const saleDto = {
      ...createSaleDto,
      storeId: user.storeId ?? createSaleDto.storeId,
      userId: user.id,
    };

    return this.salesCreateService.create(saleDto, { idempotencyKey });
  }

  @Get()
  @FunctionGuard('ver-ventas', 'read')
  async findAll(): Promise<Sale[]> {
    return this.salesService.findAll();
  }

  @Get('all')
  @FunctionGuard('ver-ventas', 'read')
  async findFiltered(
    @GetUser() user: any,
    @Query('page') page: string,
    @Query('pageSize') pageSize: string,
    // [Phase 67 W2] 날짜는 파이프에서 YYYY-MM-DD 로 고정 — 형식 위반은 400 으로 반환
    @Query('startDate', OptionalDateStringPipe) startDate?: string,
    @Query('endDate', OptionalDateStringPipe) endDate?: string,
    @Query('clientName') clientName?: string,
    // 2026-05-05 — VentaVista toolbar 신규 필터
    @Query('boxId') boxId?: string,
    @Query('terminalId') terminalId?: string,
    // CSV 형태로 N개: 'efectivo,credito,senia,favor' — 비어있으면 전체
    @Query('paymentSlugs') paymentSlugs?: string,
    // Phase 35: ventaVista 활동 분류 + 지점 필터 + Resumen 셀 드릴다운
    @Query('activityType') activityType?: string,
    @Query('originBranchId') originBranchId?: string,
    @Query('targetBranchId') targetBranchId?: string,
    @Query('direction') direction?: string,
  ) {
    const pageNum = clampPage(page);

    // [Phase 73-08] 상한 없는 pageSize 는 `?pageSize=1000000` 이 그대로 조회·직렬화가 된다.
    // 판매 목록은 연관을 여럿 포함해 비용이 특히 크다. 다만 상한을 50 으로 잡으면
    // DailySalesStats(pageSize=9999 로 일일 매출을 클라이언트 집계)가 **조용히 잘린다** —
    // 사장이 보는 숫자가 틀리게 된다. 그래서 대량 조회 상한을 쓴다.
    const pageSizeNum = clampPageSize(pageSize, { max: BULK_MAX_PAGE_SIZE });

    // Phase 35: activityType 화이트리스트 (T-35-11 — query param 변조 차단)
    const validActivityTypes = new Set(['sale', 'movido', 'fallado', 'all']);
    const at: 'sale' | 'movido' | 'fallado' | 'all' =
      activityType && validActivityTypes.has(activityType)
        ? (activityType as 'sale' | 'movido' | 'fallado' | 'all')
        : 'sale';

    // Phase 35: direction 화이트리스트 ('in' | 'out' 만 허용)
    const validDirections = new Set(['in', 'out']);
    const dir: 'in' | 'out' | null =
      direction && validDirections.has(direction)
        ? (direction as 'in' | 'out')
        : null;

    const filters = {
      startDate: startDate || null,
      endDate: endDate || null,
      clientName: clientName || null,
      boxId: boxId ? Number(boxId) : null,
      terminalId: terminalId ? Number(terminalId) : null,
      paymentSlugs: paymentSlugs
        ? paymentSlugs
            .split(',')
            .map((s) => s.trim())
            .filter(Boolean)
        : null,
      // Phase 35: 신규 활동 필터
      activityType: at,
      originBranchId: originBranchId ? Number(originBranchId) : null,
      targetBranchId: targetBranchId ? Number(targetBranchId) : null,
      direction: dir,
    };
    const result = await this.salesService.findFilteredByStore(
      pageNum,
      pageSizeNum,
      user.storeId,
      filters,
    );

    // [Phase 73-10] 이 응답이 전체를 담고 있는지 알려준다.
    //
    // DailySalesStats 는 이 엔드포인트를 pageSize=9999 로 한 번 불러 **브라우저에서**
    // 일일 매출을 집계한다. 즉 "한 페이지에 전부 들어온다"를 암묵적으로 가정한다.
    // 하루 판매가 상한을 넘는 순간 그 가정이 깨지는데, 오류도 안 나고 화면도 정상으로
    // 보인 채 **숫자만 조용히 작아진다.** 사장이 보는 매출이 틀리는데 아무도 모른다.
    //
    // 서버는 총건수를 알고 있으니 사실을 그대로 알려준다. 클라이언트가 이 플래그를 보고
    // "집계 불완전"을 표시할 수 있다. (근본 해결은 서버측 집계로 옮기는 것 — 별도 과제.)
    const returned = result.rows?.length ?? 0;
    const truncated = result.count > pageNum * pageSizeNum + returned;

    if (truncated && pageSizeNum >= BULK_MAX_PAGE_SIZE) {
      // 상한에 닿아 잘린 경우만 경고한다(일반 페이지네이션에서 잘리는 것은 정상이다).
      console.warn(
        `[SALES_TRUNCATED] store=${String(user.storeId)} count=${result.count} ` +
          `pageSize=${pageSizeNum} — 상한에 걸려 잘렸다. 클라이언트 집계라면 결과가 부정확하다.`,
      );
    }

    return {
      count: result.count,
      data: result.rows,
      page: pageNum,
      pageSize: pageSizeNum,
      truncated,
      filters: filters,
    };
  }

  // ─── Phase 35: ventaVista Resumen 테이블 데이터 source ────────────────────
  // 응답 shape: { date, perBranch:[{branchId,branchName,ventas:{count,amount},
  //                prendas, descuento, movIn, movOut, fallados, neto}],
  //              total: {...}, movBalance: {in, out, balanced} }
  //
  // NestJS route ordering: 본 라우트는 @Get(':id') 보다 위에 있어야 'daily-stats' 가
  // id param 으로 흡수되지 않음. 이 메서드 위치 = controller class 의 GET(':id') 보다 앞.
  @Get('daily-stats')
  @FunctionGuard('ver-ventas', 'read')
  async getDailyStats(
    @GetUser() user: Users,
    @Query('startDate', OptionalDateStringPipe) startDate?: string,
    @Query('endDate', OptionalDateStringPipe) endDate?: string,
  ): Promise<any> {
    if (!user?.storeId) {
      throw new Error('storeId 누락 — 사용자가 매장에 속해야 합니다');
    }

    // 기본값: 오늘 (사용자가 startDate/endDate 미지정 시)
    const today = new Date().toISOString().slice(0, 10);

    return this.salesService.getDailyStats({
      storeId: user.storeId,
      startDate: startDate || today,
      endDate: endDate || today,
    });
  }

  // ─── [Phase 73-14] 일일 통계 서버측 집계 ──────────────────────────────
  // DailySalesStats 사이드바 전용. 종전에는 프론트가 `/sales/all?pageSize=9999` 로
  // 판매를 전부 받아 브라우저에서 더했다 — 연관 8개 eager load 라 JOIN 행이 곱해지고,
  // 하루 판매가 상한을 넘으면 **숫자가 조용히 작아졌다**(73-10 truncated 경고로 임시 방어).
  // 이 라우트는 같은 계산을 SQL GROUP BY 로 하므로 전송량이 판매 건수와 무관하다.
  //
  // NestJS route ordering: @Get(':id') 보다 위여야 'daily-summary' 가 id 로 안 먹힌다.
  @Get('daily-summary')
  @FunctionGuard('ver-ventas', 'read')
  async getDailySummary(
    @GetUser() user: Users,
    @Query('startDate', OptionalDateStringPipe) startDate?: string,
    @Query('endDate', OptionalDateStringPipe) endDate?: string,
    @Query('branchId') branchId?: string,
  ): Promise<any> {
    if (!user?.storeId) {
      throw new BadRequestException(
        'storeId 누락 — 사용자가 매장에 속해야 합니다',
      );
    }

    const today = new Date().toISOString().slice(0, 10);

    // branchId 는 숫자만 허용 — 아니면 전 지점 합산(필터 미적용)으로 폴백.
    const br = Number(branchId);
    const safeBranchId = Number.isInteger(br) && br > 0 ? br : null;

    return this.salesService.getDailySummary({
      storeId: user.storeId,
      startDate: startDate || today,
      endDate: endDate || today,
      branchId: safeBranchId,
    });
  }

  @Get('by-store')
  @Auth(ValidRoles.superadmin)
  async findSalesByStore(
    @Query('page') page: string,
    @Query('pageSize') pageSize: string,
    @Query('storeName') storeName?: string,
    @Query('startDate', OptionalDateStringPipe) startDate?: string,
    @Query('endDate', OptionalDateStringPipe) endDate?: string,
  ) {
    const pageNum = clampPage(page);
    const pageSizeNum = clampPageSize(pageSize);
    const filters = {
      storeName: storeName || null,
      startDate: startDate || null,
      endDate: endDate || null,
    };
    const result = await this.salesService.findSalesByStore(
      pageNum,
      pageSizeNum,
      filters,
    );

    return {
      count: result.count,
      data: result.rows,
      page: pageNum,
      pageSize: pageSizeNum,
    };
  }

  // Reprint — 기존 판매를 같은 포맷으로 재인쇄 (variant 매트릭스 포함).
  //   권한: vendedor 포함 매장 멤버 전원 (영업 현장에서 직접 재인쇄 가능해야 함).
  //   storeId 격리: 본인 매장 판매만. superadmin 은 cross-store 허용.
  //   응답: { sent, reason? } — 인쇄 가능 여부 + 실패 사유.
  @Post(':id/reprint')
  @Auth(
    ValidRoles.vendedor,
    ValidRoles.gerente,
    ValidRoles.admin,
    ValidRoles.superadmin,
  )
  @Audit({
    entityType: 'Venta',
    action: 'edit',
    getDescription: (result) => {
      const sent = result?.sent ? 'OK' : `FAIL (${result?.reason ?? '?'})`;

      return `Reimpresión de Venta — ${sent}`;
    },
  })
  async reprintSale(
    @Param('id') id: string,
    @GetUser() user: Users,
  ): Promise<{ sent: boolean; reason?: string }> {
    const saleId = parseInt(id, 10);
    if (!Number.isFinite(saleId)) {
      return { sent: false, reason: 'invalid_id' };
    }
    const saleStoreId = await this.salesCreateService.getSaleStoreId(saleId);
    if (saleStoreId === null) {
      return { sent: false, reason: 'sale_not_found' };
    }
    const isSuperadmin = isSuperAdminUser(user);
    if (!isSuperadmin && saleStoreId !== user.storeId) {
      throw new Error('No tenés permiso para reimprimir esta venta');
    }

    return this.salesCreateService.reprintSale(saleId);
  }

  @Post(':id/nullify')
  // 무효화(anular) = modificar-venta 보유 역할만. prod 매트릭스상 owner/admin/gerente + superadmin.
  @FunctionGuard('modificar-venta', 'update')
  @Audit({
    entityType: 'Venta',
    action: 'edit',
    getDescription: (result, body, user) => {
      const originalId = result.nullifiedSaleId || 'N/A';
      const total = Math.abs(result.totalAmount || 0);
      return `Venta ID ${originalId} anulada (Total: $${total}) → Reversal ID ${result.id}`;
    },
  })
  async nullifySale(
    @Param('id') id: string,
    @GetUser() user: Users,
  ): Promise<Sale> {
    const saleId = parseInt(id, 10);
    const existingSale = await this.salesService.findOne(saleId);
    if (existingSale.storeId !== user.storeId && !isSuperAdminUser(user)) {
      throw new Error('No tienes permiso para anular esta venta');
    }
    return this.salesCreateService.nullifySale(saleId, user.id);
  }

  /**
   * 이미 등록된 판매의 수정.
   *
   * ★ a(덮어쓰기) / b(대체) 판정은 **서버가** 한다. 클라이언트가 "내용 안 바꿨음" 을
   *   보내면 낡은 화면이 잘못 분기해 금액이 바뀌었는데 이력 없이 덮일 수 있다.
   * ★ b 는 두 단계(취소+신규)라 재시도로 중복되면 안 된다 → Idempotency-Key.
   */
  @Post(':id/modify')
  @FunctionGuard('modificar-venta', 'update')
  @Audit({
    entityType: 'Venta',
    action: 'edit',

    // 콜백 첫 인자는 body 가 아니라 **result** 다(audit.interceptor.ts).
    getEntityId: (result: any) => result?.saleId,
    getDescription: (result: any) =>
      result?.mode === 'overwrite'
        ? `Venta ID ${result?.saleId} modificada en el lugar (mismo número ${result?.dailyNumber ?? '?'})`
        : `Venta ID ${result?.originalSaleId ?? '?'} reemplazada → anulación ID ${result?.reversalSaleId}, nueva venta ID ${result?.saleId}`,
  })
  async modifySale(
    @Param('id') id: string,
    @Body() dto: any,
    @GetUser() user: Users,
    @Headers('idempotency-key') idempotencyKey?: string,
  ) {
    const saleId = parseInt(id, 10);
    if (!Number.isFinite(saleId)) {
      throw new BadRequestException('ID inválido');
    }

    const result = await this.salesModifyService.modifySale(
      saleId,
      dto,
      user,
      idempotencyKey,
    );

    return { ...result, originalSaleId: saleId };
  }

  @Post(':id/payments')
  @FunctionGuard('agregar-pagos-a-venta', 'update')
  @Audit({
    entityType: 'Venta',
    action: 'edit',
    getDescription: (result, body, user) => {
      const paymentCount = Array.isArray(body)
        ? body.length
        : body.paymentMethods?.length || 0;
      const saleId = result.id || 'N/A';
      return `Métodos de pago modificados en venta ID ${saleId} (${paymentCount} métodos)`;
    },
  })
  async addPaymentMethods(
    @Param('id') id: number,
    @Body('paymentMethods') paymentMethods: any[],
  ): Promise<Sale> {
    return this.salesService.addPaymentMethods(Number(id), paymentMethods);
  }

  @Put(':id')
  @FunctionGuard('modificar-venta', 'update')
  @Audit({
    entityType: 'Venta',
    action: 'edit',
    getDescription: (result, body, user) => {
      const total = result.totalAmount || body.totalAmount || 0;
      return `Venta ID ${result.id || 'N/A'} editada (Total: $${total})`;
    },
  })
  async updateSale(
    @Param('id') id: number,
    @Body() updateData: Partial<CreateSaleDto>,
    @GetUser() user: Users,
  ): Promise<Sale> {
    const existingSale = await this.salesService.findOne(Number(id));
    if (existingSale.storeId !== user.storeId && !isSuperAdminUser(user)) {
      throw new Error('No tienes permiso para editar esta venta');
    }

    return this.salesService.update(Number(id), updateData);
  }

  @Delete(':id')
  @FunctionGuard('modificar-venta', 'delete')
  @Audit({
    entityType: 'Venta',
    action: 'remove',
    getDescription: (result, body, user) => {
      const total = result?.totalAmount || 'N/A';
      const saleId = result?.id || 'N/A';
      return `Venta eliminada ID ${saleId} (Total: $${total})`;
    },
  })
  async deleteSale(
    @Param('id') id: number,
    @GetUser() user: Users,
  ): Promise<any> {
    const existingSale = await this.salesService.findOne(Number(id));
    if (existingSale.storeId !== user.storeId && !isSuperAdminUser(user)) {
      throw new Error('No tienes permiso para eliminar esta venta');
    }
    const saleData = {
      id: existingSale.id,
      totalAmount: existingSale.totalAmount,
      clientId: existingSale.clientId,
    };
    await this.salesService.delete(Number(id));

    return { ...saleData, deleted: true };
  }

  @Get(':id')
  @FunctionGuard('detalle-de-venta', 'read')
  async findOneAdmin(@Param('id') id: string, @GetUser() user: Users) {
    const saleId = parseInt(id, 10);
    const sale = await this.salesService.findOne(saleId);

    // [Phase 67] 형제 핸들러(reprintSale/nullifySale/updateSale/deleteSale)에만 있던
    // 매장 경계 검사가 이 조회 경로에서 빠져 있었다 — 타 매장 판매 상세가 그대로 노출됐다.
    if (sale.storeId !== user.storeId && !isSuperAdminUser(user)) {
      throw new ForbiddenException('No tenés permiso para ver esta venta');
    }

    return sale;
  }

  @Get('by-store/:storeId')
  @FunctionGuard('ver-ventas', 'read')
  async findSalesByStoreFiltered(
    @Param('storeId') storeId: string,
    @Query('page') page: string,
    @Query('pageSize') pageSize: string,
    @Query('clientName') clientName?: string,
    @Query('userId') userId?: string,
    @Query('startDate', OptionalDateStringPipe) startDate?: string,
    @Query('endDate', OptionalDateStringPipe) endDate?: string,
  ) {
    const pageNum = clampPage(page);
    const pageSizeNum = clampPageSize(pageSize);
    const filters = {
      clientName: clientName || null,
      userId: userId ? Number(userId) : null,
      startDate: startDate || null,
      endDate: endDate || null,
    };
    const result = await this.salesService.findSalesByStoreFiltered(
      pageNum,
      pageSizeNum,
      Number(storeId),
      filters,
    );
    return {
      count: result.count,
      data: result.rows,
      page: pageNum,
      pageSize: pageSizeNum,
      filters: filters,
    };
  }
}
