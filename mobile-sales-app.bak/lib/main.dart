// 앱 진입점 — ProviderScope(Riverpod) + Ventago 테마 + go_router.
// Portrait 고정(폰 우선, UI-SPEC §1).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/network/session_signal.dart';
import 'core/theme/app_theme.dart';
import 'router/app_router.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 세로 방향 고정
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const ProviderScope(child: MobileSalesApp()));
}

// 루트 앱 위젯 — router Provider 구독
class MobileSalesApp extends ConsumerWidget {
  const MobileSalesApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Ventago Ventas',
      theme: AppTheme.light,
      // 인터셉터(비 UI)에서 토스트를 띄우기 위한 전역 messenger 키
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
