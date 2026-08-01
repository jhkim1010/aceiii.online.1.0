// 인증 Repository — vendor-portal 인증 API 호출
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';

// 인증 Repository Provider
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final dioClient = ref.read(dioClientProvider);

  return AuthRepository(dioClient);
});

// 인증 API 호출 클래스
class AuthRepository {
  final DioClient _client;

  AuthRepository(this._client);

  // 전화번호 + PIN(+선택 storeId)으로 로그인 — JWT 토큰 + 매장 목록 반환.
  // 동일 PIN 이 2개 이상 매장에서 통과하면 storeId 없이 호출 시
  // requiresStoreSelection=true 응답(토큰 미발급)이 온다 — storeId 를 실어 재호출한다 (R3/CR-03)
  Future<Map<String, dynamic>> login(String phone, String pin, {int? storeId}) async {
    try {
      final response = await _client.dio.post(
        '/vendor-portal/auth/login',
        data: {
          'phone': phone,
          'pin': pin,
          if (storeId != null) 'storeId': storeId,
        },
      );

      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      final message = (e.response?.data as Map<String, dynamic>?)?['message'] as String?;
      throw ApiException(
        message ?? 'Error de conexión',
        statusCode: e.response?.statusCode,
      );
    }
  }

  // 저장된 토큰으로 현재 사용자 정보 조회
  Future<Map<String, dynamic>> getMe() async {
    try {
      final response = await _client.dio.get('/vendor-portal/auth/me');

      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      final message = (e.response?.data as Map<String, dynamic>?)?['message'] as String?;
      throw ApiException(
        message ?? 'Error',
        statusCode: e.response?.statusCode,
      );
    }
  }
}
