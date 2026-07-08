import 'dart:io' show Platform;

// 앱 전역 설정 — 기본 서버 URL 및 저장 키.
// 개발: 로컬 API. Android 에뮬레이터는 호스트를 10.0.2.2 로, 데스크톱은 localhost 로 접근.
class AppConfig {
  // Android 에뮬레이터에서 Mac 호스트의 localhost 는 10.0.2.2 로 접근.
  // 운영은 https://newapi.coolsistema.com/api
  static const String defaultBaseUrlAndroidEmulator = 'http://10.0.2.2:5002/api';
  static const String defaultBaseUrlDesktop = 'http://localhost:5002/api';
  static const String defaultBaseUrlProd = 'https://newapi.coolsistema.com/api';

  // 플랫폼별 기본 서버 — Android 에뮬레이터만 10.0.2.2, 그 외(macOS/Windows 데스크톱)는 localhost.
  static String get defaultBaseUrl =>
      Platform.isAndroid ? defaultBaseUrlAndroidEmulator : defaultBaseUrlDesktop;

  // secure storage 키
  static const String kBaseUrl = 'base_url';
  static const String kToken = 'auth_token'; // 기기 토큰(Phase 2) 또는 임시 JWT

  // 앱 표시 정보
  static const String appTitle = 'Ventago Despacho';
}
