// 재고 Repository — GET /mobile/stock/:productId 호출 (Wave 2 계약).
// 백엔드 MemoryCacheService(10s) 가 pool 보호. D-14: STOCK-READ = 매장 전 지점.
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import 'stock_dto.dart';

// 재고 Repository Provider
final stockRepositoryProvider = Provider<StockRepository>((ref) {
  return StockRepository(ref.read(dioClientProvider));
});

// 상품별 재고 조회 (autoDispose family) — 테스트에서 override 가능
final productStockProvider =
    FutureProvider.autoDispose.family<StockResult, int>((ref, productId) {
  return ref.read(stockRepositoryProvider).getStock(productId);
});

class StockRepository {
  final DioClient _client;

  StockRepository(this._client);

  Future<StockResult> getStock(int productId) async {
    try {
      final response = await _client.dio.get('/mobile/stock/$productId');

      return StockResult.fromJson(response.data as Map<String, dynamic>);
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
