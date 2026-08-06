import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/dio_client.dart';
import '../../core/storage/secure_storage.dart';

class AuthUser {
  final String? name;
  final List<String> roles;

  AuthUser({this.name, required this.roles});

  bool get isSuperadmin => roles.contains('superadmin');
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.read(dioClientProvider), ref.read(secureStorageProvider));
});

class AuthRepository {
  final Dio _dio;
  final SecureStorageService _storage;

  AuthRepository(this._dio, this._storage);

  // 로그인 → accessToken 저장 + 유저 반환.
  Future<AuthUser> login(String emailOrUsername, String password) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/auth/login',
      data: {'emailOrUsername': emailOrUsername, 'password': password},
    );
    final data = res.data ?? {};
    final token = data['accessToken'] as String?;
    if (token == null || token.isEmpty) {
      throw Exception('Sin token');
    }
    await _storage.write(StorageKeys.token, token);

    return _parseUser(data);
  }

  // 저장된 토큰으로 /me 조회 (앱 재시작 시 세션 복원).
  Future<AuthUser?> me() async {
    final token = await _storage.read(StorageKeys.token);
    if (token == null || token.isEmpty) return null;
    try {
      final res = await _dio.get<Map<String, dynamic>>('/auth/me');

      return _parseUser(res.data ?? {});
    } catch (_) {
      return null;
    }
  }

  // ── [Phase 72-03] 기기 토큰 ────────────────────────────────────────────────
  // 원문 비밀번호 보관을 대체한다. 서버는 해시만 갖고, 회수하면 이 단말은 끝난다.

  /// 비밀번호 로그인 직후 호출 — 이후 지문 재로그인에 쓸 기기 토큰을 발급받는다.
  /// 실패해도 로그인 자체는 성공으로 둔다(지문이 다음 로그인부터 붙을 뿐이다).
  Future<bool> registerDevice(String platform) async {
    try {
      final deviceId = await _storage.deviceId();
      final res = await _dio.post<Map<String, dynamic>>(
        '/auth/device/register',
        data: {
          'deviceId': deviceId,
          'deviceName': _deviceName(platform),
          'platform': platform,
        },
      );
      final token = res.data?['deviceToken'] as String?;
      if (token == null || token.isEmpty) return false;
      await _storage.write(StorageKeys.deviceToken, token);

      return true;
    } catch (_) {
      return false;
    }
  }

  /// 지문 인증 성공 후 호출 — 기기 토큰으로 새 accessToken 을 받는다.
  ///
  /// 서버는 매번 토큰을 회전시키므로 **응답의 새 토큰을 반드시 저장해야** 다음 번에도
  /// 들어갈 수 있다. 저장을 accessToken 보다 먼저 하는 이유는, 둘 중 하나만 저장되는
  /// 상황에서 기기 토큰을 잃는 쪽이 더 아프기 때문이다(지문 로그인이 통째로 막힌다).
  Future<AuthUser?> refreshWithDevice() async {
    final deviceToken = await _storage.read(StorageKeys.deviceToken);
    if (deviceToken == null || deviceToken.isEmpty) return null;

    final res = await _dio.post<Map<String, dynamic>>(
      '/auth/device/refresh',
      data: {'deviceToken': deviceToken},
    );
    final data = res.data ?? {};

    final rotated = data['deviceToken'] as String?;
    if (rotated != null && rotated.isNotEmpty) {
      await _storage.write(StorageKeys.deviceToken, rotated);
    }

    final token = data['accessToken'] as String?;
    if (token == null || token.isEmpty) return null;
    await _storage.write(StorageKeys.token, token);

    return _parseUser(data);
  }

  /// 기기 토큰을 서버에서 회수하고 단말에서도 지운다.
  /// 서버 호출이 실패해도 단말 삭제는 반드시 수행한다 — 오프라인 로그아웃이
  /// 자격증명을 남기면 "로그아웃했다"는 사용자의 이해와 어긋난다.
  Future<void> revokeDevice() async {
    final deviceToken = await _storage.read(StorageKeys.deviceToken);
    if (deviceToken != null && deviceToken.isNotEmpty) {
      try {
        await _dio.post('/auth/device/revoke', data: {'deviceToken': deviceToken});
      } catch (_) {
        // 무시 — 아래 단말 삭제는 그대로 진행한다.
      }
    }
    await _storage.delete(StorageKeys.deviceToken);
  }

  Future<bool> hasDeviceToken() async {
    final t = await _storage.read(StorageKeys.deviceToken);

    return t != null && t.isNotEmpty;
  }

  String _deviceName(String platform) => 'Ventago Admin ($platform)';

  Future<void> logout() => _storage.deleteAll();

  AuthUser _parseUser(Map<String, dynamic> data) {
    final rawRoles = data['roles'];
    final roles = rawRoles is List
        ? rawRoles.map((e) => e.toString()).toList()
        : <String>[];

    return AuthUser(name: data['name'] as String?, roles: roles);
  }
}
