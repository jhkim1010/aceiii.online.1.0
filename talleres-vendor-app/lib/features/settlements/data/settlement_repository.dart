// 정산 Repository — 정산 목록 API 연동
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import 'settlement_dto.dart';

// SettlementRepository Provider
final settlementRepositoryProvider = Provider<SettlementRepository>((ref) {
  return SettlementRepository(ref.read(dioClientProvider));
});

// 정산 API 연동 레포지토리 — 읽기 전용
class SettlementRepository {
  final DioClient _client;

  SettlementRepository(this._client);

  // 매장별 정산 목록 조회 — 기간 필터 선택적 적용
  Future<List<SettlementDto>> fetchSettlements(
    int storeId, {
    String? from,
    String? to,
  }) async {
    try {
      final params = <String, dynamic>{'storeId': storeId};

      // 기간 필터가 있을 때만 파라미터 추가
      if (from != null) {
        params['from'] = from;
      }
      if (to != null) {
        params['to'] = to;
      }

      final response = await _client.dio.get(
        '/vendor-portal/settlements',
        queryParameters: params,
      );

      final data = response.data;
      final List<dynamic> rows;

      if (data is List) {
        rows = data;
      } else if (data is Map<String, dynamic> && data.containsKey('rows')) {
        rows = data['rows'] as List<dynamic>;
      } else {
        rows = [];
      }

      return rows
          .map((e) => SettlementDto.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      final message = e.response?.data?['message'] as String? ??
          e.message ??
          'Error al cargar liquidaciones';

      throw Exception(message);
    }
  }
}
