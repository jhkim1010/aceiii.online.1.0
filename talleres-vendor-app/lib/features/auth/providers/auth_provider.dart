// 인증 Provider — Riverpod AsyncNotifier로 인증 상태 관리
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../shared/models/store_info.dart';
import '../data/auth_dto.dart';
import '../data/auth_repository.dart';

// 인증 상태 AsyncNotifier Provider
final authNotifierProvider = AsyncNotifierProvider<AuthNotifier, AuthState?>(
  () => AuthNotifier(),
);

// 매장 선택 대기 상태 — requiresStoreSelection 응답을 받았을 때만 값이 채워진다 (R3/CR-03).
// Riverpod 3.x 는 StateProvider 를 제공하지 않아 selectedStoreIndexProvider 와
// 동일한 Notifier 패턴을 쓴다.
final storeSelectionPendingProvider =
    NotifierProvider<StoreSelectionPendingNotifier, List<StoreInfo>?>(
  () => StoreSelectionPendingNotifier(),
);

// 매장 선택 대기 목록 Notifier
class StoreSelectionPendingNotifier extends Notifier<List<StoreInfo>?> {
  @override
  List<StoreInfo>? build() => null;

  // 매장 선택 대기 목록 설정(로그인 응답)/해제(선택 완료·로그아웃)
  void setStores(List<StoreInfo>? stores) => state = stores;
}

// 현재 선택된 매장 탭 인덱스 — Riverpod 3.x Notifier 방식
final selectedStoreIndexProvider = NotifierProvider<SelectedStoreIndexNotifier, int>(
  () => SelectedStoreIndexNotifier(),
);

// 선택된 매장 인덱스 Notifier
class SelectedStoreIndexNotifier extends Notifier<int> {
  @override
  int build() => 0;

  // 탭 선택 시 인덱스 변경
  void setIndex(int index) => state = index;
}

// 현재 선택된 StoreInfo — 탭 인덱스 기반 계산
final currentStoreProvider = Provider<StoreInfo?>((ref) {
  final auth = ref.watch(authNotifierProvider).value;
  final index = ref.watch(selectedStoreIndexProvider);
  if (auth == null || auth.stores.isEmpty) {
    return null;
  }

  return auth.stores[index.clamp(0, auth.stores.length - 1)];
});

// 인증 상태 관리 AsyncNotifier
class AuthNotifier extends AsyncNotifier<AuthState?> {
  // 매장 선택 대기 중 재사용할 자격 증명 — 메모리에만 보관하며 영속 저장소에 쓰지 않는다 (R3/CR-03)
  String? _pendingPhone;
  String? _pendingPin;

  @override
  Future<AuthState?> build() async {
    // 앱 시작 시 저장된 토큰 복구 시도
    final storage = ref.read(secureStorageProvider);
    final token = await storage.read('vendor_token');
    final phone = await storage.read('vendor_phone');

    if (token == null || phone == null) {
      return null;
    }

    try {
      // 저장된 토큰으로 최신 매장 목록 조회
      final data = await ref.read(authRepositoryProvider).getMe();

      return AuthState(
        token: token,
        phone: phone,
        stores: (data['stores'] as List<dynamic>)
            .map((s) => StoreInfo.fromJson(s as Map<String, dynamic>))
            .toList(),
      );
    } catch (_) {
      // 토큰 만료 또는 에러 시 저장된 정보 초기화
      await storage.deleteAll();

      return null;
    }
  }

  // 전화번호 + PIN으로 로그인. 동일 PIN 이 2개 이상 매장에서 통과하면 토큰이
  // 발급되지 않고 매장 선택 대기 상태로 전이한다 (R3/CR-03)
  Future<void> login(String phone, String pin) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final data = await ref.read(authRepositoryProvider).login(phone, pin);

      if (data['requiresStoreSelection'] == true) {
        // PIN 은 재입력 없이 메모리에서만 재사용 — 영속 저장소에 쓰지 않는다
        _pendingPhone = phone;
        _pendingPin = pin;
        ref
            .read(storeSelectionPendingProvider.notifier)
            .setStores(StoreSelectionRequired.fromJson(data).stores);

        return null;
      }

      final authState = AuthState.fromLoginResponse(data, phone);

      // 토큰과 전화번호를 보안 저장소에 저장 (PIN 은 저장하지 않음)
      final storage = ref.read(secureStorageProvider);
      await storage.write('vendor_token', authState.token);
      await storage.write('vendor_phone', phone);

      return authState;
    });
  }

  // 매장 선택 완료 — 메모리에 보관한 phone/PIN 으로 storeId 를 실어 재로그인 (R3/CR-03)
  Future<void> selectStore(int storeId) async {
    final phone = _pendingPhone;
    final pin = _pendingPin;

    if (phone == null || pin == null) {
      return;
    }

    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final data = await ref.read(authRepositoryProvider).login(phone, pin, storeId: storeId);
      final authState = AuthState.fromLoginResponse(data, phone);

      final storage = ref.read(secureStorageProvider);
      await storage.write('vendor_token', authState.token);
      await storage.write('vendor_phone', phone);

      // 로그인 완료 — 대기 자격 증명 및 상태 정리
      _pendingPhone = null;
      _pendingPin = null;
      ref.read(storeSelectionPendingProvider.notifier).setStores(null);

      return authState;
    });
  }

  // 로그아웃 — 보안 저장소 초기화
  Future<void> logout() async {
    final storage = ref.read(secureStorageProvider);
    await storage.deleteAll();
    _pendingPhone = null;
    _pendingPin = null;
    ref.read(storeSelectionPendingProvider.notifier).setStores(null);
    state = const AsyncData(null);
  }
}
