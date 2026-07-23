import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/network/session_signal.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/login_screen.dart';
import 'shared/app_shell.dart';

void main() {
  runApp(const ProviderScope(child: TiendaAdminApp()));
}

class TiendaAdminApp extends StatelessWidget {
  const TiendaAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Admin de Tienda',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      theme: buildAppTheme(),
      home: const _AuthGate(),
    );
  }
}

// 앱 시작 시 저장 토큰으로 세션 복원 → 로그인/셸 분기.
class _AuthGate extends ConsumerStatefulWidget {
  const _AuthGate();

  @override
  ConsumerState<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<_AuthGate> {
  bool _booting = true;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    // 저장 토큰으로 /auth/me 복원 (실패해도 로그인 화면으로 폴백)
    await ref.read(authControllerProvider.notifier).bootstrap();
    if (mounted) setState(() => _booting = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_booting) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final loggedIn = ref.watch(authControllerProvider).isLoggedIn;

    return loggedIn ? const AppShell() : const LoginScreen();
  }
}
