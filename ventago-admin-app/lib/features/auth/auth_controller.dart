import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/biometric_service.dart';
import '../../core/config/api_config.dart';
import '../../core/network/session_signal.dart';
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
    ref.read(sessionExpiredSignalProvider),
  );
});

class AuthController extends StateNotifier<AuthState> {
  final AuthRepository _repo;
  final SecureStorageService _storage;
  final BiometricService _bio;
  final SessionExpiredSignal _signal;

  AuthController(this._repo, this._storage, this._bio, this._signal)
      : super(const AuthState()) {
    // 토큰 만료(401) 신호 → 로그인 화면으로 전환 (지문 자격증명은 보존됨).
    _signal.addListener(_onSessionExpired);
  }

  void _onSessionExpired() {
    if (!_signal.expired) return;
    _signal.reset();
    if (state.isLoggedIn) {
      // 로그인 화면이 뜨면 initState 의 자동 지문 프롬프트로 즉시 재진입 가능
      state = const AuthState();
    }
  }

  @override
  void dispose() {
    _signal.removeListener(_onSessionExpired);
    super.dispose();
  }

  // 앱 시작 시 저장 토큰으로 세션 복원.
  Future<void> bootstrap() async {
    // [Phase 72-03] 기존 설치분에 남아 있는 원문 비밀번호를 먼저 지운다.
    // 코드가 더 이상 읽지 않는 것과 단말에서 없어지는 것은 별개다 — 업데이트만으로는
    // 안 사라진다. 로그인 성공 여부와 무관하게 매 시작 시 시도한다.
    await _storage.purgeLegacyCredentials();

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
      // [Phase 72-03] 로그인 성공 → 지문 재로그인용 **기기 토큰**을 발급받는다.
      // 예전에는 여기서 원문 비밀번호를 단말에 저장했다. 더 이상 저장하지 않는다.
      await _storage.write(StorageKeys.savedUser, emailOrUsername);
      await _repo.registerDevice(_platformName());
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

  // 지문 인증 → 기기 토큰으로 재로그인.
  //
  // [Phase 72-03] 예전에는 저장해둔 원문 비밀번호로 /auth/login 을 다시 호출했다.
  // 지금은 회수 가능한 기기 토큰을 서버에 제시해 새 accessToken 을 받는다.
  // 기능(지문 한 번으로 로그인)은 그대로고, 단말에 남는 것만 바뀌었다.
  Future<bool> biometricLogin() async {
    if (!await _repo.hasDeviceToken()) {
      return false;
    }
    final ok = await _bio.authenticate();
    if (!ok) {
      // 사용자가 취소/실패 — 오류 표시 없이 비밀번호 입력 대기
      return false;
    }

    state = state.copyWith(loading: true, clearError: true);
    try {
      final user = await _repo.refreshWithDevice();
      if (user == null || !user.isSuperadmin) {
        // 토큰이 회수·만료됐거나 권한이 사라졌다 → 비밀번호 로그인으로 되돌린다.
        await _repo.revokeDevice();
        state = const AuthState();

        return false;
      }
      state = AuthState(user: user);

      return true;
    } catch (e) {
      // 401(회수/만료)이면 이 단말의 기기 토큰은 이미 쓸모없다. 남겨두면 앱을 열 때마다
      // 지문을 요구했다가 실패하는 상태가 반복된다.
      final expired = e is DioException && e.response?.statusCode == 401;
      if (expired) {
        await _repo.revokeDevice();
        state = const AuthState();

        return false;
      }
      state = state.copyWith(loading: false, error: _describeError(e));

      return false;
    }
  }

  // 로그인 화면에서 지문 버튼/자동프롬프트를 띄울지 판단.
  Future<bool> canUseBiometric() async {
    if (!await _repo.hasDeviceToken()) return false;

    return _bio.isAvailable();
  }

  String _platformName() {
    if (kIsWeb) return 'web';

    return Platform.operatingSystem;
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

  // ── 로그아웃 정책 (Phase 72-03) ──────────────────────────────────────────
  // 예전에는 "토큰만 지우고 자격증명은 남긴다"가 주석에만 있었다. 사용자는 로그아웃했다고
  // 믿지만 단말에는 원문 비밀번호가 그대로 남아 있었다. 이제 두 동작을 UI 에서 **따로 고른다**
  // (app_shell.dart 의 메뉴). 무엇이 남는지가 선택지 문구에 드러난다.

  /// 세션만 종료. 기기 토큰은 남겨 다음에 지문으로 들어올 수 있다.
  /// 남는 자격증명은 서버에서 회수 가능한 기기 토큰뿐이다 — 원문 비밀번호가 아니다.
  Future<void> logout() async {
    await _storage.delete(StorageKeys.token);
    state = const AuthState();
  }

  /// 이 기기에서 완전히 잊기 — 서버의 기기 토큰을 **회수**하고 단말 저장소를 비운다.
  /// 단말을 넘기거나 분실했을 때 쓰는 동작이다.
  Future<void> forgetDevice() async {
    await _repo.revokeDevice();
    await _storage.deleteAll();
    state = const AuthState();
  }
}
