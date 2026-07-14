// 재고 데이터 전송 모델 — GET /mobile/stock/:productId 계약 (Wave 2)
// 응답: { productId, stockByVariant:[{ color:{id,name}, size:{id,name}, stock, stockByBranch:{[branchId]:n} }], cachedAt }
// stock = 자기 지점(SELL) 재고(백엔드 계산). stockByBranch = 매장 전 지점(D-14 STOCK-READ).
import 'package:flutter/foundation.dart';
import '../../catalog/data/catalog_dto.dart' show parseStockByBranch;

// color/size 라벨 (id + name)
@immutable
class VariantLabel {
  final int? id;
  final String? name;

  const VariantLabel({this.id, this.name});

  factory VariantLabel.fromJson(dynamic json) {
    if (json is Map) {
      return VariantLabel(
        id: (json['id'] as num?)?.toInt(),
        name: json['name'] as String?,
      );
    }

    return const VariantLabel();
  }
}

// 변형(color×size)별 재고
@immutable
class VariantStock {
  final VariantLabel color;
  final VariantLabel size;
  // 자기 지점(SELL) 재고 = 매트릭스 입력 상한(UI-D2 cap)
  final int stock;
  // 매장 전 지점 분포
  final Map<int, int> stockByBranch;

  const VariantStock({
    required this.color,
    required this.size,
    required this.stock,
    required this.stockByBranch,
  });

  // 타지점 합계(otras) = 전 지점 합 − 자기 지점. read-only 비교 표시용.
  int get otras {
    final total = stockByBranch.values.fold(0, (a, b) => a + b);
    final result = total - stock;

    return result < 0 ? 0 : result;
  }

  // 물리 재고 전무(자+타 모두 0) → out 셀(dash + 비활성)
  bool get isOut => stock <= 0 && otras <= 0;

  factory VariantStock.fromJson(Map<String, dynamic> json) => VariantStock(
        color: VariantLabel.fromJson(json['color']),
        size: VariantLabel.fromJson(json['size']),
        stock: (json['stock'] as num?)?.toInt() ?? 0,
        stockByBranch: parseStockByBranch(json['stockByBranch']),
      );
}

// GET /mobile/stock/:productId 응답
@immutable
class StockResult {
  final int productId;
  final List<VariantStock> stockByVariant;
  final String cachedAt;

  const StockResult({
    required this.productId,
    required this.stockByVariant,
    required this.cachedAt,
  });

  factory StockResult.fromJson(Map<String, dynamic> json) => StockResult(
        productId: (json['productId'] as num?)?.toInt() ?? 0,
        stockByVariant: (json['stockByVariant'] as List<dynamic>? ?? [])
            .map((e) => VariantStock.fromJson(e as Map<String, dynamic>))
            .toList(),
        cachedAt: json['cachedAt'] as String? ?? '',
      );
}
