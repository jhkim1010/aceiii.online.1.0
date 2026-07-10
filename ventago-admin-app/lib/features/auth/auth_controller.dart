import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  return AuthController(ref.read(authRepositoryProvider));
});

class AuthController extends StateNotifier<AuthState> {
  final AuthRepository _repo;

  AuthController(this._repo) : super(const AuthState());

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
      state = AuthState(user: user);

      return true;
    } catch (_) {
      state = state.copyWith(loading: false, error: 'Credenciales inválidas o servidor no disponible.');

      return false;
    }
  }

  Future<void> logout() async {
    await _repo.logout();
    state = const AuthState();
  }
}
