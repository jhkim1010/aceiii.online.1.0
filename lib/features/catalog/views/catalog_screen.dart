// S2 Catálogo (/catalog) — 검색 + 카테고리 pill + 상품 카드(stock pill).
// stock pill: ok≥11 green / low 1–10 amber / out=0 grey "Sin stock" (자지점 수치, D-14).
// out(0) 카드도 상세 진입 허용(타지점 otras 조회). 하단 카트 바(카트 있을 때만).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/format/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../cart/providers/cart_provider.dart';
import '../data/catalog_dto.dart';
import '../providers/catalog_provider.dart';

class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen({super.key});

  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // 검색어 디바운스 (350ms) → catalogSearchProvider 갱신 → 목록 재조회
  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(catalogSearchProvider.notifier).set(value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final listAsync = ref.watch(catalogListProvider);
    final cart = ref.watch(cartProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () => context.pop(),
        ),
        title: const Text('Buscar producto', style: TextStyle(fontSize: 17)),
      ),
      body: Column(
        children: [
          // 검색바
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search, color: AppColors.muted),
                hintText: 'Buscar por nombre o código…',
                isDense: true,
              ),
            ),
          ),
          // 카테고리 pill (Wave 2 백엔드에 카테고리 목록 소스 없음 → "Todos" 만.
          // 실제 카테고리 필터는 /mobile/categories 엔드포인트 추가 시 슬롯인)
          const _CategoryPills(),
          // 상품 리스트
          Expanded(
            child: listAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _ErrorState(
                message: 'No se pudo cargar el catálogo.',
                onRetry: () => ref.invalidate(catalogListProvider),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return const Center(
                    child: Text('Sin resultados',
                        style: TextStyle(color: AppColors.muted)),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _ProductCard(item: items[i]),
                );
              },
            ),
          ),
        ],
      ),
      // 하단 카트 바 (카트 있을 때만)
      bottomNavigationBar:
          cart.isEmpty ? null : _CartBar(units: cart.totalUnits, total: cart.subtotal),
    );
  }
}

// 카테고리 pill 스트립 (MVP: "Todos" 활성만)
class _CategoryPills extends StatelessWidget {
  const _CategoryPills();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: const [
          _Pill(label: 'Todos', active: true),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final bool active;

  const _Pill({required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: active ? AppColors.navy : AppColors.soft,
        borderRadius: BorderRadius.circular(20),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: active ? Colors.white : AppColors.ink,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// 상품 카드 — 썸네일 placeholder + 이름/코드/가격 + stock pill
class _ProductCard extends StatelessWidget {
  final CatalogItem item;

  const _ProductCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final stock = item.ownStock;

    return Material(
      color: AppColors.bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          // out(0) 이어도 상세 진입 허용(otras 조회). 토스트로 자지점 무재고 안내.
          if (stock == 0) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(const SnackBar(
                content: Text('Sin stock en esta sucursal'),
              ));
          }
          context.push('/product/${item.productId}', extra: item);
        },
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              // 썸네일 placeholder (이미지 URL 은 Wave 2 catalog 계약에 미포함)
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.soft,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: const Text('🏷️', style: TextStyle(fontSize: 24)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.sku,
                      style: const TextStyle(fontSize: 11, color: AppColors.muted),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      formatMoney(item.price),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                        fontFeatures: kTabularFigures,
                      ),
                    ),
                  ],
                ),
              ),
              _StockPill(stock: stock),
            ],
          ),
        ),
      ),
    );
  }
}

// stock pill — ok≥11 green / low 1–10 amber / out=0 grey
class _StockPill extends StatelessWidget {
  final int stock;

  const _StockPill({required this.stock});

  @override
  Widget build(BuildContext context) {
    late final Color bg;
    late final Color fg;
    late final String label;
    if (stock == 0) {
      bg = AppColors.soft;
      fg = AppColors.muted;
      label = 'Sin stock';
    } else if (stock <= 10) {
      bg = AppColors.amberSoft;
      fg = AppColors.goldDark;
      label = '$stock u · bajo';
    } else {
      bg = AppColors.greenSoft;
      fg = AppColors.green;
      label = '$stock u';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          fontFeatures: kTabularFigures,
        ),
      ),
    );
  }
}

// 하단 카트 바
class _CartBar extends StatelessWidget {
  final int units;
  final double total;

  const _CartBar({required this.units, required this.total});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Material(
          color: AppColors.navy,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => context.push('/comanda'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  const Text('🛒', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Text(
                    '$units u · ${formatMoney(total)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      fontFeatures: kTabularFigures,
                    ),
                  ),
                  const Spacer(),
                  const Text('Ver ›',
                      style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(message, style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Reintentar')),
        ],
      ),
    );
  }
}
