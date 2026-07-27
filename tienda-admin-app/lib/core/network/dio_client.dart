import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/api_config.dart';
import '../storage/secure_storage.dart';
import 'session_signal.dart';

// Dio 클라이언트 — JWT Bearer 자동 주입 + 401 세션만료 로그아웃.
// 매장 admin 이 호출하는 엔드포인트(dashboards/cash-register/reports/role 등)는
// 모두 JwtAuthGuard(+역할/권한 가드)만 사용 → 브라우저용 x-session-token 은 불필요.
// (SessionGuard 는 웹 전용이며 이 앱의 대상 엔드포인트에는 적용되지 않음)

final dioClientProvider = Provider<Dio>((ref) {
  final storage = ref.read(secureStorageProvider);
  final signal = ref.read(sessionExpiredSignalProvider);

  final dio = Dio(
    BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: ApiConfig.connectTimeout,
      receiveTimeout: ApiConfig.receiveTimeout,
      headers: {'Content-Type': 'application/json'},
    ),
  );

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await storage.read(StorageKeys.token);
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }

        return handler.next(options);
      },
      onError: (error, handler) async {
        // /auth/login 의 401 은 자격증명 오류이지 세션 만료가 아님 → 제외
        final isLoginCall =
            error.requestOptions.path.contains('/auth/login');
        if (error.response?.statusCode == 401 && !isLoginCall) {
          // 토큰만 삭제. 지문 로그인용 자격증명(saved_user/pass)은 반드시 보존
          // → 로그인 화면에서 지문 프롬프트로 즉시 재진입 가능 (deleteAll 금지)
          await storage.delete(StorageKeys.token);
          signal.trigger();
          rootScaffoldMessengerKey.currentState?.showSnackBar(
            const SnackBar(
              content: Text('Sesión expirada. Iniciá sesión de nuevo.'),
              backgroundColor: Color(0xFFe24b4a),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }

        return handler.next(error);
      },
    ),
  );

  return dio;
});
