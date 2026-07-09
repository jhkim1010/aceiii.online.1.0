// 매트릭스 컨트롤러 (D-15 port, UI-D2 own-branch cap).
// 웹 VariantsStockVenta 의 quantities Record<`${colorId}-${sizeId}`, number> 모델을 이식.
// 셀 입력은 자지점 available(variant.stock)로 클램프 — over/red 상태 없음(UI-D2).
// ChangeNotifier 로 셀 단위 갱신(포커스 유지) + 순수 로직(단위 테스트 대상).
import 'package:flutter/foundation.dart';
import '../data/stock_dto.dart';

class VariantMatrixController extends ChangeNotifier {
  final List<VariantStock> variants;

  // colorId-sizeId → 수량
  final Map<String, int> _quantities = {};

  VariantMatrixController(this.variants);

  // 매트릭스 셀 키 (colorId-sizeId — 웹 계약과 동일)
  static String keyFor(VariantStock v) => '${v.color.id}-${v.size.id}';

  // 자지점 available (입력 상한 = 셀 cap, UI-D2)
  int availableFor(VariantStock v) => v.stock < 0 ? 0 : v.stock;

  // 현재 셀 수량
  int qtyFor(VariantStock v) => _quantities[keyFor(v)] ?? 0;

  // 수량 설정 — 자지점 available 로 클램프(초과 자체 불가, over/red 제거).
  // 0 이하이면 키 제거(빈 항목 방지).
  void setQty(VariantStock v, int value) {
    final capped = value.clamp(0, availableFor(v));
    final key = keyFor(v);
    if (capped <= 0) {
      _quantities.remove(key);
    } else {
      _quantities[key] = capped;
    }
    notifyListeners();
  }

  // 확정된 수량 맵 (>0 만). cart/suspend 의 variantQuantities 소스.
  Map<String, int> get variantQuantities => Map.unmodifiable(_quantities);

  // 선택 총 수량
  int get selectedTotal => _quantities.values.fold(0, (a, b) => a + b);

  // 선택 총 금액 (단가 × 총 수량 — 매트릭스는 단일 상품)
  double moneyFor(double unitPrice) => unitPrice * selectedTotal;

  // "Añadir al carrito ({n})" 활성 여부 (n>0)
  bool get addEnabled => selectedTotal > 0;
}
