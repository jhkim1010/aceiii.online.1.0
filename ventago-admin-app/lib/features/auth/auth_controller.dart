import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/biometric_service.dart';
import '../../core/config/api_config.dart';
import '../../core/storage/secure_storage.dart';
import 'auth_repository.dart';

class AuthState {
  final bool loading;
  final AuthUser? user;
  final String? error;

  const AuthState({this.loading = false, this.user, this.error});

  bool get isLoggedIn => user != null;

  AuthState copyWith({bool? loading, AuthUser? user, String? error, bool clearError = false}) {
    return AuthState(
      loading: loading ?? this.loading,
      user: user ?? this.user,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(
    ref.read(authRepositoryProvider),
    ref.read(secureStorageProvider),
    ref.read(biometricServiceProvider),
  );
});

class AuthController extends StateNotifier<AuthState> {
  final AuthRepository _repo;
  final SecureStorageService _storage;
  final BiometricService _bio;

  AuthController(this._repo, this._storage, this._bio) : super(const AuthState());

  // 앱 시작 시 저장 토큰으로 세션 복원.
  Future<void> bootstrap() async {
    final user = await _repo.me();
    if (user != null) {
      state = state.copyWith(user: user);
    }
  }

  Future<bool> login(String emailOrUsername, String password) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final user = await _repo.login(emailOrUsername, password);
      if (!user.isSuperadmin) {
        await _repo.logout();
        state = state.copyWith(loading: false, error: 'Acceso solo para superadmin.');

        return false;
      }
      // 첫 로그인 성공 → 이후 지문 로그인용으로 자격증명 보관
      await _saveCredentials(emailOrUsername, password);
      state = AuthState(user: user);

      return true;
    } catch (e, st) {
      final detail = _describeError(e);
      // ignore: avoid_print
      print('[LOGIN ERROR] $detail\n$st');
      state = state.copyWith(loading: false, error: detail);

      return false;
    }
  }

  // 지문 인증 → 저장된 자격증명으로 로그인.
  Future<bool> biometricLogin() async {
    final u = await _storage.read(StorageKeys.savedUser);
    final p = await _storage.read(StorageKeys.savedPass);
    if (u == null || u.isEmpty || p == null || p.isEmpty) {
      return false;
    }
    final ok = await _bio.authenticate();
    if (!ok) {
      // 사용자가 취소/실패 — 오류 표시 없이 비밀번호 입력 대기
      return false;
    }

    return login(u, p);
  }

  // 로그인 화면에서 지문 버튼/자동프롬프트를 띄울지 판단.
  Future<bool> canUseBiometric() async {
    final u = await _storage.read(StorageKeys.savedUser);
    if (u == null || u.isEmpty) return false;

    return _bio.isAvailable();
  }

  Future<void> _saveCredentials(String user, String password) async {
    await _storage.write(StorageKeys.savedUser, user);
    await _storage.write(StorageKeys.savedPass, password);
  }

  // 로그인 실패 원인을 최대한 자세히 (진단용).
  String _describeError(Object e) {
    final b = StringBuffer();
    b.writeln('BASE_URL: ${ApiConfig.baseUrl}');
    if (e is DioException) {
      b.writeln('tipo  : ${e.type}');
      b.writeln('req   : ${e.requestOptions.method} ${e.requestOptions.uri}');
      final res = e.response;
      if (res != null) {
        b.writeln('status: ${res.statusCode}');
        b.writeln('body  : ${res.data}');
      }
      final cause = e.error;
      if (cause != null) {
        b.writeln('causa : ${cause.runtimeType}: $cause');
      }
      b.writeln('msg   : ${e.message}');
    } else {
      b.writeln('${e.runtimeType}: $e');
    }

    return b.toString().trimRight();
  }

  // 로그아웃: 세션 토큰만 지우고 자격증명은 유지 → 다음에 지문으로 재로그인 가능.
  Future<void> logout() async {
    await _storage.delete(StorageKeys.token);
    state = const AuthState();
  }

  // 저장된 지문 자격증명까지 완전 삭제 (기기에서 잊기).
  Future<void> forgetDevice() async {
    await _storage.deleteAll();
    state = const AuthState();
  }
}
