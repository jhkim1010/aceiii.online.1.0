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

  Future<void> logout() => _storage.deleteAll();

  AuthUser _parseUser(Map<String, dynamic> data) {
    final rawRoles = data['roles'];
    final roles = rawRoles is List
        ? rawRoles.map((e) => e.toString()).toList()
        : <String>[];

    return AuthUser(name: data['name'] as String?, roles: roles);
  }
}
