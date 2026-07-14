// 매트릭스 컨트롤러 단위 테스트 (D-15 / UI-D2).
// Behavior:
//  1. color C1 size S2 셀에 3 입력 → variantQuantities {'C1id-S2id': 3}
//  2. 입력이 자지점 available 를 초과하면 클램프(over/red 없음, UI-D2)
//  3. 각 셀은 자지점 재고(stock)와 otras 합계(read-only)를 노출
//  4. 선택 총합 0 이면 addEnabled=false (Añadir al carrito 비활성)
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_sales_app/features/product/data/stock_dto.dart';
import 'package:mobile_sales_app/features/product/providers/variant_matrix_provider.dart';

VariantStock _v({
  required int colorId,
  required int sizeId,
  required int ownStock,
  Map<int, int>? byBranch,
}) {
  return VariantStock(
    color: VariantLabel(id: colorId, name: 'C$colorId'),
    size: VariantLabel(id: sizeId, name: 'S$sizeId'),
    stock: ownStock,
    // 자기 지점(5) + 타지점(6) 분포 — byBranch 미지정 시 자기 지점만
    stockByBranch: byBranch ?? {5: ownStock},
  );
}

void main() {
  group('VariantMatrixController', () {
    test('1. setQty keys by colorId-sizeId → variantQuantities', () {
      final c1s2 = _v(colorId: 1, sizeId: 2, ownStock: 10);
      final controller = VariantMatrixController([c1s2]);

      controller.setQty(c1s2, 3);

      expect(controller.variantQuantities, {'1-2': 3});
    });

    test('2. input is capped at own-branch available (clamp, no over)', () {
      final c1s1 = _v(colorId: 1, sizeId: 1, ownStock: 5, byBranch: {5: 5, 6: 99});
      final controller = VariantMatrixController([c1s1]);

      // 자지점 5, 타지점 99 여도 자지점 상한(5)으로 클램프
      controller.setQty(c1s1, 8);

      expect(controller.variantQuantities['1-1'], 5);
      expect(controller.availableFor(c1s1), 5);
    });

    test('3. cell exposes own stock (bold source) + otras total (read-only)', () {
      final c1s1 = _v(colorId: 1, sizeId: 1, ownStock: 20, byBranch: {5: 20, 6: 5, 7: 3});

      // 자지점 20, otras = 5 + 3 = 8
      expect(c1s1.stock, 20);
      expect(c1s1.otras, 8);
    });

    test('3b. qty 0 removes key (no zero entries)', () {
      final c1s1 = _v(colorId: 1, sizeId: 1, ownStock: 10);
      final controller = VariantMatrixController([c1s1]);

      controller.setQty(c1s1, 4);
      controller.setQty(c1s1, 0);

      expect(controller.variantQuantities.containsKey('1-1'), false);
      expect(controller.selectedTotal, 0);
    });

    test('4. addEnabled false when total 0, true when >0', () {
      final c1s1 = _v(colorId: 1, sizeId: 1, ownStock: 10);
      final controller = VariantMatrixController([c1s1]);

      expect(controller.addEnabled, false);

      controller.setQty(c1s1, 2);

      expect(controller.addEnabled, true);
      expect(controller.selectedTotal, 2);
    });

    test('4b. depleted variant (own stock 0) cannot receive qty', () {
      final depleted = _v(colorId: 2, sizeId: 1, ownStock: 0, byBranch: {5: 0, 6: 4});
      final controller = VariantMatrixController([depleted]);

      controller.setQty(depleted, 3);

      // 자지점 0 → 클램프 0, 카트 담기 불가
      expect(controller.variantQuantities.containsKey('2-1'), false);
      expect(controller.availableFor(depleted), 0);
    });
  });
}
