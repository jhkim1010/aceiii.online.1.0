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

  // 전화번호 + PIN으로 로그인 — JWT 토큰 + 매장 목록 반환
  Future<Map<String, dynamic>> login(String phone, String pin) async {
    try {
      final response = await _client.dio.post(
        '/vendor-portal/auth/login',
        data: {
          'phone': phone,
          'pin': pin,
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
