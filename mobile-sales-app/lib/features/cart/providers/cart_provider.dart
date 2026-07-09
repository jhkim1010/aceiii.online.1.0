// 카트 Provider — 변형(colorId-sizeId) 단위 라인 관리. [UI-D2] 모든 라인은 자지점,
// 라인 수량은 자지점 available 한도로만 증가(traslado/타지점 배분 없음).
// suspended 판매(POST /mobile/sales)로 보낼 때 productId 로 그룹핑해 items 로 매핑한다.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// 카트 라인 = 상품 + 색상/talle 변형 1건 (S4 Comanda 라인 = 변형 단위 표시)
@immutable
class CartLine {
  final int productId;
  final String productName;
  final double price;
  final int? colorId;
  final String colorName;
  final int? colorHex;
  final int? sizeId;
  final String sizeName;
  final int quantity;
  // 자지점 available (라인 stepper 상한 — UI-D2)
  final int ownAvailable;

  const CartLine({
    required this.productId,
    required this.productName,
    required this.price,
    required this.colorId,
    required this.colorName,
    required this.colorHex,
    required this.sizeId,
    required this.sizeName,
    required this.quantity,
    required this.ownAvailable,
  });

  // colorId-sizeId 키 (variantQuantities 매핑 키 = 웹 계약과 동일)
  String get variantKey => '$colorId-$sizeId';

  double get subtotal => price * quantity;

  CartLine copyWith({int? quantity}) => CartLine(
        productId: productId,
        productName: productName,
        price: price,
        colorId: colorId,
        colorName: colorName,
        colorHex: colorHex,
        sizeId: sizeId,
        sizeName: sizeName,
        quantity: quantity ?? this.quantity,
        ownAvailable: ownAvailable,
      );
}

// 카트 전체 상태 (라인들 + 선택 고객명)
@immutable
class CartState {
  final List<CartLine> lines;
  final String clientName;

  const CartState({this.lines = const [], this.clientName = ''});

  int get totalUnits => lines.fold(0, (sum, l) => sum + l.quantity);
  double get subtotal => lines.fold(0.0, (sum, l) => sum + l.subtotal);
  bool get isEmpty => lines.isEmpty;

  CartState copyWith({List<CartLine>? lines, String? clientName}) => CartState(
        lines: lines ?? this.lines,
        clientName: clientName ?? this.clientName,
      );
}

// 카트 Notifier Provider
final cartProvider = NotifierProvider<CartNotifier, CartState>(CartNotifier.new);

class CartNotifier extends Notifier<CartState> {
  @override
  CartState build() => const CartState();

  // 매트릭스 선택 라인들을 카트에 병합 (같은 변형은 수량 합산, 자지점 상한 클램프)
  void mergeLines(List<CartLine> newLines) {
    final map = {for (final l in state.lines) l.variantKey: l};
    for (final incoming in newLines) {
      final existing = map[incoming.variantKey];
      if (existing == null) {
        map[incoming.variantKey] = incoming;
      } else {
        final merged = (existing.quantity + incoming.quantity)
            .clamp(0, incoming.ownAvailable);
        map[incoming.variantKey] = existing.copyWith(quantity: merged);
      }
    }
    state = state.copyWith(
      lines: map.values.where((l) => l.quantity > 0).toList(),
    );
  }

  // 라인 수량 증가 (자지점 available 한도 — 초과 시 false 반환 → "Sin disponible" 토스트)
  bool increment(String variantKey) {
    var changed = false;
    final lines = state.lines.map((l) {
      if (l.variantKey == variantKey && l.quantity < l.ownAvailable) {
        changed = true;

        return l.copyWith(quantity: l.quantity + 1);
      }

      return l;
    }).toList();
    if (changed) {
      state = state.copyWith(lines: lines);
    }

    return changed;
  }

  // 라인 수량 감소 (0 이면 라인 제거)
  void decrement(String variantKey) {
    final lines = <CartLine>[];
    for (final l in state.lines) {
      if (l.variantKey == variantKey) {
        final q = l.quantity - 1;
        if (q > 0) {
          lines.add(l.copyWith(quantity: q));
        }
      } else {
        lines.add(l);
      }
    }
    state = state.copyWith(lines: lines);
  }

  void removeLine(String variantKey) {
    state = state.copyWith(
      lines: state.lines.where((l) => l.variantKey != variantKey).toList(),
    );
  }

  void setClientName(String name) => state = state.copyWith(clientName: name);

  void clear() => state = const CartState();
}
