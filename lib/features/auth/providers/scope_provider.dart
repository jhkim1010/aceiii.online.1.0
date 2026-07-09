// ScopeProvider — /mobile/me 응답으로 BranchScope(vendedor) / MultiStoreScope(revendedor)
// 결정 (criterion #10). scope 는 표시/락 용도, 백엔드 MobileScopeGuard 가 권위(D-02).
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/storage/secure_storage.dart';
import '../data/auth_dto.dart';
import '../data/auth_repository.dart';

// scope 상태 (sealed — 미인증/지점/멀티매장)
@immutable
sealed class ScopeState {
  const ScopeState();
}

// 미인증
class ScopeUnauthenticated extends ScopeState {
  const ScopeUnauthenticated();
}

// vendedor — 자기 지점(들) scope
class BranchScope extends ScopeState {
  final List<int> branchIds;
  final MobileUser user;

  const BranchScope(this.branchIds, this.user);
}

// revendedor — 다중 매장 scope (Wave 5)
class MultiStoreScope extends ScopeState {
  final List<int> storeIds;
  final MobileUser user;

  const MultiStoreScope(this.storeIds, this.user);
}

// 순수 함수: MobileUser → ScopeState (네트워크 무관, 단위 테스트 대상)
ScopeState resolveScope(MobileUser user) {
  switch (user.scopeMode) {
    case ScopeMode.vendedor:
      return BranchScope(user.scopeBranchIds, user);
    case ScopeMode.revendedor:
      return MultiStoreScope(user.scopeStoreIds, user);
    case ScopeMode.unknown:
      // 알 수 없는 모드 → branchIds 존재 시 지점 scope 로 폴백, 아니면 미인증
      if (user.scopeBranchIds.isNotEmpty) {
        return BranchScope(user.scopeBranchIds, user);
      }

      return const ScopeUnauthenticated();
  }
}

// scope 영속화 키 (오프라인 복원 보조 — criterion #11)
const String _kScopeMode = 'scope_mode';

// scope AsyncNotifier Provider
final scopeNotifierProvider = AsyncNotifierProvider<ScopeNotifier, ScopeState>(
  ScopeNotifier.new,
);

class ScopeNotifier extends AsyncNotifier<ScopeState> {
  @override
  Future<ScopeState> build() async {
    // 앱 시작 시 저장 토큰이 있으면 /mobile/me 로 scope 복원
    final storage = ref.read(secureStorageProvider);
    final token = await storage.read(StorageKeys.mobileToken);
    if (token == null || token.isEmpty) {
      return const ScopeUnauthenticated();
    }

    try {
      final user = await ref.read(authRepositoryProvider).getMe();
      final scope = resolveScope(user);
      await _persistScope(scope);

      return scope;
    } catch (_) {
      // 토큰 만료/에러 → 저장소 초기화 후 미인증
      await storage.deleteAll();

      return const ScopeUnauthenticated();
    }
  }

  // Usuario + PIN 로그인 → scope 설정
  Future<void> login({
    required String usuario,
    required String pin,
    int? selectedBranchId,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final res = await ref.read(authRepositoryProvider).login(
            usuario: usuario,
            pin: pin,
            selectedBranchId: selectedBranchId,
          );
      final scope = resolveScope(res.user);
      await _persistScope(scope);

      return scope;
    });
  }

  // 로그아웃 → 미인증
  Future<void> logout() async {
    await ref.read(authRepositoryProvider).logout();
    state = const AsyncData(ScopeUnauthenticated());
  }

  // scope 모드 영속화 (secure storage, 오프라인 표시 보조)
  Future<void> _persistScope(ScopeState scope) async {
    final storage = ref.read(secureStorageProvider);
    final mode = switch (scope) {
      BranchScope() => 'vendedor',
      MultiStoreScope() => 'revendedor',
      ScopeUnauthenticated() => '',
    };
    if (mode.isEmpty) {
      await storage.delete(_kScopeMode);
    } else {
      await storage.write(_kScopeMode, mode);
    }
  }
}
