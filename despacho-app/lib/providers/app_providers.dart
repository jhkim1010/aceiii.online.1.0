import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config.dart';
import '../models/order.dart';
import '../services/api_service.dart';

/// 보안 저장소 인스턴스.
final secureStorageProvider = Provider<FlutterSecureStorage>(
  (ref) => const FlutterSecureStorage(),
);

/// 인증/연결 상태 — baseUrl + token 을 보관하고 secure storage 와 동기화.
class AuthState {
  final String baseUrl;
  final String token;

  const AuthState({required this.baseUrl, required this.token});

  bool get isAuthenticated => baseUrl.isNotEmpty && token.isNotEmpty;

  AuthState copyWith({String? baseUrl, String? token}) =>
      AuthState(baseUrl: baseUrl ?? this.baseUrl, token: token ?? this.token);
}

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._storage) : super(const AuthState(baseUrl: '', token: '')) {
    _restore();
  }

  final FlutterSecureStorage _storage;

  /// 저장된 자격 복원 (앱 시작 시).
  Future<void> _restore() async {
    try {
      final baseUrl = await _storage.read(key: AppConfig.kBaseUrl) ?? '';
      final token = await _storage.read(key: AppConfig.kToken) ?? '';
      state = AuthState(baseUrl: baseUrl, token: token);
    } catch (_) {
      // 저장소 접근 실패해도 앱은 로그인 화면으로 진행.
      state = const AuthState(baseUrl: '', token: '');
    }
  }

  /// 로그인 — Phase 1 은 baseUrl + 토큰(임시 JWT) 직접 저장.
  /// Phase 2 에서 기기 apiKey → POST /despacho/auth 로 교체.
  Future<void> signIn({required String baseUrl, required String token}) async {
    final normalized = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    await _storage.write(key: AppConfig.kBaseUrl, value: normalized);
    await _storage.write(key: AppConfig.kToken, value: token.trim());
    state = AuthState(baseUrl: normalized, token: token.trim());
  }

  Future<void> signOut() async {
    await _storage.delete(key: AppConfig.kToken);
    state = state.copyWith(token: '');
  }
}

final authProvider = StateNotifierProvider<AuthController, AuthState>(
  (ref) => AuthController(ref.watch(secureStorageProvider)),
);

/// 현재 자격으로 구성된 ApiService.
final apiServiceProvider = Provider<ApiService?>((ref) {
  final auth = ref.watch(authProvider);
  if (!auth.isAuthenticated) return null;

  return ApiService(baseUrl: auth.baseUrl, token: auth.token);
});

/// preparing 주문 목록 — 당김 새로고침 시 invalidate.
final preparingOrdersProvider = FutureProvider.autoDispose<List<OnlineOrder>>((ref) async {
  final api = ref.watch(apiServiceProvider);
  if (api == null) return const <OnlineOrder>[];

  return api.fetchPreparingOrders();
});

/// 주문 상세 (id 별).
final orderDetailProvider =
    FutureProvider.autoDispose.family<OnlineOrder, int>((ref, id) async {
  final api = ref.watch(apiServiceProvider);
  if (api == null) {
    throw Exception('No autenticado');
  }

  return api.fetchOrderDetail(id);
});
