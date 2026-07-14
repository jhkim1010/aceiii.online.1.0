// 카탈로그 데이터 전송 모델 — GET /mobile/catalog 계약 (Wave 2)
// 응답: { items:[{ productId, name, sku, price, stockByBranch:{[branchId]:n} }], total, cachedAt }
import 'package:flutter/foundation.dart';

// 카탈로그 상품 1건
@immutable
class CatalogItem {
  final int productId;
  final String name;
  final String sku;
  final double price;
  // 지점별 재고 분포 (vendedor 는 자기 SELL 지점 1개만 채워짐)
  final Map<int, int> stockByBranch;

  const CatalogItem({
    required this.productId,
    required this.name,
    required this.sku,
    required this.price,
    required this.stockByBranch,
  });

  // 자기 지점 재고 (stockByBranch 의 첫 값 = vendedor SELL 지점). 값 없으면 0.
  int get ownStock =>
      stockByBranch.isEmpty ? 0 : stockByBranch.values.first;

  factory CatalogItem.fromJson(Map<String, dynamic> json) => CatalogItem(
        productId: (json['productId'] as num).toInt(),
        name: json['name'] as String? ?? '',
        sku: json['sku'] as String? ?? '',
        price: (json['price'] as num?)?.toDouble() ?? 0,
        stockByBranch: parseStockByBranch(json['stockByBranch']),
      );
}

// JSON object 키는 문자열이므로 int 로 파싱 (stockByBranch/stockByVariant 공용)
Map<int, int> parseStockByBranch(dynamic value) {
  final map = <int, int>{};
  if (value is Map) {
    value.forEach((k, v) {
      final ki = k is num ? k.toInt() : int.tryParse(k.toString());
      final vi = v is num ? v.toInt() : int.tryParse(v.toString());
      if (ki != null && vi != null) {
        map[ki] = vi;
      }
    });
  }

  return map;
}

// GET /mobile/catalog 응답
@immutable
class CatalogResult {
  final List<CatalogItem> items;
  final int total;
  final String cachedAt;

  const CatalogResult({
    required this.items,
    required this.total,
    required this.cachedAt,
  });

  factory CatalogResult.fromJson(Map<String, dynamic> json) => CatalogResult(
        items: (json['items'] as List<dynamic>? ?? [])
            .map((e) => CatalogItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        total: (json['total'] as num?)?.toInt() ?? 0,
        cachedAt: json['cachedAt'] as String? ?? '',
      );
}
