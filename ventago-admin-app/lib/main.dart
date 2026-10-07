import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/network/session_signal.dart';
import 'core/theme/app_theme.dart';
import 'core/update/actualizacion.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/login_screen.dart';
import 'shared/app_shell.dart';

void main() {
  runApp(const ProviderScope(child: VentagoAdminApp()));
}

// [2026-10-07] 새 버전 안내 — build-apk.sh 가 이 주소에 version.json 을 올린다 (tienda-admin 과 같은 방식)
const _feedActualizacion =
    'https://github.com/jhkim1010/ventago-downloads/releases/download/ventago-admin-app-latest/version.json';

// 앱 시작 시 업데이트 다이얼로그를 띄우기 위한 루트 navigator 키
final rootNavigatorKey = GlobalKey<NavigatorState>();

class VentagoAdminApp extends StatefulWidget {
  const VentagoAdminApp({super.key});

  @override
  State<VentagoAdminApp> createState() => _VentagoAdminAppState();
}

class _VentagoAdminAppState extends State<VentagoAdminApp> {
  @override
  void initState() {
    super.initState();
    // 첫 화면이 뜬 뒤 1회 — 새 버전이 있으면 묻는다(절대 혼자 설치하지 않음)
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => chequearActualizacion(rootNavigatorKey, feedUrl: _feedActualizacion),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      title: 'Ventago Admin',
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
