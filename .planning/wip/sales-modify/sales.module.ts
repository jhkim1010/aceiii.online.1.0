import { forwardRef, Module } from '@nestjs/common';
import { SalesController } from './sales.controller';
import { SalesService } from './sales.service';
import { Sale } from './sales.model';
import { SaleItem } from './sales-item/sales-item.model';
import { SequelizeModule } from '@nestjs/sequelize';
import { ProductsModule } from '../products/products.module';
import { DiscountModule } from '../discounts/discounts.module';
import { DiscountReason } from '../discounts/reason/discount-reason-model';
import { PaymentMethod } from '../payment-methods/payment-methods.model';
import { PaymentMethodsModule } from '../payment-methods/payment-methods.module';
import { SalePaymentMethod } from './sales-payment-methods/sales-payment-method.model';
import { PaymentMethodsOption } from '../payment-methods/option/payment-methods-option.model';
import { SaleDiscount } from './sales-discount/sale-discount.model';
import { SaleRecharge } from './sales-recharge/sale-recharge.model';
import { BoxOperationService } from '../box-operation/box-operation.service';
import { BoxOperationModule } from '../box-operation/box-operation.module';
import { SalesCreateService } from './sales-create.service';
import { SalesModifyService } from './sales-modify.service';
import { WebsocketModule } from 'src/common/socket/websocket.module';
import { Seller } from '../sellers/sellers.model';
// Phase 26 — Crédito · Seña · Favor 통합
import { CreditModule } from '../credit/credit.module';
import { StoreClient } from '../shared/store-clients/store-clients.model';
import { SaleSenia } from '../credit/sale-senia.model';
// Phase 29 Plan 09 — nullifySale 자동 환불 후크 (MpRefundService)
import { MercadopagoModule } from '../mercadopago/mercadopago.module';
// Phase 25 Plan 15 — OwnerScopeService 주입 (Pitfall 6: storeId=null aggregate)
import { CommonModule } from '../common/common.module';
// reprint/sendToprinters → PrintService.emitPrintInvoice (branch room 라우팅)
import { PrintModule } from '../print/print.module';
// resolveSaleBranchId — terminal→box→branch 조회용
import { Terminal } from '../terminal/terminal.model';
import { Box } from '../box/box.model';
// WP 재고/가격 push — sale create 후 영향 SKU 동기화
import { WpModule } from '../integrations/wp/wp.module';
// Phase 43 — outbox 기반 멀티플랫폼 push (USE_OUTBOX_SYNC 플래그로 병행)
import { CommerceCoreModule } from '../integrations/core/commerce-core.module';
// Phase 39 — 식당 sale 라이프사이클 (DRAFT 누적/타이밍/cuenta/split·merge 결제)
import { RestaurantSaleService } from './restaurant-sale/restaurant-sale.service';
import { RestaurantSaleController } from './restaurant-sale/restaurant-sale.controller';
import { RestaurantTablesModule } from '../restaurant-tables/restaurant-tables.module';
import { RestaurantTable } from '../restaurant-tables/restaurant-tables.model';
import { CashRegister } from '../cashRegister/cashRegister.model';
// 수표 결제 — ChequesService.createFromSale 훅
import { ChequesModule } from '../cheques/cheques.module';
// Factura Electrónica 자동 발급 훅 — AfipVoucherService/AfipIssuerService 주입.
// AfipModule 은 SalesModule 을 import 하지 않음(Sale 은 모델만 참조) → 순환 없음, forwardRef 불필요.
import { AfipModule } from '../afip/afip.module';
// Phase 64 W1 — 판매 요청 멱등키 (같은 Idempotency-Key 재시도가 판매를 복제하지 않도록)
import { SaleIdempotencyKey } from './sale-idempotency.model';
import { SaleIdempotencyService } from './sale-idempotency.service';
import { DailyNumberModule } from './daily-number.module';

@Module({
  imports: [
    DailyNumberModule,
    SequelizeModule.forFeature([
      Sale,
      SaleItem,
      SalePaymentMethod,
      SaleDiscount,
      SaleRecharge,
      DiscountReason,
      PaymentMethod,
      PaymentMethodsOption,
      Seller,
      // Phase 26
      StoreClient,
      SaleSenia,
      // resolveSaleBranchId — terminal→box→branch
      Terminal,
      Box,
      // Phase 39 — 식당 sale 라이프사이클 (테이블 점유 동기화 + 금전함 기록)
      RestaurantTable,
      CashRegister,
      // Phase 64 W1 — 판매 요청 멱등키
      SaleIdempotencyKey,
    ]),
    // Phase 39 — RestaurantTablesService.syncTableStatus 사용 (상태↔sale 트랜잭션 동기화)
    RestaurantTablesModule,
    forwardRef(() => WebsocketModule),
    // print-agent emit (PrintService). 순환(Print↔Sales via Sale) 회피 forwardRef.
    forwardRef(() => PrintModule),
    ProductsModule,
    DiscountModule,
    PaymentMethodsModule,
    BoxOperationModule,
    // Phase 26 — CreditLedgerService / CreditValidationService 사용
    CreditModule,
    // Phase 29 Plan 09 — MpRefundService 주입 (nullifySale 후크)
    MercadopagoModule,
    // Phase 25 Plan 15 — OwnerScopeService (resolveStoresForOwnerGroup) 사용
    CommonModule,
    // WP 재고/가격 push (WpSyncService). 순환 회피 forwardRef.
    forwardRef(() => WpModule),
    // Phase 43 — SyncOrchestratorService 주입 (outbox enqueue, feature flag 병행)
    CommerceCoreModule,
    ChequesModule,
    // Factura Electrónica 자동 발급 (AfipVoucherService/AfipIssuerService)
    AfipModule,
  ],
  providers: [
    SalesService,
    SalesCreateService,
    SalesModifyService,
    BoxOperationService,
    RestaurantSaleService,
    // Phase 64 W1
    SaleIdempotencyService,
  ],
  controllers: [SalesController, RestaurantSaleController],
  exports: [
    SequelizeModule,
    SalesService,
    SalesCreateService,
    SalesModifyService,
    SaleIdempotencyService,
  ],
})
export class SalesModule {}
