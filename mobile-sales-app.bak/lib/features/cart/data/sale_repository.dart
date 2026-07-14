// 판매 Repository — POST /mobile/sales (보류 생성 위임, D-13).
// 카트의 변형(colorId-sizeId) 라인들을 productId 로 그룹핑해 items[] 로 매핑.
// paymentMethods 없음(결제 UI 없음) — 백엔드가 suspended-sale 로만 적재.
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../providers/cart_provider.dart';

// POST /mobile/sales 응답
class SuspendedSaleResult {
  final int suspendedSaleId;
  final String status;

  const SuspendedSaleResult({required this.suspendedSaleId, required this.status});

  factory SuspendedSaleResult.fromJson(Map<String, dynamic> json) => SuspendedSaleResult(
        suspendedSaleId: (json['suspendedSaleId'] as num?)?.toInt() ?? 0,
        status: json['status'] as String? ?? 'en_espera',
      );
}

// 판매 Repository Provider
final saleRepositoryProvider = Provider<SaleRepository>((ref) {
  return SaleRepository(ref.read(dioClientProvider));
});

class SaleRepository {
  final DioClient _client;

  SaleRepository(this._client);

  // 카트 → 보류 생성. 라인들을 productId 로 그룹핑해 items + variantQuantities 구성.
  Future<SuspendedSaleResult> sendToCaja(CartState cart) async {
    final byProduct = <int, _ItemAgg>{};
    for (final line in cart.lines) {
      final agg = byProduct.putIfAbsent(
        line.productId,
        () => _ItemAgg(productId: line.productId, price: line.price),
      );
      agg.quantity += line.quantity;
      agg.variantQuantities[line.variantKey] = line.quantity;
    }

    final items = byProduct.values
        .map((a) => {
              'productId': a.productId,
              'quantity': a.quantity,
              'price': a.price,
              'variantQuantities': a.variantQuantities,
            })
        .toList();

    final subtotal = cart.subtotal;

    try {
      final response = await _client.dio.post(
        '/mobile/sales',
        data: {
          'items': items,
          'subtotal': subtotal,
          'totalAmount': subtotal,
          if (cart.clientName.trim().isNotEmpty) 'notes': cart.clientName.trim(),
        },
      );

      return SuspendedSaleResult.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  ApiException _toApiException(DioException e) {
    final data = e.response?.data;
    String? code;
    String? message;
    if (data is Map) {
      code = (data['code'] ?? data['error'])?.toString();
      message = data['message']?.toString();
    }

    return ApiException(
      message ?? 'Error de conexión',
      statusCode: e.response?.statusCode,
      code: code,
    );
  }
}

// productId 별 집계 헬퍼
class _ItemAgg {
  final int productId;
  final double price;
  int quantity = 0;
  final Map<String, int> variantQuantities = {};

  _ItemAgg({required this.productId, required this.price});
}
