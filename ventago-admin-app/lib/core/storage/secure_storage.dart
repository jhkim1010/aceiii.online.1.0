import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// 보안 저장 키
class StorageKeys {
  static const token = 'admin_access_token';

  // 표시용 + 지문 버튼 노출 판단용. 비밀이 아니다.
  static const savedUser = 'admin_saved_user';

  // [Phase 72-03] 지문 재로그인 자격증명. 원문 비밀번호를 대체한다.
  // 서버가 sha256 해시만 보관하고 revoked_at 으로 언제든 회수할 수 있다.
  static const deviceToken = 'admin_device_token';

  // 이 설치를 식별하는 값. 재등록 시 기기 목록이 중복으로 늘어나지 않게 한다.
  static const deviceId = 'admin_device_id';

  // ── 폐기된 키 ──────────────────────────────────────────────────────────────
  // [Phase 72-03] superadmin 의 **원문 비밀번호**를 무기한 보관하던 키.
  // 더 이상 쓰지 않으며, 이미 배포된 단말에서 지우기 위해서만 남겨둔다.
  // 코드에서 안 쓰게 바꾸는 것만으로는 단말에 남은 원문이 사라지지 않는다.
  static const legacySavedPass = 'admin_saved_pass';
}

final secureStorageProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

class SecureStorageService {
  // macOS 비-sandbox 빌드는 data-protection keychain 접근에 서명 entitlement 가
  // 필요해 write 시 errSecMissingEntitlement(-34018) 로 실패한다.
  // 레거시 file-based keychain 을 사용하도록 하여 회피.
  //
  // [Phase 72-03] 이 우회는 의도적이며 그대로 둔다. entitlement 없이 true 로 되돌리면
  // 저장이 통째로 깨져 앱에 로그인조차 못 한다. 대신 이 저장소에 담기는 **내용**을 줄였다 —
  // 이제 여기 남는 자격증명은 원문 비밀번호가 아니라 서버에서 회수 가능한 기기 토큰이다.
  // (근본 해결은 앱 서명/entitlement 정비이며 별도 과제로 남는다.)
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

  /// [Phase 72-03] 기존 설치분 정리 — 앱 시작 시 1회.
  ///
  /// 업데이트만으로는 이미 저장된 원문 비밀번호가 사라지지 않는다. 코드에서 읽지 않게
  /// 바꾸는 것과 단말에서 없어지는 것은 다른 문제다. 그래서 시작 시 명시적으로 지운다.
  Future<void> purgeLegacyCredentials() async {
    final legacy = await read(StorageKeys.legacySavedPass);
    if (legacy == null) return;

    await delete(StorageKeys.legacySavedPass);
  }

  /// 이 설치의 기기 식별자. 없으면 만들어 저장한다.
  /// 비밀이 아니라 식별자다 — 그래도 예측 가능한 값을 쓰지 않도록 secure random 으로 만든다.
  Future<String> deviceId() async {
    final existing = await read(StorageKeys.deviceId);
    if (existing != null && existing.isNotEmpty) return existing;

    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    final id = base64Url.encode(bytes).replaceAll('=', '');
    await write(StorageKeys.deviceId, id);

    return id;
  }
}
