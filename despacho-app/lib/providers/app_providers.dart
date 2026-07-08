import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../models/order.dart';
import '../models/transporte.dart';
import '../models/operario.dart';
import '../services/api_service.dart';

/// 인증/연결 상태 — baseUrl + token 을 보관하고 로컬 저장소와 동기화.
class AuthState {
  final String baseUrl;
  final String token;

  const AuthState({required this.baseUrl, required this.token});

  // 서버 URL 은 코드 고정값(AppConfig.defaultBaseUrl)이라 항상 존재 → 토큰만으로 판단.
  bool get isAuthenticated => token.isNotEmpty;

  AuthState copyWith({String? baseUrl, String? token}) =>
      AuthState(baseUrl: baseUrl ?? this.baseUrl, token: token ?? this.token);
}

class AuthController extends StateNotifier<AuthState> {
  AuthController() : super(const AuthState(baseUrl: '', token: '')) {
    _restore();
  }

  /// 저장된 자격 복원 (앱 시작 시).
  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(AppConfig.kToken) ?? '';

      // baseUrl 은 코드 고정값만 사용 — 사용자 입력/과거 저장값(잘못된 10.0.2.2 등) 무시.
      state = AuthState(baseUrl: AppConfig.defaultBaseUrl, token: token);
    } catch (_) {
      // 저장소 접근 실패해도 앱은 로그인 화면으로 진행.
      state = AuthState(baseUrl: AppConfig.defaultBaseUrl, token: '');
    }
  }

  /// 로그인 — 기기 토큰(x-device-key)만 저장. 서버 URL 은 코드 고정값(AppConfig.defaultBaseUrl).
  Future<void> signIn({required String token}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConfig.kToken, token.trim());
    state = AuthState(baseUrl: AppConfig.defaultBaseUrl, token: token.trim());
  }

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConfig.kToken);
    state = state.copyWith(token: '');
  }
}

final authProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) => AuthController());

/// 현재 작업자(operario) — 감사 추적용. null 이면 작업자 미선택(로그인 필요).
class OperarioController extends StateNotifier<Operario?> {
  OperarioController() : super(null) {
    _restore();
  }

  static const _kId = 'operario_id';
  static const _kName = 'operario_name';

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getInt(_kId);
      final name = prefs.getString(_kName);
      if (id != null && name != null && name.isNotEmpty) {
        state = Operario(id: id, name: name);
      }
    } catch (_) {
      state = null;
    }
  }

  Future<void> setOperario(Operario op) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kId, op.id);
    await prefs.setString(_kName, op.name);
    state = op;
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kId);
    await prefs.remove(_kName);
    state = null;
  }
}

final operarioProvider =
    StateNotifierProvider<OperarioController, Operario?>((ref) => OperarioController());

/// 현재 자격으로 구성된 ApiService (기기 토큰 + 현재 operario 이름 헤더).
final apiServiceProvider = Provider<ApiService?>((ref) {
  final auth = ref.watch(authProvider);
  if (!auth.isAuthenticated) return null;
  final operario = ref.watch(operarioProvider);

  return ApiService(baseUrl: auth.baseUrl, deviceKey: auth.token, operarioName: operario?.name);
});

/// 작업자 목록(이름 선택 그리드).
final operariosProvider = FutureProvider.autoDispose<List<Operario>>((ref) async {
  final api = ref.watch(apiServiceProvider);
  if (api == null) return const <Operario>[];

  return api.fetchOperarios();
});

/// preparando(준비) 주문 목록.
final preparingOrdersProvider = FutureProvider.autoDispose<List<OnlineOrder>>((ref) async {
  final api = ref.watch(apiServiceProvider);
  if (api == null) return const <OnlineOrder>[];

  return api.fetchOrders('preparando');
});

/// listo(발송 대기) 주문 목록.
final listoOrdersProvider = FutureProvider.autoDispose<List<OnlineOrder>>((ref) async {
  final api = ref.watch(apiServiceProvider);
  if (api == null) return const <OnlineOrder>[];

  return api.fetchOrders('listo');
});

/// enviado(발송됨, 배송 확인 대기) 주문 목록.
final enviadoOrdersProvider = FutureProvider.autoDispose<List<OnlineOrder>>((ref) async {
  final api = ref.watch(apiServiceProvider);
  if (api == null) return const <OnlineOrder>[];

  return api.fetchOrders('enviado');
});

/// 매장 활성 운송업체 목록 (발송 인계 드롭다운).
final transportesProvider = FutureProvider.autoDispose<List<Transporte>>((ref) async {
  final api = ref.watch(apiServiceProvider);
  if (api == null) return const <Transporte>[];

  return api.fetchTransportes();
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
