// 매트릭스 컨트롤러 (RED 스텁) — GREEN 단계에서 구현.
import 'package:flutter/foundation.dart';
import '../data/stock_dto.dart';

class VariantMatrixController extends ChangeNotifier {
  final List<VariantStock> variants;

  VariantMatrixController(this.variants);

  // colorId-sizeId 키 → 수량 (미구현)
  Map<String, int> get variantQuantities => const {};

  void setQty(VariantStock variant, int value) {
    // TODO(GREEN): 구현
  }
}
