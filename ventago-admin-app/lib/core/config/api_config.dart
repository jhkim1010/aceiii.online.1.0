// API 설정 — 환경별 URL. --dart-define=BASE_URL 로 빌드 시 주입.
// 기본값 로컬 개발(운영: https://newapi.coolsistema.com/api).
class ApiConfig {
  static const String baseUrl = String.fromEnvironment(
    'BASE_URL',
    defaultValue: 'http://localhost:5002/api',
  );

  static String get displayHost => Uri.parse(baseUrl).host;

  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 15);
}
