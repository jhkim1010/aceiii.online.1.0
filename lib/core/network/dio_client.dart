// Dio HTTP 클라이언트 — JWT + x-mobile-session-token 자동 주입 + 401 세션만료 처리
// Phase 17(talleres-vendor-app)의 pass-through 인터셉터와 달리, 여기서 401
// MOBILE_SESSION_EXPIRED 를 잡아 토큰을 지우고 /login 으로 보낸다 (MOBILE-C-07).
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/api_config.dart';
import '../storage/secure_storage.dart';
import 'session_signal.dart';

// 세션 만료로 판정할 백엔드 에러 코드들
const _sessionExpiredCodes = {
  'MOBILE_SESSION_EXPIRED',
  'SESSION_EXPIRED',
  'INVALID_MOBILE_SESSION',
};

// DioClient Provider
final dioClientProvider = Provider<DioClient>((ref) {
  final storage = ref.read(secureStorageProvider);
  final signal = ref.read(sessionExpiredSignalProvider);

  return DioClient(ApiConfig.baseUrl, storage, signal);
});

// Dio 인스턴스 래핑 클래스
class DioClient {
  late Dio dio;
  final SecureStorageService _storage;
  final SessionExpiredSignal _sessionSignal;

  DioClient(String baseUrl, this._storage, this._sessionSignal) {
    dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: ApiConfig.connectTimeout,
        receiveTimeout: ApiConfig.receiveTimeout,
        headers: {
          'Content-Type': 'application/json',
        },
      ),
    );

    // JWT + 모바일 세션 토큰 주입 + 401 세션만료 처리 인터셉터
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // accessToken → Authorization 헤더
          final token = await _storage.read(StorageKeys.mobileToken);
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }

          // mobileSessionToken → x-mobile-session-token 헤더 (MobileScopeGuard 검증용)
          final sessionToken = await _storage.read(StorageKeys.mobileSessionToken);
          if (sessionToken != null && sessionToken.isNotEmpty) {
            options.headers['x-mobile-session-token'] = sessionToken;
          }

          return handler.next(options);
        },
        onError: (error, handler) async {
          // 401 + 세션만료 코드 → 저장소 초기화 + /login redirect + 토스트
          if (error.response?.statusCode == 401 && _isSessionExpired(error)) {
            await _handleSessionExpired();
          }

          return handler.next(error);
        },
      ),
    );
  }

  // 응답 body 의 code 필드가 세션만료 계열인지 판정
  bool _isSessionExpired(DioException error) {
    final data = error.response?.data;
    if (data is Map) {
      final code = (data['code'] ?? data['error'] ?? data['message'])?.toString();
      if (code != null && _sessionExpiredCodes.contains(code)) {
        return true;
      }
    }

    return false;
  }

  // 세션 만료 공통 처리: 토큰 삭제 → 신호 발생 → 토스트 (MOBILE-C-07)
  Future<void> _handleSessionExpired() async {
    await _storage.deleteAll();
    _sessionSignal.trigger();
    rootScaffoldMessengerKey.currentState?.showSnackBar(
      const SnackBar(
        content: Text('Tu sesión se cerró porque ingresaste en otro dispositivo.'),
        backgroundColor: Color(0xFFe24b4a),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
