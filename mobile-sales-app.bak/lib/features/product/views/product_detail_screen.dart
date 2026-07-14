// S3 Detalle (/product/:id) — hero + "Stock por color y talle" 매트릭스 + selbar + 하단 액션.
// hero(name/price)는 카탈로그에서 넘어온 CatalogItem(extra) 또는 in-memory 캐시에서 역참조.
// QR 직행(캐시 미스) 시에도 매트릭스는 /mobile/stock 로 완전 동작(D-14 재고 비교가 목적).
// 하단: ✨ Probar con foto(disabled+"Próximamente", UI-D1) + Añadir al carrito({n})(navy).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/format/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../catalog/data/catalog_dto.dart';
import '../../catalog/providers/catalog_provider.dart';
import '../../cart/providers/cart_provider.dart';
import '../data/stock_dto.dart';
import '../data/stock_repository.dart';
import '../providers/variant_matrix_provider.dart';
import '../providers/product_image_provider.dart';
import '../widgets/variant_stock_matrix.dart';

class ProductDetailScreen extends ConsumerStatefulWidget {
  final int productId;
  // 카탈로그에서 넘어온 상품(hero/price 소스). QR 직행 시 null → 캐시 역참조.
  final CatalogItem? item;

  const ProductDetailScreen({super.key, required this.productId, this.item});

  @override
  ConsumerState<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  VariantMatrixController? _controller;

  // hero/price 소스: extra → in-memory 카탈로그 캐시 → null
  CatalogItem? get _resolvedItem =>
      widget.item ?? cachedCatalogItem(widget.productId);

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  VariantMatrixController _ensureController(StockResult stock) {
    final existing = _controller;
    if (existing != null) {
      return existing;
    }
    final c = VariantMatrixController(stock.stockByVariant);
    _controller = c;

    return c;
  }

  void _addToCart(CatalogItem? item) {
    final controller = _controller;
    if (controller == null || !controller.addEnabled) {
      return;
    }
    final name = item?.name ?? 'Producto #${widget.productId}';
    final price = item?.price ?? 0;
    final lines = <CartLine>[];
    for (final v in controller.variants) {
      final qty = controller.qtyFor(v);
      if (qty <= 0) {
        continue;
      }
      lines.add(CartLine(
        productId: widget.productId,
        productName: name,
        price: price,
        colorId: v.color.id,
        colorName: v.color.name ?? '—',
        colorHex: null,
        sizeId: v.size.id,
        sizeName: v.size.name ?? '—',
        quantity: qty,
        ownAvailable: controller.availableFor(v),
      ));
    }
    ref.read(cartProvider.notifier).mergeLines(lines);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Añadido al carrito')));
    context.push('/comanda');
  }

  @override
  Widget build(BuildContext context) {
    final stockAsync = ref.watch(productStockProvider(widget.productId));
    final item = _resolvedItem;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () => context.pop(),
        ),
        title: const Text('Detalle', style: TextStyle(fontSize: 17)),
      ),
      body: stockAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'No se pudo cargar el stock del producto.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted),
            ),
          ),
        ),
        data: (stock) {
          final controller = _ensureController(stock);

          return Column(
            children: [
              _hero(item),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: Row(
                  children: [
                    const Text(
                      'Stock por color y talle',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink),
                    ),
                    const Spacer(),
                    // 범례 (traslado 문구 제거 — UI-D2)
                    const Text(
                      'tu sucursal · otras',
                      style: TextStyle(fontSize: 11, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: VariantStockMatrix(controller: controller),
                ),
              ),
              _bottomBar(controller, item),
            ],
          );
        },
      ),
    );
  }

  Widget _hero(CatalogItem? item) {
    final name = item?.name ?? 'Producto #${widget.productId}';
    final sku = item?.sku ?? '';
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          _heroPhoto(),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink),
                ),
                if (sku.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(sku, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                ],
                const SizedBox(height: 6),
                Text(
                  item != null ? formatMoney(item.price) : '—',
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                    fontFeatures: kTabularFigures,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 제품 대표 사진 — 없으면 🏷️ 이모지 폴백. 로드 실패 시에도 폴백.
  Widget _heroPhoto() {
    final imgAsync = ref.watch(productImageUrlProvider(widget.productId));
    const fallback = Text('🏷️', style: TextStyle(fontSize: 30));

    return Container(
      width: 72,
      height: 72,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.soft,
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.center,
      child: imgAsync.maybeWhen(
        data: (url) => url == null
            ? fallback
            : Image.network(
                url,
                width: 72,
                height: 72,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => fallback,
              ),
        orElse: () => fallback,
      ),
    );
  }

  Widget _bottomBar(VariantMatrixController controller, CatalogItem? item) {
    return SafeArea(
      top: false,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final total = controller.selectedTotal;
          final price = item?.price ?? 0;

          return Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.line)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // selbar
                Row(
                  children: [
                    Text(
                      total > 0
                          ? 'Seleccionado: $total u · ${formatMoney(controller.moneyFor(price))}'
                          : 'Escribí cuántas unidades querés llevar',
                      style: const TextStyle(fontSize: 13, color: AppColors.muted),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    // ✨ Probar con foto — disabled + "Próximamente" (UI-D1)
                    Expanded(
                      child: _ProbarConFotoButton(),
                    ),
                    const SizedBox(width: 10),
                    // Añadir al carrito ({n}) — navy solid, n==0 이면 disabled
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: controller.addEnabled ? () => _addToCart(item) : null,
                        child: Text('Añadir al carrito ($total)'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// disabled 상태로 렌더 + 탭 시 "Próximamente" 토스트 (UI-D1 — AI 미구현)
class _ProbarConFotoButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Próximamente')));
      },
      child: Opacity(
        opacity: 0.5,
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.soft,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.line),
          ),
          child: const Text(
            '✨ Probar con foto',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.muted),
          ),
        ),
      ),
    );
  }
}
