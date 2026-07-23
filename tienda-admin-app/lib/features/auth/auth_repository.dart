import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/dio_client.dart';
import '../../core/storage/secure_storage.dart';

// 매장 관리자 권한으로 인정되는 역할.
// UserRoleGuard 별칭 정리: store_owner/store_admin→admin, branch_manager→gerente.
const _storeManagerRoles = <String>{
  'admin',
  'superadmin',
  'gerente',
  'store_owner',
  'store_admin',
};

class AuthUser {
  final int? id;
  final String? name;
  final List<String> roles;
  final int? storeId;
  final String? storeName;
  final String? aliasName;
  final String? logoUrl;

  AuthUser({
    this.id,
    this.name,
    required this.roles,
    this.storeId,
    this.storeName,
    this.aliasName,
    this.logoUrl,
  });

  // 매장 admin 앱 접근 게이트: 매장 관리자 역할 중 하나라도 있으면 허용.
  bool get isStoreManager => roles.any(_storeManagerRoles.contains);

  // 표시용 매장명 (별칭 우선).
  String get displayStore => (aliasName?.isNotEmpty == true)
      ? aliasName!
      : (storeName ?? 'Mi tienda');
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    ref.read(dioClientProvider),
    ref.read(secureStorageProvider),
  );
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

  // 저장된 토큰으로 /auth/me 조회 (앱 재시작 시 세션 복원).
  // /me 는 fresh accessToken 을 재발급하므로 저장 토큰도 갱신한다.
  Future<AuthUser?> me() async {
    final token = await _storage.read(StorageKeys.token);
    if (token == null || token.isEmpty) return null;
    try {
      final res = await _dio.get<Map<String, dynamic>>('/auth/me');
      final data = res.data ?? {};
      final fresh = data['accessToken'] as String?;
      if (fresh != null && fresh.isNotEmpty) {
        await _storage.write(StorageKeys.token, fresh);
      }

      return _parseUser(data);
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

    return AuthUser(
      id: data['id'] is int ? data['id'] as int : int.tryParse('${data['id']}'),
      name: data['name'] as String?,
      roles: roles,
      storeId: data['storeId'] is int
          ? data['storeId'] as int
          : int.tryParse('${data['storeId']}'),
      storeName: data['storeName'] as String?,
      aliasName: data['aliasName'] as String?,
      logoUrl: data['logoUrl'] as String?,
    );
  }
}
