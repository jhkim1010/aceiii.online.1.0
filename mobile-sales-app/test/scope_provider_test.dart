// ScopeProvider 단위 테스트 — /mobile/me 응답(scopeMode)으로 scope 해석 검증.
// resolveScope 는 순수 함수라 네트워크 없이 테스트 가능.
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_sales_app/features/auth/data/auth_dto.dart';
import 'package:mobile_sales_app/features/auth/providers/scope_provider.dart';

void main() {
  group('resolveScope — /mobile/me → ScopeState', () {
    test('vendedor scopeBranchIds:[5] → BranchScope([5])', () {
      // /mobile/me 응답 목업
      final user = MobileUser.fromJson(const {
        'id': 42,
        'name': 'Vendedor Uno',
        'role': 'vendedor',
        'scopeMode': 'vendedor',
        'scopeBranchIds': [5],
        'scopeStoreIds': <int>[],
        'storeId': 6,
        'storeName': 'coolsistema',
        'branchName': 'Centro',
      });

      final scope = resolveScope(user);

      expect(scope, isA<BranchScope>());
      expect((scope as BranchScope).branchIds, [5]);
      expect(scope.user.name, 'Vendedor Uno');
    });

    test('revendedor scopeStoreIds:[6,8] → MultiStoreScope([6,8])', () {
      final user = MobileUser.fromJson(const {
        'id': 99,
        'name': 'Revendedor',
        'role': 'revendedor',
        'scopeMode': 'revendedor',
        'scopeBranchIds': <int>[],
        'scopeStoreIds': [6, 8],
        'storeId': null,
        'storeName': null,
        'branchName': null,
      });

      final scope = resolveScope(user);

      expect(scope, isA<MultiStoreScope>());
      expect((scope as MultiStoreScope).storeIds, [6, 8]);
    });

    test('unknown scopeMode con branchIds → BranchScope (fallback)', () {
      final user = MobileUser.fromJson(const {
        'id': 1,
        'name': 'X',
        'role': 'vendedor',
        'scopeMode': 'weird',
        'scopeBranchIds': [3],
        'scopeStoreIds': <int>[],
      });

      expect(resolveScope(user), isA<BranchScope>());
    });

    test('unknown scopeMode sin scope → ScopeUnauthenticated', () {
      final user = MobileUser.fromJson(const {
        'id': 1,
        'name': 'X',
        'role': 'vendedor',
        'scopeMode': null,
        'scopeBranchIds': <int>[],
        'scopeStoreIds': <int>[],
      });

      expect(resolveScope(user), isA<ScopeUnauthenticated>());
    });
  });
}
