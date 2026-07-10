// API 설정 — 기본값 = 운영 서버(항상 운영 사용). 개발 시에만
// --dart-define=BASE_URL=http://localhost:5002/api 로 덮어쓴다.
class ApiConfig {
  static const String baseUrl = String.fromEnvironment(
    'BASE_URL',
    defaultValue: 'https://newapi.coolsistema.com/api',
  );

  static String get displayHost => Uri.parse(baseUrl).host;

  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 15);
}
