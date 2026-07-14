// 제품 대표 이미지 URL — 공용 엔드포인트 /products/:id/images (JWT 인증).
// 카탈로그 DTO 에 이미지가 없어 productId 로 별도 조회한다. 없으면 null.
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/api_config.dart';
import '../../../core/network/dio_client.dart';

// productId → 대표(Principal) 사진의 완전한 URL. 없으면 null.
final productImageUrlProvider =
    FutureProvider.autoDispose.family<String?, int>((ref, productId) async {
  final client = ref.read(dioClientProvider);
  try {
    final res = await client.dio.get('/products/$productId/images');
    final data = res.data as Map<String, dynamic>?;
    final urls = (data?['imageUrls'] as List?) ?? const [];
    final first =
        urls.isNotEmpty ? urls.first?.toString() : data?['imageUrl']?.toString();
    if (first == null || first.isEmpty) return null;

    return first.startsWith('http') ? first : '${ApiConfig.baseUrl}/minio/$first';
  } on DioException {
    return null;
  }
});
