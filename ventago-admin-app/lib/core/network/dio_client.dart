import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/api_config.dart';
import '../storage/secure_storage.dart';
import '../tenant/acting_store.dart';
import 'session_signal.dart';

// Dio 클라이언트 — JWT Bearer 자동 주입 + 401 세션만료 로그아웃.
// superadmin 콘솔 엔드포인트는 JWT 만 요구(SessionGuard 없음) → x-session-token 불필요.

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

        // [Phase 67-C] 매장 대행 중이면 그 매장으로 요청한다.
        // ref.watch 가 아니라 read 를 쓴다 — watch 하면 대행 매장이 바뀔 때마다
        // Dio 인스턴스가 재생성돼 인터셉터가 중복 등록된다.
        final acting = ref.read(actingStoreProvider);
        if (acting != null) {
          options.headers['X-Store-Id'] = acting.id.toString();
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
