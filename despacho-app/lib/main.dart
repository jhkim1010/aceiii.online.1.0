import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config.dart';
import 'core/update/actualizacion.dart';
import 'providers/app_providers.dart';
import 'screens/login_screen.dart';
import 'screens/operario_login_screen.dart';
import 'screens/home_shell.dart';

void main() {
  runApp(const ProviderScope(child: DespachoApp()));
  // 첫 화면이 뜬 뒤 1회 — 새 버전이 있으면 묻는다(절대 혼자 설치하지 않음). Android 전용.
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => chequearActualizacion(rootNavigatorKey, feedUrl: _feedActualizacion),
  );
}

// [2026-10-24] 새 버전 안내 — build-apk.sh 가 이 주소에 version.json 을 올린다
const _feedActualizacion =
    'https://github.com/jhkim1010/ventago-downloads/releases/download/despacho-app-latest/version.json';

// 앱 시작 시 업데이트 확인 다이얼로그를 띄우기 위한 루트 navigator 키
final rootNavigatorKey = GlobalKey<NavigatorState>();

class DespachoApp extends ConsumerWidget {
  const DespachoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final operario = ref.watch(operarioProvider);

    // 다크 네이비 + 골드 (Ventago 테마 규약).
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFF5A623),
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(0xFFF6F6FA),
    );

    return MaterialApp(
      title: AppConfig.appTitle,
      navigatorKey: rootNavigatorKey,
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: !auth.isAuthenticated
          ? const LoginScreen()
          : operario == null
              ? const OperarioLoginScreen()
              : const HomeShell(),
    );
  }
}
