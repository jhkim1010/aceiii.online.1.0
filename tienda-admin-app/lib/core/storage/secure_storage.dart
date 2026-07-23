import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// 보안 저장 키
class StorageKeys {
  static const token = 'admin_access_token';
  // 지문 로그인용 자격증명 보관 (Android Keystore/Keychain 백업)
  static const savedUser = 'admin_saved_user';
  static const savedPass = 'admin_saved_pass';
}

final secureStorageProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

class SecureStorageService {
  // macOS 비-sandbox 빌드는 data-protection keychain 접근에 서명 entitlement 가
  // 필요해 write 시 errSecMissingEntitlement(-34018) 로 실패한다.
  // 레거시 file-based keychain 을 사용하도록 하여 회피.
  final _storage = const FlutterSecureStorage(
    mOptions: MacOsOptions(
      useDataProtectionKeyChain: false,
    ),
  );

  Future<String?> read(String key) => _storage.read(key: key);

  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  Future<void> delete(String key) => _storage.delete(key: key);

  Future<void> deleteAll() => _storage.deleteAll();
}
