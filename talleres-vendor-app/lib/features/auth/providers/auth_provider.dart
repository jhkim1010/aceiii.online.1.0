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

  // 전화번호 + PIN으로 로그인
  Future<void> login(String phone, String pin) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final data = await ref.read(authRepositoryProvider).login(phone, pin);
      final authState = AuthState.fromLoginResponse(data, phone);

      // 토큰과 전화번호를 보안 저장소에 저장
      final storage = ref.read(secureStorageProvider);
      await storage.write('vendor_token', authState.token);
      await storage.write('vendor_phone', phone);

      return authState;
    });
  }

  // 로그아웃 — 보안 저장소 초기화
  Future<void> logout() async {
    final storage = ref.read(secureStorageProvider);
    await storage.deleteAll();
    state = const AsyncData(null);
  }
}
