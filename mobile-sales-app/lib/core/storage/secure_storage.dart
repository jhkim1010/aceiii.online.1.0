// 보안 저장소 — OS 키체인/키스토어에 JWT 토큰 저장
// T-37-12 완화: 토큰은 flutter_secure_storage 에만 저장, SharedPreferences 금지.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// 저장 키 상수 (문자열 오타 방지)
class StorageKeys {
  // JWT accessToken — Authorization: Bearer 헤더에 주입
  static const String mobileToken = 'mobile_token';

  // mobile_sessions.active_session_token — x-mobile-session-token 헤더에 주입
  static const String mobileSessionToken = 'mobile_session_token';

  // 마지막 선택 지점 (D-10, 재로그인 시 복원)
  static const String lastBranchId = 'last_branch_id';
}

// 보안 저장소 서비스 Provider
final secureStorageProvider = Provider<SecureStorageService>((ref) => SecureStorageService());

// flutter_secure_storage 래핑 클래스
class SecureStorageService {
  final _storage = const FlutterSecureStorage();

  // 값 읽기
  Future<String?> read(String key) => _storage.read(key: key);

  // 값 쓰기
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  // 특정 키 삭제
  Future<void> delete(String key) => _storage.delete(key: key);

  // 전체 삭제 (로그아웃 / 세션 만료 시 사용)
  Future<void> deleteAll() => _storage.deleteAll();
}
