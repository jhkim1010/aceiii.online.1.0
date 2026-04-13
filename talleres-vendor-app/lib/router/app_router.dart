// 앱 라우터 — go_router + 인증 상태 기반 리다이렉트
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../features/auth/providers/auth_provider.dart';
import '../features/auth/views/login_screen.dart';
import '../features/envios/data/envio_dto.dart';
import '../features/envios/views/envio_detail_screen.dart';
import '../features/home/views/home_screen.dart';

// GoRouter Provider — 인증 상태 변화 시 자동 리다이렉트
final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authNotifierProvider);

  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) {
      // 로딩 중에는 리다이렉트 보류
      if (authState.isLoading) {
        return null;
      }

      final isLoggedIn = authState.value != null;
      final isLoginRoute = state.matchedLocation == '/login';

      // 미인증 상태에서 로그인 외 경로 접근 시 로그인으로
      if (!isLoggedIn && !isLoginRoute) {
        return '/login';
      }

      // 인증 상태에서 로그인 화면 접근 시 홈으로
      if (isLoggedIn && isLoginRoute) {
        return '/home';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => const HomeScreen(),
      ),

      // 발송 상세 화면 — envioId를 path param으로, EnvioDto를 extra로 전달
      GoRoute(
        path: '/envio/:id',
        builder: (context, state) {
          final envioId = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
          final envio = state.extra as EnvioDto?;

          return EnvioDetailScreen(envioId: envioId, initialEnvio: envio);
        },
      ),
    ],
  );
});
