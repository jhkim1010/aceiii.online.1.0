// 인증 Repository — POST /mobile/auth/login, GET /mobile/me 호출 (Wave 1 계약)
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/device/device_fingerprint.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/network/session_signal.dart';
import '../../../core/storage/secure_storage.dart';
import 'auth_dto.dart';

// 인증 Repository Provider
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    ref.read(dioClientProvider),
    ref.read(secureStorageProvider),
    ref.read(deviceFingerprintProvider),
    ref.read(sessionExpiredSignalProvider),
  );
});

// 인증 API 호출 클래스
class AuthRepository {
  final DioClient _client;
  final SecureStorageService _storage;
  final DeviceFingerprintService _fingerprint;
  final SessionExpiredSignal _sessionSignal;

  AuthRepository(this._client, this._storage, this._fingerprint, this._sessionSignal);

  // Usuario + 암호 로그인 (2026-07-14: PIN → users.password 단일 인증)
  Future<MobileLoginResponse> login({
    required String usuario,
    required String password,
    int? selectedBranchId,
  }) async {
    try {
      final deviceFingerprint = await _fingerprint.getFingerprint();
      final response = await _client.dio.post(
        '/mobile/auth/login',
        data: MobileLoginRequest(
          usuario: usuario,
          password: password,
          deviceFingerprint: deviceFingerprint,
        ).toJson(),
      );

      final result = MobileLoginResponse.fromJson(response.data as Map<String, dynamic>);

      // T-37-12: 토큰은 secure storage 에만 저장 (SharedPreferences 금지)
      await _storage.write(StorageKeys.mobileToken, result.accessToken);
      await _storage.write(StorageKeys.mobileSessionToken, result.mobileSessionToken);

      // 선택 지점 기억 (D-10): 명시 선택 우선, 없으면 scope 단일 지점
      final branchToRemember = selectedBranchId ??
          (result.user.scopeBranchIds.length == 1 ? result.user.scopeBranchIds.first : null);
      if (branchToRemember != null) {
        await _storage.write(StorageKeys.lastBranchId, branchToRemember.toString());
      }

      // 로그인 성공 → 이전 세션 만료 신호 초기화
      _sessionSignal.reset();

      return result;
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  // 저장된 토큰으로 현재 사용자 정보 조회 (앱 시작 시 scope 복원)
  Future<MobileUser> getMe() async {
    try {
      final response = await _client.dio.get('/mobile/me');

      return MobileUser.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  // 마지막 선택 지점 읽기 (로그인 화면 기본값)
  Future<int?> readLastBranchId() async {
    final raw = await _storage.read(StorageKeys.lastBranchId);

    return raw == null ? null : int.tryParse(raw);
  }

  // 로그아웃 — 저장소 초기화
  Future<void> logout() => _storage.deleteAll();

  // DioException → ApiException (code + message 보존, es-AR 카피 매핑용)
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
