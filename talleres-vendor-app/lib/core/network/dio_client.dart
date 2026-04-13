// Dio HTTP 클라이언트 — JWT 자동 주입 인터셉터 포함
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/api_config.dart';
import '../storage/secure_storage.dart';

// DioClient Provider
final dioClientProvider = Provider<DioClient>((ref) {
  final storage = ref.read(secureStorageProvider);

  return DioClient(ApiConfig.baseUrl, storage);
});

// Dio 인스턴스 래핑 클래스
class DioClient {
  late Dio dio;

  DioClient(String baseUrl, SecureStorageService storage) {
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

    // JWT 자동 주입 + 401 처리 인터셉터
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // 저장된 토큰을 Authorization 헤더에 자동 주입
          final token = await storage.read('vendor_token');
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }

          return handler.next(options);
        },
        onError: (error, handler) {
          // 401 처리는 auth_provider에서 관리
          return handler.next(error);
        },
      ),
    );
  }
}
