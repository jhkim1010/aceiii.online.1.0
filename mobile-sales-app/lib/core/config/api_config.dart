// API 설정 — 환경별 URL과 타임아웃 관리
class ApiConfig {
  // --dart-define=BASE_URL 로 빌드 시 주입 가능
  // 기본값: 로컬 개발 서버 (운영: https://newapi.coolsistema.com/api)
  static const String baseUrl = String.fromEnvironment(
    'BASE_URL',
    defaultValue: 'http://localhost:5002/api',
  );

  // 로그인 화면에 읽기전용으로 표시할 서버 라벨 (S0, 사용자 입력 불필요)
  static String get displayHost => Uri.parse(baseUrl).host;

  // 연결 타임아웃
  static const Duration connectTimeout = Duration(seconds: 10);

  // 응답 수신 타임아웃
  static const Duration receiveTimeout = Duration(seconds: 15);
}
