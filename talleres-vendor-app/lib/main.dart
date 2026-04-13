// 앱 진입점 — ProviderScope로 Riverpod 상태관리 초기화
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'router/app_router.dart';

void main() {
  runApp(
    // 전체 앱을 ProviderScope로 감싸 Riverpod 활성화
    const ProviderScope(child: TalleresVendorApp()),
  );
}

// 루트 앱 위젯 — ConsumerWidget으로 router Provider 구독
class TalleresVendorApp extends ConsumerWidget {
  const TalleresVendorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Portal de Talleres',
      theme: ThemeData(
        // 기본 색상 시드 — Material 3 색상 체계 사용
        colorSchemeSeed: const Color(0xFF1976D2),
        useMaterial3: true,
      ),
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
