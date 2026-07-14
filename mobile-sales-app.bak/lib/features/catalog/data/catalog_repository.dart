// 카탈로그 Repository — GET /mobile/catalog 호출 (Wave 2 계약)
// 백엔드 MemoryCacheService(60s) 가 1차 방어선. 클라이언트는 in-memory lastFetch 캐시만
// (Hive/sqflite 미사용 — UI-SPEC §4 오프라인 규칙).
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import 'catalog_dto.dart';

// 카탈로그 Repository Provider
final catalogRepositoryProvider = Provider<CatalogRepository>((ref) {
  return CatalogRepository(ref.read(dioClientProvider));
});

class CatalogRepository {
  final DioClient _client;

  CatalogRepository(this._client);

  // 상품 목록 조회 — 이름/코드 검색 + 카테고리 + 페이지네이션 (pageSize 최대 50)
  Future<CatalogResult> fetchCatalog({
    String? search,
    int? categoryId,
    int offset = 0,
    int limit = 50,
  }) async {
    try {
      final response = await _client.dio.get(
        '/mobile/catalog',
        queryParameters: {
          if (search != null && search.isNotEmpty) 'search': search,
          'categoryId': ?categoryId,
          'offset': offset,
          'limit': limit,
        },
      );

      return CatalogResult.fromJson(response.data as Map<String, dynamic>);
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
