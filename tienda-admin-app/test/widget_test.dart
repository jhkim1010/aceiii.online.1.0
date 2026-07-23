// 기본 스모크 테스트 (앱 부팅은 네트워크에 의존하므로 최소 검증만).
import 'package:flutter_test/flutter_test.dart';
import 'package:tienda_admin_app/core/theme/app_theme.dart';

void main() {
  test('테마가 빌드된다', () {
    final theme = buildAppTheme();
    expect(theme.useMaterial3, true);
  });
}
