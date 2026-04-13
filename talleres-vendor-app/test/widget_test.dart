// 기본 위젯 테스트 — 앱 구동 확인
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:talleres_vendor_app/main.dart';

void main() {
  testWidgets('앱 구동 스모크 테스트', (WidgetTester tester) async {
    // ProviderScope로 감싸서 앱 구동
    await tester.pumpWidget(
      const ProviderScope(child: TalleresVendorApp()),
    );

    // 앱이 에러 없이 구동되는지 확인
    expect(find.byType(TalleresVendorApp), findsOneWidget);
  });
}
