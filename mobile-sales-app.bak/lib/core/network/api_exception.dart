// API 에러 모델 — HTTP 응답 에러를 구조화 (code 로 es-AR 카피 매핑)
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  // 백엔드 에러 코드 (VENDEDOR_SCOPE_NOT_DEFINED / MOBILE_SESSION_EXPIRED / STORE_SUSPENDED 등)
  final String? code;

  ApiException(this.message, {this.statusCode, this.code});

  @override
  String toString() => 'ApiException($statusCode/$code): $message';
}
