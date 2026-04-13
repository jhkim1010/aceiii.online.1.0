// 보안 저장소 — OS 키체인/키스토어에 JWT 토큰 저장
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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

  // 전체 삭제 (로그아웃 시 사용)
  Future<void> deleteAll() => _storage.deleteAll();
}
