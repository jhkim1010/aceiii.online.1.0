// Envio Repository — 외주 발송 목록 API 연동
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import 'envio_dto.dart';

// EnvioRepository Provider
final envioRepositoryProvider = Provider<EnvioRepository>((ref) {
  return EnvioRepository(ref.read(dioClientProvider));
});

// 외주 발송 API 연동 레포지토리
class EnvioRepository {
  final DioClient _client;

  EnvioRepository(this._client);

  // 매장별 발송 목록 조회
  Future<List<EnvioDto>> fetchEnvios(
    int storeId, {
    String? status,
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final params = <String, dynamic>{
        'storeId': storeId,
        'page': page,
        'pageSize': pageSize,
      };

      // 상태 필터가 있을 때만 파라미터 추가
      if (status != null) {
        params['status'] = status;
      }

      final response = await _client.dio.get(
        '/vendor-portal/envios',
        queryParameters: params,
      );

      // 응답이 { rows: [...] } 또는 [...] 형식 모두 처리
      final data = response.data;
      final List<dynamic> rows;
      if (data is Map<String, dynamic> && data.containsKey('rows')) {
        rows = data['rows'] as List<dynamic>;
      } else if (data is List) {
        rows = data;
      } else {
        rows = [];
      }

      return rows.map((e) => EnvioDto.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      // DioException을 더 명확한 메시지로 변환
      final message = e.response?.data?['message'] as String? ?? e.message ?? 'Error al cargar envíos';
      throw Exception(message);
    }
  }
}
